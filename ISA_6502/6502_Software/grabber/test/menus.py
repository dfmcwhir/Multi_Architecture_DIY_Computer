# PY65=... python3 test/menus.py : the title, the controls, pause and quit
from gtest import *
results = []
def check(what, ok):
    results.append(ok); print('%-55s %s' % (what, 'ok' if ok else 'FAILED'))
g = Game(pad=None) if False else None
import sim as _s
mc = Machine('GRABBER.BIN', code_end=code_end)          # (as built: no override)
g = Game.__new__(Game); g.mc = mc; g.mem = mc.mpu.memory
mc.run(3_000_000)
check('title: "GOLD GRABBER", gamepad by default', 'GOLD GRABBER' in g.text() and 'CONTROLS: GAMEPAD' in g.text())
mc.keys.append(ord('g')); mc.run(500_000)
check('G: the keyboard', 'CONTROLS: KEYBOARD' in g.text() and g.v('ctrl') == 0)
mc.keys.append(ord(' ')); mc.run(1_500_000)
check('space: "LEVEL 1" and its goal', 'LEVEL 1' in g.text() and 'GOAL   $' in g.text())
mc.run(6_000_000)
check('playing: the status line', 'MONEY  $0' in g.text() and 'TIME' in g.text() and 'BOMBS 0' in g.text())
f0 = g.v('frame')
mc.keys.append(ord('p')); mc.run(2_000_000)
check('P: paused', 'PAUSED' in g.text() and g.v('frame') == f0 + 1 or ('PAUSED' in g.text() and abs(g.v('frame') - f0) <= 2))
f1 = g.v('frame'); mc.run(1_000_000)
check('... and stays still', g.v('frame') == f1)
mc.keys.append(ord('x')); mc.run(1_000_000)
check('a key: going again', g.v('frame') != f1 and 'PAUSED' not in g.text())
t0 = g.v('tsec'); mc.run(25_000_000)
check('the clock counts down (%d -> %d)' % (t0, g.v('tsec')), 0 < t0 - g.v('tsec') <= 15)
mc.keys.append(ord('q')); mc.run(2_000_000)
check('Q: back to the title', 'SPACE OR START: PLAY' in g.text())
mc.keys.append(ord('q')); mc.run(1_000_000)
check('Q on the title: the boot menu', mc.exited)
mc = Machine('GRABBER.BIN', code_end=code_end); g.mc = mc; g.mem = mc.mpu.memory
mc.run(3_000_000); mc.set_pad(0x08); mc.run(50_000); mc.set_pad(0); mc.run(8_000_000)
f0 = g.v('frame'); mc.set_pad(0x08); mc.run(250_000); mc.set_pad(0); mc.run(2_000_000)
check('pad: Start pauses', 'PAUSED' in g.text())
f1 = g.v('frame'); mc.set_pad(0x08); mc.run(250_000); mc.set_pad(0); mc.run(1_000_000)
check('... and Start goes on', g.v('frame') != f1)
mc.set_pad(0x01); mc.run(250_000); mc.set_pad(0); mc.run(400_000)
check('pad A: the grabber goes out', g.v('hst') in (1, 2))
print('%d checks, %d failed' % (len(results), results.count(False)))
