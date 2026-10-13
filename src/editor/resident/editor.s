; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Resident editor: image header, initialization and the main-menu entry.
;
; The WHDLoad slave loads the image at the start of the editor area of the
; expansion memory, checks its length, CRC-32 and header, applies its
; relocation and import tables, builds the CRC-32 table in the working data,
; calls editor_init and then installs the runtime hook table. This object is
; linked first; the build fills the header fields marked "build" after
; linking.
;
; editor_init clears the working data and builds the extended native pages
; (resident/menus.s); the runtime hooks then point the game at them.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "crc32.i"

        xdef    editor_image
        xdef    editor_base
        xdef    crc32_table_update, crc32_buffer
        xref    menus_init, copies_init

        section .text,code
editor_image:
        dc.l    EDH_MAGIC_VALUE
        dc.w    EDH_VERSION_VALUE
        dc.w    0                       ; EDH_FLAGS
        dc.l    0                       ; EDH_LENGTH (build)
        dc.l    editor_init-editor_image ; EDH_INIT
        dc.l    0                       ; EDH_HOOKS (build)
        dc.l    0                       ; EDH_FIXUPS (build)
        dc.l    0                       ; EDH_IMPORTS (build)
        dcb.b   8,0                     ; EDH_IDENTITY (build)
        dc.l    0                       ; EDH_CODE_LENGTH (build)

; The editor base after relocation (this field is in the relocation table).
editor_base:
        dc.l    editor_image

; ---------------------------------------------------------------------------
; editor_init: A5 = editor base. D0.l = 0 when ready for the hooks.
; ---------------------------------------------------------------------------
editor_init:
        movem.l d1-d7/a0-a6,-(sp)
        lea     WORK_CLEAR_START(a5),a0
        move.w  #(WORK_DATA_OFFSET+WORKING_DATA_MAX_SIZE-WORK_CLEAR_START)/4-1,d0
.clear:
        clr.l   (a0)+
        dbf     d0,.clear
        bsr.l   copies_init             ; the cups' 96/97 participants
        bsr.l   menus_init              ; D0 = 0 or the failing page + 1
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts

; crc32_buffer: A0 = data, D1.l = length, A5 = editor base. D0.l = the
; CRC-32 of the data, flags set from it; A0 advanced, D1-D2 changed.
crc32_buffer:
        move.l  a1,-(sp)
        moveq   #-1,d0
        lea     WORK_CRC_TABLE(a5),a1
        bsr.s   crc32_table_update
        movea.l (sp)+,a1
        not.l   d0
        rts

        CRC32_TABLE_020
