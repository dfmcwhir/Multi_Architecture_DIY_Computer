#!/usr/bin/env python3
"""
emu8085.py - emulator for the custom 8085 computer.

    python3 emu8085.py boot_bios.bin                 # run the ROM, console = display card
    python3 emu8085.py boot_bios.asm                 # assemble with asm8085.py first
    python3 emu8085.py boot_bios.bin --disk ./usb    # CH376 "USB stick" = host folder ./usb
    python3 emu8085.py boot_bios.bin --console serial
    python3 emu8085.py boot_bios.bin --serial tcp:2323      # serial card on a TCP port (telnet/nc)
    python3 emu8085.py boot_bios.bin --serial-send prog.hex # feed a file into the serial card

What is emulated (memory map and I/O as on the real board):
    0000-7FFF ROM (loaded from the file, writes ignored)    8000-FFFF RAM
    00-0F   65C22 VIA   (ports, timers T1/T2, IFR/IER, interrupt flags)
    14-17   6551 ACIA   serial card         18-1B  6551 ACIA   keyboard/display card
    20/21   CH376       (also mirrors 24/25 28/29 2C/2D)  USB storage = a host folder
    FF      interrupt register: (7 - IRQ) * 2 of the highest priority IRQ, FFh if none
    IRQ 2 = VIA, IRQ 3 = serial card, IRQ 5 = keyboard/display card, all wired to RST 6.5
Serial/KB speed is modelled: bytes arrive and leave at the programmed baud rate
(UM6551: control value 10h = 115200), so receive overruns happen like on the real board.

Keys: everything you type goes to the console device.  Ctrl-] opens the emulator
prompt (type "help").  Ctrl-C is passed through to the computer (BASIC break).
"""
import argparse
import os
import random
import select
import socket
import sys
import threading
import time
from collections import deque

CPU_HZ_DEFAULT = 2457600          # 4.9152 MHz crystal / 2

# ---------------------------------------------------------------- CPU tables
ZSP = []
for _v in range(256):
    _f = 0x80 if _v & 0x80 else 0
    if _v == 0:
        _f |= 0x40
    if bin(_v).count("1") % 2 == 0:
        _f |= 0x04
    ZSP.append(_f)

MNEM_COND = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
REGN = ["B", "C", "D", "E", "H", "L", "M", "A"]
RPN = ["B", "D", "H", "SP"]


class Halted(Exception):
    pass


