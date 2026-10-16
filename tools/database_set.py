#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.91b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Database mode on the host: the edited database set, link files, CSV and
season packs.

An edited database is a set of complete raw team groups in the save
directory data/ of the WHDLoad install, declared by a manifest:

* DBASE.CFG, the manifest in use, and DBASE.BAK, the previous one;
* Tgggnnnn.GRP, generation nnnn of group ggg: the native BE16 count and
  count*684 team records, exactly as the game's own TEAM.ggg after
  unpacking, with the same keys, record order and division capacities;
* the copies that follow the set: T100nnnn.GRP, T101nnnn.GRP and
  T102nnnn.GRP, the team copies of the European club cups (16, 32 and 32
  headerless records in participant order, like the game's EUROCUP.TMD,
  EUROCWC.TMD and UEFACUP.TMD), and T103nnnn.GRP, the transfer pool (900
  entries of 58 bytes, like POOLPLYR.DAT), each declared only when it
  differs from the game's 96/97 copy;
* DBASE.USE, the remembered state of USE EDITED DATABASE (outside the
  fingerprint).

A competition started with an edited set is bound to it through a link
file next to its save (.DLD, .DLP, .DLS, .DLC for .DIY, .PRE, .SEA, .CAR):
the save's length and CRC-32 and a copy of the manifest.

The in-game database editor (src/editor/editors/database.s, dbstore.s and
dbgroup.s) reads and writes the same files; this module is the host
reference of their layout, of the checks the editor makes and of the lines
it shows, and of the CSV files and season packs (the fields that differ
from the user's own 96/97 database):

  python3 tools/database_set.py manifest data/DBASE.CFG
  python3 tools/database_set.py link data/CAREER.DLC
  python3 tools/database_set.py check data --disk2 Disk.2
  python3 tools/database_set.py export --disk1 Disk.1 --disk2 Disk.2 [--data data] out/
  python3 tools/database_set.py import --disk1 Disk.1 --disk2 Disk.2 --data data \\
      [--label "SEASON 26/27"] out/players.csv out/teams.csv
  python3 tools/database_set.py diff --disk1 Disk.1 --disk2 Disk.2 --data data pack.json
  python3 tools/database_set.py apply --disk1 Disk.1 --disk2 Disk.2 --data data pack.json
  python3 tools/database_set.py write --disk1 Disk.1 --disk2 Disk.2 --data data \\
      [--label "SEASON 26/27"] [--switch on|off] pack.json | *.csv | TEAM.ggg.json ...

Every value is big-endian; every CRC-32 is CRC-32/ISO-HDLC (zlib.crc32).
Nothing in this module deletes a file: superseded generations stay until
REMOVE OLD VERSIONS in EDIT DATABASE removes them.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import struct
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))

import custom_set  # noqa: E402
import team_data  # noqa: E402

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
CLUB_GROUPS = (tuple(range(0, 9)) + tuple(range(10, 47)) + (48, 49, 50, 51, 55, 60, 62, 64, 65, 66, 67,
                                                            69, 71, 73, 75, 76, 77, 78, 79))
NATIONAL_GROUPS = tuple(range(80, 86))
SUPPORTED_GROUPS = CLUB_GROUPS + NATIONAL_GROUPS
CUSTOM_GROUP = 72                       # the custom set, CUSTOMS.EDT; not a database group
TEAM_SIZE = 0x2AC
PLAYER_SIZE = 0x26
PLAYERS = 0x4C
GROUP_MAX_TEAMS = 93                    # the largest group, TEAM.008
GROUP_WORK_SIZE = 2 + GROUP_MAX_TEAMS * TEAM_SIZE   # 63,614 bytes
DISK2_SHA256 = "ed921246c05531a2445a3f61aee4afd493771ab79042d7c4ed210fd3f3c30d36"
DISK1_SHA256 = "b70c0db66d8c2e93f1e12aa00c5df4b465c9f29d458723130e5a946428ca92ee"
# SHA-256 of the unpacked, unrelocated SWOS2 of the supported release: the
# identity every manifest carries (the editor compares it byte for byte).
SWOS2_SHA256 = "a14c565459493dc0377caf08822b0d3a6766f3ca899290dbbc17d43eee403c79"
SWOS2_IDENTITY = bytes.fromhex(SWOS2_SHA256)
RUNTIME_BASE = 0x180000
NATIONALITY_TABLE = 0x1CEB94 - RUNTIME_BASE       # offset in the unpacked SWOS2
NATIONALITIES = 153
POSITIONS = ("G", "RB", "LB", "D", "RW", "LW", "M", "A")
SKILLS = ("passing", "shooting", "heading", "tackling", "control", "speed", "finishing")

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
MANIFEST_NAME = "DBASE.CFG"
BACKUP_NAME = "DBASE.BAK"
MANIFEST_MAGIC = b"SWOSGRP1"
MANIFEST_VERSION = 2                    # written; version 1 (no copies) is still read
MANIFEST_VERSIONS = (1, 2)
M_MAGIC, M_VERSION, M_COUNT, M_GENERATION = 0x00, 0x08, 0x0A, 0x0C
M_IDENTITY, M_BASE, M_LENGTH, M_CRC, M_RESERVED, M_LABEL = 0x10, 0x30, 0x34, 0x38, 0x3C, 0x40
MANIFEST_HEADER = 0x50
ENTRY_SIZE = 16
# The copies that follow the set: the European club cups'
# team copies and the transfer pool, declared with these codes after the
# database groups.
CUP_EUROCUP, CUP_EUROCWC, CUP_UEFACUP, COPY_POOL = 100, 101, 102, 103
CUP_CODES = (CUP_EUROCUP, CUP_EUROCWC, CUP_UEFACUP)
COPY_CODES = CUP_CODES + (COPY_POOL,)
CUP_NAMES = {CUP_EUROCUP: "EUROCUP", CUP_EUROCWC: "EUROCWC", CUP_UEFACUP: "UEFACUP"}
CUP_SIZES = {CUP_EUROCUP: 16, CUP_EUROCWC: 32, CUP_UEFACUP: 32}
# The cups' compact descriptors and their BE16 participant key lists in
# the unpacked SWOS2 at runtime base RUNTIME_BASE.
CUP_DESCRIPTORS = {CUP_EUROCUP: 0x1CF35A, CUP_EUROCWC: 0x1CF3A8, CUP_UEFACUP: 0x1CF404}
CUP_KEY_LISTS = {CUP_EUROCUP: 0x1CF388, CUP_EUROCWC: 0x1CF3C4, CUP_UEFACUP: 0x1CF420}
POOL_ENTRIES, POOL_ENTRY_SIZE = 900, 58
POOL_SIZE = POOL_ENTRIES * POOL_ENTRY_SIZE                      # 52,200 bytes
SET_CODES = SUPPORTED_GROUPS + COPY_CODES                       # what a manifest declares
MAX_ENTRIES_V1 = 28
MAX_ENTRIES = 71 + len(COPY_CODES)                              # 75
MANIFEST_MAX_V1 = MANIFEST_HEADER + MAX_ENTRIES_V1 * ENTRY_SIZE  # 528 bytes
MANIFEST_MAX = MANIFEST_HEADER + MAX_ENTRIES * ENTRY_SIZE        # 1,280 bytes
LABEL_SIZE = 16
GENERATION_MAX = 9999
# Set labels are typed with the editors' keyboard field: the glyphs of the
# game's own menu font that its text entry accepts (team.i NAME_GLYPHS).
LABEL_GLYPHS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -/.")
# Names changed by a CSV file or a pack: the same glyphs and the punctuation
# the original groups use (' ( )), which the game's font shows.
TEXT_GLYPHS = LABEL_GLYPHS | frozenset("'()")

# Problems of a manifest, in the order the editor checks them (dbstore.s
# manifest_check), with the lines it shows ("%d" is the group).
MC_OK, MC_SIZE, MC_MAGIC, MC_VERSION, MC_CRC, MC_IDENTITY, MC_LABEL, MC_GROUP, MC_ORDER, MC_ENTRY = range(10)
MANIFEST_TEXTS = {
    MC_SIZE: "THE MANIFEST HAS THE WRONG SIZE.",
    MC_MAGIC: "THE FILE IS NOT A DATABASE MANIFEST.",
    MC_VERSION: "THE MANIFEST HAS AN UNKNOWN VERSION.",
    MC_CRC: "THE MANIFEST CRC-32 DIFFERS.",
    MC_IDENTITY: "THE SET IS FOR ANOTHER VERSION OF THE GAME.",
    MC_LABEL: "THE SET LABEL CANNOT BE SHOWN BY THE GAME.",
    MC_GROUP: "GROUP %d IS NOT A DATABASE GROUP.",
    MC_ORDER: "THE GROUPS ARE OUT OF ORDER OR LISTED TWICE.",
    MC_ENTRY: "THE ENTRY OF GROUP %d IS DAMAGED.",
}

