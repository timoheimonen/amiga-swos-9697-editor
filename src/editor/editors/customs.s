; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The custom set CUSTOMS.EDT in the save directory. Runtime hooks replace
; four calls of the native custom-team flow:
;
;   storage_volume_ready the save-disk requests before loading and saving
;                        the set (custom_load_request_call,
;                        custom_save_request_call): the save directory is
;                        always present, so it is selected without a prompt
;                        (resident/storage.s)
;   customs_load         the read of CUSTOMS.EDT (custom_load_call): the
;                        length is queried first, then the native read; a
;                        file that is not a whole set of CUSTOM_SET_TEAMS
;                        teams (cut, or changed outside the editors) is
;                        refused with a message and the game's read error,
;                        so no team of it is used (a longer file is not
;                        read at all); the message says whether CUSTOMS.BAK
;                        holds a whole set; otherwise the CRC-32 of the set
;                        as loaded
;   customs_save_prompt  the SAVE/ABORT prompt (custom_save_prompt_call):
;                        after ABORT a message says the file is unchanged,
;                        or that a failed save may have damaged it
;   customs_save         the write of the set (custom_save_write_call): a
;                        verified CUSTOMS.BAK of the previous file first (only
;                        of a whole set: a damaged CUSTOMS.EDT leaves the
;                        backup as it is), then
;                        CUSTOMS.EDT read back and compared (storage_replace,
;                        resident/storage.s); on success the
;                        CRC-32 of the saved set; on a failure the native
;                        error message and prompt follow, the set stays in
;                        RAM, and when CUSTOMS.EDT failed after its backup
;                        the editor offers to restore it from CUSTOMS.BAK
;
;   customs_check        whether CUSTOMS.EDT is a whole custom set, for the
;                        editors that use its teams without loading it
;                        through the team browser (editors/definition.s)
;
; The gateway records the CRC-32 of the original custom teams (group 72)
; through customs_record_crc. The previous content is held in the group work
; area of the expansion memory, which is free while the team editor runs.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    customs_load, customs_save_prompt
        xdef    customs_save, customs_record_crc, customs_check
        xref    editor_base
        xref    crc32_buffer
        xref    storage_size, storage_read_part, storage_write, storage_replace
        xref    storage_native_result
        xref    message_title, message_line, message_lines, message_note
        xref    message_show, message_ask, message_storage_reason

        section .text,code

; ---------------------------------------------------------------------------
; customs_load: replaces JSR file_load_unpack for CUSTOMS.EDT (A0 = name,
; A1 = team_group_buffer). Same return contract: D0.w = 0 with Z set and
; D1 = length, or the native error with Z clear. A set of another length or
; team count than the game's own is refused: the message, then the native
; read error, as for a file the game cannot read.
; ---------------------------------------------------------------------------
customs_load:
        movem.l d1/a0,-(sp)
        lea     edt_name(pc),a0
        bsr.l   storage_size            ; D1 = length
        bne.s   .read                   ; the native read reports it
        cmpi.l  #CUSTOM_SET_SIZE,d1
        beq.s   .read
        movem.l (sp)+,d1/a0
        bra.s   .damaged                ; not read: it may not fit the buffer
.read:
        movem.l (sp)+,d1/a0
        jsr     file_load_unpack
        tst.w   d0
        bne.s   .done
        cmpi.l  #CUSTOM_SET_SIZE,d1
        bne.s   .damaged
        cmpi.w  #CUSTOM_SET_TEAMS,team_group_buffer
        bne.s   .damaged
        move.l  a0,-(sp)
        lea     team_group_buffer,a0
        bsr.w   customs_record_crc
        movea.l (sp)+,a0
        tst.w   d0
.done:
        rts
.damaged:
        movem.l d0-d7/a0-a6,-(sp)
        lea     not_loaded_title(pc),a0
        lea     not_loaded_lines(pc),a1
        bsr.l   message_title
        movea.l a1,a0
        moveq   #0,d0
        bsr.l   message_lines
        bsr.w   backup_line             ; A0 = what CUSTOMS.BAK holds
        moveq   #2,d0
        bsr.l   message_line
        bsr.l   message_show
        movem.l (sp)+,d0-d7/a0-a6
        moveq   #FSE_READ_ERROR,d0
        rts

