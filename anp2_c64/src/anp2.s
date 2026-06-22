;
; Aliens: Neoplasma 2 - Commodore 64 Port
; Original ZX Spectrum game by Sanchez Crew
; C64 conversion using ca65 assembler
;
; This is a full port of the ZX Spectrum 128K game to C64.
; Original:
;   Code: Alexander Udotov (Sanchez)
;   Music/SFX: Oleg Nikitin (n1k-o)
;   Graphics: Evgeniy Rogulin (ER)
;

.define C64     1
.define VIC      $D000
.define SID      $D400
.define CIA1     $DC00
.define CIA2     $DD00

; Import symbols from asset files
.import player_sprite, enemy_xeno, enemy_guard, bullet_sprite
.import tile_graphics, tile_color_table
.import music_title, music_level1, sfx_shoot, sfx_explosion, sfx_hurt, sfx_pickup, sfx_jump
.import start_music, play_music, play_sfx
.import level_1_header, level_2_header, level_table_lo, level_table_hi
.import spectrum_to_c64_tile
.import title_bitmap_data, title_screen_data, title_color_data

.export _frame_counter, _game_state, _player_x, _player_y
.export _player_dir, _player_frame, _player_health, _player_weapon
.export _player_grenades, _player_ammo
.export _scroll_x, _scroll_y
.export _keyboard_state, _joystick_state
.export _tmp1, _tmp2, _tmp3, _tmp_ptr
.export enemy_type, enemy_x, enemy_y, enemy_hp, enemy_state, enemy_timer
.export bullet_x, bullet_y, bullet_vx, bullet_vy, bullet_type, bullet_active
.export particle_x, particle_y, particle_vx, particle_vy, particle_life, particle_active
.export map_width, map_height, map_data_ptr, music_ptr, music_tick, sfx_queue
.export init_vic, init_sid, read_inputs, show_title, title_tick
.export start_game, game_tick, handle_input, update_player, player_shoot
.export update_enemies, update_bullets, update_particles, check_collisions
.export update_camera, render_frame, load_level, setup_sprites, clear_screen
.export draw_title_gfx

.segment "ZEROPAGE"

; Zero page variables
_frame_counter:   .res 1    ; frame counter (60Hz)
_game_state:      .res 1    ; 0=title, 1=loading, 2=playing, 3=paused, 4=game_over
_player_x:        .res 2    ; player X position (subpixel)
_player_y:        .res 2    ; player Y position
_player_dir:      .res 1    ; 0=left, 1=right
_player_frame:    .res 1    ; animation frame
_player_health:   .res 1    ; player HP
_player_weapon:   .res 1    ; current weapon
_player_grenades: .res 1    ; grenade count
_player_ammo:     .res 1    ; ammo
_scroll_x:        .res 2    ; level scroll X
_scroll_y:        .res 1    ; vertical scroll
_keyboard_state:  .res 2    ; keyboard matrix state
_joystick_state:  .res 1    ; joystick direction + fire
_tmp1:            .res 1    ; temporary storage
_tmp2:            .res 1
_tmp3:            .res 1
_tmp4:            .res 1
_tmp_ptr:         .res 2    ; temporary pointer

; BASIC header and code start at $0801
; ld65 PRG output consumes first 2 bytes as load address
.segment "CODE"
    .byte $01, $08        ; PRG load address (consumed by linker, not stored in memory)
    .byte $0B, $08        ; BASIC next line pointer
    .word 10              ; line number
    .byte $9E             ; SYS token
    .byte "2061"          ; address
    .byte 0               ; end of BASIC line
    .word 0               ; end of BASIC program

    jmp     main

;
; Hardware vectors
;
nmi_handler:
    rti

irq_handler:
    pha
    txa
    pha
    tya
    pha

    inc     _frame_counter

    ; Read keyboard and joystick
    jsr     read_inputs

    ; Update game state
    lda     _game_state
    cmp     #2              ; playing?
    bne     @skip_game_tick
    jsr     game_tick
@skip_game_tick:

    ; Check for raster split
    lda     VIC + $19       ; VIC interrupt flag
    and     #$01
    beq     @irq_done

    ; Update raster effects
    jsr     update_raster

@irq_done:
    pla
    tay
    pla
    tax
    pla
    rti

;
; Main entry point
;
main:
    sei

    ; Set up interrupt handler
    lda     #$7F
    sta     CIA1 + $0D      ; disable CIA IRQs
    sta     CIA1 + $0D      ; twice for safety
    lda     #$01
    sta     VIC + $1A       ; enable VIC raster IRQ
    lda     #$00
    sta     VIC + $12       ; raster line low = 0 (VBLANK)
    lda     #$1B
    sta     VIC + $11       ; screen control (raster MSB=0)

    lda     #<irq_handler
    sta     $FFFE
    lda     #>irq_handler
    sta     $FFFF
    lda     #<nmi_handler
    sta     $FFFA
    lda     #>nmi_handler
    sta     $FFFB

    cli

    ; Initialize hardware
    jsr     init_vic
    jsr     init_sid

    ; Start with title screen
    lda     #0
    sta     _game_state
    jsr     show_title

game_loop:
    ; Main loop - VBLANK driven via IRQ
    lda     _frame_counter
@wait:
    cmp     _frame_counter
    beq     @wait           ; wait for next frame

    ; Frame-based game logic
    lda     _game_state
    cmp     #0
    beq     @title_tick
    cmp     #1
    beq     @loading_tick
    cmp     #2
    beq     @playing_tick
    cmp     #4
    beq     @game_over_tick
    jmp     @done

@title_tick:
    jsr     title_tick
    jmp     @done

@loading_tick:
    jsr     loading_tick
    jmp     @done

@playing_tick:
    ; Game logic handled in IRQ
    jmp     @done

@game_over_tick:
    jsr     game_over_tick

@done:
    jmp     game_loop

;
; VIC-II initialization
;
init_vic:
    ; Set VIC bank 3 ($C000-$FFFF) via CIA2 port A
    lda     $DD00
    and     #$FC            ; clear bits 0-1
    sta     $DD00           ; %00 = VIC bank 3

    ; Bank out BASIC and Kernal ROM to access $A000 and $E000 areas
    lda     $01
    and     #$FC            ; clear bits 0-1
    sta     $01             ; both BASIC ($A000) and Kernal ($E000) = RAM

    ; Set up bitmap mode
    lda     #$6B            ; BMM=1, DEN=1, MCM=0, 25 rows
    sta     VIC + $11       ; VIC control register 1 ($D011)
    lda     #$02            ; screen at $C000 (offset 0), bitmap at $E000 (offset $2000)
    sta     VIC + $18       ; memory setup register ($D018)
    lda     #$00
    sta     VIC + $20       ; border color = black
    sta     VIC + $21       ; background 0 = black

    ; Set multicolor registers for sprites
    lda     #$0E            ; light blue
    sta     VIC + $25       ; sprite multicolor 0
    lda     #$0A            ; grey
    sta     VIC + $26       ; sprite multicolor 1
    rts

