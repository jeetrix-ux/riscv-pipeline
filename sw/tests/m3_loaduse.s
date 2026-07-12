# m3_loaduse.s - load-use hazard stalls + the store-data no-stall corner.
# M3 removes the software rule "leave 1 gap after a load before using it":
# every consumer below sits at distance 1 from its producing load.
# Taken control flow still needs 2 wrong-path NOP slots until M4.

start:
    li   x1, 0x123
    sw   x1, 0(x0)         # mem[0] = 0x123
    li   x2, 0x456
    sw   x2, 4(x0)         # mem[1] = 0x456

# T1: classic load-use, rs1 consumer at distance 1 -> 1-cycle stall
    lw   x3, 0(x0)         # x3 = 0x123
    addi x4, x3, 1         # x4 = 0x124

# T2: load-use via rs2
    lw   x5, 4(x0)         # x5 = 0x456
    add  x6, x0, x5        # x6 = 0x456

# T3: lw -> sw of the loaded value at distance 1: NO stall.
#     EX-time forwarding would grab the load's address; the WB->MEM
#     store-data forward supplies the real data one stage later.
    lw   x7, 0(x0)         # x7 = 0x123
    sw   x7, 8(x0)         # mem[2] = 0x123

# T4: lw -> sw where the store ADDRESS is the loaded value: must stall
    li   x28, 12
    sw   x28, 16(x0)       # mem[4] = 12
    lw   x10, 16(x0)       # x10 = 12
    sw   x2, 0(x10)        # mem[3] = 0x456 (rs1 dep -> stall)

# T5: pointer chase - load address from a load at distance 1
    lw   x11, 16(x0)       # x11 = 12
    lw   x12, 0(x11)       # x12 = mem[3] = 0x456

# T6: load-use branch operand, branch taken
    lw   x13, 0(x0)        # x13 = 0x123
    beq  x13, x1, t6_ok    # stall, forwarded compare -> taken
    nop                    # wrong-path slot (executes until M4 flush)
    nop                    # wrong-path slot
    addi x14, x0, 0xF0     # never fetched when taken -> x14 stays 0
t6_ok:
    addi x15, x0, 0xF1     # x15 = 0xF1

# T7: load-use branch operand, not taken (fall through, no padding needed)
    lw   x16, 4(x0)        # x16 = 0x456
    bne  x16, x2, poison   # equal -> not taken
    addi x17, x0, 0x77     # x17 = 0x77

# T8: load to x0 must not stall or corrupt anything
    addi x20, x0, 5
    lw   x0, 0(x0)         # discarded load
    add  x20, x20, x0      # x20 = 5 (no stall: rd = x0 is exempt)

# T9: two loads feeding both operands of one add
    lw   x24, 0(x0)        # x24 = 0x123
    lw   x25, 4(x0)        # x25 = 0x456
    add  x26, x24, x25     # x26 = 0x579 (stall for x25; x24 via regfile)

# T10: byte store of a distance-1 load result (WB->MEM fwd + wstrb path)
    lw   x23, 0(x0)        # x23 = 0x123
    sb   x23, 20(x0)       # mem[5] = 0x00000023

# T11: distance-2 load consumer still served by plain FWD_WB (regression)
    lw   x21, 8(x0)        # x21 = 0x123 (written by T3)
    nop
    addi x22, x21, 2       # x22 = 0x125

# T12: phantom-stall guard - lui's imm bits [19:15] equal 19, aliasing the
#      preceding load's rd; lui has no rs1 so this must not stall (results
#      identical either way - the guard shows up in the cycle count)
    lw   x19, 0(x0)        # x19 = 0x123
    lui  x18, 0x98         # x18 = 0x98000, instr[19:15] == 19

done:
    ecall

poison:                    # only reached if T7 mispredicts/miscompares
    li   x31, 0xBAD
    ecall
