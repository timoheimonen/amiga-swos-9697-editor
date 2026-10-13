; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; WHDLoad slave for Sensible World of Soccer '96-'97 (SWOS2, SWOS VERSION
; 152), taking the place of the game's loader SSBOOT.
;
; Start-up:
;  1. Read SWOS2 and SWOS2.REL from the unchanged image Disk.1 with a small
;     OFS reader, unpack both with resload_Decrunch and check their CRC-32.
;  2. Relocate SWOS2 to $180000 with SSBOOT's rule: each REL entry adds one
;     byte, without carry into the next byte.
;  3. Apply the base patch table, all or nothing: the game's physical disk
;     layer, the drive search and the format check come into the slave
;     (disk_service.s), and the save disk becomes the directory data/ of the
;     install (file_service.s). Any difference at a patch site quits through
;     WHDLoad with a message.
;  4. Load the editor file into the expansion memory, check it, relocate it,
;     call its init and install its runtime hook table, all or nothing. Any
;     failure leaves the game without editor hooks.
;  5. Enter the game with SSBOOT's hand-over state.
;
; The slave is position independent and keeps its variables in its own
; memory and in the slave area of the expansion memory (layout.i).

        include "whdload_api.i"
        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "crc32.i"
        include "slave_gen.i"

        section .text,code

SLAVE_FLAGS     equ WHDLF_Req68020|WHDLF_ReqAGA|WHDLF_EmulDivZero|WHDLF_ClearMem
QUIT_KEY        equ $59                 ; F10

; Chip memory used only during start-up; the game fills both areas with
; patterns when it starts ($1800DC..$1800FE).
PACKED_BUFFER   equ $100000             ; packed SWOS2 or SWOS2.REL
PACKED_MAX      equ SWOS2_BASE-PACKED_BUFFER
REL_BUFFER      equ $80000              ; unpacked SWOS2.REL

; Slave area at the start of the expansion memory
SA_CRC_TABLE    equ 0                   ; 256 longwords
SA_BLOCK        equ SA_CRC_TABLE+1024   ; one disk block
SA_PATH         equ SA_BLOCK+512        ; "data/" and a name
SA_PATH_SIZE    equ 64
SA_HANDLE_NAMES equ SA_PATH+SA_PATH_SIZE ; name per read handle 1 and 2
SA_HANDLE_NAME_SIZE equ 32
SA_SORT         equ SA_HANDLE_NAMES+2*SA_HANDLE_NAME_SIZE ; name pointers of the native listing
SA_SORT_SIZE    equ 4*NATIVE_LIST_MAX
SA_CATALOG      equ SA_SORT+SA_SORT_SIZE ; state of the remembered listing
SA_CATALOG_SIZE equ 16
SA_READBACK     equ 2048                ; readback buffer of verified writes
SA_READBACK_SIZE equ 4096
SA_NAMES        equ SA_READBACK+SA_READBACK_SIZE ; names of data/, NUL-separated
SA_NAMES_SIZE   equ SLAVE_AREA_SIZE-SA_NAMES

        if EDITOR_FILE_LENGTH>EDITOR_IMAGE_MAX_SIZE
        fail "the editor file does not fit the editor image area"
        endif
        if SA_CATALOG+SA_CATALOG_SIZE>SA_READBACK
        fail "slave area variables overlap the readback buffer"
        endif

; OFS block layout (Disk.1)
OFS_ROOT        equ 880
OFS_T_HEADER    equ 2
OFS_T_DATA      equ 8
OFS_ST_FILE     equ -3
OFS_HASH_TABLE  equ 24
OFS_HASH_SIZE   equ 72
OFS_FILE_SIZE   equ 324
OFS_NAME        equ 432
OFS_HASH_CHAIN  equ 496
OFS_SEC_TYPE    equ 508
OFS_DATA_FIRST  equ 16
OFS_DATA_KEY    equ 4
OFS_DATA_SEQ    equ 8
OFS_DATA_SIZE   equ 12
OFS_DATA_NEXT   equ 16
OFS_DATA        equ 24
OFS_DATA_MAX    equ 488