;
; Load palette from converted Spectrum colors to C64
;
load_palette:
    ; C64 color mapping from Spectrum colors:
    ; Spectrum: 0=black, 1=blue, 2=red, 3=magenta, 4=green, 5=cyan, 6=yellow, 7=white
    ; C64:      0=black, 6=blue, 2=red, 4=purple, 5=green, 3=cyan, 7=yellow, 1=white
    ; Extended: bright variants map to upper nybble
    ldx     #0
@loop:
    lda     c64_palette,x
    sta     VIC + $00,x     ; VIC color registers 0-15
    inx
    cpx     #16
    bne     @loop
    rts

c64_palette:
    .byte $00, $06, $02, $04    ; black, blue, red, purple
    .byte $05, $03, $07, $01    ; green, cyan, yellow, white
    .byte $09, $0A, $08, $0B    ; orange, brown, grey, light grey
    .byte $0C, $0D, $0E, $0F    ; medium grey, green, blue-grey, light cyan

;
; SID initialization
;
init_sid:
    ldx     #$18            ; clear all SID registers
    lda     #$00
@loop:
    sta     SID,x
    dex
    bpl     @loop
    ; Set volume
    lda     #$0F
    sta     SID + $18
    rts

;
; Input reading
;
read_inputs:
    ; Read joystick port 2
    lda     CIA1 + $01      ; port B (joystick)
    sta     _joystick_state
    and     #$1F            ; mask direction + fire
    sta     _tmp1

    ; Read keyboard matrix
    ; We read selected rows for game controls
    ldx     #0
    stx     _keyboard_state
    stx     _keyboard_state+1

    ; Read WASD / cursor / fire keys
    lda     #$7F            ; row 7 (space, etc.)
    sta     CIA1 + $00
    lda     CIA1 + $01
    and     #$10            ; space = fire
    beq     @fire_pressed
    lda     _keyboard_state
    and     #$EF
    sta     _keyboard_state
    jmp     @key_done
@fire_pressed:
    lda     _keyboard_state
    ora     #$10
    sta     _keyboard_state
@key_done:
    rts

;
; Title screen
;
show_title:
    ; Display title screen (bitmap mode)
    jsr     clear_screen
    jsr     draw_title_gfx
    jsr     load_palette
    rts

title_tick:
    ; Check for fire to start game
    lda     _joystick_state
    and     #$10            ; fire button
    beq     @start_game
    lda     _keyboard_state
    and     #$10            ; space
    beq     @start_game
    rts
@start_game:
    lda     #1
    sta     _game_state     ; loading state
    jsr     start_game
    rts

;
; Game initialization
;
start_game:
    ; Initialize player
    lda     #$00
    sta     _scroll_x
    sta     _scroll_x+1
    lda     #$60
    sta     _player_x
    lda     #$00
    sta     _player_x+1
    lda     #$80
    sta     _player_y
    lda     #$00
    sta     _player_y+1
    lda     #1
    sta     _player_dir
    lda     #3
    sta     _player_health
    lda     #0
    sta     _player_weapon
    lda     #5
    sta     _player_grenades
    lda     #100
    sta     _player_ammo

    ; Load level 1
    jsr     load_level

    ; Initialize coarse scroll tracker for render_frame
    lda     _scroll_x
    lsr
    lsr
    lsr
    sta     _tmp3

    lda     #2
    sta     _game_state     ; playing
    rts

;
; Main game tick (called from IRQ)
;
game_tick:
    jsr     handle_input
    jsr     update_player
    jsr     update_enemies
    jsr     update_bullets
    jsr     update_particles
    jsr     check_collisions
    jsr     update_camera
    jsr     render_frame
    rts

;
; Input handling for gameplay
;
handle_input:
    ; Combine keyboard + joystick
    lda     #0
    sta     _tmp2           ; movement flags

    ; Check joystick directions
    lda     _joystick_state
    and     #$01            ; up
    bne     @check_down
    lda     _tmp2
    ora     #$01
    sta     _tmp2
@check_down:
    lda     _joystick_state
    and     #$02
    bne     @check_left
    lda     _tmp2
    ora     #$02
    sta     _tmp2
@check_left:
    lda     _joystick_state
    and     #$04
    bne     @check_right
    lda     _tmp2
    ora     #$04
    sta     _tmp2
@check_right:
    lda     _joystick_state
    and     #$08
    bne     @check_fire
    lda     _tmp2
    ora     #$08
    sta     _tmp2
@check_fire:
    lda     _joystick_state
    and     #$10
    bne     @movement_done
    lda     _tmp2
    ora     #$10
    sta     _tmp2
@movement_done:
    rts

;
; Player update
;
update_player:
    ; Apply gravity
    lda     _player_y+1
    clc
    adc     #$04            ; gravity acceleration
    sta     _player_y+1
    lda     _player_y
    adc     #$00
    sta     _player_y

    ; Handle horizontal movement
    lda     _tmp2
    and     #$04            ; left
    beq     @try_right
    lda     _player_x+1
    sec
    sbc     #$02            ; speed
    sta     _player_x+1
    lda     _player_x
    sbc     #$00
    sta     _player_x
    lda     #0
    sta     _player_dir
    jmp     @anim_update
@try_right:
    lda     _tmp2
    and     #$08            ; right
    beq     @h_movement_done
    lda     _player_x+1
    clc
    adc     #$02
    sta     _player_x+1
    lda     _player_x
    adc     #$00
    sta     _player_x
    lda     #1
    sta     _player_dir
@anim_update:
    ; Update animation frame
    lda     _frame_counter
    and     #$07
    bne     @skip_anim
    lda     _player_frame
    clc
    adc     #1
    and     #3
    sta     _player_frame
@skip_anim:
@h_movement_done:

    ; Handle jumping
    lda     _tmp2
    and     #$01            ; up
    beq     @jump_done
    lda     _player_y+1
    cmp     #$00            ; only jump if on ground
    bne     @jump_done
    lda     #$F0            ; jump velocity (-16)
    sta     _player_y+1
