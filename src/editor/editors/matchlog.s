; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The match log: every match the match engine plays to its end, in a
; friendly, a DIY or preset competition, a season or a career, with human
; or computer teams, is appended as one record to MATCHES.LOG in the save
; directory (layout in matchlog.i). Nothing the game keeps is changed.
;
;   matchlog_start        once, at the first main menu: MACHINE.CFG gives the
;                         install's identity and name, the log the next
;                         sequence number of this install
;   matchlog_match_end    replaces TST.W match_friendly at the end of every
;                         match the engine played (match_end_friendly_test):
;                         the result is recorded and appended, unless it was
;                         training or the match was abandoned without a
;                         result; each REPLAY of a friendly is its own match
;   matchlog_forfeit      replaces the first move of the forfeit's score
;                         (forfeit_score_site): the match is marked as left
;                         with Esc, the game's awarded result is recorded
;   matchlog_after        replaces the final TST.W match_abandoned of
;                         match_setup_wrapper, after the front end is back:
;                         one note when a match could not be appended
;
; Fixtures the game only simulates and the highlights never reach the
; match engine's frame loop, so they are never logged. A failed append
; never stops play; its sequence number is used up, so a gap in the
; sequence shows a match that is missing from the log (within a session:
; the next session numbers on from the highest number in the log). The next
; append goes after the log as it is then, so a record cut by a failed
; append does not stop the later ones.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"
        include "matchlog.i"

        xdef    matchlog_start, matchlog_match_end, matchlog_after
        xdef    matchlog_forfeit, matchlog_forfeit_patch
        xref    editor_base
        xref    crc32_buffer
        xref    storage_read, storage_read_part, storage_size, storage_write
        xref    storage_append, storage_time
        xref    message_title, message_line, message_lines, message_show
        xref    message_storage_reason
        xref    text_copy
        xref    db_manifest_in_use, db_identity_of, definition_custom_crc

HEADER_PEEK             equ MR_LENGTH+2 ; bytes needed to judge a record's start

        section .text,code

; ===========================================================================
; Start
; ===========================================================================
; matchlog_start: A5 = editor base. Once: reads MACHINE.CFG, notes the
; length of MATCHES.LOG and finds the highest sequence number of the
; install's records in it. Preserves all registers.
matchlog_start:
        movem.l d0-d7/a0-a4,-(sp)
        lea     WORK_MATCHLOG(a5),a4
        tst.w   ML_STATE(a4)
        bne.s   .done
        move.w  #1,ML_STATE(a4)
        moveq   #1,d0
        move.l  d0,ML_SEQUENCE(a4)
        bsr.w   machine_read
        bsr.w   log_scan                ; the log's length, the next number
.done:
        movem.l (sp)+,d0-d7/a0-a4
        rts

; machine_read: A4 = state. A sound MACHINE.CFG sets ML_INSTALL, ML_NAME and
; ML_MACHINE_OK; otherwise ML_INSTALL stays zero.
machine_read:
        lea     machine_name(pc),a0
        lea     ML_RECORD(a4),a1
        moveq   #MID_SIZE,d1
        bsr.l   storage_read
        bne.s   .done
        cmpi.l  #MID_SIZE,d1
        bne.s   .done
        lea     ML_RECORD(a4),a2
        cmpi.l  #MID_MAGIC_HIGH,MID_MAGIC(a2)
        bne.s   .done
        cmpi.l  #MID_MAGIC_LOW,MID_MAGIC+4(a2)
        bne.s   .done
        cmpi.w  #MID_VERSION_VALUE,MID_VERSION(a2)
        bne.s   .done
        tst.l   MID_INSTALL(a2)
        beq.s   .done
        movea.l a2,a0
        moveq   #MID_CRC32,d1
        bsr.l   crc32_buffer
        cmp.l   MID_CRC32(a2),d0
        bne.s   .done
        lea     MID_NAME(a2),a0
        bsr.w   name_valid
        bne.s   .done
        move.l  MID_INSTALL(a2),ML_INSTALL(a4)
        lea     MID_NAME(a2),a0
        lea     ML_NAME(a4),a1
        moveq   #MID_NAME_SIZE/4-1,d0
.name:
        move.l  (a0)+,(a1)+
        dbf     d0,.name
        move.w  #1,ML_MACHINE_OK(a4)
