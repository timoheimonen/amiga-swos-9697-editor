; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The save disk as the directory data/ of the install.
;
; The game's file system call file_driver_call is replaced: operations on
; drive 2 (paths "DF2:name" and read handles opened there) are served here
; with the resload file functions, all others go on to the game's own code.
; The editors reach the same directory through the slave block's veneer
; (slave_service_entry, operations SVC_* in slave.i).
;
; Rules:
;   - the directory is listed with resload_ListFiles at the first use and
;     again after every write, delete or failed listing; the names are kept
;     in the slave area (with PRELOAD, files changed from outside while the
;     game runs need a restart);
;   - the game's own listing (OFS_LIST) shows only the files the native
;     screens use: the recognized saves (.DIY .PRE .SEA .CAR .TAC .HIL) and
;     CUSTOMS.EDT, sorted by name, at most NATIVE_SAVES_MAX saves, so the
;     game's 60-record buffer and its 45-save chooser stay within their
;     limits; the editors' own files never appear there;
;   - FORMAT SAVE DISK changes nothing: the directory needs no format and
;     its files are never deleted; the save-disk marker the game writes
;     afterwards is not stored;
;   - reads never pass the file's length; an editor read never passes the
;     caller's capacity; editor writes are read back and compared;
;   - before a write, a delete or a listing the four audio channels are
;     silenced, and every operation returns with no key held (WHDLoad runs
;     the operating system for them).
; Included by slave.s.

; Remembered listing (SA_CATALOG)
CAT_STATE               equ 0           ; word: 0 list needed, 1 valid
CAT_FLAGS               equ 2           ; word: bit 0 buffer full
CAT_COUNT               equ 4           ; long: names
CAT_SAVES               equ 8           ; long: recognized saves among them
CAT_USED                equ 12          ; long: bytes of SA_NAMES used

;============================================================================
; slave_file_driver: replaces file_driver_call (contract in swos2.i).
;============================================================================
slave_file_driver:
        cmpi.l  #OFS_SEEK,d0
        bhi.s   .native
        cmpi.b  #OFS_CLOSE,d0
        bcc.s   .handle
        bsr.w   path_on_save_drive
        beq.s   save_volume
        bra.s   .native
.handle:
        bsr.w   handle_on_save_drive
        beq.s   save_volume
.native:
        movem.l d0-d7/a0-a6,-(sp)       ; the replaced instructions
        move.l  d0,d6
        jmp     file_driver_call+6

;----------------------------------------------------------------------------
; save_volume: one file-system operation on drive 2.
;   in:  D0 = opcode, A0 = "DF2:name" or a handle, A1 = buffer, D1 = length
;   out: D0.l = result (flags set); D1.l as the native operation returns it
;----------------------------------------------------------------------------
save_volume:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #0,d7
        move.b  d0,d7
        add.w   d7,d7
        move.w  .table(pc,d7.w),d7
        jsr     .table(pc,d7.w)         ; D0 result, D1 value, D2 = 1 to return D1
        tst.w   d2
        beq.s   .keep
        move.l  d1,(sp)
.keep:
        bsr.w   operation_done
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts
.table:
        dc.w    sv_read-.table, sv_write-.table, sv_delete-.table
        dc.w    sv_list-.table, sv_format-.table, sv_open-.table
        dc.w    sv_close-.table, sv_read_handle-.table, sv_seek-.table

; OFS_READ: the whole file to A1 (unbounded, as the native read).
sv_read:
        movea.l a1,a3
        bsr.w   native_path             ; A0 = path
        bne.s   .missing
        bsr.w   file_size
        beq.s   .absent
        move.l  d0,d3
        moveq   #0,d1
        movea.l a3,a1
        bsr.w   file_read_part
        move.l  d3,d1
        bra.s   .done
.absent:
        move.l  #FSE_NOT_FOUND,d0
.missing:
        moveq   #0,d1
.done:
        moveq   #1,d2
        rts

; OFS_WRITE: D1 bytes from A1 (the file is replaced).
sv_write:
        movea.l a1,a3
        move.l  d1,d3
        movea.l a0,a4
        lea     4(a4),a0
        lea     marker_name(pc),a1
        bsr.w   compare_names
        beq.s   .absorbed               ; the format's marker: not stored
        movea.l a4,a0
        bsr.w   native_path
        bne.s   .done
        move.l  #FSE_DISK_FULL,d0
        tst.l   d3
        beq.s   .done                   ; the native writer never writes 0 bytes
        movea.l a3,a1
        move.l  d3,d1
        bsr.w   file_write
        bra.s   .done
.absorbed:
        moveq   #0,d0
.done:
        moveq   #0,d2
        rts

; OFS_DELETE
sv_delete:
        bsr.w   native_path
        bne.s   .done
        bsr.w   file_size
        bne.s   .exists
        move.l  #FSE_NOT_FOUND,d0
        bra.s   .done