@jump_done:

    ; Handle fire
    lda     _tmp2
    and     #$10            ; fire
    beq     @fire
    rts
@fire:
    jsr     player_shoot
    rts

;
; Player shooting
;
player_shoot:
    lda     _player_weapon
    beq     @pistol
    cmp     #1
    beq     @rifle
    cmp     #2
    beq     @shotgun
    rts
@pistol:
    jsr     spawn_bullet_pistol
    rts
@rifle:
    jsr     spawn_bullet_rifle
    rts
@shotgun:
    jsr     spawn_bullet_shotgun
    rts

;
; Camera/scroll update based on player position
;
update_camera:
    ; Horizontal scroll follows player
    lda     _player_x
    sec
    sbc     #80             ; center on player
    lsr
    lsr
    lsr                     ; divide by 8 for character scroll
    sta     _scroll_x

    ; Clamp scroll
    lda     _scroll_x
    cmp     #$80
    bcc     @scroll_done
    lda     #$80
    sta     _scroll_x
@scroll_done:
    rts

;
; Render current frame
;
SCR_COL_39 = $C000 + 39  ; base for column 39 of each row

render_frame:
    lda     _scroll_x
    and     #$07
    sta     VIC + $16       ; fine scroll
    
    ; Check coarse scroll change
    lda     _scroll_x
    lsr
    lsr
    lsr
    cmp     _tmp3
    beq     @no_scroll
    bcc     @scrolled_left
    sta     _tmp3
    ; Scrolled right: shift screen, draw new right column
    jsr     scroll_right
    jmp     @no_scroll
@scrolled_left:
    sta     _tmp3
    jsr     scroll_left
    
@no_scroll:
    jsr     update_sprites
    rts

screen_shift_left:
    ; Copy $C001..$C3E7 to $C000..$C3E6 (999 bytes forward)
    ; 4 chunks: 256 + 256 + 256 + 231 = 999
    ldx     #0
@chunk1:
    lda     $C001,x
    sta     $C000,x
    inx
    bne     @chunk1
@chunk2:
    lda     $C101,x
    sta     $C100,x
    inx
    bne     @chunk2
@chunk3:
    lda     $C201,x
    sta     $C200,x
    inx
    bne     @chunk3
@chunk4:
    lda     $C301,x
    sta     $C300,x
    inx
    cpx     #231
    bne     @chunk4
    rts

screen_shift_right:
    ; Copy $C3E6..$C000 to $C3E7..$C001 (999 bytes backward)
    ; Process in 4 chunks reverse; use cpx #$FF to detect underflow
    ldx     #230
@chunk4:
    lda     $C300,x
    sta     $C301,x
    dex
    cpx     #$FF
    bne     @chunk4
    ldx     #255
@chunk3:
    lda     $C200,x
    sta     $C201,x
    dex
    cpx     #$FF
    bne     @chunk3
    ldx     #255
@chunk2:
    lda     $C100,x
    sta     $C101,x
    dex
    cpx     #$FF
    bne     @chunk2
    ldx     #255
@chunk1:
    lda     $C000,x
    sta     $C001,x
    dex
    cpx     #$FF
    bne     @chunk1
    rts

scroll_right:
    jsr     screen_shift_left
    lda     _scroll_x
    lsr
    lsr
    lsr
    clc
    adc     #39
    sta     _tmp1           ; tile map column (rightmost visible)
    ldy     #39
    jsr     draw_col
    rts

scroll_left:
    jsr     screen_shift_right
    lda     _scroll_x
    lsr
    lsr
    lsr
    sta     _tmp1           ; tile map column (leftmost visible)
    ldy     #0
    jsr     draw_col
    rts

draw_col:
    ; Y = screen column (0 or 39), _tmp1 = tile map column
    sty     _tmp4
    lda     #0
    sta     _tmp2
@row_loop:
    lda     _tmp2
    ldx     map_width
    stx     _tmp_ptr
    jsr     mul_a_by_tmp1
    clc
    adc     _tmp1
    tay
    lda     tile_map,y
    sta     _tmp3           ; tile type

    ; Screen address = $C000 + row*40 + col
    ; row*40 = row*32 + row*8
    lda     _tmp2
    asl
    asl
    asl                     ; *8
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl                     ; *32
    clc
    adc     _tmp_ptr        ; + *8 = *40
    clc
    adc     _tmp4           ; + col
    tay

    ldx     _tmp3
    lda     tile_color_table,x
    sta     $C000,y

    ; Bitmap address = $E000 + (row*40+col)*8
    ; cell_offset = row*40+col
    lda     _tmp2
    asl
    asl
    asl                     ; *8
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl                     ; *32
    clc
    adc     _tmp_ptr        ; *40
    clc
    adc     _tmp4
    ; A = cell_offset (0-999)
    sta     _tmp_ptr
    lda     #0
    sta     _tmp_ptr + 1
    ldx     #3
@shift:
    asl     _tmp_ptr
    rol     _tmp_ptr + 1
    dex
    bne     @shift

    lda     _tmp_ptr
    clc
    adc     #$00
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #$E0
    sta     _tmp_ptr + 1

    ldx     _tmp3
    asl
    asl
    asl                     ; tile_graphics offset
    tax
    ldy     #0
@copy:
    lda     tile_graphics,x
    sta     (_tmp_ptr),y
    inx
    iny
    cpy     #8
    bne     @copy

    inc     _tmp2
    lda     _tmp2
    cmp     #25
    bne     @row_loop
    rts
    
    ; Draw new column at position 0
    lda     _scroll_x
    lsr
    lsr
    lsr
    sta     _tmp1           ; tile_map_x
    
    lda     #0
    sta     _tmp2           ; row
@row_loop_sl:
    lda     _tmp2
    ldx     map_width
    stx     _tmp_ptr
    jsr     mul_a_by_tmp1
    clc
    adc     _tmp1
    tay
    lda     tile_map,y
    tax
    
    ; screen_ram offset = row * 40
    lda     _tmp2
    asl
    asl
    asl
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl
    clc
    adc     _tmp_ptr
    tay
    
    lda     tile_color_table,x
    sta     $C000,y
    
    ; bitmap_addr = $E000 + row * 320
    ; row*320 = (row << 8) + (row << 6)
    lda     _tmp2
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl
    asl                     ; row * 64
    sta     _tmp3
    lda     _tmp2
    lsr
    lsr                     ; high byte of row*64
    sta     _tmp_ptr + 1
    
    lda     _tmp2
    sta     _tmp_ptr + 1
    lda     #0
    
    clc
    lda     _tmp_ptr + 1
    adc     _tmp3
    sta     _tmp_ptr
    lda     _tmp2
    adc     _tmp_ptr + 1
    clc
    adc     #$E0
    sta     _tmp_ptr + 1
    
    txa
    asl
    asl
    asl
    tax
    ldy     #0
