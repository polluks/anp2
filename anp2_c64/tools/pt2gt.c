/*
 * pt2gt.c - ProTracker 3.7 module to C64 SID music converter
 *
 * Reads a binary PT3 module and outputs 6502 assembly source
 * compatible with the sound.s player format:
 *   .byte delta_time, note_index, waveform, duty_lo, duty_hi, AD, SR
 *   ...
 *   .byte 0
 *
 * Build: gcc -o pt2gt pt2gt.c
 * Usage: ./pt2gt <input.pt3> [output.s] [options]
 *
 * Options:
 *   -load N     Module load address (default: 0x8000)
 *   -pat N      Pattern table offset (override header value)
 *   -title      Output as title music (default)
 *   -level      Output as level music
 *   -ch N       Which AY channel to convert (0-2, default: 0)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

#define PT3_HEADER_SIZE 0xC9
#define MAX_FILE_SIZE   65536
#define MAX_PATTERNS    64
#define MAX_POS         128
#define MAX_ROWS        64
#define MAX_NOTES       4096
#define SID_NOTE_TABLE_SIZE  72  /* C-2 to C-7, 5 octaves */

/* SID note frequency tables (lo/hi bytes) */
static const uint8_t sid_note_lo[] = {
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C2-B2 */
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C3-B3 */
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C4-B4 */
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C5-B5 */
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C6-B6 */
    0x10,0x4D,0x8D,0xCF,0x14,0x5C,0xA7,0xF5,0x47,0x9C,0xF5,0x51, /* C7-B7 */
};

static const uint8_t sid_note_hi[] = {
    0x02,0x02,0x02,0x02,0x04,0x04,0x04,0x04,0x06,0x06,0x06,0x08, /* C2-B2 */
    0x04,0x04,0x04,0x04,0x08,0x08,0x08,0x08,0x0C,0x0C,0x0C,0x10, /* C3-B3 */
    0x08,0x08,0x08,0x08,0x10,0x10,0x10,0x10,0x18,0x18,0x18,0x20, /* C4-B4 */
    0x10,0x10,0x10,0x10,0x20,0x20,0x20,0x20,0x30,0x30,0x30,0x40, /* C5-B5 */
    0x20,0x20,0x20,0x20,0x40,0x40,0x40,0x40,0x60,0x60,0x60,0x80, /* C6-B6 */
    0x40,0x40,0x40,0x40,0x80,0x80,0x80,0x80,0xC0,0xC0,0xC0,0x00, /* C7-B7 */
};

/* AY note names (C-1 to B-8 = 96 notes) */
static const char *note_names[] = {
    "C-1","C#1","D-1","D#1","E-1","F-1","F#1","G-1","G#1","A-1","A#1","B-1",
    "C-2","C#2","D-2","D#2","E-2","F-2","F#2","G-2","G#2","A-2","A#2","B-2",
    "C-3","C#3","D-3","D#3","E-3","F-3","F#3","G-3","G#3","A-3","A#3","B-3",
    "C-4","C#4","D-4","D#4","E-4","F-4","F#4","G-4","G#4","A-4","A#4","B-4",
    "C-5","C#5","D-5","D#5","E-5","F-5","F#5","G-5","G#5","A-5","A#5","B-5",
    "C-6","C#6","D-6","D#6","E-6","F-6","F#6","G-6","G#6","A-6","A#6","B-6",
    "C-7","C#7","D-7","D#7","E-7","F-7","F#7","G-7","G#7","A-7","A#7","B-7",
    "C-8","C#8","D-8","D#8","E-8","F-8","F#8","G-8","G#8","A-8","A#8","B-8",
};

/* PT3 position list entry */
typedef struct {
    uint8_t pattern;   /* pattern number */
    uint8_t trans;     /* transposition (if 3-byte format) */
    uint8_t loop;      /* loop flag (if 3-byte format) */
} pos_entry_t;

/* PT3 header */
typedef struct {
    uint8_t magic[13];
    uint8_t version;
    uint8_t compof[16];
    uint8_t name[32];
    uint8_t by[4];
    uint8_t author[32];
    uint8_t space;
} pt3_text_t;

