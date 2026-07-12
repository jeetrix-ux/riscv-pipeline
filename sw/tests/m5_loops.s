# m5_loops.s - loop-heavy program for branch-predictor measurement.
# Architectural results are checked as usual; the interesting output is the
# perf-counter line the testbench prints (CPI, control-flow count,
# mispredicts). Three phases:
#   L1: hot countdown loop        - predictor should approach 19/20 accuracy
#   L2: call/return inside a loop - exercises BTB hits on jal and jalr (ret)
#   L3: alternating branch        - worst case for 2-bit counters

start:

# L1: countdown loop, 20 iterations (backward branch taken 19x, then falls
#     through). x5 = 20+19+...+1 = 210
    li   x5, 0
    li   x6, 20
l1:
    add  x5, x5, x6
    addi x6, x6, -1
    bnez x6, l1

# L2: call a function 8 times: jal forward, ret (jalr) back - both should
#     become BTB hits after the first trip. x8 = 8 * 2 = 16
    li   x7, 8
    li   x8, 0
l2:
    jal  x1, bump
    addi x7, x7, -1
    bnez x7, l2

# L3: alternating branch, 16 iterations - taken/not-taken flips every trip,
#     the pattern a 2-bit counter cannot learn. Odd x9 adds 3 (8 times),
#     even x9 adds 5 (8 times): x10 = 24 + 40 = 64
    li   x9, 16
    li   x10, 0
l3:
    andi x12, x9, 1
    beqz x12, l3_even
    addi x10, x10, 3       # x9 odd
    j    l3_next
l3_even:
    addi x10, x10, 5       # x9 even
l3_next:
    addi x9, x9, -1
    bnez x9, l3

    ecall

bump:
    addi x8, x8, 2
    ret
