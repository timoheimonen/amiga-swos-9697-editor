; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; RULES on the DIY setup pages: every rule of the competition as the page
; holds it, with what the page does not show (the match dates of each group
; stage, the matchdays of a league, the teams a definition holds), and the
; verdict of the same checks CHOOSE TEAMS makes before it starts the
; competition: READY TO START, or the reason the game cannot run it.
;
;   rules_league, rules_cup, rules_tournament   the entry actions
;   rules_summary   D0.w = family: the summary lines of DF_BODY in DF_LINES
;                   (also the first line of SAVE DEFINITION)

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    rules_league, rules_cup, rules_tournament, rules_summary
        xdef    rules_dialog
        xref    editor_base, editor_image
        xref    screen_run
        xref    dialog_open, dialog_poll, dialog_draw
        xref    definition_capture_check, definition_problem_text
        xref    definition_group_dates
        xref    text_copy, text_decimal
        xref    ok_text

TOP                     equ 8
HEIGHT                  equ 256
LINE_X                  equ DIALOG_BAND_X+8
LINE_W                  equ DIALOG_BAND_WIDTH-16
LINE_Y                  equ TOP+16
VERDICT_Y               equ LINE_Y+DF_LINE_COUNT*10+2
BUTTON_Y                equ TOP+HEIGHT-18

        section .text,code

rules_league:
        moveq   #FAMILY_LEAGUE,d0
        bra.s   rules_action
rules_cup:
        moveq   #FAMILY_CUP,d0
        bra.s   rules_action
rules_tournament:
        moveq   #FAMILY_TOURNAMENT,d0
; rules_action: D0.w = family (an entry action).
rules_action:
        movea.l editor_base,a5
        move.w  d0,d7
        bsr.l   definition_capture_check ; D0-D3: the verdict
        move.w  d0,WORK_DEF+DF_CHECK(a5)
        move.l  d0,d6
        lea     WORK_DEF+DF_TITLE(a5),a1
        lea     title_text(pc),a0
        bsr.l   text_copy
        lea     WORK_DEF+DF_BODY+DR_NAME(a5),a0
        bsr.l   text_copy
        move.w  d7,d0
        bsr.w   rules_summary
        move.l  d6,d0
        lea     WORK_DEF+DF_STATUS(a5),a1
        lea     ready_text(pc),a0
        tst.l   d0
        beq.s   .verdict
        bsr.l   definition_problem_text
        bra.s   .run
.verdict:
        bsr.l   text_copy
.run:
        lea     rules_screen(pc),a0
        bra.l   screen_run

rules_screen:
        dc.l    rules_open
        dc.l    rules_tick

rules_open:
        lea     rules_dialog(pc),a0
        moveq   #0,d2
        bsr.l   dialog_open
        lea     verdict_ok(pc),a0
        tst.w   WORK_DEF+DF_CHECK(a5)
        beq.s   .draw
        lea     verdict_bad(pc),a0
.draw:
        bra.l   dialog_draw

; rules_tick: the one button and Esc give code 0, so D0.l = -1 + 1 stays
; and 0 + 1 closes.
rules_tick:
        bsr.l   dialog_poll
        addq.l  #1,d0
        rts

; ---------------------------------------------------------------------------
; rules_summary: D0.w = family, A5 = editor base. The lines of the rules in
; DF_BODY (and the teams held for that family) in DF_LINES; the rest empty.
; Preserves all registers.
; ---------------------------------------------------------------------------
rules_summary:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  d0,d7
        lea     WORK_DEF+DF_LINES(a5),a0
        move.w  #DF_LINE_COUNT*DF_LINE_SIZE/2-1,d1
.clear:
        clr.w   (a0)+
        dbf     d1,.clear
        lea     WORK_DEF+DF_BODY(a5),a2
        moveq   #0,d6                   ; next line
        cmpi.w  #FAMILY_CUP,d7
        beq.w   .cup
        bhi.w   .tournament
; league
        bsr.w   line
        lea     league_of(pc),a0
        bsr.l   text_copy
        move.w  DR_TEAMS(a2),d0
        bsr.l   text_decimal
        lea     teams_text(pc),a0
        bsr.l   text_copy
        bsr.w   line
        lea     meet_text(pc),a0
        bsr.l   text_copy
        move.w  DR_L_REPEAT(a2),d0
        bsr.w   times
        lea     comma(pc),a0
        bsr.l   text_copy
        move.w  DR_L_POINTS(a2),d0
        bsr.l   text_decimal
        lea     points_win(pc),a0
        bsr.l   text_copy
        move.w  DR_TEAMS(a2),d0
        cmpi.w  #2,d0
        bcs.w   .common
        bsr.w   line
        lea     matchdays_text(pc),a0
        bsr.l   text_copy
        move.w  DR_L_REPEAT(a2),d2
        bsr.l   definition_group_dates
        bsr.l   text_decimal
        lea     matches_text(pc),a0
        bsr.l   text_copy
        move.w  DR_TEAMS(a2),d0
        lsr.w   #1,d0
        bsr.l   text_decimal
        bra.w   .common