/* Convert Spectrum character to ASCII */
static char spec_to_ascii(uint8_t c) {
    if (c >= 0x20 && c <= 0x7E)
        return (char)c;
    if (c >= 0x80 && c <= 0xFE) {
        uint8_t low = c & 0x7F;
        if (low >= 0x20 && low <= 0x7E)
            return (char)low;
    }
    return '.';
}

/* Print PT3 header text */
static void print_header_text(const uint8_t *data, int offset) {
    char buf[128];
    int i, j = 0;
    for (i = 0; i < 99 && j < 120; i++) {
        buf[j++] = spec_to_ascii(data[offset + i]);
    }
    buf[j] = '\0';
    /* Trim trailing spaces */
    for (j--; j >= 0 && buf[j] == ' '; j--)
        buf[j] = '\0';
    fprintf(stderr, "; %s\n", buf);
}

/* Map AY note (0-95, C-1 to B-8) to SID note index */
/* SID note table: C2=0, C#2=1, ... B7=71 (72 notes, 6 octaves) */
/* AY C-1 = index 0, SID C2 = index 0 */
/* AY C-1 -> SID C-1 (12 below C2) = out of range */
/* Map: AY note 12..83 -> SID note 0..71 (C2..C7) */
static int ay_to_sid_note(int ay_note) {
    int sid_note = ay_note - 12;  /* Shift up by 1 octave */
    if (sid_note < 0) sid_note = 0;
    if (sid_note >= SID_NOTE_TABLE_SIZE) sid_note = SID_NOTE_TABLE_SIZE - 1;
    return sid_note;
}

/* Lookup: pattern data stream -> note events */
typedef struct {
    int row;         /* row number 0-63 */
    int note;        /* AY note index 0-95, -1 = no note */
    int sample;      /* sample number 0-31, -1 = none */
    int ornament;    /* ornament number 0-15, -1 = none */
    int volume;      /* volume 0-15, -1 = not set */
    int noise;       /* noise frequency, -1 = not set */
    int envelope;    /* envelope type, -1 = not set */
    int effect;      /* effect number 0-15, -1 = none */
    int effect_param[4]; /* effect parameter bytes */
} note_event_t;

/*
 * Parse a channel's pattern data stream
 * Returns number of rows parsed, or -1 on error
 * Stores note events in 'events' array (up to MAX_ROWS)
 *
 * Uses the uncompressed format from deater.net:
 *   0x00: end of pattern
 *   0x01-0x0f: effects (params follow after note byte)
 *   0x10-0x1f: envelope (0x10=disable, 0x11-0x1f loop+type)
 *   0x20-0x3f: set noise
 *   0x40-0x4f: set ornament
 *   0x50-0xaf: play note (note = byte - 0x50)
 *   0xb0: disable env, reset ornament
 *   0xb1: set skip (next byte = skip count)
 *   0xb2-0xbf: set envelope type
 *   0xc0: turn off note
 *   0xc1-0xcf: set volume (vol = byte - 0xc0)
 *   0xd0: end note (rest)
 *   0xd1-0xef: set sample (sample = byte - 0xd0)
 *   0xf0-0xff: init ornament (low nibble), next byte = sample*2
 */
