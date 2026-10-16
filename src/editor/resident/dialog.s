; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Dialog service (see dialog.i): descriptors, panel, buttons, list rows and
; focus as in the author's Cannon Fodder In-Game Level Editor, driven by the
; native menu input and drawn with ui_draw into both display buffers of the
; game's menu screen. The state lives in the working data (WORK_DIALOG).

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    dialog_open
        xdef    dialog_poll
        xdef    dialog_set
        xdef    dialog_draw
        xdef    dialog_paint
        xdef    dialog_batch, dialog_flush

        xref    ui_draw
        xref    editor_base

        section .text,code

; dialog_state: A4 = dialog state.
dialog_state:
        movea.l editor_base,a4
        lea     WORK_DIALOG(a4),a4
        rts

; ---------------------------------------------------------------------------
; dialog_open: A0 = descriptor, D2.l = disabled mask. D0.l = 0.
; ---------------------------------------------------------------------------
dialog_open:
        movem.l d1-d7/a0-a6,-(sp)
        bsr.s   dialog_state
        bsr.w   flush_queue             ; kept paints belong to the dialog before
        move.l  a0,DLG_DESCRIPTOR(a4)
        move.l  d2,DLG_DISABLED(a4)
        moveq   #0,d0
        move.w  DIALOG_COUNT(a0),d0
        cmpi.w  #DIALOG_MAX_BUTTONS,d0
        bls.s   .count
        moveq   #DIALOG_MAX_BUTTONS,d0
.count:
        move.w  d0,DLG_COUNT(a4)
        lea     DIALOG_BUTTONS(a0),a1
        moveq   #0,d1
.button:
        cmp.w   d0,d1
        bcc.s   .focus
        move.w  DIALOG_BUTTON_STATE(a1),d3
        btst    d1,d2
        beq.s   .enabled
        andi.w  #$FF00,d3
        ori.w   #UI_DISABLED,d3
.enabled:
        move.w  d1,d4
        add.w   d4,d4
        move.w  d3,DLG_STATES(a4,d4.w)
        add.w   d4,d4
        move.l  DIALOG_BUTTON_LABEL(a1),DLG_LABELS(a4,d4.w)
        lea     DIALOG_BUTTON_BYTES(a1),a1
        addq.w  #1,d1
        bra.s   .button
.focus:
        move.w  DIALOG_DEFAULT(a0),d1
        bsr.w   enabled_index           ; D1 = usable focus or -1
        move.w  d1,DLG_FOCUS(a4)
        lea     paint_all(pc),a2
        bsr.w   dialog_paint
        moveq   #0,d0
        movem.l (sp)+,d1-d7/a0-a6
        rts

; enabled_index: D1.w = wanted index. D1.w = it when enabled, else the first
; enabled button, else -1. A4 = state.
enabled_index:
        movem.l d0/d2,-(sp)
        tst.w   d1
        bmi.s   .first
        cmp.w   DLG_COUNT(a4),d1
        bcc.s   .first
        bsr.w   is_enabled
        bne.s   .done
.first:
        moveq   #0,d1
.scan:
        cmp.w   DLG_COUNT(a4),d1
        bcc.s   .none
        bsr.w   is_enabled
        bne.s   .done
        addq.w  #1,d1
        bra.s   .scan
.none:
        moveq   #-1,d1
.done:
        movem.l (sp)+,d0/d2
        rts

; is_enabled: D1.w = index. Z clear when the button is not disabled.
is_enabled:
        move.l  d0,-(sp)
        move.w  d1,d0
        add.w   d0,d0
        cmpi.b  #UI_DISABLED,DLG_STATES+1(a4,d0.w)  ; the state's low byte
        movem.l (sp)+,d0                ; flags kept
        rts

; ---------------------------------------------------------------------------
; dialog_poll: D7.w = menu events, D6.w = translated key.
; D0.l = -1, or the chosen code.
; ---------------------------------------------------------------------------
dialog_poll:
        movem.l d1-d7/a0-a6,-(sp)
        bsr.w   dialog_state
        movea.l DLG_DESCRIPTOR(a4),a0
        cmpi.w  #KEY_ESCAPE,d6
        bne.s   .key
        move.w  DIALOG_CANCEL(a0),d0
        ext.l   d0
        bpl.s   .return
.key:
        bsr.w   shortcut                ; D1 = button marked with the key
        bpl.s   .choose
        moveq   #3,d2                   ; direction 0 left, 1 right, 2 up, 3 down
        move.w  #MENU_EVENT_DOWN,d3
