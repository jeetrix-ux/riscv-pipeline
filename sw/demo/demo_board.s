# demo_board.s - board demo for the Nexys A7 SoC (never halts).
#
# Forever:
#   - mirror the switches onto the LEDs
#   - n = switches[3:0]; compute fib(n) iteratively
#   - print "fib(n)=xxxxxxxx" over the UART at 115200
#   - show {branches[15:0], mispredicts[15:0]} from the perf counters
#     on the 7-seg display (live predictor stats, in hardware)
#   - wait ~0.4 s
#
# MMIO map (bit 31 = I/O): 0x00 LEDs W, 0x04 switches R, 0x08 7-seg W,
# 0x0C uart data W / busy R, 0x10..0x1C perf counters R.
#
# Register use: x30 = MMIO base, x1 = puthex link, x2 = putc link.

start:
    lui  x30, 0x80000          # MMIO base = 0x8000_0000

main_loop:
    lw   x5, 4(x30)            # switches
    sw   x5, 0(x30)            # -> LEDs

# n = sw[3:0]; iterative fib: (a,b) <- (b, a+b) n times, result = a
    andi x6, x5, 15
    li   x7, 0                 # a = fib(0)
    li   x8, 1                 # b
    mv   x9, x6
    beqz x9, fib_done
fib_loop:
    add  x10, x7, x8
    mv   x7, x8
    mv   x8, x10
    addi x9, x9, -1
    bnez x9, fib_loop
fib_done:                      # x7 = fib(n)

# print "fib(" n ")=" fib(n) "\r\n"
    li   x12, 0x66             # 'f'
    jal  x2, putc
    li   x12, 0x69             # 'i'
    jal  x2, putc
    li   x12, 0x62             # 'b'
    jal  x2, putc
    li   x12, 0x28             # '('
    jal  x2, putc
    mv   x16, x6               # n as one hex digit
    jal  x2, nibble_out
    li   x12, 0x29             # ')'
    jal  x2, putc
    li   x12, 0x3D             # '='
    jal  x2, putc
    mv   x14, x7
    jal  x1, puthex
    li   x12, 0x0D             # '\r'
    jal  x2, putc
    li   x12, 0x0A             # '\n'
    jal  x2, putc

# 7-seg: branches resolved in the top half, mispredicts in the bottom
    lw   x18, 24(x30)          # perf: branches/jumps
    lw   x19, 28(x30)          # perf: mispredicts
    slli x18, x18, 16
    slli x19, x19, 16
    srli x19, x19, 16
    or   x18, x18, x19
    sw   x18, 8(x30)

# ~0.4 s pause so the UART line prints at a readable rate
    li   x20, 10000000
delay:
    addi x20, x20, -1
    bnez x20, delay

    j    main_loop

# ---- putc: send x12 over the UART (clobbers x13, link x2) ----
putc:
    lw   x13, 12(x30)          # busy flag
    andi x13, x13, 1
    bnez x13, putc
    sw   x12, 12(x30)
    jr   x2

# ---- nibble_out: print x16[3:0] as one hex char (tail-calls putc) ----
nibble_out:
    andi x16, x16, 15
    slti x17, x16, 10
    beqz x17, nib_alpha
    addi x12, x16, 48          # '0' + n
    j    putc                  # tail call: returns to x2's caller
nib_alpha:
    addi x12, x16, 87          # 'a' + n - 10
    j    putc

# ---- puthex: print x14 as 8 hex chars (clobbers x15..x17, x12; link x1) ----
puthex:
    li   x15, 8
ph_loop:
    srli x16, x14, 28
    jal  x2, nibble_out
    slli x14, x14, 4
    addi x15, x15, -1
    bnez x15, ph_loop
    jr   x1
