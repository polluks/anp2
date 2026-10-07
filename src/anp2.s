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

; Player physics constants (signed velocity in _player_vy)
PLAYER_GRAVITY  = 4    ; vertical acceleration (px/frame^2)
PLAYER_JUMP_VY  = $F0  ; jump velocity (-16 px/frame)
PLAYER_MAX_FALL = 8    ; terminal fall speed, capped at one tile per frame

; Import symbols from asset files
.import player_sprite, enemy_xeno, enemy_guard, bullet_sprite
.import tile_graphics, tile_color_table
.import hud_glyphs
.import music_title_0, music_title_1, music_title_2
.import music_level_0, music_level_1, music_level_2
.import sfx_shoot, sfx_explosion, sfx_hurt, sfx_pickup, sfx_jump
.import start_music, play_music, play_sfx
.import level_1_header, level_2_header
.import level_start_x_lo, level_start_y_lo
.import level_1_enemies, level_2_enemies
.import level_1_items, level_2_items, level_table_lo, level_table_hi
.import level_1_enemies, level_1_items
.import spectrum_to_c64_tile
.import title_bitmap_data, title_screen_data, title_color_data

.export _frame_counter, _game_state, _player_x, _player_y
.export _player_dir, _player_frame, _player_health, _player_weapon
.export _player_grenades, _player_ammo, _player_score
.export _scroll_x, _scroll_y
.export _keyboard_state, _joystick_state
.export _tmp1, _tmp2, _tmp3, _tmp_ptr, _tmp5, _tmp6, _tmp7
.export _level_index, _item_ptr, _enemy_ptr
.export enemy_type, enemy_x, enemy_y, enemy_hp, enemy_state, enemy_timer
.export bullet_x, bullet_y, bullet_vx, bullet_vy, bullet_type, bullet_active
.export particle_x, particle_y, particle_vx, particle_vy, particle_life, particle_active
.export map_width, map_height, map_data_ptr
.export music_ptr0, music_ptr1, music_ptr2
.export music_start0, music_start1, music_start2
.export music_tick0, music_tick1, music_tick2, sfx_queue
.export init_vic, init_sid, read_inputs, show_title, title_tick
.export start_game, game_tick, handle_input, update_player, player_shoot
.export update_enemies, update_bullets, update_particles, check_collisions
.export update_camera, render_frame, load_level, setup_sprites, clear_screen
.export draw_title_gfx, get_tile, mul_map_width

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
_player_score:    .res 2    ; score
_scroll_x:        .res 2    ; level scroll X
_scroll_y:        .res 1    ; vertical scroll
_keyboard_state:  .res 2    ; keyboard matrix state
_joystick_state:  .res 1    ; joystick direction + fire
_on_ground:       .res 1    ; 1 = player on solid ground
_player_vy:       .res 1    ; signed player vertical velocity (px/frame)
_invincible_timer:.res 1    ; invincibility countdown after hit
_tmp1:            .res 1    ; temporary storage
_tmp2:            .res 1
_tmp3:            .res 1
_tmp4:            .res 1
_tmp5:            .res 1
_tmp6:            .res 1
_tmp7:            .res 1
_tmp_ptr:         .res 2    ; temporary pointer
_scroll_y_prev:   .res 1    ; last rendered vertical scroll row
_scroll_x_prev:   .res 1    ; last rendered coarse horizontal scroll column
_scroll_px:       .res 1    ; vertical scroll in pixels (row * 8)
_level_index:     .res 1    ; current level (0 or 1)
_item_ptr:        .res 2    ; level item data pointer
_enemy_ptr:       .res 2    ; level enemy data pointer

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

    ; Play music every frame
    jsr     play_music

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
    ; Rendering runs here, outside the IRQ. Vertical scrolling shifts
    ; 7.7KB of bitmap RAM, which overruns the 50Hz interrupt.
    jsr     render_frame
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
    lda     #0
    jsr     start_music
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
    rts

;
; Game initialization
;
start_game:
    ; Initialize player
    lda     #$00
    sta     _scroll_x
    sta     _scroll_x+1
    sta     _scroll_y
    sta     _scroll_y_prev
    sta     _scroll_px
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
    lda     #0
    sta     _player_score
    sta     _player_score + 1

    ; Load the current level, then set the player start from its header
    lda     _level_index
    jsr     load_level

    ldx     _level_index
    lda     level_start_x_lo,x
    sta     _player_x + 1
    lda     #$00
    sta     _player_x
    lda     level_start_y_lo,x
    sta     _player_y + 1
    lda     #$00
    sta     _player_y
    sta     _player_vy
    lda     #1
    sta     _on_ground

    lda     #1
    jsr     start_music

    ; Position the camera, then draw the map for the resulting scroll offset
    jsr     update_camera
    jsr     render_full_map

    ; Initialize scroll trackers for render_frame
    lda     _scroll_x
    lsr
    lsr
    lsr
    sta     _scroll_x_prev
    lda     _scroll_y
    sta     _scroll_y_prev

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
    jsr     update_items
    jsr     update_camera

    ; Check for player death
    lda     _player_health
    bne     @alive
    lda     #4
    sta     _game_state     ; game over
