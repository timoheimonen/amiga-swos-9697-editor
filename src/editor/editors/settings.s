; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; TEAM SETTINGS: the team's default tactic, its lineup order and its shirt
; numbers, edited in the team page's working copy, and the team's strength
; summary (read only):
;
;   AVG 31.4  GK 28  SKILLS 314/451  SPECIAL 14/20
;
; the average RATING of the outfield players in lineup roles 2-11 (tenths
; rounded half up, '-' without one), the RATING of role 1, and the skill
; points and specialty flags of the outfield players of roles 1-11 and of
; the whole squad. It follows every change of the screen; the player
; screen's changes show when the screen opens again. The host reference is
; custom_set.strength_line.
;
;   DEFAULT TACTIC  LEFT/RIGHT (or Fire) step through the builtin tactics
;                   0-11, the user slots 12-17 that are user-owned in this
;                   session (editors/tactics.s), the value the team had
;                   when the screen opened and the values team OK keeps
;                   (the original record's and IMPORT's), so a user slot
;                   from the data can be chosen again; a
;                   user slot is shown by its current name, with the note
;                   that the same tactic must be loaded into that slot
;                   after a restart
;   lineup rows     one row per role: roles 1-11 start, 12-16 are the
;                   substitutes. Fire on two rows swaps them: their places
;                   in the lineup (SWAP PLACES) or their shirt numbers
;                   (SWAP NUMBERS), so the lineup stays a permutation and the
;                   numbers stay 1-16, each once
;   OK              keeps the changes when role 1 is a goalkeeper
;   CANCEL, Esc     restores the working copy as it was when the screen
;                   opened

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    settings_screen
        xref    dialog_open, dialog_poll, dialog_set, dialog_draw
        xref    editor_base, editor_image
        xref    message_title, message_lines, message_open, message_poll
        xref    text_copy, text_copy_max, text_decimal, text_pad
        xref    team_screen_save, team_screen_cancel
        xref    ok_text, cancel_text

TOP                     equ 8
HEIGHT                  equ 256
ROW_X                   equ 24
ROW_W                   equ 304
ROW_H                   equ 9
TACTIC_Y                equ TOP+26
NOTE_Y                  equ TACTIC_Y+12
STRENGTH_Y              equ NOTE_Y+9
HEAD_Y                  equ TOP+56
LIST_Y                  equ HEAD_Y+10
STATUS_Y                equ LIST_Y+16*10+2
BUTTON_Y                equ TOP+HEIGHT-16
; Button codes
CODE_CANCEL             equ 0
CODE_TACTIC             equ 1
CODE_PLACES             equ 2
CODE_NUMBERS            equ 3
CODE_OK                 equ 4
CODE_ROW                equ 100         ; +role
; Button indices
INDEX_TACTIC            equ 0
INDEX_FIRST_ROW         equ 1
INDEX_PLACES            equ 17
INDEX_NUMBERS           equ 18
LABEL_TACTIC            equ 16          ; TS_LABELS index of the tactic row

        section .text,code

settings_screen:
        dc.l    settings_open
        dc.l    settings_tick

; ---------------------------------------------------------------------------
; settings_open: A5 = editor base.
; ---------------------------------------------------------------------------
settings_open:
        bsr.l   team_screen_save
        lea     WORK_TEAM_SCREEN(a5),a4
        move.w  #TSM_MAIN,TS_MODE(a4)
        move.w  #-1,TS_CHOICE(a4)
        clr.w   TS_SWAP(a4)
        lea     TS_TITLE(a4),a1
        lea     title_text(pc),a0
        bsr.l   text_copy
        lea     team_working_copy+TEAM_NAME,a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        bsr.w   build_labels
        bsr.w   build_strength
        bsr.w   status_default
        bra.w   show_settings

; ---------------------------------------------------------------------------
; settings_tick: A5 = editor base, D7.w = events, D6.w = key.
; D0.l <> 0 closes the screen.
; ---------------------------------------------------------------------------
settings_tick:
        lea     WORK_TEAM_SCREEN(a5),a4
        cmpi.w  #TSM_MESSAGE,TS_MODE(a4)
        bne.s   .main
        bsr.l   message_poll
        bmi.s   .stay
        move.w  #TSM_MAIN,TS_MODE(a4)
        bsr.w   show_settings
        bra.s   .stay
