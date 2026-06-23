#!/usr/bin/env python3
"""Z80 disassembler for analyzing ZX Spectrum game code"""

import struct
import sys

# Z80 main opcodes (0x00-0xFF)
# Returns (mnemonic, operands, length)
main_op = {}

def init():
    global main_op
    # 0x00-0x3F
    main_op[0x00] = ("NOP", "", 1)
    main_op[0x01] = ("LD", "BC,$+2", 3)
    main_op[0x02] = ("LD", "(BC),A", 1)
    main_op[0x03] = ("INC", "BC", 1)
    main_op[0x04] = ("INC", "B", 1)
    main_op[0x05] = ("DEC", "B", 1)
    main_op[0x06] = ("LD", "B,$+1", 2)
    main_op[0x07] = ("RLCA", "", 1)
    main_op[0x08] = ("EX", "AF,AF'", 1)
    main_op[0x09] = ("ADD", "HL,BC", 1)
    main_op[0x0A] = ("LD", "A,(BC)", 1)
    main_op[0x0B] = ("DEC", "BC", 1)
    main_op[0x0C] = ("INC", "C", 1)
    main_op[0x0D] = ("DEC", "C", 1)
    main_op[0x0E] = ("LD", "C,$+1", 2)
    main_op[0x0F] = ("RRCA", "", 1)
    main_op[0x10] = ("DJNZ", "$+2", 2)
    main_op[0x11] = ("LD", "DE,$+2", 3)
    main_op[0x12] = ("LD", "(DE),A", 1)
    main_op[0x13] = ("INC", "DE", 1)
    main_op[0x14] = ("INC", "D", 1)
    main_op[0x15] = ("DEC", "D", 1)
    main_op[0x16] = ("LD", "D,$+1", 2)
    main_op[0x17] = ("RLA", "", 1)
    main_op[0x18] = ("JR", "$+2", 2)
    main_op[0x19] = ("ADD", "HL,DE", 1)
    main_op[0x1A] = ("LD", "A,(DE)", 1)
    main_op[0x1B] = ("DEC", "DE", 1)
    main_op[0x1C] = ("INC", "E", 1)
    main_op[0x1D] = ("DEC", "E", 1)
    main_op[0x1E] = ("LD", "E,$+1", 2)
    main_op[0x1F] = ("RRA", "", 1)
    main_op[0x20] = ("JR", "NZ,$+2", 2)
    main_op[0x21] = ("LD", "HL,$+2", 3)
    main_op[0x22] = ("LD", "($+2),HL", 3)
    main_op[0x23] = ("INC", "HL", 1)
    main_op[0x24] = ("INC", "H", 1)
    main_op[0x25] = ("DEC", "H", 1)
    main_op[0x26] = ("LD", "H,$+1", 2)
    main_op[0x27] = ("DAA", "", 1)
    main_op[0x28] = ("JR", "Z,$+2", 2)
    main_op[0x29] = ("ADD", "HL,HL", 1)
    main_op[0x2A] = ("LD", "HL,($+2)", 3)
    main_op[0x2B] = ("DEC", "HL", 1)
    main_op[0x2C] = ("INC", "L", 1)
    main_op[0x2D] = ("DEC", "L", 1)
    main_op[0x2E] = ("LD", "L,$+1", 2)
    main_op[0x2F] = ("CPL", "", 1)
    main_op[0x30] = ("JR", "NC,$+2", 2)
    main_op[0x31] = ("LD", "SP,$+2", 3)
    main_op[0x32] = ("LD", "($+2),A", 3)
    main_op[0x33] = ("INC", "SP", 1)
    main_op[0x34] = ("INC", "(HL)", 1)
    main_op[0x35] = ("DEC", "(HL)", 1)
    main_op[0x36] = ("LD", "(HL),$+1", 2)
    main_op[0x37] = ("SCF", "", 1)
    main_op[0x38] = ("JR", "C,$+2", 2)
    main_op[0x39] = ("ADD", "HL,SP", 1)
    main_op[0x3A] = ("LD", "A,($+2)", 3)
    main_op[0x3B] = ("DEC", "SP", 1)
    main_op[0x3C] = ("INC", "A", 1)
    main_op[0x3D] = ("DEC", "A", 1)
    main_op[0x3E] = ("LD", "A,$+1", 2)
    main_op[0x3F] = ("CCF", "", 1)
    # 0x40-0x7F: LD r,r'
    ld_regs = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
    for i in range(0x40, 0x80):
        src = ld_regs[i & 7]
        dst = ld_regs[(i >> 3) & 7]
        main_op[i] = ("LD", f"{dst},{src}", 1)
    # 0x80-0xBF: ADD/ADC/SUB/SBC/AND/XOR/OR/CP
    alu_ops = ["ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR", "CP"]
    alu_regs = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
    for i in range(0x80, 0xC0):
        alu_idx = (i >> 3) & 7
        reg_idx = i & 7
        main_op[i] = (alu_ops[alu_idx], alu_regs[reg_idx], 1)
    # 0xC0-0xFF: RET/POP/JP/CALL/RST/PUSH/IN/OUT
    # RET cc
    ret_cc = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
    for i, cc in enumerate(ret_cc):
        main_op[0xC0 + i] = ("RET", cc, 1)
    # POP
    pop_regs = ["BC", "DE", "HL", "AF"]
    for i, r in enumerate(pop_regs):
        main_op[0xC1 + i*0x10] = ("POP", r, 1)
    # JP cc
    for i, cc in enumerate(ret_cc):
        main_op[0xC2 + i*0x10] = ("JP", f"{cc},$+2", 3) if i < 4 else ("JP", f"{cc},$+2", 3)
    main_op[0xC2] = ("JP", "NZ,$+2", 3)
    main_op[0xC3] = ("JP", "$+2", 3)
    main_op[0xCA] = ("JP", "Z,$+2", 3)
    main_op[0xD2] = ("JP", "NC,$+2", 3)
    main_op[0xDA] = ("JP", "C,$+2", 3)
    main_op[0xE2] = ("JP", "PO,$+2", 3)
    main_op[0xEA] = ("JP", "PE,$+2", 3)
    main_op[0xF2] = ("JP", "P,$+2", 3)
    main_op[0xFA] = ("JP", "M,$+2", 3)
    # CALL cc
    main_op[0xC4] = ("CALL", "NZ,$+2", 3)
    main_op[0xCC] = ("CALL", "Z,$+2", 3)
    main_op[0xD4] = ("CALL", "NC,$+2", 3)
    main_op[0xDC] = ("CALL", "C,$+2", 3)
    main_op[0xE4] = ("CALL", "PO,$+2", 3)
    main_op[0xEC] = ("CALL", "PE,$+2", 3)
    main_op[0xF4] = ("CALL", "P,$+2", 3)
    main_op[0xFC] = ("CALL", "M,$+2", 3)
    main_op[0xCD] = ("CALL", "$+2", 3)
    # RST
    rst_addrs = [0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38]
    for i, addr in enumerate(rst_addrs):
        main_op[0xC7 + i*0x08] = ("RST", f"${addr:02X}", 1)
    # PUSH
    for i, r in enumerate(pop_regs):
        main_op[0xC5 + i*0x10] = ("PUSH", r, 1)
    main_op[0xC6] = ("ADD", "A,$+1", 2)   # ADD A,n
    main_op[0xCE] = ("ADC", "A,$+1", 2)
    main_op[0xD6] = ("SUB", "$+1", 2)
    main_op[0xDE] = ("SBC", "A,$+1", 2)
    main_op[0xE6] = ("AND", "$+1", 2)
    main_op[0xEE] = ("XOR", "$+1", 2)
    main_op[0xF6] = ("OR", "$+1", 2)
    main_op[0xFE] = ("CP", "$+1", 2)
    main_op[0xCF] = ("RST", "$08", 1)
    main_op[0xD7] = ("RST", "$10", 1)
    main_op[0xDF] = ("RST", "$18", 1)
    main_op[0xE7] = ("RST", "$20", 1)
    main_op[0xEF] = ("RST", "$28", 1)
    main_op[0xF7] = ("RST", "$30", 1)
    main_op[0xFF] = ("RST", "$38", 1)
    # Misc
    main_op[0xC9] = ("RET", "", 1)
    main_op[0xD3] = ("OUT", "($+1),A", 2)
    main_op[0xD9] = ("EXX", "", 1)
    main_op[0xDB] = ("IN", "A,($+1)", 2)
    main_op[0xE3] = ("EX", "(SP),HL", 1)
    main_op[0xE5] = ("PUSH", "HL", 1)
    main_op[0xE9] = ("JP", "(HL)", 1)
    main_op[0xEB] = ("EX", "DE,HL", 1)
    main_op[0xED] = ("PREFIX_ED", "", 1)
    main_op[0xF3] = ("DI", "", 1)
    main_op[0xF5] = ("PUSH", "AF", 1)
    main_op[0xF9] = ("LD", "SP,HL", 1)
    main_op[0xFB] = ("EI", "", 1)
    main_op[0xDD] = ("PREFIX_DD", "", 1)
    main_op[0xFD] = ("PREFIX_FD", "", 1)
    main_op[0xCB] = ("PREFIX_CB", "", 1)

