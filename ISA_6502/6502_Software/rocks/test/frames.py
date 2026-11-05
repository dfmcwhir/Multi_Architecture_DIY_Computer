"""frame times in real ms during play (at the clock in CPU_MHZ)"""
import sys, os, re, random
sys.path.insert(0, os.path.dirname(__file__))
import sim
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
mc = Machine('ROCKS.BIN'); mpu = mc.mpu
mc.run(3_000_000 * sim.CPU_MHZ); mc.keys.append(32); mc.run(1_000_000 * sim.CPU_MHZ)
marks = []; nb = []; orig = mpu.step
def step():
    if mpu.pc == syms['game_loop']: marks.append(mpu.processorCycles); nb.append(mc.term.nbytes)
    orig()
mpu.step = step
random.seed(5)
for i in range(80):
    mc.keys.extend(map(ord, random.choice(['d', 'a', 'w', ' ', '', 'dd', ' w'])))
    mc.run(50_000 * sim.CPU_MHZ)
ms = [(b - a) / (1000 * sim.CPU_MHZ) for a, b in zip(marks, marks[1:])]
ms.sort()
print('CPU_MHZ=%d: %d frames, frame ms: median %.1f, 10%% %.1f, 90%% %.1f, max %.1f' % (sim.CPU_MHZ, len(ms), ms[len(ms)//2], ms[len(ms)//10], ms[len(ms)*9//10], ms[-1]))
bb = sorted(b - a for a, b in zip(nb, nb[1:]))
print('bytes a frame: median %d, 90%% %d, max %d' % (bb[len(bb)//2], bb[len(bb)*9//10], bb[-1]))
