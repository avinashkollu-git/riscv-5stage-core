# Test program for the RV32I 5-stage core.
# Computes sum(1..10)=55, stores/reloads it (load-use hazard), and exercises
# forwarding and a taken/not-taken branch loop.
#
# Expected final state:
#   x1  = 55   (sum)
#   x5  = 55   (reloaded from mem[0])
#   x6  = 110  (x5 + x5, tests MEM/WB forwarding after a load)
#   x7  = 45   (55 - 10, tests SUB + forwarding)
#   mem[0] = 55

        li   x1, 0          # sum = 0
        li   x2, 1          # i = 1
        li   x3, 11         # limit = 11
loop:
        beq  x2, x3, done   # exit when i == 11
        add  x1, x1, x2     # sum += i   (x1 forwarded each iteration)
        addi x2, x2, 1      # i++
        j    loop
done:
        sw   x1, 0(x0)      # mem[0] = 55
        lw   x5, 0(x0)      # x5 = mem[0]      (load)
        add  x6, x5, x5     # x6 = 110         (load-use: needs a stall)
        addi x8, x0, 10
        sub  x7, x1, x8     # x7 = 55 - 10 = 45
halt:
        j    halt           # spin
