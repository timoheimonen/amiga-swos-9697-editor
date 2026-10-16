; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Database mode: the edited database set in the save directory, the link
; files of competition saves and the results of their checks. All values
; are big-endian; every CRC-32 is CRC-32/ISO-HDLC. Include after swos2.i,
; slave.i and team.i.
;
; The set is declared by a manifest, DBASE.CFG (the previous one is kept as
; DBASE.BAK). Each entry names one file Tgggnnnn.GRP (code ggg, generation
; nnnn):
;   - a database group (0-85): one complete raw team group, the native count
;     word and count records, exactly as the game's own TEAM.ggg after
;     unpacking, with the same keys, record order and division capacities;
;   - COPY_EUROCUP, COPY_EUROCWC, COPY_UEFACUP (100-102): a European club
;     cup's team copies, CUP_*_TEAMS headerless records in participant order
;     (the game's EUROCUP.TMD, EUROCWC.TMD, UEFACUP.TMD hold the 96/97 ones);
;   - COPY_POOL (103): the transfer pool, POOL_ENTRIES entries of
;     POOL_ENTRY_SIZE bytes (the game's POOLPLYR.DAT).
; Version 1 manifests (at most 28 database groups) are still read; the
; editor writes version 2. DBASE.USE remembers USE EDITED DATABASE.

        ifnd    MANIFEST_MAX

; ---------------------------------------------------------------------------
; Manifest
; ---------------------------------------------------------------------------
MANIFEST_MAGIC_HIGH     equ 'SWOS'
MANIFEST_MAGIC_LOW      equ 'GRP1'
MANIFEST_VERSION        equ 2           ; written; MANIFEST_VERSION_V1 is still read
MANIFEST_VERSION_V1     equ 1
MF_MAGIC                equ $00         ; 8 bytes
MF_VERSION              equ $08         ; word
MF_COUNT                equ $0A         ; word: entries, 1-MANIFEST_ENTRIES (V1: 1-28)
MF_GENERATION           equ $0C         ; long: manifest generation
MF_IDENTITY             equ $10         ; 32 bytes: SHA-256 of the supported SWOS2
MF_BASE                 equ $30         ; long: SWOS2_BASE
MF_LENGTH               equ $34         ; long: MANIFEST_HEADER+MANIFEST_ENTRY*count
MF_CRC32                equ $38         ; long: CRC-32 of the manifest, this field zero
MF_RESERVED             equ $3C         ; long: zero
MF_LABEL                equ $40         ; 16 bytes: set label, NUL padded
MANIFEST_HEADER         equ $50
MANIFEST_IDENTITY_SIZE  equ 32
SET_LABEL_SIZE          equ 16
; Entry
ME_GROUP                equ 0           ; word: database group or COPY_*
ME_GENERATION           equ 2           ; word: file generation 1-9999
ME_TEAMS                equ 4           ; word: records of the file
ME_RESERVED             equ 6           ; word: zero
ME_LENGTH               equ 8           ; long: GROUP_COUNT_SIZE+TEAM_SIZE*count for
                                        ; a group, TEAM_SIZE*count for a cup,
                                        ; POOL_SIZE for the pool
ME_CRC32                equ 12          ; long: CRC-32 of the file
MANIFEST_ENTRY          equ 16
MANIFEST_ENTRIES        equ 75          ; 71 database groups and 4 copies
MANIFEST_ENTRIES_V1     equ 28
MANIFEST_MAX            equ MANIFEST_HEADER+MANIFEST_ENTRIES*MANIFEST_ENTRY
GENERATION_MAX          equ 9999
GROUP_MAX_TEAMS         equ 93          ; the largest group, TEAM.008
DATABASE_GROUP_COUNT    equ 71          ; 65 club groups, 6 national groups
NATIONAL_FIRST          equ 80          ; the first national group

; The copies that follow the set in use.
COPY_EUROCUP            equ 100
COPY_EUROCWC            equ 101
COPY_UEFACUP            equ 102
COPY_POOL               equ 103
COPY_FIRST              equ COPY_EUROCUP
COPY_COUNT              equ 4
CUP_COUNT               equ 3
CUP_EUROCUP_TEAMS       equ 16
CUP_EUROCWC_TEAMS       equ 32
CUP_UEFACUP_TEAMS       equ 32
CUP_KEYS                equ CUP_EUROCUP_TEAMS+CUP_EUROCWC_TEAMS+CUP_UEFACUP_TEAMS
CUP_MAX_TEAMS           equ 32
POOL_ENTRIES            equ 900
POOL_ENTRY_SIZE         equ 58
POOL_GROUP              equ 0           ; byte: team group
POOL_ORDINAL            equ 1           ; byte: team ordinal
POOL_SLOT               equ 2           ; byte: physical player slot
POOL_TEAM_NAME          equ 3           ; TEAM_NAME_SIZE bytes
POOL_PLAYER             equ $14         ; PLAYER_SIZE bytes
POOL_SIZE               equ POOL_ENTRIES*POOL_ENTRY_SIZE

; The remembered switch: DBASE.USE, SWITCH_SIZE bytes.
SWITCH_MAGIC_HIGH       equ 'SWOS'
SWITCH_MAGIC_LOW        equ 'USE1'
SWITCH_VERSION          equ 1
SW_VERSION              equ 8           ; word
SW_STATE                equ 10          ; word: 0 off, 1 on
SW_CRC32                equ 12          ; long: CRC-32 of the twelve bytes before
SWITCH_SIZE             equ 16

; ---------------------------------------------------------------------------
; Link file of a competition save: base name of the save and LINK_SUFFIX_*
; ---------------------------------------------------------------------------
LINK_MAGIC_HIGH         equ 'SWOS'
LINK_MAGIC_LOW          equ 'LNK1'
LINK_VERSION            equ 2           ; written; a version 1 link (with a
LINK_VERSION_V1         equ 1           ; version 1 manifest) is still read
LH_MAGIC                equ $00         ; 8 bytes
LH_VERSION              equ $08         ; word
LH_LENGTH               equ $0A         ; word: body length
LH_CRC32                equ $0C         ; long: CRC-32 of the body
LINK_HEADER             equ $10
LB_FAMILY               equ 0           ; word: FAMILY_* of the save
LB_SAVE_LENGTH          equ 2           ; long: exact length of the save
LB_SAVE_CRC32           equ 6           ; long: its CRC-32
LB_MANIFEST             equ 10          ; the manifest of the set it was started with
LINK_MIN                equ LINK_HEADER+LB_MANIFEST+MANIFEST_HEADER+MANIFEST_ENTRY
LINK_MAX                equ LINK_HEADER+LB_MANIFEST+MANIFEST_MAX

; Competition families (competition_family).
FAMILY_NONE             equ 0
FAMILY_DIY              equ 1
FAMILY_PRESET           equ 2
FAMILY_SEASON           equ 3
FAMILY_CAREER           equ 4

; ---------------------------------------------------------------------------
; Results of the checks, in the order they are made (D0.l; D1 the group of
; DC_GROUP, DC_ORDER and DC_ENTRY). The texts are problem_* in dbstore.s.
; ---------------------------------------------------------------------------
MC_OK                   equ 0
MC_SIZE                 equ 1
MC_MAGIC                equ 2
MC_VERSION              equ 3
MC_CRC                  equ 4
MC_IDENTITY             equ 5
MC_LABEL                equ 6
MC_GROUP                equ 7
MC_ORDER                equ 8
MC_ENTRY                equ 9
LC_SIZE                 equ 10
LC_MAGIC                equ 11
LC_VERSION              equ 12
LC_CRC                  equ 13
LC_FAMILY               equ 14
LC_SAVE                 equ 15
GC_MISSING              equ 20          ; a declared group file (name in DB_NAME)
GC_LENGTH               equ 21
GC_CRC                  equ 22
GC_CONTENT              equ 23
PROBLEM_LAST            equ GC_CONTENT


; State of the set in the save directory (DB_SET_STATE).
DSS_UNKNOWN             equ 0           ; not read since the start
DSS_NONE                equ 1           ; no DBASE.CFG
DSS_VALID               equ 2           ; DB_SET holds DBASE.CFG
DSS_DAMAGED             equ 3           ; DBASE.CFG fails its check (DB_SET_PROBLEM)

        endif
