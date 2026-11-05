"""frame times in real ms during play (at the clock in CPU_MHZ), and bytes a frame"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
import sim
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('breaker.lbl')) if m}
mc = Machine('BREAKER.BIN', ctrl=1); mpu = mc.mpu
mc.run(3_000_000 * sim.CPU_MHZ); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0); mc.run(1_000_000 * sim.CPU_MHZ)
marks = []; nb = []; orig = mpu.step
def step():
    if mpu.pc == syms['game_loop']: marks.append(mpu.processorCycles); nb.append(mc.term.nbytes)
    orig()
mpu.step = step
for i in range(60):
    mc.set_pad(0x01 if i % 10 == 0 else (0x40 if i % 4 < 2 else 0x80))
    mc.run(50_000 * sim.CPU_MHZ)
ms = sorted((b - a) / (1000 * sim.CPU_MHZ) for a, b in zip(marks, marks[1:]))
bb = sorted(b - a for a, b in zip(nb, nb[1:]))
print('CPU_MHZ=%d: %d frames, frame ms: median %.1f, 10%% %.1f, 90%% %.1f, max %.1f; bytes a frame: median %d, max %d' % (
    sim.CPU_MHZ, len(ms), ms[len(ms)//2], ms[len(ms)//10], ms[len(ms)*9//10], ms[-1], bb[len(bb)//2], bb[-1]))