;============================================================================
; Slave header
;============================================================================
base:
        moveq   #-1,d0                  ; ws_Security
        rts
        dc.b    "WHDLOADS"              ; ws_ID
        dc.w    17                      ; ws_Version
        dc.w    SLAVE_FLAGS             ; ws_Flags
        dc.l    SWOS2_RAM_SIZE          ; ws_BaseMemSize: 2 MiB Chip at 0
        dc.l    0                       ; ws_ExecInstall
        dc.w    start-base              ; ws_GameLoader
        dc.w    0                       ; ws_CurrentDir
        dc.w    0                       ; ws_DontCache
        dc.b    0                       ; ws_keydebug
        dc.b    QUIT_KEY                ; ws_keyexit
        dc.l    EXPMEM_SIZE             ; ws_ExpMem, replaced by its address
        dc.w    name-base               ; ws_name
        dc.w    copy-base               ; ws_copy
        dc.w    info-base               ; ws_info
        dc.w    0                       ; ws_kickname: no Kickstart image
        dc.l    0                       ; ws_kicksize
        dc.w    0                       ; ws_kickcrc
        dc.w    0                       ; ws_config

name:   dc.b    "Sensible World of Soccer '96-'97",0
copy:   dc.b    "1996 Sensible Software / Renegade",0
info:   dc.b    "In-Game Editors V0.9b",10
        dc.b    "by Timo Heimonen",0
        even

resload:
        dc.l    0                       ; resload base
expmem:
        dc.l    0                       ; expansion memory

;============================================================================
; Entry from WHDLoad: A0 = resload base. Supervisor mode, operating system off.
;============================================================================
start:
        lea     resload(pc),a1
        move.l  a0,(a1)
        lea     base(pc),a0
        move.l  WS_EXPMEM(a0),d0        ; the block's address by now
        lea     expmem(pc),a1
        move.l  d0,(a1)
        movea.l d0,a0
        lea     SA_CRC_TABLE(a0),a0
        bsr.w   crc32_make_table

        bsr.w   load_executable
        bne.s   .wrong_disk
        lea     base_table(pc),a2
        bsr.w   table_check
        bne.s   .wrong_table
        lea     base_table(pc),a2
        lea     base(pc),a4
        bsr.w   table_write
        bsr.w   block_init
        bsr.w   editor_load
        movea.l resload(pc),a2
        jsr     resload_FlushCache(a2)

        ; Hand-over as SSBOOT leaves it ($1A8..$28A): supervisor mode with
        ; interrupts masked, DMA and interrupts off, the forced RAM
        ; description of a 2 MiB Chip machine, A2 = the image.
        move.w  #$2700,sr
        lea     $dff000,a6
        move.w  #$7fff,$9a(a6)          ; INTENA
        move.w  #$7fff,$9c(a6)          ; INTREQ
        move.w  #$7fff,$96(a6)          ; DMACON
        moveq   #SWOS2_FAST_REGIONS,d5
        moveq   #SWOS2_RAM_REGIONS,d6
        move.l  #SWOS2_RAM_SIZE,d7
        lea     SWOS2_BASE,a2
        jmp     (a2)

.wrong_disk:
        pea     msg_wrong_disk(pc)
        bra.s   .abort
.wrong_table:
        pea     msg_wrong_table(pc)
.abort:
        pea     TDREASON_FAILMSG
        move.l  resload(pc),-(sp)
        addq.l  #resload_Abort,(sp)
        rts

;============================================================================
; load_executable: SWOS2 relocated to SWOS2_BASE.
;   out: D0.l = 0 (Z set), or -1 when Disk.1 does not hold the supported
;        SWOS2 and SWOS2.REL
;============================================================================
load_executable:
        movem.l d1-d7/a0-a6,-(sp)
        lea     swos2_name(pc),a0
        lea     PACKED_BUFFER,a1
        move.l  #PACKED_MAX,d1
        bsr.w   ofs_read_file
        bne.w   .fail
        lea     PACKED_BUFFER,a0
        lea     SWOS2_BASE,a1
        movea.l resload(pc),a2
        jsr     resload_Decrunch(a2)
        cmpi.l  #SWOS2_IMAGE_SIZE,d0
        bne.w   .fail
        lea     swos2_rel_name(pc),a0
        lea     PACKED_BUFFER,a1
        move.l  #PACKED_MAX,d1
        bsr.w   ofs_read_file
        bne.w   .fail
        lea     PACKED_BUFFER,a0
        lea     REL_BUFFER,a1
        movea.l resload(pc),a2
        jsr     resload_Decrunch(a2)
        cmpi.l  #SWOS2_REL_SIZE,d0
        bne.s   .fail

        lea     SWOS2_BASE,a0
        move.l  #SWOS2_IMAGE_SIZE,d1
        bsr.w   crc32
        cmpi.l  #SWOS2_RAW_CRC32,d0
        bne.s   .fail
        lea     REL_BUFFER,a0
        move.l  #SWOS2_REL_SIZE,d1
        bsr.w   crc32
        cmpi.l  #SWOS2_REL_CRC32,d0
        bne.s   .fail

        lea     REL_BUFFER,a0
        lea     SWOS2_BASE,a1
        move.l  #SWOS2_REL_SIZE/4-1,d2
        move.l  #SWOS2_IMAGE_SIZE,d3
