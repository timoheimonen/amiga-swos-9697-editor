; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; EDIT DATABASE (main-menu entry): edited real clubs and players for new
; seasons, careers and competitions.
;
; database_action passes the game's abandon gate (after the note of
; editors/boundary.s that a started competition's teams cannot be edited),
; so no competition exists while the database is edited or the switch
; changes, and then runs the screens one after another, each as a modal
; child of the main menu:
;
;   the database screen   the country groups (the 65 club groups, then the
;                         national groups 80-85), the set in the save
;                         directory, EUROPEAN CUPS, SET LABEL, SAVE, REMOVE
;                         OLD VERSIONS, USE EDITED DATABASE: ON/OFF (kept
;                         across restarts in DBASE.USE) and EXIT
;   the cups screen       the participants of the European club cups in the
;                         saved set, read only (editors/dbcups.s)
;   the group screen      the clubs of the group being edited and their
;                         actions (editors/dbgroup.s)
;   the team page         the game's own team page of EDIT CUSTOM TEAMS with
;                         its EDIT actions, TEAM SETTINGS and the player
;                         screen, on one club of the working group
;
; One group at a time is edited, in the group work area of the expansion
; memory (the working group); SAVE writes it as a new generation and the
; set as a new DBASE.CFG (editors/dbstore.s). Choosing another group, or
; leaving, with unsaved changes asks first. A copy to another country
; chooses its destination group on this screen (PICK_COPY_COUNTRY).
;
; Controls: joystick or cursor keys move the focus, Fire or Return chooses,
; Esc leaves (or ends a copy). The label is typed in a keyboard field.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    database_action, database_dialog, database_menu_init
        xref    editor_base, editor_image
        xref    screen_run
        xref    dialog_open, dialog_poll, dialog_set, dialog_draw
        xref    field_start, field_key
        xref    message_title, message_line, message_lines, message_open, message_poll
        xref    message_storage_reason
        xref    text_copy, text_copy_max, text_decimal
        xref    group_screen, cups_screen
        xref    db_read_set, db_restore_backup, db_backup_usable, db_problem_text
        xref    db_find_entry, db_group_list, db_group_name, db_label_crc
        xref    db_switch_on, db_switch_off, db_switch_store, db_load_group, db_save, db_old_versions
        xref    db_start_check, db_problem_name
        xref    matchlog_start
        xref    boundary_gate
        xref    previous_text, next_text

GROUP_ROWS              equ DB_ROW_COUNT ; 2 columns of 12
COLUMN_ROWS             equ 12
TOP                     equ 8
HEIGHT                  equ 256
INFO_Y                  equ TOP+15
INFO2_Y                 equ INFO_Y+10
HEAD_Y                  equ INFO2_Y+12
ROW_Y                   equ HEAD_Y+10
ROW_X                   equ DIALOG_BAND_X+8
ROW_W                   equ 148
ROW_X2                  equ ROW_X+ROW_W+8
ROW_H                   equ 9
PAGE_Y                  equ ROW_Y+COLUMN_ROWS*10+2
LABEL_Y                 equ PAGE_Y+17
SAVE_Y                  equ LABEL_Y+17
SWITCH_Y                equ SAVE_Y+17
STATUS_Y                equ SWITCH_Y+16
CREDIT_Y                equ STATUS_Y+10    ; the version and author line
BUTTON_H                equ 13
FIELD_X                 equ ROW_X+104
FIELD_W                 equ ROW_X+ROW_W*2+8-FIELD_X
; Button codes and indices
CODE_EXIT               equ 0
CODE_PREVIOUS           equ 1
CODE_NEXT               equ 2
CODE_LABEL              equ 3
CODE_SAVE               equ 4
CODE_REMOVE             equ 5
CODE_SWITCH             equ 6
CODE_CUPS               equ 7
CODE_ROW                equ 100
INDEX_PREVIOUS          equ GROUP_ROWS
INDEX_NEXT              equ GROUP_ROWS+1
INDEX_LABEL             equ GROUP_ROWS+2
INDEX_SAVE              equ GROUP_ROWS+3
INDEX_REMOVE            equ GROUP_ROWS+4
INDEX_SWITCH            equ GROUP_ROWS+5
INDEX_EXIT              equ GROUP_ROWS+6
INDEX_CUPS              equ GROUP_ROWS+7
; DB_STEP of the questions and messages
STEP_NONE               equ 0
STEP_RECOVER            equ 1           ; question: restore DBASE.CFG from DBASE.BAK
STEP_DISCARD_OPEN       equ 2           ; question: discard, then open DB_SECOND
STEP_DISCARD_EXIT       equ 3           ; question: leave without saving
STEP_REMOVE             equ 4           ; question: remove the old versions
STEP_RESTORE            equ 5           ; question after a failed DBASE.CFG
STEP_CHECK              equ 6           ; on entry: offer the recovery

        section .text,code

; ===========================================================================
; The main menu
; ===========================================================================
; database_menu_init: init callback of the main menu's copy. The first time
; the main menu is built, the match log learns the install and its next
; sequence number (matchlog_start) and a remembered USE EDITED DATABASE: ON
; is checked (db_start_check), so the set is in use from the start or the
; caption says why not; then the native init.
database_menu_init:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        bsr.l   matchlog_start
        bsr.l   db_start_check
        movem.l (sp)+,d0-d7/a0-a6
        jmp     main_menu_init

