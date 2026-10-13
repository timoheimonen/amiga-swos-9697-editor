# Patch points

Addresses are those of `SWOS2` relocated to `$180000`. The base patch table is
applied by the slave before the game starts; the runtime hook table belongs to
the editors and is installed only after the editor file has been checked. Both
tables check the CRC-32 of every site first and write nothing unless all match.

## Base patch table (the slave)

| Address | Bytes | Game code | Replacement |
|---|---:|---|---|
| `$180438` | 6 | Entry of the drive search for a disk mode (marker file per mode) | `JMP` to the slave: disk 1 and the old-disk marker on drive 0, disk 2 on drive 1, the save disk on drive 2, found at once |
| `$1804AC` | 6 | Entry of the check before FORMAT SAVE DISK (refuses game disks in DF0) | `JMP` to the slave: the save directory on drive 2 is selected and accepted |
| `$1805C0` | 6 | Entry of the file-system dispatcher (read, write, delete, list, format, open, close, read, seek) | `JMP` to the slave: operations on drive 2 work on `data/`; all others continue in the game at `$1805C6` |
| `$180E7E` | 70 | Entry of the physical disk layer (the only code that drives the floppy hardware) | `JMP` to the slave's disk layer (sector reads from `Disk.1`/`Disk.2`, writes refused), followed by the slave block |

## Slave block at `$180E84`

| Offset | Size | Contents |
|---|---:|---|
| `$00` | 6 | `JMP` to the slave's services (operation number in D0) |
| `$08` | 4 | `SWHD` |
| `$0C` | 2 | Version 1 |
| `$0E` | 2 | Flags: bit 0 editors loaded, bit 1 listing of `data/` possibly incomplete |
| `$10` | 4 | Address of the slave |
| `$14` | 4 | Expansion memory |
| `$18` | 4 | Its size |
| `$1C` | 4 | Editor load status: 2 loaded, -1 no file, -4 length, -5 read, -6 CRC-32, -7 identity, -9 init refused, -10 hook site differs |
| `$20` | 4 | Last load step reached |
| `$24` | 4 | Detail of a failure (length found, failing hook) |
| `$28` | 4 | Editor base, 0 when not loaded |
| `$2C` | 4 | Result of the last save-directory operation |
| `$30` | 4 | Save-directory operations so far |
| `$34` | 4 | Names in `data/` at the last listing |
| `$38` | 4 | Listings of `data/` so far |

## Runtime hook table (the editors)

| Address | Bytes | Game code | Replacement |
|---|---:|---|---|
| `$1A0432` | 4 | Operand of the main menu's template | The extended main menu with EDIT DATABASE |
| `$1B1C82` | 4 | Operand of the DESIGN DIY LEAGUE template | The page with RULES and the definition entries |
| `$1B7394` | 4 | Operand of the EDIT CUSTOM TEAMS template | The page with SETTINGS and PLAYER |
| `$1D1CCA` | 6 | `JSR` reading a team group (`data/team.nnn`) | `JSR` to the group gateway (edited groups from `data/`) |
