;
; ANP2 - Sound driver for Commodore 64 SID
; Original music by Oleg Nikitin (n1k-o)
; SID voices: 3x synthesizers, 4x waveforms each
;
; Simple note-based music player
;

.segment "RODATA"

; ---- Music data (placeholder/converted note tables) ----
; Format: delta_time, note, waveform, duty_cycle, attack_decay, sustain_release
; Delta time in frames (1/60th second)

; Title screen music
music_title:
    .byte $10, $1E, $21, $80, $09, $A8    ; C3, pulse 50%, AD=0, SR=a8
    .byte $10, $24, $21, $80, $09, $A8    ; E3
    .byte $10, $27, $21, $80, $09, $A8    ; G3
    .byte $10, $2B, $21, $80, $09, $A8    ; C4
    .byte $10, $29, $21, $80, $09, $A8    ; B3
    .byte $10, $27, $11, $80, $09, $A8    ; G3, triangle
    .byte $10, $24, $11, $80, $09, $A8    ; E3
    .byte $10, $1E, $11, $80, $09, $A8    ; C3
    .byte $20, $1E, $41, $80, $09, $A8    ; C3, noise
    .byte $00                              ; end marker

; Level music (placeholder)
music_level1:
    .byte $08, $1E, $21, $80, $09, $A8
    .byte $08, $1E, $21, $80, $09, $A8
    .byte $08, $1E, $21, $80, $09, $A8
    .byte $08, $24, $21, $80, $09, $A8
    .byte $08, $24, $21, $80, $09, $A8
    .byte $08, $27, $21, $80, $09, $A8
    .byte $08, $27, $21, $80, $09, $A8
    .byte $08, $2B, $21, $80, $09, $A8
    .byte $00

; ---- Sound effects ----
; Format: note, waveform, duty_cycle, attack_decay, sustain_release

sfx_shoot:
    .byte $30, $81, $80, $0F, $00, $F0, $00    ; noise sweep down

sfx_explosion:
    .byte $10, $81, $80, $0F, $00, $F0, $00
    .byte $08, $81, $80, $0F, $00, $80, $00
    .byte $08, $81, $80, $0F, $00, $40, $00
    .byte $08, $81, $80, $0F, $00, $20, $00
    .byte $00

sfx_hurt:
    .byte $20, $81, $80, $0F, $00, $F0, $00
    .byte $20, $21, $10, $0F, $00, $40, $00
    .byte $00

sfx_pickup:
    .byte $08, $21, $40, $09, $A8
    .byte $08, $28, $40, $09, $A8
    .byte $08, $2B, $40, $09, $A8
    .byte $00

sfx_jump:
    .byte $04, $21, $10, $09, $FF
    .byte $04, $24, $10, $09, $FF
    .byte $04, $27, $10, $09, $FF
    .byte $04, $2B, $10, $09, $FF
    .byte $00

;
; SID register values for note frequencies (lo/hi)
; Note table: C2 to C5
;
note_table_lo:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 ; C0-B0
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51 ; C1-B1
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51 ; C2-B2
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51 ; C3-B3
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51 ; C4-B4
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51 ; C5-B5

note_table_hi:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $01,$01,$01,$01,$02,$02,$02,$02,$03,$03,$03,$04 ; C1-B1
    .byte $02,$02,$02,$02,$04,$04,$04,$04,$06,$06,$06,$08 ; C2-B2
    .byte $04,$04,$04,$04,$08,$08,$08,$08,$0C,$0C,$0C,$10 ; C3-B3
    .byte $08,$08,$08,$08,$10,$10,$10,$10,$18,$18,$18,$20 ; C4-B4
    .byte $10,$10,$10,$10,$20,$20,$20,$20,$30,$30,$30,$40 ; C5-B5

.segment "CODE"

.define SID $D400

; Import from main module
.importzp _tmp_ptr
.import music_ptr, music_tick

; Export symbols for main module
.export start_music, play_music, play_sfx
.export music_title, music_level1
.export sfx_shoot, sfx_explosion, sfx_hurt, sfx_pickup, sfx_jump

;
; Play music - call once per frame
; X = music data index, updates in place
;
play_music:
    lda     music_ptr
    sta     _tmp_ptr
    lda     music_ptr+1
    sta     _tmp_ptr+1

    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop_music       ; end marker

    dec     music_tick
    bne     @skip_note

    ; Play next note
    sta     music_tick        ; reset timer

    iny
    lda     (_tmp_ptr),y      ; note
    tax
    lda     note_table_lo,x
    sta     SID + $00         ; voice 1 freq lo
    lda     note_table_hi,x
    sta     SID + $01         ; voice 1 freq hi

    iny
    lda     (_tmp_ptr),y      ; waveform
    sta     SID + $04         ; voice 1 control

    iny
    lda     (_tmp_ptr),y      ; duty cycle
    sta     SID + $02         ; voice 1 pulse lo
    iny
    lda     (_tmp_ptr),y
    sta     SID + $03         ; voice 1 pulse hi

    iny
    lda     (_tmp_ptr),y      ; attack/decay
    sta     SID + $05

    iny
    lda     (_tmp_ptr),y      ; sustain/release
    sta     SID + $06

    ; Move to next note entry
    tya
    clc
    adc     _tmp_ptr
    sta     _tmp_ptr
    bcc     @skip_inc
    inc     _tmp_ptr+1
@skip_inc:
    lda     _tmp_ptr
    sta     music_ptr
    lda     _tmp_ptr+1
    sta     music_ptr+1

@skip_note:
    rts

@stop_music:
    ; Reset and stop
    lda     #$00
    sta     SID + $04         ; voice 1 off
    rts

;
; Start playing a music track
; A = track number (0=title, 1=level1)
;
start_music:
    cmp     #0
    beq     @title_music
    cmp     #1
    beq     @level_music
    rts

@title_music:
    lda     #<music_title
    sta     music_ptr
    lda     #>music_title
    sta     music_ptr+1
    lda     #1
    sta     music_tick
    rts

@level_music:
    lda     #<music_level1
    sta     music_ptr
    lda     #>music_level1
    sta     music_ptr+1
    lda     #1
    sta     music_tick
    rts

;
; Play sound effect (interrupts music briefly)
; X = sfx number (0=shoot, 1=explosion, 2=hurt, 3=pickup, 4=jump)
;
play_sfx:
    ; Get sfx address
    lda     sfx_table_lo,x
    sta     _tmp_ptr
    lda     sfx_table_hi,x
    sta     _tmp_ptr+1

    ; Play first note on voice 3
    ldy     #0
    lda     (_tmp_ptr),y      ; note
    tax
    lda     note_table_lo,x
    sta     SID + $0E         ; voice 3 freq lo
    lda     note_table_hi,x
    sta     SID + $0F         ; voice 3 freq hi

    iny
    lda     (_tmp_ptr),y
    sta     SID + $12         ; voice 3 control

    iny
    lda     (_tmp_ptr),y      ; pulse
    sta     SID + $10
    iny
    lda     (_tmp_ptr),y
    sta     SID + $11
    iny
    lda     (_tmp_ptr),y      ; AD
    sta     SID + $13
    iny
    lda     (_tmp_ptr),y      ; SR
    sta     SID + $14

    rts

sfx_table_lo:
    .byte <sfx_shoot, <sfx_explosion, <sfx_hurt, <sfx_pickup, <sfx_jump

sfx_table_hi:
    .byte >sfx_shoot, >sfx_explosion, >sfx_hurt, >sfx_pickup, >sfx_jump
