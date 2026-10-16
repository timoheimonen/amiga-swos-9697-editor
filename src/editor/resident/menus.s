; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Editor entries on the game's own pages.
;
; For each page in page_extensions, menus_init checks the CRC-32 of the
; native compact template in RAM against the value the build measured,
; copies it into the working data, appends the editor's entries, optionally
; replaces the restore callback, writes the navigation bytes that lead from
; native entries to the new ones and the longwords that point callbacks of
; the copy (init, entry actions) at the editor. The runtime hooks then point
; the game's LEA of each template at its copy. No game bytes are stored in
; the editor files.
;
; Appended entries start with $FC1C (reset inherited defaults), $FC1A 0,0
; (no coordinate shift) and $FFFE (word geometry), so whatever the native
; template left in effect does not reach them. Geometry in the template is
; screen x-24, y-36.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "editor_gen.i"
        include "team.i"

        xdef    menus_init
        xref    crc32_buffer
        xref    editor_image
        xref    database_action, database_menu_init
        xref    team_page_init, team_import_action, team_ok_action
        xref    team_row_action, team_settings_action
        xref    definition_type_init
        xref    definition_init_league, definition_init_cup, definition_init_tournament
        xref    definition_ok_league, definition_ok_cup, definition_ok_tournament
        xref    definition_choose_league, definition_choose_cup, definition_choose_tournament
        xref    rules_league, rules_cup, rules_tournament
        xref    defsave_league, defsave_cup, defsave_tournament
        xref    defload_action

; Page extension record
EXT_TEMPLATE            equ 0           ; long: native template
EXT_SIZE                equ 4           ; word: template bytes without $FC19
EXT_CRC32               equ 6           ; long: CRC-32 of those bytes
EXT_WORK                equ 10          ; long: copy's offset from the base
EXT_RESTORE             equ 14          ; long: new restore callback, 0 keep
EXT_TAIL                equ 18          ; long: appended entries
EXT_TAIL_SIZE           equ 22          ; word
EXT_PATCHES             equ 24          ; word count, then (offset, value) words,
                                        ; then word count, (offset word, value long)

        section .text,code

; ---------------------------------------------------------------------------
; menus_init: A5 = editor base. D0.l = 0, or the number of the first page
; whose native template differs (no further page is built).
; ---------------------------------------------------------------------------
menus_init:
        movem.l d1-d7/a0-a4,-(sp)
        lea     page_extensions(pc),a3
        moveq   #0,d6
.page:
        move.l  EXT_TEMPLATE(a3),d0
        beq.w   .ok
        addq.l  #1,d6
        movea.l d0,a0
        moveq   #0,d1
        move.w  EXT_SIZE(a3),d1
        bsr.l   crc32_buffer
        cmp.l   EXT_CRC32(a3),d0
        bne.s   .refuse
        movea.l EXT_TEMPLATE(a3),a0
        movea.l a5,a2
        adda.l  EXT_WORK(a3),a2
        movea.l a2,a1
        move.w  EXT_SIZE(a3),d0
        subq.w  #1,d0
.copy:
        move.b  (a0)+,(a1)+
        dbf     d0,.copy
        movea.l EXT_TAIL(a3),a0
        move.w  EXT_TAIL_SIZE(a3),d0
        subq.w  #1,d0
.append:
        move.b  (a0)+,(a1)+
        dbf     d0,.append
        movea.l a2,a1
        move.l  EXT_RESTORE(a3),d0
        beq.s   .patches
        move.l  d0,4(a1)
.patches:
        lea     EXT_PATCHES(a3),a0
        move.w  (a0)+,d0
        bra.s   .test
.patch:
        move.w  (a0)+,d1
        move.w  (a0)+,d2
        move.b  d2,(a1,d1.w)
.test:
        dbf     d0,.patch
        move.w  (a0)+,d0
        bra.s   .long_test
.long:
        move.w  (a0)+,d1
        move.l  (a0)+,(a1,d1.w)         ; the copy is in Fast RAM, any alignment
.long_test:
        dbf     d0,.long
        movea.l a0,a3
        bra.w   .page
.ok:
        moveq   #0,d0
.done:
        movem.l (sp)+,d1-d7/a0-a4
        rts
.refuse:
        move.l  d6,d0
        bra.s   .done

; ---------------------------------------------------------------------------
; Page extensions
; ---------------------------------------------------------------------------
EXTENSION macro                         ; template,size,crc,work,restore,tail
        dc.l    \1
        dc.w    \2
        dc.l    \3,\4,\5,\6
        dc.w    \6_end-\6
        endm

