; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; LOAD DEFINITION on the DIY type page: an own list of the .DEF files in
; the save directory (listed through the slave with an explicit capacity,
; sorted by name, sixteen to a page), each with its competition and the
; CRC-32 of its body. Choosing one:
;
;   1. reads it after querying its length (never more than DEF_FILE_MAX
;      bytes) and checks it completely; a file with a problem is refused
;      with FILE DAMAGED, its name and the problem;
;   2. compares the database it was made with with the one in use; a
;      difference shows DEFINITION MADE WITH ANOTHER DATABASE and goes on
;      only after YES;
;   3. finds every listed team in the database and custom set in use; a
;      missing team is reported (TEAM NOT FOUND), never replaced;
;   4. asks once before its tactics replace a different tactic the user
;      loaded or edited;
;   5. installs its tactics (tactics_install: user-owned, refreshed), holds
;      its rules and teams and opens the family's setup page, whose init
;      applies the rules (editors/definition.s).
;
; Nothing changes before step 5; NO at a question returns to the list.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    defload_action, load_dialog
        xref    editor_base, editor_image
        xref    screen_run
        xref    dialog_open, dialog_poll, dialog_draw
        xref    message_title, message_line, message_lines
        xref    message_open, message_poll, message_storage_reason
        xref    definition_check_file, definition_identity
        xref    definition_listed_teams, definition_problem_lines, definition_team_missing
        xref    tactics_owned, tactics_install
        xref    slot_list
        xref    storage_list, storage_size, storage_read, storage_read_part
        xref    text_copy, text_copy_max, text_decimal, text_hex32, text_pad
        xref    cancel_text, previous_text

TOP                     equ 8
HEIGHT                  equ 256
ROW_X                   equ DIALOG_BAND_X+8
ROW_W                   equ DIALOG_BAND_WIDTH-16
HEAD_Y                  equ TOP+16
LIST_Y                  equ HEAD_Y+11
ROWS                    equ 16
STATUS_Y                equ LIST_Y+ROWS*12+4
BUTTON_Y                equ TOP+HEIGHT-18
; Columns of a row (characters)
COLUMN_TYPE             equ 13
COLUMN_NAME             equ 24
COLUMN_CRC              equ 41
NAME_SHOWN              equ 12
COMPETITION_SHOWN       equ 16
; Button codes and indices
CODE_CANCEL             equ 0
CODE_PREVIOUS           equ 1
CODE_NEXT               equ 2
CODE_ROW                equ 100
INDEX_PREVIOUS          equ ROWS
INDEX_NEXT              equ ROWS+1
; DF_STEP
STEP_NONE               equ 0
STEP_EMPTY              equ 1           ; message: nothing to list, then close
STEP_DATABASE           equ 2           ; question: another database
STEP_TACTICS            equ 3           ; question: replace the user's tactics
; Read of a row's description: the header and the body up to the pitch.
PREVIEW_SIZE            equ DEF_HEADER_SIZE+DR_PITCH_MODE

        section .text,code

; ---------------------------------------------------------------------------
; defload_action: LOAD DEFINITION (an entry action of the type page). After
; a definition has been loaded the type page ends with its family chosen.
; ---------------------------------------------------------------------------
defload_action:
        movea.l editor_base,a5
        bclr    #DFS_LOADED,WORK_DEF+DF_STATE+1(a5)
        lea     load_screen(pc),a0
        bsr.l   screen_run
        btst    #DFS_LOADED,WORK_DEF+DF_STATE+1(a5)
        beq.s   .done
        move.w  WORK_DEF+DF_FAMILY(a5),diy_type_choice
        jmp     menu_request_exit
.done:
        rts

load_screen:
        dc.l    load_open
        dc.l    load_tick

; ---------------------------------------------------------------------------
; load_open: lists the definitions. A5 = editor base.
; ---------------------------------------------------------------------------
load_open:
        lea     WORK_DEF(a5),a4
        move.w  #DFM_MAIN,DF_MODE(a4)
        move.w  #STEP_NONE,DF_STEP(a4)
        clr.w   DF_PAGE(a4)
        clr.w   DF_COUNT(a4)
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  #LIST_WORK_RECORDS,d1
        bsr.l   storage_list            ; D1 = names
        bne.s   .listed
        cmpi.l  #LIST_WORK_RECORDS,d1
        bls.s   .filter
        move.l  #LIST_WORK_RECORDS,d1
.filter:
        bsr.w   keep_definitions        ; DF_COUNT
        bsr.w   sort_definitions
