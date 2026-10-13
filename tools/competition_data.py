#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""Lossless Amiga SWOS competition definitions and native save payloads.

Inputs: unpacked SWOS2 for builtin definitions; raw .DIY/.PRE/.SEA/.CAR saves.
Outputs: JSON or the raw payload. No disk image is changed. Known fields
overlay an explicit raw baseline; unidentified bytes, pointers and state are
retained. This is a codec, not a fixture/schedule generator or a guarantee
that edited state will be playable; patch.py exports saves with it for
reading only.

  python3 tools/competition_data.py decode SWOS/data/TEST.DIY diy.json --kind diy
  python3 tools/competition_data.py encode diy.json TEST-copy.DIY
  python3 tools/competition_data.py builtins SWOS2 builtins.json

Encoding builtin JSON emits only the $4F35A..$50897 definition block, not SWOS2.
It preserves the source image's pointer base; it does not relocate pointers.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import tactic_data
import team_data

SCHEMA = "swos-amiga-competition-data-v1"
SAVE_HEADER_SIZE = 0x1432
CAREER_PREFIX_SIZE = 0x16C7C
STATE_SIZE = 0xB54
USER_TACTICS_OFFSET = 0xB60
COMPATIBILITY_OFFSET = 0x141E
LOADED_COUNT_OFFSET = 0x1430
BUILTIN_END = 0x50898
# Measured SWOS2 image offsets: descriptor IDs 0..161 in physical order. Regions
# include their local auxiliary tables/padding through the next descriptor.
BUILTIN_OFFSETS = (
    0x4F35A, 0x4F3A8, 0x4F404, 0x4F460, 0x4F4D0, 0x4F530, 0x4F558, 0x4F580, 0x4F5A8, 0x4F5D0,
    0x4F5F8, 0x4F620, 0x4F648, 0x4F670, 0x4F6B8, 0x4F6F8, 0x4F768, 0x4F7D4, 0x4F7F8, 0x4F81C,
    0x4F840, 0x4F868, 0x4F8B6, 0x4F904, 0x4F92C, 0x4F954, 0x4F97C, 0x4F9A4, 0x4F9CC, 0x4F9F4,
    0x4FA1C, 0x4FA40, 0x4FA86, 0x4FAB6, 0x4FAE4, 0x4FB14, 0x4FB30, 0x4FB68, 0x4FB7C, 0x4FB90,
    0x4FBA4, 0x4FBB8, 0x4FBCC, 0x4FBE0, 0x4FBF4, 0x4FC08, 0x4FC1C, 0x4FD52, 0x4FD72, 0x4FD92,
    0x4FDB2, 0x4FDC6, 0x4FDDA, 0x4FDEE, 0x4FE18, 0x4FE42, 0x4FE56, 0x4FEC0, 0x4FEE0, 0x4FEF4,
    0x4FF08, 0x4FF1C, 0x4FF46, 0x4FF5A, 0x4FF6E, 0x4FF82, 0x4FF96, 0x4FFAA, 0x4FFBE, 0x4FFD2,
    0x4FFE6, 0x4FFFA, 0x5000E, 0x50022, 0x50036, 0x50084, 0x500A0, 0x500B4, 0x500C8, 0x50142,
    0x50162, 0x50176, 0x5018A, 0x5019E, 0x501B2, 0x501C6, 0x501DA, 0x501EE, 0x50208, 0x5024E,
    0x50262, 0x50276, 0x5028A, 0x5029E, 0x502B2, 0x502D8, 0x502EC, 0x50316, 0x50330, 0x50368,
    0x5037C, 0x50390, 0x503A4, 0x503B8, 0x503CC, 0x5040E, 0x5042A, 0x5043E, 0x50452, 0x50466,
    0x50478, 0x5048A, 0x5049C, 0x504AE, 0x504C0, 0x504D2, 0x504E4, 0x504F6, 0x50508, 0x50524,
    0x50540, 0x5055C, 0x50578, 0x5058A, 0x5059C, 0x505AE, 0x505CA, 0x505E6, 0x505F8, 0x5060A,
    0x5061C, 0x5062E, 0x50640, 0x5065C, 0x5066E, 0x50680, 0x50692, 0x506A4, 0x506B8, 0x506CA,
    0x506DC, 0x506EE, 0x50700, 0x50712, 0x50724, 0x50736, 0x50752, 0x5076E, 0x50780, 0x50792,
    0x507AE, 0x507C0, 0x507D2, 0x507E4, 0x507F6, 0x50808, 0x5081A, 0x5082C, 0x50840, 0x5085A,
    0x50874, 0x50886,
)