page_extensions:
        EXTENSION main_menu_template,MAIN_MENU_PREFIX_SIZE,MAIN_MENU_PREFIX_CRC32,WORK_MAIN_MENU,main_menu_refresh,main_menu_tail
        dc.w    1
        dc.w    MAIN_MENU_NAV_1_UP,MAIN_MENU_ENTRIES
        dc.w    1
        dc.w    0                       ; init callback
        dc.l    database_menu_init
        EXTENSION team_editor_template,TEAM_EDITOR_PREFIX_SIZE,TEAM_EDITOR_PREFIX_CRC32,WORK_TEAM_EDITOR,0,team_editor_tail
        dc.w    25
        dc.w    TEAM_EDITOR_NAV_20_DOWN,TEAM_SETTINGS_ENTRY
        dc.w    TEAM_EDITOR_NAV_21_DOWN,TEAM_SETTINGS_ENTRY
        dc.w    TEAM_EDITOR_NAV_22_DOWN,TEAM_SETTINGS_ENTRY
        dc.w    TEAM_EDITOR_NAV_5_LEFT,TEAM_ROW_ENTRY+2
        dc.w    TEAM_EDITOR_NAV_6_LEFT,TEAM_ROW_ENTRY+4
        dc.w    TEAM_EDITOR_NAV_7_LEFT,TEAM_ROW_ENTRY+6
        dc.w    TEAM_EDITOR_NAV_9_LEFT,TEAM_ROW_ENTRY+10
        dc.w    TEAM_EDITOR_NAV_10_LEFT,TEAM_ROW_ENTRY+12
        dc.w    TEAM_EDITOR_NAV_11_LEFT,TEAM_ROW_ENTRY+14
        dc.w    TEAM_EDITOR_NAV_39_RIGHT,TEAM_ROW_ENTRY+0
        dc.w    TEAM_EDITOR_NAV_40_RIGHT,TEAM_ROW_ENTRY+1
        dc.w    TEAM_EDITOR_NAV_41_RIGHT,TEAM_ROW_ENTRY+2
        dc.w    TEAM_EDITOR_NAV_42_RIGHT,TEAM_ROW_ENTRY+3
        dc.w    TEAM_EDITOR_NAV_43_RIGHT,TEAM_ROW_ENTRY+4
        dc.w    TEAM_EDITOR_NAV_44_RIGHT,TEAM_ROW_ENTRY+5
        dc.w    TEAM_EDITOR_NAV_45_RIGHT,TEAM_ROW_ENTRY+6
        dc.w    TEAM_EDITOR_NAV_46_RIGHT,TEAM_ROW_ENTRY+7
        dc.w    TEAM_EDITOR_NAV_47_RIGHT,TEAM_ROW_ENTRY+8
        dc.w    TEAM_EDITOR_NAV_48_RIGHT,TEAM_ROW_ENTRY+9
        dc.w    TEAM_EDITOR_NAV_49_RIGHT,TEAM_ROW_ENTRY+10
        dc.w    TEAM_EDITOR_NAV_50_RIGHT,TEAM_ROW_ENTRY+11
        dc.w    TEAM_EDITOR_NAV_51_RIGHT,TEAM_ROW_ENTRY+12
        dc.w    TEAM_EDITOR_NAV_52_RIGHT,TEAM_ROW_ENTRY+13
        dc.w    TEAM_EDITOR_NAV_53_RIGHT,TEAM_ROW_ENTRY+14
        dc.w    TEAM_EDITOR_NAV_54_RIGHT,TEAM_ROW_ENTRY+15
        dc.w    3
        dc.w    0                       ; init callback
        dc.l    team_page_init
        dc.w    TEAM_EDITOR_ACTION_20   ; IMPORT
        dc.l    team_import_action
        dc.w    TEAM_EDITOR_ACTION_21   ; OK
        dc.l    team_ok_action
        EXTENSION diy_type_template,DIY_TYPE_PREFIX_SIZE,DIY_TYPE_PREFIX_CRC32,WORK_DIY_TYPE,0,diy_type_tail
        dc.w    2
        dc.w    DIY_TYPE_NAV_3_DOWN,DIY_TYPE_ENTRIES
        dc.w    DIY_TYPE_NAV_4_UP,DIY_TYPE_ENTRIES
        dc.w    1
        dc.w    0                       ; init callback (natively none)
        dc.l    definition_type_init
        EXTENSION diy_league_template,DIY_LEAGUE_PREFIX_SIZE,DIY_LEAGUE_PREFIX_CRC32,WORK_DIY_LEAGUE,diy_league_init,diy_league_tail
        dc.w    2
        dc.w    DIY_LEAGUE_NAV_21_LEFT,DIY_LEAGUE_ENTRIES
        dc.w    DIY_LEAGUE_NAV_21_RIGHT,DIY_LEAGUE_ENTRIES+1
        dc.w    3
        dc.w    0                       ; init callback
        dc.l    definition_init_league
        dc.w    DIY_LEAGUE_ACTION_20    ; CHOOSE TEAMS
        dc.l    definition_choose_league
        dc.w    DIY_LEAGUE_ACTION_21    ; OK
        dc.l    definition_ok_league
        EXTENSION diy_cup_template,DIY_CUP_PREFIX_SIZE,DIY_CUP_PREFIX_CRC32,WORK_DIY_CUP,diy_cup_init,diy_cup_tail
        dc.w    2
        dc.w    DIY_CUP_NAV_49_LEFT,DIY_CUP_ENTRIES
        dc.w    DIY_CUP_NAV_49_RIGHT,DIY_CUP_ENTRIES+1
        dc.w    3
        dc.w    0
        dc.l    definition_init_cup
        dc.w    DIY_CUP_ACTION_48       ; CHOOSE TEAMS
        dc.l    definition_choose_cup
        dc.w    DIY_CUP_ACTION_49       ; OK
        dc.l    definition_ok_cup
        EXTENSION diy_tournament_template,DIY_TOURNAMENT_PREFIX_SIZE,DIY_TOURNAMENT_PREFIX_CRC32,WORK_DIY_TOURNAMENT,diy_tournament_init,diy_tournament_tail
        dc.w    3
        dc.w    DIY_TOURNAMENT_NAV_89_DOWN,DIY_TOURNAMENT_ENTRIES
        dc.w    DIY_TOURNAMENT_NAV_90_DOWN,DIY_TOURNAMENT_ENTRIES
        dc.w    DIY_TOURNAMENT_NAV_91_DOWN,DIY_TOURNAMENT_ENTRIES+1
        dc.w    3
        dc.w    0
        dc.l    definition_init_tournament
        dc.w    DIY_TOURNAMENT_ACTION_89 ; CHOOSE TEAMS
        dc.l    definition_choose_tournament
        dc.w    DIY_TOURNAMENT_ACTION_90 ; OK
        dc.l    definition_ok_tournament
        dc.l    0