.exists:
        bsr.w   file_delete
.done:
        moveq   #0,d2
        rts

; OFS_LIST: native records at A1, D1 = their number.
sv_list:
        moveq   #0,d1
        bsr.w   catalog
        bne.s   .done
        bsr.w   native_listing
        moveq   #0,d0
.done:
        moveq   #1,d2
        rts

; OFS_FORMAT: the directory is not formatted; nothing is deleted.
sv_format:
        moveq   #0,d0
        moveq   #0,d2
        rts

; OFS_OPEN: D0 = handle 1 or 2 and D1 = length, or D0 = 0.
sv_open:
        movea.l a1,a3                   ; handle buffer (marks the record used)
        movea.l a0,a4
        bsr.w   native_path
        bne.s   .fail
        bsr.w   file_size
        beq.s   .fail
        move.l  d0,d3                   ; length
        lea     file_handle_records,a2
        moveq   #1,d4                   ; handle
.find:
        tst.l   FHR_BUFFER(a2)
        beq.s   .free
        lea     FILE_HANDLE_RECORD_SIZE(a2),a2
        addq.w  #1,d4
        cmpi.w  #2,d4
        bls.s   .find
        bra.s   .fail
.free:
        move.w  #DRIVE_SAVE,FHR_DRIVE(a2)
        clr.w   2(a2)
        move.w  #-1,4(a2)
        clr.l   FHR_POSITION(a2)
        move.l  a3,d0
        bne.s   .marked
        moveq   #1,d0                   ; any non-zero value marks it used
.marked:
        move.l  d0,FHR_BUFFER(a2)
        move.l  d3,FHR_LENGTH(a2)
        lea     4(a4),a0                ; the name after "DF2:"
        bsr.w   handle_name             ; A1 = name slot of handle D4
        moveq   #SA_HANDLE_NAME_SIZE-2,d0
.copy:
        move.b  (a0)+,(a1)+
        dbeq    d0,.copy
        clr.b   (a1)
        move.l  d4,d0
        move.l  d3,d1
        bra.s   .done
.fail:
        moveq   #0,d0
        moveq   #0,d1
.done:
        moveq   #1,d2
        rts

; OFS_CLOSE: A0 = handle.
sv_close:
        bsr.w   handle_record
        clr.l   FHR_BUFFER(a2)
        moveq   #0,d0
        moveq   #0,d2
        rts

; OFS_READ_HANDLE: at most D1 bytes to A1; D1 = bytes read.
sv_read_handle:
        movea.l a1,a3
        move.l  d1,d3
        bsr.w   handle_record           ; A2 = record, D4 = handle
        move.l  FHR_LENGTH(a2),d5
        sub.l   FHR_POSITION(a2),d5     ; bytes left
        cmp.l   d3,d5
        bls.s   .count
        move.l  d3,d5
.count:
        moveq   #0,d1
        moveq   #0,d0
        tst.l   d5
        beq.s   .done
        bsr.w   handle_name             ; A1 = name of handle D4
        movea.l a1,a0
        bsr.w   make_path               ; A0 = path
        move.l  d5,d0
        move.l  FHR_POSITION(a2),d1
        movea.l a3,a1
        bsr.w   file_read_part
        bne.s   .failed
        add.l   d5,FHR_POSITION(a2)
        move.l  d5,d1
        moveq   #0,d0
        bra.s   .done
.failed:
        moveq   #0,d1
.done:
        moveq   #1,d2
        rts

; OFS_SEEK: position D1, at most the length.
sv_seek:
        bsr.w   handle_record
        cmp.l   FHR_LENGTH(a2),d1
        bls.s   .set
        move.l  FHR_LENGTH(a2),d1
.set:
        move.l  d1,FHR_POSITION(a2)
        moveq   #0,d0
        moveq   #0,d2
        rts

;----------------------------------------------------------------------------
; Drive tests (all registers preserved)
;----------------------------------------------------------------------------
; path_on_save_drive: A0 = path. Z set when it starts with "DF2:".
path_on_save_drive:
        movem.l d0/a0,-(sp)
        move.b  (a0)+,d0
        bsr.w   upper_case
        cmpi.b  #'D',d0
        bne.s   .done
        move.b  (a0)+,d0
        bsr.w   upper_case
        cmpi.b  #'F',d0
        bne.s   .done
        cmpi.b  #'0'+DRIVE_SAVE,(a0)+
        bne.s   .done
        cmpi.b  #':',(a0)
.done:
        movem.l (sp)+,d0/a0
        rts

; handle_on_save_drive: A0 = handle. Z set for an open handle of drive 2.
handle_on_save_drive:
        movem.l d0/a2,-(sp)
        move.l  a0,d0
        subq.l  #1,d0
        cmpi.l  #1,d0
        bhi.s   .other
        bsr.s   record_of
        tst.l   FHR_BUFFER(a2)
        beq.s   .other
        cmpi.w  #DRIVE_SAVE,FHR_DRIVE(a2)
        bra.s   .done