.direction:
        move.w  d7,d0
        and.w   d3,d0
        bne.s   .move
        lsr.w   #1,d3
        dbf     d2,.direction
        btst    #5,d7                   ; MENU_EVENT_FIRE
        beq.s   .nothing
        move.w  DLG_FOCUS(a4),d1
        bmi.s   .nothing
.choose:
        bsr.w   is_enabled
        beq.s   .nothing
        move.w  d1,d0
        lsl.w   #4,d0
        move.w  DIALOG_BUTTONS+DIALOG_BUTTON_CODE(a0,d0.w),d0
        ext.l   d0
        bra.s   .return
.move:
        cmpi.w  #1,d2                   ; LEFT or RIGHT on a value control?
        bhi.s   .focus
        move.w  DLG_FOCUS(a4),d1
        bmi.s   .focus
        move.w  d1,d0
        add.w   d0,d0
        btst    #DIALOG_SPIN_BIT-8,DLG_STATES(a4,d0.w)
        beq.s   .focus
        bsr.w   is_enabled
        beq.s   .nothing
        lsl.w   #3,d0                   ; index*16
        move.w  DIALOG_BUTTONS+DIALOG_BUTTON_CODE(a0,d0.w),d0
        ori.w   #DIALOG_INC,d0
        tst.w   d2
        bne.s   .spin
        eori.w  #DIALOG_INC|DIALOG_DEC,d0
.spin:
        ext.l   d0
        bra.s   .return
.focus:
        bsr.w   move_focus
.nothing:
        moveq   #-1,d0
.return:
        movem.l (sp)+,d1-d7/a0-a6
        rts

; shortcut: D6.w = key, A0 = descriptor, A4 = state. D1.w = index of the
; enabled button whose label marks the key with UI_KEY_MARK, else -1 (N set).
; List rows have no key marks: their labels (file and player names) are
; drawn as they are, so an underscore in them is no shortcut.
shortcut:
        movem.l d0/d2/a1-a2,-(sp)
        moveq   #-1,d1
        move.w  d6,d0
        cmpi.w  #'0',d0
        bcs.s   .done
        cmpi.w  #'9',d0
        bls.s   .search
        cmpi.w  #'A',d0
        bcs.s   .done
        cmpi.w  #'Z',d0
        bhi.s   .done
.search:
        moveq   #0,d2
.button:
        cmp.w   DLG_COUNT(a4),d2
        bcc.s   .done
        move.w  d2,d1
        add.w   d1,d1
        btst    #DIALOG_ROW_BIT-8,DLG_STATES(a4,d1.w)
        bne.s   .next
        add.w   d1,d1
        movea.l DLG_LABELS(a4,d1.w),a1
.char:
        move.b  (a1)+,d1
        beq.s   .next
        cmpi.b  #UI_KEY_MARK,d1
        bne.s   .char
        move.b  (a1),d1
        cmpi.b  #'a',d1
        bcs.s   .upper
        subi.b  #'a'-'A',d1
.upper:
        cmp.b   d0,d1
        bne.s   .next
        move.w  d2,d1
        bsr.w   is_enabled
        bne.s   .found
.next:
        addq.w  #1,d2
        bra.s   .button
.found:
        move.w  d2,d1
        bra.s   .out
.done:
        moveq   #-1,d1
.out:
        movem.l (sp)+,d0/d2/a1-a2
        tst.w   d1
        rts

; move_focus: D2.w = direction (0 left, 1 right, 2 up, 3 down). Moves the
; focus to the nearest enabled button in that direction (forward distance of
; the centres plus twice the sideways distance; eight times for LEFT and
; RIGHT, so a button on the same line wins over a wide row above it) and
; repaints both buttons.
move_focus:
        movem.l d0-d7/a0-a2,-(sp)
        move.w  DLG_FOCUS(a4),d7
        bmi.w   .done
        move.w  d7,d0
        bsr.w   centre                  ; D0 = x, D1 = y of the focus
        move.w  d0,d4
        move.w  d1,d5
        moveq   #-1,d6                  ; best index
        move.l  #$7FFF,d3               ; best score
        moveq   #0,d0
.candidate:
        cmp.w   DLG_COUNT(a4),d0
        bcc.s   .chosen
        cmp.w   d7,d0
        beq.s   .skip
        move.w  d0,d1
        bsr.w   is_enabled
        beq.s   .skip
        movem.l d0/d3,-(sp)
        bsr.w   centre
        sub.w   d4,d0                   ; dx
        sub.w   d5,d1                   ; dy
        cmpi.w  #2,d2
        bcs.s   .horizontal
        exg     d0,d1                   ; vertical: forward is dy
        cmpi.w  #2,d2
        beq.s   .negate
        bra.s   .score