; ---------------------------------------------------------------------------
; customs_check: D0.l = 0 (Z set) when CUSTOMS.EDT in the save directory is
; a whole custom set: CUSTOM_SET_SIZE bytes that start with the count
; CUSTOM_SET_TEAMS. Otherwise STE_NOT_FOUND when there is none (or it is
; empty), or CUSTOMS_DAMAGED. Preserves D1-D7/A0-A6.
; ---------------------------------------------------------------------------
CUSTOMS_DAMAGED         equ 1

customs_check:
        move.l  a0,-(sp)
        lea     edt_name(pc),a0
        bsr.s   whole_set
        movea.l (sp)+,a0                ; MOVEA keeps the flags
        rts

; whole_set: A0 = name. As customs_check for that file. Preserves
; D1-D7/A0-A6.
whole_set:
        movem.l d1-d2/a1,-(sp)
        bsr.l   storage_size            ; D1 = length
        beq.s   .length
        cmpi.l  #STE_NOT_FOUND,d0
        beq.s   .done
        bra.s   .damaged
.length:
        cmpi.l  #CUSTOM_SET_SIZE,d1
        bne.s   .damaged
        clr.w   -(sp)
        movea.l sp,a1
        moveq   #2,d1
        moveq   #0,d2
        bsr.l   storage_read_part       ; the count word
        move.w  (sp)+,d1
        tst.l   d0
        bne.s   .damaged
        cmpi.w  #CUSTOM_SET_TEAMS,d1
        beq.s   .done                   ; D0 = 0
.damaged:
        moveq   #CUSTOMS_DAMAGED,d0
.done:
        movem.l (sp)+,d1-d2/a1
        tst.l   d0
        rts

; backup_line: A0 = the line that says whether CUSTOMS.BAK holds a whole
; set. Preserves D0-D7/A1-A6.
backup_line:
        move.l  d0,-(sp)
        lea     bak_name(pc),a0
        bsr.s   whole_set
        lea     bak_whole_line(pc),a0
        beq.s   .done
        lea     bak_none_line(pc),a0
.done:
        move.l  (sp)+,d0
        rts

; ---------------------------------------------------------------------------
; customs_record_crc: A0 = custom set as read, D1.l = its length. Records
; its CRC-32 as the set's fingerprint. Preserves all registers.
; ---------------------------------------------------------------------------
customs_record_crc:
        movem.l d0-d2/a0/a5,-(sp)
        movea.l editor_base,a5
        bsr.l   crc32_buffer
        move.l  d0,WORK_TEAM+TE_SET_CRC(a5)
        move.w  #1,WORK_TEAM+TE_SET_KNOWN(a5)
        movem.l (sp)+,d0-d2/a0/a5
        rts

; ---------------------------------------------------------------------------
; customs_save_prompt: replaces JSR frontend_prompt for CUSTOM TEAMS HAVE
; BEEN CHANGED (SAVE/ABORT). Returns its D0.w and flags.
; ---------------------------------------------------------------------------
customs_save_prompt:
        jsr     frontend_prompt
        tst.w   d0
        beq.s   .done                   ; SAVE
        movem.l d0-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        lea     not_saved_title(pc),a0
        bsr.l   message_title
        lea     unchanged_line(pc),a0
        moveq   #0,d0
        tst.w   WORK_TEAM+TE_SAVE_FAILED(a5)
        beq.s   .first
        clr.w   WORK_TEAM+TE_SAVE_FAILED(a5) ; a failed save wrote CUSTOMS.EDT
        lea     may_be_damaged_line(pc),a0
        bsr.l   message_line
        bsr.s   backup_line
        moveq   #1,d0
.first:
        bsr.l   message_line
        addq.w  #1,d0
        lea     in_memory_lines(pc),a0
        bsr.l   message_lines
        bsr.l   message_show
        movem.l (sp)+,d0-d7/a0-a6
        tst.w   d0
.done:
        rts

; ---------------------------------------------------------------------------
; customs_save: replaces JSR file_save_buffer for CUSTOMS.EDT.
;   in:  A0 = name, A1 = the counted set, D1.l = its length
;   out: D0.w = 0 with Z set when CUSTOMS.EDT is written and verified, else a
;        native file result (Z clear) for file_error_message
; ---------------------------------------------------------------------------
customs_save:
        movem.l d1-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        movea.l a1,a2                   ; the set
        move.l  d1,d5                   ; its length
        lea     edt_name(pc),a0
        lea     bak_name(pc),a3
        lea     GROUP_WORK_OFFSET(a5),a4 ; the old file, bounded to the work area
        move.l  #GROUP_WORK_AREA,d3
        moveq   #-1,d6                  ; only a whole set is backed up
        bsr.w   customs_check
        bne.s   .replace
        move.l  #CUSTOM_SET_SIZE,d6
