; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Database mode: the edited database set in the save directory and the
; binding of competitions to it.
;
; The set (database.i): the manifest DBASE.CFG (the previous one is kept as
; DBASE.BAK) and the files Tgggnnnn.GRP it declares: database groups and the
; copies that follow the set (the European cups' team copies and the
; transfer pool). Generations are never deleted here; a save writes new
; generation names, reads them back and only then replaces the manifest,
; after a verified DBASE.BAK. A save of a group also refreshes the copies
; of its clubs and players.
;
; The database in use:
;   - USE EDITED DATABASE (DB_SWITCH) keeps its state across restarts in
;     DBASE.USE; switching it on verifies DBASE.CFG and every file it
;     declares (exact length and CRC-32) and keeps the verified manifest as
;     DB_ACTIVE; at the first main menu a remembered ON is checked the same
;     way, and a failure leaves the original database with the reason in
;     the main-menu caption (db_start_check);
;   - a new competition family is bound to what the switch says when it
;     starts (db_family_reset, from competition_family_reset);
;   - a competition save written while the family is bound to an edited set
;     gets a link file next to it (base name and .DLD, .DLP, .DLS or .DLC):
;     the save's length and CRC-32 and the manifest of the set; a save of an
;     unbound family removes a stale link of the same name;
;   - DELETE FILE removing a competition save removes its link too;
;   - loading a save reads its link first: a link that is damaged or does
;     not match the save, or a set whose files are missing or different,
;     refuses the load with DATABASE LINK DAMAGED or DATABASE NOT FOUND, and
;     the native code returns to the main menu; a save without a link is a
;     competition of the original database, whatever the switch says;
;   - while a family exists the gateway uses the set it is bound to,
;     otherwise the switch's set (db_manifest_in_use).
;
; Unless stated otherwise routines take A5 = editor base and preserve every
; register but D0 and D1.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "editor_gen.i"

        xdef    db_manifest_in_use, db_find_entry, db_entry_name
        xdef    db_manifest_check, db_problem_text, db_is_group, db_group_list
        xdef    db_group_name, db_read_set, db_restore_backup, db_verify_set
        xdef    db_switch_on, db_switch_off, db_switch_store, db_caption_update
        xdef    db_start_check, db_is_set_code, db_problem_name, db_cup_teams, db_cup_copy
        xdef    db_load_group, db_save, db_old_versions, db_identity
        xdef    db_family_reset
        xdef    db_save_diy, db_save_preset, db_save_season, db_save_career
        xdef    db_load_diy, db_load_preset, db_load_season, db_load_career
        xdef    db_delete_file
        xref    editor_base
        xref    crc32_table_update, crc32_buffer
        xref    storage_list, storage_size, storage_read, storage_read_part
        xref    storage_write, storage_delete
        xref    message_title, message_line, message_lines, message_note, message_show, message_ask
        xref    message_storage_reason
        xref    text_copy, text_copy_max, text_hex32, text_decimal, text_glyph

CHUNK                   equ LIST_WORK_SIZE ; reads that compute a CRC-32

        section .text,code

