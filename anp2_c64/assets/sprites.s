;
; ANP2 - Sprite and tile data
; C64 hardware sprites: 24x21 pixels, 64 bytes each
; Multicolor mode: 2 bits per pixel (4 colors)
;
; Animation frames:
;   0-3: idle
;   4-7: walk
;   8-11: shoot
;   12-15: jump
;

.export player_sprite, enemy_xeno, enemy_guard, bullet_sprite
.export tile_graphics, tile_color_table

.segment "RODATA"

; ---- Player sprites (Ashley/Lt. Smith) ----
; Frame: idle facing right (frame 0)

player_sprite:
    ; Frame 0: idle 1
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$0A,$00,$00,$02
    .byte $AE,$80,$00,$0A,$BA,$00,$00,$2E
    .byte $BA,$00,$00,$0A,$AA,$00,$00,$2A
    .byte $A8,$00,$00,$02,$80,$00,$00,$0A
    .byte $00,$00,$00,$28,$00,$00,$00,$A0
    .byte $00,$00,$02,$80,$00,$00,$0E,$00
    .byte $00,$00,$38,$00,$00,$00,$20,$00
    .byte $00,$00,$20,$00,$00,$00,$A8,$00
    .byte $00,$02,$A8,$00,$00,$0A,$A0,$00
    .byte $00,$0A,$A0,$00,$00,$0A,$A0,$00
    .byte $00,$02,$80,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

    ; Frame 1: idle 2
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$0A,$00,$00,$02
    .byte $AE,$80,$00,$0A,$BA,$00,$00,$2E
    .byte $BA,$00,$00,$0A,$AA,$00,$00,$2A
    .byte $A8,$00,$00,$02,$80,$00,$00,$0A
    .byte $00,$00,$00,$28,$00,$00,$00,$A0
    .byte $00,$00,$02,$80,$00,$00,$0E,$00
    .byte $00,$00,$38,$00,$00,$00,$20,$00
    .byte $00,$00,$20,$00,$00,$00,$A8,$00
    .byte $00,$02,$A8,$00,$00,$0A,$A0,$00
    .byte $00,$08,$A0,$00,$00,$0A,$A0,$00
    .byte $00,$02,$80,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

    ; Frame 2: walk 1
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$0A,$00,$00,$02
    .byte $AE,$80,$00,$0A,$BA,$00,$00,$2E
    .byte $BA,$00,$00,$0A,$AA,$00,$00,$2A
    .byte $A8,$00,$00,$02,$80,$00,$00,$0A
    .byte $00,$00,$00,$28,$00,$00,$00,$A8
    .byte $00,$00,$02,$A0,$00,$00,$0E,$80
    .byte $00,$00,$39,$00,$00,$00,$24,$00
    .byte $00,$00,$28,$00,$00,$00,$A0,$00
    .byte $00,$02,$80,$00,$00,$0A,$A0,$00
    .byte $00,$0A,$A0,$00,$00,$0A,$A0,$00
    .byte $00,$02,$80,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

    ; Frame 3: walk 2
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$0A,$00,$00,$02
    .byte $AE,$80,$00,$0A,$BA,$00,$00,$2E
    .byte $BA,$00,$00,$0A,$AA,$00,$00,$2A
    .byte $A8,$00,$00,$02,$80,$00,$00,$0A
    .byte $00,$00,$00,$28,$00,$00,$00,$A0
    .byte $00,$00,$02,$90,$00,$00,$0E,$40
    .byte $00,$00,$39,$00,$00,$00,$24,$00
    .byte $00,$00,$28,$00,$00,$00,$A0,$00
    .byte $00,$02,$80,$00,$00,$0A,$A0,$00
    .byte $00,$0A,$A0,$00,$00,$0A,$A0,$00
    .byte $00,$02,$80,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; ---- Enemy sprites ----
; Xenomorph (frame 0)
enemy_xeno:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$2A,$A8,$00,$02,$AE
    .byte $A8,$00,$0A,$BA,$A0,$00,$2E,$BA
    .byte $80,$00,$0A,$AA,$00,$00,$2A,$A8
    .byte $00,$00,$82,$80,$00,$00,$20,$A0
    .byte $00,$00,$82,$A0,$00,$02,$0A,$80
    .byte $00,$0A,$02,$80,$00,$28,$0A,$80
    .byte $00,$A0,$2A,$00,$02,$80,$A8,$00
    .byte $0A,$02,$A0,$00,$28,$0A,$80,$00
    .byte $A0,$28,$00,$02,$80,$28,$00,$0A
    .byte $00,$28,$00,$00,$00,$A0,$00,$00
    .byte $02,$80,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; Guard (frame 0)