.main:
        bsr.l   dialog_poll
        bmi.s   .stay
        move.w  d0,d1
        andi.w  #DIALOG_CODE_MASK,d1
        cmpi.w  #CODE_ROW,d1
        bcc.w   row_chosen
        cmpi.w  #CODE_TACTIC,d1
        beq.s   tactic_step
        cmpi.w  #CODE_PLACES,d1
        beq.w   mode_places
        cmpi.w  #CODE_NUMBERS,d1
        beq.w   mode_numbers
        cmpi.w  #CODE_OK,d1
        beq.w   settings_ok
        cmpi.w  #CODE_CANCEL,d1
        beq.l   team_screen_cancel
.stay:
        moveq   #0,d0
        rts

; tactic_step: D0.w = code with DIALOG_DEC for the previous offered tactic,
; else the next one.
tactic_step:
        moveq   #1,d2
        btst    #14,d0                  ; DIALOG_DEC
        beq.s   .step
        moveq   #-1,d2
.step:
        moveq   #0,d1
        move.b  team_working_copy+TEAM_TACTIC,d1
        moveq   #TACTIC_USER_LAST+1,d3  ; at most one full turn
.next:
        add.w   d2,d1
        bpl.s   .low
        moveq   #TACTIC_USER_LAST,d1
.low:
        cmpi.w  #TACTIC_USER_LAST,d1
        bls.s   .offered
        moveq   #0,d1
.offered:
        cmpi.w  #TACTIC_BUILTIN_COUNT,d1
        bcs.s   .take
        cmp.b   WORK_TEAM+TE_SCREEN_BASE+TEAM_TACTIC(a5),d1
        beq.s   .take
        movea.l custom_team_original_pointer,a0 ; the values team OK keeps
        cmp.b   TEAM_TACTIC(a0),d1
        beq.s   .take
        tst.w   custom_team_imported
        beq.s   .owned
        tst.w   WORK_TEAM+TE_IMPORT_VALID(a5)
        beq.s   .owned
        cmp.b   WORK_TEAM+TE_IMPORT_BASE+TEAM_TACTIC(a5),d1
        beq.s   .take
.owned:
        move.w  d1,d0
        subi.w  #TACTIC_USER_FIRST,d0
        move.w  WORK_TACTICS+TT_OWNED(a5),d4
        btst    d0,d4                   ; a user-owned slot
        bne.s   .take
        dbf     d3,.next
        bra.s   .done
.take:
        move.b  d1,team_working_copy+TEAM_TACTIC
        bsr.w   build_tactic
        moveq   #INDEX_TACTIC,d2
        moveq   #UI_NORMAL,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        bsr.w   draw_note
.done:
        moveq   #0,d0
        rts

; row_chosen: D1.w = CODE_ROW + role.
row_chosen:
        subi.w  #CODE_ROW,d1
        move.w  TS_CHOICE(a4),d4
        bpl.s   .second
        move.w  d1,TS_CHOICE(a4)        ; first row
        move.w  d1,d2
        addq.w  #INDEX_FIRST_ROW,d2
        moveq   #UI_ACTIVE,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        lea     status_second(pc),a0
        bsr.w   set_status
        bra.w   .done
.second:
        move.w  #-1,TS_CHOICE(a4)
        cmp.w   d1,d4
        beq.s   .redraw                 ; the same row again: deselect
        lea     team_working_copy+TEAM_LINEUP,a0
        tst.w   TS_SWAP(a4)
        bne.s   .numbers
        move.b  (a0,d1.w),d2            ; swap the places of two roles
        move.b  (a0,d4.w),(a0,d1.w)
        move.b  d2,(a0,d4.w)
        bra.s   .rebuild