class CPU:
    """8085 core.  Registers: R = [B, C, D, E, H, L, (M), A].  F holds S Z - AC - P - CY."""

    def __init__(self, machine):
        self.m = machine
        self.mem = machine.mem
        self.R = [0] * 8
        self.F = 0x02
        self.SP = 0
        self.PC = 0
        self.inte = False
        self.ei_hold = False
        self.mask55 = self.mask65 = self.mask75 = True
        self.halted = False
        self.cycles = 0
        self.skip_bp = None
        self.ops = self._build()

    def reset(self):
        self.PC = 0
        self.inte = False
        self.ei_hold = False
        self.mask55 = self.mask65 = self.mask75 = True
        self.halted = False

    # -- memory / stack helpers ------------------------------------------
    def rb(self, a):
        return self.mem[a & 0xFFFF]

    def wb(self, a, v):
        a &= 0xFFFF
        if a >= 0x8000:
            self.mem[a] = v & 0xFF

    def push(self, v):
        mem = self.mem
        sp = (self.SP - 1) & 0xFFFF
        if sp >= 0x8000:
            mem[sp] = v >> 8
        sp = (sp - 1) & 0xFFFF
        if sp >= 0x8000:
            mem[sp] = v & 0xFF
        self.SP = sp

    def pop(self):
        mem = self.mem
        sp = self.SP
        lo = mem[sp]
        hi = mem[(sp + 1) & 0xFFFF]
        self.SP = (sp + 2) & 0xFFFF
        return (hi << 8) | lo

    def hl(self):
        return (self.R[4] << 8) | self.R[5]

    def getrp(self, i):
        R = self.R
        if i == 0:
            return (R[0] << 8) | R[1]
        if i == 1:
            return (R[2] << 8) | R[3]
        if i == 2:
            return (R[4] << 8) | R[5]
        return self.SP

    def setrp(self, i, v):
        v &= 0xFFFF
        R = self.R
        if i == 0:
            R[0] = v >> 8
            R[1] = v & 255
        elif i == 1:
            R[2] = v >> 8
            R[3] = v & 255
        elif i == 2:
            R[4] = v >> 8
            R[5] = v & 255
        else:
            self.SP = v

    # -- ALU --------------------------------------------------------------
    def alu(self, k, v):
        R = self.R
        a = R[7]
        if k == 0 or k == 1:                      # ADD / ADC
            c = (self.F & 1) if k == 1 else 0
            r = a + v + c
            self.F = ZSP[r & 255] | (r >> 8) | 0x02 | (0x10 if ((a & 15) + (v & 15) + c) > 15 else 0)
            R[7] = r & 255
        elif k == 2 or k == 3 or k == 7:          # SUB / SBB / CMP
            c = (self.F & 1) if k == 3 else 0
            r = a - v - c
            self.F = ZSP[r & 255] | (1 if r < 0 else 0) | 0x02 | (0x10 if ((a & 15) - (v & 15) - c) >= 0 else 0)
            if k != 7:
                R[7] = r & 255
        elif k == 4:                              # ANA
            r = a & v
            self.F = ZSP[r] | 0x12
            R[7] = r
        elif k == 5:                              # XRA
            r = a ^ v
            self.F = ZSP[r] | 0x02
            R[7] = r
        else:                                     # ORA
            r = a | v
            self.F = ZSP[r] | 0x02
            R[7] = r

    def cond(self, c):
        F = self.F
        if c == 0:
            return not F & 0x40
        if c == 1:
            return F & 0x40
        if c == 2:
            return not F & 1
        if c == 3:
            return F & 1
        if c == 4:
            return not F & 4
        if c == 5:
            return F & 4
        if c == 6:
            return not F & 0x80
        return F & 0x80

    # -- opcode table ---------------------------------------------------------
    def _build(self):
        ops = [None] * 256
        R = self.R
        mem = self.mem
        cpu = self

        def bad(op):
            def f(s):
                raise Halted("illegal opcode %02X at %04X" % (op, (s.PC - 1) & 0xFFFF))
            return f

        for op in range(256):
            ops[op] = bad(op)

        def fetch16(s):
            pc = s.PC
            v = mem[pc] | (mem[(pc + 1) & 0xFFFF] << 8)
            s.PC = (pc + 2) & 0xFFFF
            return v

        def nop(s):
            return 4
        ops[0x00] = nop
        for op in (0x08, 0x10, 0x18, 0x28, 0x38, 0xCB, 0xD9, 0xDD, 0xED, 0xFD):
            ops[op] = nop                           # undefined / 8085 undocumented: treat as NOP

        # MOV
        for d in range(8):
            for sr in range(8):
                op = 0x40 | (d << 3) | sr
                if op == 0x76:
                    continue

                def mk(d, sr):
                    if d == 6:
                        def f(s):
                            s.wb((R[4] << 8) | R[5], R[sr])
                            return 7
                    elif sr == 6:
                        def f(s):
                            R[d] = mem[(R[4] << 8) | R[5]]
                            return 7
                    else:
                        def f(s):
                            R[d] = R[sr]
                            return 4
                    return f
                ops[op] = mk(d, sr)

        def hlt(s):
            s.halted = True
            return 5
        ops[0x76] = hlt

        # MVI, INR, DCR
        for r in range(8):
            def mk_mvi(r):
                def f(s):
                    v = mem[s.PC]
                    s.PC = (s.PC + 1) & 0xFFFF
                    if r == 6:
                        s.wb((R[4] << 8) | R[5], v)
                        return 10
                    R[r] = v
                    return 7
                return f

            def mk_inr(r):
                def f(s):
                    if r == 6:
                        a = (R[4] << 8) | R[5]
                        v = (mem[a] + 1) & 255
                        s.wb(a, v)
                        t = 10
                    else:
                        v = (R[r] + 1) & 255
                        R[r] = v
                        t = 4
                    s.F = (s.F & 1) | ZSP[v] | (0x10 if (v & 15) == 0 else 0) | 0x02
                    return t
                return f

            def mk_dcr(r):
                def f(s):
                    if r == 6:
                        a = (R[4] << 8) | R[5]
                        v = (mem[a] - 1) & 255
                        s.wb(a, v)
                        t = 10
                    else:
                        v = (R[r] - 1) & 255
                        R[r] = v
                        t = 4
                    s.F = (s.F & 1) | ZSP[v] | (0x10 if (v & 15) != 15 else 0) | 0x02
                    return t
                return f
            ops[0x06 | (r << 3)] = mk_mvi(r)
            ops[0x04 | (r << 3)] = mk_inr(r)
            ops[0x05 | (r << 3)] = mk_dcr(r)

        # ALU with register / memory / immediate
        for k in range(8):
            for r in range(8):
                def mk_alu(k, r):
                    def f(s):
                        if r == 6:
                            s.alu(k, mem[(R[4] << 8) | R[5]])
                            return 7
                        s.alu(k, R[r])
                        return 4
                    return f
                ops[0x80 | (k << 3) | r] = mk_alu(k, r)

            def mk_alui(k):
                def f(s):
                    v = mem[s.PC]
                    s.PC = (s.PC + 1) & 0xFFFF
                    s.alu(k, v)
                    return 7
                return f
            ops[0xC6 | (k << 3)] = mk_alui(k)

        # LXI / INX / DCX / DAD / PUSH / POP
        for i in range(4):
            def mk_lxi(i):
                def f(s):
                    s.setrp(i, fetch16(s))
                    return 10
                return f

            def mk_inx(i):
                def f(s):
                    s.setrp(i, s.getrp(i) + 1)
                    return 6
                return f

            def mk_dcx(i):
                def f(s):
                    s.setrp(i, s.getrp(i) - 1)
                    return 6
                return f

            def mk_dad(i):
                def f(s):
                    r = ((R[4] << 8) | R[5]) + s.getrp(i)
                    s.F = (s.F & 0xFE) | (1 if r > 0xFFFF else 0)
                    s.setrp(2, r)
                    return 10
                return f
            ops[0x01 | (i << 4)] = mk_lxi(i)
            ops[0x03 | (i << 4)] = mk_inx(i)
            ops[0x0B | (i << 4)] = mk_dcx(i)
            ops[0x09 | (i << 4)] = mk_dad(i)

            def mk_push(i):
                def f(s):
                    if i == 3:
                        s.push((R[7] << 8) | s.F | 0x02)
                    else:
                        s.push(s.getrp(i))
                    return 12
                return f

            def mk_pop(i):
                def f(s):
                    v = s.pop()
                    if i == 3:
                        R[7] = v >> 8
                        s.F = (v & 0xD5) | 0x02
                    else:
                        s.setrp(i, v)
                    return 10
                return f
            ops[0xC5 | (i << 4)] = mk_push(i)
            ops[0xC1 | (i << 4)] = mk_pop(i)

        # loads and stores
        def lda(s):
            R[7] = mem[fetch16(s)]
            return 13

        def sta(s):
            s.wb(fetch16(s), R[7])
            return 13

        def lhld(s):
            a = fetch16(s)
            R[5] = mem[a]
            R[4] = mem[(a + 1) & 0xFFFF]
            return 16

        def shld(s):
            a = fetch16(s)
            s.wb(a, R[5])
            s.wb(a + 1, R[4])
            return 16
        ops[0x3A], ops[0x32], ops[0x2A], ops[0x22] = lda, sta, lhld, shld
        ops[0x0A] = lambda s: (R.__setitem__(7, mem[(R[0] << 8) | R[1]]), 7)[1]
        ops[0x1A] = lambda s: (R.__setitem__(7, mem[(R[2] << 8) | R[3]]), 7)[1]
        ops[0x02] = lambda s: (s.wb((R[0] << 8) | R[1], R[7]), 7)[1]
        ops[0x12] = lambda s: (s.wb((R[2] << 8) | R[3], R[7]), 7)[1]

        def xchg(s):
            R[2], R[3], R[4], R[5] = R[4], R[5], R[2], R[3]
            return 4
        ops[0xEB] = xchg

        def xthl(s):
            sp = s.SP
            lo, hi = mem[sp], mem[(sp + 1) & 0xFFFF]
            s.wb(sp, R[5])
            s.wb(sp + 1, R[4])
            R[5], R[4] = lo, hi
            return 16
        ops[0xE3] = xthl

        def sphl(s):
            s.SP = (R[4] << 8) | R[5]
            return 6

        def pchl(s):
            s.PC = (R[4] << 8) | R[5]
            return 6
        ops[0xF9], ops[0xE9] = sphl, pchl

        # rotates, misc accumulator / flag ops
        def rlc(s):
            a = R[7]
            c = a >> 7
            R[7] = ((a << 1) | c) & 255
            s.F = (s.F & 0xFE) | c
            return 4

        def rrc(s):
            a = R[7]
            c = a & 1
            R[7] = (a >> 1) | (c << 7)
            s.F = (s.F & 0xFE) | c
            return 4

        def ral(s):
            a = R[7]
            c = s.F & 1
            R[7] = ((a << 1) | c) & 255
            s.F = (s.F & 0xFE) | (a >> 7)
            return 4

        def rar(s):
            a = R[7]
            c = s.F & 1
            R[7] = (a >> 1) | (c << 7)
            s.F = (s.F & 0xFE) | (a & 1)
            return 4

        def cma(s):
            R[7] ^= 255
            return 4

        def stc(s):
            s.F |= 1
            return 4

        def cmc(s):
            s.F ^= 1
            return 4

        def daa(s):
            a = R[7]
            F = s.F
            c = F & 1
            if (a & 15) > 9 or F & 0x10:
                if (a & 15) + 6 > 15:
                    F |= 0x10
                else:
                    F &= ~0x10
                a += 6
            if a > 0x9F or c:
                a += 0x60
                c = 1
            R[7] = a & 255
            s.F = ZSP[R[7]] | (F & 0x10) | c | 0x02
            return 4
        ops[0x07], ops[0x0F], ops[0x17], ops[0x1F] = rlc, rrc, ral, rar
        ops[0x2F], ops[0x37], ops[0x3F], ops[0x27] = cma, stc, cmc, daa

        # jumps, calls, returns, restarts
        def jmp(s):
            s.PC = fetch16(s)
            return 10

        def call(s):
            a = fetch16(s)
            s.push(s.PC)
            s.PC = a
            return 18

        def ret(s):
            s.PC = s.pop()
            return 10
        ops[0xC3], ops[0xCD], ops[0xC9] = jmp, call, ret
        for c in range(8):
            def mk(c):
                def j(s):
                    a = fetch16(s)
                    if s.cond(c):
                        s.PC = a
                        return 10
                    return 7

                def cl(s):
                    a = fetch16(s)
                    if s.cond(c):
                        s.push(s.PC)
                        s.PC = a
                        return 18
                    return 9

                def rt(s):
                    if s.cond(c):
                        s.PC = s.pop()
                        return 12
                    return 6
                return j, cl, rt
            j, cl, rt = mk(c)
            ops[0xC2 | (c << 3)] = j
            ops[0xC4 | (c << 3)] = cl
            ops[0xC0 | (c << 3)] = rt
        for n in range(8):
            def mk_rst(n):
                def f(s):
                    s.push(s.PC)
                    s.PC = n * 8
                    return 12
                return f
            ops[0xC7 | (n << 3)] = mk_rst(n)

        # I/O, interrupts
        def in_(s):
            p = mem[s.PC]
            s.PC = (s.PC + 1) & 0xFFFF
            R[7] = s.m.io_read(p) & 255
            return 10

        def out_(s):
            p = mem[s.PC]
            s.PC = (s.PC + 1) & 0xFFFF
            s.m.io_write(p, R[7])
            return 10
        ops[0xDB], ops[0xD3] = in_, out_

        def ei(s):
            s.inte = True
            s.ei_hold = True
            return 4

        def di(s):
            s.inte = False
            return 4
        ops[0xFB], ops[0xF3] = ei, di

        def rim(s):
            v = (0x08 if s.inte else 0) | (4 if s.mask75 else 0) | (2 if s.mask65 else 0) | (1 if s.mask55 else 0)
            v |= 0x20 if (s.m.irq_line() and not False) else 0
            R[7] = v
            return 4

        def sim(s):
            a = R[7]
            if a & 8:
                s.mask75 = bool(a & 4)
                s.mask65 = bool(a & 2)
                s.mask55 = bool(a & 1)
            return 4
        ops[0x20], ops[0x30] = rim, sim
        return ops

    # -- execution ---------------------------------------------------------
    def run(self, budget):
        """Execute about `budget` T-states.  Returns the cycles used."""
        ops = self.ops
        mem = self.mem
        start = self.cycles
        end = start + budget
        m = self.m
        bps = m.breakpoints
        cyc = start
        while cyc < end:
            if self.halted:
                if self.inte and not self.mask65 and m.irq_line():
                    self.halted = False
                else:
                    cyc += 100
                    m.tick(cyc)
                    continue
            if self.inte and not self.mask65 and not self.ei_hold and m.irq_line():
                self.inte = False
                self.push(self.PC)
                self.PC = 0x34
                cyc += 12
                continue
            self.ei_hold = False
            pc = self.PC
            if bps and pc in bps:
                if pc == self.skip_bp:
                    self.skip_bp = None
                else:
                    self.cycles = cyc
                    raise Halted("breakpoint at %04X" % pc)
            op = mem[pc]
            self.PC = (pc + 1) & 0xFFFF
            if op & 0xF7 == 0xD3:                       # IN / OUT: devices need the time
                self.cycles = cyc
            cyc += ops[op](self)
            if cyc >= m.next_tick:
                m.tick(cyc)
        self.cycles = cyc
        return cyc - start


