#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Lossless JSON reader/writer for 370-byte Amiga SWOS tactics.

Input: a raw native .TAC, concatenated tactic records, or an explicitly selected
range of the unpacked executable. There is no RNC wrapper, count, or checksum
inside a .TAC payload. This tool never modifies an ADF. A record is a nine-byte
name, ten player maps of 35 ball zones (one byte per zone: x in the high nibble,
y in the low nibble), ten mirror-pair labels and the base formation byte;
validate_for_game and check_record hold the game's constraints.

  python3 tools/tactic_data.py decode SWOS/data/TEST.TAC tactic.json
  python3 tools/tactic_data.py encode tactic.json SWOS/data/TEST.TAC
  python3 tools/tactic_data.py decode unpacked/disk1/SWOS2 builtins.json \
      --offset 0x234f0 --count 12
  python3 tools/tactic_data.py validate tactic.json
  python3 tools/tactic_data.py check SWOS/data/TEST.TAC

The codec preserves even engine-invalid values, including x=15, unknown mirror
labels/base IDs and unterminated names. Run validate before loading edits. Text
keeps its raw nine-byte baseline, including bytes beyond the first NUL; changing
the readable text replaces that field with NUL-terminated, zero-padded Latin-1.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Any

SCHEMA = "swos-amiga-tactics-v1"
TACTIC_SIZE = 0x172
NAME_SIZE = 9
PLAYER_COUNT = 10
ZONE_COLUMNS = 5
ZONE_ROWS = 7
ZONE_COUNT = ZONE_COLUMNS * ZONE_ROWS
MIRROR_OFFSET = NAME_SIZE + PLAYER_COUNT * ZONE_COUNT
BASE_OFFSET = 0x171
BUILTINS_OFFSET = 0x234F0  # SWOS2 unpacked image, before or after relocation
BUILTIN_COUNT = 12


def _uint(value: Any, bits: int, name: str) -> int:
    if type(value) is not int or not 0 <= value < 1 << bits:
        raise ValueError(f"{name} must be an unsigned {bits}-bit integer")
    return value


def _array(value: Any, length: int, name: str) -> list:
    if not isinstance(value, list) or len(value) != length:
        raise ValueError(f"{name} must contain exactly {length} entries")
    return value


def _read_name(raw: bytes) -> dict[str, str]:
    return {"text": raw.split(b"\0", 1)[0].decode("latin-1"), "raw_hex": raw.hex()}


def _write_name(name: dict[str, str]) -> bytes:
    text = name["text"]
    if not isinstance(text, str) or "\0" in text:
        raise ValueError("name.text must be a string without NUL characters")
    try:
        raw = bytes.fromhex(name["raw_hex"])
    except (TypeError, ValueError) as exc:
        raise ValueError("name.raw_hex must be hexadecimal bytes") from exc
    if len(raw) != NAME_SIZE:
        raise ValueError("name.raw_hex must contain exactly nine bytes")
    if text == _read_name(raw)["text"]:
        return raw
    try:
        encoded = text.encode("latin-1")
    except UnicodeEncodeError as exc:
        raise ValueError("name.text is not Latin-1 encodable") from exc
    if len(encoded) >= NAME_SIZE:
        raise ValueError("name.text must leave room for NUL (eight bytes maximum)")
    return encoded.ljust(NAME_SIZE, b"\0")


def read_tactic(raw: bytes) -> dict[str, Any]:
    if len(raw) != TACTIC_SIZE:
        raise ValueError(f"tactic record must be exactly {TACTIC_SIZE} bytes")
    return {
        "name": _read_name(raw[:NAME_SIZE]),
        "positions": [
            [{"x": value >> 4, "y": value & 15}
             for value in raw[NAME_SIZE + player * ZONE_COUNT:
                              NAME_SIZE + (player + 1) * ZONE_COUNT]]
            for player in range(PLAYER_COUNT)
        ],
        "mirror_pair_groups": list(raw[MIRROR_OFFSET:BASE_OFFSET]),
        "base_formation": raw[BASE_OFFSET],
    }


def write_tactic(tactic: dict[str, Any]) -> bytes:
    result = bytearray(_write_name(tactic["name"]))
    players = _array(tactic["positions"], PLAYER_COUNT, "positions")
    for player, positions in enumerate(players):
        for zone, xy in enumerate(_array(positions, ZONE_COUNT, f"positions[{player}]")):
            label = f"positions[{player}][{zone}]"
            result.append((_uint(xy["x"], 4, label + ".x") << 4)
                          | _uint(xy["y"], 4, label + ".y"))
    groups = _array(tactic["mirror_pair_groups"], PLAYER_COUNT, "mirror_pair_groups")
    result.extend(_uint(value, 8, f"mirror_pair_groups[{i}]")
                  for i, value in enumerate(groups))
    result.append(_uint(tactic["base_formation"], 8, "base_formation"))
    assert len(result) == TACTIC_SIZE
    return bytes(result)


