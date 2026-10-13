; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Dialog service (resident/dialog.s), the technique of the author's Cannon
; Fodder In-Game Level Editor on the game's menu screen. A dialog is a
; full-width panel band drawn from a descriptor: title, a body command list
; (ui.i) and up to DIALOG_MAX_BUTTONS buttons or list rows. Input is the
; joystick in port 2 and the keyboard, exactly as the native menus deliver
; it; there is no pointer. One button holds the focus frame: directions
; move it, Fire or Return chooses it, Esc gives the cancel code, and a letter
; or digit chooses the button whose label marks it with an underscore.
; Everything is drawn into both native display buffers.
;
; Calls (all registers but D0 preserved):
;   dialog_open    A0 = descriptor, D2.l = disabled mask (bit n = button n)
;                  -> D0.l = 0
;   dialog_poll    D7.w = native menu event bits, D6.w = translated key
;                  -> D0.l = -1 while nothing is chosen, else the chosen
;                  button's code or the cancel code; flags set from D0
;   dialog_set     D2.w = button index, D3.w = state (UI_NORMAL, UI_ACTIVE,
;                  UI_DISABLED), A0 = new label or 0 to keep it; redraws it
;   dialog_draw    A0 = UI command list drawn into the panel (screen
;                  coordinates), in both buffers

; Descriptor, word aligned; addresses are absolute (relocated with the image).
DIALOG_TOP          equ 0   ; first screen row of the band
DIALOG_HEIGHT       equ 2   ; rows, at least DIALOG_MIN_HEIGHT
DIALOG_TITLE_ROLE   equ 4   ; title strip colour role
DIALOG_TITLE        equ 6   ; title string (long)
DIALOG_BODY         equ 10  ; UI command list drawn below the title (long, 0 none)
DIALOG_DEFAULT      equ 14  ; button index focused on open, -1 none
DIALOG_CANCEL       equ 16  ; code returned by Esc, -1 none
DIALOG_COUNT        equ 18  ; buttons, 0..DIALOG_MAX_BUTTONS
DIALOG_BUTTONS      equ 20
DIALOG_MAX_BUTTONS  equ 32
DIALOG_MIN_HEIGHT   equ 24

; Button: x,y,w,h, code, state, label address. The state word holds the UI
; state in its low byte and these flags in its high byte.
DIALOG_REPEAT       equ $100    ; a held Fire repeats the code (native repeat)
DIALOG_ROW_BIT      equ 9
DIALOG_ROW          equ 1<<DIALOG_ROW_BIT   ; drawn as a flat list row
; A value control: while it has the focus, LEFT and RIGHT do not move the
; focus but return its code with DIALOG_DEC or DIALOG_INC added (held
; directions repeat as in the native menus). Codes stay below DIALOG_INC.
DIALOG_SPIN_BIT     equ 10
DIALOG_SPIN         equ 1<<DIALOG_SPIN_BIT
DIALOG_INC          equ $2000
DIALOG_DEC          equ $4000
DIALOG_CODE_MASK    equ DIALOG_INC-1
DIALOG_BUTTON_X     equ 0
DIALOG_BUTTON_Y     equ 2
DIALOG_BUTTON_W     equ 4
DIALOG_BUTTON_H     equ 6
DIALOG_BUTTON_CODE  equ 8
DIALOG_BUTTON_STATE equ 10
DIALOG_BUTTON_LABEL equ 12
DIALOG_BUTTON_BYTES equ 16

; The band covers the visible menu screen width.
DIALOG_BAND_X       equ 16
DIALOG_BAND_WIDTH   equ 320
DIALOG_TITLE_ROWS   equ 11

; Native menu event bits delivered to an entry action (D7) and the
; translated keys the dialog understands.
MENU_EVENT_FIRE     equ $0020
MENU_EVENT_LEFT     equ $0040
MENU_EVENT_RIGHT    equ $0080
MENU_EVENT_UP       equ $0100
MENU_EVENT_DOWN     equ $0200
KEY_RETURN          equ $0D
KEY_ESCAPE          equ $1B
KEY_BACKSPACE       equ $7F