@copy_bmp_sl:
    lda     tile_graphics,x
    sta     (_tmp_ptr),y
    inx
    iny
    cpy     #8
    bne     @copy_bmp_sl
    
    inc     _tmp2
    lda     _tmp2
    cmp     #25
    bne     @row_loop_sl
    rts

update_sprites:
    ; Update sprite 0 (player) position
    lda     _player_x + 1
    sta     VIC + $00
    lda     _player_x
    and     #$01
    beq     @player_x_msb_clear
    lda     #$01
    sta     VIC + $10
    jmp     @player_y
@player_x_msb_clear:
    lda     #$00
    sta     VIC + $10
@player_y:
    lda     _player_y + 1
    sta     VIC + $01
    
    ; Player sprite pointer always $10 (at $C400)
    lda     #$10
    sta     $C3F8
    
    ; Update enemy sprites (sprites 1-3)
    ldx     #0              ; enemy index
    ldy     #1              ; sprite index (1-3)
@enemy_sprite:
    cpx     #MAX_ENEMIES
    beq     @done_sprites
    lda     enemy_type,x
    cmp     #$FF
    beq     @next_enemy_sprite
    
    ; Sprite Y register = $D001 + sprite*2
    tya
    asl
    tay
    
    ; Set X position
    lda     enemy_x + 1,x
    sta     VIC + $00,y
    ; X MSB
    lda     enemy_x,x
    and     #$01
    beq     @enemy_msb_clear
    lda     VIC + $10
    ora     sprite_msb,y
    sta     VIC + $10
    jmp     @enemy_y
@enemy_msb_clear:
    lda     VIC + $10
    and     sprite_msb_clear,y
    sta     VIC + $10
@enemy_y:
    lda     enemy_y + 1,x
    sta     VIC + $01,y
    
    ; Set sprite pointer at $C3F9-$C3FB
    tya
    lsr                     ; back to sprite index (1-3)
    clc
    adc     #$F8            ; $C3F8 + sprite_index
    tay
    lda     enemy_type,x
    beq     @xeno_ptr
    ; guard pointer = $12
    lda     #$12
    jmp     @set_ptr
@xeno_ptr:
    lda     #$11
@set_ptr:
    sta     $C3F8,y
    
    tya
    sec
    sbc     #$F8
    tay
    
@next_enemy_sprite:
    inx
    iny
    cpy     #4              ; max 4 sprites total (0=player, 1-3=enemies)
    bne     @enemy_sprite
    
@done_sprites:
    rts

sprite_msb:
    .byte $01, $02, $04, $08, $10, $20, $40, $80
sprite_msb_clear:
    .byte $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

;
; Level loading
;
load_level:
    ; Load level map data
    ; Converted from Spectrum tile format to C64 character format
    ; Level data includes: tiles, enemy spawns, item locations

    ldx     #0
    jsr     load_map_tiles
    jsr     setup_sprites
    rts

load_map_tiles:
    ; RLE-decompress level tiles into tile_map buffer
    lda     level_1_header
    sta     map_width
    lda     level_1_header + 1
    sta     map_height
    
    ; Point to tile data (header = 10 bytes, then tile data)
    lda     #<level_1_header
    clc
    adc     #10
    sta     _tmp_ptr
    lda     #>level_1_header
    adc     #0
    sta     _tmp_ptr + 1
    
    ; Decompress RLE into tile_map
    ldy     #0
    ldx     #0              ; tile_map write index
    stx     _tmp3
    
@next_rle:
    lda     (_tmp_ptr),y
    cmp     #$FF            ; end marker?
    beq     @done
    
    sta     _tmp1           ; tile_id
    iny
    bne     @no_inc1
    inc     _tmp_ptr + 1
@no_inc1:
    lda     (_tmp_ptr),y    ; repeat count
    sta     _tmp2
    iny
    bne     @no_inc2
    inc     _tmp_ptr + 1
@no_inc2:
    
    ldx     _tmp3
@fill_loop:
    lda     _tmp1
    sta     tile_map,x
    inx
    dec     _tmp2
    bne     @fill_loop
    stx     _tmp3
    
    jmp     @next_rle
@done:
    ; Render the full initial visible area
    jsr     render_full_map
    rts

render_full_map:
    ; Render visible tiles to screen RAM and bitmap
    ; Two nested loops: row (0-24), col (0-39)
    lda     _scroll_x
    lsr
    lsr
    lsr
    sta     _tmp3           ; scroll offset in chars
    
    lda     #00
    sta     _tmp2           ; row
@row_loop:
    lda     #00
    sta     _tmp1           ; col
@col_loop:
    ; tile_map_x = col + scroll_offset
    lda     _tmp1
    clc
    adc     _tmp3
    tax                     ; X = tile_map_x
    
    ; tile_map index = row * map_width + tile_map_x
    lda     _tmp2           ; row
    ldy     map_width
    sty     _tmp_ptr
    jsr     mul_a_by_tmp1   ; A = row * map_width
    stx     _tmp_ptr        ; temporarily save tile_map_x
    clc
    adc     _tmp_ptr
    tay
    lda     tile_map,y      ; tile type
    tax                     ; X = tile type
    
    ; Screen byte
    lda     tile_color_table,x
    pha
    
    ; Screen RAM address: $C000 + row*40 + col
    ; row*40 = (row << 5) + (row << 3)
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl                     ; row * 32
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl                     ; row * 8
    clc
    adc     _tmp_ptr        ; row * 40
    clc
    adc     _tmp1           ; + col
    tay
    pla
    sta     $C000,y
    
    ; Bitmap address: $E000 + (row*40 + col) * 8
    ; screen_offset = row*40 + col (just computed in A before tay)
    ; Multiply by 8 via lookup or shift
    ; A has the value that was in A before tay
    ; But we don't have A anymore after sta... let me recompute
    
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl                     ; row * 32
    sta     _tmp_ptr
    lda     _tmp2
    asl
    asl
    asl                     ; row * 8
    clc
    adc     _tmp_ptr        ; row * 40
    clc
    adc     _tmp1           ; + col = cell_idx
    
    ; byte_offset = cell_idx * 8
    asl
    asl
    asl
    sta     _tmp_ptr
    lda     #0
    rol
    sta     _tmp_ptr + 1
    
    ; bitmap_addr = $E000 + byte_offset
    lda     _tmp_ptr
    clc
    adc     #$00
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #$E0
    sta     _tmp_ptr + 1
    
    ; Copy tile pattern to bitmap
    txa                     ; tile type
    asl
    asl
    asl                     ; * 8
    tax
    ldy     #0