# ---------------------------------------------------------------------------
# Link files
# ---------------------------------------------------------------------------
LINK_MAGIC = b"SWOSLNK1"
LINK_VERSION = 2                        # written; version 1 is still read
LINK_VERSIONS = (1, 2)
LINK_HEADER = 16
L_FAMILY, L_SAVE_LENGTH, L_SAVE_CRC, L_MANIFEST = 0, 2, 6, 10
LINK_MIN = LINK_HEADER + L_MANIFEST + MANIFEST_HEADER + ENTRY_SIZE
LINK_MAX_V1 = LINK_HEADER + L_MANIFEST + MANIFEST_MAX_V1           # 554 bytes
LINK_MAX = LINK_HEADER + L_MANIFEST + MANIFEST_MAX                 # 1,306 bytes
# Competition families as the game numbers them (word $1EEBDE).
FAMILY_DIY, FAMILY_PRESET, FAMILY_SEASON, FAMILY_CAREER = 1, 2, 3, 4
SAVE_SUFFIX = {FAMILY_DIY: ".DIY", FAMILY_PRESET: ".PRE", FAMILY_SEASON: ".SEA", FAMILY_CAREER: ".CAR"}
LINK_SUFFIX = {FAMILY_DIY: ".DLD", FAMILY_PRESET: ".DLP", FAMILY_SEASON: ".DLS", FAMILY_CAREER: ".DLC"}
LC_SIZE, LC_MAGIC, LC_VERSION, LC_CRC, LC_FAMILY, LC_SAVE = range(10, 16)
LINK_TEXTS = {
    LC_SIZE: "THE LINK FILE HAS THE WRONG SIZE.",
    LC_MAGIC: "THE FILE IS NOT A DATABASE LINK.",
    LC_VERSION: "THE LINK FILE HAS AN UNKNOWN VERSION.",
    LC_CRC: "THE LINK FILE CRC-32 DIFFERS.",
    LC_FAMILY: "THE LINK BELONGS TO ANOTHER KIND OF SAVE.",
    LC_SAVE: "THE SAVE DOES NOT MATCH ITS LINK.",
}

# Problems of a declared group file (verification before the set is used,
# and the read into the working group); "%s" is the file name.
GC_MISSING, GC_LENGTH, GC_CRC, GC_CONTENT = range(20, 24)
GROUP_TEXTS = {
    GC_MISSING: "%s IS MISSING.",
    GC_LENGTH: "%s HAS THE WRONG LENGTH.",
    GC_CRC: "%s HAS ANOTHER CRC-32.",
    GC_CONTENT: "%s IS DAMAGED.",
}

# Save directory admission (SAVE_DIR_MAX_NAMES of src/editor/include/slave.i):
# the slave admits a new name only while data/ holds fewer than this many
# names.
SAVE_DIR_MAX_NAMES = 512

# The remembered state of USE EDITED DATABASE: DBASE.USE, magic, version 1,
# the state word (0 off, 1 on) and the CRC-32 of the twelve bytes before it.
# Hidden from the game's own file listing (only the editors read it) and
# outside the set's fingerprint.
SWITCH_NAME = "DBASE.USE"
SWITCH_MAGIC = b"SWOSUSE1"
SWITCH_VERSION = 1
SWITCH_SIZE = 16


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def problem_text(code: int, detail: int | str = 0) -> str:
    """The line the editor shows for a problem (at most 50 characters); empty
    for MC_OK."""
    if code == MC_OK:
        return ""
    text = {**MANIFEST_TEXTS, **LINK_TEXTS, **GROUP_TEXTS}[code]
    if "%d" in text:
        return text % int(detail)
    if "%s" in text:
        return text % detail
    return text


class SetError(ValueError):
    """A file or an input the editor would refuse; str() is the problem line."""

    def __init__(self, code: int, detail: int | str = 0):
        super().__init__(problem_text(code, detail))
        self.code = code
        self.detail = detail


# ---------------------------------------------------------------------------
# Manifest codec
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Entry:
    group: int
    generation: int
    count: int
    length: int
    crc: int

    @property
    def name(self) -> str:
        return generation_name(self.group, self.generation)


@dataclass
class Manifest:
    generation: int
    label: str
    entries: list[Entry] = field(default_factory=list)

    def entry(self, group: int) -> Entry | None:
        return next((e for e in self.entries if e.group == group), None)

    def names(self) -> set[str]:
        return {e.name for e in self.entries}


def generation_name(group: int, generation: int) -> str:
    if group not in SET_CODES or not 1 <= generation <= GENERATION_MAX:
        raise ValueError(f"no generation name for group {group}, generation {generation}")
    return f"T{group:03d}{generation:04d}.GRP"


def parse_generation_name(name: str) -> tuple[int, int] | None:
    """(group, generation) of a name Tgggnnnn.GRP (any case), else None."""
    upper = name.upper()
    if len(upper) != 12 or upper[0] != "T" or upper[8:] != ".GRP" or not upper[1:8].isdigit():
        return None
    group, generation = int(upper[1:4]), int(upper[4:8])
    if group not in SET_CODES or not 1 <= generation <= GENERATION_MAX:
        return None
    return group, generation


def check_label(label: str) -> bytes:
    raw = label.encode("latin-1", "replace")
    if len(raw) > LABEL_SIZE or any(chr(c) not in LABEL_GLYPHS for c in raw):
        raise SetError(MC_LABEL)
    return raw.ljust(LABEL_SIZE, b"\0")


def entry_shape(code: int, count: int) -> int | None:
    """The length an entry of code with count records must have, or None
    when the count is wrong for the code: a database group 1-93 teams with
    its count word, a cup copy exactly its participants, the pool its 900
    entries."""
    if code in SUPPORTED_GROUPS:
        return 2 + count * TEAM_SIZE if 1 <= count <= GROUP_MAX_TEAMS else None
    if code in CUP_CODES:
        return count * TEAM_SIZE if count == CUP_SIZES[code] else None
    if code == COPY_POOL:
        return POOL_SIZE if count == POOL_ENTRIES else None
    return None


def encode_manifest(manifest: Manifest, version: int = MANIFEST_VERSION) -> bytes:
    entries = sorted(manifest.entries, key=lambda e: e.group)
    if version not in MANIFEST_VERSIONS or not 1 <= len(entries) <= (MAX_ENTRIES_V1 if version == 1 else MAX_ENTRIES):
        raise SetError(MC_SIZE)
    if not 1 <= manifest.generation <= 0xFFFFFFFF:
        raise ValueError("manifest generation must be 1 or more")
    out = bytearray(MANIFEST_HEADER + ENTRY_SIZE * len(entries))
    out[M_MAGIC:M_MAGIC + 8] = MANIFEST_MAGIC
    struct.pack_into(">HHI", out, M_VERSION, version, len(entries), manifest.generation)
    out[M_IDENTITY:M_IDENTITY + 32] = SWOS2_IDENTITY
    struct.pack_into(">II", out, M_BASE, RUNTIME_BASE, len(out))
    out[M_LABEL:M_LABEL + LABEL_SIZE] = check_label(manifest.label)
    for index, entry in enumerate(entries):
        struct.pack_into(">HHHHII", out, MANIFEST_HEADER + index * ENTRY_SIZE, entry.group,
                         entry.generation, entry.count, 0, entry.length, entry.crc)
    struct.pack_into(">I", out, M_CRC, crc32(bytes(out)))
    decode_manifest(bytes(out))
    return bytes(out)


def manifest_crc(raw: bytes) -> int:
    """The manifest's fingerprint: its CRC-32 field."""
    return struct.unpack_from(">I", raw, M_CRC)[0]


def check_manifest(raw: bytes) -> tuple[int, int]:
    """(MC_*, detail) of the first problem, in the editor's order. Version 1,
    the earlier format, declares at most 28 database groups; version 2 every
    database group and the copies."""
    size = len(raw)
    if size < MANIFEST_HEADER + ENTRY_SIZE or size > MANIFEST_MAX or (size - MANIFEST_HEADER) % ENTRY_SIZE:
        return MC_SIZE, 0
    if raw[M_MAGIC:M_MAGIC + 8] != MANIFEST_MAGIC:
        return MC_MAGIC, 0
    version, count = struct.unpack_from(">HH", raw, M_VERSION)
    if version not in MANIFEST_VERSIONS:
        return MC_VERSION, 0
    (length,) = struct.unpack_from(">I", raw, M_LENGTH)
    limit = MAX_ENTRIES_V1 if version == 1 else MAX_ENTRIES
    if not 1 <= count <= limit or length != size or size != MANIFEST_HEADER + ENTRY_SIZE * count:
        return MC_SIZE, 0
    stored = manifest_crc(raw)
    if crc32(raw[:M_CRC] + b"\0\0\0\0" + raw[M_CRC + 4:]) != stored:
        return MC_CRC, 0
    base, reserved = struct.unpack_from(">I", raw, M_BASE)[0], struct.unpack_from(">I", raw, M_RESERVED)[0]
    if raw[M_IDENTITY:M_IDENTITY + 32] != SWOS2_IDENTITY or base != RUNTIME_BASE:
        return MC_IDENTITY, 0
    if reserved:
        return MC_VERSION, 0
    label = raw[M_LABEL:M_LABEL + LABEL_SIZE]
    text, _, tail = label.partition(b"\0")
    if any(tail) or any(chr(c) not in LABEL_GLYPHS for c in text):
        return MC_LABEL, 0
    previous = -1
    for index in range(count):
        group, generation, teams, zero, length, _crc = struct.unpack_from(
            ">HHHHII", raw, MANIFEST_HEADER + index * ENTRY_SIZE)
        if group not in (SUPPORTED_GROUPS if version == 1 else SET_CODES):
            return MC_GROUP, group
        if group <= previous:
            return MC_ORDER, group
        previous = group
        if not 1 <= generation <= GENERATION_MAX or zero or length != entry_shape(group, teams):
            return MC_ENTRY, group
    return MC_OK, 0


def manifest_version(raw: bytes) -> int:
    return struct.unpack_from(">H", raw, M_VERSION)[0]


def decode_manifest(raw: bytes) -> Manifest:
    code, detail = check_manifest(raw)
    if code != MC_OK:
        raise SetError(code, detail)
    _version, count, generation = struct.unpack_from(">HHI", raw, M_VERSION)
    label = raw[M_LABEL:M_LABEL + LABEL_SIZE].partition(b"\0")[0].decode("latin-1")
    entries = []
    for index in range(count):
        group, gen, teams, _zero, length, crc = struct.unpack_from(">HHHHII", raw, MANIFEST_HEADER + index * ENTRY_SIZE)
        entries.append(Entry(group, gen, teams, length, crc))
    return Manifest(generation, label, entries)


