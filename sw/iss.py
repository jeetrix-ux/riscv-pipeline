#!/usr/bin/env python3
"""iss.py - tiny RV32I instruction-set simulator (golden model).

Executes the same program.hex the RTL runs and emits the final
architectural state in the testbench's expected-state format
(40 words: x0..x31 then dmem words 0..7), so the RTL can be checked
against an independent model instead of hand-written expectations.

Memory semantics deliberately mirror the RTL (word-indexed dmem,
sub-word access via shift + byte strobes) so the two can only disagree
when one of them is actually wrong.

Usage:
    python iss.py prog.hex -o golden.exp      # write final state
    python iss.py prog.hex --check hand.exp   # diff against a hand-written
                                              # .exp ('x' words are skipped)
"""
import argparse
import sys

MASK = 0xFFFFFFFF
DMEM_WORDS = 4096


def s32(v):
    """Interpret a 32-bit value as signed."""
    return v - 0x100000000 if v & 0x80000000 else v


def sext(v, bits):
    """Sign-extend a bits-wide value to Python int."""
    if v & (1 << (bits - 1)):
        v -= 1 << bits
    return v


class IssError(Exception):
    pass


def load_hex(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].split("#")[0].strip()
            if line:
                words.append(int(line, 16))
    return words


def run(prog, max_steps=200000):
    regs = [0] * 32
    dmem = [0] * DMEM_WORDS
    pc = 0

    for _ in range(max_steps):
        if pc & 3:
            raise IssError("misaligned pc 0x%08x" % pc)
        idx = pc >> 2
        if idx >= len(prog):
            raise IssError("pc 0x%08x ran past the program" % pc)
        instr = prog[idx]

        opc = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        f3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        f7 = (instr >> 25) & 0x7F

        imm_i = sext(instr >> 20, 12)
        imm_s = sext(((instr >> 25) << 5) | rd, 12)
        imm_b = sext((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11)
                     | (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
        imm_u = instr & 0xFFFFF000
        imm_j = sext((((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12)
                     | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21)

        a = regs[rs1]
        b = regs[rs2]
        next_pc = (pc + 4) & MASK
        wval = None

        if opc == 0b0110111:                       # lui
            wval = imm_u
        elif opc == 0b0010111:                     # auipc
            wval = (pc + imm_u) & MASK
        elif opc == 0b1101111:                     # jal
            wval = next_pc
            next_pc = (pc + imm_j) & MASK
        elif opc == 0b1100111:                     # jalr
            wval = next_pc
            next_pc = (a + imm_i) & MASK & ~1
        elif opc == 0b1100011:                     # branches
            taken = {
                0b000: a == b,
                0b001: a != b,
                0b100: s32(a) < s32(b),
                0b101: s32(a) >= s32(b),
                0b110: a < b,
                0b111: a >= b,
            }.get(f3)
            if taken is None:
                raise IssError("bad branch funct3 %d at pc 0x%08x" % (f3, pc))
            if taken:
                next_pc = (pc + imm_b) & MASK
        elif opc == 0b0000011:                     # loads (RTL-style shift)
            addr = (a + imm_i) & MASK
            word = dmem[(addr >> 2) % DMEM_WORDS]
            shifted = (word >> (8 * (addr & 3))) & MASK
            if f3 == 0b000:   wval = sext(shifted & 0xFF, 8) & MASK    # lb
            elif f3 == 0b001: wval = sext(shifted & 0xFFFF, 16) & MASK # lh
            elif f3 == 0b010: wval = shifted                           # lw
            elif f3 == 0b100: wval = shifted & 0xFF                    # lbu
            elif f3 == 0b101: wval = shifted & 0xFFFF                  # lhu
            else:
                raise IssError("bad load funct3 %d at pc 0x%08x" % (f3, pc))
        elif opc == 0b0100011:                     # stores (RTL-style strobes)
            addr = (a + imm_s) & MASK
            widx = (addr >> 2) % DMEM_WORDS
            wdata = (b << (8 * (addr & 3))) & MASK
            strb = {0b000: 0b0001, 0b001: 0b0011, 0b010: 0b1111}.get(f3)
            if strb is None:
                raise IssError("bad store funct3 %d at pc 0x%08x" % (f3, pc))
            strb = (strb << (addr & 3)) & 0xF
            word = dmem[widx]
            for lane in range(4):
                if strb & (1 << lane):
                    m = 0xFF << (8 * lane)
                    word = (word & ~m) | (wdata & m)
            dmem[widx] = word & MASK
        elif opc in (0b0010011, 0b0110011):        # op-imm / op
            if opc == 0b0010011:
                b = imm_i & MASK
                sub_sra = (f3 == 0b101) and (instr >> 30) & 1  # srai
            else:
                sub_sra = (instr >> 30) & 1                    # sub/sra
            sh = b & 31
            if f3 == 0b000:
                wval = (a - b if (sub_sra and opc == 0b0110011) else a + b) & MASK
            elif f3 == 0b001: wval = (a << sh) & MASK
            elif f3 == 0b010: wval = 1 if s32(a) < s32(b) else 0
            elif f3 == 0b011: wval = 1 if a < (b & MASK) else 0
            elif f3 == 0b100: wval = a ^ (b & MASK)
            elif f3 == 0b101: wval = (s32(a) >> sh) & MASK if sub_sra else a >> sh
            elif f3 == 0b110: wval = a | (b & MASK)
            else:             wval = a & (b & MASK)
        elif opc == 0b0001111:                     # fence: nop
            pass
        elif opc == 0b1110011:                     # ecall/ebreak: halt
            return regs, dmem
        else:
            raise IssError("unknown opcode 0x%02x at pc 0x%08x" % (opc, pc))

        if wval is not None and rd != 0:
            regs[rd] = wval & MASK
        pc = next_pc

    raise IssError("no halt after %d steps" % max_steps)


def state_words(regs, dmem):
    return regs + dmem[0:8]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hex", help="program hex (one 32-bit word per line)")
    ap.add_argument("-o", "--out", help="write final state as a 40-word .exp file")
    ap.add_argument("--check", help="compare final state against a .exp file "
                                    "(words containing x are skipped)")
    args = ap.parse_args()

    try:
        regs, dmem = run(load_hex(args.hex))
    except IssError as e:
        print("iss: ERROR: %s" % e, file=sys.stderr)
        return 1

    words = state_words(regs, dmem)

    if args.out:
        with open(args.out, "w") as f:
            f.write("// golden state from iss.py: x0..x31 then dmem words 0..7\n")
            for w in words:
                f.write("%08x\n" % w)

    if args.check:
        names = ["x%d" % i for i in range(32)] + ["mem[%d]" % i for i in range(8)]
        bad = 0
        with open(args.check) as f:
            exp = [l.split("//")[0].strip() for l in f]
            exp = [l for l in exp if l]
        for i, (got, want) in enumerate(zip(words, exp)):
            if "x" in want.lower():
                continue
            if got != int(want, 16):
                print("iss: MISMATCH %s: iss=%08x exp=%s" % (names[i], got, want),
                      file=sys.stderr)
                bad += 1
        if bad:
            return 1
        print("iss: state matches %s" % args.check)

    return 0


if __name__ == "__main__":
    sys.exit(main())
