"""frame times in real ms while playing (at the clock in CPU_MHZ)"""
from gtest import *
g = Game(pad=False); mc = g.mc; mpu = mc.mpu
mc.run(3_000_000 * sim.CPU_MHZ); mc.keys.append(32); mc.run(1_000_000 * sim.CPU_MHZ)
if os.environ.get('LASER'): g.mem[syms['has_laser']] = 1     # (with the laser pointer on)
mc.run(5_000_000 * sim.CPU_MHZ)
marks = []; orig = mpu.step
def step():
    if mpu.pc == syms['game_loop']: marks.append(mpu.processorCycles)
    orig()
mpu.step = step
for i in range(120):
    if i % 10 == 0: mc.keys.append(32)
    mc.run(100_000 * sim.CPU_MHZ)
ms = [(b - a) / (1000 * sim.CPU_MHZ) for a, b in zip(marks, marks[1:])]
ms.sort()
print('CPU_MHZ=%d: %d frames, frame ms: median %.1f, 10%% %.1f, 90%% %.1f, max %.1f' % (sim.CPU_MHZ, len(ms), ms[len(ms)//2], ms[len(ms)//10], ms[len(ms)*9//10], ms[-1]))
