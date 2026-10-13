# SWOS 96-97 In-Game Editors: WHDLoad slave

The WHDLoad slave of the in-game editors for Sensible World of Soccer '96-'97
(Sensible Software / Renegade, 1996), version SWOS2 "SWOS VERSION 152" on disk 1
[a2] and disk 2 [cr HF]. It takes the place of the game's loader: it reads the
game's executable from the unchanged disk image `Disk.1`, relocates it, replaces
the game's floppy access with file access, loads the editors and starts the
game.

## Requirements

- An Amiga with a 68020 or better, the AGA chipset, 2 MiB Chip RAM and at least
  2 MiB Fast RAM, and WHDLoad (the slave uses `ws_Version` 17). WHDLoad refuses
  to start on any other machine.
- The two disk images of the supported release.

## The install

| File | Contents |
|---|---|
| `SWOS.slave` | The slave |
| `SWOS.info` | Icon: default tool `WHDLoad`, tool types `SLAVE=SWOS.slave`, `PRELOAD`, `NOWRITECACHE`, `WRITEDELAY=10` |
| `Disk.1`, `Disk.2` | The game's disk images, unchanged; the slave only reads them |
| `Editor.bin` | The editors; without this file the original game runs |
| `data/` | The save directory: the game's saves, the editors' files, the match log `MATCHES.LOG` and `MACHINE.CFG` (the machine name the log records) |

F10 quits.

## How it works

- **Start-up.** The slave reads `SWOS2` and `SWOS2.REL` from `Disk.1` with its
  own small OFS reader, unpacks them with `resload_Decrunch`, checks their
  CRC-32, relocates the executable to `$180000` as the game's loader does and
  applies its base patch table. Any difference from the supported release quits
  through WHDLoad with a message.
- **Game disks.** The game's own file system reads its files from the disk
  images; only its physical disk layer is replaced by `resload_DiskLoad`.
  Writes to the game disks are refused.
- **Save disk.** The game's save disk is the directory `data/`: saves, loads,
  deletes and listings of the game work on the files there. The game's own
  screens see only its saves (`.DIY .PRE .SEA .CAR .TAC .HIL`, at most 45) and
  `CUSTOMS.EDT`. FORMAT SAVE DISK changes nothing; no file is ever deleted by
  it. WHDLoad keeps the files it has read in memory: a file changed in `data/`
  from outside while the game runs is seen after the game is started again.
- **Editors.** The slave loads `Editor.bin` into WHDLoad's expansion memory,
  checks its length, CRC-32 and identity, relocates it, calls its
  initialization and installs its hooks into the game, all or nothing. If
  anything differs, the game runs without the editors (no EDIT DATABASE entry in
  the main menu).

[docs/](docs/) describes the patch points, the memory map and the save
directory in detail.

## Building

The repository's `build.py` builds the slave together with the editors from
your disk 1 image and embeds both in `patch.py`. The slave is assembled with
vasm (`vasmm68k_mot`, Motorola syntax) and linked with vlink; `build.py` in
this directory is the slave's part of that build and can also be run alone:

```
python3 build.py GENERATED_DIR -o SWOS.slave
```

`GENERATED_DIR` holds `slave_gen.i` (the CRC-32 values of the supported
`SWOS2`, `SWOS2.REL` and editor file) and `base_table.bin` (the base patch
table), which the repository's build writes. The sources include the
editors' shared definitions from `../src/editor/include/`.

## License

MIT, see [LICENSE](LICENSE).