; ===========================================================================
; The frontend (main-menu entry action)
; ===========================================================================
database_action:
        lea     title_text(pc),a0
        bsr.l   boundary_gate           ; its prompt changes the registers
        bne.w   .done
        movea.l editor_base,a5
        lea     WORK_DB(a5),a4
        move.w  #-1,DB_GROUP(a4)
        clr.w   DB_DIRTY(a4)
        clr.w   DB_PICK(a4)
        clr.w   DB_PAGE(a4)
        clr.w   DB_CLUB_PAGE(a4)
        move.w  #-1,DB_CLUB(a4)
        move.w  #STEP_CHECK,DB_STEP(a4)
        bsr.l   db_read_set
        bsr.w   label_from_set
        move.w  #DBS_MAIN,DB_NEXT(a4)
.loop:
        lea     WORK_DB(a5),a4
        move.w  DB_NEXT(a4),d0
        move.w  d0,DB_SCREEN(a4)
        cmpi.w  #DBS_MAIN,d0
        beq.s   .main
        cmpi.w  #DBS_TEAM,d0
        beq.s   .team
        lea     group_screen,a0
        cmpi.w  #DBS_GROUP,d0
        beq.s   .back
        lea     cups_screen,a0
        cmpi.w  #DBS_CUPS,d0
        bne.s   .leave
.back:                                  ; the group and cups screens return here
        move.w  #DBS_MAIN,DB_NEXT(a4)
.run:
        bsr.l   screen_run
        bra.s   .loop
.main:
        move.w  #DBS_EXIT,DB_NEXT(a4)
        lea     database_screen(pc),a0
        bra.s   .run
.team:
        bsr.w   run_team_page
        move.w  #DBS_GROUP,WORK_DB+DB_NEXT(a5)
        bra.s   .loop
.leave:
        move.w  #-1,DB_GROUP(a4)
        clr.w   DB_DIRTY(a4)
        move.w  #DBS_EXIT,DB_SCREEN(a4)
        clr.w   team_group_cache_valid
.done:
        rts

; run_team_page: the native team page (the copy with the editor's entries)
; on club DB_CLUB of the working group. Its OK commits the club into the
; working group, as the custom-team editor commits into the custom set.
run_team_page:
        lea     WORK_DB(a5),a4
        move.w  DB_CLUB(a4),d0
        bmi.s   .done
        mulu.w  #TEAM_SIZE,d0
        lea     GROUP_WORK_OFFSET+GROUP_COUNT_SIZE(a5),a0
        adda.l  d0,a0
        move.l  a0,custom_team_original_pointer
        move.w  custom_teams_dirty,-(sp)
        clr.w   custom_teams_dirty
        clr.w   custom_team_imported
        lea     WORK_TEAM_EDITOR(a5),a6
        jsr     menu_run_modal
        movea.l editor_base,a5
        tst.w   custom_teams_dirty
        beq.s   .unchanged
        move.w  #1,WORK_DB+DB_DIRTY(a5)
.unchanged:
        move.w  (sp)+,custom_teams_dirty
.done:
        rts

; label_from_set: DB_LABEL becomes the label of the set on the disk (empty
; without one). A4 = WORK_DB.
label_from_set:
        movem.l d0/a0-a1,-(sp)
        lea     DB_LABEL(a4),a1
        clr.b   (a1)
        clr.w   DB_LABEL_CHANGED(a4)
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4)
        bne.s   .done
        lea     DB_SET+MF_LABEL(a4),a0
        moveq   #SET_LABEL_SIZE,d0
        bsr.l   text_copy_max
.done:
        movem.l (sp)+,d0/a0-a1
        rts

; ===========================================================================
; The database screen
; ===========================================================================
database_screen:
        dc.l    database_open
        dc.l    database_tick

; database_open: A5 = editor base.
database_open:
        lea     WORK_DB(a5),a4
        cmpi.w  #STEP_CHECK,DB_STEP(a4)
        bne.w   show_database
        move.w  #STEP_NONE,DB_STEP(a4)
        ; once on entry: a damaged or missing DBASE.CFG with a sound
        ; DBASE.BAK (an interrupted save) offers the recovery
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4)
        beq.w   start_note
        bsr.l   db_backup_usable
        bne.w   start_note
        lea     recover_title(pc),a0
        bsr.l   message_title
        lea     missing_cfg_text(pc),a0
        moveq   #1,d2                   ; the first line of recover_lines
        cmpi.w  #DSS_NONE,DB_SET_STATE(a4)
        beq.s   .reason
        lea     damaged_cfg_text(pc),a0 ; the problem on a line of its own
        moveq   #0,d0
        bsr.l   message_line
        lea     DB_STATUS(a4),a1
        moveq   #0,d0
        move.w  DB_SET_PROBLEM(a4),d0
        moveq   #0,d1
        move.w  DB_SET_DETAIL(a4),d1
        bsr.l   db_problem_text
        lea     DB_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        moveq   #2,d2
        bra.s   .lines
.reason:
        moveq   #0,d0
        bsr.l   message_line
.lines:
        lea     recover_lines(pc),a0
        move.w  d2,d0
        bsr.l   message_lines
        move.w  #STEP_RECOVER,DB_STEP(a4)
        bra.w   open_question

