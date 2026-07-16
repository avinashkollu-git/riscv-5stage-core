// tb_riscv_core.v : runs program.hex on the 5-stage core and checks results.
`timescale 1ns/1ps
`default_nettype none

module tb_riscv_core;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;   // 100 MHz

    riscv_core #(.IMEM_FILE("program.hex")) dut (.clk(clk), .rst_n(rst_n));

    integer errors = 0;

    task check_reg(input [4:0] r, input [31:0] exp);
        begin
            if (dut.u_rf.regs[r] === exp)
                $display("  PASS  x%0d = %0d", r, dut.u_rf.regs[r]);
            else begin
                $display("  FAIL  x%0d = %0d (expected %0d)", r, dut.u_rf.regs[r], exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("riscv.vcd"); $dumpvars(0, tb_riscv_core);
        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;

        // Let the program run to completion (loop + drain).
        repeat (200) @(posedge clk);

        $display("RISC-V 5-stage core results:");
        check_reg(1,  32'd55);    // sum(1..10)
        check_reg(5,  32'd55);    // reloaded from mem[0]
        check_reg(6,  32'd110);   // x5 + x5 (load-use forwarding)
        check_reg(7,  32'd45);    // 55 - 10
        check_reg(2,  32'd11);    // loop counter final value

        if (dut.dmem[0] === 32'd55)
            $display("  PASS  mem[0] = %0d", dut.dmem[0]);
        else begin
            $display("  FAIL  mem[0] = %0d (expected 55)", dut.dmem[0]);
            errors = errors + 1;
        end

        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: %0d FAILURE(S)", errors);
        $finish;
    end
endmodule
`default_nettype wire
