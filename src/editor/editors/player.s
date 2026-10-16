; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The player screen: one player of the team page's working copy (the
; physical slot in TE_ROW).
;
;   NAME            Fire starts typing (22 characters the game's font
;                   shows); Return or Fire keeps the name, Esc restores it
;   NATIONALITY     the 153 native three-letter labels
;   SHIRT NUMBER    a new number is swapped with the player who has it
;   POSITION        G RB LB D RW LW M A; crossing the goalkeeper boundary
;                   shows the converted rating and the lineup effect and
;                   needs YES
;   APPEARANCE      0-2, with the native icon
;   seven skills    0-7 with LEFT/RIGHT; Fire switches the specialty flag;
;                   the outfield rating is their sum
;   GOALKEEPER      a goalkeeper's own rating, 0-38 (39 and 40 of the
;                   original data are kept until changed)
;   COPY PLAYER     puts the shown player into the clipboard
;   PASTE PLAYER    replaces name, nationality, position, appearance,
;                   skills, specialty flags and rating with the clipboard's;
;                   shirt number, low flags, status, goals, form and the
;                   rating cache stay
;   OK              keeps the changes in the working copy
;   CANCEL, Esc     restores the working copy as it was when the screen
;                   opened
; The value line shows the native price of the rating (derived, read only);
; Fire on it explains that a value cannot be set: the game works it out
; from the rating.
; The other representation of a player whose position crossed the
; goalkeeper boundary is kept, so crossing back restores it exactly.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    player_screen
        xref    dialog_open, dialog_poll, dialog_set, dialog_draw, dialog_paint
        xref    ui_draw
        xref    editor_base, editor_image
        xref    message_title, message_line, message_lines, message_open, message_poll
        xref    text_copy, text_copy_max, text_decimal, text_pad
        xref    field_start, field_key
        xref    player_rating_sum, lineup_role_of
        xref    team_screen_save, team_screen_cancel
        xref    ok_text, cancel_text

TOP                     equ 8
HEIGHT                  equ 256
ROW_X                   equ 24
ROW_W                   equ 176
NAME_W                  equ 304
ROW_H                   equ 9
ROWS_Y                  equ TOP+22
ROW_STEP                equ 11
DERIVED_Y               equ ROWS_Y+13*ROW_STEP+4
STATUS_Y                equ DERIVED_Y+12
HINT_Y                  equ STATUS_Y+14
BUTTON_Y                equ TOP+HEIGHT-16
ICON_X                  equ ROW_X+ROW_W+20
ICON_Y                  equ ROWS_Y+4*ROW_STEP
VALUE_COLUMN            equ 15          ; characters before a row's value

; Button indices and codes
INDEX_NAME              equ 0
INDEX_NATIONALITY       equ 1
INDEX_SHIRT             equ 2
INDEX_POSITION          equ 3
INDEX_APPEARANCE        equ 4
INDEX_SKILL             equ 5
INDEX_KEEPER            equ 12
INDEX_COPY              equ 13
INDEX_PASTE             equ 14
INDEX_VALUE             equ 17
ROWS                    equ 13
CODE_CANCEL             equ 0
CODE_NAME               equ 10
CODE_NATIONALITY        equ 11
CODE_SHIRT              equ 12
CODE_POSITION           equ 13
CODE_APPEARANCE         equ 14
CODE_SKILL              equ 20          ; +skill
CODE_KEEPER             equ 30
CODE_COPY               equ 40
CODE_PASTE              equ 41
CODE_OK                 equ 42
CODE_VALUE              equ 43
; Changes waiting for YES (TS_PENDING)
PENDING_POSITION        equ 1
PENDING_PASTE           equ 2

        section .text,code

player_screen:
        dc.l    player_open
        dc.l    player_tick

; player: A3 = the player shown. Uses A5 = editor base.
player:
        move.l  d0,-(sp)
        move.w  WORK_TEAM+TE_ROW(a5),d0
        andi.w  #PLAYER_COUNT-1,d0
        mulu.w  #PLAYER_SIZE,d0
        lea     team_working_copy+TEAM_PLAYERS,a3
        adda.l  d0,a3
        move.l  (sp)+,d0
        rts

; is_keeper: A3 = player. Z set when the player is a goalkeeper.
is_keeper:
        move.l  d0,-(sp)
        move.b  PLAYER_FLAGS(a3),d0
        andi.b  #POSITION_MASK,d0
        movem.l (sp)+,d0
        rts

; ---------------------------------------------------------------------------
; player_open: A5 = editor base.
; ---------------------------------------------------------------------------
player_open:
        bsr.l   team_screen_save
        lea     WORK_TEAM_SCREEN(a5),a4
        move.w  #TSM_MAIN,TS_MODE(a4)
        clr.w   TS_PENDING(a4)
        clr.w   TS_SIDE_VALID(a4)
        lea     TS_TITLE(a4),a1
        lea     title_text(pc),a0
        bsr.l   text_copy
        move.w  WORK_TEAM+TE_ROW(a5),d0
        addq.w  #1,d0
        bsr.l   text_decimal
        lea     title_separator(pc),a0
        bsr.l   text_copy
        lea     team_working_copy+TEAM_NAME,a0
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     status_ready(pc),a0
        lea     TS_STATUS(a4),a1
        bsr.l   text_copy
        bsr.w   player
        bra.w   show_player

