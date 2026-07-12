`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// imm_gen.v - Immediate extraction for all RV32I formats
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);

    always @* begin
        case (instr[6:0])
            `OPC_STORE:  imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OPC_BRANCH: imm = {{19{instr[31]}}, instr[31], instr[7],
                                instr[30:25], instr[11:8], 1'b0};
            `OPC_LUI,
            `OPC_AUIPC:  imm = {instr[31:12], 12'b0};
            `OPC_JAL:    imm = {{11{instr[31]}}, instr[31], instr[19:12],
                                instr[20], instr[30:21], 1'b0};
            default:     imm = {{20{instr[31]}}, instr[31:20]};   // I-type
        endcase
    end

endmodule