# ED prefix opcodes
ed_op = {}
ed_op[0x40] = ("IN", "B,(C)", 1)
ed_op[0x41] = ("OUT", "(C),B", 1)
ed_op[0x42] = ("SBC", "HL,BC", 1)
ed_op[0x43] = ("LD", "($+2),BC", 3)
ed_op[0x44] = ("NEG", "", 1)
ed_op[0x45] = ("RETN", "", 1)
ed_op[0x46] = ("IM", "0", 1)
ed_op[0x47] = ("LD", "I,A", 1)
ed_op[0x48] = ("IN", "C,(C)", 1)
ed_op[0x49] = ("OUT", "(C),C", 1)
ed_op[0x4A] = ("ADC", "HL,BC", 1)
ed_op[0x4B] = ("LD", "BC,($+2)", 3)
ed_op[0x4D] = ("RETI", "", 1)
ed_op[0x4F] = ("LD", "R,A", 1)
ed_op[0x50] = ("IN", "D,(C)", 1)
ed_op[0x51] = ("OUT", "(C),D", 1)
ed_op[0x52] = ("SBC", "HL,DE", 1)
ed_op[0x53] = ("LD", "($+2),DE", 3)
ed_op[0x56] = ("IM", "1", 1)
ed_op[0x57] = ("LD", "A,I", 1)
ed_op[0x58] = ("IN", "E,(C)", 1)
ed_op[0x59] = ("OUT", "(C),E", 1)
ed_op[0x5A] = ("ADC", "HL,DE", 1)
ed_op[0x5B] = ("LD", "DE,($+2)", 3)
ed_op[0x5E] = ("IM", "2", 1)
ed_op[0x5F] = ("LD", "A,R", 1)
ed_op[0x60] = ("IN", "H,(C)", 1)
ed_op[0x61] = ("OUT", "(C),H", 1)
ed_op[0x62] = ("SBC", "HL,HL", 1)
ed_op[0x63] = ("LD", "($+2),HL", 3)
ed_op[0x67] = ("RRD", "", 1)
ed_op[0x68] = ("IN", "L,(C)", 1)
ed_op[0x69] = ("OUT", "(C),L", 1)
ed_op[0x6A] = ("ADC", "HL,HL", 1)
ed_op[0x6B] = ("LD", "HL,($+2)", 3)
ed_op[0x6F] = ("RLD", "", 1)
ed_op[0x72] = ("SBC", "HL,SP", 1)
ed_op[0x73] = ("LD", "($+2),SP", 3)
ed_op[0x78] = ("IN", "A,(C)", 1)
ed_op[0x79] = ("OUT", "(C),A", 1)
ed_op[0x7A] = ("ADC", "HL,SP", 1)
ed_op[0x7B] = ("LD", "SP,($+2)", 3)
# Block transfer
ed_op[0xA0] = ("LDI", "", 1)
ed_op[0xA1] = ("CPI", "", 1)
ed_op[0xA2] = ("INI", "", 1)
ed_op[0xA3] = ("OUTI", "", 1)
ed_op[0xA8] = ("LDD", "", 1)
ed_op[0xA9] = ("CPD", "", 1)
ed_op[0xB0] = ("LDIR", "", 1)
ed_op[0xB1] = ("CPIR", "", 1)
ed_op[0xB8] = ("LDDR", "", 1)
ed_op[0xB9] = ("CPDR", "", 1)