; start_note: once after a failed start check, on entry: the remembered
; switch could not be turned on, and why.
start_note:
        tst.w   DB_START_PROBLEM(a4)
        beq.w   show_database
        tst.w   DB_START_NOTED(a4)
        bne.w   show_database
        move.w  #1,DB_START_NOTED(a4)
        lea     not_found_title(pc),a0
        bsr.l   message_title
        lea     start_line0(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     DB_STATUS(a4),a1
        clr.b   (a1)
        bsr.l   db_problem_name
        moveq   #1,d0
        bsr.w   status_line
        lea     start_line2(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        bra.w   open_message

; database_tick: A5 = editor base, D7.w = events, D6.w = key. D0.l <> 0
; closes the screen (DB_NEXT says what follows).
database_tick:
        lea     WORK_DB(a5),a4
        move.w  DB_MODE(a4),d0
        cmpi.w  #DBM_TYPING,d0
        beq.w   typing
        cmpi.w  #DBM_MESSAGE,d0
        beq.w   message_tick
        cmpi.w  #DBM_ASK,d0
        beq.w   question_tick
        bsr.l   dialog_poll
        bmi.s   .stay
        cmpi.w  #CODE_ROW,d0
        bcc.w   group_chosen
        cmpi.w  #CODE_PREVIOUS,d0
        beq.s   .previous
        cmpi.w  #CODE_NEXT,d0
        beq.s   .next
        cmpi.w  #CODE_LABEL,d0
        beq.w   label_chosen
        cmpi.w  #CODE_SAVE,d0
        beq.w   save_chosen
        cmpi.w  #CODE_REMOVE,d0
        beq.w   remove_chosen
        cmpi.w  #CODE_SWITCH,d0
        beq.w   switch_chosen
        cmpi.w  #CODE_CUPS,d0
        beq.s   .cups
        bra.w   exit_chosen             ; EXIT, Esc
.stay:
        moveq   #0,d0
        rts
.previous:
        subi.w  #GROUP_ROWS,DB_PAGE(a4)
        bpl.s   .page
        clr.w   DB_PAGE(a4)
.page:
        bra.w   show_database
.next:
        addi.w  #GROUP_ROWS,DB_PAGE(a4)
        bra.w   show_database
.cups:
        move.w  #DBS_CUPS,DB_NEXT(a4)
        moveq   #1,d0
        rts

; ---------------------------------------------------------------------------
; Showing the screen
; ---------------------------------------------------------------------------
; show_database: draws the whole screen in its state. D0.l = 0.
show_database:
        lea     WORK_DB(a5),a4
        move.w  #DBM_MAIN,DB_MODE(a4)
        bsr.w   build_texts
        lea     database_dialog(pc),a0
        bsr.w   disabled_mask           ; D2
        bsr.l   dialog_open
        lea     switch_on_label(pc),a0
        tst.w   DB_SWITCH(a4)
        bne.s   .switch
        lea     switch_off_label(pc),a0
.switch:
        moveq   #UI_NORMAL,d3
        btst    #INDEX_SWITCH,d2
        beq.s   .switch_state
        moveq   #UI_DISABLED,d3
.switch_state:
        moveq   #INDEX_SWITCH,d2
        bsr.l   dialog_set
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .exit_label
        lea     end_copy_label(pc),a0
        moveq   #INDEX_EXIT,d2
        moveq   #UI_NORMAL,d3
        bsr.l   dialog_set
.exit_label:
        bsr.w   draw_field
        ; the status line for the screen's state
        lea     DB_STATUS(a4),a1
        clr.b   (a1)
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .open_group
        lea     copy_country_text(pc),a0
        bsr.l   text_copy
        lea     DB_COPY_RECORD+TEAM_NAME(a4),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        bra.s   .draw
.open_group:
        move.w  DB_GROUP(a4),d0
        bmi.s   .choose
        tst.w   DB_DIRTY(a4)
        beq.s   .choose
        lea     changed_prefix(pc),a0
        bsr.l   text_copy
        bsr.l   db_group_name
        lea     changed_suffix(pc),a0
        bsr.l   text_copy
        bra.s   .draw
.choose:
        lea     choose_text(pc),a0
        bsr.l   text_copy
.draw:
        lea     status_commands(pc),a0
        bsr.l   dialog_draw
        moveq   #0,d0
        rts

; disabled_mask: D2.l = the buttons that cannot be chosen now. A4 = WORK_DB.
disabled_mask:
        movem.l d0-d1/d3/a0,-(sp)
        moveq   #0,d2
        moveq   #GROUP_ROWS-1,d1
.rows:
        move.w  DB_PAGE(a4),d0
        add.w   d1,d0
        cmpi.w  #DATABASE_GROUP_COUNT,d0
        bcc.s   .off
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .on
        bsr.l   db_group_list
        cmpi.b  #NATIONAL_FIRST,(a0,d0.w) ; a copy goes into a club group
        bcs.s   .on
.off:
        bset    d1,d2
.on:
        dbf     d1,.rows
        tst.w   DB_PAGE(a4)
        bne.s   .previous
        bset    #INDEX_PREVIOUS,d2
.previous:
        move.w  DB_PAGE(a4),d0
        addi.w  #GROUP_ROWS,d0
        cmpi.w  #DATABASE_GROUP_COUNT,d0
        bcs.s   .next
        bset    #INDEX_NEXT,d2
.next:
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .save
        bset    #INDEX_LABEL,d2
        bset    #INDEX_SAVE,d2
        bset    #INDEX_REMOVE,d2
        bset    #INDEX_SWITCH,d2
        bset    #INDEX_CUPS,d2
        bra.s   .done
.save:
        tst.w   DB_DIRTY(a4)
        bne.s   .switch
        tst.w   DB_LABEL_CHANGED(a4)
        bne.s   .switch
        bset    #INDEX_SAVE,d2
.switch:
        tst.w   DB_SWITCH(a4)
        bne.s   .done
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4)
        beq.s   .done
        bset    #INDEX_SWITCH,d2
.done:
        movem.l (sp)+,d0-d1/d3/a0
        rts

; build_texts: the row labels and the two information lines. A4 = WORK_DB.
build_texts:
        movem.l d0-d7/a0-a3,-(sp)
        moveq   #0,d6                   ; row
.row:
        move.w  d6,d0
        mulu.w  #DB_ROW_SIZE,d0
        lea     DB_ROWS(a4,d0.l),a1
        clr.b   (a1)
        move.w  DB_PAGE(a4),d7
        add.w   d6,d7
        cmpi.w  #DATABASE_GROUP_COUNT,d7
        bcc.s   .next
        bsr.l   db_group_list
        moveq   #0,d0
        move.b  (a0,d7.w),d0
        bsr.l   db_group_name
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4)
        bne.s   .changed
        lea     DB_SET(a4),a0
        movea.l a4,a3
        bsr.l   db_find_entry           ; A4 = entry
        movea.l a3,a4
        beq.s   .changed
        move.b  #' ',(a1)+
        move.b  #'*',(a1)+
        clr.b   (a1)
