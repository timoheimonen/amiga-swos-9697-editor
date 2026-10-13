# SWOS 96-97 In-Game Editors: User Manual

In-game editors for **Sensible World of Soccer '96-'97** on the Amiga, as a
WHDLoad install for a hard disk: you edit your own custom teams and
players, tactics, tournament definitions and the game's own database of
clubs and national teams on the game's own screens, play with them at
once, and move everything a tournament needs between installs and a
computer with `patch.py`.

The editors run only in this install of the supported release (disk 1
[a2] and disk 2). They were tested in emulation on an A1200 configuration;
they have not been tested on real hardware.

## Contents

1. [Getting started](#1-getting-started)
2. [The main menu](#2-the-main-menu)
3. [Custom teams and players](#3-custom-teams-and-players)
4. [Tactics](#4-tactics)
5. [Tournament definitions](#5-tournament-definitions)
6. [The edited database](#6-the-edited-database)
7. [The match log](#7-the-match-log)
8. [Saves and the save directory](#8-saves-and-the-save-directory)
9. [patch.py on your computer](#9-patchpy-on-your-computer)
10. [Season update and tournament day](#10-season-update-and-tournament-day)
11. [Messages](#11-messages)
12. [Limits](#12-limits)

## 1. Getting started

### What you need

- An Amiga 1200 compatible machine: a 68020 or better, the AGA chipset,
  Kickstart 3.1, 2 MiB of chip memory and at least 2 MiB of fast memory,
  and WHDLoad 17 or later on a hard disk. WHDLoad refuses to start the
  install on any other machine.
- Python 3.9 or later on a computer, for `patch.py`. Nothing else: it uses
  only the Python standard library.
- Your own ADF images of the game's two disks:

| Disk | SHA-256 |
|---|---|
| 1 ([a2]) | `b70c0db66d8c2e93f1e12aa00c5df4b465c9f29d458723130e5a946428ca92ee` |
| 2 | `ed921246c05531a2445a3f61aee4afd493771ab79042d7c4ed210fd3f3c30d36` |

Other images are refused.

### Installing

```sh
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output SWOS --machine "TABLE 1"
```

The images can be given in any order. `patch.py` checks both images before
it writes anything, only reads them, and reads every file back after writing
it. It creates the new directory `SWOS` (it never writes into an existing
one):

| File | Contents |
|---|---|
| `SWOS.slave` | The WHDLoad slave |
| `SWOS.info` | The icon: default tool `WHDLoad`, tool types `SLAVE=SWOS.slave`, `PRELOAD`, `NOWRITECACHE`, `WRITEDELAY=10` |
| `Disk.1`, `Disk.2` | Your disk images, unchanged; the game only reads them |
| `Editor.bin` | The editors |
| `data/` | The save directory: the game's saves and every file of the editors |

`--machine` names the install in the match log (chapter 7); without it the
name is `AMIGA`. Copy the directory to the Amiga's hard disk, for example
with an emulator's shared folder or a network share.

### Starting the game

Double-click `SWOS.info`. The game starts as usual and shows its main menu
with the new entry **EDIT DATABASE**. If EDIT DATABASE is missing, the
editors did not load (for example because `Editor.bin` is missing or
damaged): the game then runs as the original, without the editors. F10
quits WHDLoad.

### Controls

The game's own screens work as always: the joystick in port 2, and the
keyboard where the game offers it. The editors' own screens (team
settings, the player screen, the database screens, the definition screens
and every message) use the same controls: the joystick or the cursor keys
move the highlight between buttons and rows, Fire or Return chooses, Esc
cancels or goes back, and buttons with a letter in brackets react to that
key. Names are typed on the keyboard; only the characters the game's font
can show are accepted.

## 2. The main menu

Besides EDIT DATABASE nothing in the main menu changes. While an edited
database is in use, a line below LOAD OLD COMPETITION shows it with its
label and fingerprint, for example `DATABASE: SEASON 26/27 1A2B3C4D`
(`DATABASE: EDITED 1A2B3C4D` without a label). Two machines whose lines show
the same fingerprint play with the same database. If a set that was in use
at the last start cannot be used, the line says why instead, for example
`DATABASE OFF: T0080002.GRP MISSING`, and the game uses its original
database.

## 3. Custom teams and players

EDIT CUSTOM TEAMS works as in the original game, with more to edit.

### The team page

The page keeps all its controls (team name, coach, kits, the player names,
IMPORT, OK, UNDO) and gains:

- an **EDIT** button on every player row: the player screen of that player;
- **SETTINGS**: the team's default tactic, lineup and shirt numbers;
- a line `SET 1A2B3C4D` at the top right: the fingerprint of the custom set
  as it was last loaded or saved, with `*` after it while accepted changes
  are not saved yet.

OK checks the whole team before it accepts it. If something is wrong, the
team is not accepted, a message names the problem and the page stays open:
change it, or use UNDO to restore the team. The checks are:

- kit colours and patterns in the game's ranges;
- a default tactic the game can use (see SETTINGS);
- a lineup that names every player once, with a goalkeeper in goal;
- shirt numbers 1-16, each once;
- for every player: a nationality and appearance the game knows; a
  goalkeeper has no outfield skills and a rating of at most 38 (a higher
  rating the team already had is kept); an outfield player's rating is the
  sum of the skills.

### Team settings

- **Tactic**: the default tactic of the team, one of the twelve builtin
  tactics, or one of the six user tactics USER A-F (shown by name). A user
  tactic is offered when you loaded or edited it in this session, or when
  the team's own data names it; after a restart load the same `.TAC` into
  that slot again.
- **Lineup**: one row per role, 1-11 the starters and 12S-16S the
  substitutes, with shirt number, position and name. SWAP PLACES swaps two
  players (Fire on both), SWAP NUMBERS swaps two shirt numbers.
- The **strength line**, for example `AVG 31.4  GK 28  SKILLS 314/451
  SPECIAL 14/20`: the average rating of the outfield players in roles 2-11,
  the goalkeeper's rating, and the skill points and specialty flags of the
  outfield players of the first eleven and of the whole squad. It is
  information only; the editors enforce no house rules.

OK keeps the changes, CANCEL (or Esc) restores the team as it was when the
screen opened. OK is refused while role 1 is not a goalkeeper.

### The player screen

NAME (up to 22 characters), NATIONALITY (the game's three-letter labels),
SHIRT NUMBER (swapped with the player who has it), POSITION (G, RB, LB, D,
RW, LW, M, A), APPEARANCE, the seven skills 0-7 (LEFT/RIGHT; Fire marks the
skill's specialty `*`) and, for a goalkeeper, his rating 0-38 instead of
the skills. The line `RATING n VALUE x` shows the rating and the price the
game works out from it; Fire on it explains that a value cannot be set.

Changing a player into a goalkeeper or back converts his skills and rating
and asks first; changing him back restores what he had.

**COPY PLAYER** keeps the shown player in a clipboard; **PASTE PLAYER**
gives the shown player the clipboard's name, nationality, position,
appearance, skills, specialty flags and rating, and keeps his shirt number.
The clipboard works between teams, in the custom set and in the edited
database, until the game is quit. OK keeps the changes for the team page;
CANCEL restores the player.

### Saving

When you leave the team chooser after accepting changes, the game asks
whether to save the custom teams, as in the original game. SAVE writes
`CUSTOMS.EDT` into the save directory: first the previous `CUSTOMS.EDT` is
kept as `CUSTOMS.BAK` (read back and compared), then the new file is
written and read back. A previous file that is not a whole custom set is
not kept, so `CUSTOMS.BAK` still holds the last good set. If anything fails, the previous file stays and the
message says what happened; if the new file could not be written, the
editor offers to restore `CUSTOMS.EDT` from the backup at once. ABORT keeps
the changes in memory until the next team list is loaded, and the file
stays unchanged. A `CUSTOMS.EDT` that is not a whole custom set (cut or
changed outside the game) is not loaded: `CUSTOM TEAMS NOT LOADED` says so
and no team of it is used; `python3 patch.py check SWOS/data/CUSTOMS.EDT
--install SWOS` names the problem.

A started competition keeps its own copies of its teams: EDIT CUSTOM TEAMS
says so before the game's question about leaving the competition. Edits
are used by competitions started afterwards.

## 4. Tactics

EDIT TACTICS works as in the original game. Before a tactic is used, the
editor checks it: every player on the pitch in every ball zone, no two
players on one spot, mirror pairs of exactly two players, and a base
formation that is one of the builtin tactics. A tactic with a problem is
refused with a message that names the player, the ball zone or the pair:

- SAVE/EXIT of a changed tactic with a problem keeps the slot's previous
  tactic (`TACTIC NOT ACCEPTED`); change it, or use UNDO, IMPORT or ABORT;
- LOAD of a `.TAC` file with a problem loads nothing (`FILE DAMAGED`);
- a `.TAC` file is always exactly 370 bytes and is read back after saving.

IMPORT copies a tactic's positions into the working tactic and keeps its
name.

A user tactic you loaded or edited in this session stays in its slot when a
new competition starts (natively the game would reset all six slots); a
tactic that came from a loaded competition save is reset as in the
original game.

## 5. Tournament definitions

A tournament definition (`.DEF`) holds the rules of a DIY league, cup or
tournament, and optionally its teams and the user tactics, so that the same
competition can be started again and on other machines.

### Rules and saving

The league, cup and tournament setup pages of DIY COMPETITION gain two
buttons:

- **RULES** shows every rule of the setup, also what the page itself does
  not show (the match dates of each group stage, the matchdays of a
  league, whether a definition's teams are held), and whether the game can
  run it: `READY TO START`, or the problem, for example `STAGE 1 NEEDS 92
  MATCH DATES, AT MOST 90 FIT.` A setup with a problem cannot be saved or
  started; CHOOSE TEAMS checks it first.
- **SAVE DEFINITION** asks for a file name (up to eight characters A-Z, 0-9
  and `-`), offers to choose the teams now with the game's own team chooser
  (USE THESE TEAMS) or to leave them for the start (NO TEAMS), asks whether
  to include your user tactics, and writes `NAME.DEF`. The teams chosen
  there are kept for the page only when the definition is saved; CANCEL
  keeps the teams the page had. An existing file is replaced only after a
  question, and the previous one is kept as `NAME.DEF.BAK` first. If the
  new file cannot be written, the editor offers to restore the previous one
  from `NAME.DEF.BAK` at once. The message after saving shows the
  definition's fingerprint (CRC-32).

### Loading

**LOAD DEFINITION** on the DIY COMPETITION page (below LEAGUE, CUP and
TOURNAMENT) lists the `.DEF` files of the save directory, sixteen to a
page, with their competition type, name and fingerprint. Choosing one opens
the setup page of its type with its rules. CHOOSE TEAMS then asks whether
to start with the definition's teams (YES) or to choose them now (NO).

- A team of the definition that the database in use does not hold is
  reported (`TEAM NOT FOUND`); it is never replaced by another team.
- A definition saved with another database than the one in use asks first
  (`DEFINITION MADE WITH ANOTHER DATABASE`): its teams then come from the
  database in use.
- A definition with tactics loads them into USER A-F after checking all of
  them, and asks before it replaces a different tactic you loaded or
  edited.
- A damaged file loads nothing (`FILE DAMAGED`, with the problem).

## 6. The edited database

EDIT DATABASE edits the game's own clubs and national teams. The edited
teams are used by **new** competitions, seasons and careers while USE
EDITED DATABASE is on; the original database stays on disk 2, unchanged.

### The database screen

The screen lists the game's database groups (the countries' leagues and
the national teams), 24 to a page: `*` marks a group of the saved set, `+`
a group with changes not yet saved. Two lines describe the set (label,
fingerprint, groups) and what new competitions use; the bottom line shows
the version of the editors and their author. The buttons:

- **PREVIOUS**, **NEXT**: the pages of the list.
- **SET LABEL**: a name for the set of up to 16 characters (A-Z, 0-9,
  space, `-`, `/`, `.`), written with the next SAVE and shown in the main
  menu.
- **SAVE**: writes the edited group as a new version, keeps the previous
  manifest as `DBASE.BAK` and writes the new `DBASE.CFG`, each read back.
  The message shows the label, the fingerprint and the version. A failed
  save keeps the working group and the saved set unchanged.
- **REMOVE OLD VERSIONS**: deletes the old versions of group files that
  neither the set, its backup nor a save's link file uses, after a warning:
  saves started with them elsewhere can then no longer be continued here.
  While `DBASE.CFG` is damaged nothing is removed (`FILE DAMAGED`), since
  its files are not known.
- **USE EDITED DATABASE: ON/OFF**: which database new competitions use. The
  state is remembered across restarts (`DBASE.USE`); at the start a set
  remembered as on is checked file by file.
- **EUROPEAN CUPS**: the participants of the three European club cups in
  the saved set, one cup at a time.
- **EXIT**: back to the main menu; with unsaved changes it asks first.

### A group

Choosing a group opens its clubs (or national teams) with their divisions:

- **EDIT TEAM**: the team page, the team settings and the player screens of
  chapter 3, for the chosen club. IMPORT is not offered here; use COPY TO
  COUNTRY or EXCHANGE.
- **DIVISION SWAP**: two clubs of the group change divisions; each division
  keeps its number of clubs.
- **EXCHANGE**: two clubs change places; each place keeps its key and
  division.
- **COPY TO COUNTRY**: the chosen club replaces a club of another country
  (choose the country and the club to replace; both are shown before you
  confirm). The group must be saved first.
- **BACK**: the database screen.

One group is edited at a time: opening another with unsaved changes asks
first. DIVISION SWAP and COPY TO COUNTRY are not offered for national
teams.

### What uses the edited database

- New DIY competitions, preset competitions, seasons and careers started
  while USE EDITED DATABASE is on, with every database group, the national
  teams included. The European club cups and the foreign player market of
  a new career follow the set as well: SAVE refreshes the cups' and the
  transfer pool's copies of the edited clubs and players, and a note says
  so where the game shows them.
- A started competition keeps its own copies of its teams. Its save is
  bound to the database it started with by a **link file** next to the save
  (`.DLD`, `.DLP`, `.DLS`, `.DLC` for `.DIY`, `.PRE`, `.SEA`, `.CAR`):
  loading such a save checks that the files of its set are present and
  unchanged first and refuses the load otherwise (`DATABASE NOT FOUND`).
  Keep the link files with their saves when you copy saves to another
  install.
- Existing careers and saves are never changed.

## 7. The match log

Every match the game plays to its end (a friendly, a DIY or preset
competition, a season or a career, with human or computer teams) is added
to `MATCHES.LOG` in the save directory: the machine, a sequence number, the
date and time when the machine has a clock (WHDLoad reads the clock once,
when the game starts, so every match of one session has that time), the
database in use, the competition and round, both teams, the score after 90
minutes and at the end, extra time and penalties, and the scorers with
their minutes. Results
the game only works out (VIEW RESULT, the other matches of a round) and
replays of highlights are not logged; a match left with Esc is logged only
when the game records a result for it.

`MACHINE.CFG` holds the install's machine name and a random identity, so
the logs of several machines can be merged without mixing them up
(`patch.py results`, chapter 9). Rename a machine with `patch.py machine`.

If a match cannot be added (the save directory is full or write
protected), play goes on and one note says so after the match (`MATCH NOT
SAVED IN THE LOG`); later matches are logged again once `data/` takes them.

## 8. Saves and the save directory

The game's save disk is the directory `data/` of the install. Saves, loads,
DELETE FILE and the game's lists all work on the files there; the game
never asks for a save disk.

- The game's own lists show its saves (`.DIY .PRE .SEA .CAR .TAC .HIL`, at
  most 45, the first by name) and `CUSTOMS.EDT`.
- `data/` holds at most 512 files. A new file is refused (`TOO MANY FILES`)
  when it would hold more, and a new game save when 45 are present.
- File names have 1-29 characters with a dot.
- FORMAT SAVE DISK changes nothing: the directory needs no format (a note
  says so). DELETE FILE also deletes a deleted save's link file.
- WHDLoad keeps the files it has read in memory: a file changed in `data/`
  from outside while the game runs is seen after the game is started
  again. Change the data of an install only while the game is not running.
- After a save failed (the disk was full or write protected), fix the
  cause and start the game again before you save the same file again:
  WHDLoad may not see that file again in the same session.

## 9. patch.py on your computer

Every command that works on saved data takes the install directory
(`SWOS` in these examples). Every input is checked before anything is
written, files are written in the game's own order and read back, and no
file is ever deleted. Run them while the game is not running.

| Command | What it does |
|---|---|
| `python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output SWOS [--machine NAME] [--set FILE ...] [--label TEXT]` | A new install; with `--set`, an edited database (a season pack, CSV or group JSON files) in use from the start |
| `python3 patch.py list SWOS [--json]` | What the save directory holds: the machine, the custom set, the edited database, tactics, definitions (with their backups), saves with their databases, the match log, other files, with every fingerprint |
| `python3 patch.py check FILE ...` | Checks `.TAC`, `.DEF`, `CUSTOMS.EDT`, `DBASE.CFG`, link files, `MATCHES.LOG` and `MACHINE.CFG` as the game and the editors do |
| `python3 patch.py export SWOS OUT` | The custom set as JSON and CSV, the tactics and definitions as JSON, the edited database's groups as JSON, and saves, links and the manifest as JSON for reading only |
| `python3 patch.py import SWOS FILE ... [--replace]` | JSON and CSV files of export, `.TAC` and `.DEF` files into the save directory, checked as the editors check them |
| `python3 patch.py db export SWOS OUT` | Every database group as JSON, `players.csv`, `teams.csv` (with the strength columns) and `cups.csv` |
| `python3 patch.py db import SWOS FILE ... [--label TEXT]` | CSV, group JSON or a season pack into a new version of the edited set |
| `python3 patch.py db diff SWOS PACK.json [--label TEXT]` | A season pack: only the fields that differ from the original database |
| `python3 patch.py db apply SWOS PACK.json` | A season pack into a new version of the set |
| `python3 patch.py db check SWOS` | Checks the set as the editors do |
| `python3 patch.py db switch SWOS on\|off` | USE EDITED DATABASE at the next start |
| `python3 patch.py report SWOS_OR_SAVES ... --output OUT` | Standings, cup results and scorers of `.DIY`, `.PRE` and `.SEA` saves as CSV and Markdown |
| `python3 patch.py results SWOS_OR_LOGS ... --output OUT [--def FILE] [--teams LIST]` | The match logs of several installs as one table: matches, standings and scorers |
| `python3 patch.py machine SWOS NAME` | Renames the install's machine for the match log |

### CSV files

`players.csv` has a row per player: `group`, `ordinal` and `slot` name the
player (do not change them), `team` is for reading, and `shirt`, `name`,
`nationality` (the game's three-letter label), `position`, `appearance`,
the seven skills, their `_special` flags and, for a goalkeeper only,
`rating` can be changed. `teams.csv` has a row per team: `name`, `coach`,
`division`, the kit columns and `tactic` can be changed; the strength
columns are for reading. A file may hold only the rows and columns you
change. Every change is checked as the editors check it; a refusal names
the file, row, column and reason, and nothing is written.

The custom set has the same files as `customs-players.csv` and
`customs-teams.csv` (`export` and `import`).

### Example files

`docs/examples/` holds files that work as they are; every name and value in
them is invented, so they hold no data of the game:

| File | What it is | Use it with |
|---|---|---|
| `season-26-27.json` | A season pack: four clubs of the English league renamed, with new coaches and one new player each | `install --set`, `db apply` |
| `players.csv`, `teams.csv` | The same edits as CSV, with only the key columns and the changed columns | `db import` |
| `customs-players.csv`, `customs-teams.csv` | Two custom teams renamed, with new coaches and one new player each | `import` |
| `DIAMOND.TAC.json` | A tactic | `import` |
| `CLUBCUP.DEF.json` | A cup of the four renamed clubs, made with the season pack's set | `import` |

```sh
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output SWOS --set docs/examples/season-26-27.json
python3 patch.py import SWOS docs/examples/customs-players.csv docs/examples/customs-teams.csv
python3 patch.py import SWOS docs/examples/DIAMOND.TAC.json
python3 patch.py import SWOS docs/examples/CLUBCUP.DEF.json
python3 patch.py check SWOS/data/DIAMOND.TAC SWOS/data/CLUBCUP.DEF
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output PLAIN
python3 patch.py db import PLAIN docs/examples/players.csv docs/examples/teams.csv --label "SEASON 26/27"
python3 patch.py db switch PLAIN on
```

The first install starts with the season's set in use, its custom teams
hold the two renamed teams, EDIT TACTICS loads DIAMOND into a slot, and LOAD
DEFINITION lists CLUB CUP. The second install gets the same set from the CSV
files: both show the same fingerprint.

### Reports

`report` reads competition saves (never writes them) and writes
`standings.csv`, `cup.csv`, `scorers.csv` and `report.md`. A save holds what
the game keeps: a league its table, not its single matches; a cup the round
in play; a tournament the stage in play. Save a competition after each
round to report every round. `results` merges the match logs: every match
played on any machine, the standings and the scorers of the matches it
selects (a `.DEF`'s teams and points, a team list, a family, a machine).

## 10. Season update and tournament day

This chapter goes through one season of a tournament group step by step:
an organiser brings the database up to date and shares it as a season
pack, every machine installs it, a tournament definition is shared, the
tournament is played on several machines, and the results are put
together. The example files are in `docs/examples/` (see "Example files"
in chapter 9); their names, players and values are invented.

### 1. Make the season pack (the organiser)

Install the game once for the organiser and export the database:

```sh
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output ORGANISER
python3 patch.py db export ORGANISER export
```

Edit `export/players.csv` and `export/teams.csv` with a spreadsheet and keep
only the rows you changed (or all of them; the columns you do not change
may go too). The example files `docs/examples/players.csv` and
`docs/examples/teams.csv` are such edits; import them, or your own, with a
label, and make the pack:

```sh
python3 patch.py db import ORGANISER docs/examples/players.csv docs/examples/teams.csv --label "SEASON 26/27"
python3 patch.py db diff ORGANISER season-26-27.json
```

`season-26-27.json` now holds only the changed fields and the label. It
contains no other data of the game, so it can be shared. Editing in the
game's EDIT DATABASE and then `db diff` gives the same kind of pack.

### 2. Install it on every machine

```sh
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output SWOS --machine "TABLE 1" --set docs/examples/season-26-27.json
python3 patch.py install "Disk 1.adf" "Disk 2.adf" --output SWOS2 --machine "TABLE 2" --set docs/examples/season-26-27.json
python3 patch.py list SWOS
python3 patch.py list SWOS2
```

Each install starts with the set in use; both main menus and both lists
show the same line `DATABASE: SEASON 26/27` with the same fingerprint. An
existing install takes a pack as a new version of its set, switched on for
the next start:

```sh
python3 patch.py db apply SWOS season-26-27.json
python3 patch.py db switch SWOS on
```

### 3. Share the tournament definition

Set up the tournament in DIY COMPETITION and save it with SAVE DEFINITION
(with its teams), or start from the example:

```sh
python3 patch.py import SWOS docs/examples/CLUBCUP.DEF.json
python3 patch.py import SWOS2 docs/examples/CLUBCUP.DEF.json
python3 patch.py check SWOS/data/CLUBCUP.DEF
```

A definition made with the set in use records it, so a machine with
another database asks before loading it. `python3 patch.py export SWOS
OUT` writes the definitions of an install as JSON for other machines.

### 4. Play

On each machine: DIY COMPETITION, LOAD DEFINITION, CLUBCUP, then CHOOSE
TEAMS and YES. Play the matches of that table. Every match the game plays
is added to that machine's match log. Save the competition after each
round if you also want `report`.

### 5. Put the results together

```sh
python3 patch.py results SWOS SWOS2 --def SWOS/data/CLUBCUP.DEF --output results
python3 patch.py report SWOS --output report
```

`results/standings.csv`, `results/scorers.csv` and `results/matches.csv`
hold every match of the definition's teams played on both machines, in the
game's ranking, with the definition's points for a win; `results.md` is a
summary to read or publish. A log copied twice is counted once.

## 11. Messages

Every failure shows a short message and keeps what you were editing. The
common reasons:

| Reason | Meaning |
|---|---|
| `DISK FULL` | A write failed; the previous file is unchanged |
| `WRITE PROTECTED` | The save directory or the file cannot be written |
| `TOO MANY FILES` | `data/` would hold more than 512 files, or more than 45 game saves |
| `READ ERROR` | A file could not be read |
| `FILE DAMAGED` | A file failed its check; the problem is named |
| `TEAM NOT FOUND` | A definition names a team the database in use does not hold |
| `DATABASE NOT FOUND` | The files of a set or of a bound save are missing or changed |
| `DATABASE LINK DAMAGED`, `DATABASE LINK NOT SAVED` | A save's link file is damaged, or could not be written |

Titles say what did not happen: `CUSTOM TEAMS NOT SAVED`, `DATABASE NOT
SAVED`, `DEFINITION NOT SAVED`, `TACTIC NOT SAVED`, `TACTIC NOT ACCEPTED`,
`COMPETITION NOT STARTED`. Notes explain what the editors do not do where
you would look for it: `COMPETITION IN PROGRESS` (a started competition
keeps its teams), `VALUE CANNOT BE SET`, `EUROPEAN CLUB CUPS`, `FOREIGN
PLAYER MARKET` and `FORMAT SAVE DISK`.

## 12. Limits

- Edits are used by competitions started afterwards. A started
  competition, season or career keeps its own teams; an existing career
  is never changed.
- A player's price is worked out by the game from his rating; it cannot be
  set on its own.
- A user tactic must be loaded into its slot again after a restart.
- A DIY or preset save keeps only the round or stage in play, so a report
  of earlier rounds needs a save of each round (or the match log).
- Goals of a penalty shootout belong to no player; when a match has more
  scorers than the game lists, the minutes of the extra goals are not
  known.
- The match log's time is when the game was started, the same for every
  match of a session; a machine without a clock logs no time.
- Only the supported release and the machine described in chapter 1 are
  supported. The editors were tested in emulation only.