enemy_guard:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$02,$80,$00,$00,$0B
    .byte $A0,$00,$00,$0B,$A0,$00,$00,$0B
    .byte $A0,$00,$00,$0A,$A0,$00,$00,$2A
    .byte $A8,$00,$00,$00,$00,$00,$00,$2A
    .byte $00,$00,$00,$38,$00,$00,$00,$8A
    .byte $00,$00,$00,$2A,$00,$00,$00,$2A
    .byte $00,$00,$00,$28,$00,$00,$00,$28
    .byte $00,$00,$00,$A0,$00,$00,$02,$A0
    .byte $00,$00,$0A,$A0,$00,$00,$0A,$A0
    .byte $00,$00,$0A,$A0,$00,$00,$02,$80
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; Bullet sprite
bullet_sprite:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$2A,$A8,$00,$0A,$AA
    .byte $A0,$00,$2A,$AA,$80,$00,$0A,$AA
    .byte $A0,$00,$02,$AA,$80,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; Grenade sprite
grenade_sprite:
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$02,$80,$00,$00,$2E
    .byte $80,$00,$00,$29,$00,$00,$00,$26
    .byte $80,$00,$00,$2A,$00,$00,$00,$28
    .byte $00,$00,$00,$A0,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

; ---- Tile graphics ----
; 8x8 tiles for the game map
; Each tile is 8 bytes (one character in bitmap mode)

tile_graphics:
    ; Tile 0: empty/air
    .byte $00,$00,$00,$00,$00,$00,$00,$00

    ; Tile 1: solid wall (metal)
    .byte $FF,$81,$BD,$A5,$BD,$A5,$81,$FF

    ; Tile 2: floor tile
    .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

    ; Tile 3: platform
    .byte $FF,$FF,$00,$00,$00,$00,$00,$00

    ; Tile 4: ladder
    .byte $AA,$00,$AA,$00,$AA,$00,$AA,$00

    ; Tile 5: vent
    .byte $FF,$81,$81,$99,$99,$81,$81,$FF

    ; Tile 6: crate
    .byte $FF,$81,$A5,$81,$81,$A5,$81,$FF

    ; Tile 7: pipe horizontal
    .byte $00,$00,$FF,$FF,$FF,$FF,$00,$00

    ; Tile 8: pipe vertical
    .byte $66,$66,$66,$66,$66,$66,$66,$66

    ; Tile 9: hazard/acid
    .byte $00,$00,$18,$3C,$7E,$DB,$18,$18

    ; Tile 10: door
    .byte $00,$7E,$42,$42,$5A,$42,$42,$7E

    ; Tile 11: computer terminal
    .byte $00,$00,$7E,$42,$5A,$42,$7E,$00

    ; Tile 12: wall top
    .byte $FF,$81,$81,$BD,$81,$81,$81,$FF

    ; Tile 13-15: reserved
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00

    ; Tile 16-31: wall variations
    .res 16*8, $00

    ; Tile 32-47: decorations
    .res 16*8, $00

; ---- Tile color table ----
; Each tile type's screen byte = (bg << 4) | fg for hires bitmap mode
tile_color_table:
    .byte $00    ; 0: air      (black on black)
    .byte $01    ; 1: wall     (white on black)
    .byte $0F    ; 2: floor    (light grey on black)
    .byte $05    ; 3: platform (green on black)
    .byte $07    ; 4: ladder   (yellow on black)
    .byte $03    ; 5: vent     (cyan on black)
    .byte $09    ; 6: crate    (orange on black)
    .byte $0B    ; 7: pipe h   (light grey on black)
    .byte $0B    ; 8: pipe v   (light grey on black)
    .byte $02    ; 9: hazard   (red on black)
    .byte $06    ; 10: door    (blue on black)
    .byte $0E    ; 11: term    (light blue on black)
    .byte $01    ; 12: wall top (white on black)
    .byte $00, $00, $00  ; 13-15: reserved

; ---- Sprite color tables ----
player_sprite_colors:
    .byte $0F,$0C,$02    ; sprite multicolor: white, grey, red

enemy_sprite_colors:
    .byte $0F,$0E,$06    ; sprite multicolor: white, cyan, blue

bullet_sprite_colors:
    .byte $0F,$07,$01    ; white, yellow, white

; Animation frame lookup table (direction * 4 + frame)
player_sprite_frames:
    .word player_sprite, player_sprite+64
    .word player_sprite+128, player_sprite+192
