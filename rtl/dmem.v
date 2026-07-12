`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// dmem.v - Data memory: synchronous read, byte-writeable (BRAM)
//
// 1-cycle read latency: the output register doubles as the core's
// MEM/WB load-data register.
//////////////////////////////////////////////////////////////////////////////

module dmem #(
    parameter DEPTH_WORDS = 4096
)(
    input  wire        clk,
    input  wire        re,
    input  wire [31:0] addr,
    input  wire [3:0]  wstrb,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    localparam integer AW = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    reg [31:0] rdata_q;

    wire [AW-1:0] widx = addr[AW+1:2];

    integer i;
    initial begin
        rdata_q = 32'h0;
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0;
    end

    always @(posedge clk) begin
        if (re)
            rdata_q <= mem[widx];
        if (wstrb[0]) mem[widx][ 7: 0] <= wdata[ 7: 0];
        if (wstrb[1]) mem[widx][15: 8] <= wdata[15: 8];
        if (wstrb[2]) mem[widx][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[widx][31:24] <= wdata[31:24];
    end

    assign rdata = rdata_q;

endmodule