# (name, byte offset, byte width, signed). These are storage fields, not a claim
# that every representable value is a valid native editor choice.
COMMON = (
    ("competition_type", 0, 2, False), ("progress_state_word", 2, 2, False),
    ("title_pointer", 0x28, 4, False), ("unknown_2c", 0x2C, 2, False),
    ("descriptor_id", 0x2E, 1, False), ("team_count", 0x32, 2, False),
    ("current_date_eighth_month", 0x2F, 1, False),
    ("pitch_mode", 0x34, 2, False), ("pitch_type", 0x36, 2, True),
    ("season_start_eighth_month", 0x38, 1, False),
    ("season_end_eighth_month", 0x39, 1, False),
)
LEAGUE = tuple((n, o, 2, False) for n, o in (
    ("group_count", 0x50), ("teams_per_group", 0x52), ("promoted", 0x54),
    ("promotion_playoffs", 0x56), ("relegated", 0x58), ("relegation_playoffs", 0x5A),
    ("group_index", 0x5C), ("repeat_count", 0x5E), ("repeats_remaining", 0x60),
    ("points_for_win", 0x62),
    ("substitutes_used", 0x64), ("substitutes_bench", 0x66),
    ("pairs_per_group_cycle", 0x6A), ("pairs_remaining_in_cycle", 0x6C),
    ("matches_processed", 0x1BE), ("matchday_complete", 0x1C0),
    ("matchday_index", 0x1C2), ("matchday_count", 0x1C4),
    ("matches_per_group_day", 0x1C6), ("matches_per_day", 0x1C8),
    ("matches_processed_this_day", 0x1CA), ("pair_index", 0x1CC),
))
STANDING = (("team_offset", 0, 4, True),) + tuple((n, o, 2, False) for n, o in (
    ("played", 4), ("wins", 6), ("draws", 8), ("losses", 10),
    ("goals_for", 12), ("goals_against", 14), ("points", 16),
))
LEAGUE_ARRAYS = (
    ("rank_offsets", 0x6E, 64, 2), ("team_order", 0xEE, 64, 1),
    ("team_keys", 0x12E, 64, 2), ("playoff_team_keys", 0x1AE, 8, 2),
    ("matchday_dates", 0x1CE, 230, 1),
)
CUP = tuple((n, o, 2, False) for n, o in (
    ("ties_in_round", 0x50), ("ties_in_phase", 0x52),
    ("phase_complete", 0x54), ("competition_stage_complete", 0x56),
    ("round_index", 0x58), ("initial_round_number", 0x5C),
    ("round_count", 0x5A), ("away_goals", 0x5E),
    ("substitutes_used", 0x60), ("substitutes_bench", 0x62),
    ("tie_index", 0x64), ("leg_index", 0x14A), ("phase_legs", 0x14C),
    ("replay_tie_count", 0x32E), ("replay_index", 0x330),
    ("matches_processed", 0x332), ("matchday_count", 0x334),
    ("matchday_index", 0x336),
))
CUP_ARRAYS = (
    ("result_flags", 0x8A, 64, 1), ("scores_d4", 0xCA, 64, 2),
    ("scores_d5_prior_leg", 0x14E, 64, 2), ("scores_d6", 0x1CE, 64, 2),
    ("team_keys", 0x24E, 64, 2), ("team_order", 0x2CE, 64, 1),
    ("next_round_tie_order", 0x30E, 32, 1), ("matchday_dates", 0x338, 12, 1),
)
TOURNAMENT = tuple((n, o, 2, False) for n, o in (
    ("away_goals", 0x4A), ("substitutes_used", 0x4C),
    ("substitutes_bench", 0x4E), ("stage_count", 0x52),
    ("stage_index", 0x54), ("competition_complete", 0x58),
))
TOURNAMENT_ARRAYS = (
    ("team_order", 0x5A, 64, 1), ("team_keys", 0x9A, 64, 2),
    ("group_by_team_slot", 0x11A, 64, 1),
)
STAGE = tuple((n, o, 2, False) for n, o in (
    ("unknown_00", 0), ("playoff_flag", 2), ("group_mode_count", 4),
    ("seeded", 6), ("participants", 8), ("qualifiers", 10),
    ("repeat_count", 12), ("points_for_win", 14), ("group_count", 16),
    ("teams_per_group", 18), ("legs", 20), ("extra_time", 22), ("penalties", 24),
    ("matchday_count", 26),
))
CALENDAR_START = 0x11E4C
CALENDAR_END = 0x16C7A
CALENDAR_HEADER = (
    ("competition_slot", 0, 1, False), ("date_eighth_month", 1, 1, False),
    ("byte_size", 2, 2, False), ("inactive", 4, 1, False),
    ("match_count", 5, 1, False), ("matches_remaining", 6, 1, False),
    ("round_stage_index", 7, 1, False), ("phase", 8, 1, False),
    ("display_selector", 9, 1, False),
)
CALENDAR_MATCH = (
    ("control_mode", 0, 1, False), ("result_flags", 1, 1, False),
    ("home_team_key", 2, 2, False), ("away_team_key", 4, 2, False),
    ("score_d4", 6, 2, False), ("score_d5", 8, 2, False), ("score_d6", 10, 2, False),
)
CAREER_GLOBALS = (
    ("cached_team_count", 0, 2, False), ("managed_team_key", 0xD748, 2, False),
    ("calendar_index", 0x11E44, 2, False), ("calendar_byte_offset", 0x11E46, 2, False),
    ("calendar_entry_count", 0x11E48, 2, False),
    ("calendar_round_complete", 0x11E4A, 2, False),
)


