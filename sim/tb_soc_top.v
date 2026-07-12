`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_soc_top.v - SoC smoke test: boot the demo program, decode the UART
//
// Loads "demo.hex" into the SoC's instruction memory, drives the switches
// with 0x000A, and listens to the UART TX pin at 115200 baud. The demo
// must print "fib(a)=00000037" (fib(10) = 55) followed by CR LF.
//////////////////////////////////////////////////////////////////////////////

module tb_soc_top;

    localparam DEMO_HEX    = "demo.hex";
    localparam BIT_NS      = 8680;            // 115200 baud @ 1ns timescale
    localparam TIMEOUT_CYC = 2_000_000;

    reg         clk;
    reg         cpu_resetn;
    reg  [15:0] sw;
    wire [15:0] led;
    wire [6:0]  seg;
    wire [7:0]  an;
    wire        uart;

    // drive the core clock rate directly (USE_MMCM=0 bypasses the MMCM,
    // which would need vendor sim libraries)
    initial clk = 0;
    always #10 clk = ~clk;                    // 50 MHz

    soc_top #(.USE_MMCM(0)) u_soc (
        .clk          (clk),
        .cpu_resetn   (cpu_resetn),
        .sw           (sw),
        .led          (led),
        .seg          (seg),
        .an           (an),
        .uart_rxd_out (uart)
    );

    // ----------------------------------------------------------------
    // UART receiver (sample mid-bit)
    // ----------------------------------------------------------------
    localparam EXP_LEN = 17;                  // "fib(a)=00000037" CR LF
    wire [EXP_LEN*8-1:0] expected = {"fib(a)=00000037", 8'h0D, 8'h0A};

    reg [EXP_LEN*8-1:0] line;
    reg [7:0] ch;
    integer   nchars;
    integer   bit_i;

    initial begin
        line   = 0;
        nchars = 0;

        sw         = 16'h000A;
        cpu_resetn = 1'b0;
        $readmemh(DEMO_HEX, u_soc.u_imem.mem);
        repeat (10) @(posedge clk);
        cpu_resetn = 1'b1;

        while (nchars < EXP_LEN) begin
            @(negedge uart);                  // start bit
            #(BIT_NS + BIT_NS/2);             // middle of data bit 0
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                ch[bit_i] = uart;             // LSB first
                #BIT_NS;
            end
            line   = {line[EXP_LEN*8-9:0], ch};
            nchars = nchars + 1;
            if (ch >= 8'h20) $write("%c", ch);
            else             $display("");
        end

        if (line == expected) begin
            $display("led=%04h seg_value=%08h", led, u_soc.seg_value_q);
            $display("=== tb_soc_top: PASSED ===");
        end else begin
            $display("expected \"fib(a)=00000037\\r\\n\"");
            $display("=== tb_soc_top: FAILED ===");
        end
        $finish;
    end

    // watchdog
    initial begin
        repeat (TIMEOUT_CYC) @(posedge clk);
        $display("ERROR: timeout waiting for UART output");
        $display("=== tb_soc_top: FAILED ===");
        $finish;
    end

endmodule
