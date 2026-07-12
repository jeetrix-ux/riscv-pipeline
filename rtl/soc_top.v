`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// soc_top.v - Board-level SoC for the Nexys A7-100T
//
// core_top + imem/dmem BRAMs + memory-mapped I/O. Any data address with
// bit 31 set is MMIO (reads come back with the same 1-cycle latency as
// dmem so the core cannot tell the difference):
//
//   0x8000_0000  W   LEDs[15:0]
//   0x8000_0004  R   switches[15:0]
//   0x8000_0008  W   7-seg display value (8 hex digits)
//   0x8000_000C  W   UART TX byte   /  R  bit0 = TX busy
//   0x8000_0010  R   perf: cycles
//   0x8000_0014  R   perf: instructions retired
//   0x8000_0018  R   perf: branches/jumps resolved
//   0x8000_001C  R   perf: mispredicts
//////////////////////////////////////////////////////////////////////////////

module soc_top #(
    parameter INIT_FILE = "demo.hex",    // imem contents (from sw/asm.py)
    parameter USE_MMCM  = 1              // 0 = clock bypass for simulation
)(
    input  wire        clk,              // 100 MHz board clock
    input  wire        cpu_resetn,       // reset button, active low
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [7:0]  an,
    output wire        uart_rxd_out      // FPGA TX -> host RX
);

    // ------------------------------------------------------------------
    // Clocking: everything below runs on the 50 MHz core clock
    // ------------------------------------------------------------------
    wire clk_core, mmcm_locked;

    clk_gen #(.USE_MMCM(USE_MMCM)) u_clk_gen (
        .clk_in  (clk),
        .clk_out (clk_core),
        .locked  (mmcm_locked)
    );

    // ------------------------------------------------------------------
    // Reset and switch synchronizers
    // ------------------------------------------------------------------
    reg [1:0] rst_sync;
    initial rst_sync = 2'b11;
    always @(posedge clk_core)
        rst_sync <= {rst_sync[0], ~cpu_resetn || ~mmcm_locked};
    wire rst = rst_sync[1];

    reg [15:0] sw_q, sw_qq;
    always @(posedge clk_core) begin
        sw_q  <= sw;
        sw_qq <= sw_q;
    end

    // ------------------------------------------------------------------
    // Core + memories
    // ------------------------------------------------------------------
    wire [31:0] imem_addr, imem_rdata;
    wire        imem_en;
    wire [31:0] dmem_addr, dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_re;
    wire        halted;
    wire [31:0] perf_cycles, perf_instret, perf_ctrl, perf_mispred;

    wire        is_mmio = dmem_addr[31];
    wire [31:0] ram_rdata;
    reg  [31:0] core_rdata;

    core_top u_core (
        .clk          (clk_core),
        .rst          (rst),
        .imem_addr    (imem_addr),
        .imem_en      (imem_en),
        .imem_rdata   (imem_rdata),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_wstrb   (dmem_wstrb),
        .dmem_re      (dmem_re),
        .dmem_rdata   (core_rdata),
        .halted       (halted),
        .perf_cycles  (perf_cycles),
        .perf_instret (perf_instret),
        .perf_ctrl    (perf_ctrl),
        .perf_mispred (perf_mispred)
    );

    imem #(.DEPTH_WORDS(4096), .INIT_FILE(INIT_FILE)) u_imem (
        .clk   (clk_core),
        .en    (imem_en),
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    dmem #(.DEPTH_WORDS(4096)) u_dmem (
        .clk   (clk_core),
        .re    (dmem_re && !is_mmio),
        .addr  (dmem_addr),
        .wstrb (is_mmio ? 4'b0000 : dmem_wstrb),
        .wdata (dmem_wdata),
        .rdata (ram_rdata)
    );

    // ------------------------------------------------------------------
    // MMIO registers
    // ------------------------------------------------------------------
    wire mmio_wr = is_mmio && (dmem_wstrb != 4'b0000);
    // (all logic below is on clk_core)

    reg [15:0] led_q;
    reg [31:0] seg_value_q;
    reg        uart_wr;
    reg [7:0]  uart_data;
    wire       uart_busy;

    always @(posedge clk_core) begin
        if (rst) begin
            led_q       <= 16'h0;
            seg_value_q <= 32'h0;
            uart_wr     <= 1'b0;
        end else begin
            uart_wr <= 1'b0;                       // 1-cycle write pulse
            if (mmio_wr) begin
                case (dmem_addr[4:2])
                    3'd0: led_q       <= dmem_wdata[15:0];
                    3'd2: seg_value_q <= dmem_wdata;
                    3'd3: begin
                        uart_wr   <= 1'b1;
                        uart_data <= dmem_wdata[7:0];
                    end
                    default: ;
                endcase
            end
        end
    end

    // MMIO reads: registered like the dmem read port, so the core sees
    // identical 1-cycle latency on both
    reg        mmio_sel_q;
    reg [31:0] mmio_rdata_q;

    always @(posedge clk_core) begin
        if (dmem_re) begin
            mmio_sel_q <= is_mmio;
            case (dmem_addr[4:2])
                3'd1:    mmio_rdata_q <= {16'h0, sw_qq};
                3'd3:    mmio_rdata_q <= {31'h0, uart_busy};
                3'd4:    mmio_rdata_q <= perf_cycles;
                3'd5:    mmio_rdata_q <= perf_instret;
                3'd6:    mmio_rdata_q <= perf_ctrl;
                default: mmio_rdata_q <= perf_mispred;
            endcase
        end
    end

    always @* core_rdata = mmio_sel_q ? mmio_rdata_q : ram_rdata;

    // ------------------------------------------------------------------
    // Peripherals
    // ------------------------------------------------------------------
    assign led = led_q;

    seg7_driver u_seg7 (
        .clk   (clk_core),
        .value (seg_value_q),
        .seg   (seg),
        .an    (an)
    );

    uart_tx #(.CLKS_PER_BIT(434)) u_uart_tx (   // 50 MHz / 115200
        .clk  (clk_core),
        .rst  (rst),
        .wr   (uart_wr),
        .data (uart_data),
        .busy (uart_busy),
        .tx   (uart_rxd_out)
    );

endmodule