; ===========================================================================
; The database in use (the gateway's view)
; ===========================================================================

; db_manifest_in_use: A0 = the manifest of the set in use with Z clear, or
; A0 = 0 with Z set for the original database. Needs no A5; preserves all
; other registers.
db_manifest_in_use:
        movea.l editor_base,a0
        adda.l  #WORK_DB,a0
        tst.w   competition_family
        beq.s   .switch
        tst.w   DB_BIND(a0)
        beq.s   .none
        lea     DB_BOUND(a0),a0         ; LEA and SUBA keep the flags
        rts
.switch:
        tst.w   DB_SWITCH(a0)
        beq.s   .none
        lea     DB_ACTIVE(a0),a0
        rts
.none:
        suba.l  a0,a0
        rts

; db_find_entry: A0 = manifest, D0.w = group. A4 = its entry with Z clear,
; or Z set. Preserves all other registers.
db_find_entry:
        move.l  d1,-(sp)
        move.w  MF_COUNT(a0),d1
        cmpi.w  #MANIFEST_ENTRIES,d1
        bls.s   .count
        moveq   #MANIFEST_ENTRIES,d1
.count:
        lea     MANIFEST_HEADER(a0),a4
        bra.s   .test
.entry:
        cmp.w   ME_GROUP(a4),d0
        beq.s   .found
        lea     MANIFEST_ENTRY(a4),a4
.test:
        dbf     d1,.entry
        move.l  (sp)+,d1
        ori.b   #$04,ccr                ; Z set
        rts
.found:
        move.l  (sp)+,d1
        andi.b  #$FB,ccr                ; Z clear
        rts

; db_entry_name: A4 = entry, A1 = destination. The file name Tgggnnnn.GRP;
; A1 is left on its NUL. Preserves all other registers.
db_entry_name:
        movem.l d0/d2,-(sp)
        move.b  #'T',(a1)+
        move.w  ME_GROUP(a4),d0
        moveq   #2,d2
        bsr.w   put_digits
        move.w  ME_GENERATION(a4),d0
        moveq   #3,d2
        bsr.w   put_digits
        move.l  #'.GRP',(a1)+
        clr.b   (a1)
        movem.l (sp)+,d0/d2
        rts

; put_digits: D0.w = value, D2.w = digits - 1, at A1 with leading zeros; A1
; is left after them. Preserves all other registers.
put_digits:
        movem.l d0/d2,-(sp)
        andi.l  #$FFFF,d0
        lea     1(a1,d2.w),a1
        move.l  a1,-(sp)
.digit:
        divu.w  #10,d0
        swap    d0
        addi.b  #'0',d0
        move.b  d0,-(a1)
        clr.w   d0
        swap    d0
        dbf     d2,.digit
        movea.l (sp)+,a1
        movem.l (sp)+,d0/d2
        rts

; ===========================================================================
; Database groups
; ===========================================================================

; db_is_group: D0.w = group. Z set when it is a database group (the 65
; club groups and the national groups 80-85). Preserves all registers.
db_is_group:
        cmpi.w  #255,d0
        bhi.s   .no
        movem.l d1/a0,-(sp)
        lea     database_groups(pc),a0
        moveq   #DATABASE_GROUP_COUNT-1,d1
.next:
        cmp.b   (a0)+,d0
        dbeq    d1,.next
        movem.l (sp)+,d1/a0
        rts
.no:
        andi.b  #$FB,ccr                ; Z clear
        rts

; db_is_set_code: D0.w = code. Z set when a manifest of version 2 may
; declare it: a database group or one of the copies. Preserves all
; registers.
db_is_set_code:
        cmpi.w  #COPY_FIRST,d0
        bcs.s   db_is_group
        cmpi.w  #COPY_FIRST+COPY_COUNT,d0
        bcc.s   .no
        cmp.w   d0,d0                   ; Z set
        rts
.no:
        andi.b  #$FB,ccr                ; Z clear
        rts

; db_cup_teams: D0.w = copy code of a cup. D0.l = its number of teams.
; Preserves all other registers.
db_cup_teams:
        cmpi.w  #COPY_EUROCUP,d0
        bne.s   .large
        moveq   #CUP_EUROCUP_TEAMS,d0
        rts
.large:
        moveq   #CUP_EUROCWC_TEAMS,d0
        rts
        if CUP_UEFACUP_TEAMS!=CUP_EUROCWC_TEAMS
        fail "db_cup_teams expects the two large cups to be the same size"
        endif

; entry_length: D1.w = a set code, D4.w = records. D4.l = the length its
; file must have, or 0 with Z set when the count does not fit the code (a
; group 1-93 teams and the count word, a cup exactly its teams, the pool
; its entries). Preserves all other registers.
entry_length:
        andi.l  #$FFFF,d4
        cmpi.w  #COPY_FIRST,d1
        bcc.s   .copy
        tst.w   d4
        beq.s   .bad
        cmpi.w  #GROUP_MAX_TEAMS,d4
        bhi.s   .bad
        mulu.w  #TEAM_SIZE,d4
        addq.l  #GROUP_COUNT_SIZE,d4
        rts
.copy:
        cmpi.w  #COPY_POOL,d1
        beq.s   .pool
        move.l  d0,-(sp)
        move.w  d1,d0
        bsr.s   db_cup_teams
        cmp.w   d0,d4
        movem.l (sp)+,d0                ; the flags stay
        bne.s   .bad
        mulu.w  #TEAM_SIZE,d4
        rts
.pool:
        cmpi.w  #POOL_ENTRIES,d4
        bne.s   .bad
        move.l  #POOL_SIZE,d4
        rts
.bad:
        moveq   #0,d4
        rts

; db_group_list: A0 = the database groups, DATABASE_GROUP_COUNT bytes in
; the order the database screen lists them. Preserves all other registers.
db_group_list:
        lea     database_groups(pc),a0
        rts

; db_group_name: D0.w = group, A1 = destination. The game's own name of the
; group (team_group_descriptors); A1 is left on the NUL. Preserves all
; other registers.
db_group_name:
        movem.l d0/a0,-(sp)
        andi.w  #$FF,d0
        lsl.w   #2,d0
        lea     team_group_descriptors,a0
        movea.l (a0,d0.w),a0
        addq.l  #1,a0                   ; past the continent byte
        bsr.l   text_copy
        movem.l (sp)+,d0/a0
        rts

; ===========================================================================
; Checks
; ===========================================================================

; db_manifest_check: A0 = manifest, D0.l = its length. D0.l = MC_OK or the
; first problem in this order (database.i): size, magic, version, count and
; length fields, CRC-32, identity and base, reserved field, label, then the
; entries in order: a code the version does not declare (version 1: a
; database group; version 2: also a copy), codes out of order or twice, a
; damaged entry (D1.l = the code for the last three). Flags from D0.
; Preserves D2-D7/A0-A6.
db_manifest_check:
        movem.l d2-d7/a0-a4,-(sp)
        movea.l a0,a2
        move.l  d0,d7
        moveq   #0,d1
        moveq   #MC_SIZE,d0
        cmpi.l  #MANIFEST_HEADER+MANIFEST_ENTRY,d7
        bcs.w   .done
        cmpi.l  #MANIFEST_MAX,d7
        bhi.w   .done
        move.l  d7,d2
        andi.w  #MANIFEST_ENTRY-1,d2
        bne.w   .done
        moveq   #MC_MAGIC,d0
        cmpi.l  #MANIFEST_MAGIC_HIGH,MF_MAGIC(a2)
        bne.w   .done
        cmpi.l  #MANIFEST_MAGIC_LOW,MF_MAGIC+4(a2)
        bne.w   .done
        moveq   #MC_VERSION,d0
        move.w  MF_VERSION(a2),d5
        cmpi.w  #MANIFEST_VERSION,d5
        beq.s   .version
        cmpi.w  #MANIFEST_VERSION_V1,d5
        bne.w   .done
.version:
        moveq   #MC_SIZE,d0
        moveq   #0,d2
        move.w  MF_COUNT(a2),d2
        beq.w   .done
        moveq   #MANIFEST_ENTRIES,d3
        cmpi.w  #MANIFEST_VERSION_V1,d5
        bne.s   .limit
        moveq   #MANIFEST_ENTRIES_V1,d3
.limit:
        cmp.w   d3,d2
        bhi.w   .done
        cmp.l   MF_LENGTH(a2),d7
        bne.w   .done
        move.l  d2,d3
        lsl.l   #4,d3
        addi.l  #MANIFEST_HEADER,d3
        cmp.l   d3,d7
        bne.w   .done
        ; CRC-32 with its own field zero
        moveq   #-1,d0
        movea.l a2,a0
        moveq   #MF_CRC32,d1
        lea     WORK_CRC_TABLE(a5),a1
        bsr.l   crc32_table_update
        lea     zero_long(pc),a0
        moveq   #4,d1
        bsr.l   crc32_table_update
        lea     MF_RESERVED(a2),a0
        move.l  d7,d1
        subi.l  #MF_RESERVED,d1
        bsr.l   crc32_table_update
        not.l   d0
        cmp.l   MF_CRC32(a2),d0
        beq.s   .crc_ok
        moveq   #0,d1
        moveq   #MC_CRC,d0
        bra.w   .done
.crc_ok:
        moveq   #0,d1
        moveq   #MC_IDENTITY,d0
        lea     MF_IDENTITY(a2),a0
        lea     swos2_identity(pc),a1
        moveq   #MANIFEST_IDENTITY_SIZE/4-1,d3
.identity:
        cmpm.l  (a0)+,(a1)+
        dbne    d3,.identity
        bne.w   .done
        cmpi.l  #SWOS2_BASE,MF_BASE(a2)
        bne.w   .done
        moveq   #MC_VERSION,d0
        tst.l   MF_RESERVED(a2)
        bne.w   .done
        ; the label: glyphs, then only NUL
        moveq   #MC_LABEL,d0
        lea     MF_LABEL(a2),a0
        moveq   #SET_LABEL_SIZE-1,d3
        moveq   #0,d4                   ; 1 after the first NUL
.label:
        move.b  (a0)+,d1
        beq.s   .nul
        tst.w   d4
        bne.w   .label_bad
        exg     d0,d1
        bsr.l   text_glyph              ; Z clear when shown
        exg     d0,d1
        beq.s   .label_bad
        bra.s   .label_next
.nul:
        moveq   #1,d4
.label_next:
        dbf     d3,.label
        ; the entries (crc32_table_update changed D1-D2)
        lea     MANIFEST_HEADER(a2),a3
        moveq   #0,d2
        move.w  MF_COUNT(a2),d2
        subq.w  #1,d2
        moveq   #-1,d3                  ; previous group
.entry:
        moveq   #0,d1
        move.w  ME_GROUP(a3),d1
        move.l  d1,d0
        cmpi.w  #MANIFEST_VERSION_V1,d5
        bne.s   .any_code
        bsr.w   db_is_group
        bra.s   .code_tested
.any_code:
        bsr.w   db_is_set_code
.code_tested:
        beq.s   .group_ok
        moveq   #MC_GROUP,d0
        bra.s   .done
.group_ok:
        moveq   #MC_ORDER,d0
        cmp.w   d3,d1
        ble.s   .done
        move.w  d1,d3
        moveq   #MC_ENTRY,d0
        move.w  ME_GENERATION(a3),d4
        beq.s   .done
        cmpi.w  #GENERATION_MAX,d4
        bhi.s   .done
        tst.w   ME_RESERVED(a3)
        bne.s   .done
        move.w  ME_TEAMS(a3),d4
        bsr.w   entry_length            ; D4 = length or 0
        beq.s   .done
        cmp.l   ME_LENGTH(a3),d4
        bne.s   .done
        lea     MANIFEST_ENTRY(a3),a3
        dbf     d2,.entry
        moveq   #0,d1
        moveq   #MC_OK,d0
.done:
        movem.l (sp)+,d2-d7/a0-a4
        tst.l   d0
        rts
.label_bad:
        moveq   #0,d1
        moveq   #MC_LABEL,d0
        bra.s   .done

; db_problem_text: D0.l = problem (database.i), D1.l = its group, A1 =
; destination. The line the editor shows; a file name is the one in
; DB_NAME. A1 is left on the NUL. Preserves all other registers.
db_problem_text:
        movem.l d0-d1/a0/a2,-(sp)
        cmpi.l  #PROBLEM_LAST,d0
        bhi.s   .done
        add.w   d0,d0
        lea     problem_texts(pc),a0
        move.w  (a0,d0.w),d0
        beq.s   .done
        movea.l a0,a2
        adda.w  d0,a2
.char:
        move.b  (a2)+,d0
        beq.s   .done
        cmpi.b  #'#',d0
        beq.s   .group
        cmpi.b  #'$',d0
        beq.s   .name
        move.b  d0,(a1)+
        clr.b   (a1)
        bra.s   .char
.group:
        move.l  4(sp),d0
        bsr.l   text_decimal
        bra.s   .char
.name:
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.l   text_copy
        bra.s   .char
.done:
        movem.l (sp)+,d0-d1/a0/a2
        rts

; ===========================================================================
; Files of the set
; ===========================================================================

; file_crc: A0 = name of a file of D1.l bytes. D0.l = 0 and D1.l = its
; CRC-32, or a storage result, or STE_SHORT_READ when fewer bytes were read.
; Reads in CHUNK pieces into the listing area. Preserves D2-D7/A0-A6.
file_crc:
        movem.l d2-d6/a0-a2,-(sp)
        movea.l a0,a2
        move.l  d1,d5                   ; bytes left
        moveq   #0,d6                   ; offset
        moveq   #-1,d4                  ; running CRC
.chunk:
        tst.l   d5
        beq.s   .finished
        move.l  #CHUNK,d1
        cmp.l   d5,d1
        bls.s   .size
        move.l  d5,d1
.size:
        move.l  d1,d3
        movea.l a2,a0
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  d6,d2
        bsr.l   storage_read_part       ; D1 = bytes read
        bne.s   .out
        cmp.l   d3,d1
        bne.s   .short
        move.l  d4,d0
        lea     LIST_WORK_OFFSET(a5),a0
        lea     WORK_CRC_TABLE(a5),a1
        bsr.l   crc32_table_update
        move.l  d0,d4
        add.l   d3,d6
        sub.l   d3,d5
        bra.s   .chunk
.finished:
        move.l  d4,d1
        not.l   d1
        moveq   #0,d0
.out:
        movem.l (sp)+,d2-d6/a0-a2
        tst.l   d0
        rts
.short:
        moveq   #STE_SHORT_READ,d0
        bra.s   .out

; check_entry_file: A4 = entry. Builds its name in DB_NAME and checks that
; the file exists with the entry's exact length and CRC-32. D0.l = 0, or
; GC_MISSING, GC_LENGTH or GC_CRC. Preserves D1-D7/A0-A6.
check_entry_file:
        movem.l d1/a0-a1,-(sp)
        lea     WORK_DB+DB_NAME(a5),a1
        bsr.w   db_entry_name
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.l   storage_size            ; D1 = length
        beq.s   .length
        moveq   #GC_MISSING,d0
        bra.s   .done
.length:
        moveq   #GC_LENGTH,d0
        cmp.l   ME_LENGTH(a4),d1
        bne.s   .done
        bsr.w   file_crc                ; D1 = CRC-32
        beq.s   .crc
        moveq   #GC_MISSING,d0
        bra.s   .done
.crc:
        moveq   #GC_CRC,d0
        cmp.l   ME_CRC32(a4),d1
        bne.s   .done
        moveq   #0,d0
.done:
        movem.l (sp)+,d1/a0-a1
        tst.l   d0
        rts

; db_verify_set: A0 = a checked manifest. Checks every declared file. D0.l
; = 0, or the problem of the first file that fails (its name in DB_NAME).
; Preserves D1-D7/A0-A6.
db_verify_set:
        movem.l d1-d2/a4,-(sp)
        move.w  MF_COUNT(a0),d2
        lea     MANIFEST_HEADER(a0),a4
        bra.s   .test
.entry:
        bsr.s   check_entry_file
        bne.s   .done
        lea     MANIFEST_ENTRY(a4),a4
.test:
        dbf     d2,.entry
        moveq   #0,d0
.done:
        movem.l (sp)+,d1-d2/a4
        tst.l   d0
        rts

; db_read_set: reads DBASE.CFG into DB_SET and checks it. D0.l and
; DB_SET_STATE = DSS_NONE, DSS_VALID or DSS_DAMAGED (DB_SET_PROBLEM and
; DB_SET_DETAIL hold the problem). An empty DBASE.CFG (a write cut by a
; full volume) reads as missing; beside a sound DBASE.BAK it is damaged, so
; that a SAVE does not start a new set while the previous one waits to be
; restored. Uses DB_NEW and the listing area. Preserves D1-D7/A0-A6.
db_read_set:
        movem.l d1/a0-a1,-(sp)
        lea     config_name(pc),a0
        lea     WORK_DB+DB_SET(a5),a1
        move.l  #MANIFEST_MAX,d1
        bsr.l   storage_read            ; D1 = length
        beq.s   .check
        cmpi.l  #STE_NOT_FOUND,d0
        bne.s   .size
        bsr.w   db_backup_usable        ; 0: a previous set to restore
        bne.s   .none
        bsr.w   config_listed           ; Z set: an empty DBASE.CFG beside it
        bne.s   .none
.size:
        moveq   #MC_SIZE,d0             ; longer than any manifest, empty, or unreadable
        moveq   #0,d1
        bra.s   .damaged
.check:
        move.l  d1,d0
        movea.l a1,a0
        bsr.w   db_manifest_check
        bne.s   .damaged
        move.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        moveq   #DSS_VALID,d0
        bra.s   .done
.none:
        move.w  #DSS_NONE,WORK_DB+DB_SET_STATE(a5)
        moveq   #DSS_NONE,d0
        bra.s   .done
.damaged:
        move.w  d0,WORK_DB+DB_SET_PROBLEM(a5)
        move.w  d1,WORK_DB+DB_SET_DETAIL(a5)
        move.w  #DSS_DAMAGED,WORK_DB+DB_SET_STATE(a5)
        moveq   #DSS_DAMAGED,d0
.done:
        movem.l (sp)+,d1/a0-a1
        rts

; db_restore_backup: replaces a missing or damaged DBASE.CFG with DBASE.BAK
; when that is a sound manifest. D0.l = 0 when DBASE.CFG was written from it
; and read back (DB_SET then holds it; a failed start check that named
; DBASE.CFG no longer holds: its problem is cleared, as explained, and the
; caption follows), 1 when DBASE.BAK is missing or damaged, or a storage
; result. Preserves D1-D7/A0-A6.
db_restore_backup:
        movem.l d1/a0-a1,-(sp)
        bsr.w   db_backup_usable        ; 1: missing or damaged
        bne.s   .done
        lea     config_name(pc),a0
        lea     WORK_DB+DB_NEW(a5),a1
        move.l  MF_LENGTH(a1),d1
        bsr.l   storage_write           ; read back by the slave
        bne.s   .done
        bsr.w   db_read_set
        bsr.s   start_restored
        moveq   #0,d0
.done:
        movem.l (sp)+,d1/a0-a1
        tst.l   d0
        rts

; start_restored: DBASE.CFG is sound again. A failed start check that named
; it no longer holds: its problem is cleared (the restore explained it) and
; the main-menu caption follows. Preserves all registers.
start_restored:
        movem.l d0/a0-a1,-(sp)
        tst.w   WORK_DB+DB_START_PROBLEM(a5)
        beq.s   .done
        lea     WORK_DB+DB_START_NAME(a5),a0
        lea     config_name(pc),a1
.compare:
        move.b  (a0)+,d0
        cmp.b   (a1)+,d0
        bne.s   .done                   ; another file's problem stays
        tst.b   d0
        bne.s   .compare
        clr.w   WORK_DB+DB_START_PROBLEM(a5)
        move.w  #1,WORK_DB+DB_START_NOTED(a5)
        bsr.w   db_caption_update
.done:
        movem.l (sp)+,d0/a0-a1
        rts

; config_listed: Z set when the listing of the save directory holds
; DBASE.CFG. Uses the listing area. Preserves all registers.
config_listed:
        movem.l d0-d2/d6/a0-a1,-(sp)
        bsr.w   list_dir                ; D6 = names
        bne.s   .done                   ; not known: Z clear
        lea     config_name(pc),a0
        bsr.w   name_listed
.done:
        movem.l (sp)+,d0-d2/d6/a0-a1    ; the flags stay
        rts

; db_backup_usable: D0.l = 0 when DBASE.BAK is a sound manifest (read into
; DB_NEW). Preserves D1-D7/A0-A6.
        xdef    db_backup_usable
db_backup_usable:
        movem.l d1/a0-a1,-(sp)
        lea     backup_name(pc),a0
        lea     WORK_DB+DB_NEW(a5),a1
        move.l  #MANIFEST_MAX,d1
        bsr.l   storage_read
        bne.s   .no
        move.l  d1,d0
        movea.l a1,a0
        bsr.w   db_manifest_check
        bne.s   .no
        moveq   #0,d0
        bra.s   .done
.no:
        moveq   #1,d0
.done:
        movem.l (sp)+,d1/a0-a1          ; the flags stay
        rts

; ===========================================================================
; The switch
; ===========================================================================

; db_switch_on: the set in DB_SET (DSS_VALID) becomes the database of new
; competitions after every declared file has passed. D0.l = 0, or the
; problem of the first file that fails (its name in DB_NAME); nothing
; changes then. Preserves D1-D7/A0-A6.
db_switch_on:
        movem.l a0-a1,-(sp)
        lea     WORK_DB+DB_SET(a5),a0
        bsr.w   db_verify_set           ; keeps A0
        bne.s   .done
        lea     WORK_DB+DB_ACTIVE(a5),a1
        bsr.w   copy_manifest
        move.w  #1,WORK_DB+DB_SWITCH(a5)
        bsr.s   in_use_changed
        moveq   #0,d0
.done:
        movem.l (sp)+,a0-a1
        tst.l   d0
        rts

; db_switch_off: new competitions use the original database again.
db_switch_off:
        clr.w   WORK_DB+DB_SWITCH(a5)

; in_use_changed: the set new competitions use changed. The groups and the
; transfer pool are read again at their next use, the start check's
; problem is past and the caption follows. Preserves all registers.
in_use_changed:
        clr.w   team_group_cache_valid
        clr.w   transfer_pool_loaded
        clr.w   WORK_DB+DB_START_PROBLEM(a5)
        bra.w   db_caption_update

; db_switch_store: remembers USE EDITED DATABASE in DBASE.USE (read back by
; the slave), so the next start has the same state. D0.l = 0 or a storage
; result. Preserves D1-D7/A0-A6.
db_switch_store:
        movem.l d1-d2/a0-a1,-(sp)
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #SWITCH_MAGIC_HIGH,(a1)
        move.l  #SWITCH_MAGIC_LOW,4(a1)
        move.w  #SWITCH_VERSION,SW_VERSION(a1)
        move.w  WORK_DB+DB_SWITCH(a5),SW_STATE(a1)
        movea.l a1,a0
        moveq   #SW_CRC32,d1
        bsr.l   crc32_buffer
        move.l  d0,SW_CRC32(a1)
        lea     switch_name(pc),a0
        moveq   #SWITCH_SIZE,d1
        bsr.l   storage_write
        movem.l (sp)+,d1-d2/a0-a1
        tst.l   d0
        rts

; db_start_check: once, at the first main menu. When DBASE.USE remembers
; USE EDITED DATABASE as on, DBASE.CFG is read and every file it declares
; is verified as when the switch is turned on; a set that passes is in use
; from the start. Otherwise the switch stays off, the original database is
; used, and DB_START_PROBLEM, DB_START_DETAIL and DB_START_NAME keep the
; reason for the caption and EDIT DATABASE. A missing or unknown DBASE.USE
; means off. Preserves all registers.
db_start_check:
        movem.l d0-d2/a0-a1,-(sp)
        tst.w   WORK_DB+DB_START(a5)
        bne.w   .done
        move.w  #1,WORK_DB+DB_START(a5)
        lea     switch_name(pc),a0
        lea     WORK_IO_BUFFER(a5),a1
        moveq   #SWITCH_SIZE,d1
        bsr.l   storage_read            ; D1 = length
        bne.w   .done
        cmpi.l  #SWITCH_SIZE,d1
        bne.w   .done
        cmpi.l  #SWITCH_MAGIC_HIGH,(a1)
        bne.w   .done
        cmpi.l  #SWITCH_MAGIC_LOW,4(a1)
        bne.w   .done
        cmpi.w  #SWITCH_VERSION,SW_VERSION(a1)
        bne.w   .done
        cmpi.w  #1,SW_STATE(a1)
        bne.w   .done
        movea.l a1,a0
        moveq   #SW_CRC32,d1
        bsr.l   crc32_buffer            ; A0 = the stored CRC-32
        cmp.l   (a0),d0
        bne.s   .done
        ; remembered as on: the set as the switch checks it
        lea     WORK_DB+DB_START_NAME(a5),a1
        lea     config_name(pc),a0
        bsr.l   text_copy
        bsr.w   db_read_set             ; D0 = DSS_*
        cmpi.w  #DSS_VALID,d0
        beq.s   .verify
        moveq   #GC_MISSING,d1
        cmpi.w  #DSS_NONE,d0
        beq.s   .failed
        move.w  WORK_DB+DB_SET_PROBLEM(a5),d1
        move.w  WORK_DB+DB_SET_DETAIL(a5),WORK_DB+DB_START_DETAIL(a5)
        bra.s   .failed
.verify:
        bsr.w   db_switch_on            ; D0 = 0 or the problem, DB_NAME its file
        beq.s   .done
        move.l  d0,d1
        lea     WORK_DB+DB_NAME(a5),a0
        lea     WORK_DB+DB_START_NAME(a5),a1
        bsr.l   text_copy
.failed:
        move.w  d1,WORK_DB+DB_START_PROBLEM(a5)
        bsr.w   db_caption_update
.done:
        movem.l (sp)+,d0-d2/a0-a1
        rts

; db_problem_name: A1 = destination. The start check's problem as the line
; of db_problem_text (its file name in DB_NAME); A1 is left on the NUL.
; Preserves all other registers.
db_problem_name:
        movem.l d0-d1/a0,-(sp)
        lea     WORK_DB+DB_START_NAME(a5),a0
        move.l  a1,-(sp)
        lea     WORK_DB+DB_NAME(a5),a1
        bsr.l   text_copy
        movea.l (sp)+,a1
        moveq   #0,d0
        move.w  WORK_DB+DB_START_PROBLEM(a5),d0
        moveq   #0,d1
        move.w  WORK_DB+DB_START_DETAIL(a5),d1
        bsr.w   db_problem_text
        movem.l (sp)+,d0-d1/a0
        rts

; db_caption_update: the main-menu caption: DATABASE: <label> <CRC-32 of the
; manifest>, or DATABASE: EDITED <CRC-32> for a set without a label, while
; the switch is on; after a failed start check DATABASE OFF: <file> MISSING
; or DAMAGED; else empty. Preserves all registers.
db_caption_update:
        movem.l d0/a0-a1,-(sp)
        lea     WORK_DB+DB_CAPTION(a5),a1
        clr.b   (a1)
        tst.w   WORK_DB+DB_SWITCH(a5)
        beq.s   .off
        lea     caption_prefix(pc),a0
        bsr.l   text_copy
        lea     WORK_DB+DB_ACTIVE(a5),a0
        bsr.s   db_label_crc
        bra.s   .done
.off:
        move.w  WORK_DB+DB_START_PROBLEM(a5),d0
        beq.s   .done
        lea     caption_off_prefix(pc),a0
        bsr.l   text_copy
        lea     WORK_DB+DB_START_NAME(a5),a0
        bsr.l   text_copy
        lea     caption_damaged(pc),a0
        cmpi.w  #GC_MISSING,d0
        bne.s   .reason
        lea     caption_missing(pc),a0
.reason:
        bsr.l   text_copy
.done:
        movem.l (sp)+,d0/a0-a1
        rts

; db_label_crc: A0 = manifest. Its label as db_label_text, a space and its
; CRC-32 at A1; A1 is left on the NUL. Preserves all other registers.
        xdef    db_label_crc
db_label_crc:
        bsr.s   db_label_text
        move.b  #' ',(a1)+
        move.l  d0,-(sp)
        move.l  MF_CRC32(a0),d0
        bsr.l   text_hex32
        move.l  (sp)+,d0
        rts

; db_label_text: A0 = manifest. Its label at A1, or EDITED when it has
; none; A1 is left on the NUL. Preserves all other registers.
        xdef    db_label_text
db_label_text:
        movem.l d0/a0,-(sp)
        lea     MF_LABEL(a0),a0
        tst.b   (a0)
        bne.s   .label
        lea     edited_text(pc),a0
        bsr.l   text_copy
        bra.s   .done
.label:
        moveq   #SET_LABEL_SIZE,d0
        bsr.l   text_copy_max
.done:
        movem.l (sp)+,d0/a0
        rts

; copy_manifest: A0 = manifest, A1 = destination: MANIFEST_MAX bytes,
; whatever the manifest's length (both are manifest areas or a link file in
; the I/O buffer). Preserves all registers.
copy_manifest:
        movem.l d0/a0-a1,-(sp)
        move.w  #MANIFEST_MAX/4-1,d0