def manifest_document(raw: bytes) -> dict:
    manifest = decode_manifest(raw)
    def kind(code: int) -> str:
        return CUP_NAMES.get(code, "POOLPLYR" if code == COPY_POOL else "GROUP")
    return {"format": "SWOSGRP1", "version": manifest_version(raw), "generation": manifest.generation,
            "label": manifest.label, "crc32": f"{manifest_crc(raw):08X}",
            "groups": [{"group": e.group, "kind": kind(e.group), "file": e.name, "records": e.count,
                        "length": e.length, "crc32": f"{e.crc:08X}"} for e in manifest.entries]}


# ---------------------------------------------------------------------------
# Link files
# ---------------------------------------------------------------------------
def family_of_save(name: str) -> int:
    suffix = name[-4:].upper()
    for family, value in SAVE_SUFFIX.items():
        if value == suffix:
            return family
    raise ValueError(f"{name} is not a competition save (.DIY .PRE .SEA .CAR)")


def link_name(save_name: str) -> str:
    """The link file of a competition save: its base name and .DLD, .DLP,
    .DLS or .DLC."""
    return save_name[:-4] + LINK_SUFFIX[family_of_save(save_name)]


def encode_link(family: int, save: bytes, manifest_raw: bytes, version: int = LINK_VERSION) -> bytes:
    """A link file; version 2 (the one the editor writes) may carry a
    manifest of either version, version 1 only a version 1 manifest."""
    if family not in SAVE_SUFFIX or not save:
        raise ValueError("a link needs a competition family and a save")
    decode_manifest(manifest_raw)
    if version not in LINK_VERSIONS or (version == 1 and manifest_version(manifest_raw) != 1):
        raise ValueError("a version 1 link carries a version 1 manifest")
    body = struct.pack(">HII", family, len(save), crc32(save)) + manifest_raw
    return LINK_MAGIC + struct.pack(">HHI", version, len(body), crc32(body)) + body


def check_link(raw: bytes, family: int | None = None, save: bytes | None = None) -> tuple[int, int]:
    """(LC_* or MC_*, detail) of the first problem as the editor checks a
    link before a bound save is loaded; (MC_OK, 0) when it is sound."""
    size = len(raw)
    if size < LINK_MIN or size > LINK_MAX:
        return LC_SIZE, 0
    if raw[:8] != LINK_MAGIC:
        return LC_MAGIC, 0
    version, body_length, body_crc = struct.unpack_from(">HHI", raw, 8)
    if version not in LINK_VERSIONS:
        return LC_VERSION, 0
    if body_length != size - LINK_HEADER:
        return LC_SIZE, 0
    body = raw[LINK_HEADER:]
    if crc32(body) != body_crc:
        return LC_CRC, 0
    link_family, save_length, save_crc = struct.unpack_from(">HII", body, 0)
    if link_family not in SAVE_SUFFIX or (family is not None and link_family != family):
        return LC_FAMILY, 0
    manifest = body[L_MANIFEST:]
    if version == 1 and len(manifest) >= M_VERSION + 2 and manifest_version(manifest) != 1:
        return LC_VERSION, 0
    code, detail = check_manifest(manifest)
    if code != MC_OK:
        return code, detail
    # the editor compares the save after the link's own checks (load_common)
    if save is not None and (save_length != len(save) or save_crc != crc32(save)):
        return LC_SAVE, 0
    return MC_OK, 0


def decode_link(raw: bytes) -> dict:
    code, detail = check_link(raw)
    if code != MC_OK:
        raise SetError(code, detail)
    body = raw[LINK_HEADER:]
    family, save_length, save_crc = struct.unpack_from(">HII", body, 0)
    return {"format": "SWOSLNK1", "family": family, "save_suffix": SAVE_SUFFIX[family],
            "save_length": save_length, "save_crc32": f"{save_crc:08X}",
            "manifest": manifest_document(body[L_MANIFEST:])}


# ---------------------------------------------------------------------------
# Groups and their checks
# ---------------------------------------------------------------------------
def group_teams(raw: bytes) -> list[bytes]:
    count = struct.unpack_from(">H", raw, 0)[0]
    if len(raw) != 2 + count * TEAM_SIZE:
        raise ValueError(f"group count {count} disagrees with its length {len(raw)}")
    return [raw[2 + i * TEAM_SIZE:2 + (i + 1) * TEAM_SIZE] for i in range(count)]


def division_counts(raw: bytes) -> dict[int, int]:
    counts: dict[int, int] = {}
    for team in group_teams(raw):
        counts[team[0x19]] = counts.get(team[0x19], 0) + 1
    return counts


def original_pool(originals: dict[int, bytes]) -> dict[bytes, bytes]:
    """The original team records by team name (the first of a name), for
    the values a moved team keeps (validate_group)."""
    pool: dict[bytes, bytes] = {}
    for group in SUPPORTED_GROUPS:
        if group in originals:
            for team in group_teams(originals[group]):
                pool.setdefault(team[5:0x16], team)
    return pool


TEXT_PROBLEM = "A NAME HAS A CHARACTER THE GAME CANNOT SHOW."


def text_problem(team: bytes, bases: list[bytes]) -> int | None:
    """None when every text of the team record (its name, its coach and the
    16 player names) is one of bases' or uses only characters the game's
    font shows and its text entry takes; else -1 for the team's own texts
    or the player slot. Every text of the game's own database passes."""
    spans = [(5, 0x16, -1), (0x24, 0x3B, -1)] + [
        (0x4C + slot * 0x26 + 3, 0x4C + slot * 0x26 + 3 + 23, slot) for slot in range(16)]
    for start, end, slot in spans:
        value = _text(team[start:end])
        if all(value != _text(base[start:end]) for base in bases) and any(c not in TEXT_GLYPHS for c in value):
            return slot
    return None


def validate_group(group: int, raw: bytes, original: bytes, pool: dict[bytes, bytes] | None = None,
                   current: bytes | None = None) -> list[str]:
    """Every reason the editor or the game would refuse an edited group, as
    lines naming the team and player; [] when it is a valid override.

    Values of the original data outside the editors' ranges (goalkeeper
    ratings 39-40, a default tactic 12-17) are accepted while unchanged: as
    the original record of the slot has them, the record the install's set
    holds for the slot (current: the editor's team OK compares with the
    record it loaded, so a user tactic chosen in the game is kept), or the
    original record of the same team name in pool (a team moved by EXCHANGE
    or COPY TO COUNTRY). A changed text uses only the characters the game
    shows."""
    problems = []
    if len(raw) != len(original):
        return [f"GROUP {group}: {len(raw)} BYTES, THE ORIGINAL HAS {len(original)}"]
    teams, originals = group_teams(raw), group_teams(original)
    currents: list = [None] * len(teams)
    if current is not None and len(current) == len(original):
        currents = group_teams(current)
    for ordinal, (team, base, now) in enumerate(zip(teams, originals, currents)):
        if team[0] != group or team[1] != ordinal:
            problems.append(f"GROUP {group} TEAM {ordinal}: THE KEY IS {team[0]}/{team[1]}")
            continue
        if group in NATIONAL_GROUPS and team[0x19] != base[0x19]:
            problems.append(f"GROUP {group} TEAM {ordinal}: A NATIONAL TEAM KEEPS ITS DIVISION")
        moved = pool.get(team[5:0x16]) if pool is not None else None
        kept = (now,) if now is not None else ()
        result = custom_set.team_validate(team, base, moved, kept=kept)
        if result is None:
            slot = text_problem(team, [base, *kept] + ([moved] if moved is not None else []))
            if slot is not None:
                result = TEXT_PROBLEM, slot
        if result is not None:
            reason, slot = result
            where = f" PLAYER {slot + 1}" if slot >= 0 else ""
            problems.append(f"GROUP {group} TEAM {ordinal}{where}: {reason}")
    if division_counts(raw) != division_counts(original):
        problems.append(f"GROUP {group}: A DIVISION DOES NOT KEEP ITS NUMBER OF TEAMS")
    return problems


def check_group_file(entry: Entry, raw: bytes | None) -> tuple[int, str]:
    """(GC_* or MC_OK, file name) as the editor verifies a declared file;
    for a group also its count and keys, for a cup copy that every record
    is a club of a club group, each once, for the pool that every entry
    names a club group's team and a player slot."""
    if raw is None:
        return GC_MISSING, entry.name
    if len(raw) != entry.length:
        return GC_LENGTH, entry.name
    if crc32(raw) != entry.crc:
        return GC_CRC, entry.name
    if entry.group in CUP_CODES:
        keys = [raw[i * TEAM_SIZE:i * TEAM_SIZE + 2] for i in range(entry.count)]
        if len(set(keys)) != len(keys) or any(k[0] not in CLUB_GROUPS for k in keys):
            return GC_CONTENT, entry.name
        return MC_OK, entry.name
    if entry.group == COPY_POOL:
        if any(raw[i * POOL_ENTRY_SIZE] not in CLUB_GROUPS or raw[i * POOL_ENTRY_SIZE + 2] > 15
               for i in range(POOL_ENTRIES)):
            return GC_CONTENT, entry.name
        return MC_OK, entry.name
    count = struct.unpack_from(">H", raw, 0)[0]
    if count != entry.count or any(raw[2 + i * TEAM_SIZE] != entry.group or raw[3 + i * TEAM_SIZE] != i
                                   for i in range(count)):
        return GC_CONTENT, entry.name
    return MC_OK, entry.name


def original_groups_from_disk2(data: bytes) -> dict[int, bytes]:
    """The unpacked original TEAM groups of the user's disk 2 (hash-checked)."""
    from adf_extract import ADF
    import rnc
    if hashlib.sha256(data).hexdigest() != DISK2_SHA256:
        raise ValueError("disk 2 is not disk 2 of the supported SWOS 96-97 release")
    contents = ADF(data).contents
    groups = {}
    for group in SUPPORTED_GROUPS:
        packed = contents[f"data/TEAM.{group:03d}"]
        groups[group] = rnc.unpack(packed) if packed[:3] == b"RNC" else packed
    return groups