.numbers:
        move.b  (a0,d1.w),d2            ; swap the shirt numbers of two players
        andi.w  #PLAYER_COUNT-1,d2
        mulu.w  #PLAYER_SIZE,d2
        move.b  (a0,d4.w),d3
        andi.w  #PLAYER_COUNT-1,d3
        mulu.w  #PLAYER_SIZE,d3
        lea     team_working_copy+TEAM_PLAYERS+PLAYER_SHIRT,a1
        move.b  (a1,d2.w),d5
        move.b  (a1,d3.w),(a1,d2.w)
        move.b  d5,(a1,d3.w)
.rebuild:
        move.w  d1,d0
        bsr.w   build_row
        move.w  d4,d0
        bsr.w   build_row
        bsr.w   build_strength
        bsr.w   draw_strength
.redraw:
        move.w  d4,d2
        addq.w  #INDEX_FIRST_ROW,d2
        moveq   #UI_NORMAL,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        move.w  d1,d2
        addq.w  #INDEX_FIRST_ROW,d2
        bsr.l   dialog_set
        bsr.w   status_default
        bsr.w   draw_status
.done:
        moveq   #0,d0
        rts

mode_places:
        clr.w   TS_SWAP(a4)
        bra.s   mode_show
mode_numbers:
        move.w  #1,TS_SWAP(a4)
mode_show:
        bsr.w   draw_modes
        bsr.w   status_default
        bsr.w   draw_status
        moveq   #0,d0
        rts

; draw_modes: marks the chosen swap mode.
draw_modes:
        moveq   #INDEX_PLACES,d2
        moveq   #UI_ACTIVE,d3
        tst.w   TS_SWAP(a4)
        beq.s   .places
        moveq   #UI_NORMAL,d3
.places:
        suba.l  a0,a0
        bsr.l   dialog_set
        moveq   #INDEX_NUMBERS,d2
        eori.w  #UI_ACTIVE,d3
        bra.l   dialog_set

settings_ok:
        bsr.w   keeper_in_goal
        beq.s   .close
        lea     title_text_short(pc),a0
        bsr.l   message_title
        lea     no_keeper_lines(pc),a0
        moveq   #0,d0
        bsr.l   message_lines
        moveq   #MSG_OK,d0
        bsr.l   message_open
        move.w  #TSM_MESSAGE,TS_MODE(a4)
        moveq   #0,d0
        rts
.close:
        moveq   #1,d0
        rts

; keeper_in_goal: Z set when lineup role 0 is a goalkeeper. Changes D0/A3.
keeper_in_goal:
        moveq   #0,d0
        bsr.w   role_player
        move.b  PLAYER_FLAGS(a3),d0
        andi.b  #POSITION_MASK,d0
        rts

; ---------------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------------
show_settings:
        lea     settings_dialog(pc),a0
        moveq   #0,d2
        bsr.l   dialog_open
        bsr.w   draw_modes
        move.w  TS_CHOICE(a4),d2
        bmi.s   .texts
        addq.w  #INDEX_FIRST_ROW,d2
        moveq   #UI_ACTIVE,d3
        suba.l  a0,a0
        bsr.l   dialog_set
.texts:
        bsr.w   draw_note
        bsr.w   draw_strength
        bra.s   draw_status

draw_note:
        lea     note_commands(pc),a0
        bra.l   dialog_draw

draw_strength:
        lea     strength_commands(pc),a0
        bra.l   dialog_draw

draw_status:
        lea     status_commands(pc),a0
        bra.l   dialog_draw

; set_status: A0 = text for the status line, drawn now.
set_status:
        lea     TS_STATUS(a4),a1
        bsr.l   text_copy
        bra.s   draw_status

; status_default: the status line for the current state (not drawn).
status_default:
        lea     status_places(pc),a0
        tst.w   TS_SWAP(a4)
        beq.s   .keeper
        lea     status_numbers(pc),a0
.keeper:
        bsr.s   keeper_in_goal
        beq.s   .copy
        lea     status_no_keeper(pc),a0
.copy:
        lea     TS_STATUS(a4),a1
        bra.l   text_copy

