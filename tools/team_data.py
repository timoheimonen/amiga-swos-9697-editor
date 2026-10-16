#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.91b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Read/write decompressed Amiga SWOS team records as lossless JSON.

Input: decompressed TEAM.xxx (count + records), headerless .TMD records,
or POOLPLYR.DAT (900 fixed 58-byte entries in the supplied release).
Output: JSON with every byte represented, or the corresponding binary payload.
This tool does not decompress/recompress RNC or change an ADF.
The record layout comes from the game's own Amiga data files, not from a PC
editor. Candidate semantic names do not establish engine-valid ranges; check
edited records with the in-game editors' rules (tools/custom_set.py and
tools/database_set.py) before the game uses them.

Examples:
  python3 tools/rnc.py extracted/disk2/data/TEAM.008 unpacked/disk2/data/TEAM.008
  python3 tools/team_data.py decode unpacked/disk2/data/TEAM.008 teams.json
  python3 tools/team_data.py encode teams.json TEAM.008.raw
  python3 tools/team_data.py decode --kind team-records unpacked/disk2/data/EUROCUP.TMD cup.json

Text has a readable value and a raw fixed-width baseline. Unchanged text preserves
every baseline byte, including padding. Changed text is Latin-1 encoded, NUL
terminated and zero padded. Unknown fields and skill nibbles remain explicit.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

TEAM_SIZE = 0x2AC
PLAYER_SIZE = 0x26
PLAYER_COUNT = 16
PLAYERS_OFFSET = 0x4C
POOL_ENTRY_SIZE = 0x3A
SKILL_NAMES = ("passing", "shooting", "heading", "tackling", "ball_control", "speed", "finishing")
SCHEMA = "swos-amiga-team-data-v1"


def _uint(value: Any, bits: int, name: str) -> int:
    if type(value) is not int or not 0 <= value < 1 << bits:
        raise ValueError(f"{name} must be an unsigned {bits}-bit integer")
    return value


