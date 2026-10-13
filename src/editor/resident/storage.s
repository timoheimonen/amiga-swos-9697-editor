; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Storage in the save directory data/ of the install, through the WHDLoad
; slave's file service (slave.i). The slave keeps the rules that need the
; directory itself: names of 1-29 characters with a dot, reads that never
; pass the caller's capacity, writes read back and compared before success,
; admission of new names (SAVE_DIR_MAX_NAMES names, NATIVE_SAVES_MAX
; recognized saves), audio silenced and keys released around every
; operation. This module adds the sequences the editors build on:
;   - a listing always has an explicit capacity, so a directory with more
;     names than the buffer holds is counted without overrun;
;   - storage_replace keeps the previous content as a verified backup
;     before the new content is written (DBASE.CFG/DBASE.BAK,
;     CUSTOMS.EDT/CUSTOMS.BAK);
;   - storage_delete removes a file only when an editor asks for it.
;
; All routines run in the front end's own context (a menu action or an
; editor screen), never during a native file operation. Registers D2-D7 and
; A0-A6 are preserved unless stated. Results: 0, a native disk result or a
; STE_* refusal (slave.i).

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    storage_list
        xdef    storage_size
        xdef    storage_read
        xdef    storage_read_part
        xdef    storage_write
        xdef    storage_delete
        xdef    storage_append
        xdef    storage_time
        xdef    storage_replace
        xdef    storage_volume_ready
        xdef    storage_native_result

        section .text,code

; ---------------------------------------------------------------------------
; storage_list: list the save directory.
;   in:  A1 = records (FS_RECORD_SIZE bytes each), D1.l = capacity in records
;   out: D0.l = 0 or a result, D1.l = names in the directory (at most the
;        capacity were stored), D2.l = recognized native saves among them
; ---------------------------------------------------------------------------
storage_list:
        moveq   #SVC_LIST,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_size: A0 = name. D0.l = 0 and D1.l = length, or a result.
; ---------------------------------------------------------------------------
storage_size:
        moveq   #SVC_SIZE,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_read: read a whole file, never more than the capacity.
;   in:  A0 = name, A1 = destination, D1.l = capacity
;   out: D0.l = 0 and D1.l = length; STE_TOO_LARGE with D1.l = length and
;        nothing read; or another result
; ---------------------------------------------------------------------------
storage_read:
        moveq   #SVC_READ,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_read_part: read D1.l bytes from offset D2.l of file A0 to A1.
;   out: D0.l = 0 and D1.l = bytes read (fewer at the end), or a result
; ---------------------------------------------------------------------------
storage_read_part:
        moveq   #SVC_READ_PART,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_write: write a file, read it back and compare it.
;   in:  A0 = name, A1 = source, D1.l = length (not 0)
;   out: D0.l = 0, or a result; on any result the caller's source is intact
; An existing name is replaced; callers that need the old content write a
; backup first (storage_replace).
; ---------------------------------------------------------------------------
storage_write:
        moveq   #SVC_WRITE,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_delete: A0 = name. D0.l = 0, or a result (STE_NOT_FOUND when the
; file does not exist). Only the editors' own files are deleted, and only
; where an editor says so.
; ---------------------------------------------------------------------------
storage_delete:
        moveq   #SVC_DELETE,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_append: add bytes at the end of a file, creating it when missing.
;   in:  A0 = name, A1 = source, D1.l = length (not 0), D2.l = the file's
;        length as the caller knows it (0 when there is no file yet)
;   out: D0.l = 0 and D1.l = the offset at which they were added (D2), or a
;        result (STE_CHANGED: the file has another length); the file's
;        earlier bytes are never written
; ---------------------------------------------------------------------------
storage_append:
        moveq   #SVC_APPEND,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_time: A1 = 8 bytes for the date and time (year word, month, day,
; hour, minute, second, zero). D0.l = 0, or STE_NO_TIME with zeros when the
; machine has no date.
; ---------------------------------------------------------------------------
storage_time:
        moveq   #SVC_TIME,d0
        jmp     slave_service

; ---------------------------------------------------------------------------
; storage_replace: replace a file, keeping its previous content as a
; verified backup first.
;   in:  A0 = name, A3 = backup name, A1 = new content, D1.l = length,
;        A4 = buffer for the old content, D3.l = its capacity, D6.l = the
;        length of a usable previous file, 0 for any length (-1: none is)
;   out: D0.l = 0 when the new content is written and verified; otherwise a
;        result with D1.l = 0 when no backup was written for this call (the
;        backup step failed, or there was no usable previous file), or the
;        length of the previous content when the final step failed: the
;        backup and the buffer hold that content.
; A previous file of another length than D6 (cut by a failed write, or
; changed outside the editors) is not backed up: the backup keeps the
; content it holds.
; ---------------------------------------------------------------------------
storage_replace:
        movem.l d2-d5/a0-a5,-(sp)
        movea.l a0,a5                   ; name
        move.l  d1,d5                   ; new length
        move.l  a1,-(sp)                ; new content
        moveq   #0,d4                   ; no backup written yet
        bsr.s   storage_size            ; D1 = old length
        beq.s   .old
        cmpi.l  #STE_NOT_FOUND,d0
        beq.s   .new                    ; no previous file
        bra.s   .fail
.old:
        tst.l   d6
        beq.s   .read
        cmp.l   d6,d1
        bne.s   .new                    ; not usable: the backup stays
.read:
        movea.l a5,a0
        movea.l a4,a1
        move.l  d3,d1
        bsr.s   storage_read            ; old content, bounded
        bne.s   .fail
        move.l  d1,d2                   ; old length (a write changes D1)
        movea.l a3,a0
        movea.l a4,a1
        bsr.s   storage_write           ; verified backup
        bne.s   .fail
        move.l  d2,d4
.new:
        movea.l a5,a0
        movea.l (sp),a1
        move.l  d5,d1
        bsr.s   storage_write
.fail:
        move.l  d4,d1
        addq.l  #4,sp
        movem.l (sp)+,d2-d5/a0-a5
        tst.l   d0
        rts

; ---------------------------------------------------------------------------
; storage_volume_ready: replaces the game's save-disk requests
; (save_disk_request) where the native flow then reads or writes the save
; volume. The save directory is always present: the save volume is selected
; (file_operation_dispatch selector SELECT_SAVE_DISK) without asking for a
; disk. D0.w = 0 with Z set; D7 is clobbered, as by the native request.
; ---------------------------------------------------------------------------
storage_volume_ready:
        move.w  #SELECT_SAVE_DISK,d7
        jsr     file_operation_dispatch
        clr.w   d0
        rts

; ---------------------------------------------------------------------------
; storage_native_result: D0.l = result of a storage call. D0.l = a result
; that the native file_error_message names: the game's own results stay; a
; missing file becomes FILE NOT FOUND; refusals for lack of room DISK FULL;
; every other refusal DISK ERROR.
; ---------------------------------------------------------------------------
storage_native_result:
        tst.l   d0
        bgt.s   .done
        cmpi.l  #STE_NOT_FOUND,d0
        beq.s   .missing
        cmpi.l  #STE_DIR_FULL,d0
        beq.s   .full
        cmpi.l  #STE_SAVES_FULL,d0
        beq.s   .full
        move.l  #FSE_READ_ERROR,d0
        rts
.missing:
        move.l  #FSE_NOT_FOUND,d0
        rts
.full:
        move.l  #FSE_DISK_FULL,d0
.done:
        rts