.listed:
        tst.w   DF_COUNT(a4)
        bne.w   show_list
        lea     title_text(pc),a0
        bsr.l   message_title
        lea     none_lines(pc),a0
        moveq   #0,d0
        bsr.l   message_lines
        move.w  #STEP_EMPTY,DF_STEP(a4)
        bra.w   open_message

; keep_definitions: D1.l = records listed. Moves the names ending in .DEF
; (any case) to the front; DF_COUNT = their number.
keep_definitions:
        lea     LIST_WORK_OFFSET(a5),a0 ; read
        movea.l a0,a1                   ; write
        moveq   #0,d2
        bra.s   .test
.record:
        bsr.w   is_definition
        bne.s   .skip
        cmpa.l  a0,a1
        beq.s   .kept
        moveq   #FS_RECORD_SIZE/4-1,d0
.copy:
        move.l  (a0,d0.w*4),(a1,d0.w*4)
        dbf     d0,.copy
.kept:
        lea     FS_RECORD_SIZE(a1),a1
        addq.w  #1,d2
.skip:
        lea     FS_RECORD_SIZE(a0),a0
.test:
        dbf     d1,.record
        move.w  d2,DF_COUNT(a4)
        rts

; is_definition: A0 = record. Z set when the name ends in .DEF (any case).
is_definition:
        movem.l d0-d1/a0-a1,-(sp)
        moveq   #0,d0
.end:
        tst.b   (a0,d0.w)
        beq.s   .found
        addq.w  #1,d0
        cmpi.w  #FS_RECORD_SIZE,d0
        bcs.s   .end
.found:
        cmpi.w  #5,d0                   ; at least one character and .DEF
        bcs.s   .no
        lea     -4(a0,d0.w),a0
        lea     def_suffix(pc),a1
        moveq   #3,d1
.char:
        move.b  (a0)+,d0
        bsr.s   upper
        cmp.b   (a1)+,d0
        bne.s   .no
        dbf     d1,.char
        movem.l (sp)+,d0-d1/a0-a1
        cmp.w   d0,d0
        rts
.no:
        movem.l (sp)+,d0-d1/a0-a1
        moveq   #1,d0
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

; sort_definitions: the DF_COUNT records by name, ignoring case
; (insertion sort, records swapped whole).
sort_definitions:
        movem.l d0-d7/a0-a3,-(sp)
        moveq   #1,d6                   ; next record to insert
.outer:
        cmp.w   DF_COUNT(a4),d6
        bcc.s   .done
        move.w  d6,d7
.inner:
        tst.w   d7
        beq.s   .next
        bsr.s   record_address          ; A0 = record d7
        lea     -FS_RECORD_SIZE(a0),a1  ; the record before it
        bsr.s   compare_names           ; C set: A0 sorts before A1
        bcc.s   .next
        moveq   #FS_RECORD_SIZE/4-1,d0
.swap:
        move.l  (a0,d0.w*4),d1
        move.l  (a1,d0.w*4),(a0,d0.w*4)
        move.l  d1,(a1,d0.w*4)
        dbf     d0,.swap
        subq.w  #1,d7
        bra.s   .inner
.next:
        addq.w  #1,d6
        bra.s   .outer
.done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; record_address: D7.w = record. A0 = its address.
record_address:
        move.w  d7,d0
        mulu.w  #FS_RECORD_SIZE,d0
        lea     LIST_WORK_OFFSET(a5,d0.l),a0
        rts

; compare_names: A0, A1 = names. C set when A0 sorts before A1 (ignoring
; case). Changes D0.
compare_names:
        movem.l d1/a0-a1,-(sp)
.char:
        move.b  (a1)+,d0
        bsr.s   upper
        move.b  d0,d1
        move.b  (a0)+,d0
        bsr.s   upper
        cmp.b   d1,d0
        bne.s   .done
        tst.b   d0                      ; C clear
        bne.s   .char
.done:
        movem.l (sp)+,d1/a0-a1
        rts

; ---------------------------------------------------------------------------
; The list
; ---------------------------------------------------------------------------
; show_list: the rows of the page starting at DF_PAGE; disabled rows and
; buttons where nothing is to be shown.
show_list:
        bsr.w   build_rows
        lea     load_dialog(pc),a0
        moveq   #0,d2
        moveq   #ROWS-1,d1
.rows:
        move.w  DF_PAGE(a4),d0
        add.w   d1,d0
        cmp.w   DF_COUNT(a4),d0
        bcs.s   .shown
        bset    d1,d2