@alive:
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
    ; Decrement invincibility timer
    lda     _invincible_timer
    beq     @skip_inv_dec
    dec     _invincible_timer
@skip_inv_dec:

    ; Apply gravity to velocity, capped at terminal fall speed. A rising
    ; (negative) velocity is never clamped; only the downward speed is.
    lda     _player_vy
    clc
    adc     #PLAYER_GRAVITY
    bmi     @gravity_ok
    cmp     #PLAYER_MAX_FALL
    bcc     @gravity_ok
    lda     #PLAYER_MAX_FALL
@gravity_ok:
    sta     _player_vy

    ; Integrate velocity into position (_player_y is 16-bit, +1 = pixel).
    ; _player_vy is signed: add downward, subtract upward.
    lda     _player_vy
    bmi     @vy_negative

    ; vy >= 0: 16-bit add
    lda     _player_y
    clc
    adc     _player_vy
    sta     _player_y
    lda     _player_y + 1
    adc     #0
    sta     _player_y + 1
    bcs     @vy_integrated   ; carried past the 16-bit field: leave as-is

    ; Clamp descent to the bottom of the level. The position is 16-bit so it
    ; cannot wrap at 256, but the VIC register is still 8-bit: a fall into an
    ; open pit would keep growing the world Y and the sprite would reappear at
    ; the top of the screen. Pin the player to the last map row instead.
    lda     map_height
    asl
    asl
    asl                     ; height * 8
    beq     @vy_integrated  ; height wraps a byte (tall map): skip clamp
    sec
    sbc     #8              ; bottom pixel of playable area
    beq     @vy_integrated  ; degenerate height
    cmp     _player_y + 1
    bcs     @vy_integrated  ; still above the bottom
    sta     _player_y + 1
    lda     #0
    sta     _player_y
    sta     _player_vy
    jmp     @vy_integrated

@vy_negative:
    ; vy < 0: magnitude = -vy, 16-bit subtract
    lda     _player_vy
    eor     #$FF
    clc
    adc     #1
    sta     _tmp1
    lda     _player_y
    sec
    sbc     _tmp1
    sta     _player_y
    lda     _player_y + 1
    sbc     #0
    bcc     @clamp_top      ; borrowed below zero
    jmp     @vy_integrated

@clamp_top:
    ; Jumped above the top of the level: pin to row 0, kill velocity
    lda     #0
    sta     _player_y
    sta     _player_y + 1
    sta     _player_vy

@vy_integrated:
    ; Ceiling collision check (player head hitting solid tile above)
    lda     _player_y + 1
    lsr
    lsr
    lsr
    sta     _tmp4           ; tile row at top of player
    lda     _player_x + 1
    clc
    adc     #4              ; center of player
    lsr
    lsr
    lsr
    sta     _tmp5           ; tile col
    jsr     get_tile
    cmp     #0
    beq     @no_ceiling
    ; Hit head - snap down, zero velocity and subpixel
    lda     _tmp4
    asl
    asl
    asl
    clc
    adc     #8
    sta     _player_y + 1
    lda     #$00
    sta     _player_y
    sta     _player_vy
@no_ceiling:

    ; Handle horizontal movement with wall collision
    lda     _tmp2
    and     #$04            ; left
    beq     @try_right
    
    ; Check left wall collision
    lda     _player_x + 1
    sec
    sbc     #$02            ; proposed new position
    sta     _tmp1
    jsr     check_wall_left
    bne     @h_movement_done ; blocked
    
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
    
    ; Check right wall collision
    lda     _player_x + 1
    clc
    adc     #$02            ; proposed new position
    sta     _tmp1
    jsr     check_wall_right
    bne     @h_movement_done ; blocked
    
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

    ; Handle jumping. _on_ground was left set by the previous frame's floor
    ; check, so it still reflects ground contact from before gravity moved.
    lda     _tmp2
    and     #$01            ; up
    beq     @jump_done
    lda     _on_ground
    beq     @jump_done
    lda     #PLAYER_JUMP_VY
    sta     _player_vy
    lda     #0
    sta     _on_ground      ; leave the ground: no double jump
    ldx     #4              ; jump SFX
    jsr     play_sfx
@jump_done:

    ; Handle fire
    lda     _tmp2
    and     #$10            ; fire
    beq     @no_fire
    jsr     player_shoot
@no_fire:
    rts

;
; Player shooting
;
player_shoot:
    lda     _player_ammo
    beq     @no_ammo
    dec     _player_ammo
    lda     _player_weapon
    beq     @pistol
    cmp     #1
    beq     @rifle
    cmp     #2
    beq     @shotgun
    rts
@pistol:
    jsr     spawn_bullet_pistol
    ldx     #0
    jsr     play_sfx
    rts
@rifle:
    jsr     spawn_bullet_rifle
    ldx     #0
    jsr     play_sfx
    rts
@shotgun:
    jsr     spawn_bullet_shotgun
    ldx     #0
    jsr     play_sfx
    rts
@no_ammo:
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
    bcc     @h_scroll_done
    lda     #$80
    sta     _scroll_x
