; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; The match log: every match the match engine plays to its end is appended
; as one record to MATCHES.LOG in the save directory, which the game's own
; listing does not show. Records follow one another without a file header;
; each carries its own length and CRC-32, so a damaged record costs only
; itself and a reader finds the next record by its magic. MACHINE.CFG names
; the install: an identity that records of other installs never share and
; the machine name shown in merged tables. All values are big-endian.

        ifnd    MR_HEADER_SIZE

LOG_FILE_NAME           macro
        dc.b    'MATCHES.LOG',0
        endm
MACHINE_FILE_NAME       macro
        dc.b    'MACHINE.CFG',0
        endm

; ---------------------------------------------------------------------------
; A record
; ---------------------------------------------------------------------------
MR_MAGIC_VALUE          equ 'SWML'
MR_VERSION_VALUE        equ 1
MR_MAGIC                equ $00         ; long
MR_VERSION              equ $04         ; word
MR_LENGTH               equ $06         ; word: bytes of the record, CRC-32 included
MR_INSTALL              equ $08         ; long: install identity (MACHINE.CFG)
MR_SEQUENCE             equ $0C         ; long: 1, 2, ... per install
MR_MACHINE              equ $10         ; 16 bytes: machine name, NUL padded
MR_TIME                 equ $20         ; 8 bytes: MRT_*, all zero when unknown
MR_FAMILY               equ $28         ; word: 0 friendly, 1 DIY, 2 preset, 3 season, 4 career
MR_FLAGS                equ $2A         ; word: MRF_* bits
MR_IDENTITY             equ $2C         ; 32 bytes: the database in use, as in a .DEF
MR_COMPETITION          equ $4C         ; 40 bytes: competition name, NUL padded
MR_ROUND                equ $74         ; 40 bytes: round, NUL padded (empty in a league)
MR_TEAMS                equ $9C         ; home team, then away team (MT_SIZE each)
MR_PLAYER_COUNT         equ $DC         ; byte: scorer entries
MR_GOAL_COUNT           equ $DD         ; byte: goal entries
MR_RESERVED             equ $DE         ; word: zero
MR_HEADER_SIZE          equ $E0         ; scorers, then goals, then the CRC-32
MR_CRC_SIZE             equ 4
MR_MIN_SIZE             equ MR_HEADER_SIZE+MR_CRC_SIZE

; MR_TIME (from WHDLoad, only when the machine knows the date): WHDLoad
; reads the clock once when it starts, so every record of one session has
; the same time
MRT_YEAR                equ 0           ; word, e.g. 2026
MRT_MONTH               equ 2           ; 1-12
MRT_DAY                 equ 3           ; 1-31
MRT_HOUR                equ 4
MRT_MINUTE              equ 5
MRT_SECOND              equ 6
MRT_SIZE                equ 8

; MR_FLAGS
MRF_EXTRA_TIME          equ 0           ; extra time was played
MRF_PENALTIES           equ 1           ; a penalty shootout decided the match
MRF_SECOND_LEG          equ 2           ; second leg: MT_EARLIER holds the first
MRF_FORFEIT             equ 3           ; left with Esc; the game awarded the result
MRF_MINUTES_PARTIAL     equ 4           ; some goals have no goal entry

; A team (MR_TEAMS + side*MT_SIZE; side 0 home, 1 away)
MT_GROUP                equ 0           ; team key: group (72 for a custom team)
MT_ORDINAL              equ 1           ; team key: ordinal
MT_SOURCE               equ 2           ; MTS_*
MT_CONTROL              equ 3           ; CONTROL_* of the team record (team.i)
MT_NAME                 equ 4           ; 17 bytes: name as in the match
MT_GOALS_90             equ 22          ; goals after 90 minutes
MT_GOALS                equ 23          ; goals at the end, extra time included
MT_PENALTIES            equ 24          ; goals of the penalty shootout
MT_OWN_GOALS            equ 25          ; own goals of the opponents for this side
MT_EARLIER              equ 26          ; goals of the earlier leg
MT_SCORERS              equ 27          ; scorer entries of this side
MT_SIZE                 equ 32
MTS_DATABASE            equ 0
MTS_CUSTOM_SET          equ 1

; A scorer: a player who scored, with his goals as the game wrote them back
MS_SIDE                 equ 0           ; side of his team
MS_INDEX                equ 1           ; match player 0-15
MS_SLOT                 equ 2           ; physical slot in the team record
MS_SHIRT                equ 3           ; shirt number
MS_GOALS                equ 4
MS_FLAGS                equ 5           ; MSF_*
MS_NAME                 equ 6           ; 23 bytes: name, NUL padded
MS_SIZE                 equ 32
MS_NAME_SIZE            equ 23
MSF_SHORT_NAME          equ 0           ; bit: MS_NAME is the game's short form
SCORERS_MAX             equ 2*MATCH_PLAYERS

; A goal: one entry of the game's scorer lists, in list order per side
MG_SIDE                 equ 0           ; bit 0: side credited; bits 5-4: MGK_*
MG_SHIRT                equ 1           ; shirt of the scorer (an own goal: of
                                        ; the opponent who scored it)
MG_MINUTE               equ 2           ; 0-255, MG_NO_MINUTE when unknown
MG_SCORER               equ 3           ; scorer entry, MG_NO_SCORER for an own goal
MG_SIZE                 equ 4
MGK_SHIFT               equ 4
MGK_NORMAL              equ 0
MGK_PENALTY             equ 1
MGK_OWN_GOAL            equ 2
MG_NO_MINUTE            equ $FF
MG_NO_SCORER            equ $FF
GOALS_MAX               equ 2*SCORER_ENTRIES*SCORER_GOALS_MAX

MR_MAX_SIZE             equ MR_HEADER_SIZE+SCORERS_MAX*MS_SIZE+GOALS_MAX*MG_SIZE+MR_CRC_SIZE

; ---------------------------------------------------------------------------
; MACHINE.CFG
; ---------------------------------------------------------------------------
MID_MAGIC_HIGH           equ 'SWOS'
MID_MAGIC_LOW            equ 'MCH1'
MID_VERSION_VALUE        equ 1
MID_MAGIC                equ $00         ; 8 bytes
MID_VERSION              equ $08         ; word
MID_RESERVED             equ $0A         ; word: zero
MID_INSTALL              equ $0C         ; long: install identity, not zero
MID_NAME                 equ $10         ; 16 bytes: 1-15 characters, NUL padded
MID_CRC32                equ $20         ; long: CRC-32 of the bytes before it
MID_SIZE                 equ $24
MID_NAME_SIZE            equ 16

        endif
