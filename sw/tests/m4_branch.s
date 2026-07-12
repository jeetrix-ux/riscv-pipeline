# m4_branch.s - mispredict flush under predict-not-taken.
# No padding anywhere: every taken branch/jump is immediately followed by
# "poison" writes that must be flushed, plus a loop, calls, and a branch in
# a load-use shadow. If any wrong-path instruction retires, a poison
# register (x20..x27, expected 0) or a cumulative counter goes wrong.

start:
    li   x2, 2

# T1: taken beq - two wrong-path slots must be flushed
    beq  x2, x2, t1_ok
    addi x20, x0, 1        # poison slot 1
    addi x21, x0, 1        # poison slot 2
t1_ok:
    addi x3, x0, 3         # x3 = 3

# T2: not-taken branch falls straight through (no penalty, no flush)
    bne  x2, x2, poison
    addi x4, x0, 4         # x4 = 4

# T3: jal - wrong path flushed, link register written
    jal  x5, t3_ok         # x5 = address of the next line
    addi x22, x0, 1        # poison
t3_ok:
    addi x6, x0, 6         # x6 = 6

# T4: countdown loop - backward branch taken 4x, falls through once
    li   x8, 5
    li   x9, 0
loop:
    add  x9, x9, x8        # x9 accumulates 5+4+3+2+1 = 15
    addi x8, x8, -1
    bnez x8, loop
    # wrong-path slots of the taken iterations are the loop's own first
    # two instructions - if not flushed, x9 over-accumulates

# T5: branch consuming a distance-1 load (stall then flush together)
    li   x10, 0x55
    sw   x10, 0(x0)        # mem[0] = 0x55
    lw   x11, 0(x0)
    beq  x11, x10, t5_ok   # 1-cycle stall, forwarded compare, taken
    addi x23, x0, 1        # poison
t5_ok:
    addi x12, x0, 0xC      # x12 = 12

# T6: back-to-back taken branches (redirect target is another branch)
    beq  x0, x0, t6_a
    addi x24, x0, 1        # poison
t6_a:
    beq  x0, x0, t6_b
    addi x25, x0, 1        # poison
t6_b:
    addi x13, x0, 0xD      # x13 = 13

# T7: call/return - the return target sits right after the jal, so it is
#     fetched wrong-path at call time AND executed legitimately after ret.
#     The increment makes double-execution visible: x14 must be exactly 1.
    jal  x1, func
    addi x14, x14, 1       # x14 = 1 (once, after the return)
    j    done
    addi x26, x0, 1        # poison behind j

func:
    addi x15, x0, 0xF      # x15 = 15 proves the call landed
    ret                    # jalr x0, 0(x1)
    addi x27, x0, 1        # poison behind ret; the wrong-path slot after
                           # this one is done's ecall - a flushed ecall
                           # must NOT halt the core early

done:
    ecall

poison:                    # only reached if T2 branches when it shouldn't
    li   x31, 0xBAD
    ecall