.cup:
        lea     cup_of(pc),a0
        lea     rounds_text(pc),a6
        move.w  DR_C_ROUNDS(a2),d1
        move.w  DR_C_AWAY(a2),d2
        bsr.w   head_line
        moveq   #0,d5
.round:
        cmp.w   DR_C_ROUNDS(a2),d5
        bcc.w   .common
        cmpi.w  #CUP_ROUNDS_MAX,d5
        bcc.w   .common
        lea     round_text(pc),a0
        bsr.w   numbered
        move.w  d5,d0
        add.w   d0,d0
        move.w  DR_C_LEGS(a2,d0.w),d1
        move.w  DR_C_EXTRA(a2,d0.w),d2
        move.w  DR_C_PENALTIES(a2,d0.w),d3
        bsr.w   knockout_rules
        addq.w  #1,d5
        bra.s   .round
.tournament:
        lea     tournament_of(pc),a0
        lea     stages_text(pc),a6
        move.w  DR_T_STAGES(a2),d1
        move.w  DR_T_AWAY(a2),d2
        bsr.w   head_line
        lea     DR_T_STAGE(a2),a3
        moveq   #0,d5
.stage:
        cmp.w   DR_T_STAGES(a2),d5
        bcc.w   .common
        cmpi.w  #MAX_STAGES,d5
        bcc.w   .common
        lea     stage_text(pc),a0
        bsr.w   numbered
        tst.w   DS_GROUPS(a3)
        bne.s   .groups
        lea     knockout_of(pc),a0
        bsr.l   text_copy
        move.w  DS_TEAMS(a3),d0
        bsr.l   text_decimal
        bra.s   .through
.groups:
        move.w  DS_GROUPS(a3),d0
        bsr.l   text_decimal
        lea     groups_of(pc),a0
        cmpi.w  #1,d0
        bne.s   .group_word
        lea     group_of(pc),a0
.group_word:
        bsr.l   text_copy
        move.w  DS_GROUP_TEAMS(a3),d0
        bsr.l   text_decimal
.through:
        lea     comma(pc),a0
        bsr.l   text_copy
        move.w  DS_THROUGH(a3),d0
        cmpi.w  #1,d0
        bne.s   .go_on
        lea     one_winner(pc),a0
        bsr.l   text_copy
        bra.s   .seeded
.go_on:
        bsr.l   text_decimal
        lea     go_on(pc),a0
        bsr.l   text_copy
.seeded:
        tst.w   DS_SEEDED(a3)
        beq.s   .stage_rules
        lea     seeded_text(pc),a0
        bsr.l   text_copy
.stage_rules:
        bsr.w   line
        lea     indent(pc),a0
        bsr.l   text_copy
        tst.w   DS_GROUPS(a3)
        bne.s   .group_rules
        move.w  DS_LEGS(a3),d1
        move.w  DS_EXTRA(a3),d2
        move.w  DS_PENALTIES(a3),d3
        bsr.w   knockout_rules
        bra.s   .next_stage
.group_rules:
        lea     meet_text(pc),a0
        bsr.l   text_copy
        move.w  DS_REPEAT(a3),d0
        bsr.w   times
        lea     comma(pc),a0
        bsr.l   text_copy
        move.w  DS_POINTS(a3),d0
        bsr.l   text_decimal
        lea     points_text(pc),a0
        bsr.l   text_copy
        move.w  DS_GROUP_TEAMS(a3),d0
        cmpi.w  #2,d0
        bcs.s   .next_stage
        move.w  DS_REPEAT(a3),d2
        bsr.l   definition_group_dates
        bsr.l   text_decimal
        lea     dates_text(pc),a0
        bsr.l   text_copy
.next_stage:
        lea     DS_SIZE(a3),a3
        addq.w  #1,d5
        bra.w   .stage
.common:
        bsr.w   line
        lea     substitutes_text(pc),a0
        bsr.l   text_copy
        tst.w   DR_BENCH(a2)
        bne.s   .bench
        lea     none_text(pc),a0
        bsr.l   text_copy
        bra.s   .pitch
