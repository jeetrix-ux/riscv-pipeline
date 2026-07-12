`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// core_top.v - 5-stage pipelined RV32I core
//
// Pipeline: IF -> ID -> EX -> MEM -> WB
//
//  - imem/dmem are external synchronous-read memories (1-cycle latency).
//    Their output registers double as the IF/ID instruction register and
//    the MEM/WB load-data register respectively, so neither is duplicated
//    here.
//  - Control flow: a BTB + 2-bit bimodal predictor steers the fetch PC.
//    Branches and jumps still resolve in EX; only a MISprediction (wrong
//    direction or wrong target) redirects and flushes the two younger
//    wrong-path instructions, so a correctly predicted taken branch
//    costs 0 cycles instead of the old fixed 2-cycle penalty.
//  - Perf counters (cycles, retired instrs, control flow, mispredicts)
//    let software and the testbench compute CPI and predictor accuracy.
//  - Full forwarding: EX/MEM->EX and MEM/WB->EX paths plus the regfile
//    write-first bypass cover every RAW distance except a load's result
//    consumed at distance 1 (load-use).
//  - Load-use: the hazard unit freezes PC + IF/ID for one cycle and
//    bubbles ID/EX, turning the distance-1 consumer into a distance-2 one
//    that the FWD_WB path serves. A store's rs2 is exempt: store data is
//    consumed in MEM, where a WB->MEM forward delivers a distance-1 load
//    result just in time (lw -> sw runs stall-free).
//  - ecall/ebreak assert `halted` on reaching WB; all architectural
//    writes are suppressed once halted.
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module core_top (
    input  wire        clk,
    input  wire        rst,

    // instruction memory (sync read, 1-cycle latency)
    output wire [31:0] imem_addr,
    output wire        imem_en,
    input  wire [31:0] imem_rdata,

    // data memory (sync read, 1-cycle latency; byte-writeable)
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,

    output reg         halted
);

    // ------------------------------------------------------------------
    // Hazard controls
    //
    // stall/bubble come from hazard_unit (bottom of file); the flushes
    // are assigned in EX where the redirect is computed. Stall and flush
    // are mutually exclusive by construction: a stall needs a load in EX,
    // a flush needs a branch/jump in EX.
    // ------------------------------------------------------------------
    wire stall_f, stall_d, bubble_x;
    wire flush_d, flush_x;

    // ------------------------------------------------------------------
    // IF
    // ------------------------------------------------------------------
    reg  [31:0] pc_f;
    wire        redirect_x;
    wire [31:0] redirect_target_x;

    // predictor lookup for the PC being fetched (the instance lives in
    // the EX section, next to the resolution logic that trains it)
    wire        pred_taken_f;
    wire [31:0] pred_target_f;

    // an EX redirect (= detected misprediction) beats the IF prediction
    wire [31:0] pc_next = redirect_x     ? redirect_target_x :
                          pred_taken_f   ? pred_target_f     :
                                           pc_f + 32'd4;

    always @(posedge clk) begin
        if (rst)
            pc_f <= 32'h0;
        else if ((!stall_f || redirect_x) && !halted)   // flush beats stall
            pc_f <= pc_next;
    end

    assign imem_addr = pc_f;
    assign imem_en   = !stall_f && !halted;

    // ------------------------------------------------------------------
    // IF/ID  (instruction word itself is registered inside imem)
    // ------------------------------------------------------------------
    reg  [31:0] pc_d;
    reg         valid_d;
    reg         pred_taken_d;            // what IF predicted for this slot,
    reg  [31:0] pred_target_d;           // carried along for the EX check
    wire [31:0] instr_d = imem_rdata;

    always @(posedge clk) begin
        if (rst) begin
            pc_d          <= 32'h0;
            valid_d       <= 1'b0;
            pred_taken_d  <= 1'b0;
            pred_target_d <= 32'h0;
        end else if (flush_d) begin      // flush beats stall (they can't
            pc_d          <= pc_f;       // coincide, but priority is explicit)
            valid_d       <= 1'b0;
            pred_taken_d  <= 1'b0;
        end else if (!stall_d) begin
            pc_d          <= pc_f;
            valid_d       <= 1'b1;
            pred_taken_d  <= pred_taken_f;
            pred_target_d <= pred_target_f;
        end
    end

    // ------------------------------------------------------------------
    // ID
    // ------------------------------------------------------------------
    wire [4:0] rs1_d    = instr_d[19:15];
    wire [4:0] rs2_d    = instr_d[24:20];
    wire [4:0] rd_d     = instr_d[11:7];
    wire [2:0] funct3_d = instr_d[14:12];

    // writeback signals (driven in WB; used by the regfile write port and
    // the MEM-stage store-data forward, hence declared up here)
    wire        rf_we_w;
    reg         reg_write_w, valid_w;
    reg  [4:0]  rd_w;
    reg  [31:0] rf_wdata_w;

    wire [31:0] rf_rdata1_d, rf_rdata2_d, imm_d;

    regfile u_regfile (
        .clk    (clk),
        .raddr1 (rs1_d),
        .raddr2 (rs2_d),
        .rdata1 (rf_rdata1_d),
        .rdata2 (rf_rdata2_d),
        .we     (rf_we_w),
        .waddr  (rd_w),
        .wdata  (rf_wdata_w)
    );

    imm_gen u_imm_gen (
        .instr (instr_d),
        .imm   (imm_d)
    );

    wire       reg_write_d, mem_read_d, mem_write_d;
    wire       is_branch_d, is_jal_d, is_jalr_d, is_halt_d, is_illegal_d;
    wire       uses_rs1_d, uses_rs2_d;
    wire [1:0] wb_sel_d;
    wire [3:0] alu_op_d;
    wire [1:0] a_sel_d;
    wire       b_sel_d;

    control u_control (
        .instr      (instr_d),
        .reg_write  (reg_write_d),
        .wb_sel     (wb_sel_d),
        .mem_read   (mem_read_d),
        .mem_write  (mem_write_d),
        .alu_op     (alu_op_d),
        .a_sel      (a_sel_d),
        .b_sel      (b_sel_d),
        .is_branch  (is_branch_d),
        .is_jal     (is_jal_d),
        .is_jalr    (is_jalr_d),
        .is_halt    (is_halt_d),
        .is_illegal (is_illegal_d),
        .uses_rs1   (uses_rs1_d),
        .uses_rs2   (uses_rs2_d)
    );

    // ------------------------------------------------------------------
    // ID/EX
    // ------------------------------------------------------------------
    reg [31:0] pc_x, rs1_data_x, rs2_data_x, imm_x;
    reg [4:0]  rs1_x, rs2_x, rd_x;
    reg [2:0]  funct3_x;
    reg        valid_x;
    reg        reg_write_x, mem_read_x, mem_write_x;
    reg        is_branch_x, is_jal_x, is_jalr_x, is_halt_x;
    reg        pred_taken_x;
    reg [31:0] pred_target_x;
    reg [1:0]  wb_sel_x;
    reg [3:0]  alu_op_x;
    reg [1:0]  a_sel_x;
    reg        b_sel_x;

    wire kill_x = bubble_x || flush_x;   // slot entering EX is dead

    always @(posedge clk) begin
        if (rst) begin
            valid_x     <= 1'b0;
            reg_write_x <= 1'b0;
            mem_read_x  <= 1'b0;
            mem_write_x <= 1'b0;
            is_branch_x <= 1'b0;
            is_jal_x    <= 1'b0;
            is_jalr_x   <= 1'b0;
            is_halt_x   <= 1'b0;
            pred_taken_x <= 1'b0;
            pred_target_x <= 32'h0;
            wb_sel_x    <= `WB_ALU;
            alu_op_x    <= `ALU_ADD;
            a_sel_x     <= `A_RS1;
            b_sel_x     <= `B_RS2;
            pc_x        <= 32'h0;
            rs1_data_x  <= 32'h0;
            rs2_data_x  <= 32'h0;
            imm_x       <= 32'h0;
            rs1_x       <= 5'd0;
            rs2_x       <= 5'd0;
            rd_x        <= 5'd0;
            funct3_x    <= 3'd0;
        end else begin
            // on a kill the action bits are cleared too, not just valid,
            // so a bubbled/flushed slot never looks like a producer, a
            // memory op, or a branch to the hazard/forward/redirect logic
            valid_x     <= valid_d && !kill_x && !is_illegal_d;
            reg_write_x <= reg_write_d && !kill_x;
            mem_read_x  <= mem_read_d  && !kill_x;
            mem_write_x <= mem_write_d && !kill_x;
            is_branch_x <= is_branch_d && !kill_x;
            is_jal_x    <= is_jal_d    && !kill_x;
            is_jalr_x   <= is_jalr_d   && !kill_x;
            is_halt_x   <= is_halt_d   && !kill_x;
            pred_taken_x <= pred_taken_d && !kill_x;
            pred_target_x <= pred_target_d;
            wb_sel_x    <= wb_sel_d;
            alu_op_x    <= alu_op_d;
            a_sel_x     <= a_sel_d;
            b_sel_x     <= b_sel_d;
            pc_x        <= pc_d;
            rs1_data_x  <= rf_rdata1_d;
            rs2_data_x  <= rf_rdata2_d;
            imm_x       <= imm_d;
            rs1_x       <= rs1_d;
            rs2_x       <= rs2_d;
            rd_x        <= rd_d;
            funct3_x    <= funct3_d;
        end
    end

    // ------------------------------------------------------------------
    // EX
    // ------------------------------------------------------------------

    // ---- operand forwarding ----
    // fwd selects and result_m/rf_wdata_w are driven further down, next
    // to the pipeline registers that produce them
    wire [1:0]  fwd_a_x, fwd_b_x;
    wire [31:0] result_m;        // EX/MEM result as it will be written back
    reg  [31:0] rs1_fwd_x, rs2_fwd_x;

    always @* begin
        case (fwd_a_x)
            `FWD_MEM: rs1_fwd_x = result_m;
            `FWD_WB:  rs1_fwd_x = rf_wdata_w;
            default:  rs1_fwd_x = rs1_data_x;
        endcase
        case (fwd_b_x)
            `FWD_MEM: rs2_fwd_x = result_m;
            `FWD_WB:  rs2_fwd_x = rf_wdata_w;
            default:  rs2_fwd_x = rs2_data_x;
        endcase
    end

    reg  [31:0] alu_a_x, alu_b_x;
    wire [31:0] alu_y_x;

    always @* begin
        case (a_sel_x)
            `A_RS1:  alu_a_x = rs1_fwd_x;
            `A_PC:   alu_a_x = pc_x;
            default: alu_a_x = 32'h0;      // A_ZERO (LUI)
        endcase
        alu_b_x = (b_sel_x == `B_IMM) ? imm_x : rs2_fwd_x;
    end

    alu u_alu (
        .op (alu_op_x),
        .a  (alu_a_x),
        .b  (alu_b_x),
        .y  (alu_y_x)
    );

    wire br_taken_x;
    branch_unit u_branch_unit (
        .funct3 (funct3_x),
        .a      (rs1_fwd_x),
        .b      (rs2_fwd_x),
        .taken  (br_taken_x)
    );

    wire [31:0] pc_plus_imm_x = pc_x + imm_x;                       // branch/JAL target
    wire [31:0] jalr_target_x = (rs1_fwd_x + imm_x) & 32'hFFFF_FFFE;
    wire [31:0] pc4_x         = pc_x + 32'd4;

    // ---- prediction check ----
    // The fetch already followed the IF prediction, so EX only redirects
    // when that prediction was wrong: wrong direction, wrong target
    // (JALR, or a stale BTB entry), or a BTB hit that predicted taken
    // for something that is not control flow at all.
    wire        is_ctrl_x       = is_branch_x || is_jal_x || is_jalr_x;
    wire        actual_taken_x  = is_jal_x || is_jalr_x ||
                                  (is_branch_x && br_taken_x);
    wire [31:0] actual_target_x = is_jalr_x ? jalr_target_x : pc_plus_imm_x;

    wire dir_wrong_x = actual_taken_x != pred_taken_x;
    wire tgt_wrong_x = actual_taken_x && pred_taken_x &&
                       (pred_target_x != actual_target_x);

    assign redirect_x = valid_x &&
                        ((is_ctrl_x && (dir_wrong_x || tgt_wrong_x)) ||
                         (!is_ctrl_x && pred_taken_x));
    assign redirect_target_x = actual_taken_x ? actual_target_x : pc4_x;

    // Mispredict flush: a redirect means the two younger instructions -
    // one in ID, one arriving from IF - are wrong-path. Kill both; the
    // corrected fetch lands 2 cycles later.
    assign flush_d = redirect_x;
    assign flush_x = redirect_x;

    // train the predictor on every resolved branch/jump
    wire bp_update_x = valid_x && is_ctrl_x;

    branch_predictor u_branch_predictor (
        .clk           (clk),
        .pc_f          (pc_f),
        .pred_taken_f  (pred_taken_f),
        .pred_target_f (pred_target_f),
        .update_en     (bp_update_x),
        .taken_u       (actual_taken_x),
        .pc_u          (pc_x),
        .target_u      (actual_target_x)
    );

    // ------------------------------------------------------------------
    // EX/MEM
    // ------------------------------------------------------------------
    reg [31:0] alu_y_m, store_data_m, pc4_m;
    reg [4:0]  rd_m, rs2_m;       // rs2 kept for the WB->MEM store-data forward
    reg [2:0]  funct3_m;
    reg        valid_m;
    reg        reg_write_m, mem_read_m, mem_write_m, is_halt_m;
    reg [1:0]  wb_sel_m;

    always @(posedge clk) begin
        if (rst) begin
            valid_m      <= 1'b0;
            reg_write_m  <= 1'b0;
            mem_read_m   <= 1'b0;
            mem_write_m  <= 1'b0;
            is_halt_m    <= 1'b0;
            wb_sel_m     <= `WB_ALU;
            alu_y_m      <= 32'h0;
            store_data_m <= 32'h0;
            pc4_m        <= 32'h0;
            rd_m         <= 5'd0;
            rs2_m        <= 5'd0;
            funct3_m     <= 3'd0;
        end else begin
            valid_m      <= valid_x;
            reg_write_m  <= reg_write_x;
            mem_read_m   <= mem_read_x;
            mem_write_m  <= mem_write_x;
            is_halt_m    <= is_halt_x;
            wb_sel_m     <= wb_sel_x;
            alu_y_m      <= alu_y_x;
            store_data_m <= rs2_fwd_x;   // store data is an EX consumer too
            pc4_m        <= pc4_x;
            rd_m         <= rd_x;
            rs2_m        <= rs2_x;
            funct3_m     <= funct3_x;
        end
    end

    // EX/MEM result as it will eventually be written back (never a load:
    // the hazard unit keeps load consumers out of EX at distance 1)
    assign result_m = (wb_sel_m == `WB_PC4) ? pc4_m : alu_y_m;

    // ------------------------------------------------------------------
    // MEM
    // ------------------------------------------------------------------
    reg [3:0] wstrb_m;

    always @* begin
        case (funct3_m[1:0])
            2'b00:   wstrb_m = 4'b0001 << alu_y_m[1:0];   // sb
            2'b01:   wstrb_m = 4'b0011 << alu_y_m[1:0];   // sh
            default: wstrb_m = 4'b1111;                   // sw
        endcase
    end

    // WB->MEM store-data forward: the instruction in WB is the youngest
    // one older than this store, so if it writes the store's rs2 its
    // value is architecturally the one to store. This is what lets a
    // store consume a distance-1 load result without a stall (the hazard
    // unit exempts store rs2 on the strength of this path).
    wire [31:0] store_data_fwd_m =
        (reg_write_w && valid_w && (rd_w != 5'd0) && (rd_w == rs2_m))
            ? rf_wdata_w : store_data_m;

    assign dmem_addr  = alu_y_m;
    assign dmem_wdata = store_data_fwd_m << (8 * alu_y_m[1:0]);
    assign dmem_wstrb = (mem_write_m && valid_m && !halted) ? wstrb_m : 4'b0000;
    assign dmem_re    = mem_read_m && valid_m;

    // ------------------------------------------------------------------
    // MEM/WB  (load data word is registered inside dmem)
    // ------------------------------------------------------------------
    reg [31:0] alu_y_w, pc4_w;
    reg [2:0]  funct3_w;
    reg [1:0]  addr_lo_w;
    reg        is_halt_w;
    reg [1:0]  wb_sel_w;

    always @(posedge clk) begin
        if (rst) begin
            valid_w     <= 1'b0;
            reg_write_w <= 1'b0;
            is_halt_w   <= 1'b0;
            wb_sel_w    <= `WB_ALU;
            alu_y_w     <= 32'h0;
            pc4_w       <= 32'h0;
            rd_w        <= 5'd0;
            funct3_w    <= 3'd0;
            addr_lo_w   <= 2'd0;
        end else begin
            valid_w     <= valid_m;
            reg_write_w <= reg_write_m;
            is_halt_w   <= is_halt_m;
            wb_sel_w    <= wb_sel_m;
            alu_y_w     <= alu_y_m;
            pc4_w       <= pc4_m;
            rd_w        <= rd_m;
            funct3_w    <= funct3_m;
            addr_lo_w   <= alu_y_m[1:0];
        end
    end

    // ------------------------------------------------------------------
    // WB
    // ------------------------------------------------------------------
    wire [31:0] load_shifted_w = dmem_rdata >> (8 * addr_lo_w);
    reg  [31:0] load_data_w;

    always @* begin
        case (funct3_w)
            3'b000:  load_data_w = {{24{load_shifted_w[7]}},  load_shifted_w[7:0]};   // lb
            3'b001:  load_data_w = {{16{load_shifted_w[15]}}, load_shifted_w[15:0]};  // lh
            3'b100:  load_data_w = {24'h0, load_shifted_w[7:0]};                      // lbu
            3'b101:  load_data_w = {16'h0, load_shifted_w[15:0]};                     // lhu
            default: load_data_w = load_shifted_w;                                    // lw
        endcase
    end

    always @* begin
        case (wb_sel_w)
            `WB_MEM: rf_wdata_w = load_data_w;
            `WB_PC4: rf_wdata_w = pc4_w;
            default: rf_wdata_w = alu_y_w;
        endcase
    end

    assign rf_we_w = reg_write_w && valid_w && !halted;

    // ------------------------------------------------------------------
    // Hazard detection and forwarding
    // ------------------------------------------------------------------
    hazard_unit u_hazard_unit (
        .valid_d    (valid_d),
        .rs1_d      (rs1_d),
        .rs2_d      (rs2_d),
        .uses_rs1_d (uses_rs1_d),
        .uses_rs2_d (uses_rs2_d),
        .is_store_d (mem_write_d),
        .valid_x    (valid_x),
        .mem_read_x (mem_read_x),
        .rd_x       (rd_x),
        .stall_f    (stall_f),
        .stall_d    (stall_d),
        .bubble_x   (bubble_x)
    );

    forward_unit u_forward_unit (
        .rs1_x       (rs1_x),
        .rs2_x       (rs2_x),
        .reg_write_m (reg_write_m),
        .valid_m     (valid_m),
        .rd_m        (rd_m),
        .reg_write_w (reg_write_w),
        .valid_w     (valid_w),
        .rd_w        (rd_w),
        .fwd_a       (fwd_a_x),
        .fwd_b       (fwd_b_x)
    );

    always @(posedge clk) begin
        if (rst)
            halted <= 1'b0;
        else if (is_halt_w && valid_w)
            halted <= 1'b1;
    end

    // ------------------------------------------------------------------
    // Performance counters
    //
    // cycles/instret give CPI; ctrl/mispred give predictor accuracy.
    // Every EX redirect is by definition a misprediction now, so
    // redirect_x is the mispredict count. Read hierarchically by the
    // testbench; memory-mapped for software at board bring-up (M8).
    // ------------------------------------------------------------------
    reg [31:0] perf_cycles, perf_instret, perf_ctrl, perf_mispred;

    always @(posedge clk) begin
        if (rst) begin
            perf_cycles  <= 32'h0;
            perf_instret <= 32'h0;
            perf_ctrl    <= 32'h0;
            perf_mispred <= 32'h0;
        end else if (!halted) begin
            perf_cycles <= perf_cycles + 32'd1;
            if (valid_w)     perf_instret <= perf_instret + 32'd1;
            if (bp_update_x) perf_ctrl    <= perf_ctrl    + 32'd1;
            if (redirect_x)  perf_mispred <= perf_mispred + 32'd1;
        end
    end

endmodule