.other:
        moveq   #1,d0                   ; Z clear
.done:
        movem.l (sp)+,d0/a2
        rts

; handle_record: A0 = handle 1 or 2. A2 = its record, D4.l = handle.
handle_record:
        move.l  a0,d4
        move.l  d4,d0
        subq.l  #1,d0
        bra.w   record_of

; record_of: D0.l = handle - 1. A2 = its record. D0 clobbered.
record_of:
        mulu.w  #FILE_HANDLE_RECORD_SIZE,d0
        lea     file_handle_records,a2
        adda.l  d0,a2
        rts

; handle_name: D4.l = handle. A1 = its name slot in the slave area.
handle_name:
        move.l  d4,d0
        subq.l  #1,d0
        mulu.w  #SA_HANDLE_NAME_SIZE,d0
        movea.l expmem(pc),a1
        lea     SA_HANDLE_NAMES(a1,d0.l),a1
        rts


;============================================================================
; slave_service_entry: the editors' file operations (slave.i), reached
; through the veneer at slave_service.
;   in:  D0.w = operation, arguments as listed in slave.i
;   out: D0.l = result (flags set), D1 (and D2 for SVC_LIST) as listed
;============================================================================
slave_service_entry:
        movem.l d2-d7/a0-a6,-(sp)
        moveq   #0,d7
        move.w  d0,d7                   ; operation, kept to the end
        subq.w  #1,d0
        cmpi.w  #SVC_LAST-1,d0
        bhi.s   .unknown
        add.w   d0,d0
        move.w  .table(pc,d0.w),d0
        jsr     .table(pc,d0.w)         ; D0 result, D1 and D2 values
        cmpi.w  #SVC_LIST,d7
        bne.s   .finish
        move.l  d2,(sp)                 ; SVC_LIST returns D2
        bra.s   .finish
.unknown:
        moveq   #STE_BAD_OPERATION,d0
.finish:
        bsr.w   operation_done
        movem.l (sp)+,d2-d7/a0-a6
        tst.l   d0
        rts
.table:
        dc.w    svc_list-.table, svc_size-.table, svc_read-.table
        dc.w    svc_read_part-.table, svc_write-.table, svc_delete-.table
        dc.w    svc_append-.table, svc_time-.table

; SVC_LIST: A1 = records, D1 = capacity -> D1 = names, D2 = recognized saves.
svc_list:
        movea.l a1,a3
        move.l  d1,d3                   ; records still free
        moveq   #0,d1
        moveq   #0,d2
        bsr.w   catalog
        bne.s   .done
        movea.l expmem(pc),a2
        lea     SA_CATALOG(a2),a4
        lea     SA_NAMES(a2),a0
        move.l  CAT_COUNT(a4),d4
        move.l  d4,d5                   ; names left
.name:
        tst.l   d5
        beq.s   .listed
        subq.l  #1,d5
        tst.l   d3
        beq.s   .skip
        subq.l  #1,d3
        movea.l a3,a1
        lea     FS_RECORD_SIZE(a3),a3
        moveq   #FS_RECORD_SIZE-2,d0
.copy:
        move.b  (a0)+,(a1)+
        dbeq    d0,.copy
        beq.s   .pad
.cut:
        tst.b   (a0)+                   ; longer than a record: cut
        bne.s   .cut
.pad:
        cmpa.l  a3,a1
        bcc.s   .name
        clr.b   (a1)+
        bra.s   .pad
.skip:
        tst.b   (a0)+
        bne.s   .skip
        bra.s   .name
.listed:
        move.l  d4,d1
        move.l  CAT_SAVES(a4),d2
        moveq   #0,d0
.done:
        rts

; SVC_SIZE: A0 = name -> D1 = length.
svc_size:
        moveq   #0,d1
        bsr.w   editor_path
        bne.s   .done
        bsr.w   file_size
        bne.s   .found
        moveq   #STE_NOT_FOUND,d0
        bra.s   .done
.found:
        move.l  d0,d1
        moveq   #0,d0
.done:
        rts

; SVC_READ: A0 = name, A1 = destination, D1 = capacity -> D1 = length.
svc_read:
        movea.l a1,a3
        move.l  d1,d3
        moveq   #0,d1
        bsr.w   editor_path
        bne.s   .done
        bsr.w   file_size
        bne.s   .found
        moveq   #STE_NOT_FOUND,d0
        bra.s   .done
.found:
        move.l  d0,d1
        cmp.l   d3,d0
        bls.s   .read
        moveq   #STE_TOO_LARGE,d0       ; D1 = the length; nothing is read
        bra.s   .done
.read:
        move.l  d0,d3
        moveq   #0,d1
        movea.l a3,a1
        bsr.w   file_read_part
        move.l  d3,d1