def _hex(value: str, length: int | None = None) -> bytes:
    try:
        raw = bytes.fromhex(value)
    except (ValueError, TypeError) as exc:
        raise ValueError("baseline must contain hexadecimal bytes") from exc
    if length is not None and len(raw) != length:
        raise ValueError(f"baseline must contain exactly {length} bytes")
    return raw


def _number(value: Any, size: int, signed: bool = False) -> bytes:
    if type(value) is not int:
        raise ValueError("numeric fields must be integers")
    try:
        return value.to_bytes(size, "big", signed=signed)
    except OverflowError as exc:
        raise ValueError(f"number {value} does not fit its {size}-byte field") from exc


def _fields(raw: bytes, specification: tuple) -> dict:
    return {name: int.from_bytes(raw[offset:offset + size], "big", signed=signed)
            for name, offset, size, signed in specification}


def _overlay(raw: bytearray, values: dict, specification: tuple) -> None:
    for name, offset, size, signed in specification:
        raw[offset:offset + size] = _number(values[name], size, signed)


def _array(value: Any, size: int, name: str) -> list:
    if not isinstance(value, list) or len(value) != size:
        raise ValueError(f"{name} must contain exactly {size} entries")
    return value


def read_state(raw: bytes) -> dict:
    """Read saved or nested expanded state, retaining unused union storage."""
    if len(raw) not in (0x444, 0x734, STATE_SIZE):
        raise ValueError("expanded state must contain $444, $734 or $B54 bytes")
    result = {"baseline_hex": raw.hex(), "common": _fields(raw, COMMON),
              "name": raw[4:0x28].split(b"\0", 1)[0].decode("latin-1")}
    kind = result["common"]["competition_type"]
    if kind == 0 and len(raw) < 0x734 or kind == 2 and len(raw) < STATE_SIZE:
        raise ValueError("expanded state is too short for its declared layout")
    if kind == 0:
        result["league"] = _fields(raw, LEAGUE)
        for name, start, count, width in LEAGUE_ARRAYS:
            result["league"][name] = [int.from_bytes(raw[o:o + width], "big")
                                      for o in range(start, start + count * width, width)]
        result["league"]["standings"] = [
            _fields(raw[0x2B4 + 18 * i:], STANDING) for i in range(64)]
    elif kind == 1:
        result["cup"] = _fields(raw, CUP)
        for name, start, count, width in CUP_ARRAYS:
            result["cup"][name] = [int.from_bytes(raw[o:o + width], "big")
                                  for o in range(start, start + count * width, width)]
        result["cup"]["team_offsets"] = [int.from_bytes(raw[o:o + 4], "big", signed=True)
                                         for o in range(0x344, 0x444, 4)]
        result["cup"]["rounds"] = [
            {name: int.from_bytes(raw[offset + i * 2:offset + i * 2 + 2], "big")
             for name, offset in (("legs", 0x66), ("extra_time", 0x72), ("penalties", 0x7E))}
            for i in range(6)]
    elif kind == 2:
        result["tournament"] = _fields(raw, TOURNAMENT)
        result["tournament"]["stage_complete_byte"] = raw[0x56]
        for name, start, count, width in TOURNAMENT_ARRAYS:
            result["tournament"][name] = [int.from_bytes(raw[o:o + width], "big")
                                         for o in range(start, start + count * width, width)]
        result["tournament"]["stages"] = [
            dict(_fields(raw[0x15A + i * 0x76:], STAGE),
                 matchday_dates=list(raw[0x176 + i * 0x76:0x1D0 + i * 0x76]))
            for i in range(6)]
        # The embedded union is one active league/cup, not six result archives.
        nested = raw[0x420:]
        if int.from_bytes(nested[:2], "big") in (0, 1):
            result["tournament"]["active_stage_state"] = read_state(nested)
    return result


