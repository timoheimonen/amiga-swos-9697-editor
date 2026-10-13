; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; CRC-32/ISO-HDLC routines (reflected polynomial CRC32_POLY, initial value
; -1, final complement), shared by the WHDLoad slave and the editor.
; Each macro emits one subroutine; a part assembles only the ones it uses.
; All routines but CRC32_TABLE_020 (the editor's) use 68000 instructions
; only.

; crc32_update: bitwise, no table.
;   in:  D0.l = running CRC (start with -1), A0 = data, D1.l = length
;   out: D0.l = running CRC, A0 advanced; D1-D3 clobbered
CRC32_BITWISE macro
crc32_update:
        tst.l   d1
        beq.s   .done\@
.byte\@:
        moveq   #0,d2
        move.b  (a0)+,d2
        eor.b   d2,d0
        moveq   #7,d3
.bit\@:
        lsr.l   #1,d0
        bcc.s   .next\@
        eori.l  #CRC32_POLY,d0
.next\@:
        dbf     d3,.bit\@
        subq.l  #1,d1
        bne.s   .byte\@
.done\@:
        rts
        endm

; crc32_make_table: fills the 256-entry lookup table.
;   in:  A0 = 1024-byte table, longword aligned
;   out: A0 advanced past the table; D0-D2 clobbered
CRC32_MAKE_TABLE macro
crc32_make_table:
        moveq   #0,d1
.entry\@:
        move.l  d1,d0
        moveq   #7,d2
.bit\@:
        lsr.l   #1,d0
        bcc.s   .next\@
        eori.l  #CRC32_POLY,d0
.next\@:
        dbf     d2,.bit\@
        move.l  d0,(a0)+
        addq.w  #1,d1
        cmpi.w  #256,d1
        bne.s   .entry\@
        rts
        endm

; crc32_table_update: table driven.
;   in:  D0.l = running CRC (start with -1), A0 = data, D1.l = length,
;        A1 = table made by crc32_make_table
;   out: D0.l = running CRC, A0 advanced; D1-D2 clobbered
CRC32_TABLE macro
crc32_table_update:
        tst.l   d1
        beq.s   .done\@
.byte\@:
        moveq   #0,d2
        move.b  (a0)+,d2
        eor.b   d0,d2
        add.w   d2,d2
        add.w   d2,d2
        lsr.l   #8,d0
        move.l  (a1,d2.w),d2
        eor.l   d2,d0
        subq.l  #1,d1
        bne.s   .byte\@
.done\@:
        rts
        endm

; crc32_table_update for the 68020: the contract of CRC32_TABLE, with a
; scaled index and the table entry in D3 (kept), so a byte takes three
; instructions fewer.
CRC32_TABLE_020 macro
crc32_table_update:
        tst.l   d1
        beq.s   .done\@
        move.l  d3,-(sp)
        moveq   #0,d2                   ; D2 holds only bytes from here
.byte\@:
        move.b  (a0)+,d2
        eor.b   d0,d2
        lsr.l   #8,d0
        move.l  (a1,d2.w*4),d3
        eor.l   d3,d0
        subq.l  #1,d1
        bne.s   .byte\@
        move.l  (sp)+,d3
.done\@:
        rts
        endm