def custom_group_from_disk2(data: bytes) -> bytes:
    """The game's own custom set, group 72 (TEAM.072), of the user's disk 2:
    what EDIT CUSTOM TEAMS starts from without a CUSTOMS.EDT."""
    from adf_extract import ADF
    import rnc
    if hashlib.sha256(data).hexdigest() != DISK2_SHA256:
        raise ValueError("disk 2 is not disk 2 of the supported SWOS 96-97 release")
    packed = ADF(data).contents[f"data/TEAM.{CUSTOM_GROUP:03d}"]
    return rnc.unpack(packed) if packed[:3] == b"RNC" else packed


def nationality_labels_from_disk1(data: bytes) -> list[str]:
    """The 153 three-letter nationality labels of the user's own SWOS2."""
    from adf_extract import ADF
    import rnc
    if hashlib.sha256(data).hexdigest() != DISK1_SHA256:
        raise ValueError("disk 1 is not disk 1 of the supported SWOS 96-97 release")
    image = rnc.unpack(ADF(data).contents["SWOS2"])
    if hashlib.sha256(image).hexdigest() != SWOS2_SHA256:
        raise ValueError("SWOS2 on disk 1 differs from the supported release")
    return [image[NATIONALITY_TABLE + 3 * i:NATIONALITY_TABLE + 3 * i + 3].decode("latin-1")
            for i in range(NATIONALITIES)]


# ---------------------------------------------------------------------------
# The copies that follow the set
# ---------------------------------------------------------------------------
@dataclass
class Base:
    """The user's 96/97 database: the original groups and the game's own
    copies that a set may refresh: the European club cups' team copies in
    the order of the descriptors' participant lists, those lists, and the
    transfer pool."""
    groups: dict[int, bytes]
    cups: dict[int, list[bytes]]
    lists: dict[int, list[tuple[int, int]]]
    pool: bytes


def swos2_from_disk1(data: bytes) -> bytes:
    """The unpacked SWOS2 of the user's disk 1 (hash-checked)."""
    from adf_extract import ADF
    import rnc
    if hashlib.sha256(data).hexdigest() != DISK1_SHA256:
        raise ValueError("disk 1 is not disk 1 of the supported SWOS 96-97 release")
    image = rnc.unpack(ADF(data).contents["SWOS2"])
    if hashlib.sha256(image).hexdigest() != SWOS2_SHA256:
        raise ValueError("SWOS2 on disk 1 differs from the supported release")
    return image


def base_from_disks(disk1: bytes, disk2: bytes) -> Base:
    """The 96/97 database of the user's own disks."""
    from adf_extract import ADF
    import rnc
    groups = original_groups_from_disk2(disk2)
    image = swos2_from_disk1(disk1)
    contents = ADF(disk2).contents

    def unpacked(name: str) -> bytes:
        packed = contents[name]
        return rnc.unpack(packed) if packed[:3] == b"RNC" else packed

    lists, cups = {}, {}
    for code in CUP_CODES:
        offset = CUP_KEY_LISTS[code] - RUNTIME_BASE
        keys = [struct.unpack_from(">H", image, offset + 2 * i)[0] for i in range(CUP_SIZES[code])]
        lists[code] = [(key >> 8, key & 0xFF) for key in keys]
        records = unpacked(f"data/{CUP_NAMES[code]}.TMD")
        by_key = {records[i:i + 2]: records[i:i + TEAM_SIZE] for i in range(0, len(records), TEAM_SIZE)}
        cups[code] = [by_key[struct.pack(">BB", *key)] for key in lists[code]]
    return Base(groups, cups, lists, unpacked("data/POOLPLYR.DAT"))


def group_record(groups: dict[int, bytes], key: tuple[int, int]) -> bytes:
    group, ordinal = key
    raw = groups[group]
    if not 0 <= ordinal < struct.unpack_from(">H", raw, 0)[0]:
        raise ValueError(f"group {group} has no team {ordinal}")
    return raw[2 + ordinal * TEAM_SIZE:2 + (ordinal + 1) * TEAM_SIZE]


class CupError(ValueError):
    """A participant list the editors refuse."""


def check_cup_lists(lists: dict[int, list[tuple[int, int]]], groups: dict[int, bytes]) -> None:
    """The rules of participant lists, as the game's own lists keep them:
    each cup exactly its number of clubs, each a team of a club group (no
    national team, no custom team), no club twice, in one cup or two."""
    seen: dict[tuple[int, int], int] = {}
    for code in CUP_CODES:
        keys = lists[code]
        name = CUP_NAMES[code]
        if len(keys) != CUP_SIZES[code]:
            raise CupError(f"{name}: {len(keys)} clubs, the cup takes {CUP_SIZES[code]}")
        for place, key in enumerate(keys, start=1):
            group, ordinal = key
            if group not in CLUB_GROUPS:
                raise CupError(f"{name} place {place}: group {group} is not a club group")
            if not 0 <= ordinal < struct.unpack_from(">H", groups[group], 0)[0]:
                raise CupError(f"{name} place {place}: group {group} has no team {ordinal}")
            if key in seen:
                where = "twice" if seen[key] == code else f"also in {CUP_NAMES[seen[key]]}"
                raise CupError(f"{name} place {place}: club {group}/{ordinal} is {where}")
            seen[key] = code


def build_cup(base: Base, groups: dict[int, bytes], code: int, keys: list[tuple[int, int]]) -> bytes:
    """A cup's team copies: per participant the record of its key in the
    groups, with the secondary ID and flag a copy has in the game's own
    file (a club of another 96/97 cup list keeps that copy's, a new one its
    group's, flag 1)."""
    known = {}
    for cup in CUP_CODES:
        for record in base.cups[cup]:
            known[(record[0], record[1])] = record
    out = bytearray()
    for key in keys:
        record = bytearray(group_record(groups, key))
        original = known.get(key)
        record[2:4] = original[2:4] if original is not None else record[2:4]
        record[4] = 1
        out += record
    return bytes(out)


def build_pool(base: Base, groups: dict[int, bytes]) -> bytes:
    """The transfer pool with every entry's team name and player record
    taken from the groups (its group, ordinal and slot stay)."""
    out = bytearray(base.pool)
    for index in range(POOL_ENTRIES):
        at = index * POOL_ENTRY_SIZE
        group, ordinal, slot = out[at], out[at + 1], out[at + 2]
        record = group_record(groups, (group, ordinal))
        out[at + 3:at + 0x14] = record[5:0x16]
        out[at + 0x14:at + 0x14 + PLAYER_SIZE] = record[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE]
    return bytes(out)


def build_copies(base: Base, groups: dict[int, bytes],
                 lists: dict[int, list[tuple[int, int]]] | None = None) -> dict[int, bytes]:
    """The copies a set with these groups and participant lists declares:
    those that differ from the game's 96/97 copies (cups in descriptor
    order). lists names the participants of some cups; the others keep the
    96/97 lists."""
    lists = {**base.lists, **(lists or {})}
    check_cup_lists(lists, groups)
    copies = {}
    for code in CUP_CODES:
        data = build_cup(base, groups, code, lists[code])
        if data != b"".join(base.cups[code]):
            copies[code] = data
    pool = build_pool(base, groups)
    if pool != base.pool:
        copies[COPY_POOL] = pool
    return copies


def cup_lists_of(copies: dict[int, bytes], base: Base) -> dict[int, list[tuple[int, int]]]:
    """The participants of the three cups: a declared copy's, else 96/97."""
    lists = {}
    for code in CUP_CODES:
        data = copies.get(code)
        lists[code] = ([(data[i], data[i + 1]) for i in range(0, len(data), TEAM_SIZE)]
                       if data is not None else list(base.lists[code]))
    return lists


def check_copies(copies: dict[int, bytes], groups: dict[int, bytes]) -> list[str]:
    """Problems of declared copies against the set's groups: a cup copy's
    records equal their keys' team records but the secondary ID and flag,
    the pool's entries their keys' team names and players."""
    problems = []
    for code in CUP_CODES:
        data = copies.get(code)
        if data is None:
            continue
        for place in range(CUP_SIZES[code]):
            record = data[place * TEAM_SIZE:(place + 1) * TEAM_SIZE]
            try:
                team = group_record(groups, (record[0], record[1]))
            except (KeyError, ValueError):
                problems.append(f"{CUP_NAMES[code]} PLACE {place + 1}: NO TEAM {record[0]}/{record[1]}")
                continue
            if record[:2] + record[5:] != team[:2] + team[5:]:
                problems.append(f"{CUP_NAMES[code]} PLACE {place + 1}: THE COPY DIFFERS FROM ITS TEAM")
    pool = copies.get(COPY_POOL)
    if pool is not None:
        for index in range(POOL_ENTRIES):
            at = index * POOL_ENTRY_SIZE
            try:
                team = group_record(groups, (pool[at], pool[at + 1]))
            except (KeyError, ValueError):
                problems.append(f"POOL ENTRY {index}: NO TEAM {pool[at]}/{pool[at + 1]}")
                continue
            slot = pool[at + 2] & 15
            if pool[at + 3:at + 0x14] != team[5:0x16] or pool[at + 0x14:at + 0x3A] != \
                    team[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE]:
                problems.append(f"POOL ENTRY {index}: THE COPY DIFFERS FROM ITS PLAYER")
    return problems


def base_identity(originals: dict[int, bytes]) -> str:
    """The SHA-256 a season pack is relative to: every supported original
    group in ascending order as group byte, BE32 length and bytes."""
    digest = hashlib.sha256()
    for group in SUPPORTED_GROUPS:
        raw = originals[group]
        digest.update(bytes([group]) + struct.pack(">I", len(raw)) + raw)
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# Save directory
# ---------------------------------------------------------------------------
stored = custom_set.stored