def disasm(mem, pc):
    """Return (text, length) of the instruction at pc."""
    op = mem[pc & 0xFFFF]
    b1 = mem[(pc + 1) & 0xFFFF]
    w = b1 | (mem[(pc + 2) & 0xFFFF] << 8)
    if op & 0xC0 == 0x40:
        return ("HLT", 1) if op == 0x76 else ("MOV %s,%s" % (REGN[(op >> 3) & 7], REGN[op & 7]), 1)
    if op & 0xC0 == 0x80:
        return ("%s %s" % (["ADD", "ADC", "SUB", "SBB", "ANA", "XRA", "ORA", "CMP"][(op >> 3) & 7], REGN[op & 7]), 1)
    if op & 0xC7 == 0x06:
        return ("MVI %s,%02XH" % (REGN[(op >> 3) & 7], b1), 2)
    if op & 0xC7 == 0x04:
        return ("INR " + REGN[(op >> 3) & 7], 1)
    if op & 0xC7 == 0x05:
        return ("DCR " + REGN[(op >> 3) & 7], 1)
    if op & 0xCF == 0x01:
        return ("LXI %s,%04XH" % (RPN[(op >> 4) & 3], w), 3)
    if op & 0xCF == 0x03:
        return ("INX " + RPN[(op >> 4) & 3], 1)
    if op & 0xCF == 0x0B:
        return ("DCX " + RPN[(op >> 4) & 3], 1)
    if op & 0xCF == 0x09:
        return ("DAD " + RPN[(op >> 4) & 3], 1)
    if op & 0xCF == 0xC5:
        return ("PUSH " + ["B", "D", "H", "PSW"][(op >> 4) & 3], 1)
    if op & 0xCF == 0xC1:
        return ("POP " + ["B", "D", "H", "PSW"][(op >> 4) & 3], 1)
    if op & 0xC7 == 0xC7:
        return ("RST %d" % ((op >> 3) & 7), 1)
    if op & 0xC7 == 0xC0:
        return ("R" + MNEM_COND[(op >> 3) & 7], 1)
    if op & 0xC7 == 0xC2:
        return ("J%s %04XH" % (MNEM_COND[(op >> 3) & 7], w), 3)
    if op & 0xC7 == 0xC4:
        return ("C%s %04XH" % (MNEM_COND[(op >> 3) & 7], w), 3)
    if op & 0xC7 == 0xC6:
        return ("%s %02XH" % (["ADI", "ACI", "SUI", "SBI", "ANI", "XRI", "ORI", "CPI"][(op >> 3) & 7], b1), 2)
    simple = {0x00: "NOP", 0x07: "RLC", 0x0F: "RRC", 0x17: "RAL", 0x1F: "RAR", 0x27: "DAA", 0x2F: "CMA",
              0x37: "STC", 0x3F: "CMC", 0xC9: "RET", 0xE3: "XTHL", 0xE9: "PCHL", 0xEB: "XCHG", 0xF3: "DI",
              0xF9: "SPHL", 0xFB: "EI", 0x20: "RIM", 0x30: "SIM", 0x02: "STAX B", 0x12: "STAX D",
              0x0A: "LDAX B", 0x1A: "LDAX D"}
    if op in simple:
        return simple[op], 1
    three = {0xC3: "JMP", 0xCD: "CALL", 0x3A: "LDA", 0x32: "STA", 0x2A: "LHLD", 0x22: "SHLD"}
    if op in three:
        return "%s %04XH" % (three[op], w), 3
    if op == 0xDB:
        return "IN %02XH" % b1, 2
    if op == 0xD3:
        return "OUT %02XH" % b1, 2
    return "DB %02XH" % op, 1