@h_scroll_done:

    ; Vertical scroll: level must be taller than the screen to scroll
    lda     map_height
    cmp     #25
    bcc     @v_scroll_zero  ; map shorter than screen -> no vertical scroll
    sec
    sbc     #25
    sta     _tmp4           ; last scrollable row

    ; Player row = _player_y + 1 (8-bit high byte of world Y), >> 3
    lda     _player_y + 1
    lsr
    lsr
    lsr
    sec
    sbc     #11             ; keep player ~11 rows down the screen
    bcc     @v_scroll_zero
    cmp     _tmp4
    bcc     @v_scroll_store
    lda     _tmp4           ; clamp to bottom
    jmp     @v_scroll_store
@v_scroll_zero:
    lda     #0
@v_scroll_store:
    sta     _scroll_y
    rts

;
; Draw HUD character at screen position
; A=glyph_index, X=col, Y=row
;
draw_hud_char:
    ; Save inputs
    sta     _tmp4           ; glyph index
    stx     _tmp_ptr        ; col
    sty     _tmp2           ; row

    ; Screen address = $C000 + row*40 + col
    ; row*40 = row*32 + row*8
    tya
    asl
    asl
    asl                     ; *8
    sta     _tmp3
    tya
    asl
    asl
    asl
    asl
    asl                     ; *32
    clc
    adc     _tmp3           ; *40
    clc
    adc     _tmp_ptr        ; + col
    tay

    ; Write color byte (white on black)
    lda     #$01
    sta     $C000,y

    ; Bitmap address = $E000 + (row*40+col)*8
    tya
    asl
    rol     _tmp3           ; need temp storage
    asl
    rol     _tmp3
    asl
    rol     _tmp3
    sta     _tmp_ptr
    lda     _tmp3
    and     #$07
    clc
    adc     #$E0
    sta     _tmp_ptr+1
    lda     _tmp_ptr
    sta     _tmp_ptr
    ; _tmp_ptr now points to bitmap location

    ; Copy glyph data (8 bytes)
    lda     _tmp4
    asl
    asl
    asl                     ; *8 for glyph offset
    tax
    ldy     #0
@copy:
    lda     hud_glyphs,x
    sta     (_tmp_ptr),y
    inx
    iny
    cpy     #8
    bne     @copy
    rts

;
; Draw 2-digit number at (col, row)
; X=col, Y=row, A=value
;
draw_hud_byte:
    sta     _tmp3           ; value
    stx     _tmp2           ; col
    sty     _tmp4           ; row

    ; Tens digit
    ldx     #0
@tens:
    lda     _tmp3
    cmp     #10
    bcc     @tens_done
    sbc     #10
    sta     _tmp3
    inx
    jmp     @tens
@tens_done:
    txa                     ; tens digit
    clc
    adc     #1              ; digit 0 = glyph index 1
    ldx     _tmp2
    ldy     _tmp4
    jsr     draw_hud_char
    ; Ones digit
    lda     _tmp3
    clc
    adc     #1              ; digit 0 = glyph index 1
    ldx     _tmp2
    inx
    ldy     _tmp4
    jsr     draw_hud_char
    rts

;
; Divide 16-bit value by 10
; Input:  _tmp3 = lo, _tmp4 = hi
; Output: A = remainder (0-9), _tmp3 = quotient_lo, _tmp4 = quotient_hi
;
div16_by_10:
    lda     #0
    sta     _tmp_ptr
    sta     _tmp_ptr+1
    ldx     #16
@loop:
    asl     _tmp3
    rol     _tmp4
    rol
    cmp     #10
    bcc     @skip
    sbc     #10
    sec
    jmp     @shift
@skip:
    clc
@shift:
    rol     _tmp_ptr
    rol     _tmp_ptr+1
    dex
    bne     @loop
    lda     _tmp_ptr
    sta     _tmp3
    lda     _tmp_ptr+1
    sta     _tmp4
    rts

;
; Draw 5-digit number at (col, row)
; X=col, Y=row, value = _player_score (2 bytes)
;
draw_hud_word:
    stx     _tmp1           ; start col
    sty     _tmp2           ; row

    ; Copy score to working vars
    lda     _player_score
    sta     _tmp3
    lda     _player_score+1
    sta     _tmp4

    ; Extract 5 digits into stack (LSD first)
    ldy     #0
@digit_loop:
    jsr     div16_by_10
    pha                     ; push remainder (digit)
    iny
    cpy     #5
    bne     @digit_loop

    ; Pop and draw digits MSD first (col offset 0..4)
    lda     #0
    sta     _tmp3           ; offset
@draw_loop:
    pla
    clc
    adc     #1              ; glyph index = digit + 1
    pha
    lda     _tmp3
    clc
    adc     _tmp1           ; col = start_col + offset
    tax
    pla
    ldy     _tmp2
    jsr     draw_hud_char
    inc     _tmp3
    lda     _tmp3
    cmp     #5
    bne     @draw_loop
    rts

