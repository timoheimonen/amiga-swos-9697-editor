; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Tournament definitions: the .DEF file, the setup state of the DIY pages
; it is taken from and applied to, and the results of its checks. All
; values are big-endian. Include after swos2.i and tactic.i.

        ifnd    DEF_HEADER_SIZE

; ---------------------------------------------------------------------------
; File: header, then the body
; ---------------------------------------------------------------------------
DEF_MAGIC_HIGH          equ 'SWOS'
DEF_MAGIC_LOW           equ 'DEF1'
DEF_VERSION             equ 1
DH_MAGIC                equ $00         ; 8 bytes
DH_VERSION              equ $08         ; word
DH_LENGTH               equ $0A         ; word: the body's length
DH_CRC32                equ $0C         ; long: CRC-32 of the body
DEF_HEADER_SIZE         equ $10

; Body: database identity
DI_KIND                 equ $00         ; word: DBK_*
DI_GENERATION           equ $02         ; word: manifest generation
DI_MANIFEST_CRC         equ $04         ; long: manifest CRC-32
DI_LABEL                equ $08         ; 16 bytes: set label, NUL padded
DI_CUSTOM_CRC           equ $18         ; long: custom set CRC-32
DI_FLAGS                equ $1C         ; word: DBF_*
DI_RESERVED             equ $1E
DI_LABEL_SIZE           equ 16
DIK_ORIGINAL            equ 0
DIK_EDITED              equ 1
DIF_CUSTOM_CRC          equ 0           ; bit: DI_CUSTOM_CRC holds a value

; Body: rules
DR_FAMILY               equ $20         ; word: FAMILY_*
DR_NAME                 equ $22         ; 0-24 characters, NUL padded
DR_NAME_FIELD           equ 26
DR_NAME_MAX             equ 24
DR_PITCH_MODE           equ $3C         ; word 0-1
DR_PITCH_TYPE           equ $3E         ; signed word -1..6
DR_START                equ $40         ; byte: eighth months
DR_END                  equ $41
DR_TEAMS                equ $42         ; word
DR_SUBS                 equ $44         ; word: substitutes that may be used
DR_BENCH                equ $46         ; word: bench size
DR_RULES                equ $48         ; family rules
DR_RULES_END            equ $C8
DR_L_REPEAT             equ $48         ; league
DR_L_POINTS             equ $4A
DR_L_END                equ $4C
DR_C_ROUNDS             equ $48         ; cup
DR_C_AWAY               equ $4A
DR_C_LEGS               equ $4C         ; six words each
DR_C_EXTRA              equ $58
DR_C_PENALTIES          equ $64
DR_C_END                equ $70
DR_T_AWAY               equ $48         ; tournament
DR_T_STAGES             equ $4A
DR_T_STAGE              equ $4C         ; MAX_STAGES records
DR_T_END                equ DR_T_STAGE+MAX_STAGES*DS_SIZE
; Stage record (words)
DS_TEAMS                equ 0           ; teams entering
DS_THROUGH              equ 2           ; teams going through
DS_GROUPS               equ 4           ; 0 knockout, 1-8 groups
DS_GROUP_TEAMS          equ 6           ; teams per group (knockout: entering)
DS_SEEDED               equ 8
DS_REPEAT               equ 10
DS_POINTS               equ 12
DS_LEGS                 equ 14
DS_EXTRA                equ 16
DS_PENALTIES            equ 18
DS_SIZE                 equ 20

