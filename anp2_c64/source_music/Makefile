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

# bank_3.bin holds the genuine "ingame" PT3 module at offset 0. Its data ends
# at 0x3BC5; the rest of the bank is padding.
MOD_BANK   := $(BANKDIR)/bank_3.bin
MOD_SIZE   := 15301
MOD_INGAME := $(MODDIR)/ingame.pt3

CHANNELS := 0 1 2
SID_OUT  := $(foreach c,$(CHANNELS),$(OUTDIR)/music_ingame_ch$(c).s)

# The asset the game actually links against.
ASSETDIR     := ../assets
LEVEL_ASSET  := $(ASSETDIR)/music_level.s
PT3_SPEED    ?= 6
PT3_SOURCE   ?= bank_3.bin offset 0x0

.PHONY: all banks sid asset clean
.DELETE_ON_ERROR:

all: asset

banks: $(MOD_INGAME)

$(PT2GT): $(TOOLDIR)/pt2gt.c
	$(CC) $(CFLAGS) -o $@ $<

$(MOD_INGAME): $(MOD_BANK)
	@mkdir -p $(MODDIR)
	dd if=$(MOD_BANK) of=$@ bs=1 count=$(MOD_SIZE) status=none

$(MOD_BANK):
	@mkdir -p $(BANKDIR)
	ANP2_ROOT=$(ANP2_ROOT) ANP2_OUTDIR=$(ANP2_OUTDIR) $(PYTHON) decompress_game.py

sid: $(foreach o,$(SID_OUT),$(o))

$(OUTDIR)/music_ingame_ch%.s: $(PT2GT) $(MOD_INGAME)
	$(PT2GT) $(MOD_INGAME) $@ -ch $* -level -load 0

asset: $(LEVEL_ASSET)

$(LEVEL_ASSET): $(SID_OUT) mksong.py
	@mkdir -p $(ASSETDIR)
	$(PYTHON) mksong.py --out $@ --prefix music_level \
	    --source "$(PT3_SOURCE)" --speed $(PT3_SPEED) $(SID_OUT)

clean:
	rm -rf $(BANKDIR)
	rm -f $(PT2GT)