; ---------------------------------------------------------------------------
; player_tick: A5 = editor base, D7.w = events, D6.w = key.
; ---------------------------------------------------------------------------
player_tick:
        lea     WORK_TEAM_SCREEN(a5),a4
        bsr.w   player
        move.w  TS_MODE(a4),d0
        cmpi.w  #TSM_TYPING,d0
        beq.w   type_name
        cmpi.w  #TSM_MAIN,d0
        beq.s   .main
        bsr.l   message_poll            ; a question or a message is open
        bmi.w   stay
        cmpi.w  #TSM_CONFIRM,TS_MODE(a4)
        bne.s   .closed
        cmpi.w  #MSG_YES,d0
        bne.s   .closed
        bsr.w   apply_pending
.closed:
        move.w  #TSM_MAIN,TS_MODE(a4)
        clr.w   TS_PENDING(a4)
        bra.w   show_player
.main:
        bsr.l   dialog_poll
        bmi.w   stay
        moveq   #1,d2                   ; direction: +1, or -1 for DIALOG_DEC
        btst    #14,d0
        beq.s   .direction
        moveq   #-1,d2
.direction:
        move.w  d0,d4                   ; D4 <> 0: LEFT or RIGHT, not Fire
        andi.w  #DIALOG_INC|DIALOG_DEC,d4
        andi.w  #DIALOG_CODE_MASK,d0
        cmpi.w  #CODE_CANCEL,d0
        beq.l   team_screen_cancel
        cmpi.w  #CODE_OK,d0
        beq.w   player_ok
        cmpi.w  #CODE_NAME,d0
        beq.w   start_typing
        cmpi.w  #CODE_NATIONALITY,d0
        beq.w   step_nationality
        cmpi.w  #CODE_SHIRT,d0
        beq.w   step_shirt
        cmpi.w  #CODE_POSITION,d0
        beq.w   step_position
        cmpi.w  #CODE_APPEARANCE,d0
        beq.w   step_appearance
        cmpi.w  #CODE_KEEPER,d0
        beq.w   step_keeper
        cmpi.w  #CODE_COPY,d0
        beq.w   copy_player
        cmpi.w  #CODE_PASTE,d0
        beq.w   paste_player
        cmpi.w  #CODE_VALUE,d0
        beq.w   value_refused
        subi.w  #CODE_SKILL,d0
        cmpi.w  #SKILL_COUNT,d0
        bcs.w   step_skill
stay:
        moveq   #0,d0
        rts

player_ok:
        moveq   #1,d0
        rts

; value_refused: Fire on the value line. A player's value is not stored:
; the native price follows from the rating, so the message says how to
; change it instead.
value_refused:
        lea     value_title(pc),a0
        bsr.l   message_title
        lea     value_lines(pc),a0
        moveq   #0,d0
        bsr.l   message_lines
        moveq   #MSG_OK,d0
        bsr.l   message_open
        move.w  #TSM_MESSAGE,TS_MODE(a4)
        bra.w   stay

; ---------------------------------------------------------------------------
; Value controls: D2.l = +1 or -1, A3 = player, A4 = screen state.
; ---------------------------------------------------------------------------
step_nationality:
        moveq   #0,d0
        move.b  PLAYER_NATIONALITY(a3),d0
        add.w   d2,d0
        bpl.s   .high
        move.w  #NATIONALITY_COUNT-1,d0
.high:
        cmpi.w  #NATIONALITY_COUNT,d0
        bcs.s   .set
        moveq   #0,d0
.set:
        move.b  d0,PLAYER_NATIONALITY(a3)
        moveq   #INDEX_NATIONALITY,d0
        bra.w   redraw_row

; step_shirt: the next number up or down (1-16) is swapped with its holder.
step_shirt:
        moveq   #0,d0
        move.b  PLAYER_SHIRT(a3),d0
        move.w  d0,d4                   ; old number
        add.w   d2,d0
        bne.s   .high
        moveq   #PLAYER_COUNT,d0
.high:
        cmpi.w  #PLAYER_COUNT,d0
        bls.s   .holder
        moveq   #1,d0
.holder:
        lea     team_working_copy+TEAM_PLAYERS,a0
        moveq   #PLAYER_COUNT-1,d1
.find:
        cmpa.l  a0,a3
        beq.s   .next
        cmp.b   PLAYER_SHIRT(a0),d0
        beq.s   .found
.next:
        lea     PLAYER_SIZE(a0),a0
        dbf     d1,.find
        move.b  d0,PLAYER_SHIRT(a3)     ; nobody had it
        lea     status_ready(pc),a0
        bra.s   .status
.found:
        move.b  d4,PLAYER_SHIRT(a0)
        move.b  d0,PLAYER_SHIRT(a3)
        movea.l a0,a2
        lea     TS_STATUS(a4),a1
        lea     status_swapped(pc),a0
        bsr.l   text_copy
        lea     PLAYER_NAME(a2),a0
        moveq   #PLAYER_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     TS_STATUS(a4),a0
