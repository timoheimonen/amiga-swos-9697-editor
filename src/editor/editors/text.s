; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Text helpers of the editors' screens. Every routine writes at A1 and
; leaves A1 on the terminating NUL it wrote, so calls chain into one
; string; all other registers are preserved.

        xdef    text_copy, text_copy_max, text_hex32, text_decimal
        xdef    text_pad, text_length, text_glyph

        section .text,code

; text_copy: A0 = NUL-terminated text, appended at A1.
text_copy:
        move.l  a0,-(sp)
.copy:
        move.b  (a0)+,(a1)+
        bne.s   .copy
        subq.l  #1,a1
        movea.l (sp)+,a0
        rts

; text_copy_max: A0 = text, D0.w = most characters to copy; appended at A1.
text_copy_max:
        movem.l d0/a0,-(sp)
        bra.s   .test
.copy:
        move.b  (a0)+,(a1)
        beq.s   .done
        addq.l  #1,a1
.test:
        dbf     d0,.copy
        clr.b   (a1)
.done:
        movem.l (sp)+,d0/a0
        rts

; text_pad: spaces at A1 until A1 is D0.l (a column of the line).
text_pad:
        cmpa.l  d0,a1
        bcc.s   .done
        move.b  #' ',(a1)+
        bra.s   text_pad
.done:
        clr.b   (a1)
        rts

; text_hex32: D0.l as eight hexadecimal digits at A1.
text_hex32:
        movem.l d0-d2,-(sp)
        moveq   #7,d2
.digit:
        rol.l   #4,d0
        move.b  d0,d1
        andi.b  #$0F,d1
        addi.b  #'0',d1
        cmpi.b  #'9',d1
        bls.s   .store
        addq.b  #'A'-'9'-1,d1
.store:
        move.b  d1,(a1)+
        dbf     d2,.digit
        bra.s   digits_end

; text_decimal: D0.w unsigned as decimal digits at A1 (no leading zeros).
text_decimal:
        movem.l d0-d2,-(sp)
        andi.l  #$FFFF,d0
        moveq   #-1,d2                  ; digits on the stack, less one
.split:
        divu.w  #10,d0
        swap    d0
        move.w  d0,-(sp)
        clr.w   d0
        addq.w  #1,d2
        swap    d0                      ; the quotient, Z when it is 0
        bne.s   .split
.emit:
        move.w  (sp)+,d1
        addi.b  #'0',d1
        move.b  d1,(a1)+
        dbf     d2,.emit
digits_end:
        clr.b   (a1)
        movem.l (sp)+,d0-d2
        rts

; text_length: A0 = text. D0.l = its length.
text_length:
        move.l  a0,-(sp)
        moveq   #-1,d0
.count:
        addq.l  #1,d0
        tst.b   (a0)+
        bne.s   .count
        movea.l (sp)+,a0
        rts

; text_glyph: D0.b = character. Z clear when the game's own font shows it
; and its text entry accepts it (team.i NAME_GLYPHS).
text_glyph:
        movem.l d1/a0,-(sp)
        lea     glyphs(pc),a0
.next:
        move.b  (a0)+,d1
        beq.s   .no
        cmp.b   d0,d1
        bne.s   .next
        moveq   #1,d1                   ; Z clear
        bra.s   .out
.no:
        moveq   #0,d1                   ; Z set
.out:
        movem.l (sp)+,d1/a0
        rts

        include "team.i"
glyphs:
        NAME_GLYPHS
        even
