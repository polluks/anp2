# ANP2 — Aliens: Neoplasma 2

ZX Spectrum 128K game (Sanchez Crew, n1k-o, ER) ported to the Commodore 64.

## Build

Requires `ca65`/`ld65` (cc65 V2.19), plus `cc` and `python3` for the music
pipeline.

```
make                              # -> anp2.prg (loads at $0801)
make -C source_music              # regenerate music assets from PT3
make run                          # launch in VICE, if installed
```

`anp2.prg` is committed, and a clean build reproduces it byte for byte.

## Architecture

```mermaid
flowchart TD
    TAP["ANP2_DEMO_ENG.tap<br/>Spectrum 128K original"]
    BLOCKS["extracted_block_*.bin<br/>Exomizer 2 payloads"]
    DECOMP["source_music/decompress_game.py<br/>10 decompression sites"]
    BANKS["source_music/banks/bank_*.bin"]
    B3["bank_3.bin<br/>16383 bytes"]

    TAP --> BLOCKS --> DECOMP --> BANKS --> B3

    subgraph mods ["Three PT3 modules packed into bank_3.bin on $200 boundaries"]
        direction LR
        MI["ingame<br/>$0000, 9 patterns / 27 streams, speed 6"]
        MV["Alien: intro<br/>$2200, 2 patterns / 6 streams, speed 4"]
        MB["bossfight<br/>$2600, 3 patterns / 9 streams, speed 4"]
    end

    B3 --> MI
    B3 --> MV
    B3 --> MB

    P2G["tools/pt2sid<br/>PT3 pattern data to 6502 note stream"]
    MKS["source_music/mksong.py<br/>assemble channel streams"]

    MI --> P2G
    MV --> P2G
    P2G --> CHL["music_ingame_ch0/1/2.s"]
    P2G --> CHT["music_intro_ch0/1/2.s"]
    CHL --> MKS
    CHT --> MKS

    MKS --> A_LEVEL["assets/music_level.s<br/>export music_level_0/1/2"]
    MKS --> A_TITLE["assets/music_title.s<br/>export music_title_0/1/2"]

    S_SRC["assets/*.s<br/>screen, sprites, sound, levels"]
    A_LEVEL --> CA65["ca65 -t c64"]
    A_TITLE --> CA65
    S_SRC --> CA65
    CA65 --> OBJ["build/*.o"]
    OBJ --> LD65["ld65 -C anp2.cfg"]
    LD65 --> PRG["anp2.prg"]

    PRG --> LOAD["Loads at $0801<br/>VIC bank 3, bitmap mode"]
    LOAD --> IRQ["Raster IRQ at line 0<br/>frame counter++ + play_music"]

    IRQ --> SM{"game_state"}
    SM -->|"0"| ST["title_tick<br/>start_music(0)"]
    SM -->|"1"| LD["loading_tick"]
    SM -->|"2"| GT["game_tick<br/>start_music(1)"]
    SM -->|"3"| PU["paused"]
    SM -->|"4"| GO["game_over_tick"]

    ST --> SID["SID voices 1-3<br/>independent channel streams"]
    GT --> SID
    GT --> SFX["play_sfx(X)<br/>overrides voice 3"]

    classDef data fill:#d4edda,stroke:#28a745,color:#155724
    classDef tool fill:#cce5ff,stroke:#007bff,color:#004085
    classDef music fill:#fff3cd,stroke:#ffc107,color:#856404
    classDef code fill:#f8d7da,stroke:#dc3545,color:#721c24

    class TAP,BLOCKS,BANKS,B3,A_LEVEL,A_TITLE data
    class DECOMP,P2G,MKS,CA65,LD65 tool
    class MI,MV,MB,CHL,CHT,SID,SFX music
    class PRG,IRQ,SM,ST,LD,GT,PU,GO code
```

[AGENTS.md](AGENTS.md) has the memory map, the PT3 module layout, the game
state machine and the list of known gaps.
