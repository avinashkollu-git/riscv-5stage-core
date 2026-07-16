// -----------------------------------------------------------------------------
// riscv_core.v : 32-bit RV32I 5-stage pipelined processor.
//
//   Stages:  IF -> ID -> EX -> MEM -> WB
//   Hazards: - full EX-stage forwarding from EX/MEM and MEM/WB
//            - one-cycle load-use stall (detected in ID)
//            - branches/jumps resolve in EX; IF/ID and ID/EX are flushed on a
//              taken redirect (2-cycle penalty)
//
//   Memories are word-addressed. Program is loaded from a hex file given by the
//   IMEM_FILE parameter via $readmemh. Loads/stores are word-granular (LW/SW).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none
`include "riscv_defs.vh"

module riscv_core #(
    parameter IMEM_FILE = "program.hex",
    parameter integer IMEM_WORDS = 64,    // instruction ROM depth (assembler pads to this)
    parameter integer DMEM_WORDS = 64
) (
    input  wire clk,
    input  wire rst_n
);
    // =====================================================================
    // IF stage
    // =====================================================================
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;

    reg  [31:0] imem [0:IMEM_WORDS-1];
    integer imem_i;
    initial begin
        for (imem_i = 0; imem_i < IMEM_WORDS; imem_i = imem_i + 1)
            imem[imem_i] = 32'h0000_0000;   // unprogrammed words default to 0 (NOP-ish)
        $readmemh(IMEM_FILE, imem);
    end

    wire [31:0] if_instr = imem[pc[31:2] % IMEM_WORDS];

    // Redirect and stall controls (driven from later stages, below).
    wire        pcsrc;          // EX taken branch/jump
    wire [31:0] ex_target;
    wire        stall;          // load-use bubble

    always @(posedge clk) begin
        if (!rst_n)          pc <= 32'd0;
        else if (pcsrc)      pc <= ex_target;
        else if (stall)      pc <= pc;          // freeze
        else                 pc <= pc_plus4;
    end

    // =====================================================================
    // IF/ID pipeline register
    // =====================================================================
    reg [31:0] ifid_pc, ifid_instr;
    always @(posedge clk) begin
        if (!rst_n || pcsrc) begin       // flush on redirect
            ifid_pc    <= 32'd0;
            ifid_instr <= 32'd0;         // NOP bubble
        end else if (stall) begin        // hold
            ifid_pc    <= ifid_pc;
            ifid_instr <= ifid_instr;
        end else begin
            ifid_pc    <= pc;
            ifid_instr <= if_instr;
        end
    end

    // =====================================================================
    // ID stage : decode, register read, immediate
    // =====================================================================
    wire [6:0] opcode = ifid_instr[6:0];
    wire [4:0] rs1    = ifid_instr[19:15];
    wire [4:0] rs2    = ifid_instr[24:20];
    wire [4:0] rd     = ifid_instr[11:7];
    wire [2:0] funct3 = ifid_instr[14:12];
    wire       funct7_5 = ifid_instr[30];

    wire        c_reg_write, c_mem_read, c_mem_write, c_alu_src;
    wire        c_branch, c_jump, c_jalr, c_alu_a_pc;
    wire [1:0]  c_wb_sel;
    wire [3:0]  c_alu_ctrl;

    control_unit u_ctrl (
        .opcode(opcode), .funct3(funct3), .funct7_5(funct7_5),
        .reg_write(c_reg_write), .mem_read(c_mem_read), .mem_write(c_mem_write),
        .alu_src(c_alu_src), .branch(c_branch), .jump(c_jump), .jalr(c_jalr),
        .alu_a_pc(c_alu_a_pc), .wb_sel(c_wb_sel), .alu_ctrl(c_alu_ctrl)
    );

    wire [31:0] rd1, rd2, imm;

    // regfile write signals come from WB stage (declared later)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile u_rf (
        .clk(clk), .we(wb_reg_write),
        .ra1(rs1), .ra2(rs2), .wa(wb_rd), .wd(wb_data),
        .rd1(rd1), .rd2(rd2)
    );

    imm_gen u_imm (.instr(ifid_instr), .imm(imm));

    // ---- load-use hazard detection ----
    // If the instruction in EX is a load whose rd is a source of the ID
    // instruction, stall one cycle.
    wire idex_mem_read;   // from ID/EX (declared below)
    wire [4:0] idex_rd;
    assign stall = idex_mem_read && (idex_rd != 5'd0) &&
                   ((idex_rd == rs1) || (idex_rd == rs2));

    // Bubble injected into ID/EX when stalling or flushing.
    wire id_bubble = stall || pcsrc;

    // =====================================================================
    // ID/EX pipeline register
    // =====================================================================
    reg        idex_reg_write, idex_mem_read_r, idex_mem_write, idex_alu_src;
    reg        idex_branch, idex_jump, idex_jalr, idex_alu_a_pc;
    reg [1:0]  idex_wb_sel;
    reg [3:0]  idex_alu_ctrl;
    reg [2:0]  idex_funct3;
    reg [31:0] idex_pc, idex_rd1, idex_rd2, idex_imm;
    reg [4:0]  idex_rs1, idex_rs2, idex_rd_r;

    assign idex_mem_read = idex_mem_read_r;
    assign idex_rd       = idex_rd_r;

    always @(posedge clk) begin
        if (!rst_n || id_bubble) begin
            idex_reg_write <= 1'b0; idex_mem_read_r <= 1'b0; idex_mem_write <= 1'b0;
            idex_alu_src   <= 1'b0; idex_branch     <= 1'b0; idex_jump      <= 1'b0;
            idex_jalr      <= 1'b0; idex_alu_a_pc   <= 1'b0; idex_wb_sel    <= 2'd0;
            idex_alu_ctrl  <= 4'd0; idex_funct3     <= 3'd0;
            idex_pc  <= 32'd0; idex_rd1 <= 32'd0; idex_rd2 <= 32'd0; idex_imm <= 32'd0;
            idex_rs1 <= 5'd0;  idex_rs2 <= 5'd0;  idex_rd_r <= 5'd0;
        end else begin
            idex_reg_write <= c_reg_write; idex_mem_read_r <= c_mem_read;
            idex_mem_write <= c_mem_write; idex_alu_src    <= c_alu_src;
            idex_branch    <= c_branch;    idex_jump       <= c_jump;
            idex_jalr      <= c_jalr;      idex_alu_a_pc   <= c_alu_a_pc;
            idex_wb_sel    <= c_wb_sel;    idex_alu_ctrl   <= c_alu_ctrl;
            idex_funct3    <= funct3;
            idex_pc  <= ifid_pc; idex_rd1 <= rd1; idex_rd2 <= rd2; idex_imm <= imm;
            idex_rs1 <= rs1;     idex_rs2 <= rs2; idex_rd_r <= rd;
        end
    end

    // =====================================================================
    // EX stage : forwarding, ALU, branch resolution
    // =====================================================================
    // EX/MEM and MEM/WB forwarding sources (declared below).
    wire        exmem_reg_write;
    wire [4:0]  exmem_rd;
    wire [31:0] exmem_alu;

    // forward select: 2'b10 => from EX/MEM, 2'b01 => from MEM/WB, 2'b00 => regfile
    reg [1:0] fwd_a, fwd_b;
    always @(*) begin
        fwd_a = 2'b00;
        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs1)
            fwd_a = 2'b10;
        else if (wb_reg_write && wb_rd != 5'd0 && wb_rd == idex_rs1)
            fwd_a = 2'b01;

        fwd_b = 2'b00;
        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs2)
            fwd_b = 2'b10;
        else if (wb_reg_write && wb_rd != 5'd0 && wb_rd == idex_rs2)
            fwd_b = 2'b01;
    end

    reg [31:0] fwd_rs1, fwd_rs2;
    always @(*) begin
        case (fwd_a)
            2'b10:   fwd_rs1 = exmem_alu;
            2'b01:   fwd_rs1 = wb_data;
            default: fwd_rs1 = idex_rd1;
        endcase
        case (fwd_b)
            2'b10:   fwd_rs2 = exmem_alu;
            2'b01:   fwd_rs2 = wb_data;
            default: fwd_rs2 = idex_rd2;
        endcase
    end

    wire [31:0] alu_a = idex_alu_a_pc ? idex_pc  : fwd_rs1;
    wire [31:0] alu_b = idex_alu_src  ? idex_imm : fwd_rs2;

    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu (.a(alu_a), .b(alu_b), .ctrl(idex_alu_ctrl), .y(alu_y), .zero(alu_zero));

    // branch comparator (uses forwarded register values)
    reg branch_take;
    always @(*) begin
        case (idex_funct3)
            3'b000:  branch_take = (fwd_rs1 == fwd_rs2);                 // BEQ
            3'b001:  branch_take = (fwd_rs1 != fwd_rs2);                 // BNE
            3'b100:  branch_take = ($signed(fwd_rs1) <  $signed(fwd_rs2)); // BLT
            3'b101:  branch_take = ($signed(fwd_rs1) >= $signed(fwd_rs2)); // BGE
            3'b110:  branch_take = (fwd_rs1 <  fwd_rs2);                 // BLTU
            3'b111:  branch_take = (fwd_rs1 >= fwd_rs2);                 // BGEU
            default: branch_take = 1'b0;
        endcase
    end

    wire branch_taken = idex_branch && branch_take;
    assign pcsrc = branch_taken || idex_jump;

    // target: JALR -> (rs1+imm)&~1 ; branch/JAL -> pc+imm
    assign ex_target = idex_jalr ? ((fwd_rs1 + idex_imm) & ~32'd1)
                                 : (idex_pc + idex_imm);

    wire [31:0] idex_pc4 = idex_pc + 32'd4;

    // =====================================================================
    // EX/MEM pipeline register
    // =====================================================================
    reg        exmem_reg_write_r, exmem_mem_read, exmem_mem_write;
    reg [1:0]  exmem_wb_sel;
    reg [31:0] exmem_alu_r, exmem_store, exmem_pc4;
    reg [4:0]  exmem_rd_r;

    assign exmem_reg_write = exmem_reg_write_r;
    assign exmem_rd        = exmem_rd_r;
    assign exmem_alu       = exmem_alu_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            exmem_reg_write_r <= 1'b0; exmem_mem_read <= 1'b0; exmem_mem_write <= 1'b0;
            exmem_wb_sel <= 2'd0; exmem_alu_r <= 32'd0; exmem_store <= 32'd0;
            exmem_pc4 <= 32'd0; exmem_rd_r <= 5'd0;
        end else begin
            exmem_reg_write_r <= idex_reg_write;
            exmem_mem_read    <= idex_mem_read_r;
            exmem_mem_write   <= idex_mem_write;
            exmem_wb_sel      <= idex_wb_sel;
            exmem_alu_r       <= alu_y;
            exmem_store       <= fwd_rs2;     // store data (forwarded)
            exmem_pc4         <= idex_pc4;
            exmem_rd_r        <= idex_rd_r;
        end
    end

    // =====================================================================
    // MEM stage : data memory
    // =====================================================================
    reg  [31:0] dmem [0:DMEM_WORDS-1];
    integer di;
    initial for (di = 0; di < DMEM_WORDS; di = di + 1) dmem[di] = 32'd0;

    wire [31:0] mem_rdata = dmem[exmem_alu_r[31:2] % DMEM_WORDS];

    always @(posedge clk) begin
        if (exmem_mem_write)
            dmem[exmem_alu_r[31:2] % DMEM_WORDS] <= exmem_store;
    end

    // =====================================================================
    // MEM/WB pipeline register
    // =====================================================================
    reg        memwb_reg_write;
    reg [1:0]  memwb_wb_sel;
    reg [31:0] memwb_alu, memwb_mem, memwb_pc4;
    reg [4:0]  memwb_rd;

    always @(posedge clk) begin
        if (!rst_n) begin
            memwb_reg_write <= 1'b0; memwb_wb_sel <= 2'd0;
            memwb_alu <= 32'd0; memwb_mem <= 32'd0; memwb_pc4 <= 32'd0; memwb_rd <= 5'd0;
        end else begin
            memwb_reg_write <= exmem_reg_write_r;
            memwb_wb_sel    <= exmem_wb_sel;
            memwb_alu       <= exmem_alu_r;
            memwb_mem       <= mem_rdata;
            memwb_pc4       <= exmem_pc4;
            memwb_rd        <= exmem_rd_r;
        end
    end

    // =====================================================================
    // WB stage
    // =====================================================================
    reg [31:0] wb_mux;
    always @(*) begin
        case (memwb_wb_sel)
            `WB_MEM: wb_mux = memwb_mem;
            `WB_PC4: wb_mux = memwb_pc4;
            default: wb_mux = memwb_alu;
        endcase
    end

    assign wb_reg_write = memwb_reg_write;
    assign wb_rd        = memwb_rd;
    assign wb_data      = wb_mux;

endmodule

`default_nettype wire
