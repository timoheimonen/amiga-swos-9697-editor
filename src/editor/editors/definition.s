; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Tournament definitions: the rules of a DIY league, cup or tournament and
; its participants, as a .DEF body (definition.i), taken from and given back
; to the game's own setup pages, and their checks.
;
;   definition_capture    the rules of a setup page as a body
;   definition_apply      a body's rules into a setup page's state
;   definition_check      checks a body; definition_check_file a whole file
;   definition_problem_text  the line for a problem
;   definition_identity   the database the game uses for new competitions
;   definition_find_team  a participant's team record in the database or
;                         custom set in use
;
; Hooks of the native DIY flow (resident/menus.s, the runtime hook table):
;
;   definition_type_init  init callback of the type page: no rules or teams
;                         are held from an earlier visit
;   definition_init_*     init callbacks of the setup pages: the rules of a
;                         loaded definition are applied once, then the
;                         native init draws the page from them
;   definition_ok_*       OK: the native phase change, installing the
;                         page copy again (the native OK installs the native
;                         template through a PC-relative LEA)
;   definition_choose_*   CHOOSE TEAMS: the setup is checked first; a setup
;                         the game cannot run stays on the page with the
;                         reason. When the teams of a definition are held
;                         and fit, the user may start with them.
;   definition_chooser    the team chooser call of CHOOSE TEAMS: either the
;                         native chooser, or the held teams put into the
;                         selection exactly as the chooser does, after which
;                         the native code starts the competition through
;                         its initializers and schedule builders
;   definition_selection_note  the first instruction of team_selection_add:
;                         records whether a custom team (group 72) came from
;                         the custom set or the original custom teams
;
; Native action contract: the menu tick saves D0-D7/A0-A6 around an action
; and passes A5 = the selected expanded entry.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    definition_capture, definition_apply
        xdef    definition_check, definition_check_file, definition_problem_text
        xdef    definition_identity, definition_find_team, definition_family_info
        xdef    definition_custom_crc
        xdef    definition_capture_selection, definition_listed_teams
        xdef    definition_type_init
        xdef    definition_init_league, definition_init_cup, definition_init_tournament
        xdef    definition_ok_league, definition_ok_cup, definition_ok_tournament
        xdef    definition_choose_league, definition_choose_cup, definition_choose_tournament
        xdef    definition_chooser, definition_selection_note
        xdef    definition_group_dates
        xdef    definition_capture_check, definition_refusal, definition_problem_lines
        xdef    definition_team_missing
        xref    editor_base
        xref    crc32_buffer
        xref    db_identity
        xref    tactic_check, tactic_problem_text
        xref    storage_size, storage_volume_ready
        xref    message_title, message_line, message_lines, message_show, message_ask
        xref    text_copy, text_decimal, text_glyph

        section .text,code

; ---------------------------------------------------------------------------
; definition_family_info: D0.w = family. A0 = its record. Preserves the rest.
; ---------------------------------------------------------------------------
definition_family_info:
        move.l  d0,-(sp)
        mulu.w  #FI_SIZE,d0
        lea     family_table(pc),a0
        adda.l  d0,a0
        move.l  (sp)+,d0
        rts

; ---------------------------------------------------------------------------
; definition_identity: A1 = body. Writes the identity of the database the
; game uses for new competitions (DI_KIND..DI_LABEL): zero for the original
; database, else the set of USE EDITED DATABASE (db_identity). Preserves all
; registers.
; ---------------------------------------------------------------------------
definition_identity:
        bra.l   db_identity

