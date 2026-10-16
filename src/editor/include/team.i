; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Team and player records of the native team groups and the custom set
; (CUSTOMS.EDT): a team is TEAM_SIZE bytes, a TEAM_HEADER_SIZE-byte header
; followed by PLAYER_COUNT players of PLAYER_SIZE bytes in physical slot
; order. A counted group or set is a BE16 count followed by the teams.
; Bytes that are not named here are kept as they are.

        ifnd    TEAM_SIZE

TEAM_SIZE               equ $2AC
TEAM_WORDS              equ TEAM_SIZE/2
TEAM_HEADER_SIZE        equ $4C
PLAYER_SIZE             equ $26
PLAYER_COUNT            equ 16
GROUP_COUNT_SIZE        equ 2

; Team header
TEAM_KEY                equ $00         ; word: group and ordinal, kept
TEAM_IDENTITY_SIZE      equ 4           ; key and secondary index: a slot's identity
TEAM_CONTROL            equ $04         ; byte, in a selected team only: CONTROL_*
TEAM_NAME               equ $05         ; 16 characters and NUL
TEAM_NAME_SIZE          equ 17
TEAM_TACTIC             equ $18         ; byte: builtin 0-11, user slot 12-17
TEAM_DIVISION           equ $19         ; byte, kept
TEAM_HOME_KIT           equ $1A         ; pattern, shirt, second shirt, shorts, socks
TEAM_AWAY_KIT           equ $1F
TEAM_COACH              equ $24         ; 22 characters and NUL
TEAM_COACH_SIZE         equ 23
TEAM_LINEUP             equ $3C         ; 16 physical slots; role 0 keeps goal
TEAM_PLAYERS            equ TEAM_HEADER_SIZE
; Control of a selected team (team chooser legend $1B11BC)
CONTROL_COMPUTER        equ 1
CONTROL_PLAYER_COACH    equ 2
CONTROL_COACH           equ 3
KIT_SIZE                equ 5
KIT_PATTERNS            equ 4           ; pattern 0-3
KIT_COLOURS             equ 10          ; colour 0-9
STARTING_ROLES          equ 11          ; lineup roles 0-10 start the match

; Player
PLAYER_NATIONALITY      equ $00         ; byte 0-152
PLAYER_RATING_CACHE     equ $01         ; byte, kept
PLAYER_SHIRT            equ $02         ; byte 1-16, unique in the squad
PLAYER_NAME             equ $03         ; 22 characters and NUL
PLAYER_NAME_SIZE        equ 23
PLAYER_FLAGS            equ $1A         ; position 7-5, appearance 4-3, low flags 2-0
PLAYER_STATUS           equ $1B         ; discipline and injury, kept
PLAYER_SKILLS           equ $1C         ; long: prefix nibble, then seven skills
PLAYER_RATING           equ $20         ; outfield: sum of the skills; keeper: own
PLAYER_GOALS            equ $21         ; four goal counters, kept
PLAYER_FORM             equ $25         ; performance and sentinels, kept

POSITION_SHIFT          equ 5
POSITION_MASK           equ $E0
POSITION_KEEPER         equ 0
POSITION_COUNT          equ 8
APPEARANCE_SHIFT        equ 3
APPEARANCE_MASK         equ $18
APPEARANCE_COUNT        equ 3           ; 0-2 (3 is not a native appearance)
LOW_FLAGS_MASK          equ $07

; Skills: the long at PLAYER_SKILLS holds eight nibbles; the first is a
; prefix (kept), then passing, shooting, heading, tackling, ball control,
; speed and finishing. Each skill nibble holds the rating 0-7 in its low
; three bits and the specialty flag in bit 3.
SKILL_COUNT             equ 7
SKILL_MAX               equ 7
SKILL_SPECIALTY         equ 8
SKILL_BITS_MASK         equ $0FFFFFFF   ; the seven skills without the prefix
OUTFIELD_RATING_MAX     equ SKILL_COUNT*SKILL_MAX
; A keeper's rating is independent; 0-38 always gives a match ability of
; 0-7. Ratings 39 and 40 of the original data are kept while unchanged.
KEEPER_RATING_MAX       equ 38
KEEPER_RATING_KEPT_MAX  equ 40

; Text that the game's own font displays and its text entry accepts
; (menu_edit_text $1A0F02: A-Z, 0-9 and the punctuation table at $1A0F4C).
NAME_GLYPHS             macro
        dc.b    'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -/.',0
        endm
        endif
