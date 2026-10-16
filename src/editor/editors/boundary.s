; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; What the editors change and what they do not, said where a user would
; expect it, at the moment the user meets it:
;
;   boundary_gate         EDIT CUSTOM TEAMS and EDIT DATABASE with a
;                         competition in memory: the teams of a started
;                         competition, season or career are its own copies
;                         and are never edited; the game's own question
;                         whether to lose it follows
;   boundary_cup_copies   a European club cup of PRESET COMPETITION, or the
;                         start of a career, while the edited database is in
;                         use: the cups play with its clubs and squads and
;                         its own participants where it lists them
;                         (resident/copies.s; once per career start)
;   boundary_foreign_market  the foreign player market of a career bound to
;                         an edited database: the game's own choice of
;                         players, with their names, skills and clubs from
;                         that database (once after the career started or
;                         was loaded)
;   boundary_format_note  FORMAT SAVE DISK: the save directory needs no
;                         format and nothing changes (no disk is asked for)
;
; A player's value is refused on the player screen (editors/player.s).
;
; Native action contract: the menu tick saves D0-D7/A0-A6 around an action
; and passes A5 = the selected expanded entry.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    boundary_gate, boundary_cup_copies, boundary_foreign_market
        xdef    boundary_format_note, boundary_family_started
        xref    editor_base
        xref    db_manifest_in_use
        xref    message_note

        section .text,code

; ---------------------------------------------------------------------------
; boundary_gate: replaces JSR competition_abandon_gate at the entry of
; EDIT CUSTOM TEAMS (custom_team_gate_call); EDIT DATABASE calls it the same
; way. A0 = the gate's title. With a competition in memory a note first says
; that its teams cannot be edited; then the native gate asks whether to
; lose the competition and returns its result.
; ---------------------------------------------------------------------------
boundary_gate:
        tst.w   competition_family
        beq.s   .gate
        movem.l d0-d7/a0-a6,-(sp)
        lea     title_competition(pc),a0
        move.w  competition_family,d0
        cmpi.w  #FAMILY_SEASON,d0
        bne.s   .career
        lea     title_season(pc),a0
.career:
        cmpi.w  #FAMILY_CAREER,d0
        bne.s   .note
        lea     title_career(pc),a0
.note:
        lea     started_lines(pc),a1
        bsr.l   message_note
        movem.l (sp)+,d0-d7/a0-a6
.gate:
        jmp     competition_abandon_gate

; ---------------------------------------------------------------------------
; boundary_cup_copies: replaces LEA cup_copies_records,A1 (cup_copies_target)
; in cup_copies_load, reached when a European club cup's team copies are
; read (A0 = the file name): for PRESET COMPETITION's team list of one cup,
; or at the start of a career for all three, where only the first file is
; noted. While the edited database is in use a note says what it changes;
; the copies themselves are read afterwards (cup_copies_read). A1 =
; cup_copies_records; every other register is preserved.
; ---------------------------------------------------------------------------
boundary_cup_copies:
        movem.l d0-d7/a0-a6,-(sp)
        cmpi.w  #FAMILY_CAREER,competition_family
        bne.s   .used
        cmpa.l  #cup_copies_first_name,a0
        bne.s   .done                   ; a career's second and third cup
.used:
        bsr.l   db_manifest_in_use      ; A0 = 0 for the original database
        beq.s   .done
        lea     title_cup(pc),a0
        lea     cup_lines(pc),a1
        bsr.l   message_note
.done:
        movem.l (sp)+,d0-d7/a0-a6
        lea     cup_copies_records,a1
        rts

; ---------------------------------------------------------------------------
; boundary_foreign_market: action of VIEW FOREIGN PLAYER MARKET
; (foreign_market_operand). In a career bound to an edited database the
; first visit after the career started or was loaded explains what the
; database changes on the market; then the native action.
; ---------------------------------------------------------------------------
boundary_foreign_market:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        tst.w   competition_family
        beq.s   .native
        tst.w   WORK_DB+DB_BIND(a5)
        beq.s   .native
        tst.w   WORK_BOUNDARY+BD_MARKET_NOTED(a5)
        bne.s   .native
        move.w  #1,WORK_BOUNDARY+BD_MARKET_NOTED(a5)
        lea     title_market(pc),a0
        lea     market_lines(pc),a1
        bsr.l   message_note
.native:
        movem.l (sp)+,d0-d7/a0-a6
        jmp     foreign_market_view

; ---------------------------------------------------------------------------
; boundary_family_started: a competition family started or was loaded (from
; the editor's family reset and load hooks); the market note may come
; again. Preserves all registers.
; ---------------------------------------------------------------------------
boundary_family_started:
        move.l  a0,-(sp)
        movea.l editor_base,a0
        clr.w   WORK_BOUNDARY+BD_MARKET_NOTED(a0)
        movea.l (sp)+,a0
        rts

; ---------------------------------------------------------------------------
; boundary_format_note: replaces JSR frontend_prompt in FORMAT SAVE DISK
; (format_prompt_call). The note says that the save directory needs no
; format; D0.w = 1 with Z clear makes the native action return without
; asking for a disk or formatting.
; ---------------------------------------------------------------------------
boundary_format_note:
        movem.l d1-d7/a0-a6,-(sp)
        lea     title_format(pc),a0
        lea     format_lines(pc),a1
        bsr.l   message_note
        movem.l (sp)+,d1-d7/a0-a6
        moveq   #1,d0
        rts

title_competition:      dc.b    'COMPETITION IN PROGRESS',0
title_season:           dc.b    'SEASON IN PROGRESS',0
title_career:           dc.b    'CAREER IN PROGRESS',0
started_lines:          dc.b    'THE TEAMS OF A STARTED COMPETITION CANNOT BE',0
                        dc.b    'EDITED: IT KEEPS ITS OWN COPIES. EDITS ARE USED',0
                        dc.b    'BY COMPETITIONS STARTED AFTERWARDS.',0
                        dc.b    'SAVE IT FIRST TO PLAY IT ON LATER.',0
                        dc.b    0
title_cup:              dc.b    'EUROPEAN CLUB CUPS',0
cup_lines:              dc.b    'THE CUPS PLAY WITH THE CLUBS AND SQUADS OF THE',0
                        dc.b    'EDITED DATABASE IN USE, AND WITH ITS OWN',0
                        dc.b    'PARTICIPANTS WHERE IT LISTS THEM. EDIT DATABASE',0
                        dc.b    'SHOWS THE LISTS UNDER EUROPEAN CUPS.',0
                        dc.b    0
title_market:           dc.b    'FOREIGN PLAYER MARKET',0
market_lines:           dc.b    'THE MARKET OFFERS PLAYERS THE GAME CHOSE IN 96/97.',0
                        dc.b    'THEIR NAMES, SKILLS AND CLUBS COME FROM THE',0
                        dc.b    'EDITED DATABASE THIS CAREER IS BOUND TO.',0
                        dc.b    0
title_format:           dc.b    'FORMAT SAVE DISK',0
format_lines:           dc.b    'THE SAVES ARE FILES IN THE DIRECTORY DATA OF',0
                        dc.b    'THE INSTALL. IT NEEDS NO FORMAT, AND NOTHING',0
                        dc.b    'WAS CHANGED. DELETE FILE REMOVES SINGLE SAVES.',0
                        dc.b    0
        even
