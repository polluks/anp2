#!/usr/bin/env python3
"""Decompress ANP2 game data banks and extract PT3 modules."""

import struct
import sys
import os


class Z80Emu:
    """Minimal Z80 emulator for the ANP2 Exomizer 2 decompressor at $621A."""
    
    def __init__(self):
        self.mem = bytearray(65536)
        self.PC = 0
        self.SP = 0xFFFE
        self.A = 0; self.B = 0; self.C = 0; self.D = 0; self.E = 0
        self.H = 0; self.L = 0; self.F = 0
        self.AF2 = 0; self.IX = 0; self.IY = 0
        self.cycle_count = 0
        self.max_cycles = 2000000
        self.trace = False
        self.output_min_addr = 0xFFFF
        self.output_max_addr = 0
    
    def get_flag(self, bit):
        return (self.F >> bit) & 1
    
    def set_flag(self, bit, val):
        if val: self.F |= (1 << bit)
        else: self.F &= ~(1 << bit)
    
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
        op = self.read_mem(self.PC)
        self.PC = (self.PC + 1) & 0xFFFF
        
        if op == 0x00:  # NOP
            pass
        elif op == 0x01:  # LD BC, imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.B = hi; self.C = lo
        elif op == 0x03:  # INC BC
            self.set_bc((self.get_bc() + 1) & 0xFFFF)
        elif op == 0x04:  # INC B
            self.B = (self.B + 1) & 0xFF
            self.set_flag(6, self.B == 0)
            self.set_flag(4, (self.B & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x05:  # DEC B
            self.B = (self.B - 1) & 0xFF
            self.set_flag(6, self.B == 0)
            self.set_flag(4, (self.B & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        elif op == 0x06:  # LD B, imm
            self.B = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x08:  # EX AF,AF'
            tmp = ((self.A << 8) | (self.F & 0xFF)) & 0xFFFF
            self.A = (self.AF2 >> 8) & 0xFF
            self.F = self.AF2 & 0xFF
            self.AF2 = tmp
        elif op == 0x0c:  # INC C
            self.C = (self.C + 1) & 0xFF
            self.set_flag(6, self.C == 0)
            self.set_flag(4, (self.C & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x0e:  # LD C, imm
            self.C = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x10:  # DJNZ disp
            self.B = (self.B - 1) & 0xFF
            if self.B != 0:
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1 + disp) & 0xFFFF
            else:
                self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x11:  # LD DE, imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.D = hi; self.E = lo
        elif op == 0x12:  # LD (DE),A
            self.write_mem(self.get_de(), self.A)
            self.track_write(self.get_de())
        elif op == 0x13:  # INC DE
            self.set_de((self.get_de() + 1) & 0xFFFF)
        elif op == 0x14:  # INC D
            self.D = (self.D + 1) & 0xFF
            self.set_flag(6, self.D == 0)
            self.set_flag(4, (self.D & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x15:  # DEC D
            self.D = (self.D - 1) & 0xFF
            self.set_flag(6, self.D == 0)
            self.set_flag(4, (self.D & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        elif op == 0x16:  # LD D, imm
            self.D = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x17:  # RLA
            c_in = self.get_flag(0)
            c_out = (self.A & 0x80) >> 7
            self.A = ((self.A << 1) | c_in) & 0xFF
            self.set_flag(0, c_out)
        elif op == 0x18:  # JR disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1 + disp) & 0xFFFF
        elif op == 0x19:  # ADD HL,DE
            hl = self.get_hl(); de = self.get_de()
            result = hl + de
            self.set_hl(result & 0xFFFF)
            self.set_flag(0, result > 0xFFFF)
            self.set_flag(4, (hl & 0x0FFF) + (de & 0x0FFF) > 0x0FFF)
            self.set_flag(1, 0)
        elif op == 0x1a:  # LD A,(DE)
            self.A = self.read_mem(self.get_de())
        elif op == 0x1e:  # LD E, imm
            self.E = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x20:  # JR NZ, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if not self.get_flag(6):
                self.PC = (self.PC + disp) & 0xFFFF
        elif op == 0x21:  # LD HL, imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.H = hi; self.L = lo
        elif op == 0x22:  # LD (imm),HL
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.write_word((hi << 8) | lo, self.get_hl())
        elif op == 0x23:  # INC HL
            self.set_hl((self.get_hl() + 1) & 0xFFFF)
        elif op == 0x24:  # INC H
            self.H = (self.H + 1) & 0xFF
            self.set_flag(6, self.H == 0)
            self.set_flag(4, (self.H & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x25:  # DEC H
            self.H = (self.H - 1) & 0xFF
            self.set_flag(6, self.H == 0)
            self.set_flag(4, (self.H & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        elif op == 0x28:  # JR Z, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if self.get_flag(6):
                self.PC = (self.PC + disp) & 0xFFFF
        elif op == 0x2b:  # DEC HL
            self.set_hl((self.get_hl() - 1) & 0xFFFF)
        elif op == 0x30:  # JR NC, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if not self.get_flag(0):
                self.PC = (self.PC + disp) & 0xFFFF
        elif op == 0x31:  # LD SP, imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.SP = (hi << 8) | lo
        elif op == 0x32:  # LD (imm),A
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.write_mem((hi << 8) | lo, self.A)
        elif op == 0x33:  # INC SP
            self.SP = (self.SP + 1) & 0xFFFF
        elif op == 0x34:  # INC (HL)
            v = (self.read_mem(self.get_hl()) + 1) & 0xFF
            self.write_mem(self.get_hl(), v)
            self.set_flag(6, v == 0)
            self.set_flag(4, (v & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x35:  # DEC (HL)
            v = (self.read_mem(self.get_hl()) - 1) & 0xFF
            self.write_mem(self.get_hl(), v)
            self.set_flag(6, v == 0)
            self.set_flag(4, (v & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        elif op == 0x36:  # LD (HL),imm
            self.write_mem(self.get_hl(), self.read_mem(self.PC))
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x37:  # SCF
            self.set_flag(0, 1)
            self.set_flag(4, 0)
            self.set_flag(1, 0)
        elif op == 0x38:  # JR C, disp
            disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
            self.PC = (self.PC + 1) & 0xFFFF
            if self.get_flag(0):
                self.PC = (self.PC + disp) & 0xFFFF
        elif op == 0x3c:  # INC A
            self.A = (self.A + 1) & 0xFF
            self.set_flag(6, self.A == 0)
            self.set_flag(4, (self.A & 0x0F) == 0)
            self.set_flag(1, 0)
        elif op == 0x3d:  # DEC A
            self.A = (self.A - 1) & 0xFF
            self.set_flag(6, self.A == 0)
            self.set_flag(4, (self.A & 0x0F) == 0x0F)
            self.set_flag(1, 1)
        elif op == 0x3e:  # LD A, imm
            self.A = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
        elif op == 0x41:  # LD B,C
            self.B = self.C
        elif op == 0x42:  # LD B,D
            self.B = self.D
        elif op == 0x43:  # LD B,E
            self.B = self.E
        elif op == 0x44:  # LD B,H
            self.B = self.H
        elif op == 0x45:  # LD B,L
            self.B = self.L
        elif op == 0x46:  # LD B,(HL)
            self.B = self.read_mem(self.get_hl())
        elif op == 0x47:  # LD B,A
            self.B = self.A
        elif op == 0x48:  # LD C,B
            self.C = self.B
        elif op == 0x49:  # LD C,C
            pass
        elif op == 0x4a:  # LD C,D
            self.C = self.D
        elif op == 0x4e:  # LD C,(HL)
            self.C = self.read_mem(self.get_hl())
        elif op == 0x4f:  # LD C,A
            self.C = self.A
        elif op == 0x57:  # LD D,A
            self.D = self.A
        elif op == 0x5c:  # LD E,H
            self.E = self.H
        elif op == 0x5d:  # LD E,L
            self.E = self.L
        elif op == 0x5f:  # LD E,A
            self.E = self.A
        elif op == 0x60:  # LD H,B
            self.H = self.B
        elif op == 0x61:  # LD H,C
            self.H = self.C
        elif op == 0x62:  # LD H,D
            self.H = self.D
        elif op == 0x63:  # LD H,E
            self.H = self.E
        elif op == 0x64:  # LD H,H
            pass
        elif op == 0x65:  # LD H,L
            self.H = self.L
        elif op == 0x66:  # LD H,(HL)
            self.H = self.read_mem(self.get_hl())
        elif op == 0x67:  # LD H,A
            self.H = self.A
        elif op == 0x68:  # LD L,B
            self.L = self.B
        elif op == 0x69:  # LD L,C
            self.L = self.C
        elif op == 0x6a:  # LD L,D
            self.L = self.D
        elif op == 0x6b:  # LD L,E
            self.L = self.E
        elif op == 0x6c:  # LD L,H
            self.L = self.H
        elif op == 0x6d:  # LD L,L
            pass
        elif op == 0x6e:  # LD L,(HL)
            self.L = self.read_mem(self.get_hl())
        elif op == 0x6f:  # LD L,A
            self.L = self.A
        elif op == 0x77:  # LD (HL),A
            self.write_mem(self.get_hl(), self.A)
        elif op == 0x78:  # LD A,B
            self.A = self.B
        elif op == 0x79:  # LD A,C
            self.A = self.C
        elif op == 0x7a:  # LD A,D
            self.A = self.D
        elif op == 0x7b:  # LD A,E
            self.A = self.E
        elif op == 0x7c:  # LD A,H
            self.A = self.H
        elif op == 0x7d:  # LD A,L
            self.A = self.L
        elif op == 0x7e:  # LD A,(HL)
            self.A = self.read_mem(self.get_hl())
        elif op == 0x80:  # ADD A,B
            result = self.A + self.B
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.B & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x81:  # ADD A,C
            result = self.A + self.C
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.C & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x83:  # ADD A,E
            result = self.A + self.E
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.E & 0x0F) > 0x0F)
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
        elif op == 0x8f:  # ADC A,A
            c = self.get_flag(0)
            result = self.A + self.A + c
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (self.A & 0x0F) + c > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x90:  # SUB B
            result = self.A - self.B
            self.set_flag(0, result < 0)
            self.set_flag(4, (self.A & 0x0F) - (self.B & 0x0F) < 0)
            self.set_flag(1, 1)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x91:  # SUB C
            result = self.A - self.C
            self.set_flag(0, result < 0)
            self.set_flag(4, (self.A & 0x0F) - (self.C & 0x0F) < 0)
            self.set_flag(1, 1)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x93:  # SUB E
            result = self.A - self.E
            self.set_flag(0, result < 0)
            self.set_flag(4, (self.A & 0x0F) - (self.E & 0x0F) < 0)
            self.set_flag(1, 1)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0x97:  # SUB A
            self.A = 0
            self.set_flag(0, 0)
            self.set_flag(4, 0)
            self.set_flag(1, 1)
            self.set_flag(6, 1)
        elif op == 0xa0:  # AND B
            self.A &= self.B
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xa1:  # AND C
            self.A &= self.C
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xa8:  # XOR B
            self.A ^= self.B
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xa9:  # XOR C
            self.A ^= self.C
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xaf:  # XOR A
            self.A = 0
            self.set_flag(6, 1)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xb0:  # OR B
            self.A |= self.B
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xb1:  # OR C
            self.A |= self.C
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xb7:  # OR A
            self.set_flag(6, self.A == 0)
            self.set_flag(1, 0)
            self.set_flag(4, 1)
        elif op == 0xb8:  # CP B
            result = self.A - self.B
            self.set_flag(0, result < 0)
            self.set_flag(6, (result & 0xFF) == 0)
            self.set_flag(4, (self.A & 0x0F) - (self.B & 0x0F) < 0)
            self.set_flag(1, 1)
        elif op == 0xb9:  # CP C
            result = self.A - self.C
            self.set_flag(0, result < 0)
            self.set_flag(6, (result & 0xFF) == 0)
            self.set_flag(4, (self.A & 0x0F) - (self.C & 0x0F) < 0)
            self.set_flag(1, 1)
        elif op == 0xbb:  # CP E
            result = self.A - self.E
            self.set_flag(0, result < 0)
            self.set_flag(6, (result & 0xFF) == 0)
            self.set_flag(4, (self.A & 0x0F) - (self.E & 0x0F) < 0)
            self.set_flag(1, 1)
        elif op == 0xc1:  # POP BC
            lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.B = hi; self.C = lo
        elif op == 0xc3:  # JP imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (hi << 8) | lo
        elif op == 0xc5:  # PUSH BC
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, (self.B << 8) | self.C)
        elif op == 0xc6:  # ADD A, imm
            val = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            result = self.A + val
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (val & 0x0F) > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0xc9:  # RET
            lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.PC = (hi << 8) | lo
        elif op == 0xcd:  # CALL imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, self.PC)
            self.PC = (hi << 8) | lo
        elif op == 0xce:  # ADC A,imm
            val = self.read_mem(self.PC); self.PC = (self.PC + 1) & 0xFFFF
            c = self.get_flag(0)
            result = self.A + val + c
            self.set_flag(0, result > 0xFF)
            self.set_flag(4, (self.A & 0x0F) + (val & 0x0F) + c > 0x0F)
            self.set_flag(1, 0)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0xd1:  # POP DE
            lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.D = hi; self.E = lo
        elif op == 0xd5:  # PUSH DE
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, (self.D << 8) | self.E)
        elif op == 0xd8:  # RET C
            if self.get_flag(0):
                lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
                self.SP = (self.SP + 2) & 0xFFFF
                self.PC = (hi << 8) | lo
        elif op == 0xdb:  # IN A,(imm)
            port = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            # For tape loading: return bit from tape
            if port == 0xFE:
                self.A = 0xBF  # All keys up, bit 6=0 (tape)
            elif port == 0x1F:
                self.A = 0xFF  # No joystick
            elif port == 0x7F:
                self.A = 0xFF  # No keys pressed
            else:
                self.A = 0xFF
        elif op == 0xdc:  # CALL C,imm
            lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
            self.PC = (self.PC + 2) & 0xFFFF
            if self.get_flag(0):
                self.SP = (self.SP - 2) & 0xFFFF
                self.write_word(self.SP, self.PC)
                self.PC = (hi << 8) | lo
        elif op == 0xde:  # SBC A,imm
            val = self.read_mem(self.PC); self.PC = (self.PC + 1) & 0xFFFF
            c = self.get_flag(0)
            result = self.A - val - c
            self.set_flag(0, result < 0)
            self.set_flag(4, (self.A & 0x0F) - (val & 0x0F) - c < 0)
            self.set_flag(1, 1)
            self.A = result & 0xFF
            self.set_flag(6, self.A == 0)
        elif op == 0xd3:  # OUT (imm),A
            port = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            # Ignore port writes
        elif op == 0xe1:  # POP HL
            lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.H = hi; self.L = lo
        elif op == 0xe5:  # PUSH HL
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, self.get_hl())
        elif op == 0xeb:  # EX DE,HL
            tmp = self.get_hl()
            self.set_hl(self.get_de())
            self.set_de(tmp)
        elif op == 0xf1:  # POP AF
            lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
            self.SP = (self.SP + 2) & 0xFFFF
            self.A = hi; self.F = lo & 0xFF
        elif op == 0xf3:  # DI
            pass
        elif op == 0xf5:  # PUSH AF
            self.SP = (self.SP - 2) & 0xFFFF
            self.write_word(self.SP, (self.A << 8) | (self.F & 0xFF))
        elif op == 0xfe:  # CP imm
            val = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            result = self.A - val
            self.set_flag(0, result < 0)
            self.set_flag(6, (result & 0xFF) == 0)
            self.set_flag(4, (self.A & 0x0F) - (val & 0x0F) < 0)
            self.set_flag(1, 1)
        
        elif op == 0xed:
            ed_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            if ed_op == 0x43:  # LD (imm),BC
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                self.write_word((hi << 8) | lo, (self.B << 8) | self.C)
            elif ed_op == 0x4b:  # LD BC,(imm)
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                val = self.read_word((hi << 8) | lo)
                self.B = (val >> 8) & 0xFF; self.C = val & 0xFF
            elif ed_op == 0x53:  # LD (imm),DE
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                self.write_word((hi << 8) | lo, (self.D << 8) | self.E)
            elif ed_op == 0x5b:  # LD DE,(imm)
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                val = self.read_word((hi << 8) | lo)
                self.D = (val >> 8) & 0xFF; self.E = val & 0xFF
            elif ed_op == 0x79:  # OUT (C),A
                pass
            elif ed_op == 0xa0:  # LDI
                val = self.read_mem(self.get_hl())
                self.write_mem(self.get_de(), val)
                self.track_write(self.get_de())
                self.set_hl((self.get_hl() + 1) & 0xFFFF)
                self.set_de((self.get_de() + 1) & 0xFFFF)
                bc = self.get_bc()
                self.set_bc((bc - 1) & 0xFFFF)
                self.set_flag(1, 0)
                self.set_flag(2, bc != 1)
                self.set_flag(4, 0)
            elif ed_op == 0xb0:  # LDIR
                if self.get_bc() > 0:
                    val = self.read_mem(self.get_hl())
                    self.write_mem(self.get_de(), val)
                    self.track_write(self.get_de())
                    self.set_hl((self.get_hl() + 1) & 0xFFFF)
                    self.set_de((self.get_de() + 1) & 0xFFFF)
                    self.set_bc((self.get_bc() - 1) & 0xFFFF)
                    if self.get_bc() > 0:
                        self.PC = (self.PC - 2) & 0xFFFF
                self.set_flag(1, 0)
                self.set_flag(2, self.get_bc() != 0)
                self.set_flag(4, 0)
            elif ed_op == 0xb3:  # OTIR
                # Tape save - ignore
                if self.B > 0:
                    self.B = (self.B - 1) & 0xFF
                    self.C = (self.C + 1) & 0xFF
                    if self.B > 0:
                        self.PC = (self.PC - 2) & 0xFFFF
                else:
                    self.set_flag(1, 0)
                    self.set_flag(2, 1)
                    self.set_flag(6, 0)
            else:
                raise NotImplementedError(f"ED ${ed_op:02x} at PC=${self.PC-2:04x}")
        
        elif op == 0xcb:
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
                self.C = (self.C >> 1) | sign
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            elif cb_op == 0x39:  # SRL C
                c_out = self.C & 1
                self.C >>= 1
                self.set_flag(0, c_out)
                self.set_flag(6, self.C == 0)
            else:
                raise NotImplementedError(f"CB ${cb_op:02x} at PC=${self.PC-2:04x}")
        
        elif op == 0xdd:  # IX prefix
            dd_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            if dd_op == 0x21:  # LD IX,imm
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                self.IX = (hi << 8) | lo
            elif dd_op == 0x23:  # INC IX
                self.IX = (self.IX + 1) & 0xFFFF
            elif dd_op == 0x2b:  # DEC IX
                self.IX = (self.IX - 1) & 0xFFFF
            elif dd_op == 0x34:  # INC (IX+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                addr = (self.IX + disp) & 0xFFFF
                v = (self.read_mem(addr) + 1) & 0xFF
                self.write_mem(addr, v)
                self.set_flag(6, v == 0)
                self.set_flag(4, (v & 0x0F) == 0)
                self.set_flag(1, 0)
            elif dd_op == 0x35:  # DEC (IX+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                addr = (self.IX + disp) & 0xFFFF
                v = (self.read_mem(addr) - 1) & 0xFF
                self.write_mem(addr, v)
                self.set_flag(6, v == 0)
                self.set_flag(4, (v & 0x0F) == 0x0F)
                self.set_flag(1, 1)
            elif dd_op == 0x7e:  # LD A,(IX+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                self.A = self.read_mem((self.IX + disp) & 0xFFFF)
            elif dd_op == 0x77:  # LD (IX+disp),A
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                self.write_mem((self.IX + disp) & 0xFFFF, self.A)
            elif dd_op == 0xe1:  # POP IX
                lo = self.read_mem(self.SP); hi = self.read_mem(self.SP + 1)
                self.SP = (self.SP + 2) & 0xFFFF
                self.IX = (hi << 8) | lo
            elif dd_op == 0xe5:  # PUSH IX
                self.SP = (self.SP - 2) & 0xFFFF
                self.write_word(self.SP, self.IX)
            else:
                raise NotImplementedError(f"DD ${dd_op:02x} at PC=${self.PC-2:04x}")
        
        elif op == 0xfd:  # IY prefix
            fd_op = self.read_mem(self.PC)
            self.PC = (self.PC + 1) & 0xFFFF
            if fd_op == 0x21:  # LD IY,imm
                lo = self.read_mem(self.PC); hi = self.read_mem(self.PC + 1)
                self.PC = (self.PC + 2) & 0xFFFF
                self.IY = (hi << 8) | lo
            elif fd_op == 0x23:  # INC IY
                self.IY = (self.IY + 1) & 0xFFFF
            elif fd_op == 0x2b:  # DEC IY
                self.IY = (self.IY - 1) & 0xFFFF
            elif fd_op == 0x7e:  # LD A,(IY+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                self.A = self.read_mem((self.IY + disp) & 0xFFFF)
            elif fd_op == 0x77:  # LD (IY+disp),A
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                self.write_mem((self.IY + disp) & 0xFFFF, self.A)
            elif fd_op == 0x34:  # INC (IY+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                addr = (self.IY + disp) & 0xFFFF
                v = (self.read_mem(addr) + 1) & 0xFF
                self.write_mem(addr, v)
                self.set_flag(6, v == 0)
                self.set_flag(4, (v & 0x0F) == 0)
                self.set_flag(1, 0)
            elif fd_op == 0x35:  # DEC (IY+disp)
                disp = struct.unpack_from('<b', bytes([self.read_mem(self.PC)]))[0]
                self.PC = (self.PC + 1) & 0xFFFF
                addr = (self.IY + disp) & 0xFFFF
                v = (self.read_mem(addr) - 1) & 0xFF
                self.write_mem(addr, v)
                self.set_flag(6, v == 0)
                self.set_flag(4, (v & 0x0F) == 0x0F)
                self.set_flag(1, 1)
            else:
                raise NotImplementedError(f"FD ${fd_op:02x} at PC=${self.PC-2:04x}")
        
        else:
            raise NotImplementedError(f"Opcode ${op:02x} at PC=${self.PC-1:04x}")
    
    def track_write(self, addr):
        if addr < self.output_min_addr:
            self.output_min_addr = addr
        if addr > self.output_max_addr:
            self.output_max_addr = addr
    
    def run(self):
        """Run until RET C at $625C."""
        while self.cycle_count < self.max_cycles:
            self.cycle_count += 1
            prev_pc = self.PC
            self.step()
            # End when RET C is executed at $625C
            if prev_pc == 0x625C and self.read_mem(0x625C) == 0xD8:
                if self.get_flag(0):
                    break
            # Also stop at HALT or JP $606A (infinite loop)
            if self.PC == 0x606A or self.PC == 0x616A:
                break
            if self.cycle_count >= self.max_cycles:
                break
    
    def decompress(self, input_addr, output_addr, bank=0):
        """Decompress data using the Exomizer 2 routine at $621A."""
        self.PC = 0x621A
        self.set_hl(input_addr)
        self.set_de(output_addr)
        self.A = bank & 0xFF
        self.B = 0; self.C = 0
        self.output_min_addr = 0xFFFF
        self.output_max_addr = 0
        self.cycle_count = 0
        
        self.run()
        
        output_start = self.output_min_addr
        output_end = self.output_max_addr + 1
        
        if output_start > output_end or output_start == 0xFFFF:
            return b''
        
        return bytes(self.mem[output_start:output_end])


def load_loader(emu, loader_path):
    """Load the block 3 loader into memory at $6000."""
    with open(loader_path, 'rb') as f:
        loader = f.read()
    for i, b in enumerate(loader):
        emu.mem[0x6000 + i] = b


def load_compressed_block(emu, block_path, load_addr=0x6800):
    """Load a compressed block into memory at the given address."""
    with open(block_path, 'rb') as f:
        data = f.read()
    for i, b in enumerate(data):
        emu.mem[load_addr + i] = b
    return data


def is_pt3_module(data, offset):
    """Check if data at offset looks like a PT3 module."""
    if offset + 0xC9 > len(data):
        return False
    
    # Check version byte at offset 0x0C (should be 0..something)
    version = data[offset + 0x0C]
    if version > 3:
        return False
    
    # Check speed at offset 0x64
    speed = data[offset + 0x64]
    if speed == 0 or speed > 16:
        return False
    
    # Check num_pat-1 at offset 0x65
    num_pat = data[offset + 0x65] + 1
    if num_pat == 0 or num_pat > 64:
        return False
    
    # Check loop byte at offset 0x66
    loop = data[offset + 0x66]
    if loop > num_pat:
        return False
    
    # Pattern pointer at 0x67-0x68 (should be reasonable)
    pat_ptr = data[offset + 0x67] | (data[offset + 0x68] << 8)
    if pat_ptr < 0x67 or pat_ptr > 0x8000:
        return False
    
    # Check for readable text in title area (0x22-0x41, 32 bytes for name)
    # Spectrum text is uppercase with some control codes
    title = data[offset + 0x22:offset + 0x42]
    readable = sum(1 for c in title if 0x20 <= c <= 0x7E or c == 0)
    if readable < 10:  # At least some readable chars
        return False
    
    return True


def extract_pt3_info(data, offset):
    """Extract identifying information from a PT3 module."""
    version = data[offset + 0x0C]
    compof = data[offset + 0x0D:offset + 0x0D + 16]
    name = data[offset + 0x22:offset + 0x22 + 32]
    author = data[offset + 0x42:offset + 0x42 + 32]
    
    def to_text(buf):
        return ''.join(chr(b & 0x7F) if 0x20 <= (b & 0x7F) <= 0x7E else '.' for b in buf).rstrip('.')
    
    speed = data[offset + 0x64]
    num_pat = data[offset + 0x65] + 1
    loop = data[offset + 0x66]
    pat_ptr = data[offset + 0x67] | (data[offset + 0x68] << 8)
    
    return {
        'version': version,
        'composer': to_text(compof),
        'name': to_text(name),
        'author': to_text(author),
        'speed': speed,
        'num_patterns': num_pat,
        'loop': loop,
        'pat_ptr': pat_ptr,
    }


def find_pt3_modules(data):
    """Find all PT3 module signatures in the data."""
    modules = []
    offset = 0
    last_valid = 0
    
    while offset < len(data) - 0xC9:
        # Quick check: look for version byte 0x01 or 0x02 at +0x0C
        if data[offset + 0x0C] in (0, 1, 2, 3):
            if is_pt3_module(data, offset):
                info = extract_pt3_info(data, offset)
                modules.append((offset, info))
                offset += 0xC9  # Skip past this module
                continue
        offset += 1
    
    return modules


def main():
    base_dir = os.environ.get('ANP2_ROOT', '/root/ai/anp2')
    out_dir = os.environ.get('ANP2_OUTDIR', '/tmp')
    os.makedirs(out_dir, exist_ok=True)
    
    # Step 1: Initialize emulator
    emu = Z80Emu()
    
    # Step 2: Load loader code
    print("Loading block 3 (loader)...")
    load_loader(emu, f'{base_dir}/extracted_block_3.bin')
    
    # Step 3: Define the decompression sequence
    # Map of (block_file, block_load_addr, list_of_decompress_ops)
    # Each op: (name, input_addr, output_addr, bank)
    sequence = [
        ('extracted_block_3.bin', None, [
            ('bank_3_a', 0x629C, 0xC000, 0),
            ('bank_3_b', 0x65F0, 0xC000, 0),
        ]),
        ('extracted_block_4.bin', 0x6800, [
            ('bank_0', 0x6800, 0xC000, 0),
            ('bank_1', 0x8F19, 0xC000, 1),
            ('bank_7_v1', 0xA891, 0xC000, 7),
        ]),
        ('extracted_block_5.bin', 0x6800, [
            ('bank_3', 0x6800, 0xC000, 3),
            ('bank_4', 0x7D2D, 0xC000, 4),
            ('bank_6', 0xA90A, 0xC000, 6),
        ]),
        ('extracted_block_6.bin', 0x6800, [
            ('bank_7_v2', 0x6800, 0x9F00, 7),
        ]),
    ]
    
    all_banks = {}
    
    for block_file, load_addr, ops in sequence:
        if load_addr is None:
            print(f"\n--- {block_file} already resident at $6000 ---")
        else:
            block_path = f'{base_dir}/{block_file}'
            print(f"\n--- Loading {block_file} at ${load_addr:04x} ---")
            data = load_compressed_block(emu, block_path, load_addr)
            print(f"  Loaded {len(data)} bytes (${len(data):04x})")
        
        for name, input_addr, output_addr, bank in ops:
            print(f"\n  Decompressing {name}: HL=${input_addr:04x}, DE=${output_addr:04x}, A={bank}")
            try:
                result = emu.decompress(input_addr, output_addr, bank)
                if result:
                    out_path = f'{out_dir}/{name}.bin'
                    with open(out_path, 'wb') as f:
                        f.write(result)
                    print(f"  -> {len(result)} bytes written to {out_path}")
                    all_banks[name] = result
                    
                    # Check first bytes
                    print(f"  -> First 32 bytes: {' '.join(f'{b:02x}' for b in result[:32])}")
                    if len(result) > 0x22:
                        title = result[0x22:0x42]
                        title_text = ''.join(chr(b & 0x7F) if 0x20 <= (b & 0x7F) <= 0x7E else '.' for b in title)
                        print(f"  -> Title area: '{title_text}'")
                else:
                    print(f"  -> WARNING: No output data!")
            except Exception as e:
                print(f"  -> ERROR: {e}")
                import traceback
                traceback.print_exc()
    
    # Step 4: Handle the copy + decompress from block 6
    print(f"\n--- Block 6 post-processing ---")
    # Copy $1800 bytes from $7D27 to $C000
    src = 0x7D27
    dst = 0xC000
    size = 0x1800
    print(f"  Copying ${size:04x} bytes from ${src:04x} to ${dst:04x}")
    
    # But block 6 only has 9878 bytes, going from $6800 to $8E97
    # $7D27 + $1800 = $9527, past the end of block 6 at $8E97
    # Copy whatever is available
    actual_size = min(size, 65536 - max(src, dst))
    
    copied = 0
    for i in range(actual_size):
        if dst + i >= 65536 or src + i >= 65536:
            break
        val = emu.mem[src + i]
        emu.mem[dst + i] = val
        copied += 1
    print(f"  Actually copied {copied} bytes")
    
    # Decompress from $C000 to $6300 with A=7
    print(f"  Decompressing HL=$C000, DE=$6300, A=7")
    try:
        result = emu.decompress(0xC000, 0x6300, 7)
        if result:
            out_path = f'{out_dir}/bank_post.bin'
            with open(out_path, 'wb') as f:
                f.write(result)
            print(f"  -> {len(result)} bytes written to {out_path}")
            all_banks['bank_post'] = result
        else:
            print(f"  -> No output")
    except Exception as e:
        print(f"  -> ERROR: {e}")
    
    # Step 5: Search all banks for PT3 modules
    print(f"\n{'='*60}")
    print("SEARCHING FOR PT3 MODULES")
    print(f"{'='*60}")
    
    for bank_name, bank_data in sorted(all_banks.items()):
        modules = find_pt3_modules(bank_data)
        if modules:
            print(f"\n>>> {bank_name}: {len(modules)} PT3 module(s) found")
            for offset, info in modules:
                print(f"    Offset: ${offset:04x} ({offset})")
                print(f"    Name:   '{info['name']}'")
                print(f"    Author: '{info['author']}'")
                print(f"    Composer: '{info['composer']}'")
                print(f"    Version: {info['version']}, Speed: {info['speed']}, Patterns: {info['num_patterns']}, Loop: {info['loop']}")
                print(f"    PatPtr: ${info['pat_ptr']:04x}")
                
                # Save the module
                mod_path = f'{out_dir}/{bank_name}_pt3_at_{offset:04x}.bin'
                with open(mod_path, 'wb') as f:
                    f.write(bank_data[offset:])
                print(f"    Saved: {mod_path}")
                
                # Check if there might be a second module at known offset
                if 'PT3' in info['name'] or 'pt3' in info['name']:
                    print(f"    -> This looks like the main PT3 module!")
        else:
            print(f"\n    {bank_name}: No PT3 modules found ({len(bank_data)} bytes)")


if __name__ == '__main__':
    main()
