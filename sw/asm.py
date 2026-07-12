#!/usr/bin/env python3
"""asm.py - minimal RV32I assembler for the pipelined core project.

Usage:
    python asm.py input.s -o output.hex [-l listing.txt]

Supports the full RV32I base ISA, labels, common pseudo-instructions
(nop, li, mv, j, jr, ret, beqz, bnez), the .word directive, and
'#' / '//' comments. Output is one 32-bit hex word per line, suitable
for Verilog $readmemh.
"""
import argparse
import re
import sys


class AsmError(Exception):
    def __init__(self, msg, line_no=None, text=None):
        loc = f" (line {line_no}: '{text}')" if line_no else ""
        super().__init__(msg + loc)


# ---------------------------------------------------------------- registers
REGS = {f"x{i}": i for i in range(32)}
_ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
        "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
        "t3", "t4", "t5", "t6"]
REGS.update({n: i for i, n in enumerate(_ABI)})
REGS["fp"] = 8

# ------------------------------------------------------------- opcode tables
R_OPS = {"add": (0b000, 0), "sub": (0b000, 0b0100000), "sll": (0b001, 0),
         "slt": (0b010, 0), "sltu": (0b011, 0), "xor": (0b100, 0),
         "srl": (0b101, 0), "sra": (0b101, 0b0100000), "or": (0b110, 0),
         "and": (0b111, 0)}
I_OPS = {"addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
         "ori": 0b110, "andi": 0b111}
SHIFT_OPS = {"slli": (0b001, 0), "srli": (0b101, 0), "srai": (0b101, 0b0100000)}
LOAD_OPS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORE_OPS = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCH_OPS = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101,
              "bltu": 0b110, "bgeu": 0b111}

MEM_RE = re.compile(r"^(-?[0-9a-fA-FxX]+)\s*\(\s*(\w+)\s*\)$")


def reg(tok, ln=None, txt=None):
    t = tok.strip().lower()
    if t not in REGS:
        raise AsmError(f"unknown register '{tok}'", ln, txt)
    return REGS[t]


def parse_int(tok, ln=None, txt=None):
    try:
        return int(tok.strip(), 0)
    except ValueError:
        raise AsmError(f"bad integer '{tok}'", ln, txt)


# ------------------------------------------------------------------ encoders
def enc_r(f7, rs2, rs1, f3, rd):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0110011


