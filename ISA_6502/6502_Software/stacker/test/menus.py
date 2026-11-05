"""title: G toggle, level digits; in the game: pause, quit to the title, quit to the boot menu"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('stacker.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
mc = Machine('STACKER.BIN')
mem = mc.mpu.memory
def text(): return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
ok = True
def check(cond, what):
    global ok
    print(('ok   ' if cond else 'FAIL ') + what); ok &= bool(cond)
mc.run(2_000_000)
check('CONTROLS: KEYBOARD' in text(), 'title shows keyboard')
mc.keys.append(ord('g')); mc.run(500_000)
check('CONTROLS: GAMEPAD' in text(), 'G switches to the gamepad')
mc.keys.append(ord('g')); mc.keys.append(ord('5')); mc.run(500_000)
check('(0-9): 5' in text() and mem[syms['start_level']] == 5, 'a digit sets the starting level')
mc.keys.append(ord(' ')); mc.run(1_500_000)
check('LEVEL' in text() and mem[syms['level']] == 5, 'game starts at level 5')
mc.keys.append(ord('p')); mc.run(500_000)
t = mem[syms['ticks']]; mc.run(1_000_000)
check('PAUSED' in text() and mem[syms['ticks']] == t, 'P pauses')
mc.keys.append(ord('x')); mc.run(500_000)
check(mem[syms['ticks']] != t and 'PAUSED' not in text(), 'a key carries on')
mc.keys.append(ord('q')); mc.run(1_500_000)
check('STARTING LEVEL' in text(), 'Q back to the title')
mc.keys.append(ord('q')); mc.run(1_000_000)
check(mc.exited, 'Q on the title: back to the boot menu')
print('terminal errors', mc.term.errors[:3])
sys.exit(0 if ok else 1)
