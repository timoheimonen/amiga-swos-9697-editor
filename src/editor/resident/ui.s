; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Text and widget service (see ui.i), ported from the author's Cannon Fodder
; In-Game Level Editor. Draws a command list into a four-plane bitmap of
; UI_ROW_BYTES-byte rows (the game's interleaved menu screen). The caller
; owns the bitmap and guarantees that every command lies inside it; text is
; clipped only at the right screen edge. The service keeps no state of its
; own, so the editor image stays unchanged in memory.

        include "ui.i"

        xdef    ui_draw

        section .text,code

; A0 = command list, A1 = target, D1.w = commands to draw (0 = all).
; D0.l = 0 drawn, 10 refused; other registers preserved.
ui_draw:
        movem.l d1-d7/a0-a6,-(sp)
        move.w  d1,-(sp)                ; commands left (0 = no limit)
        moveq   #10,d0
        move.l  a0,d1
        move.l  a1,d2
        or.l    d2,d1
        btst    #0,d1
        bne.s   .return
        movea.l UI_TARGET_PLANE(a1),a5
        movea.l UI_TARGET_ROLES(a1),a6
        ; A1 holds the plane stride for every drawing routine below.
        movea.l UI_TARGET_STRIDE(a1),a1
.next:
        move.w  (a0)+,d0
        beq.s   .done
        cmpi.w  #UI_LAST_COMMAND,d0
        bhi.s   .refuse
        add.w   d0,d0
        move.w  .jump-2(pc,d0.w),d0
        jsr     .jump(pc,d0.w)
        tst.w   (sp)
        beq.s   .next
        subq.w  #1,(sp)
        bne.s   .next
.done:
        moveq   #0,d0
.return:
        addq.l  #2,sp
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts
.refuse:
        moveq   #10,d0
        bra.s   .return
.jump:
        dc.w    ui_cmd_rect-.jump,ui_cmd_text-.jump,ui_cmd_text_at-.jump
        dc.w    ui_cmd_button_at-.jump,ui_cmd_row_at-.jump

ui_cmd_rect:
        movem.w (a0)+,d1-d3/d6
        move.w (a0)+,d0
        bsr ui_role
        move.w d0,d4
        bra ui_rect

ui_cmd_text:
        bsr.s ui_text_arguments
        movea.l a0,a2
        bsr ui_text_draw
        bra.s ui_skip_string

ui_cmd_text_at:
        bsr.s ui_text_arguments
        movea.l (a0)+,a2
        bra ui_text_draw

ui_cmd_button_at:
        movem.w (a0)+,d1-d3/d6
        move.w (a0)+,d5
        movea.l (a0)+,a2
        bra ui_button

ui_cmd_row_at:
        movem.w (a0)+,d1-d3/d6
        move.w (a0)+,d5
        movea.l (a0)+,a2
        bra ui_row


; X,Y,W,role,alignment -> D1-D3, colour D4, alignment D5.
ui_text_arguments:
        movem.w (a0)+,d1-d3
        move.w (a0)+,d0
        bsr.s ui_role
        move.w d0,d4
        move.w (a0)+,d5
        rts

; Step A0 over an inline string and its padding byte.
ui_skip_string:
        tst.b (a0)+
        bne.s ui_skip_string
        move.l a0,d0
        addq.l #1,d0
        bclr #0,d0
        movea.l d0,a0
        rts

; D0.w role -> D0.w colour index.
ui_role:
        andi.w #15,d0
        move.b (a6,d0.w),d0
        andi.w #15,d0
        rts

; D1 X, D2 Y, D3 W, D6 H, D4 colour. Edge words are masked; inner words
; are written whole. Preserves all registers.
ui_rect:
        movem.l d0-d7/a2-a4,-(sp)
        tst.w d3
        ble .out
        tst.w d6
        ble .out
        move.w d1,d0
        andi.w #15,d0
        move.w #$ffff,d5
        lsr.w d0,d5
        move.w d1,d0
        add.w d3,d0
        subq.w #1,d0
        move.w d0,d7
        andi.w #15,d7
        addq.w #1,d7
        move.w #$ffff,d3
        lsr.w d7,d3
        not.w d3
        lsr.w #4,d0
        move.w d1,d7
        lsr.w #4,d7
        sub.w d7,d0
        bne.s .wide_masks
        and.w d3,d5
.wide_masks:
        mulu #UI_ROW_BYTES,d2
        add.w d7,d7
        add.w d7,d2
        lea (a5,d2.l),a2
        subq.w #1,d6
.row:
        movea.l a2,a4
        moveq #0,d1
.plane:
        btst d1,d4
        sne d2
        ext.w d2
        movea.l a4,a3
        tst.w d0
        bne.s .wide
        move.w (a3),d7
        eor.w d2,d7
        and.w d5,d7
        eor.w d7,(a3)
        bra.s .plane_next
.wide:
        move.w (a3),d7
        eor.w d2,d7
        and.w d5,d7
        eor.w d7,(a3)+
        move.w d0,d7
        subq.w #2,d7
        bmi.s .last
.middle:
        move.w d2,(a3)+
        dbra d7,.middle
.last:
        move.w (a3),d7
        eor.w d2,d7
        and.w d3,d7
        eor.w d7,(a3)
.plane_next:
        adda.l a1,a4
        addq.w #1,d1
        cmpi.w #UI_PLANES,d1
        blo.s .plane
        lea UI_ROW_BYTES(a2),a2
        dbra d6,.row
.out:
        movem.l (sp)+,d0-d7/a2-a4
        rts

; Four one-pixel edges of D1 X, D2 Y, D3 W, D6 H in colour D4. Preserves all.
ui_frame:
        movem.l d0-d3/d6,-(sp)
        move.w d6,d0
        moveq #1,d6
        bsr ui_rect
        add.w d0,d2
        subq.w #1,d2
        bsr ui_rect
        move.w 10(sp),d2
        move.w d0,d6
        moveq #1,d3
        bsr ui_rect
        add.w 14(sp),d1
        subq.w #1,d1
        bsr ui_rect
        movem.l (sp)+,d0-d3/d6
        rts

; Bevelled button D1 X, D2 Y, D3 W, D6 H, D5 state, A2 label. Preserves all.
ui_button:
        movem.l d0-d7/a2,-(sp)
        moveq #UI_FACE,d0
        cmpi.w #UI_HOVER,d5
        beq.s .hover
        cmpi.w #UI_DEFAULT_HOVER,d5
        beq.s .hover
        cmpi.w #UI_ACTIVE,d5
        beq.s .select
        cmpi.w #UI_DEFAULT_ACTIVE,d5
        bne.s .face
.select:
        moveq #UI_SELECT,d0
        bra.s .face
.hover:
        moveq #UI_FACE_HOVER,d0
.face:
        bsr ui_role
        move.w d0,d4
        bsr ui_rect
        moveq #UI_LIGHT,d0
        bsr ui_role
        move.w d0,d4
        moveq #1,d6
        bsr ui_rect
        moveq #1,d3
        move.w 26(sp),d6
        bsr ui_rect
        moveq #UI_SHADOW,d0
        bsr ui_role
        move.w d0,d4
        move.w 10(sp),d2
        add.w 26(sp),d2
        subq.w #1,d2
        move.w 14(sp),d3
        moveq #1,d6
        bsr ui_rect
        move.w 6(sp),d1
        add.w 14(sp),d1
        subq.w #1,d1
        move.w 10(sp),d2
        moveq #1,d3
        move.w 26(sp),d6
        bsr ui_rect
        cmpi.w #UI_DEFAULT,22(sp)
        blo.s .label
        moveq #UI_ACCENT,d0
        bsr ui_role
        move.w d0,d4
        move.w 6(sp),d1
        subq.w #1,d1
        move.w 10(sp),d2
        subq.w #1,d2
        move.w 14(sp),d3
        addq.w #2,d3
        move.w 26(sp),d6
        addq.w #2,d6
        bsr ui_frame
.label:
        moveq #UI_INK,d0
        cmpi.w #UI_DISABLED,22(sp)
        bne.s .not_disabled
        moveq #UI_DIM,d0
.not_disabled:
        cmpi.w #UI_ACTIVE,22(sp)
        beq.s .accent
        cmpi.w #UI_DEFAULT_ACTIVE,22(sp)
        bne.s .ink
.accent:
        moveq #UI_ACCENT,d0
.ink:
        bsr ui_role
        move.w d0,d4
        move.w 6(sp),d1
        move.w 14(sp),d3
        move.w 26(sp),d2
        subq.w #UI_GLYPH_ROWS,d2
        asr.w #1,d2
        add.w 10(sp),d2
        move.w #UI_CENTER|UI_KEYS,d5
        movea.l 32(sp),a2
        bsr.s ui_text_draw
        movem.l (sp)+,d0-d7/a2
        rts

; Flat list row D1 X, D2 Y, D3 W, D6 H, D5 state, A2 label: panel, hover or
; selection background, the label left-aligned four pixels in. Preserves all.
ui_row:
        movem.l d0-d7/a2,-(sp)
        moveq #UI_PANEL,d0
        cmpi.w #UI_ACTIVE,d5
        bne.s .hover
        moveq #UI_SELECT,d0
        bra.s .fill
.hover:
        cmpi.w #UI_HOVER,d5
        bne.s .fill
        moveq #UI_FACE_HOVER,d0
.fill:
        bsr ui_role
        move.w d0,d4
        bsr ui_rect
        moveq #UI_INK,d0
        cmpi.w #UI_DISABLED,d5
        bne.s .ink
        moveq #UI_DIM,d0
.ink:
        bsr ui_role
        move.w d0,d4
        addq.w #4,d1
        subq.w #4,d3
        move.w d6,d2
        subq.w #UI_GLYPH_ROWS,d2
        asr.w #1,d2
        add.w 10(sp),d2
        ; A long label stops at the row's end instead of running over the
        ; buttons beside the list.
        moveq #UI_LEFT_CLIPPED,d5
        bsr ui_text_draw
        movem.l (sp)+,d0-d7/a2
        rts

; Button labels: an underscore underlines the next glyph and is not drawn.
UI_KEYS             equ $100

; A2 text ending with a zero or $FF byte, D1 X, D2 Y, D3 field width, D4 colour, D5
; alignment, with UI_KEYS for a button label. Preserves all registers.
ui_text_draw:
        movem.l d0-d1/d5-d7/a2-a3,-(sp)
        moveq #0,d7
        bclr #8,d5
        beq.s .plain
        moveq #1,d7
.plain:
        moveq #0,d6
        movea.l a2,a3
.length:
        move.b (a3)+,d0
        beq.s .measured
        cmpi.b #$ff,d0
        beq.s .measured
        tst.w d7
        beq.s .count
        cmpi.b #UI_KEY_MARK,d0
        beq.s .length
.count:
        addq.w #1,d6
        bra.s .length
.measured:
        tst.w d6
        beq.s .out
        cmpi.w #UI_LEFT,d5
        beq.s .draw
        cmpi.w #UI_LEFT_CLIPPED,d5
        bne.s .align
        moveq #0,d0
        move.w d3,d0
        divu #UI_CELL_WIDTH,d0
        cmp.w d0,d6
        bls.s .draw
        move.w d0,d6
        bne.s .draw
        bra.s .out
.align:
        move.w d6,d0
        mulu #UI_CELL_WIDTH,d0
        subq.w #1,d0
        neg.w d0
        add.w d3,d0
        cmpi.w #UI_RIGHT,d5
        beq.s .shift
        asr.w #1,d0
.shift:
        add.w d0,d1
.draw:
        subq.w #1,d6
.char:
        moveq #0,d0
        move.b (a2)+,d0
        tst.w d7
        beq.s .glyph
        cmpi.b #UI_KEY_MARK,d0
        bne.s .glyph
        moveq #2,d7
        bra.s .char
.glyph:
        bsr.s ui_glyph
        cmpi.w #2,d7
        bne.s .advance
        moveq #1,d7
        bsr.s ui_underline
.advance:
        addq.w #UI_CELL_WIDTH,d1
        dbra d6,.char
.out:
        movem.l (sp)+,d0-d1/d5-d7/a2-a3
        rts

; The line under the glyph at D1 X, D2 Y in colour D4, below the descenders.
ui_underline:
        movem.l d2-d3/d6,-(sp)
        addq.w #UI_GLYPH_ROWS+1,d2
        moveq #UI_CELL_WIDTH-1,d3
        moveq #1,d6
        bsr ui_rect
        movem.l (sp)+,d2-d3/d6
        rts

; Character D0 at D1 X, D2 Y in colour D4. Codes outside 33-126 draw
; nothing; so does a glyph that would cross the right screen edge. A glyph
; inside one word is written with word accesses, otherwise with longwords.
; The lower-case letters with descenders sit one row lower, so their tails
; reach the cell's eighth row below the base line.
ui_glyph:
        movem.l d0-d7/a0/a2-a3,-(sp)
        cmpi.w #UI_SCREEN_WIDTH-UI_CELL_WIDTH,d1
        bhi .out
        subi.w #32,d0
        bls .out
        cmpi.w #94,d0
        bhi .out
        moveq #0,d3
        lea ui_descenders(pc),a0
.descender:
        move.b (a0)+,d5
        beq.s .placed
        cmp.b d5,d0
        bne.s .descender
        moveq #1,d3
.placed:
        mulu #UI_GLYPH_ROWS,d0
        lea ui_font(pc),a3
        adda.w d0,a3
        move.w d2,d0
        add.w d3,d0
        mulu #UI_ROW_BYTES,d0
        lea (a5,d0.l),a2
        move.w d1,d0
        lsr.w #4,d0
        add.w d0,d0
        adda.w d0,a2
        move.w d1,d6
        andi.w #15,d6
        moveq #UI_GLYPH_ROWS-1,d7
        cmpi.w #11,d6
        bhi.s .long_row
.word_row:
        moveq #0,d5
        move.b (a3)+,d5
        beq.s .word_next
        lsl.w #8,d5
        lsl.w #3,d5
        lsr.w d6,d5
        move.w d5,d1
        not.w d1
        movea.l a2,a0
        moveq #0,d3
.word_plane:
        btst d3,d4
        beq.s .word_clear
        or.w d5,(a0)
        bra.s .word_advance
.word_clear:
        and.w d1,(a0)
.word_advance:
        adda.l a1,a0
        addq.w #1,d3
        cmpi.w #UI_PLANES,d3
        blo.s .word_plane
.word_next:
        lea UI_ROW_BYTES(a2),a2
        dbra d7,.word_row
        bra.s .out
.long_row:
        moveq #0,d5
        move.b (a3)+,d5
        beq.s .long_next
        ror.l #5,d5
        lsr.l d6,d5
        move.l d5,d1
        not.l d1
        movea.l a2,a0
        moveq #0,d3
.long_plane:
        btst d3,d4
        beq.s .long_clear
        or.l d5,(a0)
        bra.s .long_advance
.long_clear:
        and.l d1,(a0)
.long_advance:
        adda.l a1,a0
        addq.w #1,d3
        cmpi.w #UI_PLANES,d3
        blo.s .long_plane
.long_next:
        lea UI_ROW_BYTES(a2),a2
        dbra d7,.long_row
.out:
        movem.l (sp)+,d0-d7/a0/a2-a3
        rts


        even
ui_descenders:
        dc.b 'g'-32,'j'-32,'p'-32,'q'-32,'y'-32,0
        even
        include "ui_font.i"
        even