;
; Render HUD (status bar at top of screen)
;
draw_hud:
    ; Row 0: "HP:XX  AM:XX  SC:XXXXX"
    ; Col 0='H', 1='P', 2=':', 3-4=HP, 7='A', 8='M', 9=':', 10-11=AM,
    ; 14='S', 15='C', 16=':', 17-21=SCORE
    ldx     #0
    ldy     #0

    ; HP label
    lda     #13             ; 'H'
    ldx     #0
    ldy     #0
    jsr     draw_hud_char
    lda     #18             ; 'P'
    ldx     #1
    ldy     #0
    jsr     draw_hud_char
    lda     #23             ; ':'
    ldx     #2
    ldy     #0
    jsr     draw_hud_char
    lda     _player_health
    ldx     #3
    ldy     #0
    jsr     draw_hud_byte

    ; AM label
    lda     #10             ; 'A'
    ldx     #7
    ldy     #0
    jsr     draw_hud_char
    lda     #15             ; 'M'
    ldx     #8
    ldy     #0
    jsr     draw_hud_char
    lda     #23             ; ':'
    ldx     #9
    ldy     #0
    jsr     draw_hud_char
    lda     _player_ammo
    ldx     #10
    ldy     #0
    jsr     draw_hud_byte

    ; SC label
    lda     #20             ; 'S'
    ldx     #14
    ldy     #0
    jsr     draw_hud_char
    lda     #11             ; 'C'
    ldx     #15
    ldy     #0
    jsr     draw_hud_char
    lda     #23             ; ':'
    ldx     #16
    ldy     #0
    jsr     draw_hud_char
    ldx     #17
    ldy     #0
    jsr     draw_hud_word

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
    cmp     _scroll_x_prev
    beq     @no_scroll
    bcc     @scrolled_left
    sta     _scroll_x_prev
    ; Scrolled right: shift screen, draw new right column
    jsr     scroll_right
    jmp     @no_scroll
@scrolled_left:
    sta     _scroll_x_prev
    jsr     scroll_left
    
@no_scroll:
    ; Check coarse vertical scroll change
    lda     _scroll_y
    cmp     _scroll_y_prev
    beq     @no_vscroll
    ; Apply a single row of scrolling per frame. A tile row blit is
    ; ~8600 cycles, so catching up several rows in one frame would
    ; overrun the frame and drop further camera updates.
    bcc     @vscroll_up
    ; Camera moved down one row: content moves up, expose bottom row
    jsr     screen_shift_up
    ldy     #24
    jsr     draw_row
    inc     _scroll_y_prev
    jmp     @no_vscroll

@vscroll_up:
    ; Camera moved up one row: content moves down, expose top row
    jsr     screen_shift_down
    ldy     #0
    jsr     draw_row
    dec     _scroll_y_prev

@no_vscroll:
    jsr     update_sprites
    jsr     draw_hud
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

;
; Vertical scroll blits. One tile row = 40 screen bytes and 320 bitmap bytes.
; The bitmap is walked a page at a time; vshift_src/vshift_dst double as the
; operands of the indexed loads/stores so only the page-high byte changes.
; Both directions copy all 25 rows, so the exposed row is redrawn by the
; caller afterwards via draw_row.
;
screen_shift_up:
    ; screen RAM: $C028..$C3E7 -> $C000..$C3BF (960 bytes)
    ldx     #0
@s1:
    lda     $C028,x
    sta     $C000,x
    inx
    bne     @s1
    ldx     #0
@s2:
    lda     $C128,x
    sta     $C100,x
    inx
    bne     @s2
    ldx     #0
@s3:
    lda     $C228,x
    sta     $C200,x
    inx
    bne     @s3
    ldx     #0
@s4:
    lda     $C328,x
    sta     $C300,x
    inx
    cpx     #192
    bne     @s4

    ; bitmap: $E140..$FF3F -> $E000..$F7FF (7680 bytes = 30 pages)
    lda     #<$E140
    sta     vshift_src
    lda     #>$E140
    sta     vshift_src + 1
    lda     #<$E000
    sta     vshift_dst
    lda     #>$E000
    sta     vshift_dst + 1
    ldx     #30
@up_page:
    ldy     #0
@up_byte:
    lda     vshift_src,y
    sta     vshift_dst,y
    iny
    bne     @up_byte
    inc     vshift_src + 1
    inc     vshift_dst + 1
    dex
    bne     @up_page
    rts

screen_shift_down:
    ; screen RAM: $C000..$C3BF -> $C028..$C3E7 (copy backwards)
    ldx     #191
@d4:
    lda     $C300,x
    sta     $C328,x
    dex
    cpx     #$FF
    bne     @d4
    ldx     #255
@d3:
    lda     $C200,x
    sta     $C228,x
    dex
    bne     @d3
    ldx     #255
@d2:
    lda     $C100,x
    sta     $C128,x
    dex
    bne     @d2
    ldx     #255
@d1:
    lda     $C000,x
    sta     $C028,x
    dex
    bne     @d1

    ; bitmap: $E000..$F7FF -> $E140..$FF3F (7680 bytes = 30 pages)
    lda     #<$F7FF
    sta     vshift_src
    lda     #>$F7FF
    sta     vshift_src + 1
    lda     #<$FF3F
    sta     vshift_dst
    lda     #>$FF3F
    sta     vshift_dst + 1
    ldx     #30
@down_page:
    ldy     #255
@down_byte:
    lda     vshift_src,y
    sta     vshift_dst,y
    dey
    bne     @down_byte
    dec     vshift_src + 1
    dec     vshift_dst + 1
    dex
    bne     @down_page
    rts

