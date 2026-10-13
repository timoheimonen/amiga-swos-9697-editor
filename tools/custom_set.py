#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""The custom set CUSTOMS.EDT on the host: the editors' rules in Python.

The in-game team editor (src/editor/editors/) and the host tools (patch.py
import) apply the same rules; this module is their host reference. Every
team of the game's own database passes its checks unchanged, and its results
match the values the in-game editor produces:

* team_validate: the checks team OK makes before it commits a team and its
  players, with the same reasons;
* to_keeper / to_outfield: the goalkeeper conversion of the player screen;
* paste_player: COPY/PASTE PLAYER;
* team_strength / strength_line: the strength summary of TEAM SETTINGS;
* set_fingerprint: the custom-set CRC-32;
* save_custom_set: the save into a save directory, backup first so that a
  failed save keeps the previous set: a verified CUSTOMS.BAK of the previous
  file (only of a whole set: a cut file leaves the backup as it is), then
  CUSTOMS.EDT read back and compared; nothing is ever deleted.

Records are bytes in the layout of tools/team_data.py (TEAM_SIZE-byte teams,
PLAYER_SIZE-byte players).
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

TEAM_SIZE = 0x2AC
PLAYER_SIZE = 0x26
PLAYERS = 0x4C
PLAYER_COUNT = 16
LINEUP = 0x3C
TACTIC = 0x18
HOME_KIT, AWAY_KIT = 0x1A, 0x1F
FLAGS, SKILLS, RATING = 0x1A, 0x1C, 0x20
SKILL_BITS = 0x0FFFFFFF
KEEPER_RATING_MAX = 38
KEEPER_RATING_KEPT_MAX = 40
NATIONALITIES = 153
CUSTOM_SET_NAME = "CUSTOMS.EDT"
BACKUP_NAME = "CUSTOMS.BAK"

REASONS = {
    "kit": "A KIT VALUE IS OUT OF RANGE.",
    "tactic": "THE DEFAULT TACTIC IS NOT AVAILABLE.",
    "lineup": "THE LINEUP NAMES A PLAYER TWICE.",
    "keeper": "THE LINEUP HAS NO GOALKEEPER IN GOAL.",
    "shirts": "SHIRT NUMBERS MUST BE 1-16, EACH ONCE.",
    "nationality": "THE NATIONALITY IS OUT OF RANGE.",
    "appearance": "THE APPEARANCE IS OUT OF RANGE.",
    "keeper_skills": "A GOALKEEPER HAS OUTFIELD SKILLS.",
    "keeper_rating": "THE GOALKEEPER RATING IS ABOVE 38.",
    "rating": "THE RATING DIFFERS FROM THE SKILLS.",
}


class SaveError(Exception):
    """A failed step of save_custom_set; the previous file is intact."""

    def __init__(self, step: str, detail: str):
        super().__init__(f"{step}: {detail}")
        self.step = step


def player(team: bytes, slot: int) -> bytes:
    return team[PLAYERS + slot * PLAYER_SIZE:PLAYERS + (slot + 1) * PLAYER_SIZE]


def skills(record: bytes) -> int:
    return struct.unpack_from(">I", record, SKILLS)[0]


def rating_sum(skill_long: int) -> int:
    return sum((skill_long >> (4 * i)) & 7 for i in range(7))


def is_keeper(record: bytes) -> bool:
    return record[FLAGS] >> 5 == 0


def team_validate(team: bytes, original: bytes, imported: bytes | None = None,
                  owned: int = 0) -> tuple[str, int] | None:
    """None when team OK may commit the record, else (reason, slot or -1).

    owned is the mask of user-owned tactic slots (bit n = USER A+n): a
    default tactic 12-17 passes while its slot is user-owned."""
    for kit in (HOME_KIT, AWAY_KIT):
        if team[kit] > 3 or max(team[kit + 1:kit + 5]) > 9:
            return REASONS["kit"], -1
    tactic = team[TACTIC]
    if tactic >= 12 and (tactic > 17 or not (owned >> (tactic - 12)) & 1 and (
            tactic != original[TACTIC] and (imported is None or tactic != imported[TACTIC]))):
        return REASONS["tactic"], -1
    lineup = team[LINEUP:LINEUP + 16]
    if sorted(lineup) != list(range(16)):
        return REASONS["lineup"], -1
    if not is_keeper(player(team, lineup[0])):
        return REASONS["keeper"], -1
    if sorted(player(team, slot)[2] for slot in range(16)) != list(range(1, 17)):
        return REASONS["shirts"], -1
    for slot in range(PLAYER_COUNT):
        record = player(team, slot)
        if record[0] >= NATIONALITIES:
            return REASONS["nationality"], slot
        if (record[FLAGS] >> 3) & 3 > 2:
            return REASONS["appearance"], slot
        if is_keeper(record):
            if skills(record) & SKILL_BITS:
                return REASONS["keeper_skills"], slot
            value = record[RATING]
            if value > KEEPER_RATING_MAX:
                kept = value == player(original, slot)[RATING] or (
                    imported is not None and value == player(imported, slot)[RATING])
                if value > KEEPER_RATING_KEPT_MAX or not kept:
                    return REASONS["keeper_rating"], slot
        elif record[RATING] != rating_sum(skills(record)):
            return REASONS["rating"], slot
    return None


def to_keeper(record: bytes) -> tuple[int, int]:
    """(skills, rating) of an outfield player converted to a goalkeeper."""
    value = skills(record)
    return value & ~SKILL_BITS & 0xFFFFFFFF, min(rating_sum(value), KEEPER_RATING_MAX)


