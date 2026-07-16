// regfile.v : 32x32 register file. x0 hard-wired to zero.
//   Write on the falling clock edge so a value written in WB is visible to a
//   read in the same cycle's ID stage (classic "write-first" register file).
`timescale 1ns / 1ps
`default_nettype none

module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    input  wire [4:0]  wa,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] regs [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

    always @(negedge clk) begin
        if (we && wa != 5'd0)
            regs[wa] <= wd;
    end

    assign rd1 = (ra1 == 5'd0) ? 32'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : regs[ra2];
endmodule

`default_nettype wire
