;
; ANP2 - Level data (converted from ZX Spectrum format)
;
; Level format:
;   .byte width (tiles), height (tiles)
;   .byte start_x, start_y (player spawn, in tiles)
;   .byte exit_x, exit_y (level exit)
;   .word enemy_count, item_count
;   .byte[width*height] tile map (RLE-compressed)
;   .byte[] enemy spawn data
;   .byte[] item data
;

.export level_1_header, level_2_header
.export level_table_lo, level_table_hi
.export level_start_x_lo, level_start_y_lo
.export spectrum_to_c64_tile
.export level_1_enemies, level_1_items
.export level_2_enemies, level_2_items

.segment "RODATA"

; ---- Level 1: Weyland-Yutani Lab ----
level_1_header:
    .byte 64            ; width (tiles)
    .byte 16            ; height (tiles)
    .byte 2, 12         ; player start (tile coords)
    .byte 60, 4         ; exit location
    .word 8             ; enemy count
    .word 4             ; item count

level_1_tiles:
    ; Map: 64 wide x 16 tall = 1024 tiles
    ; RLE: tile_id, repeat_count, ...
    ; Layer 1: floor/solid
    .byte 1, 64         ; row 0: solid wall
    .byte 2, 64         ; row 1: metal floor

    ; Row 2: air with platforms
    .byte 0, 10
    .byte 3, 6          ; platform
    .byte 0, 16
    .byte 3, 4
    .byte 0, 17
    .byte 3, 2
    .byte 3, 2
    .byte 0, 7

    ; Row 3-10: air
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64

    ; Row 11: more platforms
    .byte 0, 8
    .byte 3, 6
    .byte 0, 16
    .byte 3, 4
    .byte 0, 20
    .byte 3, 4
    .byte 0, 6

    ; Row 12: ground
    .byte 0, 8
    .byte 2, 56        ; metal floor

    ; Row 13: ground continues (ladder)
    .byte 1, 24
    .byte 4, 2          ; ladder
    .byte 1, 38
    .byte 4, 2
    .byte 1, 0          ; end marker

    ; Row 14: lower area
    .byte 0, 64

    ; Row 15: bottom wall
    .byte 1, 64

    ; End of tile data
    .byte $FF

; Level 1 enemies
; Format: .byte type, x_lo, x_hi, y, state
level_1_enemies:
    .byte 0, $20, $00, $90, 1    ; xeno
    .byte 1, $40, $00, $80, 1    ; guard
    .byte 0, $60, $00, $90, 1    ; xeno
    .byte 1, $80, $00, $80, 1    ; guard
    .byte 0, $A0, $00, $90, 1    ; xeno
    .byte 1, $C0, $00, $80, 1    ; guard
    .byte 0, $D0, $00, $90, 1    ; xeno
    .byte 1, $F0, $00, $80, 1    ; guard
    .byte $FF                    ; end marker

; Level 1 items
; Format: .byte type, x_lo, x_hi, y
level_1_items:
    .byte 0, $30, $00, $60    ; weapon upgrade (row 12, ground)
    .byte 1, $70, $00, $60    ; health pack   (row 12, ground)
    .byte 2, $B0, $00, $60    ; ammo          (row 12, ground)
    .byte 3, $E0, $00, $10    ; keycard       (row 2, platform)
    .byte $FF                ; end marker

; ---- Level 2: Laboratory (vertical shaft, 64x32) ----
level_2_header:
    .byte 64            ; width
    .byte 32            ; height (taller than the 25-row screen -> scrolls)
    .byte 2, 28         ; player start
    .byte 60, 4         ; exit
    .word 12
    .word 6

level_2_tiles:
    .byte 1, 64         ; row 0: ceiling
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 2, 64         ; row 8: catwalk
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 2, 64         ; row 16: catwalk
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 2, 64         ; row 24: catwalk
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 0, 64
    .byte 2, 64         ; row 31: main floor
    .byte $FF

level_2_enemies:
    .byte 0, $20, $00, $88, 1    ; on catwalk row 17
    .byte 1, $40, $00, $48, 1
    .byte 0, $60, $00, $88, 1
    .byte 1, $80, $00, $48, 1
    .byte 0, $A0, $00, $88, 1
    .byte 1, $C0, $00, $48, 1
    .byte 0, $D0, $00, $88, 1
    .byte 1, $F0, $00, $48, 1
    .byte 0, $30, $00, $C8, 1
    .byte 1, $70, $00, $88, 1
    .byte 0, $B0, $00, $C8, 1
    .byte 1, $D0, $00, $88, 1
    .byte $FF

level_2_items:
    .byte 0, $30, $00, $80    ; weapon upgrade (catwalk row 16)
    .byte 1, $50, $00, $80    ; health pack
    .byte 2, $90, $00, $80    ; ammo
    .byte 3, $10, $00, $40    ; keycard (catwalk row 8)
    .byte 2, $70, $00, $40    ; ammo
    .byte 1, $D0, $00, $40    ; health pack
    .byte $FF

; Level table
level_table_lo:
    .byte <level_1_header
    .byte <level_2_header

level_table_hi:
    .byte >level_1_header
    .byte >level_2_header

; Player start Y in pixels (tile row * 8)
level_start_y_lo:
    .byte 12*8     ; level 1: tile row 12 (matches header)
    .byte 28*8     ; level 2: tile row 28

; Player start X in pixels (tile col * 8)
level_start_x_lo:
    .byte 2*8      ; level 1: tile col 2
    .byte 2*8      ; level 2: tile col 2

; Tile mapping: Spectrum tile -> C64 tile index
spectrum_to_c64_tile:
    .byte 0             ; space/empty
    .byte 1             ; wall
    .byte 2             ; floor
    .byte 3             ; platform
    .byte 4             ; ladder
    .byte 5             ; vent
    .byte 6             ; crate
    .byte 7             ; pipe
    .byte 8             ; pipe vert
    .byte 9             ; hazard
    .byte 10            ; door
    .byte 11            ; terminal
    .byte 12            ; reserved
    .byte 13            ; item: weapon
    .byte 14            ; item: health
    .byte 15            ; item: ammo
    .byte 16            ; item: keycard
