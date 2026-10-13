#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""The match log on the host: records, merging and tables.

With the editor the game appends every match the match engine plays to its
end to MATCHES.LOG in the install's save directory data/, and MACHINE.CFG
there names the install (src/editor/editors/matchlog.s). This module reads
and checks the records, merges the logs of several installs (copies of the
same log included), selects matches and writes the matches, the standings
and the scorers as CSV and a Markdown summary. `patch.py results` exposes it
in the release.

  python3 tools/match_log.py show SWOS/data/MATCHES.LOG
  python3 tools/match_log.py results A/data/MATCHES.LOG B/MATCHES.LOG --out results
  python3 tools/match_log.py results LOGS... --def SWOS/data/LEAGUE.DEF --out results
  python3 tools/match_log.py machine SWOS/data --name "TABLE 2"

Layout (big-endian, as src/editor/include/matchlog.i defines it): records
follow one another without a file header. A record is a 224-byte header, the
scorers (32 bytes each), the goals (4 bytes each) and the CRC-32/ISO-HDLC of
all bytes before it. A reader finds records by their magic SWML, their length
and their CRC-32, so a damaged or cut record costs only itself.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import secrets
import struct
import sys
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

LOG_NAME = "MATCHES.LOG"
MACHINE_NAME = "MACHINE.CFG"

MAGIC = b"SWML"
VERSION = 1
HEADER_SIZE = 0xE0
CRC_SIZE = 4
MIN_SIZE = HEADER_SIZE + CRC_SIZE
SCORER_SIZE = 32
GOAL_SIZE = 4
SCORERS_MAX = 32
GOALS_MAX = 160
MAX_SIZE = HEADER_SIZE + SCORERS_MAX * SCORER_SIZE + GOALS_MAX * GOAL_SIZE + CRC_SIZE

# Header
R_MAGIC, R_VERSION, R_LENGTH, R_INSTALL, R_SEQUENCE = 0x00, 0x04, 0x06, 0x08, 0x0C
R_MACHINE, R_TIME, R_FAMILY, R_FLAGS, R_IDENTITY = 0x10, 0x20, 0x28, 0x2A, 0x2C
R_COMPETITION, R_ROUND, R_TEAMS = 0x4C, 0x74, 0x9C
R_PLAYER_COUNT, R_GOAL_COUNT, R_RESERVED = 0xDC, 0xDD, 0xDE
NAME_FIELD = 40
MACHINE_FIELD = 16
TEAM_SIZE = 32
TEAM_NAME_SIZE = 17
PLAYER_NAME_SIZE = 23

FLAG_EXTRA_TIME, FLAG_PENALTIES, FLAG_SECOND_LEG, FLAG_FORFEIT, FLAG_MINUTES_PARTIAL = 1, 2, 4, 8, 16
FLAG_NAMES = {FLAG_EXTRA_TIME: "extra_time", FLAG_PENALTIES: "penalties", FLAG_SECOND_LEG: "second_leg",
              FLAG_FORFEIT: "forfeit", FLAG_MINUTES_PARTIAL: "minutes_partial"}
FAMILIES = ("friendly", "diy", "preset", "season", "career")
SOURCES = ("database", "custom_set")
CONTROLS = {0: "none", 1: "computer", 2: "player_coach", 3: "coach"}
KINDS = ("normal", "penalty", "own_goal")
CUSTOM_GROUP = 72
NO_MINUTE = 0xFF
NO_SCORER = 0xFF

# MACHINE.CFG
MACHINE_MAGIC = b"SWOSMCH1"
MACHINE_VERSION = 1
MACHINE_SIZE = 0x24
MACHINE_NAME_MAX = 15
DEFAULT_MACHINE = "AMIGA"
MACHINE_GLYPHS = set(" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`{|}~")

