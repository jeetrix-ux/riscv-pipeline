# RISC-V Pipeline — 5-Stage Pipelined RV32I Core

A 5-stage pipelined RISC-V (RV32I) processor core written in plain Verilog, targeting the **Digilent Nexys A7-100T** (Artix-7) FPGA. The core implements the classic IF/ID/EX/MEM/WB pipeline with full data-hazard forwarding, a one-bubble load-use stall, and branch resolution in EX with misprediction flush — with a BTB + 2-bit bimodal branch predictor and memory-mapped performance counters as the end goal.

## Architecture

```
IF ──► ID ──► EX ──► MEM ──► WB
│      │      │       │       │
PC     decode ALU     DMEM    regfile
IMEM   regfile branch (BRAM)  write
(BRAM) immgen  resolve

Hazards:  EX/MEM──►EX and MEM/WB──►EX forwarding (priority to younger)
          WB──►ID write-first regfile bypass
          load-use: 1-bubble stall (store data exempt via WB──►MEM forward)
          branches resolve in EX: 2-cycle flush on redirect
```

## Project Structure

```
riscv-pipeline/
├── rtl/                     # Synthesisable Verilog modules
│   ├── riscv_defs.vh        # Shared opcode / ALU-op / mux-select defines
│   ├── core_top.v           # 5-stage pipeline datapath + pipeline registers
│   ├── control.v            # RV32I instruction decoder
│   ├── regfile.v            # 2R1W register file with write-first bypass
│   ├── imm_gen.v            # I/S/B/U/J immediate generator
│   ├── alu.v                # Arithmetic / logic / shift / compare unit
│   ├── branch_unit.v        # Branch condition resolution
│   ├── forward_unit.v       # EX/MEM and MEM/WB forwarding selects
│   ├── hazard_unit.v        # Load-use stall detection
│   ├── imem.v               # Instruction memory (Block RAM, sync read)
│   └── dmem.v               # Data memory (Block RAM, byte-writeable)
├── sim/                     # Simulation & testbenches
│   └── tb_core_top.v        # Self-checking top-level testbench
├── sw/                      # Software toolchain & test programs
│   ├── asm.py               # Two-pass RV32I assembler (no toolchain needed)
│   └── tests/               # Assembly tests + expected-state files (.s / .exp)
├── constraints/             # FPGA constraints
│   └── nexys_a7.xdc         # Nexys A7-100T pin assignments
├── scripts/                 # Build & simulation tooling
│   ├── 01_create_project.tcl # Vivado project creation
│   └── run_sim.ps1          # Assemble a test and run it through xsim
└── docs/                    # Planning & write-ups
    └── PLAN.md              # Microarchitecture spec + milestone plan
```

## Pipeline Hazard Handling

| Hazard | Mechanism | Cost |
|--------|-----------|------|
| RAW, distance 1–2 | EX/MEM→EX and MEM/WB→EX forwarding | 0 cycles |
| RAW at register read | Write-first bypass inside the regfile | 0 cycles |
| Load-use (ALU/branch/address consumer) | 1-bubble stall from the hazard unit | 1 cycle |
| Load-use (store data) | WB→MEM store-data forward | 0 cycles |
| Taken branch / jump | Flush IF/ID + ID/EX, redirect PC from EX | 2 cycles |

## Quick Start

### Simulation (Vivado xsim)
```powershell
# Assemble a test program and run it through the pipeline in xsim
powershell -File scripts\run_sim.ps1 -Test m1_arith
```
Each test in `sw/tests/` pairs a `.s` program with a `.exp` file holding the expected register-file and data-memory state; the testbench self-checks and prints `PASSED`/`FAILED`.

### Synthesis
1. `vivado -mode batch -source scripts/01_create_project.tcl` creates the project targeting `xc7a100tcsg324-1` (Nexys A7-100T).
2. Run Synthesis → Implementation → Generate Bitstream from the project.

### Writing Tests
```powershell
# Assemble standalone (Python 3 only, no other dependencies)
python sw\asm.py sw\tests\m1_arith.s -o build\m1_arith.hex -l build\m1_arith.lst
```

## Target Board

**Digilent Nexys A7-100T** — Xilinx Artix-7 `xc7a100tcsg324-1`, 100 MHz board clock

## License

This project is for educational / academic purposes.