; Body: participants and tactics
DR_TEAM_COUNT           equ $C8         ; word: 0 or the competition's teams
DR_TACTIC_MASK          equ $CA         ; word: bit n = USER A+n
DEF_BODY_FIXED          equ $CC
DP_GROUP                equ 0           ; participant: team key, group
DP_ORDINAL              equ 1           ; team key, ordinal
DP_SOURCE               equ 2           ; DPS_*
DP_CONTROL              equ 3           ; CONTROL_* (team.i)
DP_NAME                 equ 4           ; team name, NUL padded
DP_NAME_SIZE            equ 17
DP_SIZE                 equ 24
DPS_DATABASE            equ 0
DPS_CUSTOM_SET          equ 1
DEF_TACTIC_MASK_ALL     equ (1<<USER_TACTIC_SLOTS)-1
DEF_BODY_MAX            equ DEF_BODY_FIXED+TEAM_SELECTION_MAX*DP_SIZE+USER_TACTIC_SLOTS*TACTIC_SIZE
DEF_FILE_MIN            equ DEF_HEADER_SIZE+DEF_BODY_FIXED
DEF_FILE_MAX            equ DEF_HEADER_SIZE+DEF_BODY_MAX
; A file name: up to DEF_BASE_MAX characters and the suffix.
DEF_BASE_MAX            equ 8

; ---------------------------------------------------------------------------
; Families and their native limits
; ---------------------------------------------------------------------------
FAMILY_LEAGUE           equ 0
FAMILY_CUP              equ 1
FAMILY_TOURNAMENT       equ 2
FAMILY_COUNT            equ 3
LEAGUE_TEAMS_MIN        equ 2           ; $1B238E
LEAGUE_TEAMS_MAX        equ 24
LEAGUE_REPEAT_MAX       equ 10          ; $1B23BA
CUP_ROUNDS_MAX          equ 6           ; $1B3E2A
TOURNAMENT_TEAMS_MAX    equ 64          ; $1B6AFA
TOURNAMENT_REFUSED_A    equ 58          ; refused by $1B6C02
TOURNAMENT_REFUSED_B    equ 62
MAX_STAGES              equ 6           ; $1B6B84
MAX_GROUPS              equ 8           ; $1B6C5E
MAX_GROUP_TEAMS         equ 24          ; $1B6C84
STAGE5_KNOCKOUT_MAX     equ 48          ; $1B6C56
STAGE_REPEAT_MAX        equ 4           ; $1B64FC
STAGE_DATES_MAX         equ 90          ; date bytes of a stage slot (+$1C..+$75)
BENCH_MAX               equ 5           ; $1B245C
RULE_ENUM_MAX           equ 2           ; away goals, extra time, penalties: 0-2
PITCH_TYPE_MAX          equ 6
SEASON_UNITS            equ 96          ; eighth months of a year
CUSTOM_KEY_GROUP        equ ORIGINAL_CUSTOM_GROUP ; keys of custom teams

; Family record (definition_family_info, editors/definition.s)
FI_SCRATCH              equ 0           ; long: setup state
FI_CHOOSE               equ 4           ; long: native CHOOSE TEAMS action
FI_SUBS                 equ 8           ; word: offset of the usable substitutes
FI_BENCH                equ 10          ; word: offset of the bench size
FI_SIZE                 equ 12

; ---------------------------------------------------------------------------
; The setup state of the DIY pages (scratch)
; ---------------------------------------------------------------------------
SS_NAME                 equ $04         ; 36-byte name field
SS_TEAMS                equ $32
SS_PITCH_MODE           equ $34
SS_PITCH_TYPE           equ $36
SS_START                equ $38
SS_END                  equ $39
SS_L_REPEAT             equ $5E         ; league
SS_L_POINTS             equ $62
SS_L_SUBS               equ $64
SS_L_BENCH              equ $66
SS_C_ROUNDS             equ $5A         ; cup
SS_C_AWAY               equ $5E
SS_C_SUBS               equ $60
SS_C_BENCH              equ $62
SS_C_LEGS               equ $66         ; six words each
SS_C_EXTRA              equ $72
SS_C_PENALTIES          equ $7E
SS_T_AWAY               equ $4A         ; tournament
SS_T_SUBS               equ $4C
SS_T_BENCH              equ $4E
SS_T_STAGES             equ $52
SS_T_CURRENT            equ $54
SS_T_SLOT               equ $15A        ; six stage slots
SS_T_SLOT_SIZE          equ $76
SL_STATE                equ $00         ; stage slot fields
SL_THIRD_PLACE          equ $02
SL_SHAPE                equ $04         ; 0 knockout, else the group count
SL_SEEDED               equ $06
SL_TEAMS                equ $08
SL_THROUGH              equ $0A
SL_REPEAT               equ $0C
SL_POINTS               equ $0E
SL_GROUPS               equ $10
SL_GROUP_TEAMS          equ $12
SL_LEGS                 equ $14
SL_EXTRA                equ $16
SL_PENALTIES            equ $18
; A stage slot after the last stage holds the terminal marker of the
; native defaults ($1A9C42): one team in, one through, one group of one.
SL_MARKER               equ 1
SL_DEFAULT_RULE         equ 1           ; seeded 0, repeat, legs, extra time, penalties
SL_DEFAULT_POINTS       equ 2

