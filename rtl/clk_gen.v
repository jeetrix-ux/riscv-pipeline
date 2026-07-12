`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// clk_gen.v - Core clock generation: 100 MHz board clock -> 50 MHz
//
// The core alone makes 100 MHz out of context, but the full SoC's
// dmem-BRAM -> load-data -> forward -> branch-resolve path lands at
// ~12 ns post-route, so the board runs the core at 50 MHz with margin.
// USE_MMCM=0 bypasses the MMCM for pure-RTL simulation.
//////////////////////////////////////////////////////////////////////////////

module clk_gen #(
    parameter USE_MMCM = 1
)(
    input  wire clk_in,      // 100 MHz board clock
    output wire clk_out,     // 50 MHz core clock
    output wire locked
);

    generate
        if (USE_MMCM) begin : g_mmcm
            wire clkfb, clkfb_buf, clk_unbuf;

            MMCME2_BASE #(
                .CLKIN1_PERIOD    (10.000),
                .CLKFBOUT_MULT_F  (10.000),   // VCO = 1000 MHz
                .CLKOUT0_DIVIDE_F (20.000)    // 1000 / 20 = 50 MHz
            ) u_mmcm (
                .CLKIN1   (clk_in),
                .CLKFBIN  (clkfb_buf),
                .CLKFBOUT (clkfb),
                .CLKOUT0  (clk_unbuf),
                .LOCKED   (locked),
                .PWRDWN   (1'b0),
                .RST      (1'b0)
            );

            BUFG u_bufg_fb  (.I(clkfb),     .O(clkfb_buf));
            BUFG u_bufg_out (.I(clk_unbuf), .O(clk_out));
        end else begin : g_bypass
            assign clk_out = clk_in;
            assign locked  = 1'b1;
        end
    endgenerate

endmodule
