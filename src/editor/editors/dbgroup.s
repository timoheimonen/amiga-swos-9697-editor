; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The group screen of EDIT DATABASE: the clubs of the working group (two
; columns of twelve, each with its division) and their actions:
;
;   EDIT TEAM        the game's own team page on the chosen club (with the
;                    EDIT actions, TEAM SETTINGS and the player screen)
;   DIVISION SWAP    the chosen club and a second club of the group change
;                    divisions, so every division keeps its number of teams
;   EXCHANGE         the two clubs change places: each slot keeps its key,
;                    secondary index and division, everything else moves
;   COPY TO COUNTRY  the chosen club replaces a club of another country:
;                    the destination keeps its key, secondary index and
;                    division; the source is unchanged
;   BACK             the database screen
;
; National groups (80-85) have one division: there DIVISION SWAP and COPY
; TO COUNTRY are not offered. Every change stays in the working group until
; SAVE on the database screen.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    group_screen, group_dialog
        xref    editor_base, editor_image
        xref    dialog_open, dialog_poll, dialog_set, dialog_draw
        xref    message_title, message_line, message_lines, message_open, message_poll
        xref    text_copy, text_copy_max, text_decimal
        xref    db_group_name
        xref    previous_text, next_text, back_text

CLUB_ROWS               equ DB_ROW_COUNT ; 2 columns of 12
COLUMN_ROWS             equ 12
TOP                     equ 8
HEIGHT                  equ 256
INFO_Y                  equ TOP+15
HEAD_Y                  equ INFO_Y+12
ROW_Y                   equ HEAD_Y+10
ROW_X                   equ DIALOG_BAND_X+8
ROW_W                   equ 148
ROW_X2                  equ ROW_X+ROW_W+8
ROW_H                   equ 9
PAGE_Y                  equ ROW_Y+COLUMN_ROWS*10+2
ACTION_Y                equ PAGE_Y+20
ACTION2_Y               equ ACTION_Y+17
STATUS_Y                equ ACTION2_Y+30
BUTTON_H                equ 13
; Button codes and indices
CODE_BACK               equ 0
CODE_PREVIOUS           equ 1
CODE_NEXT               equ 2
CODE_EDIT               equ 3
CODE_SWAP               equ 4
CODE_EXCHANGE           equ 5
CODE_COPY               equ 6
CODE_ROW                equ 100
INDEX_PREVIOUS          equ CLUB_ROWS
INDEX_NEXT              equ CLUB_ROWS+1
INDEX_EDIT              equ CLUB_ROWS+2
INDEX_SWAP              equ CLUB_ROWS+3
INDEX_EXCHANGE          equ CLUB_ROWS+4
INDEX_COPY              equ CLUB_ROWS+5
; DB_STEP
STEP_NONE               equ 0
STEP_SWAP               equ 1           ; question: swap the divisions
STEP_EXCHANGE           equ 2           ; question: exchange the clubs
STEP_COPY               equ 3           ; question: copy into the destination

        section .text,code

group_screen:
        dc.l    group_open
        dc.l    group_tick

; group_open: A5 = editor base.
group_open:
        lea     WORK_DB(a5),a4
        move.w  #STEP_NONE,DB_STEP(a4)
        bra.w   show_group

; group_tick: A5 = editor base, D7.w = events, D6.w = key. D0.l <> 0
; closes the screen (DB_NEXT says what follows).
group_tick:
        lea     WORK_DB(a5),a4
        move.w  DB_MODE(a4),d0
        cmpi.w  #DBM_MESSAGE,d0
        beq.w   message_tick
        cmpi.w  #DBM_ASK,d0
        beq.w   question_tick
        bsr.l   dialog_poll
        bmi.s   .stay
        cmpi.w  #CODE_ROW,d0
        bcc.w   club_chosen
        cmpi.w  #CODE_PREVIOUS,d0
        beq.s   .previous
        cmpi.w  #CODE_NEXT,d0
        beq.s   .next
        cmpi.w  #CODE_EDIT,d0
        beq.s   .edit
        cmpi.w  #CODE_SWAP,d0
        beq.s   .swap
        cmpi.w  #CODE_EXCHANGE,d0
        beq.s   .exchange
        cmpi.w  #CODE_COPY,d0
        beq.w   copy_chosen
        bra.w   back_chosen             ; BACK, Esc
