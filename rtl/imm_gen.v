// imm_gen.v : sign-extended immediate generator for RV32I formats.
`timescale 1ns / 1ps
`default_nettype none
`include "riscv_defs.vh"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];
    always @(*) begin
        case (opcode)
            `OP_ITYPE, `OP_LOAD, `OP_JALR:   // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
            `OP_STORE:                        // S-type
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OP_BRANCH:                       // B-type
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
            `OP_LUI, `OP_AUIPC:               // U-type
                imm = {instr[31:12], 12'd0};
            `OP_JAL:                          // J-type
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'd0;
        endcase
    end
endmodule

`default_nettype wire
