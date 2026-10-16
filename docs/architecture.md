# Architecture

How the WHDLoad slave and the editors fit into Sensible World of Soccer
'96-'97 (the release with `SWOS2`, "SWOS VERSION 152", on disk 1 [a2] and
disk 2), what `patch.py` and the build do, and the files the editors write.
Addresses are those of the game's executable `SWOS2` relocated to
`$180000`, where the game's own loader puts it on an A1200 with 2 MiB of chip
memory.

## Overview

```text
patch.py install ──► SWOS/  SWOS.slave  SWOS.info  Editor.bin  Disk.1  Disk.2  data/
                              │                       │          │       │       │
WHDLoad ──► SWOS.slave ───────┘                       │          │       │       │
              reads SWOS2 and SWOS2.REL from Disk.1 ◄─┼──────────┘       │       │
              relocates SWOS2 to $180000              │                  │       │
              base patch table: floppy access ──► Disk.1, Disk.2 (read only)     │
                                save disk ──────► data/ ◄────────────────────────┘
              loads Editor.bin into expansion memory, checks it,
              runtime hook table: the editors' entries into the game
              starts the game as its own loader does
```

The game runs as on its floppy disks: its own menus, matches, file system
and saves. The slave replaces only the layer that talks to the floppy drives
and the save disk; the editors add entries, actions and screens to the
game's own menus and work on the game's own data in memory.

## The slave (`whdload/`)

`whdload/src/slave.s` with `disk_service.s` and `file_service.s` is one
position-independent code hunk of about 4.5 KiB (linked at two origins to the
same bytes, so the hunk needs no relocations), written against an own
`whdload_api.i` from the WHDLoad autodoc. Its header asks WHDLoad for a
68020, AGA, 2 MiB of base memory, 256 KiB of expansion memory and the
emulation of a division by zero; F10 quits.

Start-up:

