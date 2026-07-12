# Pipelined RISC-V Core — Project Plan

**Goal:** 5-stage pipelined RV32I core (IF/ID/EX/MEM/WB) with data-hazard forwarding,
load-use stall, and a 2-bit bimodal branch predictor + BTB with misprediction flush.
Simulated and synthesized in Vivado 2025.x, running on a **Digilent Nexys A7-100T**
(xc7a100tcsg324-1, 100 MHz board clock).

---

## 1. Microarchitecture spec

### Pipeline stages
| Stage | Work | Key structures |
|-------|------|----------------|
| IF | PC select, instruction fetch, predictor lookup | PC, IMEM (BRAM), BTB + 2-bit counter table |
| ID | Decode, register read, immediate gen | Regfile (2R1W, internal WB→ID bypass), control unit |
| EX | ALU, branch/jump resolution, forwarding muxes | ALU, comparator, forward unit consumers |
| MEM | Data memory access, MMIO | DMEM (BRAM), memory-mapped I/O |
| WB | Writeback mux | — |

### Hazard handling (the interview meat)
- **Forwarding:** EX/MEM→EX and MEM/WB→EX paths, priority to the younger (EX/MEM)
  result. Regfile does an internal write-first bypass so WB→ID needs no external mux.
- **Load-use stall:** one-bubble stall when EX holds a load whose rd matches a source
  reg in ID. Freeze PC + IF/ID, inject bubble into ID/EX.
- **Control hazards:** branches/JALR resolve in EX → 2-cycle misprediction penalty.
  On mispredict: flush IF/ID and ID/EX, redirect PC, update predictor.

### Branch predictor
- **BTB:** direct-mapped, ~32–64 entries, {valid, tag, target}. Hit in IF ⇒ predicted
  target available same cycle.
- **Direction:** 256-entry table of 2-bit saturating counters, indexed by PC[9:2].
  Predict taken only on (BTB hit && counter ≥ 2'b10).
- **Update:** at EX resolution — counter trained on actual direction, BTB allocated on
  taken branches/jumps.
- **Perf counters:** cycles, retired instructions, branches, mispredicts —
  memory-mapped so software (and the board demo) can compute CPI and predictor accuracy.

### Deliberate simplifications (be ready to defend these)
- Branch resolution in EX, not MEM (shorter flush, slightly longer EX path).
- Separate instruction/data BRAMs (Harvard) — no structural hazard, no cache yet.
- `ecall`/`ebreak` halt the core (no traps/CSRs — RV32I only, per scope decision).

---

## 2. Repository layout

```
risc v/
├── rtl/             riscv_defs.vh (shared defines), core_top, control, regfile,
│                    imm_gen, alu, branch_unit, forward_unit, hazard_unit,
│                    imem, dmem; later: branch_predictor, btb, soc_top, mmio, uart_tx
├── sim/             tb_core_top, directed unit TBs, regression harness
├── sw/              test programs (.s / .exp), Python assembler (asm.py)
├── scripts/         01_create_project.tcl, run_sim.ps1
├── constraints/     nexys_a7.xdc
└── docs/            PLAN.md, talking_points.md, measurements
```

All RTL is plain Verilog-2001 (`.v`), with shared constants in `rtl/riscv_defs.vh`.

---

## 3. Milestones (build order)

**M0 — Scaffold & tooling. ✅ (2026-07-10)** Repo layout, Vivado project tcl, xsim smoke test,
decide software flow: hand-written hex + tiny Python assembler (no toolchain install
needed), with option to switch to riscv-gnu-toolchain later.

**M1 — Pipeline skeleton, no hazards. ✅ (2026-07-10, `m1_arith` passes in xsim: 72 instrs, 69 cycles)** All 5 stages + pipeline registers, full RV32I
decode/execute, NOP-padded test programs only. Milestone test: arithmetic/logic/imm
program produces correct regfile state.

**M2 — Forwarding. ✅ (2026-07-10, `m2_forward` passes: EX/MEM + MEM/WB paths, priority, x0, store-data/branch/jalr operands)** EX/MEM→EX and MEM/WB→EX + regfile bypass. Tests: back-to-back
RAW chains, both-match priority case, x0 exclusion.

**M3 — Load-use stall.** Hazard unit stall logic. Tests: lw followed immediately by
use; lw→sw (store data can forward from MEM, no stall needed — good corner case).

**M4 — Control flow, predict-not-taken.** Branches/jumps resolve in EX with flush.
This is the correctness baseline before any predictor. Tests: taken/not-taken
branches, JAL/JALR, branch in a load-use shadow.

**M5 — Branch predictor.** BTB + 2-bit counters + perf counters. Tests: loop-heavy
program (predictor should approach ~loop-count/(loop-count+1) accuracy), alternating
branch (worst case for 2-bit), BTB aliasing case. Measure and record CPI +
mispredict rate vs the M4 baseline — these numbers are your interview ammunition.

**M6 — Verification pass.** Self-checking regression: directed tests per instruction
class + a golden-model comparison (Python ISS executing the same hex, diffing
retired register/memory writes). Run whole suite with one script.

**M7 — Synthesis & timing.** Out-of-context synth of the core for xc7a100tcsg324-1.
Initial clock target 50 MHz, then push toward 100 MHz; record critical path
(expect: forwarding mux → ALU → branch compare → PC redirect). Utilization report.

**M8 — Board bring-up.** SoC top with MMIO: switches in, LEDs out, 7-seg showing
perf-counter/program output, UART TX for prints. Demo program (e.g., fibonacci or
sieve printing over UART, mispredict rate on the 7-seg). Full XDC from Digilent
master file; bitstream on hardware.

**M9 — Write-up.** `talking_points.md`: forwarding vs stalling tradeoff, EX vs MEM
branch resolution, 2-bit vs gshare (with your measured data), timing results, what
you'd do next (gshare, caches, RAS, M-extension).

---

## 4. Board / tool facts

- Part: **xc7a100tcsg324-1** (Nexys A7-100T)
- Clock: 100 MHz on pin E3 (LVCMOS33); derive core clock via MMCM if < 100 MHz
- UART: FTDI bridge, TX to host on pin D4 (from FPGA), 115200-8N1
- Vivado 2025.x, xsim for simulation, project-mode tcl scripts (batch:
  `vivado -mode batch -source scripts/01_create_project.tcl`)
- Timing sign-off: WNS ≥ 0 in `report_timing_summary`

## 5. Open items

- [ ] Install riscv-gnu-toolchain? (fallback: Python assembler in `sw/`)
- [ ] Stretch: parameterized gshare behind a `PREDICTOR` parameter for A/B accuracy data
- [ ] Stretch: return-address stack for JALR returns
