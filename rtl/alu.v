// alu.v : 32-bit ALU for the RV32I core.
`timescale 1ns / 1ps
`default_nettype none
`include "riscv_defs.vh"

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  ctrl,
    output reg  [31:0] y,
    output wire        zero
);
    wire [4:0] shamt = b[4:0];
    always @(*) begin
        case (ctrl)
            `ALU_ADD : y = a + b;
            `ALU_SUB : y = a - b;
            `ALU_AND : y = a & b;
            `ALU_OR  : y = a | b;
            `ALU_XOR : y = a ^ b;
            `ALU_SLL : y = a << shamt;
            `ALU_SRL : y = a >> shamt;
            `ALU_SRA : y = $signed(a) >>> shamt;
            `ALU_SLT : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            `ALU_SLTU: y = (a < b) ? 32'd1 : 32'd0;
            `ALU_PASSB: y = b;
            default  : y = 32'd0;
        endcase
    end
    assign zero = (y == 32'd0);
endmodule

`default_nettype wire
