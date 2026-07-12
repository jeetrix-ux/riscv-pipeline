`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// alu.v - RV32I integer ALU
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module alu (
    input  wire [3:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);

    always @* begin
        case (op)
            `ALU_ADD:  y = a + b;
            `ALU_SUB:  y = a - b;
            `ALU_SLL:  y = a << b[4:0];
            `ALU_SLT:  y = {31'b0, $signed(a) < $signed(b)};
            `ALU_SLTU: y = {31'b0, a < b};
            `ALU_XOR:  y = a ^ b;
            `ALU_SRL:  y = a >> b[4:0];
            `ALU_SRA:  y = $signed(a) >>> b[4:0];
            `ALU_OR:   y = a | b;
            `ALU_AND:  y = a & b;
            default:   y = a + b;
        endcase
    end

endmodule
