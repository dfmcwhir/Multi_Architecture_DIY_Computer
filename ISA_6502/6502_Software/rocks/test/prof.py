"""cycles per call of named routines (nested calls allowed), during play"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
mc = Machine('ROCKS.BIN'); mpu = mc.mpu
mc.run(3_000_000); mc.keys.append(32); mc.run(1_000_000)
names = sys.argv[1:]
addr = {syms[n]: n for n in names}
tot = {n: 0 for n in names}; calls = {n: 0 for n in names}; stack = []
orig = mpu.step
def step():
    pc = mpu.pc
    if pc in addr:
        stack.append((addr[pc], mpu.processorCycles, mpu.sp)); calls[addr[pc]] += 1
    op = mpu.memory[pc]
    orig()
    if stack and op == 0x60 and mpu.sp == (stack[-1][2] + 2) & 0xFF:
        n, t, _ = stack.pop(); tot[n] += mpu.processorCycles - t
mpu.step = step
for i in range(30):
    mc.keys.extend(map(ord, 'd w '))
    mc.run(100_000)
for n in names: print('%-14s calls %6d  cycles/call %7.0f  total %8d' % (n, calls[n], tot[n] / max(1, calls[n]), tot[n]))