1. **The executable.** A small reader of the game disk's OFS file system
   (every block's checksum, type, owner and sequence checked) reads `SWOS2`
   and `SWOS2.REL` from `Disk.1` with `resload_DiskLoad`; `resload_Decrunch`
   unpacks them. Their CRC-32 values, and the relocated image's, must equal
   the values the build assembled in; otherwise WHDLoad quits with a message
   naming the reason.
2. **Relocation** to `$180000` as the game's loader does it: each entry of
   `SWOS2.REL` adds `$08` to one byte, without a carry.
3. **The base patch table** (below), checked by CRC-32 and written all or
   nothing: the game's floppy access goes to the slave.
4. **The slave block** at `$180E84`: the entry of the slave's services for
   the editors, the slave's and the expansion memory's addresses, and the
   editor's load state.
5. **The editors**: `Editor.bin` is loaded into the expansion memory, its
   length, CRC-32 and identity checked, relocated, initialized, and its
   runtime hook table installed, all or nothing (below). Any failure leaves
   the original game running under the slave, without an EDIT DATABASE
   entry.
6. **The hand-over** of the game's own loader: supervisor mode, interrupts
   and DMA off, the registers the loader passes, `JMP $180000`.

After the hand-over the game uses no operating system. Around each write,
delete or listing of the save directory the slave lets WHDLoad run the
operating system for a moment (sound volumes set to 0 before, a key the game
would still see as held released afterwards).

### What the slave replaces

| Site | Replaced by |
|---|---|
| `$180438` the game's search for its disks | the slave's: disk 1 is drive 0, disk 2 drive 1, the save disk drive 2 |
| `$1804AC` the save disk's format check | accepted for the save directory |
| `$1805C0` the file system's driver call | drive 2 (the save disk) from `data/`; the game disks continue in the game's own file system |
| `$180E7E` the physical disk layer | sectors of `Disk.1` and `Disk.2` with `resload_DiskLoad`; writes refused |

So the game's own file system reads its files from the unchanged disk
images, and the save disk is a directory: saves, loads, deletes and the
game's listings work on the files of `data/`. The game's own listing shows
only its saves (`.DIY .PRE .SEA .CAR .TAC .HIL`, at most 45, as its chooser
holds) and `CUSTOMS.EDT`; FORMAT SAVE DISK changes nothing.

### The slave's services

The editors call the slave through the veneer in the slave block:

| Service | |
|---|---|
| `SVC_LIST` | the names in `data/` into a buffer of a given capacity, and the number of game saves |
| `SVC_SIZE`, `SVC_READ`, `SVC_READ_PART` | a file's length; a read that never passes the caller's capacity |
| `SVC_WRITE` | a file written and read back in 4 KiB pieces and compared before success; new names admitted only below 512 names (and new game saves below 45) |
| `SVC_APPEND` | bytes added at the length the caller knows (a file of another length is refused), the added bytes read back |
| `SVC_DELETE` | a file deleted, an empty one too |
| `SVC_TIME` | WHDLoad's date and time when the machine has a clock (read once, when WHDLoad starts) |

Names have 1-29 characters with a dot; the game's own list shows only its
saves named as it names them (1-8 characters and the suffix in capitals: its
chooser copies a chosen name into 13-byte buffers), and a native read of a
save never passes the memory the game reads it into. WHDLoad keeps the files it has read
in memory (the install's icon asks for `PRELOAD`), so a file changed in
`data/` from outside while the game runs is seen after a restart; after a
failed write to an existing file WHDLoad does not see that file again in the
same session. `NOWRITECACHE` writes every file at once, `WRITEDELAY=10` waits
0.2 seconds after a write instead of WHDLoad's three.

## The editors (`src/editor/`)

### The image and its loading

`Editor.bin` is linked at origin 0 and checked by the build: it starts with
an identity header (magic `SWED`, version, length, the `SWOS2` identity, the
offsets of its tables), then the code and data, a relocation table (the
fields that hold offsets into the image), an import table (the fields that
hold addresses in `SWOS2`) and the runtime hook table. The slave adds the
image's base to each relocated field and checks every imported address
against the supported `SWOS2`.

The expansion memory (256 KiB) holds the slave's area (the CRC-32 table, the
listing of `data/`, a read-back buffer), the editor image, the editors'
working data, the working copy of one database group and the editors' own
listing of `data/`. The editors take nothing from the game's memory: the
game's own cache stays as without them. Every screen is drawn by the CPU into
the game's own menu screen, so no editor data needs chip memory.

### Hooks

Every place where the editors change the game is an entry of a patch
manifest (the address, the length of the bytes replaced, and the CRC-32 of
the bytes expected there; the build checks the SHA-256). The base patch table
belongs to the slave; the runtime hook table to the editors: about fifty
six-byte `JSR`/`JMP` sites and pointer operands, at the end of a match, in
the custom-team, tactic and DIY flows, in the competition saves and loads,
in the loader of the database groups and in the European cups' and transfer
pool's loaders. The slave checks every site's CRC-32 before it writes any
hook.

### Screens

The game's own screens stay where they are: the editors install copies of
the native main menu, the custom-team page and the DIY setup pages with
their own entries added (EDIT DATABASE, the player row actions and
SETTINGS, LOAD DEFINITION, RULES, SAVE DEFINITION, the database caption),
each copy checked against the game's template and within the menu system's
page budget. Everything new (team settings, the player screen, the database
screens, the definition screens, every message) is an own screen on a small
dialog service: buttons and list rows of command lists drawn with a 5x7 font
in 6x8 cells on the game's menu screen, joystick and keyboard only, with the
native parent rebuilt through its restore callback on the return.

### The editors and their data

- **Custom teams**: the native team editor works on a working copy of a team
  record; the editors check the whole record at OK (the reasons of the
  manual), keep an IMPORT's record for its values, and save `CUSTOMS.EDT`
  after a verified `CUSTOMS.BAK`.
- **Tactics**: every tactic is checked (positions on the pitch, no two
  players on one spot, mirror pairs, the base formation) before it is used;
  `.TAC` files are exactly 370 bytes; slots the user loaded or edited are
  kept in copies and restored after the game's reset of a new competition.
- **Tournament definitions**: the rules of a DIY setup page are captured
  into a `.DEF` and applied to the page's scratch state; a definition's
  teams are put into the selection by the game's own team chooser path, so
  the competition is built by the game's own constructors.
- **Database mode**: an edited set of whole database groups in `data/`,
  declared by a manifest. While USE EDITED DATABASE is on, the game's loader
  of a group (the gateway) reads the set's file of that group instead of the
  one on disk 2, and the European cups' copies and the transfer pool are
  read from the set's own copies. A competition is bound to the set it
  started with at the game's reset of a new competition: its save gets a
  link file, and loading the save checks the set first.
- **The match log**: at the end of every match the engine played, the
  editors read the match from the game's state (teams, scores, extra time,
  penalties, the scorers' goals and minutes) and append one record to
  `MATCHES.LOG`.

## patch.py and the build

`patch.py` is the end-user command. The release's `SWOS.slave`, `SWOS.info`
and `Editor.bin` are embedded in it as base64 with their SHA-256 (the
section between its `GENERATED BY build.py` markers), so `install` needs only
Python and the user's disk images, which it checks by SHA-256 and copies
unchanged. The data commands use the codecs in `tools/`: `team_data.py`
(team and player records), `tactic_data.py`, `definition_data.py`,
`competition_data.py` (competition saves), `competition_report.py`,
`custom_set.py` (the team checks), `database_set.py` (the edited database,
CSV and season packs), `match_log.py`, `adf_extract.py` and `rnc.py` (files
of the disk images).

`build.py` assembles the slave and the editors with vasm and vlink, reads
the user's disk 1 to check every patch site (length and SHA-256 of the
expected bytes) and the native menus the editors copy at run time (by
CRC-32), asserts every size and page budget, and writes the embedded
section of `patch.py`. No byte of the game enters the built files.

## Files the editors write

| File | Contents |
|---|---|
| `CUSTOMS.EDT`, `CUSTOMS.BAK` | The custom set as the game writes it (a counted list of 684-byte team records) and its backup |
| `NAME.TAC` | A tactic: the game's 370-byte record |
| `NAME.DEF` | A tournament definition: header `SWOSDEF1`, version, length, CRC-32; the database it was made with, the rules, the teams, the user tactics |
| `DBASE.CFG`, `DBASE.BAK` | The edited set's manifest (`SWOSGRP1`): label, generation, the files of the set with length and CRC-32; the fingerprint is its CRC-32 |
| `Tgggnnnn.GRP` | Generation `nnnn` of database group `ggg` (the game's group format), or of the cups' copies and the transfer pool (100-103) |
| `DBASE.USE` | The remembered state of USE EDITED DATABASE |
| `NAME.DLD`, `.DLP`, `.DLS`, `.DLC` | The link of a `.DIY`, `.PRE`, `.SEA`, `.CAR` save to its set: the save's length and CRC-32 and a copy of the manifest |
| `MATCHES.LOG` | The match log: one record per match (magic `SWML`), each with its own CRC-32 |
| `MACHINE.CFG` | The install's machine name and random identity |

The JSON and CSV files that `patch.py` reads and writes for them are
described in the [file formats](file-formats.md).
