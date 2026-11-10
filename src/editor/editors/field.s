; SWOS 96-97 In-Game Editors V0.93b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The keyboard field of the editors' own screens (the technique of the
; author's Cannon Fodder editor): text typed on the keyboard into a buffer
; with a native capacity, only with characters the game's own font shows and
; its text entry accepts (text_glyph). The field has a cursor: a character
; goes in at the cursor, Backspace removes the one before it, LEFT and
; RIGHT move it by one character, UP to the start and DOWN to the end. The
; screen draws the field itself, with field_shown for the text.
;
;   field_start  A0 = text buffer (NUL-terminated), D0.w = capacity in
;                characters (without the NUL). Keeps a copy for Esc; the
;                cursor starts after the text.
;   field_key    D7.w = native menu events, D6.w = translated key. D0.l =
;                FIELD_TYPING (D1.l = 1 when the text or the cursor
;                changed), FIELD_KEPT (Return or Fire) or FIELD_CANCELLED
;                (Esc; the text is restored).
;   field_shown  A1 = destination. Appends the text with the cursor mark
;                '_' at the cursor (one character more than the text); A1
;                is left on the NUL.
; All preserve every register except D0 and D1 (field_shown: A1).

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "dialog.i"

        xdef    field_start, field_key, field_shown
        xref    editor_base
        xref    text_copy, text_length, text_glyph

CURSOR_MARK             equ '_'

        section .text,code

; field_state: A4 = field state.
field_state:
        movea.l editor_base,a4
        lea     WORK_FIELD(a4),a4
        rts

field_start:
        movem.l d0/a0-a1/a4,-(sp)
        bsr.s   field_state
        move.l  a0,FLD_TEXT(a4)
        move.w  d0,FLD_CAPACITY(a4)
        lea     FLD_BACKUP(a4),a1
        bsr.l   text_copy
        bsr.l   text_length
        move.w  d0,FLD_CURSOR(a4)
        movem.l (sp)+,d0/a0-a1/a4
        rts

field_key:
        movem.l d2/a0-a1/a4,-(sp)
        bsr.s   field_state
        movea.l FLD_TEXT(a4),a0
        cmpi.w  #KEY_ESCAPE,d6
        beq.w   .cancel
        btst    #5,d7                   ; Fire or Return keeps the text
        bne.w   .keep
        bsr.l   text_length             ; D0 = length
        move.w  FLD_CURSOR(a4),d2
        cmp.w   d0,d2                   ; a text changed outside the field
        bls.s   .inside
        move.w  d0,d2
.inside:
        cmpi.w  #KEY_BACKSPACE,d6
        beq.s   .delete
        move.w  d7,d1
        andi.w  #MENU_EVENT_LEFT|MENU_EVENT_RIGHT|MENU_EVENT_UP|MENU_EVENT_DOWN,d1
        bne.s   .move
        move.w  d0,d1
        move.w  d6,d0
        bsr.l   text_glyph
        exg     d0,d1                   ; D0 = length again, flags kept
        beq.s   .unchanged
        cmp.w   FLD_CAPACITY(a4),d0
        bcc.s   .unchanged
        ; the cursor's character and those after it, NUL included, move up
        lea     (a0,d0.w),a1            ; the NUL
        sub.w   d2,d0                   ; characters after the cursor
.open:
        move.b  (a1),1(a1)
        subq.l  #1,a1
        dbf     d0,.open
        move.b  d6,(a0,d2.w)
        addq.w  #1,d2
        bra.s   .changed
.delete:
        tst.w   d2
        beq.s   .unchanged
        lea     (a0,d2.w),a1            ; the characters from the cursor on
.close:
        move.b  (a1)+,-2(a1)
        bne.s   .close
        subq.w  #1,d2
        bra.s   .changed
.move:
        move.w  d2,d1
        btst    #6,d7                   ; LEFT
        beq.s   .right
        tst.w   d2
        beq.s   .moved
        subq.w  #1,d2
        bra.s   .moved
.right:
        btst    #7,d7                   ; RIGHT
        beq.s   .ends
        cmp.w   d0,d2
        bcc.s   .moved
        addq.w  #1,d2
        bra.s   .moved
.ends:
        move.w  d0,d2                   ; DOWN: after the text
        btst    #9,d7
        bne.s   .moved
        moveq   #0,d2                   ; UP: before it
.moved:
        cmp.w   d1,d2
        beq.s   .unchanged
.changed:
        move.w  d2,FLD_CURSOR(a4)
        moveq   #1,d1
        bra.s   .typing
.unchanged:
        move.w  d2,FLD_CURSOR(a4)
        moveq   #0,d1
.typing:
        moveq   #FIELD_TYPING,d0
        bra.s   .done
.cancel:
        lea     FLD_BACKUP(a4),a1
        exg     a0,a1
        bsr.l   text_copy
        moveq   #0,d1
        moveq   #FIELD_CANCELLED,d0
        bra.s   .done
.keep:
        moveq   #0,d1
        moveq   #FIELD_KEPT,d0
.done:
        movem.l (sp)+,d2/a0-a1/a4
        rts

field_shown:
        movem.l d0/a0/a4,-(sp)
        bsr.w   field_state
        movea.l FLD_TEXT(a4),a0
        move.w  FLD_CURSOR(a4),d0
        bra.s   .before_test
.before:
        tst.b   (a0)
        beq.s   .mark                   ; a shorter text: the cursor ends it
        move.b  (a0)+,(a1)+
.before_test:
        dbf     d0,.before
.mark:
        move.b  #CURSOR_MARK,(a1)+
.after:
        move.b  (a0)+,(a1)+
        bne.s   .after
        subq.l  #1,a1
        movem.l (sp)+,d0/a0/a4
        rts
