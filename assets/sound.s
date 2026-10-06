;
; ANP2 - 3-voice SID music player + SFX engine
; Original music by Oleg Nikitin (n1k-o)
; Converted from PT3 format (3 independent channel streams)
;
; Voice mapping:
;   SID voice 1 = music channel 0
;   SID voice 2 = music channel 1
;   SID voice 3 = music channel 2 (shared with SFX)
;

.segment "RODATA"

; Music data imported from data files
.import music_title_0, music_title_1, music_title_2
.import music_level_0, music_level_1, music_level_2

; ---- Sound effects ----
; Format: delta_time, note, waveform, duty_lo, duty_hi, AD, SR, 0=end

sfx_shoot:
    .byte $01, $30, $81, $80, $0F, $00, $F0
    .byte $00

sfx_explosion:
    .byte $02, $10, $81, $80, $0F, $00, $F0
    .byte $02, $10, $81, $80, $0F, $00, $80
    .byte $02, $10, $81, $80, $0F, $00, $40
    .byte $02, $10, $81, $80, $0F, $00, $20
    .byte $00

sfx_hurt:
    .byte $03, $20, $81, $80, $0F, $00, $F0
    .byte $03, $20, $21, $10, $0F, $00, $40
    .byte $00

sfx_pickup:
    .byte $02, $21, $21, $40, $09, $09, $A8
    .byte $02, $28, $21, $40, $09, $09, $A8
    .byte $02, $2B, $21, $40, $09, $09, $A8
    .byte $00

sfx_jump:
    .byte $01, $21, $11, $10, $09, $09, $FF
    .byte $01, $24, $11, $10, $09, $09, $FF
    .byte $01, $27, $11, $10, $09, $09, $FF
    .byte $01, $2B, $11, $10, $09, $09, $FF
    .byte $00

sfx_table_lo:
    .byte <sfx_shoot, <sfx_explosion, <sfx_hurt, <sfx_pickup, <sfx_jump

sfx_table_hi:
    .byte >sfx_shoot, >sfx_explosion, >sfx_hurt, >sfx_pickup, >sfx_jump

;
; Note-to-frequency tables
;
note_table_lo:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51
    .byte $10,$4D,$8D,$CF,$14,$5C,$A7,$F5,$47,$9C,$F5,$51

note_table_hi:
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $01,$01,$01,$01,$02,$02,$02,$02,$03,$03,$03,$04
    .byte $02,$02,$02,$02,$04,$04,$04,$04,$06,$06,$06,$08
    .byte $04,$04,$04,$04,$08,$08,$08,$08,$0C,$0C,$0C,$10
    .byte $08,$08,$08,$08,$10,$10,$10,$10,$18,$18,$18,$20
    .byte $10,$10,$10,$10,$20,$20,$20,$20,$30,$30,$30,$40

.define SID $D400

.segment "CODE"

; Import from main module (BSS)
.importzp _tmp_ptr
.import music_ptr0, music_ptr1, music_ptr2
.import music_start0, music_start1, music_start2
.import music_tick0, music_tick1, music_tick2
.import sfx_queue

; Export symbols
.export start_music, play_music, play_sfx
.export sfx_shoot, sfx_explosion, sfx_hurt, sfx_pickup, sfx_jump

;
; Play one voice - advances pointer and sets SID registers
; A_in = lo byte of music_ptr variable address in BSS
; Need to also know which tick var and SID offset...
; We just inline the code for each voice instead.
;

;
; play_music - called once per frame from IRQ
;
play_music:
    lda     sfx_queue
    bne     @sfx_active

    ; Voice 1 = music ch0
    jsr     play_v1
    ; Voice 2 = music ch1
    jsr     play_v2
    ; Voice 3 = music ch2
    jsr     play_v3
    rts

@sfx_active:
    jsr     play_v1
    jsr     play_v2
    jsr     play_sfx_note
    rts

;
; Voice 1 player (SID $D400, music ch0)
;
play_v1:
    lda     music_ptr0
    sta     _tmp_ptr
    lda     music_ptr0+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop

    dec     music_tick0
    beq     @play

    rts
