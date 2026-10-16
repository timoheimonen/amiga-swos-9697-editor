; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The copies that follow the database in use: the European club cups'
; team copies and the transfer pool.
;
; The game keeps two copies of database teams and players outside the TEAM
; groups: each European club cup reads its clubs' team records from its
; own file (data/eurocup.tmd, eurocwc.tmd, uefacup.tmd) into the cached-team
; list, which a season or career save keeps; the career's transfer market
; reads data/poolplyr.dat, 900 player entries with their team names, again
; after every match. A set may declare its own copies of them (database.i
; COPY_*); while that set is the database in use (db_manifest_in_use: the
; set a competition family is bound to, or the switch's set without one),
; the hooks below read the set's copy instead of the game's file:
;
;   cup_copies_read  replaces JSR file_load_unpack at cup_copies_read_call
;                    (A0 = the cup's file name, A1 = the place in the cached
;                    list). The cup's participants are the keys of its
;                    copies in order: they are written to the cup's static
;                    participant list before the game selects them; without
;                    a copy of the set the game's 96/97 list is put back and
;                    the native read follows.
;   pool_read        replaces JSR file_load_unpack at transfer_pool_read_call
;                    (A0 = transfer_pool_name, A1 = transfer_pool).
;
; A copy is read whole, bounded to its length, and its length and CRC-32
; are checked before it is used; like the gateway, a copy that fails is
; never used: the read is tried again until it passes (the set was verified
; before it came into use). Return contract of file_load_unpack: D0.w = 0
; with Z set, D1 = length, D2-D7/A0-A6 preserved.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    copies_init, cup_copies_read, pool_read, copy_read_bounded
        xref    editor_base
        xref    db_manifest_in_use, db_find_entry, db_cup_teams, entry_read

RETRY_FRAMES            equ 50

        section .text,code

; ---------------------------------------------------------------------------
; copies_init: A5 = editor base. Keeps the cups' 96/97 participant lists
; (the static lists of SWOS2 as it was loaded) in DB_CUP_KEYS. Preserves
; all registers.
; ---------------------------------------------------------------------------
copies_init:
        movem.l d0/d5/d7/a1/a3,-(sp)
        moveq   #COPY_EUROCUP,d7
.cup:
        bsr.w   cup_static_keys         ; A1 = the static list, A3 = its place
        subq.w  #1,d5
.key:
        move.w  (a1)+,(a3)+
        dbf     d5,.key
        addq.w  #1,d7
        cmpi.w  #COPY_EUROCUP+CUP_COUNT,d7
        bcs.s   .cup
        movem.l (sp)+,d0/d5/d7/a1/a3
        rts

; ---------------------------------------------------------------------------
; cup_copies_read
; ---------------------------------------------------------------------------
cup_copies_read:
        movem.l d2-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        movea.l a1,a2                   ; destination
        moveq   #COPY_EUROCUP,d7
        lea     cup_copies_names,a1
        moveq   #CUP_COUNT-1,d2
.name:
        cmpa.l  a1,a0
        beq.s   .cup
        lea     CUP_NAME_STRIDE(a1),a1
        addq.w  #1,d7
        dbf     d2,.name
        bra.s   .native                 ; not a cup's file
.cup:
        bsr.w   cup_static_keys         ; A1 = static list, A3 = 96/97 keys, D5 = teams
        bsr.l   db_manifest_in_use      ; A0 = manifest or Z set
        beq.s   .original
        move.w  d7,d0
        bsr.l   db_find_entry           ; A4 = entry
        beq.s   .original
        bsr.w   read_verified           ; D1 = length
        bsr.s   cup_static_keys
        ; the copy's keys are the cup's participants
        movea.l a2,a0
        move.w  d5,d0
        subq.w  #1,d0
.key:
        move.w  (a0),(a1)+
        lea     TEAM_SIZE(a0),a0
        dbf     d0,.key
        movem.l (sp)+,d2-d7/a0-a6
        clr.w   d0
        rts
.original:
        move.w  d5,d0                   ; the 96/97 participants
        subq.w  #1,d0
.restore:
        move.w  (a3)+,(a1)+
        dbf     d0,.restore
.native:
        movem.l (sp)+,d2-d7/a0-a6
        jmp     file_load_unpack

; cup_static_keys: D7.w = cup code. A1 = the cup's static participant list
; in SWOS2, A3 = its 96/97 keys (DB_CUP_KEYS), D5.l = its teams. Changes D0.
cup_static_keys:
        move.w  d7,d0
        bsr.l   db_cup_teams
        move.l  d0,d5
        lea     WORK_DB+DB_CUP_KEYS(a5),a3
        lea     eurocup_key_list,a1
        cmpi.w  #COPY_EUROCUP,d7
        beq.s   .done
        lea     CUP_EUROCUP_TEAMS*2(a3),a3
        lea     eurocwc_key_list,a1
        cmpi.w  #COPY_EUROCWC,d7
        beq.s   .done
        lea     CUP_EUROCWC_TEAMS*2(a3),a3
        lea     uefacup_key_list,a1
.done:
        rts

; ---------------------------------------------------------------------------
; pool_read
; ---------------------------------------------------------------------------
pool_read:
        movem.l d2-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        movea.l a1,a2
        bsr.l   db_manifest_in_use
        beq.s   .native
        move.w  #COPY_POOL,d0
        bsr.l   db_find_entry
        beq.s   .native
        bsr.s   read_verified           ; D1 = length
        movem.l (sp)+,d2-d7/a0-a6
        clr.w   d0
        rts
.native:
        movem.l (sp)+,d2-d7/a0-a6
        jmp     file_load_unpack

; read_verified: A4 = the copy's entry, A2 = destination. Reads its file
; until it has the entry's length and CRC-32. D1.l = length. Changes D0,
; D2-D3/A0-A1.
read_verified:
        move.l  ME_LENGTH(a4),d3
; copy_read_bounded: the same with D3.l = the destination's capacity (the
; team group gateway's buffer).
copy_read_bounded:
.attempt:
        lea     WORK_DB+DB_COPY_NAME(a5),a0
        movea.l a2,a1
        move.l  d3,d1
        bsr.l   entry_read              ; D1 = length
        bne.s   .wait
        rts
.wait:
        moveq   #RETRY_FRAMES-1,d2
.frame:
        move.w  frame_counter,d0
.same:
        cmp.w   frame_counter,d0
        beq.s   .same
        dbf     d2,.frame
        bra.s   .attempt