.shown:
        dbf     d1,.rows
        tst.w   DF_PAGE(a4)
        bne.s   .next
        bset    #INDEX_PREVIOUS,d2
.next:
        move.w  DF_PAGE(a4),d0
        addi.w  #ROWS,d0
        cmp.w   DF_COUNT(a4),d0
        bcs.s   .open
        bset    #INDEX_NEXT,d2
.open:
        bsr.l   dialog_open             ; D0.l = 0, kept by dialog_draw
        lea     status_commands(pc),a0
        bra.l   dialog_draw

; build_rows: the labels of the rows (DF_LINES) and the status line.
build_rows:
        movem.l d0-d7/a0-a3,-(sp)
        moveq   #0,d6                   ; row
.row:
        move.w  d6,d0
        mulu.w  #DF_LINE_SIZE,d0
        lea     DF_LINES(a4,d0.l),a1
        movea.l a1,a3                   ; start of the line
        clr.b   (a1)
        move.w  DF_PAGE(a4),d7
        add.w   d6,d7
        cmp.w   DF_COUNT(a4),d7
        bcc.w   .next
        bsr.w   record_address          ; A0 = name
        movea.l a0,a2
        moveq   #NAME_SHOWN,d0
        bsr.l   text_copy_max
        moveq   #COLUMN_TYPE,d0
        add.l   a3,d0
        bsr.l   text_pad
        movea.l a2,a0                   ; the file's header and rules
        lea     WORK_IO_BUFFER(a5),a1
        moveq   #PREVIEW_SIZE,d1
        moveq   #0,d2
        bsr.l   storage_read_part       ; D1 = bytes read, flags from D0
        movea.l a1,a2
        lea     COLUMN_TYPE(a3),a1
        bne.s   .unknown
        cmpi.l  #PREVIEW_SIZE,d1
        bcs.s   .unknown
        cmpi.l  #DEF_MAGIC_HIGH,DH_MAGIC(a2)
        bne.s   .unknown
        cmpi.l  #DEF_MAGIC_LOW,DH_MAGIC+4(a2)
        bne.s   .unknown
        move.w  DEF_HEADER_SIZE+DR_FAMILY(a2),d0
        cmpi.w  #FAMILY_TOURNAMENT,d0
        bhi.s   .family_done
        lea     family_names(pc),a0
        bra.s   .family_test
.family_skip:
        tst.b   (a0)+
        bne.s   .family_skip
.family_test:
        dbf     d0,.family_skip
        bsr.l   text_copy
.family_done:
        moveq   #COLUMN_NAME,d0
        add.l   a3,d0
        bsr.l   text_pad
        lea     DEF_HEADER_SIZE+DR_NAME(a2),a0
        clr.b   DEF_HEADER_SIZE+DR_NAME+DR_NAME_MAX(a2)
        moveq   #COMPETITION_SHOWN,d0
        bsr.l   text_copy_max
        moveq   #COLUMN_CRC,d0
        add.l   a3,d0
        bsr.l   text_pad
        move.l  DH_CRC32(a2),d0
        bsr.l   text_hex32
        bra.s   .next
.unknown:
        lea     not_definition(pc),a0
        bsr.l   text_copy
.next:
        addq.w  #1,d6
        cmpi.w  #ROWS,d6
        bcs.w   .row
        lea     DF_STATUS(a4),a1
        move.w  DF_COUNT(a4),d0
        bsr.l   text_decimal
        lea     definitions_text(pc),a0
        cmpi.w  #1,d0
        bne.s   .plural
        lea     definition_text(pc),a0
.plural:
        bsr.l   text_copy
        cmpi.w  #ROWS,d0
        bls.s   .done
        lea     page_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.w  DF_PAGE(a4),d0
        divu.w  #ROWS,d0
        addq.w  #1,d0
        bsr.l   text_decimal
        lea     of_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.w  DF_COUNT(a4),d0
        addi.w  #ROWS-1,d0
        divu.w  #ROWS,d0
        bsr.l   text_decimal
.done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; ---------------------------------------------------------------------------
; load_tick: A5 = editor base, D7.w = events, D6.w = key. D0.l <> 0 closes.
; ---------------------------------------------------------------------------
load_tick:
        lea     WORK_DEF(a5),a4
        move.w  DF_MODE(a4),d0
        cmpi.w  #DFM_MESSAGE,d0
        beq.s   .message
        cmpi.w  #DFM_ASK,d0
        beq.w   question_tick
        bsr.l   dialog_poll
        bmi.s   .stay
        cmpi.w  #CODE_ROW,d0
        bcc.w   load_row
        cmpi.w  #CODE_PREVIOUS,d0
        beq.s   .previous
        cmpi.w  #CODE_NEXT,d0
        beq.s   .next
        moveq   #1,d0                   ; CANCEL, Esc
        rts