.horizontal:
        tst.w   d2
        bne.s   .score
.negate:
        neg.w   d0                      ; left and up look backwards
.score:
        tst.w   d1
        bpl.s   .side
        neg.w   d1
.side:
        add.w   d1,d1
        cmpi.w  #2,d2
        bcc.s   .vertical
        lsl.w   #2,d1                   ; LEFT/RIGHT: 8 * sideways
.vertical:
        add.w   d0,d1                   ; forward + 2 * sideways
        tst.w   d0
        movem.l (sp)+,d0/d3
        ble.s   .skip                   ; not in that direction
        ext.l   d1
        cmp.l   d3,d1
        bge.s   .skip
        move.l  d1,d3
        move.w  d0,d6
.skip:
        addq.w  #1,d0
        bra.s   .candidate
.chosen:
        tst.w   d6
        bmi.s   .done
        move.w  d6,DLG_FOCUS(a4)
        move.w  d7,d0
        swap    d0
        move.w  d6,d0
        bsr.w   repaint_pair
.done:
        movem.l (sp)+,d0-d7/a0-a2
        rts

; centre: D0.w = index, A0 = descriptor. D0.w = x, D1.w = y of its centre.
centre:
        move.l  a1,-(sp)
        lsl.w   #4,d0
        lea     DIALOG_BUTTONS(a0,d0.w),a1
        move.w  DIALOG_BUTTON_W(a1),d0
        lsr.w   #1,d0
        add.w   DIALOG_BUTTON_X(a1),d0
        move.w  DIALOG_BUTTON_H(a1),d1
        lsr.w   #1,d1
        add.w   DIALOG_BUTTON_Y(a1),d1
        movea.l (sp)+,a1
        rts

; ---------------------------------------------------------------------------
; dialog_set: D2.w = index, D3.w = state, A0 = label or 0. Repaints it.
; ---------------------------------------------------------------------------
dialog_set:
        movem.l d0-d7/a0-a6,-(sp)
        bsr.w   dialog_state
        cmp.w   DLG_COUNT(a4),d2
        bcc.s   .done
        move.w  d2,d0
        add.w   d0,d0
        move.w  DLG_STATES(a4,d0.w),d1
        andi.w  #$FF00,d1
        andi.w  #$00FF,d3
        or.w    d3,d1
        move.w  d1,DLG_STATES(a4,d0.w)
        cmpa.w  #0,a0
        beq.s   .paint
        add.w   d0,d0
        move.l  a0,DLG_LABELS(a4,d0.w)
.paint:
        cmp.w   DLG_FOCUS(a4),d2
        bne.s   .one
        move.w  d2,d1                   ; a disabled focus moves on
        bsr.w   is_enabled
        bne.s   .one
        bsr.w   enabled_index
        move.w  d1,DLG_FOCUS(a4)
.one:
        move.w  d2,d0
        swap    d0
        move.w  DLG_FOCUS(a4),d0
        bsr.s   repaint_pair
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; repaint_pair: D0.l = two button indexes (high and low word, -1 none),
; A4 = state. Repaints both; changes A2.
repaint_pair:
        move.l  d0,DLG_PAINT_ARG(a4)
        lea     paint_pair(pc),a2
        bra.s   dialog_paint

; ---------------------------------------------------------------------------
; dialog_draw: A0 = command list, drawn in both buffers.
; ---------------------------------------------------------------------------
dialog_draw:
        movem.l d0-d7/a0-a6,-(sp)
        bsr.w   dialog_state
        move.l  a0,DLG_PAINT_ARG(a4)
        lea     paint_list(pc),a2
        bsr.s   dialog_paint
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; dialog_paint: A2 = paint routine, called once per display buffer with
; A1 = UI target of that buffer and A4 = state; each pass is presented.
; Within a batch the routine is kept with DLG_PAINT_ARG instead, and the
; kept routines are painted together, in order.
; ---------------------------------------------------------------------------
dialog_paint:
        movem.l d0-d7/a0-a6,-(sp)
        bsr.w   dialog_state
        tst.w   DLG_BATCH(a4)
        beq.s   .now
        move.w  DLG_QUEUED(a4),d0
        cmpi.w  #DLG_QUEUE_MAX,d0
        bcs.s   .keep
        bsr.s   flush_queue             ; full: the kept ones first
        moveq   #0,d0
.keep:
        lsl.w   #3,d0
        move.l  a2,DLG_QUEUE(a4,d0.w)
        move.l  DLG_PAINT_ARG(a4),DLG_QUEUE+4(a4,d0.w)
        addq.w  #1,DLG_QUEUED(a4)
        bra.s   .done
