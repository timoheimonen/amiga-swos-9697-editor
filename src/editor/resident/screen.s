; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Own screens inside the native menu lifecycle.
;
; screen_run (A0 = screen record) is called from a native entry action. It
; runs the native modal child screen_host: one entry without background or
; content, whose action takes every event (mask $FFFF), so the native menu
; tick calls it once per frame with the input it has already read. On the
; first tick the record's open routine draws the screen (dialog_open) and
; SCR_OPENED is set after it; every later tick calls its tick routine with
; D7.w = events and D6.w = the translated key. The paints of either routine
; are batched (dialog_batch): one presented pass per display buffer. When the tick routine returns D0.l <> 0 the child asks to
; exit; menu_run_modal then rebuilds the native parent through its restore
; callback, as for any native child, so no bitmap backup is kept. Opening
; and closing set menu_release_gate, so the Fire that opened or closed the
; screen acts only once, however long it is held.
;
; Screen record: dc.l open routine, dc.l tick routine (both relocated with
; the image; called with A5 = editor base).

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    screen_run
        xdef    screen_host
        xref    editor_base
        xref    dialog_batch, dialog_flush
        ifd     EDITOR_TEST_BUILD
        xref    editor_test_poll
        endif

SCREEN_OPEN             equ 0
SCREEN_TICK             equ 4

        section .text,code

; screen_run: A0 = screen record. Returns when the screen has closed and
; the native parent has been rebuilt. Preserves every register.
screen_run:
        movem.l d0-d7/a0-a6,-(sp)
        bsr.l   dialog_flush            ; a screen's kept paints are its own
        movea.l editor_base,a5
        move.l  a0,WORK_SCREEN+SCR_RECORD(a5)
        clr.w   WORK_SCREEN+SCR_OPENED(a5)
        move.w  #1,menu_release_gate
        lea     screen_host(pc),a6
        jsr     menu_run_modal
        movem.l (sp)+,d0-d7/a0-a6
        rts

; Native action of the host entry: D7.w = events (the tick saves and
; restores D0-D7/A0-A6 around it).
screen_tick:
        movea.l editor_base,a5
        movea.l WORK_SCREEN+SCR_RECORD(a5),a3
        bsr.l   dialog_batch            ; the routine's paints come together
        tst.w   WORK_SCREEN+SCR_OPENED(a5)
        bne.s   .tick
        movea.l SCREEN_OPEN(a3),a0
        jsr     (a0)
        bsr.l   dialog_flush
        movea.l editor_base,a5          ; drawn: input now reaches the tick
        move.w  #1,WORK_SCREEN+SCR_OPENED(a5)
        rts
.tick:
        moveq   #0,d6
        move.w  keyboard_translated_key,d6
        ifd     EDITOR_TEST_BUILD
        jsr     editor_test_poll
        endif
        movea.l SCREEN_TICK(a3),a0
        jsr     (a0)
        bsr.l   dialog_flush            ; keeps D0
        tst.l   d0
        beq.s   .open
        move.w  #1,menu_release_gate
        jsr     menu_request_exit
.open:
        rts

; The host child: one invisible entry that receives every event. Its size
; is 0 x 0, so the native outline of the selected entry is not drawn
; ($1A14B0 skips an entry without width and height).
screen_host:
        dc.l    0,0,0,0                 ; init, restore, redraw, selected 0
        dc.w    0,0,0,0
        dc.w    14,$FFFF
        dc.l    screen_tick
        dc.w    0
        dc.w    $FC19
        even
