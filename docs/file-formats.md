# File formats: JSON and CSV

The JSON and CSV files that `patch.py` writes and reads, for users who
exchange teams, players, tactics, tournament definitions and season updates
between machines, and for writers of tools. The binary files of the save
directory `data/` are listed in the
[architecture](architecture.md#files-the-editors-write); this document
describes only the files users exchange.

- **CSV** files are Latin-1 text with a header row, comma-separated in the
  style of Python's `csv` module, one line per row. The names the editors
  accept are ASCII.
- **JSON** files are written with a fixed key order, one-space indentation
  and ASCII only.
- Hexadecimal values (CRC-32 values, raw bytes) are written as text; a
  CRC-32 has eight upper-case digits. Every CRC-32 is CRC-32/ISO-HDLC, the CRC
  that Python's `zlib.crc32` computes.
- Every input is checked as the game and the editors check it before
  anything is written; written files are read back; nothing is ever deleted.
  Do not run these commands on an install the game is running from.

## Team keys and groups

A team is named by its **key**: its group and its ordinal, 0 for the first
team of the group. The **database groups** are the 65 club groups 0-8,
10-46, 48-51, 55, 60, 62, 64-67, 69, 71, 73 and 75-79 and the national
groups 80-85, 71 groups in all. Group 72 holds the custom teams: the game's
ORIGINAL CUSTOM TEAMS and the user's custom set `CUSTOMS.EDT` (48 teams,
ordinals 0-47); it is not a database group. A player is named by his team's
key and his **slot** 0-15 in the team record.

The lineup lists the 16 slots in lineup order: its first entry is role 1,
the goalkeeper, entries 2-11 are roles 2-11, the rest the other players of
the squad. Positions are `G RB LB D RW LW M A` (codes 0-7). A nationality
is one of the 153 three-letter labels of the user's own game (codes 0-152),
read from disk 1. Tactics 0-11 are the builtin tactics (442, 541, 451, 532,
352, 433, 424, 343, SWEEP, 523, ATTACK, DEFEND), 12-17 the user tactics
USER A-F.

## CSV files of the database and the custom set

`patch.py db export INSTALL DIR` writes `players.csv`, `teams.csv` and
`cups.csv` of the install's database: the groups of its edited set, the
original for every group the set does not declare. `patch.py export INSTALL
DIR` writes `customs-players.csv` and `customs-teams.csv` of the custom set,
when the install has a `CUSTOMS.EDT`, with the columns of `players.csv` and
`teams.csv` and group 72. Rows are sorted by group, ordinal and slot.

### `players.csv`, `customs-players.csv`

One row per player, 16 per team.

| Column | Values |
|---|---|
| `group`, `ordinal` | The team's key (required on import) |
| `team` | The team's name; informative, ignored on import |
| `slot` | The player's slot 0-15 (required on import) |
| `shirt` | Shirt number 1-16 |
| `name` | Up to 22 characters |
| `nationality` | A three-letter label |
| `position` | `G RB LB D RW LW M A` |
| `appearance` | 0-2 |
| `passing`, `shooting`, `heading`, `tackling`, `control`, `speed`, `finishing` | Skills 0-7 |
| `passing_special` ... `finishing_special` | The specialty flag of each skill, 0 or 1 |
| `rating` | A goalkeeper's rating; empty for an outfield player, whose rating is the sum of his seven skills |

### `teams.csv`, `customs-teams.csv`

One row per team.

| Column | Values |
|---|---|
| `group`, `ordinal` | The team's key (required on import) |
| `name` | Up to 16 characters |
| `coach` | Up to 22 characters |
| `division` | The team's division |
| `home_pattern`, `home_shirt`, `home_shirt2`, `home_shorts`, `home_socks` | Home kit: pattern 0-3, colours 0-9 |
| `away_pattern` ... `away_socks` | Away kit, the same |
| `tactic` | Default tactic 0-17 |

Then the strength summary of TEAM SETTINGS, derived from the record and
ignored on import:

| Column | Values |
|---|---|
| `average_rating` | The average rating of the outfield players in lineup roles 2-11, with one decimal (rounded half up); empty without one |
| `keeper_rating` | The rating of the player in role 1 |
| `skills_eleven`, `skills_squad` | The skill points (the seven skills) of the outfield players among roles 1-11, and among all 16 players |
| `specials_eleven`, `specials_squad` | Their specialty flags |

### `cups.csv`