; ---------------------------------------------------------------------------
; The strength summary
; ---------------------------------------------------------------------------
; build_strength: TS_STRENGTH from team_working_copy. A4 = screen state.
build_strength:
        movem.l d0-d7/a0-a3,-(sp)
        lea     team_working_copy,a2
        lea     TS_STRENGTH(a4),a1
        ; the average of the outfield players in roles 2-11
        lea     avg_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d3                   ; sum of ratings
        moveq   #0,d4                   ; players
        moveq   #1,d5                   ; role
.average:
        move.w  d5,d0
        bsr.w   role_player             ; A3 = player
        move.b  PLAYER_FLAGS(a3),d0
        andi.b  #POSITION_MASK,d0
        beq.s   .keeper
        moveq   #0,d0
        move.b  PLAYER_RATING(a3),d0
        add.l   d0,d3
        addq.w  #1,d4
.keeper:
        addq.w  #1,d5
        cmpi.w  #STARTING_ROLES,d5
        bcs.s   .average
        tst.w   d4
        bne.s   .tenths
        move.b  #'-',(a1)+
        bra.s   .goalkeeper
.tenths:
        move.l  d3,d0                   ; (20 * sum + n) / (2 * n)
        mulu.w  #20,d0
        add.l   d4,d0
        add.w   d4,d4
        divu.w  d4,d0
        andi.l  #$FFFF,d0
        divu.w  #10,d0
        bsr.l   text_decimal            ; whole part
        move.b  #'.',(a1)+
        swap    d0
        bsr.l   text_decimal            ; tenths
.goalkeeper:
        lea     keeper_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        bsr.w   role_player
        moveq   #0,d0
        move.b  PLAYER_RATING(a3),d0
        bsr.l   text_decimal
        ; the slots of the first eleven
        moveq   #0,d6                   ; mask of slots
        moveq   #STARTING_ROLES-1,d5
.eleven:
        moveq   #0,d0
        move.b  TEAM_LINEUP(a2,d5.w),d0
        andi.w  #PLAYER_COUNT-1,d0
        bset    d0,d6
        dbf     d5,.eleven
        lea     skills_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d7                   ; skill points
        bsr.s   strength_pair
        lea     specials_text(pc),a0
        bsr.l   text_copy
        moveq   #SKILL_SPECIALTY,d7     ; specialty flags
        bsr.s   strength_pair
        movem.l (sp)+,d0-d7/a0-a3
        rts

; strength_pair: A2 = team, D6 = the eleven's slots, D7.l = 0 for skill
; points, SKILL_SPECIALTY for specialty flags. Appends '<eleven>/<squad>'
; at A1. Changes D0-D5/A3.
strength_pair:
        moveq   #0,d3                   ; eleven
        moveq   #0,d4                   ; squad
        moveq   #PLAYER_COUNT-1,d5
.slot:
        move.w  d5,d0
        mulu.w  #PLAYER_SIZE,d0
        lea     TEAM_PLAYERS(a2,d0.w),a3
        move.b  PLAYER_FLAGS(a3),d0
        andi.b  #POSITION_MASK,d0
        beq.s   .next                   ; goalkeepers' skills are not counted
        move.l  PLAYER_SKILLS(a3),d1
        moveq   #0,d2                   ; this player's value
        moveq   #SKILL_COUNT-1,d0
.skill:
        tst.w   d7
        bne.s   .flag
        move.w  d1,-(sp)
        andi.w  #SKILL_MAX,d1
        add.w   d1,d2
        move.w  (sp)+,d1
        bra.s   .shift
.flag:
        btst    #3,d1
        beq.s   .shift
        addq.w  #1,d2
.shift:
        lsr.l   #4,d1
        dbf     d0,.skill
        add.w   d2,d4
        btst    d5,d6
        beq.s   .next
        add.w   d2,d3
.next:
        dbf     d5,.slot
        move.w  d3,d0
        bsr.l   text_decimal
        move.b  #'/',(a1)+
        move.w  d4,d0
        bra.l   text_decimal

; role_player: D0.w = lineup role. A3 = its player in team_working_copy.
; Changes D0.
role_player:
        lea     team_working_copy+TEAM_LINEUP,a3
        move.b  (a3,d0.w),d0
        andi.w  #PLAYER_COUNT-1,d0
        mulu.w  #PLAYER_SIZE,d0
        lea     team_working_copy+TEAM_PLAYERS,a3
        adda.w  d0,a3
        rts