# ------------------------------------------------------------------- devices
UM6551_BAUD = {0: 115200, 1: 50, 2: 75, 3: 110, 4: 134.5, 5: 150, 6: 300, 7: 600, 8: 1200, 9: 1800,
               10: 2400, 11: 3600, 12: 4800, 13: 7200, 14: 9600, 15: 19200}


class ACIA:
    """6551 with receive/transmit timing at the programmed baud rate."""

    def __init__(self, machine, name):
        self.m = machine
        self.name = name
        self.sink = None            # callable(byte) for transmitted data
        self.reset_all()

    def reset_all(self):
        self.pending = deque()      # bytes waiting to be shifted in, one frame time apart
        self.next_rx = 0
        self.rdr = 0
        self.rdrf = False
        self.overrun = False
        self.irq = False
        self.cmd = 0
        self.ctrl = 0
        self.tx_done = 0

    def frame_cycles(self):
        baud = UM6551_BAUD.get(self.ctrl & 15, 9600)
        return int(self.m.hz * 10 / baud)

    def feed(self, data, gap=None):
        """Queue received bytes.  They arrive one frame time apart at the current baud
        rate, or `gap` CPU cycles apart if given (used for the host keyboard: a person,
        or a paste, is far slower than 115200 baud)."""
        if not self.pending:
            self.next_rx = max(self.next_rx, self.m.cpu.cycles + (gap or self.frame_cycles()))
        for b in data:
            self.pending.append((b, gap))

    def tick(self, cyc):
        f = self.pending
        while f and cyc >= self.next_rx:
            b, gap = f.popleft()
            sp = gap or self.frame_cycles()
            self.next_rx = max(self.next_rx, cyc - sp) + sp
            if not (self.cmd & 1):                  # DTR off: receiver disabled
                continue
            if self.rdrf:
                self.overrun = True                 # lost: the CPU was too slow
                continue
            self.rdr = b
            self.rdrf = True
            if not (self.cmd & 2):
                self.irq = True

    def irq_line(self):
        return self.irq and not (self.cmd & 2)

    def read(self, reg):
        if reg == 0:
            self.rdrf = False
            self.overrun = False
            return self.rdr
        if reg == 1:
            cyc = self.m.cpu.cycles
            v = (0x80 if self.irq else 0) | (0x10 if cyc >= self.tx_done else 0) \
                | (0x08 if self.rdrf else 0) | (0x04 if self.overrun else 0)
            self.irq = False                        # reading status acknowledges
            return v
        if reg == 2:
            return self.cmd
        return self.ctrl

    def write(self, reg, v):
        if reg == 0:
            cyc = self.m.cpu.cycles
            self.tx_done = max(cyc, self.tx_done) + self.frame_cycles()
            if self.sink:
                self.sink(v)
        elif reg == 1:                              # programmed reset
            self.cmd &= 0xE0
            self.irq = False
            self.rdrf = False
            self.overrun = False
            self.pending.clear()
        elif reg == 2:
            self.cmd = v
        else:
            self.ctrl = v