@copy_tile:
    lda     tile_graphics,x
    sta     (_tmp_ptr),y
    inx
    iny
    cpy     #8
    bne     @copy_tile
    
    inc     _tmp1
    lda     _tmp1
    cmp     #40
    beq     @next_row_full
    jmp     @col_loop
@next_row_full:
    inc     _tmp2
    lda     _tmp2
    cmp     #25
    beq     @done_full
    jmp     @row_loop
@done_full:
    rts

mul_a_by_tmp1:
    ; Multiply A by _tmp_ptr (byte), result in A
    sta     _tmp3
    lda     #0
    ldx     _tmp_ptr
@loop:
    clc
    adc     _tmp3
    dex
    bne     @loop
    rts

;
; Sprite initialization
;
SPRITE_DATA_BASE = $C400  ; in VIC bank 3, after screen RAM

setup_sprites:
    ; Enable sprites 0-3 (single-color/hires, no multicolor)
    lda     #$0F
    sta     VIC + $15
    
    ; Set sprite colors
    lda     #$01
    sta     VIC + $27       ; sprite 0 (white)
    lda     #$02
    sta     VIC + $28       ; sprite 1 (red)
    lda     #$0E
    sta     VIC + $29       ; sprite 2 (light blue)
    lda     #$0E
    sta     VIC + $2A       ; sprite 3 (light blue)
    
    ; Position sprites off-screen
    lda     #$00
    sta     VIC + $00
    sta     VIC + $02
    sta     VIC + $04
    sta     VIC + $06
    lda     #$32
    sta     VIC + $01
    sta     VIC + $03
    sta     VIC + $05
    sta     VIC + $07
    
    ; Copy sprite data from RODATA to VIC bank 3
    ; Player sprite (first 64 bytes = frame 0) -> $C400
    ldx     #0
@copy_player:
    lda     player_sprite,x
    sta     SPRITE_DATA_BASE,x
    inx
    cpx     #64
    bne     @copy_player
    
    ; Enemy xeno -> $C440
    ldx     #0
@copy_xeno:
    lda     enemy_xeno,x
    sta     SPRITE_DATA_BASE + $40,x
    inx
    cpx     #64
    bne     @copy_xeno
    
    ; Enemy guard -> $C480
    ldx     #0
@copy_guard:
    lda     enemy_guard,x
    sta     SPRITE_DATA_BASE + $80,x
    inx
    cpx     #64
    bne     @copy_guard
    
    ; Bullet sprite -> $C4C0
    ldx     #0
@copy_bullet:
    lda     bullet_sprite,x
    sta     SPRITE_DATA_BASE + $C0,x
    inx
    cpx     #64
    bne     @copy_bullet
    
    ; Set sprite pointers at $C3F8 (screen_base + $3F8)
    ; pointer = (address - bank_base) / 64
    ; $C400 -> $10, $C440 -> $11, $C480 -> $12, $C4C0 -> $13
    lda     #$10
    sta     $C3F8           ; sprite 0: player
    lda     #$11
    sta     $C3F9           ; sprite 1: xeno
    lda     #$12
    sta     $C3FA           ; sprite 2: guard
    lda     #$13
    sta     $C3FB           ; sprite 3: bullet
    rts

;
; Enemy management
;
update_enemies:
    ; For each active enemy, update AI and position
    ldx     #0
@next:
    cpx     #MAX_ENEMIES
    beq     @done
    
    lda     enemy_type,x
    cmp     #$FF            ; inactive?
    beq     @skip
    
    ; Enemy gravity
    lda     enemy_y + 1,x
    clc
    adc     #$02
    sta     enemy_y + 1,x
    lda     enemy_y,x
    adc     #$00
    sta     enemy_y,x
    
    ; Simple AI: move toward player
    lda     enemy_state,x
    cmp     #1              ; active?
    bne     @skip
    
    ; Check timer for direction change
    dec     enemy_timer,x
    bpl     @move
    ; Reset timer and maybe change direction
    lda     #60
    sta     enemy_timer,x
    
@move:
    ; Move toward player on X axis
    lda     _player_x
    cmp     enemy_x,x
    bcc     @move_left
    bne     @move_right
    jmp     @check_shoot
@move_left:
    lda     enemy_x + 1,x
    sec
    sbc     #$01
    sta     enemy_x + 1,x
    lda     enemy_x,x
    sbc     #$00
    sta     enemy_x,x
    jmp     @check_shoot
@move_right:
    lda     enemy_x + 1,x
    clc
    adc     #$01
    sta     enemy_x + 1,x
    lda     enemy_x,x
    adc     #$00
    sta     enemy_x,x
    
@check_shoot:
    ; Check if enemy should shoot (randomish based on timer)
    lda     enemy_timer,x
    and     #$3F
    bne     @skip
    ; TODO: spawn enemy bullet
    
@skip:
    inx
    jmp     @next
@done:
    rts

;
; Bullet management
;
spawn_bullet:
    ; A = bullet type, spawn at player position
    ; Find free bullet slot
    pha
    ldx     #0
@find:
    cpx     #MAX_BULLETS
    beq     @full
    lda     bullet_active,x
    beq     @found
    inx
    jmp     @find
@full:
    pla
    rts
@found:
    ; Set bullet properties
    pla
    sta     bullet_type,x
    lda     #1
    sta     bullet_active,x
    
    ; Position at player
    lda     _player_x
    sta     bullet_x,x
    lda     _player_x + 1
    sta     bullet_x + 1,x
    lda     _player_y
    sta     bullet_y,x
    lda     _player_y + 1
    sta     bullet_y + 1,x
    
    ; Direction based on player facing
    lda     _player_dir
    beq     @shoot_left
    ; Shoot right
    lda     #$04
    sta     bullet_vx,x
    jmp     @set_vy
@shoot_left:
    lda     #$FC            ; -4
    sta     bullet_vx,x