TAIL_START macro
        dc.w    $FC1C
        dc.w    $FC1A,0,0
        dc.w    $FFFE
        endm

; An entry is PLACE x,y,w,h,left,right,up,down followed by ACT box,label,action.
PLACE   macro
        dc.w    \1-24,\2-36,\3,\4
        dc.w    2
        dc.b    \5,\6,\7,\8
        endm
ACT     macro
        dc.w    4,\1
        dc.w    8,0
        dc.l    \2
        dc.w    13
        dc.l    \3
        dc.w    0
        endm

; Main menu: EDIT DATABASE above EDIT TACTICS (entry 14) and, below LOAD
; OLD COMPETITION, the caption of the edited database in use (empty while
; USE EDITED DATABASE is off).
main_menu_tail:
        TAIL_START
        PLACE   24,72,84,15,$FF,6,$FF,1
        ACT     14,edit_database_label,database_action
        PLACE   24,244,304,8,$FF,$FF,$FF,$FF
        dc.w    8,0
        dc.l    editor_image+WORK_DB+DB_CAPTION
        dc.w    0
        dc.w    $FC19
main_menu_tail_end:

; Team editor: one EDIT action per player row in the free column right of
; the position (the row decorations 58-60 stay hidden on this page), so
; RIGHT from a name reaches it; SETTINGS below IMPORT/UNDO/OK; and the
; custom set's CRC-32 caption above the first kit.
TEAM_ROW_ENTRY          equ TEAM_EDITOR_ENTRIES
TEAM_SETTINGS_ENTRY     equ TEAM_ROW_ENTRY+PLAYER_COUNT
TEAM_CAPTION_ENTRY      equ TEAM_SETTINGS_ENTRY+1
TEAM_ROW_X              equ 214
TEAM_ROW_W              equ 19
TEAM_ROW_Y              equ 58          ; y of name row 0; rows are 10 apart
TEAM_ROW_H              equ 8

; \1 = row, \2 = the kit entry RIGHT of its name
ROW_ACTION macro
        PLACE   TEAM_ROW_X,TEAM_ROW_Y+10*\1,TEAM_ROW_W,TEAM_ROW_H,TEAM_PAGE_FIRST_NAME+\1,\2,TEAM_ROW_ENTRY+\1-1,TEAM_ROW_ENTRY+\1+1
        ACT     14,row_action_label,team_row_action
        endm

