// control_unit.v : main decoder. Produces datapath control signals and the
//   4-bit ALU control from opcode / funct3 / funct7.
`timescale 1ns / 1ps
`default_nettype none
`include "riscv_defs.vh"

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_5,   // instr[30], distinguishes ADD/SUB, SRL/SRA
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        alu_src,    // 1 => operand B is the immediate
    output reg        branch,
    output reg        jump,       // JAL/JALR
    output reg        jalr,       // JALR specifically (target = rs1+imm)
    output reg        alu_a_pc,   // AUIPC: ALU operand A is the PC
    output reg [1:0]  wb_sel,     // writeback source
    output reg [3:0]  alu_ctrl
);
    always @(*) begin
        // safe defaults (a NOP writes nothing)
        reg_write = 1'b0; mem_read = 1'b0; mem_write = 1'b0;
        alu_src   = 1'b0; branch   = 1'b0; jump      = 1'b0; jalr = 1'b0;
        alu_a_pc  = 1'b0;
        wb_sel    = `WB_ALU; alu_ctrl = `ALU_ADD;

        case (opcode)
            `OP_RTYPE: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = funct7_5 ? `ALU_SUB : `ALU_ADD;
                    3'b111: alu_ctrl = `ALU_AND;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b001: alu_ctrl = `ALU_SLL;
                    3'b101: alu_ctrl = funct7_5 ? `ALU_SRA : `ALU_SRL;
                    3'b010: alu_ctrl = `ALU_SLT;
                    3'b011: alu_ctrl = `ALU_SLTU;
                    default: alu_ctrl = `ALU_ADD;
                endcase
            end

            `OP_ITYPE: begin
                reg_write = 1'b1; alu_src = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADD;   // ADDI
                    3'b111: alu_ctrl = `ALU_AND;   // ANDI
                    3'b110: alu_ctrl = `ALU_OR;    // ORI
                    3'b100: alu_ctrl = `ALU_XOR;   // XORI
                    3'b001: alu_ctrl = `ALU_SLL;   // SLLI
                    3'b101: alu_ctrl = funct7_5 ? `ALU_SRA : `ALU_SRL; // SRAI/SRLI
                    3'b010: alu_ctrl = `ALU_SLT;   // SLTI
                    3'b011: alu_ctrl = `ALU_SLTU;  // SLTIU
                    default: alu_ctrl = `ALU_ADD;
                endcase
            end

            `OP_LOAD: begin
                reg_write = 1'b1; alu_src = 1'b1; mem_read = 1'b1;
                wb_sel = `WB_MEM; alu_ctrl = `ALU_ADD;   // address = rs1 + imm
            end

            `OP_STORE: begin
                alu_src = 1'b1; mem_write = 1'b1; alu_ctrl = `ALU_ADD;
            end

            `OP_BRANCH: begin
                branch = 1'b1; alu_ctrl = `ALU_SUB;  // comparator handled in EX
            end

            `OP_JAL: begin
                reg_write = 1'b1; jump = 1'b1; wb_sel = `WB_PC4;
            end

            `OP_JALR: begin
                reg_write = 1'b1; jump = 1'b1; jalr = 1'b1;
                alu_src = 1'b1; wb_sel = `WB_PC4;
            end

            `OP_LUI: begin
                reg_write = 1'b1; alu_src = 1'b1; alu_ctrl = `ALU_PASSB;
            end

            `OP_AUIPC: begin
                reg_write = 1'b1; alu_src = 1'b1; alu_ctrl = `ALU_ADD;
                alu_a_pc  = 1'b1;   // operand A is PC
            end

            default: ; // NOP / unknown -> all defaults (no writes)
        endcase
    end
endmodule

`default_nettype wire
