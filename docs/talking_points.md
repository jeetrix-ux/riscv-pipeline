# Talking Points — Interview Ammunition

Everything here is backed by a measurement from this repo (perf counters in
`core_top.v`, printed by the testbench; regression via `scripts/run_all.ps1`).

## Forwarding vs stalling

The rule of thumb: **forward when the value already exists somewhere in the
pipeline, stall only when it genuinely doesn't exist yet.**

- An ALU result exists at the end of EX, so EX/MEM→EX and MEM/WB→EX forwarding
  paths cover every RAW distance for free. `m2_forward` runs unpadded RAW
  chains at CPI 1.25 (the overhead is startup fill, not hazards).
- A load's data doesn't exist until the end of MEM, so a distance-1 consumer
  *must* stall — but only one bubble, after which the MEM/WB→EX path serves it.
  `m3_loaduse` measures this: CPI 1.36 with a test that is deliberately nothing
  but load-use hazards; real code pays far less.
- The subtle exception that impresses people: **`lw → sw` needs no stall at
  all.** Store data isn't consumed until MEM, and the instruction in WB is
  always the youngest older instruction, so a WB→MEM store-data forward is
  architecturally always correct. The hazard unit exempts store rs2 on the
  strength of that path.
- One decoder detail that bites everyone: LUI/AUIPC/JAL carry immediate bits
  where rs1/rs2 would sit. Without explicit `uses_rs1/uses_rs2` decode, those
  bits alias a load's rd and cause phantom stalls.

## Branch resolution in EX, not MEM

Resolving in EX makes the mispredict penalty 2 cycles instead of 3, at the
cost of putting the forwarding mux → comparator → redirect path in EX. That
path is the expected critical path (see timing below) — this is a conscious
latency-vs-frequency trade, and the right default for a short pipeline.

## Predictor: 2-bit bimodal + BTB (measured)

Baseline (predict-not-taken) vs predictor, same loop-heavy program
(`m5_loops`: hot countdown loop, call/return in a loop, alternating branch):

| | cycles | CPI | control transfers | mispredicts |
|---|---|---|---|---|
| predict-not-taken (M4) | 345 | 1.77 | 85 | every taken one |
| BTB + 2-bit bimodal (M5) | 249 | 1.27 | 85 | 25 |

- **28% cycle reduction** on loop-heavy code; correctly predicted taken
  branches cost 0 cycles.
- The hot loop approaches the theoretical n-1/n accuracy for an n-iteration
  loop with a 2-bit counter (mispredicts only on first entry and last exit).
- The alternating-branch phase is the designed worst case: a 2-bit counter
  cannot learn a strict taken/not-taken alternation, and the mispredict count
  shows it. That's the honest limitation — and the pitch for **gshare**,
  which XORs global history into the index and learns exactly this pattern.
- BTB uses full tags, so a hit is never a false positive; the EX check still
  guards wrong-target (JALR, stale entry) and predicted-taken-on-non-branch
  cases, which is what makes the predictor *only* a performance feature —
  correctness never depends on it.

## Verification story

Two independent implementations must agree: the RTL and a ~200-line Python
ISS (`sw/iss.py`) execute the same hex, and the regression checks the final
architectural state word-for-word with zero don't-cares. The ISS itself is
cross-checked against hand-written expectations, so a shared misunderstanding
of the ISA would have to fool three artifacts written at different times.
Directed tests cover each hazard class with a "poison register" idiom: any
wrong-path instruction that escapes a flush lands a visible write.

## Synthesis & timing (Artix-7, xc7a100tcsg324-1, out-of-context)

- Meets the board's 100 MHz clock: **WNS +0.224 ns → Fmax ≈ 102 MHz**
  (`scripts/02_synth_ooc.tcl`, Vivado 2025.1 post-synthesis estimates).
- Core cost: **1257 LUTs / 488 FFs, zero BRAM/DSP** — about 2% of the
  xc7a100t (imem/dmem sit outside the core and map to BRAM at SoC level).
- The critical path is exactly the one the plan predicted: a WB-stage
  register feeds the forwarding mux, the forwarded operand resolves a
  JALR/branch in EX, and the resulting redirect gates the front-end
  enables — 16 logic levels, ~57% of the delay in routing. That's the
  price of EX-stage branch resolution; the two levers if it ever fails
  timing are resolving in MEM (+1 cycle mispredict penalty) or predicting
  JALR targets with a RAS so the resolve path stops being urgent.
- **The full SoC tells the honest version of that story**: once the dmem
  is a real BRAM, its ~2.5 ns clock-to-out lands in front of the same
  load-data → forward → branch-resolve chain and the post-route path is
  12 ns (Fmax ≈ 82 MHz). The board therefore runs the core at **50 MHz
  from an MMCM** with 8 ns of margin — the plan called this fallback
  before implementation started. Knowing *which* path breaks first and
  *why* the OOC number was optimistic is the actual takeaway.

## The demo writes its own punchline

The board demo maps the perf counters into the address space and puts
{branches, mispredicts} on the 7-seg display. While the CPU spins in the
UART busy-poll loop, the display shows tens of thousands of branches and a
mispredict count you can read off in one glance — the 2-bit predictor eats
a spin loop alive, live, in hardware. (`sim/tb_soc_top.v` verifies the same
demo in simulation by decoding the UART waveform: `fib(a)=00000037`.)

## What I'd do next

1. **gshare behind a parameter** — measured A/B against bimodal on the
   alternating-branch test; the data above predicts exactly where it wins.
2. **Return-address stack** — `ret` is a JALR whose target the BTB learns per
   call site; a RAS predicts it correctly even for varying call sites.
3. **I/D caches** — the BRAMs fake single-cycle memory; a real memory system
   turns the load-use stall into a variable-latency problem and makes the
   MEM/WB interface a handshake.
4. **M extension** — multi-cycle multiply/divide introduces structural
   hazards, the natural next hazard class after data and control.