.done:
        rts

; SVC_READ_PART: A0 = name, A1 = destination, D1 = length, D2 = offset
; -> D1 = bytes read (fewer at the end of the file).
svc_read_part:
        movea.l a1,a3
        move.l  d1,d3
        move.l  d2,d4
        moveq   #0,d1
        bsr.w   editor_path
        bne.s   .done
        bsr.w   file_size
        bne.s   .found
        moveq   #STE_NOT_FOUND,d0
        bra.s   .done
.found:
        cmp.l   d4,d0
        bls.s   .empty                  ; offset at or after the end
        sub.l   d4,d0                   ; bytes after the offset
        cmp.l   d3,d0
        bls.s   .count
        move.l  d3,d0
.count:
        move.l  d0,d3
        move.l  d4,d1
        movea.l a3,a1
        bsr.w   file_read_part
        bne.s   .done
        move.l  d3,d1
        bra.s   .done
.empty:
        moveq   #0,d0
.done:
        rts

; SVC_WRITE: A0 = name, A1 = source, D1 = length. A new name is admitted
; while data/ holds fewer than SAVE_DIR_MAX_NAMES names and, for a
; recognized save, fewer than NATIVE_SAVES_MAX saves. The file is read back
; in pieces and compared with the source before success is reported.
svc_write:
        movea.l a1,a3                   ; source
        move.l  d1,d3                   ; length
        movea.l a0,a4                   ; name
        moveq   #STE_EMPTY,d0
        tst.l   d3
        beq.w   .done
        bsr.w   editor_path
        bne.w   .done
        bsr.w   file_size
        bne.s   .write                  ; replacing: no new name
        bsr.w   admit_name
        bne.s   .done
        movea.l a4,a0
        bsr.w   editor_path
        bne.s   .done
.write:
        movea.l a3,a1
        move.l  d3,d1
        bsr.w   file_write
        bne.s   .done
        movea.l a4,a0
        moveq   #0,d4                   ; the file holds only these bytes
        bsr.w   readback_compare
.done:
        rts

; admit_name: A4 = name of a file that does not exist yet. D0.l = 0 (Z set)
; while data/ takes another name (and, for a recognized save, another save),
; else STE_DIR_FULL or STE_SAVES_FULL.
admit_name:
        movem.l a0/a2,-(sp)
        movea.l expmem(pc),a2
        lea     SA_CATALOG(a2),a2
        moveq   #STE_DIR_FULL,d0
        cmpi.l  #SAVE_DIR_MAX_NAMES,CAT_COUNT(a2)
        bcc.s   .done
        movea.l a4,a0
        moveq   #0,d0
        bsr.w   recognized_save
        bne.s   .done
        moveq   #STE_SAVES_FULL,d0
        cmpi.l  #NATIVE_SAVES_MAX,CAT_SAVES(a2)
        bcc.s   .done
        moveq   #0,d0
.done:
        movem.l (sp)+,a0/a2
        tst.l   d0
        rts

; readback_compare: A4 = name just written, A3 = the bytes written, D3.l =
; their number, D4.l = the file offset of the first of them, which must
; also be the file's length before the write. Lists data/ again, checks
; that the file now ends after them and reads them back in pieces.
; D0.l = 0 (Z set), STE_VERIFY or a read result.
readback_compare:
        movea.l a4,a0
        bsr.w   editor_path             ; lists data/ again after the write
        bne.s   .done
        bsr.w   file_size
        sub.l   d4,d0
        cmp.l   d3,d0
        bne.s   .differs
        moveq   #0,d6                   ; bytes compared
.piece:
        move.l  d3,d5
        sub.l   d6,d5
        beq.s   .same
        cmpi.l  #SA_READBACK_SIZE,d5
        bls.s   .read
        move.l  #SA_READBACK_SIZE,d5
.read:
        move.l  d5,d0
        move.l  d4,d1
        add.l   d6,d1
        movea.l expmem(pc),a1
        lea     SA_READBACK(a1),a1
        bsr.w   file_read_part          ; A0 = path, kept
        bne.s   .done
        movea.l expmem(pc),a1
        lea     SA_READBACK(a1),a1
        lea     (a3,d6.l),a2
        move.l  d5,d0
        subq.l  #1,d0
.compare:
        cmpm.b  (a2)+,(a1)+
        bne.s   .differs
        subq.l  #1,d0
        bpl.s   .compare
        add.l   d5,d6
        bra.s   .piece
.same:
        moveq   #0,d0
        bra.s   .done
.differs:
        moveq   #STE_VERIFY,d0
.done:
        tst.l   d0
        rts

; SVC_DELETE: A0 = name.
svc_delete:
        bsr.w   editor_path
        bne.s   .done
        bsr.w   file_size
        bne.s   .exists
        moveq   #STE_NOT_FOUND,d0
        bra.s   .done