; ---------------------------------------------------------------------------
; Results of definition_check (editors/definition.s): D0.l, details D1-D3.
; The order and the texts are those of tools/definition_data.py.
; ---------------------------------------------------------------------------
DC_OK                   equ 0
DC_SIZE                 equ 1
DC_MAGIC                equ 2
DC_VERSION              equ 3           ; D1 version
DC_LENGTH               equ 4
DC_CRC                  equ 5
DC_BODY                 equ 6
DC_IDENTITY             equ 7
DC_FAMILY               equ 8           ; D1 family
DC_NAME                 equ 9
DC_PITCH                equ 10
DC_MONTHS               equ 11
DC_BENCH                equ 12          ; D1 bench
DC_SUBS                 equ 13          ; D1 usable, D2 bench
DC_TEAMS                equ 14          ; D1 family, D2 teams
DC_REPEAT               equ 15          ; D1 repetitions
DC_POINTS               equ 16          ; D1 points
DC_ROUNDS               equ 17          ; D1 rounds
DC_CUP_TEAMS            equ 18          ; D1 rounds, D2 teams
DC_AWAY                 equ 19
DC_LEGS                 equ 20          ; D1 DCK_*, D2 round or stage
DC_EXTRA                equ 21
DC_PENALTIES            equ 22
DC_STAGES               equ 23          ; D1 stages
DC_CHAIN                equ 24          ; D1 stage, D2 entering, D3 expected
DC_NATIVE_TEAMS         equ 25          ; D1 stage, D2 entering
DC_THROUGH              equ 26          ; D1 stage, D2 through, D3 entering
DC_FINAL_EARLY          equ 27          ; D1 stage
DC_FINAL                equ 28          ; D1 through
DC_KNOCKOUT             equ 29          ; D1 stage, D2 entering
DC_GROUPS               equ 30          ; D1 stage, D2 groups, D3 teams per group
DC_SEEDED               equ 31          ; D1 stage
DC_STAGE_REPEAT         equ 32          ; D1 stage, D2 repetitions
DC_STAGE_POINTS         equ 33          ; D1 stage, D2 points
DC_DATES                equ 34          ; D1 stage, D2 dates
DC_UNUSED_STAGE         equ 35          ; D1 stage
DC_RESERVED             equ 36
DC_TEAM_COUNT           equ 37          ; D1 listed, D2 teams
DC_TEAM_ENTRY           equ 38          ; D1 team (1-based)
DC_TEAM_GROUP           equ 39          ; D1 team, D2 group
DC_TEAM_TWICE           equ 40          ; D1 team
DC_TACTIC_MASK          equ 41
DC_TACTIC               equ 42          ; D1 slot; the tactic's own result kept
DC_LAST                 equ DC_TACTIC
DCK_ROUND               equ 0
DCK_STAGE               equ 1

; The TEAM.ggg files of disk 2 [cr HF], one bit per group 0-95 (bit 7 of
; the first byte is group 0); the build checks the map against the disk.
TEAM_GROUP_MAP          macro
        dc.b    %11111111,%10111111,%11111111,%11111111   ; 0-31
        dc.b    %11111111,%11111110,%11110001,%00001010   ; 32-63
        dc.b    %11110101,%11011111,%11111100,%00000000   ; 64-95
        endm
TEAM_GROUP_MAP_SIZE     equ 12

        endif