; ---------------------------------------------------------------------------
; definition_custom_crc: A1 = body. The custom set's CRC-32 as last loaded or
; saved (the team editor's fingerprint) into DI_CUSTOM_CRC and DI_FLAGS, or
; both zero while it is not known. Preserves all registers.
; ---------------------------------------------------------------------------
definition_custom_crc:
        move.l  a5,-(sp)
        movea.l editor_base,a5
        clr.l   DI_CUSTOM_CRC(a1)
        clr.w   DI_FLAGS(a1)
        tst.w   WORK_TEAM+TE_SET_KNOWN(a5)
        beq.s   .done
        move.l  WORK_TEAM+TE_SET_CRC(a5),DI_CUSTOM_CRC(a1)
        move.w  #1<<DIF_CUSTOM_CRC,DI_FLAGS(a1)
.done:
        movea.l (sp)+,a5
        rts

; ---------------------------------------------------------------------------
; definition_capture: D0.w = family, A1 = body (DEF_BODY_FIXED bytes).
; Fills the identity, the custom set's CRC-32 and the rules of the setup
; page's state; no participants and no tactics. Preserves all registers.
; ---------------------------------------------------------------------------
definition_capture:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        move.w  d0,d7
        movea.l a1,a2
        moveq   #DEF_BODY_FIXED/2-1,d1
.clear:
        clr.w   (a1)+
        dbf     d1,.clear
        movea.l a2,a1
        bsr.s   definition_identity
        bsr.s   definition_custom_crc
        move.w  d7,DR_FAMILY(a2)
        move.w  d7,d0
        bsr.s   definition_family_info
        movea.l FI_SCRATCH(a0),a3
        move.w  FI_SUBS(a0),d1
        move.w  (a3,d1.w),DR_SUBS(a2)
        move.w  FI_BENCH(a0),d1
        move.w  (a3,d1.w),DR_BENCH(a2)
        lea     SS_NAME(a3),a0          ; the name, up to its NUL
        lea     DR_NAME(a2),a1
        moveq   #DR_NAME_MAX,d1
.name:
        move.b  (a0)+,(a1)+
        dbeq    d1,.name
        move.w  SS_PITCH_MODE(a3),DR_PITCH_MODE(a2)
        move.w  SS_PITCH_TYPE(a3),DR_PITCH_TYPE(a2)
        move.b  SS_START(a3),DR_START(a2)
        move.b  SS_END(a3),DR_END(a2)
        move.w  SS_TEAMS(a3),DR_TEAMS(a2)
        cmpi.w  #FAMILY_CUP,d7
        beq.s   .cup
        bhi.s   .tournament
        move.w  SS_L_REPEAT(a3),DR_L_REPEAT(a2)
        move.w  SS_L_POINTS(a3),DR_L_POINTS(a2)
        bra.w   .done
.cup:
        move.w  SS_C_ROUNDS(a3),DR_C_ROUNDS(a2)
        move.w  SS_C_AWAY(a3),DR_C_AWAY(a2)
        lea     SS_C_LEGS(a3),a0        ; legs, extra time, penalties: 18 words
        lea     DR_C_LEGS(a2),a1
        moveq   #3*CUP_ROUNDS_MAX-1,d1
.rounds:
        move.w  (a0)+,(a1)+
        dbf     d1,.rounds
        bra.s   .done
.tournament:
        move.w  SS_T_AWAY(a3),DR_T_AWAY(a2)
        moveq   #0,d1
        move.w  SS_T_STAGES(a3),d1
        move.w  d1,DR_T_STAGES(a2)
        cmpi.w  #MAX_STAGES,d1
        bls.s   .count
        moveq   #MAX_STAGES,d1
.count:
        lea     SS_T_SLOT(a3),a0
        lea     DR_T_STAGE(a2),a1
        bra.s   .stage_test
.stage:
        move.w  SL_TEAMS(a0),DS_TEAMS(a1)
        move.w  SL_THROUGH(a0),DS_THROUGH(a1)
        clr.w   DS_GROUPS(a1)
        tst.w   SL_SHAPE(a0)
        beq.s   .knockout
        move.w  SL_GROUPS(a0),DS_GROUPS(a1)
.knockout:
        move.w  SL_GROUP_TEAMS(a0),DS_GROUP_TEAMS(a1)
        move.w  SL_SEEDED(a0),DS_SEEDED(a1)
        move.w  SL_REPEAT(a0),DS_REPEAT(a1)
        move.w  SL_POINTS(a0),DS_POINTS(a1)
        move.w  SL_LEGS(a0),DS_LEGS(a1)
        move.w  SL_EXTRA(a0),DS_EXTRA(a1)
        move.w  SL_PENALTIES(a0),DS_PENALTIES(a1)
        lea     SS_T_SLOT_SIZE(a0),a0
        lea     DS_SIZE(a1),a1
.stage_test:
        dbf     d1,.stage
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; definition_apply: D0.w = family, A1 = a checked body. Writes its rules
; into the setup page's state, as the page's own controls would leave them;
; the stage slots after the last stage get the native terminal marker.
; Preserves all registers.
; ---------------------------------------------------------------------------
definition_apply:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  d0,d7
        movea.l a1,a2
        bsr.w   definition_family_info
        movea.l FI_SCRATCH(a0),a3
        move.w  FI_SUBS(a0),d1
        move.w  DR_SUBS(a2),(a3,d1.w)
        move.w  FI_BENCH(a0),d1
        move.w  DR_BENCH(a2),(a3,d1.w)
        lea     DR_NAME(a2),a0
        lea     SS_NAME(a3),a1
        moveq   #DR_NAME_FIELD-1,d1
.name:
        move.b  (a0)+,(a1)+
        dbf     d1,.name
        move.w  DR_PITCH_MODE(a2),SS_PITCH_MODE(a3)
        move.w  DR_PITCH_TYPE(a2),SS_PITCH_TYPE(a3)
        move.b  DR_START(a2),SS_START(a3)
        move.b  DR_END(a2),SS_END(a3)
        move.w  DR_TEAMS(a2),SS_TEAMS(a3)
        cmpi.w  #FAMILY_CUP,d7
        beq.s   .cup
        bhi.s   .tournament
        move.w  DR_L_REPEAT(a2),SS_L_REPEAT(a3)
        move.w  DR_L_POINTS(a2),SS_L_POINTS(a3)
        bra.w   .done
.cup:
        move.w  DR_C_ROUNDS(a2),SS_C_ROUNDS(a3)
        move.w  DR_C_AWAY(a2),SS_C_AWAY(a3)
        lea     DR_C_LEGS(a2),a0
        lea     SS_C_LEGS(a3),a1
        moveq   #3*CUP_ROUNDS_MAX-1,d1
.rounds:
        move.w  (a0)+,(a1)+
        dbf     d1,.rounds
        bra.w   .done
.tournament:
        move.w  DR_T_AWAY(a2),SS_T_AWAY(a3)
        move.w  DR_T_STAGES(a2),d2
        move.w  d2,SS_T_STAGES(a3)
        clr.w   SS_T_CURRENT(a3)
        lea     SS_T_SLOT(a3),a0
        lea     DR_T_STAGE(a2),a1
        moveq   #0,d1
.stage:
        clr.w   SL_THIRD_PLACE(a0)
        cmp.w   d2,d1
        bcc.s   .marker
        move.w  DS_TEAMS(a1),SL_TEAMS(a0)
        move.w  DS_THROUGH(a1),SL_THROUGH(a0)
        move.w  DS_GROUPS(a1),SL_SHAPE(a0)
        move.w  DS_GROUPS(a1),SL_GROUPS(a0)
        move.w  DS_GROUP_TEAMS(a1),SL_GROUP_TEAMS(a0)
        move.w  DS_SEEDED(a1),SL_SEEDED(a0)
        move.w  DS_REPEAT(a1),SL_REPEAT(a0)
        move.w  DS_POINTS(a1),SL_POINTS(a0)
        move.w  DS_LEGS(a1),SL_LEGS(a0)
        move.w  DS_EXTRA(a1),SL_EXTRA(a0)
        move.w  DS_PENALTIES(a1),SL_PENALTIES(a0)
        bra.s   .next
.marker:
        move.w  #SL_MARKER,SL_TEAMS(a0)
        move.w  #SL_MARKER,SL_THROUGH(a0)
        move.w  #SL_MARKER,SL_SHAPE(a0)
        move.w  #SL_MARKER,SL_GROUPS(a0)
        move.w  #SL_MARKER,SL_GROUP_TEAMS(a0)
        clr.w   SL_SEEDED(a0)
        move.w  #SL_DEFAULT_RULE,SL_REPEAT(a0)
        move.w  #SL_DEFAULT_POINTS,SL_POINTS(a0)
        move.w  #SL_DEFAULT_RULE,SL_LEGS(a0)
        move.w  #SL_DEFAULT_RULE,SL_EXTRA(a0)
        move.w  #SL_DEFAULT_RULE,SL_PENALTIES(a0)
.next:
        lea     SS_T_SLOT_SIZE(a0),a0
        lea     DS_SIZE(a1),a1
        addq.w  #1,d1
        cmpi.w  #MAX_STAGES,d1
        bcs.w   .stage
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; definition_check_file: A0 = a .DEF file, D0.l = its length.
;   out: D0.l = DC_OK or the first problem (definition.i), D1-D3 its
;        details; flags set from D0. Preserves D4-D7/A0-A6.
; ---------------------------------------------------------------------------
definition_check_file:
        movem.l d4-d7/a0-a6,-(sp)
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        movea.l a0,a2
        move.l  d0,d7
        cmpi.l  #DEF_FILE_MIN,d7
        bcs.s   .size
        cmpi.l  #DEF_FILE_MAX,d7
        bhi.s   .size
        cmpi.l  #DEF_MAGIC_HIGH,DH_MAGIC(a2)
        bne.s   .magic
        cmpi.l  #DEF_MAGIC_LOW,DH_MAGIC+4(a2)
        bne.s   .magic
        move.w  DH_VERSION(a2),d1
        cmpi.w  #DEF_VERSION,d1
        bne.s   .version
        moveq   #0,d6
        move.w  DH_LENGTH(a2),d6        ; the body
        moveq   #DEF_HEADER_SIZE,d1
        add.l   d6,d1
        cmp.l   d7,d1
        bne.s   .length
        movea.l editor_base,a5
        lea     DEF_HEADER_SIZE(a2),a0
        move.l  d6,d1
        bsr.l   crc32_buffer
        cmp.l   DH_CRC32(a2),d0
        bne.s   .crc
        lea     DEF_HEADER_SIZE(a2),a0
        move.l  d6,d0
        bsr.s   definition_check
        bra.s   .done
.size:
        moveq   #DC_SIZE,d0
        bra.s   .done
.magic:
        moveq   #DC_MAGIC,d0
        bra.s   .done
.version:
        moveq   #DC_VERSION,d0
        bra.s   .done
.length:
        moveq   #0,d1
        moveq   #DC_LENGTH,d0
        bra.s   .done
.crc:
        moveq   #0,d1
        moveq   #DC_CRC,d0
.done:
        movem.l (sp)+,d4-d7/a0-a6
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; definition_check: A0 = body, D0.l = its length.
;   out: D0.l = DC_OK or the first problem in the order of
;        tools/definition_data.py check_body, D1-D3 its details; flags set
;        from D0. For DC_TACTIC the tactic's own result is in DF_TACTIC.
;        Preserves D4-D7/A0-A6.
; ---------------------------------------------------------------------------
definition_check:
        movem.l d4-d7/a0-a6,-(sp)
        movea.l a0,a2
        move.l  d0,d7
        movea.l editor_base,a5
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        lea     check_steps(pc),a4
.step:
        move.w  (a4)+,d0
        beq.s   .done
        jsr     check_steps(pc,d0.w)
        tst.l   d0
        beq.s   .step
.done:
        movem.l (sp)+,d4-d7/a0-a6
        tst.l   d0
        rts

; The steps: each returns D0.l = 0 or a problem with D1-D3; A2 = body,
; D7 = length, A5 = editor base; D4-D6/A0/A1/A3 are free.
check_steps:
        dc.w    check_layout-check_steps
        dc.w    check_identity-check_steps
        dc.w    check_common-check_steps
        dc.w    check_family-check_steps
        dc.w    check_participants-check_steps
        dc.w    check_tactics-check_steps
        dc.w    0

; PROBLEM code: D0.l = code, return from the step.
PROBLEM macro
        moveq   #\1,d0
        rts
        endm

check_layout:
        cmpi.l  #DEF_BODY_FIXED,d7
        bcs.s   .bad
        moveq   #0,d0
        move.w  DR_TEAM_COUNT(a2),d0
        mulu.w  #DP_SIZE,d0
        move.w  DR_TACTIC_MASK(a2),d4
        moveq   #USER_TACTIC_SLOTS-1,d5
.slot:
        lsr.w   #1,d4
        bcc.s   .next
        addi.l  #TACTIC_SIZE,d0
.next:
        dbf     d5,.slot
        addi.l  #DEF_BODY_FIXED,d0
        cmp.l   d7,d0
        bne.s   .bad
        moveq   #0,d0
        rts
.bad:
        PROBLEM    DC_BODY

check_identity:
        move.w  DI_KIND(a2),d4
        cmpi.w  #DIK_EDITED,d4
        bhi.s   .bad
        beq.s   .edited
        lea     DI_GENERATION(a2),a0    ; the original: nothing else
        moveq   #DI_CUSTOM_CRC-DI_GENERATION-1,d5
.zero:
        tst.b   (a0)+
        bne.s   .bad
        dbf     d5,.zero
        bra.s   .flags
.edited:
        lea     DI_LABEL(a2),a0
        moveq   #DI_LABEL_SIZE,d4       ; field
        moveq   #DI_LABEL_SIZE,d5       ; characters
        moveq   #1,d6                   ; glyphs checked
        bsr.w   text_field_valid
        bne.s   .bad
.flags:
        move.w  DI_FLAGS(a2),d4
        move.w  d4,d5
        andi.w  #~(1<<DIF_CUSTOM_CRC),d5
        bne.s   .bad
        btst    #DIF_CUSTOM_CRC,d4
        bne.s   .reserved
        tst.l   DI_CUSTOM_CRC(a2)
        bne.s   .bad
.reserved:
        tst.w   DI_RESERVED(a2)
        bne.s   .bad
        moveq   #0,d0
        rts
.bad:
        PROBLEM    DC_IDENTITY

check_common:
        move.w  DR_FAMILY(a2),d1
        cmpi.w  #FAMILY_TOURNAMENT,d1
        bls.s   .name
        PROBLEM    DC_FAMILY
.name:
        moveq   #0,d1
        lea     DR_NAME(a2),a0
        moveq   #DR_NAME_FIELD,d4
        moveq   #DR_NAME_MAX,d5
        moveq   #1,d6
        bsr.w   text_field_valid
        beq.s   .pitch
        PROBLEM    DC_NAME
.pitch:
        cmpi.w  #1,DR_PITCH_MODE(a2)
        bhi.s   .bad_pitch
        move.w  DR_PITCH_TYPE(a2),d4
        cmpi.w  #-1,d4
        blt.s   .bad_pitch
        cmpi.w  #PITCH_TYPE_MAX,d4
        bgt.s   .bad_pitch
        move.b  DR_START(a2),d4
        bsr.s   .month
        bne.s   .bad_months
        move.b  DR_END(a2),d4
        bsr.s   .month
        bne.s   .bad_months
        move.w  DR_BENCH(a2),d1
        cmpi.w  #BENCH_MAX,d1
        bls.s   .subs
        PROBLEM    DC_BENCH
.subs:
        move.w  DR_SUBS(a2),d1
        move.w  DR_BENCH(a2),d2
        bne.s   .bench
        tst.w   d1
        bne.s   .bad_subs
        bra.s   .ok
.bench:
        tst.w   d1
        beq.s   .bad_subs
        cmp.w   d2,d1
        bhi.s   .bad_subs
.ok:
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d0
        rts
.bad_subs:
        PROBLEM    DC_SUBS
.bad_pitch:
        PROBLEM    DC_PITCH
.bad_months:
        PROBLEM    DC_MONTHS
; .month: D4.b = month byte. Z set when it is a multiple of eight below a year.
.month:
        moveq   #7,d5
        and.b   d4,d5
        bne.s   .month_done
        cmpi.b  #SEASON_UNITS,d4
        bcs.s   .month_ok
        moveq   #1,d5
        rts
.month_ok:
        moveq   #0,d5
.month_done:
        rts

check_family:
        move.w  DR_FAMILY(a2),d4
        cmpi.w  #FAMILY_CUP,d4
        beq.w   check_cup
        bhi.w   check_tournament
; check_league
        moveq   #0,d1
        move.w  DR_TEAMS(a2),d2
        cmpi.w  #LEAGUE_TEAMS_MIN,d2
        bcs.s   .teams
        cmpi.w  #LEAGUE_TEAMS_MAX,d2
        bls.s   .repeat
.teams:
        PROBLEM    DC_TEAMS
.repeat:
        moveq   #0,d2
        move.w  DR_L_REPEAT(a2),d1
        beq.s   .bad_repeat
        cmpi.w  #LEAGUE_REPEAT_MAX,d1
        bls.s   .points
.bad_repeat:
        PROBLEM    DC_REPEAT
.points:
        move.w  DR_L_POINTS(a2),d1
        bsr.w   points_valid
        beq.s   .rest
        PROBLEM    DC_POINTS
.rest:
        moveq   #0,d1
        lea     DR_L_END(a2),a0
        moveq   #DR_RULES_END-DR_L_END,d4
        bra.w   reserved_zero

check_cup:
        move.w  DR_C_ROUNDS(a2),d1
        beq.s   .bad_rounds
        cmpi.w  #CUP_ROUNDS_MAX,d1
        bls.s   .teams
.bad_rounds:
        PROBLEM    DC_ROUNDS
.teams:
        moveq   #1,d4
        lsl.w   d1,d4
        move.w  DR_TEAMS(a2),d2
        cmp.w   d4,d2
        beq.s   .away
        PROBLEM    DC_CUP_TEAMS
.away:
        moveq   #0,d1
        moveq   #0,d2
        cmpi.w  #RULE_ENUM_MAX,DR_C_AWAY(a2)
        bls.s   .rounds
        PROBLEM    DC_AWAY
.rounds:
        moveq   #DCK_ROUND,d1
        moveq   #0,d2
        lea     DR_C_LEGS(a2),a0
.round:
        addq.w  #1,d2
        move.w  (a0),d4
        beq.s   .bad_legs
        cmpi.w  #2,d4
        bhi.s   .bad_legs
        cmpi.w  #RULE_ENUM_MAX,DR_C_EXTRA-DR_C_LEGS(a0)
        bhi.s   .bad_extra
        cmpi.w  #RULE_ENUM_MAX,DR_C_PENALTIES-DR_C_LEGS(a0)
        bhi.s   .bad_penalties
        addq.l  #2,a0
        cmpi.w  #CUP_ROUNDS_MAX,d2
        bcs.s   .round
        moveq   #0,d1
        moveq   #0,d2
        lea     DR_C_END(a2),a0
        moveq   #DR_RULES_END-DR_C_END,d4
        bra.w   reserved_zero
.bad_legs:
        PROBLEM    DC_LEGS
.bad_extra:
        PROBLEM    DC_EXTRA
.bad_penalties:
        PROBLEM    DC_PENALTIES

check_tournament:
        moveq   #FAMILY_TOURNAMENT,d1
        move.w  DR_TEAMS(a2),d2
        cmpi.w  #2,d2
        bcs.s   .teams
        cmpi.w  #TOURNAMENT_TEAMS_MAX,d2
        bls.s   .away
.teams:
        PROBLEM    DC_TEAMS
.away:
        moveq   #0,d1
        moveq   #0,d2
        cmpi.w  #RULE_ENUM_MAX,DR_T_AWAY(a2)
        bls.s   .stages
        PROBLEM    DC_AWAY
.stages:
        move.w  DR_T_STAGES(a2),d1
        beq.s   .bad_stages
        cmpi.w  #MAX_STAGES,d1
        bls.s   .chain
.bad_stages:
        PROBLEM    DC_STAGES
.chain:
        move.w  d1,d5                   ; stages
        move.w  DR_TEAMS(a2),d6         ; teams expected
        lea     DR_T_STAGE(a2),a3
        moveq   #1,d4                   ; stage number
.stage:
        bsr.w   check_stage
        bne.s   .return
        move.w  DS_THROUGH(a3),d6
        lea     DS_SIZE(a3),a3
        addq.w  #1,d4
        cmp.w   d5,d4
        bls.s   .stage
.unused:
        cmpi.w  #MAX_STAGES,d4          ; the slots after the last stage are zero
        bhi.s   .rest
        movea.l a3,a0
        moveq   #DS_SIZE-1,d0
.unused_byte:
        tst.b   (a0)+
        bne.s   .bad_unused
        dbf     d0,.unused_byte
        lea     DS_SIZE(a3),a3
        addq.w  #1,d4
        bra.s   .unused
.bad_unused:
        moveq   #0,d1
        move.w  d4,d1
        PROBLEM    DC_UNUSED_STAGE
.rest:
        moveq   #0,d1
        lea     DR_T_END(a2),a0
        moveq   #DR_RULES_END-DR_T_END,d4
        bra.w   reserved_zero
.return:
        rts

; check_stage: A3 = stage record, D4.w = its number (1-6), D5.w = stages,
; D6.w = teams expected. D0.l = 0 or a problem with D1-D3.
check_stage:
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        move.w  d4,d1
        move.w  DS_TEAMS(a3),d2
        cmp.w   d6,d2
        beq.s   .native
        move.w  d6,d3
        PROBLEM    DC_CHAIN
.native:
        cmpi.w  #TOURNAMENT_REFUSED_A,d2
        beq.s   .refused
        cmpi.w  #TOURNAMENT_REFUSED_B,d2
        bne.s   .through
.refused:
        PROBLEM    DC_NATIVE_TEAMS
.through:
        move.w  DS_TEAMS(a3),d3
        move.w  DS_THROUGH(a3),d2
        beq.s   .bad_through
        cmp.w   d3,d2
        bcs.s   .final
.bad_through:
        PROBLEM    DC_THROUGH
.final:
        moveq   #0,d2
        moveq   #0,d3
        cmpi.w  #1,DS_THROUGH(a3)
        bne.s   .not_final
        cmp.w   d5,d4
        beq.s   .shape
        PROBLEM    DC_FINAL_EARLY
.not_final:
        cmp.w   d5,d4
        bne.s   .shape
        move.w  DS_THROUGH(a3),d1
        PROBLEM    DC_FINAL
.shape:
        move.w  DS_GROUPS(a3),d0
        bne.s   .groups
        bsr.w   knockout_valid
        beq.s   .rules
        move.w  DS_TEAMS(a3),d2
        PROBLEM    DC_KNOCKOUT
.groups:
        bsr.w   groups_valid
        beq.s   .rules
        move.w  DS_GROUPS(a3),d2
        move.w  DS_GROUP_TEAMS(a3),d3
        PROBLEM    DC_GROUPS
.rules:
        cmpi.w  #1,DS_SEEDED(a3)
        bls.s   .repeat
        PROBLEM    DC_SEEDED
.repeat:
        move.w  DS_REPEAT(a3),d2
        beq.s   .bad_repeat
        cmpi.w  #STAGE_REPEAT_MAX,d2
        bls.s   .points
.bad_repeat:
        PROBLEM    DC_STAGE_REPEAT
.points:
        move.w  DS_POINTS(a3),d2
        move.l  d1,-(sp)
        move.w  d2,d1
        bsr.w   points_valid
        movem.l (sp)+,d1                ; keeps the flags
        beq.s   .legs
        PROBLEM    DC_STAGE_POINTS
.legs:
        moveq   #DCK_STAGE,d1
        move.w  d4,d2
        move.w  DS_LEGS(a3),d0
        beq.s   .bad_legs
        cmpi.w  #2,d0
        bhi.s   .bad_legs
        cmpi.w  #RULE_ENUM_MAX,DS_EXTRA(a3)
        bhi.s   .bad_extra
        cmpi.w  #RULE_ENUM_MAX,DS_PENALTIES(a3)
        bhi.s   .bad_penalties
        move.w  d4,d1
        moveq   #0,d2
        tst.w   DS_GROUPS(a3)
        beq.s   .ok
        move.w  DS_GROUP_TEAMS(a3),d0
        move.w  DS_REPEAT(a3),d2
        bsr.w   definition_group_dates  ; D0 = dates
        move.w  d0,d2
        cmpi.w  #STAGE_DATES_MAX,d2
        bls.s   .ok
        PROBLEM    DC_DATES
.ok:
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d0
        rts
.bad_legs:
        PROBLEM    DC_LEGS
.bad_extra:
        PROBLEM    DC_EXTRA
.bad_penalties:
        PROBLEM    DC_PENALTIES

; knockout_valid: A3 = stage record, D4.w = stage. Z set when the knockout
; is one the native shape helpers offer: even entrants, twice the teams
; going through, entrants as its teams per group, in stage 6 only a
; two-team final, in stage 5 at most STAGE5_KNOCKOUT_MAX teams.
knockout_valid:
        movem.l d0-d1,-(sp)
        move.w  DS_TEAMS(a3),d0
        btst    #0,d0
        bne.s   .no
        move.w  DS_THROUGH(a3),d1
        add.w   d1,d1
        cmp.w   d0,d1
        bne.s   .no
        cmp.w   DS_GROUP_TEAMS(a3),d0
        bne.s   .no
        cmpi.w  #6,d4
        bne.s   .five
        cmpi.w  #2,d0
        bne.s   .no
.five:
        cmpi.w  #5,d4
        bne.s   .yes
        cmpi.w  #STAGE5_KNOCKOUT_MAX,d0
        bhi.s   .no
.yes:
        movem.l (sp)+,d0-d1
        cmp.w   d0,d0                   ; Z set
        rts
.no:
        movem.l (sp)+,d0-d1
        moveq   #1,d0                   ; Z clear
        rts

; groups_valid: A3 = stage record, D4.w = stage. Z set when its groups are
; a layout the native shape helpers offer.
groups_valid:
        movem.l d0-d2,-(sp)
        move.w  DS_GROUPS(a3),d1
        cmpi.w  #MAX_GROUPS,d1
        bhi.s   .no
        cmp.w   DS_THROUGH(a3),d1
        bhi.s   .no
        moveq   #0,d0
        move.w  DS_TEAMS(a3),d0
        cmp.w   d0,d1
        bcc.s   .no
        divu.w  d1,d0
        swap    d0
        tst.w   d0
        bne.s   .no
        swap    d0
        cmp.w   DS_GROUP_TEAMS(a3),d0
        bne.s   .no
        cmpi.w  #MAX_GROUP_TEAMS,d0
        bhi.s   .no
        cmpi.w  #6,d4
        bne.s   .yes
        cmpi.w  #1,d1
        bne.s   .no
.yes:
        movem.l (sp)+,d0-d2
        cmp.w   d0,d0
        rts
.no:
        movem.l (sp)+,d0-d2
        moveq   #1,d0
        rts

; definition_group_dates: D0.w = teams per group (at least 2), D2.w =
; repetitions. D0.l = the stage's match dates (the native count of
; $1A9C6A). Preserves the other registers.
definition_group_dates:
        movem.l d1/d3,-(sp)
        moveq   #0,d1
        move.w  d0,d1
        move.w  d0,d3
        subq.w  #1,d3
        mulu.w  d3,d1                   ; n*(n-1)
        lsr.l   #1,d1                   ; pairs
        lsr.w   #1,d0                   ; matches a date
        divu.w  d0,d1
        mulu.w  d2,d1
        move.l  d1,d0
        movem.l (sp)+,d1/d3
        rts

