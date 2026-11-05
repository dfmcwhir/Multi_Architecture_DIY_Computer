"""MINER MOS: no input at all: the guardians or the air take every life,
the room starts again each time, and the game ends (GAME OVER, then back to
the title with Q).  Checks the screen against the room after each restart."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import sim
from sim import Machine
import gen, phys, model
OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('miner.lbl')) if m}
mc = Machine('MINER.BIN', ctrl=1); mem = mc.mpu.memory
def v(n): return mem[syms[n]]
def text(): return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
lives = []
for i in range(1500):
    mc.run(500_000)
    if not lives or v('lives') != lives[-1]: lives.append(v('lives'))
    if 'GAME  OVER' in text(): break
mc.term.png(OUT + '/over.png')
over = 'GAME  OVER' in text()
mc.run(4_000_000); mc.keys.append(ord('q')); mc.run(3_000_000)
back = 'MINER  MOS' in text()
ok = over and back and lives == [3, 2, 1, 0]
print('lives seen %s, game over %s, back at the title %s, terminal errors %s -> %s' % (lives, over, back, mc.term.errors[:3], 'ok' if ok else 'FAILED'))