.exists:
        bsr.w   file_delete
.done:
        rts

; SVC_APPEND: A0 = name, A1 = source, D1 = length, D2 = the file's length
; the caller knows (0: there is no file yet) -> D1 = the offset at which the
; bytes were added. They go at that offset and the file is checked to end
; after them; earlier bytes are never written. A file of another length is
; refused (STE_CHANGED). After a failed write WHDLoad no longer sees the
; file (its size reads as 0): then the bytes still go at the known length,
; where a file that is really gone cannot be written. Only a file the caller
; does not know is created, as a new name.
svc_append:
        movea.l a1,a3                   ; source
        move.l  d1,d3                   ; length
        movea.l a0,a4                   ; name
        move.l  d2,d4                   ; offset: the length the caller knows
        moveq   #0,d1
        moveq   #STE_EMPTY,d0
        tst.l   d3
        beq.s   .done
        bsr.w   editor_path
        bne.s   .done
        bsr.w   file_size
        cmp.l   d4,d0
        beq.s   .known
        tst.l   d0
        beq.s   .add                    ; not seen: written at the known length
        moveq   #STE_CHANGED,d0
        bra.s   .done
.known:
        tst.l   d4
        bne.s   .add
        bsr.w   admit_name              ; no file yet
        bne.s   .done
        movea.l a4,a0
        bsr.w   editor_path
        bne.s   .done
        movea.l a3,a1
        move.l  d3,d1
        bsr.w   file_write
        bra.s   .written
.add:
        movea.l a3,a1
        move.l  d3,d0
        move.l  d4,d1
        bsr.w   file_write_part
.written:
        bne.s   .done
        bsr.w   readback_compare
        move.l  d4,d1
.done:
        rts

; SVC_TIME: A1 = 8 bytes. The date and time of WHDLoad's clock (year word,
; month, day, hour, minute, second, zero) when the machine has a clock set
; to 1995 or later; else zeros and STE_NO_TIME. WHDLoad reads the clock once,
; when it starts: the time does not advance while the game runs.
svc_time:
        movea.l a1,a3
        clr.l   (a3)
        clr.l   4(a3)
        clr.l   -(sp)                   ; TAG_DONE
        clr.l   -(sp)                   ; data: the structure's address
        move.l  #WHDLTAG_TIME_GET,-(sp)
        movea.l sp,a0
        movea.l resload(pc),a2
        jsr     resload_Control(a2)
        movea.l 4(sp),a0
        lea     12(sp),sp
        moveq   #STE_NO_TIME,d0
        cmpa.w  #0,a0
        beq.s   .done
        moveq   #0,d1
        move.b  WT_YEAR(a0),d1
        addi.w  #1900,d1
        cmpi.w  #1978,d1
        bcc.s   .century
        addi.w  #100,d1                 ; 00-77: 2000-2077
.century:
        cmpi.w  #1995,d1
        bcs.s   .done                   ; no clock: the date stays near 1978
        move.w  d1,(a3)
        move.b  WT_MONTH(a0),2(a3)
        move.b  WT_DAY(a0),3(a3)
        move.b  WT_HOUR(a0),4(a3)
        move.b  WT_MINUTE(a0),5(a3)
        move.b  WT_SECOND(a0),6(a3)
        moveq   #0,d0
.done:
        rts

;============================================================================
; Names and paths
;============================================================================
; native_path: A0 = "DF2:name". A0 = "data/name" in the slave area and
; D0.l = 0 (Z set); or D0.l = FSE_NO_DISK when data/ cannot be listed, or
; FSE_BAD_PATH for a name the save directory does not take.
native_path:
        bsr.w   catalog
        bne.s   .done
        addq.l  #4,a0
        moveq   #NATIVE_NAME_MAX,d0
        bsr.s   name_check
        bne.s   .bad
        bsr.s   make_path
        moveq   #0,d0
        bra.s   .done
.bad:
        move.l  #FSE_BAD_PATH,d0
.done:
        tst.l   d0
        rts

; editor_path: A0 = name. As native_path for an editor name: 1-29
; characters with a dot; STE_BAD_NAME otherwise.
editor_path:
        bsr.w   catalog
        bne.s   .done
        moveq   #FS_NAME_MAX,d0
        bsr.s   name_check
        bne.s   .bad
        bsr.s   has_dot
        bne.s   .bad
        bsr.s   make_path
        moveq   #0,d0
        bra.s   .done
.bad:
        moveq   #STE_BAD_NAME,d0
.done:
        tst.l   d0
        rts

; name_check: A0 = name, D0.l = maximum length. Z set when the name has 1
; to D0 characters and none of them is "/", ":" or below a space.
name_check:
        movem.l d1-d2/a0,-(sp)
        moveq   #0,d2                   ; characters