@play:
    lda     (_tmp_ptr),y
    sta     music_tick0
    iny

    lda     (_tmp_ptr),y
    tax
    lda     note_table_lo,x
    sta     SID + 0
    lda     note_table_hi,x
    sta     SID + 1
    iny

    lda     (_tmp_ptr),y
    sta     SID + 4
    iny

    lda     (_tmp_ptr),y
    sta     SID + 2
    iny
    lda     (_tmp_ptr),y
    sta     SID + 3
    iny

    lda     (_tmp_ptr),y
    sta     SID + 5
    iny

    lda     (_tmp_ptr),y
    sta     SID + 6
    iny

    tya
    clc
    adc     _tmp_ptr
    sta     _tmp_ptr
    bcc     @no_inc
    inc     _tmp_ptr+1
@no_inc:
    lda     _tmp_ptr
    sta     music_ptr0
    lda     _tmp_ptr+1
    sta     music_ptr0+1
@stop:
    lda     music_start0
    sta     music_ptr0
    lda     music_start0+1
    sta     music_ptr0+1
    lda     #1
    sta     music_tick0
    ; fall through to play_v1 entry
    lda     music_ptr0
    sta     _tmp_ptr
    lda     music_ptr0+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop
    dec     music_tick0
    beq     @play
    rts

;
; Voice 2 player (SID $D407, music ch1)
;
play_v2:
    lda     music_ptr1
    sta     _tmp_ptr
    lda     music_ptr1+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop

    dec     music_tick1
    beq     @play

    rts
@play:
    lda     (_tmp_ptr),y
    sta     music_tick1
    iny

    lda     (_tmp_ptr),y
    tax
    lda     note_table_lo,x
    sta     SID + 7
    lda     note_table_hi,x
    sta     SID + 8
    iny

    lda     (_tmp_ptr),y
    sta     SID + 11
    iny

    lda     (_tmp_ptr),y
    sta     SID + 9
    iny
    lda     (_tmp_ptr),y
    sta     SID + 10
    iny

    lda     (_tmp_ptr),y
    sta     SID + 12
    iny

    lda     (_tmp_ptr),y
    sta     SID + 13
    iny

    tya
    clc
    adc     _tmp_ptr
    sta     _tmp_ptr
    bcc     @no_inc
    inc     _tmp_ptr+1
@no_inc:
    lda     _tmp_ptr
    sta     music_ptr1
    lda     _tmp_ptr+1
    sta     music_ptr1+1
@stop:
    lda     music_start1
    sta     music_ptr1
    lda     music_start1+1
    sta     music_ptr1+1
    lda     #1
    sta     music_tick1
    lda     music_ptr1
    sta     _tmp_ptr
    lda     music_ptr1+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop
    dec     music_tick1
    beq     @play
    rts

;
; Voice 3 player (SID $D40E, music ch2)
;
play_v3:
    lda     music_ptr2
    sta     _tmp_ptr
    lda     music_ptr2+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop

    dec     music_tick2
    beq     @play

    rts
@play:
    lda     (_tmp_ptr),y
    sta     music_tick2
    iny

    lda     (_tmp_ptr),y
    tax
    lda     note_table_lo,x
    sta     SID + $0E
    lda     note_table_hi,x
    sta     SID + $0F
    iny

    lda     (_tmp_ptr),y
    sta     SID + $12
    iny

    lda     (_tmp_ptr),y
    sta     SID + $10
    iny
    lda     (_tmp_ptr),y
    sta     SID + $11
    iny

    lda     (_tmp_ptr),y
    sta     SID + $13
    iny

    lda     (_tmp_ptr),y
    sta     SID + $14
    iny

    tya
    clc
    adc     _tmp_ptr
    sta     _tmp_ptr
    bcc     @no_inc
    inc     _tmp_ptr+1
@no_inc:
    lda     _tmp_ptr
    sta     music_ptr2
    lda     _tmp_ptr+1
    sta     music_ptr2+1
@stop:
    lda     music_start2
    sta     music_ptr2
    lda     music_start2+1
    sta     music_ptr2+1
    lda     #1
    sta     music_tick2
    lda     music_ptr2
    sta     _tmp_ptr
    lda     music_ptr2+1
    sta     _tmp_ptr+1
    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop
    dec     music_tick2
    beq     @play
    rts