.long:
        move.l  (a0)+,(a1)+
        dbf     d0,.long
        movem.l (sp)+,d0/a0-a1
        rts

; db_identity: A1 = body of a tournament definition. The identity of the
; database new competitions use (DI_KIND..DI_LABEL): zero for the original
; database, else the switch's set. Needs no A5; preserves all registers.
db_identity:
        movem.l d0/a0/a5,-(sp)
        movea.l editor_base,a5
        moveq   #DI_CUSTOM_CRC/2-1,d0
.clear:
        clr.w   (a1,d0.w*2)
        dbf     d0,.clear
        tst.w   WORK_DB+DB_SWITCH(a5)
        beq.s   .done
        lea     WORK_DB+DB_ACTIVE(a5),a0
        bsr.s   db_identity_of
.done:
        movem.l (sp)+,d0/a0/a5
        rts

; db_identity_of: A0 = the manifest of an edited set, A1 = an identity
; (definition.i). Its kind, generation, manifest CRC-32 and label for that
; set. Changes D0.
        xdef    db_identity_of
db_identity_of:
        move.w  #DIK_EDITED,DI_KIND(a1)
        move.w  MF_GENERATION+2(a0),DI_GENERATION(a1)
        move.l  MF_CRC32(a0),DI_MANIFEST_CRC(a1)
        moveq   #DI_LABEL_SIZE-1,d0
.label:
        move.b  MF_LABEL(a0,d0.w),DI_LABEL(a1,d0.w)
        dbf     d0,.label
        rts

; ===========================================================================
; The working group
; ===========================================================================