class VIA:
    """65C22: enough for ports, timers and interrupts."""
    T1, T2, CB1, CB2, SR, CA1, CA2 = 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

    def __init__(self, machine):
        self.m = machine
        self.reset_all()

    def reset_all(self):
        self.orb = self.ora = self.ddrb = self.ddra = 0
        self.pinb = self.pina = 0xFF
        self.acr = self.pcr = 0
        self.ifr = self.ier = 0
        self.t1_latch = 0xFFFF
        self.t1_next = None
        self.t2_latch = 0
        self.t2_next = None
        self.t2_lo = 0

    def tick(self, cyc):
        if self.t1_next is not None and cyc >= self.t1_next:
            self.ifr |= self.T1
            if self.acr & 0x40:                       # free running
                self.t1_next += self.t1_latch + 2
            else:
                self.t1_next = None
        if self.t2_next is not None and cyc >= self.t2_next:
            self.ifr |= self.T2
            self.t2_next = None

    def irq_line(self):
        return bool(self.ifr & self.ier & 0x7F)

    def raise_flag(self, bit):
        self.ifr |= bit

    def _counter(self, nxt, cyc):
        return 0xFFFF if nxt is None else max(0, nxt - cyc - 2) & 0xFFFF

    def read(self, reg):
        cyc = self.m.cpu.cycles
        if reg == 0:
            self.ifr &= ~(self.CB1 | self.CB2)
            return (self.orb & self.ddrb) | (self.pinb & ~self.ddrb & 255)
        if reg in (1, 15):
            self.ifr &= ~(self.CA1 | self.CA2) if reg == 1 else 0xFF
            return (self.ora & self.ddra) | (self.pina & ~self.ddra & 255)
        if reg == 2:
            return self.ddrb
        if reg == 3:
            return self.ddra
        if reg == 4:
            self.ifr &= ~self.T1
            return self._counter(self.t1_next, cyc) & 255
        if reg == 5:
            return self._counter(self.t1_next, cyc) >> 8
        if reg == 6:
            return self.t1_latch & 255
        if reg == 7:
            return self.t1_latch >> 8
        if reg == 8:
            self.ifr &= ~self.T2
            return self._counter(self.t2_next, cyc) & 255
        if reg == 9:
            return self._counter(self.t2_next, cyc) >> 8
        if reg == 11:
            return self.acr
        if reg == 12:
            return self.pcr
        if reg == 13:
            return (self.ifr & 0x7F) | (0x80 if self.irq_line() else 0)
        if reg == 14:
            return self.ier | 0x80
        return 0

    def write(self, reg, v):
        cyc = self.m.cpu.cycles
        if reg == 0:
            self.orb = v
            self.ifr &= ~(self.CB1 | self.CB2)
            self.m.port_write_hook("VIA B", v & self.ddrb)
        elif reg in (1, 15):
            self.ora = v
            if reg == 1:
                self.ifr &= ~(self.CA1 | self.CA2)
            self.m.port_write_hook("VIA A", v & self.ddra)
        elif reg == 2:
            self.ddrb = v
        elif reg == 3:
            self.ddra = v
        elif reg in (4, 6):
            self.t1_latch = (self.t1_latch & 0xFF00) | v
        elif reg == 5:
            self.t1_latch = (self.t1_latch & 0x00FF) | (v << 8)
            self.ifr &= ~self.T1
            self.t1_next = cyc + self.t1_latch + 2
        elif reg == 7:
            self.t1_latch = (self.t1_latch & 0x00FF) | (v << 8)
            self.ifr &= ~self.T1
        elif reg == 8:
            self.t2_lo = v
        elif reg == 9:
            self.t2_latch = (v << 8) | self.t2_lo
            self.ifr &= ~self.T2
            self.t2_next = cyc + self.t2_latch + 2
        elif reg == 11:
            self.acr = v
        elif reg == 12:
            self.pcr = v
        elif reg == 13:
            self.ifr &= ~(v & 0x7F)                   # write 1s to clear
        elif reg == 14:
            if v & 0x80:
                self.ier |= v & 0x7F
            else:
                self.ier &= ~v & 0x7F


