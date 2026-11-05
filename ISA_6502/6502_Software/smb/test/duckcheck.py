# PY65=... python3 test/duckcheck.py : ducking while running (small and big)
# slides on; A while ducked jumps, still ducked; letting go stands up
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
R, B, DOWN, A = 0x80, 0x02, 0x20, 0x01
fails = []
def check(c, m):
    print(('ok    ' if c else 'FAIL  ') + m)
    if not c: fails.append(m)

def frames(mc, g, n):
    for i in range(n):
        f = g.v('frame')
        while g.v('frame') == f:
            mc.run(2_000)

def samples(mc, g, n, what):
    out = []
    for i in range(n):
        frames(mc, g, 2)
        out.append(what())
    return out

for big in (0, 1):
    name = 'big' if big else 'small'
    g = Game(pad=True, speed=0); mc = g.mc
    mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0); mc.run(6_000_000)
    if big:
        g.mem[syms['big']] = 1
        g.mem[syms['o_y']] = (g.v('o_y') - 8) & 255
    mc.set_pad(R | B); frames(mc, g, 28)              # running right, on open ground
    x0 = g.ox(0)
    mc.set_pad(DOWN)
    s = samples(mc, g, 12, lambda: (g.ox(0), g.v('duck')))
    check(all(d == 1 for x, d in s) and s[-1][0] > x0 + 15 and all(b[0] >= a[0] for a, b in zip(s, s[1:])),
          '%s: running, then down: ducked, sliding on (x %d -> %d)' % (name, x0, s[-1][0]))
    y0 = g.v('o_y')
    mc.set_pad(DOWN | A)
    s = samples(mc, g, 24, lambda: (g.v('o_y'), g.v('duck'), g.v('onground')))
    check(min(y for y, d, o in s) < y0 - 20 and all(d == 1 for y, d, o in s) and s[-1][2] == 1,
          '%s: A while ducked: a jump (up %d), ducked all the way, landed' % (name, y0 - min(y for y, d, o in s)))
    mc.set_pad(0); frames(mc, g, 6)
    check(g.v('duck') == 0 and g.v('mh') == (16 if big else 8), '%s: down let go: standing again' % name)

print('\n%d failed' % len(fails) if fails else '\nall passed')