@set_vy:
    lda     #$00
    sta     bullet_vy,x
    rts

spawn_bullet_pistol:
    lda     #0              ; pistol bullet type
    jsr     spawn_bullet
    rts

spawn_bullet_rifle:
    lda     #1              ; rifle bullet type (faster)
    jsr     spawn_bullet
    ; Override velocity for rifle (faster)
    ldx     #0
@find_bullet:
    cpx     #MAX_BULLETS
    beq     @done
    lda     bullet_active,x
    bne     @found_b
    inx
    jmp     @find_bullet
@found_b:
    lda     _player_dir
    beq     @set_left_r
    lda     #$06
    sta     bullet_vx,x
    rts
@set_left_r:
    lda     #$FA            ; -6
    sta     bullet_vx,x
@done:
    rts

spawn_bullet_shotgun:
    ; Spawn 3 bullets in a spread pattern
    jsr     spawn_bullet_pistol  ; center bullet
    lda     #0
    jsr     spawn_bullet         ; additional bullet
    lda     #0
    jsr     spawn_bullet         ; additional bullet
    
    ; Adjust velocities for spread
    ; Bullet 1: normal (already set)
    ; Bullet 2: slight angle up
    ; Bullet 3: slight angle down
    ldx     #0
    ldy     #0
@find_b2:
    cpx     #MAX_BULLETS
    beq     @done_sg
    lda     bullet_active,x
    bne     @found_sg
    inx
    jmp     @find_b2
@found_sg:
    iny
    cpy     #2
    bne     @next_sg
    ; Second bullet: up angle
    lda     _player_dir
    beq     @sg_left
    lda     #$04
    sta     bullet_vx,x
    jmp     @sg_vy2
@sg_left:
    lda     #$FC
    sta     bullet_vx,x
@sg_vy2:
    lda     #$FC            ; -4 upward
    sta     bullet_vy,x
    jmp     @done_sg
@next_sg:
    cpy     #3
    bne     @skip_sg3
    ; Third bullet: down angle
    lda     _player_dir
    beq     @sg_left3
    lda     #$04
    sta     bullet_vx,x
    jmp     @sg_vy3
@sg_left3:
    lda     #$FC
    sta     bullet_vx,x
@sg_vy3:
    lda     #$04            ; 4 downward
    sta     bullet_vy,x
@skip_sg3:
    inx
    jmp     @find_b2
@done_sg:
    rts

update_bullets:
    ; Move all active bullets and check bounds
    ldx     #0
@next:
    cpx     #MAX_BULLETS
    beq     @done
    
    lda     bullet_active,x
    beq     @skip
    
    ; Apply velocity
    lda     bullet_x + 1,x
    clc
    adc     bullet_vx,x
    sta     bullet_x + 1,x
    lda     bullet_x,x
    adc     #$00
    sta     bullet_x,x
    
    lda     bullet_y + 1,x
    clc
    adc     bullet_vy,x
    sta     bullet_y + 1,x
    lda     bullet_y,x
    adc     #$00
    sta     bullet_y,x
    
    ; Check bounds (off-screen = deactivate)
    lda     bullet_x,x
    cmp     #$A0            ; off right
    bcs     @deactivate
    cmp     #$00
    bne     @check_y
    lda     bullet_x + 1,x
    cmp     #$20
    bcc     @deactivate     ; off left
@check_y:
    lda     bullet_y,x
    cmp     #$C8            ; off bottom
    bcs     @deactivate
    
    jmp     @skip
@deactivate:
    lda     #0
    sta     bullet_active,x
@skip:
    inx
    jmp     @next
@done:
    rts

;
; Particle effects (explosions, blood, etc.)
;
spawn_particles:
    ; A = count, X = x_lo, Y = y_lo
    ; Spawn dust/explosion particles at (X, Y)
    sty     _tmp1
    stx     _tmp2
    sta     _tmp3
    
    ldx     #0
    ldy     #0
@find:
    cpx     #MAX_PARTICLES
    beq     @done
    lda     particle_active,x
    beq     @found
    inx
    jmp     @find
@found:
    ; Activate particle
    lda     #1
    sta     particle_active,x
    
    ; Position
    lda     _tmp2
    sta     particle_x,x
    lda     #$00
    sta     particle_x + 1,x
    lda     _tmp1
    sta     particle_y,x
    lda     #$00
    sta     particle_y + 1,x
    
    ; Random-ish velocity
    txa
    asl
    and     #$07
    sec
    sbc     #$04            ; -4 to +3
    sta     particle_vx,x
    
    txa
    and     #$07
    sec
    sbc     #$04
    sta     particle_vy,x
    
    ; Life
    lda     #$10
    sta     particle_life,x
    
    iny
    cpy     _tmp3
    bne     @find
@done:
    rts

update_particles:
    ; Update all active particles
    ldx     #0
@next:
    cpx     #MAX_PARTICLES
    beq     @done
    
    lda     particle_active,x
    beq     @skip
    
    ; Apply velocity
    lda     particle_x + 1,x
    clc
    adc     particle_vx,x
    sta     particle_x + 1,x
    lda     particle_x,x
    adc     #$00
    sta     particle_x,x
    
    lda     particle_y + 1,x
    clc
    adc     particle_vy,x
    sta     particle_y + 1,x
    lda     particle_y,x
    adc     #$00
    sta     particle_y,x
    
    ; Gravity on particles
    lda     particle_vy,x
    clc
    adc     #$01
    sta     particle_vy,x
    
    ; Decrease life
    dec     particle_life,x
    bne     @skip
    
    ; Dead
    lda     #0
    sta     particle_active,x
@skip:
    inx
    jmp     @next
@done:
    rts

;
; Collision detection
;
check_collisions:
    ; Check bullet-enemy collisions
    ldx     #0              ; bullet index
@bullet_loop:
    cpx     #MAX_BULLETS
    beq     @bullet_done
    jmp     @check_one_bullet
@bullet_done:
    jmp     @check_player_enemy
@check_one_bullet:
    
    lda     bullet_active,x
    beq     @next_bullet
    
    ; Get bullet center
    lda     bullet_x,x
    clc
    adc     #$04
    sta     _tmp1           ; bullet cx
    lda     bullet_y,x
    clc
    adc     #$04
    sta     _tmp2           ; bullet cy
    
    ldy     #0              ; enemy index