.now:
        bsr.s   paint_passes
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; paint_passes: A2 = paint routine, A4 = state. One pass per display
; buffer, each presented. Changes D0-D7/A0-A1/A3/A5-A6.
paint_passes:
        moveq   #1,d7
.pass:
        lea     DLG_TARGET(a4),a1
        movea.l display_draw_buffer,a0
        move.w  display_scroll_y,d0
        mulu.w  #UI_ROW_BYTES,d0
        adda.l  d0,a0
        move.w  display_scroll_x,d0
        lsr.w   #3,d0
        andi.w  #$FFFE,d0
        adda.w  d0,a0
        move.l  a0,UI_TARGET_PLANE(a1)
        move.l  #UI_PLANE_BYTES,UI_TARGET_STRIDE(a1)
        lea     menu_roles(pc),a0
        move.l  a0,UI_TARGET_ROLES(a1)
        movem.l d7/a2,-(sp)
        jsr     (a2)
        movem.l (sp)+,d7/a2
        jsr     display_wait_present
        dbf     d7,.pass
        rts

; flush_queue: A4 = state. Paints the kept routines (if any) and empties
; the queue. Preserves all registers.
flush_queue:
        tst.w   DLG_QUEUED(a4)
        beq.s   .done
        movem.l d0-d7/a0-a6,-(sp)
        lea     paint_queue(pc),a2
        bsr.s   paint_passes
        clr.w   DLG_QUEUED(a4)
        movem.l (sp)+,d0-d7/a0-a6
.done:
        rts

; paint_queue: the kept routines in order, each with its DLG_PAINT_ARG
; (A1 = target, A4 = state).
paint_queue:
        lea     DLG_QUEUE(a4),a6
        move.w  DLG_QUEUED(a4),d6
        subq.w  #1,d6
.entry:
        movea.l (a6)+,a2
        move.l  (a6)+,DLG_PAINT_ARG(a4)
        movem.l d6/a1/a6,-(sp)
        jsr     (a2)
        movem.l (sp)+,d6/a1/a6
        dbf     d6,.entry
        rts

; ---------------------------------------------------------------------------
; dialog_batch: the dialog's paints are kept from now until dialog_flush,
; which paints them together: two presented passes instead of two for each
; (resident/screen.s around the open and tick routines of a screen; a new
; dialog_open first paints what was kept for the dialog before it).
; dialog_flush: paints what was kept and ends the batch. Both preserve all
; registers.
; ---------------------------------------------------------------------------
dialog_batch:
        move.l  a4,-(sp)
        bsr.w   dialog_state
        move.w  #1,DLG_BATCH(a4)
        movea.l (sp)+,a4
        rts

dialog_flush:
        move.l  a4,-(sp)
        bsr.w   dialog_state
        clr.w   DLG_BATCH(a4)
        bsr.s   flush_queue
        movea.l (sp)+,a4
        rts

; Paint routines: A1 = target, A4 = state.
paint_list:
        movea.l DLG_PAINT_ARG(a4),a0
        moveq   #0,d1
        bra.l   ui_draw

paint_all:
        movea.l DLG_DESCRIPTOR(a4),a3
        lea     DLG_COMMANDS(a4),a0
        move.w  DIALOG_TOP(a3),d2
        move.w  DIALOG_HEIGHT(a3),d3
        move.w  #UI_RECT,(a0)+           ; band
        move.w  #DIALOG_BAND_X,(a0)+
        move.w  d2,(a0)+
        move.w  #DIALOG_BAND_WIDTH,(a0)+
        move.w  d3,(a0)+
        move.w  #UI_PANEL,(a0)+
        move.w  #UI_RECT,(a0)+           ; light line
        move.w  #DIALOG_BAND_X,(a0)+
        move.w  d2,d0
        addq.w  #1,d0
        move.w  d0,(a0)+
        move.w  #DIALOG_BAND_WIDTH,(a0)+
        move.w  #1,(a0)+
        move.w  #UI_LIGHT,(a0)+
        move.w  #UI_RECT,(a0)+           ; title strip
        move.w  #DIALOG_BAND_X,(a0)+
        addq.w  #1,d0
        move.w  d0,(a0)+
        move.w  #DIALOG_BAND_WIDTH,(a0)+
        move.w  #DIALOG_TITLE_ROWS,(a0)+
        move.w  DIALOG_TITLE_ROLE(a3),(a0)+
        move.w  #UI_TEXT_AT,(a0)+        ; title text
        move.w  #DIALOG_BAND_X+8,(a0)+
        addq.w  #2,d0
        move.w  d0,(a0)+
        move.w  #DIALOG_BAND_WIDTH-16,(a0)+
        move.w  #UI_INK,(a0)+
        move.w  #UI_LEFT_CLIPPED,(a0)+
        move.l  DIALOG_TITLE(a3),(a0)+
        move.w  #UI_RECT,(a0)+           ; shadow line
        move.w  #DIALOG_BAND_X,(a0)+
        move.w  d2,d0
        add.w   d3,d0
        subq.w  #1,d0
        move.w  d0,(a0)+
        move.w  #DIALOG_BAND_WIDTH,(a0)+
        move.w  #1,(a0)+
        move.w  #UI_SHADOW,(a0)+
        move.w  #UI_END,(a0)+
        lea     DLG_COMMANDS(a4),a0
        moveq   #0,d1
        bsr.l   ui_draw
        move.l  DIALOG_BODY(a3),d0
        beq.s   .buttons
        movea.l d0,a0
        moveq   #0,d1
        bsr.l   ui_draw