; db_load_group: D0.w = group. Reads it into the group work area: the file
; the set in DB_SET declares for it, else the original group from game
; disk 2 (exactly as the game's own loader reads it, before reindexing).
; D0.l = 0 (DB_GROUP, DB_COUNT set, DB_DIRTY clear), or a problem with its
; file name in DB_NAME. Preserves D1-D7/A0-A6.
db_load_group:
        movem.l d1-d4/a0-a2/a4,-(sp)
        move.w  d0,d3
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        bne.s   .original
        lea     WORK_DB+DB_SET(a5),a0
        bsr.w   db_find_entry           ; A4 = entry
        beq.s   .original
        lea     WORK_DB+DB_NAME(a5),a0
        lea     GROUP_WORK_OFFSET(a5),a1
        move.l  #GROUP_WORK_AREA,d1
        bsr.w   entry_read              ; D1 = length
        bne.w   .done
        move.l  d1,d4
        bra.s   .content
.original:
        lea     WORK_DB+DB_NAME(a5),a1
        lea     team_file_prefix(pc),a0
        bsr.l   text_copy
        move.w  d3,d0
        moveq   #2,d2
        bsr.w   put_digits
        clr.b   (a1)
        lea     WORK_DB+DB_NAME(a5),a0
        lea     team_group_buffer,a2
        bsr.w   read_original           ; D1 = length
        beq.s   .copy
        moveq   #GC_MISSING,d0
        bra.s   .done
.copy:
        move.l  d1,d4
        moveq   #GC_LENGTH,d0
        cmpi.l  #GROUP_WORK_AREA,d1
        bhi.s   .done
        movea.l a2,a0
        lea     GROUP_WORK_OFFSET(a5),a1
        move.l  d1,d2
        addq.l  #3,d2
        lsr.l   #2,d2
        subq.l  #1,d2
.long:
        move.l  (a0)+,(a1)+
        dbf     d2,.long
.content:
        ; count word and keys (group, 0..count-1)
        moveq   #GC_CONTENT,d0
        lea     GROUP_WORK_OFFSET(a5),a0
        moveq   #0,d2
        move.w  (a0)+,d2
        beq.s   .done
        cmpi.w  #GROUP_MAX_TEAMS,d2
        bhi.s   .done
        move.l  d2,d1
        mulu.w  #TEAM_SIZE,d1
        addq.l  #GROUP_COUNT_SIZE,d1
        cmp.l   d4,d1                   ; the length the count says
        bne.s   .done
        moveq   #0,d1                   ; ordinal
.key:
        cmp.b   (a0),d3
        bne.s   .done
        cmp.b   1(a0),d1
        bne.s   .done
        lea     TEAM_SIZE(a0),a0
        addq.w  #1,d1
        cmp.w   d2,d1
        bcs.s   .key
        move.w  d3,WORK_DB+DB_GROUP(a5)
        move.w  d2,WORK_DB+DB_COUNT(a5)
        clr.w   WORK_DB+DB_DIRTY(a5)
        moveq   #0,d0
.done:
        movem.l (sp)+,d1-d4/a0-a2/a4
        tst.l   d0
        rts

; ===========================================================================
; SAVE
; ===========================================================================

; db_save: writes the working group (when DB_DIRTY) as a new generation,
; refreshes the copies of its clubs and players (save_copies), and the set
; with the label DB_LABEL as a new DBASE.CFG, the previous one kept as a
; verified DBASE.BAK first.
;   out: D0.l = 0 when saved; 1 when there is nothing to save; or a storage
;        result with D1.l = the step that failed: 0 the directory, 1 a new
;        file of the set (the group or a copy; nothing replaced) or the
;        first DBASE.CFG (no previous set), 2 DBASE.BAK (nothing replaced),
;        3 DBASE.CFG (DBASE.BAK holds the previous set).
; Preserves D2-D7/A0-A6.
db_save:
        movem.l d2-d7/a0-a4,-(sp)
        moveq   #1,d0
        moveq   #0,d1
        tst.w   WORK_DB+DB_DIRTY(a5)
        bne.s   .something
        tst.w   WORK_DB+DB_LABEL_CHANGED(a5)
        beq.w   .done
.something:
        cmpi.w  #DSS_DAMAGED,WORK_DB+DB_SET_STATE(a5)
        beq.w   .done                   ; restored or replaced first (D0 = 1)
        ; DB_NEW starts as the set on the disk, or empty
        lea     WORK_DB+DB_NEW(a5),a3
        clr.w   MF_COUNT(a3)
        clr.l   MF_GENERATION(a3)
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        bne.s   .listed_count
        lea     WORK_DB+DB_SET(a5),a0
        movea.l a3,a1
        bsr.w   copy_manifest
.listed_count:
        ; the directory: every name, for admission and unused names
        bsr.w   list_dir                ; D6 = names
        bne.w   .done                   ; D1 = 0: the directory
        moveq   #0,d5                   ; new names
        tst.w   WORK_DB+DB_DIRTY(a5)
        beq.s   .manifests
        ; a new generation of the working group
        move.w  WORK_DB+DB_GROUP(a5),d7
        move.w  WORK_DB+DB_COUNT(a5),d5
        move.l  d5,d3
        mulu.w  #TEAM_SIZE,d3
        addq.l  #GROUP_COUNT_SIZE,d3
        lea     GROUP_WORK_OFFSET(a5),a2
        bsr.w   new_generation          ; A4 = its entry, DB_NAME its file
        moveq   #1+COPY_COUNT,d5        ; the group and, at most, each copy
.manifests:
        moveq   #1,d0
        moveq   #0,d1
        tst.w   MF_COUNT(a3)
        beq.w   .done                   ; a set holds at least one file
        lea     config_name(pc),a0
        bsr.w   name_listed
        beq.s   .config_listed
        addq.l  #1,d5
.config_listed:
        lea     backup_name(pc),a0
        bsr.w   name_listed
        beq.s   .backup_listed
        addq.l  #1,d5
.backup_listed:
        add.l   d6,d5
        cmpi.l  #SAVE_DIR_MAX_NAMES,d5
        bhi.w   .too_many
        ; the group file and the copies that changed, read back by the slave
        tst.w   WORK_DB+DB_DIRTY(a5)
        beq.s   .header
        lea     WORK_DB+DB_NAME(a5),a0
        movea.l a2,a1
        move.l  ME_LENGTH(a4),d1
        bsr.l   storage_write
        bne.w   .fail_file
        bsr.w   save_copies
        bne.w   .fail_file
.header:
        bsr.w   finish_manifest         ; DB_NEW: header, label, CRC-32
        ; DBASE.BAK: the set on the disk, verified, before DBASE.CFG changes
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        bne.s   .config
        lea     backup_name(pc),a0
        lea     WORK_DB+DB_SET(a5),a1
        move.l  MF_LENGTH(a1),d1
        bsr.l   storage_write
        sne     d1                      ; DB_BAK_FAILED: 0 or 1
        andi.w  #1,d1
        move.w  d1,WORK_DB+DB_BAK_FAILED(a5)
        tst.l   d0
        beq.s   .config
        moveq   #2,d1
        bra.s   .done
.config:
        lea     config_name(pc),a0
        movea.l a3,a1
        move.l  MF_LENGTH(a3),d1
        bsr.l   storage_write
        beq.s   .saved
        moveq   #3,d1
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        beq.s   .done                   ; DBASE.BAK holds the previous set
        moveq   #1,d1                   ; no previous set: nothing replaced
        bra.s   .done
.saved:
        movea.l a3,a0
        lea     WORK_DB+DB_SET(a5),a1
        bsr.w   copy_manifest
        move.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        clr.w   WORK_DB+DB_DIRTY(a5)
        clr.w   WORK_DB+DB_LABEL_CHANGED(a5)
        tst.w   WORK_DB+DB_SWITCH(a5)
        beq.s   .switch_off
        lea     WORK_DB+DB_ACTIVE(a5),a1
        bsr.w   copy_manifest           ; its new files were read back
        bsr.w   in_use_changed
.switch_off:
        moveq   #0,d0
        moveq   #0,d1
.done:
        movem.l (sp)+,d2-d7/a0-a4
        tst.l   d0
        rts
.fail_file:
        moveq   #1,d1
        bra.s   .done
.too_many:
        moveq   #STE_DIR_FULL,d0
        moveq   #0,d1
        bra.s   .done

; list_dir: lists the save directory into the listing area. D0.l = 0 and
; D1.l = D6.l = its names; or, with D1.l = 0, STE_DIR_FULL when it holds
; more names than the area, or a storage result. Flags from D0. Changes
; D2/A1.
list_dir:
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  #LIST_WORK_RECORDS,d1
        bsr.l   storage_list            ; D1 = names
        bne.s   .failed
        move.l  d1,d6
        cmpi.l  #LIST_WORK_RECORDS,d1
        bls.s   .listed
        moveq   #STE_DIR_FULL,d0
.failed:
        moveq   #0,d1
        tst.l   d0
        rts
.listed:
        moveq   #0,d0
        rts

; ---------------------------------------------------------------------------
; The copies that follow the set
; ---------------------------------------------------------------------------
; A copy's base is the file DB_SET declares for it (read, length and CRC-32
; checked), else the game's own 96/97 copy from game disk 2 (a cup's .TMD in
; the order of its 96/97 participant list, the transfer pool). The records
; of the working group's clubs (all but the key, secondary ID and flag) and
; the pool entries of its players (team name and player record) are taken
; from the working group; a copy that changed is written as a new
; generation and declared in DB_NEW. The group work area holds the group,
; team_group_buffer the copy.

; save_copies: A3 = DB_NEW, D6.l = names listed. D0.l = 0, or the result of
; the copy that failed. Preserves D1-D7/A0-A6.
save_copies:
        movem.l d7,-(sp)
        moveq   #0,d0
        cmpi.w  #NATIONAL_FIRST,WORK_DB+DB_GROUP(a5)
        bcc.s   .done                   ; no national team plays in a cup or the pool
        moveq   #COPY_EUROCUP,d7
.cup:
        bsr.s   save_cup
        bne.s   .done
        addq.w  #1,d7
        cmpi.w  #COPY_POOL,d7
        bcs.s   .cup
        bsr.w   save_pool
.done:
        movem.l (sp)+,d7
        tst.l   d0
        rts

; save_cup: D7.w = a cup's code. D0.l = 0 or a result. Preserves D1-D7/A0-A6.
save_cup:
        movem.l d1-d7/a0-a4,-(sp)
        move.w  d7,d0
        bsr.w   db_cup_teams
        move.l  d0,d5                   ; teams
        lea     team_group_buffer,a2
        bsr.w   declared_copy           ; A4 = its entry in DB_SET
        bne.s   .read
        ; the game's copy only when a 96/97 participant is a club of the
        ; working group
        bsr.w   cup_keys_of             ; A0 = the 96/97 keys
        move.w  WORK_DB+DB_GROUP(a5),d2
        move.w  d5,d3
        subq.w  #1,d3
.scan:
        cmp.b   (a0),d2
        beq.s   .read
        addq.l  #2,a0
        dbf     d3,.scan
        moveq   #0,d0
        bra.s   .done
.read:
        move.w  d7,d0
        bsr.s   db_cup_copy             ; the set's copy, else the game's
        bne.s   .done
        bsr.w   patch_cup               ; D0 = 1 when a record changed
        beq.w   .done
        move.l  d5,d1
        mulu.w  #TEAM_SIZE,d1
        bsr.w   new_copy_generation
.done:
        movem.l (sp)+,d1-d7/a0-a4
        tst.l   d0
        rts

; save_pool: D0.l = 0 or a result. Preserves D1-D7/A0-A6.
save_pool:
        movem.l d1-d7/a0-a4,-(sp)
        moveq   #COPY_POOL,d7
        move.l  #POOL_ENTRIES,d5
        lea     team_group_buffer,a2
        bsr.w   declared_copy
        beq.s   .original
        move.l  #POOL_SIZE,d1
        bsr.w   read_copy
        bne.s   .done
        bra.s   .patch
.original:
        lea     transfer_pool_name,a0
        bsr.w   read_original
        bne.s   .done
        moveq   #STE_SHORT_READ,d0
        cmpi.l  #POOL_SIZE,d1
        bne.s   .done
.patch:
        bsr.w   patch_pool
        beq.s   .done
        move.l  #POOL_SIZE,d1
        bsr.w   new_copy_generation
.done:
        movem.l (sp)+,d1-d7/a0-a4
        tst.l   d0
        rts

; db_cup_copy: D0.w = a cup's code. Reads its team copies into
; team_group_buffer in participant order: the copy the set on the disk
; (DB_SET) declares, else the game's 96/97 copy. D0.l = 0 and D1.l = 1 for
; the set's copy, 0 for the game's; or a result. Preserves D2-D7/A0-A6.
db_cup_copy:
        movem.l d2-d7/a0-a4,-(sp)
        move.w  d0,d7
        bsr.w   db_cup_teams
        move.l  d0,d5
        lea     team_group_buffer,a2
        bsr.s   declared_copy
        beq.s   .original
        move.l  d5,d1
        mulu.w  #TEAM_SIZE,d1
        bsr.s   read_copy
        moveq   #1,d1
        bra.s   .done
