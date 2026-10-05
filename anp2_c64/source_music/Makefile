# Music extraction + conversion pipeline.
#
#   make            build the converter and regenerate the game music asset
#   make banks      decompress the Spectrum banks only
#   make sid        PT3 -> 6502 .s streams (what sound.s consumes)
#   make asset      .s streams -> ../assets/music_level.s
#   make clean      remove generated banks, modules and the converter

CC       ?= cc
CFLAGS   ?= -O2 -Wall
PYTHON   ?= python3

TOOLDIR  := ../tools
BANKDIR  ?= banks
MODDIR   := $(BANKDIR)/modules
OUTDIR   := .

PT2GT := $(TOOLDIR)/pt2gt

# decompress_game.py reads extracted_block_*.bin from ANP2_ROOT and writes
# bank_*.bin to ANP2_OUTDIR. Blocks 3-6 all live next to this Makefile.
ANP2_ROOT  ?= $(CURDIR)
ANP2_OUTDIR = $(CURDIR)/$(BANKDIR)

# bank_3.bin packs three PT3 modules back to back on $200 boundaries. Each one
# starts with its own "ProTracker 3.7 compilation of ..." header.
#
#
# Bounding each module to its own $200 slot matters: the old single 15301-byte
# extraction ran ingame's data straight through the other two headers.
MOD_BANK   := $(BANKDIR)/bank_3.bin

# Offsets/lengths are decimal because dd has no hex literal syntax.
#   $0000  Neoplasma 2: ingame      27 patterns, speed 6
#   $2200  Alien: intro              6 patterns, speed 4   <- title screen
#   $2600  Neoplasma 2: bossfight    9 patterns, speed 4
MOD_INGAME_OFF := 0
MOD_INGAME_LEN := 8704
MOD_INTRO_OFF := 8704
MOD_INTRO_LEN := 1024
MOD_BOSS_OFF := 9728
MOD_BOSS_LEN := 6656

MOD_INGAME := $(MODDIR)/ingame.pt3
MOD_INTRO  := $(MODDIR)/intro.pt3
MOD_BOSS   := $(MODDIR)/bossfight.pt3
MODULES    := $(MOD_INGAME) $(MOD_INTRO) $(MOD_BOSS)

CHANNELS := 0 1 2
SID_OUT  := $(foreach c,$(CHANNELS),$(OUTDIR)/music_ingame_ch$(c).s)
TITLE_OUT := $(foreach c,$(CHANNELS),$(OUTDIR)/music_intro_ch$(c).s)

# The assets the game actually links against.
ASSETDIR     := ../assets
LEVEL_ASSET  := $(ASSETDIR)/music_level.s
TITLE_ASSET  := $(ASSETDIR)/music_title.s
PT3_SPEED    ?= 6
PT3_SOURCE   ?= bank_3.bin offset 0x0

.PHONY: all banks sid asset clean
.DELETE_ON_ERROR:

all: asset

banks: $(MODULES)

$(PT2GT): $(TOOLDIR)/pt2gt.c
	$(CC) $(CFLAGS) -o $@ $<

$(MODDIR)/ingame.pt3: $(MOD_BANK)
	@mkdir -p $(MODDIR)
	dd if=$(MOD_BANK) of=$@ bs=1 skip=$(MOD_INGAME_OFF) \
	    count=$(MOD_INGAME_LEN) status=none

$(MODDIR)/intro.pt3: $(MOD_BANK)
	@mkdir -p $(MODDIR)
	dd if=$(MOD_BANK) of=$@ bs=1 skip=$(MOD_INTRO_OFF) \
	    count=$(MOD_INTRO_LEN) status=none

$(MODDIR)/bossfight.pt3: $(MOD_BANK)
	@mkdir -p $(MODDIR)
	dd if=$(MOD_BANK) of=$@ bs=1 skip=$(MOD_BOSS_OFF) \
	    count=$(MOD_BOSS_LEN) status=none

$(MOD_BANK):
	@mkdir -p $(BANKDIR)
	ANP2_ROOT=$(ANP2_ROOT) ANP2_OUTDIR=$(ANP2_OUTDIR) $(PYTHON) decompress_game.py

sid: $(SID_OUT) $(TITLE_OUT)

$(OUTDIR)/music_ingame_ch%.s: $(PT2GT) $(MOD_INGAME)
	$(PT2GT) $(MOD_INGAME) $@ -ch $* -level -load 0

$(OUTDIR)/music_intro_ch%.s: $(PT2GT) $(MOD_INTRO)
	$(PT2GT) $(MOD_INTRO) $@ -ch $* -level -load 0

asset: $(LEVEL_ASSET) $(TITLE_ASSET)

$(LEVEL_ASSET): $(SID_OUT) mksong.py
	@mkdir -p $(ASSETDIR)
	$(PYTHON) mksong.py --out $@ --prefix music_level \
	    --source "$(PT3_SOURCE)" --speed $(PT3_SPEED) $(SID_OUT)

$(TITLE_ASSET): $(TITLE_OUT) mksong.py
	@mkdir -p $(ASSETDIR)
	$(PYTHON) mksong.py --out $@ --prefix music_title \
	    --source "bank_3.bin offset 0x2200 (Alien: intro)" --speed 4 $(TITLE_OUT)

clean:
	rm -rf $(BANKDIR)
	rm -f $(PT2GT)