.buttons:
        moveq   #0,d0
.button:
        cmp.w   DLG_COUNT(a4),d0
        bcc.s   .done
        bsr.s   paint_button
        addq.w  #1,d0
        bra.s   .button
.done:
        rts

; paint_pair: repaints the buttons in the high and low word of DLG_PAINT_ARG.
paint_pair:
        move.l  DLG_PAINT_ARG(a4),d0
        swap    d0
        tst.w   d0
        bmi.s   .second
        bsr.s   paint_button
.second:
        swap    d0
        tst.w   d0
        bmi.s   .done
        bsr.s   paint_button
.done:
        rts

; paint_button: D0.w = index; A1 = target, A4 = state. Clears the frame
; area to the panel, then draws the button or row in its shown state.
paint_button:
        movem.l d0-d4/a0-a3,-(sp)
        movea.l DLG_DESCRIPTOR(a4),a3
        move.w  d0,d4
        lsl.w   #4,d0
        lea     DIALOG_BUTTONS(a3,d0.w),a2
        move.w  d4,d0
        add.w   d0,d0
        move.w  DLG_STATES(a4,d0.w),d1   ; flags and state
        move.w  d1,d2
        andi.w  #$00FF,d2
        cmp.w   DLG_FOCUS(a4),d4
        bne.s   .shown
        btst    #DIALOG_ROW_BIT,d1
        bne.s   .row_focus
        addq.w  #UI_DEFAULT_HOVER-UI_NORMAL,d2  ; NORMAL->DEFAULT_HOVER
        cmpi.w  #UI_DEFAULT_HOVER,d2
        beq.s   .shown
        moveq   #UI_DEFAULT_ACTIVE,d2   ; ACTIVE (or HOVER) -> framed active
        bra.s   .shown
.row_focus:
        cmpi.w  #UI_ACTIVE,d2
        beq.s   .shown
        moveq   #UI_HOVER,d2
.shown:
        lea     DLG_COMMANDS(a4),a0
        move.w  #UI_RECT,(a0)+
        move.w  DIALOG_BUTTON_X(a2),d3
        subq.w  #1,d3
        move.w  d3,(a0)+
        move.w  DIALOG_BUTTON_Y(a2),d3
        subq.w  #1,d3
        move.w  d3,(a0)+
        move.w  DIALOG_BUTTON_W(a2),d3
        addq.w  #2,d3
        move.w  d3,(a0)+
        move.w  DIALOG_BUTTON_H(a2),d3
        addq.w  #2,d3
        move.w  d3,(a0)+
        move.w  #UI_PANEL,(a0)+
        move.w  #UI_BUTTON_AT,d3
        btst    #DIALOG_ROW_BIT,d1
        beq.s   .kind
        move.w  #UI_ROW_AT,d3
.kind:
        move.w  d3,(a0)+
        move.l  DIALOG_BUTTON_X(a2),(a0)+       ; x, y
        move.l  DIALOG_BUTTON_W(a2),(a0)+       ; w, h
        move.w  d2,(a0)+
        move.w  d4,d3
        add.w   d3,d3
        add.w   d3,d3
        move.l  DLG_LABELS(a4,d3.w),(a0)+
        move.w  #UI_END,(a0)+
        lea     DLG_COMMANDS(a4),a0
        moveq   #0,d1
        bsr.l   ui_draw
        movem.l (sp)+,d0-d4/a0-a3
        rts

menu_roles:
        UI_MENU_ROLES
        even
