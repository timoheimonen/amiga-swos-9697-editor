# The save directory `data/`

The game's save disk is the directory `data/` of the install. The game's own
file system addresses it as drive 2.

| Game operation | In `data/` |
|---|---|
| Read a file | The whole file; a missing file is FILE NOT FOUND; a save or `CUSTOMS.EDT` longer than the memory the game reads it into is DISK ERROR and nothing is read |
| Write a file | The file is written (replaced); a failed write is DISK FULL, DISK WRITE PROTECTED (a write-protected volume or file) or, without the directory, NO DISK IN DRIVE |
| Delete a file | The file is deleted (an empty one too) |
| List the disk | Only the game's saves and `CUSTOMS.EDT`, sorted by name: names as the game gives them, 1-8 characters and then `.DIY .PRE .SEA .CAR .TAC .HIL` in capitals, at most 45, the first by name. The game copies a chosen name into buffers of 12 characters and a NUL, so a longer name is never listed |
| Format the disk | Nothing changes; no file is deleted |

The editors list, read and write the same directory through the slave's
services: names of 1-29 characters with a dot; reads never pass the caller's
buffer; every write is read back and compared before it counts as done; new
names are admitted while `data/` holds fewer than 512 names, new game saves
while fewer than 45 are present. A name the listing holds is a file even when
its length reads as 0 (an empty file, or one WHDLoad no longer sees after a
failed write to it): it is no new name, and it can be deleted. The match log `MATCHES.LOG` grows by
appending: the slave adds a record at the length the editors know, never
rewrites the bytes before it, refuses a log of another length, and reads the
added bytes back. `MACHINE.CFG` holds the install's
machine name and identity. Neither file appears in the game's own listing.
The slave also passes the date and time of WHDLoad's clock to the editors when
the machine has one, as WHDLoad read it when it started.

Around each write, delete or listing WHDLoad runs the operating system for a
moment: the slave sets the sound volumes to 0 before and releases a key the
game would otherwise still see as held afterwards.

WHDLoad keeps the files it has read in memory, so a file changed in `data/` from
outside while the game runs is seen after the game is started again. The
install's icon gives WHDLoad `NOWRITECACHE`, so every save reaches the disk at
once, and `WRITEDELAY=10`, so a save takes a fraction of a second.
