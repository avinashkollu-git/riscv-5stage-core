// riscv_defs.vh : shared opcodes and ALU control codes for the RV32I core.
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// RV32I opcodes
`define OP_RTYPE   7'b0110011
`define OP_ITYPE   7'b0010011   // ALU immediate
`define OP_LOAD    7'b0000011
`define OP_STORE   7'b0100011
`define OP_BRANCH  7'b1100011
`define OP_JAL     7'b1101111
`define OP_JALR    7'b1100111
`define OP_LUI     7'b0110111
`define OP_AUIPC   7'b0010111

// ALU control codes
`define ALU_ADD  4'd0
`define ALU_SUB  4'd1
`define ALU_AND  4'd2
`define ALU_OR   4'd3
`define ALU_XOR  4'd4
`define ALU_SLL  4'd5
`define ALU_SRL  4'd6
`define ALU_SRA  4'd7
`define ALU_SLT  4'd8
`define ALU_SLTU 4'd9
`define ALU_PASSB 4'd10   // pass operand B (for LUI)

// result-select (writeback source)
`define WB_ALU 2'd0
`define WB_MEM 2'd1
`define WB_PC4 2'd2        // return address for JAL/JALR

`endif