scroll_right:
    jsr     screen_shift_left
    ldy     #39
    jsr     draw_col
    rts

scroll_left:
    jsr     screen_shift_right
    ldy     #0
    jsr     draw_col
    rts

;
; Draw one screen cell from the tile map
;   _tmp2 = screen row (0-24), _tmp4 = screen col (0-39)
; Map coords = (row + _scroll_y, col + scroll_x/8)
;
draw_cell:
    ; screen cell index = row*40 + col
    lda     _tmp2
    asl
    asl
    asl                     ; *8
    sta     _tmp7
    lda     _tmp2
    asl
    asl
    asl
    asl
    asl                     ; *32
    clc
    adc     _tmp7
    adc     _tmp4           ; *40 + col
    sta     _tmp7

    ; map col = (scroll_x >> 3) + screen col
    lda     _scroll_x
    lsr
    lsr
    lsr
    clc
    adc     _tmp4
    sta     _tmp5
    ; map row = screen row + _scroll_y
    lda     _tmp2
    clc
    adc     _scroll_y
    sta     _tmp4

    jsr     get_tile
    sta     _tmp6           ; tile id

    ; screen RAM: $C000 + cell index
    ldx     _tmp6
    lda     tile_color_table,x
    ldy     _tmp7
    sta     $C000,y

    ; bitmap: $E000 + cell index * 8
    lda     _tmp7
    asl
    asl
    asl                     ; *8
    sta     _tmp_ptr
    lda     #0
    rol
    sta     _tmp_ptr + 1
    clc
    lda     _tmp_ptr
    adc     #$E0
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1

    ldx     _tmp6
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
    rts

;
; Draw one screen column of tiles (used by horizontal scrolling)
;   Y = screen column
;
draw_col:
    sty     _tmp4
    lda     #0
    sta     _tmp2
@row_loop:
    jsr     draw_cell
    inc     _tmp2
    lda     _tmp2
    cmp     #25
    bne     @row_loop
    rts

;
; Draw one screen row of tiles (used by vertical scrolling)
;   Y = screen row
;
draw_row:
    sty     _tmp2
    lda     #0
    sta     _tmp4
@col_loop:
    jsr     draw_cell
    inc     _tmp4
    lda     _tmp4
    cmp     #40
    bne     @col_loop
    rts

update_sprites:
    ; Vertical scroll in pixels = _scroll_y * 8
    lda     _scroll_y
    asl
    asl
    asl
    sta     _scroll_px

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
    sec
    sbc     _scroll_px
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
    sec
    sbc     _scroll_px
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
    ; A = level index (0 or 1)

    sta     _level_index
    tax
    lda     level_table_lo,x
    sta     map_data_ptr
    lda     level_table_hi,x
    sta     map_data_ptr + 1

    jsr     load_map_tiles
    jsr     setup_sprites
    jsr     spawn_enemies
    jsr     place_items
    rts

level_enemy_ptr:
    lda     _level_index
    beq     @l1
    lda     #<level_2_enemies
    sta     _enemy_ptr
    lda     #>level_2_enemies
    sta     _enemy_ptr + 1
    rts
@l1:
    lda     #<level_1_enemies
    sta     _enemy_ptr
    lda     #>level_1_enemies
    sta     _enemy_ptr + 1
    rts

level_item_ptr:
    lda     _level_index
    beq     @l1
    lda     #<level_2_items
    sta     _item_ptr
    lda     #>level_2_items
    sta     _item_ptr + 1
    rts
@l1:
    lda     #<level_1_items
    sta     _item_ptr
    lda     #>level_1_items
    sta     _item_ptr + 1
    rts

place_items:
    ; Place item tiles from level item data onto the tile map
    jsr     level_item_ptr
    ldy     #0              ; byte offset into item data
    ldx     #0              ; scratch
@loop:
    ; Read type
    lda     (_item_ptr),y
    cmp     #$FF            ; end marker?
    beq     @done
    sta     _tmp4           ; item type (0-3)
    iny
    ; Read x_lo
    lda     (_item_ptr),y
    sta     _tmp1           ; x_lo
    iny
    ; Read x_hi
    lda     (_item_ptr),y
    sta     _tmp2           ; x_hi (not used for tile col)
    iny
    ; Read y
    lda     (_item_ptr),y
    sta     _tmp3           ; y
    iny

    ; Convert pixel coords to tile coords
    lda     _tmp1
    lsr
    lsr
    lsr                     ; tile col = x >> 3
    sta     _tmp1
    lda     _tmp3
    lsr
    lsr
    lsr                     ; tile row = y >> 3
    sta     _tmp2

    ; Bounds check
    lda     _tmp2           ; row < map_height?
    cmp     map_height
    bcs     @next
    lda     _tmp1           ; col < map_width?
    cmp     map_width
    bcs     @next

    ; tile_map index = row * map_width + col
    lda     _tmp2
    jsr     mul_map_width
    clc
    lda     _tmp_ptr
    adc     _tmp1
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1

    ; Write item tile: 13 + type
    ldy     #0
    lda     _tmp4
    clc
    adc     #13
    sta     (_tmp_ptr),y

@next:
    jmp     @loop
@done:
    rts