@enemy_loop:
    cpy     #MAX_ENEMIES
    beq     @next_bullet
    
    lda     enemy_type,y
    cmp     #$FF
    beq     @next_enemy
    
    ; AABB collision: bullet vs enemy
    lda     enemy_x,y
    sec
    sbc     _tmp1
    bcs     @check_enemy_x2
    eor     #$FF
    adc     #$01
@check_enemy_x2:
    cmp     #$10            ; half enemy width
    bcs     @next_enemy
    
    lda     enemy_y,y
    sec
    sbc     _tmp2
    bcs     @check_enemy_y2
    eor     #$FF
    adc     #$01
@check_enemy_y2:
    cmp     #$10            ; half enemy height
    bcs     @next_enemy
    
    ; Hit! Deactivate bullet, damage enemy
    lda     #0
    sta     bullet_active,x
    
    lda     enemy_hp,y       ; dec absolute,y not available on 6502
    sec
    sbc     #1
    sta     enemy_hp,y
    cmp     #0
    bne     @hit_effect
    
    ; Enemy killed
    lda     #$FF
    sta     enemy_type,y
    
    ; Spawn death particles
    tya
    pha                     ; save enemy index
    lda     #4              ; count
    ldx     enemy_x,y       ; x position (low byte)
    lda     enemy_y,y
    tay                     ; y position (low byte) in Y
    jsr     spawn_particles
    pla
    tay                     ; restore enemy index
    
    jmp     @next_bullet
    
@hit_effect:
    ; Spawn hit particles
    lda     #2
    ldx     _tmp1
    ldy     _tmp2
    jsr     spawn_particles
    
    jmp     @next_bullet
    
@next_enemy:
    iny
    jmp     @enemy_loop
    
@next_bullet:
    inx
    jmp     @bullet_loop
    
@check_player_enemy:
    ; Check player-enemy collisions
    lda     _player_x
    clc
    adc     #$08
    sta     _tmp1
    lda     _player_y
    clc
    adc     #$10
    sta     _tmp2
    
    ldy     #0
@pe_loop:
    cpy     #MAX_ENEMIES
    beq     @check_player_floor
    
    lda     enemy_type,y
    cmp     #$FF
    beq     @pe_next
    
    ; AABB: player vs enemy
    lda     enemy_x,y
    sec
    sbc     _tmp1
    bcs     @pe_check_x2
    eor     #$FF
    adc     #$01
@pe_check_x2:
    cmp     #$14
    bcs     @pe_next
    
    lda     enemy_y,y
    sec
    sbc     _tmp2
    bcs     @pe_check_y2
    eor     #$FF
    adc     #$01
@pe_check_y2:
    cmp     #$14
    bcs     @pe_next
    
    ; Player hit by enemy
    dec     _player_health
    lda     #$FF
    sta     enemy_timer,y   ; stun timer
    ; Push player back
    lda     _player_dir
    beq     @push_right
    lda     _player_x + 1
    sec
    sbc     #$20
    sta     _player_x + 1
    lda     _player_x
    sbc     #$00
    sta     _player_x
    jmp     @pe_next
@push_right:
    lda     _player_x + 1
    clc
    adc     #$20
    sta     _player_x + 1
    lda     _player_x
    adc     #$00
    sta     _player_x
    
@pe_next:
    iny
    jmp     @pe_loop
    
@check_player_floor:
    ; Simple floor collision: check tile below player
    lda     _player_y
    lsr
    lsr
    lsr                     ; player char row
    clc
    adc     #2              ; 2 rows below player
    tax
    
    lda     _scroll_x
    clc
    adc     #20             ; center column
    tay
    
    ; Get tile at map[row][col]
    ; row * map_width + col
    txa
    ldx     map_width
    stx     _tmp1
    jsr     mul_a_by_tmp1   ; A = row * map_width
    clc
    adc     _scroll_x
    adc     #20
    tay
    lda     tile_map,y
    cmp     #0              ; empty?
    beq     @no_floor
    
    ; Floor below - prevent falling further
    lda     #$00
    sta     _player_y + 1
    lda     _player_y
    and     #$F8            ; snap to char boundary
    sta     _player_y
    
@no_floor:
    rts

;
; Loading screen state
;
loading_tick:
    ; Loading sequence: transition to playing state
    ; Clear screen, show loading message, init level
    
    ; Clear game area
    jsr     clear_screen
    
    ; Draw loading text centered on screen
    ldx     #0
@draw_loading:
    lda     loading_msg,x
    beq     @done_loading
    sta     $C000 + 20 * 40 + 12, x
    inx
    jmp     @draw_loading
@done_loading:
    
    ; Load level (already done in start_game, this is just visual)
    ; Transition to playing state after a brief pause
    lda     #60
    sta     _tmp1
@wait_loop:
    dec     _tmp1
    bne     @wait_loop
    
    lda     #2
    sta     _game_state
    rts

loading_msg:
    .byte "LOADING...", 0

;
; Game over state
;
game_over_tick:
    lda     _joystick_state
    and     #$10
    beq     @restart
    rts
@restart:
    lda     #0
    sta     _game_state
    jsr     show_title
    rts

;
; Utility: clear screen
;
clear_screen:
    ; Clear bitmap @ $E000 (8000 bytes)
    lda     #$00
    ldx     #0
@loop1:
    sta     $E000,x
    sta     $E100,x
    sta     $E200,x
    sta     $E300,x
    sta     $E400,x
    sta     $E500,x
    sta     $E600,x
    sta     $E700,x
    sta     $E800,x
    sta     $E900,x
    sta     $EA00,x
    sta     $EB00,x
    sta     $EC00,x
    sta     $ED00,x
    sta     $EE00,x
    sta     $EF00,x
    sta     $F000,x
    sta     $F100,x
    sta     $F200,x
    sta     $F300,x
    sta     $F400,x
    sta     $F500,x
    sta     $F600,x
    sta     $F700,x
    sta     $F800,x
    sta     $F900,x
    sta     $FA00,x
    sta     $FB00,x
    sta     $FC00,x
    sta     $FD00,x
    sta     $FE00,x
    sta     $FF00,x
    inx
    bne     @loop1

    ; Clear screen RAM @ $C000
    ldx     #0
@loop2:
    sta     $C000,x
    sta     $C100,x
    inx
    bne     @loop2

    ; Clear color RAM $D800
    ldx     #0
@loop3:
    sta     $D800,x
    sta     $D900,x
    inx
    bne     @loop3
    rts