; points_valid: D1.w = points. Z set for 2 or 3.
points_valid:
        cmpi.w  #2,d1
        beq.s   .done
        cmpi.w  #3,d1
.done:
        rts

; reserved_zero: A0 = bytes, D4.w = count. D0.l = 0, or DC_RESERVED.
reserved_zero:
        subq.w  #1,d4
.byte:
        tst.b   (a0)+
        bne.s   .bad
        dbf     d4,.byte
        moveq   #0,d0
        rts
.bad:
        PROBLEM    DC_RESERVED

check_participants:
        move.w  DR_TEAM_COUNT(a2),d1
        beq.w   .ok
        move.w  DR_TEAMS(a2),d2
        cmp.w   d2,d1
        beq.s   .entries
        PROBLEM    DC_TEAM_COUNT
.entries:
        moveq   #0,d2
        lea     DEF_BODY_FIXED(a2),a3
        moveq   #0,d5                   ; index
.entry:
        moveq   #0,d1
        move.w  d5,d1
        addq.w  #1,d1                   ; reported 1-based
        cmpi.b  #DPS_CUSTOM_SET,DP_SOURCE(a3)
        bhi.s   .bad_entry
        move.b  DP_CONTROL(a3),d4
        cmpi.b  #CONTROL_COMPUTER,d4
        bcs.s   .bad_entry
        cmpi.b  #CONTROL_COACH,d4
        bhi.s   .bad_entry
        lea     DP_NAME(a3),a0
        moveq   #DP_NAME_SIZE,d4
        moveq   #DP_NAME_SIZE-1,d5
        moveq   #0,d6
        bsr.w   text_field_valid        ; keeps D1
        bne.s   .bad_entry
        move.w  d1,d5                   ; the index again
        subq.w  #1,d5
        tst.b   DP_NAME+DP_NAME_SIZE(a3)
        bne.s   .bad_entry
        tst.w   DP_NAME+DP_NAME_SIZE+1(a3)
        bne.s   .bad_entry
        moveq   #0,d2
        move.b  DP_GROUP(a3),d2
        tst.b   DP_SOURCE(a3)
        bne.s   .custom
        bsr.w   group_known
        bne.s   .bad_group
        bra.s   .twice