class CH376:
    """CH376 in parallel mode.  The USB stick is a host folder (None = no stick)."""

    def __init__(self, machine, folder, present=True):
        self.m = machine
        self.folder = folder
        self.present = present
        self.reset_all()

    def reset_all(self):
        self.out = deque()
        self.int = False
        self.status = 0
        self.cmd = None
        self.args = []
        self.name = b""
        self.fh = None            # (path, bytearray, dirty)
        self.pos = 0
        self.wr_remaining = 0
        self.rd_remaining = 0
        self.enum = []
        self.enum_i = 0
        self.mode = None
        self.have_disk = False

    # -- host folder -----------------------------------------------------
    def _path(self, name):
        n = name.decode("latin1").lstrip("/\\").upper()
        if not n or "/" in n or "\\" in n:
            return None
        return os.path.join(self.folder, n)

    def _find(self, name):
        """Case-insensitive lookup of an existing host file."""
        n = name.decode("latin1").lstrip("/\\")
        if not self.folder or not os.path.isdir(self.folder):
            return None
        for f in os.listdir(self.folder):
            if f.upper() == n.upper() and os.path.isfile(os.path.join(self.folder, f)):
                return os.path.join(self.folder, f)
        return None

    def _flush(self):
        if self.fh and self.fh[2]:
            with open(self.fh[0], "wb") as f:
                f.write(self.fh[1])
            self.fh = (self.fh[0], self.fh[1], False)

    def _entries(self):
        ents = []
        for f in sorted(os.listdir(self.folder)):
            full = os.path.join(self.folder, f)
            up = f.upper()
            nm, _, ext = up.rpartition(".") if "." in up else (up, "", "")
            if len(nm) > 8 or len(ext) > 3 or f.startswith("."):
                continue
            e = bytearray(32)
            e[0:11] = (nm.ljust(8) + ext.ljust(3)).encode("latin1", "replace")
            if os.path.isdir(full):
                e[11] = 0x10
            else:
                e[11] = 0x20
                e[28:32] = os.path.getsize(full).to_bytes(4, "little")
            ents.append(bytes(e))
        return ents

    # -- bus ----------------------------------------------------------------
    def rd_status(self):
        if not self.present:
            return 0xFF
        return 0x00 if self.int else 0x80

    def rd_data(self):
        if not self.present:
            return 0xFF
        return self.out.popleft() if self.out else 0

    def setint(self, v):
        self.status = v
        self.int = True

    def wr_cmd(self, c):
        if not self.present:
            return
        self.cmd = c
        self.args = []
        if c == 0x05:
            self._flush()
            self.reset_all()
        elif c == 0x22:
            self.out = deque([self.status])
            self.int = False
        elif c == 0x31:
            self.have_disk = bool(self.folder) and os.path.isdir(self.folder)
            self.setint(0x14 if self.have_disk else 0x82)
        elif c == 0x2F:
            self.name = b""
        elif c == 0x32:
            self._open()
        elif c == 0x33:
            self.enum_i += 1
            self.setint(0x1D if self.enum_i < len(self.enum) else 0x42)
        elif c == 0x35:
            p = self._find(self.name)
            if p:
                os.remove(p)
                self.setint(0x14)
            else:
                self.setint(0x42)
        elif c == 0x34:
            p = self._path(self.name)
            if not p:
                self.setint(0xB4)
                return
            self._flush()
            self.fh = (p, bytearray(), True)
            with open(p, "wb"):
                pass
            self.mode = "w"
            self.setint(0x14)
        elif c == 0x2D:
            n = min(64, self.wr_remaining)
            self.out = deque([n])
        elif c == 0x3D:
            self.setint(0x1E if self.wr_remaining > 0 else 0x14)
        elif c == 0x27:
            if self.mode == "enum":
                self.out = deque([32] + list(self.enum[self.enum_i]))
            else:
                n = min(64, self.rd_remaining)
                data = self.fh[1][self.pos:self.pos + n]
                self.out = deque([n] + list(data))
                self.pos += n
                self.rd_remaining -= n
        elif c == 0x3B:
            self.setint(0x1D if self.rd_remaining > 0 else 0x14)

    def _open(self):
        if self.name in (b"/*", b"*"):
            self.enum = self._entries() if self.have_disk else []
            self.enum_i = 0
            self.mode = "enum"
            self.setint(0x1D if self.enum else 0x42)
            return
        p = self._find(self.name)
        if p:
            self._flush()
            with open(p, "rb") as f:
                self.fh = (p, bytearray(f.read()), False)
            self.pos = 0
            self.mode = "r"
            self.rd_remaining = len(self.fh[1])
            self.setint(0x14)
        else:
            self.setint(0x42)

    def wr_data(self, v):
        if not self.present:
            return
        c = self.cmd
        if c == 0x06:
            self.out = deque([(~v) & 255])
        elif c == 0x15:
            self.out = deque([0x51])
        elif c == 0x2F:
            if v:
                self.name += bytes([v])
        elif c == 0x3C:
            self.args.append(v)
            if len(self.args) == 2:
                self.wr_remaining = self.args[0] | (self.args[1] << 8)
                self.setint(0x1E)
        elif c == 0x2D:
            if self.fh:
                self.fh[1].append(v)
                self.fh = (self.fh[0], self.fh[1], True)
            self.wr_remaining -= 1
        elif c == 0x3A:
            self.args.append(v)
            if len(self.args) == 2:
                req = self.args[0] | (self.args[1] << 8)
                have = len(self.fh[1]) - self.pos if self.fh else 0
                self.rd_remaining = min(req, have)
                self.setint(0x1D if self.rd_remaining > 0 else 0x14)
        elif c == 0x36:
            self._flush()
            self.setint(0x14)


# -------------------------------------------------------------------- machine
class Machine:
    def __init__(self, rom, hz=CPU_HZ_DEFAULT, disk=None, ch376=True, ram_random=False):
        self.hz = hz
        self.mem = bytearray(65536)
        if ram_random:
            for a in range(0x8000, 0x10000):
                self.mem[a] = random.randrange(256)
        self.mem[:len(rom)] = rom[:0x8000]
        self.breakpoints = set()
        self.next_tick = 0
        self.cpu = CPU(self)
        self.via = VIA(self)
        self.serial = ACIA(self, "serial")
        self.kbd = ACIA(self, "display")          # keyboard/display card
        self.ch = CH376(self, disk, present=ch376)
        self.trace_io = False
        self.io_log = []
        self.misc_ports = {}
        self.port_hook = None
        self.mirrors = {0x24: 0x20, 0x25: 0x21, 0x28: 0x20, 0x29: 0x21, 0x2C: 0x20, 0x2D: 0x21}
        self.tick(0)

    def reset(self):
        self.cpu.reset()
        for d in (self.via, self.serial, self.kbd, self.ch):
            d.reset_all()

    def tick(self, cyc):
        self.via.tick(cyc)
        self.serial.tick(cyc)
        self.kbd.tick(cyc)
        self.next_tick = cyc + 40

    def irq_line(self):
        return self.via.irq_line() or self.serial.irq_line() or self.kbd.irq_line()

    def port_write_hook(self, name, v):
        if self.port_hook:
            self.port_hook(name, v)

    def io_read(self, p):
        p = self.mirrors.get(p, p)
        if p <= 0x0F:
            v = self.via.read(p)
        elif 0x14 <= p <= 0x17:
            v = self.serial.read(p - 0x14)
        elif 0x18 <= p <= 0x1B:
            v = self.kbd.read(p - 0x18)
        elif p == 0x20:
            v = self.ch.rd_data()
        elif p == 0x21:
            v = self.ch.rd_status()
        elif p == 0xFF:
            v = 0xFF
            for n, dev in ((2, self.via), (3, self.serial), (5, self.kbd)):
                if dev.irq_line():
                    v = (7 - n) * 2
                    break
        else:
            v = self.misc_ports.get(p, 0xFF)
        if self.trace_io:
            self.io_log.append("IN  %02X -> %02X" % (p, v))
        return v

    def io_write(self, p, v):
        if self.trace_io:
            self.io_log.append("OUT %02X <- %02X" % (p, v))
        p = self.mirrors.get(p, p)
        if p <= 0x0F:
            self.via.write(p, v)
        elif 0x14 <= p <= 0x17:
            self.serial.write(p - 0x14, v)
        elif 0x18 <= p <= 0x1B:
            self.kbd.write(p - 0x18, v)
        elif p == 0x20:
            self.ch.wr_data(v)
        elif p == 0x21:
            self.ch.wr_cmd(v)
        else:
            self.misc_ports[p] = v

    def run_cycles(self, n):
        return self.cpu.run(n)


