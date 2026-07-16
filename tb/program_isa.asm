# RV32I comprehensive ISA-coverage test.
# Exercises every instruction the core claims to support and leaves the results
# in registers; tb_riscv_isa.v checks them against golden values.

        li    x1, 15
        li    x2, 4
        add   x3, x1, x2        # 19
        sub   x4, x1, x2        # 11
        and   x5, x1, x2        # 4
        or    x6, x1, x2        # 15
        xor   x7, x1, x2        # 11
        li    x8, 2
        sll   x9, x1, x8        # 15 << 2  = 60
        srl   x10, x1, x8       # 15 >> 2  = 3
        li    x11, -16          # 0xFFFFFFF0
        sra   x12, x11, x8      # -16 >> 2 = -4  (arithmetic)
        slt   x13, x11, x1      # signed  : -16 < 15  -> 1
        sltu  x14, x11, x1      # unsigned: huge < 15 -> 0
        addi  x15, x1, 5        # 20
        andi  x16, x1, 6        # 6
        ori   x17, x2, 1        # 5
        xori  x18, x1, 1        # 14
        slli  x19, x2, 3        # 32
        srli  x20, x1, 1        # 7
        srai  x21, x11, 1       # -16 >> 1 = -8
        slti  x22, x11, 0       # -16 < 0  -> 1
        sltiu x23, x1, 100      # 15 < 100 -> 1
        lui   x24, 1            # 1 << 12  = 4096
        sw    x3, 0(x0)         # mem[0] = 19
        lw    x25, 0(x0)        # x25 = 19

        # ---- branch coverage: all six should be TAKEN (skip the +100) ----
        li    x26, 0
        li    x27, 5
        li    x28, 5
        beq   x27, x28, e1
        addi  x26, x26, 100
e1:     bne   x27, x1,  e2
        addi  x26, x26, 100
e2:     blt   x11, x1,  e3
        addi  x26, x26, 100
e3:     bge   x1,  x27, e4
        addi  x26, x26, 100
e4:     bltu  x1,  x11, e5
        addi  x26, x26, 100
e5:     bgeu  x11, x1,  e6
        addi  x26, x26, 100
e6:     addi  x26, x26, 7       # x26 = 7 if every taken branch behaved

        # not-taken branch: operands equal, bne must fall through
        bne   x27, x28, e7
        addi  x26, x26, 1       # executed -> x26 = 8
e7:     # ---- JAL (call) and JALR (return) ----
        jal   x29, func
        addi  x26, x26, 1       # runs after func returns -> x26 = 29
        j     after
func:   addi  x26, x26, 20      # x26 = 28
        jalr  x0, x29, 0        # return to the instruction after JAL
after:  # ---- AUIPC is PC-relative: two back-to-back differ by 4 ----
        auipc x30, 0            # P
        auipc x31, 0            # P + 4
        sub   x28, x31, x30     # = 4
halt:   j     halt