DEFAULT_POINTS = 3


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def _text(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("latin-1")


def _field(text: str, size: int) -> bytes:
    raw = text.encode("latin-1")
    if len(raw) >= size:
        raise ValueError(f"{text!r} is longer than {size - 1} characters")
    return raw.ljust(size, b"\0")


# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------
@dataclass
class Team:
    group: int
    ordinal: int
    source: str
    control: str
    name: str
    goals_90: int
    goals: int
    penalties: int
    own_goals: int
    earlier: int
    scorers: int

    @property
    def key(self) -> tuple[int, int]:
        return (self.group, self.ordinal)


@dataclass
class Scorer:
    side: int
    index: int
    slot: int
    shirt: int
    goals: int
    short_name: bool
    name: str


@dataclass
class Goal:
    side: int
    kind: str
    shirt: int
    minute: int | None
    scorer: int | None


@dataclass
class Record:
    install: int
    sequence: int
    machine: str
    time: tuple[int, int, int, int, int, int] | None
    family: str
    flags: int
    database: dict[str, Any]
    custom_set_crc32: str | None
    competition: str
    round: str
    teams: list[Team]
    scorers: list[Scorer]
    goals: list[Goal]
    raw: bytes = field(repr=False, default=b"")
    source: str = ""
    offset: int = 0

    @property
    def identity(self) -> tuple[int, int]:
        return (self.install, self.sequence)

    def flag(self, value: int) -> bool:
        return bool(self.flags & value)

    @property
    def fingerprint(self) -> str:
        db = self.database
        return "ORIGINAL" if db["kind"] == "original" else f"{db['label']} {db['crc32']}"

    def to_json(self) -> dict[str, Any]:
        return {
            "install": f"{self.install:08X}", "sequence": self.sequence, "machine": self.machine,
            "time": (None if self.time is None else
                     "%04d-%02d-%02d %02d:%02d:%02d" % self.time),
            "family": self.family,
            "flags": [name for value, name in FLAG_NAMES.items() if self.flags & value],
            "database": self.database, "custom_set_crc32": self.custom_set_crc32,
            "competition": self.competition, "round": self.round,
            "teams": [team.__dict__ for team in self.teams],
            "scorers": [scorer.__dict__ for scorer in self.scorers],
            "goals": [goal.__dict__ for goal in self.goals],
        }


class RecordError(ValueError):
    pass


def decode_record(raw: bytes) -> Record:
    """One whole record (its exact bytes)."""
    if len(raw) < MIN_SIZE or raw[:4] != MAGIC:
        raise RecordError("not a match log record")
    length = struct.unpack_from(">H", raw, R_LENGTH)[0]
    if length != len(raw) or not MIN_SIZE <= length <= MAX_SIZE:
        raise RecordError(f"length {length} does not fit")
    if crc32(raw[:-CRC_SIZE]) != struct.unpack_from(">I", raw, length - CRC_SIZE)[0]:
        raise RecordError("CRC-32 differs")
    version = struct.unpack_from(">H", raw, R_VERSION)[0]
    if version != VERSION:
        raise RecordError(f"record version {version} is not known")
    players, goals = raw[R_PLAYER_COUNT], raw[R_GOAL_COUNT]
    if players > SCORERS_MAX or goals > GOALS_MAX or \
            HEADER_SIZE + players * SCORER_SIZE + goals * GOAL_SIZE + CRC_SIZE != length:
        raise RecordError("scorer and goal counts do not fit the length")
    install, sequence = struct.unpack_from(">II", raw, R_INSTALL)
    stamp = struct.unpack_from(">HBBBBB", raw, R_TIME)
    family = struct.unpack_from(">H", raw, R_FAMILY)[0]
    flags = struct.unpack_from(">H", raw, R_FLAGS)[0]
    ident = raw[R_IDENTITY:R_IDENTITY + 32]
    kind, generation, manifest = struct.unpack_from(">HHI", ident, 0)
    database = ({"kind": "original"} if kind == 0 else
                {"kind": "edited", "generation": generation, "crc32": f"{manifest:08X}",
                 "label": _text(ident[8:24])})
    custom_flags = struct.unpack_from(">H", ident, 0x1C)[0]
    custom = f"{struct.unpack_from('>I', ident, 0x18)[0]:08X}" if custom_flags & 1 else None
    teams = []
    for side in range(2):
        t = raw[R_TEAMS + side * TEAM_SIZE:R_TEAMS + (side + 1) * TEAM_SIZE]
        teams.append(Team(group=t[0], ordinal=t[1], source=SOURCES[t[2] & 1],
                          control=CONTROLS.get(t[3], str(t[3])), name=_text(t[4:4 + TEAM_NAME_SIZE]),
                          goals_90=t[22], goals=t[23], penalties=t[24], own_goals=t[25], earlier=t[26],
                          scorers=t[27]))
    scorers = []
    offset = HEADER_SIZE
    for _ in range(players):
        s = raw[offset:offset + SCORER_SIZE]
        scorers.append(Scorer(side=s[0] & 1, index=s[1], slot=s[2], shirt=s[3], goals=s[4],
                              short_name=bool(s[5] & 1), name=_text(s[6:6 + PLAYER_NAME_SIZE])))
        offset += SCORER_SIZE
    goal_list = []
    for _ in range(goals):
        side_kind, shirt, minute, scorer = raw[offset:offset + GOAL_SIZE]
        goal_list.append(Goal(side=side_kind & 1, kind=KINDS[(side_kind >> 4) & 3] if (side_kind >> 4) & 3 < 3
                              else "unknown", shirt=shirt,
                              minute=None if minute == NO_MINUTE else minute,
                              scorer=None if scorer == NO_SCORER else scorer))
        offset += GOAL_SIZE
    return Record(install=install, sequence=sequence, machine=_text(raw[R_MACHINE:R_MACHINE + MACHINE_FIELD]),
                  time=None if stamp[0] == 0 else stamp,
                  family=FAMILIES[family] if family < len(FAMILIES) else str(family), flags=flags,
                  database=database, custom_set_crc32=custom,
                  competition=_text(raw[R_COMPETITION:R_COMPETITION + NAME_FIELD]),
                  round=_text(raw[R_ROUND:R_ROUND + NAME_FIELD]), teams=teams, scorers=scorers,
                  goals=goal_list, raw=bytes(raw))


def encode_record(document: dict[str, Any]) -> bytes:
    """A record from the dictionary to_json gives (tests and examples)."""
    raw = bytearray(HEADER_SIZE)
    raw[0:4] = MAGIC
    struct.pack_into(">HHII", raw, R_VERSION, VERSION, 0, int(document["install"], 16), document["sequence"])
    raw[R_MACHINE:R_MACHINE + MACHINE_FIELD] = _field(document["machine"], MACHINE_FIELD)
    if document.get("time"):
        date, clock = document["time"].split()
        year, month, day = map(int, date.split("-"))
        hour, minute, second = map(int, clock.split(":"))
        struct.pack_into(">HBBBBB", raw, R_TIME, year, month, day, hour, minute, second)
    flags = 0
    for value, name in FLAG_NAMES.items():
        if name in document.get("flags", ()):
            flags |= value
    struct.pack_into(">HH", raw, R_FAMILY, FAMILIES.index(document["family"]), flags)
    db = document.get("database", {"kind": "original"})
    if db["kind"] == "edited":
        struct.pack_into(">HHI", raw, R_IDENTITY, 1, db["generation"], int(db["crc32"], 16))
        raw[R_IDENTITY + 8:R_IDENTITY + 24] = db["label"].encode("latin-1").ljust(16, b"\0")
    if document.get("custom_set_crc32"):
        struct.pack_into(">IH", raw, R_IDENTITY + 0x18, int(document["custom_set_crc32"], 16), 1)
    raw[R_COMPETITION:R_COMPETITION + NAME_FIELD] = _field(document.get("competition", ""), NAME_FIELD)
    raw[R_ROUND:R_ROUND + NAME_FIELD] = _field(document.get("round", ""), NAME_FIELD)
    controls = {name: value for value, name in CONTROLS.items()}
    scorers = document.get("scorers", [])
    goals = document.get("goals", [])
    for side, team in enumerate(document["teams"]):
        base = R_TEAMS + side * TEAM_SIZE
        raw[base] = team["group"]
        raw[base + 1] = team["ordinal"]
        raw[base + 2] = SOURCES.index(team.get("source", "custom_set" if team["group"] == CUSTOM_GROUP
                                               else "database"))
        raw[base + 3] = controls[team.get("control", "computer")]
        raw[base + 4:base + 4 + TEAM_NAME_SIZE] = _field(team["name"], TEAM_NAME_SIZE)
        raw[base + 22] = team.get("goals_90", team["goals"])
        raw[base + 23] = team["goals"]
        raw[base + 24] = team.get("penalties", 0)
        raw[base + 25] = team.get("own_goals", 0)
        raw[base + 26] = team.get("earlier", 0)
        raw[base + 27] = team.get("scorers", sum(1 for s in scorers if s["side"] == side))
    raw[R_PLAYER_COUNT], raw[R_GOAL_COUNT] = len(scorers), len(goals)
    for s in scorers:
        raw += bytes([s["side"], s.get("index", 0), s.get("slot", 0), s.get("shirt", 0), s["goals"],
                      1 if s.get("short_name") else 0]) + _field(s["name"], PLAYER_NAME_SIZE) + bytes(3)
    for g in goals:
        minute = g.get("minute")
        scorer = g.get("scorer")
        raw += bytes([g["side"] | KINDS.index(g.get("kind", "normal")) << 4, g.get("shirt", 0),
                      NO_MINUTE if minute is None else minute, NO_SCORER if scorer is None else scorer])
    length = len(raw) + CRC_SIZE
    struct.pack_into(">H", raw, R_LENGTH, length)
    return bytes(raw) + struct.pack(">I", crc32(bytes(raw)))


# ---------------------------------------------------------------------------
# Log files
# ---------------------------------------------------------------------------
@dataclass
class Problem:
    source: str
    offset: int
    length: int
    what: str

    def text(self) -> str:
        return f"{self.source}: {self.length} bytes at offset {self.offset} {self.what}"


def scan_log(data: bytes, source: str = LOG_NAME) -> tuple[list[Record], list[Problem]]:
    """Every sound record of a log in file order, and the stretches that are
    not records: damaged bytes, or a record cut at the end of the file."""
    records: list[Record] = []
    problems: list[Problem] = []
    position, bad_start = 0, None

    def close_bad(end: int, cut: bool = False) -> None:
        nonlocal bad_start
        if bad_start is not None:
            problems.append(Problem(source, bad_start, end - bad_start,
                                    "cut at the end of the file, skipped" if cut else "damaged, skipped"))
            bad_start = None

    while position < len(data):
        record = None
        if data[position:position + 4] == MAGIC and position + 8 <= len(data):
            length = struct.unpack_from(">H", data, position + R_LENGTH)[0]
            if MIN_SIZE <= length <= MAX_SIZE and position + length <= len(data):
                try:
                    record = decode_record(data[position:position + length])
                except RecordError:
                    record = None
        if record is None:
            if bad_start is None:
                bad_start = position
            position += 1
            continue
        close_bad(position)
        record.source, record.offset = source, position
        records.append(record)
        position += len(record.raw)
    if bad_start is not None:
        tail = data[bad_start:]
        cut = tail[:4] == MAGIC and len(tail) >= 8 and \
            len(tail) < struct.unpack_from(">H", tail, R_LENGTH)[0] <= MAX_SIZE
        close_bad(len(data), cut)
    return records, problems


def read_log(path: Path) -> tuple[list[Record], list[Problem]]:
    path = Path(path)
    if path.is_dir():
        path = path / LOG_NAME
    return scan_log(path.read_bytes(), str(path))


@dataclass
class Merged:
    records: list[Record]
    problems: list[Problem]
    duplicates: int
    conflicts: list[tuple[Record, Record]]
    gaps: list[tuple[int, str, int, int]]


def merge(logs: Iterable[tuple[list[Record], list[Problem]]]) -> Merged:
    """Records of several logs once each: a record seen again with the same
    bytes is a duplicate and dropped; the same install and sequence number
    with other bytes is a conflict, and both records stay. Sorted by machine
    name, install and sequence number. Gaps in an install's sequence numbers
    are matches its log does not hold (a failed append, or a log copied
    before them)."""
    seen: dict[tuple[int, int], list[Record]] = {}
    problems: list[Problem] = []
    duplicates = 0
    conflicts: list[tuple[Record, Record]] = []
    for records, found in logs:
        problems.extend(found)
        for record in records:
            known = seen.setdefault(record.identity, [])
            if any(other.raw == record.raw for other in known):
                duplicates += 1
                continue
            if known:
                conflicts.append((known[0], record))
            known.append(record)
    records = sorted((r for group in seen.values() for r in group),
                     key=lambda r: (r.machine, r.install, r.sequence, r.raw))
    gaps = []
    by_install: dict[int, list[int]] = {}
    names: dict[int, str] = {}
    for record in records:
        by_install.setdefault(record.install, []).append(record.sequence)
        names[record.install] = record.machine
    for install, sequences in sorted(by_install.items()):
        ordered = sorted(set(sequences))
        expected = 1
        for value in ordered:
            if value > expected:
                gaps.append((install, names[install], expected, value - 1))
            expected = value + 1
    return Merged(records, problems, duplicates, conflicts, gaps)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
@dataclass
class Selection:
    teams: set[tuple[int, int]] | None = None
    names: set[str] | None = None
    families: set[str] | None = None
    machine: str | None = None
    first: int | None = None
    last: int | None = None
    points: int = DEFAULT_POINTS
    definition: str | None = None

    def accepts(self, record: Record) -> bool:
        if self.families is not None and record.family not in self.families:
            return False
        if self.machine is not None and self.machine.upper() not in (
                record.machine.upper(), f"{record.install:08X}"):
            return False
        if self.first is not None and record.sequence < self.first:
            return False
        if self.last is not None and record.sequence > self.last:
            return False
        for team in record.teams:
            if self.teams is not None and team.key not in self.teams and \
                    (self.names is None or team.name.upper() not in self.names):
                return False
            if self.teams is None and self.names is not None and team.name.upper() not in self.names:
                return False
        return True


def definition_selection(path: Path) -> Selection:
    """The teams and the points rule of a tournament definition (.DEF)."""
    import definition_data
    document = definition_data.decode(Path(path).read_bytes())
    teams = {(p["group"], p["ordinal"]) for p in document["participants"]}
    if not teams:
        raise ValueError(f"{path} lists no teams")
    points = DEFAULT_POINTS
    if document["family"] == "league":
        points = document["league"]["points"]
    elif document["family"] == "tournament":
        points = next((stage["points"] for stage in document["tournament"]["stages"]
                       if stage["points"] in (2, 3)), DEFAULT_POINTS)
    return Selection(teams=teams, points=points, definition=document["name"] or Path(path).name)


def team_list_selection(items: Iterable[str]) -> tuple[set[tuple[int, int]] | None, set[str] | None]:
    """GROUP:ORDINAL keys and team names."""
    keys, names = set(), set()
    for item in items:
        item = item.strip()
        if not item:
            continue
        group, sep, ordinal = item.partition(":")
        if sep and group.isdigit() and ordinal.isdigit():
            keys.add((int(group), int(ordinal)))
        else:
            names.add(item.upper())
    return (keys or None), (names or None)


# ---------------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------------
@dataclass
class Row:
    key: tuple[int, int]
    team: str
    played: int = 0
    wins: int = 0
    draws: int = 0
    losses: int = 0
    goals_for: int = 0
    goals_against: int = 0
    points: int = 0

    @property
    def difference(self) -> int:
        return self.goals_for - self.goals_against


def standings(records: list[Record], points: int = DEFAULT_POINTS) -> list[Row]:
    """The table of the matches, ranked as the game ranks a league (points,
    goal difference, goals scored, team name). The result after extra time
    counts; a penalty shootout does not change it (the matches table shows
    it)."""
    rows: dict[tuple[int, int], Row] = {}
    for record in records:
        home, away = record.teams
        for team in (home, away):
            row = rows.setdefault(team.key, Row(team.key, team.name))
            row.team = team.name
        for team, other in ((home, away), (away, home)):
            row = rows[team.key]
            row.played += 1
            row.goals_for += team.goals
            row.goals_against += other.goals
            if team.goals > other.goals:
                row.wins += 1
                row.points += points
            elif team.goals == other.goals:
                row.draws += 1
                row.points += 1
            else:
                row.losses += 1
    return sorted(rows.values(), key=lambda r: (-r.points, -r.difference, -r.goals_for, r.team, r.key))


@dataclass
class ScorerRow:
    player: str
    team: str
    goals: int


def scorers(records: list[Record]) -> list[ScorerRow]:
    """Goals per player as the game wrote them back after each match (own
    goals are not a player's)."""
    totals: dict[tuple[tuple[int, int], str], int] = {}
    team_names: dict[tuple[int, int], str] = {}
    for record in records:
        for team in record.teams:
            team_names[team.key] = team.name
        for scorer in record.scorers:
            team = record.teams[scorer.side]
            key = (team.key, scorer.name)
            totals[key] = totals.get(key, 0) + scorer.goals
    rows = [ScorerRow(name, team_names[key], goals) for (key, name), goals in totals.items()]
    return sorted(rows, key=lambda r: (-r.goals, r.player, r.team))


def warnings(merged: Merged, selected: list[Record]) -> list[str]:
    lines = [problem.text() for problem in merged.problems]
    for first, second in merged.conflicts:
        lines.append(f"conflict: {first.machine} ({first.install:08X}) sequence {first.sequence} "
                     f"differs between {first.source} and {second.source}; both are kept")
    for install, name, low, high in merged.gaps:
        span = f"{low}" if low == high else f"{low}-{high}"
        lines.append(f"{name} ({install:08X}): sequence {span} not in the logs (matches not logged "
                     "or not copied)")
    sets = sorted({record.fingerprint for record in selected})
    if len(sets) > 1:
        lines.append("the selected matches were played with different databases: " + ", ".join(sets))
    customs = sorted({record.custom_set_crc32 for record in selected if record.custom_set_crc32})
    if len(customs) > 1:
        lines.append("the selected matches were played with different custom sets: " + ", ".join(customs))
    return lines


def _score(record: Record) -> str:
    home, away = record.teams
    return f"{home.goals}-{away.goals}"


def match_rows(records: list[Record]) -> list[list[str]]:
    rows = []
    for r in records:
        home, away = r.teams
        rows.append([r.machine, f"{r.install:08X}", str(r.sequence),
                     "" if r.time is None else "%04d-%02d-%02d %02d:%02d:%02d" % r.time,
                     r.family, r.competition, r.round, home.name, away.name,
                     str(home.goals), str(away.goals),
                     "yes" if r.flag(FLAG_EXTRA_TIME) else "",
                     f"{home.penalties}-{away.penalties}" if r.flag(FLAG_PENALTIES) else "",
                     f"{home.earlier + home.goals}-{away.earlier + away.goals}" if r.flag(FLAG_SECOND_LEG) else "",
                     "yes" if r.flag(FLAG_FORFEIT) else "", r.fingerprint, r.custom_set_crc32 or ""])
    return rows


MATCH_COLUMNS = ["machine", "install", "sequence", "time", "family", "competition", "round", "home",
                 "away", "home_goals", "away_goals", "extra_time", "penalties", "aggregate", "forfeit",
                 "database", "custom_set_crc32"]
STANDING_COLUMNS = ["position", "team", "played", "wins", "draws", "losses", "goals_for", "goals_against",
                    "goal_difference", "points"]
SCORER_COLUMNS = ["position", "player", "team", "goals"]


def standing_rows(rows: list[Row]) -> list[list[str]]:
    return [[str(i + 1), r.team, str(r.played), str(r.wins), str(r.draws), str(r.losses), str(r.goals_for),
             str(r.goals_against), str(r.difference), str(r.points)] for i, r in enumerate(rows)]


def scorer_rows(rows: list[ScorerRow]) -> list[list[str]]:
    return [[str(i + 1), r.player, r.team, str(r.goals)] for i, r in enumerate(rows)]


def csv_text(columns: list[str], rows: list[list[str]]) -> str:
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(columns)
    writer.writerows(rows)
    return out.getvalue()


def _markdown_table(columns: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "|" + "---|" * len(columns)]
    lines += ["| " + " | ".join(cell.replace("|", "/") for cell in row) + " |" for row in rows]
    return lines


@dataclass
class Results:
    matches: list[Record]
    table: list[Row]
    scorers: list[ScorerRow]
    warnings: list[str]
    duplicates: int
    selection: Selection


def results(logs: list[tuple[list[Record], list[Problem]]], selection: Selection) -> Results:
    merged = merge(logs)
    chosen = [record for record in merged.records if selection.accepts(record)]
    return Results(chosen, standings(chosen, selection.points), scorers(chosen),
                   warnings(merged, chosen), merged.duplicates, selection)


def markdown(result: Results) -> str:
    lines = ["# Match results", ""]
    selection = result.selection
    what = [f"{len(result.matches)} matches"]
    if selection.definition:
        what.append(f"definition {selection.definition}")
    what.append(f"{selection.points} points for a win")
    if result.duplicates:
        what.append(f"{result.duplicates} duplicate records dropped")
    lines += [", ".join(what) + ".", ""]
    if result.warnings:
        lines += ["## Warnings", ""] + [f"- {line}" for line in result.warnings] + [""]
    lines += ["## Standings", ""] + _markdown_table(STANDING_COLUMNS, standing_rows(result.table)) + [""]
    lines += ["## Scorers", ""] + _markdown_table(SCORER_COLUMNS, scorer_rows(result.scorers)) + [""]
    short = [[row[0], row[2], row[4], row[5], row[6], row[7], row[8], f"{row[9]}-{row[10]}",
              row[11], row[12], row[14]] for row in match_rows(result.matches)]
    lines += ["## Matches", ""] + _markdown_table(
        ["machine", "sequence", "family", "competition", "round", "home", "away", "score", "extra_time",
         "penalties", "forfeit"], short) + [""]
    return "\n".join(lines)


def result_files(result: Results) -> dict[str, str]:
    """The files of results by name: matches, standings and scorers as CSV
    and the Markdown summary."""
    return {
        "matches.csv": csv_text(MATCH_COLUMNS, match_rows(result.matches)),
        "standings.csv": csv_text(STANDING_COLUMNS, standing_rows(result.table)),
        "scorers.csv": csv_text(SCORER_COLUMNS, scorer_rows(result.scorers)),
        "results.md": markdown(result),
    }


def write_results(result: Results, out: Path) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    files = result_files(result)
    written = []
    for name, text in files.items():
        path = out / name
        path.write_text(text)
        written.append(path)
    return written


# ---------------------------------------------------------------------------
# MACHINE.CFG
# ---------------------------------------------------------------------------
def machine_file(name: str, install: int) -> bytes:
    name = name.upper()
    if not 1 <= len(name) <= MACHINE_NAME_MAX or set(name) - MACHINE_GLYPHS:
        raise ValueError(f"a machine name has 1-{MACHINE_NAME_MAX} characters A-Z, 0-9, space or punctuation")
    if not 0 < install <= 0xFFFFFFFF:
        raise ValueError("an install identity is a non-zero 32-bit value")
    body = MACHINE_MAGIC + struct.pack(">HHI", MACHINE_VERSION, 0, install) + _field(name, MACHINE_FIELD)
    return body + struct.pack(">I", crc32(body))


def read_machine(data: bytes) -> tuple[str, int]:
    if len(data) != MACHINE_SIZE or data[:8] != MACHINE_MAGIC:
        raise ValueError("not a MACHINE.CFG")
    if crc32(data[:-4]) != struct.unpack_from(">I", data, MACHINE_SIZE - 4)[0]:
        raise ValueError("MACHINE.CFG: CRC-32 differs")
    version, _, install = struct.unpack_from(">HHI", data, 8)
    if version != MACHINE_VERSION or install == 0:
        raise ValueError("MACHINE.CFG: unknown version or no identity")
    return _text(data[0x10:0x20]), install


def new_install() -> int:
    while True:
        value = secrets.randbits(32)
        if value:
            return value


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------
def _parse_range(text: str) -> tuple[int | None, int | None]:
    low, sep, high = text.partition("-")
    if not sep:
        return int(low), int(low)
    return (int(low) if low else None), (int(high) if high else None)


def selection(definition: Path | None = None, teams: str | None = None, families: list[str] | None = None,
              machine: str | None = None, sequence: str | None = None, points: int | None = None) -> Selection:
    """The matches results takes: the teams and points of a .DEF, a team
    list (names or GROUP:ORDINAL keys, comma-separated), families, one
    machine and a range FROM-TO of its sequence numbers."""
    chosen = definition_selection(definition) if definition else Selection()
    if teams:
        keys, names = team_list_selection(teams.split(","))
        if keys:
            chosen.teams = (chosen.teams or set()) | keys
        chosen.names = names
    if families:
        chosen.families = set(families)
    if machine:
        chosen.machine = machine
    if sequence:
        if not machine:
            raise ValueError("a sequence range needs a machine")
        chosen.first, chosen.last = _parse_range(sequence)
    if points:
        chosen.points = points
    return chosen


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    show = sub.add_parser("show", help="decode a log as JSON")
    show.add_argument("log", type=Path)
    res = sub.add_parser("results", help="merge logs into matches, standings and scorers")
    res.add_argument("logs", type=Path, nargs="+", help="MATCHES.LOG files or save directories")
    res.add_argument("--out", type=Path, required=True)
    res.add_argument("--def", dest="definition", type=Path, help="select the teams of a .DEF, its points")
    res.add_argument("--teams", help="comma-separated team names or GROUP:ORDINAL keys")
    res.add_argument("--family", action="append", choices=FAMILIES)
    res.add_argument("--machine", help="only this machine (name or install identity)")
    res.add_argument("--sequence", help="sequence numbers FROM-TO (with --machine)")
    res.add_argument("--points", type=int, choices=(2, 3), help="points for a win (default 3 or the .DEF's)")
    mach = sub.add_parser("machine", help="write MACHINE.CFG into a save directory")
    mach.add_argument("data", type=Path)
    mach.add_argument("--name", default=DEFAULT_MACHINE)
    mach.add_argument("--install", help="identity as 8 hexadecimal digits (default: new)")
    args = parser.parse_args(argv)

    if args.command == "show":
        records, problems = read_log(args.log)
        print(json.dumps({"records": [r.to_json() for r in records],
                          "problems": [p.text() for p in problems]}, indent=2))
        return 0
    if args.command == "machine":
        install = int(args.install, 16) if args.install else new_install()
        (args.data / MACHINE_NAME).write_bytes(machine_file(args.name, install))
        print(f"{args.data / MACHINE_NAME}: {args.name.upper()} {install:08X}")
        return 0
    if args.sequence and not args.machine:
        parser.error("--sequence needs --machine")
    chosen = selection(args.definition, args.teams, args.family, args.machine, args.sequence, args.points)
    logs = [read_log(path) for path in args.logs]
    result = results(logs, chosen)
    for path in write_results(result, args.out):
        print(path)
    for line in result.warnings:
        print(f"warning: {line}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