team_editor_tail:
        TAIL_START
        PLACE   TEAM_ROW_X,TEAM_ROW_Y,TEAM_ROW_W,TEAM_ROW_H,TEAM_PAGE_FIRST_NAME,5,0,TEAM_ROW_ENTRY+1
        ACT     14,row_action_label,team_row_action
        ROW_ACTION 1,5
        ROW_ACTION 2,5
        ROW_ACTION 3,5
        ROW_ACTION 4,6
        ROW_ACTION 5,6
        ROW_ACTION 6,7
        ROW_ACTION 7,7
        ROW_ACTION 8,9
        ROW_ACTION 9,9
        ROW_ACTION 10,9
        ROW_ACTION 11,9
        ROW_ACTION 12,10
        ROW_ACTION 13,10
        ROW_ACTION 14,11
        PLACE   TEAM_ROW_X,TEAM_ROW_Y+150,TEAM_ROW_W,TEAM_ROW_H,TEAM_PAGE_FIRST_NAME+15,11,TEAM_ROW_ENTRY+14,3
        ACT     14,row_action_label,team_row_action
        PLACE   188,240,65,13,3,$FF,20,$FF
        ACT     13,settings_label,team_settings_action
        PLACE   222,38,106,8,$FF,$FF,$FF,$FF
        dc.w    8,$4000
        dc.l    editor_image+WORK_TEAM+TE_CAPTION
        dc.w    0
        dc.w    $FC19
team_editor_tail_end:

; SELECT DIY COMPETITION TYPE: LOAD DEFINITION (5) below TOURNAMENT; a
; definition opens the setup page of its own family.
diy_type_tail:
        TAIL_START
        PLACE   116,151,120,15,$FF,$FF,3,4
        ACT     13,load_definition_label,defload_action
        dc.w    $FC19
diy_type_tail_end:

; The setup pages: RULES and SAVE DEFINITION. On the league and cup pages
; they stand left and right of OK, on the tournament page below its last
; row of buttons (its six stage rows fill the page above). The copies'
; restore callback is the native init (its text of the team count and the
; native restore), because after OK the page returns from the editor's
; screens too, which the native page never does there.
diy_league_tail:
        TAIL_START
        PLACE   24,201,120,15,$FF,21,16,20
        ACT     13,rules_label,rules_league
        PLACE   208,201,120,15,21,$FF,17,22
        ACT     13,save_definition_label,defsave_league
        dc.w    $FC19
diy_league_tail_end:

diy_cup_tail:
        TAIL_START
        PLACE   24,201,120,15,$FF,49,45,48
        ACT     13,rules_label,rules_cup
        PLACE   208,201,120,15,49,$FF,47,50
        ACT     13,save_definition_label,defsave_cup
        dc.w    $FC19
diy_cup_tail_end:

diy_tournament_tail:
        TAIL_START
        PLACE   24,239,120,13,$FF,DIY_TOURNAMENT_ENTRIES+1,90,$FF
        ACT     13,rules_label,rules_tournament
        PLACE   208,239,120,13,DIY_TOURNAMENT_ENTRIES,$FF,91,$FF
        ACT     13,save_definition_label,defsave_tournament
        dc.w    $FC19
diy_tournament_tail_end:

        if MAIN_MENU_PREFIX_SIZE+main_menu_tail_end-main_menu_tail>WORK_MAIN_MENU_SIZE
        fail "extended main menu exceeds its working area"
        endif
        if TEAM_EDITOR_PREFIX_SIZE+team_editor_tail_end-team_editor_tail>WORK_TEAM_EDITOR_SIZE
        fail "extended team editor exceeds its working area"
        endif
        if DIY_TYPE_PREFIX_SIZE+diy_type_tail_end-diy_type_tail>WORK_DIY_TYPE_SIZE
        fail "extended DIY type page exceeds its working area"
        endif
        if DIY_LEAGUE_PREFIX_SIZE+diy_league_tail_end-diy_league_tail>WORK_DIY_LEAGUE_SIZE
        fail "extended DIY league page exceeds its working area"
        endif
        if DIY_CUP_PREFIX_SIZE+diy_cup_tail_end-diy_cup_tail>WORK_DIY_CUP_SIZE
        fail "extended DIY cup page exceeds its working area"
        endif
        if DIY_TOURNAMENT_PREFIX_SIZE+diy_tournament_tail_end-diy_tournament_tail>WORK_DIY_TOURNAMENT_SIZE
        fail "extended DIY tournament page exceeds its working area"
        endif

edit_database_label:    dc.b    'EDIT DATABASE',0
settings_label:         dc.b    'SETTINGS',0
row_action_label:       dc.b    'EDIT',0
rules_label:            dc.b    'RULES',0
save_definition_label:  dc.b    'SAVE DEFINITION',0
load_definition_label:  dc.b    'LOAD DEFINITION',0
        even
