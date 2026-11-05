import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('rocks.map').read()).group(1), 16)
mc = Machine('ROCKS.BIN', code_end=code_end); mem = mc.mpu.memory
OUT = sys.argv[1]
mc.run(3_000_000); mc.term.png(OUT + '/title.png')
mc.keys.append(32); mc.run(1_000_000); mc.term.png(OUT + '/start.png')
f0 = mem[syms['frame']]; c0 = mc.mpu.processorCycles; b0 = mc.term.nbytes
for i in range(60):
    mc.keys.extend(map(ord, 'd w ' if i % 3 else 'w'))
    mc.run(100_000)
f1 = mem[syms['frame']]
print('frames', (f1 - f0) & 255, 'in', (mc.mpu.processorCycles - c0) / 2e6, 's at 2 MHz;', mc.term.nbytes - b0, 'bytes')
print('score', ['%02X' % mem[syms['score'] + i] for i in (2, 1, 0)], 'lives', mem[syms['lives']], 'wave', mem[syms['wave']])
print('errors', mc.term.errors[:5])
mc.term.png(OUT + '/play.png')