static int parse_channel_data(const uint8_t *data, int size, int offset,
                               note_event_t *events, int max_events,
                               int *end_off)
{
    int pos = offset;
    int row = 0;
    int current_sample = -1;
    int current_ornament = -1;
    int current_volume = -1;
    int current_noise = -1;
    int current_envelope = -1;
    int effects_pending[16]; /* which effects are pending */
    int num_pending = 0;
    int has_note_or_rest = 0;
    
    memset(effects_pending, 0, sizeof(effects_pending));
    
    if (pos >= size) {
        if (end_off) *end_off = pos;
        return 0;
    }
    
    while (pos < size && row < max_events) {
        uint8_t b = data[pos++];
        
        if (b == 0x00) {
            /* End of pattern */
            break;
        }
        
        if (b >= 0x01 && b <= 0x0f) {
            /* Effect: store for later (params after note) */
            if (num_pending < 16) {
                effects_pending[num_pending++] = b;
            }
            continue;
        }
        
        if (b >= 0x10 && b <= 0x1f) {
            /* Envelope */
            if (b == 0x10) {
                current_envelope = -1; /* disable envelope */
                /* Next byte is sample number */
                if (pos < size) {
                    current_sample = data[pos++];
                }
            } else {
                current_envelope = b - 0x10; /* loop envelope type */
                /* Skip envelope period (2 bytes BE) and delay (1 byte) */
                if (pos + 3 < size) {
                    pos += 3; /* period_hi, period_lo, delay */
                }
                /* Next byte is sample number */
                if (pos < size) {
                    current_sample = data[pos++];
                }
            }
            continue;
        }
        
        if (b >= 0x20 && b <= 0x3f) {
            /* Set noise */
            current_noise = b - 0x20;
            continue;
        }
        
        if (b >= 0x40 && b <= 0x4f) {
            /* Set ornament */
            current_ornament = b - 0x40;
            continue;
        }
        
        if (b >= 0x50 && b <= 0xaf) {
            /* PLAY NOTE! Store the event for this row */
            int note_idx = b - 0x50;
            events[row].row = row;
            events[row].note = note_idx;
            events[row].sample = current_sample;
            events[row].ornament = current_ornament;
            events[row].volume = current_volume;
            events[row].noise = current_noise;
            events[row].envelope = current_envelope;
            events[row].effect = -1;
            memset(events[row].effect_param, 0, sizeof(events[row].effect_param));
            
            /* Read effect parameters that follow the note */
            for (int e = 0; e < num_pending && pos < size; e++) {
                events[row].effect = effects_pending[e];
                /* Read param bytes based on effect type */
                switch (effects_pending[e]) {
                    case 1: /* Glissando - delay, freq_lo, freq_hi */
                        if (pos + 3 <= size) {
                            events[row].effect_param[0] = data[pos++]; /* delay */
                            events[row].effect_param[1] = data[pos++]; /* freq_lo */
                            events[row].effect_param[2] = data[pos++]; /* freq_hi */
                        }
                        break;
                    case 2: /* Tone portamento - delay, ignore, step_lo, step_hi */
                        if (pos + 5 <= size) {
                            events[row].effect_param[0] = data[pos++]; /* delay */
                            pos += 2; /* ignored bytes */
                            events[row].effect_param[1] = data[pos++]; /* step_lo */
                            events[row].effect_param[2] = data[pos++]; /* step_hi */
                        }
                        break;
                    case 3: /* Sample offset */
                    case 4: /* Ornament offset */
                        if (pos < size)
                            events[row].effect_param[0] = data[pos++];
                        break;
                    case 5: /* Vibrato - off_on, on_off */
                        if (pos + 2 <= size) {
                            events[row].effect_param[0] = data[pos++];
                            events[row].effect_param[1] = data[pos++];
                        }
                        break;
                    case 8: /* Env gliss down - delay, add_lo, add_hi */
                    case 9: /* Env gliss up - delay, add_lo, add_hi */
                        if (pos + 3 <= size) {
                            events[row].effect_param[0] = data[pos++];
                            events[row].effect_param[1] = data[pos++];
                            events[row].effect_param[2] = data[pos++];
                        }
                        break;
                    case 0x0b: /* Set speed */
                        if (pos < size)
                            events[row].effect_param[0] = data[pos++];
                        break;
                    default:
                        break;
                }
            }
            
            row++;
            num_pending = 0;
            current_volume = -1;
            current_noise = -1;
            continue;
        }
        
        if (b == 0xb0) {
            /* Disable envelope, reset ornament */
            current_envelope = -1;
            continue;
        }
        
        if (b == 0xb1) {
            /* Set skip value */
            if (pos < size) pos++; /* skip count byte */
            continue;
        }
        
        if (b >= 0xb2 && b <= 0xbf) {
            /* Set envelope type */
            current_envelope = b - 0xb2 + 1;
            /* Envelope period: next 2 bytes big-endian */
            if (pos + 2 <= size) {
                pos += 2;
            }
            continue;
        }
        
        if (b == 0xc0) {
            /* Turn off note (mute) */
            events[row].row = row;
            events[row].note = -2; /* mute */
            events[row].sample = current_sample;
            events[row].volume = 0;
            events[row].effect = -1;
            row++;
            num_pending = 0;
            continue;
        }
        
        if (b >= 0xc1 && b <= 0xcf) {
            /* Set volume */
            current_volume = b - 0xc0;
            continue;
        }
        
        if (b == 0xd0) {
            /* End note (rest) */
            events[row].row = row;
            events[row].note = -1; /* rest */
            events[row].sample = current_sample;
            events[row].volume = current_volume;
            events[row].effect = -1;
            row++;
            num_pending = 0;
            continue;
        }
        
        if (b >= 0xd1 && b <= 0xef) {
            /* Set sample */
            current_sample = b - 0xd0;
            continue;
        }
        
        if (b >= 0xf0 && b <= 0xff) {
            /* Initialize ornament + sample */
            current_ornament = b & 0x0f;
            if (pos < size) {
                current_sample = data[pos++] / 2;
            }
            current_envelope = -1; /* Disable envelope */
            continue;
        }
        
        /* Unknown byte - skip */
        fprintf(stderr, "; WARNING: unknown byte %02x at offset %d\n", b, pos-1);
    }

    /* A PT3 pattern is always 64 rows, but a channel stream ends at the 0x00
       terminator as soon as it runs out of commands. Rows the stream does not
       cover are empty for that channel, so pad them with silence. Without this
       each channel emits a different number of rows for the same order entry
       (the ingame module ranged from 0 to 64) and the three SID voices drift
       out of step with each other. */
    while (row < max_events) {
        note_event_t *ev = &events[row];
        memset(ev, 0, sizeof(*ev));
        ev->row = row;
        ev->note = -1;    /* rest -> gate off */
        ev->sample = -1;  /* no sample, so print_sid_event keeps the gate off */
        ev->ornament = -1;
        ev->volume = 0;
        ev->noise = -1;
        ev->envelope = -1;
        ev->effect = -1;
        row++;
    }

    if (end_off) *end_off = pos;
    return row;
}