The participants of the three European club cups in place order: the
edited set's lists, or the game's 96/97 ones.

| Column | Values |
|---|---|
| `cup` | `EUROCUP` (16 places), `EUROCWC` (32) or `UEFACUP` (32) |
| `place` | 1 to the cup's size |
| `group`, `ordinal` | The club's key: a team of a club group |
| `team` | The club's name; informative, ignored on import |

### Importing CSV files

`patch.py db import INSTALL FILES` applies `players.csv`, `teams.csv` and
`cups.csv` to the install's database (its edited set, or the original
groups) and writes a new generation of the edited set. `patch.py import
INSTALL FILES` applies `customs-players.csv` and `customs-teams.csv` to the
custom set (to the `CUSTOMS.EDT.json` of the same import, else to the
install's `CUSTOMS.EDT`, else to the game's own custom teams) and saves
`CUSTOMS.EDT` with the previous one kept as `CUSTOMS.BAK`.

- A file may hold any subset of the rows and of the columns. The key
  columns are required: `group` and `ordinal`, and `slot` in a players file;
  `cup`, `place`, `group` and `ordinal` in `cups.csv`. A column the file does
  not have, and a row it does not have, keep the data as it is.
- The informative columns (`team`, the strength columns) are ignored.
- The header may not name an unknown column or a column twice; every row
  must have as many cells as the header; empty lines are skipped.
- Numbers are decimal within the ranges of the tables above; the group must
  be one the file can change (a database group, 72 in the custom set's
  files), the ordinal a team of that group.
- A changed text is written NUL-terminated and zero-padded and may use
  `A-Z 0-9 space - / . ' ( )`; an unchanged text keeps its field as it is.
- A goalkeeper needs a rating 0-40 (see the checks below); an outfield
  player's `rating` must be empty, and his rating is computed from his
  skills, also when his position changes.
- `cups.csv` changes complete cups: every place of each cup the file names,
  each once.
- A refused cell names the file, the row (the header is row 1) and the
  column; a refusal of the checks below names the file and the group, team
  and player, or the cup and place.

After all changes the teams are checked as the editors check them, so a CSV
may exchange the divisions of two teams:

- A group keeps its number of teams, its keys in order and the number of
  teams in each division; a national team keeps its division.
- A team is refused, in this order, for: a kit value out of range (`A KIT
  VALUE IS OUT OF RANGE.`); a default tactic that is not available (`THE
  DEFAULT TACTIC IS NOT AVAILABLE.`: 0-11 always, 12-17 only unchanged); a
  lineup that is not the slots 0-15 each once (`THE LINEUP NAMES A PLAYER
  TWICE.`); role 1 not a goalkeeper (`THE LINEUP HAS NO GOALKEEPER IN
  GOAL.`); shirt numbers not 1-16 each once (`SHIRT NUMBERS MUST BE 1-16,
  EACH ONCE.`). Then player by player: nationality (`THE NATIONALITY IS OUT
  OF RANGE.`), appearance (`THE APPEARANCE IS OUT OF RANGE.`), a goalkeeper
  with skills or specialty flags (`A GOALKEEPER HAS OUTFIELD SKILLS.`), a
  goalkeeper rating above 38 (`THE GOALKEEPER RATING IS ABOVE 38.`), an
  outfield rating that is not the sum of the skills (`THE RATING DIFFERS
  FROM THE SKILLS.`), and a changed name or coach with a character the
  game cannot show (`A NAME HAS A CHARACTER THE GAME CANNOT SHOW.`). Values
  of the game's own data outside these ranges (goalkeeper ratings 39-40, a
  default tactic 12-17) are accepted while they are unchanged: as the
  original team has them, as the install's edited set (or custom set) holds
  them, which is the record the editors load and keep, or as the original
  team of the same name has them (a team moved by EXCHANGE or COPY TO
  COUNTRY, a club IMPORT brought into a custom slot). A user tactic 12-17
  set in the game is therefore kept by later imports on the same install;
  on another install it counts as new and is refused.
- The cups: exactly 16, 32 and 32 clubs of club groups, no club twice in
  one cup or in two, no national or custom team.
- The custom set keeps the game's number of teams.

## Season packs