.previous:
        subi.w  #ROWS,DF_PAGE(a4)
        bra.w   show_list
.next:
        addi.w  #ROWS,DF_PAGE(a4)
        bra.w   show_list
.message:
        bsr.l   message_poll
        bmi.s   .stay
        cmpi.w  #STEP_EMPTY,DF_STEP(a4)
        bne.s   back_to_list
        moveq   #1,d0
        rts
.stay:
        moveq   #0,d0
        rts

; question_tick: the answer to a question of the load.
question_tick:
        bsr.l   message_poll
        bmi.s   .stay
        beq.s   back_to_list
        cmpi.w  #STEP_DATABASE,DF_STEP(a4)
        beq.w   load_teams
        bra.w   load_finish             ; STEP_TACTICS
.stay:
        moveq   #0,d0
        rts

; back_to_list: the list's own dialog again.
back_to_list:
        move.w  #DFM_MAIN,DF_MODE(a4)
        move.w  #STEP_NONE,DF_STEP(a4)
        bra.w   show_list

; ---------------------------------------------------------------------------
; Loading
; ---------------------------------------------------------------------------
; load_row: D0.w = CODE_ROW + row.
load_row:
        subi.w  #CODE_ROW,d0
        add.w   DF_PAGE(a4),d0
        move.w  d0,d7
        bsr.w   record_address
        lea     DF_FILE(a4),a1
        bsr.l   text_copy
        lea     DF_FILE(a4),a0
        bsr.l   storage_size            ; D1 = length
        bne.w   load_failed
        cmpi.l  #DEF_FILE_MAX,d1
        bhi.s   .size
        cmpi.l  #DEF_FILE_MIN,d1
        bcs.s   .size
        lea     DF_FILE(a4),a0
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #DEF_FILE_MAX,d1
        bsr.l   storage_read            ; D1 = length, never more than asked
        bne.w   load_failed
        lea     WORK_IO_BUFFER(a5),a0
        move.l  d1,d0
        bsr.l   definition_check_file
        bne.s   damaged
        lea     WORK_IO_BUFFER+DEF_HEADER_SIZE(a5),a2
        lea     -DI_CUSTOM_CRC(sp),sp   ; the identity in use
        movea.l sp,a1
        bsr.l   definition_identity
        moveq   #DI_CUSTOM_CRC/2-1,d0
.compare:
        cmpm.w  (a1)+,(a2)+
        dbne    d0,.compare
        lea     DI_CUSTOM_CRC(sp),sp
        beq.w   load_teams
        bra.w   ask_database
.size:
        moveq   #DC_SIZE,d0
        moveq   #0,d1