def enc_i(imm, rs1, f3, rd, opc, ln=None, txt=None):
    if not (-2048 <= imm <= 4095):
        raise AsmError(f"I-immediate {imm} out of range", ln, txt)
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_s(imm, rs2, rs1, f3, ln=None, txt=None):
    if not (-2048 <= imm <= 2047):
        raise AsmError(f"S-immediate {imm} out of range", ln, txt)
    i = imm & 0xFFF
    return ((i >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((i & 0x1F) << 7) | 0b0100011


def enc_b(off, rs2, rs1, f3, ln=None, txt=None):
    if off % 2 or not (-4096 <= off <= 4094):
        raise AsmError(f"branch offset {off} invalid", ln, txt)
    i = off & 0x1FFF
    return (((i >> 12) & 1) << 31) | (((i >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((i >> 1) & 0xF) << 8) | (((i >> 11) & 1) << 7) | 0b1100011


def enc_u(imm20, rd, opc, ln=None, txt=None):
    if not (-(1 << 19) <= imm20 <= 0xFFFFF):
        raise AsmError(f"U-immediate {imm20} out of range", ln, txt)
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc


def enc_j(off, rd, ln=None, txt=None):
    if off % 2 or not (-(1 << 20) <= off <= (1 << 20) - 2):
        raise AsmError(f"jump offset {off} invalid", ln, txt)
    i = off & 0x1FFFFF
    return (((i >> 20) & 1) << 31) | (((i >> 1) & 0x3FF) << 21) | \
           (((i >> 11) & 1) << 20) | (((i >> 12) & 0xFF) << 12) | (rd << 7) | 0b1101111


def li_parts(val):
    """Split a 32-bit value into (hi20, lo12) for lui+addi."""
    val &= 0xFFFFFFFF
    lo = val & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((val - lo) >> 12) & 0xFFFFF
    return hi, lo


# ---------------------------------------------------------------- first pass
def expand(mnem, ops, ln, txt):
    """Expand one source statement into concrete instructions (pseudo-ops
    become 1-2 real instructions). Returns a list of (mnem, ops) tuples."""
    m = mnem.lower()
    if m == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if m == "mv":
        return [("addi", [ops[0], ops[1], "0"])]
    if m == "li":
        val = parse_int(ops[1], ln, txt)
        if -2048 <= val <= 2047:
            return [("addi", [ops[0], "x0", str(val)])]
        hi, lo = li_parts(val)
        out = [("lui", [ops[0], str(hi)])]
        if lo != 0:
            out.append(("addi", [ops[0], ops[0], str(lo)]))
        return out
    if m == "j":
        return [("jal", ["x0", ops[0]])]
    if m == "jal" and len(ops) == 1:
        return [("jal", ["ra", ops[0]])]
    if m == "jr":
        return [("jalr", ["x0", ops[0], "0"])]
    if m == "ret":
        return [("jalr", ["x0", "ra", "0"])]
    if m == "beqz":
        return [("beq", [ops[0], "x0", ops[1]])]
    if m == "bnez":
        return [("bne", [ops[0], "x0", ops[1]])]
    return [(m, ops)]


def parse_source(path):
    """Pass 1: tokenize, expand pseudo-ops, assign addresses, collect labels."""
    labels = {}
    prog = []  # (addr, mnem, ops, line_no, source_text)
    addr = 0
    with open(path) as f:
        for ln, raw in enumerate(f, 1):
            line = raw.split("#")[0].split("//")[0].strip()
            while True:
                m = re.match(r"^(\w+)\s*:\s*(.*)$", line)
                if not m:
                    break
                label = m.group(1)
                if label in labels:
                    raise AsmError(f"duplicate label '{label}'", ln, raw.strip())
                labels[label] = addr
                line = m.group(2).strip()
            if not line:
                continue
            if line.startswith("."):
                parts = line.split(None, 1)
                if parts[0] == ".word":
                    prog.append((addr, ".word", [parts[1].strip()], ln, line))
                    addr += 4
                # .text/.globl/.align/.section etc. are ignored
                continue
            parts = line.split(None, 1)
            mnem = parts[0]
            ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
            for em, eo in expand(mnem, ops, ln, line):
                prog.append((addr, em, eo, ln, line))
                addr += 4
    return prog, labels


# --------------------------------------------------------------- second pass
def encode(addr, mnem, ops, labels, ln, txt):
    def branch_off(tok):
        if tok in labels:
            return labels[tok] - addr
        return parse_int(tok, ln, txt)

    if mnem == ".word":
        return parse_int(ops[0], ln, txt) & 0xFFFFFFFF
    if mnem in R_OPS:
        f3, f7 = R_OPS[mnem]
        return enc_r(f7, reg(ops[2], ln, txt), reg(ops[1], ln, txt), f3, reg(ops[0], ln, txt))
    if mnem in I_OPS:
        return enc_i(parse_int(ops[2], ln, txt), reg(ops[1], ln, txt),
                     I_OPS[mnem], reg(ops[0], ln, txt), 0b0010011, ln, txt)
    if mnem in SHIFT_OPS:
        f3, f7 = SHIFT_OPS[mnem]
        shamt = parse_int(ops[2], ln, txt)
        if not (0 <= shamt <= 31):
            raise AsmError(f"shift amount {shamt} out of range", ln, txt)
        return enc_i((f7 << 5) | shamt, reg(ops[1], ln, txt), f3,
                     reg(ops[0], ln, txt), 0b0010011, ln, txt)
    if mnem in LOAD_OPS:
        m = MEM_RE.match(ops[1])
        if not m:
            raise AsmError("expected 'offset(reg)' operand", ln, txt)
        return enc_i(parse_int(m.group(1), ln, txt), reg(m.group(2), ln, txt),
                     LOAD_OPS[mnem], reg(ops[0], ln, txt), 0b0000011, ln, txt)
    if mnem in STORE_OPS:
        m = MEM_RE.match(ops[1])
        if not m:
            raise AsmError("expected 'offset(reg)' operand", ln, txt)
        return enc_s(parse_int(m.group(1), ln, txt), reg(ops[0], ln, txt),
                     reg(m.group(2), ln, txt), STORE_OPS[mnem], ln, txt)
    if mnem in BRANCH_OPS:
        return enc_b(branch_off(ops[2]), reg(ops[1], ln, txt),
                     reg(ops[0], ln, txt), BRANCH_OPS[mnem], ln, txt)
    if mnem == "lui":
        return enc_u(parse_int(ops[1], ln, txt), reg(ops[0], ln, txt), 0b0110111, ln, txt)
    if mnem == "auipc":
        return enc_u(parse_int(ops[1], ln, txt), reg(ops[0], ln, txt), 0b0010111, ln, txt)
    if mnem == "jal":
        return enc_j(branch_off(ops[1]), reg(ops[0], ln, txt), ln, txt)
    if mnem == "jalr":
        if len(ops) == 3:
            return enc_i(parse_int(ops[2], ln, txt), reg(ops[1], ln, txt),
                         0, reg(ops[0], ln, txt), 0b1100111, ln, txt)
        m = MEM_RE.match(ops[1])
        if not m:
            raise AsmError("expected 'jalr rd, rs, imm' or 'jalr rd, imm(rs)'", ln, txt)
        return enc_i(parse_int(m.group(1), ln, txt), reg(m.group(2), ln, txt),
                     0, reg(ops[0], ln, txt), 0b1100111, ln, txt)
    if mnem == "ecall":
        return 0x00000073
    if mnem == "ebreak":
        return 0x00100073
    if mnem == "fence":
        return 0x0FF0000F
    raise AsmError(f"unknown mnemonic '{mnem}'", ln, txt)


def main():
    ap = argparse.ArgumentParser(description="Minimal RV32I assembler")
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True, help="output hex file")
    ap.add_argument("-l", "--listing", help="optional listing file")
    args = ap.parse_args()

    prog, labels = parse_source(args.input)
    words, listing = [], []
    for addr, mnem, ops, ln, txt in prog:
        w = encode(addr, mnem, ops, labels, ln, txt)
        words.append(w)
        listing.append(f"{addr:08x}: {w:08x}  {txt}")

    with open(args.output, "w") as f:
        f.write("\n".join(f"{w:08x}" for w in words) + "\n")
    if args.listing:
        with open(args.listing, "w") as f:
            f.write("\n".join(listing) + "\n")
            f.write("\nlabels:\n")
            for name, a in sorted(labels.items(), key=lambda kv: kv[1]):
                f.write(f"  {a:08x}  {name}\n")
    print(f"assembled {len(words)} words -> {args.output}")


if __name__ == "__main__":
    try:
        main()
    except AsmError as e:
        print(f"asm error: {e}", file=sys.stderr)
        sys.exit(1)