def decode(raw: bytes) -> dict[str, Any]:
    if not raw or len(raw) % TACTIC_SIZE:
        raise ValueError("input must contain one or more complete 370-byte tactics")
    return {"schema": SCHEMA, "tactics": [
        read_tactic(raw[start:start + TACTIC_SIZE])
        for start in range(0, len(raw), TACTIC_SIZE)
    ]}


def encode(document: dict[str, Any]) -> bytes:
    if document["schema"] != SCHEMA:
        raise ValueError(f"expected schema {SCHEMA!r}")
    tactics = document["tactics"]
    if not isinstance(tactics, list) or not tactics:
        raise ValueError("tactics must be a nonempty array")
    return b"".join(write_tactic(tactic) for tactic in tactics)


def validate_for_game(tactic: dict[str, Any]) -> list[str]:
    """Check native-editor constraints separately from lossless byte encoding.

    Labels 0..4 must occur twice when used; 255 means unpaired. Duplicate player
    coordinates are rejected by the native editor, although the match reader
    itself does not check them. Empty names and character/font compatibility
    are not checked here; filename validation belongs to the storage/UI layer.
    """
    raw = write_tactic(tactic)
    issues = []
    if b"\0" not in raw[:NAME_SIZE]:
        issues.append("name has no NUL terminator in its nine-byte field")
    if raw[BASE_OFFSET] >= BUILTIN_COUNT:
        issues.append("base_formation must select a builtin (0..11)")
    groups = Counter(raw[MIRROR_OFFSET:BASE_OFFSET])
    for group, count in sorted(groups.items()):
        if group == 255:
            continue
        if group > 4:
            issues.append(f"mirror label {group} is outside 0..4 or 255")
        elif count != 2:
            issues.append(f"mirror label {group} occurs {count} times, expected two")
    for zone in range(ZONE_COUNT):
        coordinates = [raw[NAME_SIZE + player * ZONE_COUNT + zone]
                       for player in range(PLAYER_COUNT)]
        for player, packed in enumerate(coordinates):
            if packed >> 4 == 15:
                issues.append(f"player {player + 1}, zone {zone}: x=15 exceeds 14")
        if len(set(coordinates)) != PLAYER_COUNT:
            issues.append(f"zone {zone}: two or more players occupy the same coordinate")
    return issues


# The editor's commit and load check (src/editor/editors/tactics.s
# tactic_check), in the same order and with the same message text, so a
# host-written file is refused or accepted exactly as on the Amiga.
TC_OK, TC_SIZE, TC_NAME, TC_RANGE, TC_SHARED, TC_LABEL, TC_PAIR, TC_BASE = range(8)
X_MAX = 14
PAIR_LABELS = 5
UNPAIRED = 0xFF
FIRST_ROLE = 2          # lineup role of map 0; role 1 keeps goal
BODY_SIZE = TACTIC_SIZE - NAME_SIZE


def check_record(raw: bytes) -> tuple[int, tuple[int, ...]]:
    """(TC_*, details) of the first problem the editor reports, or (TC_OK, ()).

    A .TAC of another length gives (TC_SIZE, (length,)). Order: the name
    field without NUL; x above 14 (maps in record order, zones in order);
    two maps on one position (zones in order, then the first map, then the
    second); a label neither 0-4 nor 255; a used label not on exactly two
    maps; a base formation that is not a builtin.
    """
    if len(raw) != TACTIC_SIZE:
        return TC_SIZE, (len(raw),)
    if b"\0" not in raw[:NAME_SIZE]:
        return TC_NAME, ()
    for player in range(PLAYER_COUNT):
        for zone in range(ZONE_COUNT):
            x = raw[NAME_SIZE + player * ZONE_COUNT + zone] >> 4
            if x > X_MAX:
                return TC_RANGE, (player, zone, x)
    for zone in range(ZONE_COUNT):
        packed = [raw[NAME_SIZE + player * ZONE_COUNT + zone] for player in range(PLAYER_COUNT)]
        for first in range(PLAYER_COUNT - 1):
            for second in range(first + 1, PLAYER_COUNT):
                if packed[first] == packed[second]:
                    return TC_SHARED, (first, second, zone)
    labels = raw[MIRROR_OFFSET:BASE_OFFSET]
    for player, label in enumerate(labels):
        if label != UNPAIRED and label >= PAIR_LABELS:
            return TC_LABEL, (player, label)
    for label in range(PAIR_LABELS):
        count = labels.count(label)
        if count not in (0, 2):
            return TC_PAIR, (label, count)
    if raw[BASE_OFFSET] >= BUILTIN_COUNT:
        return TC_BASE, (raw[BASE_OFFSET],)
    return TC_OK, ()