;
; Start playing a music track
; A = track number (0=title, 1=level)
;
start_music:
    cmp     #0
    beq     @title
    cmp     #1
    beq     @level
    rts

@title:
    lda     #<music_title_0
    sta     music_ptr0
    lda     #>music_title_0
    sta     music_ptr0+1
    lda     #<music_title_1
    sta     music_ptr1
    lda     #>music_title_1
    sta     music_ptr1+1
    lda     #<music_title_2
    sta     music_ptr2
    lda     #>music_title_2
    sta     music_ptr2+1
    jmp     @init_ticks

@level:
    lda     #<music_level_0
    sta     music_ptr0
    lda     #>music_level_0
    sta     music_ptr0+1
    lda     #<music_level_1
    sta     music_ptr1
    lda     #>music_level_1
    sta     music_ptr1+1
    lda     #<music_level_2
    sta     music_ptr2
    lda     #>music_level_2
    sta     music_ptr2+1

@init_ticks:
    ; Save start addresses for looping
    lda     music_ptr0
    sta     music_start0
    lda     music_ptr0+1
    sta     music_start0+1
    lda     music_ptr1
    sta     music_start1
    lda     music_ptr1+1
    sta     music_start1+1
    lda     music_ptr2
    sta     music_start2
    lda     music_ptr2+1
    sta     music_start2+1

    lda     #1
    sta     music_tick0
    sta     music_tick1
    sta     music_tick2
    lda     #0
    sta     sfx_queue       ; clear SFX state
    rts

;
; Play sound effect (queued, overrides music voice 3)
; X = SFX number (0=shoot, 1=explosion, 2=hurt, 3=pickup, 4=jump)
;
play_sfx:
    ; Set up SFX pointer
    lda     sfx_table_lo,x
    sta     sfx_queue+2     ; ptr_lo
    lda     sfx_table_hi,x
    sta     sfx_queue+3     ; ptr_hi

    ; Play first note immediately on voice 3
    sta     _tmp_ptr+1
    lda     sfx_table_lo,x
    sta     _tmp_ptr

    ldy     #1              ; skip delta byte
    lda     (_tmp_ptr),y
    tax
    lda     note_table_lo,x
    sta     SID + $0E
    lda     note_table_hi,x
    sta     SID + $0F
    iny

    lda     (_tmp_ptr),y
    sta     SID + $12
    iny

    lda     (_tmp_ptr),y
    sta     SID + $10
    iny
    lda     (_tmp_ptr),y
    sta     SID + $11
    iny

    lda     (_tmp_ptr),y
    sta     SID + $13
    iny

    lda     (_tmp_ptr),y
    sta     SID + $14

    ; Set tick from delta
    ldy     #0
    lda     (_tmp_ptr),y
    sta     sfx_queue+1     ; sfx_tick

    ; Activate SFX
    lda     #1
    sta     sfx_queue       ; sfx_state
    rts

;
; Process SFX note advancement (called from play_music when SFX active)
;
play_sfx_note:
    lda     sfx_queue+2
    sta     _tmp_ptr
    lda     sfx_queue+3
    sta     _tmp_ptr+1

    ldy     #0
    lda     (_tmp_ptr),y
    beq     @stop_sfx

    dec     sfx_queue+1
    beq     @play_sfx_entry
    rts

@play_sfx_entry:
    lda     (_tmp_ptr),y
    sta     sfx_queue+1
    iny

    lda     (_tmp_ptr),y
    tax
    lda     note_table_lo,x
    sta     SID + $0E
    lda     note_table_hi,x
    sta     SID + $0F
    iny

    lda     (_tmp_ptr),y
    sta     SID + $12
    iny

    lda     (_tmp_ptr),y
    sta     SID + $10
    iny
    lda     (_tmp_ptr),y
    sta     SID + $11
    iny

    lda     (_tmp_ptr),y
    sta     SID + $13
    iny

    lda     (_tmp_ptr),y
    sta     SID + $14
    iny

    tya
    clc
    adc     sfx_queue+2
    sta     sfx_queue+2
    bcc     @done_sfx
    inc     sfx_queue+3
@done_sfx:
    rts

@stop_sfx:
    lda     #0
    sta     sfx_queue
    sta     sfx_queue+1
    rts