A season pack holds the fields in which an edited database differs from the
game's original groups, so that every machine of a tournament group makes
the same set from its own disks. `patch.py db diff INSTALL PACK.json`
writes it (a new file; `--label` names the set, else the set's own label),
and `patch.py db apply INSTALL PACK.json`, `db import` and
`install --set` apply it. Two installs that apply the same pack show the
same fingerprint. Abbreviated example (a cup lists all its clubs):

```json
{
 "format": "SWOSPACK",
 "version": 2,
 "label": "SEASON 26/27",
 "base": "<64 lower-case hexadecimal digits>",
 "teams": [
  {
   "group": 8,
   "ordinal": 0,
   "fields": {"name": "NEW CLUB", "division": 1},
   "players": [{"slot": 5, "fields": {"name": "NEW NAME", "position": "A"}}]
  }
 ],
 "cups": [{"cup": "EUROCUP", "teams": [[8, 0], [25, 0]]}]
}
```

| Key | Contents |
|---|---|
| `format`, `version` | `"SWOSPACK"`, 2 |
| `label` | The set label: up to 16 of `A-Z 0-9 space - / .`, may be empty |
| `base` | The SHA-256 of the original groups the pack is relative to: over every database group in ascending order, each as the group byte, its length as a big-endian 32-bit number and the unpacked original group file |
| `teams` | The changed teams, sorted by group and ordinal: `group`, `ordinal`, the changed team `fields` and the changed `players`, sorted by slot, each with `slot` and its changed `fields` |
| `cups` | Optional: for each cup whose participant list differs from the game's 96/97 one, `cup` (`EUROCUP`, `EUROCWC`, `UEFACUP`) and its complete list of `[group, ordinal]` pairs |

The fields a pack may change:

| Team field | Value |
|---|---|
| `name` | Up to 16 characters |
| `coach` | Up to 22 characters |
| `division` | The division |
| `home_kit`, `away_kit` | Five values: pattern, shirt, second shirt, shorts, socks |
| `tactic` | Default tactic |
| `lineup` | The 16 slots in lineup order |

| Player field | Value |
|---|---|
| `shirt` | 1-16 |
| `name` | Up to 22 characters |
| `nationality` | The code 0-152 |
| `position` | A letter, `G RB LB D RW LW M A` |
| `appearance` | 0-2 |
| `skills` | Seven values 0-7: passing, shooting, heading, tackling, control, speed, finishing |
| `specialties` | Seven values 0 or 1, in the same order |
| `rating` | A goalkeeper's rating 0-40; an outfield player's rating is computed from his skills and not written |

Texts use the characters of the CSV files. `diff` writes only the fields
that differ from the original groups. `apply` builds the groups from the
user's own original groups and the pack (not from the set already in the
install) and checks the result as a CSV import does. It refuses a file that
is not a `SWOSPACK` of version 1 or 2, a `base` of other original groups, a
label the game cannot show, a group that is not a database group, a team or
slot the group does not have, a field a pack may not change, a value out of
range, a goalkeeper without a rating, a cup named twice or not a cup, a
`teams` entry that is not a `[group, ordinal]` pair, a cup without its exact
number of clubs, with a team that is not a club or with a club twice, and a
`cups` section in a version 1 pack. Version 1 packs, without `cups`, are
still applied. The label of the new set is `--label`, else the pack's.

## JSON files of export and db export

`patch.py export INSTALL DIR` writes the data of the save directory into the
new directory `DIR`; `patch.py db export INSTALL DIR` writes the database:

| Command | Path | Contents |
|---|---|---|
| `export` | `CUSTOMS.EDT.json` | The custom set, when the install has a `CUSTOMS.EDT` (with `customs-players.csv` and `customs-teams.csv`) |
| `export` | `tactics/NAME.TAC.json` | Each `.TAC` the editors accept |
| `export` | `definitions/NAME.DEF.json` | Each `.DEF` the editors accept |
| `export` | `saves/NAME.json` | Each readable competition save (`.DIY .PRE .SEA .CAR`) and link file (`.DLD .DLP .DLS .DLC`), for reading only |
| `export` | `database/DBASE.CFG.json` | The edited set's manifest, for reading only |
| `export` | `database/TEAM.ggg.json` | Each database group the edited set declares |
| `db export` | `TEAM.ggg.json` | All 71 database groups (`ggg` three digits): the edited set's, the original for every other group |
| `db export` | `players.csv`, `teams.csv`, `cups.csv` | The CSV files above |

### The lossless convention

The JSON of team groups, of the custom set and of tactics is lossless:
every byte of the file is represented, and an unchanged export imports to
the same bytes (the import then reports the file as unchanged). The JSON of
a competition save is lossless as well, but for reading only.