.rel:
        move.l  (a0)+,d0
        cmp.l   d3,d0
        bcc.s   .fail
        addi.b  #SWOS2_REL_ADDEND,(a1,d0.l)
        subq.l  #1,d2
        bpl.s   .rel

        lea     SWOS2_BASE,a0
        move.l  #SWOS2_IMAGE_SIZE,d1
        bsr.w   crc32
        cmpi.l  #SWOS2_RUNTIME_CRC32,d0
        bne.s   .fail
        moveq   #0,d0
        bra.s   .done
.fail:
        moveq   #-1,d0
.done:
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts

;============================================================================
; ofs_read_file: read a file from the root directory of Disk.1.
;   in:  A0 = name, A1 = destination, D1.l = capacity
;   out: D0.l = 0 and D1.l = length, or D0.l = -1 (missing, larger than the
;        capacity, or a damaged block); every block checksum is checked
;============================================================================
ofs_read_file:
        movem.l d2-d7/a2-a6,-(sp)
        movea.l a0,a3                   ; name
        movea.l a1,a4                   ; destination
        move.l  d1,d7                   ; capacity
        bsr.w   ofs_hash                ; D6 = hash table offset
        move.l  #OFS_ROOT,d1
        bsr.w   ofs_block               ; A5 = block
        bne.w   .fail
        cmpi.l  #OFS_T_HEADER,(a5)
        bne.w   .fail
        move.l  OFS_HASH_TABLE(a5,d6.w),d5
.chain:
        tst.l   d5
        beq.w   .fail
        move.l  d5,d1
        bsr.w   ofs_block
        bne.w   .fail
        cmpi.l  #OFS_T_HEADER,(a5)
        bne.s   .fail
        bsr.w   ofs_name_equal
        beq.s   .found
        move.l  OFS_HASH_CHAIN(a5),d5
        bra.s   .chain
.found:
        cmpi.l  #OFS_ST_FILE,OFS_SEC_TYPE(a5)
        bne.s   .fail
        move.l  OFS_FILE_SIZE(a5),d6    ; length
        beq.s   .fail
        cmp.l   d7,d6
        bhi.s   .fail
        move.l  d5,d4                   ; header block
        move.l  OFS_DATA_FIRST(a5),d5
        moveq   #1,d3                   ; expected sequence number
        move.l  d6,d7                   ; bytes still to copy
.data:
        tst.l   d7
        beq.s   .done
        move.l  d5,d1
        beq.s   .fail
        bsr.w   ofs_block
        bne.s   .fail
        cmpi.l  #OFS_T_DATA,(a5)
        bne.s   .fail
        cmp.l   OFS_DATA_KEY(a5),d4
        bne.s   .fail
        cmp.l   OFS_DATA_SEQ(a5),d3
        bne.s   .fail
        move.l  OFS_DATA_SIZE(a5),d0
        beq.s   .fail
        cmpi.l  #OFS_DATA_MAX,d0
        bhi.s   .fail
        cmp.l   d7,d0
        bhi.s   .fail
        sub.l   d0,d7
        lea     OFS_DATA(a5),a0
        subq.w  #1,d0
.copy:
        move.b  (a0)+,(a4)+
        dbf     d0,.copy
        move.l  OFS_DATA_NEXT(a5),d5
        addq.l  #1,d3
        bra.s   .data
.done:
        moveq   #0,d0
        move.l  d6,d1
        bra.s   .exit
.fail:
        moveq   #-1,d0
.exit:
        movem.l (sp)+,d2-d7/a2-a6
        tst.l   d0
        rts

; ofs_hash: A3 = name. D6.l = offset of its hash-table slot. The AmigaDOS
; hash: length, then hash*13 + upper-case character, 11 bits, modulo 72.
ofs_hash:
        movea.l a3,a0
        moveq   #0,d6
.length:
        tst.b   (a0)+
        beq.s   .counted
        addq.l  #1,d6
        bra.s   .length