/* Derive the number of pattern table entries.
   Header offset $65 is the song length (order positions), not the pattern
   count, so it cannot be used here. The pattern pointer table is a flat list
   of 16-bit offsets that ends exactly where the first pattern's data begins,
   so the entry count is (first_pointer - table_offset) / 2. */
static int count_pattern_entries(const uint8_t *data, int size, int pat_off)
{
    if (pat_off < 0 || pat_off + 2 > size) return 0;

    /* The table holds one 16-bit offset per pattern and is followed
       immediately by pattern data, so the lowest offset it contains is the
       address of the first pattern stored: pat_off + 2*numpat.
       Entry 0 is NOT that pattern -- a module may order its table so the
       first pattern lives anywhere. Offsets may also repeat or step
       backwards when patterns are shared or reordered, so scan for the
       candidate n whose minimum entry matches the implied data start. */
    for (int cand = 1; cand <= MAX_PATTERNS; cand++) {
        if (pat_off + cand * 2 > size) break;

        int lo = 0xFFFF;
        for (int p = 0; p < cand; p++) {
            int addr = data[pat_off + p * 2] | (data[pat_off + p * 2 + 1] << 8);
            if (addr < lo) lo = addr;
        }

        if (lo == pat_off + 2 * cand)
            return cand;
    }

    return 0;
}