def to_outfield(record: bytes) -> tuple[int, int]:
    """(skills, rating) of a goalkeeper converted to an outfield player: the
    rating spread over the seven skills, passing first."""
    value = min(record[RATING], 7 * 7)
    base, extra = divmod(value, 7)
    result = skills(record) & ~SKILL_BITS & 0xFFFFFFFF
    for index in range(7):
        rating = base + (1 if index < extra else 0)
        result |= rating << (4 * (6 - index))
    return result, value


def paste_player(destination: bytes, clipboard: bytes) -> bytes:
    """PASTE PLAYER: name, nationality, position, appearance, skills,
    specialty flags and rating from the clipboard; everything else kept."""
    out = bytearray(destination)
    out[0] = clipboard[0]
    out[3:0x1A] = clipboard[3:0x1A]
    out[FLAGS] = (clipboard[FLAGS] & 0xF8) | (destination[FLAGS] & 0x07)
    value = (skills(destination) & ~SKILL_BITS & 0xFFFFFFFF) | (skills(clipboard) & SKILL_BITS)
    struct.pack_into(">I", out, SKILLS, value)
    out[RATING] = clipboard[RATING] if is_keeper(out) else rating_sum(value)
    return bytes(out)


def skill_values(record: bytes) -> list[int]:
    """The seven skills 0-7 of a player (passing first)."""
    value = skills(record)
    return [(value >> (4 * (6 - index))) & 7 for index in range(7)]


def specialty_flags(record: bytes) -> int:
    """How many of the seven skills carry the specialty flag."""
    value = skills(record)
    return sum((value >> (4 * (6 - index) + 3)) & 1 for index in range(7))


def team_strength(team: bytes) -> dict:
    """The strength summary of TEAM SETTINGS, from the record as it is:

    * average: the average RATING (byte $20, what the player screen shows)
      of the outfield players in lineup roles 2-11, in tenths rounded half
      up, or None without an outfield player there;
    * keeper: the RATING of the player in role 1;
    * skills_eleven / skills_squad: the skill points (the seven skills 0-7)
      of the outfield players of roles 1-11 / of all 16 players;
    * specials_eleven / specials_squad: their specialty flags.

    Goalkeepers' skills are not counted. A lineup value is used as the
    editor uses it, modulo 16."""
    lineup = [value & (PLAYER_COUNT - 1) for value in team[LINEUP:LINEUP + PLAYER_COUNT]]
    eleven = set(lineup[:11])
    ratings = [player(team, slot)[RATING] for slot in lineup[1:11] if not is_keeper(player(team, slot))]
    result = {"average": None, "keeper": player(team, lineup[0])[RATING],
              "skills_eleven": 0, "skills_squad": 0, "specials_eleven": 0, "specials_squad": 0}
    if ratings:
        result["average"] = (20 * sum(ratings) + len(ratings)) // (2 * len(ratings))
    for slot in range(PLAYER_COUNT):
        record = player(team, slot)
        if is_keeper(record):
            continue
        points, flags = sum(skill_values(record)), specialty_flags(record)
        result["skills_squad"] += points
        result["specials_squad"] += flags
        if slot in eleven:
            result["skills_eleven"] += points
            result["specials_eleven"] += flags
    return result


def average_text(tenths: int | None) -> str:
    """An average in tenths with one decimal, '-' for none."""
    return "-" if tenths is None else f"{tenths // 10}.{tenths % 10}"


def strength_line(team: bytes) -> str:
    """The strength line TEAM SETTINGS shows (src/editor/editors/settings.s),
    e.g. AVG 31.4  GK 28  SKILLS 314/451  SPECIAL 14/20."""
    s = team_strength(team)
    return (f"AVG {average_text(s['average'])}  GK {s['keeper']}  "
            f"SKILLS {s['skills_eleven']}/{s['skills_squad']}  "
            f"SPECIAL {s['specials_eleven']}/{s['specials_squad']}")


def set_fingerprint(data: bytes) -> str:
    """The custom-set CRC-32 as the team page shows it."""
    return f"{zlib.crc32(data) & 0xFFFFFFFF:08X}"


def save_custom_set(directory: Path, data: bytes, whole: int | None = None) -> bool:
    """Writes CUSTOMS.EDT into a save directory, backup first so that a
    failed save keeps the previous set. A previous CUSTOMS.EDT whose length
    is not `whole` (when given) is not a whole set and is not backed up, so
    CUSTOMS.BAK keeps what it holds. Returns whether the backup was written.
    Raises SaveError naming the failed step; the previous CUSTOMS.EDT is
    then either untouched (backup step) or kept in a verified CUSTOMS.BAK."""
    if not data:
        raise SaveError("check", "a custom set is never empty")
    target, backup = directory / CUSTOM_SET_NAME, directory / BACKUP_NAME
    backed_up = False
    if target.exists() and (whole is None or target.stat().st_size == whole):
        try:
            previous = target.read_bytes()
            backup.write_bytes(previous)
            if backup.read_bytes() != previous:
                raise SaveError("backup", "CUSTOMS.BAK reads back differently")
        except OSError as exc:
            raise SaveError("backup", str(exc)) from exc
        backed_up = True
    try:
        target.write_bytes(data)
        if target.read_bytes() != data:
            raise SaveError("write", "CUSTOMS.EDT reads back differently")
    except OSError as exc:
        raise SaveError("write", str(exc)) from exc
    return backed_up