.stay:
        moveq   #0,d0
        rts
.previous:
        subi.w  #CLUB_ROWS,DB_CLUB_PAGE(a4)
        bpl.s   .page
        clr.w   DB_CLUB_PAGE(a4)
.page:
        bra.w   show_group
.next:
        addi.w  #CLUB_ROWS,DB_CLUB_PAGE(a4)
        bra.w   show_group
.edit:
        move.w  #DBS_TEAM,DB_NEXT(a4)
        moveq   #1,d0
        rts
.swap:
        move.w  #PICK_SWAP,DB_PICK(a4)
        bra.w   show_group
.exchange:
        move.w  #PICK_EXCHANGE,DB_PICK(a4)
        bra.w   show_group

; ---------------------------------------------------------------------------
; Showing the screen
; ---------------------------------------------------------------------------
show_group:
        lea     WORK_DB(a5),a4
        move.w  #DBM_MAIN,DB_MODE(a4)
        bsr.w   build_texts
        bsr.w   disabled_mask           ; D2
        lea     group_dialog(pc),a0
        bsr.l   dialog_open
        move.w  DB_CLUB(a4),d2          ; the chosen club, marked
        bmi.s   .status
        sub.w   DB_CLUB_PAGE(a4),d2
        bmi.s   .status
        cmpi.w  #CLUB_ROWS,d2
        bcc.s   .status
        moveq   #UI_ACTIVE,d3
        suba.l  a0,a0
        bsr.l   dialog_set
.status:
        ; the status line for the screen's state
        lea     DB_STATUS(a4),a1
        clr.b   (a1)
        move.w  DB_PICK(a4),d0
        cmpi.w  #PICK_SWAP,d0
        beq.s   .swap
        cmpi.w  #PICK_EXCHANGE,d0
        beq.s   .exchange
        cmpi.w  #PICK_COPY_SLOT,d0
        beq.s   .copy
        move.w  DB_CLUB(a4),d0
        bmi.s   .choose
        bsr.w   club_record
        lea     TEAM_NAME(a0),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     chosen_text(pc),a0
        bra.s   .text
.choose:
        lea     choose_text(pc),a0
        bra.s   .text
.swap:
        lea     pick_swap_text(pc),a0
        bra.s   .text
.exchange:
        lea     pick_exchange_text(pc),a0
        bra.s   .text
.copy:
        lea     pick_copy_text(pc),a0
        bsr.l   text_copy
        lea     DB_COPY_RECORD+TEAM_NAME(a4),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     pick_copy_suffix(pc),a0
.text:
        bsr.l   text_copy
        lea     status_commands(pc),a0
        bsr.l   dialog_draw
        moveq   #0,d0
        rts

; disabled_mask: D2.l = buttons that cannot be chosen now. A4 = WORK_DB.
disabled_mask:
        movem.l d0-d1,-(sp)
        moveq   #0,d2
        moveq   #CLUB_ROWS-1,d1
.rows:
        move.w  DB_CLUB_PAGE(a4),d0
        add.w   d1,d0
        cmp.w   DB_COUNT(a4),d0
        bcs.s   .on
        bset    d1,d2
.on:
        dbf     d1,.rows
        tst.w   DB_CLUB_PAGE(a4)
        bne.s   .previous
        bset    #INDEX_PREVIOUS,d2
.previous:
        move.w  DB_CLUB_PAGE(a4),d0
        addi.w  #CLUB_ROWS,d0
        cmp.w   DB_COUNT(a4),d0
        bcs.s   .next
        bset    #INDEX_NEXT,d2
.next:
        tst.w   DB_PICK(a4)
        bne.s   .picking
        tst.w   DB_CLUB(a4)
        bpl.s   .national
