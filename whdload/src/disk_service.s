; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The game's own disk code under the slave. Its file system (directory,
; files, read handles, RNC unpacking) stays in use for the game disks; only
; the physical layer disk_io and the drive selection are replaced:
;
;   disk_io             reads sectors of Disk.1 (drive 0) and Disk.2 (drive
;                       1) with resload_DiskLoad; writes to them return the
;                       game's write-protect result; the drive search
;                       reports drives 0-2
;   find_disk_marker    selects the drive that holds a disk mode at once:
;                       game disk 1 and the old-disk marker on drive 0, game
;                       disk 2 on drive 1, the save disk on drive 2
;   format check        always accepts drive 2, the save directory
;
; Drive 2 never reaches disk_io: file_service.s serves it from data/.
; Included by slave.s.

;----------------------------------------------------------------------------
; slave_disk_io: replaces disk_io (contract in swos2.i).
;   in:  D0.w = drive, D1.w = first sector, D2.w = sectors, D3.w = mode,
;        A0 = data
;   out: D0.l = 0 or the game's result; D1.l = the first sector on a failure;
;        mode DISK_IO_DETECT returns the drive mask in D0
;----------------------------------------------------------------------------
slave_disk_io:
        cmpi.w  #DISK_IO_DETECT,d3
        bne.s   .transfer
        moveq   #DRIVE_MASK,d0
        rts
.transfer:
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #0,d4
        move.w  d1,d4                   ; first sector
        moveq   #0,d5
        move.w  d2,d5                   ; sectors
        beq.s   .ok                     ; release only
        moveq   #3,d7
        and.w   d0,d7                   ; drive
        moveq   #$1E,d0                 ; sector range
        move.l  d4,d6
        add.l   d5,d6
        cmpi.l  #DISK_SECTORS,d6
        bhi.s   .fail
        moveq   #FSE_NO_DISK,d0
        cmpi.w  #DRIVE_DISK2,d7
        bhi.s   .fail
        moveq   #FSE_WRITE_PROTECTED,d0
        tst.b   d3                      ; 0 = read
        bne.s   .fail
        move.l  d4,d0
        moveq   #9,d1
        lsl.l   d1,d0                   ; byte offset
        move.l  d5,d1
        moveq   #9,d2
        lsl.l   d2,d1                   ; byte count
        moveq   #1,d2
        add.w   d7,d2                   ; Disk.1 or Disk.2
        movea.l resload(pc),a2
        jsr     resload_DiskLoad(a2)
        bsr.w   keys_released
        moveq   #FSE_READ_ERROR,d1
        tst.l   d0
        exg     d0,d1
        beq.s   .fail
.ok:
        moveq   #0,d0
        movem.l (sp)+,d1-d7/a0-a6
        rts
.fail:
        move.l  d4,(sp)                 ; D1 = the sector that failed
        movem.l (sp)+,d1-d7/a0-a6
        tst.l   d0
        rts

;----------------------------------------------------------------------------
; slave_find_marker: replaces game_find_disk_marker.
;   in:  D0.w = disk mode 1-4
;   out: D0.w = 0 (Z set) with the drive selected, or -1 for another mode
;----------------------------------------------------------------------------
slave_find_marker:
        movem.l d1/a0,-(sp)
        subq.w  #1,d0
        cmpi.w  #SAVE_DISK_MODE-1,d0
        bhi.s   .unknown
        lea     mode_drives(pc),a0
        moveq   #0,d1
        move.b  (a0,d0.w),d1
        lea     file_mode_drive_cache,a0
        move.b  d1,(a0,d0.w)
        move.w  d1,file_drive_index
        addq.w  #1,d0
        move.w  d0,file_disk_mode
        moveq   #0,d0
        bra.s   .done
.unknown:
        moveq   #-1,d0
.done:
        movem.l (sp)+,d1/a0
        tst.w   d0
        rts

; Drive of disk modes 1-4: game disk 1, game disk 2, the old-disk marker
; grafs/disk2.raw (on disk 1 of this release) and the save disk.
mode_drives:
        dc.b    DRIVE_DISK1,DRIVE_DISK2,DRIVE_DISK1,DRIVE_SAVE

;----------------------------------------------------------------------------
; slave_format_check: replaces file_format_check. The save directory is the
; only save disk, so FORMAT SAVE DISK always gets it.
;   out: D0.w = 0 (Z set), drive 2 and the save-disk mode selected
;----------------------------------------------------------------------------
slave_format_check:
        move.w  #DRIVE_SAVE,file_drive_index
        move.w  #SAVE_DISK_MODE,file_disk_mode
        move.b  #DRIVE_SAVE,file_mode_drive_cache+SAVE_DISK_MODE-1
        moveq   #0,d0
        rts

;----------------------------------------------------------------------------
; keys_released: after WHDLoad has run the operating system, a key released
; meanwhile still counts as held and the game would repeat it for ever.
; Mark the last key released and stop the repeat. Changes no register.
;----------------------------------------------------------------------------
keys_released:
        clr.w   keyboard_repeat_timer
        bset    #7,keyboard_last_raw
        rts

;----------------------------------------------------------------------------
; audio_silence: WHDLoad switches to the operating system for writes and
; listings, while the game's sound interrupt stands still; set the four
; channels to volume 0 so that no sample loops audibly meanwhile. The game
; sets the volumes again with its next sound. Changes no register.
;----------------------------------------------------------------------------
audio_silence:
        move.l  a0,-(sp)
        lea     $dff0a8,a0              ; AUD0VOL
        clr.w   (a0)
        clr.w   $10(a0)                 ; AUD1VOL
        clr.w   $20(a0)                 ; AUD2VOL
        clr.w   $30(a0)                 ; AUD3VOL
        movea.l (sp)+,a0
        rts
