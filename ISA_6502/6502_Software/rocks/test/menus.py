"""title: G toggle; in the game: pause, quit to the title, quit to the boot menu"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
mc = Machine('ROCKS.BIN'); mem = mc.mpu.memory
def text(): return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
ok = True
def check(cond, what):
    global ok
    print(('ok   ' if cond else 'FAIL ') + what); ok &= bool(cond)
mc.run(3_000_000)
check('CONTROLS: KEYBOARD' in text(), 'title shows keyboard')
mc.keys.append(ord('g')); mc.run(1_000_000)
check('CONTROLS: GAMEPAD' in text() and mem[syms['ctrl']] == 1, 'G switches to the gamepad')
mc.keys.append(ord('G')); mc.run(1_000_000)
check('CONTROLS: KEYBOARD' in text(), 'G switches back')
mc.keys.append(ord(' ')); mc.run(2_000_000)
check('SCORE' in text() and 'WAVE' in text(), 'game started')
mc.keys.append(ord('p')); mc.run(1_000_000)
f = mem[syms['frame']]; mc.run(2_000_000)
check('PAUSED' in text() and mem[syms['frame']] == f, 'P pauses')
mc.keys.append(ord('x')); mc.run(1_000_000)
check(mem[syms['frame']] != f and 'PAUSED' not in text(), 'a key carries on')
mc.keys.append(ord('q')); mc.run(3_000_000)
check('SPACE ROCKS' in text(), 'Q back to the title')
mc.keys.append(ord('q')); mc.run(2_000_000)
check(mc.exited, 'Q on the title: back to the boot menu')
print('terminal errors', mc.term.errors[:3])
sys.exit(0 if ok else 1)