.bench:
        move.w  DR_SUBS(a2),d0
        bsr.l   text_decimal
        lea     from_text(pc),a0
        bsr.l   text_copy
        move.w  DR_BENCH(a2),d0
        bsr.l   text_decimal
.pitch:
        bsr.w   line
        lea     pitch_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        lea     season_word(pc),a0
        tst.w   DR_PITCH_MODE(a2)
        bne.s   .pitch_name
        move.w  DR_PITCH_TYPE(a2),d0
        addq.w  #1,d0
        cmpi.w  #PITCH_TYPE_MAX+1,d0
        bhi.s   .season
        lea     pitch_names(pc),a0
.pitch_name:
        bsr.w   nth_copy
.season:
        bsr.w   line
        lea     season_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.b  DR_START(a2),d0
        bsr.w   month
        lea     to_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.b  DR_END(a2),d0
        bsr.w   month
        bsr.w   line
        lea     teams_line(pc),a0
        bsr.l   text_copy
        lea     teams_on_start(pc),a0
        tst.w   WORK_DEF+DF_TEAMS(a5)
        beq.s   .teams_text
        cmp.w   WORK_DEF+DF_FAMILY(a5),d7
        bne.s   .teams_text
        move.w  WORK_DEF+DF_TEAMS(a5),d0
        cmp.w   WORK_DEF+DF_BODY+DR_TEAMS(a5),d0
        bne.s   .teams_text             ; as CHOOSE TEAMS: a list of another size is not used
        bsr.l   text_decimal
        lea     teams_held(pc),a0
.teams_text:
        bsr.l   text_copy
        movem.l (sp)+,d0-d7/a0-a6
        rts

; line: A1 = the next line of DF_LINES (D6 = its number, advanced); the
; last line is reused when all are taken.
line:
        move.l  d0,-(sp)
        move.w  d6,d0
        cmpi.w  #DF_LINE_COUNT-1,d0
        bls.s   .take
        moveq   #DF_LINE_COUNT-1,d0
.take:
        mulu.w  #DF_LINE_SIZE,d0
        lea     WORK_DEF+DF_LINES(a5,d0.l),a1
        clr.b   (a1)
        addq.w  #1,d6
        move.l  (sp)+,d0
        rts

; numbered: A0 = word. A new line "<word> n: " for D5.w = n - 1.
numbered:
        bsr.s   line
        bsr.l   text_copy
        move.w  d5,d0
        addq.w  #1,d0
        bsr.l   text_decimal
        lea     colon(pc),a0
        bra.l   text_copy