.changed:
        cmp.w   DB_GROUP(a4),d0
        bne.s   .next
        tst.w   DB_DIRTY(a4)
        beq.s   .next
        move.b  #' ',(a1)+
        move.b  #'+',(a1)+
        clr.b   (a1)
.next:
        addq.w  #1,d6
        cmpi.w  #GROUP_ROWS,d6
        bcs.s   .row
        ; the set in the save directory
        lea     DB_INFO(a4),a1
        move.w  DB_SET_STATE(a4),d0
        lea     no_set_text(pc),a0
        cmpi.w  #DSS_VALID,d0
        beq.s   .valid
        cmpi.w  #DSS_DAMAGED,d0
        bne.s   .info
        lea     damaged_set_text(pc),a0
.info:
        bsr.l   text_copy
        bra.s   .use
.valid:
        lea     set_text(pc),a0
        bsr.l   text_copy
        lea     DB_SET(a4),a0
        bsr.l   db_label_crc
        lea     comma_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0                   ; the groups; the copies follow them
        move.w  DB_SET+MF_COUNT(a4),d1
        lea     DB_SET+MANIFEST_HEADER(a4),a0
        bra.s   .count_next
.count:
        cmpi.w  #COPY_FIRST,ME_GROUP(a0)
        bcc.s   .counted
        addq.w  #1,d0
        lea     MANIFEST_ENTRY(a0),a0
.count_next:
        dbf     d1,.count
.counted:
        bsr.l   text_decimal
        lea     groups_text(pc),a0
        cmpi.w  #1,d0
        bne.s   .plural
        lea     group_text(pc),a0
.plural:
        bsr.l   text_copy
.use:
        lea     DB_INFO2(a4),a1
        lea     use_original_text(pc),a0
        tst.w   DB_SWITCH(a4)
        beq.s   .use_text
        lea     use_edited_text(pc),a0
.use_text:
        bsr.l   text_copy
        tst.w   DB_SWITCH(a4)
        beq.s   .done
        lea     DB_ACTIVE(a4),a0
        bsr.l   db_label_crc
.done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; draw_field: the label field (with a cursor while typing).
draw_field:
        movem.l a0-a1/a4,-(sp)
        lea     WORK_DB(a5),a4
        lea     DB_LABEL(a4),a0
        lea     DB_FIELD(a4),a1
        bsr.l   text_copy
        cmpi.w  #DBM_TYPING,DB_MODE(a4)
        bne.s   .draw
        move.b  #'_',(a1)+
        clr.b   (a1)
.draw:
        lea     field_commands(pc),a0
        bsr.l   dialog_draw
        movem.l (sp)+,a0-a1/a4
        rts

