; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Text and widget service (resident/ui.s), the technique of the author's
; Cannon Fodder In-Game Level Editor: a command list drawn into a four-plane
; bitmap with a 5x7 font in 6x8 cells and colour roles.
;
; ui_draw: A0 = command list, A1 = target, D1.w = number of commands to draw
; (0 = up to UI_END). D0.l = 0 drawn, 10 refused (odd address or unknown
; opcode; commands before it are drawn); all other registers are preserved.
UI_CELL_WIDTH       equ 6
UI_LINE_HEIGHT      equ 8
UI_GLYPH_ROWS       equ 7

; The game's menu screen: interleaved planes, rows of four 44-byte plane
; lines (352 pixels), 273 rows; screen coordinates are pixels from its start.
UI_PLANES           equ 4
UI_PLANE_BYTES      equ 44
UI_ROW_BYTES        equ UI_PLANES*UI_PLANE_BYTES
UI_SCREEN_WIDTH     equ UI_PLANE_BYTES*8
UI_SCREEN_ROWS      equ 272

; Target: plane 0 address, bytes from one plane to the next, and a 16-byte
; table mapping the roles below to colour indices 0-15.
UI_TARGET_PLANE     equ 0
UI_TARGET_STRIDE    equ 4
UI_TARGET_ROLES     equ 8
UI_TARGET_BYTES     equ 12

; Commands: one opcode word followed by word arguments. Inline strings end
; with a zero byte and are padded to an even address.
UI_END              equ 0
UI_RECT             equ 1   ; x,y,w,h,role
UI_TEXT             equ 2   ; x,y,w,role,align, inline string
UI_TEXT_AT          equ 3   ; x,y,w,role,align, string address (long)
UI_BUTTON_AT        equ 4   ; x,y,w,h,state, label address (long)
UI_ROW_AT           equ 5   ; x,y,w,h,state, label address (long): flat list row
UI_LAST_COMMAND     equ 5

; Text alignment within the field [x,x+w).
UI_LEFT             equ 0
UI_CENTER           equ 1
UI_RIGHT            equ 2
UI_LEFT_CLIPPED     equ 3   ; left, cut after the last glyph that fits

; Button states. A button label may mark its key with an underscore before
; the letter ("_Save"): the letter is underlined and the underscore is not
; drawn. List rows draw their labels as they are.
UI_NORMAL           equ 0
UI_HOVER            equ 1
UI_ACTIVE           equ 2
UI_DISABLED         equ 3
UI_DEFAULT          equ 4
UI_DEFAULT_HOVER    equ 5
UI_DEFAULT_ACTIVE   equ 6   ; selected or held down, and framed
UI_KEY_MARK         equ '_'

; Colour roles.
UI_BG               equ 0
UI_PANEL            equ 1
UI_FACE             equ 2
UI_FACE_HOVER       equ 3
UI_LIGHT            equ 4
UI_SHADOW           equ 5
UI_INK              equ 6
UI_DIM              equ 7
UI_ACCENT           equ 8
UI_SELECT           equ 9
UI_ERROR            equ 10
UI_OK               equ 11
UI_WARN             equ 12
UI_ROLE_COUNT       equ 13

; Role table for the game's own menu palette (colour indices of the
; front-end palette: 0 $001, 1 $AAB, 2 $FFF, 3 $102, 6 $F71, 7 $667,
; 8 $204, 9 $445, 10 $F00, 11 $00F, 14 $380, 15 $FF0), so the editor's
; screens look like the native menus around them.
UI_MENU_ROLES       macro
        dc.b    0,8,9,7,1,3,2,7,15,11,10,14,6,0,0,0
        endm