update_items:
    ; Check if player overlaps an item tile
    ; Player center tile coords
    lda     _player_x + 1
    clc
    adc     #4
    lsr
    lsr
    lsr
    sta     _tmp5           ; tile col

    lda     _player_y + 1
    clc
    adc     #4
    lsr
    lsr
    lsr
    sta     _tmp4           ; tile row

    ; Recompute the tile address so the pickup can clear it
    lda     _tmp4
    jsr     mul_map_width
    clc
    lda     _tmp_ptr
    adc     _tmp5
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1
    ldy     #0
    lda     (_tmp_ptr),y
    sta     _tmp6           ; tile type

    cmp     #13             ; item tile range 13-16
    bcc     @no_item
    cmp     #17
    bcs     @no_item

    ; Item type = tile - 13
    sec
    sbc     #13
    tax                     ; X = item type

    ; Apply item effect
    cpx     #0
    beq     @weapon
    cpx     #1
    beq     @health
    cpx     #2
    beq     @ammo
    ; type 3 = keycard
    jmp     @no_item        ; keycard: placeholder

@weapon:
    ; Upgrade weapon (pistol->rifle, rifle->shotgun)
    lda     _player_weapon
    cmp     #2
    bcs     @no_item
    inc     _player_weapon
    jmp     @pickup

@health:
    lda     _player_health
    cmp     #5
    bcs     @no_item        ; max HP check
    inc     _player_health
    jmp     @pickup

@ammo:
    lda     _player_ammo
    clc
    adc     #10
    bcc     @set_ammo
    lda     #$FF            ; clamp to 255
@set_ammo:
    sta     _player_ammo
    jmp     @pickup

@pickup:
    ; Remove item tile, play SFX
    ldy     #0
    lda     #0
    sta     (_tmp_ptr),y
    ldx     #3              ; pickup SFX
    jsr     play_sfx

@no_item:
    rts

spawn_enemies:
    ; Spawn enemies from level data
    jsr     level_enemy_ptr
    ldy     #0              ; byte offset into enemy data
    ldx     #0              ; enemy slot
@loop:
    cpx     #MAX_ENEMIES
    beq     @done
    ; Read type
    lda     (_enemy_ptr),y
    cmp     #$FF            ; end marker?
    beq     @done
    sta     enemy_type,x
    iny
    ; Read x_lo
    lda     (_enemy_ptr),y
    sta     enemy_x,x
    iny
    ; Read x_hi
    lda     (_enemy_ptr),y
    sta     enemy_x + 1,x
    iny
    ; Read y
    lda     (_enemy_ptr),y
    sta     enemy_y,x
    lda     #$00
    sta     enemy_y + 1,x
    iny
    ; Read state
    lda     (_enemy_ptr),y
    sta     enemy_state,x
    iny
    ; Set default HP
    lda     #3
    sta     enemy_hp,x
    lda     #0
    sta     enemy_timer,x
    inx
    jmp     @loop
@done:
    ; Mark unused slots as empty
    lda     #$FF
@clear:
    sta     enemy_type,x
    inx
    cpx     #MAX_ENEMIES
    bne     @clear
    rts

load_map_tiles:
    ; RLE-decompress level tiles into tile_map buffer
    ; Dimensions come from the level header pointed to by map_data_ptr
    lda     map_data_ptr
    sta     _tmp_ptr
    lda     map_data_ptr + 1
    sta     _tmp_ptr + 1

    ; Reject levels larger than the tile map buffer can hold
    ldy     #0
    lda     (_tmp_ptr),y
    cmp     #MAP_MAX_WIDTH
    bcc     @width_ok
    lda     #MAP_MAX_WIDTH
@width_ok:
    sta     map_width
    iny
    lda     (_tmp_ptr),y
    cmp     #MAP_MAX_HEIGHT
    bcc     @height_ok
    lda     #MAP_MAX_HEIGHT
@height_ok:
    sta     map_height
    
    ; Point to tile data (header = 10 bytes, then tile data)
    lda     map_data_ptr
    clc
    adc     #10
    sta     _tmp_ptr
    lda     map_data_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1
    
    ; Decompress RLE into tile_map
    ; Index is 16-bit: _tmp3 = low byte, _tmp4 = high byte
    ; Buffer capacity: _tmp5 = low byte, _tmp6 = high byte
    ldy     #0
    lda     #0
    sta     _tmp3
    sta     _tmp4
    lda     #<(MAP_MAX_WIDTH * MAP_MAX_HEIGHT)
    sta     _tmp5
    lda     #>(MAP_MAX_WIDTH * MAP_MAX_HEIGHT)
    sta     _tmp6

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
    
@fill_loop:
    ldx     _tmp3
    lda     _tmp1
    sta     tile_map,x
    inc     _tmp3
    bne     @no_page
    inc     _tmp4           ; low byte wrapped -> next page
@no_page:
    ; Stop once the write index reaches the buffer capacity
    lda     _tmp3
    cmp     _tmp5
    bcc     @fill_more
    lda     _tmp4
    cmp     _tmp6
    bcc     @fill_more
    jmp     @done
@fill_more:
    dec     _tmp2
    bne     @fill_loop
    
    jmp     @next_rle
@done:
    rts