.original:
        bsr.w   read_original_cup
        moveq   #0,d1
.done:
        movem.l (sp)+,d2-d7/a0-a4
        tst.l   d0
        rts

; declared_copy: D7.w = copy code. A4 = the entry the set on the disk
; (DB_SET) declares for it with Z clear, or Z set. Changes D0.
declared_copy:
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        bne.s   .none
        move.l  a0,-(sp)
        lea     WORK_DB+DB_SET(a5),a0
        move.w  d7,d0
        bsr.w   db_find_entry           ; Z set when not declared
        movea.l (sp)+,a0
        rts
.none:
        ori.b   #$04,ccr
        rts

; read_copy: A4 = entry of DB_SET, A2 = destination, D1.l = capacity. Reads
; its file and checks its length and CRC-32. D0.l = 0, or STE_VERIFY when
; it is missing or differs. Preserves all other registers.
read_copy:
        movem.l d1/a0-a1,-(sp)
        lea     WORK_DB+DB_NAME(a5),a0
        movea.l a2,a1
        bsr.s   entry_read
        movem.l (sp)+,d1/a0-a1          ; the flags stay
        beq.s   .done
        moveq   #STE_VERIFY,d0
.done:
        rts

; entry_read: A4 = an entry of a manifest, A0 = 16 bytes for its file name,
; A1 = destination, D1.l = its capacity. Builds the name and reads the file.
; D0.l = 0 and D1.l = the length when the file has the entry's length and
; CRC-32; else GC_MISSING (not readable), GC_LENGTH or GC_CRC. Flags from
; D0. Preserves D2-D7/A0-A6.
        xdef    entry_read
entry_read:
        movem.l d2/a0-a1,-(sp)
        exg     a0,a1
        bsr.w   db_entry_name
        movem.l 4(sp),a0-a1             ; the name, the destination
        bsr.l   storage_read            ; D1 = length, within the capacity
        beq.s   .read
        cmpi.l  #STE_TOO_LARGE,d0
        beq.s   .length
        moveq   #GC_MISSING,d0
        bra.s   .done
.read:
        cmp.l   ME_LENGTH(a4),d1
        bne.s   .length
        movea.l a1,a0
        bsr.l   crc32_buffer            ; changes D1-D2
        cmp.l   ME_CRC32(a4),d0
        bne.s   .crc
        move.l  ME_LENGTH(a4),d1
        moveq   #0,d0
        bra.s   .done
.crc:
        moveq   #GC_CRC,d0
        bra.s   .done
.length:
        moveq   #GC_LENGTH,d0
.done:
        movem.l (sp)+,d2/a0-a1
        tst.l   d0
        rts

; read_original: A0 = name of a packed file of game disk 2, A2 =
; destination (team_group_buffer). Reads it as the game's own loader does.
; D0.l = 0 and D1.l = its length, or STE_SHORT_READ. Preserves D2-D7/A0-A6.
read_original:
        movem.l d2-d7/a0-a6,-(sp)
        move.l  a0,-(sp)
        jsr     game_disk2_request      ; the file is read from game disk 2
        movea.l (sp)+,a0
        movea.l a2,a1
        jsr     file_load_unpack        ; D0.w = 0, D1 = length
        clr.w   team_group_cache_valid  ; the buffer no longer holds a loaded group
        movem.l (sp)+,d2-d7/a0-a6
        tst.w   d0
        beq.s   .read
        moveq   #STE_SHORT_READ,d0
        rts
.read:
        moveq   #0,d0
        rts

; read_original_cup: D7.w = cup code, D5.l = teams, A2 = destination. The
; game's 96/97 copy of the cup, its records in the order of the cup's 96/97
; participant list. D0.l = 0 or STE_SHORT_READ (STE_VERIFY when a listed
; key is not in the file). Preserves all other registers.
read_original_cup:
        movem.l d1-d6/a0-a4,-(sp)
        move.w  d7,d0
        subi.w  #COPY_EUROCUP,d0
        mulu.w  #CUP_NAME_STRIDE,d0
        lea     cup_copies_names,a0
        adda.w  d0,a0
        bsr.s   read_original           ; D1 = length
        bne.s   .done
        move.l  d5,d2
        mulu.w  #TEAM_SIZE,d2
        moveq   #STE_SHORT_READ,d0
        cmp.l   d2,d1
        bne.s   .done
        ; sort: record i gets the key of list place i
        bsr.w   cup_keys_of             ; A0 = keys
        movea.l a2,a1                   ; place i
        moveq   #0,d3                   ; i
.place:
        move.w  (a0)+,d4                ; its key
        movea.l a1,a3
        move.w  d3,d2
.find:
        cmp.w   (a3),d4
        beq.s   .found
        lea     TEAM_SIZE(a3),a3
        addq.w  #1,d2
        cmp.w   d5,d2
        bcs.s   .find
        moveq   #STE_VERIFY,d0
        bra.s   .done
.found:
        cmpa.l  a1,a3
        beq.s   .next
        move.w  #TEAM_SIZE/4-1,d2       ; swap the two records
.swap:
        move.l  (a1),d6
        move.l  (a3),(a1)+
        move.l  d6,(a3)+
        dbf     d2,.swap
        lea     -TEAM_SIZE(a1),a1
.next:
        lea     TEAM_SIZE(a1),a1
        addq.w  #1,d3
        cmp.w   d5,d3
        bcs.s   .place
        moveq   #0,d0
.done:
        movem.l (sp)+,d1-d6/a0-a4
        tst.l   d0
        rts

; cup_keys_of: D7.w = cup code. A0 = its 96/97 participant keys
; (DB_CUP_KEYS). Preserves all other registers.
cup_keys_of:
        lea     WORK_DB+DB_CUP_KEYS(a5),a0
        cmpi.w  #COPY_EUROCUP,d7
        beq.s   .done
        lea     CUP_EUROCUP_TEAMS*2(a0),a0
        cmpi.w  #COPY_EUROCWC,d7
        beq.s   .done
        lea     CUP_EUROCWC_TEAMS*2(a0),a0
.done:
        rts

; patch_cup: A2 = D5.l team copies. The working group's clubs among them
; get the bytes of their records in the working group, all but the key,
; the secondary ID and the flag. D0.l = 1 when a byte changed, else 0.
; Preserves all other registers.
patch_cup:
        movem.l d1-d5/a0-a2,-(sp)
        moveq   #0,d4                   ; changed
        move.w  d5,d3
        subq.w  #1,d3
        move.w  WORK_DB+DB_GROUP(a5),d2
.record:
        cmp.b   (a2),d2
        bne.s   .next
        moveq   #0,d0
        move.b  1(a2),d0
        cmp.w   WORK_DB+DB_COUNT(a5),d0
        bcc.s   .next
        mulu.w  #TEAM_SIZE,d0
        lea     GROUP_WORK_OFFSET+GROUP_COUNT_SIZE+TEAM_NAME(a5),a0
        adda.l  d0,a0
        lea     TEAM_NAME(a2),a1
        move.w  #TEAM_SIZE-TEAM_NAME-1,d1
        bsr.s   patch_bytes
.next:
        lea     TEAM_SIZE(a2),a2
        dbf     d3,.record
        move.l  d4,d0
        movem.l (sp)+,d1-d5/a0-a2
        tst.l   d0
        rts

; patch_bytes: A0 = source, A1 = destination, D1.w = bytes - 1. Copies
; them; D4.l = 1 when one differed. Changes D0-D1/A0-A1.
patch_bytes:
        move.b  (a0)+,d0
        cmp.b   (a1),d0
        beq.s   .same
        moveq   #1,d4
        move.b  d0,(a1)
.same:
        addq.l  #1,a1
        dbf     d1,patch_bytes
        rts

; patch_pool: A2 = the transfer pool. The entries of the working group's
; players get their team's name and their player record from the working
; group. D0.l = 1 when a byte changed, else 0. Preserves all other
; registers.
patch_pool:
        movem.l d1-d5/a0-a3,-(sp)
        moveq   #0,d4
        move.w  #POOL_ENTRIES-1,d3
        move.w  WORK_DB+DB_GROUP(a5),d2
.entry:
        cmp.b   POOL_GROUP(a2),d2
        bne.s   .next
        moveq   #0,d0
        move.b  POOL_ORDINAL(a2),d0
        cmp.w   WORK_DB+DB_COUNT(a5),d0
        bcc.s   .next
        mulu.w  #TEAM_SIZE,d0
        lea     GROUP_WORK_OFFSET+GROUP_COUNT_SIZE(a5),a3
        adda.l  d0,a3                   ; the team
        lea     TEAM_NAME(a3),a0
        lea     POOL_TEAM_NAME(a2),a1
        moveq   #TEAM_NAME_SIZE-1,d1
        bsr.s   patch_bytes
        moveq   #0,d0
        move.b  POOL_SLOT(a2),d0
        andi.w  #PLAYER_COUNT-1,d0
        mulu.w  #PLAYER_SIZE,d0
        lea     TEAM_PLAYERS(a3,d0.w),a0
        lea     POOL_PLAYER(a2),a1
        moveq   #PLAYER_SIZE-1,d1
        bsr.s   patch_bytes
.next:
        lea     POOL_ENTRY_SIZE(a2),a2
        dbf     d3,.entry
        move.l  d4,d0
        movem.l (sp)+,d1-d5/a0-a3
        tst.l   d0
        rts

; new_copy_generation: D7.w = copy code, D5.l = records, D1.l = length, A2 =
; the copy, A3 = DB_NEW, D6.l = names listed. Declares it in DB_NEW under
; a generation name no file has and writes it (read back by the slave).
; D0.l = 0 or a result. Preserves all other registers.
new_copy_generation:
        movem.l d1-d4/a0-a1/a4,-(sp)
        move.l  d1,d3
        bsr.s   new_generation
        lea     WORK_DB+DB_NAME(a5),a0
        movea.l a2,a1
        move.l  d3,d1
        bsr.l   storage_write
        movem.l (sp)+,d1-d4/a0-a1/a4
        tst.l   d0
        rts

; new_generation: D7.w = code, D5.w = records, D3.l = length, A2 = the
; data, A3 = DB_NEW, D6.l = names listed. Declares the data in DB_NEW under
; a generation name no file has (DB_NAME). A4 = its entry. Changes
; D0-D2/D4/A0-A1.
new_generation:
        move.w  d7,d0
        movea.l a3,a0
        bsr.w   db_find_entry
        bne.s   .known
        bsr.s   insert_entry            ; A4 = the new entry (generation 0)
.known:
        move.w  ME_GENERATION(a4),d4
        bsr.w   unused_generation       ; its generation, DB_NAME its file
        clr.w   ME_RESERVED(a4)
        move.w  d5,ME_TEAMS(a4)
        move.l  d3,ME_LENGTH(a4)
        movea.l a2,a0
        move.l  d3,d1
        bsr.l   crc32_buffer
        move.l  d0,ME_CRC32(a4)
        rts

; insert_entry: A3 = manifest, D0.w = a code it does not hold. Inserts an
; empty entry for it in code order. A4 = the entry. Preserves all others.
insert_entry:
        movem.l d1-d2/a0-a1,-(sp)
        move.w  MF_COUNT(a3),d1
        lea     MANIFEST_HEADER(a3),a4
        bra.s   .test
.find:
        cmp.w   ME_GROUP(a4),d0
        bcs.s   .found
        lea     MANIFEST_ENTRY(a4),a4
        subq.w  #1,d1
