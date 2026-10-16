; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Tactics: the checks of a tactic record, the user-owned tactic slots and
; the editor's part of EDIT TACTICS. The native slot chooser, pitch and
; controls stay as they are; runtime hooks add:
;
;   tactics_save_exit     SAVE/EXIT: a changed working tactic is checked
;                         before the native commit; a refused one stays in
;                         the editor with a message naming the problem.
;                         After a commit the slot is user-owned and its
;                         record is copied.
;   tactics_load_file     the read of a .TAC file (LOAD in the IMPORT
;                         chooser): the length is queried first, exactly
;                         TACTIC_SIZE bytes are read into the editor's I/O
;                         buffer and checked; only a valid record reaches
;                         the working tactic.
;   tactics_save_file     the write of a .TAC file: the working tactic is
;                         checked, written and read back by the slave.
;   tactic_import_count_patch  IMPORT copies exactly the TACTIC_BODY_SIZE
;                         body bytes of the chosen record; the native copy
;                         moves nine more, over the editor's UNDO copy.
;   tactics_family_reset  a new competition resets the six user slots; then
;                         the user-owned slots are restored from their
;                         copies, the role order is rebuilt and the teams
;                         using them are marked for a rebuild.
;   tactics_competition_loaded  a competition save has been loaded: its own
;                         six slots replace the user's, so no slot stays
;                         user-owned.
;   storage_volume_ready  (resident/storage.s) the save-disk requests of the
;                         .TAC save and load.
;
; A slot becomes user-owned when the user commits it in EDIT TACTICS (a
; pitch edit, COPY, IMPORT or a loaded .TAC, then SAVE/EXIT) or when
; tactics_install puts a record into it, and stays so until a competition
; save is loaded. Ownership and copies live in the working data only.
;
; For the other editors:
;   tactic_check          checks a record
;   tactic_problem_text   the problem a check found, as one line of text
;   tactics_owned         the user-owned slots
;   tactics_install       installs a checked record in a user slot as
;                         user-owned, with the native refresh
;
; Native action contract: the menu tick saves D0-D7/A0-A6 around an action
; and passes A5 = the selected expanded entry.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    tactic_check, tactic_problem_text, tactics_owned, tactics_install
        xdef    tactics_save_exit, tactics_load_file, tactics_save_file
        xdef    tactics_family_reset, tactics_competition_loaded
        xdef    tactic_import_count_patch
        xref    editor_base
        xref    db_family_reset, boundary_family_started
        xref    storage_size, storage_read, storage_write, storage_native_result
        xref    message_title, message_line, message_lines, message_show
        xref    text_copy, text_decimal

        section .text,code

; ---------------------------------------------------------------------------
; tactic_check: A0 = tactic record (TACTIC_SIZE bytes).
;   out: D0.l = TC_OK, or the first problem in this order (tactic.i):
;        TC_NAME    the name field holds no NUL
;        TC_RANGE   D1 = map, D2 = zone, D3 = x above TACTIC_X_MAX; the maps
;                   in record order, each map's zones in order
;        TC_SHARED  D1 < D2 = maps, D3 = zone: two roles on one position;
;                   the zones in order, then the first map, then the second
;        TC_LABEL   D1 = map, D2 = its label, neither 0-4 nor unpaired
;        TC_PAIR    D1 = label, D2 = maps using it, neither 0 nor 2
;        TC_BASE    D1 = base formation, not a builtin
;        Flags are set from D0. y (four bits) and the zones (35 bytes per
;        map) cannot leave their ranges.
; Preserves D4-D7/A0-A6.
; ---------------------------------------------------------------------------
tactic_check:
        movem.l d4-d5/a1-a2,-(sp)
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        ; the name: a NUL inside its field
        movea.l a0,a1
        moveq   #TACTIC_NAME_SIZE-1,d4
