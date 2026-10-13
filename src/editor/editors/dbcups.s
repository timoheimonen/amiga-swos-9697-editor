; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The cups screen of EDIT DATABASE (EUROPEAN CUPS): the participants of
; the three European club cups in the saved set, read only. Each cup shows
; its clubs in place order, two columns of sixteen, and whether they are
; the set's own copies (its participants and its squads) or the game's
; 96/97 copies (the saved set changes none of them). Participant lists are
; written on the host; a SAVE of a group refreshes the copies of its clubs.
;
;   PREVIOUS CUP, NEXT CUP   the other cups
;   BACK, Esc                the database screen

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    cups_screen, cups_dialog
        xref    editor_image
        xref    dialog_open, dialog_poll
        xref    text_copy, text_copy_max, text_decimal
        xref    db_cup_copy, db_cup_teams
        xref    back_text

TOP                     equ 8
HEIGHT                  equ 256
INFO_Y                  equ TOP+15
HEAD_Y                  equ INFO_Y+12
ROW_Y                   equ HEAD_Y+12
ROW_X                   equ DIALOG_BAND_X+8
ROW_W                   equ 148
ROW_X2                  equ ROW_X+ROW_W+8
COLUMN_ROWS             equ 16
BUTTON_Y                equ ROW_Y+COLUMN_ROWS*10+8
BUTTON_W                equ 96
BUTTON_H                equ 13
; Button codes
CODE_BACK               equ 0
CODE_PREVIOUS           equ 1
CODE_NEXT               equ 2

        section .text,code

cups_screen:
        dc.l    cups_open
        dc.l    cups_tick

; cups_open: A5 = editor base.
cups_open:
        lea     WORK_DB(a5),a4
        bra.s   show_cup

; cups_tick: A5 = editor base, D7.w = events, D6.w = key. D0.l <> 0 closes
; the screen.
cups_tick:
        lea     WORK_DB(a5),a4
        bsr.l   dialog_poll
        bmi.s   .stay
        cmpi.w  #CODE_PREVIOUS,d0
        beq.s   .previous
        cmpi.w  #CODE_NEXT,d0
        beq.s   .next
        moveq   #1,d0                   ; BACK, Esc
        rts
.previous:
        subq.w  #1,DB_CUP(a4)
        bpl.s   show_cup
        move.w  #CUP_COUNT-1,DB_CUP(a4)
        bra.s   show_cup
.next:
        addq.w  #1,DB_CUP(a4)           ; load_cup turns CUP_COUNT into 0
        bra.s   show_cup
.stay:
        moveq   #0,d0
        rts

; show_cup: draws the screen with cup DB_CUP. D0.l = 0 (dialog_open).
show_cup:
        bsr.s   load_cup
        lea     cups_dialog(pc),a0
        moveq   #0,d2
        bra.l   dialog_open

; load_cup: the title, the information line and the rows of cup DB_CUP.
; A4 = WORK_DB.
load_cup:
        movem.l d0-d7/a0-a3,-(sp)
        move.w  DB_CUP(a4),d7
        cmpi.w  #CUP_COUNT,d7
        bcs.s   .cup
        moveq   #0,d7
        move.w  d7,DB_CUP(a4)
.cup:
        lea     DB_TITLE(a4),a1
        move.w  d7,d0
        add.w   d0,d0
        lea     cup_titles(pc),a0
        adda.w  (a0,d0.w),a0
        bsr.l   text_copy
        ; the rows are empty until the copy is read
        lea     DB_CUP_ROWS(a4),a0
        moveq   #CUP_MAX_TEAMS-1,d0
.clear:
        clr.b   (a0)
        lea     DB_CUP_ROW_SIZE(a0),a0
        dbf     d0,.clear
        addi.w  #COPY_EUROCUP,d7
        move.w  d7,d0
        bsr.l   db_cup_copy             ; team_group_buffer, D1 = 1 for the set's
        lea     DB_INFO(a4),a1
        beq.s   .read
        lea     unreadable_text(pc),a0
        bsr.l   text_copy
        bra.s   .done
.read:
        lea     original_text(pc),a0
        tst.w   d1
        beq.s   .source
        lea     set_text(pc),a0
.source:
        bsr.l   text_copy
        move.w  d7,d0
        bsr.l   db_cup_teams
        move.w  d0,d5                   ; teams
        lea     team_group_buffer,a2
        lea     DB_CUP_ROWS(a4),a3
        moveq   #0,d6                   ; place - 1
.row:
        movea.l a3,a1
        move.w  d6,d0
        addq.w  #1,d0
        cmpi.w  #10,d0
        bcc.s   .number
        move.b  #' ',(a1)+
.number:
        bsr.l   text_decimal
        move.b  #' ',(a1)+
        lea     TEAM_NAME(a2),a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     TEAM_SIZE(a2),a2
        lea     DB_CUP_ROW_SIZE(a3),a3
        addq.w  #1,d6
        cmp.w   d5,d6
        bcs.s   .row
.done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
ROW     macro                           ; \1 = place - 1
        if \1<COLUMN_ROWS
        dc.w    UI_TEXT_AT,ROW_X,ROW_Y+\1*10,ROW_W,UI_INK,UI_LEFT_CLIPPED
        else
        dc.w    UI_TEXT_AT,ROW_X2,ROW_Y+(\1-COLUMN_ROWS)*10,ROW_W,UI_INK,UI_LEFT_CLIPPED
        endif
        dc.l    editor_image+WORK_DB+DB_CUP_ROWS+\1*DB_CUP_ROW_SIZE
        endm

cups_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_DB+DB_TITLE
        dc.l    body_commands
        dc.w    2,CODE_BACK,3
        dc.w    ROW_X,BUTTON_Y,BUTTON_W,BUTTON_H,CODE_PREVIOUS,UI_NORMAL
        dc.l    previous_label
        dc.w    ROW_X+BUTTON_W+8,BUTTON_Y,BUTTON_W,BUTTON_H,CODE_NEXT,UI_NORMAL
        dc.l    next_label
        dc.w    ROW_X+2*(BUTTON_W+8),BUTTON_Y,BUTTON_W,BUTTON_H,CODE_BACK,UI_NORMAL
        dc.l    back_text

body_commands:
        dc.w    UI_TEXT_AT,ROW_X,INFO_Y,ROW_W*2+8,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DB+DB_INFO
        dc.w    UI_TEXT,ROW_X,HEAD_Y,ROW_W*2+8,UI_DIM,UI_LEFT
        dc.b    'READ ONLY. CUPS.CSV ON THE HOST SETS THE LISTS.',0
        even
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
        ROW     24
        ROW     25
        ROW     26
        ROW     27
        ROW     28
        ROW     29
        ROW     30
        ROW     31
        dc.w    UI_END

cup_titles:
        dc.w    title_eurocup-cup_titles
        dc.w    title_eurocwc-cup_titles
        dc.w    title_uefacup-cup_titles
title_eurocup:          dc.b    'EUROPEAN CHAMPIONS CUP',0
title_eurocwc:          dc.b    'EUROPEAN CUP-WINNERS CUP',0
title_uefacup:          dc.b    'UEFA CUP',0
set_text:               dc.b    'THE SAVED SET',39,'S PARTICIPANTS AND SQUADS',0
original_text:          dc.b    'AS IN 96/97: THE SAVED SET CHANGES NONE OF THEM',0
unreadable_text:        dc.b    'THE COPY CANNOT BE READ: FILE DAMAGED',0
previous_label:         dc.b    '_PREVIOUS CUP',0
next_label:             dc.b    '_NEXT CUP',0
        even
