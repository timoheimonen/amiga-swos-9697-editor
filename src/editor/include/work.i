; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Working data of the resident editor: offsets from the editor base, inside
; the WORKING_DATA_MAX_SIZE bytes at WORK_DATA_OFFSET (see layout.i).
; editor_init clears everything after the CRC-32 table, which the slave has
; already built. Include after layout.i.

        include "team.i"
        include "tactic.i"
        include "definition.i"
        include "database.i"
        include "matchlog.i"

WORK_CLEAR_START        equ WORK_CRC_TABLE+WORK_CRC_TABLE_SIZE

; Extended native pages: each native template copied from the game,
; followed by the editor's entries (resident/menus.s).
WORK_MAIN_MENU          equ WORK_CLEAR_START
WORK_MAIN_MENU_SIZE     equ 640
WORK_TEAM_EDITOR        equ WORK_MAIN_MENU+WORK_MAIN_MENU_SIZE
WORK_TEAM_EDITOR_SIZE   equ 2560
WORK_DIY_LEAGUE         equ WORK_TEAM_EDITOR+WORK_TEAM_EDITOR_SIZE
WORK_DIY_LEAGUE_SIZE    equ 768
WORK_DIY_CUP            equ WORK_DIY_LEAGUE+WORK_DIY_LEAGUE_SIZE
WORK_DIY_CUP_SIZE       equ 1536
WORK_DIY_TOURNAMENT     equ WORK_DIY_CUP+WORK_DIY_CUP_SIZE
WORK_DIY_TOURNAMENT_SIZE equ 2560
WORK_DIY_TYPE           equ WORK_DIY_TOURNAMENT+WORK_DIY_TOURNAMENT_SIZE
WORK_DIY_TYPE_SIZE      equ 256

; Storage: the I/O buffer of the editors.
WORK_IO_BUFFER          equ WORK_DIY_TYPE+WORK_DIY_TYPE_SIZE
WORK_IO_BUFFER_SIZE     equ STORAGE_CHUNK

; Dialog service state (resident/dialog.s).
WORK_DIALOG             equ WORK_IO_BUFFER+WORK_IO_BUFFER_SIZE
DLG_DESCRIPTOR          equ 0           ; long
DLG_DISABLED            equ 4           ; long: mask
DLG_FOCUS               equ 8           ; word: focused button, -1 none
DLG_COUNT               equ 10          ; word
DLG_TARGET              equ 12          ; UI_TARGET_BYTES
DLG_COMMANDS            equ 24          ; scratch command list, 96 bytes
DLG_PAINT_ARG           equ 120         ; long
DLG_STATES              equ 124         ; DIALOG_MAX_BUTTONS words
DLG_LABELS              equ 188         ; DIALOG_MAX_BUTTONS longs
DLG_BATCH               equ 316         ; word: 1 while paints are kept
DLG_QUEUED              equ 318         ; word: paints kept
DLG_QUEUE               equ 320         ; DLG_QUEUE_MAX (routine, argument) longs
DLG_QUEUE_MAX           equ 16
DLG_SIZE                equ DLG_QUEUE+DLG_QUEUE_MAX*8

; Own screen host (resident/screen.s).
WORK_SCREEN             equ WORK_DIALOG+DLG_SIZE
SCR_RECORD              equ 0           ; long: screen record running
SCR_OPENED              equ 4           ; word: 1 after its open routine ran
SCR_SIZE                equ 8