.status:
        bsr.w   set_status_text
        moveq   #INDEX_SHIRT,d0
        bra.w   redraw_row

step_appearance:
        move.b  PLAYER_FLAGS(a3),d0
        andi.w  #APPEARANCE_MASK,d0
        lsr.w   #APPEARANCE_SHIFT,d0
        add.w   d2,d0
        bpl.s   .high
        moveq   #APPEARANCE_COUNT-1,d0
.high:
        cmpi.w  #APPEARANCE_COUNT,d0
        bcs.s   .set
        moveq   #0,d0
.set:
        lsl.b   #APPEARANCE_SHIFT,d0
        andi.b  #~APPEARANCE_MASK&$FF,PLAYER_FLAGS(a3)
        or.b    d0,PLAYER_FLAGS(a3)
        bsr.w   draw_icon
        moveq   #INDEX_APPEARANCE,d0
        bra.w   redraw_row

; step_skill: D0.w = skill 0-6. LEFT/RIGHT change its rating 0-7, Fire
; switches its specialty flag; the outfield rating is recomputed.
step_skill:
        move.w  d0,d5
        moveq   #SKILL_COUNT-1,d1
        sub.w   d0,d1
        lsl.w   #2,d1                   ; shift of the skill's nibble
        move.l  PLAYER_SKILLS(a3),d3
        move.l  d3,d0
        lsr.l   d1,d0
        andi.w  #$F,d0                  ; specialty and rating
        tst.w   d4
        bne.s   .rating
        eori.w  #SKILL_SPECIALTY,d0
        bra.s   .store
.rating:
        move.w  d0,d6
        andi.w  #SKILL_SPECIALTY,d6
        andi.w  #SKILL_MAX,d0
        add.w   d2,d0
        bpl.s   .low
        moveq   #0,d0
.low:
        cmpi.w  #SKILL_MAX,d0
        bls.s   .join
        moveq   #SKILL_MAX,d0
.join:
        or.w    d6,d0
.store:
        moveq   #$F,d6
        lsl.l   d1,d6
        not.l   d6
        and.l   d6,d3
        andi.l  #$F,d0
        lsl.l   d1,d0
        or.l    d0,d3
        move.l  d3,PLAYER_SKILLS(a3)
        move.l  d3,d0
        bsr.l   player_rating_sum
        move.b  d0,PLAYER_RATING(a3)
        move.w  d5,d0
        addq.w  #INDEX_SKILL,d0
        bra.w   redraw_row

; step_keeper: a goalkeeper's rating, 0-38 for new values.
step_keeper:
        moveq   #0,d0
        move.b  PLAYER_RATING(a3),d0
        tst.w   d2
        bpl.s   .up
        cmpi.w  #KEEPER_RATING_MAX,d0
        bls.s   .down
        moveq   #KEEPER_RATING_MAX,d0
        bra.s   .set
.down:
        subq.w  #1,d0
        bpl.s   .set
        moveq   #0,d0
        bra.s   .set
.up:
        cmpi.w  #KEEPER_RATING_MAX,d0
        bcc.w   stay
        addq.w  #1,d0
.set:
        move.b  d0,PLAYER_RATING(a3)
        moveq   #INDEX_KEEPER,d0
        bra.w   redraw_row

; step_position: crossing the goalkeeper boundary asks first.
step_position:
        move.b  PLAYER_FLAGS(a3),d0
        lsr.b   #POSITION_SHIFT,d0
        andi.w  #POSITION_COUNT-1,d0
        move.w  d0,d1                   ; old
        add.w   d2,d0
        andi.w  #POSITION_COUNT-1,d0
        tst.w   d1
        seq     d3
        tst.w   d0
        seq     d5
        cmp.b   d3,d5
        bne.s   .boundary
        bsr.w   set_position
        moveq   #INDEX_POSITION,d0
        bra.w   redraw_row
.boundary:
        move.w  #PENDING_POSITION,TS_PENDING(a4)
        move.w  d0,TS_PENDING_VALUE(a4)
        bsr.w   ask_position
        moveq   #0,d0
        rts

; set_position: D0.w = position. Keeps appearance and the low flags.
set_position:
        lsl.b   #POSITION_SHIFT,d0
        andi.b  #~POSITION_MASK&$FF,PLAYER_FLAGS(a3)
        or.b    d0,PLAYER_FLAGS(a3)
        rts

; ---------------------------------------------------------------------------
; Clipboard
; ---------------------------------------------------------------------------
copy_player:
        movea.l a3,a0
        lea     WORK_TEAM+TE_CLIP(a5),a1
        moveq   #PLAYER_SIZE-1,d0
.copy:
        move.b  (a0)+,(a1)+
        dbf     d0,.copy
        move.w  #1,WORK_TEAM+TE_CLIP_VALID(a5)
        moveq   #INDEX_PASTE,d2
        moveq   #UI_NORMAL,d3
        suba.l  a0,a0
        bsr.l   dialog_set
        lea     status_copied(pc),a0
        bsr.w   set_status_text
        bra.w   stay

