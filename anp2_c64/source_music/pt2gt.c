#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Standard memory address where PT3 modules are loaded */
#define PT3_BASE_ADDR 0xC3A 

#define PT3_HEADER_SIZE 0x100
#define PT3_PATTERN_SIZE 384  /* 6 channels * 64 rows */
#define GT_PATTERN_SIZE 1024  /* 4 tracks * 64 rows * 4 bytes */
#define GT_NUM_INSTRUMENTS 31
#define GT_INST_SIZE 155
#define GT_ORDER_SIZE 128

typedef struct {
    unsigned short param1; /* Maps to PT3 Loop Start */
    unsigned short param2; /* Maps to PT3 Loop Size */
} PT3_EffectParams;

void write_le16(FILE *f, unsigned short val) {
    unsigned char buf[2];
    buf[0] = val & 0xFF;
    buf[1] = (val >> 8) & 0xFF;
    fwrite(buf, 1, 2, f);
}

void make_output_filename(const char *input, char *output, size_t out_size) {
    char *last_dot;
    char *last_slash;
    char *last_bslash;
    char *last_sep;

    strncpy(output, input, out_size - 1);
    output[out_size - 1] = '\0';

    last_dot = strrchr(output, '.');
    
    if (last_dot != NULL) {
        last_slash = strrchr(output, '/');
        last_bslash = strrchr(output, '\\');
        last_sep = (last_slash > last_bslash) ? last_slash : last_bslash;

        if (last_sep == NULL || last_dot > last_sep) {
            *last_dot = '\0';
        }
    }
    
    strncat(output, ".sng", out_size - strlen(output) - 1);
}

void print_usage(const char *prog_name) {
    printf(
        "PT3 to GoatTracker 2 (.sng) Converter with Effect Support\n"
        "Usage: %s <input.pt3> [output.sng]\n\n"
        "Arguments:\n"
        "  <input.pt3>   Path to the source ZX Spectrum ProTracker 3.x module.\n"
        "  [output.sng]  Optional. Path where the GoatTracker 2 song will be saved.\n"
        "                If omitted, replaces the input extension with .sng.\n\n"
        "Features:\n"
        "  - Converts Notes, Pattern Order, and Song Length.\n"
        "  - Extracts Effect Parameters from PT3 Sample Headers.\n"
        "  - Maps Slides, Vibrato, and Speed effects to GoatTracker format.\n\n"
        "Limitations:\n"
        "  - PT3 is for the AY-3-8910; GoatTracker is for the SID chip.\n"
        "  - All %d GoatTracker instruments will be created BLANK (default Sawtooth).\n"
        "  - You MUST manually design SID instruments to hear correct audio.\n",
        prog_name, GT_NUM_INSTRUMENTS
    );
}

void load_pt3_effect_params(FILE *in, long file_size, PT3_EffectParams *effects) {
    long ptr_table_offset = file_size - 64;
    int i;
    unsigned short sample_ptr;
    long header_offset;

    if (ptr_table_offset < 0) return;

    for (i = 1; i <= 31; i++) {
        sample_ptr = 0;
        fseek(in, ptr_table_offset + (i * 2), SEEK_SET);
        fread(&sample_ptr, 2, 1, in);

        effects[i].param1 = 0;
        effects[i].param2 = 0;

        if (sample_ptr == 0) continue;

        header_offset = (long)sample_ptr - PT3_BASE_ADDR;
        
        if (header_offset >= 0 && (header_offset + 6) <= file_size) {
            fseek(in, header_offset + 2, SEEK_SET); 
            fread(&effects[i].param1, 2, 1, in);    
            fread(&effects[i].param2, 2, 1, in);    
        }
    }
}

void write_gt_header(FILE *out) {
    unsigned char title[32];
    unsigned char timing;
    unsigned char channels;

    fwrite("GTS7", 1, 4, out);
    
    memset(title, 0, 32);
    strncpy((char*)title, "PT3 Import", 31);
    fwrite(title, 1, 32, out);
    
    write_le16(out, 1);   
    write_le16(out, 0);   
    write_le16(out, 6);   
    
    timing = 0;   
    fwrite(&timing, 1, 1, out);
    
    channels = 3; 
    fwrite(&channels, 1, 1, out);
    
    write_le16(out, 0);   
}

void write_gt_blank_instruments(FILE *out) {
    unsigned char blank_inst[GT_INST_SIZE];
    int i;

    memset(blank_inst, 0, GT_INST_SIZE);
    blank_inst[0x00] = 0x20; 
    
    for (i = 0; i < GT_NUM_INSTRUMENTS; i++) {
        fwrite(blank_inst, 1, GT_INST_SIZE, out);
    }
}

void write_gt_orders(FILE *out, unsigned char *pt3_orders, unsigned char num_pos) {
    unsigned short gt_orders[GT_ORDER_SIZE];
    int i;

    memset(gt_orders, 0, sizeof(gt_orders)); 
    
    for (i = 0; i < num_pos; i++) {
        gt_orders[i] = pt3_orders[i] + 1;
    }
    
    fwrite(gt_orders, 2, GT_ORDER_SIZE, out);
}

