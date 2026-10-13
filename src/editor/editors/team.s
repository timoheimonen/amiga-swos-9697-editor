; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The editor's part of the native team page (EDIT CUSTOM TEAMS). The page
; copy built by menus_init points these callbacks at the editor:
;   team_page_init      init callback: the native one (working copy and
;                       refresh), then the caption with the custom set's
;                       CRC-32, marked '*' while accepted edits are unsaved
;   team_import_action  IMPORT: the native one, then a copy of the imported
;                       record as the baseline its kept values are checked
;                       against
;   team_ok_action      OK: validates the whole working copy first; a team
;                       that breaks a rule stays on the page with a message
;   team_row_action     EDIT of a player row: the player screen
;   team_settings_action SETTINGS: the team settings screen
; The native transaction stays: every screen edits the working copy
; team_working_copy, UNDO restores the original record, OK commits it.
;
; Native action contract: the menu tick saves D0-D7/A0-A6 around an action
; and passes A5 = the selected expanded entry.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "editor_gen.i"

        xdef    team_page_init, team_import_action, team_ok_action
        xdef    team_row_action, team_settings_action
        xdef    team_screen_save, team_screen_cancel
        xref    editor_base
        xref    screen_run
        xref    player_screen, settings_screen
        xref    team_validate
        xref    message_title, message_line, message_show, message_note
        xref    text_copy, text_copy_max, text_hex32, text_decimal
        xref    db_group_name

        section .text,code

; ---------------------------------------------------------------------------
; team_page_init: init callback of the team page copy.
; ---------------------------------------------------------------------------
team_page_init:
        movem.l d0-d7/a0-a6,-(sp)
        jsr     custom_team_init_working_copy
        movea.l editor_base,a5
        clr.w   WORK_TEAM+TE_IMPORT_VALID(a5)
        bsr.w   team_caption
        movem.l (sp)+,d0-d7/a0-a6
        rts

; team_caption: A5 = editor base. Builds the caption 'SET 1A2B3C4D', with
; '*' while custom_teams_dirty is set; empty while no set is known. In EDIT
; DATABASE the caption names the group being edited instead, with '*'
; while it has unsaved changes.
team_caption:
        movem.l d0/a0-a1,-(sp)
        lea     WORK_TEAM+TE_CAPTION(a5),a1
        clr.b   (a1)
        cmpi.w  #DBS_TEAM,WORK_DB+DB_SCREEN(a5)
        bne.s   .custom
        move.w  WORK_DB+DB_GROUP(a5),d0
        bsr.l   db_group_name
        tst.w   WORK_DB+DB_DIRTY(a5)
        beq.s   .done
        move.b  #' ',(a1)+
        bra.s   .changed
.custom:
        tst.w   WORK_TEAM+TE_SET_KNOWN(a5)
        beq.s   .done
        lea     set_text(pc),a0
        bsr.l   text_copy
        move.l  WORK_TEAM+TE_SET_CRC(a5),d0
        bsr.l   text_hex32
        tst.w   custom_teams_dirty
        beq.s   .done
.changed:
        move.b  #'*',(a1)+
        clr.b   (a1)
.done:
        movem.l (sp)+,d0/a0-a1
        rts

; team_screen_save: A5 = editor base. Keeps the working copy as it is when
; a team screen opens (TE_SCREEN_BASE), for CANCEL. Changes D0/A0-A1.
team_screen_save:
        lea     team_working_copy,a0
        lea     WORK_TEAM+TE_SCREEN_BASE(a5),a1
        bra.s   team_copy

; team_screen_cancel: A5 = editor base. CANCEL of a team screen: the working
; copy as it was when the screen opened. D0.l = 1 (the screen closes).
team_screen_cancel:
        lea     WORK_TEAM+TE_SCREEN_BASE(a5),a0
        lea     team_working_copy,a1
        bsr.s   team_copy
        moveq   #1,d0
        rts

; team_copy: a team record from A0 to A1. Changes D0/A0-A1.
        if TEAM_SIZE&3
        fail "team_copy copies longwords"
        endif