.name:
        tst.b   (a1)+
        beq.s   .coordinates
        dbf     d4,.name
        moveq   #TC_NAME,d0
        bra.w   .done
        ; x of every position
.coordinates:
        lea     TACTIC_MAPS(a0),a1
.map:
        moveq   #0,d2
.zone:
        moveq   #0,d3
        move.b  (a1)+,d3
        lsr.w   #4,d3
        cmpi.w  #TACTIC_X_MAX,d3
        bls.s   .x_valid
        moveq   #TC_RANGE,d0
        bra.w   .done
.x_valid:
        addq.w  #1,d2
        cmpi.w  #TACTIC_ZONES,d2
        bcs.s   .zone
        addq.w  #1,d1
        cmpi.w  #TACTIC_ROLES,d1
        bcs.s   .map
        ; no two roles on one position of a zone
        moveq   #0,d3
.shared_zone:
        lea     TACTIC_MAPS(a0,d3.w),a1 ; zone d3 of map 0
        moveq   #0,d1
.first:
        move.w  d1,d4
        mulu.w  #TACTIC_ZONES,d4
        move.b  (a1,d4.w),d5
        move.w  d1,d2
.second:
        addq.w  #1,d2
        cmpi.w  #TACTIC_ROLES,d2
        bcc.s   .next_first
        move.w  d2,d4
        mulu.w  #TACTIC_ZONES,d4
        cmp.b   (a1,d4.w),d5
        bne.s   .second
        moveq   #TC_SHARED,d0
        bra.s   .done
.next_first:
        addq.w  #1,d1
        cmpi.w  #TACTIC_ROLES-1,d1
        bcs.s   .first
        addq.w  #1,d3
        cmpi.w  #TACTIC_ZONES,d3
        bcs.s   .shared_zone
        ; mirror pair labels: 0-4 or unpaired
        lea     TACTIC_PAIRS(a0),a1
        moveq   #0,d1
.label:
        moveq   #0,d2
        move.b  (a1,d1.w),d2
        cmpi.w  #TACTIC_UNPAIRED,d2
        beq.s   .label_next
        cmpi.w  #TACTIC_PAIR_LABELS,d2
        bcs.s   .label_next
        moveq   #TC_LABEL,d0
        bra.s   .done
.label_next:
        addq.w  #1,d1
        cmpi.w  #TACTIC_ROLES,d1
        bcs.s   .label
        ; a used label on exactly two maps
        moveq   #0,d1
.pair:
        moveq   #0,d2
        movea.l a1,a2
        moveq   #TACTIC_ROLES-1,d4
.count:
        cmp.b   (a2)+,d1
        bne.s   .count_next
        addq.w  #1,d2
.count_next:
        dbf     d4,.count
        tst.w   d2
        beq.s   .pair_next
        cmpi.w  #2,d2
        beq.s   .pair_next
        moveq   #TC_PAIR,d0
        bra.s   .done
.pair_next:
        addq.w  #1,d1
        cmpi.w  #TACTIC_PAIR_LABELS,d1
        bcs.s   .pair
        ; the base formation selects a builtin
        moveq   #0,d1
        moveq   #0,d2
        move.b  TACTIC_BASE(a0),d1
        moveq   #TC_OK,d0
        cmpi.w  #TACTIC_BUILTIN_COUNT,d1
        bcs.s   .done
        moveq   #TC_BASE,d0
.done:
        movem.l (sp)+,d4-d5/a1-a2
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; tactic_problem_text: D0.l = result of tactic_check (or TC_SIZE with D1.l =
; the file length), D1-D3 = its details. Appends one line naming the
; problem at A1 (text helpers: A1 ends on the NUL). Maps are named by their
; lineup role (map + TACTIC_FIRST_ROLE). Preserves all other registers.
; ---------------------------------------------------------------------------
tactic_problem_text:
        movem.l d0-d4/a0,-(sp)
        move.l  d0,d4
        lea     text_size(pc),a0
        cmpi.w  #TC_SIZE,d4
        bne.s   .name
        bsr.l   text_copy
        cmpi.l  #$FFFF,d1
        bls.s   .length
        lea     text_size_over(pc),a0
        bsr.l   text_copy
        bra.s   .size_end
