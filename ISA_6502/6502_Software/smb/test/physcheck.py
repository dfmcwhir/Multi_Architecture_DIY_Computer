# PY65=... python3 test/physcheck.py : the Python physics against the game, frame by frame
import sys, os, random
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import phys
g = Game(pad=True, speed=0); mc = g.mc
mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0); mc.run(6_000_000)
rnd = random.Random(1)
st = {'f': -1, 'n': 0, 'pred': None, 'bad': 0, 'ok': 0}
def poll(m):
    if not g.at_frame_start(m) or g.v('frame') == st['f'] or g.v('full'): return
    st['f'] = g.v('frame'); st['n'] += 1
    if st['pred'] is not None and g.v('mstate') == 0:
        s = st['pred']
        got = (g.ox(0), g.v('o_xf'), g.v('o_y'), g.v('o_yf'), g.v('o_vxl') | g.v('o_vxh') << 8, g.v('o_vyl') | g.v('o_vyh') << 8, g.v('onground'))
        exp = (s.x, s.xf, s.y, s.yf, s.vx, s.vy, s.onground)
        if got != exp and not s.hurt and not s.dead:
            st['bad'] += 1
            if st['bad'] < 6: print('frame', st['n'], 'got', got, 'model', exp)
        else: st['ok'] += 1
    # (the pad was read at the top of this frame: what was set last time)
    s, wd = phys.from_game(g)
    if g.v('mstate') == 0:
        phys.step(s, wd, st['d'], st['run'], st['A'])
        st['pred'] = s
    else:
        st['pred'] = None
    if st['n'] % 6 == 0:     # random-ish inputs, from the next frame
        st['d'] = rnd.choice([1, 1, 1, 0, -1]); st['run'] = rnd.random() < 0.5
        st['A'] = rnd.random() < 0.4
    b = (0x80 if st['d'] > 0 else 0x40 if st['d'] < 0 else 0) | (0x02 if st['run'] else 0) | (0x01 if st['A'] else 0)
    m.set_pad(b)
st['d'] = 0; st['run'] = 0; st['A'] = 0
while st['n'] < int(os.environ.get('N', '600')) and not mc.exited:
    mc.run(100_000, poll)
    if 'GAME  OVER' in g.text(): break
print('frames', st['n'], 'matched', st['ok'], 'differed', st['bad'], 'lives', g.v('lives'), 'x', g.ox(0))