.done:
        rts

; name_valid: A0 = MID_NAME_SIZE bytes. Z set for 1-15 printable characters
; followed by NUL bytes only.
name_valid:
        movem.l d0-d1/a0,-(sp)
        moveq   #MID_NAME_SIZE-1,d1
        tst.b   (a0)
        beq.s   .bad
.char:
        move.b  (a0)+,d0
        beq.s   .padding
        cmpi.b  #' ',d0
        bcs.s   .bad
        cmpi.b  #'~',d0
        bhi.s   .bad
        dbf     d1,.char
        bra.s   .bad                    ; no NUL in the field
.padding:
        subq.w  #1,d1
        bmi.s   .good
.pad:
        tst.b   (a0)+
        bne.s   .bad
        dbf     d1,.pad
.good:
        moveq   #0,d0
        bra.s   .done
.bad:
        moveq   #1,d0
.done:
        movem.l (sp)+,d0-d1/a0
        rts

; log_scan: A4 = state. Notes the length of MATCHES.LOG in ML_LOG_LENGTH,
; reads it in pieces into the listing area and sets ML_SEQUENCE after the
; highest sequence number among the sound records of this install (none
; while ML_INSTALL is zero). A record is sound when its magic,
; length and CRC-32 agree; anything else is passed over byte by byte, so a
; damaged or cut record costs only itself.
;   D7 = file length, D6 = offset of the piece, D5 = bytes in it,
;   D4 = position in it, D3 = a record's length
log_scan:
        lea     log_name(pc),a0
        bsr.l   storage_size
        bne.w   .done                   ; no log yet
        move.l  d1,ML_LOG_LENGTH(a4)
        move.l  d1,d7
        moveq   #0,d6
.piece:
        move.l  d7,d1
        sub.l   d6,d1
        cmpi.l  #MR_MIN_SIZE,d1
        bcs.w   .done
        cmpi.l  #LIST_WORK_SIZE,d1
        bls.s   .read
        move.l  #LIST_WORK_SIZE,d1
.read:
        lea     log_name(pc),a0
        lea     LIST_WORK_OFFSET(a5),a1
        move.l  d6,d2
        bsr.l   storage_read_part
        bne.w   .done
        move.l  d1,d5
        moveq   #0,d4
.find:
        move.l  d5,d0
        sub.l   d4,d0
        cmpi.l  #HEADER_PEEK,d0
        bcs.s   .next
        lea     LIST_WORK_OFFSET(a5),a2
        adda.l  d4,a2
        cmpi.l  #MR_MAGIC_VALUE,MR_MAGIC(a2)
        bne.s   .skip
        moveq   #0,d3
        move.w  MR_LENGTH(a2),d3
        cmpi.l  #MR_MIN_SIZE,d3
        bcs.s   .skip
        cmpi.l  #MR_MAX_SIZE,d3
        bhi.s   .skip
        move.l  d4,d0
        add.l   d3,d0
        cmp.l   d5,d0
        bls.s   .whole
        add.l   d6,d0                   ; the record ends after this piece
        cmp.l   d7,d0
        bhi.s   .skip                   ; and after the file: cut
        bra.s   .next                   ; read on from its start
.whole:
        movea.l a2,a0
        move.l  d3,d1
        subq.l  #MR_CRC_SIZE,d1
        bsr.l   crc32_buffer
        cmp.l   -MR_CRC_SIZE(a2,d3.l),d0
        bne.s   .skip
        move.l  MR_INSTALL(a2),d0
        cmp.l   ML_INSTALL(a4),d0
        bne.s   .counted
        move.l  MR_SEQUENCE(a2),d0
        cmp.l   ML_SEQUENCE(a4),d0
        bcs.s   .counted
        addq.l  #1,d0
        move.l  d0,ML_SEQUENCE(a4)
.counted:
        add.l   d3,d4
        bra.w   .find
.skip:
        addq.l  #1,d4
        bra.w   .find
.next:
        tst.l   d4
        beq.s   .done
        add.l   d4,d6
        bra.w   .piece
.done:
        rts

