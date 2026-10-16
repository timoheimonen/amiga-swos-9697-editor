; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Team group gateway.
;
; file_load_team_group reads an ordinary group through one six-byte JSR to
; file_load_unpack at team_group_load_source, with A0 = "data/team.ggg" and
; A1 = team_group_buffer; the group code is in team_group_cache_key. The
; runtime hook makes that JSR call team_group_gateway instead.
;
; The database in use is an edited set's manifest or the original database
; (db_manifest_in_use, editors/dbstore.s): while a competition family
; exists, the set the family is bound to; otherwise the set of the USE
; EDITED DATABASE switch. A group the set does not declare goes to
; file_load_unpack unchanged. For a declared group, the gateway reads its
; file Tgggnnnn.GRP from the save directory into team_group_buffer bounded
; to TEAM_GROUP_BUFFER_SIZE, and checks its exact length and CRC-32 before
; it returns. On any failure it never returns a partial group: like the
; native loader it waits and tries again, until the declared file is
; readable. The caller then continues natively (length check, reindexing,
; career deltas, count). Whoever changes the set in use or the binding
; clears team_group_cache_valid, so the next request reaches the gateway.
;
; Return contract of file_load_unpack: D0.w = 0 with Z set, D1 = length,
; D2-D7/A0-A6 preserved.

        include "swos2.i"
        include "slave.i"
        include "layout.i"
        include "editor.i"
        include "work.i"

        xdef    team_group_gateway
        xref    editor_base
        xref    copy_read_bounded
        xref    customs_record_crc
        xref    db_manifest_in_use, db_find_entry

        section .text,code

team_group_gateway:
        movem.l d2-d7/a0-a6,-(sp)
        movea.l editor_base,a5
        bsr.l   db_manifest_in_use      ; A0 = manifest or Z set
        beq.w   .native
        moveq   #0,d0
        move.b  team_group_cache_key,d0
        bsr.l   db_find_entry           ; A4 = entry
        beq.w   .native
        lea     team_group_buffer,a2
        move.l  #TEAM_GROUP_BUFFER_SIZE,d3
        bsr.l   copy_read_bounded       ; D1 = length
        movem.l (sp)+,d2-d7/a0-a6
        clr.w   d0
        rts
.native:
        movem.l (sp)+,d2-d7/a0-a6
        cmpi.b  #ORIGINAL_CUSTOM_GROUP,team_group_cache_key
        bne.s   .unpack
        jsr     file_load_unpack        ; the original custom teams: their
        tst.w   d0                      ; CRC-32 is the custom set's
        bne.s   .loaded                 ; fingerprint as loaded
        move.l  a0,-(sp)
        lea     team_group_buffer,a0
        bsr.l   customs_record_crc
        movea.l (sp)+,a0
        tst.w   d0
.loaded:
        rts
.unpack:
        jmp     file_load_unpack