def problem_text(code: int, details: tuple[int, ...]) -> str:
    """The line the editor shows for a problem; players are lineup roles."""
    if code == TC_SIZE:
        length = details[0]
        return f"THE FILE HAS {length if length <= 0xFFFF else 'OVER 65535'} BYTES, A TACTIC HAS 370."
    if code == TC_NAME:
        return "THE NAME IS LONGER THAN 8 CHARACTERS."
    if code == TC_RANGE:
        return f"PLAYER {details[0] + FIRST_ROLE} IS OFF THE PITCH IN BALL ZONE {details[1]}."
    if code == TC_SHARED:
        return (f"PLAYERS {details[0] + FIRST_ROLE} AND {details[1] + FIRST_ROLE} "
                f"SHARE A SPOT IN BALL ZONE {details[2]}.")
    if code == TC_LABEL:
        return f"PLAYER {details[0] + FIRST_ROLE} HAS AN UNKNOWN MIRROR PAIR {details[1]}."
    if code == TC_PAIR:
        if details[1] == 1:
            return f"MIRROR PAIR {details[0]} HAS ONLY ONE PLAYER."
        return f"MIRROR PAIR {details[0]} HAS {details[1]} PLAYERS, NOT TWO."
    if code == TC_BASE:
        return f"THE BASE FORMATION {details[0]} IS NOT A BUILTIN TACTIC."
    return ""


def import_body(working: bytes, source: bytes) -> bytes:
    """IMPORT as the editor does it: the source's 361 body bytes over the
    working tactic, which keeps its name (the native loop copies 370)."""
    if len(working) != TACTIC_SIZE or len(source) != TACTIC_SIZE:
        raise ValueError("both records must be 370 bytes")
    return working[:NAME_SIZE] + source[NAME_SIZE:]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    reader = subparsers.add_parser("decode", help="raw tactic records to JSON")
    reader.add_argument("source", type=Path)
    reader.add_argument("output", type=Path)
    reader.add_argument("--offset", type=lambda n: int(n, 0), default=0)
    reader.add_argument("--count", type=int, help="select this many records from offset")
    writer = subparsers.add_parser("encode", help="JSON to raw tactic records")
    writer.add_argument("source", type=Path)
    writer.add_argument("output", type=Path)
    checker = subparsers.add_parser("validate", help="check native-editor constraints")
    checker.add_argument("source", type=Path)
    tac = subparsers.add_parser("check", help="check a .TAC file as the editor's LOAD does")
    tac.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "check":
            code, details = check_record(args.source.read_bytes())
            if code != TC_OK:
                parser.exit(1, f"FILE DAMAGED: {problem_text(code, details)}\n")
            print("the editor accepts this tactic")
            return
        if args.command == "decode":
            if args.offset < 0 or (args.count is not None and args.count <= 0):
                raise ValueError("offset must be nonnegative and count positive")
            source = args.source.read_bytes()
            end = len(source) if args.count is None else args.offset + args.count * TACTIC_SIZE
            if end > len(source) or args.offset >= len(source):
                raise ValueError("selected records exceed input length")
            document = decode(source[args.offset:end])
            result = (json.dumps(document, ensure_ascii=True, indent=2) + "\n").encode("utf-8")
        else:
            document = json.loads(args.source.read_text(encoding="utf-8"))
            result = encode(document)
            if args.command == "validate":
                issues = [f"tactic {i}: {issue}" for i, tactic in enumerate(document["tactics"])
                          for issue in validate_for_game(tactic)]
                if issues:
                    raise ValueError("\n".join(issues))
                print(f"{len(document['tactics'])} tactics satisfy known native-editor constraints")
                return
        if args.source.resolve() == args.output.resolve():
            raise ValueError("input and output must be different paths")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
    except (ValueError, KeyError, TypeError, OSError) as exc:
        parser.exit(1, f"tactic_data: {exc}\n")


if __name__ == "__main__":
    main()