paste_player:
        tst.w   WORK_TEAM+TE_CLIP_VALID(a5)
        beq.w   stay
        bsr.w   is_keeper
        seq     d0
        move.b  WORK_TEAM+TE_CLIP+PLAYER_FLAGS(a5),d1
        andi.b  #POSITION_MASK,d1
        seq     d1
        cmp.b   d0,d1
        bne.s   .boundary
        bsr.w   apply_paste
        bra.w   show_player
.boundary:
        move.w  #PENDING_PASTE,TS_PENDING(a4)
        bsr.w   ask_paste
        bra.w   stay

; apply_paste: the clipboard into the shown player.
apply_paste:
        lea     WORK_TEAM+TE_CLIP(a5),a0
        move.b  PLAYER_NATIONALITY(a0),PLAYER_NATIONALITY(a3)
        moveq   #PLAYER_NAME_SIZE-1,d0
.name:
        move.b  PLAYER_NAME(a0,d0.w),PLAYER_NAME(a3,d0.w)
        dbf     d0,.name
        move.b  PLAYER_FLAGS(a0),d0
        andi.b  #~LOW_FLAGS_MASK&$FF,d0
        andi.b  #LOW_FLAGS_MASK,PLAYER_FLAGS(a3)
        or.b    d0,PLAYER_FLAGS(a3)
        move.l  PLAYER_SKILLS(a0),d0
        andi.l  #SKILL_BITS_MASK,d0
        andi.l  #~SKILL_BITS_MASK,PLAYER_SKILLS(a3)
        or.l    d0,PLAYER_SKILLS(a3)
        move.b  PLAYER_RATING(a0),d1
        bsr.w   is_keeper
        beq.s   .rating
        bsr.l   player_rating_sum
        move.b  d0,d1
.rating:
        move.b  d1,PLAYER_RATING(a3)
        clr.w   TS_SIDE_VALID(a4)
        lea     status_pasted(pc),a0
        lea     TS_STATUS(a4),a1
        bra.l   text_copy

; apply_pending: YES to the open question.
apply_pending:
        cmpi.w  #PENDING_PASTE,TS_PENDING(a4)
        beq.s   apply_paste
        bsr.w   converted               ; D1 = skills, D2 = rating of the other side
        move.l  PLAYER_SKILLS(a3),TS_SIDE_SKILLS(a4)
        moveq   #0,d0
        move.b  PLAYER_RATING(a3),d0
        move.w  d0,TS_SIDE_RATING(a4)
        move.w  #1,TS_SIDE_VALID(a4)
        move.l  d1,PLAYER_SKILLS(a3)
        move.b  d2,PLAYER_RATING(a3)
        move.w  TS_PENDING_VALUE(a4),d0
        bra.w   set_position

; converted: A3 = player. D1.l = skills and D2.w = rating in the other
; representation: the one kept from the last crossing, else a keeper's
; rating min(sum, 38) without skills, or an outfield player's skills
; spread evenly over the seven skills from the keeper's rating.
converted:
        movem.l d0/d3-d5,-(sp)
        tst.w   TS_SIDE_VALID(a4)
        beq.s   .compute
        move.l  TS_SIDE_SKILLS(a4),d1
        move.w  TS_SIDE_RATING(a4),d2
        bra.s   .done
.compute:
        move.l  PLAYER_SKILLS(a3),d1
        andi.l  #~SKILL_BITS_MASK,d1    ; the prefix nibble stays
        moveq   #0,d2
        move.b  PLAYER_RATING(a3),d2
        bsr.w   is_keeper
        beq.s   .to_outfield
        move.l  PLAYER_SKILLS(a3),d0    ; to a goalkeeper
        bsr.l   player_rating_sum
        move.w  d0,d2
        cmpi.w  #KEEPER_RATING_MAX,d2
        bls.s   .done
        moveq   #KEEPER_RATING_MAX,d2
        bra.s   .done
.to_outfield:
        cmpi.w  #OUTFIELD_RATING_MAX,d2
        bls.s   .spread
        moveq   #OUTFIELD_RATING_MAX,d2
.spread:
        moveq   #0,d3
        move.w  d2,d3
        divu.w  #SKILL_COUNT,d3         ; low word base, high word remainder
        move.l  d3,d4
        swap    d4                      ; remainder: skills that get one more
        moveq   #SKILL_COUNT-1,d5       ; passing first
.skill:
        moveq   #0,d0
        move.w  d3,d0
        tst.w   d4
        beq.s   .put
        addq.w  #1,d0
        subq.w  #1,d4
.put:
        lsl.l   #2,d5                   ; shift of the nibble
        lsl.l   d5,d0
        lsr.l   #2,d5
        or.l    d0,d1
        dbf     d5,.skill
.done:
        movem.l (sp)+,d0/d3-d5
        rts