def write_state(state: dict) -> bytes:
    raw = bytearray(_hex(state["baseline_hex"]))
    if len(raw) not in (0x444, 0x734, STATE_SIZE):
        raise ValueError("expanded state must contain $444, $734 or $B54 bytes")
    _overlay(raw, state["common"], COMMON)
    name = state["name"]
    if not isinstance(name, str) or "\0" in name:
        raise ValueError("name must be text without NUL")
    original = bytes(raw[4:0x28]).split(b"\0", 1)[0].decode("latin-1")
    if name != original:
        try:
            encoded = name.encode("latin-1")
        except UnicodeEncodeError as exc:
            raise ValueError("name is not Latin-1 encodable") from exc
        if len(encoded) >= 36:
            raise ValueError("name exceeds its 36-byte storage field including NUL")
        raw[4:0x28] = encoded.ljust(36, b"\0")
    kind = state["common"]["competition_type"]
    if kind == 0 and len(raw) < 0x734 or kind == 2 and len(raw) < STATE_SIZE:
        raise ValueError("expanded state is too short for its declared layout")
    if kind == 0:
        _overlay(raw, state["league"], LEAGUE)
        for name, start, count, width in LEAGUE_ARRAYS:
            for i, value in enumerate(_array(state["league"][name], count, name)):
                offset = start + i * width
                raw[offset:offset + width] = _number(value, width)
        for i, standing in enumerate(_array(state["league"]["standings"], 64, "standings")):
            start = 0x2B4 + 18 * i
            part = raw[start:start + 18]
            _overlay(part, standing, STANDING)
            raw[start:start + 18] = part
    elif kind == 1:
        _overlay(raw, state["cup"], CUP)
        for name, start, count, width in CUP_ARRAYS:
            for i, value in enumerate(_array(state["cup"][name], count, name)):
                offset = start + i * width
                raw[offset:offset + width] = _number(value, width)
        for i, value in enumerate(_array(state["cup"]["team_offsets"], 64, "team_offsets")):
            raw[0x344 + 4*i:0x348 + 4*i] = _number(value, 4, True)
        for i, row in enumerate(_array(state["cup"]["rounds"], 6, "rounds")):
            for name, offset in (("legs", 0x66), ("extra_time", 0x72), ("penalties", 0x7E)):
                raw[offset + 2 * i:offset + 2 * i + 2] = _number(row[name], 2)
    elif kind == 2:
        _overlay(raw, state["tournament"], TOURNAMENT)
        raw[0x56] = _number(state["tournament"]["stage_complete_byte"], 1)[0]
        for name, start, count, width in TOURNAMENT_ARRAYS:
            for i, value in enumerate(_array(state["tournament"][name], count, name)):
                offset = start + i * width
                raw[offset:offset + width] = _number(value, width)
        for i, stage in enumerate(_array(state["tournament"]["stages"], 6, "stages")):
            start = 0x15A + i * 0x76
            part = raw[start:start + 0x76]
            _overlay(part, stage, STAGE)
            part[0x1C:] = b"".join(_number(n, 1) for n in
                                   _array(stage["matchday_dates"], 90, "matchday_dates"))
            raw[start:start + 0x76] = part
        if "active_stage_state" in state["tournament"]:
            nested = write_state(state["tournament"]["active_stage_state"])
            if len(nested) != 0x734:
                raise ValueError("embedded tournament union must contain $734 bytes")
            raw[0x420:] = nested
    return bytes(raw)


def league_fixture_pairs(image: bytes, teams_per_group: int, *, image_base: int = 0x100000,
                         special_european_table: bool = False) -> list[tuple[int, int]]:
    """Read native pair order from unpacked SWOS2; no fixture data is embedded.

    The standard table covers 2..24 teams. Descriptor IDs 21 and 22 select the
    separate four-team table; callers must select that explicitly. image_base
    describes the pointers in the supplied image (unrelocated default $100000).
    """
    if type(teams_per_group) is not int or not 2 <= teams_per_group <= 24:
        raise ValueError("fixture table supports 2..24 teams per group")
    if special_european_table:
        if teams_per_group != 4:
            raise ValueError("special European fixture table requires four teams")
        start = 0x533B4
    else:
        offset = 0x53358 + 4 * (teams_per_group - 2)
        if offset + 4 > len(image):
            raise ValueError("executable is shorter than the fixture pointer table")
        start = int.from_bytes(image[offset:offset + 4], "big") - image_base
    size = teams_per_group * (teams_per_group - 1)
    if start < 0 or start + size > len(image):
        raise ValueError("fixture pointer lies outside the supplied executable")
    pairs = [(image[o], image[o + 1]) for o in range(start, start + size, 2)]
    if any(a == b or max(a, b) >= teams_per_group for a, b in pairs):
        raise ValueError("fixture pair is invalid for the selected team count")
    return pairs


