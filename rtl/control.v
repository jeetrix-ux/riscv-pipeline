`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// control.v - Main decoder: instruction -> datapath control signals
//
// Illegal/unimplemented encodings decode to a NOP (is_illegal flags it
// for debug visibility; the pipeline treats it as a bubble-equivalent).
//////////////////////////////////////////////////////////////////////////////

`include "riscv_defs.vh"

module control (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg  [1:0]  wb_sel,
    output reg         mem_read,
    output reg         mem_write,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  a_sel,
    output reg         b_sel,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_halt,
    output reg         is_illegal,
    output reg         uses_rs1,    // rs1 field is a real source (hazard detection)
    output reg         uses_rs2     // rs2 field is a real source
);

    wire [6:0] opc  = instr[6:0];
    wire [2:0] f3   = instr[14:12];
    wire       f7b5 = instr[30];   // funct7[5]: sub/sra (and srai's imm[10])

    // funct3 -> ALU op for the OP / OP-IMM classes
    reg [3:0] op_from_f3;
    always @* begin
        case (f3)
            3'b000:  op_from_f3 = `ALU_ADD;
            3'b001:  op_from_f3 = `ALU_SLL;
            3'b010:  op_from_f3 = `ALU_SLT;
            3'b011:  op_from_f3 = `ALU_SLTU;
            3'b100:  op_from_f3 = `ALU_XOR;
            3'b101:  op_from_f3 = f7b5 ? `ALU_SRA : `ALU_SRL;
            3'b110:  op_from_f3 = `ALU_OR;
            default: op_from_f3 = `ALU_AND;
        endcase
    end

    always @* begin
        reg_write  = 1'b0;
        wb_sel     = `WB_ALU;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_op     = `ALU_ADD;
        a_sel      = `A_RS1;
        b_sel      = `B_IMM;
        is_branch  = 1'b0;
        is_jal     = 1'b0;
        is_jalr    = 1'b0;
        is_halt    = 1'b0;
        is_illegal = 1'b0;

        case (opc)
            `OPC_OP: begin
                reg_write = 1'b1;
                b_sel     = `B_RS2;
                alu_op    = (f3 == 3'b000 && f7b5) ? `ALU_SUB : op_from_f3;
            end
            `OPC_OPIMM: begin
                reg_write = 1'b1;
                alu_op    = op_from_f3;
            end
            `OPC_LUI: begin
                reg_write = 1'b1;
                a_sel     = `A_ZERO;
            end
            `OPC_AUIPC: begin
                reg_write = 1'b1;
                a_sel     = `A_PC;
            end
            `OPC_LOAD: begin
                reg_write = 1'b1;
                mem_read  = 1'b1;
                wb_sel    = `WB_MEM;
            end
            `OPC_STORE: begin
                mem_write = 1'b1;
            end
            `OPC_BRANCH: begin
                is_branch = 1'b1;
            end
            `OPC_JAL: begin
                reg_write = 1'b1;
                wb_sel    = `WB_PC4;
                is_jal    = 1'b1;
            end
            `OPC_JALR: begin
                reg_write = 1'b1;
                wb_sel    = `WB_PC4;
                is_jalr   = 1'b1;
            end
            `OPC_SYSTEM: begin
                is_halt   = 1'b1;   // ecall/ebreak: halt the core (no traps in RV32I scope)
            end
            `OPC_MISCMEM: ;         // fence: NOP on this single-hart in-order core
            default: begin
                is_illegal = 1'b1;  // decodes as NOP
            end
        endcase
    end

    // Which register fields are genuine sources. LUI/AUIPC/JAL carry
    // immediate bits where rs1/rs2 would sit - without this, those bits
    // could alias a load's rd and trigger a phantom load-use stall.
    always @* begin
        case (opc)
            `OPC_OP,
            `OPC_BRANCH,
            `OPC_STORE: begin uses_rs1 = 1'b1; uses_rs2 = 1'b1; end
            `OPC_OPIMM,
            `OPC_LOAD,
            `OPC_JALR:  begin uses_rs1 = 1'b1; uses_rs2 = 1'b0; end
            default:    begin uses_rs1 = 1'b0; uses_rs2 = 1'b0; end
        endcase
    end

endmodule
