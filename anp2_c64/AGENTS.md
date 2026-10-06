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
src/anp2.s          # Main game engine (~2266 lines)
assets/screen.s     # Title/loading screen graphics placeholders
assets/sprites.s    # Player, enemy, bullet sprite data (hires, no multicolor)
assets/sound.s      # 3-voice SID music player + SFX engine (~350 lines)
assets/levels.s     # Level map data + enemy/item spawns
assets/music_title.s # Title music (3 channels) — GENERATED from "Alien: intro"
assets/music_level.s # Level music (3 channels) — GENERATED, do not hand-edit
tools/pt2gt.c        # PT3 pattern data -> 6502 note stream converter
source_music/Makefile     # PT3 extraction + conversion pipeline
source_music/decompress_game.py # Exomizer bank decompression
source_music/mksong.py    # Assembles assets/*.s from channel streams
source_music/music_ingame_ch{0,1,2}.s # Per-channel pt2gt output (level)
source_music/music_intro_ch{0,1,2}.s  # Per-channel pt2gt output (title)
```

## Build Commands
- `make` — assemble all .s files and link into anp2.prg
- `make clean` — remove build artifacts
- `ca65 -t c64 -g -I src -o build/foo.o foo.s` — assemble single file
- `ld65 -C anp2.cfg -o anp2.prg build/*.o` — link manually
- `make -C source_music` — regenerate `assets/music_level.s` **and** `assets/music_title.s` from the PT3 modules
- `make -C source_music clean` — drop decompressed banks, modules, and the pt2gt binary

`assets/music_level.s` and `assets/music_title.s` are generated. Editing them by hand
will be overwritten; change `tools/pt2gt.c` or the Makefile instead and re-run
`make -C source_music`.

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
- $D011=$6B = %01101011: BMM=1 (bitmap mode), DEN=1 (display ON), MCM=0 (standard bitmap), 25 rows
- $D021=0: background black
- Sprites: single-color (hires), enabled 0-3, pointers at $C3F8-$C3FB
- Sprite data copied at runtime from RODATA to VIC bank 3 ($C400-$C4BF)
  - $C400 = player sprite, $C440 = xeno, $C480 = guard, $C4C0 = bullet
- Sprite pointer values: $10 (player), $11 (xeno), $12 (guard), $13 (bullet)
- VIC memory layout: bank $C000-$FFFF, screen $C000 (offset $0000), bitmap $E000 (offset $2000)

## Screen Data
- **screen.s** (assets/screen.s): bitmap/screen/color data via `.incbin` of binary files
- **title_bitmap.bin** (8000B): C64 bitmap, converted from Spectrum format
- **title_screen.bin** (1000B): screen byte codes (0-124, = char_row*5+col_group)
- **title_color.bin** (1000B): foreground color per cell (Spectrum INK -> C64 color)
- **spec2c64.py**: Python converter script (Spectrum -> C64 BMM format)
- Bitmap conversion: SB=$2000 + char_row*5 + col_group; addr = SB*64 + scanline*8 + col_in_byte
- Screen data copied by `draw_title_gfx` in 3 phases: bitmap (2x16-pair loops), screen RAM (4 blocks), color RAM (4 blocks)

### C64 Bitmap Color Limitation
- **Standard bitmap mode (BMM=1, MCM=0)**: Colors come from screen RAM byte (upper nybble = bg, lower nybble = fg). Color RAM ($D800) is **NOT used** for pixel colors.
- Screen byte = sb_index = char_row*5 + col_group (0-124) -> address is correct, colors are position-dependent (wrong Spectrum INK/PAPER).
- **Color RAM is ignored** in standard bitmap mode. Title screen image shapes are correct but colors are wrong.
- **Fix (future)**: Reorganize bitmap data so each cell's 8-byte pattern lives at address `$2000 + desired_byte * 64 + ...` where desired_byte = (paper<<4) | ink.

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
- `_player_health` (ZP, 1 byte) — player HP (starts at 3)
- `_player_weapon` (ZP, 1 byte) — 0=pistol, 1=rifle, 2=shotgun
- `_player_ammo` (ZP, 1 byte) — ammo count
- `_scroll_x` (ZP, 2 bytes) — camera scroll (pixels)
- `_scroll_y` (ZP, 1 byte) — vertical scroll (unused)
- `_joystick_state` (ZP, 1 byte) — CIA1 port B
- `_on_ground` (ZP, 1 byte) — 1 when player on solid ground
- `_invincible_timer` (ZP, 1 byte) — countdown after taking damage
- `music_ptr0/1/2` (BSS, 2 bytes each) — 3 music channel data pointers
- `music_tick0/1/2` (BSS, 1 byte each) — per-channel frame counters
- `sfx_queue` (BSS, 4 bytes) — SFX state, tick, data pointer
- `enemy_type/x/y/hp/state/timer` (BSS) — enemy array
- `bullet_x/y/vx/vy/type/active` (BSS) — bullet array
- `particle_x/y/vx/vy/life/active` (BSS) — particle array
- `tile_map` (BSS, 1280 bytes) — decompressed level tiles

## IRQ System
- VIC raster IRQ at line 0 (VBLANK)
- IRQ handler increments `_frame_counter`, reads input, calls `game_tick` when state=2
- `play_music` called from IRQ handler every frame
- Main loop busy-waits on `_frame_counter` change

## Rendering
- Bitmap cleared by writing $00 to $E000-$FF3F (32x 256-byte chunks, needs $01=$00)
- Screen RAM ($C000) holds tile color bytes in game mode
- Hardware scrolling via VIC register $D016 (bits 0-2)
- Tile scrolling: when coarse scroll changes, screen RAM shifts left/right and new column is drawn
- `draw_col` renders one column of tiles (screen byte + 8-byte bitmap pattern)
- `render_full_map` draws all 40x25 tiles on initial load
- Sprite positions updated in VIC registers $D000-$D00F

## Sound
- `start_music(A)` — play track 0=title, 1=level1 (called from show_title, start_game)
- `play_music` — called every frame from IRQ handler
- `play_sfx(X)` — X=0=shoot, 1=explosion, 2=hurt, 3=pickup, 4=jump (called from player_shoot, etc.)
- Music data format: delta_time, note, waveform, duty_lo, duty_hi, AD, SR, 0=end
- **Voice mapping**: SID voice 1 = music ch0, voice 2 = music ch1, voice 3 = music ch2 (shared with SFX)
- **3 independent channel streams**: PT3 tick patterns converted via pt2gt → 3 separate data streams
- **SFX**: queue-based (`sfx_queue`: state, tick, ptr_lo, ptr_hi), overrides voice 3 when active; first note played immediately, subsequent notes frame-stepped until $00 end marker
- **Music data files**: `assets/music_title.s` (`music_title_0/1/2`), `assets/music_level.s` (`music_level_0/1/2`)
- **Level music**: speed=6, 27 patterns, 13-position order list -> 832 rows/channel. Source: `bank_3.bin` offset `$0000` (8704 bytes)
- **Title music**: speed=4, 6 patterns, **2-position** order list `[0,3]` -> 128 rows/channel. Source: `bank_3.bin` offset `$2200`, module name **"Alien: intro"** (1024 bytes)
- **Composer**: all three modules are by **Oleg Nikitin** (`n1k-o`) — the header string is `ProTracker 3.7 compilation of ... by n1k-o`. ZXArt lists the same release under his name
- **PT3 extraction process**: `source_music/decompress_game.py` decompresses the Spectrum blocks with Exomizer 2 and writes `banks/bank_*.bin`; the loader's 10 decompression sites are enumerated there, including two loader-internal buffers at `$629C` and `$65F0`. `tools/pt2gt` then walks the packed pattern table of a module once per channel

### PT3 Module Layout (Neoplasma 2)
`bank_3.bin` is **16383 bytes and packs three modules back to back**, each on a `$200`
boundary and each carrying its own `ProTracker 3.7 compilation of ...` header:

| Module | Offset | Size | Patterns | Speed | Role |
|--------|--------|------|----------|-------|------|
| `Neoplasma 2: ingame` | `$0000` | `$2200` | 27 | 6 | level music |
| `Alien: intro` | `$2200` | `$0400` | 6 | 4 | **title screen** |
| `Neoplasma 2: bossfight` | `$2600` | `$1A00` | 9 | 4 | boss music (not wired up) |

> Always bound an extraction to its own `$200` slot. The earlier single 15301-byte
> extraction ran `ingame`'s data straight through the other two headers.
> `dd` has no hex literal syntax — `count=0x2200` parses as **0**, so offsets and
> lengths are decimal in the Makefile.

Key offsets — do not assume these are standard:

| Offset | Meaning |
|--------|---------|
| `$64`  | speed (6 / 4 / 4) |
| `$65`  | **song length = order-list length**, reliable in every module here (13 / 2 / 3 / 11 for `ingame` / `intro` / `bossfight` / `Final Cut`). It is *not* the pattern count |
| `$66`  | loop position — always below the length (0 / 1 / 1 / 5), which cross-checks `$65` |
| `$67`  | pattern table offset (`$00D7` / `$00CC` / `$00CD`) |
| order list | exactly the `$65` bytes in `[pattab-1-$65, pattab-2]`, ending at a `$FF` sitting directly below the table. All four modules here start at `$C9` |
| `$D7`+ | pattern pointer table, one 16-bit offset per pattern, stride **2** |

**Do not derive the order list by scanning backwards while the byte looks like a
pattern index.** Nothing stops that scan at the `$FF` terminator, so when the header
bytes ahead of the list happen to be small it runs straight into them: `Alien: intro`
reads **31** positions that way instead of **2** (and `Final Cut` reads 12 instead of
11), which inflated the row count until `RODATA` overflowed `MAIN` by 37 KB.
`read_order_list()` anchors on `$FF` at `pattab-1` and takes the length from `$65`.

**Pattern count cannot be read from a header field and entry 0 is not "the first
pattern".** `count_pattern_entries()` therefore scans for the candidate `n` whose
*minimum* pointer equals `pat_off + 2*n` — the table is immediately followed by pattern
data, so the lowest offset it contains is the address of the first stored pattern.
Pointers may repeat or step backwards when patterns are shared or reordered, so
`find_pattern_table()` validates entries against `pat_off + 2*n < addr < size` rather
than requiring them to increase.

`ingame` (27) satisfies both *old* rules coincidentally — entry 0 is the first data
address and its pointers increase — which is why the bug shipped unnoticed. The ZXArt
reference module `nq_-_..._Final_Cut_(2023).pt3` (33) does not: its table is reordered
and repeats pointers, and it previously failed with `ERROR: Could not find pattern table`.

Pattern pointers address channel 0 only. Each pattern holds 3 channel streams packed
back to back, each `$00`-terminated, so `parse_channel_data` reports the stream end and the
caller steps over the preceding channels.

Every order position emits a full 64 rows: a channel stream ends at its `$00` as soon
as it runs out of commands, and `parse_channel_data` pads the rows it did not cover
with silence. `extract_all_notes` then renumbers those rows globally across the order
list, and `convert_module` folds runs that drive the SID identically into a single
event whose delta spans the gap — without that fold the padded rests cost ~40KB.
Deltas are multiplied by the module `speed` (`mksong.py --speed` only writes a comment,
so nothing scaled them before) and split whenever a run would exceed 255 frames.

| Module | speed | positions | rows/ch | frames/ch | events ch0/1/2 |
|--------|-------|-----------|---------|-----------|----------------|
| `ingame` (level) | 6 | 13 | 832 | 4992 | 632 / 779 / 521 |
| `Alien: intro` (title) | 4 | 2 | 128 | 512 | 68 / 18 / 5 |
| `Final Cut` (ZXArt fixture) | 2 | 11 | 704 | 1408 | — |

All three channels of a track sum to exactly `rows × speed` frames — check this by
parsing the generated `.s`, it is the property that keeps playback in step. `play_v3`'s
`@stop` handlers still restart each channel from its own `music_startN` independently
when it hits `$00`, but since every channel now ends on the same frame the restarts
stay together.

A naive structural scan over all decompressed files reports only one module because it
assumes an increasing pointer table — grep the module headers instead:
`re.finditer(b'ProTracker 3.7', bank)` finds all three.

## Game Logic Details

### Player Physics
- Gravity: +4 per frame to _player_y (subpixel)
- Jump: velocity = -16 (up), only when `_on_ground` is set
- Horizontal speed: 2 pixels per frame
- Floor collision: checks tile directly below player feet (bottom + 1 row), snaps to tile top, sets `_on_ground = 1`

### Collision Detection
- Player bullets vs enemies: AABB check, decrement `enemy_hp`, kill when HP <= 0
- Player vs enemies: AABB check, decrement `_player_health`, set `_invincible_timer = $80` (~2s), push player back
- Invincibility: damage skipped while `_invincible_timer > 0`, decremented each frame
- Floor collision: after gravity, check tile below feet, snap if solid

### Weapons
- Pistol: fires 1 bullet forward
- Rifle: fires 1 bullet with higher velocity
- Shotgun: fires 3 bullets with spread
- Ammo decremented on each shot, no shooting when ammo = 0

### Scrolling
- `update_camera`: sets `_scroll_x` to `_player_x+1 - 24` (pixels), clamped 0-128
- `render_frame`: applies fine scroll ($D016), compares coarse scroll (x>>3) to `_tmp3`
- On coarse scroll increase: `screen_shift_left` (4 chunks, 999 bytes forward), then `draw_col` at column 39
- On coarse scroll decrease: `screen_shift_right` (4 chunks reverse), then `draw_col` at column 0
- `draw_col(Y, _tmp1)`: Y = screen column (0 or 39), `_tmp1` = tile map column

## Current Status (Jun 2026)
- **3-voice music playback**: level and title both convert and link (level from `bank_3.bin` `$0000`, title from `$2200` "Alien: intro"). Channels are padded to equal length: level 832 rows/channel (4992 frames), title 128 (512)
- **Music looping**: each channel wraps to **its own** `music_startN` when it hits its `$00` end marker, but all three now end on the same frame so the restarts stay in step
- **SFX**: queue-based on voice 3, 5 effects (shoot, explosion, hurt, pickup, jump)
- **HUD**: Text-mode status bar at top of screen — HP, ammo, score (5-digit) rendered via bitmap font
- **Wall collision**: Horizontal + ceiling collision with tile map
- **Item pickup**: 4 item types (weapon upgrade, health, ammo, keycard) placed on tile map, collision checked each frame, pickup SFX
- **Enemy AI**: Patrol mode (direction toggle every ~60 frames, move 1px/frame) when player >96px away; chase mode (2px/frame toward player, shoot every ~60 frames) when closer
- **Build**: `make` produces `anp2.prg` (31288 bytes)

## Known Issues & Missing Features
- **Title music is probably inaudible**: `Alien: intro`'s only note byte anywhere in its channel streams is `$59` (AY index 9 = A-1), and `ay_to_sid_note()` computes `note - 12` with a floor of 0, so it lands on `note_table` index 0 = frequency 0. The title therefore renders as one inaudible note plus rests on all three channels. Level music is unaffected (AY 44-56 -> SID 32-44)
- **`Alien: intro` order list may be too short**: `$65` says 2 positions `[0,3]`, but the module packs 6 patterns and patterns 4/5 hold the only varied pitches (`$8B`/`$8C`/`$81`). If the real list is longer, that melody is being dropped — worth confirming against an AY emulator before trusting the title track
- **Ornaments are parsed but never applied**: `ev->ornament` reaches the output comment only; PT3 ornaments shift the note pitch per row and `print_sid_event()` ignores them
- **`bossfight` module extracted but not wired**: `bank_3.bin` `$2600` is extracted to `banks/modules/bossfight.pt3` by `make -C source_music banks`, but nothing calls `start_music` for it — no boss state exists. Also note the bank is 16383 bytes while the third slot ends at 16384, so the last byte is truncated by `dd`
- **Vertical scrolling unverified at runtime**: implemented in `src/anp2.s` (16-bit tile indexing, vertical camera offset, row blits/redraws, one shifted row per rendered frame, `_scroll_x_prev` fix, Level 1 start row 12). Compiles and links cleanly but has not been confirmed in an emulator — see VICE note below
- **VICE validation blocked**: `x64sc` autostart halts at BASIC `searching for anp2` / `loading` and reports `Main CPU: Error - cycle limit reached.`; remote-monitor never reaches `render_frame`. Emulator verification of both scrolling and the rebuilt music is still outstanding
- **Pause**: State 3 handler not implemented
- **Multiple levels**: Level progression not implemented
- **Grenades**: `_player_grenades` variable exists but no throw logic
- **Physics**: Jump velocity uses unsigned 16-bit addition causing sprite Y to wrap through off-screen values; ceiling collision helps mitigate
- **Enemy gravity**: Enemies pushed by gravity but no floor collision — they fall through the map
- **pt2gt warnings**: unused variables `sid_note_lo`, `sid_note_hi`, `has_note_or_rest`, `all_events`, `row_counts`, `total_notes`
- **`find_pt3_modules()` is over-permissive**: it still writes many false-positive `bank_*_pt3_at_*.bin` files; it is unused by the build but makes the `banks/` directory noisy

## Actions Not Allowed
- Do NOT create new .md or README files unless explicitly asked
- Do NOT use `.fill` directive — use `.res` instead
- Do NOT use `.include` for cross-file symbols — use `.import`/`.export`
- Do NOT commit to git unless explicitly asked