.custom:
        cmpi.b  #CUSTOM_KEY_GROUP,d2
        bne.s   .bad_group
.twice:
        moveq   #0,d2
        move.w  (a3),d4                 ; key
        lea     DEF_BODY_FIXED(a2),a0
.earlier:
        cmpa.l  a3,a0
        bcc.s   .next
        cmp.w   (a0),d4
        beq.s   .bad_twice
        lea     DP_SIZE(a0),a0
        bra.s   .earlier
.next:
        lea     DP_SIZE(a3),a3
        addq.w  #1,d5
        cmp.w   DR_TEAM_COUNT(a2),d5
        bcs.w   .entry
.ok:
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d0
        rts
.bad_entry:
        moveq   #0,d2
        PROBLEM    DC_TEAM_ENTRY
.bad_group:
        PROBLEM    DC_TEAM_GROUP
.bad_twice:
        PROBLEM    DC_TEAM_TWICE

; group_known: D2.w = group. Z set when TEAM.ggg is on disk 2.
group_known:
        movem.l d0-d1/a0,-(sp)
        cmpi.w  #TEAM_GROUP_MAP_SIZE*8,d2
        bcc.s   .no
        move.w  d2,d0
        lsr.w   #3,d0
        lea     team_group_map(pc),a0
        move.b  (a0,d0.w),d0
        moveq   #7,d1
        and.w   d2,d1
        eori.w  #7,d1                   ; bit 7 is the first group of a byte
        btst    d1,d0
        beq.s   .no
        movem.l (sp)+,d0-d1/a0
        cmp.w   d0,d0
        rts