; head_line: A0 = opening, A6 = the unit of D1.w, D2.w = away goals rule.
; The line "<opening>n TEAMS IN <D1><unit>", then the away goals line.
head_line:
        bsr.s   line
        bsr.l   text_copy
        move.w  DR_TEAMS(a2),d0
        bsr.l   text_decimal
        lea     teams_in(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        bsr.l   text_decimal
        movea.l a6,a0
        bsr.l   text_copy
        move.w  d2,d0
        ; then the away goals line
        bsr.s   line
        lea     away_text(pc),a0
        bsr.l   text_copy
        cmpi.w  #RULE_ENUM_MAX,d0
        bhi.s   rules_done
        lea     away_names(pc),a0
        bra.s   nth_copy

; times: D0.w = count, appended as "1 TIME" or "n TIMES".
times:
        lea     time_text(pc),a0
; plural: D0.w = count, A0 = its unit, appended as "n UNIT" with an S
; unless n is 1.
plural:
        bsr.l   text_decimal
        bsr.l   text_copy
        cmpi.w  #1,d0
        beq.s   rules_done
        move.b  #'S',(a1)+
        clr.b   (a1)
rules_done:
        rts

; knockout_rules: D1.w = legs, D2.w = extra time, D3.w = penalties, as
; "1 LEG, EXTRA TIME, PENALTIES" in the native words.
knockout_rules:
        move.w  d1,d0
        lea     leg_text(pc),a0
        bsr.s   plural
        lea     comma(pc),a0
        bsr.l   text_copy
        move.w  d2,d0
        cmpi.w  #RULE_ENUM_MAX,d0
        bhi.s   .penalties
        lea     extra_names(pc),a0
        bsr.s   nth_copy
.penalties:
        lea     comma(pc),a0
        bsr.l   text_copy
        move.w  d3,d0
        cmpi.w  #RULE_ENUM_MAX,d0
        bhi.s   rules_done
        lea     penalty_names(pc),a0
        bra.s   nth_copy

; month: D0.w = eighth months; the month's name (JAN-DEC).
month:
        lsr.w   #3,d0
        cmpi.w  #11,d0
        bls.s   .name
        moveq   #11,d0
.name:
        lea     month_names(pc),a0
; nth_copy: A0 = NUL-separated texts, D0.w = index. That text appended at
; A1.
nth_copy:
        move.l  d0,-(sp)
        bra.s   .test
.skip:
        tst.b   (a0)+
        bne.s   .skip
.test:
        dbf     d0,.skip
        move.l  (sp)+,d0
        bra.l   text_copy

; ---------------------------------------------------------------------------
; The screen
; ---------------------------------------------------------------------------
LINE    macro
        dc.w    UI_TEXT_AT,LINE_X,LINE_Y+\1*10,LINE_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_LINES+\1*DF_LINE_SIZE
        endm

rules_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_DEF+DF_TITLE
        dc.l    rules_body
        dc.w    0,0,1
        dc.w    136,BUTTON_Y,80,13,0,UI_NORMAL
        dc.l    ok_text

rules_body:
        LINE    0
        LINE    1
        LINE    2
        LINE    3
        LINE    4
        LINE    5
        LINE    6
        LINE    7
        LINE    8
        LINE    9
        LINE    10
        LINE    11
        LINE    12
        LINE    13
        LINE    14
        LINE    15
        LINE    16
        LINE    17
        LINE    18
        LINE    19
        dc.w    UI_END

verdict_ok:
        dc.w    UI_TEXT_AT,LINE_X,VERDICT_Y,LINE_W,UI_OK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_STATUS
        dc.w    UI_END
verdict_bad:
        dc.w    UI_TEXT_AT,LINE_X,VERDICT_Y,LINE_W,UI_ERROR,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_DEF+DF_STATUS
        dc.w    UI_END

title_text:             dc.b    'RULES: ',0
ready_text:             dc.b    'READY TO START.',0
league_of:              dc.b    'LEAGUE OF ',0
cup_of:                 dc.b    'CUP OF ',0
tournament_of:          dc.b    'TOURNAMENT OF ',0
teams_text:             dc.b    ' TEAMS',0
teams_in:               dc.b    ' TEAMS IN ',0
rounds_text:            dc.b    ' ROUNDS',0
stages_text:            dc.b    ' STAGES',0
meet_text:              dc.b    'TEAMS MEET ',0
time_text:              dc.b    ' TIME',0
comma:                  dc.b    ', ',0
colon:                  dc.b    ': ',0
points_win:             dc.b    ' POINTS FOR A WIN',0
points_text:            dc.b    ' POINTS, ',0
dates_text:             dc.b    ' MATCH DATES',0
matchdays_text:         dc.b    'MATCHDAYS: ',0
matches_text:           dc.b    ', MATCHES A DAY: ',0
round_text:             dc.b    'ROUND ',0
stage_text:             dc.b    'STAGE ',0
knockout_of:            dc.b    'KNOCKOUT OF ',0
groups_of:              dc.b    ' GROUPS OF ',0
group_of:               dc.b    ' GROUP OF ',0
go_on:                  dc.b    ' GO ON',0
one_winner:             dc.b    'ONE WINNER',0
seeded_text:            dc.b    ', SEEDED',0
indent:                 dc.b    '   ',0
leg_text:               dc.b    ' LEG',0
substitutes_text:       dc.b    'SUBSTITUTES: ',0
none_text:              dc.b    'NONE',0
from_text:              dc.b    ' FROM ',0
pitch_text:             dc.b    'PITCH: ',0
season_word:            dc.b    'SEASON',0
season_text:            dc.b    'SEASON: ',0
to_text:                dc.b    ' TO ',0
teams_line:             dc.b    'TEAMS: ',0
teams_on_start:         dc.b    'CHOSEN WHEN THE COMPETITION STARTS',0
teams_held:             dc.b    ' FROM THE DEFINITION',0
away_text:              dc.b    'AWAY GOALS: ',0
away_names:             dc.b    'OFF',0,'AFTER 90 MINS',0,'AFTER EXTRA TIME',0
extra_names:            dc.b    'NO EXTRA TIME',0,'EXTRA TIME',0,'E.T. IF REPLAY',0
penalty_names:          dc.b    'NO PENALTIES',0,'PENALTIES',0,'PENS IF REPLAY',0
pitch_names:            dc.b    'RANDOM',0,'FROZEN',0,'MUDDY',0,'WET',0,'SOFT',0
                        dc.b    'NORMAL',0,'DRY',0,'HARD',0
month_names:            dc.b    'JAN',0,'FEB',0,'MAR',0,'APR',0,'MAY',0,'JUN',0
                        dc.b    'JUL',0,'AUG',0,'SEP',0,'OCT',0,'NOV',0,'DEC',0
        even
