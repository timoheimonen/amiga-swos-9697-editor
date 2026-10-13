# Memory map

## Base memory: 2 MiB Chip RAM at `$000000`

The game sees the memory of an A1200 with 2 MiB Chip RAM and no Fast RAM, as on
the floppy (the slave hands over D7 = `$200000`, D6 = `$F`, D5 = 0).

| Range | Contents |
|---|---|
| `$000000..$17FFFF` | The game's Chip RAM data and its resource cache (`$100000..$17FFFF` and others), as on the floppy |
| `$180000..$1D7369` | `SWOS2`, relocated; the base patches and the editors' hooks are in it |
| `$1D736A..$1FFFFF` | The game's data above its image |

During start-up only, before the game runs, the slave uses `$100000` for the
packed files and `$080000` for the unpacked `SWOS2.REL`.

## Expansion memory: 256 KiB (`ws_ExpMem`, Fast RAM)

| Offset | Size | Contents |
|---|---:|---|
| `$00000` | 32 KiB | Slave area: CRC-32 table, disk block buffer, path and handle names, the remembered listing of `data/`, readback buffer |
| `$08000` | 112,512 bytes | Editor image (code, tables) |
| `$23780` | 36 KiB | Editor working data |
| `$2C780` | 63,616 bytes | Working copy of one team group |
| `$3C000` | 16 KiB | The editors' listing of `data/` (512 names) |

Nothing in the expansion memory is read by DMA: the editors draw with the CPU
into the game's display buffers in Chip RAM.
