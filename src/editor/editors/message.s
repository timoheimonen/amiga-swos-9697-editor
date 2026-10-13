; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Messages and questions of the editors: a title and up to MSG_LINE_COUNT
; lines in a dialog band with OK, or with YES and NO (Esc answers NO, NO is
; focused first).
;
; Start a message with message_title, fill its lines with message_line or
; message_lines (fixed texts, one per line, packed: each ends with a NUL and
; an empty text ends them), then
;   - from a native menu action or flow: message_show (OK) or message_ask
;     (YES/NO) run the dialog as a modal child, so the native parent is
;     rebuilt afterwards; message_ask returns D0.l = 1 for YES, 0 for NO;
;     message_note (A0 = title, A1 = packed lines) does all three for a
;     message of fixed texts;
;   - inside an editor screen: message_open (D0.w = MSG_OK or MSG_ASK)
;     replaces the screen's dialog, and message_poll (D7.w events, D6.w key)
;     returns D0.l = -1 while it is open, else the answer; the screen then
;     draws its own dialog again.
; message_title, message_line, message_lines, message_note and message_show
; preserve every register; message_ask, message_open (0) and message_poll
; (flags set from it) return D0.l; message_storage_reason returns A0.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "ui.i"
        include "dialog.i"

        xdef    message_title, message_line, message_lines, message_note
        xdef    message_show, message_ask, message_open, message_poll
        xdef    message_storage_reason
        xdef    ok_text, cancel_text, previous_text, next_text, back_text
        xref    dialog_open, dialog_poll
        xref    screen_run
        xref    editor_base, editor_image
        xref    text_copy_max

ANSWER_NO               equ MSG_NO
ANSWER_YES              equ MSG_YES
TOP                     equ 72
HEIGHT                  equ 96
LINE_Y                  equ TOP+20
BUTTON_Y                equ TOP+HEIGHT-20

        section .text,code

; message_state: A4 = message state.
message_state:
        movea.l editor_base,a4
        lea     WORK_MESSAGE(a4),a4
        rts

; message_title: A0 = title text. Starts a new message: no lines yet.
message_title:
        movem.l d0/a1/a4,-(sp)
        bsr.s   message_state
        movea.l a4,a1
        moveq   #MSG_SIZE/2-1,d0
.clear:
        clr.w   (a1)+
        dbf     d0,.clear
        lea     MSG_TITLE(a4),a1
        moveq   #MSG_LINES-MSG_TITLE-1,d0
        bsr.l   text_copy_max
        movem.l (sp)+,d0/a1/a4
        rts

