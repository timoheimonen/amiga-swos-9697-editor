; SWOS 96-97 In-Game Editors V0.9b
; Copyright (c) 2026 Timo Heimonen <timo.heimonen@proton.me>
; Licensed under the MIT License. See the LICENSE file for details.
;
; Addresses in the game executable SWOS2 (SWOS VERSION 152) of Sensible World
; of Soccer '96-'97, as relocated by SSBOOT on an A1200 with 2 MiB Chip RAM and
; no Fast RAM: the image is assembled for $100000 and runs at $180000. Every
; address the editor uses is named here; the comment after it gives the
; register contract and the code that shows it. Addresses below $180000 are
; Chip RAM globals of the game.

; ---------------------------------------------------------------------------
; Executable image and relocation
; ---------------------------------------------------------------------------
SWOS2_BASE              equ $180000     ; runtime base; entry JMP $1800C4
SWOS2_ASSEMBLY_BASE     equ $100000     ; base the shipped image is assembled for
SWOS2_IMAGE_END         equ $1D736A     ; end of the 357,226-byte unpacked image
; SSBOOT relocates by adding this value to single bytes named by SWOS2.REL
; (byte offsets, no carry into the neighbouring byte).
SWOS2_REL_ADDEND        equ ((SWOS2_BASE-SWOS2_ASSEMBLY_BASE)>>16)&$FF
SWOS2_IMAGE_SIZE        equ SWOS2_IMAGE_END-SWOS2_BASE
; SSBOOT enters the image at SWOS2_BASE (JMP $1800C4) in supervisor mode with
; interrupts masked and DMA off, D7 = RAM size, D6 = mask of present 512 KiB
; regions, D5 = mask of Fast regions (SSBOOT $262..$28A). Whenever it selects
; SWOS2 it forces "2 MiB Chip, no Fast" ($1AE..$1E4). The entry stores the
; three values at $1D73D0, $1D73C8 and $1D73CC; cache_initialize then gives
; the region $100000..$17FFFF to the resource cache.
SWOS2_RAM_SIZE          equ $200000
SWOS2_RAM_REGIONS       equ $F
SWOS2_FAST_REGIONS      equ 0

; ---------------------------------------------------------------------------
; Start-up of the front end
; ---------------------------------------------------------------------------
game_frontend_startup   equ $18E6FE     ; one-time front-end start-up
startup_cache_init_call equ $18E78C     ; six-byte JSR cache_initialize
startup_cache_init_return equ $18E792   ; instruction after that JSR
startup_preload_call    equ $18E880     ; six-byte JSR startup_preload_resources
startup_preload_return  equ $18E886     ; instruction after that JSR
; One-time preload of the main-menu resources and its filename table. Called
; only from startup_preload_call; it returns through RTS at $18F870. Its two
; absolute operands at $18F83E and $18F8C6 point inside the routine (to $18F872
; and $18F8CE). The live code at STARTUP_PRELOAD_END is not part of it.
startup_preload_resources equ $18F834
STARTUP_PRELOAD_END     equ $18F8DC
STARTUP_PRELOAD_SIZE    equ STARTUP_PRELOAD_END-startup_preload_resources

