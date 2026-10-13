#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Tournament definitions (.DEF) on the host.

A definition is a DIY league, cup or tournament as the game's own setup pages
describe it: every native rule, the stage chain, the participants by team key
and source, the database identity it was made with and optionally the user
tactic slots USER A-F. The in-game tournament editor (src/editor/editors/
definition.s and friends) writes and reads the same files; this module is the
host reference of their layout, of the checks LOAD DEFINITION makes and of the
lines it shows, and its results match those of the in-game editor.

  python3 tools/definition_data.py decode SWOS/data/LEAGUE.DEF league.json
  python3 tools/definition_data.py encode league.json SWOS/data/LEAGUE.DEF
  python3 tools/definition_data.py check SWOS/data/LEAGUE.DEF

Layout (big-endian, as src/editor/include/definition.i defines it): a 16-byte
header SWOSDEF1, version 1, body length, CRC-32/ISO-HDLC of the body, then the
body. A valid body has no byte outside the fields listed below that is not
zero, so decode followed by encode gives the file back byte for byte.
"""
from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path
from typing import Any

import tactic_data

SCHEMA = "swos-amiga-definition-v1"
MAGIC = b"SWOSDEF1"
VERSION = 1
HEADER_SIZE = 16
TACTIC_SIZE = tactic_data.TACTIC_SIZE
USER_SLOTS = 6

# Body
B_DB_KIND = 0x00            # word: 0 original database, 1 edited set
B_DB_GENERATION = 0x02      # word: manifest generation (edited set)
B_DB_CRC = 0x04             # long: manifest CRC-32 (edited set)
B_DB_LABEL = 0x08           # 16 bytes: set label, NUL padded (edited set)
B_CUSTOM_CRC = 0x18         # long: CRC-32 of CUSTOMS.EDT as last read or written
B_DB_FLAGS = 0x1C           # word: bit 0 = the custom set CRC is known
B_DB_RESERVED = 0x1E
B_FAMILY = 0x20             # word: 0 league, 1 cup, 2 tournament
B_NAME = 0x22               # 26 bytes: 0-24 characters, NUL padded
B_PITCH_MODE = 0x3C         # word: 0 pitch type, 1 season
B_PITCH_TYPE = 0x3E         # signed word: -1 random, 0-6
B_START = 0x40              # byte: start of the season, eighth months
B_END = 0x41                # byte: end of the season
B_TEAMS = 0x42              # word: teams of the competition
B_SUBS = 0x44               # word: substitutes that may be used
B_BENCH = 0x46              # word: substitutes on the bench
B_RULES = 0x48              # 128 bytes, by family
B_RULES_END = 0xC8
B_TEAM_COUNT = 0xC8         # word: 0, or the teams of the competition
B_TACTIC_MASK = 0xCA        # word: bit n = USER A+n present
B_LIST = 0xCC               # participants, then the present tactic records
BODY_FIXED = B_LIST
NAME_FIELD = 26
NAME_MAX = 24
LABEL_SIZE = 16
# League
B_L_REPEAT = 0x48
B_L_POINTS = 0x4A
B_L_END = 0x4C
# Cup
B_C_ROUNDS = 0x48
B_C_AWAY = 0x4A
B_C_LEGS = 0x4C             # six words, one per round
B_C_EXTRA = 0x58
B_C_PENALTIES = 0x64
B_C_END = 0x70
# Tournament
B_T_AWAY = 0x48
B_T_STAGES = 0x4A
B_T_STAGE = 0x4C            # six stage records
STAGE_SIZE = 20
B_T_END = B_T_STAGE + 6 * STAGE_SIZE
STAGE_FIELDS = ("teams", "through", "groups", "group_teams", "seeded", "repetitions",
                "points", "legs", "extra_time", "penalties")
# Participant
PARTICIPANT_SIZE = 24
P_GROUP, P_ORDINAL, P_SOURCE, P_CONTROL, P_NAME = 0, 1, 2, 3, 4
TEAM_NAME_SIZE = 17
MAX_TEAMS = 64
BODY_MAX = BODY_FIXED + MAX_TEAMS * PARTICIPANT_SIZE + USER_SLOTS * TACTIC_SIZE
FILE_MIN = HEADER_SIZE + BODY_FIXED
FILE_MAX = HEADER_SIZE + BODY_MAX

FAMILIES = ("league", "cup", "tournament")
SOURCES = ("database", "custom set")
CONTROLS = {1: "computer", 2: "player-coach", 3: "coach"}
CUSTOM_GROUP = 72           # keys of custom teams, original or edited
# The TEAM.ggg files on disk 2 [cr HF] (the build checks the editor's map
# against the disk): a database participant must come from one of them.
TEAM_GROUPS = frozenset(list(range(0, 9)) + list(range(10, 47)) + [48, 49, 50, 51, 55, 60, 62, 64,
                         65, 66, 67, 69, 71, 72, 73] + list(range(75, 86)))
# Characters the native text entry accepts (team.i NAME_GLYPHS).
NAME_GLYPHS = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -/.")
LEAGUE_TEAMS = range(2, 25)
LEAGUE_REPEAT = range(1, 11)
CUP_ROUNDS = range(1, 7)
TOURNAMENT_TEAMS = range(2, 65)
STAGE_REPEAT = range(1, 5)
NATIVE_REFUSED = (58, 62)   # choose_tournament_stage_shape $1B6C02
MAX_STAGES = 6
MAX_GROUPS = 8
MAX_GROUP_TEAMS = 24
STAGE_DATES_MAX = 90        # date bytes of a stage slot
STAGE5_KNOCKOUT_MAX = 48
SEASON_UNITS = 96           # eighth months of a year

# Problems (the editor's DC_* in src/editor/include/definition.i)
(DC_OK, DC_SIZE, DC_MAGIC, DC_VERSION, DC_LENGTH, DC_CRC, DC_BODY, DC_IDENTITY, DC_FAMILY,
 DC_NAME, DC_PITCH, DC_MONTHS, DC_BENCH, DC_SUBS, DC_TEAMS, DC_REPEAT, DC_POINTS, DC_ROUNDS,
 DC_CUP_TEAMS, DC_AWAY, DC_LEGS, DC_EXTRA, DC_PENALTIES, DC_STAGES, DC_CHAIN, DC_NATIVE_TEAMS,
 DC_THROUGH, DC_FINAL_EARLY, DC_FINAL, DC_KNOCKOUT, DC_GROUPS, DC_SEEDED, DC_STAGE_REPEAT,
 DC_STAGE_POINTS, DC_DATES, DC_UNUSED_STAGE, DC_RESERVED, DC_TEAM_COUNT, DC_TEAM_ENTRY,
 DC_TEAM_GROUP, DC_TEAM_TWICE, DC_TACTIC_MASK, DC_TACTIC) = range(43)
ROUND, STAGE = 0, 1         # kind of DC_LEGS/DC_EXTRA/DC_PENALTIES


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def word(body: bytes, offset: int) -> int:
    return struct.unpack_from(">H", body, offset)[0]


def signed_word(body: bytes, offset: int) -> int:
    return struct.unpack_from(">h", body, offset)[0]


def group_dates(group_teams: int, repetitions: int) -> int:
    """Match dates of a group stage: the native count of $1A9C6A."""
    n = group_teams
    return (n * (n - 1) // 2) // (n // 2) * repetitions


def stage_record(body: bytes, stage: int) -> list[int]:
    return list(struct.unpack_from(">10H", body, B_T_STAGE + stage * STAGE_SIZE))


def body_length(teams: int, mask: int) -> int:
    return BODY_FIXED + teams * PARTICIPANT_SIZE + bin(mask & 0x3F).count("1") * TACTIC_SIZE


def _zero(body: bytes, start: int, end: int) -> bool:
    return not any(body[start:end])


def _text_field(raw: bytes, limit: int, glyphs: bool) -> bool:
    """NUL within the first limit+1 bytes, zero after it, known glyphs."""
    end = raw.find(b"\0")
    if end < 0 or end > limit or any(raw[end:]):
        return False
    return not glyphs or all(c in NAME_GLYPHS for c in raw[:end])


def check_body(body: bytes) -> tuple[int, tuple[int, ...]]:
    """(DC_*, details) of the first problem LOAD DEFINITION reports for a
    body, in the editor's order, or (DC_OK, ()). The same checks without the
    participants and tactics run on the setup pages (RULES, SAVE DEFINITION,
    CHOOSE TEAMS)."""
    if len(body) < BODY_FIXED:
        return DC_BODY, ()
    teams_listed, mask = word(body, B_TEAM_COUNT), word(body, B_TACTIC_MASK)
    if len(body) != body_length(teams_listed, mask):
        return DC_BODY, ()
    # Database identity
    kind = word(body, B_DB_KIND)
    flags = word(body, B_DB_FLAGS)
    if kind > 1 or (kind == 0 and not _zero(body, B_DB_GENERATION, B_CUSTOM_CRC)) \
            or not _text_field(body[B_DB_LABEL:B_CUSTOM_CRC] + b"\0", LABEL_SIZE, True) \
            or flags & ~1 or (not flags and not _zero(body, B_CUSTOM_CRC, B_DB_FLAGS)) \
            or word(body, B_DB_RESERVED):
        return DC_IDENTITY, ()
    family = word(body, B_FAMILY)
    if family > 2:
        return DC_FAMILY, (family,)
    if not _text_field(body[B_NAME:B_NAME + NAME_FIELD], NAME_MAX, True):
        return DC_NAME, ()
    pitch_mode, pitch_type = word(body, B_PITCH_MODE), signed_word(body, B_PITCH_TYPE)
    if pitch_mode > 1 or not -1 <= pitch_type <= 6:
        return DC_PITCH, ()
    start, end = body[B_START], body[B_END]
    if start % 8 or end % 8 or start >= SEASON_UNITS or end >= SEASON_UNITS:
        return DC_MONTHS, ()
    teams, subs, bench = word(body, B_TEAMS), word(body, B_SUBS), word(body, B_BENCH)
    if bench > 5:
        return DC_BENCH, (bench,)
    if (bench == 0 and subs != 0) or (bench and not 1 <= subs <= bench):
        return DC_SUBS, (subs, bench)
    problem = (check_league, check_cup, check_tournament)[family](body, teams)
    if problem[0] != DC_OK:
        return problem
    # Participants
    if teams_listed not in (0, teams):
        return DC_TEAM_COUNT, (teams_listed, teams)
    keys = []
    for index in range(teams_listed):
        entry = body[B_LIST + index * PARTICIPANT_SIZE:B_LIST + (index + 1) * PARTICIPANT_SIZE]
        if entry[P_SOURCE] > 1 or entry[P_CONTROL] not in CONTROLS \
                or not _text_field(entry[P_NAME:P_NAME + TEAM_NAME_SIZE], TEAM_NAME_SIZE - 1, False) \
                or any(entry[P_NAME + TEAM_NAME_SIZE:]):
            return DC_TEAM_ENTRY, (index + 1,)
        group = entry[P_GROUP]
        if (entry[P_SOURCE] == 0 and group not in TEAM_GROUPS) or \
                (entry[P_SOURCE] == 1 and group != CUSTOM_GROUP):
            return DC_TEAM_GROUP, (index + 1, group)
        key = entry[P_GROUP] << 8 | entry[P_ORDINAL]
        if key in keys:
            return DC_TEAM_TWICE, (index + 1,)
        keys.append(key)
    # Tactics
    if mask & ~0x3F:
        return DC_TACTIC_MASK, ()
    offset = B_LIST + teams_listed * PARTICIPANT_SIZE
    for slot in range(USER_SLOTS):
        if mask & (1 << slot):
            code, _ = tactic_data.check_record(body[offset:offset + TACTIC_SIZE])
            if code != tactic_data.TC_OK:
                return DC_TACTIC, (slot,)
            offset += TACTIC_SIZE
    return DC_OK, ()


def check_league(body: bytes, teams: int) -> tuple[int, tuple[int, ...]]:
    if teams not in LEAGUE_TEAMS:
        return DC_TEAMS, (0, teams)
    repeat, points = word(body, B_L_REPEAT), word(body, B_L_POINTS)
    if repeat not in LEAGUE_REPEAT:
        return DC_REPEAT, (repeat,)
    if points not in (2, 3):
        return DC_POINTS, (points,)
    if not _zero(body, B_L_END, B_RULES_END):
        return DC_RESERVED, ()
    return DC_OK, ()


def check_cup(body: bytes, teams: int) -> tuple[int, tuple[int, ...]]:
    rounds = word(body, B_C_ROUNDS)
    if rounds not in CUP_ROUNDS:
        return DC_ROUNDS, (rounds,)
    if teams != 1 << rounds:
        return DC_CUP_TEAMS, (rounds, teams)
    if word(body, B_C_AWAY) > 2:
        return DC_AWAY, ()
    for index in range(6):
        if word(body, B_C_LEGS + 2 * index) not in (1, 2):
            return DC_LEGS, (ROUND, index + 1)
        if word(body, B_C_EXTRA + 2 * index) > 2:
            return DC_EXTRA, (ROUND, index + 1)
        if word(body, B_C_PENALTIES + 2 * index) > 2:
            return DC_PENALTIES, (ROUND, index + 1)
    if not _zero(body, B_C_END, B_RULES_END):
        return DC_RESERVED, ()
    return DC_OK, ()


def knockout_valid(stage: int, teams: int, through: int, group_teams: int) -> bool:
    """A knockout as choose/cycle_tournament_stage_shape allow it (stage 1-6)."""
    return (teams % 2 == 0 and teams == 2 * through and group_teams == teams
            and (stage != 6 or teams == 2) and (stage != 5 or teams <= STAGE5_KNOCKOUT_MAX))


def groups_valid(stage: int, teams: int, through: int, groups: int, group_teams: int) -> bool:
    """A group layout as the native shape helpers allow it."""
    return (groups <= MAX_GROUPS and groups <= through and groups < teams and teams % groups == 0
            and group_teams == teams // groups and group_teams <= MAX_GROUP_TEAMS
            and (stage != 6 or groups == 1))


def check_tournament(body: bytes, teams: int) -> tuple[int, tuple[int, ...]]:
    if teams not in TOURNAMENT_TEAMS:
        return DC_TEAMS, (2, teams)
    if word(body, B_T_AWAY) > 2:
        return DC_AWAY, ()
    stages = word(body, B_T_STAGES)
    if not 1 <= stages <= MAX_STAGES:
        return DC_STAGES, (stages,)
    expected = teams
    for index in range(stages):
        stage = index + 1
        (entering, through, groups, group_teams, seeded, repeat, points, legs, extra,
         penalties) = stage_record(body, index)
        if entering != expected:
            return DC_CHAIN, (stage, entering, expected)
        if entering in NATIVE_REFUSED:
            return DC_NATIVE_TEAMS, (stage, entering)
        if not 1 <= through < entering:
            return DC_THROUGH, (stage, through, entering)
        if stage < stages and through == 1:
            return DC_FINAL_EARLY, (stage,)
        if stage == stages and through != 1:
            return DC_FINAL, (through,)
        if groups == 0:
            if not knockout_valid(stage, entering, through, group_teams):
                return DC_KNOCKOUT, (stage, entering)
        elif not groups_valid(stage, entering, through, groups, group_teams):
            return DC_GROUPS, (stage, groups, group_teams)
        if seeded > 1:
            return DC_SEEDED, (stage,)
        if repeat not in STAGE_REPEAT:
            return DC_STAGE_REPEAT, (stage, repeat)
        if points not in (2, 3):
            return DC_STAGE_POINTS, (stage, points)
        if legs not in (1, 2):
            return DC_LEGS, (STAGE, stage)
        if extra > 2:
            return DC_EXTRA, (STAGE, stage)
        if penalties > 2:
            return DC_PENALTIES, (STAGE, stage)
        if groups:
            dates = group_dates(group_teams, repeat)
            if dates > STAGE_DATES_MAX:
                return DC_DATES, (stage, dates)
        expected = through
    for index in range(stages, MAX_STAGES):
        if any(stage_record(body, index)):
            return DC_UNUSED_STAGE, (index + 1,)
    if not _zero(body, B_T_END, B_RULES_END):
        return DC_RESERVED, ()
    return DC_OK, ()


def check_file(raw: bytes) -> tuple[int, tuple[int, ...]]:
    """(DC_*, details) of the first problem LOAD DEFINITION reports for a
    file, or (DC_OK, ())."""
    if not FILE_MIN <= len(raw) <= FILE_MAX:
        return DC_SIZE, ()
    if raw[:8] != MAGIC:
        return DC_MAGIC, ()
    version, length, crc = struct.unpack_from(">HHI", raw, 8)
    if version != VERSION:
        return DC_VERSION, (version,)
    if length != len(raw) - HEADER_SIZE:
        return DC_LENGTH, ()
    body = raw[HEADER_SIZE:]
    if crc32(body) != crc:
        return DC_CRC, ()
    return check_body(body)


def _ordinal_kind(kind: int) -> str:
    return "ROUND" if kind == ROUND else "STAGE"


def problem_text(code: int, details: tuple[int, ...]) -> str:
    """The line the editor shows for a problem (at most 50 characters)."""
    d = details
    texts = {
        DC_SIZE: lambda: "THE FILE HAS THE WRONG SIZE FOR A DEFINITION.",
        DC_MAGIC: lambda: "THE FILE IS NOT A TOURNAMENT DEFINITION.",
        DC_VERSION: lambda: f"THE DEFINITION FORMAT VERSION {d[0]} IS NOT KNOWN.",
        DC_LENGTH: lambda: "THE LENGTH IN THE HEADER DOES NOT MATCH THE FILE.",
        DC_CRC: lambda: "THE CRC-32 DOES NOT MATCH THE CONTENT.",
        DC_BODY: lambda: "THE TEAM AND TACTIC COUNTS DO NOT FIT THE LENGTH.",
        DC_IDENTITY: lambda: "THE DATABASE IDENTITY IS NOT VALID.",
        DC_FAMILY: lambda: f"THE COMPETITION TYPE {d[0]} IS NOT KNOWN.",
        DC_NAME: lambda: "THE COMPETITION NAME IS NOT VALID.",
        DC_PITCH: lambda: "THE PITCH SETTING IS NOT ONE THE GAME OFFERS.",
        DC_MONTHS: lambda: "THE SEASON MONTHS ARE NOT VALID.",
        DC_BENCH: lambda: f"THE BENCH HOLDS 0-5 PLAYERS, NOT {d[0]}.",
        DC_SUBS: lambda: ("WITHOUT A BENCH NO SUBSTITUTE CAN BE USED." if d[1] == 0 else
                          f"USE 1-{d[1]} OF THE {d[1]} SUBSTITUTES, NOT {d[0]}."),
        DC_TEAMS: lambda: (f"A LEAGUE HAS 2-24 TEAMS, NOT {d[1]}." if d[0] == 0 else
                           f"A TOURNAMENT HAS 2-64 TEAMS, NOT {d[1]}."),
        DC_REPEAT: lambda: f"TEAMS MEET 1-10 TIMES, NOT {d[0]}.",
        DC_POINTS: lambda: f"A WIN GIVES 2 OR 3 POINTS, NOT {d[0]}.",
        DC_ROUNDS: lambda: f"A CUP HAS 1-6 ROUNDS, NOT {d[0]}.",
        DC_CUP_TEAMS: lambda: f"A CUP OF {d[0]} ROUNDS HAS {1 << d[0]} TEAMS, NOT {d[1]}.",
        DC_AWAY: lambda: "THE AWAY GOALS RULE IS NOT ONE THE GAME OFFERS.",
        DC_LEGS: lambda: f"{_ordinal_kind(d[0])} {d[1]} IS NOT PLAYED OVER 1 OR 2 LEGS.",
        DC_EXTRA: lambda: f"{_ordinal_kind(d[0])} {d[1]} HAS AN UNKNOWN EXTRA TIME RULE.",
        DC_PENALTIES: lambda: f"{_ordinal_kind(d[0])} {d[1]} HAS AN UNKNOWN PENALTY RULE.",
        DC_STAGES: lambda: f"A TOURNAMENT HAS 1-6 STAGES, NOT {d[0]}.",
        DC_CHAIN: lambda: f"STAGE {d[0]} STARTS WITH {d[1]} TEAMS, NOT {d[2]}.",
        DC_NATIVE_TEAMS: lambda: f"THE GAME CANNOT START STAGE {d[0]} WITH {d[1]} TEAMS.",
        DC_THROUGH: lambda: f"STAGE {d[0]} SENDS {d[1]} OF ITS {d[2]} TEAMS ON.",
        DC_FINAL_EARLY: lambda: f"STAGE {d[0]} ALREADY LEAVES THE WINNER.",
        DC_FINAL: lambda: f"THE LAST STAGE SENDS {d[0]} ON, NOT ONE WINNER.",
        DC_KNOCKOUT: lambda: f"STAGE {d[0]} CANNOT BE A KNOCKOUT OF {d[1]} TEAMS.",
        DC_GROUPS: lambda: f"STAGE {d[0]} CANNOT HAVE {d[1]} GROUPS OF {d[2]} TEAMS.",
        DC_SEEDED: lambda: f"STAGE {d[0]} HAS AN UNKNOWN SEEDING VALUE.",
        DC_STAGE_REPEAT: lambda: f"IN STAGE {d[0]} TEAMS MEET 1-4 TIMES, NOT {d[1]}.",
        DC_STAGE_POINTS: lambda: f"IN STAGE {d[0]} A WIN GIVES 2 OR 3 POINTS, NOT {d[1]}.",
        DC_DATES: lambda: f"STAGE {d[0]} NEEDS {d[1]} MATCH DATES, AT MOST 90 FIT.",
        DC_UNUSED_STAGE: lambda: f"STAGE {d[0]} IS NOT PLAYED BUT HOLDS VALUES.",
        DC_RESERVED: lambda: "UNUSED BYTES OF THE DEFINITION ARE NOT ZERO.",
        DC_TEAM_COUNT: lambda: f"THE TEAM LIST HAS {d[0]} TEAMS, THE COMPETITION {d[1]}.",
        DC_TEAM_ENTRY: lambda: f"TEAM {d[0]} OF THE LIST IS NOT VALID.",
        DC_TEAM_GROUP: lambda: f"TEAM {d[0]} COMES FROM AN UNKNOWN GROUP {d[1]}.",
        DC_TEAM_TWICE: lambda: f"TEAM {d[0]} OF THE LIST IS THERE TWICE.",
        DC_TACTIC_MASK: lambda: "THE TACTIC SLOTS ARE NOT VALID.",
        DC_TACTIC: lambda: f"THE TACTIC IN USER {chr(65 + d[0])} IS NOT VALID:",
    }
    return texts[code]() if code in texts else ""


def problem_lines(raw: bytes) -> list[str]:
    """The lines FILE DAMAGED shows for a file (without the file name and
    the last line), as the editor builds them: the problem, and for a
    tactic its own problem line (tactic_data.problem_text)."""
    code, details = check_file(raw)
    if code == DC_OK:
        return []
    lines = [problem_text(code, details)]
    if code == DC_TACTIC:
        body = raw[HEADER_SIZE:]
        offset = B_LIST + word(body, B_TEAM_COUNT) * PARTICIPANT_SIZE
        mask = word(body, B_TACTIC_MASK)
        for slot in range(details[0]):
            if mask & (1 << slot):
                offset += TACTIC_SIZE
        lines.append(tactic_data.problem_text(*tactic_data.check_record(body[offset:offset + TACTIC_SIZE])))
    return lines


# ---------------------------------------------------------------------------
# JSON view
# ---------------------------------------------------------------------------
def _text(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("latin-1")


def _field(text: str, size: int, what: str) -> bytes:
    data = text.encode("latin-1")
    if len(data) >= size:
        raise ValueError(f"{what} is longer than {size - 1} characters")
    return data.ljust(size, b"\0")


def decode_body(body: bytes) -> dict[str, Any]:
    code, details = check_body(body)
    if code != DC_OK:
        raise ValueError(problem_text(code, details))
    family = FAMILIES[word(body, B_FAMILY)]
    kind = word(body, B_DB_KIND)
    document: dict[str, Any] = {
        "schema": SCHEMA,
        "database": ({"kind": "original"} if kind == 0 else
                     {"kind": "edited", "generation": word(body, B_DB_GENERATION),
                      "crc32": f"{struct.unpack_from('>I', body, B_DB_CRC)[0]:08X}",
                      "label": _text(body[B_DB_LABEL:B_DB_LABEL + LABEL_SIZE])}),
        "custom_set_crc32": (f"{struct.unpack_from('>I', body, B_CUSTOM_CRC)[0]:08X}"
                             if word(body, B_DB_FLAGS) & 1 else None),
        "family": family,
        "name": _text(body[B_NAME:B_NAME + NAME_FIELD]),
        "pitch": {"mode": word(body, B_PITCH_MODE), "type": signed_word(body, B_PITCH_TYPE)},
        "season": {"start": body[B_START], "end": body[B_END]},
        "teams": word(body, B_TEAMS),
        "substitutes": {"usable": word(body, B_SUBS), "bench": word(body, B_BENCH)},
    }
    if family == "league":
        document["league"] = {"repetitions": word(body, B_L_REPEAT), "points": word(body, B_L_POINTS)}
    elif family == "cup":
        document["cup"] = {
            "rounds": word(body, B_C_ROUNDS), "away_goals": word(body, B_C_AWAY),
            "legs": list(struct.unpack_from(">6H", body, B_C_LEGS)),
            "extra_time": list(struct.unpack_from(">6H", body, B_C_EXTRA)),
            "penalties": list(struct.unpack_from(">6H", body, B_C_PENALTIES))}
    else:
        stages = word(body, B_T_STAGES)
        document["tournament"] = {
            "away_goals": word(body, B_T_AWAY),
            "stages": [dict(zip(STAGE_FIELDS, stage_record(body, i))) for i in range(stages)]}
    participants = []
    for index in range(word(body, B_TEAM_COUNT)):
        entry = body[B_LIST + index * PARTICIPANT_SIZE:B_LIST + (index + 1) * PARTICIPANT_SIZE]
        participants.append({"group": entry[P_GROUP], "ordinal": entry[P_ORDINAL],
                             "source": SOURCES[entry[P_SOURCE]], "control": CONTROLS[entry[P_CONTROL]],
                             "name": _text(entry[P_NAME:P_NAME + TEAM_NAME_SIZE])})
    document["participants"] = participants
    tactics = {}
    offset = B_LIST + len(participants) * PARTICIPANT_SIZE
    mask = word(body, B_TACTIC_MASK)
    for slot in range(USER_SLOTS):
        if mask & (1 << slot):
            tactics[f"USER {chr(65 + slot)}"] = tactic_data.read_tactic(body[offset:offset + TACTIC_SIZE])
            offset += TACTIC_SIZE
    document["tactics"] = tactics
    return document


def encode_body(document: dict[str, Any]) -> bytes:
    if document.get("schema") != SCHEMA:
        raise ValueError(f"expected schema {SCHEMA!r}")
    body = bytearray(BODY_FIXED)
    database = document["database"]
    if database["kind"] == "edited":
        struct.pack_into(">HHI", body, B_DB_KIND, 1, database["generation"], int(database["crc32"], 16))
        body[B_DB_LABEL:B_DB_LABEL + LABEL_SIZE] = database["label"].encode("latin-1").ljust(LABEL_SIZE, b"\0")
    elif database["kind"] != "original":
        raise ValueError("database.kind must be original or edited")
    if document.get("custom_set_crc32") is not None:
        struct.pack_into(">I", body, B_CUSTOM_CRC, int(document["custom_set_crc32"], 16))
        struct.pack_into(">H", body, B_DB_FLAGS, 1)
    family = FAMILIES.index(document["family"])
    struct.pack_into(">H", body, B_FAMILY, family)
    body[B_NAME:B_NAME + NAME_FIELD] = _field(document["name"], NAME_FIELD, "name")
    struct.pack_into(">Hh", body, B_PITCH_MODE, document["pitch"]["mode"], document["pitch"]["type"])
    body[B_START], body[B_END] = document["season"]["start"], document["season"]["end"]
    struct.pack_into(">HHH", body, B_TEAMS, document["teams"], document["substitutes"]["usable"],
                     document["substitutes"]["bench"])
    if family == 0:
        rules = document["league"]
        struct.pack_into(">HH", body, B_L_REPEAT, rules["repetitions"], rules["points"])
    elif family == 1:
        rules = document["cup"]
        struct.pack_into(">HH", body, B_C_ROUNDS, rules["rounds"], rules["away_goals"])
        struct.pack_into(">6H", body, B_C_LEGS, *rules["legs"])
        struct.pack_into(">6H", body, B_C_EXTRA, *rules["extra_time"])
        struct.pack_into(">6H", body, B_C_PENALTIES, *rules["penalties"])
    else:
        rules = document["tournament"]
        stages = rules["stages"]
        if not 1 <= len(stages) <= MAX_STAGES:
            raise ValueError("a tournament has 1-6 stages")
        struct.pack_into(">HH", body, B_T_AWAY, rules["away_goals"], len(stages))
        for index, stage in enumerate(stages):
            struct.pack_into(">10H", body, B_T_STAGE + index * STAGE_SIZE,
                             *(stage[name] for name in STAGE_FIELDS))
    participants = document.get("participants", [])
    controls = {name: value for value, name in CONTROLS.items()}
    struct.pack_into(">H", body, B_TEAM_COUNT, len(participants))
    for entry in participants:
        body += bytes([entry["group"], entry["ordinal"], SOURCES.index(entry["source"]),
                       controls[entry["control"]]])
        body += _field(entry["name"], TEAM_NAME_SIZE, "team name") + bytes(3)
    mask = 0
    for slot in range(USER_SLOTS):
        tactic = document.get("tactics", {}).get(f"USER {chr(65 + slot)}")
        if tactic is not None:
            mask |= 1 << slot
            body += tactic_data.write_tactic(tactic)
    struct.pack_into(">H", body, B_TACTIC_MASK, mask)
    return bytes(body)


def wrap(body: bytes) -> bytes:
    """Header and body: the file the editor writes."""
    return MAGIC + struct.pack(">HHI", VERSION, len(body), crc32(body)) + body


def decode(raw: bytes) -> dict[str, Any]:
    code, details = check_file(raw)
    if code != DC_OK:
        raise ValueError(problem_text(code, details))
    return decode_body(raw[HEADER_SIZE:])


def encode(document: dict[str, Any]) -> bytes:
    body = encode_body(document)
    code, details = check_body(body)
    if code != DC_OK:
        raise ValueError(problem_text(code, details))
    return wrap(body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)
    reader = subparsers.add_parser("decode", help=".DEF to JSON")
    reader.add_argument("source", type=Path)
    reader.add_argument("output", type=Path)
    writer = subparsers.add_parser("encode", help="JSON to .DEF (checked first)")
    writer.add_argument("source", type=Path)
    writer.add_argument("output", type=Path)
    checker = subparsers.add_parser("check", help="check a .DEF as LOAD DEFINITION does")
    checker.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "check":
            raw = args.source.read_bytes()
            lines = problem_lines(raw)
            if lines:
                parser.exit(1, "FILE DAMAGED: " + " ".join(lines) + "\n")
            print(f"the editor accepts this definition (CRC-32 {crc32(raw[HEADER_SIZE:]):08X})")
            return
        if args.command == "decode":
            result = (json.dumps(decode(args.source.read_bytes()), indent=2) + "\n").encode()
        else:
            result = encode(json.loads(args.source.read_text(encoding="utf-8")))
        if args.source.resolve() == args.output.resolve():
            raise ValueError("input and output must be different paths")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
    except (ValueError, KeyError, TypeError, OSError, struct.error) as exc:
        parser.exit(1, f"definition_data: {exc}\n")


if __name__ == "__main__":
    main()