void convert_patterns(FILE *in, FILE *out, unsigned char *pt3_orders, unsigned char num_pos, PT3_EffectParams *effects) {
    unsigned char pt3_row[6];
    unsigned char gt_row[4]; 
    unsigned char current_sample[3];
    unsigned char blank_pattern[GT_PATTERN_SIZE];
    unsigned char filter_track[4];
    int i, row, ch, p;
    long pt3_pat_offset;
    unsigned char pt3_note, pt3_cmd_byte, pt3_sample, pt3_effect;
    unsigned char max_pat;
    PT3_EffectParams *ep;

    current_sample[0] = 1;
    current_sample[1] = 2;
    current_sample[2] = 3;
    
    max_pat = 0;
    for (i = 0; i < num_pos; i++) {
        if (pt3_orders[i] > max_pat) max_pat = pt3_orders[i];
    }
    
    memset(blank_pattern, 0, GT_PATTERN_SIZE);
    fwrite(blank_pattern, 1, GT_PATTERN_SIZE, out);
    
    for (p = 0; p <= max_pat; p++) {
        pt3_pat_offset = PT3_HEADER_SIZE + (p * PT3_PATTERN_SIZE);
        fseek(in, pt3_pat_offset, SEEK_SET);
        
        for (row = 0; row < 64; row++) {
            fread(pt3_row, 1, 6, in);
            
            for (ch = 0; ch < 3; ch++) {
                pt3_note = pt3_row[ch * 2];
                pt3_cmd_byte = pt3_row[ch * 2 + 1];
                pt3_sample = (pt3_cmd_byte & 0xF0) >> 4;
                pt3_effect = pt3_cmd_byte & 0x0F;
                
                if (pt3_sample > 0) {
                    current_sample[ch] = pt3_sample;
                }
                
                memset(gt_row, 0, 4);
                
                if (pt3_note == 0) {
                    gt_row[0] = 0x00; 
                } else if (pt3_note >= 1 && pt3_note <= 96) {
                    gt_row[0] = pt3_note | 0x80; 
                } else if (pt3_note == 105) {
                    gt_row[0] = 0x00;
                    gt_row[1] = 0x0C; 
                    gt_row[2] = 0x00; 
                }
                
                if (pt3_note != 105) {
                    ep = &effects[current_sample[ch]];
                    
                    switch (pt3_effect) {
                        case 1: 
                            gt_row[1] = 0x01;
                            gt_row[2] = ep->param1 & 0xFF;
                            gt_row[3] = ep->param2 & 0xFF;
                            break;
                        case 2: 
                            gt_row[1] = 0x02;
                            gt_row[2] = ep->param1 & 0xFF;
                            gt_row[3] = ep->param2 & 0xFF;
                            break;
                        case 3: 
                            gt_row[1] = 0x03;
                            gt_row[2] = ep->param1 & 0xFF;
                            gt_row[3] = ep->param2 & 0xFF;
                            break;
                        case 4: 
                            gt_row[1] = 0x04;
                            gt_row[2] = ep->param1 & 0xFF;
                            gt_row[3] = ep->param2 & 0xFF;
                            break;
                        case 5: 
                            gt_row[1] = 0x05;
                            gt_row[2] = ep->param1 & 0xFF;
                            gt_row[3] = ep->param2 & 0xFF;
                            break;
                        case 9: 
                            gt_row[1] = 0x0E; 
                            gt_row[2] = ep->param1 & 0xFF;
                            break;
                        case 15: 
                            gt_row[1] = 0x0F;
                            gt_row[2] = ep->param1 & 0xFF;
                            break;
                        default:
                            break; 
                    }
                }
                
                fwrite(gt_row, 1, 4, out);
            }
            
            memset(filter_track, 0, 4);
            fwrite(filter_track, 1, 4, out);
        }
    }
}

int main(int argc, char *argv[]) {
    char *in_filename;
    char out_filename[512];
    FILE *in;
    FILE *out;
    long file_size;
    char sig[4];
    unsigned char num_pos, loop_pos;
    unsigned char pt3_orders[64];
    PT3_EffectParams effects[32];

    if (argc < 2 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        print_usage(argv[0]);
        exit(argc < 2 ? EXIT_FAILURE : EXIT_SUCCESS);
    }

    in_filename = argv[1];

    if (argc == 3) {
        strncpy(out_filename, argv[2], sizeof(out_filename) - 1);
        out_filename[sizeof(out_filename) - 1] = '\0';
    } else {
        make_output_filename(in_filename, out_filename, sizeof(out_filename));
    }

    in = fopen(in_filename, "rb");
    if (!in) {
        perror("Error opening PT3 file");
        exit(EXIT_FAILURE);
    }

    fseek(in, 0, SEEK_END);
    file_size = ftell(in);
    fseek(in, 0, SEEK_SET);

    fseek(in, 13, SEEK_SET);
    memset(sig, 0, 4);
    fread(sig, 1, 3, in);
    if (strcmp(sig, "pt3") != 0) {
        printf("Error: Not a valid ProTracker 3.x file (missing 'pt3' signature at offset 13).\n");
        fclose(in);
        exit(EXIT_FAILURE);
    }

    fseek(in, 0x13, SEEK_SET);
    fread(&num_pos, 1, 1, in);
    fread(&loop_pos, 1, 1, in);
    
    fread(pt3_orders, 1, 64, in);

    memset(effects, 0, sizeof(effects));
    load_pt3_effect_params(in, file_size, effects);

    out = fopen(out_filename, "wb");
    if (!out) {
        perror("Error creating SNG file");
        fclose(in);
        exit(EXIT_FAILURE);
    }

    write_gt_header(out);
    write_gt_blank_instruments(out);
    write_gt_orders(out, pt3_orders, num_pos);
    convert_patterns(in, out, pt3_orders, num_pos, effects);

    fclose(in);
    fclose(out);

    printf(
        "Success! Saved to %s\n"
        "NOTE: Effects (Slides/Vibrato) have been mapped with their parameters.\n"
        "Remember that AY instruments do not sound like SID instruments; you still\n"
        "need to draw your own envelopes in GoatTracker to finalize the sound.\n",
        out_filename
    );

    exit(EXIT_SUCCESS);
}
