; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Formats shared by the WHDLoad slave and the editor: the editor image
; header, its relocation and import tables and the patch tables (the slave's
; base patch table and the editor's runtime hook table).

; ---------------------------------------------------------------------------
; Editor image (the editor file of the install, loaded into the expansion
; memory by the slave)
; ---------------------------------------------------------------------------
EDH_MAGIC               equ $00         ; 'SWED'
EDH_VERSION             equ $04         ; word
EDH_FLAGS               equ $06         ; word, zero
EDH_LENGTH              equ $08         ; long: image length in bytes
EDH_INIT                equ $0C         ; long: offset of editor_init
EDH_HOOKS               equ $10         ; long: offset of the runtime hook table
EDH_FIXUPS              equ $14         ; long: offset of the relocation table
EDH_IMPORTS             equ $18         ; long: offset of the import table
EDH_IDENTITY            equ $1C         ; 8 bytes: SWOS2 identity (SHA-256 prefix)
EDH_CODE_LENGTH         equ $24         ; long: bytes that stay unchanged in RAM
EDH_SIZE                equ $28

EDH_MAGIC_VALUE         equ 'SWED'
EDH_VERSION_VALUE       equ 2

; Relocation table: dc.l count, dc.l offset[count]; each offset names a BE32
; field holding an image offset, to which the image base is added.
; Import table: dc.l count, dc.l offset[count]; each offset names a BE32
; field holding a SWOS2 address for the base SWOS2_BASE, to which the
; difference between the actual runtime base and SWOS2_BASE is added.

; editor_init: A5 = image base. Returns D0.l = 0 when the editor is ready
; for its hooks; any other value makes the slave install no hook.

; ---------------------------------------------------------------------------
; Patch tables (base patch table in the slave, runtime hook table in the
; editor image)
; ---------------------------------------------------------------------------
; dc.w count; per entry, sorted by address:
PT_ADDRESS              equ 0           ; long: runtime address
PT_LENGTH               equ 4           ; word: bytes replaced
PT_CRC32                equ 6           ; long: CRC-32 of the original bytes
PT_FIXUPS               equ 10          ; word: number of image-relative fields
PT_FIXUP_LIST           equ 12          ; word offset[fixups], then the bytes
; followed by the replacement bytes, padded to an even length. An applier
; checks the CRC-32 of every site first and writes nothing unless all match;
; it adds the base of the image that owns the table to every fixup field.

; ---------------------------------------------------------------------------
; CRC-32/ISO-HDLC (reflected polynomial $EDB88320)
; ---------------------------------------------------------------------------
CRC32_POLY              equ $EDB88320

; ---------------------------------------------------------------------------
; Storage in the save directory (resident/storage.s)
; ---------------------------------------------------------------------------
STORAGE_CHUNK           equ 4096        ; I/O buffer of the editor
