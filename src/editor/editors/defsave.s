; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; SAVE DEFINITION on the DIY setup pages: the page's rules, checked as
; CHOOSE TEAMS checks them, with a file name of up to eight characters, the
; teams (chosen here with the game's own team chooser, or left to be chosen
; when the competition starts) and, after a question, the user's own tactic
; slots, written as NAME.DEF in the save directory and read back by the
; slave. An existing file is replaced only after a question, and a sound
; one is kept first as NAME.DEF.BAK (verified); when the new file then
; fails, the screen offers to restore it from there.
;
;   defsave_league, defsave_cup, defsave_tournament   the entry actions
;
; The screen: FILE NAME (Fire types), TEAMS (Fire runs the team chooser),
; NO TEAMS, SAVE and CANCEL (Esc). Choosing the teams leaves the screen for
; the chooser and opens it again afterwards, so the chooser runs at the
; same depth as from CHOOSE TEAMS. TEAMS and NO TEAMS change the teams held
; for the page only with a save: CANCEL (or leaving after a failed save)
; brings back the teams held when the screen opened.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    defsave_league, defsave_cup, defsave_tournament
        xdef    save_dialog, slot_list
        xref    editor_base, editor_image
        xref    screen_run
        xref    dialog_open, dialog_poll, dialog_set, dialog_draw
        xref    field_start, field_key
        xref    message_title, message_line, message_lines
        xref    message_open, message_poll, message_storage_reason
        xref    definition_capture_check, definition_check, definition_check_file
        xref    definition_problem_text
        xref    definition_refusal, definition_problem_lines
        xref    definition_capture_selection, definition_family_info, definition_custom_crc
        xref    rules_summary
        xref    tactics_owned
        xref    crc32_buffer
        xref    storage_size, storage_read, storage_write, storage_replace
        xref    text_copy, text_decimal, text_hex32, text_length
        xref    cancel_text

TOP                     equ 40
HEIGHT                  equ 176
ROW_X                   equ DIALOG_BAND_X+8
ROW_W                   equ DIALOG_BAND_WIDTH-16
SUMMARY_Y               equ TOP+16
NAME_Y                  equ TOP+32
TEAMS_Y                 equ NAME_Y+12
TACTICS_Y               equ TEAMS_Y+14
HINT_Y                  equ TACTICS_Y+14
STATUS_Y                equ HINT_Y+30
BUTTON_Y                equ TOP+HEIGHT-18
; Button codes and indices
CODE_CANCEL             equ 0
CODE_NAME               equ 1
CODE_TEAMS              equ 2
CODE_NO_TEAMS           equ 3
CODE_SAVE               equ 4
INDEX_NAME              equ 0
INDEX_TEAMS             equ 1
INDEX_NO_TEAMS          equ 2
; Lines of DF_LINES used here (rules_summary fills the first ones)
LINE_NAME               equ 16
LINE_TEAMS              equ 17
LINE_TACTICS            equ 18
; DF_RESULT
RESULT_DONE             equ 0
RESULT_CHOOSE           equ 1
; DF_STEP
STEP_NONE               equ 0
STEP_TACTICS            equ 1           ; question: include the tactics?
STEP_REPLACE            equ 2           ; question: replace the file?
STEP_SAVED              equ 3           ; message after a save: then close
STEP_RESTORE            equ 4           ; question: restore NAME.DEF from its backup?
; DF_ROW holds the answer to STEP_TACTICS here.

        section .text,code

defsave_league:
        moveq   #FAMILY_LEAGUE,d0
        bra.s   defsave_action
defsave_cup:
        moveq   #FAMILY_CUP,d0
        bra.s   defsave_action
defsave_tournament:
        moveq   #FAMILY_TOURNAMENT,d0
; defsave_action: D0.w = family (an entry action).
defsave_action:
        movea.l editor_base,a5
        move.w  d0,d7
        bsr.l   definition_capture_check
        beq.s   .rules_valid
        lea     title_not_saved(pc),a0
        bra.l   definition_refusal
.rules_valid:
        bsr.w   held_keep               ; for CANCEL
        tst.w   WORK_DEF+DF_TEAMS(a5)   ; teams held for another family are dropped
        beq.s   .loop
        cmp.w   WORK_DEF+DF_FAMILY(a5),d7
        beq.s   .loop
        clr.w   WORK_DEF+DF_TEAMS(a5)
