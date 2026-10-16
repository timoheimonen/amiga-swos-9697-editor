; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The contract between the WHDLoad slave and the code it serves: the slave
; block at a fixed address, the service operations behind its veneer, the
; save volume and the results of file operations. Include after swos2.i.
;
; The slave replaces the game's physical disk layer disk_io with a jump into
; itself. Nothing else reaches the rest of that routine, so the base patch
; table puts the slave block there: the veneer through which game-side code
; and the editor call the slave, followed by the slave's state as seen from
; the game (expansion memory, editor load result, save-volume counters).

SLAVE_BLOCK             equ disk_io+6
SB_SERVICE              equ $00         ; JMP abs.l into the slave's service dispatcher
SB_MAGIC                equ $08         ; long SLAVE_BLOCK_MAGIC
SB_VERSION              equ $0C         ; word SLAVE_BLOCK_VERSION
SB_FLAGS                equ $0E         ; word, SBF_* bits
SB_SLAVE                equ $10         ; long: load address of the slave
SB_EXPMEM               equ $14         ; long: expansion memory (ws_ExpMem)
SB_EXPMEM_SIZE          equ $18         ; long: its size
SB_EDITOR_STATUS        equ $1C         ; long: EDST_*
SB_EDITOR_STEP          equ $20         ; long: last EDSTEP_* reached
SB_EDITOR_DETAIL        equ $24         ; long: failing entry or value
SB_EDITOR_BASE          equ $28         ; long: editor base, 0 when not loaded
SB_FILE_RESULT          equ $2C         ; long: result of the last save-volume operation
SB_FILE_OPERATIONS      equ $30         ; long: save-volume operations so far
SB_CATALOG_NAMES        equ $34         ; long: names in data/ at the last listing
SB_CATALOG_LISTINGS     equ $38         ; long: listings of data/ so far
SB_SIZE                 equ $40

slave_service           equ SLAVE_BLOCK+SB_SERVICE
SLAVE_BLOCK_MAGIC       equ 'SWHD'
SLAVE_BLOCK_VERSION     equ 1
SBF_EDITOR              equ 0           ; bit: the editor is loaded and hooked
SBF_CATALOG_FULL        equ 1           ; bit: data/ holds more names than listed

; Editor load (SB_EDITOR_STATUS)
EDST_NOT_RUN            equ 0
EDST_ACTIVE             equ 2           ; loaded, initialized, hooks installed
EDST_ABSENT             equ -1          ; no editor file in the install
EDST_BAD_LENGTH         equ -4          ; the file has another length
EDST_READ_FAILED        equ -5          ; the file could not be read
EDST_BAD_CRC            equ -6          ; the file has another CRC-32
EDST_BAD_HEADER         equ -7          ; identity header differs
EDST_INIT_FAILED        equ -9          ; editor_init refused (native data differs)
EDST_HOOK_MISMATCH      equ -10         ; a hook site differs; no hook installed

; Steps of the editor load (SB_EDITOR_STEP)
EDSTEP_LOAD             equ 1
EDSTEP_VERIFY           equ 2
EDSTEP_RELOCATE         equ 3
EDSTEP_INIT             equ 4
EDSTEP_HOOKS            equ 5
EDSTEP_DONE             equ 6

; ---------------------------------------------------------------------------
; Drives as the game's file system sees them under the slave
; ---------------------------------------------------------------------------
DRIVE_DISK1             equ 0           ; Disk.1 (markers swos4.dk1, grafs/disk2.raw)
DRIVE_DISK2             equ 1           ; Disk.2 (marker swos4.dk2)
DRIVE_SAVE              equ 2           ; the save directory data/ (marker swos4.dku)
DRIVE_MASK              equ (1<<DRIVE_DISK1)|(1<<DRIVE_DISK2)|(1<<DRIVE_SAVE)
SAVE_DISK_MODE          equ 4           ; disk mode of the save volume

