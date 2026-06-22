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
.export spectrum_to_c64_tile

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

; Level 1 items
; Format: .byte type, x_lo, x_hi, y
level_1_items:
    .byte 0, $30, $00, $A0    ; weapon upgrade
    .byte 1, $70, $00, $A0    ; health pack
    .byte 2, $B0, $00, $A0    ; ammo
    .byte 3, $E0, $00, $A0    ; keycard

; ---- Level 2: Laboratory ----
level_2_header:
    .byte 80            ; width
    .byte 16            ; height
    .byte 2, 12
    .byte 76, 4
    .word 12
    .word 6

level_2_tiles:
    .byte $FF           ; all solid (placeholder)
    .byte $FF

level_2_enemies:
    .res 12*5, 0

level_2_items:
    .res 6*4, 0

; Level table
level_table_lo:
    .byte <level_1_header
    .byte <level_2_header

level_table_hi:
    .byte >level_1_header
    .byte >level_2_header

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