; Database mode (editors/database.s, dbgroup.s, dbstore.s, dbcups.s,
; resident/copies.s): the switch, the binding of the competition family,
; the set in the save directory, the working group's state (the group
; itself is at GROUP_WORK_OFFSET), the source of a copy, the state and
; texts of the screens, the manifests (DBASE.CFG as read or written, the
; switch's verified set, the set the competition family is bound to and the
; one being written), the start check of the remembered switch and the
; European cups' 96/97 participant lists.
WORK_DB                 equ WORK_SCREEN+SCR_SIZE
DB_SWITCH               equ 0           ; word: 1 while USE EDITED DATABASE is on
DB_BIND                 equ 2           ; word: 1 while the family is bound to DB_BOUND
DB_SET_STATE            equ 4           ; word: DSS_*
DB_SET_PROBLEM          equ 6           ; word: MC_* of a damaged DBASE.CFG
DB_SET_DETAIL           equ 8           ; word: its detail
DB_GROUP                equ 10          ; word: group in the working group, -1 none
DB_DIRTY                equ 12          ; word: the working group differs from its file
DB_COUNT                equ 14          ; word: teams in the working group
DB_MODE                 equ 16          ; word: DBM_* of the open screen
DB_STEP                 equ 18          ; word: the question or message open
DB_PAGE                 equ 20          ; word: first group row shown
DB_CLUB                 equ 22          ; word: chosen club, -1 none
DB_PICK                 equ 24          ; word: PICK_*: what the next row choice does
DB_NEXT                 equ 26          ; word: DBS_*: the screen the frontend runs next
DB_COPY_GROUP           equ 28          ; word: the group of DB_COPY_RECORD
DB_SCREEN               equ 30          ; word: DBS_* running
DB_SECOND               equ 32          ; word: the second club of a pick
DB_CLUB_PAGE            equ 34          ; word: first club row shown
DB_LABEL_CHANGED        equ 36          ; word: DB_LABEL differs from the set's label
DB_LABEL                equ 38          ; 18 bytes: the label written with the next SAVE
DB_FIELD                equ 56          ; 40 bytes: the label field's text
DB_TITLE                equ 96          ; 48 bytes
DB_STATUS               equ 144         ; 56 bytes: status line
DB_INFO                 equ 200         ; 56 bytes: the set line
DB_INFO2                equ 256         ; 56 bytes: what new competitions use
DB_CAPTION              equ 312         ; 40 bytes: the main-menu caption
DB_NAME                 equ 352         ; 16 bytes: a file name being built
DB_ROW_SIZE             equ 24
DB_ROW_COUNT            equ 24
DB_ROWS                 equ 368         ; DB_ROW_COUNT row labels
DB_COPY_RECORD          equ DB_ROWS+DB_ROW_COUNT*DB_ROW_SIZE ; TEAM_SIZE bytes
DB_SET                  equ DB_COPY_RECORD+TEAM_SIZE ; MANIFEST_MAX bytes each
DB_ACTIVE               equ DB_SET+MANIFEST_MAX
DB_BOUND                equ DB_ACTIVE+MANIFEST_MAX
DB_NEW                  equ DB_BOUND+MANIFEST_MAX
DB_START                equ DB_NEW+MANIFEST_MAX ; word: the start check has run
DB_START_PROBLEM        equ DB_START+2  ; word: MC_* or GC_* of a failed start check, 0 none
DB_START_DETAIL         equ DB_START+4  ; word: its group
DB_START_NOTED          equ DB_START+6  ; word: EDIT DATABASE has explained it
DB_START_NAME           equ DB_START+8  ; 16 bytes: the file it names
DB_COPY_NAME            equ DB_START+24 ; 16 bytes: the file name of a copy or a group read by
                                        ; resident/copies.s and gateway.s
DB_CUP                  equ DB_START+40 ; word: the cup the cups screen shows
DB_CUP_KEYS             equ DB_START+42 ; CUP_KEYS words: the 96/97 participant lists
DB_CUP_ROW_SIZE         equ 24
DB_CUP_ROWS             equ DB_CUP_KEYS+CUP_KEYS*2 ; CUP_MAX_TEAMS row labels
DB_SIZE                 equ DB_CUP_ROWS+CUP_MAX_TEAMS*DB_CUP_ROW_SIZE
DBM_MAIN                equ 0           ; the screen's own dialog
DBM_TYPING              equ 1           ; the keyboard field takes the keys
DBM_MESSAGE             equ 2           ; a message is open
DBM_ASK                 equ 3           ; a YES/NO question is open
DBS_EXIT                equ 0           ; DB_NEXT and DB_SCREEN
DBS_MAIN                equ 1
DBS_GROUP               equ 2
DBS_TEAM                equ 3
DBS_CUPS                equ 4
PICK_NONE               equ 0           ; DB_PICK
PICK_SWAP               equ 1           ; the second club of a division swap
PICK_EXCHANGE           equ 2           ; the second club of an exchange
PICK_COPY_COUNTRY       equ 3           ; the destination group of a copy
PICK_COPY_SLOT          equ 4           ; the destination club of a copy

; Team editor (editors/team.s, settings.s, player.s, customs.s): the
; custom set's fingerprint, the IMPORT baseline, the player clipboard and
; the baseline of the open team screen, which CANCEL restores.
WORK_TEAM               equ WORK_DB+DB_SIZE
TE_SET_CRC              equ 0           ; long: CRC-32 of the set as last loaded or saved
TE_SET_KNOWN            equ 4           ; word: 1 when TE_SET_CRC holds a value
TE_ROW                  equ 6           ; word: physical slot shown on the player screen
TE_CAPTION              equ 8           ; caption of the team page, 20 bytes
TE_CAPTION_SIZE         equ 20
TE_IMPORT_VALID         equ 28          ; word: TE_IMPORT_BASE holds the last IMPORT
TE_CLIP_VALID           equ 30          ; word: the clipboard holds a player
TE_CLIP                 equ 32          ; PLAYER_SIZE bytes, then a pad word
TE_IMPORT_BASE          equ 72          ; TEAM_SIZE bytes: working copy after IMPORT
TE_SCREEN_BASE          equ TE_IMPORT_BASE+TEAM_SIZE ; working copy when a screen opened
TE_SIZE                 equ TE_SCREEN_BASE+TEAM_SIZE

