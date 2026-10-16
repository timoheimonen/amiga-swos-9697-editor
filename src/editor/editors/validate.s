; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Commit checks of a 16-player team record before the native OK installs
; it: kits, default tactic, lineup, shirt numbers and every player. Values
; the game's own data uses outside the editors' ranges stay valid while
; they are unchanged: a default tactic 12-17 and a goalkeeper rating of 39
; or 40 pass when the original record or the record IMPORT brought in has
; the same value. A default tactic 12-17 also passes while its user slot is
; user-owned (editors/tactics.s).

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    team_validate, player_rating_sum, lineup_role_of
        xref    editor_base

        section .text,code

; ---------------------------------------------------------------------------
; team_validate
;   in:  A0 = team record, A1 = its original record, A2 = record brought in
;        by IMPORT or 0
;   out: D0.l = 0 when the team may be committed, else the reason text;
;        D1.w = the physical slot the reason is about, or -1
; ---------------------------------------------------------------------------
team_validate:
        movem.l d2-d7/a0-a6,-(sp)
        moveq   #-1,d1
        ; kits
        lea     TEAM_HOME_KIT(a0),a3
        bsr.w   check_kit
        bne.w   .fail
        lea     TEAM_AWAY_KIT(a0),a3
        bsr.w   check_kit
        bne.w   .fail
        ; default tactic
        moveq   #0,d2
        move.b  TEAM_TACTIC(a0),d2
        cmpi.w  #TACTIC_BUILTIN_COUNT,d2
        bcs.s   .lineup
        lea     reason_tactic(pc),a4
        cmpi.w  #TACTIC_USER_LAST,d2
        bhi.w   .fail
        move.w  d2,d3
        subi.w  #TACTIC_USER_FIRST,d3
        movea.l editor_base,a3
        move.w  WORK_TACTICS+TT_OWNED(a3),d4
        btst    d3,d4                   ; a user-owned slot
        bne.s   .lineup
        cmp.b   TEAM_TACTIC(a1),d2
        beq.s   .lineup
        cmpa.w  #0,a2
        beq.w   .fail
        cmp.b   TEAM_TACTIC(a2),d2
        bne.w   .fail
.lineup:
        ; lineup: a permutation of the 16 slots, a goalkeeper in role 0
        lea     TEAM_LINEUP(a0),a3
        moveq   #0,d3                   ; slots seen
        moveq   #PLAYER_COUNT-1,d4
.role:
        moveq   #0,d2
        move.b  (a3)+,d2
        lea     reason_lineup(pc),a4
        cmpi.w  #PLAYER_COUNT,d2
        bcc.w   .fail
        bset    d2,d3
        bne.w   .fail
        dbf     d4,.role
        moveq   #0,d2
        move.b  TEAM_LINEUP(a0),d2
        bsr.w   player_address          ; A3 = player D2
        move.b  PLAYER_FLAGS(a3),d3
        andi.b  #POSITION_MASK,d3
        lea     reason_keeper(pc),a4
        bne.w   .fail
        ; shirt numbers: 1-16, each once
        moveq   #0,d3
        moveq   #0,d2
.shirt:
        bsr.w   player_address
        moveq   #0,d4
        move.b  PLAYER_SHIRT(a3),d4
        lea     reason_shirts(pc),a4
        subq.w  #1,d4
        cmpi.w  #PLAYER_COUNT,d4
        bcc.w   .fail
        bset    d4,d3
        bne.w   .fail
        addq.w  #1,d2
        cmpi.w  #PLAYER_COUNT,d2
        bcs.s   .shirt
        ; players
        moveq   #0,d2
.player:
        move.w  d2,d1
        bsr.w   player_address
        lea     reason_nationality(pc),a4
        cmpi.b  #NATIONALITY_COUNT,PLAYER_NATIONALITY(a3)
        bcc.s   .fail
        move.b  PLAYER_FLAGS(a3),d3
        andi.b  #APPEARANCE_MASK,d3
        lea     reason_appearance(pc),a4
        cmpi.b  #APPEARANCE_COUNT<<APPEARANCE_SHIFT,d3
        bcc.s   .fail
        move.b  PLAYER_FLAGS(a3),d3
        andi.b  #POSITION_MASK,d3
        bne.s   .outfield
        move.l  PLAYER_SKILLS(a3),d3
        andi.l  #SKILL_BITS_MASK,d3
        lea     reason_keeper_skills(pc),a4
        bne.s   .fail
        moveq   #0,d3
        move.b  PLAYER_RATING(a3),d3
        cmpi.w  #KEEPER_RATING_MAX,d3
        bls.s   .next
        lea     reason_keeper_rating(pc),a4
        cmpi.w  #KEEPER_RATING_KEPT_MAX,d3
        bhi.s   .fail
        move.w  d2,d4                   ; kept from the original or IMPORT?
        mulu.w  #PLAYER_SIZE,d4
        cmp.b   TEAM_PLAYERS+PLAYER_RATING(a1,d4.w),d3
        beq.s   .next
        cmpa.w  #0,a2
        beq.s   .fail
        cmp.b   TEAM_PLAYERS+PLAYER_RATING(a2,d4.w),d3
        bne.s   .fail
        bra.s   .next
