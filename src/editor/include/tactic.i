; SWOS 96-97 In-Game Editors V0.91b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Tactic records: TACTIC_SIZE bytes (swos2.i), the same in the six user
; slots, the twelve builtins, the editor's working tactic and a .TAC file.
; A map holds one packed position (x << 4 | y) per ball zone for one
; outfield role; map n belongs to lineup role n + TACTIC_FIRST_ROLE (role 1
; keeps goal and has no map). Ball zone = row * 5 + column (five columns,
; seven rows). Include after swos2.i.

        ifnd    TACTIC_MAPS
TACTIC_NAME             equ $000        ; up to 8 characters and NUL
TACTIC_MAPS             equ $009        ; TACTIC_ROLES maps of TACTIC_ZONES bytes
TACTIC_PAIRS            equ $167        ; mirror pair label per map
TACTIC_BASE             equ $171        ; base formation: builtin 0-11
TACTIC_ROLES            equ 10
TACTIC_ZONES            equ 35
TACTIC_FIRST_ROLE       equ 2
TACTIC_X_MAX            equ 14          ; x 0-14 (four bits could hold 15)
TACTIC_PAIR_LABELS      equ 5           ; labels 0-4, each on exactly two maps
TACTIC_UNPAIRED         equ $FF
TACTIC_BODY_SIZE        equ TACTIC_SIZE-TACTIC_NAME_SIZE ; 361

; Results of tactic_check (editors/tactics.s), D0.l; details in D1-D3.
TC_OK                   equ 0
TC_SIZE                 equ 1           ; a .TAC file: D1.l = its length
TC_NAME                 equ 2           ; no NUL in the name field
TC_RANGE                equ 3           ; D1 = map, D2 = zone, D3 = x
TC_SHARED               equ 4           ; D1 < D2 = maps on one spot, D3 = zone
TC_LABEL                equ 5           ; D1 = map, D2 = its label
TC_PAIR                 equ 6           ; D1 = label, D2 = maps using it
TC_BASE                 equ 7           ; D1 = base formation
TC_LAST                 equ TC_BASE
        endif