.counted:
        movea.l a3,a0
.char:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .end
        bsr.s   upper_case
        mulu.w  #13,d6
        add.l   d0,d6
        andi.l  #$7ff,d6
        bra.s   .char
.end:
        divu.w  #OFS_HASH_SIZE,d6
        clr.w   d6
        swap    d6
        lsl.l   #2,d6
        rts

; ofs_name_equal: A3 = name, A5 = header block. Z set when the block's
; name is the same, ignoring the case of ASCII letters.
ofs_name_equal:
        movem.l d0-d2/a0-a1,-(sp)
        lea     OFS_NAME(a5),a0
        moveq   #0,d2
        move.b  (a0)+,d2                ; BSTR length
        movea.l a3,a1
.char:
        subq.w  #1,d2
        bmi.s   .end
        move.b  (a0)+,d0
        bsr.s   upper_case
        move.b  d0,d1
        move.b  (a1)+,d0
        bsr.s   upper_case
        cmp.b   d0,d1
        beq.s   .char
        bra.s   .done                   ; Z clear
.end:
        tst.b   (a1)                    ; Z set when the name ends too
.done:
        movem.l (sp)+,d0-d2/a0-a1
        rts

; upper_case: D0.b, ASCII a-z to A-Z.
upper_case:
        cmpi.b  #'a',d0
        bcs.s   .done
        cmpi.b  #'z',d0
        bhi.s   .done
        subi.b  #'a'-'A',d0
.done:
        rts

; ofs_block: D1.l = block number. A5 = the block in the slave area,
; D0.l = 0 (Z set) when it was read and its checksum is right, else -1.
ofs_block:
        movem.l d1-d2/a0-a2,-(sp)
        moveq   #-1,d2
        cmpi.l  #DISK_SECTORS,d1
        bcc.s   .done
        move.l  d1,d0
        moveq   #9,d2
        lsl.l   d2,d0                   ; byte offset
        move.l  #DISK_SECTOR_SIZE,d1
        moveq   #1,d2                   ; Disk.1
        movea.l expmem(pc),a5
        lea     SA_BLOCK(a5),a5
        movea.l a5,a0
        movea.l resload(pc),a2
        jsr     resload_DiskLoad(a2)
        moveq   #-1,d2
        tst.l   d0
        beq.s   .done
        moveq   #0,d0
        movea.l a5,a0
        moveq   #DISK_SECTOR_SIZE/4-1,d1
.sum:
        add.l   (a0)+,d0
        dbf     d1,.sum
        move.l  d0,d2                   ; 0 when the block is intact
.done:
        move.l  d2,d0
        movem.l (sp)+,d1-d2/a0-a2
        tst.l   d0
        rts

;============================================================================
; Patch tables (base patch table, runtime hook table; format in editor.i)
;============================================================================
; table_check: A2 = table. D0.l = 0 (Z set) when every site matches, else
; D0.l = 1 and D1.l = index of the first entry that differs.
table_check:
        movem.l d2-d7/a0-a2,-(sp)
        move.w  (a2)+,d6
        moveq   #0,d1
.entry:
        cmp.w   d6,d1
        beq.s   .ok
        move.l  d1,d7
        movea.l PT_ADDRESS(a2),a0
        moveq   #0,d1
        move.w  PT_LENGTH(a2),d1
        bsr.w   crc32
        move.l  d7,d1
        cmp.l   PT_CRC32(a2),d0
        bne.s   .bad
        bsr.s   table_next
        addq.w  #1,d1
        bra.s   .entry
.ok:
        moveq   #0,d0
        bra.s   .done
.bad:
        moveq   #1,d0
.done:
        movem.l (sp)+,d2-d7/a0-a2
        tst.l   d0
        rts

; table_write: A2 = checked table, A4 = base of the image that owns it.
table_write:
        movem.l d0-d6/a0-a2,-(sp)
        move.w  (a2)+,d6
        bra.s   .test
.entry:
        movea.l PT_ADDRESS(a2),a1
        move.w  PT_FIXUPS(a2),d2
        lea     PT_FIXUP_LIST(a2),a0
        add.w   d2,d2
        lea     (a0,d2.w),a0            ; replacement bytes
        move.w  PT_LENGTH(a2),d1
        subq.w  #1,d1
