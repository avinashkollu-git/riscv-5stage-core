#!/usr/bin/env python3
"""Tiny RV32I assembler -> Verilog $readmemh hex.

Supports the instruction subset used by this core's tests:
  R:   add sub and or xor sll srl sra slt sltu
  I:   addi andi ori xori slli srli srai slti sltiu  jalr  lw
  S:   sw
  B:   beq bne blt bge bltu bgeu
  U:   lui auipc
  J:   jal
  pseudo: nop, li rd,imm (-> addi rd,x0,imm), mv rd,rs (-> addi rd,rs,0), j label (-> jal x0,label)

Usage: python3 assemble.py program.asm program.hex
One instruction per line; '#' starts a comment; 'label:' defines a label.
"""
import sys, re

REG = {f"x{i}": i for i in range(32)}
# common ABI aliases
REG.update({"zero":0,"ra":1,"sp":2,"gp":3,"tp":4,"t0":5,"t1":6,"t2":7,
            "s0":8,"fp":8,"s1":9,"a0":10,"a1":11,"a2":12,"a3":13,"a4":14,
            "a5":15,"a6":16,"a7":17})

def reg(t):
    t = t.strip()
    if t not in REG: raise ValueError(f"bad register '{t}'")
    return REG[t]

def imm(t, bits, signed=True):
    v = int(t, 0)
    return v & ((1 << bits) - 1) if signed else v

R_FUNCT = {  # name -> (funct7, funct3)
    "add":(0x00,0x0),"sub":(0x20,0x0),"sll":(0x00,0x1),"slt":(0x00,0x2),
    "sltu":(0x00,0x3),"xor":(0x00,0x4),"srl":(0x00,0x5),"sra":(0x20,0x5),
    "or":(0x00,0x6),"and":(0x00,0x7),
}
I_FUNCT = {  # ALU-immediate
    "addi":0x0,"slti":0x2,"sltiu":0x3,"xori":0x4,"ori":0x6,"andi":0x7,
    "slli":0x1,"srli":0x5,"srai":0x5,
}
B_FUNCT = {"beq":0x0,"bne":0x1,"blt":0x4,"bge":0x5,"bltu":0x6,"bgeu":0x7}

def enc_r(rd,rs1,rs2,f7,f3):
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x33
def enc_i(rd,rs1,imm12,f3,op=0x13):
    return ((imm12&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(rs1,rs2,imm12,f3):
    i=imm12&0xfff
    return ((i>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((i&0x1f)<<7)|0x23
def enc_b(rs1,rs2,off,f3):
    i=off&0x1fff
    b12=(i>>12)&1; b11=(i>>11)&1; b10_5=(i>>5)&0x3f; b4_1=(i>>1)&0xf
    return (b12<<31)|(b10_5<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(b4_1<<8)|(b11<<7)|0x63
def enc_u(rd,imm20,op):
    return ((imm20&0xfffff)<<12)|(rd<<7)|op
def enc_j(rd,off):
    i=off&0x1fffff
    b20=(i>>20)&1; b19_12=(i>>12)&0xff; b11=(i>>11)&1; b10_1=(i>>1)&0x3ff
    return (b20<<31)|(b10_1<<21)|(b11<<20)|(b19_12<<12)|(rd<<7)|0x6f

def parse_mem(op):  # "off(reg)" -> (off, reg)
    m = re.match(r"\s*(-?\w+)\s*\(\s*(\w+)\s*\)", op)
    return int(m.group(1),0), reg(m.group(2))

def main():
    src, out = sys.argv[1], sys.argv[2]
    # optional 3rd arg: pad the image out to this many words with 0x00000000 so
    # it exactly fills the core's instruction ROM (avoids a $readmemh range note).
    pad = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    lines = open(src).read().splitlines()
    # pass 1: addresses + labels
    prog, labels, addr = [], {}, 0
    for ln in lines:
        ln = ln.split("#")[0].strip()
        if not ln: continue
        if ln.endswith(":"):
            labels[ln[:-1]] = addr; continue
        m = re.match(r"^(\w+):\s*(.*)$", ln)
        if m and m.group(2)=="":  # label alone with colon handled above
            labels[m.group(1)] = addr; continue
        if m:  # label: instr
            labels[m.group(1)] = addr; ln = m.group(2)
        prog.append((addr, ln)); addr += 4

    words = []
    for pc, ln in prog:
        parts = re.split(r"[,\s]+", ln.strip())
        op = parts[0]; a = parts[1:]
        if op == "nop": op, a = "addi", ["x0","x0","0"]
        elif op == "li": op, a = "addi", [a[0], "x0", a[1]]
        elif op == "mv": op, a = "addi", [a[0], a[1], "0"]
        elif op == "j":  op, a = "jal", ["x0", a[0]]

        if op in R_FUNCT:
            f7,f3 = R_FUNCT[op]; w = enc_r(reg(a[0]),reg(a[1]),reg(a[2]),f7,f3)
        elif op in I_FUNCT:
            f3 = I_FUNCT[op]
            iv = int(a[2],0)
            if op == "srai": iv = 0x400 | (iv & 0x1f)
            w = enc_i(reg(a[0]),reg(a[1]),iv,f3)
        elif op == "jalr":
            w = enc_i(reg(a[0]),reg(a[1]),int(a[2],0),0x0,op=0x67)
        elif op == "lw":
            off,rs1 = parse_mem(" ".join(a[1:])); w = enc_i(reg(a[0]),rs1,off,0x2,op=0x03)
        elif op == "sw":
            off,rs1 = parse_mem(" ".join(a[1:])); w = enc_s(rs1,reg(a[0]),off,0x2)
        elif op in B_FUNCT:
            tgt = labels[a[2]] if a[2] in labels else int(a[2],0)
            w = enc_b(reg(a[0]),reg(a[1]),tgt-pc,B_FUNCT[op])
        elif op == "lui":
            w = enc_u(reg(a[0]),int(a[1],0),0x37)
        elif op == "auipc":
            w = enc_u(reg(a[0]),int(a[1],0),0x17)
        elif op == "jal":
            tgt = labels[a[1]] if a[1] in labels else int(a[1],0)
            w = enc_j(reg(a[0]),tgt-pc)
        else:
            raise ValueError(f"unknown instruction: {op}")
        words.append(w & 0xffffffff)

    n = len(words)
    if pad and n < pad:
        words += [0] * (pad - n)           # zero-fill remaining ROM words
    with open(out,"w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"assembled {n} instructions -> {out}" + (f" (padded to {pad} words)" if pad else ""))

if __name__ == "__main__":
    main()
