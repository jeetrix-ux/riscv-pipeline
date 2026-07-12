`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// seg7_driver.v - 8-digit multiplexed seven-segment driver (hex)
//
// Shows a 32-bit value as 8 hex digits. Nexys A7 style: segments and
// anodes are both active low; one digit is lit at a time, cycling fast
// enough (~1 kHz per digit) that all eight appear solid.
//////////////////////////////////////////////////////////////////////////////

module seg7_driver (
    input  wire        clk,
    input  wire [31:0] value,
    output reg  [6:0]  seg,     // {CG..CA} active low
    output reg  [7:0]  an       // digit anodes, active low
);

    reg [16:0] refresh_cnt;
    initial refresh_cnt = 17'd0;

    always @(posedge clk)
        refresh_cnt <= refresh_cnt + 17'd1;

    wire [2:0] digit_sel = refresh_cnt[16:14];   // ~381 Hz per digit @50 MHz

    reg [3:0] nibble;
    always @* begin
        case (digit_sel)
            3'd0: nibble = value[3:0];
            3'd1: nibble = value[7:4];
            3'd2: nibble = value[11:8];
            3'd3: nibble = value[15:12];
            3'd4: nibble = value[19:16];
            3'd5: nibble = value[23:20];
            3'd6: nibble = value[27:24];
            default: nibble = value[31:28];
        endcase
        an = ~(8'b0000_0001 << digit_sel);
    end

    // segment patterns, active low, bit order {CG,CF,CE,CD,CC,CB,CA}
    always @* begin
        case (nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            default: seg = 7'b0001110;   // F
        endcase
    end

endmodule