.test:
        tst.w   d1
        bne.s   .find
.found:
        ; move the D1 entries from A4 up by one
        move.w  d1,d2
        lsl.w   #4,d2
        lea     (a4,d2.w),a0            ; end of the entries
        lea     MANIFEST_ENTRY(a0),a1
        bra.s   .move_test
.move:
        move.b  -(a0),-(a1)
.move_test:
        cmpa.l  a4,a0
        bhi.s   .move
        addq.w  #1,MF_COUNT(a3)
        move.w  d0,ME_GROUP(a4)
        clr.w   ME_GENERATION(a4)
        clr.w   ME_TEAMS(a4)
        clr.w   ME_RESERVED(a4)
        clr.l   ME_LENGTH(a4)
        clr.l   ME_CRC32(a4)
        movem.l (sp)+,d1-d2/a0-a1
        rts

; unused_generation: A4 = entry, D4.w = its current generation (0 none).
; D4.w = the next generation whose file name the listing in the listing
; area (D6 records) does not hold, wrapping after GENERATION_MAX; its name
; is in DB_NAME. Preserves all other registers.
unused_generation:
        movem.l d0-d1/a0-a1,-(sp)
        move.w  #GENERATION_MAX,d1      ; tries
.next:
        addq.w  #1,d4
        cmpi.w  #GENERATION_MAX,d4
        bls.s   .name
        moveq   #1,d4
.name:
        move.w  d4,ME_GENERATION(a4)
        lea     WORK_DB+DB_NAME(a5),a1
        bsr.w   db_entry_name
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.s   name_listed
        dbne    d1,.next
        movem.l (sp)+,d0-d1/a0-a1
        rts

; name_listed: A0 = name, D6.l = records in the listing area. Z set when a
; record holds the name (any case). Preserves all registers.
name_listed:
        move.l  a1,-(sp)
        bsr.w   name_record
        movea.l (sp)+,a1
        eori.b  #$04,ccr                ; Z set when found
        rts

; upper: D0.b in upper case.
upper:
        cmpi.b  #'a',d0
        bcs.s   .done
        cmpi.b  #'z',d0
        bhi.s   .done
        subi.b  #'a'-'A',d0
.done:
        rts

; finish_manifest: A3 = manifest with its entries. Writes the header (the
; next generation, identity, base, length, label DB_LABEL) and the CRC-32.
; Preserves all registers.
finish_manifest:
        movem.l d0-d2/a0-a1,-(sp)
        move.l  #MANIFEST_MAGIC_HIGH,MF_MAGIC(a3)
        move.l  #MANIFEST_MAGIC_LOW,MF_MAGIC+4(a3)
        move.w  #MANIFEST_VERSION,MF_VERSION(a3)
        addq.l  #1,MF_GENERATION(a3)
        lea     swos2_identity(pc),a0
        lea     MF_IDENTITY(a3),a1
        moveq   #MANIFEST_IDENTITY_SIZE/4-1,d0
.identity:
        move.l  (a0)+,(a1)+
        dbf     d0,.identity
        move.l  #SWOS2_BASE,MF_BASE(a3)
        moveq   #0,d0
        move.w  MF_COUNT(a3),d0
        lsl.l   #4,d0
        addi.l  #MANIFEST_HEADER,d0
        move.l  d0,MF_LENGTH(a3)
        clr.l   MF_CRC32(a3)
        clr.l   MF_RESERVED(a3)
        lea     WORK_DB+DB_LABEL(a5),a0
        lea     MF_LABEL(a3),a1
        moveq   #SET_LABEL_SIZE-1,d1
        moveq   #0,d2                   ; 1 after the NUL
.label:
        move.b  (a0)+,d0
        bne.s   .char
        moveq   #1,d2
.char:
        tst.w   d2
        beq.s   .store
        moveq   #0,d0
.store:
        move.b  d0,(a1)+
        dbf     d1,.label
        move.l  MF_LENGTH(a3),d1
        movea.l a3,a0
        bsr.l   crc32_buffer
        move.l  d0,MF_CRC32(a3)
        movem.l (sp)+,d0-d2/a0-a1
        rts

; ===========================================================================
; REMOVE OLD VERSIONS
; ===========================================================================

; db_old_versions: D0.w = 0 to count, 1 to delete. Lists the save
; directory and marks every group file that the set (DB_SET, as read on
; entry or saved since), DBASE.BAK or a sound link file references; the
; others are old versions.
;   out: D0.l = 0 and D1.l = old versions found (counting) or deleted;
;        STE_VERIFY while DBASE.CFG is damaged (its files are not known);
;        STE_NOT_FOUND while DBASE.BAK cannot be read after a SAVE of this
;        session failed to write it (WHDLoad no longer sees a file after a
;        failed write to it, and its set may still be whole);
;        STE_DIR_FULL when the directory holds more names than the listing
;        area; or a storage result with D1.l = the files deleted before it.
; Preserves D2-D7/A0-A6.
db_old_versions:
        movem.l d2-d7/a0-a4,-(sp)
        move.w  d0,d7                   ; 1 = delete
        moveq   #0,d5                   ; found or deleted
        moveq   #STE_VERIFY,d0
        cmpi.w  #DSS_DAMAGED,WORK_DB+DB_SET_STATE(a5)
        beq.w   .stopped
        bsr.w   list_dir                ; D6 = names
        bne.w   .stopped
        ; clear the marks (the last byte of each record)
        lea     LIST_WORK_OFFSET(a5),a2
        move.l  d6,d2
        bra.s   .clear_test
.clear:
        clr.b   FS_RECORD_SIZE-1(a2)
        lea     FS_RECORD_SIZE(a2),a2
.clear_test:
        subq.l  #1,d2
        bpl.s   .clear
        ; the set and DBASE.BAK (a DBASE.CFG left damaged by a failed SAVE
        ; still has the set's files: they are the backup's)
        cmpi.w  #DSS_VALID,WORK_DB+DB_SET_STATE(a5)
        bne.s   .backup
        lea     WORK_DB+DB_SET(a5),a0
        bsr.w   mark_manifest
.backup:
        bsr.w   db_backup_usable
        beq.s   .backup_set
        moveq   #STE_NOT_FOUND,d0
        tst.w   WORK_DB+DB_BAK_FAILED(a5)
        bne.w   .stopped                ; DBASE.BAK unseen: its files stay
        bra.s   .links
.backup_set:
        lea     WORK_DB+DB_NEW(a5),a0
        bsr.w   mark_manifest
.links:
        ; every sound link file
        lea     LIST_WORK_OFFSET(a5),a2
        move.l  d6,d2
        bra.s   .link_test
.link:
        movea.l a2,a0
        lea     link_suffixes(pc),a1
        bsr.w   suffix_family           ; D0 = the family of a link name or 0
        beq.s   .link_next
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #LINK_MAX,d1
        bsr.l   storage_read            ; D1 = length
        bne.s   .link_next
        lea     WORK_IO_BUFFER(a5),a0
        moveq   #0,d0                   ; any family
        bsr.w   link_check
        bne.s   .link_next
        lea     WORK_IO_BUFFER+LINK_HEADER+LB_MANIFEST(a5),a0
        bsr.w   mark_manifest
.link_next:
        lea     FS_RECORD_SIZE(a2),a2
.link_test:
        subq.l  #1,d2
        bpl.s   .link
        ; the unmarked group files
        moveq   #0,d5                   ; found or deleted
        lea     LIST_WORK_OFFSET(a5),a2
        move.l  d6,d2
        bra.s   .old_test
.old:
        tst.b   FS_RECORD_SIZE-1(a2)
        bne.s   .old_next
        movea.l a2,a0
        bsr.w   is_generation_name
        bne.s   .old_next
        tst.w   d7
        beq.s   .count
        movea.l a2,a0
        bsr.l   storage_delete
        beq.s   .count
        cmpi.l  #STE_NOT_FOUND,d0
        bne.s   .stopped
        bra.s   .old_next               ; gone already
.count:
        addq.l  #1,d5
.old_next:
        lea     FS_RECORD_SIZE(a2),a2
.old_test:
        subq.l  #1,d2
        bpl.s   .old
        moveq   #0,d0
.stopped:
        move.l  d5,d1
        movem.l (sp)+,d2-d7/a0-a4
        tst.l   d0
        rts

; mark_manifest: A0 = checked manifest, D6.l = records in the listing area.
; Marks the record of every file it declares. Preserves all registers.
mark_manifest:
        movem.l d0-d2/a0-a4,-(sp)
        move.w  MF_COUNT(a0),d2
        lea     MANIFEST_HEADER(a0),a4
        bra.s   .test
.entry:
        lea     WORK_DB+DB_NAME(a5),a1
        bsr.w   db_entry_name
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.w   name_record             ; A1 = record or 0
        beq.s   .next
        st      FS_RECORD_SIZE-1(a1)
.next:
        lea     MANIFEST_ENTRY(a4),a4
.test:
        dbf     d2,.entry
        movem.l (sp)+,d0-d2/a0-a4
        rts

; name_record: A0 = name, D6.l = records. A1 = the record holding it with Z
; clear, or Z set. Preserves all other registers.
name_record:
        movem.l d0-d3/a2,-(sp)
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  d6,d3
        bra.s   .test
.record:
        movea.l a0,a2
        moveq   #0,d2
.char:
        move.b  (a2)+,d0
        bsr.w   upper
        move.b  d0,d1
        move.b  (a1,d2.w),d0
        bsr.w   upper
        cmp.b   d0,d1
        bne.s   .other
        addq.w  #1,d2
        tst.b   d0
        bne.s   .char
        movem.l (sp)+,d0-d3/a2
        andi.b  #$FB,ccr                ; Z clear
        rts
.other:
        lea     FS_RECORD_SIZE(a1),a1
.test:
        subq.l  #1,d3
        bpl.s   .record
        movem.l (sp)+,d0-d3/a2
        suba.l  a1,a1
        ori.b   #$04,ccr                ; Z set
        rts

; is_generation_name: A0 = name. Z set for Tgggnnnn.GRP (any case) of a
; database group or a copy. Preserves all registers.
is_generation_name:
        movem.l d0-d2/a0-a1,-(sp)
        move.b  (a0)+,d0
        bsr.w   upper
        cmpi.b  #'T',d0
        bne.s   .no
        moveq   #0,d1                   ; group
        moveq   #2,d2
        bsr.s   .number
        bne.s   .no
        move.w  d1,-(sp)
        moveq   #0,d1
        moveq   #3,d2
        bsr.s   .number                 ; generation
        movem.w (sp)+,d0
        bne.s   .no
        tst.w   d1
        beq.s   .no
        bsr.w   db_is_set_code
        bne.s   .no
        lea     group_suffix(pc),a1
        moveq   #4,d2
.suffix:
        move.b  (a0)+,d0
        bsr.w   upper
        cmp.b   (a1)+,d0
        dbne    d2,.suffix
        bne.s   .no
        movem.l (sp)+,d0-d2/a0-a1
        ori.b   #$04,ccr                ; Z set
        rts
.no:
        movem.l (sp)+,d0-d2/a0-a1
        andi.b  #$FB,ccr                ; Z clear
        rts
; .number: D2.w + 1 decimal digits at A0 into D1.w. Z set when all digits.
.number:
        move.b  (a0)+,d0
        subi.b  #'0',d0
        cmpi.b  #9,d0
        bhi.s   .not_digit
        mulu.w  #10,d1
        andi.w  #$FF,d0
        add.w   d0,d1
        dbf     d2,.number
        cmp.b   d0,d0
        rts
.not_digit:
        moveq   #1,d0
        rts

; ===========================================================================
; Link files
; ===========================================================================