; ---------------------------------------------------------------------------
; Questions
; ---------------------------------------------------------------------------
ask_position:
        lea     position_title(pc),a0
        bsr.l   message_title
        bsr.w   converted               ; D1 skills, D2 rating
        lea     TS_SCRATCH(a4),a1
        bsr.w   is_keeper
        beq.s   .to_outfield
        lea     keeper_line0(pc),a0
        bsr.l   text_copy
        move.w  d2,d0
        bsr.l   text_decimal
        move.b  #'.',(a1)+
        clr.b   (a1)
        bra.s   .line0
.to_outfield:
        lea     outfield_line0(pc),a0
        bsr.l   text_copy
        move.l  d1,d3
        moveq   #24,d4
.skill:
        move.l  d3,d0
        lsr.l   d4,d0
        andi.w  #SKILL_MAX,d0
        bsr.l   text_decimal
        move.b  #' ',(a1)+
        subq.w  #4,d4
        bpl.s   .skill
        lea     outfield_rating(pc),a0
        bsr.l   text_copy
        move.w  d2,d0
        bsr.l   text_decimal
        move.b  #')',(a1)+
        clr.b   (a1)
.line0:
        lea     TS_SCRATCH(a4),a0
        moveq   #0,d0
        bsr.l   message_line
        bsr.w   is_keeper
        sne     d0                      ; becomes a goalkeeper?
        bsr.w   lineup_effect
        lea     position_question(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bra.s   ask_open

ask_paste:
        lea     paste_title(pc),a0
        bsr.l   message_title
        lea     paste_keeper(pc),a0
        bsr.w   is_keeper
        sne     d0                      ; the pasted player is a goalkeeper
        bne.s   .line0
        lea     paste_outfield(pc),a0
.line0:
        move.l  d0,-(sp)
        moveq   #0,d0
        bsr.l   message_line
        move.l  (sp)+,d0
        bsr.w   lineup_effect
        lea     paste_question(pc),a0
        moveq   #3,d0
        bsr.l   message_line
ask_open:
        moveq   #MSG_ASK,d0
        bsr.l   message_open
        move.w  #TSM_CONFIRM,TS_MODE(a4)
        rts

; lineup_effect: D0.b <> 0 when the player becomes a goalkeeper. Writes
; the effect on the lineup as message line 2.
lineup_effect:
        movem.l d0-d2/a0-a1,-(sp)
        move.b  d0,d2
        move.w  WORK_TEAM+TE_ROW(a5),d0
        lea     team_working_copy,a0
        bsr.l   lineup_role_of          ; D0 = role or -1
        lea     TS_SCRATCH(a4),a1
        lea     effect_unchanged(pc),a0
        tst.l   d0
        bmi.s   .copy
        cmpi.w  #STARTING_ROLES,d0
        bcs.s   .starter
        lea     effect_substitute(pc),a0
        bra.s   .copy
.starter:
        tst.b   d2
        bne.s   .to_keeper
        tst.w   d0
        bne.s   .copy
        lea     effect_goal(pc),a0      ; role 1 loses its goalkeeper
        bra.s   .copy
.to_keeper:
        tst.w   d0
        beq.s   .copy
        move.w  d0,d1
        lea     effect_outfield(pc),a0  ; a goalkeeper in an outfield role
        bsr.l   text_copy
        move.w  d1,d0
        addq.w  #1,d0
        bsr.l   text_decimal
        lea     effect_outfield_end(pc),a0
.copy:
        bsr.l   text_copy
        lea     TS_SCRATCH(a4),a0
        moveq   #2,d0
        bsr.l   message_line
        movem.l (sp)+,d0-d2/a0-a1
        rts

; ---------------------------------------------------------------------------
; Name entry
; ---------------------------------------------------------------------------
start_typing:
        lea     PLAYER_NAME(a3),a0
        lea     TS_NAME(a4),a1
        moveq   #PLAYER_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     TS_NAME(a4),a0
        bsr.l   field_start             ; D0 = capacity
        move.w  #TSM_TYPING,TS_MODE(a4)
        lea     status_typing(pc),a0
        bsr.w   set_status_text
; typed_name: the NAME row as typed so far, with the cursor.
typed_name:
        moveq   #INDEX_NAME,d2
        moveq   #UI_ACTIVE,d3
        bsr.w   build_name
        suba.l  a0,a0
        bsr.l   dialog_set
        bra.w   stay

; type_name: one frame of typing (editors/field.s). Return or Fire keeps
; the name, Esc leaves it unchanged.
type_name:
        bsr.l   field_key
        tst.l   d0
        bne.s   .finish
        tst.l   d1
        bne.s   typed_name
        bra.w   stay
.finish:
        bmi.s   .done                   ; Esc: the player's name is unchanged
        lea     TS_NAME(a4),a0          ; the new text and its NUL; the bytes
        lea     PLAYER_NAME(a3),a1      ; after it stay, as natively
        bsr.l   text_copy
.done:
        move.w  #TSM_MAIN,TS_MODE(a4)
        lea     status_ready(pc),a0
        bsr.w   set_status_text
        moveq   #INDEX_NAME,d0
        bra.w   redraw_row

; ---------------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------------
; show_player: the whole screen in its current state.
show_player:
        bsr.w   build_rows
        moveq   #0,d2                   ; disabled buttons
        bsr.w   is_keeper
        bne.s   .outfield
        move.l  #((1<<SKILL_COUNT)-1)<<INDEX_SKILL,d2
        bra.s   .clip
.outfield:
        move.l  #1<<INDEX_KEEPER,d2
.clip:
        tst.w   WORK_TEAM+TE_CLIP_VALID(a5)
        bne.s   .open
        bset    #INDEX_PASTE,d2
.open:
        lea     player_dialog(pc),a0
        bsr.l   dialog_open
        bsr.w   draw_icon
        bsr.w   draw_derived
        bsr.w   draw_status
        bra.w   stay

; redraw_row: D0.w = row index. Rebuilds and repaints it and the derived
; line.
redraw_row:
        move.w  d0,d2
        bsr.w   build_row
        suba.l  a0,a0
        bsr.w   row_state
        bsr.l   dialog_set
        bsr.w   draw_derived
        bra.w   stay

; row_state: D2.w = row. D3.w = its shown state.
row_state:
        moveq   #UI_NORMAL,d3
        cmpi.w  #INDEX_SKILL,d2
        bcs.s   .done
        cmpi.w  #INDEX_KEEPER,d2
        bhi.s   .done
        bsr.w   is_keeper
        seq     d3                      ; keeper: skills disabled
        cmpi.w  #INDEX_KEEPER,d2
        bne.s   .skill
        not.b   d3                      ; outfield: keeper row disabled
.skill:
        andi.w  #UI_DISABLED,d3
.done:
        rts

draw_derived:
        lea     TS_DERIVED(a4),a1
        lea     rating_text(pc),a0
        bsr.l   text_copy
        moveq   #0,d0
        move.b  PLAYER_RATING(a3),d0
        bsr.l   text_decimal
        movem.l d0-d7/a0-a6,-(sp)
        jsr     aggregate_to_base_price ; D0.w = thousands
        lea     TS_VALUE(a4),a1
        jsr     format_price_thousands
        movem.l (sp)+,d0-d7/a0-a6
        lea     value_text(pc),a0
        bsr.l   text_copy
        lea     TS_VALUE(a4),a0
        cmpi.b  #PRICE_POUND_SIGN,(a0)
        bne.s   .price
        addq.l  #1,a0                   ; the 5x7 font has no pound sign
.price:
        moveq   #12,d0
        bsr.l   text_copy_max
        moveq   #INDEX_VALUE,d2         ; the value line is a row
        moveq   #UI_NORMAL,d3
        suba.l  a0,a0
        bra.l   dialog_set

draw_status:
        lea     status_commands(pc),a0
        bra.l   dialog_draw

; set_status_text: A0 = text for the status line, drawn now.
set_status_text:
        lea     TS_STATUS(a4),a1
        bsr.l   text_copy
        bra.s   draw_status

; draw_icon: the native sprite of the player's appearance beside its row.
draw_icon:
        move.l  a2,-(sp)
        lea     paint_icon(pc),a2
        bsr.l   dialog_paint
        movea.l (sp)+,a2
        rts

; paint_icon: one display buffer (dialog_paint: A1 = target).
paint_icon:
        movem.l d0-d7/a0-a6,-(sp)
        lea     icon_clear(pc),a0
        moveq   #0,d1
        bsr.l   ui_draw
        movea.l editor_base,a5
        bsr.w   player
        moveq   #0,d0
        move.b  PLAYER_FLAGS(a3),d0
        andi.w  #APPEARANCE_MASK,d0
        lsr.w   #APPEARANCE_SHIFT,d0
        addi.w  #APPEARANCE_SPRITE_BASE,d0
        move.w  #ICON_X,d1
        move.w  #ICON_Y,d2
        jsr     sprite_draw
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; Labels
; ---------------------------------------------------------------------------
build_rows:
        moveq   #0,d0
.row:
        bsr.w   build_row
        addq.w  #1,d0
        cmpi.w  #ROWS,d0
        bcs.s   .row
        rts

; label: D0.w = row. A1 = its label, A0 = its caption.
label:
        move.l  d0,-(sp)
        mulu.w  #TS_LABEL_SIZE,d0
        lea     TS_LABELS(a4,d0.w),a1
        move.l  (sp),d0
        lea     captions(pc),a0
        movea.l (a0,d0.w*4),a0
        move.l  (sp)+,d0
        rts

; column: pads at A1 to the value column of the label starting at D1.
column:
        move.l  d0,-(sp)
        moveq   #VALUE_COLUMN,d0
        add.l   d1,d0
        bsr.l   text_pad
        move.l  (sp)+,d0
        rts

; build_name: the NAME row while typing (with a cursor) or not.
build_name:
        movem.l d0-d1/a0-a1,-(sp)
        moveq   #INDEX_NAME,d0
        bsr.w   label
        move.l  a1,d1
        bsr.l   text_copy
        bsr.w   column
        cmpi.w  #TSM_TYPING,TS_MODE(a4)
        bne.s   .shown
        lea     TS_NAME(a4),a0
        bsr.l   text_copy
        move.b  #'_',(a1)+
        clr.b   (a1)
        bra.s   .done
.shown:
        lea     PLAYER_NAME(a3),a0
        moveq   #PLAYER_NAME_SIZE-1,d0
        bsr.l   text_copy_max
.done:
        movem.l (sp)+,d0-d1/a0-a1
        rts

; build_row: D0.w = row index. Its label: caption and '< value >', a
; skill's specialty as ' *', '-' on a row the player has not (row_state).
build_row:
        tst.w   d0
        beq.s   build_name
        movem.l d0-d4/a0-a1,-(sp)
        move.w  d0,d4
        bsr.w   label
        move.l  a1,d1
        bsr.l   text_copy
        bsr.w   column
        move.w  d4,d2
        bsr.w   row_state               ; D3 = UI_DISABLED: not this player's row
        tst.w   d3
        bne.w   .dash
        move.b  #'<',(a1)+
        move.b  #' ',(a1)+
        moveq   #0,d0
        cmpi.w  #INDEX_SKILL,d4
        bcc.s   .skill_or_keeper
        cmpi.w  #INDEX_NATIONALITY,d4
        bne.s   .shirt
        move.b  PLAYER_NATIONALITY(a3),d0
        cmpi.w  #NATIONALITY_COUNT,d0
        bcc.s   .number                 ; out of range: its number
        mulu.w  #3,d0
        lea     nationality_abbreviations,a0
        adda.w  d0,a0
        move.b  (a0)+,(a1)+
        move.b  (a0)+,(a1)+
        move.b  (a0)+,(a1)+
        bra.s   .close
.shirt:
        move.b  PLAYER_SHIRT(a3),d0
        cmpi.w  #INDEX_SHIRT,d4
        beq.s   .number
        move.b  PLAYER_FLAGS(a3),d0
        cmpi.w  #INDEX_POSITION,d4
        bne.s   .appearance
        lsr.b   #POSITION_SHIFT,d0
        andi.w  #POSITION_COUNT-1,d0
        lea     position_labels,a0
        movea.l (a0,d0.w*4),a0
        moveq   #2,d0
        bsr.l   text_copy_max
        bra.s   .close
.appearance:
        andi.w  #APPEARANCE_MASK,d0
        lsr.w   #APPEARANCE_SHIFT,d0
        bra.s   .number
.skill_or_keeper:
        move.b  PLAYER_RATING(a3),d0
        cmpi.w  #INDEX_KEEPER,d4
        beq.s   .number
        moveq   #SKILL_COUNT-1+INDEX_SKILL,d2
        sub.w   d4,d2
        lsl.w   #2,d2                   ; shift of the skill's nibble
        move.l  PLAYER_SKILLS(a3),d3
        lsr.l   d2,d3                   ; bit 3: its specialty
        move.w  d3,d0
        andi.w  #SKILL_MAX,d0
.number:
        bsr.l   text_decimal
.close:
        move.b  #' ',(a1)+
        move.b  #'>',(a1)+
        btst    #3,d3                   ; D3 = 0 but on a skill row
        beq.s   .end
        move.b  #' ',(a1)+
        move.b  #'*',(a1)+
        bra.s   .end
.dash:
        move.b  #'-',(a1)+
.end:
        clr.b   (a1)
        movem.l (sp)+,d0-d4/a0-a1
        rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
LABEL_AT macro
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_LABELS+(\1)*TS_LABEL_SIZE
        endm
FIELD   macro                           ; row, width, code, flags
        dc.w    ROW_X,ROWS_Y+(\1)*ROW_STEP,\2,ROW_H,\3,DIALOG_ROW|\4|UI_NORMAL
        LABEL_AT \1
        endm

player_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_TITLE
        dc.l    player_body
        dc.w    INDEX_NAME,CODE_CANCEL,18
        FIELD   0,NAME_W,CODE_NAME,0
        FIELD   1,ROW_W,CODE_NATIONALITY,DIALOG_SPIN
        FIELD   2,ROW_W,CODE_SHIRT,DIALOG_SPIN
        FIELD   3,ROW_W,CODE_POSITION,DIALOG_SPIN
        FIELD   4,ROW_W,CODE_APPEARANCE,DIALOG_SPIN
        FIELD   5,ROW_W,CODE_SKILL+0,DIALOG_SPIN
        FIELD   6,ROW_W,CODE_SKILL+1,DIALOG_SPIN
        FIELD   7,ROW_W,CODE_SKILL+2,DIALOG_SPIN
        FIELD   8,ROW_W,CODE_SKILL+3,DIALOG_SPIN
        FIELD   9,ROW_W,CODE_SKILL+4,DIALOG_SPIN
        FIELD   10,ROW_W,CODE_SKILL+5,DIALOG_SPIN
        FIELD   11,ROW_W,CODE_SKILL+6,DIALOG_SPIN
        FIELD   12,ROW_W,CODE_KEEPER,DIALOG_SPIN
        dc.w    ROW_X,BUTTON_Y,84,13,CODE_COPY,UI_NORMAL
        dc.l    copy_text
        dc.w    ROW_X+90,BUTTON_Y,84,13,CODE_PASTE,UI_NORMAL
        dc.l    paste_text
        dc.w    ROW_X+196,BUTTON_Y,48,13,CODE_OK,UI_NORMAL
        dc.l    ok_text
        dc.w    ROW_X+250,BUTTON_Y,54,13,CODE_CANCEL,UI_NORMAL
        dc.l    cancel_text
        dc.w    ROW_X,DERIVED_Y,NAME_W,9,CODE_VALUE,UI_NORMAL|DIALOG_ROW
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_DERIVED

player_body:
        dc.w    UI_TEXT,ROW_X,HINT_Y,NAME_W,UI_DIM,UI_LEFT
        dc.b    'LEFT/RIGHT CHANGES A VALUE. FIRE ON A SKILL',0
        even
        dc.w    UI_TEXT,ROW_X,HINT_Y+10,NAME_W,UI_DIM,UI_LEFT
        dc.b    'SWITCHES ITS SPECIALTY (*), FIRE ON NAME TYPES.',0
        even
        dc.w    UI_END

status_commands:
        dc.w    UI_RECT,ROW_X,STATUS_Y,NAME_W,9,UI_PANEL
        dc.w    UI_TEXT_AT,ROW_X,STATUS_Y+1,NAME_W,UI_INK,UI_LEFT_CLIPPED
        dc.l    editor_image+WORK_TEAM_SCREEN+TS_STATUS
        dc.w    UI_END

icon_clear:
        dc.w    UI_RECT,ICON_X-2,ICON_Y-2,20,14,UI_PANEL
        dc.w    UI_END

captions:
        dc.l    caption_name,caption_nationality,caption_shirt,caption_position
        dc.l    caption_appearance,caption_passing,caption_shooting,caption_heading
        dc.l    caption_tackling,caption_control,caption_speed,caption_finishing
        dc.l    caption_keeper

caption_name:           dc.b    'NAME',0
caption_nationality:    dc.b    'NATIONALITY',0
caption_shirt:          dc.b    'SHIRT NUMBER',0
caption_position:       dc.b    'POSITION',0
caption_appearance:     dc.b    'APPEARANCE',0
caption_passing:        dc.b    'PASSING',0
caption_shooting:       dc.b    'SHOOTING',0
caption_heading:        dc.b    'HEADING',0
caption_tackling:       dc.b    'TACKLING',0
caption_control:        dc.b    'BALL CONTROL',0
caption_speed:          dc.b    'SPEED',0
caption_finishing:      dc.b    'FINISHING',0
caption_keeper:         dc.b    'GOALKEEPER',0
title_text:             dc.b    'PLAYER ',0
title_separator:        dc.b    ' OF ',0
copy_text:              dc.b    'COP_Y PLAYER',0
paste_text:             dc.b    '_PASTE PLAYER',0
rating_text:            dc.b    'RATING ',0
value_text:             dc.b    '    VALUE ',0
status_ready:           dc.b    'OK KEEPS THE CHANGES, CANCEL UNDOES THEM',0
status_typing:          dc.b    'TYPE THE NAME. RETURN KEEPS IT, ESC LEAVES IT',0
status_swapped:         dc.b    'NUMBER SWAPPED WITH ',0
status_copied:          dc.b    'THE PLAYER IS IN THE CLIPBOARD',0
status_pasted:          dc.b    'PASTED. SHIRT NUMBER AND HISTORY STAY',0
position_title:         dc.b    'POSITION CHANGE',0
keeper_line0:           dc.b    'AS A GOALKEEPER THE RATING IS ',0
outfield_line0:         dc.b    'SKILLS ',0
outfield_rating:        dc.b    '(RATING ',0
position_question:      dc.b    'CHANGE THE POSITION?',0
paste_title:            dc.b    'PASTE PLAYER',0
paste_keeper:           dc.b    'A GOALKEEPER REPLACES AN OUTFIELD PLAYER.',0
paste_outfield:         dc.b    'AN OUTFIELD PLAYER REPLACES A GOALKEEPER.',0
paste_question:         dc.b    'PASTE THE PLAYER?',0
effect_unchanged:       dc.b    'THE LINEUP DOES NOT CHANGE.',0
effect_substitute:      dc.b    'A SUBSTITUTE: THE STARTING ELEVEN STAYS.',0
effect_goal:            dc.b    'IN GOAL NOW: PUT A KEEPER IN ROLE 1 IN SETTINGS.',0
effect_outfield:        dc.b    'STARTS IN ROLE ',0
effect_outfield_end:    dc.b    ', NOT IN GOAL.',0
value_title:            dc.b    'VALUE CANNOT BE SET',0
value_lines:            dc.b    'A PLAYER HAS NO STORED PRICE: THE GAME WORKS',0
                        dc.b    'OUT THE VALUE FROM THE RATING. CHANGE THE',0
                        dc.b    "SKILLS, OR A GOALKEEPER'S RATING, TO CHANGE",0
                        dc.b    'THE VALUE.',0
                        dc.b    0
        even