/* Find pattern table in module data */
/* Returns file offset of pattern table, or -1 if not found */
static int find_pattern_table(const uint8_t *data, int size, int mod_start,
                               int load_addr, int override_pat)
{
    if (override_pat >= 0) {
        return override_pat;
    }
    
    /* Try PatsPtrs from header as absolute memory address */
    int pat_ptr = data[mod_start + 0x67] | (data[mod_start + 0x68] << 8);
    
    /* Try different interpretations and pick the one with all entries valid */
    int best_offset = -1;
    int best_valid = -1;
    
    int tries[][2] = {
        {0x0000, 0},  /* direct file offset */
        {0x4000, 0},
        {0x5B00, 0},
        {0x8000, 0},
        {0xC000, 0},
    };
    int num_tries = sizeof(tries) / sizeof(tries[0]);
    
    for (int t = 0; t < num_tries; t++) {
        int base = tries[t][0];
        int pat_off = pat_ptr - base;
        
        if (pat_off < 0 || pat_off + 2 > size)
            continue;
        
        int n = count_pattern_entries(data, size, pat_off);
        if (n < 1)
            continue;
        
        /* One 16-bit pointer per pattern. Offsets may repeat or step
           backwards when patterns are shared or reordered, so require only
           that every entry lands past the table and inside the module. */
        int first_data = pat_off + n * 2;
        int valid = 0;
        for (int p = 0; p < n; p++) {
            int addr = data[pat_off + p*2] | (data[pat_off + p*2 + 1] << 8);
            int file_off = addr - base;
            if (file_off >= first_data && file_off < size)
                valid++;
        }
        
        if (valid == n && n > best_valid) {
            best_valid = n;
            best_offset = pat_off;
        }
    }
    
    return best_offset;
}

/* Read the pattern order list.
   The list sits in front of the pattern pointer table and ends at the 0xFF
   terminator directly below it; its length is the song length at header
   offset $65. The entries are therefore exactly the $65 bytes in
   [pat_off-1-len, pat_off-2].

   Scanning backwards while the byte merely looks like a pattern index is not
   enough: nothing stops that scan at the terminator, so whenever the bytes
   ahead of the list happen to be small it runs straight into header data.
   `Alien: intro` reads 31 positions that way instead of 2, which padded its
   row count to ~40KB of note data and overflowed MAIN. $66 holds the loop
   position, and it is below the length in every module here, which is a
   useful cross-check. Returns the count, or 0 if the header disagrees. */
static int read_order_list(const uint8_t *data, int size, int pat_off,
                           int mod_start, int num_pat, int *order, int max_pos)
{
    if (pat_off < 2 || size <= mod_start + 0x65) return 0;
    if (data[pat_off - 1] != 0xFF) return 0;

    int len = data[mod_start + 0x65];
    int start = pat_off - 1 - len;

    /* the list lives above the header, which reaches at least $69 */
    if (len < 1 || start < mod_start + 0x69 || start >= pat_off - 1) return 0;

    int n = 0;
    for (int i = start; i < pat_off - 1 && n < max_pos && n < len; i++) {
        if (num_pat > 0 && data[i] >= num_pat) {
            fprintf(stderr, "; Order entry %d = %d exceeds pattern count %d\n",
                    n, data[i], num_pat);
            return 0;
        }
        order[n++] = data[i];
    }

    return n;
}

/* Parse pattern table and extract all note events */
static int extract_all_notes(const uint8_t *data, int size, int mod_start,
                              int pat_table_off, const int *order, int num_pos,
                              int channel, int load_addr,
                              note_event_t *all_events, int *row_counts)
{
    int total_rows = 0;
    note_event_t scratch[MAX_ROWS];
    
    /* PT3 pattern pointer tables hold ONE 16-bit pointer per pattern. That
       pointer addresses channel 0's stream; the remaining channel streams are
       packed immediately after it, each terminated by a 0x00 byte. */
    for (int i = 0; i < num_pos && pat_table_off + order[i]*2 + 2 <= size; i++) {
        int p = order[i];
        int ch_addr = data[pat_table_off + p*2] | (data[pat_table_off + p*2 + 1] << 8);
        
        /* Convert to file offset */
        int ch_off = ch_addr - load_addr;
        if (ch_off < 0 || ch_off >= size) {
            /* Try as direct offset */
            ch_off = ch_addr;
            if (ch_off < 0 || ch_off >= size) {
                row_counts[p] = 0;
                continue;
            }
        }
        
        /* Step over the streams preceding the requested channel. */
        for (int skip = 0; skip < channel; skip++) {
            int dummy = 0;
            if (parse_channel_data(data, size, ch_off, scratch, MAX_ROWS,
                                    &dummy) == 0 && dummy == ch_off)
                break;
            ch_off = dummy;
        }
        
        /* Every pattern now contributes a full MAX_ROWS events, so check the
           remaining room BEFORE parsing. MAX_POS * MAX_ROWS can exceed
           MAX_NOTES, and writing a partial pattern would put the channels
           back out of step. */
        if (total_rows + MAX_ROWS > MAX_NOTES) {
            fprintf(stderr, "; WARNING: row limit reached after %d rows, "
                    "dropping order position %d\n", total_rows, i);
            break;
        }

        int base = total_rows;
        int rows = parse_channel_data(data, size, ch_off,
                                       all_events + base,
                                       MAX_ROWS, NULL);
        /* parse_channel_data numbers rows from 0 inside each pattern, but the
           order list plays patterns back to back, so make the index global
           before the output loop folds runs together. Without this a gap that
           spans a pattern boundary reads as a backwards jump. */
        for (int k = 0; k < rows; k++)
            all_events[base + k].row = base + k;
        row_counts[p] = rows;
        total_rows += rows;
    }
    
    return total_rows;
}

