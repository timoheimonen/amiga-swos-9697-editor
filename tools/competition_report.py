#!/usr/bin/env python3
# SWOS 96-97 In-Game Editors V0.9b
# Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
# Licensed under the MIT License. See the LICENSE file for details.
"""The tables of a competition save: standings, cup results and scorers.

Reads a .DIY (DIY competition), .PRE (preset competition) or .SEA (season)
save as the game wrote it, for reading only, and gives what the game's own
screens show from it:

* standings of a league, or of each group of a tournament's group stage,
  ranked as the game ranks them (points, goal difference, goals scored,
  team name);
* the ties of a cup round, or of a tournament's knockout stage, that the
  save marks as played, with extra time, penalties, away goals, replays
  and first legs where the save records them;
* the scorers of the competition, from each player's goal counter of the
  competition's slot.

What a save does not hold is left out and named in the notes, never
guessed: a league keeps its table but not its single matches, a cup only
the round in play, a tournament only the stage in play.

  python3 tools/competition_report.py SWOS/data/LEAGUE.DIY [SAVE ...] --out RESULTS

Layout (big-endian): a DIY or preset save is the competition state ($B54
bytes) followed by globals and, from $1432, the loaded teams (684-byte team
records, their count at state +$32). A season save starts with the career
part; its competition slots are states at the run-time addresses listed at
$F758 (five BE32, used where the descriptor pointer at $F70C is not zero;
file offset = address - $1D7408) and its teams start at $180AE. Team
references are signed BE32 offsets from the first loaded team.
"""
from __future__ import annotations

import argparse
import csv
import io
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

TEAM_SIZE = 0x2AC
PLAYER_SIZE = 0x26
PLAYERS = 0x4C
PLAYER_COUNT = 16
STATE_SIZE = 0xB54
FAMILY_WORD = 0xB5A
DIY_TEAMS = 0x1432
SEASON_RAM_BASE = 0x1D7408               # run-time address - file offset in a season save
SEASON_DESCRIPTORS = 0xF70C
SEASON_STATES = 0xF758
SEASON_TEAMS = 0x180AE
SEASON_SLOTS = 5
TYPE_LEAGUE, TYPE_CUP, TYPE_TOURNAMENT = 0, 1, 2
TOURNAMENT_STAGE = 0x420                 # the stage in play, in league or cup layout

# Competition state fields.
S_TYPE, S_NAME, S_SLOT, S_TEAMS = 0x00, 0x04, 0x2C, 0x32
S_GROUPS, S_GROUP_TEAMS = 0x50, 0x52
S_RANK = 0x6E                            # 64 BE16 offsets of standings rows, in rank order per group
S_ROWS = 0x2B4                           # 64 standings rows of 18 bytes
ROW_SIZE = 18
# Cup fields.
C_TIES, C_PHASE_TIES, C_ROUND, C_ROUNDS, C_FIRST_ROUND = 0x50, 0x52, 0x58, 0x5A, 0x5C
C_FLAGS, C_SCORE, C_SECOND, C_PENALTIES = 0x8A, 0xCA, 0x14E, 0x1CE
C_PAIRS, C_ENTRANTS = 0x2CE, 0x344
C_LEG, C_LEG_MODE = 0x14A, 0x14C          # leg index 0/1; 2 = two legs
TWO_LEGS = 2
# Tournament fields.
T_STAGES, T_STAGE = 0x52, 0x54

# Result flags of a tie.
F_AWAY_WON, F_DECIDED, F_EXTRA, F_PENALTIES, F_AWAY_GOALS, F_SECOND_LEG, F_REPLAY, F_PLAYED = (
    1, 2, 4, 8, 16, 32, 64, 128)

ROUND_NAMES = ("FIRST ROUND", "SECOND ROUND", "THIRD ROUND", "FOURTH ROUND", "FIFTH ROUND", "SIXTH ROUND")
KINDS = {".DIY": "diy", ".PRE": "pre", ".SEA": "sea"}

STANDING_COLUMNS = ["save", "competition", "stage", "group", "position", "team", "played", "wins", "draws",
                    "losses", "goals_for", "goals_against", "goal_difference", "points"]