.outfield:
        move.l  PLAYER_SKILLS(a3),d0
        bsr.w   player_rating_sum
        lea     reason_rating(pc),a4
        cmp.b   PLAYER_RATING(a3),d0
        bne.s   .fail
.next:
        addq.w  #1,d2
        cmpi.w  #PLAYER_COUNT,d2
        bcs.w   .player
        moveq   #0,d0
        moveq   #-1,d1
        bra.s   .return
.fail:
        move.l  a4,d0
.return:
        movem.l (sp)+,d2-d7/a0-a6
        rts

; check_kit: A3 = kit. Z set when the pattern and the colours are in range,
; else A4 = the reason.
check_kit:
        lea     reason_kit(pc),a4
        cmpi.b  #KIT_PATTERNS,(a3)
        bcc.s   .bad
        moveq   #KIT_SIZE-2,d3
.colour:
        cmpi.b  #KIT_COLOURS,1(a3,d3.w)
        bcc.s   .bad
        dbf     d3,.colour
        moveq   #0,d3
        rts
.bad:
        moveq   #1,d3
        rts

; player_address: A0 = team, D2.w = physical slot. A3 = the player.
player_address:
        move.l  d2,-(sp)
        mulu.w  #PLAYER_SIZE,d2
        lea     TEAM_PLAYERS(a0,d2.l),a3
        move.l  (sp)+,d2
        rts

; ---------------------------------------------------------------------------
; player_rating_sum: D0.l = skill long. D0.l = sum of the seven ratings.
; ---------------------------------------------------------------------------
player_rating_sum:
        movem.l d1-d3,-(sp)
        moveq   #0,d1
        moveq   #SKILL_COUNT-1,d2
.skill:
        moveq   #SKILL_MAX,d3
        and.l   d0,d3
        add.l   d3,d1
        lsr.l   #4,d0
        dbf     d2,.skill
        move.l  d1,d0
        movem.l (sp)+,d1-d3
        rts

; ---------------------------------------------------------------------------
; lineup_role_of: A0 = team, D0.w = physical slot. D0.l = its lineup role
; 0-15, or -1 when the lineup does not name it.
; ---------------------------------------------------------------------------
lineup_role_of:
        move.l  d1,-(sp)
        moveq   #0,d1
.role:
        cmp.b   TEAM_LINEUP(a0,d1.w),d0
        beq.s   .found
        addq.w  #1,d1
        cmpi.w  #PLAYER_COUNT,d1
        bcs.s   .role
        moveq   #-1,d0
        bra.s   .done
.found:
        move.l  d1,d0
.done:
        move.l  (sp)+,d1
        rts

reason_kit:             dc.b    'A KIT VALUE IS OUT OF RANGE.',0
reason_tactic:          dc.b    'THE DEFAULT TACTIC IS NOT AVAILABLE.',0
reason_lineup:          dc.b    'THE LINEUP NAMES A PLAYER TWICE.',0
reason_keeper:          dc.b    'THE LINEUP HAS NO GOALKEEPER IN GOAL.',0
reason_shirts:          dc.b    'SHIRT NUMBERS MUST BE 1-16, EACH ONCE.',0
reason_nationality:     dc.b    'THE NATIONALITY IS OUT OF RANGE.',0
reason_appearance:      dc.b    'THE APPEARANCE IS OUT OF RANGE.',0
reason_keeper_skills:   dc.b    'A GOALKEEPER HAS OUTFIELD SKILLS.',0
reason_keeper_rating:   dc.b    'THE GOALKEEPER RATING IS ABOVE 38.',0
reason_rating:          dc.b    'THE RATING DIFFERS FROM THE SKILLS.',0
        even