; damaged: D0.l = problem, D1-D3 details. FILE DAMAGED.
damaged:
        lea     title_damaged(pc),a0
        bsr.l   message_title
        moveq   #1,d4
        bsr.l   definition_problem_lines
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_not_loaded(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bra.w   open_message

; load_failed: D0.l = storage result. The approved reason.
load_failed:
        lea     title_not_loaded(pc),a0
        bsr.l   message_title
        moveq   #0,d1                   ; a read
        bsr.l   message_storage_reason
        moveq   #1,d0
        bsr.l   message_line
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message

; ask_database: the definition was made with another database.
ask_database:
        lea     title_database(pc),a0
        bsr.l   message_title
        lea     DF_STATUS(a4),a1
        lea     made_with(pc),a0
        bsr.l   text_copy
        lea     WORK_IO_BUFFER+DEF_HEADER_SIZE(a5),a2
        bsr.w   database_text
        lea     DF_STATUS(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        lea     in_use(pc),a0
        bsr.l   text_copy
        lea     -DI_CUSTOM_CRC(sp),sp
        movea.l a1,a3
        movea.l sp,a1
        bsr.l   definition_identity
        movea.l sp,a2
        movea.l a3,a1
        bsr.w   database_text
        lea     DI_CUSTOM_CRC(sp),sp
        lea     DF_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     anyway_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        move.w  #STEP_DATABASE,DF_STEP(a4)
        bra.w   open_question

; database_text: A2 = identity, appended at A1: ORIGINAL DATABASE, or the
; set label (EDITED without one) and the manifest CRC-32.
database_text:
        movem.l d0/a0,-(sp)
        lea     original_text(pc),a0
        tst.w   DI_KIND(a2)
        beq.s   .copy
        lea     edited_text(pc),a0
        tst.b   DI_LABEL(a2)
        beq.s   .label
        lea     DI_LABEL(a2),a0
        moveq   #DI_LABEL_SIZE,d0
        bsr.l   text_copy_max
        bra.s   .crc
.label:
        bsr.l   text_copy
.crc:
        move.b  #' ',(a1)+
        move.l  DI_MANIFEST_CRC(a2),d0
        bsr.l   text_hex32
        bra.s   .done
.copy:
        bsr.l   text_copy
.done:
        movem.l (sp)+,d0/a0
        rts

; load_teams: every listed team must be in the database or custom set in
; use; then the tactics.
load_teams:
        lea     WORK_IO_BUFFER+DEF_HEADER_SIZE(a5),a2
        bsr.l   definition_listed_teams ; D0 = missing team (1-based) or 0
        beq.w   .tactics
        move.w  d0,d7
        subq.w  #1,d0
        mulu.w  #DP_SIZE,d0
        lea     DEF_BODY_FIXED(a2,d0.l),a3
        move.w  d7,d0
        moveq   #1,d1
        bsr.l   definition_team_missing
        lea     DF_FILE(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_not_loaded(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bra.w   open_message
.tactics:
        bsr.w   replaced_slots          ; D0 = user-owned slots it changes
        beq.w   load_finish
        move.w  d0,d7
        lea     title_tactics(pc),a0
        bsr.l   message_title
        lea     DF_STATUS(a4),a1
        lea     brings_text(pc),a0
        bsr.l   text_copy
        move.w  DR_TACTIC_MASK(a2),d0
        bsr.l   slot_list
        lea     stop_text(pc),a0
        bsr.l   text_copy
        lea     DF_STATUS(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     line_replaces(pc),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     DF_STATUS(a4),a1
        move.w  d7,d0
        bsr.l   slot_list
        lea     stop_text(pc),a0
        bsr.l   text_copy
        lea     DF_STATUS(a4),a0
        moveq   #2,d0
        bsr.l   message_line
        lea     line_replace_answer(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        move.w  #STEP_TACTICS,DF_STEP(a4)
        bra.w   open_question

; replaced_slots: A2 = body. D0.l = mask of the user-owned slots whose
; content a present tactic would change (flags set).
replaced_slots:
        movem.l d1-d5/a0-a1/a3,-(sp)
        bsr.l   tactics_owned
        move.w  d0,d4
        move.w  DR_TACTIC_MASK(a2),d5
        moveq   #0,d0
        move.w  DR_TEAM_COUNT(a2),d0
        mulu.w  #DP_SIZE,d0
        lea     DEF_BODY_FIXED(a2,d0.l),a0
        moveq   #0,d3                   ; result
        moveq   #0,d2                   ; slot
.slot:
        btst    d2,d5
        beq.s   .next
        btst    d2,d4
        beq.s   .record
        move.w  d2,d0
        mulu.w  #TACTIC_SIZE,d0
        lea     user_tactic_slots,a1
        adda.l  d0,a1
        move.w  #TACTIC_SIZE-1,d1
        movea.l a0,a3
.compare:
        cmpm.b  (a1)+,(a3)+
        dbne    d1,.compare
        beq.s   .record
        bset    d2,d3
.record:
        lea     TACTIC_SIZE(a0),a0
.next:
        addq.w  #1,d2
        cmpi.w  #USER_TACTIC_SLOTS,d2
        bcs.s   .slot
        move.l  d3,d0
        movem.l (sp)+,d1-d5/a0-a1/a3
        tst.l   d0
        rts

; load_finish: installs the tactics, holds the rules and teams and closes
; the list; the type page then opens the family's setup page.
load_finish:
        lea     WORK_IO_BUFFER+DEF_HEADER_SIZE(a5),a2
        moveq   #0,d0
        move.w  DR_TEAM_COUNT(a2),d0
        mulu.w  #DP_SIZE,d0
        lea     DEF_BODY_FIXED(a2,d0.l),a0
        move.w  DR_TACTIC_MASK(a2),d5
        moveq   #0,d4
.slot:
        btst    d4,d5
        beq.s   .next
        move.w  d4,d0
        bsr.l   tactics_install         ; checked before: always accepted
        lea     TACTIC_SIZE(a0),a0
.next:
        addq.w  #1,d4
        cmpi.w  #USER_TACTIC_SLOTS,d4
        bcs.s   .slot
        movea.l a2,a0                   ; the fixed part and the teams
        lea     DF_BODY(a4),a1
        move.w  #DEF_BODY_FIXED/2-1,d0
.fixed:
        move.w  (a0)+,(a1)+
        dbf     d0,.fixed
        moveq   #0,d0
        move.w  DR_TEAM_COUNT(a2),d0
        move.w  d0,DF_TEAMS(a4)
        mulu.w  #DP_SIZE/2,d0
        lea     DF_LIST(a4),a1
        bra.s   .list_test
.list:
        move.w  (a0)+,(a1)+
.list_test:
        dbf     d0,.list
        move.w  DR_FAMILY(a2),DF_FAMILY(a4)
        move.l  WORK_IO_BUFFER+DH_CRC32(a5),DF_SAVED_CRC(a4)
        bset    #DFS_APPLY,DF_STATE+1(a4)
        bset    #DFS_LOADED,DF_STATE+1(a4)
        moveq   #1,d0
        rts

; open_message / open_question: in place of the list's dialog. D0.l = 0.
open_message:
        move.w  #DFM_MESSAGE,DF_MODE(a4)
        moveq   #MSG_OK,d0
        bra.l   message_open

open_question:
        move.w  #DFM_ASK,DF_MODE(a4)
        moveq   #MSG_ASK,d0
        bra.l   message_open

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
ROW     macro
        dc.w    ROW_X,LIST_Y+\1*12,ROW_W,9,CODE_ROW+\1,DIALOG_ROW|UI_NORMAL
        dc.l    editor_image+WORK_DEF+DF_LINES+\1*DF_LINE_SIZE
        endm

load_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    title_text
        dc.l    load_body
        dc.w    0,CODE_CANCEL,ROWS+3
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
        dc.w    ROW_X,BUTTON_Y,88,13,CODE_PREVIOUS,UI_NORMAL
        dc.l    previous_text
        dc.w    ROW_X+108,BUTTON_Y,88,13,CODE_NEXT,UI_NORMAL
        dc.l    next_text
        dc.w    ROW_X+216,BUTTON_Y,88,13,CODE_CANCEL,UI_NORMAL
        dc.l    cancel_text

load_body:
        dc.w    UI_TEXT,ROW_X,HEAD_Y,ROW_W,UI_ACCENT,UI_LEFT
        dc.b    'FILE         TYPE       COMPETITION      CRC-32',0
        even
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,ROW_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,ROW_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_STATUS
        dc.w    UI_END

title_text:             dc.b    'LOAD DEFINITION',0
title_damaged:          dc.b    'FILE DAMAGED',0
title_not_loaded:       dc.b    'DEFINITION NOT LOADED',0
title_database:         dc.b    'DEFINITION MADE WITH ANOTHER DATABASE',0
title_tactics:          dc.b    'REPLACE YOUR TACTICS?',0
none_lines:             dc.b    'THE SAVE DIRECTORY HOLDS NO DEFINITION.',0
                        dc.b    'SAVE ONE WITH SAVE DEFINITION ON A SETUP PAGE.',0
                        dc.b    0
line_not_loaded:        dc.b    'THE DEFINITION WAS NOT LOADED.',0
anyway_lines:           dc.b    'THE TEAMS COME FROM THE DATABASE IN USE.',0
                        dc.b    'LOAD IT ANYWAY?',0
                        dc.b    0
line_replaces:          dc.b    'IT REPLACES YOUR OWN TACTICS IN',0
line_replace_answer:    dc.b    'YES LOADS IT, NO KEEPS YOURS.',0
made_with:              dc.b    'MADE WITH: ',0
in_use:                 dc.b    'IN USE: ',0
original_text:          dc.b    'ORIGINAL DATABASE',0
edited_text:            dc.b    'EDITED',0
brings_text:            dc.b    'THE DEFINITION BRINGS ',0
stop_text:              dc.b    '.',0
not_definition:         dc.b    '(NOT A DEFINITION)',0
definitions_text:       dc.b    ' DEFINITIONS',0
definition_text:        dc.b    ' DEFINITION',0
page_text:              dc.b    ', PAGE ',0
of_text:                dc.b    ' OF ',0
family_names:           dc.b    'LEAGUE',0,'CUP',0,'TOURNAMENT',0
def_suffix:             dc.b    '.DEF'
next_text:              dc.b    'NE_XT',0
        even
