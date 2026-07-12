`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// forward_unit.v - EX-stage operand forwarding selects
//
// Compares the source registers of the instruction in EX against the
// destinations of the older instructions in EX/MEM and MEM/WB. Priority
// goes to the younger producer (EX/MEM) since it holds the most recent
// write to the register. x0 never forwards, and only slots that really
// write back (reg_write && valid) count as producers.
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module forward_unit (
    input  wire [4:0] rs1_x,
    input  wire [4:0] rs2_x,

    input  wire       reg_write_m,
    input  wire       valid_m,
    input  wire [4:0] rd_m,

    input  wire       reg_write_w,
    input  wire       valid_w,
    input  wire [4:0] rd_w,

    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);

    wire m_fwds = reg_write_m && valid_m && (rd_m != 5'd0);
    wire w_fwds = reg_write_w && valid_w && (rd_w != 5'd0);

    always @* begin
        fwd_a = (m_fwds && rd_m == rs1_x) ? `FWD_MEM :
                (w_fwds && rd_w == rs1_x) ? `FWD_WB  : `FWD_NONE;
        fwd_b = (m_fwds && rd_m == rs2_x) ? `FWD_MEM :
                (w_fwds && rd_w == rs2_x) ? `FWD_WB  : `FWD_NONE;
    end

endmodule