; message_line: D0.w = line, A0 = text (cut to the line's capacity).
message_line:
        movem.l d0/a1/a4,-(sp)
        bsr.w   message_state
        cmpi.w  #MSG_LINE_COUNT,d0
        bcc.s   .done
        mulu.w  #MSG_LINE_SIZE,d0
        lea     MSG_LINES(a4,d0.w),a1
        moveq   #MSG_LINE_SIZE-1,d0
        bsr.l   text_copy_max
.done:
        movem.l (sp)+,d0/a1/a4
        rts

; message_lines: D0.w = first line, A0 = packed texts, one per line.
message_lines:
        movem.l d0/a0,-(sp)
.line:
        tst.b   (a0)
        beq.s   .done
        bsr.s   message_line
.skip:
        tst.b   (a0)+
        bne.s   .skip
        addq.w  #1,d0
        bra.s   .line
.done:
        movem.l (sp)+,d0/a0
        rts

; message_note: A0 = title, A1 = packed texts from line 0, shown with OK.
message_note:
        bsr.s   message_title
        movem.l d0/a0,-(sp)
        movea.l a1,a0
        moveq   #0,d0
        bsr.s   message_lines
        movem.l (sp)+,d0/a0
        ; then message_show

; message_show: OK message as a modal child of the current native menu.
message_show:
        move.l  d0,-(sp)
        moveq   #MSG_OK,d0
        bsr.s   run_modal
        move.l  (sp)+,d0
        rts

; message_ask: YES/NO question as a modal child. D0.l = answer.
message_ask:
        moveq   #MSG_ASK,d0
; run_modal: D0.w = MSG_OK or MSG_ASK. D0.l = the answer.
run_modal:
        movem.l a0/a4,-(sp)
        bsr.w   message_state
        move.w  d0,MSG_KIND(a4)
        move.w  #ANSWER_NO,MSG_ANSWER(a4)
        lea     message_screen(pc),a0
        bsr.l   screen_run
        moveq   #0,d0
        move.w  MSG_ANSWER(a4),d0
        movem.l (sp)+,a0/a4
        rts

message_screen:
        dc.l    modal_open
        dc.l    modal_tick

; Screen record routines (resident/screen.s): A5 = editor base.
modal_open:
        move.w  WORK_MESSAGE+MSG_KIND(a5),d0
        bra.s   message_open

modal_tick:
        bsr.s   message_poll
        bmi.s   .stay
        move.w  d0,WORK_MESSAGE+MSG_ANSWER(a5)
        moveq   #1,d0
        rts
.stay:
        moveq   #0,d0
        rts

; message_open: D0.w = MSG_OK or MSG_ASK.
message_open:
        movem.l d2/a0,-(sp)
        lea     ok_dialog(pc),a0
        cmpi.w  #MSG_ASK,d0
        bne.s   .open
        lea     ask_dialog(pc),a0
.open:
        moveq   #0,d2
        bsr.l   dialog_open
        movem.l (sp)+,d2/a0
        moveq   #0,d0
        rts

; message_poll: D7.w = events, D6.w = key. D0.l = -1 or the answer.
message_poll:
        bra.l   dialog_poll

; message_storage_reason: D0.l = result of a storage call (slave.i), D1.w =
; 0 for a read, 1 for a write. A0 = the approved message for it.
message_storage_reason:
        lea     reason_write_protected(pc),a0
        cmpi.l  #FSE_WRITE_PROTECTED,d0
        beq.s   .done
        lea     reason_too_many(pc),a0
        cmpi.l  #STE_DIR_FULL,d0
        beq.s   .done
        cmpi.l  #STE_SAVES_FULL,d0
        beq.s   .done
        lea     reason_damaged(pc),a0
        cmpi.l  #STE_VERIFY,d0
        beq.s   .done
        cmpi.l  #STE_CHANGED,d0
        beq.s   .done
        cmpi.l  #STE_TOO_LARGE,d0
        beq.s   .done
        cmpi.l  #STE_SHORT_READ,d0
        beq.s   .done
        lea     reason_read(pc),a0
        tst.w   d1
        beq.s   .done
        lea     reason_disk_full(pc),a0
.done:
        rts

; ---------------------------------------------------------------------------
; Dialogs
; ---------------------------------------------------------------------------
LINE    macro
        dc.w    UI_TEXT_AT,DIALOG_BAND_X+8,LINE_Y+\1*10,DIALOG_BAND_WIDTH-16,UI_INK,UI_CENTER
        dc.l    editor_image+WORK_MESSAGE+MSG_LINES+\1*MSG_LINE_SIZE
        endm

message_body:
        LINE    0
        LINE    1
        LINE    2
        LINE    3
        dc.w    UI_END

ok_dialog:
        dc.w    TOP,HEIGHT,UI_SELECT
        dc.l    editor_image+WORK_MESSAGE+MSG_TITLE
        dc.l    message_body
        dc.w    0,ANSWER_NO,1
        dc.w    136,BUTTON_Y,80,13,ANSWER_NO,UI_NORMAL
        dc.l    ok_text

ask_dialog:
        dc.w    TOP,HEIGHT,UI_WARN
        dc.l    editor_image+WORK_MESSAGE+MSG_TITLE
        dc.l    message_body
        dc.w    1,ANSWER_NO,2
        dc.w    96,BUTTON_Y,64,13,ANSWER_YES,UI_NORMAL
        dc.l    yes_text
        dc.w    192,BUTTON_Y,64,13,ANSWER_NO,UI_NORMAL
        dc.l    no_text

reason_write_protected: dc.b    'WRITE PROTECTED',0
reason_too_many:        dc.b    'TOO MANY FILES',0
reason_damaged:         dc.b    'FILE DAMAGED',0
reason_read:            dc.b    'READ ERROR',0
reason_disk_full:       dc.b    'DISK FULL',0
; Button labels the editors' dialogs share.
ok_text:        dc.b    '_OK',0
cancel_text:    dc.b    '_CANCEL',0
previous_text:  dc.b    '_PREVIOUS',0
next_text:      dc.b    '_NEXT',0
back_text:      dc.b    '_BACK',0
yes_text:       dc.b    '_YES',0
no_text:        dc.b    '_NO',0
        even
