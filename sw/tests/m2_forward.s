# m2_forward.s - M2 forwarding test: dependent instructions with NO padding.
#
# Still required in M2:
#   - 1 gap instruction between a load and its consumer (load-use stall is M3)
#   - 2 wrong-path slots after taken branches/jumps (flush is M4)

# EX/MEM->EX and MEM/WB->EX chains
        addi x1, x0, 1          # x1 = 1
        addi x2, x1, 2          # x2 = 3   (x1 dist 1: EX/MEM fwd)
        add  x3, x2, x1         # x3 = 4   (x2 EX/MEM + x1 MEM/WB)
        add  x4, x3, x3         # x4 = 8   (both operands EX/MEM)
        sub  x5, x4, x1         # x5 = 7   (x1 from regfile, no fwd)

# double write: youngest in-flight value must win
        addi x6, x0, 10
        addi x6, x6, 5          # x6 = 15
        add  x7, x6, x0         # x7 = 15  (EX/MEM has 15, MEM/WB has 10)

# x0 must never forward
        addi x0, x0, 99         # write to x0 is discarded
        add  x8, x0, x0         # x8 = 0

# store-data forwarding, then read memory back
        addi x9, x0, 0x77
        sw   x9, 0(x0)          # store data via EX/MEM fwd
        addi x10, x0, 4
        sw   x10, 4(x0)         # store data via EX/MEM fwd
        lw   x11, 0(x0)         # x11 = 0x77
        addi x13, x0, 4         # (doubles as the load-use gap for x11)
        add  x12, x11, x0       # x12 = 0x77 (load data dist 2: MEM/WB fwd)
        lw   x14, 0(x13)        # x14 = 4    (base x13 dist 2: MEM/WB fwd)
        nop                     # load-use gap for x14
        add  x15, x14, x14      # x15 = 8    (load data dist 2: MEM/WB fwd)
        addi x23, x0, 0
        lw   x24, 4(x23)        # x24 = 4    (base x23 dist 1: EX/MEM fwd)

# branch operand forwarded
        addi x16, x0, 5
        bne  x16, x0, t6ok      # taken; x16 dist 1: EX/MEM fwd
        nop
        nop
        addi x17, x0, 1         # never fetched
t6ok:
        addi x17, x0, 2         # x17 = 2

# li large constant: the dependent lui+addi pair now works unpadded
        li   x18, 0x12345678

# jalr through a freshly computed target
        auipc x19, 0            # x19 = pc of this instruction
        addi x20, x19, 24       # x20 = &t8ok (x19 dist 1: EX/MEM fwd)
        jalr x21, x20, 0        # target via EX/MEM fwd; x21 = pc+4
        nop
        nop
        addi x22, x0, 1         # never fetched
t8ok:
        addi x22, x0, 7         # x22 = 7
        ecall
        nop
        nop
        nop
        nop
