;
; ANP2 - Title screen and loading screen graphics
; Converted from ZX Spectrum to C64 bitmap format
;
; C64 bitmap mode (VIC bank 3):
;   Bitmap at $E000 (8000 bytes, accessed as VIC bank 3 offset $2000)
;   Screen RAM at $C000 (1000 bytes, VIC bank 3 offset $0000)
;   Color RAM at $D800 (1000 bytes)
;
; Data stored in MAIN segment, copied at runtime by draw_title_gfx
;

.export title_bitmap_data, title_screen_data, title_color_data

.segment "RODATA"

; Title screen bitmap (8000 bytes)
; Converted from Spectrum screen 2 - game title screen
title_bitmap_data:
    .incbin "title_bitmap.bin"

; Title screen RAM (1000 bytes)
; Contains screen byte codes for each of 40x25 cells
title_screen_data:
    .incbin "title_screen.bin"

; Title color RAM (1000 bytes)
; Foreground color (4-bit) for each cell
title_color_data:
    .incbin "title_color.bin"