- Bytes whose meaning the editors do not use are explicit fields
  (`unknown_04`, `flags_17`, `unknown_21_25_hex` and the like) and are kept.
- A text is an object `{"text": ..., "raw_hex": ...}`: `raw_hex` is the whole
  fixed field as it is in the file. While `text` equals the text of
  `raw_hex`, the field is written as `raw_hex`, bytes after the NUL included;
  a changed `text` is written as Latin-1, NUL-terminated and zero-padded, and
  must leave room for the NUL.
- Numbers must fit their field (a byte 0-255, a nibble 0-15), and lists have
  their exact lengths.

A definition's JSON holds its fields only, because every other byte of a
valid definition is zero; encoding it gives the file back byte for byte.

### Team groups and the custom set (`TEAM.ggg.json`, `CUSTOMS.EDT.json`)

`{"schema": "swos-amiga-team-data-v1", "kind": "team-file", "teams":
[...]}`; the team count of the file is the number of teams in the list.

| Team key | Meaning |
|---|---|
| `group_code`, `ordinal` | The team's key |
| `database_id` | The secondary ID (16 bits); the game rebuilds it from the key when it loads a group |
| `unknown_04` | Zero in a group |
| `name` | Text, up to 16 characters |
| `unknown_16`, `flags_17`, `flags_3b` | Game state, kept |
| `tactic_code` | Default tactic 0-17 |
| `division_code` | Division |
| `home_kit_bytes`, `away_kit_bytes` | Five values: pattern 0-3, shirt, second shirt, shorts, socks (colours 0-9) |
| `coach` | Text, up to 22 characters |
| `lineup` | The 16 slots in lineup order |
| `players` | The 16 players, slots 0-15 |

| Player key | Meaning |
|---|---|
| `nationality_code` | 0-152 |
| `unknown_01`, `unknown_1b` | Game state, kept |
| `shirt_number` | 1-16 |
| `name` | Text, up to 22 characters |
| `position_appearance_bits` | Bits 7-5 the position code 0-7, bits 4-3 the appearance 0-2, bits 2-0 kept |
| `skill_prefix_nibble` | 0 |
| `skill_nibbles` | Seven values: passing, shooting, heading, tackling, ball control, speed, finishing; bits 2-0 the skill 0-7, bit 3 (value 8) the specialty flag |
| `aggregate_rating` | The rating: for an outfield player the sum of his seven skills, for a goalkeeper his own |
| `unknown_21_25_hex` | Five bytes of game state (goal counters and a performance value) as ten hex digits, kept |

Import checks a group as a CSV import does (the same number of teams, the
keys, the divisions, the team checks), and the custom set's teams with the
team checks and the game's number of teams.

### Tactics (`NAME.TAC.json`)

`{"schema": "swos-amiga-tactics-v1", "tactics": [tactic]}`, one tactic:

| Key | Meaning |
|---|---|
| `name` | Text, a nine-byte field: up to 8 characters |
| `positions` | Ten lists, one per lineup role 2-11, of 35 ball zones each (zone `row*5 + column`, five columns by seven rows): `{"x": 0-14, "y": 0-15}` |
| `mirror_pair_groups` | Ten values, one per role: a mirror pair label 0-4, or 255 for none |
| `base_formation` | The builtin tactic 0-11 the tactic is based on |

Import refuses a tactic as the editors do, in this order: a name of more than
8 characters; x above 14; two players on one spot in a zone; a label not 0-4
or 255; a used label not on exactly two players; a base formation above 11.

### Tournament definitions (`NAME.DEF.json`)

A DIY league, cup or tournament as the game's setup pages describe it, with
the database it was made with and optionally its teams and user tactics:

