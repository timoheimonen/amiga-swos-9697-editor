; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Memory layout, size caps and budgets of the slave and the editor. Include
; after swos2.i and slave.i. The build reads every value defined here and
; stops when a linked part, a file or a native menu page exceeds its cap.

; ---------------------------------------------------------------------------
; Expansion memory (ws_ExpMem): one block from WHDLoad, divided internally
; ---------------------------------------------------------------------------
; Layout from its start:
;   0                    slave area: CRC-32 table, disk block buffer, the
;                        remembered listing of data/, readback buffer
;   EDITOR_AREA_OFFSET   editor area; its start is the editor base:
;     0                    editor image (code, tables, constant data)
;     WORK_DATA_OFFSET     working data, cleared by editor_init
;     GROUP_WORK_OFFSET    working copy of one team group
;     LIST_WORK_OFFSET     listing of the save directory for the editors
; Nothing in this block is read by DMA: the editor draws with the CPU into
; the game's Chip RAM display buffers.
        ifnd    EXPMEM_SIZE
EXPMEM_SIZE             equ 256*1024
        endif
SLAVE_AREA_SIZE         equ 32*1024
EDITOR_AREA_OFFSET      equ SLAVE_AREA_SIZE
EDITOR_AREA_SIZE        equ EXPMEM_SIZE-SLAVE_AREA_SIZE
; Working copy of the largest team group (TEAM.008), longword aligned.
GROUP_WORK_SIZE         equ 63614
GROUP_WORK_AREA         equ (GROUP_WORK_SIZE+3)&-4
; Team copy and baseline, tactic slot copies, clipboard, definition,
; manifests, the I/O buffer and the CRC-32 table.
WORKING_DATA_MAX_SIZE   equ 36*1024
; Listing of the save directory: the editors' explicit capacity.
LIST_WORK_RECORDS       equ 512
LIST_WORK_SIZE          equ LIST_WORK_RECORDS*FS_RECORD_SIZE
; Code, templates and tables of the editor image.
EDITOR_IMAGE_MAX_SIZE   equ EDITOR_AREA_SIZE-WORKING_DATA_MAX_SIZE-GROUP_WORK_AREA-LIST_WORK_SIZE
WORK_DATA_OFFSET        equ EDITOR_IMAGE_MAX_SIZE
GROUP_WORK_OFFSET       equ WORK_DATA_OFFSET+WORKING_DATA_MAX_SIZE
LIST_WORK_OFFSET        equ GROUP_WORK_OFFSET+GROUP_WORK_AREA
EDITOR_AREA_END         equ LIST_WORK_OFFSET+LIST_WORK_SIZE
; Fixed start of the working data: the slave builds the CRC-32 table here
; before it calls editor_init.
WORK_CRC_TABLE          equ WORK_DATA_OFFSET            ; 256 longwords
WORK_CRC_TABLE_SIZE     equ 1024

        if EDITOR_AREA_END!=EDITOR_AREA_SIZE
        fail "editor area partitions do not tile the area"
        endif
        if EDITOR_IMAGE_MAX_SIZE<64*1024
        fail "expansion memory leaves less than 64 KiB for the editor image"
        endif
        if (EXPMEM_SIZE&4095)|(EDITOR_IMAGE_MAX_SIZE&3)
        fail "expansion memory layout must be 4 KiB sized and longword aligned"
        endif

; The slave: one code hunk loaded by WHDLoad into its own memory.
SLAVE_MAX_SIZE          equ 16*1024

; ---------------------------------------------------------------------------
; Native menu pages
; ---------------------------------------------------------------------------
; menu_construct expands a page into menu_arena..MENU_ARENA_END: a
; MENU_HEADER_SIZE header, MENU_ENTRY_SIZE bytes per entry, then one
; MENU_TEXT_BUFFER_SIZE buffer per writable text. Its bounds checks are:
;   $19FC92  header end <= MENU_ARENA_END
;   $19FEBC  after each entry, room for one further entry (A1+$38 <= $417C)
;   $19FE56  end of each text buffer <= MENU_ARENA_END, no further reserve
; A page therefore fits exactly when
;   22 + 56*entries + max(56, 70*text_buffers) <= 6500
; (at most 114 entries). The build checks the stricter sum below, which
; implies it.
MENU_PAGE_LIMIT         equ MENU_ARENA_END-menu_arena
MENU_PARSER_RESERVE     equ MENU_ENTRY_SIZE

; \1 = entries, \2 = writable text buffers
menu_page_check macro
        if MENU_HEADER_SIZE+(\1)*MENU_ENTRY_SIZE+(\2)*MENU_TEXT_BUFFER_SIZE+MENU_PARSER_RESERVE>MENU_PAGE_LIMIT
        fail "native menu page exceeds the menu arena"
        endif
        endm

; ---------------------------------------------------------------------------
; Own screens (dialog service)
; ---------------------------------------------------------------------------
DIALOG_MAX_ITEMS        equ 32          ; buttons and list rows per dialog
