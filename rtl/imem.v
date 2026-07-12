`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// imem.v - Instruction memory: synchronous single-port read (BRAM)
//
// The output register doubles as the core's IF/ID instruction register,
// so it initialises to a NOP and holds when the fetch stage is stalled
// (en = 0).
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module imem #(
    parameter DEPTH_WORDS = 4096,
    parameter INIT_FILE   = ""
)(
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] addr,
    output wire [31:0] rdata
);

    localparam integer AW = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    reg [31:0] rdata_q;

    initial begin
        rdata_q = `NOP_INSTR;   // NOP until the first fetch completes
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (en)
            rdata_q <= mem[addr[AW+1:2]];
    end

    assign rdata = rdata_q;

endmodule
