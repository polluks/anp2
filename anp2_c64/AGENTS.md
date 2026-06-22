# ANP2 C64 Port — Agent Guide

## Project Overview
Port of the ZX Spectrum 128K game "Aliens: Neoplasma 2" (Sanchez Crew, n1k-o, ER) to the Commodore 64. Side-scrolling action game set in the Aliens universe.

## Assembler & Toolchain
- **Assembler**: ca65/ld65 (cc65 v2.19) — NOT 64tass or KickAssembler
- **Build**: `make` (clean build: `make clean && make`)
- **Output**: `anp2.prg` (C64 PRG format, loads at $0801)
- **Config**: `anp2.cfg` — ZP ($02-$FF), BASIC ($0801-$088D), MAIN ($0900-$9FFF)

## Project Structure
```
src/anp2.s          # Main game engine (~800 lines)
assets/screen.s     # Title/loading screen graphics placeholders
assets/sprites.s    # Player, enemy, bullet sprite data (multicolor)
assets/sound.s      # SID music player + SFX engine
assets/levels.s     # Level map data + enemy/item spawns
```

## Build Commands
- `make` — assemble all .s files and link into anp2.prg
- `make clean` — remove build artifacts
- `ca65 -t c64 -g -I src -o build/foo.o foo.s` — assemble single file
- `ld65 -C anp2.cfg -o anp2.prg build/*.o` — link manually

## Memory Map (linker config)
| Address   | Use                      |
|-----------|--------------------------|
| $02-$FF   | Zero page variables      |
| $0801     | BASIC stub + CODE + RODATA + BSS (continuous) |
| $C000-$C3E7 | Screen RAM (1000 bytes) |
| $D800-$DBE7 | Color RAM (1000 bytes) |
| $E000-$FF3F | Bitmap (8000 bytes, VIC bank 3, Kernal banked out) |

### PRG Load Address
- ld65 PRG output consumes **first 2 bytes of first segment data** as the load address.
- The BASIC header must **prefix** with `.byte $01, $08` so PRG loads at $0801.
- Without this prefix, ld65 uses the BASIC `next line pointer` value ($080B) as load address → program loads 10 bytes too late, SYS 2061 hits garbage.
- `file anp2.prg` should say "Commodore C64 program". If it says "Applesoft BASIC" the load address is wrong.

## VIC-II Setup
- VIC bank 3 ($DD00=$FC): screen at $C000 (offset $0000), bitmap at $E000 (offset $2000)
- Kernal+BASIC banked out via `lda #$00 / sta $01`
  - $01 bit 1=0 (Kernal out) is REQUIRED to write to $E000-$FFFF (bitmap)
  - $01 bit 0=0 (BASIC out) recommended for safety
- $D018=$02: screen at $C000 (bits 4-3=$0), bitmap at $E000 (bits 1-0=$2)
- $D011=$6B = %01101011: BMM=1 (bitmap mode), DEN=1 (display ON, was $3B with DEN=0), MCM=0 (standard bitmap), 25 rows
- $D021=0: background black
- 8 hardware sprites enabled, multicolor mode
- Sprite pointers at $C7F8-$C7FF
- VIC memory layout: bank $C000-$FFFF, screen $C000 (offset $0000), bitmap $E000 (offset $2000)

## Screen Data
- **screen.s** (assets/screen.s): bitmap/screen/color data via `.incbin` of binary files
- **title_bitmap.bin** (8000B): C64 bitmap, converted from Spectrum format
- **title_screen.bin** (1000B): screen byte codes (0-124, = char_row*5+col_group)
- **title_color.bin** (1000B): foreground color per cell (Spectrum INK → C64 color)
- **spec2c64.py**: Python converter script (Spectrum → C64 BMM format)
- Bitmap conversion: SB=$2000 + char_row*5 + col_group; addr = SB*64 + scanline*8 + col_in_byte
- Screen data copied by `draw_title_gfx` in 3 phases: bitmap (2×16-pair loops), screen RAM (4 blocks), color RAM (4 blocks)

### C64 Bitmap Color Limitation
- **Standard bitmap mode (BMM=1, MCM=0)**: Colors come from screen RAM byte (upper nybble = bg, lower nybble = fg). Color RAM ($D800) is **NOT used** for pixel colors.
- Screen byte = sb_index = char_row*5 + col_group (0-124) → address is correct, colors are position-dependent (wrong Spectrum INK/PAPER).
- **Color RAM is ignored** in standard bitmap mode. Title screen image shapes are correct but colors are wrong.
- **Fix (future)**: Reorganize bitmap data so each cell's 8-byte pattern lives at address `$2000 + desired_byte * 64 + ...` where desired_byte = (paper<<4) | ink. Requires cells with same (ink,paper) to have matching pixel data. Title screen has 761/768 unique patterns → conflicts make this approach unworkable without per-cell color independence.
- **Alternative (future)**: Use multi-color bitmap mode (MCM=1) → 160×200 res but 3 colors per cell from color RAM. Or use character mode with max 256 unique chars.

