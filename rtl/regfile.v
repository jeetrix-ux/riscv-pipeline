`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// regfile.v - 32x32 register file, 2 read ports / 1 write port
//
// Write-first (internal WB->ID bypass): a read of the register being
// written this cycle returns the new value, so a producer in WB and a
// consumer in ID never conflict. x0 is hardwired to zero.
//////////////////////////////////////////////////////////////////////////////

module regfile (
    input  wire        clk,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    output reg  [31:0] rdata1,
    output reg  [31:0] rdata2,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);

    reg [31:0] rf [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'h0;
    end

    always @(posedge clk) begin
        if (we && waddr != 5'd0)
            rf[waddr] <= wdata;
    end

    // Reads are combinational with the write-first bypass
    always @* begin
        rdata1 = (raddr1 == 5'd0) ? 32'h0 :
                 (we && waddr == raddr1) ? wdata : rf[raddr1];
        rdata2 = (raddr2 == 5'd0) ? 32'h0 :
                 (we && waddr == raddr2) ? wdata : rf[raddr2];
    end

endmodule