; State of the open team screen (SETTINGS or PLAYER; never both).
WORK_TEAM_SCREEN        equ WORK_TEAM+TE_SIZE
TS_MODE                 equ 0           ; word: TSM_*
TS_CHOICE               equ 2           ; word: first chosen row, -1 none
TS_SWAP                 equ 4           ; word: 0 swap places, 1 swap numbers
TS_PENDING              equ 6           ; word: change waiting for a confirmation
TS_PENDING_VALUE        equ 8           ; word
TS_SIDE_VALID           equ 10          ; word: TS_SIDE_* hold the other representation
TS_SIDE_SKILLS          equ 12          ; long: skills before a goalkeeper conversion
TS_SIDE_RATING          equ 16          ; word: rating before it
TS_NAME                 equ 18          ; 24 bytes: the name being typed
TS_TITLE                equ 42          ; 40 bytes: dialog title
TS_STATUS               equ 82          ; 56 bytes: status line
TS_DERIVED              equ 138         ; 56 bytes: derived values line
TS_VALUE                equ 194         ; 24 bytes: native price text
TS_SCRATCH              equ 218         ; 56 bytes: a message line being built
TS_STRENGTH             equ 274         ; 56 bytes: the strength line of TEAM SETTINGS
TS_LABELS               equ 330         ; TS_LABEL_COUNT labels of TS_LABEL_SIZE bytes
TS_LABEL_SIZE           equ 56
TS_LABEL_COUNT          equ 18
TS_SIZE                 equ TS_LABELS+TS_LABEL_COUNT*TS_LABEL_SIZE
TSM_MAIN                equ 0           ; the screen's own dialog
TSM_TYPING              equ 1           ; the keyboard field takes the keys
TSM_CONFIRM             equ 2           ; a YES/NO question is open
TSM_MESSAGE             equ 3           ; a message is open

; Messages and questions (editors/message.s).
WORK_MESSAGE            equ WORK_TEAM_SCREEN+TS_SIZE
MSG_TITLE               equ 0           ; 40 bytes
MSG_LINES               equ 40          ; MSG_LINE_COUNT lines of MSG_LINE_SIZE bytes
MSG_LINE_SIZE           equ 52
MSG_LINE_COUNT          equ 4
MSG_ANSWER              equ MSG_LINES+MSG_LINE_COUNT*MSG_LINE_SIZE ; word
MSG_KIND                equ MSG_ANSWER+2 ; word: MSG_OK or MSG_ASK
MSG_SIZE                equ MSG_KIND+2
MSG_OK                  equ 0           ; one button: OK
MSG_ASK                 equ 1           ; YES and NO; NO is focused first
MSG_NO                  equ 0           ; answers
MSG_YES                 equ 1

; Keyboard field of the own screens (editors/field.s).
WORK_FIELD              equ WORK_MESSAGE+MSG_SIZE
FLD_TEXT                equ 0           ; long: the buffer being typed into
FLD_CAPACITY            equ 4           ; word: characters without the NUL
FLD_BACKUP              equ 6           ; FLD_BACKUP_SIZE bytes: text before typing
FLD_BACKUP_SIZE         equ 40
FLD_SIZE                equ FLD_BACKUP+FLD_BACKUP_SIZE
FIELD_TYPING            equ 0           ; field_key results
FIELD_KEPT              equ 1
FIELD_CANCELLED         equ -1

; Tactics (editors/tactics.s): the user-owned slots of the user tactics
; and a copy of each, the result of the last tactic check and a line of
; text for its messages.
WORK_TACTICS            equ WORK_FIELD+FLD_SIZE
TT_OWNED                equ 0           ; word: bit n set while USER A+n is user-owned
TT_CHECK                equ 2           ; word: TC_* of the last check
TT_DETAIL               equ 4           ; three longs: its D1-D3
TT_LINE                 equ 16          ; TT_LINE_SIZE bytes: a message line
TT_LINE_SIZE            equ 56
TT_COPIES               equ TT_LINE+TT_LINE_SIZE ; USER_TACTIC_SLOTS records
TT_SIZE                 equ TT_COPIES+USER_TACTIC_SLOTS*TACTIC_SIZE