.no:
        movem.l (sp)+,d0-d1/a0
        moveq   #1,d0
        rts

check_tactics:
        move.w  DR_TACTIC_MASK(a2),d4
        move.w  d4,d0
        andi.w  #~DEF_TACTIC_MASK_ALL,d0
        beq.s   .slots
        PROBLEM    DC_TACTIC_MASK
.slots:
        moveq   #0,d0
        move.w  DR_TEAM_COUNT(a2),d0
        mulu.w  #DP_SIZE,d0
        lea     DEF_BODY_FIXED(a2,d0.l),a0
        moveq   #0,d5                   ; slot
.slot:
        btst    d5,d4
        beq.s   .next
        bsr.l   tactic_check            ; A0 = record; preserves D4-D7/A0-A6
        bne.s   .bad
        lea     TACTIC_SIZE(a0),a0
.next:
        addq.w  #1,d5
        cmpi.w  #USER_TACTIC_SLOTS,d5
        bcs.s   .slot
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        moveq   #0,d0
        rts
.bad:
        move.w  d0,WORK_DEF+DF_TACTIC(a5)
        movem.l d1-d3,WORK_DEF+DF_TACTIC_DETAIL(a5)
        moveq   #0,d1
        move.w  d5,d1
        moveq   #0,d2
        moveq   #0,d3
        PROBLEM    DC_TACTIC

; text_field_valid: A0 = field, D4.w = its size, D5.w = most characters,
; D6.w = 1 to require the glyphs of the native text entry. Z set when the
; text ends with a NUL within D5+1 bytes (or fills a field of D5 bytes),
; every byte after its end is zero and its characters are allowed.
; Preserves D0-D3.
text_field_valid:
        movem.l d0-d3/a0,-(sp)
        moveq   #0,d1                   ; end of the text
.scan:
        cmp.w   d4,d1
        bcc.s   .end
        tst.b   (a0,d1.w)
        beq.s   .end
        addq.w  #1,d1
        bra.s   .scan
.end:
        cmp.w   d5,d1
        bhi.s   .no
        move.w  d1,d2
.tail:
        cmp.w   d4,d2
        bcc.s   .glyphs
        tst.b   (a0,d2.w)
        bne.s   .no
        addq.w  #1,d2
        bra.s   .tail
.glyphs:
        tst.w   d6
        beq.s   .yes
        moveq   #0,d2
.glyph:
        cmp.w   d1,d2
        bcc.s   .yes
        move.b  (a0,d2.w),d0
        bsr.l   text_glyph              ; Z clear when the font shows it
        beq.s   .no
        addq.w  #1,d2
        bra.s   .glyph
.yes:
        movem.l (sp)+,d0-d3/a0
        cmp.w   d0,d0
        rts
.no:
        movem.l (sp)+,d0-d3/a0
        moveq   #1,d4                   ; Z clear (D4 is the caller's scratch)
        rts

; ---------------------------------------------------------------------------
; definition_problem_text: D0.l = DC_* (not DC_OK), D1-D3 = details, A1 =
; text. Appends the line of tools/definition_data.py problem_text.
; Preserves all registers except A1 (left on the NUL).
; ---------------------------------------------------------------------------
definition_problem_text:
        movem.l d0-d4/a0,-(sp)
        move.w  d0,d4
        cmpi.w  #DC_SUBS,d4
        bne.s   .teams
        tst.w   d2
        bne.s   .lookup
        moveq   #DC_LAST+1,d4           ; without a bench
        bra.s   .lookup
.teams:
        cmpi.w  #DC_TEAMS,d4
        bne.s   .lookup
        tst.w   d1
        beq.s   .lookup
        moveq   #DC_LAST+2,d4           ; a tournament
.lookup:
        cmpi.w  #DC_LAST+2,d4
        bhi.s   .done
        add.w   d4,d4
        lea     problem_texts(pc),a0
        adda.w  (a0,d4.w),a0
.char:
        move.b  (a0)+,d0
        beq.s   .done
        cmpi.b  #PT_LAST,d0
        bhi.s   .literal
        bsr.s   .insert
        bra.s   .char
.literal:
        move.b  d0,(a1)+
        bra.s   .char
.done:
        clr.b   (a1)
        movem.l (sp)+,d0-d4/a0
        rts
; .insert: D0.b = PT_* code; A0 (the template) is kept.
.insert:
        movem.l d0/a0,-(sp)
        cmpi.b  #PT_D1,d0
        bne.s   .d2
        move.w  d1,d0
        bra.s   .number
.d2:
        cmpi.b  #PT_D2,d0
        bne.s   .d3
        move.w  d2,d0
        bra.s   .number
.d3:
        cmpi.b  #PT_D3,d0
        bne.s   .kind
        move.w  d3,d0
        bra.s   .number
.kind:
        cmpi.b  #PT_KIND,d0
        bne.s   .letter
        lea     text_round(pc),a0
        tst.w   d1
        beq.s   .kind_text
        lea     text_stage(pc),a0
.kind_text:
        bsr.l   text_copy
        bra.s   .inserted
.letter:
        cmpi.b  #PT_LETTER,d0
        bne.s   .power
        moveq   #'A',d0
        add.b   d1,d0
        move.b  d0,(a1)+                ; the caller's NUL follows
        bra.s   .inserted
.power:
        moveq   #1,d0
        lsl.w   d1,d0
.number:
        bsr.l   text_decimal
.inserted:
        movem.l (sp)+,d0/a0
        rts