# CB prefix opcodes
cb_op = {}
cb_rot = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SLL", "SRL"]
cb_regs = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
for i in range(0x00, 0x100):
    if i < 0x40:
        op_idx = i >> 3
        reg_idx = i & 7
        cb_op[i] = (cb_rot[op_idx], cb_regs[reg_idx], 1)
    elif i < 0x80:
        bit = (i >> 3) & 7
        reg_idx = i & 7
        cb_op[i] = ("BIT", f"{bit},{cb_regs[reg_idx]}", 1)
    elif i < 0xC0:
        bit = (i >> 3) & 7
        reg_idx = i & 7
        cb_op[i] = ("RES", f"{bit},{cb_regs[reg_idx]}", 1)
    else:
        bit = (i >> 3) & 7
        reg_idx = i & 7
        cb_op[i] = ("SET", f"{bit},{cb_regs[reg_idx]}", 1)

def disasm_one(data, offset, org=0):
    """Disassemble one Z80 instruction at given offset in data.
    Returns (mnemonic, operands, length) or None on error.
    """
    if offset >= len(data):
        return None
    b = data[offset]
    
    if b == 0xED:
        if offset + 1 >= len(data):
            return ("DB", f"${b:02x}", 1)
        ed_b = data[offset + 1]
        if ed_b in ed_op:
            mne, ops, elen = ed_op[ed_b]
            if "$+2" in ops:
                if offset + 3 >= len(data):
                    return ("DB", f"$ED ${ed_b:02x}", 2)
                addr = struct.unpack_from("<H", data, offset + 2)[0]
                ops = ops.replace("$+2", f"${addr:04X}")
                return (mne, ops, 4)
            elif "$+1" in ops:
                if offset + 2 >= len(data):
                    return ("DB", f"$ED ${ed_b:02x}", 2)
                val = data[offset + 2]
                ops = ops.replace("$+1", f"${val:02X}")
                return (mne, ops, 3)
            else:
                return (mne, ops, 2)
        else:
            return ("DB", f"$ED ${ed_b:02x}", 2)
    
    elif b == 0xCB:
        if offset + 1 >= len(data):
            return ("DB", f"$CB", 1)
        cb_b = data[offset + 1]
        if cb_b in cb_op:
            mne, ops, _ = cb_op[cb_b]
            return (mne, ops, 2)
        else:
            return ("DB", f"$CB ${cb_b:02x}", 2)
    
    elif b == 0xDD:
        # IX prefix
        if offset + 1 >= len(data):
            return ("DB", f"$DD", 1)
        dd_b = data[offset + 1]
        if dd_b == 0xCB:
            # DD CB dd op
            if offset + 4 >= len(data):
                return ("DB", "$DD $CB", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            op_b = data[offset + 3]
            dd_cb_ops = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SLL", "SRL"]
            op_idx = op_b >> 3
            bit = (op_b >> 3) & 7
            reg_idx = op_b & 7
            regs = ["B", "C", "D", "E", "H", "L", "(IX+$)", "A"]
            if op_idx < 8:
                dst = regs[reg_idx].replace("(IX+$)", f"(IX+${disp&0xFF:02X})")
                ops = f"{dst}"
                return (dd_cb_ops[op_idx], ops, 4)
            elif op_idx < 16:
                dst = regs[reg_idx].replace("(IX+$)", f"(IX+${disp&0xFF:02X})")
                return ("BIT", f"{bit},{dst}", 4)
            elif op_idx < 24:
                dst = regs[reg_idx].replace("(IX+$)", f"(IX+${disp&0xFF:02X})")
                return ("RES", f"{bit},{dst}", 4)
            else:
                dst = regs[reg_idx].replace("(IX+$)", f"(IX+${disp&0xFF:02X})")
                return ("SET", f"{bit},{dst}", 4)
        if dd_b == 0x21:
            if offset + 3 >= len(data):
                return ("DB", "$DD $21", 2)
            addr = struct.unpack_from("<H", data, offset + 2)[0]
            return ("LD", f"IX,${addr:04X}", 4)
        if dd_b == 0x22:
            if offset + 3 >= len(data):
                return ("DB", "$DD $22", 2)
            addr = struct.unpack_from("<H", data, offset + 2)[0]
            return ("LD", f"(${addr:04X}),IX", 4)
        if dd_b == 0x2A:
            if offset + 3 >= len(data):
                return ("DB", "$DD $2A", 2)
            addr = struct.unpack_from("<H", data, offset + 2)[0]
            return ("LD", f"IX,(${addr:04X})", 4)
        if dd_b == 0x36:
            if offset + 3 >= len(data):
                return ("DB", "$DD $36", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            val = data[offset + 3]
            return ("LD", f"(IX+${disp&0xFF:02X}),${val:02X}", 4)
        if dd_b == 0xE5:
            return ("PUSH", "IX", 2)
        if dd_b == 0xE1:
            return ("POP", "IX", 2)
        if dd_b == 0xE9:
            return ("JP", "(IX)", 2)
        if dd_b == 0x23:
            return ("INC", "IX", 2)
        if dd_b == 0x2B:
            return ("DEC", "IX", 2)
        if dd_b == 0x09:
            return ("ADD", "IX,BC", 2)
        if dd_b == 0x19:
            return ("ADD", "IX,DE", 2)
        if dd_b == 0x29:
            return ("ADD", "IX,IX", 2)
        if dd_b == 0x39:
            return ("ADD", "IX,SP", 2)
        if dd_b == 0x7C:
            return ("LD", "A,IXH", 2)
        if dd_b == 0x7D:
            return ("LD", "A,IXL", 2)
        if dd_b == 0x67:
            return ("LD", "IXH,A", 2)
        if dd_b == 0x6F:
            return ("LD", "IXL,A", 2)
        if dd_b == 0x84:
            return ("ADD", "A,IXH", 2)
        if dd_b == 0x85:
            return ("ADD", "A,IXL", 2)
        if dd_b == 0x94:
            return ("SUB", "IXH", 2)
        if dd_b == 0x95:
            return ("SUB", "IXL", 2)
        if dd_b == 0x26:
            if offset + 2 >= len(data):
                return ("DB", "$DD $26", 2)
            return ("LD", f"IXH,${data[offset+2]:02X}", 3)
        if dd_b == 0x2E:
            if offset + 2 >= len(data):
                return ("DB", "$DD $2E", 2)
            return ("LD", f"IXL,${data[offset+2]:02X}", 3)
        # DD with displacement (LD, INC, DEC for (IX+d))
        if dd_b in [0x34, 0x35, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x77]:
            if offset + 2 >= len(data):
                return ("DB", f"$DD ${dd_b:02x}", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            dstr = f"IX+${disp&0xFF:02X}"
            ld_regs_ix = ["B","C","D","E","H","L","(IX+d)","A"]
            if dd_b == 0x34:
                return ("INC", f"({dstr})", 3)
            elif dd_b == 0x35:
                return ("DEC", f"({dstr})", 3)
            elif 0x70 <= dd_b <= 0x77:
                r = ld_regs_ix[dd_b - 0x70]
                return ("LD", f"({dstr}),{r}", 3)
        # DD LD r,(IX+d) and LD (IX+d),r
        if 0x46 <= dd_b <= 0x7E and ((dd_b & 7) == 6 or ((dd_b >> 3) & 7) == 6):
            if offset + 2 >= len(data):
                return ("DB", f"$DD ${dd_b:02x}", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            dstr = f"IX+${disp&0xFF:02X}"
            ld_regs2 = ["B","C","D","E","H","L","(HL)","A"]
            dst = ld_regs2[(dd_b >> 3) & 7]
            src = ld_regs2[dd_b & 7]
            if dst == "(HL)":
                dst = f"({dstr})"
            if src == "(HL)":
                src = f"({dstr})"
            return ("LD", f"{dst},{src}", 3)
        # DD IN(C) / OUT(C) variants
        if dd_b == 0x7E:
            if offset + 2 >= len(data):
                return ("DB", "$DD $7E", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            return ("LD", f"A,(IX+${disp&0xFF:02X})", 3)
        if dd_b == 0x77:
            if offset + 2 >= len(data):
                return ("DB", "$DD $77", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            return ("LD", f"(IX+${disp&0xFF:02X}),A", 3)
        
        return ("DB", f"$DD ${dd_b:02x}", 2)
    
    elif b == 0xFD:
        # IY prefix - similar to IX
        if offset + 1 >= len(data):
            return ("DB", f"$FD", 1)
        fd_b = data[offset + 1]
        if fd_b == 0xCB:
            if offset + 4 >= len(data):
                return ("DB", "$FD $CB", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            op_b = data[offset + 3]
            return ("DD_CB", f"(IY+${disp&0xFF:02X}),${op_b:02x}", 4)
        if fd_b in [0x21, 0x22, 0x2A, 0x36, 0xE5, 0xE1, 0xE9, 0x23, 0x2B, 0x09, 0x19, 0x29, 0x39]:
            return handle_iy(fd_b, data, offset)
        if fd_b == 0x7E:
            if offset + 2 >= len(data):
                return ("DB", "$FD $7E", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            return ("LD", f"A,(IY+${disp&0xFF:02X})", 3)
        if fd_b == 0x77:
            if offset + 2 >= len(data):
                return ("DB", "$FD $77", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            return ("LD", f"(IY+${disp&0xFF:02X}),A", 3)
        # IY LD r,(IY+d) and LD (IY+d),r
        if 0x46 <= fd_b <= 0x7E and ((fd_b & 7) == 6 or ((fd_b >> 3) & 7) == 6):
            if offset + 2 >= len(data):
                return ("DB", f"$FD ${fd_b:02x}", 2)
            disp = struct.unpack_from("<b", data, offset + 2)[0]
            dstr = f"IY+${disp&0xFF:02X}"
            ld_regs_fd = ["B","C","D","E","H","L","(HL)","A"]
            dst = ld_regs_fd[(fd_b >> 3) & 7]
            src = ld_regs_fd[fd_b & 7]
            if dst == "(HL)": dst = f"({dstr})"
            if src == "(HL)": src = f"({dstr})"
            return ("LD", f"{dst},{src}", 3)
        return ("DB", f"$FD ${fd_b:02x}", 2)
    
    if b in main_op:
        mne, ops, length = main_op[b]
        if mne in ("JR", "DJNZ"):
            if offset + 1 >= len(data):
                return ("DB", f"${b:02x}", 1)
            disp = struct.unpack_from("<b", data, offset + 1)[0]
            target = org + offset + 2 + disp
            cond = ops.split(",")[0] if "," in ops else ""
            if cond:
                return (mne, f"{cond},${target:04X}", 2)
            else:
                return (mne, f"${target:04X}", 2)
        elif "$+2" in ops:
            if offset + 2 >= len(data):
                return ("DB", f"${b:02x}", 1)
            addr = struct.unpack_from("<H", data, offset + 1)[0]
            ops = ops.replace("$+2", f"${addr:04X}")
            return (mne, ops, 3)
        elif "$+1" in ops:
            if offset + 1 >= len(data):
                return ("DB", f"${b:02x}", 1)
            val = data[offset + 1]
            ops = ops.replace("$+1", f"${val:02X}")
            return (mne, ops, 2)
        else:
            return (mne, ops, length)
    else:
        return ("DB", f"${b:02x}", 1)

def handle_iy(fd_b, data, offset):
    suffixes = {
        0x21: ("LD", "IY,$+2", 4, "IY"),
        0x22: ("LD", "($+2),IY", 4, None),
        0x2A: ("LD", "IY,($+2)", 4, "IY"),
        0x36: ("LD", "(IY+$+1),$+2", 4, None),
        0x23: ("INC", "IY", 2, None),
        0x2B: ("DEC", "IY", 2, None),
        0x09: ("ADD", "IY,BC", 2, None),
        0x19: ("ADD", "IY,DE", 2, None),
        0x29: ("ADD", "IY,IY", 2, None),
        0x39: ("ADD", "IY,SP", 2, None),
        0xE5: ("PUSH", "IY", 2, None),
        0xE1: ("POP", "IY", 2, None),
        0xE9: ("JP", "(IY)", 2, None),
    }
    if fd_b == 0x36:
        if offset + 3 >= len(data):
            return ("DB", "$FD $36", 2)
        disp = struct.unpack_from("<b", data, offset + 2)[0]
        val = data[offset + 3]
        return ("LD", f"(IY+${disp&0xFF:02X}),${val:02X}", 4)
    if fd_b in suffixes:
        mne, ops, length, _ = suffixes[fd_b]
        if "$+2" in ops:
            if offset + 2 >= len(data):
                return ("DB", f"$FD ${fd_b:02x}", 2)
            addr = struct.unpack_from("<H", data, offset + 2)[0]
            ops = ops.replace("$+2", f"${addr:04X}")
            return (mne, ops, 4)
        if "$+1" in ops:
            return ("DB", f"$FD ${fd_b:02x}", 2)
        return (mne, ops, 2)
    return ("DB", f"$FD ${fd_b:02x}", 2)

def disasm_range(data, start_offset, end_offset, org=0, show_addr=True):
    """Disassemble a range of bytes."""
    offset = start_offset
    result = []
    while offset < end_offset and offset < len(data):
        instr = disasm_one(data, offset, org)
        if instr is None:
            break
        mne, ops, length = instr
        addr = org + offset if org else offset
        if show_addr:
            line = f"${addr:04X}  {data[offset:offset+length].hex().ljust(12)}  {mne} {ops}"
        else:
            line = f"  {data[offset:offset+length].hex().ljust(12)}  {mne} {ops}"
        result.append((addr, line, length))
        offset += length
    return result

def find_code_blocks(data, org=0):
    """Try to find code by looking for common patterns."""
    blocks = []
    i = 0
    while i < len(data) - 2:
        b = data[i]
        # Look for CALL, JP, JR targets or start of code
        if b == 0xCD:  # CALL
            addr = struct.unpack_from("<H", data, i+1)[0]
            blocks.append(addr)
        elif b == 0xC3:  # JP
            addr = struct.unpack_from("<H", data, i+1)[0]
            blocks.append(addr)
        elif b == 0x18:  # JR
            disp = struct.unpack_from("<b", data, i+1)[0]
            blocks.append(org + i + 2 + disp)
        elif b in [0x20, 0x28, 0x30, 0x38]:  # JR cc
            disp = struct.unpack_from("<b", data, i+1)[0]
            blocks.append(org + i + 2 + disp)
        i += 1
    return sorted(set(b for b in blocks if b >= org and b < org + len(data)))

if __name__ == "__main__":
    init()
    import os
    
    # Analyze the loader code (block 3, loaded at 0x6000)
    files_to_analyze = [
        ("Loader (block 3 @ 0x6000)", "/root/ghidra/extracted_block_3.bin", 0x6000),
        ("Block 4 (@ 0x8000?)", "/root/ghidra/extracted_block_4.bin", 0x8000),
        ("Block 5 (@ ?)", "/root/ghidra/extracted_block_5.bin", 0x0000),
        ("Block 6 (@ 0xA000?)", "/root/ghidra/extracted_block_6.bin", 0xA000),
    ]
    
    for name, path, org in files_to_analyze:
        if not os.path.exists(path):
            print(f"\n*** {name}: file not found")
            continue
        with open(path, "rb") as f:
            d = f.read()
        print(f"\n{'='*60}")
        print(f"*** {name} ({len(d)} bytes) @ {org:#06x} ***")
        print(f"{'='*60}")
        
        # Disassemble first 128 bytes
        output = disasm_range(d, 0, min(128, len(d)), org)
        for addr, line, length in output:
            print(line)