# ANP2 (Aliens: Neoplasma 2) - C64 Port
# Using ca65/ld65 from cc65 toolchain

CA65 := ca65
LD65 := ld65
CFLAGS := -t c64 -g -I src
LDFLAGS := -C anp2.cfg

SRCDIR := src
BLDDIR := build
ASMDIR := assets

SOURCES := $(wildcard $(SRCDIR)/anp2.s) $(wildcard $(ASMDIR)/*.s)
OBJECTS := $(patsubst %.s, $(BLDDIR)/%.o, $(notdir $(SOURCES)))

TARGET := anp2.prg

.PHONY: all clean run

all: $(TARGET)

$(BLDDIR)/%.o: $(SRCDIR)/%.s
	$(CA65) $(CFLAGS) -o $@ $<

$(BLDDIR)/%.o: $(ASMDIR)/%.s
	$(CA65) $(CFLAGS) -o $@ $<

$(TARGET): $(OBJECTS) anp2.cfg
	$(LD65) $(LDFLAGS) -o $@ $(OBJECTS)

clean:
	rm -f $(BLDDIR)/*.o $(TARGET)

run: $(TARGET)
	x64 $(TARGET) 2>/dev/null || xscpu64 $(TARGET) 2>/dev/null || echo "No C64 emulator found (x64/xscpu64 from VICE)"