; ===========================================================================
; The end of a match
; ===========================================================================
; matchlog_match_end: replaces TST.W match_friendly at
; match_end_friendly_test, reached once at the end of every match the
; engine played. Returns that test's flags; preserves all registers.
matchlog_match_end:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        lea     WORK_MATCHLOG(a5),a4
        tst.w   training_mode
        bne.s   .skip
        tst.w   match_abandoned
        bne.s   .skip
        bsr.w   matchlog_start          ; done at the first main menu
        bsr.w   record_build            ; D7 = length
        bsr.w   record_append
        move.l  d0,ML_LAST_RESULT(a4)
        beq.s   .skip
        move.w  #1,ML_NOTE(a4)
        move.l  d0,ML_NOTE_RESULT(a4)
.skip:
        clr.w   ML_FORFEIT(a4)
        movem.l (sp)+,d0-d7/a0-a6
        tst.w   match_friendly
        rts

; matchlog_forfeit: called by matchlog_forfeit_patch at forfeit_score_site.
; Marks the match as left with Esc, then does the replaced move. Preserves
; all registers.
matchlog_forfeit:
        move.l  a0,-(sp)
        movea.l editor_base,a0
        move.w  #1,WORK_MATCHLOG+ML_FORFEIT(a0)
        movea.l (sp)+,a0
        move.w  match_score,match_score_90
        rts

; The eight bytes written at forfeit_score_site (the address is relocated
; by the hook table).
matchlog_forfeit_patch:
        jsr     matchlog_forfeit
        nop

; matchlog_after: replaces TST.W match_abandoned at match_wrapper_return.
; After a failed append one note says that the match is not in the log and
; why; then the test the wrapper returns.
matchlog_after:
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        lea     WORK_MATCHLOG(a5),a4
        tst.w   ML_NOTE(a4)
        beq.s   .done
        clr.w   ML_NOTE(a4)
        bsr.w   note_show
.done:
        movem.l (sp)+,d0-d7/a0-a6
        tst.w   match_abandoned
        rts

; note_show: A4 = state. The note of a failed append.
note_show:
        lea     not_saved_title(pc),a0
        bsr.l   message_title
        lea     not_saved_line0(pc),a0
        moveq   #0,d0
        bsr.l   message_line
        lea     ML_TEXT(a4),a1
        lea     reason_prefix_line(pc),a0
        bsr.l   text_copy
        move.l  ML_NOTE_RESULT(a4),d0
        moveq   #1,d1                   ; a write
        bsr.l   message_storage_reason  ; A0 = reason
        bsr.l   text_copy
        move.b  #'.',(a1)+
        clr.b   (a1)
        lea     ML_TEXT(a4),a0
        moveq   #1,d0
        bsr.l   message_line
        lea     go_on_lines(pc),a0
        moveq   #2,d0
        bsr.l   message_lines
        bra.l   message_show

; ===========================================================================
; The record
; ===========================================================================
; record_build: A4 = state, A5 = editor base. Builds the record of the
; match that just ended at ML_RECORD, apart from the install, sequence
; number, machine name and CRC-32 (record_append). D7.l = its length.
record_build:
        lea     ML_RECORD(a4),a3
        movea.l a3,a0
        moveq   #MR_HEADER_SIZE/4-1,d0
.clear:
        clr.l   (a0)+
        dbf     d0,.clear
        move.l  #MR_MAGIC_VALUE,MR_MAGIC(a3)
        move.w  #MR_VERSION_VALUE,MR_VERSION(a3)
        lea     MR_TIME(a3),a1
        bsr.l   storage_time            ; zeros when the machine has no date
        move.w  competition_family,MR_FAMILY(a3)
        moveq   #0,d0
        tst.w   match_extra_time
        bpl.s   .penalties
        bset    #MRF_EXTRA_TIME,d0
.penalties:
        tst.w   match_penalties
        bpl.s   .leg
        bset    #MRF_PENALTIES,d0
.leg:
        tst.w   match_second_leg
        beq.s   .forfeit
        bset    #MRF_SECOND_LEG,d0
.forfeit:
        tst.w   ML_FORFEIT(a4)
        beq.s   .flags
        bset    #MRF_FORFEIT,d0