/* Map a note event to SID format and print it */
static void print_sid_event(FILE *out, const note_event_t *ev, int *last_note) {
    int sid_note;
    uint8_t waveform = 0x21;  /* default: pulse */
    uint8_t duty_lo = 0x80;   /* default 50% duty */
    uint8_t duty_hi = 0x08;
    uint8_t ad = 0x09;        /* attack=0, decay=9 */
    uint8_t sr = 0xA8;        /* sustain=A, release=8 */
    
    if (ev->note >= 0) {
        sid_note = ay_to_sid_note(ev->note);
        *last_note = sid_note;
    } else if (ev->note == -1) {
        /* Rest - keep previous note but volume 0 */
        sid_note = *last_note;
        waveform = 0x10; /* gate off */
    } else if (ev->note == -2) {
        /* Mute */
        sid_note = *last_note;
        waveform = 0x10;
    } else {
        return; /* should not happen */
    }
    
    /* Convert AY volume (0-15) to SID ADSR */
    if (ev->volume >= 0) {
        /* Approximate: map volume to sustain level */
        sr = (sr & 0x0F) | ((ev->volume << 4) & 0xF0);
    }
    
    /* Sample-based waveform mapping */
    if (ev->sample >= 0) {
        switch (ev->sample % 4) {
            case 0: waveform = 0x21; break; /* pulse */
            case 1: waveform = 0x41; break; /* sawtooth */
            case 2: waveform = 0x81; break; /* triangle */
            case 3: waveform = 0x11; break; /* noise */
        }
    }
    
    /* Output in sound.s format: delta_time, note, waveform, duty_lo, duty_hi, AD, SR */
    fprintf(out, "    .byte $%02x, $%02x, $%02x, $%02x, $%02x, $%02x, $%02x",
            ev->row, sid_note, waveform, duty_lo, duty_hi, ad, sr);
    
    /* Comment with original note info */
    if (ev->note >= 0 && ev->note < 96) {
        fprintf(out, "  ; %s", note_names[ev->note]);
        if (ev->sample >= 0) fprintf(out, " smp=%d", ev->sample);
        if (ev->ornament >= 0) fprintf(out, " orn=%d", ev->ornament);
        if (ev->volume >= 0) fprintf(out, " vol=%d", ev->volume);
        if (ev->noise >= 0) fprintf(out, " noise=%d", ev->noise);
    } else if (ev->note == -1) {
        fprintf(out, "  ; rest");
    } else if (ev->note == -2) {
        fprintf(out, "  ; mute");
    }
    fprintf(out, "\n");
}

