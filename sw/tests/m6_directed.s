# m6_directed.s - directed coverage for everything the other tests missed:
# the signed/unsigned branch quartet (blt/bge/bltu/bgeu), xori/ori, fence,
# and the classic sign traps (sra of a negative, sltu against -1).
# Poison registers x20..x23 must stay 0.

start:
    li   x5, -1            # 0xFFFFFFFF: signed -1, unsigned max
    li   x6, 1

# signed vs unsigned branch behavior on the same operands
    blt  x5, x6, ok1       # signed: -1 < 1, taken
    addi x20, x0, 1        # poison
ok1:
    bltu x6, x5, ok2       # unsigned: 1 < 0xFFFFFFFF, taken
    addi x21, x0, 1        # poison
ok2:
    bge  x6, x5, ok3       # signed: 1 >= -1, taken
    addi x22, x0, 1        # poison
ok3:
    bgeu x5, x6, ok4       # unsigned: 0xFFFFFFFF >= 1, taken
    addi x23, x0, 1        # poison
ok4:
    bge  x5, x6, poison    # signed: -1 >= 1 is false, falls through
    addi x7, x0, 7         # x7 = 7

# xori / ori (the two op-imms no other test touches)
    li   x8, 0xF0
    xori x9, x8, 0xFF      # x9  = 0x0F
    ori  x10, x8, 0x700    # x10 = 0x7F0

# fence decodes to a NOP on this single-hart core
    fence
    addi x11, x0, 0xB      # x11 = 11

# shift sign traps
    li   x12, -8           # 0xFFFFFFF8
    srai x13, x12, 2       # arithmetic: x13 = 0xFFFFFFFE (-2)
    srli x14, x12, 28      # logical:    x14 = 0xF
    sra  x15, x12, x6      # by-register: x15 = 0xFFFFFFFC (-4)

# compare sign traps: -1 is huge unsigned, small signed
    sltiu x16, x5, 1       # unsigned: 0xFFFFFFFF < 1 ? no  -> 0
    slti  x17, x5, 1       # signed:   -1 < 1         ? yes -> 1
    sltu  x18, x0, x5      # unsigned: 0 < 0xFFFFFFFF ? yes -> 1

    ecall

poison:                    # only reached if a branch misbehaves
    li   x31, 0xBAD
    ecall