.copy:
        move.b  (a0)+,(a1)+
        dbf     d1,.copy
        movea.l PT_ADDRESS(a2),a1
        lea     PT_FIXUP_LIST(a2),a0
        move.w  PT_FIXUPS(a2),d2
        bra.s   .fixup_test
.fixup:
        move.w  (a0)+,d1
        move.l  a4,d0
        add.l   d0,(a1,d1.w)
.fixup_test:
        dbf     d2,.fixup
        bsr.s   table_next
.test:
        dbf     d6,.entry
        movem.l (sp)+,d0-d6/a0-a2
        rts

; table_next: A2 = table entry -> A2 = next entry. D0, D2 clobbered.
table_next:
        move.w  PT_FIXUPS(a2),d0
        add.w   d0,d0
        moveq   #1,d2
        add.w   PT_LENGTH(a2),d2
        andi.w  #$FFFE,d2
        add.w   d2,d0
        lea     PT_FIXUP_LIST(a2,d0.w),a2
        rts

;============================================================================
; block_init: the run-time fields of the slave block.
;============================================================================
block_init:
        lea     SLAVE_BLOCK,a0
        move.l  expmem(pc),SB_EXPMEM(a0)
        move.l  #EXPMEM_SIZE,SB_EXPMEM_SIZE(a0)
        move.l  #EDST_NOT_RUN,SB_EDITOR_STATUS(a0)
        rts

;============================================================================
; editor_load: load, check and hook the editor (all or nothing). The result
; goes to the slave block; the game starts either way.
;============================================================================
editor_load:
        movem.l d0-d7/a0-a6,-(sp)
        lea     SLAVE_BLOCK,a5
        movea.l expmem(pc),a4
        lea     EDITOR_AREA_OFFSET(a4),a4 ; editor base
        moveq   #EDSTEP_LOAD,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        lea     editor_name(pc),a0
        movea.l resload(pc),a2
        jsr     resload_GetFileSize(a2)
        moveq   #EDST_ABSENT,d7
        tst.l   d0
        beq.w   .done
        moveq   #EDST_BAD_LENGTH,d7
        move.l  d0,SB_EDITOR_DETAIL(a5)
        cmpi.l  #EDITOR_FILE_LENGTH,d0
        bne.w   .done
        lea     editor_name(pc),a0
        movea.l a4,a1
        move.l  #EDITOR_FILE_LENGTH,d0
        moveq   #0,d1
        movea.l resload(pc),a2
        jsr     resload_LoadFileOffset(a2)
        moveq   #EDST_READ_FAILED,d7
        tst.l   d0
        beq.w   .done

        moveq   #EDSTEP_VERIFY,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        movea.l a4,a0
        move.l  #EDITOR_FILE_LENGTH,d1
        bsr.w   crc32
        moveq   #EDST_BAD_CRC,d7
        cmpi.l  #EDITOR_FILE_CRC32,d0
        bne.w   .done
        bsr.w   editor_header_check
        moveq   #EDST_BAD_HEADER,d7
        tst.l   d0
        bne.w   .done

        moveq   #EDSTEP_RELOCATE,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        movea.l a4,a0
        adda.l  EDH_FIXUPS(a4),a0
        move.l  a4,d2
        bsr.w   apply_offsets           ; image base into its own pointers
        movea.l a4,a0
        adda.l  EDH_IMPORTS(a4),a0
        moveq   #0,d2                   ; SWOS2 runs at SWOS2_BASE
        bsr.w   apply_offsets
        lea     WORK_CRC_TABLE(a4),a0
        bsr.w   crc32_make_table

        moveq   #EDSTEP_INIT,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        movea.l resload(pc),a2
        jsr     resload_FlushCache(a2)  ; the image is code now
        movem.l a4-a5,-(sp)
        movea.l a4,a0
        adda.l  EDH_INIT(a4),a0
        movea.l a4,a5
        jsr     (a0)                    ; editor_init, A5 = editor base
        movem.l (sp)+,a4-a5
        move.l  d0,SB_EDITOR_DETAIL(a5)
        moveq   #EDST_INIT_FAILED,d7
        tst.l   d0
        bne.s   .done

        moveq   #EDSTEP_HOOKS,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        movea.l a4,a2
        adda.l  EDH_HOOKS(a4),a2
        bsr.w   table_check
        move.l  d1,SB_EDITOR_DETAIL(a5)
        moveq   #EDST_HOOK_MISMATCH,d7
        tst.l   d0
        bne.s   .done
        movea.l a4,a2
        adda.l  EDH_HOOKS(a4),a2
        bsr.w   table_write             ; A4 = editor base for the fixups
        moveq   #EDSTEP_DONE,d0
        move.l  d0,SB_EDITOR_STEP(a5)
        move.l  a4,SB_EDITOR_BASE(a5)
        bset    #SBF_EDITOR,SB_FLAGS+1(a5)
        moveq   #EDST_ACTIVE,d7