; ---------------------------------------------------------------------------
; definition_find_team: A3 = participant. Loads its group through
; file_load_team_group from the volume the team chooser reads it from: game
; disk 2 for a database group, the save volume for the custom set
; (DPS_CUSTOM_SET, after the request storage_volume_ready replaces); game
; disk 2 is selected again afterwards, as the native flows leave it. Finds
; the participant's key. A0 = the record in team_group_buffer with Z clear,
; or Z set when the team is missing. Preserves D1-D7/A1-A6.
; ---------------------------------------------------------------------------
definition_find_team:
        movem.l d1-d2/d7/a1,-(sp)
        moveq   #0,d0
        move.b  DP_GROUP(a3),d0
        cmpi.b  #DPS_CUSTOM_SET,DP_SOURCE(a3)
        bne.s   .database
        lea     custom_set_name,a0      ; a missing custom set is a missing team
        bsr.l   storage_size
        bne.s   .missing
        bsr.l   storage_volume_ready    ; clobbers D7
        moveq   #CUSTOM_SET_GROUP,d0
        jsr     file_load_team_group
        jsr     game_disk2_request
        bra.s   .loaded
.database:
        jsr     game_disk2_request      ; D0/D1 are its results
        moveq   #0,d0
        move.b  DP_GROUP(a3),d0
        jsr     file_load_team_group
.loaded:
        lea     team_group_buffer,a0
        moveq   #0,d1
        move.w  (a0)+,d1
        cmpi.w  #(TEAM_GROUP_BUFFER_SIZE-GROUP_COUNT_SIZE)/TEAM_SIZE,d1
        bls.s   .count
        move.w  #(TEAM_GROUP_BUFFER_SIZE-GROUP_COUNT_SIZE)/TEAM_SIZE,d1
.count:
        move.w  (a3),d2                 ; key: group and ordinal
        bra.s   .test
.scan:
        cmp.w   TEAM_KEY(a0),d2
        beq.s   .found
        lea     TEAM_SIZE(a0),a0
.test:
        dbf     d1,.scan
.missing:
        movem.l (sp)+,d1-d2/d7/a1
        moveq   #0,d0                   ; Z set
        rts
.found:
        movem.l (sp)+,d1-d2/d7/a1
        moveq   #1,d0                   ; Z clear
        rts

; ---------------------------------------------------------------------------
; definition_listed_teams: A2 = body. Resolves every participant
; (definition_find_team). D0.l = 0, or the 1-based participant that is
; missing (flags set). Preserves all other registers.
; ---------------------------------------------------------------------------
definition_listed_teams:
        movem.l d1/a0/a3,-(sp)
        lea     DEF_BODY_FIXED(a2),a3
        moveq   #0,d1
.next:
        cmp.w   DR_TEAM_COUNT(a2),d1
        bcc.s   .all
        bsr.w   definition_find_team
        beq.s   .missing
        lea     DP_SIZE(a3),a3
        addq.w  #1,d1
        bra.s   .next
.all:
        moveq   #0,d0
        bra.s   .done
.missing:
        moveq   #0,d0
        move.w  d1,d0
        addq.w  #1,d0
.done:
        movem.l (sp)+,d1/a0/a3
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; definition_capture_selection: the chooser's selection as participants
; (DF_LIST, DF_TEAMS) for the family D0.w; the selection is emptied after.
; A5 = editor base. Preserves all registers.
; ---------------------------------------------------------------------------
definition_capture_selection:
        movem.l d0-d7/a0-a6,-(sp)
        move.w  d0,WORK_DEF+DF_FAMILY(a5)
        moveq   #0,d7
        move.w  team_selection_count,d7
        cmpi.w  #TEAM_SELECTION_MAX,d7
        bls.s   .count
        moveq   #TEAM_SELECTION_MAX,d7
.count:
        move.w  d7,WORK_DEF+DF_TEAMS(a5)
        lea     team_selection,a0
        lea     WORK_DEF+DF_LIST(a5),a1
        bra.s   .test
.team:
        movea.l a1,a2
        moveq   #DP_SIZE/2-1,d0
.clear:
        clr.w   (a2)+
        dbf     d0,.clear
        move.b  TEAM_KEY(a0),DP_GROUP(a1)
        move.b  TEAM_KEY+1(a0),DP_ORDINAL(a1)
        move.b  TEAM_CONTROL(a0),DP_CONTROL(a1)
        cmpi.b  #CUSTOM_KEY_GROUP,TEAM_KEY(a0)
        bne.s   .name
        moveq   #TEAM_SELECTION_MAX-1,d0
        and.b   TEAM_KEY+1(a0),d0
        move.b  WORK_DEF+DF_CUSTOM(a5,d0.w),DP_SOURCE(a1)
.name:
        lea     TEAM_NAME(a0),a2
        lea     DP_NAME(a1),a3
        moveq   #DP_NAME_SIZE-2,d0      ; at most 16 characters
.char:
        move.b  (a2)+,(a3)+
        dbeq    d0,.char
        lea     TEAM_SIZE(a0),a0
        lea     DP_SIZE(a1),a1
.test:
        dbf     d7,.team
        clr.w   team_selection_count
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; definition_selection_note: replaces the first instruction of
; team_selection_add (LEA team_selection,A1). A0 = the record being added.
; For a custom team (group 72) it records whether the group in the buffer
; is the custom set; then it does the replaced LEA. Preserves the rest.
; ---------------------------------------------------------------------------
definition_selection_note:
        movem.l d0/a1,-(sp)
        cmpi.b  #CUSTOM_KEY_GROUP,TEAM_KEY(a0)
        bne.s   .done
        movea.l editor_base,a1
        moveq   #TEAM_SELECTION_MAX-1,d0
        and.b   TEAM_KEY+1(a0),d0
        adda.w  d0,a1
        move.b  #DPS_DATABASE,WORK_DEF+DF_CUSTOM(a1)
        cmpi.b  #CUSTOM_SET_GROUP,team_group_cache_key
        bne.s   .done
        move.b  #DPS_CUSTOM_SET,WORK_DEF+DF_CUSTOM(a1)
.done:
        movem.l (sp)+,d0/a1
        lea     team_selection,a1
        rts

; ---------------------------------------------------------------------------
; Page callbacks and actions
; ---------------------------------------------------------------------------

; definition_type_init: init callback of the type page copy.
definition_type_init:
        move.l  a5,-(sp)
        movea.l editor_base,a5
        clr.w   WORK_DEF+DF_STATE(a5)
        clr.w   WORK_DEF+DF_TEAMS(a5)
        movea.l (sp)+,a5
        rts

definition_init_league:
        move.l  d0,-(sp)
        moveq   #FAMILY_LEAGUE,d0
        bsr.s   apply_held
        move.l  (sp)+,d0
        jmp     diy_league_init

definition_init_cup:
        move.l  d0,-(sp)
        moveq   #FAMILY_CUP,d0
        bsr.s   apply_held
        move.l  (sp)+,d0
        jmp     diy_cup_init

definition_init_tournament:
        move.l  d0,-(sp)
        moveq   #FAMILY_TOURNAMENT,d0
        bsr.s   apply_held
        move.l  (sp)+,d0
        jmp     diy_tournament_init

; apply_held: D0.w = family of the page. The rules of a loaded definition
; of that family are written into its state, once. Preserves all registers.
apply_held:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        bclr    #DFS_APPLY,WORK_DEF+DF_STATE+1(a5)
        beq.s   .done
        cmp.w   WORK_DEF+DF_FAMILY(a5),d0
        bne.s   .done
        lea     WORK_DEF+DF_BODY(a5),a1
        bsr.w   definition_apply
.done:
        movem.l (sp)+,d0-d7/a0-a6
        rts

definition_ok_league:
        move.w  #1,diy_league_phase
        move.l  #WORK_DIY_LEAGUE,d0
        bra.s   install_copy

definition_ok_cup:
        move.w  #1,diy_cup_phase
        move.l  #WORK_DIY_CUP,d0
        bra.s   install_copy

definition_ok_tournament:
        move.w  #1,diy_tournament_phase
        move.l  #WORK_DIY_TOURNAMENT,d0
; install_copy: D0.l = offset of the page copy. Installs it as the
; native OK does with its template.
install_copy:
        movea.l editor_base,a6
        adda.l  d0,a6
        jmp     menu_install

definition_choose_league:
        moveq   #FAMILY_LEAGUE,d0
        bra.s   choose