/* Main conversion function */
static int convert_module(FILE *out, const uint8_t *data, int size,
                           int mod_start, int load_addr, int channel,
                           int override_pat, int is_title)
{
    int speed = data[mod_start + 0x64];
    if (speed < 1) speed = 1;   /* a 0 here would stall the player's tick counter */
    int loop = data[mod_start + 0x66];
    int num_pat = 0;
    
    /* Print header info */
    fprintf(stderr, "; Module at offset 0x%X\n", mod_start);
    fprintf(stderr, "; Speed: %d, Loop: %d\n", speed, loop);
    print_header_text(data, mod_start);
    
    /* Find pattern table */
    int pat_off = find_pattern_table(data, size, mod_start, load_addr, override_pat);
    if (pat_off < 0) {
        fprintf(stderr, "; ERROR: Could not find pattern table\n");
        return -1;
    }
    fprintf(stderr, "; Pattern table at file offset 0x%X\n", pat_off);
    
    num_pat = count_pattern_entries(data, size, pat_off);
    if (num_pat < 1) {
        fprintf(stderr, "; ERROR: Could not derive pattern count\n");
        return -1;
    }
    fprintf(stderr, "; Patterns: %d\n", num_pat);
    
    /* Playback order */
    int order[MAX_POS];
    int num_pos = read_order_list(data, size, pat_off, mod_start, num_pat,
                                  order, MAX_POS);
    if (num_pos < 1) {
        for (int i = 0; i < num_pat && i < MAX_POS; i++) order[i] = i;
        num_pos = num_pat;
        fprintf(stderr, "; No order list, playing patterns in table order\n");
    } else {
        fprintf(stderr, "; Order list: %d positions", num_pos);
        for (int i = 0; i < num_pos; i++) fprintf(stderr, " %d", order[i]);
        fprintf(stderr, "\n");
    }
    
    /* Extract notes */
    int all_events[MAX_NOTES];
    int row_counts[MAX_PATTERNS];
    int total_notes = 0;
    
    for (int ch = 0; ch < 3; ch++) {
        if (channel >= 0 && ch != channel) continue;
        
        note_event_t events[MAX_NOTES];
        int rows[MAX_PATTERNS];
        int n = extract_all_notes(data, size, mod_start, pat_off, order, num_pos,
                                   ch, load_addr, events, rows);
        
        if (n <= 0) {
            fprintf(stderr, "; Channel %d: no notes found\n", ch);
            continue;
        }
        
        fprintf(stderr, "; Channel %d: %d notes across %d positions\n", ch, n, num_pos);
        
        /* Output assembly */
        if (is_title) {
            if (ch == 0)
                fprintf(out, "\nmusic_title_ch%d:\n", ch);
            else
                fprintf(out, "\nmusic_title_ch%d:\n", ch);
        } else {
            if (ch == 0)
                fprintf(out, "\nmusic_level_ch%d:\n", ch);
            else
                fprintf(out, "\nmusic_level_ch%d:\n", ch);
        }
        
        int last_note = 24; /* default: C3 */
        int prev_row = -1;
        int have_prev = 0;
        note_event_t prev_ev;
        memset(&prev_ev, 0, sizeof prev_ev);

        for (int i = 0; i < n; i++) {
            const note_event_t *ev = &events[i];

            /* Rows that drive the SID identically can be folded into a single
               event: the delta carries the time across the gap, so the
               registers see exactly the same byte sequence either way. The
               padded runs of rests collapse here, which is most of the data. */
            if (have_prev && ev->note == prev_ev.note &&
                ev->sample == prev_ev.sample && ev->volume == prev_ev.volume)
                continue;

            /* Row gap, converted to frames. PT3 holds each row for `speed`
               ticks of 1 frame, so a module with speed 6 keeps every row for
               6 frames. Emitting the bare row gap plays the track `speed`
               times too fast. */
            int gap = (prev_row < 0) ? 1 : (ev->row - prev_row);
            if (gap < 1) gap = 1;

            /* The delta is a single byte, so a run held longer than 255
               frames has to be chopped up. Each piece repeats the previous
               SID state, which leaves the registers unchanged. */
            while (have_prev && gap * speed > 255) {
                int piece = 255 / speed;
                if (piece < 1) piece = 1;
                note_event_t fill = prev_ev;
                fill.row = piece * speed;
                print_sid_event(out, &fill, &last_note);
                gap -= piece;
            }

            note_event_t tmp = *ev;
            tmp.row = gap * speed;
            print_sid_event(out, &tmp, &last_note);

            prev_row = ev->row;
            prev_ev = *ev;
            have_prev = 1;
        }

        /* Rows folded away at the tail still have to be held, or this channel
           stops short of the other two and drifts as soon as it restarts. */
        if (have_prev && prev_row < n - 1) {
            int gap = (n - 1) - prev_row;
            while (gap * speed > 255) {
                int piece = 255 / speed;
                if (piece < 1) piece = 1;
                note_event_t fill = prev_ev;
                fill.row = piece * speed;
                print_sid_event(out, &fill, &last_note);
                prev_row += piece;
                gap -= piece;
            }
            if (gap > 0) {
                note_event_t fill = prev_ev;
                fill.row = gap * speed;
                print_sid_event(out, &fill, &last_note);
                prev_row += gap;
            }
        }
        
        fprintf(out, "    .byte $00  ; end\n");
        total_notes += n;
    }
    
    return 0;
}

