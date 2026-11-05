# PY65=... python3 test/ghost.py : while the view scrolls, MOS must never be
# shown out of place.  At each scroll code (16) the terminal's picture,
# moved left as the code moves it, is compared with the picture at the end
# of that frame under MOS: they must match (he was drawn before the scroll).
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
g = Game(pad=True, speed=0); mc = g.mc
mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0x82)
term = mc.term
snaps = []
orig = term.scroll_side
def hook(d):
    orig(d)
    snaps.append([row[:] for row in term.pix])
term.scroll_side = hook
st = dict(f=-1, n=0, bad=0, checked=0)
def poll(m):
    if not g.at_frame_start(m) or g.v('frame') == st['f']: return
    st['f'] = g.v('frame'); st['n'] += 1
    if snaps and g.v('mstate') == 0:
        after = snaps[-1]                       # just after the last scroll code
        x = g.ox(0) - g.w('sc2'); y = g.s8('o_y') + 8   # MOS on the screen now
        h = g.v('mh')
        for yy in range(max(8, y), min(96, y + h)):
            for xx in range(max(0, x), min(156, x + 8)):
                st['checked'] += 1
                if after[yy][xx] != term.pix[yy][xx]: st['bad'] += 1
    snaps.clear()
    m.set_pad(0x82 if (st['n'] // 30) % 4 else 0x83)
while st['n'] < int(os.environ.get('N', '300')) and not mc.exited:
    mc.run(100_000, poll)
print('frames %d, pixels under MOS checked %d, out of place just after a scroll %d' % (st['n'], st['checked'], st['bad']))