.length:
        move.w  d1,d0
        bsr.l   text_decimal
.size_end:
        lea     text_size_end(pc),a0
        bra.w   .last
.name:
        lea     text_name(pc),a0
        cmpi.w  #TC_NAME,d4
        beq.w   .last
        lea     text_range(pc),a0
        cmpi.w  #TC_RANGE,d4
        beq.s   .one
        lea     text_label(pc),a0
        cmpi.w  #TC_LABEL,d4
        beq.s   .one
        cmpi.w  #TC_SHARED,d4
        bne.s   .pair
        lea     text_players(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.w   role_number
        lea     text_and(pc),a0
        bsr.l   text_copy
        move.w  d2,d0
        bsr.w   role_number
        lea     text_shared(pc),a0
        bsr.l   text_copy
        move.w  d3,d0
.zone_end:
        bsr.l   text_decimal
        lea     text_stop(pc),a0
        bra.w   .last
.one:                                   ; one player: A0 = what is wrong
        move.l  a0,d3
        lea     text_player(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.w   role_number
        movea.l d3,a0
        bsr.l   text_copy
        move.w  d2,d0
        bra.s   .zone_end
.pair:
        cmpi.w  #TC_PAIR,d4
        bne.s   .base
        lea     text_pair(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.l   text_decimal
        lea     text_pair_one(pc),a0
        cmpi.w  #1,d2
        beq.s   .last
        lea     text_pair_has(pc),a0
        bsr.l   text_copy
        move.w  d2,d0
        bsr.l   text_decimal
        lea     text_pair_end(pc),a0
        bra.w   .last
.base:
        cmpi.w  #TC_BASE,d4
        bne.s   .done
        lea     text_base(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.l   text_decimal
        lea     text_base_end(pc),a0
.last:
        bsr.l   text_copy
.done:
        movem.l (sp)+,d0-d4/a0
        rts

; role_number: D0.w = map. Appends its lineup role at A1.
role_number:
        addq.w  #TACTIC_FIRST_ROLE,d0
        bra.l   text_decimal

; ---------------------------------------------------------------------------
; tactics_owned: D0.l = mask of the user-owned slots (bit n = USER A+n).
; ---------------------------------------------------------------------------
tactics_owned:
        move.l  a0,-(sp)
        movea.l editor_base,a0
        moveq   #0,d0
        move.w  WORK_TACTICS+TT_OWNED(a0),d0
        movea.l (sp)+,a0
        rts

; ---------------------------------------------------------------------------
; tactics_install: A0 = tactic record, D0.w = user slot 0-5.
;   out: D0.l = TC_OK when the record is in the slot, user-owned and
;        refreshed (role order, teams using it); otherwise the result of
;        tactic_check and nothing changed (or -1 for a slot outside 0-5).
;        Flags are set from D0.
; ---------------------------------------------------------------------------
tactics_install:
        movem.l d1-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        move.w  d0,d6
        moveq   #-1,d0
        cmpi.w  #USER_TACTIC_SLOTS,d6
        bcc.s   .done
        movea.l a0,a2
        bsr.w   check_and_record
        bne.s   .done
        move.w  d6,d0
        bsr.w   slot_addresses          ; A0 = copy, A1 = slot
        movea.l a0,a3
        movea.l a2,a0
        bsr.w   copy_record             ; into the slot
        movea.l a2,a0
        movea.l a3,a1
        bsr.w   copy_record             ; into the copy
        bset    d6,WORK_TACTICS+TT_OWNED+1(a5) ; slots 0-5: the low byte
        moveq   #0,d7
        bset    d6,d7
        bsr.w   refresh_slots
        moveq   #TC_OK,d0
.done:
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; tactics_save_exit: action of SAVE/EXIT (tactic_save_exit_operand). A
; changed working tactic must pass tactic_check before the native SAVE/EXIT
; commits it; after a commit the slot is user-owned.
; ---------------------------------------------------------------------------
tactics_save_exit:
        move.l  a5,-(sp)                ; the selected entry
        movea.l editor_base,a5
        tst.w   tactic_editor_dirty
        beq.s   .native
        lea     tactic_work_buffer,a0
        bsr.w   check_and_record
        beq.s   .native
        lea     title_refused(pc),a0
        moveq   #0,d0
        bsr.w   problem_message
        lea     refused_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        bsr.l   message_show
        movea.l (sp)+,a5
        rts
.native:
        movea.l (sp)+,a5
        move.w  tactic_editor_dirty,-(sp)
        move.w  tactic_editor_slot,-(sp)
        jsr     tactic_save_exit
        move.w  (sp)+,d1                ; the slot edited
        move.w  (sp)+,d0                ; changed: committed
        beq.s   .done
        subi.w  #TACTIC_USER_FIRST,d1
        cmpi.w  #USER_TACTIC_SLOTS,d1
        bcc.s   .done
        movea.l editor_base,a5          ; the menu tick restores A5
        move.w  d1,d0
        bsr.w   own_slot
.done:
        rts

; own_slot: D0.w = user slot 0-5. Copies the slot and marks it user-owned.
; Preserves all registers.
own_slot:
        movem.l d0-d1/a0-a1,-(sp)
        move.w  d0,d1
        bsr.w   slot_addresses          ; A0 = copy, A1 = slot
        exg     a0,a1
        bsr.w   copy_record
        bset    d1,WORK_TACTICS+TT_OWNED+1(a5) ; slots 0-5: the low byte
        movem.l (sp)+,d0-d1/a0-a1
        rts

; ---------------------------------------------------------------------------
; tactics_load_file: replaces JSR tactic_file_load (tactic_load_call).
;   in:  A0 = file name, A1 = tactic_work_buffer
;   out: D0.w = 0 with Z set when the file's record is in the working
;        tactic; otherwise 1 (Z clear) after a message, the working tactic
;        unchanged: the native message for a read failure, FILE DAMAGED for
;        a file that is not one valid tactic record.
; ---------------------------------------------------------------------------
tactics_load_file:
        movem.l d1-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        movea.l a0,a3                   ; name
        movea.l a1,a2                   ; working tactic
        bsr.l   storage_size            ; D1 = length
        bne.s   tactic_file_failed
        cmpi.l  #TACTIC_SIZE,d1
        beq.s   .read
        moveq   #TC_SIZE,d0
        moveq   #0,d2
        moveq   #0,d3
        bsr.w   record_check
        bra.s   .damaged
.read:
        movea.l a3,a0
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #TACTIC_SIZE,d1
        bsr.l   storage_read            ; never more than TACTIC_SIZE bytes
        bne.s   tactic_file_failed
        lea     WORK_IO_BUFFER(a5),a0
        bsr.w   check_and_record
        bne.s   .damaged
        movea.l a2,a1
        bsr.w   copy_record
        moveq   #0,d0
        bra.s   tactic_file_return
.damaged:
        lea     title_damaged(pc),a0
        moveq   #1,d0
        bsr.w   problem_message
        movea.l a3,a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_not_loaded(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bsr.l   message_show
        moveq   #1,d0
        bra.s   tactic_file_return
; The ends of both file hooks: a failed storage call gets the native
; message.
tactic_file_failed:
        bsr.l   storage_native_result
        jsr     file_error_message
        moveq   #1,d0
tactic_file_return:
        movem.l (sp)+,d1-d7/a0-a6
        tst.w   d0
        rts

; ---------------------------------------------------------------------------
; tactics_save_file: replaces JSR tactic_file_save (tactic_save_call).
;   in:  A0 = file name, A1 = tactic_work_buffer
;   out: D0.w = 0 with Z set when exactly TACTIC_SIZE bytes are written and
;        read back; otherwise 1 (Z clear) after a message: the native one
;        for a failed write, TACTIC NOT SAVED for an invalid record.
; ---------------------------------------------------------------------------
tactics_save_file:
        movem.l d1-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        movea.l a0,a3
        movea.l a1,a2
        movea.l a1,a0
        bsr.w   check_and_record
        bne.s   .refused
        movea.l a3,a0
        movea.l a2,a1
        move.l  #TACTIC_SIZE,d1
        bsr.l   storage_write           ; read back and compared
        beq.s   tactic_file_return
        bra.s   tactic_file_failed
.refused:
        lea     title_not_saved(pc),a0
        moveq   #0,d0
        bsr.w   problem_message
        lea     line_not_written(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        bsr.l   message_show
        moveq   #1,d0
        bra.s   tactic_file_return

; ---------------------------------------------------------------------------
; tactics_family_reset: replaces the end of competition_family_reset (JSR
; tactic_slots_reset and RTS, family_reset_tactic_call). The binding of the
; new family to the database (db_family_reset), the notes of the new family
; (boundary_family_started), the native reset of the six user slots, then
; every user-owned slot back from its copy.
; ---------------------------------------------------------------------------
tactics_family_reset:
        bsr.l   db_family_reset         ; the binding of the new family
        bsr.l   boundary_family_started
        jsr     tactic_slots_reset
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        move.w  WORK_TACTICS+TT_OWNED(a5),d7
        beq.s   .done
        moveq   #0,d6
.slot:
        btst    d6,d7
        beq.s   .next
        move.w  d6,d0
        bsr.w   slot_addresses          ; A0 = copy, A1 = slot
        bsr.w   copy_record
.next:
        addq.w  #1,d6
        cmpi.w  #USER_TACTIC_SLOTS,d6
        bcs.s   .slot
        bsr.w   refresh_slots
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; tactics_competition_loaded: replaces JSR competition_load_finish after a
; competition save has been loaded (diy_loaded_call, preset_loaded_call,
; season_loaded_call). The save's slots are not the user's.
; ---------------------------------------------------------------------------
tactics_competition_loaded:
        bsr.l   boundary_family_started
        move.l  a0,-(sp)
        movea.l editor_base,a0
        clr.w   WORK_TACTICS+TT_OWNED(a0)
        movea.l (sp)+,a0
        jmp     competition_load_finish

; ---------------------------------------------------------------------------
; Helpers. A5 = editor base.
; ---------------------------------------------------------------------------

; refresh_slots: D7.w = mask of user slots whose records changed. The
; native post-commit refresh: the role order of all tactics, then the teams
; using each slot marked for a rebuild. Preserves all registers.
refresh_slots:
        movem.l d0-d7/a0-a6,-(sp)
        jsr     tactic_rebuild_order
        move.l  7*4(sp),d7              ; the mask (saved D7)
        move.w  tactic_editor_slot,-(sp)
        moveq   #0,d6
.slot:
        btst    d6,d7
        beq.s   .next
        move.w  d6,d0
        addi.w  #TACTIC_USER_FIRST,d0
        move.w  d0,tactic_editor_slot
        jsr     tactic_invalidate_teams
.next:
        addq.w  #1,d6
        cmpi.w  #USER_TACTIC_SLOTS,d6
        bcs.s   .slot
        move.w  (sp)+,tactic_editor_slot
        movem.l (sp)+,d0-d7/a0-a6
        rts

; slot_addresses: D0.w = user slot 0-5. A0 = its copy, A1 = the slot.
slot_addresses:
        move.l  d0,-(sp)
        mulu.w  #TACTIC_SIZE,d0
        lea     WORK_TACTICS+TT_COPIES(a5),a0
        adda.l  d0,a0
        lea     user_tactic_slots,a1
        adda.l  d0,a1
        move.l  (sp)+,d0
        rts

; copy_record: TACTIC_SIZE bytes from A0 to A1. Preserves all registers.
        if TACTIC_SIZE&1
        fail "copy_record copies words"
        endif
copy_record:
        movem.l d0/a0-a1,-(sp)
        move.w  #TACTIC_SIZE/2-1,d0
.copy:
        move.w  (a0)+,(a1)+
        dbf     d0,.copy
        movem.l (sp)+,d0/a0-a1
        rts

; check_and_record: A0 = record. tactic_check, its result kept for the
; messages. D0.l and the flags as tactic_check.
check_and_record:
        bsr.w   tactic_check
; record_check: D0.l = result, D1-D3 = details. Keeps them in TT_CHECK and
; TT_DETAIL; flags set from D0.
record_check:
        move.w  d0,WORK_TACTICS+TT_CHECK(a5)
        movem.l d1-d3,WORK_TACTICS+TT_DETAIL(a5)
        tst.l   d0
        rts

; problem_message: A0 = title, D0.w = message line for the problem of the
; last check. Starts a message (editors/message.s).
problem_message:
        movem.l d0-d3/a0-a1,-(sp)
        bsr.l   message_title
        lea     WORK_TACTICS+TT_LINE(a5),a1
        clr.b   (a1)
        moveq   #0,d0
        move.w  WORK_TACTICS+TT_CHECK(a5),d0
        movem.l WORK_TACTICS+TT_DETAIL(a5),d1-d3
        bsr.w   tactic_problem_text
        lea     WORK_TACTICS+TT_LINE(a5),a0
        move.w  2(sp),d0
        bsr.l   message_line
        movem.l (sp)+,d0-d3/a0-a1
        rts

; IMPORT: the count of the native copy loop, replaced by the runtime hook
; table at tactic_import_count (the same MOVE.W #count,D0).
tactic_import_count_patch:
        move.w  #TACTIC_BODY_SIZE-1,d0

title_refused:          dc.b    'TACTIC NOT ACCEPTED',0
title_damaged:          dc.b    'FILE DAMAGED',0
title_not_saved:        dc.b    'TACTIC NOT SAVED',0
refused_lines:          dc.b    'THE SLOT KEEPS ITS PREVIOUS TACTIC.',0
                        dc.b    'CHANGE IT, OR USE UNDO, IMPORT OR ABORT.',0
                        dc.b    0
line_not_loaded:        dc.b    'THE TACTIC WAS NOT LOADED.',0
line_not_written:       dc.b    'THE FILE WAS NOT WRITTEN.',0
text_size:              dc.b    'THE FILE HAS ',0
text_size_over:         dc.b    'OVER 65535',0
text_size_end:          dc.b    ' BYTES, A TACTIC HAS 370.',0
text_name:              dc.b    'THE NAME IS LONGER THAN 8 CHARACTERS.',0
text_player:            dc.b    'PLAYER ',0
text_players:           dc.b    'PLAYERS ',0
text_and:               dc.b    ' AND ',0
text_range:             dc.b    ' IS OFF THE PITCH IN BALL ZONE ',0
text_shared:            dc.b    ' SHARE A SPOT IN BALL ZONE ',0
text_stop:              dc.b    '.',0
text_label:             dc.b    ' HAS AN UNKNOWN MIRROR PAIR ',0
text_pair:              dc.b    'MIRROR PAIR ',0
text_pair_one:          dc.b    ' HAS ONLY ONE PLAYER.',0
text_pair_has:          dc.b    ' HAS ',0
text_pair_end:          dc.b    ' PLAYERS, NOT TWO.',0
text_base:              dc.b    'THE BASE FORMATION ',0
text_base_end:          dc.b    ' IS NOT A BUILTIN TACTIC.',0
        even