.loop:
        move.w  #RESULT_DONE,WORK_DEF+DF_RESULT(a5)
        lea     save_screen(pc),a0
        bsr.l   screen_run
        cmpi.w  #RESULT_CHOOSE,WORK_DEF+DF_RESULT(a5)
        bne.s   .done
        bsr.w   choose_teams
        bra.s   .loop
.done:
        cmpi.w  #STEP_SAVED,WORK_DEF+DF_STEP(a5)
        beq.s   .saved
        bsr.w   held_restore            ; nothing saved: the teams held before
.saved:
        rts

; held_keep: the teams held for the page (family, count, participants)
; into DF_HELD_*. held_restore: back from there. A5 = editor base.
held_keep:
        lea     WORK_DEF+DF_FAMILY(a5),a0
        lea     WORK_DEF+DF_HELD_FAMILY(a5),a1
        move.l  (a0),(a1)+              ; DF_FAMILY and DF_TEAMS
        lea     WORK_DEF+DF_LIST(a5),a0
        bra.s   held_copy
held_restore:
        lea     WORK_DEF+DF_HELD_FAMILY(a5),a0
        lea     WORK_DEF+DF_FAMILY(a5),a1
        move.l  (a0)+,(a1)
        lea     WORK_DEF+DF_LIST(a5),a1
; held_copy: A0 = participants, copied to A1.
held_copy:
        move.w  #TEAM_SELECTION_MAX*DP_SIZE/4-1,d0
.copy:
        move.l  (a0)+,(a1)+
        dbf     d0,.copy
        rts

; choose_teams: D7.w = family. The game's team chooser for the page's team
; count; the teams chosen become the teams held for the definition.
choose_teams:
        move.w  d7,d0
        bsr.l   definition_family_info
        movea.l FI_SCRATCH(a0),a3
        lea     WORK_DEF+DF_CUSTOM(a5),a0
        moveq   #TEAM_SELECTION_MAX/4-1,d0
.clear:
        clr.l   (a0)+
        dbf     d0,.clear
        move.w  SS_TEAMS(a3),d0
        lea     SS_NAME(a3),a0
        lea     use_teams_label(pc),a1
        moveq   #1,d2
        moveq   #1,d3
        moveq   #1,d4
        move.l  d7,-(sp)
        jsr     team_chooser
        move.l  (sp)+,d7
        movea.l editor_base,a5
        tst.w   team_chooser_done
        beq.s   .kept
        move.w  d7,d0
        bra.l   definition_capture_selection
.kept:
        clr.w   team_selection_count
        rts

save_screen:
        dc.l    save_open
        dc.l    save_tick

; ---------------------------------------------------------------------------
; save_open: A5 = editor base.
; ---------------------------------------------------------------------------
save_open:
        lea     WORK_DEF(a5),a4
        move.w  #DFM_MAIN,DF_MODE(a4)
        move.w  #STEP_NONE,DF_STEP(a4)
        lea     DF_TITLE(a4),a1
        lea     title_text(pc),a0
        bsr.l   text_copy
        lea     DF_BODY+DR_NAME(a4),a0
        bsr.l   text_copy
        move.w  DF_BODY+DR_FAMILY(a4),d0
        bsr.l   rules_summary
        bsr.w   build_labels
        lea     hint_text(pc),a0
        bsr.w   set_status_text
        bra.w   show_save

; ---------------------------------------------------------------------------
; save_tick: A5 = editor base, D7.w = events, D6.w = key. D0.l <> 0 closes.
; ---------------------------------------------------------------------------
save_tick:
        lea     WORK_DEF(a5),a4
        move.w  DF_MODE(a4),d0
        cmpi.w  #DFM_TYPING,d0
        beq.w   typing
        cmpi.w  #DFM_MESSAGE,d0
        beq.w   message_open_tick
        cmpi.w  #DFM_ASK,d0
        beq.w   question_tick
        bsr.l   dialog_poll
        bmi.s   .stay
        cmpi.w  #CODE_NAME,d0
        beq.s   .name
        cmpi.w  #CODE_TEAMS,d0
        beq.s   .teams
        cmpi.w  #CODE_NO_TEAMS,d0
        beq.s   .no_teams
        cmpi.w  #CODE_SAVE,d0
        beq.w   save_chosen
        moveq   #1,d0                   ; CANCEL, Esc
        rts
