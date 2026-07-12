`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// uart_tx.v - Minimal UART transmitter, 8N1
//
// Write a byte with wr=1 when busy=0; tx idles high. CLKS_PER_BIT is the
// clock divider (100 MHz / 115200 baud = 868).
//////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       wr,
    input  wire [7:0] data,
    output wire       busy,
    output reg        tx
);

    localparam S_IDLE  = 2'd0;
    localparam S_SHIFT = 2'd1;

    reg [1:0]  state;
    reg [9:0]  shift;      // {stop, data[7:0], start}
    reg [3:0]  bits_left;
    reg [15:0] clk_cnt;

    initial begin
        state = S_IDLE;
        tx    = 1'b1;
    end

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            tx    <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (wr) begin
                        shift     <= {1'b1, data, 1'b0};
                        bits_left <= 4'd10;
                        clk_cnt   <= 16'd0;
                        state     <= S_SHIFT;
                    end
                end
                default: begin              // S_SHIFT
                    tx <= shift[0];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        shift   <= {1'b1, shift[9:1]};
                        if (bits_left == 4'd1)
                            state <= S_IDLE;
                        else
                            bits_left <= bits_left - 4'd1;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end
            endcase
        end
    end

endmodule
