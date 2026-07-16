// tb_riscv_isa.v : comprehensive ISA-coverage check. Runs program_isa.hex and
//   verifies every instruction class produced the correct result.
`timescale 1ns/1ps
`default_nettype none

module tb_riscv_isa;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    riscv_core #(.IMEM_FILE("program_isa.hex")) dut (.clk(clk), .rst_n(rst_n));

    integer errors = 0;

    task chk(input [8*10:1] name, input [4:0] r, input [31:0] exp);
        begin
            if (dut.u_rf.regs[r] === exp)
                $display("  PASS  %-6s x%0d = 0x%08x", name, r, dut.u_rf.regs[r]);
            else begin
                $display("  FAIL  %-6s x%0d = 0x%08x (expected 0x%08x)", name, r, dut.u_rf.regs[r], exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("riscv_isa.vcd"); $dumpvars(0, tb_riscv_isa);
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
        repeat (300) @(posedge clk);

        $display("RV32I ISA coverage:");
        chk("add",   3,  32'd19);
        chk("sub",   4,  32'd11);
        chk("and",   5,  32'd4);
        chk("or",    6,  32'd15);
        chk("xor",   7,  32'd11);
        chk("sll",   9,  32'd60);
        chk("srl",   10, 32'd3);
        chk("sra",   12, 32'hFFFFFFFC);   // -4
        chk("slt",   13, 32'd1);
        chk("sltu",  14, 32'd0);
        chk("addi",  15, 32'd20);
        chk("andi",  16, 32'd6);
        chk("ori",   17, 32'd5);
        chk("xori",  18, 32'd14);
        chk("slli",  19, 32'd32);
        chk("srli",  20, 32'd7);
        chk("srai",  21, 32'hFFFFFFF8);   // -8
        chk("slti",  22, 32'd1);
        chk("sltiu", 23, 32'd1);
        chk("lui",   24, 32'd4096);
        chk("lw",    25, 32'd19);
        chk("branch",26, 32'd29);         // 6 taken + 1 not-taken + jal/jalr
        chk("auipc", 28, 32'd4);          // two AUIPCs differ by 4

        if (dut.dmem[0] === 32'd19)
            $display("  PASS  sw     mem[0] = 0x%08x", dut.dmem[0]);
        else begin
            $display("  FAIL  sw     mem[0] = 0x%08x (expected 0x13)", dut.dmem[0]);
            errors = errors + 1;
        end

        if (errors == 0) $display("RESULT: ALL ISA TESTS PASSED");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end
endmodule
`default_nettype wire
