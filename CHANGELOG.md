# Changelog

## V0.94b 12-11-2026

The same fingerprint for the same database, and easier exchange of data.

- The fingerprint of the edited database no longer depends on how often a
  set was saved: it covers the label and the set's files. Every install
  that applies the same season pack shows the same code in the main menu,
  in `patch.py list` and in the match log, and a definition made on one of
  them loads on the others without a question. The code of a set differs
  from the one V0.93b showed, so every machine of a tournament needs the
  same version of the editors. Definitions saved by earlier versions load
  as before.
- CSV files go in as a spreadsheet saves them: commas, semicolons or tabs,
  with or without a byte order mark, empty rows skipped, new names in small
  letters stored in capitals. `export` and `db export` take `--semicolon`.
  Several players or teams files go in with one command.
- `export` always writes the custom teams, and `import` takes the directory
  `export` or `db export` wrote as it is, on the same install or another;
  it also takes season packs and the database's CSV files.
- A season pack makes the database exactly the pack's: the groups and cups
  that become the original ones again are listed. `db diff` prints the
  fingerprint every install of the pack shows and says when the install it
  read differs from it, and the commands say when USE EDITED DATABASE is
  off. A dry run shows every changed field with its old and new value.
- Fixed: of two players files in one `db import` only the last was used; a
  pack without cups kept the cup participants an install had changed;
  malformed JSON files ended in a Python traceback.

## V0.93b 10-11-2026

Easier editing.

- Your user tactics are kept: a tactic you save in EDIT TACTICS or load with
  a definition is written to `TACTICS.CFG` in the save directory and is back
  in its slot at the next start and in every new competition. `patch.py`
  checks, lists, exports and imports the file.
- `patch.py import`, `db import` and `db apply` take `--dry-run`: they check
  everything and list what would change, and write nothing.
- The player screen has PREVIOUS PLAYER and NEXT PLAYER, the keys 0-7 type
  a skill, and Fire on NATIONALITY opens a list of all labels.
- Name fields have a cursor: LEFT and RIGHT move it, characters go in and
  are deleted at it.
- A group of EDIT DATABASE has a column heading and a SHOW button that
  lists one division at a time; Fire on the chosen club opens it.
- The highlight stays where it was when a screen is drawn again, and
  CANCEL or Esc asks before it discards changes.

## V0.92b 04-11-2026

A small update.

- The game no longer shows its picture of the old disk 1 for a second after
  the intro. The disks are always there, so nothing waits for that disk.

## V0.91b 16-10-2026

Fixes for edge cases.

- Saves and tactics whose names the game cannot hold (longer than 8
  characters before the suffix, or not in capitals) are no longer shown to
  the game, whose lists could overrun with them; `patch.py import` refuses
  such a tactic and `list` marks the files the game does not show.
- A save longer than the game's memory for it is refused with `DISK ERROR`
  instead of being read past that memory.
- LOAD DEFINITION with a damaged `CUSTOMS.EDT` reports the edited custom
  teams as not found instead of closing the screen or starting with the
  game's own custom teams.
- `patch.py db check`, `db import` and `db apply` accept a set that the
  editor saved with a user tactic or a goalkeeper rating the team already
  had; the custom set likewise.
- EDIT DATABASE: an empty `DBASE.CFG` beside a sound `DBASE.BAK` counts as
  damaged, so no new set replaces the backup; REMOVE OLD VERSIONS no longer
  stops at an empty file and is refused after a SAVE that could not write
  `DBASE.BAK`; END COPY has its own key E; several lines that were cut or
  stayed on the screen are fixed.
- EDIT CUSTOM TEAMS: a `CUSTOMS.EDT` with another team count is no longer
  backed up over a good `CUSTOMS.BAK`; a cancelled IMPORT no longer changes
  what OK accepts.
- SAVE DEFINITION names `NAME.DEF.BAK` when its backup fails.
- `patch.py`: names in JSON imports are checked against the characters the
  game shows, a definition JSON with a value out of range is refused with a
  message, files of a set copied in lower case are found, `check` takes
  `NAME.DEF.BAK` and `import --replace` keeps it, `db switch on` checks the
  set's files first.

## V0.9b 13-10-2026

The first release.

- WHDLoad install from your own disk images with `patch.py`: the game's
  files come from the unchanged disk images, the save disk is the directory
  `data/` of the install, and the game never asks for a disk.
- EDIT CUSTOM TEAMS: a player screen with every field, team settings with a
  strength summary, copy and paste of players, the checks of a team before
  it is accepted, and a save that keeps a verified backup first.
- EDIT TACTICS: every tactic checked before it is used, exact `.TAC` files,
  tactics you loaded kept when a new competition starts.
- DIY COMPETITION: RULES, SAVE DEFINITION and LOAD DEFINITION, tournament
  definitions with their teams and tactics.
- EDIT DATABASE: the game's clubs and national teams for new competitions,
  seasons and careers, with a set label and a fingerprint, the European club
  cups and the foreign player market following the edited database, and
  competitions bound to the database they started with.
- The match log: every match the game plays added to `data/MATCHES.LOG`.
- `patch.py`: install, list, check, export and import as JSON and CSV, the
  database as JSON and CSV with season packs, reports of competition saves
  and the results of the match logs of several machines.
- EDIT DATABASE shows the version and the author.
