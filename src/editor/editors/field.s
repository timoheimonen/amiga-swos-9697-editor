; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The keyboard field of the editors' own screens (the technique of the
; author's Cannon Fodder editor): text typed on the keyboard into a buffer
; with a native capacity, only with characters the game's own font shows and
; its text entry accepts (text_glyph). The screen draws the field itself.
;
;   field_start  A0 = text buffer (NUL-terminated), D0.w = capacity in
;                characters (without the NUL). Keeps a copy for Esc.
;   field_key    D7.w = native menu events, D6.w = translated key. D0.l =
;                FIELD_TYPING (D1.l = 1 when the text changed), FIELD_KEPT
;                (Return or Fire) or FIELD_CANCELLED (Esc; the text is
;                restored).
; Both preserve every register except D0 and D1.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "dialog.i"

        xdef    field_start, field_key
        xref    editor_base
        xref    text_copy, text_length, text_glyph

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
        movem.l (sp)+,d0/a0-a1/a4
        rts

field_key:
        movem.l a0-a1/a4,-(sp)
        bsr.s   field_state
        movea.l FLD_TEXT(a4),a0
        moveq   #0,d1
        cmpi.w  #KEY_ESCAPE,d6
        beq.s   .cancel
        btst    #5,d7                   ; Fire or Return keeps the text
        bne.s   .keep
        bsr.l   text_length             ; D0 = length
        cmpi.w  #KEY_BACKSPACE,d6
        beq.s   .delete
        move.w  d0,d1
        move.w  d6,d0
        bsr.l   text_glyph
        exg     d0,d1                   ; D0 = length again, flags kept
        beq.s   .unchanged
        cmp.w   FLD_CAPACITY(a4),d0
        bcc.s   .unchanged
        move.b  d6,(a0,d0.w)
        clr.b   1(a0,d0.w)
        bra.s   .changed
.delete:
        tst.w   d0
        beq.s   .unchanged
        clr.b   -1(a0,d0.w)
.changed:
        moveq   #1,d1
        bra.s   .typing
.unchanged:
        moveq   #0,d1
.typing:
        moveq   #FIELD_TYPING,d0
        bra.s   .done
.cancel:
        lea     FLD_BACKUP(a4),a1
        exg     a0,a1
        bsr.l   text_copy
        moveq   #FIELD_CANCELLED,d0
        bra.s   .done
.keep:
        moveq   #FIELD_KEPT,d0
.done:
        movem.l (sp)+,a0-a1/a4
        rts