.stay:
        moveq   #0,d0
        rts
.name:
        lea     DF_BASE(a4),a0
        moveq   #DEF_BASE_MAX,d0
        bsr.l   field_start
        move.w  #DFM_TYPING,DF_MODE(a4)
        bsr.w   build_labels
        bsr.w   repaint_name
        lea     typing_text(pc),a0
        bsr.w   set_status_text
        moveq   #0,d0
        rts
.teams:
        move.w  #RESULT_CHOOSE,DF_RESULT(a4)
        moveq   #1,d0
        rts
.no_teams:
        clr.w   DF_TEAMS(a4)
        bsr.w   build_labels
        moveq   #INDEX_TEAMS,d2
        moveq   #UI_NORMAL,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        moveq   #INDEX_NO_TEAMS,d2
        moveq   #UI_DISABLED,d3
        bsr.l   dialog_set
        moveq   #0,d0
        rts

; typing: the keyboard field takes the keys.
typing:
        bsr.l   field_key
        tst.l   d0
        bne.s   .end
        tst.l   d1
        beq.s   .stay
        bsr.w   build_labels
        bsr.w   repaint_name
.stay:
        moveq   #0,d0
        rts
.end:
        move.w  #DFM_MAIN,DF_MODE(a4)
        bsr.w   build_labels
        bsr.w   repaint_name
        lea     hint_text(pc),a0
        bsr.w   set_status_text
        moveq   #0,d0
        rts

; message_open_tick: a message is open; after it the screen returns, or
; closes after a successful save.
message_open_tick:
        bsr.l   message_poll
        bmi.s   tick_stay
        cmpi.w  #STEP_SAVED,DF_STEP(a4)
        bne.s   back_to_screen
        moveq   #1,d0
        rts

; question_tick: a YES/NO question of the save is open.
question_tick:
        bsr.l   message_poll
        bmi.s   tick_stay
        cmpi.w  #STEP_TACTICS,DF_STEP(a4)
        bne.s   .replace
        move.w  d0,DF_ROW(a4)           ; include the tactics
        bra.w   save_replace
.replace:
        cmpi.w  #STEP_RESTORE,DF_STEP(a4)
        beq.s   restore_answer
        tst.l   d0
        bne.w   save_write
; back_to_screen: the screen's own dialog again.
back_to_screen:
        move.w  #DFM_MAIN,DF_MODE(a4)
        move.w  #STEP_NONE,DF_STEP(a4)
        bsr.w   show_save
tick_stay:
        moveq   #0,d0
        rts

; restore_answer: D0.l = the answer to RESTORE: YES writes the previous
; file (still in the listing area) back as NAME.DEF.
restore_answer:
        tst.l   d0
        beq.s   back_to_screen
        lea     DF_FILE(a4),a0
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  DF_PREVIOUS(a4),d1
        bsr.l   storage_write           ; read back by the slave
        move.l  d0,d2
        lea     title_not_saved(pc),a0
        bsr.l   message_title
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        lea     text_restored(pc),a0
        tst.l   d2
        beq.s   .restored
        lea     text_restore_failed(pc),a0
.restored:
        bsr.l   text_copy
        lea     DF_BACKUP(a4),a0
        bsr.l   text_copy
        lea     text_stop(pc),a0
        tst.l   d2
        beq.s   .line
        lea     text_unchanged(pc),a0
