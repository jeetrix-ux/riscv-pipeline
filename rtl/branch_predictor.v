`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// branch_predictor.v - BTB + 2-bit bimodal direction predictor
//
// Looked up combinationally in IF: predict taken only when the BTB has a
// target for this PC (full tag, so no false hits between different PCs)
// AND the 2-bit counter for this PC says taken. Trained in EX when the
// branch/jump actually resolves.
//
//  - Counters start weakly-not-taken (01), saturate at 00/11.
//  - The BTB allocates on taken control flow only, so a never-taken
//    branch costs no BTB space.
//  - Jumps train their counter taken every time and quickly stick at 11.
//////////////////////////////////////////////////////////////////////////////

module branch_predictor #(
    parameter BTB_ENTRIES = 32,     // direct-mapped
    parameter CNT_ENTRIES = 256     // 2-bit saturating counters
)(
    input  wire        clk,

    // IF-stage lookup (combinational)
    input  wire [31:0] pc_f,
    output wire        pred_taken_f,
    output wire [31:0] pred_target_f,

    // EX-stage training (actual branch/jump outcome)
    input  wire        update_en,
    input  wire        taken_u,
    input  wire [31:0] pc_u,
    input  wire [31:0] target_u
);

    localparam integer BTB_AW = $clog2(BTB_ENTRIES);
    localparam integer CNT_AW = $clog2(CNT_ENTRIES);
    localparam integer TAG_W  = 30 - BTB_AW;   // full tag: rest of pc[31:2]

    reg              btb_valid [0:BTB_ENTRIES-1];
    reg [TAG_W-1:0]  btb_tag   [0:BTB_ENTRIES-1];
    reg [31:0]       btb_tgt   [0:BTB_ENTRIES-1];
    reg [1:0]        cnt       [0:CNT_ENTRIES-1];

    integer i;
    initial begin
        for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
            btb_valid[i] = 1'b0;
            btb_tag[i]   = {TAG_W{1'b0}};
            btb_tgt[i]   = 32'h0;
        end
        for (i = 0; i < CNT_ENTRIES; i = i + 1)
            cnt[i] = 2'b01;                    // weakly not-taken
    end

    // ---- IF lookup ----
    wire [BTB_AW-1:0] idx_f  = pc_f[BTB_AW+1:2];
    wire [TAG_W-1:0]  tag_f  = pc_f[31:BTB_AW+2];
    wire [CNT_AW-1:0] cidx_f = pc_f[CNT_AW+1:2];

    wire btb_hit_f = btb_valid[idx_f] && (btb_tag[idx_f] == tag_f);

    assign pred_taken_f  = btb_hit_f && cnt[cidx_f][1];
    assign pred_target_f = btb_tgt[idx_f];

    // ---- EX training ----
    wire [BTB_AW-1:0] idx_u  = pc_u[BTB_AW+1:2];
    wire [TAG_W-1:0]  tag_u  = pc_u[31:BTB_AW+2];
    wire [CNT_AW-1:0] cidx_u = pc_u[CNT_AW+1:2];

    always @(posedge clk) begin
        if (update_en) begin
            if (taken_u) begin
                if (cnt[cidx_u] != 2'b11) cnt[cidx_u] <= cnt[cidx_u] + 2'd1;
                btb_valid[idx_u] <= 1'b1;
                btb_tag[idx_u]   <= tag_u;
                btb_tgt[idx_u]   <= target_u;
            end else begin
                if (cnt[cidx_u] != 2'b00) cnt[cidx_u] <= cnt[cidx_u] - 2'd1;
            end
        end
    end

endmodule