def read_set(directory: Path) -> tuple[Manifest | None, bytes | None]:
    path = stored(directory, MANIFEST_NAME)
    if not path.exists():
        return None, None
    raw = path.read_bytes()
    return decode_manifest(raw), raw


def set_contents(directory: Path, originals: dict[int, bytes]) -> tuple[dict[int, bytes], dict[int, bytes]]:
    """(groups, copies) as the edited set in directory declares them (each
    file verified): the original groups for every group it does not
    declare, and the copies it declares."""
    groups, copies = dict(originals), {}
    manifest, _ = read_set(directory)
    if manifest is None:
        return groups, copies
    for entry in manifest.entries:
        path = stored(directory, entry.name)
        raw = path.read_bytes() if path.exists() else None
        code, name = check_group_file(entry, raw)
        if code != MC_OK:
            raise SetError(code, name)
        (copies if entry.group in COPY_CODES else groups)[entry.group] = raw
    return groups, copies


def set_groups(directory: Path, originals: dict[int, bytes]) -> dict[int, bytes]:
    """The groups as the edited set in directory declares them (each file
    verified), the original groups for every other group."""
    return set_contents(directory, originals)[0]


def encode_switch(on: bool) -> bytes:
    head = SWITCH_MAGIC + struct.pack(">HH", SWITCH_VERSION, 1 if on else 0)
    return head + struct.pack(">I", crc32(head))


def decode_switch(raw: bytes) -> bool | None:
    """The state DBASE.USE remembers, or None for a file the editor ignores
    (another size, magic, version, state or CRC-32): the switch is off."""
    if len(raw) != SWITCH_SIZE or raw[:8] != SWITCH_MAGIC:
        return None
    version, state = struct.unpack_from(">HH", raw, 8)
    if version != SWITCH_VERSION or state > 1 or struct.unpack_from(">I", raw, 12)[0] != crc32(raw[:12]):
        return None
    return state == 1


def read_switch(directory: Path) -> bool:
    path = stored(directory, SWITCH_NAME)
    return bool(path.exists() and decode_switch(path.read_bytes()))


def write_switch(directory: Path, on: bool) -> None:
    """Remembers USE EDITED DATABASE as the editor does (read back)."""
    directory.mkdir(parents=True, exist_ok=True)
    names = {p.name.upper() for p in directory.iterdir() if p.is_file()}
    if SWITCH_NAME not in names and len(names) + 1 > SAVE_DIR_MAX_NAMES:
        raise AdmissionError(f"the save directory would hold more than {SAVE_DIR_MAX_NAMES} files")
    _write_verified(stored(directory, SWITCH_NAME), encode_switch(on))


def next_generation(names: Iterable[str], group: int, start: int = 1) -> int:
    """The first generation from start whose file name is not used yet
    (numbering wraps after 9999; a name that exists is never reused)."""
    used = {parsed[1] for parsed in map(parse_generation_name, names)
            if parsed is not None and parsed[0] == group}
    for step in range(GENERATION_MAX):
        generation = (start - 1 + step) % GENERATION_MAX + 1
        if generation not in used:
            return generation
    raise SetError(GC_CONTENT, generation_name(group, 1))


class AdmissionError(ValueError):
    """The save directory cannot take the set: it would hold too many names,
    or the set would declare nothing while a set is in use."""


def _write_verified(path: Path, data: bytes) -> None:
    if not data:
        raise ValueError(f"{path.name}: a file is never written empty")
    path.write_bytes(data)
    if path.read_bytes() != data:
        raise OSError(f"{path.name}: the readback differs")


@dataclass
class SetPlan:
    """What write_set writes, in order: the new generation files, the
    previous DBASE.CFG as DBASE.BAK (backup, None without one) and the new
    DBASE.CFG. manifest is None when nothing differs from the set there."""
    manifest: Manifest | None
    files: dict[str, bytes] = field(default_factory=dict)
    backup: bytes | None = None
    raw_manifest: bytes | None = None


def write_set(directory: Path, originals: dict[int, bytes], groups: dict[int, bytes], label: str, *,
              base: Base | None = None, lists: dict[int, list[tuple[int, int]]] | None = None) -> Manifest | None:
    """Writes the edited groups (those differing from the originals) as a new
    generation of the set in directory, in the editor's sequence: new
    generation files first, the previous DBASE.CFG as a verified DBASE.BAK,
    then DBASE.CFG read back. A file that equals its current generation
    keeps it. Returns the new manifest, or None when nothing differs from
    the set already there. Raises AdmissionError, SetError or OSError before
    anything of the set in use is replaced (see plan_set)."""
    return write_plan(directory, plan_set(directory, originals, groups, label, base=base, lists=lists))


def write_plan(directory: Path, plan: SetPlan) -> Manifest | None:
    """Writes a plan of plan_set, every file read back."""
    if plan.manifest is None:
        return None
    directory.mkdir(parents=True, exist_ok=True)
    for name, raw in plan.files.items():
        _write_verified(directory / name, raw)
    if plan.backup is not None:
        _write_verified(stored(directory, BACKUP_NAME), plan.backup)
    _write_verified(stored(directory, MANIFEST_NAME), plan.raw_manifest)
    return plan.manifest


def plan_set(directory: Path, originals: dict[int, bytes], groups: dict[int, bytes], label: str, *,
             base: Base | None = None, lists: dict[int, list[tuple[int, int]]] | None = None) -> SetPlan:
    """Every check of write_set, without writing: the files a new generation
    of the set in directory (which need not exist yet) consists of.

    With base (the user's 96/97 database, base_from_disks) the set also
    declares the copies that follow it: the cups' team copies for the
    participant lists (lists names some cups; the others keep the
    participants the set has, else 96/97) and the transfer pool, each when
    it differs from the 96/97 copy. Without base the copies the set already
    declares stay as they are."""
    check_label(label)
    for group in groups:
        if group not in SUPPORTED_GROUPS:
            raise SetError(MC_GROUP, group)
    full = {**originals, **groups}
    edited = {g: raw for g, raw in full.items() if raw != originals[g]}
    pool = original_pool(originals)
    current, current_raw = read_set(directory)
    current_groups, current_copies = set_contents(directory, originals) if current is not None else ({}, {})
    for group, raw in edited.items():
        problems = validate_group(group, raw, originals[group], pool, current_groups.get(group))
        if problems:
            raise ValueError("; ".join(problems[:5]))
    if base is not None:
        kept = {code: data for code, data in cup_lists_of(current_copies, base).items()}
        copies = build_copies(base, full, {**kept, **(lists or {})})
    else:
        if lists:
            raise ValueError("participant lists need the 96/97 database (base)")
        copies = current_copies
    problems = check_copies(copies, full)
    if problems:
        raise ValueError("; ".join(problems[:5]))
    declared = {**edited, **copies}
    if not declared:
        if current is None:
            return SetPlan(None)
        raise AdmissionError("every group equals the original database; the set in use stays "
                             "(switch USE EDITED DATABASE off to play with the originals)")
    names = [p.name for p in directory.iterdir() if p.is_file()] if directory.is_dir() else []
    entries, new_files = [], {}
    for group in sorted(declared):
        raw = declared[group]
        old = current.entry(group) if current else None
        if old is not None and old.crc == crc32(raw) and old.length == len(raw) \
                and stored(directory, old.name).exists() and stored(directory, old.name).read_bytes() == raw:
            entries.append(old)
            continue
        start = old.generation + 1 if old else 1
        generation = next_generation(names + list(new_files), group, start)
        records = len(raw) // (POOL_ENTRY_SIZE if group == COPY_POOL else TEAM_SIZE)
        entry = Entry(group, generation, records, len(raw), crc32(raw))
        new_files[entry.name] = raw
        entries.append(entry)
    manifest = Manifest(current.generation + 1 if current else 1, label, entries)
    if current is not None and current.entries == entries and current.label == label \
            and manifest_version(current_raw) == MANIFEST_VERSION:
        return SetPlan(None)
    new_names = set(new_files) | {MANIFEST_NAME, BACKUP_NAME}
    if len({n.upper() for n in names} | new_names) > SAVE_DIR_MAX_NAMES:
        raise AdmissionError(f"the save directory would hold more than {SAVE_DIR_MAX_NAMES} files")
    return SetPlan(manifest, new_files, current_raw, encode_manifest(manifest))


def write_install(directory: Path, base: Base, groups: dict[int, bytes], label: str, *,
                  lists: dict[int, list[tuple[int, int]]] | None = None, switch: bool = True) -> Manifest | None:
    """A set written into the save directory of an install: the groups,
    participant lists and label as write_set with base, then USE EDITED
    DATABASE remembered as switch, so the game starts with the set in use.
    Two directories written from the same disks and inputs show the same
    fingerprint."""
    manifest = write_set(directory, base.groups, groups, label, base=base, lists=lists)
    write_switch(directory, switch and read_set(directory)[0] is not None)
    return manifest


# ---------------------------------------------------------------------------
# Field view of teams and players (CSV and packs)
# ---------------------------------------------------------------------------
def _text(raw: bytes) -> str:
    return raw.partition(b"\0")[0].decode("latin-1")


def _put_text(record: bytearray, offset: int, size: int, value: str, what: str) -> None:
    """A changed text: NUL-terminated and zero-padded within its span; an
    unchanged text keeps its whole span, the bytes after its NUL included, so
    an unchanged record stays byte for byte the game's."""
    if _text(bytes(record[offset:offset + size])) == value:
        return
    raw = value.encode("latin-1", "replace")
    if len(raw) >= size:
        raise ValueError(f"{what}: at most {size - 1} characters")
    if any(chr(c) not in TEXT_GLYPHS for c in raw):
        raise ValueError(f"{what}: a character the game cannot show")
    record[offset:offset + size] = raw.ljust(size, b"\0")