.char:
        move.b  (a0)+,d1
        beq.s   .end
        cmpi.b  #' ',d1
        bcs.s   .bad
        cmpi.b  #'/',d1
        beq.s   .bad
        cmpi.b  #':',d1
        beq.s   .bad
        addq.l  #1,d2
        cmp.l   d0,d2
        bls.s   .char
.bad:
        moveq   #1,d1                   ; Z clear
        bra.s   .done
.end:
        tst.l   d2
        beq.s   .bad
        cmp.b   d1,d1                   ; Z set
.done:
        movem.l (sp)+,d1-d2/a0
        rts

; has_dot: A0 = name. Z set when it holds a dot.
has_dot:
        move.l  a0,-(sp)
.char:
        tst.b   (a0)
        beq.s   .none
        cmpi.b  #'.',(a0)+
        bne.s   .char
        movea.l (sp)+,a0
        cmp.b   d0,d0                   ; Z set
        rts
.none:
        movea.l (sp)+,a0
        cmpa.l  #0,sp                   ; Z clear
        rts

; make_path: A0 = checked name. A0 = SA_PATH holding "data/" and the name.
make_path:
        movem.l a1-a2,-(sp)
        movea.l expmem(pc),a1
        lea     SA_PATH(a1),a1
        movea.l a1,a2
        move.l  a0,-(sp)
        lea     directory_prefix(pc),a0
.prefix:
        move.b  (a0)+,(a1)+
        bne.s   .prefix
        subq.l  #1,a1
        movea.l (sp)+,a0
.name:
        move.b  (a0)+,(a1)+
        bne.s   .name
        movea.l a2,a0
        movem.l (sp)+,a1-a2
        rts

; recognized_save: A0 = name. Z set when it is a save the native chooser
; recognizes: 5-29 characters ending in .DIY .PRE .SEA .CAR .TAC or .HIL,
; in any case, without control characters.
recognized_save:
        movem.l d0-d2/a0-a1,-(sp)
        moveq   #FS_NAME_MAX,d0
        bsr.s   name_check
        bne.s   .no
        movea.l a0,a1
.end:
        tst.b   (a1)+
        bne.s   .end
        subq.l  #1,a1                   ; the NUL
        move.l  a1,d0
        sub.l   a0,d0
        cmpi.l  #5,d0
        bcs.s   .no
        lea     -4(a1),a0               ; the last four characters
        lea     save_suffixes(pc),a1
.suffix:
        tst.b   (a1)
        beq.s   .no
        moveq   #0,d1
.char:
        move.b  (a0,d1.w),d0
        bsr.w   upper_case
        cmp.b   (a1,d1.w),d0
        bne.s   .next
        addq.w  #1,d1
        cmpi.w  #4,d1
        bne.s   .char
        moveq   #0,d0                   ; Z set
        bra.s   .done
.next:
        addq.l  #4,a1
        bra.s   .suffix
.no:
        moveq   #1,d0                   ; Z clear
.done:
        movem.l (sp)+,d0-d2/a0-a1
        rts

; compare_names: A0, A1 = names. D0.l < 0, 0 or > 0 (flags set) as the
; first sorts before, equal to or after the second, ignoring ASCII case.
compare_names:
        movem.l d1/a0-a1,-(sp)
.char:
        moveq   #0,d0
        move.b  (a0)+,d0
        bsr.w   upper_case
        move.w  d0,d1
        moveq   #0,d0
        move.b  (a1)+,d0
        bsr.w   upper_case
        sub.w   d0,d1
        bne.s   .differ
        tst.b   d0
        bne.s   .char
.differ:
        move.w  d1,d0
        ext.l   d0
        movem.l (sp)+,d1/a0-a1
        tst.l   d0
        rts

;============================================================================
; The remembered listing of data/
;============================================================================
; catalog: list data/ unless the remembered listing is still valid.
;   out: D0.l = 0 (Z set), or FSE_NO_DISK when data/ cannot be listed
catalog:
        movem.l d1-d4/a0-a4,-(sp)
        movea.l expmem(pc),a3
        lea     SA_CATALOG(a3),a2
        moveq   #0,d0
        tst.w   CAT_STATE(a2)
        bne.w   .done
        bsr.w   audio_silence
        move.l  #SA_NAMES_SIZE,d0
        lea     directory_name(pc),a0
        lea     SA_NAMES(a3),a1
        movea.l resload(pc),a4
        jsr     resload_ListFiles(a4)
        lea     SLAVE_BLOCK,a1
        addq.l  #1,SB_CATALOG_LISTINGS(a1)
        tst.l   d1
        bne.s   .missing
        move.l  d0,CAT_COUNT(a2)
        move.l  d0,SB_CATALOG_NAMES(a1)
        lea     SA_NAMES(a3),a0
        move.l  d0,d2                   ; names left
        moveq   #0,d3                   ; recognized saves
.name:
        tst.l   d2
        beq.s   .counted
        subq.l  #1,d2
        bsr.w   recognized_save
        bne.s   .next
        addq.l  #1,d3