; ---------------------------------------------------------------------------
; Native file system (the game's own OFS driver, not dos.library)
; ---------------------------------------------------------------------------
; D7.w = even selector (0 init, 2 read, 4 write, 6 delete, 8 list, $0A format,
; $0C size query, $0E find disk marker, $10 check save disk); D7 is clobbered.
file_operation_dispatch equ $1801AC
; D0.w = disk mode (1 = game disk 1, marker swos4.dk1). Searches the drives for
; the marker and selects that drive; D0.w = 0 on success.
game_find_disk_marker   equ $180438
file_drive_index        equ $180586     ; word: drive selected for file access
file_disk_mode          equ $180588     ; word: current disk mode (4 = save disk)
; A0 = filename, A1 = destination. D0.w = 0 on success, D1 = length. Outside
; save-disk mode a packed (RNC1/RNC2) file is unpacked; a staged file longer
; than FILE_STAGED_MAX_SIZE stops the game through game_diagnostic_handler.
file_load_unpack        equ $18594C
FILE_STAGED_MAX_SIZE    equ $BBB0       ; compared at $18599C (48,048 bytes)
; A0 = filename, A1 = source, D1 = length; writes through selector 4.
file_save_buffer        equ $185B26
; Selector $0C: A0 = filename on the selected drive. D0.w = 0 and D1 = file
; length when it exists (opens and closes a read handle, $18040A..$180436).
file_exists             equ $18040A
; A0 = filename. Copies the selected drive's prefix ("DFn:") and the name to
; file_path_buffer without a bound and returns A0 = file_path_buffer.
file_path_assemble      equ $180528
file_path_buffer        equ $18058E     ; 50 bytes, $18058E..$1805BF
file_scratch_pointer    equ $18055E     ; long: driver scratch area
file_handle_buffer_pointer equ $180562  ; long: 1,024-byte handle buffer
; Lower driver call: D0 = opcode (OFS_*), A0 = drive-prefixed path or
; handle, A1 = buffer, A2 = file_scratch_pointer value, D1 = length.
; Returns D0 (and D1 for OFS_READ, OFS_LIST, OFS_OPEN, OFS_READ_HANDLE);
; every other register is preserved. Opcodes below OFS_CLOSE parse the
; "DFn:" prefix ($180D06). Not reentrant: one operation at a time.
file_driver_call        equ $1805C0
OFS_READ                equ 0           ; whole file to A1, D1 = length read
OFS_WRITE               equ 1           ; D1 bytes from A1, delete first
OFS_DELETE              equ 2
OFS_LIST                equ 3           ; 32-byte entries to A1, D1 = count
OFS_FORMAT              equ 4
OFS_OPEN                equ 5           ; D0 = handle 1/2 or 0, D1 = length
OFS_CLOSE               equ 6           ; A0 = handle
OFS_READ_HANDLE         equ 7           ; A0 = handle, A1 = dest, D1 = max
OFS_SEEK                equ 8           ; A0 = handle, D1 = position
FILE_PATH_BUFFER_SIZE   equ 50
; Stops the game with the diagnostic code in word $D656 (menu construction
; uses $9091-$9093, the staged loader $E000).
game_diagnostic_handler equ $182464

; Lower layers of the file system ($1805C0 and below).
; Selector $10: checks that the disk in DF0 carries no game-disk marker
; before FORMAT SAVE DISK; on acceptance DF0 and mode 4 stay selected
; ($1804AC..$180522, D0.w = 0 or -100).
file_format_check       equ $1804AC
file_drive_slots        equ $180566     ; 4 longs: "DFn:" string per present drive, else 0
file_mode_drive_cache   equ $18058A     ; 4 bytes: last drive found per disk mode 1-4
; Two 18-byte read-handle records, for handles 1 and 2 ($18065E..$1806A2):
; +0 drive word, +6 position, +$0A buffer (0 = free), +$0E file length.
file_handle_records     equ $180E04
FILE_HANDLE_RECORD_SIZE equ 18
FHR_DRIVE               equ $00
FHR_POSITION            equ $06
FHR_BUFFER              equ $0A
FHR_LENGTH              equ $0E
file_current_drive      equ $180E32     ; word: drive of the operation in progress
; Physical disk layer, called only from the file system ($180E70, $180228):
; D0.w = drive, D1.w = first sector, D2.w = sector count, D3.w = mode
; (0 read, 1 write, 3 detect drives, other values with D2 = 0 release the
; drive), A0 = data, A1 = scratch. D0.l = 0 or an error ($1C write protected,
; $1D no disk, $1E sector range, $18-$1B decoding); on an error D1.l is the
; sector that failed. Mode 3 returns the bit mask of present drives in D0.
; The routine and its helpers ($180E7E..$1816A7) are the only code that
; touches the drive hardware.
disk_io                 equ $180E7E
DISK_IO_DETECT          equ 3
DISK_SECTORS            equ 1760        ; checked at $180ECA ($6E0)
DISK_SECTOR_SIZE        equ 512

; ---------------------------------------------------------------------------
; Resource cache
; ---------------------------------------------------------------------------
; A block is a $30-byte header followed by its payload. Header: +0 next block,
; +4 word 1 = free, +6 capacity, +$0A file length, +$0E NUL-terminated name.
cache_head              equ $18589C     ; long: first block of the chain
cache_reported_remaining equ $1858A0    ; long: game's own free counter
cache_initialize        equ $18670A     ; builds the chain; called once at start
; D0 = payload size. D0.w = 0 on success with A0 = header; the payload starts
; at A0+CACHE_HEADER_SIZE. First fit; the block stays occupied (no free call).
cache_allocate          equ $1867DE
; A0 = name. Returns A0 = payload and D0 = file length of a cached file.
cache_find_file         equ $18685A
; A0 = filename on the selected disk. Queries the length (selector $0C at
; $186902), allocates a block of that size through cache_allocate and reads the
; whole file into it. D0.w = 0 on success.
cache_read_disk_file    equ $1868F8
CACHE_HEADER_SIZE       equ $30
CACHE_NEXT              equ $00
CACHE_FREE              equ $04
CACHE_CAPACITY          equ $06
CACHE_LENGTH            equ $0A
CACHE_NAME              equ $0E
CACHE_NAME_SIZE         equ CACHE_HEADER_SIZE-CACHE_NAME

; ---------------------------------------------------------------------------
; Display and input of the front end
; ---------------------------------------------------------------------------
; The menu screen is double buffered: drawing goes to the buffer in
; display_draw_buffer; display_wait_present ($185238) asks the interrupt to
; show it and waits, after which the pointers have swapped. Native redraws
; draw and present twice so both buffers hold the result. Each buffer is
; 273 rows of four interleaved 44-byte plane lines (rectangle blits at
; $183BD6 use the row stride $B0). Coordinates are offset by the scroll
; words, which are zero on the menu screens.
display_draw_buffer     equ $2BC90      ; long: buffer drawn into
display_other_buffer    equ $2BC94      ; long: buffer shown
display_wait_present    equ $185238
display_scroll_x        equ $18F118     ; word
display_scroll_y        equ $18F11A     ; word
; Last key translated by keyboard_dequeue_translated ($181CCC) in this tick
; (uppercase ASCII, $0D Return, $1B Escape, $7F Backspace, $10-$13 arrows).
keyboard_translated_key equ $18F112     ; word
; Word incremented by the vertical blank interrupt; file_load_unpack waits
; 50 of its steps between retries ($185A14..$185A2A).
frame_counter           equ $18F10A
; Keyboard interrupt $181B2C: every key event stores its code in
; keyboard_last_raw (bit 7 set on release) and a press arms
; keyboard_repeat_timer ($800C); while the timer word is negative the
; vertical blank interrupt ($181C6E..$181CA2) queues keyboard_last_raw
; again every few fields. A release lost while the operating system ran
; would therefore repeat the key for ever.
keyboard_last_raw       equ $18F111     ; byte
keyboard_repeat_timer   equ $181BBA     ; word, negative while a key repeats

; ---------------------------------------------------------------------------
; Native menus
; ---------------------------------------------------------------------------
menu_current_template   equ $19FBCC     ; long: compact template now installed
; A0 = compact template, A1 = destination (menu_arena). Expands the header,
; the entries and the writable text buffers; checks the arena end at $19FC92,
; $19FEBC and $19FE56.
menu_construct          equ $19FC88
menu_template_opcode_table equ $1A00B8  ; word-opcode jump table of the parser
menu_tick               equ $1A0114     ; input, selection and entry actions
menu_entry_address      equ $1A0C4C     ; D0.w = index; A0 = expanded entry
menu_edit_text          equ $1A0DB0     ; A5 = text entry, D0.w = capacity
menu_draw_entry         equ $1A107E     ; A5 = expanded entry
; A6 = child template. Saves the parent and its selection, runs the child until
; menu_modal_exit is set, then rebuilds the parent through menu_restore.
menu_run_modal          equ $1A156C
menu_restore            equ $1A15B4     ; A6 = template, A5 = saved selection
menu_request_exit       equ $1A15EC     ; sets menu_modal_exit to 1
menu_install            equ $1A15F6     ; A6 = template; build, init, redraw
menu_modal_exit         equ $997C8      ; word: 1 ends the running modal menu
; Word: while set, a held activation is ignored until it is released
; (checked and cleared by menu_update_input at $1A08CA; set by the native DIY
; screens, for example $1B2E8E, before they hand control back).
menu_release_gate       equ $19FBCA
menu_arena_used         equ $99788      ; long: bytes used by the current page
menu_arena_remaining    equ $9978C      ; long: bytes left in the arena

; Expanded page: header at menu_arena, entries from MENU_FIRST_ENTRY.
menu_arena              equ $2818
MENU_ARENA_END          equ $417C
MENU_HEADER_SIZE        equ $16
MENU_HEADER_SELECTED    equ $0C         ; long: selected entry
MENU_HEADER_COUNT       equ $10         ; word: number of entries
MENU_HEADER_END         equ $12         ; long: end of entries and text buffers
MENU_FIRST_ENTRY        equ menu_arena+MENU_HEADER_SIZE
MENU_ENTRY_SIZE         equ $38
MENU_TEXT_BUFFER_SIZE   equ 70          ; writable text buffer after the entries

; Main menu. frontend_reset_state installs the main menu through
; LEA main_menu_template,A6 at main_template_lea; main_template_operand is its
; absolute operand.
frontend_reset_state    equ $1A036C
main_template_lea       equ $1A0430
main_template_operand   equ $1A0432
main_menu_template      equ $1C0AE4     ; 14 entries, one writable caption
main_menu_init          equ $1C0CA4     ; init callback: calls the refresh
main_menu_restore_noop  equ $1C0CAC     ; original restore callback (RTS only)
main_menu_refresh       equ $1C0CAE     ; rebuilds conditional captions

; Native pages that get editor entries. Each is opened by LEA template,A6
; followed by menu_run_modal; the *_operand names the LEA's absolute operand.
team_editor_template    equ $1B73A8     ; 61 entries, restore $1B7B62
team_editor_operand     equ $1B7394     ; LEA at $1B7392 (EDIT CUSTOM TEAMS)
diy_type_template       equ $1B6D24     ; SELECT DIY COMPETITION TYPE, 5 entries
diy_type_operand        equ $1C0D8A     ; LEA at $1C0D88 (DIY COMPETITION)
diy_league_template     equ $1B1CF4     ; DESIGN DIY LEAGUE, 24 entries
diy_league_operand      equ $1B1C82     ; LEA at $1B1C80
diy_cup_template        equ $1B33B2     ; DESIGN DIY CUP, 52 entries
diy_cup_operand         equ $1B3344     ; LEA at $1B3342
diy_tournament_template equ $1B543A     ; DESIGN DIY TOURNAMENT, 93 entries
diy_tournament_operand  equ $1B5416     ; LEA at $1B5414

; ---------------------------------------------------------------------------
; Teams, groups and tactics
; ---------------------------------------------------------------------------
; Loads a team group into team_group_buffer. A cached group (word
; team_group_cache_valid set and the same group in team_group_cache_key) is
; reused without reading; otherwise team_group_load_source, a six-byte
; JSR file_load_unpack with A1 = team_group_buffer, reads data/team.nnn. The
; custom set CUSTOMS.EDT has its own call at $1D1C54.
file_load_team_group    equ $1D1C1E
; 256 longword pointers by group code; each non-zero one points to the
; continent byte, the country name and its adjective, NUL-terminated
; ($1BE7AE reads the name through it).
team_group_descriptors  equ $1CE73E
team_group_load_source  equ $1D1CCA
team_group_cache_valid  equ $6765E      ; word: cleared to force a fresh load
team_group_cache_key    equ $B6C2       ; byte: group held in the buffer
team_group_buffer       equ $4A120      ; loaded group or the counted custom set
TEAM_GROUP_BUFFER_SIZE  equ $FA00       ; checked at $1D1CD4 after the load
CUSTOM_SET_SIZE         equ $8042       ; CUSTOMS.EDT: count word + 48 teams
tactic_work_buffer      equ $D072       ; tactic being edited, $172 bytes
user_tactic_slots       equ $1EEBE4     ; six $172-byte user tactic slots
TACTIC_SIZE             equ $172
USER_TACTIC_SLOTS       equ 6
; Starting a new competition family: competition_family_reset calls
; tactic_slots_reset at family_reset_tactic_call, a four-byte JSR (d16,PC)
; followed by the routine's RTS (family_reset_tail, six bytes in all).
; tactic_slots_reset copies the builtin tactic 0 into all six user slots,
; renames them USER A-F and calls tactic_rebuild_order; it preserves every
; register. frontend_reset_state also calls it once at start-up.
competition_family_reset equ $1A7AA2
family_reset_tactic_call equ $1A7B0C
FAMILY_RESET_TAIL_SIZE  equ 6
tactic_slots_reset      equ $1A050E
competition_normalize_new equ $1A7B12   ; new-competition normalization

; The competition family (competition_family_reset stores its D0 here):
; 0 none, 1 DIY, 2 preset, 3 season, 4 career. The abandon gate asks
; whether to lose a running competition (A0 = title of its prompt) and
; resets the family with D0 = 0 when the user agrees; D0.w = 0 (Z set)
; when no competition is left.
competition_family      equ $1EEBDE     ; word
competition_saved       equ $1EEBE0     ; word: set after a successful save
competition_abandon_gate equ $1A7A3C
; Competition saves. SAVE COMPETITION ($1C122A) and the career hub's own
; SAVE ($1BAF5A) call a writer with A0 = the file name: it stamps the
; save's identity ($1D1948) and writes through file_save_buffer
;   DIY, preset:    competition_state .. team_selection +
;                   TEAM_SIZE * word competition_team_count
;   season, career: season_state .. team_selection +
;                   TEAM_SIZE * word team_selection_count
; showing file_error_message itself on a failure (D0.w = 1, else 0).
competition_state       equ $1EE084     ; DIY and preset competition state
competition_team_count  equ $1EE0B6     ; word: teams of a DIY or preset competition
season_state            equ $1D7408     ; season and career state
competition_save_diy    equ $1D1B3E
competition_save_preset equ $1D1AC6
competition_save_season equ $1D1A80     ; BRA to competition_save_career
competition_save_career equ $1D1A4A
save_diy_call           equ $1C127C     ; six-byte JSR writer in SAVE COMPETITION
save_preset_call        equ $1C12C4
save_season_call        equ $1C130E
save_career_call        equ $1C1356
career_hub_save_call    equ $1BAF8E     ; the career hub's SAVE
; LOAD OLD COMPETITION ($1C138C): the abandon gate, the save chooser, then
; a loader by suffix with A0 = the file name: D0.w = 0 (Z set) when the
; competition is loaded; otherwise the caller resets the family (D0 = 0)
; and returns to the main menu ($1C1490).
competition_load_diy    equ $1D1AFA
competition_load_preset equ $1D1A82
competition_load_season equ $1D1A7E     ; BRA to competition_load_career
competition_load_career equ $1D1A06
load_diy_call           equ $1C13F2     ; six-byte JSR loader
load_preset_call        equ $1C141A
load_season_call        equ $1C143C
load_career_call        equ $1C145E

; LOAD OLD COMPETITION reads a save with one of three loaders: $1D1AFA
; (.DIY), $1D1A82 (.PRE) and $1D1A06 (.SEA and .CAR). Each reads the file
; over the competition state, which holds the six user tactic slots, checks
; the save's identity ($1D197A) and then calls competition_load_finish at
; its *_loaded_call (six-byte JSR). On a failure it calls tactic_slots_reset
; instead, and its caller ($1C1490) starts a new competition family.
competition_load_finish equ $1B512C
diy_loaded_call         equ $1D1B1C
preset_loaded_call      equ $1D1AA4
season_loaded_call      equ $1D1A28

; ---------------------------------------------------------------------------
; Tactic editor (EDIT TACTICS)
; ---------------------------------------------------------------------------
; tactics_frontend $1CB4B8 (main menu $1C14B4): the slot chooser $1CB622
; (USER A-F set tactic_editor_slot to 12-17), then the editor page $1CB7CC.
; Its init copies the slot into tactic_work_buffer and that into
; tactic_undo_buffer (UNDO copies it back). The page changes only the
; working tactic and sets tactic_editor_dirty; ABORT leaves without a
; commit.
tactic_editor_slot      equ $1CB4A4     ; word: tactic being edited, 12-17
tactic_editor_dirty     equ $1CB4B4     ; word: the working tactic was changed
tactic_undo_buffer      equ $D1E4       ; TACTIC_SIZE bytes after tactic_work_buffer
; SAVE/EXIT (action longword tactic_save_exit_operand of the page): when
; tactic_editor_dirty is set, tactic_commit_to_slot and
; tactic_invalidate_teams, then the question whether to save it as a file:
; save_disk_request (tactic_save_request_call), the filename field, the
; working tactic renamed after the file and written by tactic_file_save
; (tactic_save_call), then committed again; finally menu_request_exit.
; Without a change it only leaves the page.
tactic_save_exit        equ $1CBE44
tactic_save_exit_operand equ $1CB8B2
tactic_save_request_call equ $1CBE86    ; six-byte JSR save_disk_request
tactic_save_call        equ $1CBEF2     ; six-byte JSR tactic_file_save
; IMPORT $1CBF3A: the chooser $1CD320 (twelve builtins, USER A-F, LOAD,
; EXIT); a chosen record's body is copied over the working tactic by a
; MOVE.W #count,D0 at tactic_import_count and a DBF byte loop from the
; record + TACTIC_NAME_SIZE to tactic_work_buffer + TACTIC_NAME_SIZE. The
; native count $171 moves 370 bytes, nine past the record's end, over the
; first nine bytes of tactic_undo_buffer.
tactic_import_count     equ $1CBF84
TACTIC_IMPORT_COUNT_NATIVE equ $171
; LOAD $1CD532 (in the IMPORT chooser): save_disk_request
; (tactic_load_request_call), the native file chooser, a .TAC name check,
; the UNDO copy, then tactic_file_load (tactic_load_call) and the dirty word.
tactic_load_request_call equ $1CD540    ; six-byte JSR save_disk_request
tactic_load_call        equ $1CD574     ; six-byte JSR tactic_file_load
; tactic_file_load: A0 = name, A1 = tactic_work_buffer. Reads the whole file
; into the buffer addressed by display_draw_buffer and copies TACTIC_SIZE
; bytes, with no length or content check. D0.w = 0 (Z set), or 1 after
; file_error_message.
tactic_file_load        equ $1D1B72
; tactic_file_save: A0 = name, A1 = record. Writes TACTIC_SIZE bytes through
; file_save_buffer. D0.w = 0 (Z set), or 1 after file_error_message.
tactic_file_save        equ $1D1BBA
; Copies tactic_work_buffer into the slot of tactic_editor_slot, then
; tactic_rebuild_order.
tactic_commit_to_slot   equ $1CD276
; Sets the rebuild byte +$3B of the career team (while word
; $1E4B50 is not -1) and of every loaded team whose tactic byte TEAM_TACTIC
; equals tactic_editor_slot. Clobbers D0, D1 and A0.
tactic_invalidate_teams equ $1CD6B6
; Rebuilds the derived role order of all 18 tactics (eleven-byte tables
; through the pointers at $1A2B9C). Clobbers D0-D7 and A2-A6.
tactic_rebuild_order    equ $1CD6F2

; The match: $191258 (A6 = team context, A1 = player entity) reads the
; tactic of context word +$1C through tactic_pointer_table, the map of the
; entity's lineup slot (word +$02, minus 2) at the ball zone in word
; match_ball_zone (the second team reads zone 34-z and the byte $EF-b) and
; stores the target position words +$3A and +$3C at match_tactic_targets.
match_ball_zone         equ $1911F8
match_tactic_targets    equ $19132A

; ---------------------------------------------------------------------------
; Custom-team editor (EDIT CUSTOM TEAMS)
; ---------------------------------------------------------------------------
; custom_team_frontend $1B72DC: abandon gate, team_browser over the custom
; categories, then, when custom_teams_dirty is set, the SAVE/ABORT prompt
; (custom_save_prompt_call), the save-disk request (custom_save_request_call)
; and the write of the counted set from team_group_buffer as CUSTOMS.EDT
; (custom_save_write_call); a write result other than 0 shows file_error_message
; and asks again. It ends with team_group_cache_key = -1.
custom_team_frontend    equ $1B72DC
custom_save_prompt_call equ $1B7336     ; six-byte JSR frontend_prompt
custom_save_request_call equ $1B7346    ; six-byte JSR save_disk_request
custom_save_write_call  equ $1B7366     ; six-byte JSR file_save_buffer, A0 = custom_set_name
; team_browser $1BE8D2, category EDITED CUSTOM TEAMS: the save-disk request
; before file_load_team_group(100) (six-byte JSR save_disk_request).
custom_load_request_call equ $1BDF4A
; file_load_team_group, group CUSTOM_SET_GROUP: six-byte JSR file_load_unpack
; that reads CUSTOMS.EDT into team_group_buffer.
custom_load_call        equ $1D1C54
custom_set_name         equ $1D1E3A     ; 'CUSTOMS.EDT'
CUSTOM_SET_GROUP        equ 100         ; group code of CUSTOMS.EDT
ORIGINAL_CUSTOM_GROUP   equ 72          ; TEAM.072, ORIGINAL CUSTOM TEAMS
CUSTOM_SET_TEAMS        equ 48          ; teams in the native custom set

; The team page: team_editor_template, a modal child of team_browser.
; custom_team_init_working_copy (init callback) copies the chosen record
; (custom_team_original_pointer) to team_working_copy and refreshes; the
; restore callback custom_team_restore only refreshes. custom_team_commit
; (OK) compares the working copy with the original, sets custom_teams_dirty
; and copies it back when they differ; custom_team_undo (UNDO) copies the
; original over the working copy; custom_team_import (IMPORT) replaces the
; working copy with a club or national team, keeping the key word and the
; division, and sets custom_team_imported. The refresh custom_team_refresh
; draws names, kits and the 16 rows in physical player order from the
; working copy.
custom_team_init_working_copy equ $1B7B46
custom_team_restore     equ $1B7B62
custom_team_import      equ $1B7B6C
custom_team_undo        equ $1B7C42
custom_team_commit      equ $1B7C68
custom_team_refresh     equ $1B804E
custom_team_original_pointer equ $1B82EE ; long: record in team_group_buffer
custom_teams_dirty      equ $1B82F2     ; word: an accepted change is not saved
custom_team_imported    equ $1B82F4     ; word: the working copy came from IMPORT
team_working_copy       equ $1EF4B6     ; $2AC bytes edited by the team page
TEAM_PAGE_FIRST_NAME    equ 39          ; entries 39-54: player names, rows 0-15
TEAM_PAGE_IMPORT        equ 20          ; entries of the native page
TEAM_PAGE_OK            equ 21
TEAM_PAGE_UNDO          equ 22

; Prompts and messages of the front end (modal native menus).
; frontend_prompt: A0 = title, A1 = message (first byte $01), A2 and A3 =
; button texts (A3 = 0 for one button), D0.w = default; returns D0.w = 0 for
; the first button and sets the flags from it.
frontend_prompt         equ $1C08E6
; save_disk_request: asks for the save disk with frontend_prompt and checks
; it through file_operation_dispatch selector $10 until it is accepted;
; D0.w = 0 (Z set) or the cancel result. D7 is clobbered.
save_disk_request       equ $1D1912
SELECT_SAVE_DISK        equ $10         ; file_operation_dispatch selector
; The other flows that ask for the save disk with save_disk_request (a
; six-byte JSR each) before they read, write or delete on the save volume:
career_hub_save_request_call equ $1BAF60 ; the career hub's SAVE
delete_file_request_call equ $1C087A    ; SAVE DISK FILING > DELETE FILE
; DELETE FILE then lets the user choose a save ($1BFD3A, A0 = its name) and
; deletes it with a six-byte JSR file_operation_dispatch (D7.w = 6) here.
delete_file_call        equ $1C0894
save_competition_request_call equ $1C1230 ; SAVE COMPETITION
load_competition_request_call equ $1C13A2 ; LOAD OLD COMPETITION
load_highlights_request_call equ $1CDEB4 ; HIGHLIGHTS: load a .HIL file
save_highlights_request_call equ $1CDF3C ; HIGHLIGHTS: save a .HIL file
; FORMAT SAVE DISK ($1C07E2) first asks for a blank disk in DF0 with
; frontend_prompt (six-byte JSR at format_prompt_call, CONTINUE/ABORT); any
; result but 0 returns at once ($1C0804 -> $1C0864), otherwise it checks the
; disk, formats it and writes the save-disk marker.
format_prompt_call      equ $1C07FE
; EDIT CUSTOM TEAMS (custom_team_frontend) starts with the abandon gate:
; LEA title,A0, then a six-byte JSR competition_abandon_gate at this site.
custom_team_gate_call   equ $1B72E2
; game_disk2_request: selects game disk 2 (game_find_disk_marker, mode 2)
; and asks for it until it is found; the native flows call it after every
; save-disk operation ($1B7384, $1BEB9A, $1CBF20, ...), because the team
; groups are read from the selected disk. Under the slave the marker search
; always finds it.
game_disk2_request      equ $1D18E8
; file_error_message: D0.w = file result; shows DISK WRITE PROTECTED ($1C),
; NO DISK IN DRIVE ($1D), FILE NOT FOUND ($CD), DISK FULL ($DD) or DISK ERROR.
file_error_message      equ $1BFC00

; ---------------------------------------------------------------------------
; The European club cups' team copies and the transfer pool
; ---------------------------------------------------------------------------
; The European club cups (EUROPEAN CHAMPIONS CUP, EUROPEAN CUP-WINNERS CUP,
; EUFA CUP) play the team copies of data/eurocup.tmd, eurocwc.tmd and
; uefacup.tmd, not the TEAM groups. cup_copies_load ($1D1402, A0 = a compact
; builtin descriptor) reads a cup's file through cup_copies_read_call, a
; six-byte JSR file_load_unpack (A0 = its name, one of the three names
; cup_copies_names + CUP_NAME_STRIDE * cup, A1 = cup_copies_records +
; TEAM_SIZE * word cup_copies_count), adds the records to the cached-team
; list and rebuilds their secondary IDs from the keys. Before it, the
; six-byte LEA cup_copies_records,A1 at cup_copies_target. It is reached for
; PRESET COMPETITION when the team browser $1BDF1A lists such a cup
; (builtin_select_* $1A7472, $1A74B0, $1A74E8), and at the start of a career
; ($1AE210..$1AE22E, after competition_family_reset with the career family)
; for all three, the first being cup_copies_first_name. Then the
; descriptor's BE16 participant keys (cup_key_lists) are selected: a key's
; cached copy first, else its group (select_teams_by_key_list $1D1454). The
; cached list starts season_state, so season and career saves keep it; a
; career copies the three descriptors with their key lists into its state.
cup_copies_load         equ $1D1402
cup_copies_target       equ $1D1428
cup_copies_read_call    equ $1D143A
cup_copies_count        equ $1D7408     ; word
cup_copies_records      equ $1D740A
cup_copies_names        equ $1CF326     ; 'data/eurocup.tmd', 'data/eurocwc.tmd', 'data/uefacup.tmd'
cup_copies_first_name   equ cup_copies_names
CUP_NAME_STRIDE         equ 17
eurocup_key_list        equ $1CF388     ; 16 keys
eurocwc_key_list        equ $1CF3C4     ; 32 keys
uefacup_key_list        equ $1CF420     ; 32 keys
; The career's BUY PLAYER page (template $1C538A): VIEW FOREIGN PLAYER
; MARKET runs foreign_market_view through the action longword at
; foreign_market_operand. Its list (word $1E4B8E entries at $1E4B94, in the
; saved career state) is drawn from the transfer pool data/poolplyr.dat
; (900 entries: team key, slot, team name and player record), which
; transfer_pool_load ($1C2A36) reads through transfer_pool_read_call, a
; six-byte JSR file_load_unpack (A0 = transfer_pool_name, A1 =
; transfer_pool), when word transfer_pool_loaded is clear; every match and
; frontend_reset_state clear it. The list screen $1C4BC2 shows the pool's
; copies. The domestic market ($1C2E94) takes its players from the career's
; loaded teams.
foreign_market_operand  equ $1C53EE
foreign_market_view     equ $1C5498
transfer_pool_read_call equ $1C2A52
transfer_pool_name      equ $18187D     ; 'data/poolplyr.dat'
transfer_pool_loaded    equ $67660      ; word
transfer_pool           equ $67662

; ---------------------------------------------------------------------------
; Player and tactic tables
; ---------------------------------------------------------------------------
; 153 three-letter nationality labels without terminators, index 0-152
; (read as nationality*3 without a bounds check at its consumers).
nationality_abbreviations equ $1CEB94
NATIONALITY_COUNT       equ 153
; Eight longword pointers to the position labels G RB LB D RW LW M A
; (custom_team_row_draw $1B8102 indexes it with position*4).
position_labels         equ $1D20C8
; Eighteen longword pointers to the tactic records: builtins 0-11, the six
; user slots 12-17 (team byte +$18 selects one; tactic name at +0).
tactic_pointer_table    equ $1A4648
TACTIC_BUILTIN_COUNT    equ 12
TACTIC_USER_FIRST       equ 12
TACTIC_USER_LAST        equ 17
TACTIC_NAME_SIZE        equ 9
; D0.b = aggregate 0-49 -> D0.w = base price in thousands ($1D3488, $1D33D0).
aggregate_to_base_price equ $1A64A8
; D0.w = price in thousands, A1 = output: writes the native price text
; ($9C pound sign, then "%1K", "%0M" or "%0.%1M") through format_frontend_text.
format_price_thousands  equ $1A7414
PRICE_POUND_SIGN        equ $9C
; D0.w = sprite, D1.w = x, D2.w = y: draws a sprite into display_draw_buffer
; (blitter, through the sprite pointers at $1D7364).
sprite_draw             equ $1842EE
APPEARANCE_SPRITE_BASE  equ $BA         ; icon of appearance 0 ($1B8040)

; ---------------------------------------------------------------------------
; DIY COMPETITION
; ---------------------------------------------------------------------------
; The main-menu action $1C0D70 passes the abandon gate $1A7A3C, so no
; competition family exists while the setup pages are open. It runs the type
; page diy_type_template, whose actions set diy_type_choice (0 league, 1 cup,
; 2 tournament, -1 EXIT) and leave, then calls the family's setup entry
; ($1B1C6C, $1B332A, $1B53FC): the committed competition is copied into the
; scratch state, the family's initializer writes the native defaults, the
; page's mode and phase words are cleared and the page runs modally through
; LEA template,A6 at diy_*_operand. (The other entries $1B1C8C, $1B334E and
; $1B5420 show a running competition's rules read-only with the native
; template.)
diy_type_choice         equ $1B6DF8     ; word
diy_scratch             equ $2DEF0      ; setup state of a league or cup
diy_tournament_scratch  equ $2DAD0      ; setup state of a tournament
; A page has two phases: the rules are edited until OK, which sets the
; phase word to 1 and installs the page again through a PC-relative LEA
; ($1B2204, $1B3C76, $1B6216); then CHOOSE TEAMS starts the competition.
diy_league_phase        equ $1B24C4     ; word
diy_cup_phase           equ $1B4086
diy_tournament_phase    equ $1B6D1A
diy_league_init         equ $1B1FF4     ; init callbacks of the pages: draw the
diy_cup_init            equ $1B3AF2     ; controls from the scratch state
diy_tournament_init     equ $1B6076
; CHOOSE TEAMS: team_chooser (D0 = the scratch state's team count), then,
; when team_chooser_done is set, competition_family_reset (D0 = 1), the
; team keys of the selection into the scratch state ($1AABF4), the
; family's initializers and schedule builders, competition_normalize_new
; and the commit of the scratch state to $1EE084; then the page leaves.
diy_league_choose       equ $1B2222
diy_cup_choose          equ $1B3C94
diy_tournament_choose   equ $1B6234
diy_league_chooser_call equ $1B2240     ; six-byte JSR team_chooser in each
diy_cup_chooser_call    equ $1B3CB2
diy_tournament_chooser_call equ $1B6252
; team_chooser: D0.w = teams to choose, A0 = competition name, A1 = label of
; the button that ends the choice, D2.w/D3.w/D4.w = club, national and
; custom categories enabled. It clears the selection, runs the category
; template $1BF96C and its browsers, in which Fire on a team cycles its
; control and adds or removes it ($1B0E60); team_chooser_done is 1 after
; the ending button with the full count, 0 after ABORT or EXIT.
team_chooser            equ $1BEB18
team_chooser_done       equ $1B1136     ; word
; The selection: team_selection_count full team records from team_selection
; (the same buffer as team_working_copy). team_selection_add (A0 = record)
; appends a copy and returns A0 = the copy; its first instruction, LEA
; team_selection,A1, is six bytes. The chooser stores the control in the
; copy's byte TEAM_CONTROL (team.i).
team_selection_count    equ $1EF4B4     ; word
team_selection          equ $1EF4B6
team_selection_add      equ $1B1140
TEAM_SELECTION_MAX      equ 64


; ---------------------------------------------------------------------------
; Matches played by the match engine (the match log)
; ---------------------------------------------------------------------------
; match_setup_wrapper ($1A8566) is the only way into the match engine: a
; friendly (friendly_prepare_match $1A7D40), a league fixture
; (league_match_play $1A818C) and a knockout tie of a cup or tournament
; (cup_match_play $1A7E0A) call it with A1/A2 = the home and away team
; records, which it keeps at match_team_records. It builds the match teams
; (match_team_home/away), runs match_main through match_preserve_menu_run
; and, unless the match was abandoned, writes the goals back to the teams
; ($1A89DC). Fixtures the game only simulates (fixture_simulate $1A2400)
; and the highlights (their own player $18EC1C) never reach it.
match_team_records      equ $1A8ECE     ; two longs: home and away team records
; The frame loop of match_main ends only through its cleanup at $18EB60,
; which tests match_friendly at match_end_friendly_test (six bytes, TST.W
; abs.l; a BEQ follows): every match the engine played to its end passes
; here once, each REPLAY of a friendly included (friendly_replay_chosen
; makes the post-match screen restart the match from match_restart_state,
; which restores both match teams and clears the score). The results are
; final at this point.
match_end_friendly_test equ $18EB78
match_friendly          equ $1AF6F0     ; word: 1 in a friendly or training
friendly_replay_chosen  equ $18FC04     ; word: REPLAY chosen after a friendly
training_mode           equ $1AFF94     ; word: TRAINING (no result, never logged)
; match_abandoned is set when a match ends without a result: Esc while both
; sides or neither side is human-controlled, or before the clock started
; (match_key_handler $18F6A6), and by the abort of the pre-match team
; screens ($1A8454, before the engine runs). match_main clears it at its
; start ($18E8D6). match_setup_wrapper returns its test (Z clear: abandoned)
; at match_wrapper_return (six bytes, TST.W abs.l, then RTS), after the
; front end is back (menu resources reloaded at $1A889A).
match_abandoned         equ $1AF6FC     ; word
match_wrapper_return    equ $1A88BC
; Esc with exactly one side human-controlled after the clock started gives
; the other side 5 goals and more until it leads (forfeit_goals_award
; $1A16F2, to random players by position, or to the own-goal bucket); both
; forfeit paths end at forfeit_score_site, MOVE.W match_score,match_score_90
; (eight bytes, PC-relative source), and the result is recorded.
forfeit_score_site      equ $18F6FE
FORFEIT_SITE_SIZE       equ 8
; Scores (words, home then away): match_score_90 at 90 minutes (set at
; $18B502; a forfeit copies the total), match_score after extra time,
; without the penalty shootout (penalty_shootout_start $191910 keeps the
; score and kick_done $193E18 restores it), match_penalty_score the
; shootout. match_extra_time and match_penalties hold 1 when the rules
; allow them and become negative when they were played ($18B638,
; $18B64A); a forfeit clears both.
match_score_90          equ $18F160
match_score             equ $18F164
match_penalty_score     equ $1AF710
match_extra_time        equ $1AF708     ; word
match_penalties         equ $1AF70A     ; word
; A second leg of a two-legged tie (cup_match_play $1A7FCE): the earlier
; goals of the home and away team (words, low bytes from the tie's score
; word $14E) count towards the aggregate.
match_second_leg        equ $1AF6F4     ; word
match_earlier_goals     equ $1AF70C     ; two words
; The competition's name and the round as shown with the match (40 bytes
; each; FRIENDLY or TRAINING, a league's or cup's name; the round is empty
; for a league), written by the three callers above.
match_competition_name  equ $CC8C
match_round_name        equ $CCF0
MATCH_NAME_SIZE         equ 40
; Match teams (match_team_build $1A8A0A): the home team at match_team_home,
; the away team at match_team_away. MT_NAME is the team's name, MT_OWN_GOALS
; the goals its opponents put into their own net; 16 match players follow,
; player i (0-15) at the team + i*MATCH_PLAYER_SIZE (biased offsets below):
; MP_SLOT its physical slot in the team record, MP_GOALS the goals it
; scored ($18C85E; the forfeit adds here too), MP_SHIRT its shirt number,
; MP_SHORT_NAME the short form name_abbreviate ($1A7276) made from the
; record's name ("I. SURNAME", at most 14 characters), as the game shows it.
match_team_home         equ $BEB8
match_team_away         equ $C2B2
MATCH_TEAM_NAME         equ $16
MATCH_TEAM_OWN_GOALS    equ $28         ; byte
MATCH_PLAYERS           equ 16
MATCH_PLAYER_SIZE       equ $3D
MATCH_PLAYER_SLOT       equ $2B         ; byte
MATCH_PLAYER_GOALS      equ $2C         ; byte
MATCH_PLAYER_SHIRT      equ $2D         ; byte
MATCH_PLAYER_SHORT_NAME equ $36         ; 15 bytes
; The scorer lists of the result display (match_goal_scored $18C6D8), the
; home list then the away list, each SCORER_ENTRIES entries in use order
; until a zero key (cleared at match start, $18B8CC). An entry belongs to
; the side the goals count for: key = the scorer's shirt, or the shirt +
; SCORER_OWN_GOAL_KEY of an opponent who put the ball into his own net;
; up to SCORER_GOALS_MAX goals of SCORER_GOAL_SIZE bytes: the kind word
; (SCORER_NORMAL, SCORER_PENALTY, SCORER_OWN_GOAL) and the minute as four
; characters (a zero byte and three digits from match_clock). Goals of a
; shootout and of a forfeit are not listed; the lists hold at most eight
; lines in all.
match_scorer_lists      equ $18FC16
SCORER_LIST_SIZE        equ $210
SCORER_ENTRIES          equ 8
SCORER_ENTRY_SIZE       equ $42
SE_KEY                  equ 0           ; word
SE_GOALS                equ 4           ; word
SE_GOAL                 equ 6
SCORER_GOAL_SIZE        equ 6
SCORER_GOALS_MAX        equ 10
SCORER_OWN_GOAL_KEY     equ 100
SCORER_NORMAL           equ 0
SCORER_PENALTY          equ 1
SCORER_OWN_GOAL         equ 2