.replace:
        bsr.l   storage_replace
        bne.s   .failed
        clr.w   WORK_TEAM+TE_SAVE_FAILED(a5)
        movea.l a2,a0
        move.l  d5,d1
        bsr.w   customs_record_crc
        moveq   #0,d0
        bra.s   .return
.failed:
        tst.l   d1
        bne.s   .final                  ; CUSTOMS.EDT failed after its backup
        tst.l   d6
        bpl.s   .report                 ; the backup step failed: nothing replaced
        move.w  #1,WORK_TEAM+TE_SAVE_FAILED(a5) ; no whole set before: the write may have changed it
        bra.s   .report
.final:
        bsr.s   offer_restore
.report:
        bsr.l   storage_native_result
.return:
        movem.l (sp)+,d1-d7/a0-a6
        tst.w   d0
        rts

; offer_restore: CUSTOMS.EDT failed after a verified backup; D0.l = result,
; D1.l = length of the previous file, still in the group work area (A4),
; A5 = editor base. TE_SAVE_FAILED stays set unless CUSTOMS.EDT is restored.
; Preserves D0.
offer_restore:
        move.l  d0,d7
        move.l  d1,d4
        move.w  #1,WORK_TEAM+TE_SAVE_FAILED(a5)
        lea     not_saved_title(pc),a0
        bsr.l   message_title
        moveq   #1,d1
        bsr.l   message_storage_reason
        moveq   #0,d0
        bsr.l   message_line
        lea     restore_lines(pc),a0
        moveq   #1,d0
        bsr.l   message_lines
        bsr.l   message_ask
        tst.l   d0
        beq.s   .done
        lea     edt_name(pc),a0
        movea.l a4,a1
        move.l  d4,d1
        bsr.l   storage_write
        move.l  d0,d1
        lea     not_saved_title(pc),a0
        bsr.l   message_title
        lea     not_restored_line(pc),a0
        tst.l   d1
        bne.s   .result
        clr.w   WORK_TEAM+TE_SAVE_FAILED(a5) ; CUSTOMS.EDT is the previous set again
        lea     restored_line(pc),a0
.result:
        moveq   #0,d0
        bsr.l   message_line
        bsr.l   message_show
.done:
        move.l  d7,d0
        rts

edt_name:               dc.b    'CUSTOMS.EDT',0
bak_name:               dc.b    'CUSTOMS.BAK',0
not_loaded_title:       dc.b    'CUSTOM TEAMS NOT LOADED',0
not_loaded_lines:       dc.b    'CUSTOMS.EDT IS DAMAGED: NOT A WHOLE CUSTOM SET.',0
                        dc.b    'THE ORIGINAL CUSTOM TEAMS STILL WORK.',0
                        dc.b    0
bak_whole_line:         dc.b    'CUSTOMS.BAK HOLDS THE SET OF THE SAVE BEFORE.',0
bak_none_line:          dc.b    'CUSTOMS.BAK HOLDS NO WHOLE SET EITHER.',0
not_saved_title:        dc.b    'CUSTOM TEAMS NOT SAVED',0
unchanged_line:         dc.b    'CUSTOMS.EDT IS UNCHANGED.',0
in_memory_lines:        dc.b    'THE CHANGES STAY IN MEMORY ONLY UNTIL',0
                        dc.b    'THE NEXT TEAM LIST IS LOADED.',0
                        dc.b    0
may_be_damaged_line:    dc.b    'THE FAILED SAVE MAY HAVE DAMAGED CUSTOMS.EDT.',0
restore_lines:          dc.b    'THE PREVIOUS SET IS SAFE IN CUSTOMS.BAK.',0
                        dc.b    'RESTORE CUSTOMS.EDT FROM IT NOW?',0
                        dc.b    0
restored_line:          dc.b    'CUSTOMS.EDT RESTORED FROM CUSTOMS.BAK.',0
not_restored_line:      dc.b    'RESTORE FAILED. CUSTOMS.BAK IS UNCHANGED.',0
        even