# ----------------------------------------------------------- host side
class HostTerm:
    """Raw keyboard in, VT100 out, on the host terminal."""

    def __init__(self):
        self.q = deque()
        self.out = sys.stdout.buffer
        self.saved = None
        self.alive = True
        self.paused = False
        self.is_tty = sys.stdin.isatty()

    def start(self):
        if os.name == "nt":
            os.system("")                              # enable ANSI escapes
            threading.Thread(target=self._win_reader, daemon=True).start()
        else:
            if self.is_tty:
                import termios
                import tty
                self.saved = termios.tcgetattr(sys.stdin.fileno())
                tty.setraw(sys.stdin.fileno())
            threading.Thread(target=self._posix_reader, daemon=True).start()

    def _posix_reader(self):
        fd = sys.stdin.fileno()
        while self.alive:
            if self.paused:
                time.sleep(0.02)
                continue
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r or self.paused:
                continue
            try:
                d = os.read(fd, 64)
            except OSError:
                break
            if not d:
                break
            self.q.extend(d)

    def _win_reader(self):
        import msvcrt
        while self.alive:
            if self.paused or not msvcrt.kbhit():
                time.sleep(0.01)
                continue
            ch = msvcrt.getwch()
            if ch in ("\x00", "\xe0"):
                msvcrt.getwch()
                continue
            self.q.extend(ch.encode("latin1", "replace"))

    def stop(self):
        self.alive = False
        if self.saved:
            import termios
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, self.saved)
            self.saved = None

    def suspend(self):
        self.paused = True
        time.sleep(0.1)
        if self.saved:
            import termios
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, self.saved)

    def resume(self):
        if self.saved:
            import tty
            tty.setraw(sys.stdin.fileno())
        self.paused = False

    def write(self, b):
        self.out.write(bytes([b]))

    def flush(self):
        self.out.flush()

    def read_all(self):
        data = bytearray()
        while self.q:
            data.append(self.q.popleft())
        return bytes(data)


class TcpPort:
    def __init__(self, port):
        self.srv = socket.socket()
        self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.srv.bind(("127.0.0.1", port))
        self.srv.listen(1)
        self.srv.setblocking(False)
        self.cli = None

    def poll(self):
        try:
            if self.cli is None:
                try:
                    self.cli, _ = self.srv.accept()
                    self.cli.setblocking(False)
                except BlockingIOError:
                    return b""
            r, _, _ = select.select([self.cli], [], [], 0)
            if r:
                d = self.cli.recv(256)
                if not d:
                    self.cli.close()
                    self.cli = None
                    return b""
                return d
        except OSError:
            self.cli = None
        return b""

    def send(self, b):
        if self.cli:
            try:
                self.cli.send(bytes([b]))
            except OSError:
                self.cli = None


