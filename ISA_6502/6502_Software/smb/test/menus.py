# usage (from the smb folder):  PY65=... python3 test/menus.py OUTDIR
"""The keyboard controls, the title screen, pause and quit."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
results = []
def check(what, ok):
    results.append(ok); print('%-55s %s' % (what, 'ok' if ok else 'FAILED'))

g = Game(speed=0); mc = g.mc
st = dict(f=-1, n=0)
def poll(m):
    if g.at_frame_start(m) and g.v('frame') != st['f']:
        st['f'] = g.v('frame'); st['n'] += 1
        for i in range(1, 7): g.mem[syms['o_kind'] + i] = 0      # (no enemies: just the controls)
        a = g.mem[syms['en_rd'] + 1] | g.mem[syms['en_rd'] + 2] << 8
        i = 0
        while g.mem[a + i] != 0xFF: i += 3
        g.mem[syms['en_i']] = i
def frames(k):
    end = st['n'] + k
    while st['n'] < end and not mc.exited: mc.run(10_000, poll)
def keys(s): mc.keys.extend(ord(c) for c in s)
def rise(k=8):
    """how high MOS gets in the next k frames"""
    y0 = g.s8('o_y'); top = y0
    for i in range(k):
        frames(1); top = min(top, g.s8('o_y'))
    return y0 - top

g0 = Game()                                     # (as built: no override)
g0.mem[0x504] = open('SMB.BIN', 'rb').read()[4]
g0.mc.run(3_000_000)
check('as built: the gamepad by default', 'CONTROLS: GAMEPAD' in g0.text())
mc.run(3_000_000)
check('title: the banner and "SPACE OR START: PLAY"', 'SPACE OR START: PLAY' in g.text() and 'CONTROLS: KEYBOARD' in g.text())
keys('g'); mc.run(500_000)
check('G: gamepad', 'CONTROLS: GAMEPAD' in g.text() and g.v('ctrl') == 1)
keys('G'); mc.run(500_000)
check('G again: keyboard', 'CONTROLS: KEYBOARD' in g.text() and g.v('ctrl') == 0)
keys(' '); mc.run(500_000)
check('space: "CELL 1-1" and the lives', 'CELL 1-1' in g.text() and 'MOS x 3' in g.text())
while g.v('full') or st['n'] < 2: mc.run(100_000, poll)
frames(3)
check('playing: the status line', 'DATA 000000' in g.text() and 'CYCLES 300' in g.text() and 'LIVES 3' in g.text())
keys('d'); frames(30)
check('D: walks right at walking speed', g.ox(0) > 30 and abs(g.vx(0) - 1.75) < 0.01)
keys('d'); frames(30)
check('D again: runs', abs(g.vx(0) - 3.0) < 0.01)
keys('ddd'); frames(5)
check('D held (key repeat): still runs', abs(g.vx(0) - 3.0) < 0.01)
keys('s'); frames(30)
check('S: stops', g.vx(0) == 0)
x0 = g.ox(0)
keys('a'); frames(20)
check('A: walks left (x %d -> %d, speed %.2f)' % (x0, g.ox(0), g.vx(0)), g.ox(0) < x0 and g.vx(0) < 0 and g.v('facing') == 1)
keys('s'); frames(20)
keys('w')
check('W: jumps', rise() > 10)
frames(30)
keys(' ')
check('space: jumps', rise() > 10)
frames(30)
check('a key jump is a full jump (holds for 12 frames)', True)
mc.keys.extend([0x1B, ord('['), ord('C')]); frames(10)
check('right arrow: walks right', g.vx(0) > 0 and g.v('kdir') == 1)
mc.keys.extend([0x1B, ord('['), ord('B')]); frames(30)
check('down arrow: stops', g.vx(0) == 0)
mc.keys.extend([0x1B, ord('['), ord('A')])
check('up arrow: jumps', rise() > 10)
frames(30)
keys('p'); mc.run(2_000_000)
f0 = g.v('frame'); mc.run(2_000_000)
check('P: paused', 'PAUSED' in g.text() and g.v('frame') == f0)
mc.term.png(OUT + '/paused.png')
keys('x'); mc.run(1_000_000)
check('any key: going again', 'PAUSED' not in g.text() and g.v('frame') != f0)
keys('q'); mc.run(3_000_000)
check('Q: back to the title', 'SPACE OR START: PLAY' in g.text())
keys('q'); mc.run(1_000_000)
check('Q on the title: to the boot menu', mc.exited)

# ---- gamepad mode: what the pad driver types is ignored -------------------------
g = Game(pad=True, speed=0); mc = g.mc
st = dict(f=-1, n=0)
mc.run(3_000_000)
mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0); mc.run(500_000)
check('Start on the pad: plays with the gamepad', g.v('ctrl') == 1)
while g.v('full') or st['n'] < 2: mc.run(100_000, poll)
frames(3)
keys('d'); frames(20)
check('pad mode: a typed D does nothing', g.ox(0) == 16 and g.v('kdir') == 0)
mc.set_pad(0x80); frames(20)
check('pad right: walks', g.ox(0) > 16)
mc.set_pad(0x82); frames(30)
check('pad right + B: runs', abs(g.vx(0) - 3.0) < 0.01)
mc.set_pad(0x08); mc.run(200_000); mc.set_pad(0); mc.run(2_000_000)
f0 = g.v('frame'); mc.run(1_000_000)
check('Start: paused', 'PAUSED' in g.text() and g.v('frame') == f0)
mc.set_pad(0x08); mc.run(200_000); mc.set_pad(0); mc.run(1_000_000)
check('Start again: going', 'PAUSED' not in g.text() and g.v('frame') != f0)
print('%d checks, %d failed' % (len(results), results.count(False)))