| Key | Meaning |
|---|---|
| `schema` | `"swos-amiga-definition-v1"` |
| `database` | `{"kind": "original"}`, or `{"kind": "edited", "generation": ..., "crc32": ..., "label": ...}`: the edited set's manifest generation, fingerprint and label |
| `custom_set_crc32` | The CRC-32 of `CUSTOMS.EDT` as last loaded or saved, or `null` |
| `family` | `"league"`, `"cup"` or `"tournament"` |
| `name` | 0-24 characters of `A-Z 0-9 space - / .` |
| `pitch` | `{"mode": ..., "type": ...}`: mode 0 pitch type, 1 season; type -1 random, 0 frozen ... 6 hard |
| `season` | `{"start": ..., "end": ...}` in eighths of a month, whole months: 0, 8, ..., 88 |
| `teams` | Teams of the competition: a league 2-24, a cup `2^rounds`, a tournament 2-64 |
| `substitutes` | `{"usable": ..., "bench": 0-5}`: usable 0 without a bench, else 1 to the bench size |
| `league` | `{"repetitions": 1-10, "points": 2 or 3}` |
| `cup` | `{"rounds": 1-6, "away_goals": ..., "legs": [...], "extra_time": [...], "penalties": [...]}`; away goals 0 off, 1 after 90 minutes, 2 after extra time; six values per list, one per round, all checked: legs 1 or 2, extra time 0 none, 1 yes, 2 only in a replay, penalties the same |
| `tournament` | `{"away_goals": 0-2, "stages": [...]}`, 1-6 stages |
| `participants` | `[]` (the teams are chosen when the competition starts) or exactly `teams` entries in the order of the team selection |
| `tactics` | The user tactics it carries, as `{"USER A": tactic, ...}` with keys `USER A` to `USER F`, each a tactic object as in `NAME.TAC.json` |

Only the family's own rules object is present. A stage has `teams` (the
teams entering), `through` (the teams going on, the next stage's
entrants), `groups` (0 for a knockout, else 1-8), `group_teams` (for a
knockout the teams entering), `seeded` (0 or 1), `repetitions` (1-4),
`points` (2 or 3), `legs` (1 or 2), `extra_time` and `penalties` (as in a
cup); every value is checked in every stage. The stages must form a chain
the game's own setup offers: the first stage enters all teams and each next
one the teams the previous sends on; no stage starts with 58 or 62 teams; a
stage sends on at least one team and fewer than it enters, and only the
last stage sends on one. A knockout enters twice the teams it sends on (in
stage 5 at most 48 teams, in stage 6 only a two-team final). Groups divide
the entrants evenly, with at most 24 and more than one team per group, no
more groups than teams going through, and exactly one group in stage 6. A
group stage needs at most 90 match dates, `floor((n(n-1)/2) / floor(n/2)) *
repetitions` for `n` teams per group.

A participant has `group` and `ordinal`, `source` (`"database"`, which
includes the ORIGINAL CUSTOM TEAMS as group 72, or `"custom set"`, group 72,
the EDITED CUSTOM TEAMS), `control` (`"computer"`, `"player-coach"` or
`"coach"`) and `name`, the team's name when the definition was saved (up to
16 characters, for messages only). A database participant's group is a
database group or 72. A key appears once. Import checks the encoded file
with every check of LOAD DEFINITION and refuses it with the line the game
shows.

### Read-only exports

