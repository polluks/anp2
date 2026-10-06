"""Convert ZX Spectrum screen to C64 bitmap mode format.

C64 bitmap mode (BMM) address generation:
  For pixel at (X, Y):
    char_row = Y >> 3       (0-24)
    char_col = X >> 3       (0-39)
    col_group = char_col >> 3  (0-4)
    col_in_group = char_col & 7 (0-7)
    scanline = Y & 7        (0-7)
    screen_byte = char_row * 5 + col_group
    byte_addr = $2000 + screen_byte * 64 + scanline * 8 + col_in_group
    bit_pos = 7 - (X & 7)

  Screen RAM: stores screen_byte for each of 40x25 cells
  Color RAM: stores foreground color (4-bit) for each cell
  Background color = $D021
"""

import sys

# Spectrum color to C64 color mapping
# Spectrum: 0=black, 1=blue, 2=red, 3=magenta, 4=green, 5=cyan, 6=yellow, 7=white
# C64:      0=black, 1=white, 2=red, 3=cyan, 4=purple, 5=green, 6=blue, 7=yellow
#          8=orange, 9=brown, 10=pink, 11=dark grey, 12=grey, 13=light green,
#          14=light blue, 15=light grey
SPECTRUM_TO_C64 = {
    0: 0,  # black -> black
    1: 6,  # blue -> blue
    2: 2,  # red -> red
    3: 4,  # magenta -> purple
    4: 5,  # green -> green
    5: 3,  # cyan -> cyan
    6: 7,  # yellow -> yellow
    7: 1,  # white -> white
}

def spectrum_pixel(data, x, y):
    """Get pixel value (0/1) from Spectrum screen at (x,y)."""
    addr = (y & 7) * 32 + (y >> 3) * 256 + (x >> 3)
    byte = data[addr] if addr < len(data) else 0
    bit = 7 - (x & 7)
    return (byte >> bit) & 1

def spectrum_attr(data, x, y):
    """Get attribute byte at Spectrum position (x,y)."""
    attr_addr = 6144 + ((y >> 3) * 32 + (x >> 3))
    return data[attr_addr] if attr_addr < len(data) else 0

def convert_screen(spec_data, x_offset=32, y_offset=4):
    """Convert Spectrum screen data to C64 bitmap format.
    
    Args:
        spec_data: 6912-byte Spectrum screen (6144 bitmap + 768 attr)
        x_offset: horizontal offset in pixels (default 32 = center)
        y_offset: vertical offset in pixels (default 4)
    
    Returns:
        (bitmap_8000, screen_1000, color_1000, bg_color)
    """
    # Initialize outputs
    bitmap = bytearray(8000)
    screen = bytearray(1000)
    color = bytearray(1000)
    
    # Spectrum screen dimensions
    spec_w = 256
    spec_h = 192
    
    # For each C64 pixel
    for cy in range(200):
        for cx in range(320):
            char_row = cy >> 3
            char_col = cx >> 3
            col_group = char_col >> 3
            col_in_group = char_col & 7
            scanline = cy & 7
            
            sb_index = char_row * 5 + col_group
            
            # Bitmap address
            bm_addr = sb_index * 64 + scanline * 8 + col_in_group
            
            if bm_addr >= 8000:
                continue
            
            # Pixel value
            sx = cx - x_offset
            sy = cy - y_offset
            
            if 0 <= sx < spec_w and 0 <= sy < spec_h:
                pixel = spectrum_pixel(spec_data, sx, sy)
            else:
                pixel = 0  # border
            
            # Set bit in bitmap (bit 7 = leftmost pixel of this byte)
            bit_pos = 7 - (cx & 7)
            if pixel:
                bitmap[bm_addr] |= (1 << bit_pos)
            else:
                bitmap[bm_addr] &= ~(1 << bit_pos)
    
    # Build screen and color RAM
    for char_row in range(25):
        for char_col in range(40):
            cell_idx = char_row * 40 + char_col
            col_group = char_col >> 3
            sb_index = char_row * 5 + col_group
            screen[cell_idx] = sb_index
            
            # Color from Spectrum
            sx = char_col * 8 - x_offset
            sy = char_row * 8 - y_offset
            
            if 0 <= sx < spec_w and 0 <= sy < spec_h:
                attr = spectrum_attr(spec_data, sx, sy)
                ink = attr & 0x07
                color[cell_idx] = SPECTRUM_TO_C64.get(ink, 0)
            else:
                color[cell_idx] = 0  # black border
    
    return bitmap, screen, color

def save_koala(bitmap, screen, color, bg_color, filepath):
    """Save as Koala Painter format (.koa).
    
    Format:
        $0000-$1F3F: Bitmap (8000 bytes)
        $1F40-$2327: Screen RAM (1000 bytes)
        $2328-$271F: Color RAM (1000 bytes)
        $2720: Background color (1 byte)
    """
    data = bytearray(10001)
    data[0:8000] = bitmap
    data[8000:9000] = screen
    data[9000:10000] = color
    data[10000] = bg_color
    
    with open(filepath, 'wb') as f:
        f.write(data)
    print(f"Saved Koala file: {filepath} ({len(data)} bytes)")
    
    # Also save raw splits
    base = filepath.rsplit('.', 1)[0]
    with open(f'{base}_bitmap.bin', 'wb') as f:
        f.write(bitmap)
    with open(f'{base}_screen.bin', 'wb') as f:
        f.write(screen)
    with open(f'{base}_color.bin', 'wb') as f:
        f.write(color)
    print(f"  Bitmap: {base}_bitmap.bin ({len(bitmap)} bytes)")
    print(f"  Screen: {base}_screen.bin ({len(screen)} bytes)")
    print(f"  Color:  {base}_color.bin ({len(color)} bytes)")

if __name__ == '__main__':
    # Load Spectrum screen data
    for screen_file, label, xoff, yoff in [
        ('/tmp/screen1_v2.bin', 'loading', 32, 4),
        ('/tmp/screen2.bin', 'title', 32, 4),
        ('/tmp/screen1_v2.bin', 'loading_nopad', 0, 0),
        ('/tmp/screen2.bin', 'title_nopad', 0, 0),
    ]:
        try:
            with open(screen_file, 'rb') as f:
                data = f.read()
            print(f"\nConverting {label} screen ({len(data)} bytes)...")
            bitmap, screen_ram, color_ram = convert_screen(data, xoff, yoff)
            
            # Show stats
            unique_sb = len(set(screen_ram))
            unique_colors = len(set(color_ram))
            used_bitmap = sum(1 for b in bitmap if b != 0)
            print(f"  Unique screen byte values: {unique_sb}")
            print(f"  Unique colors: {unique_colors}")
            print(f"  Non-zero bitmap bytes: {used_bitmap}/{len(bitmap)}")
            
            save_koala(bitmap, screen_ram, color_ram, 0x00,
                      f'/tmp/c64_{label}.koa')
        except FileNotFoundError:
            print(f"File not found: {screen_file}, skipping...")