.picking:
        bset    #INDEX_EDIT,d2
        bset    #INDEX_SWAP,d2
        bset    #INDEX_EXCHANGE,d2
        bset    #INDEX_COPY,d2
.national:
        cmpi.w  #NATIONAL_FIRST,DB_GROUP(a4)
        bcs.s   .done
        bset    #INDEX_SWAP,d2
        bset    #INDEX_COPY,d2
.done:
        movem.l (sp)+,d0-d1
        rts

; build_texts: the title, the row labels and the information line.
build_texts:
        movem.l d0-d7/a0-a3,-(sp)
        lea     DB_TITLE(a4),a1
        move.w  DB_GROUP(a4),d0
        bsr.l   db_group_name
        moveq   #0,d6                   ; row
.row:
        move.w  d6,d0
        mulu.w  #DB_ROW_SIZE,d0
        lea     DB_ROWS(a4,d0.l),a1
        clr.b   (a1)
        move.w  DB_CLUB_PAGE(a4),d7
        add.w   d6,d7
        cmp.w   DB_COUNT(a4),d7
        bcc.s   .next
        move.w  d7,d0
        bsr.w   club_record             ; A0 = record
        cmpi.w  #NATIONAL_FIRST,DB_GROUP(a4)
        bcc.s   .name
        moveq   #0,d0
        move.b  TEAM_DIVISION(a0),d0
        bsr.l   text_decimal
        move.b  #' ',(a1)+
.name:
        lea     TEAM_NAME(a0),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
.next:
        addq.w  #1,d6
        cmpi.w  #CLUB_ROWS,d6
        bcs.s   .row
        lea     DB_INFO(a4),a1
        move.w  DB_COUNT(a4),d0
        bsr.l   text_decimal
        lea     clubs_text(pc),a0
        cmpi.w  #NATIONAL_FIRST,DB_GROUP(a4)
        bcs.s   .kind
        lea     teams_text(pc),a0
.kind:
        bsr.l   text_copy
        tst.w   DB_DIRTY(a4)
        beq.s   .done
        lea     changed_text(pc),a0
        bsr.l   text_copy
.done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; club_pair: A2 = the record of club DB_CLUB, A0 = that of DB_SECOND.
; Changes D0.
club_pair:
        move.w  DB_CLUB(a4),d0
        bsr.s   club_record
        movea.l a0,a2
        move.w  DB_SECOND(a4),d0
; club_record: D0.w = ordinal. A0 = its record in the working group.
club_record:
        move.l  d0,-(sp)
        mulu.w  #TEAM_SIZE,d0
        lea     GROUP_WORK_OFFSET+GROUP_COUNT_SIZE(a5),a0
        adda.l  d0,a0
        move.l  (sp)+,d0
        rts

; ---------------------------------------------------------------------------
; Choosing a club
; ---------------------------------------------------------------------------
; club_chosen: D0.w = CODE_ROW + row.
club_chosen:
        subi.w  #CODE_ROW,d0
        add.w   DB_CLUB_PAGE(a4),d0
        move.w  DB_PICK(a4),d1
        beq.s   .choose
        cmpi.w  #PICK_COPY_SLOT,d1
        beq.w   ask_copy
        cmp.w   DB_CLUB(a4),d0
        beq.s   .same
        move.w  d0,DB_SECOND(a4)
        cmpi.w  #PICK_SWAP,d1
        beq.w   ask_swap
        bra.w   ask_exchange