def load_rom(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".asm":
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from asm8085 import Asm
        a = Asm()
        a.assemble_file(path)
        hi = max(i for i, u in enumerate(a.used) if u)
        return bytes(a.mem[:hi + 1])
    if ext in (".hex", ".ihx"):
        rom = bytearray(0x8000)
        for line in open(path):
            line = line.strip()
            if not line.startswith(":"):
                continue
            n = int(line[1:3], 16)
            addr = int(line[3:7], 16)
            typ = int(line[7:9], 16)
            if typ == 0:
                for i in range(n):
                    if addr + i < 0x8000:
                        rom[addr + i] = int(line[9 + 2 * i:11 + 2 * i], 16)
        return bytes(rom)
    return open(path, "rb").read()


HELP = """emulator commands (Ctrl-] to get here):
  help                this text
  go | cont           back to the computer
  quit                leave the emulator
  reset               reset the CPU and devices (RAM is kept)
  regs                registers and flags, next instruction
  step [n]            execute n instructions (default 1)
  dump ADDR [LEN]     hex dump of memory (numbers are hex)
  poke ADDR VAL       write RAM
  bp ADDR / unbp ADDR set / clear a breakpoint ("bp" alone lists them)
  io on|off           log I/O port reads and writes
  ca1 ca2 cb1 cb2     raise that VIA interrupt flag (VIA IRQ is IRQ 2)
  pina VAL / pinb VAL set the level seen on the VIA port pins when read
  type TEXT           type text into the console (\\r is Enter)
  serial TEXT         send text to the serial card (\\r \\n allowed)
  sendfile FILE       send a file to the serial card at the programmed baud rate
  disk                show the USB stick folder contents"""


class Emulator:
    def __init__(self, args):
        rom = load_rom(args.rom)
        self.hz = int(args.speed * 1e6) if args.speed else CPU_HZ_DEFAULT
        self.realtime = args.speed != 0
        self.args = args
        disk = args.disk
        if disk and not os.path.isdir(disk):
            os.makedirs(disk, exist_ok=True)
        self.m = Machine(rom, hz=self.hz, disk=None if args.no_disk else disk,
                         ch376=not args.no_ch376, ram_random=args.ram_random)
        self.term = HostTerm()
        self.console = self.m.kbd if args.console == "display" else self.m.serial
        self.other = self.m.serial if args.console == "display" else self.m.kbd
        self.console.sink = self.term.write
        self.tcp = None
        if args.serial:
            if args.serial.startswith("tcp:"):
                self.tcp = TcpPort(int(args.serial[4:]))
                if self.console is not self.m.serial:
                    self.m.serial.sink = self.tcp.send
                print("serial card: connect to 127.0.0.1:%s" % args.serial[4:], file=sys.stderr)
        if args.serial_send:
            self.m.serial.feed(open(args.serial_send, "rb").read())
        self.m.trace_io = False

    def dbg(self):
        t = self.term
        t.suspend()
        t.flush()
        m = self.m
        out = sys.stdout
        out.write("\r\n[emulator]  type 'help'\r\n")
        out.flush()
        while True:
            try:
                out.write("emu> ")
                out.flush()
                line = sys.stdin.readline() if not t.saved else self._cooked_line()
            except (EOFError, KeyboardInterrupt):
                return False
            if line == "":
                return False
            parts = line.strip().split()
            if not parts:
                continue
            cmd, a = parts[0].lower(), parts[1:]
            try:
                if cmd in ("go", "cont", "g", "c"):
                    m.cpu.skip_bp = m.cpu.PC
                    break
                elif cmd in ("quit", "q", "exit"):
                    return False
                elif cmd == "help":
                    print(HELP)
                elif cmd == "reset":
                    m.reset()
                elif cmd == "regs":
                    self._regs()
                elif cmd == "step":
                    for _ in range(int(a[0]) if a else 1):
                        try:
                            m.cpu.skip_bp = m.cpu.PC
                            m.cpu.run(1)
                        except Halted as e:
                            print(e)
                            break
                    self._regs()
                elif cmd == "dump":
                    base = int(a[0], 16)
                    n = int(a[1], 16) if len(a) > 1 else 128
                    for r in range(0, n, 16):
                        row = bytes(m.mem[(base + r + i) & 0xFFFF] for i in range(min(16, n - r)))
                        print("%04X: %-48s %s" % ((base + r) & 0xFFFF, " ".join("%02X" % b for b in row),
                                                  "".join(chr(b) if 32 <= b < 127 else "." for b in row)))
                elif cmd == "poke":
                    m.mem[int(a[0], 16) & 0xFFFF] = int(a[1], 16) & 255
                elif cmd == "bp":
                    if a:
                        m.breakpoints.add(int(a[0], 16))
                    print("breakpoints:", " ".join("%04X" % b for b in sorted(m.breakpoints)) or "none")
                elif cmd == "unbp":
                    m.breakpoints.discard(int(a[0], 16))
                elif cmd == "io":
                    m.trace_io = a and a[0].lower() == "on"
                    if m.trace_io:
                        m.io_log.clear()
                elif cmd in ("ca1", "ca2", "cb1", "cb2"):
                    m.via.raise_flag({"ca1": VIA.CA1, "ca2": VIA.CA2, "cb1": VIA.CB1, "cb2": VIA.CB2}[cmd])
                elif cmd == "pina":
                    m.via.pina = int(a[0], 16) & 255
                elif cmd == "pinb":
                    m.via.pinb = int(a[0], 16) & 255
                elif cmd == "type":
                    self.console.feed(self._unesc(line.strip()[5:]), gap=self.hz // 250)
                elif cmd == "serial":
                    m.serial.feed(self._unesc(line.strip()[7:]))
                elif cmd == "sendfile":
                    m.serial.feed(open(a[0], "rb").read())
                elif cmd == "disk":
                    d = self.args.disk
                    print("\n".join(sorted(os.listdir(d))) if d and os.path.isdir(d) else "no disk folder")
                else:
                    print("unknown command; try help")
            except (ValueError, IndexError, OSError) as e:
                print("error:", e)
        t.resume()
        return True

    def _cooked_line(self):
        return sys.stdin.readline()

    @staticmethod
    def _unesc(s):
        return s.replace("\\r", "\r").replace("\\n", "\n").encode("latin1", "replace")

    def _regs(self):
        c = self.m.cpu
        R = c.R
        f = "".join(n if c.F & b else "-" for n, b in (("S", 0x80), ("Z", 0x40), ("A", 0x10), ("P", 4), ("C", 1)))
        print("A=%02X B=%02X C=%02X D=%02X E=%02X H=%02X L=%02X  SP=%04X PC=%04X  F=%s  IE=%d M6.5=%d" % (
            R[7], R[0], R[1], R[2], R[3], R[4], R[5], c.SP, c.PC, f, c.inte, c.mask65))
        txt, _ = disasm(self.m.mem, c.PC)
        print("%04X: %s" % (c.PC, txt))
        if self.m.trace_io and self.m.io_log:
            print("\n".join(self.m.io_log[-20:]))
            self.m.io_log.clear()

    def run(self):
        a = self.args
        m = self.m
        t = self.term
        t.start()
        chunk = max(2000, self.hz // 200)              # ~5 ms of CPU time per slice
        t0 = time.perf_counter()
        c0 = m.cpu.cycles
        try:
            while True:
                try:
                    m.run_cycles(chunk)
                except Halted as e:
                    t.flush()
                    sys.stdout.write("\r\n[%s]\r\n" % e)
                    if not self.dbg():
                        break
                    t0 = time.perf_counter()
                    c0 = m.cpu.cycles
                    continue
                data = t.read_all()
                if data:
                    if 0x1D in data:                   # Ctrl-]
                        data = data.replace(b"\x1d", b"")
                        if data:
                            self.console.feed(data, gap=self.hz // 250)
                        if not self.dbg():
                            break
                        t0 = time.perf_counter()
                        c0 = m.cpu.cycles
                        continue
                    self.console.feed(data, gap=self.hz // 250)
                if self.tcp:
                    d = self.tcp.poll()
                    if d:
                        m.serial.feed(d)
                t.flush()
                if self.realtime:
                    ahead = (m.cpu.cycles - c0) / self.hz - (time.perf_counter() - t0)
                    if ahead > 0:
                        time.sleep(min(ahead, 0.05))
                    elif ahead < -0.5:                  # fell behind: do not try to catch up
                        t0 = time.perf_counter()
                        c0 = m.cpu.cycles
        finally:
            t.stop()
            sys.stdout.write("\r\n")


def main():
    ap = argparse.ArgumentParser(description="Emulator for the custom 8085 computer (see the file header).")
    ap.add_argument("rom", help="ROM image: .bin (loaded at 0000), .hex, or .asm (needs asm8085.py)")
    ap.add_argument("--console", choices=("display", "serial"), default="display",
                    help="which port your keyboard/screen are connected to (default display card)")
    ap.add_argument("--disk", metavar="DIR", help="host folder used as the CH376 USB stick")
    ap.add_argument("--no-disk", action="store_true", help="CH376 present but no stick inserted")
    ap.add_argument("--no-ch376", action="store_true", help="no CH376 at all")
    ap.add_argument("--serial", metavar="tcp:PORT", help="connect the serial card to a TCP port on 127.0.0.1")
    ap.add_argument("--serial-send", metavar="FILE", help="feed FILE into the serial card at start-up")
    ap.add_argument("--speed", type=float, default=2.4576,
                    help="CPU clock in MHz (default 2.4576, 0 = as fast as possible)")
    ap.add_argument("--ram-random", action="store_true", help="fill RAM with random bytes at power-up")
    args = ap.parse_args()
    Emulator(args).run()


if __name__ == "__main__":
    main()
