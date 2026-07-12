`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// hazard_unit.v - Load-use hazard detection
//
// A load's data does not exist until WB (synchronous dmem read lands in
// the MEM/WB register), so a consumer at distance 1 cannot be forwarded
// to in EX - the EX/MEM "result" of a load is just its address. Detect
// that case while the consumer is still in ID: freeze PC and IF/ID for
// one cycle and inject a bubble into ID/EX. After the stall the consumer
// sees the load in MEM/WB and the ordinary FWD_WB path supplies the data.
//
// Exemption: a store's rs2 is not consumed in EX at all - the store data
// is only needed when the store performs its write in MEM, by which time
// a distance-1 load producer has reached WB. core_top's WB->MEM
// store-data forward covers that, so lw -> sw of the loaded value runs
// stall-free. (The store's rs1/address IS an EX consumer and still
// stalls.)
//////////////////////////////////////////////////////////////////////////////

module hazard_unit (
    // consumer in ID
    input  wire       valid_d,
    input  wire [4:0] rs1_d,
    input  wire [4:0] rs2_d,
    input  wire       uses_rs1_d,
    input  wire       uses_rs2_d,
    input  wire       is_store_d,

    // potential load producer in EX
    input  wire       valid_x,
    input  wire       mem_read_x,
    input  wire [4:0] rd_x,

    output wire       stall_f,
    output wire       stall_d,
    output wire       bubble_x
);

    wire load_x   = valid_x && mem_read_x && (rd_x != 5'd0);
    wire load_use = valid_d && load_x &&
                    ((uses_rs1_d && (rd_x == rs1_d)) ||
                     (uses_rs2_d && !is_store_d && (rd_x == rs2_d)));

    assign stall_f  = load_use;
    assign stall_d  = load_use;
    assign bubble_x = load_use;

endmodule