.next:
        tst.b   (a0)+
        bne.s   .next
        bra.s   .name
.counted:
        move.l  d3,CAT_SAVES(a2)
        move.l  a0,d0
        lea     SA_NAMES(a3),a0
        sub.l   a0,d0
        move.l  d0,CAT_USED(a2)
        clr.w   CAT_FLAGS(a2)
        bclr    #SBF_CATALOG_FULL,SB_FLAGS+1(a1)
        addi.l  #2*NATIVE_NAME_MAX+2,d0
        cmpi.l  #SA_NAMES_SIZE,d0
        bls.s   .valid
        move.w  #1,CAT_FLAGS(a2)        ; the buffer was nearly full
        bset    #SBF_CATALOG_FULL,SB_FLAGS+1(a1)
.valid:
        move.w  #1,CAT_STATE(a2)
        moveq   #0,d0
        bra.s   .done
.missing:
        clr.l   CAT_COUNT(a2)
        clr.l   CAT_SAVES(a2)
        move.l  #FSE_NO_DISK,d0
.done:
        movem.l (sp)+,d1-d4/a0-a4
        tst.l   d0
        rts

; catalog_stale: the next operation lists data/ again. Changes no register.
catalog_stale:
        move.l  a0,-(sp)
        movea.l expmem(pc),a0
        clr.w   SA_CATALOG+CAT_STATE(a0)
        movea.l (sp)+,a0
        rts

; native_listing: A1 = destination (catalog valid). Writes the game's
; 32-byte records [$FD, length, name padded to 30] of the recognized saves
; (at most NATIVE_SAVES_MAX, the first by name) and CUSTOMS.EDT, sorted by
; name. D1.l = records written (at most NATIVE_SAVES_MAX+1).
native_listing:
        movem.l d0/d2-d7/a0-a5,-(sp)
        movea.l a1,a5
        movea.l expmem(pc),a3
        lea     SA_CATALOG(a3),a2
        lea     SA_SORT(a3),a4
        moveq   #0,d6                   ; names in the sorted array
        moveq   #NATIVE_SAVES_MAX,d7
        moveq   #0,d5                   ; pass 1: recognized saves
        bsr.s   .pass
        moveq   #1,d5                   ; pass 2: CUSTOMS.EDT
        move.l  d6,d7
        addq.l  #1,d7
        bsr.s   .pass
        move.l  d6,d1
        move.l  d6,d2
        movea.l a4,a1
.record:
        subq.l  #1,d2
        bmi.s   .written
        movea.l (a1)+,a0
        move.b  #OFS_TYPE_FILE,(a5)
        moveq   #0,d0
.length:
        tst.b   (a0,d0.w)
        beq.s   .measured
        addq.w  #1,d0
        bra.s   .length
.measured:
        move.b  d0,1(a5)
        moveq   #NATIVE_NAME_MAX-1,d3
        lea     2(a5),a3
.char:
        move.b  (a0),(a3)+
        beq.s   .pad
        addq.l  #1,a0
.pad:
        dbf     d3,.char
        lea     FS_RECORD_SIZE(a5),a5
        bra.s   .record
.written:
        movem.l (sp)+,d0/d2-d7/a0-a5
        rts

; One pass over the remembered names: D5 = 0 saves, 1 CUSTOMS.EDT.
.pass:
        lea     SA_NAMES(a3),a0
        move.l  CAT_COUNT(a2),d4
.name:
        subq.l  #1,d4
        bmi.s   .passed
        tst.w   d5
        bne.s   .custom
        bsr.w   recognized_save
        bne.s   .skip
        bra.s   .insert
.custom:
        lea     customs_name(pc),a1
        bsr.w   compare_names
        bne.s   .skip
.insert:
        bsr.s   sorted_insert
.skip:
        tst.b   (a0)+
        bne.s   .skip
        bra.s   .name
.passed:
        rts

; sorted_insert: A0 = name, A4 = array of D6.l name pointers sorted by
; name, D7.l = its capacity. Puts A0 in order; in a full array the last
; name is dropped, or A0 itself when it sorts after it.
sorted_insert:
        movem.l d0-d2/a1,-(sp)
        move.l  d6,d2                   ; position of A0
.find:
        tst.l   d2
        beq.s   .found
        move.l  d2,d0
        subq.l  #1,d0
        lsl.l   #2,d0
        movea.l (a4,d0.l),a1
        bsr.w   compare_names
        bpl.s   .found                  ; A0 sorts at or after it
        subq.l  #1,d2
        bra.s   .find
.found:
        cmp.l   d7,d2
        bcc.s   .done                   ; after the last of a full array
        move.l  d6,d1                   ; slot that receives the last name
        cmp.l   d7,d1
        bcs.s   .grow
        subq.l  #1,d1                   ; full: the last name is dropped
        bra.s   .shift