TIE_COLUMNS = ["save", "competition", "round", "leg", "home", "away", "home_goals", "away_goals", "extra_time",
               "score_90", "penalties", "aggregate", "away_goals_rule", "replay", "winner", "state"]
SCORER_COLUMNS = ["save", "competition", "position", "player", "team", "goals"]


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def s32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">i", data, offset)[0]


def text(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("latin-1")


@dataclass
class Standing:
    stage: str
    group: str
    position: int
    team: str
    played: int
    wins: int
    draws: int
    losses: int
    goals_for: int
    goals_against: int
    points: int

    @property
    def difference(self) -> int:
        return self.goals_for - self.goals_against


@dataclass
class Tie:
    round: str
    leg: str
    home: str
    away: str
    home_goals: int
    away_goals: int
    extra_time: bool = False
    score_90: str = ""
    penalties: str = ""
    aggregate: str = ""
    away_goals_rule: bool = False
    replay: bool = False
    winner: str = ""
    state: str = ""


@dataclass
class Scorer:
    position: int
    player: str
    team: str
    goals: int


@dataclass
class Competition:
    save: str
    name: str
    kind: str
    standings: list[Standing] = field(default_factory=list)
    ties: list[Tie] = field(default_factory=list)
    scorers: list[Scorer] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


class Teams:
    """The loaded teams of a save and the references to them."""

    def __init__(self, data: bytes, start: int, count: int, cached: bool):
        self.data = data
        self.start = start
        self.count = count
        self.cached = cached                     # a season save: references may name cached teams

    def record(self, offset: int) -> bytes | None:
        """The team record a signed reference names, or None."""
        position = self.start + offset
        if offset >= 0 and offset % TEAM_SIZE == 0 and offset // TEAM_SIZE < self.count:
            return self.data[position:position + TEAM_SIZE]
        if self.cached and 2 <= position and (position - 2) % TEAM_SIZE == 0 \
                and position + TEAM_SIZE <= len(self.data):
            return self.data[position:position + TEAM_SIZE]
        return None

    def name(self, offset: int) -> str | None:
        record = self.record(offset)
        return None if record is None else text(record[5:0x16])

    def loaded(self) -> list[bytes]:
        return [self.data[self.start + i * TEAM_SIZE:self.start + (i + 1) * TEAM_SIZE] for i in range(self.count)]


# ---------------------------------------------------------------------------
# Standings
# ---------------------------------------------------------------------------
def _ranks_before(state: bytes, teams: Teams, row_a: int, row_b: int) -> bool:
    """True when standings row b ranks before row a (the game swaps them)."""
    a, b = S_ROWS + row_a, S_ROWS + row_b
    points_a, points_b = u16(state, a + 16), u16(state, b + 16)
    if points_a != points_b:
        return points_b > points_a
    difference_a = ((u16(state, a + 12) - u16(state, a + 14)) & 0xFFFF) ^ 0x8000
    difference_b = ((u16(state, b + 12) - u16(state, b + 14)) & 0xFFFF) ^ 0x8000
    if difference_a != difference_b:
        return difference_b > difference_a
    goals_a, goals_b = u16(state, a + 12), u16(state, b + 12)
    if goals_a != goals_b:
        return goals_b > goals_a
    name_a = teams.record(s32(state, a))
    name_b = teams.record(s32(state, b))
    if name_a is None or name_b is None:
        return False
    first, second = name_a[5:], name_b[5:]
    for index, byte in enumerate(first):
        if byte == 0 or byte < second[index]:
            return False
        if byte > second[index]:
            return True
    return False


def standings(state: bytes, teams: Teams, stage: str, notes: list[str]) -> list[Standing]:
    """The table (or the group tables) of a league-layout state, ranked as
    the game ranks it: an exchange sort of each group's slice of the rank
    list by points, goal difference, goals scored and team name."""
    groups, per_group = u16(state, S_GROUPS), u16(state, S_GROUP_TEAMS)
    count = u16(state, S_TEAMS)
    if not 1 <= groups <= 8 or per_group * groups != count or count > 64:
        notes.append(f"{stage}: the save holds no readable table ({count} teams in {groups} groups)")
        return []
    ranks = [u16(state, S_RANK + 2 * i) for i in range(64)]
    rows: list[Standing] = []
    for group in range(groups):
        order = ranks[group * per_group:(group + 1) * per_group]
        if any(r % ROW_SIZE or r // ROW_SIZE >= 64 for r in order):
            notes.append(f"{stage}: the rank list of group {group + 1} is damaged")
            continue
        for i in range(len(order) - 1):
            for j in range(i + 1, len(order)):
                if _ranks_before(state, teams, order[i], order[j]):
                    order[i], order[j] = order[j], order[i]
        label = f"GROUP {chr(65 + group)}" if groups > 1 else ""
        for position, row in enumerate(order, start=1):
            base = S_ROWS + row
            name = teams.name(s32(state, base))
            if name is None:
                notes.append(f"{stage} {label}".strip() + f": position {position} names no team of the save")
                name = ""
            values = [u16(state, base + offset) for offset in range(4, 18, 2)]
            rows.append(Standing(stage, label, position, name, *values[:6], values[6]))
    return rows


# ---------------------------------------------------------------------------
# Cup ties
# ---------------------------------------------------------------------------
def _score(word: int) -> tuple[int, int]:
    return word >> 8, word & 0xFF


def round_name(state: bytes, tournament_stage: str | None) -> str:
    if tournament_stage is not None:
        return tournament_stage
    index, count, first = u16(state, C_ROUND), u16(state, C_ROUNDS), u16(state, C_FIRST_ROUND)
    if index == count - 1:
        return "FINAL"
    if index == count - 2:
        return "SEMI-FINAL"
    if index == count - 3:
        return "QUARTER-FINAL"
    number = index + first - 1
    return ROUND_NAMES[number] if 0 <= number < len(ROUND_NAMES) else f"ROUND {index + 1}"


def ties(state: bytes, teams: Teams, notes: list[str], tournament_stage: str | None = None) -> list[Tie]:
    """The ties of the round in play that the save marks as played, and the
    first legs of ties whose second leg is still to come."""
    count = u16(state, C_TIES)
    if count > 32:
        notes.append(f"the cup round lists {count} ties; the save holds at most 32")
        return []
    name = round_name(state, tournament_stage)
    # Before the second leg is set up, the round in play is a first leg.
    first_legs = u16(state, C_LEG_MODE) == TWO_LEGS and u16(state, C_LEG) == 0
    result: list[Tie] = []
    for t in range(count):
        flags = state[C_FLAGS + t]
        if not flags & (F_PLAYED | F_SECOND_LEG):
            continue
        home = teams.name(s32(state, C_ENTRANTS + 4 * state[C_PAIRS + 2 * t]))
        away = teams.name(s32(state, C_ENTRANTS + 4 * state[C_PAIRS + 2 * t + 1]))
        if home is None or away is None:
            notes.append(f"{name}: tie {t + 1} names a team the save does not hold")
            continue
        score, second, shootout = (u16(state, C_SCORE + 2 * t), u16(state, C_SECOND + 2 * t),
                                   u16(state, C_PENALTIES + 2 * t))
        if flags & F_SECOND_LEG:
            # The first leg: the teams the other way round, its score swapped
            # into this match's orientation.
            first_home, first_away = _score(second)
            result.append(Tie(name, "1", away, home, first_away, first_home,
                              state="" if flags & F_PLAYED else "second leg to come"))
            if not flags & F_PLAYED:
                continue
        home_goals, away_goals = _score(score)
        if first_legs and not flags & F_SECOND_LEG:
            result.append(Tie(name, "1", home, away, home_goals, away_goals, state="second leg to come"))
            continue
        tie = Tie(name, "2" if flags & F_SECOND_LEG else "", home, away, home_goals, away_goals,
                  extra_time=bool(flags & F_EXTRA), replay=bool(flags & F_REPLAY),
                  away_goals_rule=bool(flags & F_AWAY_GOALS))
        if flags & F_EXTRA and not flags & F_SECOND_LEG:
            tie.score_90 = "%d-%d" % _score(second)
        if flags & F_PENALTIES:
            tie.penalties = "%d-%d" % _score(shootout)
        if flags & F_SECOND_LEG:
            tie.aggregate = f"{home_goals + _score(second)[0]}-{away_goals + _score(second)[1]}"
        if flags & F_DECIDED:
            tie.winner = away if flags & F_AWAY_WON else home
        else:
            tie.state = "drawn, replay to come"
        result.append(tie)
    return result


# ---------------------------------------------------------------------------
# Scorers
# ---------------------------------------------------------------------------
def surname(name: bytes) -> bytes:
    return name.rsplit(b" ", 1)[-1]


def scorers(teams: Teams, slot: int) -> list[Scorer]:
    """Every player of the loaded teams with goals in the slot's counter,
    most goals first, then by surname as the game's list orders them."""
    found = []
    for team in teams.loaded():
        name = text(team[5:0x16])
        for player in range(PLAYER_COUNT):
            record = team[PLAYERS + player * PLAYER_SIZE:PLAYERS + (player + 1) * PLAYER_SIZE]
            goals = record[0x21 + slot]
            if goals:
                raw = record[3:0x1A].split(b"\0", 1)[0]
                found.append((goals, surname(raw), raw.decode("latin-1"), name))
    found.sort(key=lambda item: (-item[0], item[1]))
    return [Scorer(i + 1, player, team, goals) for i, (goals, _, player, team) in enumerate(found)]


# ---------------------------------------------------------------------------
# Saves
# ---------------------------------------------------------------------------
def _competition(save: str, kind: str, state: bytes, teams: Teams, slot: int) -> Competition:
    name = text(state[S_NAME:S_NAME + 36]) or {"diy": "DIY COMPETITION", "pre": "PRESET COMPETITION"}.get(kind, "")
    competition = Competition(save, name, kind)
    kind_word = u16(state, S_TYPE)
    if kind_word == TYPE_LEAGUE:
        competition.standings = standings(state, teams, "", competition.notes)
        competition.notes.append("a league save keeps its table, not its single matches")
    elif kind_word == TYPE_CUP:
        competition.ties = ties(state, teams, competition.notes)
        competition.notes.append("a cup save keeps only the round in play; earlier rounds are not in it")
    elif kind_word == TYPE_TOURNAMENT:
        stage = state[TOURNAMENT_STAGE:]
        index, count = u16(state, T_STAGE), u16(state, T_STAGES)
        label = f"STAGE {index + 1} OF {count}" + (" (FINAL STAGE)" if index == count - 1 else "")
        if u16(stage, S_TYPE) == TYPE_LEAGUE:
            competition.standings = standings(stage, teams, label, competition.notes)
        else:
            competition.ties = ties(stage, teams, competition.notes, label)
        competition.notes.append("a tournament save keeps only the stage in play; earlier stages are not in it")
    else:
        competition.notes.append(f"unknown competition type {kind_word}: no table read")
        return competition
    if 0 <= slot <= 3:
        competition.scorers = scorers(teams, slot)
        if kind == "sea":
            competition.notes.append("own goals are not players' goals and are not listed")
    else:
        competition.notes.append(f"the competition's goal counter {slot} is unknown: no scorers")
    return competition


def read_save(name: str, data: bytes) -> list[Competition]:
    """The competitions of one save, by its suffix."""
    kind = KINDS.get(Path(name).suffix.upper())
    if kind is None:
        raise ValueError(f"{name}: a report reads .DIY, .PRE and .SEA saves")
    if kind in ("diy", "pre"):
        if len(data) < DIY_TEAMS:
            raise ValueError(f"{name}: shorter than a competition save")
        state = data[:STATE_SIZE]
        count = u16(state, S_TEAMS)
        if len(data) != DIY_TEAMS + count * TEAM_SIZE:
            raise ValueError(f"{name}: the length does not fit its {count} teams")
        teams = Teams(data, DIY_TEAMS, count, cached=False)
        return [_competition(name, kind, state, teams, u16(state, S_SLOT))]
    if len(data) < SEASON_TEAMS:
        raise ValueError(f"{name}: shorter than a season save")
    count = u16(data, SEASON_TEAMS - 2)
    if len(data) != SEASON_TEAMS + count * TEAM_SIZE:
        raise ValueError(f"{name}: the length does not fit its {count} teams")
    teams = Teams(data, SEASON_TEAMS, count, cached=True)
    result = []
    for slot in range(SEASON_SLOTS):
        descriptor = struct.unpack_from(">I", data, SEASON_DESCRIPTORS + 4 * slot)[0]
        if not descriptor:
            continue
        offset = struct.unpack_from(">I", data, SEASON_STATES + 4 * slot)[0] - SEASON_RAM_BASE
        if not 0 <= offset <= len(data) - STATE_SIZE:
            raise ValueError(f"{name}: competition slot {slot} lies outside the save")
        result.append(_competition(name, kind, data[offset:offset + STATE_SIZE], teams, slot))
    return result


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def csv_text(columns: list[str], rows: list[list]) -> str:
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(columns)
    writer.writerows([[str(cell) for cell in row] for row in rows])
    return out.getvalue()


def _yes(value: bool) -> str:
    return "yes" if value else ""


def standing_rows(competitions: list[Competition]) -> list[list]:
    return [[c.save, c.name, r.stage, r.group, r.position, r.team, r.played, r.wins, r.draws, r.losses,
             r.goals_for, r.goals_against, r.difference, r.points] for c in competitions for r in c.standings]


def tie_rows(competitions: list[Competition]) -> list[list]:
    return [[c.save, c.name, t.round, t.leg, t.home, t.away, t.home_goals, t.away_goals, _yes(t.extra_time),
             t.score_90, t.penalties, t.aggregate, _yes(t.away_goals_rule), _yes(t.replay), t.winner, t.state]
            for c in competitions for t in c.ties]


def scorer_rows(competitions: list[Competition]) -> list[list]:
    return [[c.save, c.name, s.position, s.player, s.team, s.goals] for c in competitions for s in c.scorers]


def _table(columns: list[str], rows: list[list]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "|" + "---|" * len(columns)]
    lines += ["| " + " | ".join(str(cell).replace("|", "/") for cell in row) + " |" for row in rows]
    return lines


def markdown(competitions: list[Competition]) -> str:
    lines = ["# Competition report", ""]
    for c in competitions:
        lines += [f"## {c.name} ({c.save})", ""]
        if c.standings:
            for stage, group in dict.fromkeys((r.stage, r.group) for r in c.standings):
                title = " ".join(part for part in (stage, group) if part)
                if title:
                    lines += [f"### {title}", ""]
                rows = [[r.position, r.team, r.played, r.wins, r.draws, r.losses, r.goals_for, r.goals_against,
                         r.difference, r.points] for r in c.standings if (r.stage, r.group) == (stage, group)]
                lines += _table(["pos", "team", "pl", "w", "d", "l", "f", "a", "gd", "pts"], rows) + [""]
        if c.ties:
            rows = []
            for t in c.ties:
                score = f"{t.home_goals}-{t.away_goals}"
                extra = ", ".join(part for part in (
                    "a.e.t." if t.extra_time else "", f"90 mins {t.score_90}" if t.score_90 else "",
                    f"pens {t.penalties}" if t.penalties else "", f"agg. {t.aggregate}" if t.aggregate else "",
                    "away goals" if t.away_goals_rule else "", "replay" if t.replay else "", t.state) if part)
                rows.append([t.round, t.leg, t.home, t.away, score, extra, t.winner])
            lines += _table(["round", "leg", "home", "away", "score", "notes", "winner"], rows) + [""]
        if c.scorers:
            lines += ["### Scorers", ""]
            lines += _table(["pos", "player", "team", "goals"],
                            [[s.position, s.player, s.team, s.goals] for s in c.scorers]) + [""]
        if c.notes:
            lines += [f"- {note}" for note in c.notes] + [""]
    return "\n".join(lines)


def report_files(competitions: list[Competition]) -> dict[str, str]:
    """The files of a report by name."""
    return {"standings.csv": csv_text(STANDING_COLUMNS, standing_rows(competitions)),
            "cup.csv": csv_text(TIE_COLUMNS, tie_rows(competitions)),
            "scorers.csv": csv_text(SCORER_COLUMNS, scorer_rows(competitions)),
            "report.md": markdown(competitions)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("saves", type=Path, nargs="+")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        competitions = [c for path in args.saves for c in read_save(path.name, path.read_bytes())]
        args.out.mkdir(parents=True, exist_ok=True)
        for name, content in report_files(competitions).items():
            (args.out / name).write_text(content, encoding="latin-1")
            print(args.out / name)
    except (ValueError, OSError) as exc:
        parser.exit(1, f"competition_report: {exc}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
