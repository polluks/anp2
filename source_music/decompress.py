#!/usr/bin/env python3
"""Z80 emulator for the ANP2 Exomizer decompressor at $621A.

Executes the exact decompressor code from the loader on compressed data.
"""

import struct
import sys


class Z80Emu:
    """Minimal Z80 emulator for the ANP2 decompressor."""
    
    def __init__(self, data, comp_offset, output_size=6912, bank_skip=True):
        self.mem = bytearray(65536)
        
        # Load decompressor code (block 3, base $6000)
        with open('/root/ghidra/extracted_block_3.bin', 'rb') as f:
            loader = f.read()
        
        # Load entire block 3 into memory at $6000
        for i, b in enumerate(loader):
            self.mem[0x6000 + i] = b
        
        # Load compressed data into memory (after loader if needed)
        # Compressed data follows the loader in memory
        data_addr = 0x6000 + len(loader)
        for i, b in enumerate(data):
            if data_addr + i < 65536:
                self.mem[data_addr + i] = b
        
        # Registers
        self.PC = 0x621A  # decompressor entry
        self.SP = 0xFFFE
        self.A = 0        # bank number (0 for screen 1)
        self.B = 0
        self.C = 0
        self.D = 0
        self.E = 0
        self.H = 0
        self.L = 0
        self.F = 0        # flags: SZ-H-PNC, bit7=S, bit6=Z, bit4=H, bit2=P, bit1=N, bit0=C
        self.AF2 = 0      # shadow AF
        self.IX = 0
        self.IY = 0
        
        self.output = bytearray()
        self.output_addr = 0  # DE tracks output position
        
        # Emulation control
        self.max_cycles = 500000
        self.cycle_count = 0
    
    def get_flag(self, bit):
        return (self.F >> bit) & 1
    
    def set_flag(self, bit, val):
        if val:
            self.F |= (1 << bit)
        else:
            self.F &= ~(1 << bit)
    
    def read_mem(self, addr):
        return self.mem[addr & 0xFFFF]
    
    def write_mem(self, addr, val):
        self.mem[addr & 0xFFFF] = val & 0xFF
    
    def read_word(self, addr):
        return self.read_mem(addr) | (self.read_mem(addr + 1) << 8)
    
    def write_word(self, addr, val):
        self.write_mem(addr, val & 0xFF)
        self.write_mem(addr + 1, (val >> 8) & 0xFF)
    
    def get_hl(self): return (self.H << 8) | self.L
    def set_hl(self, v): self.H = (v >> 8) & 0xFF; self.L = v & 0xFF
    def get_de(self): return (self.D << 8) | self.E
    def set_de(self, v): self.D = (v >> 8) & 0xFF; self.E = v & 0xFF
    def get_bc(self): return (self.B << 8) | self.C
    def set_bc(self, v): self.B = (v >> 8) & 0xFF; self.C = v & 0xFF
    
    def step(self):
        """Execute one Z80 instruction at PC."""
        op = self.read_mem(self.PC)
        self.PC = (self.PC + 1) & 0xFFFF
        
        if op == 0x00:  # NOP
            pass
        
        elif op == 0x01:  # LD BC, imm
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.B = hi
            self.C = lo
        
        elif op == 0x03:  # INC BC
            v = (self.get_bc() + 1) & 0xFFFF
            self.set_bc(v)
        
        elif op == 0x04:  # INC B
            self.B = (self.B + 1) & 0xFF
            self.set_flag(6, self.B == 0)  # Z
            self.set_flag(4, (self.B & 0x0F) == 0)  # H
            self.set_flag(1, 0)  # N
        
        elif op == 0x05:  # DEC B
            old = self.B
            self.B = (self.B - 1) & 0xFF
            self.set_flag(6, self.B == 0)
            self.set_flag(4, (self.B & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        
        elif op == 0x06:  # LD B, imm
            self.B = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x08:  # EX AF,AF'
            tmp = (self.A << 8) | (self.F & 0xFF)
            self.A = (self.AF2 >> 8) & 0xFF
            self.F = self.AF2 & 0xFF
            self.AF2 = tmp
        
        elif op == 0x0C:  # INC C
            self.C = (self.C + 1) & 0xFF
            self.set_flag(6, self.C == 0)
            self.set_flag(4, (self.C & 0x0F) == 0)
            self.set_flag(1, 0)
        
        elif op == 0x0E:  # LD C, imm
            self.C = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x10:  # DJNZ disp
            self.B = (self.B - 1) & 0xFF
            if self.B != 0:
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1 + disp) & 0xFFFF
            else:
                self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x12:  # LD (DE),A
            self.write_mem(self.get_de(), self.A)
        
        elif op == 0x13:  # INC DE
            self.set_de((self.get_de() + 1) & 0xFFFF)
        
        elif op == 0x15:  # DEC D
            self.D = (self.D - 1) & 0xFF
            self.set_flag(6, self.D == 0)
            self.set_flag(4, (self.D & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        
        elif op == 0x16:  # LD D, imm
            self.D = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x17:  # RLA (rotate A left through carry)
            c_in = self.get_flag(0)
            c_out = (self.A & 0x80) >> 7
            self.A = ((self.A << 1) | c_in) & 0xFF
            self.set_flag(0, c_out)
        
        elif op == 0x18:  # JR disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1 + disp) & 0xFFFF
        
        elif op == 0x19:  # ADD HL,DE
            hl = self.get_hl()
            de = self.get_de()
            result = hl + de
            self.set_hl(result & 0xFFFF)
            self.set_flag(0, result > 0xFFFF)
            self.set_flag(4, (hl & 0x0FFF) + (de & 0x0FFF) > 0x0FFF)
            self.set_flag(1, 0)
        
        elif op == 0x1A:  # LD A,(DE)
            self.A = self.read_mem(self.get_de())
        
        elif op == 0x1E:  # LD E, imm
            self.E = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x20:  # JR NZ, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if not self.get_flag(6):
                self.PC = (self.PC + disp) & 0xFFFF
        
        elif op == 0x21:  # LD HL, imm
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.H = hi
            self.L = lo
        
        elif op == 0x22:  # LD (imm),HL
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.write_word((hi << 8) | lo, self.get_hl())
        
        elif op == 0x23:  # INC HL
            self.set_hl((self.get_hl() + 1) & 0xFFFF)
        
        elif op == 0x28:  # JR Z, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if self.get_flag(6):
                self.PC = (self.PC + disp) & 0xFFFF
        
        elif op == 0x2B:  # DEC HL
            self.set_hl((self.get_hl() - 1) & 0xFFFF)
        
        elif op == 0x30:  # JR NC, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if not self.get_flag(0):
                self.PC = (self.PC + disp) & 0xFFFF
        
        elif op == 0x31:  # LD SP, imm
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.SP = (hi << 8) | lo
        
        elif op == 0x32:  # LD (imm),A
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.write_mem((hi << 8) | lo, self.A)
        
        elif op == 0x37:  # SCF
            self.set_flag(0, 1)
            self.set_flag(4, 0)
            self.set_flag(1, 0)
        
        elif op == 0x38:  # JR C, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if self.get_flag(0):
                self.PC = (self.PC + disp) & 0xFFFF
        
        elif op == 0x3C:  # INC A
            self.A = (self.A + 1) & 0xFF
            self.set_flag(6, self.A == 0)
            self.set_flag(4, (self.A & 0x0F) == 0)
            self.set_flag(1, 0)
        
        elif op == 0x3E:  # LD A, imm
            self.A = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        
        elif op == 0x41:  # LD B,C
            self.B = self.C
        
        elif op == 0x4E:  # LD C,(HL)
            self.C = self.read_mem(self.get_hl())
        
        elif op == 0x4F:  # LD C,A
            self.C = self.A
        
        elif op == 0x60:  # LD H,B
            self.H = self.B
        
        elif op == 0x69:  # LD L,C
            self.L = self.C
        
        elif op == 0x7E:  # LD A,(HL)
            self.A = self.read_mem(self.get_hl())
        
        elif op == 0x79:  # LD A,C
            self.A = self.C
        
        elif op == 0x80:  # ADD A,B
            result = self.A + self.B
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.B & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
            self.set_flag(2, (self.A & 1) == 0)  # P=even parity
        
        elif op == 0x81:  # ADD A,C
            result = self.A + self.C
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.C & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        
        elif op == 0x87:  # ADD A,A
            result = self.A + self.A
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.A & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        
        elif op == 0xC3:  # JP imm
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (hi << 8) | lo
        
        elif op == 0xC6:  # ADD A, imm
            val = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            result = self.A + val
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (val & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        
        elif op == 0xC9:  # RET
            lo = self.read_mem(self.SP)
            hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.PC = (hi << 8) | lo
        
        elif op == 0xCD:  # CALL imm
            lo = self.read_mem(self.PC)
            hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, self.PC)
            self.PC = (hi << 8) | lo
        
        elif op == 0xD8:  # RET C
            if self.get_flag(0):
                lo = self.read_mem(self.SP)
                hi = self.read_mem(self.SP + 1)
                self.SP = (self.SP + 2) & 0xFFFF
                self.PC = (hi << 8) | lo
        
        elif op == 0xE1:  # POP HL
            lo = self.read_mem(self.SP)
            hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.H = hi
            self.L = lo
        
        elif op == 0xE5:  # PUSH HL
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, self.get_hl())
        
        elif op == 0xF3:  # DI
            pass  # ignore interrupts
        
        elif op == 0xED:
            ed_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            
            if ed_op == 0x79:  # OUT (C),A
                pass  # ignore I/O
            
            elif ed_op == 0xA0:  # LDI
                self.write_mem(self.get_de(), self.read_mem(self.get_hl()))
                self.set_hl((self.get_hl() + 1) & 0xFFFF)
                self.set_de((self.get_de() + 1) & 0xFFFF)
                bc = self.get_bc()
                self.set_bc((bc - 1) & 0xFFFF)
                self.set_flag(1, 0)
                self.set_flag(2, bc != 1)
                self.set_flag(4, 0)
            
            elif ed_op == 0xB0:  # LDIR
                src = self.get_hl()
                dst = self.get_de()
                count = self.get_bc()
                if count > 0:
                    self.write_mem(dst, self.read_mem(src))
                    self.set_hl((src + 1) & 0xFFFF)
                    self.set_de((dst + 1) & 0xFFFF)
                    self.set_bc((count - 1) & 0xFFFF)
                    if count > 1:
                        self.PC = (self.PC - 2) & 0xFFFF  # repeat
                self.set_flag(1, 0)
                self.set_flag(2, count > 1)
                self.set_flag(4, 0)
        
        elif op == 0xDD:  # IX prefix
            dd_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            
            if dd_op == 0xE1:  # POP IX
                lo = self.read_mem(self.SP)
                hi = self.read_mem(self.SP + 1)
                self.SP = (self.SP + 2) & 0xFFFF
                self.IX = (hi << 8) | lo
            
            elif dd_op == 0xE5:  # PUSH IX
                self.SP = (self.SP - 2) & 0xFFFF
                self.write_word(self.SP, self.IX)
            
            else:
                raise NotImplementedError(f"DD prefix ${dd_op:02x} not implemented")
        
        elif op == 0xCB:
            cb_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            
            if cb_op == 0x10:  # RL B
                c_in = self.get_flag(0)
                c_out = (self.B & 0x80) >> 7
                self.B = ((self.B << 1) | c_in) & 0xFF
                self.set_flag(0, c_out)
                self.set_flag(6, self.B == 0)
            
            elif cb_op == 0x11:  # RL C
                c_in = self.get_flag(0)
                c_out = (self.C & 0x80) >> 7
                self.C = ((self.C << 1) | c_in) & 0xFF
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            
            elif cb_op == 0x19:  # RR C
                c_in = self.get_flag(0)
                c_out = self.C & 1
                self.C = (c_in << 7) | (self.C >> 1)
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            
            elif cb_op == 0x29:  # SRA C
                c_out = self.C & 1
                sign = self.C & 0x80
                self.C = (self.C >> 1) | sign  # arithmetic shift preserves sign
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            
            elif cb_op == 0x39:  # SRL C
                c_out = self.C & 1
                self.C >>= 1
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            
            else:
                raise NotImplementedError(f"CB prefix ${cb_op:02x} not implemented")
        
        else:
            raise NotImplementedError(f"Opcode ${op:02x} at PC=${self.PC-1:04x} not implemented")
    
    def run(self):
        """Run the emulator until RET or decompressed size reached."""
        output_end = self.output_addr + 6912
        while self.cycle_count < self.max_cycles:
            self.cycle_count += 1
            self.step()
            
            # Check if we've decompressed enough (6912 bytes for Spectrum screen)
            if self.get_de() >= output_end:
                break
            
            # Check for RET C return (end of stream marker)
            # The decompressor returns via RET C at $625C
            if self.PC == 0x6052:  # return address
                break
            
            if self.cycle_count >= self.max_cycles:
                break
    
    def decompress(self, input_addr, output_addr, bank=0):
        """Decompress data from input_addr to output_addr.
        
        Sets up registers like the Z80 CALL $621A convention:
          HL = input_addr
          DE = output_addr
          A  = bank number
        """
        self.PC = 0x621A
        self.set_hl(input_addr)
        self.set_de(output_addr)
        self.A = bank
        self.output_addr = output_addr
        
        # Run the decompressor
        self.run()
        
        # Extract output from memory
        # The output was written to output_addr via LDI/LDIR
        output_len = 6912  # standard Spectrum screen size
        self.output = bytes(self.mem[output_addr:output_addr + output_len])
        return self.output


def decompress_screen(data, screen_num=1):
    """Decompress a loading screen from block 3.
    
    screen_num: 1 = first loading screen at $629C
                2 = second loading screen at $65F0
    """
    emu = Z80Emu(data, 0)
    
    if screen_num == 1:
        input_addr = 0x629C
    else:
        input_addr = 0x65F0
    
    output_addr = 0xC000  # decompression buffer
    
    result = emu.decompress(input_addr, output_addr, 0)
    return result


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <loader_file> <output_file> [screen_num]")
        print(f"  screen_num: 1 or 2 (default 1)")
        sys.exit(1)
    
    with open(sys.argv[1], "rb") as f:
        indata = f.read()
    
    screen_num = int(sys.argv[3], 0) if len(sys.argv) > 3 else 1
    
    result = decompress_screen(indata, screen_num)
    
    with open(sys.argv[2], "wb") as f:
        f.write(result)
    
    print(f"Decompressed screen {screen_num}: {len(result)} bytes")
    print(f"First 64 bytes: {' '.join(f'{b:02x}' for b in result[:64])}")
    print(f"Output: {sys.argv[2]}")
