"""MINER MOS: the keyboard (G on the title, then Space): D walks right, A
left, W jumps, P pauses and any key goes on, Q quits to the title."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
import sim
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('miner.lbl')) if m}
mc = Machine('MINER.BIN', ctrl=1); mem = mc.mpu.memory
def v(n): return mem[syms[n]]
def text(): return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
res = []
def check(what, ok): res.append(ok); print('%-40s %s' % (what, 'ok' if ok else 'FAILED'))
mc.run(3_000_000)
mc.keys.append(ord('g')); mc.run(500_000)
check('G: the keyboard', 'CONTROLS: KEYBOARD' in text())
mc.keys.append(ord(' ')); mc.run(4_000_000)
x0 = v('w_x')
for i in range(10): mc.keys.append(ord('d')); mc.run(200_000)
x1 = v('w_x')
check('D: right (%d -> %d)' % (x0, x1), x1 > x0 + 10)
for i in range(4): mc.keys.append(ord('a')); mc.run(200_000)
check('A: left (%d -> %d)' % (x1, v('w_x')), v('w_x') < x1)
mc.run(400_000)
y0 = v('w_y'); mc.keys.append(ord('w')); mc.run(300_000)
check('W: a jump (y %d -> %d)' % (y0, v('w_y')), v('w_y') < y0 or v('w_mode') != 0)
mc.run(1_000_000)
mc.keys.append(ord('p')); mc.run(500_000)
check('P: paused', 'PAUSED' in text())
a0 = v('air'); mc.run(3_000_000)
check('... the air stays', v('air') == a0)
mc.keys.append(ord('x')); mc.run(500_000)
check('a key: going again', 'PAUSED' not in text())
mc.keys.append(ord('q')); mc.run(3_000_000)
check('Q: the title', 'MINER  MOS' in text())
print('%d checks, %d failed' % (len(res), res.count(False)))