The exports of competition saves, link files and the manifest start with
`"read_only": true`, and `import` refuses them ("an export of a game save,
a link or a manifest is for reading only"):

- a save: the competition save codec's document (`"schema":
  "swos-amiga-competition-data-v1"`, `kind` `diy`, `pre`, `sea` or `car`):
  the competition state, the user tactics and the loaded teams;
- a link: `"format": "SWOSLNK1"`, `family` (1 DIY, 2 preset, 3 season, 4
  career), `save_suffix`, `save_length`, `save_crc32` and the `manifest`;
- the manifest: `"format": "SWOSGRP1"`, `version`, `generation`, `label`,
  `crc32` (the set's fingerprint) and `groups`, each with `group`, `kind`
  (`GROUP`, `EUROCUP`, `EUROCWC`, `UEFACUP` or `POOLPLYR`), `file`,
  `records`, `length` and `crc32`.

### How import chooses the target

`patch.py import INSTALL FILES` decides by the file name, case ignored:

| File | Target |
|---|---|
| `CUSTOMS.EDT.json` | The custom set `CUSTOMS.EDT`, saved with `CUSTOMS.BAK` first |
| `NAME.TAC.json` | The tactic `NAME.TAC` (the name in upper case) |
| `NAME.DEF.json` | The definition `NAME.DEF` (the name in upper case) |
| `TEAM.ggg.json` | A database group, into a new generation of the edited set; the group is the one of the teams in the file |
| `customs-players.csv`, `customs-teams.csv` | The custom set |
| `NAME.TAC`, `NAME.DEF` | Copied as they are, after the checks |

Any other file is refused. A target name has 1-29 characters with a dot; a
`.TAC` needs a name of 1-8 characters before `.TAC`, the names the game lists.
A target that exists with the same contents is reported unchanged; a `.TAC`
or `.DEF` that exists with other contents is replaced only with `--replace`,
and a sound `.DEF` replaced is kept as `NAME.DEF.BAK` first, as SAVE
DEFINITION keeps it.
The save directory holds at most 512 names, 45 of them game saves.

`patch.py db import INSTALL FILES` takes files ending in `players.csv`,
`teams.csv` and `cups.csv`, season packs and `TEAM.ggg.json` files; a
`.json` file is a pack when its `format` is `SWOSPACK`, else a group,
identified by its teams. Packs and groups are applied in the order given (a
pack starts again from the original groups), then the players and teams
files, then the cups file. The new set's label is `--label`, else a pack's,
else the label the set has. `patch.py install --set FILES` takes the same
files for the database of a new install.

## Reports and results

### `patch.py report`

`patch.py report SAVES --output DIR` reads `.DIY`, `.PRE` and `.SEA` saves,
or all of them in an install, for reading only, and writes what the game's own
screens show from them. What a save does not hold is left out and named in
the notes: a league keeps its table but not its single matches, a cup only
the round in play, a tournament only the stage in play.

| File | Columns |
|---|---|
| `standings.csv` | save, competition, stage, group, position, team, played, wins, draws, losses, goals_for, goals_against, goal_difference, points |
| `cup.csv` | save, competition, round, leg, home, away, home_goals, away_goals, extra_time, score_90, penalties, aggregate, away_goals_rule, replay, winner, state |
| `scorers.csv` | save, competition, position, player, team, goals |
| `report.md` | Per competition its tables, ties, scorers and notes |

Standings are a league's table, or each group's of a tournament's group
stage, ranked as the game ranks them: points, goal difference, goals scored,
team name. `stage` is `STAGE n OF m` in a tournament (with `(FINAL STAGE)`
for the last), `group` is `GROUP A` and on when there is more than one. In
`cup.csv`, `round` is the round's name (`FIRST ROUND` ... `QUARTER-FINAL`,
`SEMI-FINAL`, `FINAL`) or the tournament stage; `leg` is `1`, `2` or empty;
`extra_time`, `away_goals_rule` and `replay` are `yes` or empty;
`score_90` (the score after 90 minutes of a match that went to extra time),
`penalties` and `aggregate` (a second leg) are `h-a`; `winner` is the team
that went through; `state` is `second leg to come`, `drawn, replay to come`
or empty. Scorers come from each player's goal counter of the competition,
most goals first.

### `patch.py results`

`patch.py results LOGS --output DIR` reads the match logs of several
installs (and copies of a log), merges them and writes:

| File | Columns |
|---|---|
| `matches.csv` | machine, install, sequence, time, family, competition, round, home, away, home_goals, away_goals, extra_time, penalties, aggregate, forfeit, database, custom_set_crc32 |
| `standings.csv` | position, team, played, wins, draws, losses, goals_for, goals_against, goal_difference, points |
| `scorers.csv` | position, player, team, goals |
| `results.md` | The warnings, the standings, the scorers and the matches |

In `matches.csv`, `install` is the install identity (eight hex digits),
`sequence` the install's match number, `time` `YYYY-MM-DD HH:MM:SS` (when
the game was started: WHDLoad reads the clock once) or empty when the
machine has no clock, `family` `friendly`, `diy`, `preset`,
`season` or `career`; `extra_time` and `forfeit` are `yes` or empty;
`penalties` (the shootout) and `aggregate` (a second leg) are `h-a`;
`database` is `ORIGINAL` or the set's label and fingerprint;
`custom_set_crc32` the custom set's CRC-32 when it is known.

A record seen again with the same bytes is dropped as a duplicate; the same
install and sequence number with other bytes is a conflict, and both are
kept. Damaged and cut records, conflicts, gaps in an install's sequence
numbers and matches played with different databases or custom sets are
warnings. `--def` selects the teams of a definition (by key) and its points
for a win (a league's, a tournament's first stage's, else 3); `--teams` names or
`GROUP:ORDINAL` keys, `--family`, `--machine` (a name or an install
identity) with `--sequence FROM-TO` select further; `--points` sets 2 or 3
points for a win (3 by default). Standings count the result after extra time
(a shootout does not change it), a draw 1 point, and are ranked as a league:
points, goal difference, goals scored, team name. Own goals are no player's.
