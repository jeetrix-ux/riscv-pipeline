//////////////////////////////////////////////////////////////////////////////
// riscv_defs.vh - Shared opcodes and control encodings for the RV32I core
//
// Included by every RTL module so there is a single source of truth for
// instruction opcodes, ALU operation codes, and pipeline mux selects.
//////////////////////////////////////////////////////////////////////////////

`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---- opcodes (instr[6:0]) ----
`define OPC_LUI     7'b0110111
`define OPC_AUIPC   7'b0010111
`define OPC_JAL     7'b1101111
`define OPC_JALR    7'b1100111
`define OPC_BRANCH  7'b1100011
`define OPC_LOAD    7'b0000011
`define OPC_STORE   7'b0100011
`define OPC_OPIMM   7'b0010011
`define OPC_OP      7'b0110011
`define OPC_MISCMEM 7'b0001111
`define OPC_SYSTEM  7'b1110011

// ---- ALU operations ----
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_SLL     4'd2
`define ALU_SLT     4'd3
`define ALU_SLTU    4'd4
`define ALU_XOR     4'd5
`define ALU_SRL     4'd6
`define ALU_SRA     4'd7
`define ALU_OR      4'd8
`define ALU_AND     4'd9

// ---- EX operand selects ----
`define A_RS1       2'd0
`define A_PC        2'd1
`define A_ZERO      2'd2

`define B_RS2       1'b0
`define B_IMM       1'b1

// ---- writeback source ----
`define WB_ALU      2'd0
`define WB_MEM      2'd1
`define WB_PC4      2'd2

// ---- EX-stage forwarding source ----
`define FWD_NONE    2'd0
`define FWD_MEM     2'd1
`define FWD_WB      2'd2

`define NOP_INSTR   32'h0000_0013   // addi x0, x0, 0

`endif // RISCV_DEFS_VH