definition_choose_cup:
        moveq   #FAMILY_CUP,d0
        bra.s   choose
definition_choose_tournament:
        moveq   #FAMILY_TOURNAMENT,d0
; choose: CHOOSE TEAMS of the family D0.w (an entry action).
choose:
        move.l  a5,-(sp)
        movea.l editor_base,a5
        move.w  d0,d6
        bclr    #DFS_ARMED,WORK_DEF+DF_STATE+1(a5)
        bsr.w   definition_capture_check
        bne.w   .refused
        tst.w   WORK_DEF+DF_TEAMS(a5)
        beq.w   .native
        cmp.w   WORK_DEF+DF_FAMILY(a5),d6
        bne.w   .native
        move.w  WORK_DEF+DF_TEAMS(a5),d0
        cmp.w   WORK_DEF+DF_BODY+DR_TEAMS(a5),d0
        bne.s   .native
        lea     title_start(pc),a0
        bsr.l   message_title
        lea     WORK_DEF+DF_STATUS(a5),a1
        lea     text_listed(pc),a0
        bsr.l   text_copy
        move.w  WORK_DEF+DF_TEAMS(a5),d0
        bsr.l   text_decimal
        lea     text_listed_end(pc),a0
        bsr.l   text_copy
        lea     WORK_DEF+DF_STATUS(a5),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     start_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        bsr.l   message_ask
        tst.l   d0
        beq.s   .native
        bset    #DFS_ARMED,WORK_DEF+DF_STATE+1(a5)
.native:
        move.w  d6,d0
        bsr.w   definition_family_info
        movea.l FI_CHOOSE(a0),a0
        movea.l (sp)+,a5
        jmp     (a0)
.refused:
        lea     title_not_started(pc),a0
        bsr.s   definition_refusal
        movea.l (sp)+,a5
        rts

; ---------------------------------------------------------------------------
; definition_capture_check: D0.w = family, A5 = editor base. The setup
; page's rules as a body in DF_BODY (definition_capture), checked: A0 = A1
; = DF_BODY; D0.l, D1-D3 and the flags as definition_check.
; ---------------------------------------------------------------------------
definition_capture_check:
        lea     WORK_DEF+DF_BODY(a5),a1
        bsr.w   definition_capture
        movea.l a1,a0
        move.l  #DEF_BODY_FIXED,d0
        bra.w   definition_check

; ---------------------------------------------------------------------------
; definition_refusal: A0 = title, D0.l = a problem of definition_check with
; D1-D3, A5 = editor base. Shows it with CHANGE THE RULES ON THIS PAGE.
; Changes D0-D3/A0-A1.
; ---------------------------------------------------------------------------
definition_refusal:
        bsr.l   message_title
        move.l  d4,-(sp)
        moveq   #0,d4
        bsr.s   definition_problem_lines
        move.l  (sp)+,d4
        lea     line_change_rules(pc),a0
        moveq   #2,d0
        bsr.l   message_line
        bra.l   message_show

; ---------------------------------------------------------------------------
; definition_problem_lines: D0.l = a problem of definition_check with D1-D3,
; D4.w = message line, A5 = editor base. Its line in the message being
; built, and for DC_TACTIC the tactic's own problem on the next line.
; Changes D0-D3/A0-A1.
; ---------------------------------------------------------------------------
definition_problem_lines:
        move.l  d0,-(sp)
        lea     WORK_DEF+DF_STATUS(a5),a1
        bsr.w   definition_problem_text
        lea     WORK_DEF+DF_STATUS(a5),a0
        move.w  d4,d0
        bsr.l   message_line
        cmpi.l  #DC_TACTIC,(sp)+
        bne.s   .done
        lea     WORK_DEF+DF_STATUS(a5),a1
        clr.b   (a1)
        moveq   #0,d0
        move.w  WORK_DEF+DF_TACTIC(a5),d0
        movem.l WORK_DEF+DF_TACTIC_DETAIL(a5),d1-d3
        bsr.l   tactic_problem_text
        lea     WORK_DEF+DF_STATUS(a5),a0
        move.w  d4,d0
        addq.w  #1,d0
        bra.l   message_line
.done:
        rts

; ---------------------------------------------------------------------------
; definition_team_missing: A3 = participant, D0.w = its number (1-based),
; D1.w = message line, A5 = editor base. Starts the message TEAM NOT FOUND
; with TEAM n OF THE LIST: <name> on line D1 and where it is missing on the
; next line. Changes D0/A0-A1.
; ---------------------------------------------------------------------------
definition_team_missing:
        lea     title_team_missing(pc),a0
        bsr.l   message_title
        lea     WORK_DEF+DF_STATUS(a5),a1
        lea     text_team(pc),a0
        bsr.l   text_copy
        bsr.l   text_decimal
        lea     text_of_list(pc),a0
        bsr.l   text_copy
        lea     DP_NAME(a3),a0
        bsr.l   text_copy
        lea     WORK_DEF+DF_STATUS(a5),a0
        move.w  d1,d0
        bsr.l   message_line
        lea     line_not_in_database(pc),a0
        tst.b   DP_SOURCE(a3)
        beq.s   .where
        lea     line_not_in_custom(pc),a0
.where:
        addq.w  #1,d0
        bra.l   message_line

; ---------------------------------------------------------------------------
; definition_chooser: replaces JSR team_chooser in CHOOSE TEAMS (D0 = teams,
; A0 = name, A1 = button label, D2-D4 categories). When the user chose to
; start with a definition's teams, they go into the selection as the
; chooser puts them there and team_chooser_done is set; otherwise the native
; chooser runs.
; ---------------------------------------------------------------------------
definition_chooser:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        bclr    #DFS_ARMED,WORK_DEF+DF_STATE+1(a5)
        bne.s   .held
        lea     WORK_DEF+DF_CUSTOM(a5),a0
        moveq   #TEAM_SELECTION_MAX/4-1,d0
.clear:
        clr.l   (a0)+
        dbf     d0,.clear
        movem.l (sp)+,d0-d7/a0-a6
        jmp     team_chooser
.held:
        clr.w   team_selection_count
        lea     WORK_DEF+DF_LIST(a5),a3
        moveq   #0,d7
.team:
        cmp.w   WORK_DEF+DF_TEAMS(a5),d7
        bcc.s   .done
        bsr.w   definition_find_team    ; A0 = record
        beq.s   .missing
        jsr     team_selection_add      ; A0 = the copy
        move.b  DP_CONTROL(a3),TEAM_CONTROL(a0)
        lea     DP_SIZE(a3),a3
        addq.w  #1,d7
        bra.s   .team
.done:
        move.w  #1,team_chooser_done
        movem.l (sp)+,d0-d7/a0-a6
        rts
.missing:
        move.w  d7,d0
        addq.w  #1,d0
        moveq   #0,d1
        bsr.w   definition_team_missing
        lea     line_not_started(pc),a0
        moveq   #3,d0
        bsr.l   message_line
        bsr.l   message_show
        clr.w   team_selection_count
        clr.w   team_chooser_done
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
family_table:
        dc.l    diy_scratch,diy_league_choose
        dc.w    SS_L_SUBS,SS_L_BENCH
        dc.l    diy_scratch,diy_cup_choose
        dc.w    SS_C_SUBS,SS_C_BENCH
        dc.l    diy_tournament_scratch,diy_tournament_choose
        dc.w    SS_T_SUBS,SS_T_BENCH

team_group_map:
        TEAM_GROUP_MAP

; Problem texts: placeholders PT_D1..PT_D3 (a detail in decimal), PT_KIND
; (ROUND for DCK_ROUND in D1, else STAGE), PT_LETTER ('A' + D1), PT_POWER
; (2 to the power D1).
PT_D1                   equ 1
PT_D2                   equ 2
PT_D3                   equ 3
PT_KIND                 equ 4
PT_LETTER               equ 5
PT_POWER                equ 6
PT_LAST                 equ PT_POWER

PTEXT   macro
        dc.w    \1-problem_texts
        endm
