# RISC-V Pipeline — 5-Stage Pipelined RV32I Core

A 5-stage pipelined RISC-V (RV32I) processor core written in plain Verilog, targeting the **Digilent Nexys A7-100T** (Artix-7) FPGA. The core implements the classic IF/ID/EX/MEM/WB pipeline with full data-hazard forwarding, a one-bubble load-use stall, a BTB + 2-bit bimodal branch predictor steering the fetch stage (branches verify in EX and flush only on a mispredict), and performance counters for measuring CPI and predictor accuracy. On the loop-heavy benchmark the predictor cuts CPI from 1.77 to 1.27.

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
          control:  BTB + 2-bit bimodal predictor picks the fetch PC,
                    EX verifies: 2-cycle flush only on a mispredict
```

## Pipeline Hazard Handling

| Hazard | Mechanism | Cost |
|--------|-----------|------|
| RAW, distance 1–2 | EX/MEM→EX and MEM/WB→EX forwarding | 0 cycles |
| RAW at register read | Write-first bypass inside the regfile | 0 cycles |
| Load-use (ALU/branch/address consumer) | 1-bubble stall from the hazard unit | 1 cycle |
| Load-use (store data) | WB→MEM store-data forward | 0 cycles |
| Correctly predicted branch / jump | BTB + 2-bit bimodal predictor in IF | 0 cycles |
| Mispredicted branch / jump | Flush IF/ID + ID/EX, redirect PC from EX | 2 cycles |

## Quick Start

The main output of this project is **simulation in Vivado (xsim)**: a test program runs on the pipelined core and the testbench checks the final register-file and memory state.

### Run a simulation
```powershell
# Assemble a test program and run it through the pipeline in xsim
powershell -File scripts\run_sim.ps1 -Test m1_arith
```
Each test in `sw/tests/` pairs a `.s` program with a `.exp` file holding the expected register-file and data-memory state; the testbench self-checks and prints `PASSED`/`FAILED` plus the cycle count.

To simulate from the Vivado GUI instead: `vivado -mode batch -source scripts/01_create_project.tcl` creates the project, then assemble a test with `sw/asm.py`, copy the `.hex`/`.exp` files into the xsim run directory as `program.hex`/`expected.hex`, and launch behavioral simulation on `tb_core_top`.

### Writing Tests
```powershell
# Assemble standalone (Python 3 only, no other dependencies)
python sw\asm.py sw\tests\m1_arith.s -o build\m1_arith.hex -l build\m1_arith.lst
```

## Target Board

**Digilent Nexys A7-100T** — Xilinx Artix-7 `xc7a100tcsg324-1`, 100 MHz board clock

## License

This project is for educational / academic purposes.