def _hex(value: str, size: int, name: str) -> bytes:
    try:
        result = bytes.fromhex(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be hexadecimal bytes") from exc
    if len(result) != size:
        raise ValueError(f"{name} must contain exactly {size} bytes")
    return result


def _read_text(raw: bytes) -> dict[str, str]:
    return {"text": raw.split(b"\0", 1)[0].decode("latin-1"), "raw_hex": raw.hex()}


def _write_text(value: dict[str, str], size: int, name: str) -> bytes:
    text = value["text"]
    if not isinstance(text, str) or "\0" in text:
        raise ValueError(f"{name}.text must be a string without NUL characters")
    raw = _hex(value["raw_hex"], size, name + ".raw_hex")
    if text == _read_text(raw)["text"]:
        return raw
    try:
        encoded = text.encode("latin-1")
    except UnicodeEncodeError as exc:
        raise ValueError(f"{name}.text is not Latin-1 encodable") from exc
    if len(encoded) >= size:
        raise ValueError(f"{name}.text must leave room for a NUL ({size - 1} bytes maximum)")
    return encoded.ljust(size, b"\0")


def _byte_list(value: list[int], size: int, name: str) -> bytes:
    if not isinstance(value, list) or len(value) != size:
        raise ValueError(f"{name} must contain exactly {size} integers")
    return bytes(_uint(item, 8, f"{name}[{i}]") for i, item in enumerate(value))


def read_player(raw: bytes) -> dict[str, Any]:
    if len(raw) != PLAYER_SIZE:
        raise ValueError(f"player record must be {PLAYER_SIZE} bytes")
    skill_word = int.from_bytes(raw[0x1C:0x20], "big")
    return {
        "nationality_code": raw[0],
        "unknown_01": raw[1],
        "shirt_number": raw[2],
        "name": _read_text(raw[3:0x1A]),
        "position_appearance_bits": raw[0x1A],
        "unknown_1b": raw[0x1B],
        "skill_prefix_nibble": skill_word >> 28,
        "skill_nibbles": [(skill_word >> shift) & 15 for shift in range(24, -1, -4)],
        "aggregate_rating": raw[0x20],
        "unknown_21_25_hex": raw[0x21:0x26].hex(),
    }


def write_player(player: dict[str, Any]) -> bytes:
    skills = player["skill_nibbles"]
    if not isinstance(skills, list) or len(skills) != 7:
        raise ValueError("skill_nibbles must contain exactly seven integers")
    skill_word = _uint(player["skill_prefix_nibble"], 4, "skill_prefix_nibble")
    for i, skill in enumerate(skills):
        skill_word = (skill_word << 4) | _uint(skill, 4, f"skill_nibbles[{i}]")
    result = bytes(_uint(player[key], 8, key) for key in (
        "nationality_code", "unknown_01", "shirt_number"
    ))
    result += _write_text(player["name"], 23, "player.name")
    result += bytes(_uint(player[key], 8, key) for key in (
        "position_appearance_bits", "unknown_1b"
    ))
    result += skill_word.to_bytes(4, "big")
    result += bytes([_uint(player["aggregate_rating"], 8, "aggregate_rating")])
    result += _hex(player["unknown_21_25_hex"], 5, "unknown_21_25_hex")
    assert len(result) == PLAYER_SIZE
    return result


def set_player_skill(player: dict[str, Any], skill: str, rating: int,
                     *, specialty: bool | None = None) -> None:
    """Edit a low-three-bit skill; keep its specialty flag unless explicitly set.

    Recompute outfield aggregate rating. Goalkeeper aggregate rating is independent
    and remains untouched; the caller must decide whether nonzero keeper skills
    are appropriate (the supplied keeper records all store zero skills).
    """
    try:
        index = SKILL_NAMES.index(skill)
    except ValueError as exc:
        raise ValueError(f"unknown skill {skill!r}") from exc
    rating = _uint(rating, 3, "skill rating")
    old = _uint(player["skill_nibbles"][index], 4, "skill nibble")
    if specialty is not None and type(specialty) is not bool:
        raise ValueError("specialty must be a boolean or None")
    flag = old & 8 if specialty is None else int(specialty) << 3
    player["skill_nibbles"][index] = flag | rating
    if player["position_appearance_bits"] >> 5:
        player["aggregate_rating"] = sum(nibble & 7 for nibble in player["skill_nibbles"])


def read_pool_entry(raw: bytes) -> dict[str, Any]:
    if len(raw) != POOL_ENTRY_SIZE:
        raise ValueError(f"pool entry must be {POOL_ENTRY_SIZE} bytes")
    return {
        "group_code": raw[0],
        "team_ordinal": raw[1],
        "player_slot": raw[2],
        "team_name": _read_text(raw[3:20]),
        "player": read_player(raw[20:]),
    }


def write_pool_entry(entry: dict[str, Any]) -> bytes:
    result = bytes(_uint(entry[key], 8, key) for key in
                   ("group_code", "team_ordinal", "player_slot"))
    result += _write_text(entry["team_name"], 17, "pool.team_name")
    result += write_player(entry["player"])
    assert len(result) == POOL_ENTRY_SIZE
    return result


def read_team(raw: bytes) -> dict[str, Any]:
    if len(raw) != TEAM_SIZE:
        raise ValueError(f"team record must be {TEAM_SIZE} bytes")
    return {
        "group_code": raw[0],
        "ordinal": raw[1],
        "database_id": int.from_bytes(raw[2:4], "big"),
        "unknown_04": raw[4],
        "name": _read_text(raw[5:0x16]),
        "unknown_16": raw[0x16],
        "flags_17": raw[0x17],
        "tactic_code": raw[0x18],
        "division_code": raw[0x19],
        "home_kit_bytes": list(raw[0x1A:0x1F]),
        "away_kit_bytes": list(raw[0x1F:0x24]),
        "coach": _read_text(raw[0x24:0x3B]),
        "flags_3b": raw[0x3B],
        "lineup": list(raw[0x3C:0x4C]),
        "players": [read_player(raw[start:start + PLAYER_SIZE])
                    for start in range(PLAYERS_OFFSET, TEAM_SIZE, PLAYER_SIZE)],
    }


def write_team(team: dict[str, Any]) -> bytes:
    players = team["players"]
    if not isinstance(players, list) or len(players) != PLAYER_COUNT:
        raise ValueError(f"players must contain exactly {PLAYER_COUNT} records")
    result = bytes(_uint(team[key], 8, key) for key in ("group_code", "ordinal"))
    result += _uint(team["database_id"], 16, "database_id").to_bytes(2, "big")
    result += bytes([_uint(team["unknown_04"], 8, "unknown_04")])
    result += _write_text(team["name"], 17, "team.name")
    result += bytes(_uint(team[key], 8, key) for key in ("unknown_16", "flags_17"))
    result += bytes(_uint(team[key], 8, key) for key in ("tactic_code", "division_code"))
    result += _byte_list(team["home_kit_bytes"], 5, "home_kit_bytes")
    result += _byte_list(team["away_kit_bytes"], 5, "away_kit_bytes")
    result += _write_text(team["coach"], 23, "coach")
    result += bytes([_uint(team["flags_3b"], 8, "flags_3b")])
    result += _byte_list(team["lineup"], PLAYER_COUNT, "lineup")
    result += b"".join(write_player(player) for player in players)
    assert len(result) == TEAM_SIZE
    return result


def decode(raw: bytes, *, kind: str = "team-file") -> dict[str, Any]:
    """Decode exact-length payloads; never silently drop a trailer or partial record."""
    if kind == "player-pool":
        if len(raw) % POOL_ENTRY_SIZE:
            raise ValueError("player pool ends in a partial entry")
        return {
            "schema": SCHEMA,
            "kind": kind,
            "entries": [read_pool_entry(raw[start:start + POOL_ENTRY_SIZE])
                        for start in range(0, len(raw), POOL_ENTRY_SIZE)],
        }
    if kind == "team-file":
        if len(raw) < 2:
            raise ValueError("TEAM file is missing its two-byte count")
        count = int.from_bytes(raw[:2], "big")
        payload = raw[2:]
        if len(payload) != count * TEAM_SIZE:
            raise ValueError(f"TEAM count {count} disagrees with payload length {len(payload)}")
    elif kind == "team-records":
        payload = raw
        if len(payload) % TEAM_SIZE:
            raise ValueError("headerless team data ends in a partial record")
    else:
        raise ValueError(f"unknown team data kind {kind!r}")
    return {
        "schema": SCHEMA,
        "kind": kind,
        "teams": [read_team(payload[start:start + TEAM_SIZE])
                  for start in range(0, len(payload), TEAM_SIZE)],
    }


def encode(document: dict[str, Any]) -> bytes:
    if document["schema"] != SCHEMA:
        raise ValueError(f"expected schema {SCHEMA!r}")
    if document["kind"] == "player-pool":
        entries = document["entries"]
        if not isinstance(entries, list):
            raise ValueError("entries must be an array")
        return b"".join(write_pool_entry(entry) for entry in entries)
    teams = document["teams"]
    if not isinstance(teams, list):
        raise ValueError("teams must be an array")
    if document["kind"] == "team-file":
        prefix = _uint(len(teams), 16, "team count").to_bytes(2, "big")
    elif document["kind"] == "team-records":
        prefix = b""
    else:
        raise ValueError(f"unknown team data kind {document['kind']!r}")
    return prefix + b"".join(write_team(team) for team in teams)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    reader = subparsers.add_parser("decode", help="convert decompressed binary to JSON")
    reader.add_argument("--kind", choices=("team-file", "team-records", "player-pool"), default="team-file")
    reader.add_argument("source", type=Path)
    reader.add_argument("output", type=Path)
    writer = subparsers.add_parser("encode", help="convert JSON to decompressed binary")
    writer.add_argument("source", type=Path)
    writer.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "decode":
            result = (json.dumps(decode(args.source.read_bytes(), kind=args.kind),
                                 ensure_ascii=True, indent=2) + "\n").encode("utf-8")
        else:
            result = encode(json.loads(args.source.read_text(encoding="utf-8")))
        # The input is never replaced, including through symlinks.
        if args.source.resolve() == args.output.resolve():
            raise ValueError("input and output must be different paths")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f"team_data: {exc}\n")


if __name__ == "__main__":
    main()
