# PY65=... python3 test/frames.py : frame times (ms) while the bot plays, at the
# default speed.  WALK=1: walk instead of run.  CPU_MHZ=1 for a 1 MHz build.
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import phys, bot
g = Game(pad=True); mc = g.mc; mpu = mc.mpu
mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
st = dict(f=-1, q=[], cur=(0, 0, 0), c0=None, b0=0)
times = []
WALK = os.environ.get('WALK')
def poll(m):
    if not g.at_frame_start(m) or g.v('frame') == st['f']: return
    st['f'] = g.v('frame')
    c = mpu.processorCycles
    if st['c0'] is not None and g.v('mstate') == 0 and not g.v('full'):
        times.append(((c - st['c0']) / (1000 * sim.CPU_MHZ), mc.term.nbytes - st['b0']))
    st['c0'] = c; st['b0'] = mc.term.nbytes
    if g.v('mstate') != 0 or g.v('full'): m.set_pad(0); st['q'] = []; st['cur'] = (0, 0, 0); return
    if not st['q']:
        s, wd = phys.from_game(g)
        d, r, ap = bot.plan(s, wd, st['cur']); st['q'] = [(d, 0 if WALK else r, a) for a in ap]
    st['cur'] = st['q'].pop(0); m.set_pad(bot.pad_bits(*st['cur']))
while len(times) < int(os.environ.get('N', '400')) and not mc.exited:
    mc.run(200_000, poll)
    if 'GAME  OVER' in g.text(): break
t = sorted(x for x, b in times)
n = len(t)
print('%d frames at %d MHz: mean %.1f ms, median %.1f, 90%% %.1f, worst %.1f; bytes a frame %.0f' % (
    n, sim.CPU_MHZ, sum(t) / n, t[n // 2], t[n * 9 // 10], t[-1], sum(b for x, b in times) / n))