.grow:
        addq.l  #1,d6
.shift:
        cmp.l   d2,d1
        beq.s   .put
        move.l  d1,d0
        lsl.l   #2,d0
        move.l  -4(a4,d0.l),(a4,d0.l)
        subq.l  #1,d1
        bra.s   .shift
.put:
        lsl.l   #2,d2
        move.l  a0,(a4,d2.l)
.done:
        movem.l (sp)+,d0-d2/a1
        rts

;============================================================================
; resload file functions (A0 = path; registers other than D0 preserved)
;============================================================================
; file_size: D0.l = length (flags set), 0 when the file does not exist.
file_size:
        movem.l d1/a0-a2,-(sp)
        movea.l resload(pc),a2
        jsr     resload_GetFileSize(a2)
        movem.l (sp)+,d1/a0-a2
        tst.l   d0
        rts

; file_read_part: A1 = destination, D0.l = length, D1.l = offset.
; D0.l = 0 (Z set) or FSE_READ_ERROR.
file_read_part:
        movem.l d1/a0-a2,-(sp)
        movea.l resload(pc),a2
        jsr     resload_LoadFileOffset(a2)
        tst.l   d0
        beq.s   .fail
        moveq   #0,d0
        bra.s   .done
.fail:
        moveq   #FSE_READ_ERROR,d0
.done:
        movem.l (sp)+,d1/a0-a2
        tst.l   d0
        rts

; file_write: A1 = source, D1.l = length. D0.l = 0 (Z set) or a result.
file_write:
        movem.l d1/a0-a2,-(sp)
        bsr.w   audio_silence
        move.l  d1,d0
        movea.l resload(pc),a2
        jsr     resload_SaveFile(a2)
        bsr.w   catalog_stale
        tst.l   d0
        beq.s   .fail
        moveq   #0,d0
        bra.s   .done
.fail:
        bsr.s   dos_result
.done:
        movem.l (sp)+,d1/a0-a2
        tst.l   d0
        rts

; file_write_part: A1 = source, D0.l = length, D1.l = offset in the
; existing file. D0.l = 0 (Z set) or a result.
file_write_part:
        movem.l d1/a0-a2,-(sp)
        bsr.w   audio_silence
        movea.l resload(pc),a2
        jsr     resload_SaveFileOffset(a2)
        bsr.w   catalog_stale
        tst.l   d0
        beq.s   .fail
        moveq   #0,d0
        bra.s   .done
.fail:
        bsr.s   dos_result
.done:
        movem.l (sp)+,d1/a0-a2
        tst.l   d0
        rts

; file_delete: D0.l = 0 (Z set) or a result.
file_delete:
        movem.l d1/a0-a2,-(sp)
        bsr.w   audio_silence
        movea.l resload(pc),a2
        jsr     resload_DeleteFile(a2)
        bsr.w   catalog_stale
        tst.l   d0
        beq.s   .fail
        moveq   #0,d0
        bra.s   .done
.fail:
        bsr.s   dos_result
.done:
        movem.l (sp)+,d1/a0-a2
        tst.l   d0
        rts

; dos_result: D1.l = AmigaDOS error. D0.l = the game's result for it.
dos_result:
        move.l  #FSE_WRITE_PROTECTED,d0
        cmpi.l  #DOSERR_WRITE_PROTECTED,d1
        beq.s   .done
        cmpi.l  #DOSERR_FILE_PROTECTED,d1
        beq.s   .done
        cmpi.l  #DOSERR_DELETE_PROTECTED,d1
        beq.s   .done
        move.l  #FSE_NO_DISK,d0
        cmpi.l  #DOSERR_OBJECT_NOT_FOUND,d1
        beq.s   .done
        move.l  #FSE_DISK_FULL,d0
.done:
        rts

; operation_done: D0.l = result of a save-volume operation. Records it in
; the slave block, makes the next operation list data/ again after a
; failure, and returns with no key held. Changes no register.
operation_done:
        move.l  a0,-(sp)
        lea     SLAVE_BLOCK,a0
        move.l  d0,SB_FILE_RESULT(a0)
        addq.l  #1,SB_FILE_OPERATIONS(a0)
        tst.l   d0
        beq.s   .keys
        cmpi.l  #FSE_NOT_FOUND,d0
        beq.s   .keys
        cmpi.l  #STE_NOT_FOUND,d0
        beq.s   .keys
        bsr.w   catalog_stale
.keys:
        bsr.w   keys_released
        movea.l (sp)+,a0
        rts

directory_name:
        dc.b    "data",0
directory_prefix:
        dc.b    "data/",0
customs_name:
        dc.b    "CUSTOMS.EDT",0
marker_name:
        dc.b    "swos4.dku",0
save_suffixes:
        dc.b    ".DIY.PRE.SEA.CAR.TAC.HIL",0
        even