def team_fields(team: bytes) -> dict:
    return {"name": _text(team[5:0x16]), "coach": _text(team[0x24:0x3B]), "division": team[0x19],
            "home_kit": list(team[0x1A:0x1F]), "away_kit": list(team[0x1F:0x24]), "tactic": team[0x18],
            "lineup": list(team[0x3C:0x4C])}


def player_fields(record: bytes) -> dict:
    skills = struct.unpack_from(">I", record, 0x1C)[0]
    nibbles = [(skills >> (24 - 4 * i)) & 15 for i in range(7)]
    keeper = record[0x1A] >> 5 == 0
    return {"shirt": record[2], "name": _text(record[3:0x1A]), "nationality": record[0],
            "position": POSITIONS[record[0x1A] >> 5], "appearance": (record[0x1A] >> 3) & 3,
            "skills": [n & 7 for n in nibbles], "specialties": [n >> 3 for n in nibbles],
            "rating": record[0x20] if keeper else None}


TEAM_FIELDS = ("name", "coach", "division", "home_kit", "away_kit", "tactic", "lineup")
PLAYER_FIELDS = ("shirt", "name", "nationality", "position", "appearance", "skills", "specialties", "rating")


def _byte(value, what: str, low: int = 0, high: int = 255) -> int:
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{what}: {value!r} is not {low}-{high}")
    return value


def _bytes(value, size: int, what: str, high: int = 255) -> list[int]:
    if not isinstance(value, list) or len(value) != size:
        raise ValueError(f"{what}: {size} values expected")
    return [_byte(v, f"{what}[{i}]", 0, high) for i, v in enumerate(value)]


def set_team_fields(team: bytearray, fields: dict, where: str) -> None:
    for name, value in fields.items():
        what = f"{where} {name}"
        if name == "name":
            _put_text(team, 5, 17, value, what)
        elif name == "coach":
            _put_text(team, 0x24, 23, value, what)
        elif name == "division":
            team[0x19] = _byte(value, what)
        elif name in ("home_kit", "away_kit"):
            offset = 0x1A if name == "home_kit" else 0x1F
            team[offset:offset + 5] = bytes(_bytes(value, 5, what))
        elif name == "tactic":
            team[0x18] = _byte(value, what)
        elif name == "lineup":
            team[0x3C:0x4C] = bytes(_bytes(value, 16, what, 15))
        else:
            raise ValueError(f"{what}: not a field a pack may change")


def set_player_fields(team: bytearray, slot: int, fields: dict, where: str) -> None:
    base = PLAYERS + slot * PLAYER_SIZE
    record = bytearray(team[base:base + PLAYER_SIZE])
    skills = struct.unpack_from(">I", record, 0x1C)[0]
    for name, value in fields.items():
        what = f"{where} {name}"
        if name == "shirt":
            record[2] = _byte(value, what, 1, 16)
        elif name == "name":
            _put_text(record, 3, 23, value, what)
        elif name == "nationality":
            record[0] = _byte(value, what, 0, NATIONALITIES - 1)
        elif name == "position":
            if value not in POSITIONS:
                raise ValueError(f"{what}: {value!r} is not one of {' '.join(POSITIONS)}")
            record[0x1A] = (POSITIONS.index(value) << 5) | (record[0x1A] & 0x1F)
        elif name == "appearance":
            record[0x1A] = (_byte(value, what, 0, 2) << 3) | (record[0x1A] & 0xE7)
        elif name in ("skills", "specialties"):
            values = _bytes(value, 7, what, 7 if name == "skills" else 1)
            for index, item in enumerate(values):
                shift = 24 - 4 * index
                if name == "skills":
                    skills = (skills & ~(7 << shift)) | (item << shift)
                else:
                    skills = (skills & ~(8 << shift)) | (item << (shift + 3))
        elif name == "rating":
            if value is not None:
                record[0x20] = _byte(value, what, 0, 40)
        else:
            raise ValueError(f"{what}: not a field a pack may change")
    struct.pack_into(">I", record, 0x1C, skills & 0xFFFFFFFF)
    if record[0x1A] >> 5:
        record[0x20] = custom_set.rating_sum(skills)
    elif "rating" in fields and fields["rating"] is None:
        raise ValueError(f"{where} rating: a goalkeeper needs a rating")
    team[base:base + PLAYER_SIZE] = record


# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------
PLAYER_COLUMNS = (["group", "ordinal", "team", "slot", "shirt", "name", "nationality", "position",
                   "appearance"] + list(SKILLS) + [f"{s}_special" for s in SKILLS] + ["rating"])
TEAM_COLUMNS = ["group", "ordinal", "name", "coach", "division",
                "home_pattern", "home_shirt", "home_shirt2", "home_shorts", "home_socks",
                "away_pattern", "away_shirt", "away_shirt2", "away_shorts", "away_socks", "tactic"]
# Derived, read-only columns of teams.csv: the strength summary of TEAM
# SETTINGS (custom_set.team_strength); import ignores them like the team
# name of players.csv.
STRENGTH_COLUMNS = ["average_rating", "keeper_rating", "skills_eleven", "skills_squad",
                    "specials_eleven", "specials_squad"]
KIT_COLUMNS = ("pattern", "shirt", "shirt2", "shorts", "socks")
CUP_COLUMNS = ["cup", "place", "group", "ordinal", "team"]