; ---------------------------------------------------------------------------
; Service operations: D0.w = operation, JSR slave_service. D0.l returns the
; result (flags set by TST.L D0); D1 returns a value where listed and is
; changed by the other operations too. Every other register is preserved.
; Names are 1-29 characters with a dot, without "/" or ":", relative to the
; save directory.
; ---------------------------------------------------------------------------
SVC_LIST                equ 1           ; A1 = records, D1 = capacity in records
                                        ; -> D1 = names in data/ (all of them; at
                                        ; most the capacity is stored),
                                        ; D2 = recognized native saves among them
SVC_SIZE                equ 2           ; A0 = name -> D1 = length
SVC_READ                equ 3           ; A0 = name, A1 = destination, D1 = capacity
                                        ; -> D1 = length; nothing is read when the
                                        ; file is longer than the capacity
SVC_READ_PART           equ 4           ; A0 = name, A1 = destination, D1 = length,
                                        ; D2 = offset -> D1 = bytes read
SVC_WRITE               equ 5           ; A0 = name, A1 = source, D1 = length;
                                        ; read back and compared before success
SVC_DELETE              equ 6           ; A0 = name
SVC_APPEND              equ 7           ; A0 = name, A1 = source, D1 = length,
                                        ; D2 = the file's known length (0: no
                                        ; file yet, then it is created) -> D1 =
                                        ; offset at which it was added (D2); the
                                        ; bytes before it are never written, a
                                        ; file of another length is refused, and
                                        ; the added bytes are read back and
                                        ; compared before success
SVC_TIME                equ 8           ; A1 = 8 bytes -> the date and time (year
                                        ; word, month, day, hour, minute,
                                        ; second, zero) when the machine knows
                                        ; it, as WHDLoad read it at its start;
                                        ; STE_NO_TIME and zeros otherwise
SVC_LAST                equ SVC_TIME

; A listing record: the name, NUL-terminated and zero padded.
FS_RECORD_SIZE          equ 32
FS_NAME_MAX             equ 29          ; characters of an editor name
NATIVE_NAME_MAX         equ 30          ; characters of a name in a native record
OFS_TYPE_FILE           equ $FD         ; type byte of a file in a native record

; Results: 0 success; positive values are the game's own disk results, so the
; native messages apply; negative values are refusals of the service.
FSE_WRITE_PROTECTED     equ $1C         ; DISK WRITE PROTECTED
FSE_NO_DISK             equ $1D         ; NO DISK IN DRIVE (no save directory)
FSE_READ_ERROR          equ $1B         ; DISK ERROR
FSE_NOT_FOUND           equ $CD         ; FILE NOT FOUND
FSE_DISK_FULL           equ $DD         ; DISK FULL
FSE_BAD_PATH            equ $CC         ; DISK ERROR (name not acceptable)
STE_TOO_LARGE           equ -2          ; file longer than the capacity
STE_EMPTY               equ -3          ; zero length
STE_SHORT_READ          equ -4          ; fewer bytes than requested
STE_VERIFY              equ -5          ; readback differs
STE_DIR_FULL            equ -6          ; the listing cannot hold another name
STE_SAVES_FULL          equ -7          ; would be the 46th recognized save
STE_NOT_FOUND           equ -8          ; file does not exist
STE_BAD_NAME            equ -9          ; empty, too long, no dot or a path
STE_BAD_OPERATION       equ -11         ; unknown service operation
STE_NO_TIME             equ -12         ; the machine has no date (no clock)
STE_CHANGED             equ -13         ; the file's length is not the one known

; The slave admits a new name from the editors only while data/ holds
; fewer than this many names.
SAVE_DIR_MAX_NAMES      equ 512

; Native listing limits kept by the save directory: the chooser's buffer
; holds 60 raw records before it reaches the custom-team buffer, and it
; offers at most 45 recognized saves.
NATIVE_LIST_MAX         equ 60
NATIVE_SAVES_MAX        equ 45
; A save the game lists is named as the game names its saves: a base of at
; most this many characters, then the suffix (.DIY .PRE .SEA .CAR .TAC
; .HIL) in capitals at the first dot. The chooser copies a chosen name into
; 13-byte buffers without a bound.
SAVE_BASE_MAX           equ 8
