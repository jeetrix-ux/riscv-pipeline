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
//  - Branches and jumps resolve in EX and redirect the fetch PC. There is
//    no flush yet (arrives in M4), so the two wrong-path instructions
//    fetched behind a taken branch/jump DO execute: software must pad
//    2 NOPs after control flow.
//  - Full forwarding (M2): EX/MEM->EX and MEM/WB->EX paths plus the
//    regfile write-first bypass cover every RAW distance except a load's
//    result consumed at distance 1 (load-use) - that still requires one
//    intervening instruction until the M3 stall lands.
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
    // Hazard-control hooks (tied off until M3-M4)
    // ------------------------------------------------------------------
    wire stall_f  = 1'b0;   // TODO(M3): freeze PC on load-use hazard
    wire stall_d  = 1'b0;   // TODO(M3): freeze IF/ID on load-use hazard
    wire bubble_x = 1'b0;   // TODO(M3): inject bubble into ID/EX
    wire flush_d  = 1'b0;   // TODO(M4): kill wrong-path instr in IF/ID
    wire flush_x  = 1'b0;   // TODO(M4): kill wrong-path instr in ID/EX

    // ------------------------------------------------------------------
    // IF
    // ------------------------------------------------------------------
    reg  [31:0] pc_f;
    wire        redirect_x;
    wire [31:0] redirect_target_x;

    wire [31:0] pc_next = redirect_x ? redirect_target_x : pc_f + 32'd4;

    always @(posedge clk) begin
        if (rst)
            pc_f <= 32'h0;
        else if (!stall_f && !halted)
            pc_f <= pc_next;
    end

    assign imem_addr = pc_f;
    assign imem_en   = !stall_f && !halted;

    // ------------------------------------------------------------------
    // IF/ID  (instruction word itself is registered inside imem)
    // ------------------------------------------------------------------
    reg  [31:0] pc_d;
    reg         valid_d;
    wire [31:0] instr_d = imem_rdata;

    always @(posedge clk) begin
        if (rst) begin
            pc_d    <= 32'h0;
            valid_d <= 1'b0;
        end else if (!stall_d) begin
            pc_d    <= pc_f;
            valid_d <= !flush_d;
        end
    end

    // ------------------------------------------------------------------
    // ID
    // ------------------------------------------------------------------
    wire [4:0] rs1_d    = instr_d[19:15];
    wire [4:0] rs2_d    = instr_d[24:20];
    wire [4:0] rd_d     = instr_d[11:7];
    wire [2:0] funct3_d = instr_d[14:12];

    // writeback signals (driven in WB, used by the regfile write port)
    wire        rf_we_w;
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
        .is_illegal (is_illegal_d)
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
    reg [1:0]  wb_sel_x;
    reg [3:0]  alu_op_x;
    reg [1:0]  a_sel_x;
    reg        b_sel_x;

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
            valid_x     <= valid_d && !bubble_x && !flush_x && !is_illegal_d;
            reg_write_x <= reg_write_d;
            mem_read_x  <= mem_read_d;
            mem_write_x <= mem_write_d;
            is_branch_x <= is_branch_d;
            is_jal_x    <= is_jal_d;
            is_jalr_x   <= is_jalr_d;
            is_halt_x   <= is_halt_d;
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

    // ---- operand forwarding (M2) ----
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

    assign redirect_x        = valid_x && (is_jal_x || is_jalr_x ||
                                           (is_branch_x && br_taken_x));
    assign redirect_target_x = is_jalr_x ? jalr_target_x : pc_plus_imm_x;

    // ------------------------------------------------------------------
    // EX/MEM
    // ------------------------------------------------------------------
    reg [31:0] alu_y_m, store_data_m, pc4_m;
    reg [4:0]  rd_m;
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
            funct3_m     <= funct3_x;
        end
    end

    // EX/MEM result as it will eventually be written back (never a load:
    // the M3 hazard unit keeps load consumers out of EX at distance 1)
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

    assign dmem_addr  = alu_y_m;
    assign dmem_wdata = store_data_m << (8 * alu_y_m[1:0]);
    assign dmem_wstrb = (mem_write_m && valid_m && !halted) ? wstrb_m : 4'b0000;
    assign dmem_re    = mem_read_m && valid_m;

    // ------------------------------------------------------------------
    // MEM/WB  (load data word is registered inside dmem)
    // ------------------------------------------------------------------
    reg [31:0] alu_y_w, pc4_w;
    reg [2:0]  funct3_w;
    reg [1:0]  addr_lo_w;
    reg        valid_w;
    reg        reg_write_w, is_halt_w;
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
    // Forwarding
    // ------------------------------------------------------------------
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

endmodule