render_full_map:
    ; Render visible tiles to screen RAM and bitmap
    ; Two nested loops: row (0-24), col (0-39)
    lda     #0
    sta     _tmp2           ; row
@row_loop:
    lda     #0
    sta     _tmp4           ; col
@col_loop:
    jsr     draw_cell
    inc     _tmp4
    lda     _tmp4
    cmp     #40
    bne     @col_loop
    inc     _tmp2
    lda     _tmp2
    cmp     #25
    bne     @row_loop
    rts

;
; 16-bit multiply: A * map_width -> _tmp_ptr (lo/hi)
; Needed because map_width * row exceeds 255 for all but the top rows.
;
mul_map_width:
    sta     _tmp3
    lda     #0
    sta     _tmp_ptr
    sta     _tmp_ptr + 1
    ldx     #8
@loop:
    lsr     _tmp3
    bcc     @no_add
    clc
    lda     _tmp_ptr
    adc     map_width
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1
@no_add:
    asl     _tmp_ptr
    rol     _tmp_ptr + 1
    dex
    bne     @loop
    lda     _tmp_ptr
    ldy     _tmp_ptr + 1
    rts

;
; Fetch tile at map coords (_tmp4 = row, _tmp5 = col)
; Returns tile id in A. Clobbers _tmp1, _tmp3, _tmp_ptr, X, Y.
;
get_tile:
    lda     _tmp4
    jsr     mul_map_width
    clc
    lda     _tmp_ptr
    adc     _tmp5
    sta     _tmp_ptr
    lda     _tmp_ptr + 1
    adc     #0
    sta     _tmp_ptr + 1
    ldy     #0
    lda     (_tmp_ptr),y
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
    bne     *+5
    jmp     @done
    
    lda     enemy_type,x
    cmp     #$FF            ; inactive?
    bne     *+5
    jmp     @skip
    
    ; Enemy gravity
    lda     enemy_y + 1,x
    clc
    adc     #$02
    sta     enemy_y + 1,x
    lda     enemy_y,x
    adc     #$00
    sta     enemy_y,x
    
    ; Check if active (bit 0 set, ignoring patrol dir in bit 7)
    lda     enemy_state,x
    and     #$01
    cmp     #1
    beq     *+5
    jmp     @skip
    
    ; Decrement AI timer
    dec     enemy_timer,x
    bpl     @ai_move
    ; Timer expired: reset and toggle patrol direction
    lda     #60
    sta     enemy_timer,x
    ; Toggle patrol direction (bit 7 of enemy_state)
    lda     enemy_state,x
    eor     #$80
    sta     enemy_state,x
    
@ai_move:
    ; Calculate X distance to player
    lda     _player_x
    sec
    sbc     enemy_x,x
    bcs     @dist_pos
    eor     #$FF
    adc     #$01
@dist_pos:
    cmp     #$60            ; within 96 pixels?
    bcc     @chase
    ; Far: patrol (bit 7 of enemy_state = direction, 0=left, 1=right)
    lda     enemy_state,x
    bmi     @patrol_r
@patrol_l:
    lda     enemy_x + 1,x
    sec
    sbc     #$01
    sta     enemy_x + 1,x
    lda     enemy_x,x
    sbc     #$00
    sta     enemy_x,x
    jmp     @ai_done
@patrol_r:
    lda     enemy_x + 1,x
    clc
    adc     #$01
    sta     enemy_x + 1,x
    lda     enemy_x,x
    adc     #$00
    sta     enemy_x,x
    jmp     @ai_done

@chase:
    ; Close: move toward player
    lda     _player_x
    cmp     enemy_x,x
    bcc     @chase_left
    bne     @chase_right
    jmp     @check_shoot
@chase_left:
    lda     enemy_x + 1,x
    sec
    sbc     #$02            ; faster when chasing
    sta     enemy_x + 1,x
    lda     enemy_x,x
    sbc     #$00
    sta     enemy_x,x
    jmp     @check_shoot
@chase_right:
    lda     enemy_x + 1,x
    clc
    adc     #$02
    sta     enemy_x + 1,x
    lda     enemy_x,x
    adc     #$00
    sta     enemy_x,x
    
@check_shoot:
    ; Shoot when timer reaches 0 (every ~60 frames)
    lda     enemy_timer,x
    bne     @ai_done
    stx     _tmp4
    jsr     spawn_enemy_bullet
    ldx     _tmp4
    
@ai_done:
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

spawn_enemy_bullet:
    ; Spawn bullet at enemy position (_tmp4 = enemy index)
    ; Shoot toward player direction
    ldx     #0
@find:
    cpx     #MAX_BULLETS
    beq     @done
    lda     bullet_active,x
    beq     @found
    inx
    jmp     @find
@found:
    lda     #1
    sta     bullet_active,x
    lda     #2
    sta     bullet_type,x   ; type 2 = enemy bullet

    ldy     _tmp4
    ; Position at enemy
    lda     enemy_x,y
    sta     bullet_x,x
    lda     enemy_x + 1,y
    sta     bullet_x + 1,x
    lda     enemy_y,y
    sta     bullet_y,x
    lda     enemy_y + 1,y
    sta     bullet_y + 1,x

    ; Velocity toward player on X
    lda     _player_x + 1
    cmp     enemy_x + 1,y
    bcc     @shoot_left
    lda     #$FD            ; +3 right
    sta     bullet_vx,x
    jmp     @set_vy