## Cross-Module Symbol Convention
- Zero-page symbols use `.importzp`/`.exportzp` (e.g., `_tmp_ptr`)
- Regular symbols use `.import`/`.export`
- Constants (`.define`) must be defined in each module that uses them

## Game State Machine
| State | Value | Handler           |
|-------|-------|-------------------|
| Title | 0     | `title_tick`      |
| Loading | 1  | `loading_tick`    |
| Playing | 2  | `game_tick` (IRQ) |
| Paused | 3   | (not implemented) |
| Game Over | 4 | `game_over_tick` |

## Key Variables (zeropage + BSS)
- `_frame_counter` (ZP, 1 byte) — incremented each IRQ
- `_game_state` (ZP, 1 byte) — 0/1/2/3/4
- `_player_x/_player_y` (ZP, 2 bytes each) — 16-bit subpixel position
- `_player_dir` (ZP, 1 byte) — 0=left, 1=right
- `_player_frame` (ZP, 1 byte) — animation frame index
- `_scroll_x/_scroll_y` (ZP, 3 bytes) — camera scroll
- `_joystick_state` (ZP, 1 byte) — CIA1 port B
- `music_ptr`/`music_tick` (BSS) — sound engine state

## IRQ System
- VIC raster IRQ at line 0 (VBLANK)
- IRQ handler increments `_frame_counter`, reads input, calls `game_tick` when state=2
- Main loop busy-waits on `_frame_counter` change

## Rendering
- Bitmap cleared by writing $00 to $E000-$FF3F (32x 256-byte chunks, needs $01=$00 to access $E000+)
- Screen RAM ($C000) holds character codes for text/title (1000 bytes, 40×25)
- Color RAM ($D800) holds foreground colors
- Hardware scrolling via VIC register $D016 (bits 0-2)
- Sprite positions updated in VIC registers $D000-$D00F
- `draw_title_gfx` copies bitmap/screen/color from RODATA to VIC addresses

## Sound
- `start_music(A)` — play track 0=title, 1=level1
- `play_music` — call once per frame from IRQ
- `play_sfx(X)` — X=0=shoot, 1=explosion, 2=hurt, 3=pickup, 4=jump
- Music data format: delta_time, note, waveform, duty_lo, duty_hi, AD, SR, 0=end
- Voices: voice 1 = music, voice 2 = unused (reserved), voice 3 = SFX

## Original ZX Spectrum Files
- `ANP2_DEMO_ENG.tap` — source tape image (58965 bytes)
- `extracted_block_*.bin` — extracted TAP blocks 3-6
- Block 3 = loader + compressed loading screen (6668 bytes)
- Blocks 4/5/6 = compressed game data (22191/20129/9878 bytes)

## Decompression (Exomizer 2)
- **Algorithm**: Exomizer 2.x — DJNZ state machine with bit-stream LZ77
- **Decompressor**: Z80 at $621A in block 3 (offset 0x021A in file)
- **Signature**: `LD BC,$7FFD / ADD A,$10 / OUT (C),A` prefix, then `EX AF,AF' / LDI / LD BC,$02FF / EX AF,AF' / ADD A / JR NZ / LD A,(HL)+ / RLA / RL C / JR NC / EX AF,AF' / DJNZ`
- **Python depacker**: `/root/ghidra/decompress.py` (work in progress — bit stream and state machine still being refined)
- **Compressed data locations within block 3**:
  - Loading screen 1: offset `$629C - $6000 = 0x029C` (after decompressor at $621A-$628E and helper at $628F-$629B)
  - Loading screen 2: offset `$65F0 - $6000 = 0x05F0`
- **Blocks 4/5/6**: Each is a standalone Exomizer 2 compressed stream (no loader prefix)

### Exomizer 2 State Machine (Z80)
- B register tracks state (initial B=2 after LD BC,$02FF)
- State 1 (B=1, after DJNZ): `SRL C` — if bit=1 → literal (LDI), B=2; if bit=0 → INC B, back to bit reader
- State 0 (B=0, after second DJNZ): `SRA C` — reads match/length encoding
- Bit reader: ADD A shifts buffer; when empty loads (HL); RLA/RL C chains bits into C
- Match copy: `PUSH HL / LD L,C / LD H,B / ADD HL,DE / LD C,A / LD B,0 / LDIR / POP HL` pattern

## Z80 Disassembler
- `/root/ghidra/z80dasm.py` — partially working, has opcode bugs for 0xC6-0xFE range (immediate ALU ops), JR displacements, and RET cc opcodes at $C8/$D0/$D8/$E0/$E8/$F0/$F8
- To disassemble specific range: edit the `files_to_analyze` entries and re-run
- Fixed opcodes already: JR/DJNZ displacement, ADD A,n/ADC/SUB/SBC/AND/XOR/OR/CP immediate

## Actions Not Allowed
- Do NOT create new .md or README files unless explicitly asked
- Do NOT use `.fill` directive — use `.res` instead
- Do NOT use `.include` for cross-file symbols — use `.import`/`.export`
- Do NOT commit to git unless explicitly asked