; ---------------------------------------------------------------------------
; Groups
; ---------------------------------------------------------------------------
; group_chosen: D0.w = CODE_ROW + row.
group_chosen:
        subi.w  #CODE_ROW,d0
        add.w   DB_PAGE(a4),d0
        bsr.l   db_group_list
        moveq   #0,d1
        move.b  (a0,d0.w),d1            ; the group
        move.w  d1,DB_SECOND(a4)
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        beq.s   open_group              ; the source group is saved (no changes)
        cmp.w   DB_GROUP(a4),d1
        beq.s   .same
        tst.w   DB_DIRTY(a4)
        beq.s   open_group
        lea     discard_title(pc),a0
        bsr.l   message_title
        bsr.w   changed_line            ; line 0
        lea     discard_line1(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        move.w  #STEP_DISCARD_OPEN,DB_STEP(a4)
        bra.w   open_question
.same:
        move.w  #DBS_GROUP,DB_NEXT(a4)
        moveq   #1,d0
        rts

; open_group: loads the group DB_SECOND as the working group and opens it.
open_group:
        move.w  DB_SECOND(a4),d0
        bsr.l   db_load_group
        bne.s   .failed
        clr.w   DB_CLUB_PAGE(a4)
        move.w  #-1,DB_CLUB(a4)
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .open
        move.w  #PICK_COPY_SLOT,DB_PICK(a4)
.open:
        move.w  #DBS_GROUP,DB_NEXT(a4)
        moveq   #1,d0
        rts
.failed:
        move.w  #-1,DB_GROUP(a4)
        clr.w   DB_DIRTY(a4)
        lea     not_found_title(pc),a0
        cmpi.l  #GC_MISSING,d0
        beq.s   .title
        lea     damaged_title(pc),a0
.title:
        bsr.l   message_title
        lea     DB_STATUS(a4),a1
        clr.b   (a1)
        bsr.l   db_problem_text
        moveq   #0,d0
        bsr.w   status_line
        lea     group_not_opened_line(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        bra.w   open_message

; changed_line: message line 0, changed_line_1: line 1: THE CHANGES TO
; <group> ARE NOT SAVED.
changed_line_1:
        movem.l d0-d1/a0-a1,-(sp)
        moveq   #1,d1
        bra.s   changed_text
changed_line:
        movem.l d0-d1/a0-a1,-(sp)
        moveq   #0,d1
changed_text:
        lea     DB_STATUS(a4),a1
        lea     changes_to_text(pc),a0
        bsr.l   text_copy
        move.w  DB_GROUP(a4),d0
        bsr.l   db_group_name
        lea     not_saved_text(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.s   status_line
        movem.l (sp)+,d0-d1/a0-a1
        rts

; status_line: D0.w = message line for the text in DB_STATUS. A0 = DB_STATUS.
status_line:
        lea     DB_STATUS(a4),a0
        bra.l   message_line

; ---------------------------------------------------------------------------
; SET LABEL
; ---------------------------------------------------------------------------
label_chosen:
        lea     DB_LABEL(a4),a0
        moveq   #SET_LABEL_SIZE,d0
        bsr.l   field_start
        move.w  #DBM_TYPING,DB_MODE(a4)
        moveq   #INDEX_LABEL,d2
        moveq   #UI_ACTIVE,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        bsr.w   draw_field
        lea     DB_STATUS(a4),a1
        lea     typing_text(pc),a0
        bsr.l   text_copy
        lea     status_commands(pc),a0
        bsr.l   dialog_draw
        moveq   #0,d0
        rts

; typing: the keyboard field takes the keys.
typing:
        bsr.l   field_key
        tst.l   d0
        bne.s   .end
        tst.l   d1
        beq.s   .stay
        bsr.w   draw_field
.stay:
        moveq   #0,d0
        rts
.end:
        ; the label differs from the set's when the next SAVE must write it
        clr.w   DB_LABEL_CHANGED(a4)
        lea     DB_LABEL(a4),a0
        lea     DB_SET+MF_LABEL(a4),a1
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4)
        beq.s   .compare
        tst.b   (a0)
        beq.s   .shown
        bra.s   .changed
.compare:
        moveq   #SET_LABEL_SIZE-1,d0
.char:
        move.b  (a0)+,d1
        cmp.b   (a1)+,d1
        bne.s   .changed
        tst.b   d1
        dbeq    d0,.char
        bra.s   .shown
.changed:
        move.w  #1,DB_LABEL_CHANGED(a4)
.shown:
        bra.w   show_database

; ---------------------------------------------------------------------------
; SAVE
; ---------------------------------------------------------------------------
save_chosen:
        bsr.l   db_save                 ; D0 result, D1 step
        beq.w   .saved
        cmpi.l  #1,d0
        beq.w   .nothing
        lea     save_failed_title(pc),a0
        bsr.l   message_title
        move.l  d1,d2                   ; the step
        moveq   #1,d1
        bsr.l   message_storage_reason
        moveq   #0,d0
        bsr.l   message_line
        lea     kept_line(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        cmpi.w  #3,d2
        bne.w   open_message
        ; DBASE.CFG failed after a verified DBASE.BAK
        lea     restore_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        move.w  #STEP_RESTORE,DB_STEP(a4)
        bra.w   open_question
.nothing:
        lea     save_title(pc),a0
        bsr.l   message_title
        lea     nothing_line(pc),a0
        cmpi.w  #DSS_DAMAGED,DB_SET_STATE(a4)
        bne.s   .nothing_line
        lea     damaged_set_text(pc),a0
.nothing_line:
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.saved:
        lea     save_title(pc),a0
        bsr.l   message_title
        lea     DB_STATUS(a4),a1
        lea     saved_text(pc),a0
        bsr.l   text_copy
        lea     DB_SET(a4),a0
        bsr.l   db_label_crc
        moveq   #0,d0
        bsr.w   status_line
        lea     DB_STATUS(a4),a1
        lea     generation_text(pc),a0
        bsr.l   text_copy
        move.w  DB_SET+MF_GENERATION+2(a4),d0
        bsr.l   text_decimal
        moveq   #1,d0
        bsr.w   status_line
        lea     saved_use_line(pc),a0
        tst.w   DB_SWITCH(a4)
        beq.s   .use
        lea     saved_in_use_line(pc),a0
.use:
        moveq   #2,d0
        bsr.l   message_line
        bra.w   open_message

; ---------------------------------------------------------------------------
; REMOVE OLD VERSIONS
; ---------------------------------------------------------------------------
remove_chosen:
        moveq   #0,d0
        bsr.l   db_old_versions         ; D1 = old versions
        bne.w   .failed
        lea     remove_title(pc),a0
        bsr.l   message_title
        tst.l   d1
        beq.s   .none
        lea     DB_STATUS(a4),a1
        lea     remove_count_text(pc),a0
        bsr.l   text_copy
        move.l  d1,d0
        bsr.l   text_decimal
        lea     remove_count_suffix(pc),a0
        cmpi.l  #1,d1
        bne.s   .plural
        lea     remove_one_suffix(pc),a0
.plural:
        bsr.l   text_copy
        moveq   #0,d0
        bsr.w   status_line
        lea     remove_lines(pc),a0
        moveq   #1,d0
        bsr.l   message_lines
        move.w  #STEP_REMOVE,DB_STEP(a4)
        bra.w   open_question
.none:
        lea     no_old_line(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.failed:
        move.l  d0,d2
        lea     remove_title(pc),a0
        bsr.l   message_title
        moveq   #0,d1
        bsr.l   message_storage_reason
        moveq   #0,d0
        bsr.l   message_line
        lea     nothing_removed_line(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        cmpi.l  #STE_NOT_FOUND,d2
        bne.s   .reason_shown
        lea     backup_unseen_lines(pc),a0  ; DBASE.BAK unseen after a failed save
        moveq   #2,d0
        bsr.l   message_lines
.reason_shown:
        bra.w   open_message

; ---------------------------------------------------------------------------
; USE EDITED DATABASE
; ---------------------------------------------------------------------------
switch_chosen:
        tst.w   DB_SWITCH(a4)
        beq.s   .on
        bsr.l   db_switch_off
        bsr.w   remember_switch
        bne.w   open_message
        bra.w   show_database
.on:
        cmpi.w  #DSS_VALID,DB_SET_STATE(a4) ; its files are checked on the disk
        bne.s   .no_set
        bsr.l   db_switch_on
        bne.s   .not_found
        bsr.w   remember_switch
        bne.w   open_message
        tst.w   DB_DIRTY(a4)
        beq.w   show_database
        lea     switch_title(pc),a0
        bsr.l   message_title
        lea     switch_on_line(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        bsr.w   changed_line_1
        lea     switch_save_line(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        bra.w   open_message
.no_set:
        lea     switch_title(pc),a0
        bsr.l   message_title
        lea     no_set_text(pc),a0
        cmpi.w  #DSS_DAMAGED,DB_SET_STATE(a4)
        bne.s   .no_set_line
        lea     damaged_set_text(pc),a0
.no_set_line:
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.not_found:
        lea     not_found_title(pc),a0
        bsr.l   message_title
        lea     DB_STATUS(a4),a1
        clr.b   (a1)
        bsr.l   db_problem_text
        moveq   #0,d0
        bsr.w   status_line
        lea     switch_stays_off_line(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        bra.w   open_message

; remember_switch: writes the switch's new state to DBASE.USE. D0.l = 0, or
; a result with the message prepared (SWITCH NOT SAVED).
remember_switch:
        bsr.l   db_switch_store
        beq.s   .done
        move.l  d0,-(sp)
        lea     switch_not_saved_title(pc),a0
        bsr.l   message_title
        moveq   #1,d1
        bsr.l   message_storage_reason
        moveq   #0,d0
        bsr.l   message_line
        lea     switch_not_saved_line(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        move.l  (sp)+,d0
.done:
        rts

; ---------------------------------------------------------------------------
; EXIT
; ---------------------------------------------------------------------------
exit_chosen:
        cmpi.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        bne.s   .leave
        clr.w   DB_PICK(a4)             ; the copy ends, nothing changed
        bra.w   show_database
.leave:
        tst.w   DB_DIRTY(a4)
        bne.s   .ask
        tst.w   DB_LABEL_CHANGED(a4)
        bne.s   .ask
        move.w  #DBS_EXIT,DB_NEXT(a4)
        moveq   #1,d0
        rts
.ask:
        lea     leave_title(pc),a0
        bsr.l   message_title
        tst.w   DB_DIRTY(a4)
        beq.s   .label
        bsr.w   changed_line
        bra.s   .question
.label:
        lea     label_not_saved_line(pc),a0
        moveq   #0,d0
        bsr.l   message_line
.question:
        lea     leave_line(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        move.w  #STEP_DISCARD_EXIT,DB_STEP(a4)
        bra.w   open_question

; ---------------------------------------------------------------------------
; Messages and questions inside the screen
; ---------------------------------------------------------------------------
; open_message, open_question: the message or question in place of the
; screen's dialog. D0.l = 0 (message_open).
open_message:
        move.w  #DBM_MESSAGE,DB_MODE(a4)
        moveq   #MSG_OK,d0
        bra.l   message_open

open_question:
        move.w  #DBM_ASK,DB_MODE(a4)
        moveq   #MSG_ASK,d0
        bra.l   message_open

message_tick:
        bsr.l   message_poll
        bmi.s   .stay
        move.w  #STEP_NONE,DB_STEP(a4)
        bra.w   show_database
.stay:
        moveq   #0,d0
        rts

question_tick:
        bsr.l   message_poll
        bmi.s   .stay
        move.w  DB_STEP(a4),d1
        move.w  #STEP_NONE,DB_STEP(a4)
        tst.l   d0
        beq.w   show_database           ; NO: nothing changes
        cmpi.w  #STEP_RECOVER,d1
        beq.s   .recover
        cmpi.w  #STEP_RESTORE,d1
        beq.s   .recover
        cmpi.w  #STEP_DISCARD_OPEN,d1
        beq.s   .discard_open
        cmpi.w  #STEP_DISCARD_EXIT,d1
        beq.s   .discard_exit
        cmpi.w  #STEP_REMOVE,d1
        beq.s   .remove
        bra.w   show_database
.stay:
        moveq   #0,d0
        rts
.recover:
        bsr.l   db_restore_backup       ; keeps D1
        move.l  d0,d2
        cmpi.w  #STEP_RECOVER,d1
        bne.s   .label_kept             ; after a failed SAVE: still to save
        bsr.w   label_from_set
.label_kept:
        lea     recover_title(pc),a0
        bsr.l   message_title
        lea     restored_line(pc),a0
        tst.l   d2
        beq.s   .recovered
        lea     not_restored_line(pc),a0
.recovered:
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.discard_open:
        clr.w   DB_DIRTY(a4)
        move.w  #-1,DB_GROUP(a4)
        bra.w   open_group
.discard_exit:
        clr.w   DB_DIRTY(a4)
        move.w  #DBS_EXIT,DB_NEXT(a4)
        moveq   #1,d0
        rts
.remove:
        moveq   #1,d0
        bsr.l   db_old_versions         ; D1 = removed
        move.l  d0,d2
        lea     remove_title(pc),a0
        bsr.l   message_title
        lea     DB_STATUS(a4),a1
        move.l  d1,d0
        bsr.l   text_decimal
        lea     removed_suffix(pc),a0
        cmpi.l  #1,d1
        bne.s   .removed_plural
        lea     removed_one_suffix(pc),a0
.removed_plural:
        bsr.l   text_copy
        moveq   #0,d0
        bsr.w   status_line
        tst.l   d2
        beq.w   open_message
        move.l  d2,d0
        moveq   #1,d1
        bsr.l   message_storage_reason
        moveq   #1,d0
        bsr.l   message_line
        bra.w   open_message

; ===========================================================================
; Data
; ===========================================================================
database_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    title_text
        dc.l    body_commands
        dc.w    0,CODE_EXIT,GROUP_ROWS+8
ROW     macro                           ; \1 = row
        if \1<COLUMN_ROWS
        dc.w    ROW_X,ROW_Y+\1*10,ROW_W,ROW_H,CODE_ROW+\1,DIALOG_ROW|UI_NORMAL
        else
        dc.w    ROW_X2,ROW_Y+(\1-COLUMN_ROWS)*10,ROW_W,ROW_H,CODE_ROW+\1,DIALOG_ROW|UI_NORMAL
        endif
        dc.l    editor_image+WORK_DB+DB_ROWS+\1*DB_ROW_SIZE
        endm
        ROW     0
        ROW     1
        ROW     2
        ROW     3
        ROW     4
        ROW     5
        ROW     6
        ROW     7
        ROW     8
        ROW     9
        ROW     10
        ROW     11
        ROW     12
        ROW     13
        ROW     14
        ROW     15
        ROW     16
        ROW     17
        ROW     18
        ROW     19
        ROW     20
        ROW     21
        ROW     22
        ROW     23
        dc.w    ROW_X,PAGE_Y,96,BUTTON_H,CODE_PREVIOUS,UI_NORMAL
        dc.l    previous_text
        dc.w    FIELD_X+104,PAGE_Y,96,BUTTON_H,CODE_NEXT,UI_NORMAL
        dc.l    next_text
        dc.w    ROW_X,LABEL_Y,96,BUTTON_H,CODE_LABEL,UI_NORMAL
        dc.l    label_label
        dc.w    ROW_X,SAVE_Y,96,BUTTON_H,CODE_SAVE,UI_NORMAL
        dc.l    save_label
        dc.w    FIELD_X,SAVE_Y,FIELD_W,BUTTON_H,CODE_REMOVE,UI_NORMAL
        dc.l    remove_label
        dc.w    FIELD_X,SWITCH_Y,FIELD_W,BUTTON_H,CODE_SWITCH,UI_NORMAL
        dc.l    switch_off_label
        dc.w    ROW_X,SWITCH_Y,96,BUTTON_H,CODE_EXIT,UI_NORMAL
        dc.l    exit_label
        dc.w    FIELD_X,PAGE_Y,96,BUTTON_H,CODE_CUPS,UI_NORMAL
        dc.l    cups_label

body_commands:
        dc.w    UI_TEXT_AT,ROW_X,INFO_Y,ROW_W*2+8,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_INFO
        dc.w    UI_TEXT_AT,ROW_X,INFO2_Y,ROW_W*2+8,UI_DIM,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_INFO2
        dc.w    UI_TEXT,ROW_X,HEAD_Y,ROW_W,UI_ACCENT,UI_LEFT
        dc.b    'COUNTRY GROUPS',0
        even
        dc.w    UI_TEXT,ROW_X2,HEAD_Y,ROW_W,UI_DIM,UI_RIGHT
        dc.b    '* IN THE SET  + CHANGED',0
        even
        dc.w    UI_TEXT,ROW_X,CREDIT_Y,ROW_W*2+8,UI_DIM,UI_CENTER
        dc.b    'V0.91b by Timo Heimonen (timo.heimonen@proton.me)',0
        even
        dc.w    UI_END

; The label field right of SET LABEL.
field_commands:
        dc.w    UI_RECT,FIELD_X,LABEL_Y+1,FIELD_W,BUTTON_H-2,UI_SHADOW
        dc.w    UI_TEXT_AT,FIELD_X+3,LABEL_Y+3,FIELD_W-6,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_FIELD
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,ROW_W*2+8,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,ROW_W*2+8,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_STATUS
        dc.w    UI_END

title_text:             dc.b    'EDIT DATABASE',0
label_label:            dc.b    'SET _LABEL',0
save_label:             dc.b    '_SAVE',0
remove_label:           dc.b    '_REMOVE OLD VERSIONS',0
switch_off_label:       dc.b    '_USE EDITED DATABASE: OFF',0
switch_on_label:        dc.b    '_USE EDITED DATABASE: ON',0
exit_label:             dc.b    'E_XIT',0
cups_label:             dc.b    '_EUROPEAN CUPS',0
start_line0:            dc.b    'THE EDITED DATABASE WAS NOT SWITCHED ON AT START:',0
start_line2:            dc.b    'NEW COMPETITIONS USE THE ORIGINAL DATABASE.',0
switch_not_saved_title: dc.b    'SWITCH NOT SAVED',0
switch_not_saved_line:  dc.b    'THE NEXT START DOES NOT REMEMBER THIS CHANGE.',0
end_copy_label:         dc.b    '_END COPY',0
no_set_text:            dc.b    'NO EDITED SET IN THE SAVE DIRECTORY YET',0
damaged_set_text:       dc.b    'DBASE.CFG IS DAMAGED. NOTHING CAN BE SAVED.',0
set_text:               dc.b    'SET: ',0
comma_text:             dc.b    ', ',0
groups_text:            dc.b    ' GROUPS',0
group_text:             dc.b    ' GROUP',0
use_original_text:      dc.b    'NEW COMPETITIONS USE THE ORIGINAL DATABASE',0
use_edited_text:        dc.b    'NEW COMPETITIONS USE ',0
choose_text:            dc.b    'CHOOSE A COUNTRY GROUP',0
copy_country_text:      dc.b    'CHOOSE THE COUNTRY FOR ',0
changed_prefix:         dc.b    'CHANGES TO ',0
changed_suffix:         dc.b    ' NOT SAVED YET',0
typing_text:            dc.b    'TYPE THE LABEL, RETURN KEEPS IT, ESC UNDOES',0
recover_title:          dc.b    'DBASE.CFG',0
missing_cfg_text:       dc.b    'DBASE.CFG IS MISSING.',0
damaged_cfg_text:       dc.b    'DBASE.CFG IS DAMAGED:',0
recover_lines:          dc.b    'DBASE.BAK HOLDS THE PREVIOUS SET.',0
                        dc.b    'RESTORE DBASE.CFG FROM IT NOW?',0
                        dc.b    0
restored_line:          dc.b    'DBASE.CFG RESTORED FROM DBASE.BAK.',0
not_restored_line:      dc.b    'RESTORE FAILED. DBASE.BAK IS UNCHANGED.',0
discard_title:          dc.b    'OTHER GROUP',0
discard_line1:          dc.b    'DISCARD THEM AND OPEN THE OTHER GROUP?',0
changes_to_text:        dc.b    'THE CHANGES TO ',0
not_saved_text:         dc.b    ' ARE NOT SAVED.',0
not_found_title:        dc.b    'DATABASE NOT FOUND',0
damaged_title:          dc.b    'FILE DAMAGED',0
group_not_opened_line:  dc.b    'THE GROUP IS NOT OPENED.',0
save_title:             dc.b    'SAVE',0
save_failed_title:      dc.b    'DATABASE NOT SAVED',0
kept_line:              dc.b    'THE CHANGES STAY IN MEMORY.',0
restore_lines:          dc.b    'THE PREVIOUS SET IS SAFE IN DBASE.BAK.',0
                        dc.b    'RESTORE DBASE.CFG FROM IT NOW?',0
                        dc.b    0
nothing_line:           dc.b    'NOTHING TO SAVE.',0
saved_text:             dc.b    'SAVED: ',0
generation_text:        dc.b    'GENERATION ',0
saved_use_line:         dc.b    'USE EDITED DATABASE: ON USES IT.',0
saved_in_use_line:      dc.b    'NEW COMPETITIONS USE IT NOW.',0
remove_title:           dc.b    'REMOVE OLD VERSIONS',0
remove_count_text:      dc.b    'REMOVE ',0
remove_count_suffix:    dc.b    ' OLD GROUP FILES?',0
remove_one_suffix:      dc.b    ' OLD GROUP FILE?',0
remove_lines:           dc.b    'NO DBASE.CFG, DBASE.BAK OR LINK HERE USES THEM.',0
                        dc.b    'SAVES STARTED WITH THEM IN OTHER SAVE',0
                        dc.b    'DIRECTORIES CANNOT BE CONTINUED THEN.',0
                        dc.b    0
no_old_line:            dc.b    'THERE ARE NO OLD VERSIONS.',0
nothing_removed_line:   dc.b    'NOTHING WAS REMOVED.',0
backup_unseen_lines:    dc.b    'DBASE.BAK CANNOT BE READ AFTER A FAILED SAVE:',0
                        dc.b    'START THE GAME AGAIN FIRST.',0
                        dc.b    0
removed_suffix:         dc.b    ' OLD GROUP FILES REMOVED.',0
removed_one_suffix:     dc.b    ' OLD GROUP FILE REMOVED.',0
switch_title:           dc.b    'USE EDITED DATABASE',0
switch_on_line:         dc.b    'NEW COMPETITIONS USE THE SAVED SET.',0
switch_save_line:       dc.b    'SAVE TO MAKE THEM PART OF THE SET.',0
switch_stays_off_line:  dc.b    'THE SWITCH STAYS OFF.',0
leave_title:            dc.b    'EXIT',0
label_not_saved_line:   dc.b    'THE NEW SET LABEL IS NOT SAVED.',0
leave_line:             dc.b    'LEAVE WITHOUT SAVING?',0
        even
