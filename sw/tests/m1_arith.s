# m1_arith.s - M1 pipeline-skeleton test: full RV32I, NOP-padded.
#
# M1 has no forwarding, no stalls, no flush, so this program obeys:
#   - >= 2 NOPs (distance >= 3) between a producer and its consumer
#     (the regfile write-first bypass covers distance exactly 3)
#   - exactly 2 NOPs after every taken branch/jump (wrong-path slots)
#
# Expected architectural state at halt is checked by tb/core_tb.sv.

        addi  x1, x0, 5          # x1 = 5
        auipc x16, 0             # x16 = 4 (pc of this instruction)
        addi  x2, x0, 12         # x2 = 12
        nop
        nop
        add   x3, x1, x2         # x3 = 17
        sub   x4, x1, x2         # x4 = -7 = 0xFFFFFFF9
        xor   x5, x1, x2         # x5 = 9
        or    x6, x1, x2         # x6 = 13
        and   x7, x1, x2         # x7 = 4
        slli  x8, x1, 4          # x8 = 80
        nop
        nop
        srli  x9, x4, 28         # x9 = 0xF
        srai  x10, x4, 2         # x10 = -2 = 0xFFFFFFFE
        slt   x11, x4, x1        # x11 = 1  (-7 < 5 signed)
        sltu  x12, x4, x1        # x12 = 0  (0xFFFFFFF9 < 5 unsigned is false)
        slti  x13, x1, -3        # x13 = 0
        sltiu x14, x1, 7         # x14 = 1
        lui   x15, 0xDEADB       # x15 = 0xDEADB000
        nop
        nop
        addi  x17, x15, 0x2EF    # x17 = 0xDEADB2EF
        nop
        nop
        sw    x17, 0(x0)         # mem[0] = 0xDEADB2EF
        sw    x1, 4(x0)          # mem[4] = 5
        sb    x1, 8(x0)          # mem[8] byte0 = 05
        sh    x2, 10(x0)         # mem[8] bytes 3:2 = 000C -> word = 0x000C0005
        nop
        nop
        lw    x18, 0(x0)         # x18 = 0xDEADB2EF
        lb    x19, 1(x0)         # x19 = 0xFFFFFFB2 (sign-extended 0xB2)
        lhu   x20, 2(x0)         # x20 = 0x0000DEAD
        lbu   x21, 3(x0)         # x21 = 0x000000DE
        lh    x22, 0(x0)         # x22 = 0xFFFFB2EF (sign-extended 0xB2EF)
        addi  x23, x0, 3         # x23 = 3
        nop
        nop
        sll   x24, x2, x23       # x24 = 96
        srl   x25, x4, x23       # x25 = 0x1FFFFFFF
        sra   x26, x4, x23       # x26 = 0xFFFFFFFF
        jal   x27, target1       # x27 = pc+4
        nop                      # wrong-path slot 1 (executes, harmless)
        nop                      # wrong-path slot 2 (executes, harmless)
        addi  x28, x0, 111       # never fetched
target1:
        addi  x28, x0, 222       # x28 = 222
        nop
        nop
        beq   x28, x28, target2  # taken
        nop
        nop
        addi  x29, x0, 333       # never fetched
target2:
        addi  x29, x0, 444       # x29 = 444
        nop
        nop
        bne   x29, x28, target3  # taken (444 != 222)
        nop
        nop
        addi  x30, x0, 555       # never fetched
target3:
        addi  x30, x0, 666       # x30 = 666
        lui   x31, 0xC10         # li x31, 0xC0FFEE spelled out with padding
        nop                      # (li expands to dependent lui+addi, which
        nop                      #  needs M2 forwarding - not available yet)
        addi  x31, x31, -18      # x31 = 0xC10000 - 18 = 0x00C0FFEE
        nop
        nop
        ecall                    # halt
        nop
        nop
        nop
        nop