; ---------------------------------------------------------------------------
; Labels
; ---------------------------------------------------------------------------
build_labels:
        bsr.w   build_tactic
        moveq   #0,d0
.row:
        bsr.w   build_row
        addq.w  #1,d0
        cmpi.w  #PLAYER_COUNT,d0
        bcs.s   .row
        rts

; build_tactic: the tactic row and the note line.
build_tactic:
        movem.l d0-d1/a0-a1,-(sp)
        lea     TS_LABELS+LABEL_TACTIC*TS_LABEL_SIZE(a4),a1
        lea     tactic_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.b  team_working_copy+TEAM_TACTIC,d0
        bsr.w   team_tactic_name        ; keeps D0
        move.b  #'>',(a1)+
        clr.b   (a1)
        lea     TS_DERIVED(a4),a1
        clr.b   (a1)
        cmpi.w  #TACTIC_USER_FIRST,d0
        bcs.s   .done
        lea     note_text(pc),a0
        bsr.l   text_copy
.done:
        movem.l (sp)+,d0-d1/a0-a1
        rts

; team_tactic_name: D0.w = tactic, appended at A1 as ' NAME ' (the name
; of the record the tactic table points to, 'USER n' style names of the
; user slots included); a value outside 0-17 as its number.
team_tactic_name:
        movem.l d0/a0,-(sp)
        move.b  #' ',(a1)+
        cmpi.w  #TACTIC_USER_LAST,d0
        bhi.s   .number
        lsl.w   #2,d0
        lea     tactic_pointer_table,a0
        movea.l (a0,d0.w),a0
        moveq   #TACTIC_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        bra.s   .space
.number:
        bsr.l   text_decimal
.space:
        move.b  #' ',(a1)+
        clr.b   (a1)
        movem.l (sp)+,d0/a0
        rts

; build_row: D0.w = role. Its label: role, shirt, position, name.
build_row:
        movem.l d0-d2/a0-a1,-(sp)
        move.w  d0,d2
        mulu.w  #TS_LABEL_SIZE,d0
        lea     TS_LABELS(a4,d0.w),a1
        move.w  d2,d0
        addq.w  #1,d0
        cmpi.w  #10,d0
        bcc.s   .role
        move.b  #' ',(a1)+
.role:
        bsr.l   text_decimal
        cmpi.w  #STARTING_ROLES,d0
        bls.s   .starter
        move.b  #'S',(a1)+              ; substitute
        bra.s   .player
.starter:
        move.b  #' ',(a1)+
.player:
        moveq   #0,d0
        lea     team_working_copy+TEAM_LINEUP,a0
        move.b  (a0,d2.w),d0
        andi.w  #PLAYER_COUNT-1,d0
        bsr.w   team_player_line
        movem.l (sp)+,d0-d2/a0-a1
        rts

; team_player_line: D0.w = physical slot of team_working_copy. Appends
; '  NO 12  RB  NAME' at A1.
team_player_line:
        movem.l d0-d2/a0,-(sp)
        mulu.w  #PLAYER_SIZE,d0
        lea     team_working_copy+TEAM_PLAYERS,a0
        adda.w  d0,a0
        move.l  a0,d2
        lea     number_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        movea.l d2,a0
        move.b  PLAYER_SHIRT(a0),d0
        cmpi.w  #10,d0
        bcc.s   .shirt
        move.b  #' ',(a1)+
.shirt:
        bsr.l   text_decimal
        move.b  #' ',(a1)+
        move.b  #' ',(a1)+
        movea.l d2,a0
        move.b  PLAYER_FLAGS(a0),d0
        lsr.b   #POSITION_SHIFT,d0
        andi.w  #POSITION_COUNT-1,d0
        lsl.w   #2,d0
        lea     position_labels,a0
        movea.l (a0,d0.w),a0
        move.l  a1,d1
        addq.l  #4,d1
        moveq   #2,d0
        bsr.l   text_copy_max
        move.l  d1,d0
        bsr.l   text_pad
        movea.l d2,a0
        lea     PLAYER_NAME(a0),a0
        moveq   #PLAYER_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        movem.l (sp)+,d0-d2/a0
        rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