def next_league_fixture(state: dict, image: bytes, *, image_base: int = 0x100000) -> dict | None:
    """Resolve the current native cursor to saved team keys/offsets, read-only."""
    league = state["league"]
    if league["repeats_remaining"] == 0:
        return None
    n = league["teams_per_group"]
    pairs = league_fixture_pairs(image, n, image_base=image_base,
                                 special_european_table=state["common"]["descriptor_id"] in (21, 22))
    index = league["pair_index"]
    group = league["group_index"]
    if not 0 <= index < len(pairs) or not 0 <= group < league["group_count"]:
        raise ValueError("league fixture cursor is out of range")
    a, b = pairs[index]
    slots = [group * n + a, group * n + b]
    if max(slots) >= 64:
        raise ValueError("league group exceeds its 64 saved team slots")
    rows = [league["team_order"][slot] for slot in slots]
    if max(rows) >= 64:
        raise ValueError("league team-order index is out of range")
    if league["repeats_remaining"] & 1:
        rows.reverse()
    result = {}
    for side, row in zip(("home", "away"), rows):
        result[side] = {"row": row, "team_key": league["team_keys"][row],
                        "team_offset": league["standings"][row]["team_offset"]}
    return result


def tournament_stage_matchdays(stage: dict) -> int:
    """Return the native schedule constructor's count for a configured stage.

    This validates shape operands used in the count; it does not validate the
    entire tournament chain, team allocation, seeding or qualifier policy.
    """
    if stage["group_mode_count"]:
        n, groups, repeats = (stage[key] for key in
                              ("teams_per_group", "group_count", "repeat_count"))
        if not (type(n) is int and 2 <= n <= 24 and
                type(groups) is int and 1 <= groups <= 8 and
                type(repeats) is int and 1 <= repeats <= 4):
            raise ValueError("groups need 2..24 teams, 1..8 groups and 1..4 repetitions")
        if stage["participants"] != groups * n or stage["group_mode_count"] != groups:
            raise ValueError("stage participants/group fields disagree")
        return ((n * (n - 1) // 2) // (n // 2)) * repeats
    if stage["legs"] not in (1, 2) or stage["penalties"] not in (0, 1, 2):
        raise ValueError("knockout legs/penalty rule outside the native domain")
    return 1 if stage["legs"] == 1 and stage["penalties"] == 1 else 2


def validate_tournament_schedule_capacity(state: dict) -> list[str]:
    """Check constructor operands and each stage's 90 exclusive date bytes.

    Kept separate from lossless decoding/encoding. The native constructor has
    no per-stage write bound; 23/24-team groups repeated four times produce 92
    dates and spill into the next stage's first word (or final padding).
    Other native tournament constraints must still be checked by the caller.
    """
    tournament = state["tournament"]
    count = tournament["stage_count"]
    if type(count) is not int or not 1 <= count <= 6:
        return ["stage_count must be 1..6"]
    stages = tournament["stages"]
    if not isinstance(stages, list) or len(stages) != 6:
        return ["tournament must retain all six stage slots"]
    errors = []
    for index, stage in enumerate(stages[:count]):
        try:
            days = tournament_stage_matchdays(stage)
        except (KeyError, TypeError, ValueError) as exc:
            errors.append(f"stage {index + 1}: {exc}")
            continue
        if days > 90:
            errors.append(f"stage {index + 1}: {days} dates exceed 90 exclusive bytes")
    return errors


def read_career_prefix(raw: bytes) -> dict:
    """Decode confirmed prefix structures; calendar must be structurally valid.

    All80 cached records and both32-player squads are preserved, including unused
    slots. Inactive squad count words may be uninitialized. No roster or calendar
    reconstruction is performed. write_career_prefix requires this raw baseline.
    """
    if len(raw) != CAREER_PREFIX_SIZE:
        raise ValueError("career prefix must contain $16C7C bytes")
    result = {"globals": _fields(raw, CAREER_GLOBALS),
              "cached_teams": [team_data.read_team(raw[2 + i * 684:2 + (i + 1) * 684])
                               for i in range(80)], "squads": [], "calendar": []}
    for base, lineup, count in ((0xDB7E, 0xDB5E, 0xE08A), (0xF0AA, 0xF5B6, 0xF5D6)):
        result["squads"].append({
            "team": team_data.read_team(raw[base:base + 684]),
            "extra_players": [team_data.read_player(raw[o:o + 38])
                              for o in range(base + 684, base + 0x50C, 38)],
            "lineup": list(raw[lineup:lineup + 32]),
            "active_count": int.from_bytes(raw[count:count + 2], "big"),
        })
    offset = CALENDAR_START
    for _ in range(result["globals"]["calendar_entry_count"]):
        if offset + 10 > CALENDAR_END:
            raise ValueError("calendar header exceeds its arena")
        row = _fields(raw[offset:], CALENDAR_HEADER)
        size = row["byte_size"]
        if size < 10 or (size - 10) % 12 or offset + size > CALENDAR_END:
            raise ValueError("calendar entry size is invalid")
        capacity = (size - 10) // 12
        if row["match_count"] > capacity:
            raise ValueError("populated calendar match count exceeds capacity")
        row["matches"] = [_fields(raw[o:], CALENDAR_MATCH)
                          for o in range(offset + 10, offset + size, 12)]
        result["calendar"].append(row)
        offset += size
    return result


def write_career_prefix(state: dict, baseline: bytes) -> bytes:
    original = read_career_prefix(baseline)
    raw = bytearray(baseline)
    _overlay(raw, state["globals"], CAREER_GLOBALS)
    if state["globals"]["calendar_entry_count"] != original["globals"]["calendar_entry_count"]:
        raise ValueError("calendar count changes require native reconstruction")
    for i, team in enumerate(_array(state["cached_teams"], 80, "cached_teams")):
        raw[2 + i * 684:2 + (i + 1) * 684] = team_data.write_team(team)
    for squad, (base, lineup, count) in zip(_array(state["squads"], 2, "squads"),
            ((0xDB7E, 0xDB5E, 0xE08A), (0xF0AA, 0xF5B6, 0xF5D6))):
        raw[base:base + 684] = team_data.write_team(squad["team"])
        for i, player in enumerate(_array(squad["extra_players"], 16, "extra_players")):
            start = base + 684 + i * 38
            raw[start:start + 38] = team_data.write_player(player)
        raw[lineup:lineup + 32] = b"".join(_number(n, 1) for n in _array(squad["lineup"], 32, "lineup"))
        raw[count:count + 2] = _number(squad["active_count"], 2)
    offset = CALENDAR_START
    rows = _array(state["calendar"], len(original["calendar"]), "calendar")
    for row, old in zip(rows, original["calendar"]):
        size = old["byte_size"]
        if row["byte_size"] != size:
            raise ValueError("calendar size changes require native reconstruction")
        part = raw[offset:offset + size]
        _overlay(part, row, CALENDAR_HEADER)
        for i, match in enumerate(_array(row["matches"], len(old["matches"]), "matches")):
            start = 10 + i * 12
            entry = part[start:start + 12]
            _overlay(entry, match, CALENDAR_MATCH)
            part[start:start + 12] = entry
        raw[offset:offset + size] = part
        offset += size
    read_career_prefix(bytes(raw))  # Recheck written bounds/counts, not gameplay legality.
    return bytes(raw)


def decode(raw: bytes, *, kind: str = "diy", career_details: bool = False) -> dict:
    if kind not in ("diy", "pre", "sea", "car"):
        raise ValueError("kind must be diy, pre, sea or car")
    prefix_size = CAREER_PREFIX_SIZE if kind in ("sea", "car") else 0
    if len(raw) < prefix_size + SAVE_HEADER_SIZE:
        raise ValueError("save is shorter than its fixed header")
    header = raw[prefix_size:prefix_size + SAVE_HEADER_SIZE]
    count_offset = LOADED_COUNT_OFFSET if prefix_size else 0x32
    count = int.from_bytes(header[count_offset:count_offset + 2], "big")
    if len(raw) != prefix_size + SAVE_HEADER_SIZE + count * team_data.TEAM_SIZE:
        raise ValueError("save length disagrees with the writer's team-count field")
    result = {
        "schema": SCHEMA, "kind": kind,
        "career_prefix_hex": raw[:prefix_size].hex(),
        "state": read_state(header[:STATE_SIZE]),
        "globals_b54_b5f_hex": header[STATE_SIZE:USER_TACTICS_OFFSET].hex(),
        "user_tactics": [tactic_data.read_tactic(header[start:start + 370])
                         for start in range(USER_TACTICS_OFFSET, 0x140C, 370)],
        "globals_140c_141d_hex": header[0x140C:COMPATIBILITY_OFFSET].hex(),
        "compatibility": _fields(header, (
            ("version", 0x141E, 2, False), ("identity_0", 0x1420, 4, False),
            ("identity_1", 0x1424, 4, False), ("identity_2", 0x1428, 4, False),
            ("executable_base", 0x142C, 4, False))),
        "loaded_team_count": int.from_bytes(header[0x1430:0x1432], "big"),
        "teams": [team_data.read_team(raw[start:start + team_data.TEAM_SIZE])
                  for start in range(prefix_size + SAVE_HEADER_SIZE, len(raw), team_data.TEAM_SIZE)],
    }
    if career_details:
        if not prefix_size:
            raise ValueError("career details require a SEA or CAR payload")
        result["career_state"] = read_career_prefix(raw[:prefix_size])
    return result


def encode(document: dict) -> bytes:
    if document["schema"] != SCHEMA:
        raise ValueError(f"expected schema {SCHEMA!r}")
    if document["kind"] == "builtin-definitions":
        records = _array(document["definitions"], 162, "definitions")
        parts = [write_definition(record) for record in records]
        for i, (part, start, end) in enumerate(zip(parts, BUILTIN_OFFSETS, BUILTIN_OFFSETS[1:] + (BUILTIN_END,))):
            if len(part) != end - start:
                raise ValueError(f"definition {i} changed size")
        return b"".join(parts)
    kind = document["kind"]
    if kind not in ("diy", "pre", "sea", "car"):
        raise ValueError("unsupported save kind")
    prefix = _hex(document["career_prefix_hex"], CAREER_PREFIX_SIZE if kind in ("sea", "car") else 0)
    if "career_state" in document:
        prefix = write_career_prefix(document["career_state"], prefix)
    header = write_state(document["state"])
    header += _hex(document["globals_b54_b5f_hex"], 12)
    header += b"".join(tactic_data.write_tactic(t)
                       for t in _array(document["user_tactics"], 6, "user_tactics"))
    header += _hex(document["globals_140c_141d_hex"], 18)
    compat = document["compatibility"]
    header += _number(compat["version"], 2)
    header += b"".join(_number(compat[key], 4) for key in
                       ("identity_0", "identity_1", "identity_2", "executable_base"))
    header += _number(document["loaded_team_count"], 2)
    assert len(header) == SAVE_HEADER_SIZE
    teams = document["teams"]
    if not isinstance(teams, list):
        raise ValueError("teams must be an array")
    count = document["loaded_team_count"] if prefix else document["state"]["common"]["team_count"]
    if count != len(teams):
        raise ValueError("team array length disagrees with the writer's count; counts are not silently changed")
    return prefix + header + b"".join(team_data.write_team(team) for team in teams)


def _round(raw: int) -> dict:
    return {"legs": raw >> 6, "extra_time": (raw >> 4) & 3,
            "penalties": (raw >> 2) & 3, "unknown_low_bits": raw & 3}


def _pack_round(row: dict) -> int:
    value = 0
    for name in ("legs", "extra_time", "penalties", "unknown_low_bits"):
        n = row[name]
        if type(n) is not int or not 0 <= n <= 3:
            raise ValueError(f"{name} must fit two bits")
        value = (value << 2) | n
    return value


def read_definition(raw: bytes) -> dict:
    """Read one compact builtin descriptor including its preserved auxiliary tail."""
    if len(raw) < 14 or raw[1] > 2:
        raise ValueError("invalid compact descriptor header")
    result = {"baseline_hex": raw.hex(), "id": raw[0], "type": raw[1],
              "country": raw[2], "season_start": raw[3], "season_end": raw[4],
              "name_table_relative_byte": raw[5], "team_list_relative_byte": raw[7]}
    kind = raw[1]
    subs_offset = 13 if kind == 2 else 12
    result["substitutes_used"] = raw[subs_offset] >> 4
    result["substitutes_bench"] = raw[subs_offset] & 15
    if kind == 0:
        count = raw[9]
        if 13 + count * 6 > len(raw):
            raise ValueError("division records exceed descriptor region")
        result.update(repeat_byte=raw[10], points_for_win=raw[11], divisions=[
            dict(zip(("teams", "promoted", "promotion_playoff_byte", "relegated",
                      "relegation_playoff_byte", "unknown_05"), raw[13 + i * 6:19 + i * 6]))
            for i in range(count)])
    elif kind == 1:
        count = max(0, raw[10].bit_length() - 1)
        if 14 + count > len(raw):
            raise ValueError("round rules exceed descriptor region")
        result.update(teams=raw[10], away_goals=raw[11], initial_round_number=raw[13],
                      rounds=[_round(v) for v in raw[14:14 + count]])
    else:
        count = raw[14]
        if not 1 <= count <= 6 or 34 + count > len(raw):
            raise ValueError("stage rules exceed descriptor region")
        result.update(away_goals=raw[10], repeat_count=raw[11], points_for_win=raw[12],
                      stage_chain=list(raw[15:16 + 3 * count]),
                      rounds=[_round(v) for v in raw[34:34 + count]])
    return result


def write_definition(definition: dict) -> bytes:
    raw = bytearray(_hex(definition["baseline_hex"]))
    baseline = read_definition(raw)
    kind = definition["type"]
    if kind != baseline["type"]:
        raise ValueError("descriptor type conversion requires rebuilding its layout")
    for name, offset in (("id", 0), ("type", 1), ("country", 2), ("season_start", 3),
                         ("season_end", 4), ("name_table_relative_byte", 5), ("team_list_relative_byte", 7)):
        raw[offset] = _number(definition[name], 1)[0]
    subs = [definition[key] for key in ("substitutes_used", "substitutes_bench")]
    if any(type(n) is not int or not 0 <= n <= 15 for n in subs):
        raise ValueError("substitute counts must fit nibbles")
    raw[13 if kind == 2 else 12] = (subs[0] << 4) | subs[1]
    if kind == 0:
        raw[10] = _number(definition["repeat_byte"], 1)[0]
        raw[11] = _number(definition["points_for_win"], 1)[0]
        rows = _array(definition["divisions"], len(baseline["divisions"]), "divisions")
        for i, row in enumerate(rows):
            raw[13 + 6 * i:19 + 6 * i] = b"".join(_number(row[key], 1) for key in
                ("teams", "promoted", "promotion_playoff_byte", "relegated", "relegation_playoff_byte", "unknown_05"))
    elif kind == 1:
        raw[10] = _number(definition["teams"], 1)[0]
        raw[11] = _number(definition["away_goals"], 1)[0]
        raw[13] = _number(definition["initial_round_number"], 1)[0]
        rows = _array(definition["rounds"], len(baseline["rounds"]), "rounds")
        if max(0, raw[10].bit_length() - 1) != len(rows):
            raise ValueError("team-count edit changes the compact round-array layout")
        raw[14:14 + len(rows)] = bytes(_pack_round(row) for row in rows)
    else:
        for name, offset in (("away_goals", 10), ("repeat_count", 11), ("points_for_win", 12)):
            raw[offset] = _number(definition[name], 1)[0]
        chain = _array(definition["stage_chain"], len(baseline["stage_chain"]), "stage_chain")
        raw[15:15 + len(chain)] = b"".join(_number(n, 1) for n in chain)
        rows = _array(definition["rounds"], len(baseline["rounds"]), "rounds")
        raw[34:34 + len(rows)] = bytes(_pack_round(row) for row in rows)
    return bytes(raw)


def decode_builtins(image: bytes) -> dict:
    if len(image) < BUILTIN_END:
        raise ValueError("input must be the unpacked SWOS2 image, not an RNC stream")
    records = []
    for ident, start, end in zip(range(162), BUILTIN_OFFSETS, BUILTIN_OFFSETS[1:] + (BUILTIN_END,)):
        raw = image[start:end]
        if raw[0] != ident:
            raise ValueError(f"descriptor {ident} ID mismatch; wrong executable or release")
        records.append(read_definition(raw))
    return {"schema": SCHEMA, "kind": "builtin-definitions", "definitions": records}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("decode", "builtins", "encode"):
        sub = commands.add_parser(command)
        sub.add_argument("source", type=Path)
        sub.add_argument("output", type=Path)
        if command == "decode":
            sub.add_argument("--kind", choices=("diy", "pre", "sea", "car"), default="diy")
            sub.add_argument("--career-details", action="store_true",
                             help="decode confirmed calendar, cache and expanded-squad views")
    args = parser.parse_args()
    try:
        if args.command == "encode":
            result = encode(json.loads(args.source.read_text(encoding="utf-8")))
        else:
            raw = args.source.read_bytes()
            document = decode_builtins(raw) if args.command == "builtins" else decode(
                raw, kind=args.kind, career_details=args.career_details)
            result = (json.dumps(document, ensure_ascii=True, indent=2) + "\n").encode()
        if args.output.resolve() == args.source.resolve():
            raise ValueError("input and output must be different paths")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
    except (ValueError, KeyError, TypeError, OSError) as exc:
        parser.exit(1, f"competition_data: {exc}\n")


if __name__ == "__main__":
    main()