; suffix_family: A0 = name, A1 = the four four-character suffixes of the
; families FAMILY_DIY to FAMILY_CAREER. D0.l = the family whose suffix ends
; the name (any case) with Z clear, or 0 with Z set. Preserves all other
; registers.
suffix_family:
        movem.l d1-d2/a0-a1,-(sp)
        moveq   #0,d1
.end:
        tst.b   (a0,d1.w)
        beq.s   .length
        addq.w  #1,d1
        cmpi.w  #FS_RECORD_SIZE-1,d1
        bcs.s   .end
.length:
        cmpi.w  #5,d1
        bcs.s   .none
        lea     -4(a0,d1.w),a0
        moveq   #FAMILY_DIY,d2
.suffix:
        movem.l a0-a1,-(sp)
        moveq   #3,d1
.char:
        move.b  (a0)+,d0
        bsr.w   upper
        cmp.b   (a1)+,d0
        dbne    d1,.char
        movem.l (sp)+,a0-a1
        beq.s   .found
        addq.l  #4,a1
        addq.w  #1,d2
        cmpi.w  #FAMILY_CAREER,d2
        bls.s   .suffix
.none:
        moveq   #0,d0
        bra.s   .done
.found:
        moveq   #0,d0
        move.w  d2,d0
.done:
        movem.l (sp)+,d1-d2/a0-a1
        tst.l   d0
        rts

; link_name: A0 = save name (base and four-character suffix), D7.w =
; family. The name of its link file in DB_NAME. Preserves all registers.
link_name:
        movem.l d0-d1/a0-a2,-(sp)
        lea     WORK_DB+DB_NAME(a5),a1
        moveq   #0,d0
.end:
        tst.b   (a0,d0.w)
        beq.s   .base
        addq.w  #1,d0
        cmpi.w  #FS_NAME_MAX,d0
        bcs.s   .end
.base:
        subq.w  #4,d0                   ; without the suffix
        bmi.s   .copied
        bra.s   .test
.copy:
        move.b  (a0)+,(a1)+
.test:
        dbf     d0,.copy
.copied:
        lea     link_suffixes(pc),a2
        move.w  d7,d0
        subq.w  #FAMILY_DIY,d0
        lsl.w   #2,d0
        adda.w  d0,a2
        moveq   #3,d1
.suffix:
        move.b  (a2)+,(a1)+
        dbf     d1,.suffix
        clr.b   (a1)
        movem.l (sp)+,d0-d1/a0-a2
        rts

; link_check: A0 = link file, D1.l = its length, D0.w = the expected family
; (0 any). D0.l = MC_OK, or the first problem of its header, CRC-32 and
; family (LC_*), then of its manifest (MC_*, D1.l = group). The save itself
; is checked by the caller. Preserves D2-D7/A0-A6.
link_check:
        movem.l d2-d7/a0-a4,-(sp)
        movea.l a0,a2
        move.w  d0,d6
        move.l  d1,d7
        moveq   #0,d1
        moveq   #LC_SIZE,d0
        cmpi.l  #LINK_MIN,d7
        bcs.w   .done
        cmpi.l  #LINK_MAX,d7
        bhi.w   .done
        moveq   #LC_MAGIC,d0
        cmpi.l  #LINK_MAGIC_HIGH,LH_MAGIC(a2)
        bne.w   .done
        cmpi.l  #LINK_MAGIC_LOW,LH_MAGIC+4(a2)
        bne.w   .done
        moveq   #LC_VERSION,d0
        move.w  LH_VERSION(a2),d5
        cmpi.w  #LINK_VERSION,d5
        beq.s   .version
        cmpi.w  #LINK_VERSION_V1,d5
        bne.s   .done
.version:
        moveq   #LC_SIZE,d0
        moveq   #0,d2
        move.w  LH_LENGTH(a2),d2
        move.l  d7,d3
        subi.l  #LINK_HEADER,d3
        cmp.l   d3,d2
        bne.s   .done
        move.l  d2,d4                   ; body length
        lea     LINK_HEADER(a2),a0
        move.l  d2,d1
        bsr.l   crc32_buffer
        moveq   #0,d1
        cmp.l   LH_CRC32(a2),d0
        beq.s   .family
        moveq   #LC_CRC,d0
        bra.s   .done
.family:
        moveq   #LC_FAMILY,d0
        move.w  LINK_HEADER+LB_FAMILY(a2),d3
        beq.s   .done
        cmpi.w  #FAMILY_CAREER,d3
        bhi.s   .done
        tst.w   d6
        beq.s   .manifest
        cmp.w   d6,d3
        bne.s   .done
.manifest:
        moveq   #LC_VERSION,d0          ; a version 1 link holds a version 1 manifest
        cmpi.w  #LINK_VERSION_V1,d5
        bne.s   .check
        cmpi.w  #MANIFEST_VERSION_V1,LINK_HEADER+LB_MANIFEST+MF_VERSION(a2)
        bne.s   .done
.check:
        lea     LINK_HEADER+LB_MANIFEST(a2),a0
        move.l  d4,d0
        subi.l  #LB_MANIFEST,d0
        bsr.w   db_manifest_check
.done:
        movem.l (sp)+,d2-d7/a0-a4
        tst.l   d0
        rts

; save_region: D7.w = family. A1 = the competition state a native writer
; saves and D1.l = its length. Preserves all other registers.
save_region:
        move.l  d0,-(sp)
        moveq   #0,d0
        lea     competition_state,a1
        move.w  competition_team_count,d0
        cmpi.w  #FAMILY_SEASON,d7
        bcs.s   .length
        lea     season_state,a1
        move.w  team_selection_count,d0
.length:
        mulu.w  #TEAM_SIZE,d0
        addi.l  #team_selection,d0
        sub.l   a1,d0
        move.l  d0,d1
        move.l  (sp)+,d0
        rts

; ===========================================================================
; The binding
; ===========================================================================

; db_family_reset: from competition_family_reset, after it stored the new
; family. A family that starts is bound to what the switch says; without a
; family nothing is bound. Needs no A5; preserves all registers.
db_family_reset:
        movem.l d0/a0-a1/a5,-(sp)
        movea.l editor_base,a5
        clr.w   transfer_pool_loaded    ; read again for the set the family uses
        clr.w   WORK_DB+DB_BIND(a5)
        tst.w   competition_family
        beq.s   .done
        tst.w   WORK_DB+DB_SWITCH(a5)
        beq.s   .done
        lea     WORK_DB+DB_ACTIVE(a5),a0
        lea     WORK_DB+DB_BOUND(a5),a1
        bsr.w   copy_manifest
        move.w  #1,WORK_DB+DB_BIND(a5)
.done:
        movem.l (sp)+,d0/a0-a1/a5
        rts