.done:
        move.l  d7,SB_EDITOR_STATUS(a5)
        movem.l (sp)+,d0-d7/a0-a6
        rts

; editor_header_check: A4 = loaded image. D0.l = 0 when magic, version,
; length, SWOS2 identity and every table offset are right.
editor_header_check:
        movem.l d1/a0-a1,-(sp)
        moveq   #-1,d0
        cmpi.l  #EDH_MAGIC_VALUE,EDH_MAGIC(a4)
        bne.s   .done
        cmpi.w  #EDH_VERSION_VALUE,EDH_VERSION(a4)
        bne.s   .done
        cmpi.l  #EDITOR_FILE_LENGTH,EDH_LENGTH(a4)
        bne.s   .done
        lea     EDH_IDENTITY(a4),a0
        lea     swos2_identity(pc),a1
        cmpm.l  (a0)+,(a1)+
        bne.s   .done
        cmpm.l  (a0)+,(a1)+
        bne.s   .done
        lea     EDH_INIT(a4),a0
        moveq   #4-1,d1                 ; init, hooks, fixups, imports
.offset:
        cmpi.l  #EDITOR_FILE_LENGTH-4,(a0)+
        bhi.s   .done
        dbf     d1,.offset
        moveq   #0,d0
.done:
        movem.l (sp)+,d1/a0-a1
        rts

; apply_offsets: A0 = table (dc.l count, dc.l offset[count]), A4 = image,
; D2.l = value added to every BE32 field named by the table.
apply_offsets:
        move.l  (a0)+,d1
        beq.s   .done
.field:
        move.l  (a0)+,d0
        cmpi.l  #EDITOR_FILE_LENGTH-4,d0
        bhi.s   .skip                   ; outside the image: never written
        add.l   d2,(a4,d0.l)
.skip:
        subq.l  #1,d1
        bne.s   .field
.done:
        rts

;============================================================================
; CRC-32 with the slave's table
;============================================================================
; crc32: A0 = data, D1.l = length. D0.l = CRC-32/ISO-HDLC; D1, D2 and A0
; clobbered.
crc32:
        move.l  a1,-(sp)
        movea.l expmem(pc),a1
        lea     SA_CRC_TABLE(a1),a1
        moveq   #-1,d0
        bsr.s   crc32_table_update
        not.l   d0
        movea.l (sp)+,a1
        rts

        CRC32_MAKE_TABLE
        CRC32_TABLE

        include "disk_service.s"
        include "file_service.s"

;============================================================================
; Data
;============================================================================
swos2_name:
        dc.b    "SWOS2",0
swos2_rel_name:
        dc.b    "SWOS2.REL",0
editor_name:
        dc.b    "Editor.bin",0
msg_wrong_disk:
        dc.b    "Disk.1 is not disk 1 of the supported",10
        dc.b    "SWOS 96-97 release (SWOS2, VERSION 152).",0
msg_wrong_table:
        dc.b    "SWOS2 on Disk.1 differs from the supported",10
        dc.b    "release at a patch site.",0
        even
swos2_identity:
        SWOS2_IDENTITY

; Templates for the base patch table (replacement bytes; the slave base is
; added to the fields the manifest names as fixups).
        cnop    0,2
slave_block_template:
        dc.w    $4EF9                   ; disk_io: JMP slave_disk_io
        dc.l    slave_disk_io-base
        dc.w    $4EF9                   ; SB_SERVICE: JMP slave_service_entry
        dc.l    slave_service_entry-base
        dc.w    0
        dc.l    SLAVE_BLOCK_MAGIC       ; SB_MAGIC
        dc.w    SLAVE_BLOCK_VERSION     ; SB_VERSION
        dc.w    0                       ; SB_FLAGS
        dc.l    0                       ; SB_SLAVE (fixup: the slave base)
        dcb.b   SB_SIZE-SB_EXPMEM,0
slave_block_template_end:

; The base patch table, generated from the manifest; it stays the last part
; of the slave so that its size alone moves nothing before it.
        cnop    0,4
base_table:
        incbin  "base_table.bin"
base_table_end:
