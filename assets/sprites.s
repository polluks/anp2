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
.export hud_glyphs

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

    ; Tile 13: weapon upgrade
    .byte $00,$7E,$42,$7A,$42,$7E,$00,$00
    ; Tile 14: health pack
    .byte $00,$18,$7E,$FF,$7E,$18,$00,$00
    ; Tile 15: ammo
    .byte $00,$3C,$7E,$66,$7E,$3C,$00,$00
    ; Tile 16: keycard
    .byte $00,$66,$7E,$5A,$7E,$66,$00,$00

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
    .byte $05    ; 13: weapon (green on black)
    .byte $02    ; 14: health (red on black)
    .byte $07    ; 15: ammo (yellow on black)
    .byte $06    ; 16: keycard (blue on black)

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

; HUD font glyphs (8x8 bitmap patterns)
; Each character is 8 bytes, one per scanline
; Index 0='0', 1='1', ... 9='9', 10='A', 11='C', 12='E', 13='H'
; Index 14='I', 15='M', 16='N', 17='O', 18='P', 19='R', 20='S'
; Index 21='T', 22='W', 23=':', 24=' ', 25='L', 26='F', 27='U', 28='G'
hud_glyphs:
    .byte $3C,$66,$6E,$76,$66,$66,$3C,$00  ; 0
    .byte $18,$38,$18,$18,$18,$18,$3C,$00  ; 1
    .byte $3C,$66,$06,$0C,$30,$60,$7E,$00  ; 2
    .byte $3C,$66,$06,$0C,$06,$66,$3C,$00  ; 3
    .byte $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00  ; 4
    .byte $7E,$60,$7C,$06,$06,$66,$3C,$00  ; 5
    .byte $3C,$66,$60,$7C,$66,$66,$3C,$00  ; 6
    .byte $7E,$06,$0C,$18,$30,$30,$30,$00  ; 7
    .byte $3C,$66,$66,$3C,$66,$66,$3C,$00  ; 8
    .byte $3C,$66,$66,$3E,$06,$66,$3C,$00  ; 9
    .byte $18,$3C,$66,$66,$7E,$66,$66,$00  ; A
    .byte $3C,$66,$60,$60,$60,$66,$3C,$00  ; C
    .byte $7E,$60,$60,$7C,$60,$60,$7E,$00  ; E
    .byte $66,$66,$66,$7E,$66,$66,$66,$00  ; H
    .byte $3C,$18,$18,$18,$18,$18,$3C,$00  ; I
    .byte $66,$6E,$7E,$7E,$76,$66,$66,$00  ; M
    .byte $42,$62,$72,$5A,$4E,$46,$42,$00  ; N
    .byte $3C,$66,$66,$66,$66,$66,$3C,$00  ; O
    .byte $7C,$66,$66,$7C,$60,$60,$60,$00  ; P
    .byte $7C,$66,$66,$7C,$6C,$66,$66,$00  ; R
    .byte $3C,$66,$60,$3C,$06,$66,$3C,$00  ; S
    .byte $7E,$18,$18,$18,$18,$18,$18,$00  ; T
    .byte $66,$66,$66,$66,$66,$66,$3C,$00  ; W
    .byte $00,$00,$18,$00,$00,$18,$00,$00  ; :
    .byte $00,$00,$00,$00,$00,$00,$00,$00  ; space
    .byte $60,$60,$60,$60,$60,$60,$7E,$00  ; L
    .byte $7E,$60,$60,$7C,$60,$60,$60,$00  ; F
    .byte $66,$66,$66,$66,$66,$66,$3C,$00  ; U
    .byte $3C,$66,$66,$6C,$66,$66,$3C,$00  ; G