.line:
        bsr.l   text_copy
        lea     DF_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     line_rules_stay(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        lea     hint_text(pc),a0        ; the screen's status line again
        lea     DF_STATUS(a4),a1
        bsr.l   text_copy
        move.w  #STEP_NONE,DF_STEP(a4)
        bra.w   open_message

; ---------------------------------------------------------------------------
; SAVE: the name, the teams, then the questions and the write.
; ---------------------------------------------------------------------------
save_chosen:
        lea     DF_BASE(a4),a0          ; 1-8 of A-Z, 0-9 and -
        bsr.l   text_length
        tst.w   d0
        beq.w   .bad_name
        move.w  d0,d1
        subq.w  #1,d1
.char:
        move.b  (a0)+,d0
        cmpi.b  #'-',d0
        beq.s   .next
        cmpi.b  #'0',d0
        bcs.w   .bad_name
        cmpi.b  #'9',d0
        bls.s   .next
        cmpi.b  #'A',d0
        bcs.w   .bad_name
        cmpi.b  #'Z',d0
        bhi.w   .bad_name
.next:
        dbf     d1,.char
        lea     DF_FILE(a4),a1
        lea     DF_BASE(a4),a0
        bsr.l   text_copy
        lea     suffix_text(pc),a0
        bsr.l   text_copy
        lea     DF_BACKUP(a4),a1        ; NAME.DEF.BAK
        lea     DF_FILE(a4),a0
        bsr.l   text_copy
        lea     backup_suffix(pc),a0
        bsr.l   text_copy
        move.w  DF_TEAMS(a4),d0
        beq.s   .tactics
        cmp.w   DF_BODY+DR_TEAMS(a4),d0
        beq.s   .tactics
        lea     title_not_saved(pc),a0
        bsr.l   message_title
        lea     DF_STATUS(a4),a1
        moveq   #DC_TEAM_COUNT,d0
        moveq   #0,d1
        move.w  DF_TEAMS(a4),d1
        moveq   #0,d2
        move.w  DF_BODY+DR_TEAMS(a4),d2
        bsr.l   definition_problem_text
        lea     DF_STATUS(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_choose_again(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        bra.w   open_message
.bad_name:
        lea     title_not_saved(pc),a0
        bsr.l   message_title
        lea     line_name_rule(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.tactics:
        clr.w   DF_ROW(a4)
        bsr.l   tactics_owned       ; flags set from D0
        beq.s   save_replace
        lea     title_tactics(pc),a0
        bsr.l   message_title
        lea     DF_STATUS(a4),a1
        lea     text_your_tactics(pc),a0
        bsr.l   text_copy
        bsr.w   slot_list
        lea     text_stop(pc),a0
        bsr.l   text_copy
        lea     DF_STATUS(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     tactics_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        move.w  #STEP_TACTICS,DF_STEP(a4)
        bra.w   open_question

; save_replace: an existing file is replaced only after a question.
save_replace:
        lea     DF_FILE(a4),a0
        bsr.l   storage_size
        bne.w   save_write
        lea     title_replace(pc),a0
        bsr.l   message_title
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_exists(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     line_replace(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        move.w  #STEP_REPLACE,DF_STEP(a4)
        bra.w   open_question

; save_write: builds the file in the I/O buffer and writes it.
save_write:
        lea     WORK_IO_BUFFER(a5),a3
        lea     DEF_HEADER_SIZE(a3),a2  ; body
        lea     DF_BODY(a4),a0
        movea.l a2,a1
        move.w  #DEF_BODY_FIXED/2-1,d0
.fixed:
        move.w  (a0)+,(a1)+
        dbf     d0,.fixed
        movea.l a1,a0                   ; the custom set as known now: the
        movea.l a2,a1                   ; chooser may have read it since
        bsr.l   definition_custom_crc
        movea.l a0,a1
        moveq   #0,d0
        move.w  DF_TEAMS(a4),d0
        move.w  d0,DR_TEAM_COUNT(a2)
        mulu.w  #DP_SIZE/2,d0
        lea     DF_LIST(a4),a0
        bra.s   .list_test
.list:
        move.w  (a0)+,(a1)+
.list_test:
        dbf     d0,.list
        moveq   #0,d4                   ; mask
        tst.w   DF_ROW(a4)
        beq.s   .mask
        bsr.l   tactics_owned
        move.w  d0,d4
.mask:
        move.w  d4,DR_TACTIC_MASK(a2)
        moveq   #0,d5
.slot:
        btst    d5,d4
        beq.s   .next_slot
        move.w  d5,d0
        mulu.w  #TACTIC_SIZE,d0
        lea     user_tactic_slots,a0
        adda.l  d0,a0
        move.w  #TACTIC_SIZE/2-1,d0
.copy:
        move.w  (a0)+,(a1)+
        dbf     d0,.copy
.next_slot:
        addq.w  #1,d5
        cmpi.w  #USER_TACTIC_SLOTS,d5
        bcs.s   .slot
        move.l  a1,d6
        sub.l   a2,d6                   ; body length
        movea.l a2,a0
        move.l  d6,d0
        bsr.l   definition_check
        bne.w   .invalid
        move.l  #DEF_MAGIC_HIGH,DH_MAGIC(a3)
        move.l  #DEF_MAGIC_LOW,DH_MAGIC+4(a3)
        move.w  #DEF_VERSION,DH_VERSION(a3)
        move.w  d6,DH_LENGTH(a3)
        movea.l a2,a0
        move.l  d6,d1
        bsr.l   crc32_buffer
        move.l  d0,DH_CRC32(a3)
        move.l  d0,DF_SAVED_CRC(a4)
        move.l  d6,d5
        addi.l  #DEF_HEADER_SIZE,d5     ; the file's length
        bsr.w   previous_length         ; D6 = a sound previous file's, or -1
        lea     DF_FILE(a4),a0
        movea.l a3,a1
        move.l  d5,d1
        movem.l a3-a4,-(sp)
        lea     DF_BACKUP(a4),a3
        lea     LIST_WORK_OFFSET(a5),a4 ; the previous file, for the restore
        move.l  #DEF_FILE_MAX,d3
        bsr.l   storage_replace         ; D1 = the backed-up length on a failure
        movem.l (sp)+,a3-a4             ; the flags stay
        bne.w   .failed
        lea     title_saved(pc),a0
        bsr.l   message_title
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        lea     text_crc(pc),a0
        bsr.l   text_copy
        move.l  DF_SAVED_CRC(a4),d0
        bsr.l   text_hex32
        lea     DF_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        lea     text_teams(pc),a0
        bsr.l   text_copy
        bsr.w   teams_text
        lea     DF_STATUS(a4),a0
        moveq   #2,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        lea     text_tactics(pc),a0
        bsr.l   text_copy
        move.w  d4,d0
        bne.s   .slots
        lea     text_none(pc),a0
        bsr.l   text_copy
        bra.s   .tactics_line
.slots:
        bsr.w   slot_list
.tactics_line:
        lea     DF_STATUS(a4),a0
        moveq   #3,d0
        bsr.l   message_line
        move.w  #STEP_SAVED,DF_STEP(a4)
        bra.w   open_message
.failed:
        move.l  d1,DF_PREVIOUS(a4)      ; 0: no backup written
        lea     title_not_saved(pc),a0
        bsr.l   message_title
        moveq   #1,d1                   ; a write
        bsr.l   message_storage_reason
        moveq   #1,d0
        bsr.l   message_line
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        tst.l   DF_PREVIOUS(a4)
        bne.s   .offer_restore
        lea     line_rules_stay(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bra.s   open_message
.offer_restore:
        lea     DF_STATUS(a4),a1
        lea     text_safe_in(pc),a0
        bsr.l   text_copy
        lea     DF_BACKUP(a4),a0
        bsr.l   text_copy
        lea     text_stop(pc),a0
        bsr.l   text_copy
        lea     DF_STATUS(a4),a0
        moveq   #2,d0
        bsr.l   message_line
        lea     line_restore(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        lea     hint_text(pc),a0        ; the screen's status line again
        lea     DF_STATUS(a4),a1
        bsr.l   text_copy
        move.w  #STEP_RESTORE,DF_STEP(a4)
        bra.s   open_question
.invalid:
        lea     title_not_saved(pc),a0
        bsr.l   message_title
        moveq   #0,d4
        bsr.l   definition_problem_lines
; open_message: the message in place of the screen's dialog. D0.l = 0.
open_message:
        move.w  #DFM_MESSAGE,DF_MODE(a4)
        moveq   #MSG_OK,d0
        bra.l   message_open

; open_question: a YES/NO question in place of the screen's dialog.
open_question:
        move.w  #DFM_ASK,DF_MODE(a4)
        moveq   #MSG_ASK,d0
        bra.l   message_open

; previous_length: D6.l = the length of DF_FILE when it is a sound
; definition, which is then kept as the backup; else -1 (none, or one that
; LOAD DEFINITION refuses: the backup keeps what it holds).
previous_length:
        movem.l d0-d3/a0-a1,-(sp)
        lea     DF_FILE(a4),a0
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  #DEF_FILE_MAX,d1
        bsr.l   storage_read            ; D1 = length
        bne.s   .none                   ; missing, unreadable or too long
        move.l  d1,d6
        movea.l a1,a0
        move.l  d1,d0
        bsr.l   definition_check_file   ; keeps D6
        beq.s   .done
.none:
        moveq   #-1,d6
.done:
        movem.l (sp)+,d0-d3/a0-a1
        rts

; ---------------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------------
show_save:
        lea     save_dialog(pc),a0
        moveq   #0,d2
        tst.w   DF_TEAMS(a4)
        bne.s   .open
        moveq   #1<<INDEX_NO_TEAMS,d2
.open:
        bsr.l   dialog_open
        lea     status_commands(pc),a0
        bra.l   dialog_draw

repaint_name:
        moveq   #INDEX_NAME,d2
        moveq   #UI_NORMAL,d3
        cmpi.w  #DFM_TYPING,DF_MODE(a4)
        bne.s   .set
        moveq   #UI_ACTIVE,d3
.set:
        suba.l  a0,a0
        bra.l   dialog_set

; set_status_text: A0 = text of the status line, drawn now.
set_status_text:
        lea     DF_STATUS(a4),a1
        bsr.l   text_copy
        lea     status_commands(pc),a0
        bra.l   dialog_draw

; build_labels: the rows FILE NAME and TEAMS and the tactics line.
build_labels:
        movem.l d0-d1/a0-a1,-(sp)
        lea     DF_LINES+LINE_NAME*DF_LINE_SIZE(a4),a1
        lea     name_label(pc),a0
        bsr.l   text_copy
        lea     DF_BASE(a4),a0
        bsr.l   text_copy
        cmpi.w  #DFM_TYPING,DF_MODE(a4)
        bne.s   .suffix
        move.b  #'_',(a1)+
        clr.b   (a1)
        bra.s   .teams
.suffix:
        lea     suffix_text(pc),a0
        bsr.l   text_copy
.teams:
        lea     DF_LINES+LINE_TEAMS*DF_LINE_SIZE(a4),a1
        lea     teams_label(pc),a0
        bsr.l   text_copy
        bsr.s   teams_text
        lea     DF_LINES+LINE_TACTICS*DF_LINE_SIZE(a4),a1
        lea     tactics_label(pc),a0
        bsr.l   text_copy
        bsr.l   tactics_owned           ; flags set from D0
        bne.s   .owned
        lea     text_no_own(pc),a0
        bsr.l   text_copy
        bra.s   .done
.owned:
        bsr.s   slot_list
.done:
        movem.l (sp)+,d0-d1/a0-a1
        rts

; teams_text: how many teams the definition holds, appended at A1.
; Changes D0/A0.
teams_text:
        lea     text_on_start(pc),a0
        move.w  DF_TEAMS(a4),d0
        beq.s   .copy
        bsr.l   text_decimal
        lea     text_chosen(pc),a0
.copy:
        bra.l   text_copy

; slot_list: D0.w = mask of user slots, appended at A1 as "USER A, C, F".
; Preserves all registers except A1.
slot_list:
        movem.l d0-d2/a0,-(sp)
        move.w  d0,d2
        lea     user_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d1
        moveq   #0,d0                   ; letters written
.slot:
        btst    d1,d2
        beq.s   .next
        tst.w   d0
        beq.s   .letter
        lea     comma_text(pc),a0
        bsr.l   text_copy
.letter:
        move.b  d1,(a1)                 ; USER A + the slot
        addi.b  #'A',(a1)+
        clr.b   (a1)
        addq.w  #1,d0
.next:
        addq.w  #1,d1
        cmpi.w  #USER_TACTIC_SLOTS,d1
        bcs.s   .slot
        movem.l (sp)+,d0-d2/a0
        rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
LABEL_AT macro
        dc.l    editor_image+WORK_DEF+DF_LINES+(\1)*DF_LINE_SIZE
        endm

save_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_DEF+DF_TITLE
        dc.l    save_body
        dc.w    INDEX_NAME,CODE_CANCEL,5
        dc.w    ROW_X,NAME_Y,ROW_W,9,CODE_NAME,DIALOG_ROW|UI_NORMAL
        LABEL_AT LINE_NAME
        dc.w    ROW_X,TEAMS_Y,ROW_W,9,CODE_TEAMS,DIALOG_ROW|UI_NORMAL
        LABEL_AT LINE_TEAMS
        dc.w    ROW_X,BUTTON_Y,96,13,CODE_NO_TEAMS,UI_NORMAL
        dc.l    no_teams_text
        dc.w    ROW_X+136,BUTTON_Y,72,13,CODE_SAVE,UI_NORMAL
        dc.l    save_text
        dc.w    ROW_X+216,BUTTON_Y,88,13,CODE_CANCEL,UI_NORMAL
        dc.l    cancel_text

save_body:
        dc.w    UI_TEXT_AT,ROW_X,SUMMARY_Y,ROW_W,UI_ACCENT,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_LINES
        dc.w    UI_TEXT_AT,ROW_X,TACTICS_Y,ROW_W,UI_INK,UI_LEFT_CLIPPED
        LABEL_AT LINE_TACTICS
        dc.w    UI_TEXT,ROW_X,HINT_Y,ROW_W,UI_DIM,UI_LEFT
        dc.b    'FIRE ON FILE NAME TYPES IT, ON TEAMS CHOOSES THEM.',0
        even
        dc.w    UI_TEXT,ROW_X,HINT_Y+10,ROW_W,UI_DIM,UI_LEFT
        dc.b    'WITHOUT TEAMS THEY ARE CHOSEN AT THE START.',0
        even
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,ROW_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,ROW_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_STATUS
        dc.w    UI_END

title_text:             dc.b    'SAVE DEFINITION: ',0
title_not_saved:        dc.b    'DEFINITION NOT SAVED',0
title_saved:            dc.b    'DEFINITION SAVED',0
title_tactics:          dc.b    'INCLUDE YOUR TACTICS?',0
title_replace:          dc.b    'REPLACE THE DEFINITION?',0
line_choose_again:      dc.b    'CHOOSE THE TEAMS AGAIN OR USE NO TEAMS.',0
line_name_rule:         dc.b    'USE 1-8 LETTERS, DIGITS OR - FOR THE NAME.',0
tactics_lines:          dc.b    'YES SAVES THEM WITH THE DEFINITION,',0
                        dc.b    'NO SAVES THE DEFINITION WITHOUT TACTICS.',0
                        dc.b    0
line_exists:            dc.b    'IS ALREADY IN THE SAVE DIRECTORY.',0
line_replace:           dc.b    'REPLACE IT?',0
line_rules_stay:        dc.b    'THE RULES STAY ON THE PAGE.',0
line_restore:           dc.b    'RESTORE THE DEFINITION FROM IT NOW?',0
text_safe_in:           dc.b    'THE PREVIOUS ONE IS SAFE IN ',0
text_restored:          dc.b    'RESTORED FROM ',0
text_restore_failed:    dc.b    'RESTORE FAILED. ',0
text_unchanged:         dc.b    ' IS UNCHANGED.',0
backup_suffix:          dc.b    '.BAK',0
text_your_tactics:      dc.b    'YOUR OWN TACTICS: ',0
text_stop:              dc.b    '.',0
text_crc:               dc.b    'CRC-32 ',0
text_teams:             dc.b    'TEAMS: ',0
text_chosen:            dc.b    ' CHOSEN',0
text_on_start:          dc.b    'CHOSEN AT THE START',0
text_tactics:           dc.b    'TACTICS: ',0
text_none:              dc.b    'NONE',0
text_no_own:            dc.b    'NO TACTIC OF YOUR OWN',0
user_text:              dc.b    'USER ',0
comma_text:             dc.b    ', ',0
suffix_text:            dc.b    '.DEF',0
name_label:             dc.b    'FILE NAME    ',0
teams_label:            dc.b    'TEAMS        ',0
tactics_label:          dc.b    'TACTICS      ',0
hint_text:              dc.b    'SAVE WRITES THE DEFINITION TO THE SAVE DIRECTORY.',0
typing_text:            dc.b    'TYPE THE NAME: RETURN KEEPS IT, ESC UNDOES IT.',0
use_teams_label:        dc.b    'USE THESE TEAMS',0
no_teams_text:          dc.b    'NO _TEAMS',0
save_text:              dc.b    '_SAVE',0
        even