team_copy:
        move.w  #TEAM_SIZE/4-1,d0
.copy:
        move.l  (a0)+,(a1)+
        dbf     d0,.copy
        rts

; ---------------------------------------------------------------------------
; team_import_action: IMPORT with the imported record kept as a baseline.
; ---------------------------------------------------------------------------
team_import_action:
        movea.l editor_base,a4
        cmpi.w  #DBS_TEAM,WORK_DB+DB_SCREEN(a4)
        beq.s   .database
        jsr     custom_team_import
        movea.l editor_base,a4
        tst.w   custom_team_imported
        beq.s   .done
        lea     team_working_copy,a0
        lea     WORK_TEAM+TE_IMPORT_BASE(a4),a1
        bsr.s   team_copy
        move.w  #1,WORK_TEAM+TE_IMPORT_VALID(a4)
.done:
        rts
.database:
        ; a club of another country replaces this one with COPY TO COUNTRY
        lea     import_title(pc),a0
        lea     import_lines(pc),a1
        bra.l   message_note

; ---------------------------------------------------------------------------
; team_ok_action: OK, after the whole team has passed team_validate.
; ---------------------------------------------------------------------------
team_ok_action:
        movea.l editor_base,a4
        lea     team_working_copy,a0
        movea.l custom_team_original_pointer,a1
        suba.l  a2,a2
        tst.w   custom_team_imported
        beq.s   .check
        tst.w   WORK_TEAM+TE_IMPORT_VALID(a4)
        beq.s   .check
        lea     WORK_TEAM+TE_IMPORT_BASE(a4),a2
.check:
        bsr.l   team_validate           ; D0 = 0 or reason, D1 = slot or -1
        tst.l   d0
        bne.s   .refuse
        jmp     custom_team_commit
.refuse:
        movea.l d0,a3
        lea     refused_title(pc),a0
        bsr.l   message_title
        movea.l a3,a0
        moveq   #0,d0
        bsr.l   message_line
        tst.w   d1
        bmi.s   .hint
        lea     WORK_TEAM_SCREEN+TS_STATUS(a4),a1
        lea     player_text(pc),a0
        bsr.l   text_copy
        move.w  d1,d0
        addq.w  #1,d0
        bsr.l   text_decimal
        lea     separator_text(pc),a0
        bsr.l   text_copy
        mulu.w  #PLAYER_SIZE,d1
        lea     team_working_copy+TEAM_PLAYERS+PLAYER_NAME,a0
        adda.w  d1,a0
        moveq   #PLAYER_NAME_SIZE-1,d0
        bsr.l   text_copy_max
        lea     WORK_TEAM_SCREEN+TS_STATUS(a4),a0
        moveq   #1,d0
        bsr.l   message_line
.hint:
        lea     refused_hint(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bra.l   message_show

; ---------------------------------------------------------------------------
; team_row_action: A5 = the row's EDIT entry. Opens the player screen for
; that row's physical slot.
; ---------------------------------------------------------------------------
team_row_action:
        move.w  2(a5),d0                ; entry index
        subi.w  #TEAM_EDITOR_ENTRIES,d0
        cmpi.w  #PLAYER_COUNT,d0
        bcc.s   .done
        movea.l editor_base,a4
        move.w  d0,WORK_TEAM+TE_ROW(a4)
        lea     player_screen,a0
        bra.l   screen_run
.done:
        rts

; team_settings_action: the team settings screen.
team_settings_action:
        lea     settings_screen,a0
        bra.l   screen_run

set_text:       dc.b    'SET ',0
refused_title:  dc.b    'TEAM NOT ACCEPTED',0
player_text:    dc.b    'PLAYER ',0
separator_text: dc.b    ': ',0
refused_hint:   dc.b    'CHANGE IT, OR USE UNDO TO RESTORE THE TEAM.',0
import_title:   dc.b    'IMPORT',0
import_lines:   dc.b    'IN EDIT DATABASE A CLUB IS REPLACED WITH',0
                dc.b    'COPY TO COUNTRY OR EXCHANGE ON THE GROUP SCREEN.',0
                dc.b    0
        even