.flags:
        move.w  d0,MR_FLAGS(a3)
        lea     MR_IDENTITY(a3),a1
        bsr.w   identity_fill
        lea     match_competition_name,a0
        lea     MR_COMPETITION(a3),a1
        moveq   #MATCH_NAME_SIZE-1,d0
        bsr.w   text_field
        lea     match_round_name,a0
        lea     MR_ROUND(a3),a1
        moveq   #MATCH_NAME_SIZE-1,d0
        bsr.w   text_field
        moveq   #0,d6
        bsr.w   team_fill
        moveq   #1,d6
        bsr.w   team_fill
        lea     MR_HEADER_SIZE(a3),a2   ; scorers
        moveq   #0,d6
        bsr.w   scorers_fill
        moveq   #1,d6
        bsr.w   scorers_fill
        bsr.w   goals_fill              ; A2 = end of the goals
        ; goals without an entry (beyond the game's lists, or awarded)
        moveq   #0,d0
        move.b  MR_TEAMS+MT_GOALS(a3),d0
        moveq   #0,d1
        move.b  MR_TEAMS+MT_SIZE+MT_GOALS(a3),d1
        add.w   d1,d0
        moveq   #0,d1
        move.b  MR_GOAL_COUNT(a3),d1
        cmp.w   d0,d1
        bcc.s   .complete
        bset    #MRF_MINUTES_PARTIAL,MR_FLAGS+1(a3)
.complete:
        move.l  a2,d7
        sub.l   a3,d7
        addq.l  #MR_CRC_SIZE,d7
        rts

; identity_fill: A1 = MR_IDENTITY (zero). The database the match's teams
; came from (the one bound to the competition, or the switch's set for a
; friendly), as the identity of a tournament definition, and the custom
; set's CRC-32 while it is known.
identity_fill:
        bsr.l   db_manifest_in_use      ; A0 = manifest, or Z set
        beq.s   .custom
        bsr.l   db_identity_of
.custom:
        bra.l   definition_custom_crc

; text_field: A0 = text, A1 = zeroed field, D0.w = most characters.
text_field:
        subq.w  #1,d0
        bmi.s   .done
.char:
        move.b  (a0)+,(a1)+
        dbeq    d0,.char
.done:
        rts

; team_fill: D6.w = side (0 home, 1 away), A3 = record. The team's key,
; source, control, name and goals.
team_fill:
        bsr.w   side_pointers           ; A0 = team record, A1 = match team
        lea     MR_TEAMS(a3),a2
        move.w  d6,d0
        lsl.w   #5,d0                   ; MT_SIZE
        adda.w  d0,a2
        move.b  TEAM_KEY(a0),MT_GROUP(a2)
        move.b  TEAM_KEY+1(a0),MT_ORDINAL(a2)
        cmpi.b  #CUSTOM_KEY_GROUP,MT_GROUP(a2)
        bne.s   .control
        move.b  #MTS_CUSTOM_SET,MT_SOURCE(a2)
.control:
        move.b  TEAM_CONTROL(a0),MT_CONTROL(a2)
        movea.l a1,a0
        lea     MATCH_TEAM_NAME(a0),a0
        lea     MT_NAME(a2),a1
        moveq   #TEAM_NAME_SIZE-1,d0
        bsr.s   text_field
        move.w  d6,d1
        add.w   d1,d1                   ; word of the side
        lea     match_score_90,a0
        move.b  1(a0,d1.w),MT_GOALS_90(a2)
        lea     match_score,a0
        move.b  1(a0,d1.w),MT_GOALS(a2)
        tst.w   match_penalties
        bpl.s   .own
        lea     match_penalty_score,a0
        move.b  1(a0,d1.w),MT_PENALTIES(a2)
.own:
        bsr.w   side_pointers
        move.b  MATCH_TEAM_OWN_GOALS(a1),MT_OWN_GOALS(a2)
        tst.w   match_second_leg
        beq.s   .done
        lea     match_earlier_goals,a0
        move.b  1(a0,d1.w),MT_EARLIER(a2)
.done:
        rts

; side_pointers: D6.w = side. A0 = its team record, A1 = its match team.
side_pointers:
        move.w  d6,d0
        lsl.w   #2,d0
        lea     match_team_records,a0
        movea.l (a0,d0.w),a0
        lea     match_team_home,a1
        tst.w   d6
        beq.s   .done
        lea     match_team_away,a1
.done:
        rts

; scorers_fill: D6.w = side, A3 = record, A2 = next scorer entry (advanced).
; One entry per match player of the side with goals: his goals as the game
; writes them back, his slot and shirt, and his name from the team record
; when the record's player in that slot wears the same shirt, else the
; game's short form.
scorers_fill:
        bsr.s   side_pointers           ; A0 = team record, A1 = match team
        movea.l a0,a6
        moveq   #0,d5                   ; match player
.player:
        move.w  d5,d0
        mulu.w  #MATCH_PLAYER_SIZE,d0
        lea     (a1,d0.l),a0            ; biased match player
        move.b  MATCH_PLAYER_GOALS(a0),d1
        beq.w   .next
        cmpi.b  #SCORERS_MAX,MR_PLAYER_COUNT(a3)
        bcc.w   .next
        addq.b  #1,MR_PLAYER_COUNT(a3)
        movea.l a2,a5                   ; clear the entry
        moveq   #MS_SIZE/4-1,d0
.clear:
        clr.l   (a5)+
        dbf     d0,.clear
        move.b  d6,MS_SIDE(a2)
        move.b  d5,MS_INDEX(a2)
        move.b  MATCH_PLAYER_SLOT(a0),MS_SLOT(a2)
        move.b  MATCH_PLAYER_SHIRT(a0),MS_SHIRT(a2)
        move.b  d1,MS_GOALS(a2)
        move.w  d6,d0
        lsl.w   #5,d0
        addq.b  #1,MR_TEAMS+MT_SCORERS(a3,d0.w)
        ; the record's player in that slot
        moveq   #0,d0
        move.b  MATCH_PLAYER_SLOT(a0),d0
        cmpi.w  #PLAYER_COUNT,d0
        bcc.s   .short
        mulu.w  #PLAYER_SIZE,d0
        lea     TEAM_PLAYERS(a6,d0.l),a5
        move.b  PLAYER_SHIRT(a5),d0
        cmp.b   MATCH_PLAYER_SHIRT(a0),d0
        bne.s   .short
        tst.b   PLAYER_NAME(a5)
        beq.s   .short
        move.l  a0,-(sp)
        lea     PLAYER_NAME(a5),a0
        lea     MS_NAME(a2),a5
        exg     a1,a5
        moveq   #MS_NAME_SIZE-1,d0
        bsr.w   text_field
        exg     a1,a5
        movea.l (sp)+,a0
        bra.s   .entered
.short:
        move.l  a1,-(sp)
        lea     MATCH_PLAYER_SHORT_NAME(a0),a0
        lea     MS_NAME(a2),a1
        moveq   #14,d0
        bsr.w   text_field
        movea.l (sp)+,a1
        bset    #MSF_SHORT_NAME,MS_FLAGS(a2)
.entered:
        lea     MS_SIZE(a2),a2
.next:
        addq.w  #1,d5
        cmpi.w  #MATCH_PLAYERS,d5
        bne.w   .player
        movea.l editor_base,a5
        rts

; goals_fill: A3 = record, A2 = first goal entry (advanced to the end of
; the goals). One entry per goal of the game's scorer lists, home list
; first, each in the list's order: the side credited, the kind, the
; scorer's shirt, the minute and the scorer entry of a goal that is not an
; own goal.
goals_fill:
        moveq   #0,d6                   ; side
.side:
        lea     match_scorer_lists,a1
        move.w  d6,d0
        mulu.w  #SCORER_LIST_SIZE,d0
        adda.l  d0,a1
        moveq   #SCORER_ENTRIES-1,d5
.entry:
        move.w  SE_KEY(a1),d4           ; shirt, or shirt + 100
        beq.w   .listed
        move.w  SE_GOALS(a1),d3
        cmpi.w  #SCORER_GOALS_MAX,d3
        bls.s   .count
        moveq   #SCORER_GOALS_MAX,d3
.count:
        lea     SE_GOAL(a1),a0
        bra.s   .goal_test
.goal:
        cmpi.b  #GOALS_MAX,MR_GOAL_COUNT(a3)
        bcc.s   .goal_next
        addq.b  #1,MR_GOAL_COUNT(a3)
        move.w  (a0),d0                 ; kind
        andi.w  #3,d0
        lsl.w   #MGK_SHIFT,d0
        or.w    d6,d0
        move.b  d0,MG_SIDE(a2)
        move.b  #MG_NO_SCORER,MG_SCORER(a2)
        move.w  d4,d0
        cmpi.w  #SCORER_OWN_GOAL_KEY,d0
        bcs.s   .scorer
        subi.w  #SCORER_OWN_GOAL_KEY,d0
        move.b  d0,MG_SHIRT(a2)
        bra.s   .minute
.scorer:
        move.b  d0,MG_SHIRT(a2)
        bsr.s   scorer_index            ; D0.b = entry or MG_NO_SCORER
        move.b  d0,MG_SCORER(a2)
.minute:
        bsr.s   goal_minute             ; D0.b
        move.b  d0,MG_MINUTE(a2)
        addq.l  #MG_SIZE,a2
.goal_next:
        lea     SCORER_GOAL_SIZE(a0),a0
.goal_test:
        dbf     d3,.goal
        lea     SCORER_ENTRY_SIZE(a1),a1
        dbf     d5,.entry
.listed:
        addq.w  #1,d6
        cmpi.w  #2,d6
        bne.w   .side
        rts

; scorer_index: D6.w = side, MG_SHIRT(A2) = shirt, A3 = record. D0.b = the
; scorer entry of that side with that shirt, or MG_NO_SCORER.
scorer_index:
        movem.l d1-d2/a0,-(sp)
        lea     MR_HEADER_SIZE(a3),a0
        moveq   #0,d2
        move.b  MR_PLAYER_COUNT(a3),d2
        moveq   #0,d0
.entry:
        cmp.w   d2,d0
        bcc.s   .none
        cmp.b   MS_SIDE(a0),d6
        bne.s   .next
        move.b  MS_SHIRT(a0),d1
        cmp.b   MG_SHIRT(a2),d1
        beq.s   .done
.next:
        lea     MS_SIZE(a0),a0
        addq.w  #1,d0
        bra.s   .entry
.none:
        move.w  #MG_NO_SCORER,d0
.done:
        movem.l (sp)+,d1-d2/a0
        rts

; goal_minute: A0 = a goal of a scorer list. D0.b = its minute from the three
; digits after the first byte, or MG_NO_MINUTE.
goal_minute:
        movem.l d1-d2/a0,-(sp)
        moveq   #0,d0
        moveq   #2,d2
        lea     3(a0),a0
.digit:
        moveq   #0,d1
        move.b  (a0)+,d1
        subi.b  #'0',d1
        cmpi.b  #9,d1
        bhi.s   .unknown
        mulu.w  #10,d0
        add.w   d1,d0
        dbf     d2,.digit
        cmpi.w  #MG_NO_MINUTE,d0
        bcs.s   .done
.unknown:
        move.w  #MG_NO_MINUTE,d0
.done:
        movem.l (sp)+,d1-d2/a0
        rts

; ===========================================================================
; Appending
; ===========================================================================
; record_append: A4 = state, A5 = editor base, D7.l = length of the record
; at ML_RECORD. Gives it the install, the next sequence number, the machine
; name and the CRC-32, and appends it to MATCHES.LOG. D0.l = 0 or the
; result of the append. The sequence number is used up either way.
record_append:
        tst.l   ML_INSTALL(a4)
        bne.s   .known
        bsr.w   machine_create
.known:
        tst.w   ML_MACHINE_OK(a4)
        bne.s   .identity
        bsr.w   machine_write           ; written once it succeeds
.identity:
        lea     ML_RECORD(a4),a3
        move.w  d7,MR_LENGTH(a3)
        move.l  ML_INSTALL(a4),MR_INSTALL(a3)
        move.l  ML_SEQUENCE(a4),MR_SEQUENCE(a3)
        addq.l  #1,ML_SEQUENCE(a4)
        lea     ML_NAME(a4),a0
        lea     MR_MACHINE(a3),a1
        moveq   #MID_NAME_SIZE/4-1,d0
.name:
        move.l  (a0)+,(a1)+
        dbf     d0,.name
        movea.l a3,a0
        move.l  d7,d1
        subq.l  #MR_CRC_SIZE,d1
        bsr.l   crc32_buffer
        move.l  d0,-MR_CRC_SIZE(a3,d7.l)
        lea     log_name(pc),a0
        movea.l a3,a1
        move.l  d7,d1
        move.l  ML_LOG_LENGTH(a4),d2
        bsr.l   storage_append          ; D1 = offset
        bne.s   .failed
        addq.l  #1,ML_APPENDS(a4)
        add.l   d7,d1
        move.l  d1,ML_LOG_LENGTH(a4)
        moveq   #0,d0
        rts
.failed:
        ; a failed append may have left part of the record: the next one
        ; goes after the log as it is now (the scan skips a cut record)
        move.l  d0,-(sp)
        lea     log_name(pc),a0
        bsr.l   storage_size
        bne.s   .done
        move.l  d1,ML_LOG_LENGTH(a4)
.done:
        move.l  (sp)+,d0
        rts

; machine_create: A4 = state. A new install identity when MACHINE.CFG is
; missing or damaged: a CRC-32 of the beam position, the CIA timers and
; time-of-day counters and the date (if the machine has one), never zero;
; the default machine name.
machine_create:
        lea     WORK_IO_BUFFER(a5),a1
        move.l  $DFF004,(a1)            ; VPOSR, VHPOSR
        move.b  $BFE401,4(a1)           ; CIA-A timer A
        move.b  $BFE501,5(a1)
        move.b  $BFE801,6(a1)           ; CIA-A time of day
        move.b  $BFE901,7(a1)
        move.b  $BFD400,8(a1)           ; CIA-B timer A
        move.b  $BFD500,9(a1)
        move.b  $BFD800,10(a1)          ; CIA-B time of day (horizontal lines)
        move.b  $BFD900,11(a1)
        lea     12(a1),a1
        bsr.l   storage_time
        move.l  $DFF004,8(a1)
        lea     WORK_IO_BUFFER(a5),a0
        moveq   #24,d1
        bsr.l   crc32_buffer
        bne.s   .identity
        moveq   #1,d0
.identity:
        move.l  d0,ML_INSTALL(a4)
        lea     ML_NAME(a4),a1
        moveq   #MID_NAME_SIZE/4-1,d0
.clear:
        clr.l   (a1)+
        dbf     d0,.clear
        lea     default_machine(pc),a0
        lea     ML_NAME(a4),a1
        bsr.l   text_copy
        clr.w   ML_MACHINE_OK(a4)
        rts

; machine_write: A4 = state. Writes MACHINE.CFG with the identity and name
; in use; ML_MACHINE_OK once it is written and verified.
machine_write:
        lea     WORK_IO_BUFFER(a5),a1
        move.l  #MID_MAGIC_HIGH,MID_MAGIC(a1)
        move.l  #MID_MAGIC_LOW,MID_MAGIC+4(a1)
        move.w  #MID_VERSION_VALUE,MID_VERSION(a1)
        clr.w   MID_RESERVED(a1)
        move.l  ML_INSTALL(a4),MID_INSTALL(a1)
        lea     ML_NAME(a4),a0
        lea     MID_NAME(a1),a2
        moveq   #MID_NAME_SIZE/4-1,d0
.name:
        move.l  (a0)+,(a2)+
        dbf     d0,.name
        movea.l a1,a0
        moveq   #MID_CRC32,d1
        bsr.l   crc32_buffer
        move.l  d0,MID_CRC32(a1)
        lea     machine_name(pc),a0
        moveq   #MID_SIZE,d1
        bsr.l   storage_write
        bne.s   .done
        move.w  #1,ML_MACHINE_OK(a4)
.done:
        rts

log_name:               LOG_FILE_NAME
machine_name:           MACHINE_FILE_NAME
default_machine:        dc.b    'AMIGA',0
not_saved_title:        dc.b    'MATCH NOT SAVED IN THE LOG',0
not_saved_line0:        dc.b    'THIS MATCH COULD NOT BE ADDED TO MATCHES.LOG',0
reason_prefix_line:     dc.b    'IN THE DIRECTORY DATA: ',0
go_on_lines:            dc.b    'THE GAME GOES ON AS USUAL, AND LATER MATCHES',0
                        dc.b    'ARE LOGGED AGAIN ONCE DATA TAKES THEM.',0
                        dc.b    0
        even
