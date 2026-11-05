# PY65=... python3 test/prof.py : where the 6502's time goes while walking (and scrolling)
import sys, os, bisect, collections
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
g = Game(speed=0); mc = g.mc
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(8_000_000)
mc.keys.append(ord('D'))
mc.run(500_000)
labs = sorted((a, n) for n, a in syms.items() if 0x500 <= a < code_end and not n.startswith('@'))
addrs = [a for a, n in labs]
cyc = collections.Counter()
mpu = mc.mpu
f0 = g.v('frame'); b0 = mc.term.nbytes; c0 = mpu.processorCycles
CH = sim.CHROUT
while (g.v('frame') - f0) & 255 < int(os.environ.get('N', '30')):
    pc = mpu.pc
    before = mpu.processorCycles
    if pc == CH:
        cyc['(serial)'] += 87 * sim.CPU_MHZ
    mc.run(1)
    if pc != CH:
        i = bisect.bisect_right(addrs, pc) - 1
        cyc[labs[i][1]] += mpu.processorCycles - before
n = (g.v('frame') - f0) & 255
tot = mpu.processorCycles - c0
print('frames', n, 'cycles/frame', tot // n, 'bytes/frame', (mc.term.nbytes - b0) // n, 'scroll', g.w('scroll'))
for k, c in cyc.most_common(14): print('%-14s %6d per frame %4.1f%%' % (k, c // n, 100 * c / tot))
