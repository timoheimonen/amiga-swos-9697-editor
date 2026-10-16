# Changelog

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
