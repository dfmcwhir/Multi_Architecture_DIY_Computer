"""measure each frame's work (cycles from the top of the loop to pace) and fit
work = a + b * pixels + c * rows + d * bytes  (serial time taken out)"""
import sys, os, re
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import sim
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
mc = Machine('ROCKS.BIN'); mpu = mc.mpu; mem = mpu.memory
mc.run(3_000_000); mc.keys.append(32); mc.run(1_000_000)
rows = []; st = {}
orig = mpu.step
def step():
    pc = mpu.pc
    if pc == syms['game_loop']: st['t0'] = mpu.processorCycles; st['b0'] = mc.term.nbytes
    elif pc == syms['pace'] and 't0' in st:
        nb = mc.term.nbytes - st['b0']
        work = mpu.processorCycles - st['t0'] - nb * 87 * sim.CPU_MHZ     # minus the serial waiting
        rows.append((work, mem[syms['npix']] + 256 * mem[syms['npix'] + 1], mem[syms['nrows_seen']], nb))
    orig()
mpu.step = step
import random; random.seed(3)
for i in range(120):
    mc.keys.extend(map(ord, random.choice(['d', 'a', 'w', ' ', '', 'dd', ' w'])))
    mc.run(100_000)
A = np.array([[1, p, r, b] for w, p, r, b in rows], float); y = np.array([w for w, p, r, b in rows], float)
coef, *_ = np.linalg.lstsq(A, y, rcond=None)
pred = A @ coef
print('frames', len(rows), 'work cycles mean %.0f, max %.0f' % (y.mean(), y.max()))
print('fit (cycles at this clock): base %.0f, per pixel %.1f, per row %.0f, per byte %.1f' % tuple(coef))
print('worst error %.0f cycles' % np.abs(pred - y).max())
print('mean pixels %.0f rows %.1f bytes %.0f' % (A[:, 1].mean(), A[:, 2].mean(), A[:, 3].mean()))
