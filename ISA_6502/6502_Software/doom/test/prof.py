"""cycles per call of named routines (nested calls allowed)"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
mc = Machine('DOOM.BIN', speed=0, code_end=code_end)
mc.set_disk('.')
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(3_000_000)
mpu = mc.mpu
names = sys.argv[1:]
addr = {syms[n]: n for n in names}
tot = {n: 0 for n in names}; calls = {n: 0 for n in names}
stack = []
orig = mpu.step
def step():
    pc = mpu.pc
    if pc in addr:
        stack.append((addr[pc], mpu.processorCycles, mpu.sp)); calls[addr[pc]] += 1
    op = mpu.memory[pc]
    orig()
    while stack and op == 0x60 and mpu.sp == (stack[-1][2] + 2) & 0xFF:
        n, t, _ = stack.pop(); tot[n] += mpu.processorCycles - t
        break
mpu.step = step
seq = list(os.environ.get('SEQ', 'DDDWWW'))
def poll(m):
    if not m.keys and seq: m.keys.append(ord(seq.pop(0)))
mc.run(4_000_000, poll)
for n in names: print('%-14s calls %6d  cycles/call %7.0f  total %8d' % (n, calls[n], tot[n] / max(1, calls[n]), tot[n]))