; Tournament definitions (editors/definition.s, rules.s, defsave.s,
; defload.s): the rules and teams held for the DIY setup pages, the
; sources of the custom teams the chooser added, the last check and the
; texts of the screens. DF_BODY and DF_LIST together are a definition body
; without tactics. SAVE DEFINITION keeps the teams held when it opened
; (DF_HELD_*) for CANCEL, and the name and length of the backup it wrote.
WORK_DEF                equ WORK_TACTICS+TT_SIZE
DF_STATE                equ 0           ; word: DFS_* bits
DF_FAMILY               equ 2           ; word: family of the rules and teams held
DF_TEAMS                equ 4           ; word: participants in DF_LIST
DF_CHECK                equ 6           ; word: DC_* of the last check
DF_TACTIC               equ 8           ; word: TC_* of a tactic in a definition
DF_TACTIC_DETAIL        equ 10          ; three longs
DF_MODE                 equ 22          ; word: mode of the open screen (DFM_*)
DF_STEP                 equ 24          ; word: step of a load or save
DF_ROW                  equ 26          ; word: chosen list row or button
DF_PAGE                 equ 28          ; word: first list record shown
DF_COUNT                equ 30          ; word: definitions listed
DF_RESULT               equ 32          ; word: result of a screen for its action
DF_SAVED_CRC            equ 34          ; long: CRC-32 of the body last written or read
DF_CUSTOM               equ 38          ; TEAM_SELECTION_MAX bytes: DPS_* of custom team n
DF_FILE                 equ DF_CUSTOM+TEAM_SELECTION_MAX ; 32 bytes: file name
DF_BASE                 equ DF_FILE+FS_RECORD_SIZE ; 12 bytes: base name typed
DF_TITLE                equ DF_BASE+12  ; 48 bytes
DF_STATUS               equ DF_TITLE+48 ; 56 bytes
DF_LINE_SIZE            equ 52
DF_LINE_COUNT           equ 20
DF_LINES                equ DF_STATUS+56 ; DF_LINE_COUNT lines
DF_BODY                 equ DF_LINES+DF_LINE_COUNT*DF_LINE_SIZE ; DEF_BODY_FIXED bytes
DF_LIST                 equ DF_BODY+DEF_BODY_FIXED ; TEAM_SELECTION_MAX participants
DF_HELD_FAMILY          equ DF_LIST+TEAM_SELECTION_MAX*DP_SIZE ; word
DF_HELD_TEAMS           equ DF_HELD_FAMILY+2 ; word
DF_HELD_LIST            equ DF_HELD_TEAMS+2 ; TEAM_SELECTION_MAX participants
DF_PREVIOUS             equ DF_HELD_LIST+TEAM_SELECTION_MAX*DP_SIZE ; long: length of the backed-up file
DF_BACKUP               equ DF_PREVIOUS+4 ; FS_RECORD_SIZE bytes: the backup's name
DF_SIZE                 equ DF_BACKUP+FS_RECORD_SIZE
DFS_APPLY               equ 0           ; bit: the rules wait for the page's init
DFS_ARMED               equ 1           ; bit: CHOOSE TEAMS takes the teams held
DFS_LOADED              equ 2           ; bit: a definition was loaded (type page)
DFM_MAIN                equ 0           ; the screen's own dialog
DFM_TYPING              equ 1           ; the keyboard field takes the keys
DFM_MESSAGE             equ 2           ; a message is open
DFM_ASK                 equ 3           ; a YES/NO question is open

; Explained refusals (editors/boundary.s): whether the note about the
; foreign player market was shown since the competition family started or
; was loaded.
WORK_BOUNDARY           equ WORK_DEF+DF_SIZE
BD_MARKET_NOTED         equ 0           ; word
BD_SIZE                 equ 2

; The match log (editors/matchlog.s): the install's identity and name, the
; next sequence number, the note after a failed append and the record of
; the match that just ended.
WORK_MATCHLOG           equ WORK_BOUNDARY+BD_SIZE
ML_STATE                equ 0           ; word: 1 after matchlog_start
ML_FORFEIT              equ 2           ; word: the match was left with Esc
ML_NOTE                 equ 4           ; word: the note is due
ML_MACHINE_OK           equ 6           ; word: MACHINE.CFG holds ML_INSTALL
ML_NOTE_RESULT          equ 8           ; long: result of the failed append
ML_INSTALL              equ 12          ; long: install identity, 0 none yet
ML_SEQUENCE             equ 16          ; long: next sequence number
ML_APPENDS              equ 20          ; long: records appended this session
ML_LAST_RESULT          equ 24          ; long: result of the last append
ML_NAME                 equ 28          ; MID_NAME_SIZE bytes: machine name
ML_TEXT                 equ 44          ; 56 bytes: the note's reason line
ML_LOG_LENGTH           equ 100         ; long: the log's length after the
                                        ; last sound append (or as read at the
                                        ; start); the next record goes there
ML_RECORD               equ 104         ; MR_MAX_SIZE bytes
ML_SIZE                 equ ML_RECORD+((MR_MAX_SIZE+3)&-4)

WORK_USED_END           equ WORK_MATCHLOG+ML_SIZE

        if WORK_USED_END>WORK_DATA_OFFSET+WORKING_DATA_MAX_SIZE
        fail "working data exceeds WORKING_DATA_MAX_SIZE"
        endif