.same:
        lea     pick_title(pc),a0
        bsr.l   message_title
        lea     another_club_line(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        bra.w   open_message
.choose:
        move.w  d0,DB_CLUB(a4)          ; the screen is drawn with its mark
        bra.w   show_group

; ask_swap: the second club of a division swap is DB_SECOND.
ask_swap:
        bsr.w   club_pair
        movea.l a0,a3
        move.b  TEAM_DIVISION(a2),d0
        cmp.b   TEAM_DIVISION(a3),d0
        bne.s   .ask
        lea     swap_title(pc),a0
        bsr.l   message_title
        lea     same_division_lines(pc),a0
        moveq   #0,d0
        bsr.l   message_lines
        clr.w   DB_PICK(a4)
        bra.w   open_message
.ask:
        lea     swap_title(pc),a0
        bsr.l   message_title
        movea.l a2,a0
        movea.l a3,a1
        moveq   #0,d0
        bsr.w   division_line
        movea.l a3,a0
        movea.l a2,a1
        moveq   #1,d0
        bsr.w   division_line
        lea     swap_line(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        move.w  #STEP_SWAP,DB_STEP(a4)
        bra.w   open_question

; division_line: A0 = club, A1 = the club whose division it takes, D0.w =
; message line: <CLUB>: DIVISION a TO b.
division_line:
        movem.l d0-d1/a0-a2,-(sp)
        movea.l a1,a2
        lea     DB_STATUS(a4),a1
        move.l  a0,-(sp)
        lea     TEAM_NAME(a0),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     division_text(pc),a0
        bsr.l   text_copy
        movea.l (sp)+,a0
        moveq   #0,d0
        move.b  TEAM_DIVISION(a0),d0
        bsr.l   text_decimal
        lea     to_text(pc),a0
        bsr.l   text_copy
        move.b  TEAM_DIVISION(a2),d0
        bsr.l   text_decimal
        lea     DB_STATUS(a4),a0
        move.l  (sp),d0
        bsr.l   message_line
        movem.l (sp)+,d0-d1/a0-a2
        rts

; ask_exchange: the second club of an exchange is DB_SECOND.
ask_exchange:
        lea     exchange_title(pc),a0
        bsr.l   message_title
        move.w  DB_CLUB(a4),d0
        moveq   #0,d1
        bsr.w   name_line
        move.w  DB_SECOND(a4),d0
        moveq   #1,d1
        bsr.w   name_line
        lea     exchange_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        move.w  #STEP_EXCHANGE,DB_STEP(a4)
        bra.w   open_question

; name_line: D0.w = ordinal, D1.w = message line. The club's name.
name_line:
        movem.l d0-d1/a0,-(sp)
        bsr.w   club_record
        lea     TEAM_NAME(a0),a0
        lea     DB_STATUS(a4),a1
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     DB_STATUS(a4),a0
        move.w  d1,d0
        bsr.l   message_line
        movem.l (sp)+,d0-d1/a0
        rts

; ask_copy: D0.w = the destination club of a copy.
ask_copy:
        move.w  d0,DB_SECOND(a4)
        lea     copy_title(pc),a0
        bsr.l   message_title
        lea     DB_STATUS(a4),a1        ; <SOURCE> (<ITS COUNTRY>)
        lea     DB_COPY_RECORD+TEAM_NAME(a4),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     open_text(pc),a0
        bsr.l   text_copy
        move.w  DB_COPY_GROUP(a4),d0
        bsr.l   db_group_name
        move.b  #')',(a1)+
        clr.b   (a1)
        lea     DB_STATUS(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     DB_STATUS(a4),a1        ; REPLACES <DEST> (<COUNTRY>)
        lea     replaces_text(pc),a0
        bsr.l   text_copy
        move.w  DB_SECOND(a4),d0
        bsr.w   club_record
        lea     TEAM_NAME(a0),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     open_text(pc),a0
        bsr.l   text_copy
        move.w  DB_GROUP(a4),d0
        bsr.l   db_group_name
        move.b  #')',(a1)+
        clr.b   (a1)
        lea     DB_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     copy_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        move.w  #STEP_COPY,DB_STEP(a4)
        bra.w   open_question

; ---------------------------------------------------------------------------
; COPY TO COUNTRY and BACK
; ---------------------------------------------------------------------------
; copy_chosen: the chosen club becomes the source; the destination group is
; chosen on the database screen. A copy starts from a saved working group,
; since the working group is replaced by the destination.
copy_chosen:
        tst.w   DB_DIRTY(a4)
        beq.s   .copy
        lea     copy_title(pc),a0
        bsr.l   message_title
        lea     save_first_lines(pc),a0
        moveq   #0,d0
        bsr.l   message_lines
        bra.w   open_message
.copy:
        move.w  DB_CLUB(a4),d0
        bsr.w   club_record
        lea     DB_COPY_RECORD(a4),a1
        move.w  #TEAM_SIZE/4-1,d0
.long:
        move.l  (a0)+,(a1)+
        dbf     d0,.long
        move.w  DB_GROUP(a4),DB_COPY_GROUP(a4)
        move.w  #PICK_COPY_COUNTRY,DB_PICK(a4)
        move.w  #DBS_MAIN,DB_NEXT(a4)
        moveq   #1,d0
        rts

; back_chosen: BACK or Esc ends a choice of a second club or a copy;
; otherwise the database screen.
back_chosen:
        tst.w   DB_PICK(a4)
        beq.s   .back
        clr.w   DB_PICK(a4)
        bra.w   show_group
.back:
        move.w  #DBS_MAIN,DB_NEXT(a4)
        moveq   #1,d0
        rts

; ---------------------------------------------------------------------------
; Messages and questions
; ---------------------------------------------------------------------------
; open_message, open_question: D0.l = 0 (message_open).
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
        bra.w   show_group
.stay:
        moveq   #0,d0
        rts

question_tick:
        bsr.l   message_poll
        bmi.s   .stay
        move.w  DB_STEP(a4),d1
        move.w  #STEP_NONE,DB_STEP(a4)
        tst.l   d0
        beq.s   .no
        cmpi.w  #STEP_SWAP,d1
        beq.s   .swap
        cmpi.w  #STEP_EXCHANGE,d1
        beq.s   .exchange
        cmpi.w  #STEP_COPY,d1
        beq.s   .copy
        bra.w   show_group
.stay:
        moveq   #0,d0
        rts
.no:
        cmpi.w  #STEP_COPY,d1           ; NO keeps the copy: another club may
        beq.w   show_group              ; be chosen, or BACK ends it
        clr.w   DB_PICK(a4)
        bra.w   show_group
.swap:
        bsr.w   club_pair
        move.b  TEAM_DIVISION(a2),d0
        move.b  TEAM_DIVISION(a0),TEAM_DIVISION(a2)
        move.b  d0,TEAM_DIVISION(a0)
        bra.s   .changed
.exchange:
        bsr.w   club_pair
        bsr.w   exchange_content        ; A0, A2 = the records
        bra.s   .changed
.copy:
        move.w  DB_SECOND(a4),d0
        bsr.w   club_record
        lea     DB_COPY_RECORD(a4),a2   ; the copy's source, not used again:
        bsr.w   exchange_content        ; its content goes into the club
        move.w  DB_SECOND(a4),DB_CLUB(a4)
.changed:
        clr.w   DB_PICK(a4)
        move.w  #1,DB_DIRTY(a4)
        bra.w   show_group

; exchange_content: A0, A2 = two records. Every byte but the identity (key
; and secondary index, TEAM_IDENTITY_SIZE bytes) and the division changes
; places. Preserves all registers.
exchange_content:
        movem.l d0-d1/a0/a2,-(sp)
        move.w  #TEAM_SIZE-1,d1
        moveq   #0,d0
.byte:
        cmpi.w  #TEAM_IDENTITY_SIZE,d0
        bcs.s   .kept
        cmpi.w  #TEAM_DIVISION,d0
        beq.s   .kept
        move.b  (a0,d0.w),-(sp)
        move.b  (a2,d0.w),(a0,d0.w)
        move.b  (sp)+,(a2,d0.w)
.kept:
        addq.w  #1,d0
        dbf     d1,.byte
        movem.l (sp)+,d0-d1/a0/a2
        rts

; ===========================================================================
; Data
; ===========================================================================
group_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_DB+DB_TITLE
        dc.l    body_commands
        dc.w    0,CODE_BACK,CLUB_ROWS+7
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
        dc.w    ROW_X,PAGE_Y,ROW_W,BUTTON_H,CODE_PREVIOUS,UI_NORMAL
        dc.l    previous_text
        dc.w    ROW_X2,PAGE_Y,ROW_W,BUTTON_H,CODE_NEXT,UI_NORMAL
        dc.l    next_text
        dc.w    ROW_X,ACTION_Y,96,BUTTON_H,CODE_EDIT,UI_NORMAL
        dc.l    edit_label
        dc.w    ROW_X+104,ACTION_Y,96,BUTTON_H,CODE_SWAP,UI_NORMAL
        dc.l    swap_label
        dc.w    ROW_X+208,ACTION_Y,96,BUTTON_H,CODE_EXCHANGE,UI_NORMAL
        dc.l    exchange_label
        dc.w    ROW_X,ACTION2_Y,200,BUTTON_H,CODE_COPY,UI_NORMAL
        dc.l    copy_label
        dc.w    ROW_X+208,ACTION2_Y,96,BUTTON_H,CODE_BACK,UI_NORMAL
        dc.l    back_text

body_commands:
        dc.w    UI_TEXT_AT,ROW_X,INFO_Y,ROW_W*2+8,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_INFO
        dc.w    UI_TEXT,ROW_X,HEAD_Y,ROW_W*2+8,UI_DIM,UI_LEFT
        dc.b    'DIVISION AND CLUB: CHOOSE ONE, THEN AN ACTION',0
        even
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,ROW_W*2+8,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,ROW_W*2+8,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_STATUS
        dc.w    UI_END

edit_label:             dc.b    '_EDIT TEAM',0
swap_label:             dc.b    '_DIVISION SWAP',0
exchange_label:         dc.b    'E_XCHANGE',0
copy_label:             dc.b    '_COPY TO COUNTRY',0
clubs_text:             dc.b    ' CLUBS',0
teams_text:             dc.b    ' NATIONAL TEAMS',0
changed_text:           dc.b    ', CHANGED (SAVE ON THE DATABASE SCREEN)',0
choose_text:            dc.b    'CHOOSE A CLUB',0
chosen_text:            dc.b    ': EDIT TEAM, SWAP, EXCHANGE OR COPY',0
pick_swap_text:         dc.b    'DIVISION SWAP: CHOOSE THE SECOND CLUB',0
pick_exchange_text:     dc.b    'EXCHANGE: CHOOSE THE SECOND CLUB',0
pick_copy_text:         dc.b    'COPY ',0
pick_copy_suffix:       dc.b    ': CHOOSE THE CLUB IT REPLACES',0
pick_title:             dc.b    'SECOND CLUB',0
another_club_line:      dc.b    'CHOOSE ANOTHER CLUB, OR BACK.',0
swap_title:             dc.b    'DIVISION SWAP',0
same_division_lines:    dc.b    'BOTH CLUBS PLAY IN THE SAME DIVISION.',0
                        dc.b    'A SWAP WOULD CHANGE NOTHING.',0
                        dc.b    0
division_text:          dc.b    ': DIVISION ',0
to_text:                dc.b    ' TO ',0
swap_line:              dc.b    'SWAP THE DIVISIONS?',0
exchange_title:         dc.b    'EXCHANGE',0
exchange_lines:         dc.b    'CHANGE PLACES. EACH PLACE KEEPS ITS DIVISION.',0
                        dc.b    'EXCHANGE THE TWO CLUBS?',0
                        dc.b    0
copy_title:             dc.b    'COPY TO COUNTRY',0
open_text:              dc.b    ' (',0
replaces_text:          dc.b    'REPLACES ',0
copy_lines:             dc.b    'WHICH KEEPS ITS PLACE AND DIVISION.',0
                        dc.b    'COPY THE CLUB?',0
                        dc.b    0
save_first_lines:       dc.b    'SAVE THE CHANGES TO THIS GROUP FIRST:',0
                        dc.b    'A COPY OPENS THE GROUP OF THE OTHER COUNTRY.',0
                        dc.b    0
        even