; ---------------------------------------------------------------------------
; Competition saves. Each replaces the JSR of a native writer in SAVE
; COMPETITION or the career hub (A0 = the save's name); same contract:
; D0.w = 0 (Z set) when saved, else 1 with the reason shown.
; ---------------------------------------------------------------------------
db_save_diy:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_DIY,d7
        lea     competition_save_diy,a3
        bra.s   save_common
db_save_preset:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_PRESET,d7
        lea     competition_save_preset,a3
        bra.s   save_common
db_save_season:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_SEASON,d7
        lea     competition_save_season,a3
        bra.s   save_common
db_save_career:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_CAREER,d7
        lea     competition_save_career,a3

save_common:
        movea.l editor_base,a5
        movea.l a0,a2                   ; the save's name
        bsr.w   link_name               ; DB_NAME
        tst.w   WORK_DB+DB_BIND(a5)
        beq.s   .native
        bsr.w   link_admission
        bne.s   .refused
.native:
        movem.l d7/a2/a5,-(sp)
        movea.l a2,a0
        jsr     (a3)                    ; the native writer (it and its error
        movem.l (sp)+,d7/a2/a5          ; message change the registers)
        tst.w   d0
        bne.s   .return
        tst.w   WORK_DB+DB_BIND(a5)
        beq.s   .stale
        bsr.w   link_write              ; D0 = 0 or 1
        bra.s   .return
.stale:
        movea.l a2,a0
        bsr.w   link_name
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.l   storage_delete          ; a missing link is fine
        beq.s   .unbound
        cmpi.l  #STE_NOT_FOUND,d0
        beq.s   .unbound
        bsr.w   stale_link_note         ; an earlier save's link stays
.unbound:
        moveq   #0,d0
        bra.s   .return
.refused:
        moveq   #1,d0
.return:
        movem.l (sp)+,d1-d7/a0-a6
        tst.w   d0
        rts

; stale_link_note: D0.l = the result of deleting the link DB_NAME of an
; earlier save of the same name. The save itself is written, but LOAD
; refuses it while that link is there: the note names the file. Preserves
; all registers.
stale_link_note:
        movem.l d0-d1/a0,-(sp)
        lea     link_kept_title(pc),a0
        bsr.l   message_title
        lea     WORK_DB+DB_NAME(a5),a0
        move.l  d0,-(sp)
        moveq   #0,d0
        bsr.l   message_line
        move.l  (sp)+,d0
        moveq   #1,d1                   ; a write
        bsr.l   message_storage_reason
        moveq   #1,d0
        bsr.l   message_line
        lea     link_kept_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        bsr.l   message_show
        movem.l (sp)+,d0-d1/a0
        rts

; link_admission: A2 = save name, DB_NAME = its link. D0.l = 0 when the
; save directory takes the save and its link; otherwise TOO MANY FILES is
; shown and D0.l = 1. Preserves D1-D7/A0-A6.
link_admission:
        movem.l d1-d2/d6/a0-a1,-(sp)
        bsr.w   list_dir                ; D1 = names
        bne.s   .full
        movea.l a2,a0
        bsr.w   name_listed
        beq.s   .save_listed
        addq.l  #1,d1
.save_listed:
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.w   name_listed
        beq.s   .link_listed
        addq.l  #1,d1
.link_listed:
        cmpi.l  #SAVE_DIR_MAX_NAMES,d1
        bhi.s   .full
        moveq   #0,d0
        bra.s   .done
.full:
        lea     not_saved_title(pc),a0
        lea     too_many_lines(pc),a1
        bsr.l   message_note
        moveq   #1,d0
.done:
        movem.l (sp)+,d1-d2/d6/a0-a1
        tst.l   d0
        rts

; link_write: the native save A2 succeeded. Writes its link DB_NAME (read
; back by the slave), asking to try again after a failure; when the user
; gives up, the save is removed, since it cannot go on without its link.
; D0.l = 0 when the link is written, else 1. Preserves D1-D7/A0-A6.
link_write:
        movem.l d1-d4/a0-a4,-(sp)
        bsr.w   save_region             ; A1 = state, D1 = length
        move.l  d1,d3
        movea.l a1,a0
        bsr.l   crc32_buffer
        move.l  d0,d4                   ; the save's CRC-32
        ; the link: header, family, the save's length and CRC-32, the set
        lea     WORK_IO_BUFFER(a5),a4
        move.l  #LINK_MAGIC_HIGH,LH_MAGIC(a4)
        move.l  #LINK_MAGIC_LOW,LH_MAGIC+4(a4)
        move.w  #LINK_VERSION,LH_VERSION(a4)
        move.w  d7,LINK_HEADER+LB_FAMILY(a4)
        move.l  d3,LINK_HEADER+LB_SAVE_LENGTH(a4)
        move.l  d4,LINK_HEADER+LB_SAVE_CRC32(a4)
        lea     WORK_DB+DB_BOUND(a5),a0
        lea     LINK_HEADER+LB_MANIFEST(a4),a1
        bsr.w   copy_manifest
        move.l  WORK_DB+DB_BOUND+MF_LENGTH(a5),d1
        addi.l  #LB_MANIFEST,d1
        move.w  d1,LH_LENGTH(a4)
        lea     LINK_HEADER(a4),a0
        bsr.l   crc32_buffer
        move.l  d0,LH_CRC32(a4)
        ; the save on the disk must be exactly what was saved; when it
        ; differs, trying again cannot help (D4 = 0)
        moveq   #1,d4
        movea.l a2,a0
        bsr.l   storage_size            ; D1 = length
        bne.s   .attempt
        cmp.l   d3,d1
        beq.s   .attempt
        moveq   #0,d4
        moveq   #STE_VERIFY,d0
        bra.s   .failed
.attempt:
        moveq   #0,d1
        move.w  LH_LENGTH(a4),d1
        addi.l  #LINK_HEADER,d1
        lea     WORK_DB+DB_NAME(a5),a0
        movea.l a4,a1
        bsr.l   storage_write
        beq.w   .done
.failed:
        tst.w   d4
        beq.s   .give_up                ; trying again cannot help
        lea     link_failed_title(pc),a0
        bsr.l   message_title
        moveq   #1,d1
        bsr.l   message_storage_reason
        moveq   #0,d0
        bsr.l   message_line
        lea     link_retry_lines(pc),a0
        moveq   #1,d0
        bsr.l   message_lines
        bsr.l   message_ask
        tst.l   d0
        bne.s   .attempt
.give_up:
        movea.l a2,a0                   ; the save, and a link of its name
        bsr.l   storage_delete          ; that an earlier save left
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.l   storage_delete
        lea     link_failed_title(pc),a0
        bsr.l   message_title
        movea.l a2,a0
        moveq   #0,d0
        bsr.l   message_line
        lea     removed_lines(pc),a0
        moveq   #1,d0
        bsr.l   message_lines
        bsr.l   message_show
        moveq   #1,d0
.done:
        movem.l (sp)+,d1-d4/a0-a4
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; db_delete_file: replaces JSR file_operation_dispatch in DELETE FILE
; (delete_file_call): A0 = the save chosen, D7.w = the delete selector. The
; native delete; when it removed a competition save (.DIY .PRE .SEA .CAR),
; the save's link file goes with it, so that no link outlives its save and
; keeps group generations from REMOVE OLD VERSIONS. D0 and the flags are the
; native delete's.
; ---------------------------------------------------------------------------
db_delete_file:
        jsr     file_operation_dispatch
        bne.s   .done
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        lea     save_suffixes(pc),a1
        bsr.w   suffix_family           ; the family of the deleted save
        beq.s   .restore
        move.w  d0,d7
        bsr.w   link_name               ; DB_NAME
        lea     WORK_DB+DB_NAME(a5),a0
        bsr.l   storage_delete          ; STE_NOT_FOUND when it had none
.restore:
        movem.l (sp)+,d0-d7/a0-a6
        tst.w   d0
.done:
        rts

; ---------------------------------------------------------------------------
; Competition loads. Each replaces the JSR of a native loader in LOAD OLD
; COMPETITION (A0 = the save's name); same contract: D0.w = 0 (Z set) when
; the competition is loaded; otherwise the native code resets the family
; and returns to the main menu.
; ---------------------------------------------------------------------------
db_load_diy:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_DIY,d7
        lea     competition_load_diy,a3
        bra.s   load_common
db_load_preset:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_PRESET,d7
        lea     competition_load_preset,a3
        bra.s   load_common
db_load_season:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_SEASON,d7
        lea     competition_load_season,a3
        bra.s   load_common
db_load_career:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #FAMILY_CAREER,d7
        lea     competition_load_career,a3

load_common:
        movea.l editor_base,a5
        movea.l a0,a2
        bsr.w   link_name               ; DB_NAME
        clr.w   WORK_DB+DB_BIND(a5)
        lea     WORK_DB+DB_NAME(a5),a0
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #LINK_MAX,d1
        bsr.l   storage_read            ; D1 = length
        beq.s   .read
        cmpi.l  #STE_NOT_FOUND,d0
        beq.w   .native                 ; no link: the original database
        moveq   #LC_SIZE,d0             ; longer than any link, or unreadable
        bra.w   .damaged
.read:
        movea.l a1,a0
        move.w  d7,d0
        bsr.w   link_check
        bne.w   .damaged
        ; the save must be exactly the one the link was written for
        movea.l a2,a0
        bsr.l   storage_size            ; D1 = length
        bne.s   .native                 ; unreadable: the native load reports it
        lea     WORK_IO_BUFFER(a5),a4
        cmp.l   LINK_HEADER+LB_SAVE_LENGTH(a4),d1
        bne.s   .other_save
        movea.l a2,a0
        bsr.w   file_crc                ; D1 = CRC-32
        bne.s   .native
        cmp.l   LINK_HEADER+LB_SAVE_CRC32(a4),d1
        beq.s   .set
.other_save:
        moveq   #LC_SAVE,d0
        moveq   #0,d1
        bra.s   .damaged
.set:
        ; every file of the set, then the binding
        lea     LINK_HEADER+LB_MANIFEST(a4),a0
        bsr.w   db_verify_set           ; keeps A0 and the link
        bne.s   .not_found
        lea     WORK_DB+DB_BOUND(a5),a1
        bsr.w   copy_manifest
        move.w  #1,WORK_DB+DB_BIND(a5)
.native:
        clr.w   team_group_cache_valid
        clr.w   transfer_pool_loaded
        movea.l a2,a0
        jsr     (a3)                    ; the native loader
        bra.s   .return
.damaged:
        lea     link_damaged_title(pc),a0
        lea     link_damaged_line2(pc),a3
        bra.s   .refuse
.not_found:
        lea     not_found_title(pc),a0
        lea     not_found_line2(pc),a3
.refuse:
        bsr.l   message_title
        move.l  d0,d2                   ; the problem; D2 is free here
        movea.l a2,a0
        moveq   #0,d0
        bsr.l   message_line
        move.l  d2,d0
        lea     WORK_DB+DB_STATUS(a5),a1
        clr.b   (a1)
        bsr.w   db_problem_text
        lea     WORK_DB+DB_STATUS(a5),a0
        moveq   #1,d0
        bsr.l   message_line
        movea.l a3,a0
        moveq   #2,d0
        bsr.l   message_line
        bsr.l   message_show
        moveq   #1,d0
.return:
        movem.l (sp)+,d1-d7/a0-a6
        tst.w   d0
        rts

; ===========================================================================
; Data
; ===========================================================================
zero_long:              dc.l    0
swos2_identity:
        dc.l    SWOS2_ID_0,SWOS2_ID_1,SWOS2_ID_2,SWOS2_ID_3
        dc.l    SWOS2_ID_4,SWOS2_ID_5,SWOS2_ID_6,SWOS2_ID_7

; The database groups in the order of the database screen: the club groups
; by group code, then the national groups.
database_groups:
        dc.b    0,1,2,3,4,5,6,7,8
        dc.b    10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28
        dc.b    29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46
        dc.b    48,49,50,51,55,60,62,64,65,66,67,69,71,73,75,76,77,78,79
        dc.b    80,81,82,83,84,85
database_groups_end:
        if database_groups_end-database_groups!=DATABASE_GROUP_COUNT
        fail "database_groups does not hold DATABASE_GROUP_COUNT groups"
        endif

link_suffixes:          dc.b    '.DLD.DLP.DLS.DLC'
save_suffixes:          dc.b    '.DIY.PRE.SEA.CAR'
group_suffix:           dc.b    '.GRP',0
config_name:            dc.b    'DBASE.CFG',0
switch_name:            dc.b    'DBASE.USE',0
caption_off_prefix:     dc.b    'DATABASE OFF: ',0
caption_missing:        dc.b    ' MISSING',0
caption_damaged:        dc.b    ' DAMAGED',0
backup_name:            dc.b    'DBASE.BAK',0
team_file_prefix:       dc.b    'data/team.',0
caption_prefix:         dc.b    'DATABASE: ',0
edited_text:            dc.b    'EDITED',0
not_saved_title:        dc.b    'COMPETITION NOT SAVED',0
too_many_lines:         dc.b    'TOO MANY FILES',0
                        dc.b    'THE SAVE DIRECTORY CANNOT TAKE THE SAVE',0
                        dc.b    'AND ITS DATABASE LINK. REMOVE OLD VERSIONS.',0
                        dc.b    0
link_failed_title:      dc.b    'DATABASE LINK NOT SAVED',0
link_retry_lines:       dc.b    'THE SAVE NEEDS IT TO KEEP THE EDITED DATABASE.',0
                        dc.b    'TRY AGAIN?',0
                        dc.b    0
removed_lines:          dc.b    'WAS REMOVED: IT CANNOT GO ON WITHOUT ITS LINK.',0
                        dc.b    'THE COMPETITION IS STILL IN MEMORY.',0
                        dc.b    0
link_damaged_title:     dc.b    'DATABASE LINK DAMAGED',0
link_kept_title:        dc.b    'OLD DATABASE LINK KEPT',0
link_kept_lines:        dc.b    'IT BELONGS TO AN EARLIER SAVE OF THIS NAME:',0
                        dc.b    'DELETE IT, OR THIS SAVE CANNOT BE LOADED.',0
                        dc.b    0
link_damaged_line2:     dc.b    'THE COMPETITION CANNOT BE LOADED.',0
not_found_title:        dc.b    'DATABASE NOT FOUND',0
not_found_line2:        dc.b    'THE EDITED DATABASE OF THIS SAVE IS NOT HERE.',0
        even

; Problem texts: # is the group, $ the file name in DB_NAME (database.i).
PTEXT   macro
        dc.w    problem_\1-problem_texts
        endm
problem_texts:
        dc.w    0                       ; MC_OK
        PTEXT   size
        PTEXT   magic
        PTEXT   version
        PTEXT   crc
        PTEXT   identity
        PTEXT   label
        PTEXT   group
        PTEXT   order
        PTEXT   entry
        PTEXT   link_size
        PTEXT   link_magic
        PTEXT   link_version
        PTEXT   link_crc
        PTEXT   link_family
        PTEXT   link_save
        dc.w    0,0,0,0                 ; 16-19
        PTEXT   missing
        PTEXT   length
        PTEXT   file_crc
        PTEXT   content
problem_size:           dc.b    'THE MANIFEST HAS THE WRONG SIZE.',0
problem_magic:          dc.b    'THE FILE IS NOT A DATABASE MANIFEST.',0
problem_version:        dc.b    'THE MANIFEST HAS AN UNKNOWN VERSION.',0
problem_crc:            dc.b    'THE MANIFEST CRC-32 DIFFERS.',0
problem_identity:       dc.b    'THE SET IS FOR ANOTHER VERSION OF THE GAME.',0
problem_label:          dc.b    'THE SET LABEL CANNOT BE SHOWN BY THE GAME.',0
problem_group:          dc.b    'GROUP # IS NOT A DATABASE GROUP.',0
problem_order:          dc.b    'THE GROUPS ARE OUT OF ORDER OR LISTED TWICE.',0
problem_entry:          dc.b    'THE ENTRY OF GROUP # IS DAMAGED.',0
problem_link_size:      dc.b    'THE LINK FILE HAS THE WRONG SIZE.',0
problem_link_magic:     dc.b    'THE FILE IS NOT A DATABASE LINK.',0
problem_link_version:   dc.b    'THE LINK FILE HAS AN UNKNOWN VERSION.',0
problem_link_crc:       dc.b    'THE LINK FILE CRC-32 DIFFERS.',0
problem_link_family:    dc.b    'THE LINK BELONGS TO ANOTHER KIND OF SAVE.',0
problem_link_save:      dc.b    'THE SAVE DOES NOT MATCH ITS LINK.',0
problem_missing:        dc.b    '$ IS MISSING.',0
problem_length:         dc.b    '$ HAS THE WRONG LENGTH.',0
problem_file_crc:       dc.b    '$ HAS ANOTHER CRC-32.',0
problem_content:        dc.b    '$ IS DAMAGED.',0
        even