def _csv_text(rows: list[list]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerows(rows)
    return buffer.getvalue()


def export_csv(groups: dict[int, bytes], labels: list[str], *, group_list: Iterable[int] = SUPPORTED_GROUPS,
               ) -> tuple[str, str]:
    """(players.csv, teams.csv) of the groups, sorted by group, ordinal, slot."""
    players, teams = [PLAYER_COLUMNS], [TEAM_COLUMNS + STRENGTH_COLUMNS]
    for group in group_list:
        for ordinal, team in enumerate(group_teams(groups[group])):
            fields = team_fields(team)
            strength = custom_set.team_strength(team)
            teams.append([group, ordinal, fields["name"], fields["coach"], fields["division"]]
                         + fields["home_kit"] + fields["away_kit"] + [fields["tactic"]]
                         + ["" if strength["average"] is None else custom_set.average_text(strength["average"]),
                            strength["keeper"], strength["skills_eleven"], strength["skills_squad"],
                            strength["specials_eleven"], strength["specials_squad"]])
            for slot in range(16):
                p = player_fields(team[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE])
                players.append([group, ordinal, fields["name"], slot, p["shirt"], p["name"],
                                labels[p["nationality"]], p["position"], p["appearance"]]
                               + p["skills"] + p["specialties"] + ["" if p["rating"] is None else p["rating"]])
    return _csv_text(players), _csv_text(teams)


def export_customs_csv(customs: bytes, labels: list[str]) -> tuple[str, str]:
    """(customs-players.csv, customs-teams.csv) of the custom set
    CUSTOMS.EDT, in the layouts of players.csv and teams.csv with group 72,
    the strength columns included."""
    return export_csv({CUSTOM_GROUP: customs}, labels, group_list=(CUSTOM_GROUP,))


def export_cups_csv(lists: dict[int, list[tuple[int, int]]], groups: dict[int, bytes]) -> str:
    """cups.csv: the participants of the three European club cups in place
    order; team is informative."""
    rows: list[list] = [CUP_COLUMNS]
    for code in CUP_CODES:
        for place, (group, ordinal) in enumerate(lists[code], start=1):
            rows.append([CUP_NAMES[code], place, group, ordinal, _text(group_record(groups, (group, ordinal))[5:0x16])])
    return _csv_text(rows)


class CsvError(ValueError):
    def __init__(self, file: str, row: int, column: str, message: str):
        super().__init__(f"{file} row {row} column {column}: {message}")


def _int_cell(file: str, row: int, column: str, text: str, low: int, high: int) -> int:
    try:
        value = int(text, 10)
    except ValueError:
        raise CsvError(file, row, column, f"{text!r} is not a number") from None
    if not low <= value <= high:
        raise CsvError(file, row, column, f"{value} is not {low}-{high}")
    return value


def _records(file: str, text: str, columns: list[str], keys: tuple[str, ...]):
    reader = csv.reader(io.StringIO(text))
    try:
        header = next(reader)
    except StopIteration:
        raise CsvError(file, 1, "-", "the file is empty") from None
    for column in header:
        if column not in columns:
            raise CsvError(file, 1, column, "unknown column")
    if len(set(header)) != len(header):
        raise CsvError(file, 1, "-", "a column is listed twice")
    for key in keys:
        if key not in header:
            raise CsvError(file, 1, key, "the key column is missing")
    for number, cells in enumerate(reader, start=2):
        if not cells:
            continue
        if len(cells) != len(header):
            raise CsvError(file, number, "-", f"{len(cells)} cells, the header has {len(header)}")
        yield number, dict(zip(header, cells))


def _team_at(groups: dict[int, bytearray], file: str, row: int, cells: dict) -> tuple[int, int, bytearray]:
    group = _int_cell(file, row, "group", cells["group"], 0, 255)
    if group not in groups:
        raise CsvError(file, row, "group", f"{group} is not a database group")
    count = struct.unpack_from(">H", groups[group], 0)[0]
    ordinal = _int_cell(file, row, "ordinal", cells["ordinal"], 0, count - 1)
    return group, ordinal, groups[group]


def import_csv(base: dict[int, bytes], originals: dict[int, bytes], labels: list[str],
               players_csv: str | None = None, teams_csv: str | None = None,
               players_file: str = "players.csv", teams_file: str = "teams.csv") -> dict[int, bytes]:
    """The groups after applying the CSV files to base (original groups or
    an existing set). Each file changes only the columns it carries; the
    result is checked per group as the editors check it."""
    groups = {g: bytearray(raw) for g, raw in base.items()}
    nationality = {label: code for code, label in enumerate(labels)}
    if teams_csv is not None:
        for row, cells in _records(teams_file, teams_csv, TEAM_COLUMNS + STRENGTH_COLUMNS, ("group", "ordinal")):
            group, ordinal, data = _team_at(groups, teams_file, row, cells)
            team = bytearray(data[2 + ordinal * TEAM_SIZE:2 + (ordinal + 1) * TEAM_SIZE])
            fields: dict = {}
            for column, text in cells.items():
                if column in ("group", "ordinal") or column in STRENGTH_COLUMNS:
                    continue
                if column in ("name", "coach"):
                    fields[column] = text
                elif column == "division":
                    fields["division"] = _int_cell(teams_file, row, column, text, 0, 255)
                elif column == "tactic":
                    fields["tactic"] = _int_cell(teams_file, row, column, text, 0, 17)
                else:
                    side, part = column.split("_", 1)
                    kit = fields.setdefault(f"{side}_kit", list(team[0x1A if side == "home" else 0x1F:][:5]))
                    high = 3 if part == "pattern" else 9
                    kit[KIT_COLUMNS.index(part)] = _int_cell(teams_file, row, column, text, 0, high)
            try:
                set_team_fields(team, fields, f"group {group} team {ordinal}")
            except ValueError as exc:
                raise CsvError(teams_file, row, "-", str(exc)) from None
            data[2 + ordinal * TEAM_SIZE:2 + (ordinal + 1) * TEAM_SIZE] = team
    if players_csv is not None:
        for row, cells in _records(players_file, players_csv, PLAYER_COLUMNS, ("group", "ordinal", "slot")):
            group, ordinal, data = _team_at(groups, players_file, row, cells)
            slot = _int_cell(players_file, row, "slot", cells["slot"], 0, 15)
            team = bytearray(data[2 + ordinal * TEAM_SIZE:2 + (ordinal + 1) * TEAM_SIZE])
            current = player_fields(team[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE])
            fields = {}
            for column, text in cells.items():
                if column in ("group", "ordinal", "slot", "team"):
                    continue
                if column == "name":
                    fields["name"] = text
                elif column == "shirt":
                    fields["shirt"] = _int_cell(players_file, row, column, text, 1, 16)
                elif column == "nationality":
                    if text not in nationality:
                        raise CsvError(players_file, row, column, f"{text!r} is not a nationality label")
                    fields["nationality"] = nationality[text]
                elif column == "position":
                    if text not in POSITIONS:
                        raise CsvError(players_file, row, column, f"{text!r} is not one of {' '.join(POSITIONS)}")
                    fields["position"] = text
                elif column == "appearance":
                    fields["appearance"] = _int_cell(players_file, row, column, text, 0, 2)
                elif column in SKILLS:
                    fields.setdefault("skills", list(current["skills"]))[SKILLS.index(column)] = \
                        _int_cell(players_file, row, column, text, 0, 7)
                elif column.endswith("_special"):
                    fields.setdefault("specialties", list(current["specialties"]))[
                        SKILLS.index(column[:-8])] = _int_cell(players_file, row, column, text, 0, 1)
                elif column == "rating":
                    fields["rating"] = None if text == "" else _int_cell(players_file, row, column, text, 0, 40)
            position = fields.get("position", current["position"])
            if "rating" in fields:
                if position != "G":
                    rating = fields.pop("rating")
                    if rating is not None:
                        raise CsvError(players_file, row, "rating",
                                       "an outfield rating is the sum of the skills; leave it empty")
                elif fields["rating"] is None:
                    raise CsvError(players_file, row, "rating", "a goalkeeper needs a rating")
            try:
                set_player_fields(team, slot, fields, f"group {group} team {ordinal} slot {slot}")
            except ValueError as exc:
                raise CsvError(players_file, row, "-", str(exc)) from None
            data[2 + ordinal * TEAM_SIZE:2 + (ordinal + 1) * TEAM_SIZE] = team
    result = {g: bytes(raw) for g, raw in groups.items()}
    pool = original_pool(originals)
    for group, raw in result.items():
        if raw != base[group]:
            problems = validate_group(group, raw, originals[group], pool, base[group])
            if problems:
                raise ValueError(f"{players_file if players_csv is not None else teams_file}: "
                                 + "; ".join(problems[:5]))
    return result


def import_cups_csv(text: str, groups: dict[int, bytes], file: str = "cups.csv") -> dict[int, list[tuple[int, int]]]:
    """The participant lists a cups.csv names: every cup it mentions with
    all its places 1..n; team is informative. The rules of check_cup_lists
    apply to the result together with the other cups' lists."""
    places: dict[int, dict[int, tuple[int, int]]] = {}
    codes = {name: code for code, name in CUP_NAMES.items()}
    for row, cells in _records(file, text, CUP_COLUMNS, ("cup", "place", "group", "ordinal")):
        if cells["cup"] not in codes:
            raise CsvError(file, row, "cup", f"{cells['cup']!r} is not one of {' '.join(codes)}")
        code = codes[cells["cup"]]
        place = _int_cell(file, row, "place", cells["place"], 1, CUP_SIZES[code])
        group = _int_cell(file, row, "group", cells["group"], 0, 255)
        if group not in CLUB_GROUPS:
            raise CsvError(file, row, "group", f"{group} is not a club group")
        count = struct.unpack_from(">H", groups[group], 0)[0]
        ordinal = _int_cell(file, row, "ordinal", cells["ordinal"], 0, count - 1)
        if place in places.setdefault(code, {}):
            raise CsvError(file, row, "place", f"{CUP_NAMES[code]} place {place} is listed twice")
        places[code][place] = (group, ordinal)
    lists = {}
    for code, chosen in places.items():
        if len(chosen) != CUP_SIZES[code]:
            raise CupError(f"{file}: {CUP_NAMES[code]} lists {len(chosen)} places, the cup takes {CUP_SIZES[code]}")
        lists[code] = [chosen[place] for place in range(1, CUP_SIZES[code] + 1)]
    return lists


# ---------------------------------------------------------------------------
# Season packs
# ---------------------------------------------------------------------------
PACK_FORMAT = "SWOSPACK"
PACK_VERSION = 2                        # with the cups section
PACK_VERSIONS = (1, 2)


def diff(originals: dict[int, bytes], edited: dict[int, bytes], label: str = "", *,
         lists: dict[int, list[tuple[int, int]]] | None = None, base: Base | None = None) -> dict:
    """A pack of the fields that differ between the original and the edited
    groups (only fields the editors may change), sorted by group, ordinal
    and slot; with base, the participant lists (of lists) that differ from
    the 96/97 ones as the cups section."""
    check_label(label)
    teams = []
    for group in SUPPORTED_GROUPS:
        if edited.get(group, originals[group]) == originals[group]:
            continue
        for ordinal, (old, new) in enumerate(zip(group_teams(originals[group]), group_teams(edited[group]))):
            if old == new:
                continue
            before, after = team_fields(old), team_fields(new)
            changed = {name: after[name] for name in TEAM_FIELDS if before[name] != after[name]}
            players = []
            for slot in range(16):
                a = player_fields(old[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE])
                b = player_fields(new[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE])
                fields = {name: b[name] for name in PLAYER_FIELDS if a[name] != b[name]}
                if "rating" in fields and b["rating"] is None:
                    del fields["rating"]
                if fields:
                    players.append({"slot": slot, "fields": fields})
            if changed or players:
                item = {"group": group, "ordinal": ordinal}
                if changed:
                    item["fields"] = changed
                if players:
                    item["players"] = players
                teams.append(item)
    pack = {"format": PACK_FORMAT, "version": PACK_VERSION, "label": label,
            "base": base_identity(originals), "teams": teams}
    if base is not None and lists:
        cups = [{"cup": CUP_NAMES[code], "teams": [list(key) for key in lists[code]]}
                for code in CUP_CODES if code in lists and list(lists[code]) != list(base.lists[code])]
        if cups:
            pack["cups"] = cups
    return pack


def apply(pack: dict, originals: dict[int, bytes],
          current: dict[int, bytes] | None = None) -> tuple[dict[int, bytes], str]:
    """(groups, label) of a pack applied to the user's own original groups;
    refused for another base, format or version; checked as an import (the
    values a kept field may have include those of current, the groups of the
    install's set)."""
    if not isinstance(pack, dict) or pack.get("format") != PACK_FORMAT or pack.get("version") not in PACK_VERSIONS:
        raise ValueError(f"not a {PACK_FORMAT} version 1 or 2 pack")
    if pack.get("base") != base_identity(originals):
        raise ValueError("the pack was made for other original groups (base identity differs)")
    label = pack.get("label", "")
    check_label(label)
    groups = {g: bytearray(raw) for g, raw in originals.items()}
    for item in pack.get("teams", []):
        group, ordinal = item.get("group"), item.get("ordinal")
        if group not in SUPPORTED_GROUPS:
            raise ValueError(f"group {group!r} is not a database group")
        count = struct.unpack_from(">H", groups[group], 0)[0]
        if type(ordinal) is not int or not 0 <= ordinal < count:
            raise ValueError(f"group {group}: no team {ordinal!r}")
        start = 2 + ordinal * TEAM_SIZE
        team = bytearray(groups[group][start:start + TEAM_SIZE])
        where = f"group {group} team {ordinal}"
        set_team_fields(team, item.get("fields", {}), where)
        for player in item.get("players", []):
            slot = player.get("slot")
            if type(slot) is not int or not 0 <= slot < 16:
                raise ValueError(f"{where}: no player slot {slot!r}")
            set_player_fields(team, slot, player.get("fields", {}), f"{where} slot {slot}")
        groups[group][start:start + TEAM_SIZE] = team
    result = {g: bytes(raw) for g, raw in groups.items()}
    pool = original_pool(originals)
    for group, raw in result.items():
        if raw != originals[group]:
            problems = validate_group(group, raw, originals[group], pool, (current or {}).get(group))
            if problems:
                raise ValueError("; ".join(problems[:5]))
    return result, label


def pack_cups(pack: dict, groups: dict[int, bytes]) -> dict[int, list[tuple[int, int]]]:
    """The participant lists of a pack's cups section (version 2)."""
    codes = {name: code for code, name in CUP_NAMES.items()}
    lists = {}
    for item in pack.get("cups", []):
        name = item.get("cup") if isinstance(item, dict) else None
        if name not in codes or codes[name] in lists:
            raise ValueError(f"cups: {name!r} is not a cup or is listed twice")
        keys = item.get("teams")
        if not isinstance(keys, list) or not all(isinstance(k, list) and len(k) == 2 and all(type(v) is int for v in k)
                                                 for k in keys):
            raise ValueError(f"cups: {name}: teams must be [group, ordinal] pairs")
        lists[codes[name]] = [tuple(k) for k in keys]
    if lists and pack.get("version") == 1:
        raise ValueError("a version 1 pack has no cups section")
    full = dict(lists)
    for code, keys in full.items():
        if len(keys) != CUP_SIZES[code]:
            raise CupError(f"{CUP_NAMES[code]}: {len(keys)} clubs, the cup takes {CUP_SIZES[code]}")
        for group, ordinal in keys:
            if group not in CLUB_GROUPS or not 0 <= ordinal < struct.unpack_from(">H", groups[group], 0)[0]:
                raise CupError(f"{CUP_NAMES[code]}: no club {group}/{ordinal}")
    return lists


def pack_text(pack: dict) -> str:
    """Deterministic JSON of a pack (fixed key order, sorted entries)."""
    return json.dumps(pack, indent=1, ensure_ascii=True) + "\n"


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------
def _originals(path: Path) -> dict[int, bytes]:
    return original_groups_from_disk2(path.read_bytes())


def _base(args) -> Base:
    return base_from_disks(args.disk1.read_bytes(), args.disk2.read_bytes())


def read_sources(paths: list[Path], base: Base, labels: list[str], groups: dict[int, bytes],
                 lists: dict[int, list[tuple[int, int]]]) -> tuple[dict[int, bytes], dict, str | None]:
    """The groups and participant lists after applying the sources in
    order to groups and lists: a season pack (its label is returned),
    players.csv, teams.csv and cups.csv, or group JSON files of export
    (TEAM.ggg.json)."""
    label = None
    players = teams = cups = None
    for path in paths:
        name = path.name.lower()
        if name.endswith("teams.csv"):
            teams = path.read_text()
        elif name.endswith("players.csv"):
            players = path.read_text()
        elif name.endswith("cups.csv"):
            cups = path
        elif name.endswith(".json"):
            document = json.loads(path.read_text())
            if isinstance(document, dict) and document.get("format") == PACK_FORMAT:
                groups, label = apply(document, base.groups, groups)
                lists = {**lists, **pack_cups(document, groups)}
            else:
                raw = team_data.encode(document)
                group = raw[2] if len(raw) > 2 else -1
                if group not in SUPPORTED_GROUPS or any(raw[2 + i * TEAM_SIZE] != group
                                                        for i in range(len(raw) // TEAM_SIZE)):
                    raise ValueError(f"{path.name}: not a database group")
                groups = {**groups, group: raw}
        else:
            raise ValueError(f"{path.name}: expected a pack, players.csv, teams.csv, cups.csv or TEAM.ggg.json")
    if players is not None or teams is not None:
        groups = import_csv(groups, base.groups, labels, players, teams)
    if cups is not None:
        lists = {**lists, **import_cups_csv(cups.read_text(), groups, cups.name)}
    return groups, lists, label


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("manifest", help="check and show DBASE.CFG or DBASE.BAK")
    p.add_argument("source", type=Path)
    p = sub.add_parser("link", help="check and show a link file")
    p.add_argument("source", type=Path)
    p = sub.add_parser("check", help="check the edited set of a save directory")
    p.add_argument("data", type=Path)
    p.add_argument("--disk1", type=Path)
    p.add_argument("--disk2", type=Path)
    p = sub.add_parser("export", help="groups as JSON plus players.csv, teams.csv and cups.csv")
    p.add_argument("output", type=Path)
    p.add_argument("--disk1", type=Path, required=True)
    p.add_argument("--disk2", type=Path, required=True)
    p.add_argument("--data", type=Path, help="save directory whose edited set replaces the originals")
    for command, text in (("import", "CSV or JSON files into a new generation of the set"),
                          ("write", "a complete set into a save directory (an install's data/)")):
        p = sub.add_parser(command, help=text)
        p.add_argument("files", type=Path, nargs="+")
        p.add_argument("--disk1", type=Path, required=True)
        p.add_argument("--disk2", type=Path, required=True)
        p.add_argument("--data", type=Path, required=True)
        p.add_argument("--label")
        if command == "write":
            p.add_argument("--switch", choices=("on", "off"), default="on")
    p = sub.add_parser("diff", help="a season pack of the set in a save directory")
    p.add_argument("output", type=Path)
    p.add_argument("--disk1", type=Path, required=True)
    p.add_argument("--disk2", type=Path, required=True)
    p.add_argument("--data", type=Path, required=True)
    p.add_argument("--label")
    p = sub.add_parser("apply", help="a season pack into a new generation of the set")
    p.add_argument("pack", type=Path)
    p.add_argument("--disk1", type=Path, required=True)
    p.add_argument("--disk2", type=Path, required=True)
    p.add_argument("--data", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "manifest":
            raw = args.source.read_bytes()
            print(json.dumps(manifest_document(raw), indent=2))
        elif args.command == "link":
            print(json.dumps(decode_link(args.source.read_bytes()), indent=2))
        elif args.command == "check":
            manifest, raw = read_set(args.data)
            if manifest is None:
                print("no edited set (DBASE.CFG) in", args.data)
                return
            originals = _originals(args.disk2) if args.disk2 else None
            for entry in manifest.entries:
                path = stored(args.data, entry.name)
                data = path.read_bytes() if path.exists() else None
                code, name = check_group_file(entry, data)
                if code != MC_OK:
                    parser.exit(1, f"DATABASE NOT FOUND: {problem_text(code, name)}\n")
                if originals is not None and entry.group in SUPPORTED_GROUPS:
                    problems = validate_group(entry.group, data, originals[entry.group], original_pool(originals),
                                              data)   # the set itself: the editors keep its values
                    if problems:
                        parser.exit(1, "\n".join(problems) + "\n")
            if originals is not None:
                groups, copies = set_contents(args.data, originals)
                problems = check_copies(copies, groups)
                if args.disk1 is not None:
                    try:
                        check_cup_lists(cup_lists_of(copies, _base(args)), groups)
                    except CupError as exc:
                        problems.append(str(exc))
                if problems:
                    parser.exit(1, "\n".join(problems) + "\n")
            print(f"the editor accepts this set: label {manifest.label!r}, generation "
                  f"{manifest.generation}, {len(manifest.entries)} files, CRC-32 {manifest_crc(raw):08X}, "
                  f"USE EDITED DATABASE {'on' if read_switch(args.data) else 'off'}")
        elif args.command == "export":
            base = _base(args)
            labels = nationality_labels_from_disk1(args.disk1.read_bytes())
            groups, copies = set_contents(args.data, base.groups) if args.data else (base.groups, {})
            args.output.mkdir(parents=True, exist_ok=True)
            for group in SUPPORTED_GROUPS:
                document = team_data.decode(groups[group])
                (args.output / f"TEAM.{group:03d}.json").write_text(json.dumps(document, indent=1) + "\n")
            players, teams = export_csv(groups, labels)
            (args.output / "players.csv").write_text(players)
            (args.output / "teams.csv").write_text(teams)
            (args.output / "cups.csv").write_text(export_cups_csv(cup_lists_of(copies, base), groups))
        elif args.command in ("import", "write"):
            base = _base(args)
            labels = nationality_labels_from_disk1(args.disk1.read_bytes())
            current, _ = read_set(args.data)
            groups, copies = set_contents(args.data, base.groups)
            groups, lists, pack_label = read_sources(args.files, base, labels, groups, cup_lists_of(copies, base))
            label = args.label if args.label is not None else (
                pack_label if pack_label is not None else (current.label if current else ""))
            if args.command == "write":
                manifest = write_install(args.data, base, groups, label, lists=lists, switch=args.switch == "on")
                state = "on" if read_switch(args.data) else "off"
                written = read_set(args.data)[1]
                print(("unchanged" if manifest is None else f"wrote generation {manifest.generation}")
                      + (f", CRC-32 {manifest_crc(written):08X}" if written else "") + f", USE EDITED DATABASE {state}")
            else:
                manifest = write_set(args.data, base.groups, groups, label, base=base, lists=lists)
                print("unchanged" if manifest is None else f"wrote generation {manifest.generation}")
        elif args.command == "diff":
            base = _base(args)
            current, _ = read_set(args.data)
            label = args.label if args.label is not None else (current.label if current else "")
            groups, copies = set_contents(args.data, base.groups)
            args.output.write_text(pack_text(diff(base.groups, groups, label,
                                                   lists=cup_lists_of(copies, base), base=base)))
        elif args.command == "apply":
            base = _base(args)
            pack = json.loads(args.pack.read_text())
            groups, label = apply(pack, base.groups)
            manifest = write_set(args.data, base.groups, groups, label, base=base, lists=pack_cups(pack, groups))
            print("unchanged" if manifest is None else f"wrote generation {manifest.generation}")
    except (ValueError, KeyError, OSError, struct.error) as exc:
        parser.exit(1, f"database_set: {exc}\n")


if __name__ == "__main__":
    main()