@shoot_left:
    lda     #$FD            ; -3 left
    sta     bullet_vx,x
@set_vy:
    lda     #$00
    sta     bullet_vy,x
@done:
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
; Wall collision helpers
;
check_wall_left:
    ; Check tile at player's left edge
    ; _tmp1 = proposed new x position (pixel)
    ; Returns: Z=1 if clear, Z=0 if blocked
    ; Tile col = (x + 0) >> 3
    lda     _tmp1
    lsr
    lsr
    lsr
    sta     _tmp5           ; col
    ; Tile row = (player_y+1 + 4) >> 3 (midpoint)
    lda     _player_y + 1
    clc
    adc     #4
    lsr
    lsr
    lsr
    sta     _tmp4           ; row
    jsr     get_tile
    cmp     #0
    rts

check_wall_right:
    ; Check tile at player's right edge
    ; _tmp1 = proposed new x position (pixel)
    ; Tile col = (x + 7) >> 3 (right edge of 8-pixel player)
    lda     _tmp1
    clc
    adc     #7
    lsr
    lsr
    lsr
    sta     _tmp5           ; col
    ; Tile row = (player_y+1 + 4) >> 3 (midpoint)
    lda     _player_y + 1
    clc
    adc     #4
    lsr
    lsr
    lsr
    sta     _tmp4           ; row
    jsr     get_tile
    cmp     #0
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
    bne     @check_bullet
    jmp     @next_bullet
@check_bullet:
    
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
    
    ; Add score
    lda     _player_score
    clc
    adc     #10
    sta     _player_score
    lda     _player_score + 1
    adc     #0
    sta     _player_score + 1
    
    ; Spawn death particles
    tya
    pha                     ; save enemy index
    lda     enemy_x,y
    tax                     ; X = x
    lda     enemy_y,y
    tay                     ; Y = y
    lda     #4              ; A = count
    jsr     spawn_particles
    ldx     #1              ; explosion SFX
    jsr     play_sfx
    pla
    tay                     ; restore enemy index
    
    jmp     @next_bullet
    
@hit_effect:
    ; Spawn hit particles
    lda     #2
    ldx     _tmp1
    ldy     _tmp2
    jsr     spawn_particles
    ldx     #2              ; hurt SFX
    jsr     play_sfx
    
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
    
    ; Player hit by enemy (skip if invincible)
    lda     _invincible_timer
    bne     @pe_next
    dec     _player_health
    lda     #$80
    sta     _invincible_timer   ; ~2 seconds of invincibility
    ldx     #2              ; hurt SFX
    jsr     play_sfx
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
    ; Check tile directly below player's feet
    ; Player tile row = (player_y+1 + 7) >> 3 (bottom of 8-pixel player)
    lda     _player_y + 1
    clc
    adc     #7
    lsr
    lsr
    lsr
    sta     _tmp4           ; tile row below feet

    ; Player tile col = (player_x+1 + 3) >> 3 (center of player)
    lda     _player_x + 1
    clc
    adc     #3
    lsr
    lsr
    lsr
    sta     _tmp5           ; tile col

    jsr     get_tile
    cmp     #0
    beq     @no_floor
    lda     _player_vy
    bmi     @no_floor       ; ascending: let the jump leave the ground

    ; Solid tile below - snap player, zero velocity and set ground flag
    lda     _tmp4           ; tile row
    asl
    asl
    asl                     ; *8 = top of tile
    sec
    sbc     #8              ; player feet align to tile top
    sta     _player_y + 1
    lda     #$00
    sta     _player_y
    sta     _player_vy
    lda     #1
    sta     _on_ground

@no_floor:
    rts

;
; Loading screen state
;
loading_tick:
    ; Loading sequence: clear screen, show loading message, init game
    jsr     clear_screen

    ; Draw loading text centered on row 12
    ldx     #0
@draw_loading:
    lda     loading_msg,x
    beq     @done_loading
    sta     $C000 + 12 * 40 + 14, x
    inx
    jmp     @draw_loading
@done_loading:

    ; Brief pause to show the loading message
    lda     #30
    sta     _tmp1
@wait_loop:
    dec     _tmp1
    bne     @wait_loop

    ; Initialize game
    jsr     start_game
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
MAP_MAX_WIDTH = 80
; World Y is a single pixel byte, so the map tops out at 32 rows (256 px)
MAP_MAX_HEIGHT = 32

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
tile_map:       .res MAP_MAX_WIDTH * MAP_MAX_HEIGHT   ; 80x48 level tiles

; Self-modifying operands for vertical scroll blits.
; Used as "lda vshift_src,y / sta vshift_dst,y"; the high byte is
; incremented per 256-byte page while the blit walks the bitmap.
vshift_src:     .res 2
vshift_dst:     .res 2

; Sound engine state (3 voices)
music_ptr0:     .res 2
music_ptr1:     .res 2
music_ptr2:     .res 2
music_start0:   .res 2
music_start1:   .res 2
music_start2:   .res 2
music_tick0:    .res 1
music_tick1:    .res 1
music_tick2:    .res 1
sfx_queue:      .res 4