int main(int argc, char *argv[]) {
    const char *infile = NULL;
    const char *outfile = NULL;
    int load_addr = 0x8000;
    int override_pat = -1;
    int channel = 0;
    int is_title = 1;
    int mod_start = 0;
    int mod2_offset = -1;
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-load") == 0 && i+1 < argc) {
            load_addr = (int)strtol(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "-pat") == 0 && i+1 < argc) {
            override_pat = (int)strtol(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "-ch") == 0 && i+1 < argc) {
            channel = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-title") == 0) {
            is_title = 1;
        } else if (strcmp(argv[i], "-level") == 0) {
            is_title = 0;
        } else if (strcmp(argv[i], "-mod2") == 0) {
            mod_start = 1; /* flag to use module 2 */
        } else if (strcmp(argv[i], "-mod2off") == 0 && i+1 < argc) {
            mod2_offset = (int)strtol(argv[++i], NULL, 0);
        } else if (infile == NULL) {
            infile = argv[i];
        } else if (outfile == NULL) {
            outfile = argv[i];
        }
    }
    
    if (infile == NULL) {
        fprintf(stderr, "Usage: %s <input.pt3> [output.s] [options]\n", argv[0]);
        fprintf(stderr, "Options:\n");
        fprintf(stderr, "  -load N     Module load address (default: 0x8000)\n");
        fprintf(stderr, "  -pat N      Pattern table offset (override)\n");
        fprintf(stderr, "  -ch N       AY channel to convert (0-2, default: 0)\n");
        fprintf(stderr, "  -title      Output as title music (default)\n");
        fprintf(stderr, "  -level      Output as level music\n");
        fprintf(stderr, "  -mod2       Use module 2 (default: module 1)\n");
        fprintf(stderr, "  -mod2off N  Module 2 offset (default: 0x098D)\n");
        return 1;
    }
    
    /* Read input file */
    FILE *f = fopen(infile, "rb");
    if (!f) {
        fprintf(stderr, "Error: cannot open %s\n", infile);
        return 1;
    }
    
    uint8_t data[MAX_FILE_SIZE];
    int size = fread(data, 1, MAX_FILE_SIZE, f);
    fclose(f);
    
    if (size <= 0) {
        fprintf(stderr, "Error: empty file\n");
        return 1;
    }
    
    fprintf(stderr, "; Read %d bytes from %s\n", size, infile);
    
    /* Determine module start */
    if (mod_start == 1) {
        /* Use module 2 */
        if (mod2_offset < 0) mod2_offset = 0x098D;
        mod_start = mod2_offset;
    }
    
    /* Open output */
    FILE *out = stdout;
    if (outfile) {
        out = fopen(outfile, "w");
        if (!out) {
            fprintf(stderr, "Error: cannot write %s\n", outfile);
            return 1;
        }
    }
    
    /* Print assembly header */
    fprintf(out, "; Converted from PT3 module\n");
    fprintf(out, "; Source: %s\n", infile);
    print_header_text(data, mod_start);
    if (mod_start > 0) {
        fprintf(out, "; Module offset: 0x%X\n", mod_start);
    }
    fprintf(out, "; Speed: %d\n", data[mod_start + 0x64]);
    fprintf(out, "; Channel: %d\n", channel);
    
    /* Convert */
    convert_module(out, data, size, mod_start, load_addr,
                   channel, override_pat, is_title);
    
    if (out != stdout) fclose(out);
    
    fprintf(stderr, "; Done.\n");
    return 0;
}
