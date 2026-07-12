`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_core_top.v - Self-checking testbench for the pipelined core
//
// Loads "program.hex" into instruction memory, runs until the core halts
// (ecall) or times out, then compares architectural state against
// "expected.hex": 40 words = x0..x31 followed by dmem words 0..7.
// An all-x word means "don't check". Both files are staged into the
// simulation directory by scripts/run_sim.ps1.
//////////////////////////////////////////////////////////////////////////////

module tb_core_top;

    // ----------------------------------------------------------------
    // Test configuration
    // ----------------------------------------------------------------
    localparam PROGRAM_HEX  = "program.hex";
    localparam EXPECTED_HEX = "expected.hex";
    localparam TIMEOUT_CYC  = 20000;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ----------------------------------------------------------------
    // DUT + memories
    // ----------------------------------------------------------------
    wire [31:0] imem_addr, imem_rdata;
    wire        imem_en;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_re;
    wire        halted;

    core_top dut (
        .clk        (clk),
        .rst        (rst),
        .imem_addr  (imem_addr),
        .imem_en    (imem_en),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_wstrb (dmem_wstrb),
        .dmem_re    (dmem_re),
        .dmem_rdata (dmem_rdata),
        .halted     (halted)
    );

    imem #(.DEPTH_WORDS(4096)) u_imem (
        .clk   (clk),
        .en    (imem_en),
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    dmem #(.DEPTH_WORDS(4096)) u_dmem (
        .clk   (clk),
        .re    (dmem_re),
        .addr  (dmem_addr),
        .wstrb (dmem_wstrb),
        .wdata (dmem_wdata),
        .rdata (dmem_rdata)
    );

    // ----------------------------------------------------------------
    // Cycle counter
    // ----------------------------------------------------------------
    integer cycles;
    initial cycles = 0;
    always @(posedge clk)
        if (!rst && !halted) cycles = cycles + 1;

    // ----------------------------------------------------------------
    // Run program, wait for halt, check architectural state
    // ----------------------------------------------------------------
    reg [31:0] expected [0:39];   // [0:31] regs x0..x31, [32:39] dmem 0..7

    integer errors;
    integer timeout;
    integer i;

    initial begin
        errors = 0;
        rst    = 1;

        $display("loading program: %s", PROGRAM_HEX);
        $readmemh(PROGRAM_HEX, u_imem.mem);
        $readmemh(EXPECTED_HEX, expected);

        repeat (3) @(posedge clk);
        rst <= 0;

        // wait for halt with timeout
        timeout = 0;
        while (!halted && timeout < TIMEOUT_CYC) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!halted) begin
            $display("ERROR: timeout waiting for halt");
            errors = errors + 1;
        end

        repeat (2) @(posedge clk);
        $display("halted after %0d cycles", cycles);
        $display("perf: cycles=%0d instret=%0d CPIx100=%0d ctrl=%0d mispred=%0d",
                 dut.perf_cycles, dut.perf_instret,
                 (dut.perf_instret != 0) ? (dut.perf_cycles * 100) / dut.perf_instret : 0,
                 dut.perf_ctrl, dut.perf_mispred);

        // an expected word containing x means "don't check"
        for (i = 0; i < 32; i = i + 1) begin
            if ((^expected[i] !== 1'bx) && dut.u_regfile.rf[i] !== expected[i]) begin
                $display("FAIL: x%0d = %08h, expected %08h",
                         i, dut.u_regfile.rf[i], expected[i]);
                errors = errors + 1;
            end
        end
        for (i = 0; i < 8; i = i + 1) begin
            if ((^expected[32+i] !== 1'bx) && u_dmem.mem[i] !== expected[32+i]) begin
                $display("FAIL: mem[%0d] = %08h, expected %08h",
                         i, u_dmem.mem[i], expected[32+i]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("=== tb_core_top: PASSED ===");
        else             $display("=== tb_core_top: FAILED (%0d errors) ===", errors);
        $finish;
    end

endmodule