LABEL_AT macro
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_LABELS+(\1)*TS_LABEL_SIZE
        endm
ROLE    macro
        dc.w    ROW_X,LIST_Y+\1*10,ROW_W,ROW_H,CODE_ROW+\1,DIALOG_ROW|UI_NORMAL
        LABEL_AT \1
        endm

settings_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_TITLE
        dc.l    settings_body
        dc.w    INDEX_TACTIC,CODE_CANCEL,21
        dc.w    ROW_X,TACTIC_Y,ROW_W,ROW_H,CODE_TACTIC,DIALOG_ROW|DIALOG_SPIN|UI_NORMAL
        LABEL_AT LABEL_TACTIC
        ROLE    0
        ROLE    1
        ROLE    2
        ROLE    3
        ROLE    4
        ROLE    5
        ROLE    6
        ROLE    7
        ROLE    8
        ROLE    9
        ROLE    10
        ROLE    11
        ROLE    12
        ROLE    13
        ROLE    14
        ROLE    15
        dc.w    ROW_X,BUTTON_Y,96,13,CODE_PLACES,UI_NORMAL
        dc.l    places_text
        dc.w    ROW_X+102,BUTTON_Y,96,13,CODE_NUMBERS,UI_NORMAL
        dc.l    numbers_text
        dc.w    ROW_X+204,BUTTON_Y,44,13,CODE_OK,UI_NORMAL
        dc.l    ok_text
        dc.w    ROW_X+252,BUTTON_Y,52,13,CODE_CANCEL,UI_NORMAL
        dc.l    cancel_text

settings_body:
        dc.w    UI_TEXT,ROW_X,TOP+15,ROW_W,UI_ACCENT,UI_LEFT
        dc.b    'LEFT/RIGHT CHANGES THE TACTIC',0
        even
        dc.w    UI_TEXT,ROW_X,HEAD_Y,ROW_W,UI_ACCENT,UI_LEFT
        dc.b    'ROLES 1-11 START, 12S-16S ARE THE SUBSTITUTES',0
        even
        dc.w    UI_RECT,ROW_X,LIST_Y+11*10-1,ROW_W,1,UI_DIM
        dc.w    UI_END

note_commands:
        dc.w    UI_RECT,ROW_X,NOTE_Y,ROW_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,NOTE_Y+1,ROW_W,UI_WARN,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_DERIVED
        dc.w    UI_END

strength_commands:
        dc.w    UI_RECT,ROW_X,STRENGTH_Y,ROW_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STRENGTH_Y+1,ROW_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_STRENGTH
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,ROW_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,ROW_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_STATUS
        dc.w    UI_END

title_text:             dc.b    'TEAM SETTINGS: ',0
avg_text:               dc.b    'AVG ',0
keeper_text:            dc.b    '  GK ',0
skills_text:            dc.b    '  SKILLS ',0
specials_text:          dc.b    '  SPECIAL ',0
title_text_short:       dc.b    'TEAM SETTINGS',0
tactic_text:            dc.b    'DEFAULT TACTIC      <',0
note_text:              dc.b    'AFTER A RESTART LOAD THE SAME .TAC INTO THIS SLOT',0
number_text:            dc.b    '  NO ',0
places_text:            dc.b    'SWAP _PLACES',0
numbers_text:           dc.b    'SWAP _NUMBERS',0
status_places:          dc.b    'FIRE ON TWO ROWS SWAPS THEIR PLACES IN THE LINEUP',0
status_numbers:         dc.b    'FIRE ON TWO ROWS SWAPS THEIR SHIRT NUMBERS',0
status_second:          dc.b    'NOW CHOOSE THE SECOND ROW',0
status_no_keeper:       dc.b    'ROLE 1 MUST BE A GOALKEEPER',0
no_keeper_lines:        dc.b    'ROLE 1 STARTS IN GOAL.',0
                        dc.b    'SWAP A GOALKEEPER INTO ROLE 1 FIRST.',0
                        dc.b    0
        even
