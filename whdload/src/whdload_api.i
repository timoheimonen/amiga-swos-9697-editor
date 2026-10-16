; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The parts of the WHDLoad slave interface this slave uses, written from the
; WHDLoad autodoc: the slave header layout, slave flags, termination reasons
; and the offsets of the resload functions from the resload base that
; WHDLoad passes to the slave in A0. Resload functions may change D0/D1/A0/A1.

; ---------------------------------------------------------------------------
; Slave header (ws_Version 17)
; ---------------------------------------------------------------------------
; +$00 ws_Security     moveq #-1,d0 / rts
; +$04 ws_ID           "WHDLOADS"
; +$0C ws_Version      word
; +$0E ws_Flags        word, WHDLF_*
; +$10 ws_BaseMemSize  long, BaseMem from address 0 (Chip memory)
; +$14 ws_ExecInstall  long, 0
; +$18 ws_GameLoader   word, offset of the entry point from the header
; +$1A ws_CurrentDir   word, offset of a subdirectory name or 0
; +$1C ws_DontCache    word, offset of a file pattern or 0
; +$1E ws_keydebug     byte, raw key code or 0
; +$1F ws_keyexit      byte, raw key code that quits WHDLoad
; +$20 ws_ExpMem       long, size of the expansion memory; WHDLoad replaces it
;                      with the address of the block before the slave starts
; +$24 ws_name, ws_copy, ws_info   words, offsets of strings
; +$2A ws_kickname     word, 0 when no Kickstart image is used
; +$2C ws_kicksize     long
; +$30 ws_kickcrc      word
; +$32 ws_config       word, offset of the configuration string or 0
WS_EXPMEM               equ $20

; ---------------------------------------------------------------------------
; ws_Flags
; ---------------------------------------------------------------------------
WHDLF_Req68020          equ 1<<4        ; refuse to start below a 68020
WHDLF_ReqAGA            equ 1<<5        ; refuse to start without AGA
WHDLF_ClearMem          equ 1<<12       ; clear BaseMem and ExpMem at start
WHDLF_EmulDivZero       equ 1<<14       ; forward divide by zero to vector $14

; ---------------------------------------------------------------------------
; Termination reasons for resload_Abort
; ---------------------------------------------------------------------------
TDREASON_OK             equ -1
TDREASON_WRONGVER       equ 9
TDREASON_FAILMSG        equ 43          ; primary: pointer to the message

; ---------------------------------------------------------------------------
; Offsets from the resload base
; ---------------------------------------------------------------------------
resload_Abort           equ $04         ; on the stack: reason, primary, secondary
resload_LoadFile        equ $08         ; A0 name, A1 address -> D0 length, D1 error
resload_SaveFile        equ $0c         ; D0 length, A0 name, A1 address -> D0 success, D1 error
resload_ListFiles       equ $14         ; D0 buffer size, A0 directory, A1 buffer
                                        ; -> D0 names stored, D1 error
resload_Decrunch        equ $18         ; A0 source, A1 destination -> D0 length (0: not packed)
resload_FlushCache      equ $20
resload_GetFileSize     equ $24         ; A0 name -> D0 length (0: missing)
resload_DiskLoad        equ $28         ; D0 offset, D1 length, D2 disk, A0 address
                                        ; -> D0 success, D1 error
resload_Control         equ $34         ; A0 tag list -> D0 success
resload_SaveFileOffset  equ $38         ; D0 length, D1 offset, A0 name, A1 address
                                        ; -> D0 success, D1 error
resload_LoadFileOffset  equ $4c         ; D0 length, D1 offset, A0 name, A1 address
                                        ; -> D0 success, D1 error
resload_DeleteFile      equ $58         ; A0 name -> D0 success, D1 error

; resload_Control tags (TAG_USER+$8000000 onwards). WHDLTAG_TIME_GET stores
; in its data the address of a whdload_time structure: WT_DAYS since 1978-01-01,
; minutes and ticks, then the date as bytes (year 78-77 for 1978-2077, month,
; day, hour, minute, second).
WHDLTAG_VERSION_GET     equ $88000011
WHDLTAG_TIME_GET        equ $88000014
TAG_DONE                equ 0
WT_DAYS                 equ 0
WT_YEAR                 equ 12
WT_MONTH                equ 13
WT_DAY                  equ 14
WT_HOUR                 equ 15
WT_MINUTE               equ 16
WT_SECOND               equ 17

; AmigaDOS error codes returned by the file functions in D1
DOSERR_OBJECT_NOT_FOUND equ 205
DOSERR_WRITE_PROTECTED  equ 214
DOSERR_DISK_FULL        equ 221
DOSERR_DELETE_PROTECTED equ 222         ; the file's delete protection bit
DOSERR_FILE_PROTECTED   equ 223         ; the file's write protection bit