problem_texts:
        PTEXT    pt_none
        PTEXT    pt_size
        PTEXT    pt_magic
        PTEXT    pt_version
        PTEXT    pt_length
        PTEXT    pt_crc
        PTEXT    pt_body
        PTEXT    pt_identity
        PTEXT    pt_family
        PTEXT    pt_name
        PTEXT    pt_pitch
        PTEXT    pt_months
        PTEXT    pt_bench
        PTEXT    pt_subs
        PTEXT    pt_teams
        PTEXT    pt_repeat
        PTEXT    pt_points
        PTEXT    pt_rounds
        PTEXT    pt_cup_teams
        PTEXT    pt_away
        PTEXT    pt_legs
        PTEXT    pt_extra
        PTEXT    pt_penalties
        PTEXT    pt_stages
        PTEXT    pt_chain
        PTEXT    pt_native_teams
        PTEXT    pt_through
        PTEXT    pt_final_early
        PTEXT    pt_final
        PTEXT    pt_knockout
        PTEXT    pt_groups
        PTEXT    pt_seeded
        PTEXT    pt_stage_repeat
        PTEXT    pt_stage_points
        PTEXT    pt_dates
        PTEXT    pt_unused_stage
        PTEXT    pt_reserved
        PTEXT    pt_team_count
        PTEXT    pt_team_entry
        PTEXT    pt_team_group
        PTEXT    pt_team_twice
        PTEXT    pt_tactic_mask
        PTEXT    pt_tactic
        PTEXT    pt_no_bench             ; DC_LAST+1
        PTEXT    pt_tournament_teams     ; DC_LAST+2

pt_none:                dc.b    0
pt_size:                dc.b    'THE FILE HAS THE WRONG SIZE FOR A DEFINITION.',0
pt_magic:               dc.b    'THE FILE IS NOT A TOURNAMENT DEFINITION.',0
pt_version:             dc.b    'THE DEFINITION FORMAT VERSION ',PT_D1,' IS NOT KNOWN.',0
pt_length:              dc.b    'THE LENGTH IN THE HEADER DOES NOT MATCH THE FILE.',0
pt_crc:                 dc.b    'THE CRC-32 DOES NOT MATCH THE CONTENT.',0
pt_body:                dc.b    'THE TEAM AND TACTIC COUNTS DO NOT FIT THE LENGTH.',0
pt_identity:            dc.b    'THE DATABASE IDENTITY IS NOT VALID.',0
pt_family:              dc.b    'THE COMPETITION TYPE ',PT_D1,' IS NOT KNOWN.',0
pt_name:                dc.b    'THE COMPETITION NAME IS NOT VALID.',0
pt_pitch:               dc.b    'THE PITCH SETTING IS NOT ONE THE GAME OFFERS.',0
pt_months:              dc.b    'THE SEASON MONTHS ARE NOT VALID.',0
pt_bench:               dc.b    'THE BENCH HOLDS 0-5 PLAYERS, NOT ',PT_D1,'.',0
pt_subs:                dc.b    'USE 1-',PT_D2,' OF THE ',PT_D2,' SUBSTITUTES, NOT ',PT_D1,'.',0
pt_no_bench:            dc.b    'WITHOUT A BENCH NO SUBSTITUTE CAN BE USED.',0
pt_teams:               dc.b    'A LEAGUE HAS 2-24 TEAMS, NOT ',PT_D2,'.',0
pt_tournament_teams:    dc.b    'A TOURNAMENT HAS 2-64 TEAMS, NOT ',PT_D2,'.',0
pt_repeat:              dc.b    'TEAMS MEET 1-10 TIMES, NOT ',PT_D1,'.',0
pt_points:              dc.b    'A WIN GIVES 2 OR 3 POINTS, NOT ',PT_D1,'.',0
pt_rounds:              dc.b    'A CUP HAS 1-6 ROUNDS, NOT ',PT_D1,'.',0
pt_cup_teams:           dc.b    'A CUP OF ',PT_D1,' ROUNDS HAS ',PT_POWER,' TEAMS, NOT ',PT_D2,'.',0
pt_away:                dc.b    'THE AWAY GOALS RULE IS NOT ONE THE GAME OFFERS.',0
pt_legs:                dc.b    PT_KIND,' ',PT_D2,' IS NOT PLAYED OVER 1 OR 2 LEGS.',0
pt_extra:               dc.b    PT_KIND,' ',PT_D2,' HAS AN UNKNOWN EXTRA TIME RULE.',0
pt_penalties:           dc.b    PT_KIND,' ',PT_D2,' HAS AN UNKNOWN PENALTY RULE.',0
pt_stages:              dc.b    'A TOURNAMENT HAS 1-6 STAGES, NOT ',PT_D1,'.',0
pt_chain:               dc.b    'STAGE ',PT_D1,' STARTS WITH ',PT_D2,' TEAMS, NOT ',PT_D3,'.',0
pt_native_teams:        dc.b    'THE GAME CANNOT START STAGE ',PT_D1,' WITH ',PT_D2,' TEAMS.',0
pt_through:             dc.b    'STAGE ',PT_D1,' SENDS ',PT_D2,' OF ITS ',PT_D3,' TEAMS ON.',0
pt_final_early:         dc.b    'STAGE ',PT_D1,' ALREADY LEAVES THE WINNER.',0
pt_final:               dc.b    'THE LAST STAGE SENDS ',PT_D1,' ON, NOT ONE WINNER.',0
pt_knockout:            dc.b    'STAGE ',PT_D1,' CANNOT BE A KNOCKOUT OF ',PT_D2,' TEAMS.',0
pt_groups:              dc.b    'STAGE ',PT_D1,' CANNOT HAVE ',PT_D2,' GROUPS OF ',PT_D3,' TEAMS.',0
pt_seeded:              dc.b    'STAGE ',PT_D1,' HAS AN UNKNOWN SEEDING VALUE.',0
pt_stage_repeat:        dc.b    'IN STAGE ',PT_D1,' TEAMS MEET 1-4 TIMES, NOT ',PT_D2,'.',0
pt_stage_points:        dc.b    'IN STAGE ',PT_D1,' A WIN GIVES 2 OR 3 POINTS, NOT ',PT_D2,'.',0
pt_dates:               dc.b    'STAGE ',PT_D1,' NEEDS ',PT_D2,' MATCH DATES, AT MOST 90 FIT.',0
pt_unused_stage:        dc.b    'STAGE ',PT_D1,' IS NOT PLAYED BUT HOLDS VALUES.',0
pt_reserved:            dc.b    'UNUSED BYTES OF THE DEFINITION ARE NOT ZERO.',0
pt_team_count:          dc.b    'THE TEAM LIST HAS ',PT_D1,' TEAMS, THE COMPETITION ',PT_D2,'.',0
pt_team_entry:          dc.b    'TEAM ',PT_D1,' OF THE LIST IS NOT VALID.',0
pt_team_group:          dc.b    'TEAM ',PT_D1,' COMES FROM AN UNKNOWN GROUP ',PT_D2,'.',0
pt_team_twice:          dc.b    'TEAM ',PT_D1,' OF THE LIST IS THERE TWICE.',0
pt_tactic_mask:         dc.b    'THE TACTIC SLOTS ARE NOT VALID.',0
pt_tactic:              dc.b    'THE TACTIC IN USER ',PT_LETTER,' IS NOT VALID:',0
text_round:             dc.b    'ROUND',0
text_stage:             dc.b    'STAGE',0

title_start:            dc.b    'START THE COMPETITION',0
text_listed:            dc.b    'THE DEFINITION LISTS ',0
text_listed_end:        dc.b    ' TEAMS.',0
start_lines:            dc.b    'YES STARTS WITH THEM,',0
                        dc.b    'NO CHOOSES THE TEAMS NOW.',0
                        dc.b    0
title_not_started:      dc.b    'COMPETITION NOT STARTED',0
line_change_rules:      dc.b    'CHANGE THE RULES ON THIS PAGE.',0
title_team_missing:     dc.b    'TEAM NOT FOUND',0
text_team:              dc.b    'TEAM ',0
text_of_list:           dc.b    ' OF THE LIST: ',0
line_not_in_database:   dc.b    'IS NOT IN THE DATABASE IN USE.',0
line_not_in_custom:     dc.b    'IS NOT IN THE EDITED CUSTOM TEAMS.',0
line_not_started:       dc.b    'THE COMPETITION WAS NOT STARTED.',0
        even