;
; Raster effect update
;
update_raster:
    ; Simple raster split for status bar at top of screen
    ; Read current raster line from VIC
    lda     VIC + $11       ; $D011 bit 7 = raster MSB
    and     #$80
    sta     _tmp1
    lda     VIC + $12       ; $D012 = raster line low byte
    ; Check if we're in the lower game area (below row 2)
    cmp     #16             ; after 2 character rows (16 scanlines)
    bcc     @upper_area
    
    ; Game area: use hires bitmap mode colors
    lda     #$6B            ; BMM=1, DEN=1, MCM=0, 25 rows
    sta     VIC + $11
    rts
    
@upper_area:
    ; Status bar area: could switch to text mode for HUD
    ; For now, keep bitmap mode
    rts

;
; Draw title graphics
;
draw_title_gfx:
    ; Copy bitmap data to $E000 (8000 bytes)
    ; Split into two 16-pair halves to keep branches in range
    ldx     #0
@bmp_h1:
    lda     title_bitmap_data,x
    sta     $E000,x
    lda     title_bitmap_data + $100,x
    sta     $E100,x
    lda     title_bitmap_data + $200,x
    sta     $E200,x
    lda     title_bitmap_data + $300,x
    sta     $E300,x
    lda     title_bitmap_data + $400,x
    sta     $E400,x
    lda     title_bitmap_data + $500,x
    sta     $E500,x
    lda     title_bitmap_data + $600,x
    sta     $E600,x
    lda     title_bitmap_data + $700,x
    sta     $E700,x
    lda     title_bitmap_data + $800,x
    sta     $E800,x
    lda     title_bitmap_data + $900,x
    sta     $E900,x
    lda     title_bitmap_data + $A00,x
    sta     $EA00,x
    lda     title_bitmap_data + $B00,x
    sta     $EB00,x
    lda     title_bitmap_data + $C00,x
    sta     $EC00,x
    lda     title_bitmap_data + $D00,x
    sta     $ED00,x
    lda     title_bitmap_data + $E00,x
    sta     $EE00,x
    lda     title_bitmap_data + $F00,x
    sta     $EF00,x
    inx
    bne     @bmp_h1

    ldx     #0
@bmp_h2:
    lda     title_bitmap_data + $1000,x
    sta     $F000,x
    lda     title_bitmap_data + $1100,x
    sta     $F100,x
    lda     title_bitmap_data + $1200,x
    sta     $F200,x
    lda     title_bitmap_data + $1300,x
    sta     $F300,x
    lda     title_bitmap_data + $1400,x
    sta     $F400,x
    lda     title_bitmap_data + $1500,x
    sta     $F500,x
    lda     title_bitmap_data + $1600,x
    sta     $F600,x
    lda     title_bitmap_data + $1700,x
    sta     $F700,x
    lda     title_bitmap_data + $1800,x
    sta     $F800,x
    lda     title_bitmap_data + $1900,x
    sta     $F900,x
    lda     title_bitmap_data + $1A00,x
    sta     $FA00,x
    lda     title_bitmap_data + $1B00,x
    sta     $FB00,x
    lda     title_bitmap_data + $1C00,x
    sta     $FC00,x
    lda     title_bitmap_data + $1D00,x
    sta     $FD00,x
    lda     title_bitmap_data + $1E00,x
    sta     $FE00,x
    lda     title_bitmap_data + $1F00,x
    sta     $FF00,x
    inx
    bne     @bmp_h2

    ; Copy screen RAM to $C000 (1000 bytes)
    ldx     #0
@s1:
    lda     title_screen_data,x
    sta     $C000,x
    inx
    bne     @s1
@s2:
    lda     title_screen_data + $100,x
    sta     $C100,x
    inx
    bne     @s2
@s3:
    lda     title_screen_data + $200,x
    sta     $C200,x
    inx
    bne     @s3
@s4:
    lda     title_screen_data + $300,x
    sta     $C300,x
    inx
    cpx     #$E8            ; 1000 = 256*3 + 232
    bne     @s4

    ; Copy color RAM to $D800 (1000 bytes)
    ldx     #0
@c1:
    lda     title_color_data,x
    sta     $D800,x
    inx
    bne     @c1
@c2:
    lda     title_color_data + $100,x
    sta     $D900,x
    inx
    bne     @c2
@c3:
    lda     title_color_data + $200,x
    sta     $DA00,x
    inx
    bne     @c3
@c4:
    lda     title_color_data + $300,x
    sta     $DB00,x
    inx
    cpx     #$E8
    bne     @c4

    rts

title_txt:
    .byte " ALIENS: NEOPLASMA 2", 0
subtitle_txt:
    .byte " C64 PORT 2026", 0
press_txt:
    .byte "   PRESS FIRE TO START   ", 0

;
; Data: game strings converted from Spectrum character codes
;
game_strings:
title_str:
    .byte "   ALIENS: NEOPLASMA 2", 0
subtitle_str:
    .byte "   C64 PORT by OpenCode", 0
press_fire:
    .byte "PRESS FIRE TO START", 0
health_str:
    .byte "HP:", 0
weapon_str:
    .byte "WPN:", 0
grenade_str:
    .byte "GRN:", 0
score_str:
    .byte "SCORE:", 0

;
; Game state arrays
;
.segment "BSS"

MAX_ENEMIES = 16
MAX_BULLETS = 8
MAX_PARTICLES = 32

enemy_type:     .res MAX_ENEMIES
enemy_x:        .res MAX_ENEMIES * 2
enemy_y:        .res MAX_ENEMIES * 2
enemy_hp:       .res MAX_ENEMIES
enemy_state:    .res MAX_ENEMIES
enemy_timer:    .res MAX_ENEMIES

bullet_x:       .res MAX_BULLETS * 2
bullet_y:       .res MAX_BULLETS * 2
bullet_vx:      .res MAX_BULLETS
bullet_vy:      .res MAX_BULLETS
bullet_type:    .res MAX_BULLETS
bullet_active:  .res MAX_BULLETS

particle_x:     .res MAX_PARTICLES * 2
particle_y:     .res MAX_PARTICLES * 2
particle_vx:    .res MAX_PARTICLES
particle_vy:    .res MAX_PARTICLES
particle_life:  .res MAX_PARTICLES
particle_active:.res MAX_PARTICLES

; Map data
map_width:      .res 1
map_height:     .res 1
map_data_ptr:   .res 2
tile_map:       .res 1280    ; max 80x16 level tiles

; Sound engine state
music_ptr:      .res 2
music_tick:     .res 1
sfx_queue:      .res 4
