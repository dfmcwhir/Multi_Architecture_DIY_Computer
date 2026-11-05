# PY65=... python3 test/fit.py : measure the 6502's work per frame against the
# counters the game keeps, for the timing model in pace (smb.s)
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import phys, bot
import numpy as np
g = Game(pad=True, speed=0); mc = g.mc; mpu = mc.mpu
mc.run(3_000_000); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
PACE, TOP = syms['pace'], syms['game_loop']
rows = []
st = dict(f=-1, q=[], cur=(0, 0, 0), t0=None, b0=0)
def poll(m):
    if not g.at_frame_start(m) or g.v('frame') == st['f']: return
    st['f'] = g.v('frame')
    if g.v('mstate') != 0 or g.v('full'): m.set_pad(0); st['q'] = []; st['cur'] = (0, 0, 0); return
    if not st['q']:
        s, wd = phys.from_game(g)
        d, r, ap = bot.plan(s, wd, st['cur']); st['q'] = [(d, r, a) for a in ap]
    st['cur'] = st['q'].pop(0); m.set_pad(bot.pad_bits(*st['cur']))
N = int(os.environ.get('N', '700'))
def run_until(n):
    """Machine.run, also watching for the top of the frame loop and pace"""
    m = mc
    while len(rows) < n and not m.exited:
        pc = mpu.pc
        if pc == TOP: st['t0'] = mpu.processorCycles; st['b0'] = m.term.nbytes
        elif pc == PACE and st['t0'] is not None:
            nb = m.term.nbytes - st['b0']
            cyc = mpu.processorCycles - st['t0'] - nb * 87 * sim.CPU_MHZ
            rows.append((cyc, g.w('nbytes'), g.w('ncmp'), g.v('ncells'), g.v('nrows_seen'), g.v('scrolled')))
            st['t0'] = None
            if len(rows) % 100 == 0 and 'GAME  OVER' in g.text(): return
        if pc == sim.CHROUT:
            m.term.put(mpu.a); mpu.processorCycles += 87 * sim.CPU_MHZ; m.rts()
        elif pc == sim.CHRIN:
            poll(m)
            if m.keys: mpu.a = m.keys.pop(0); mpu.p |= mpu.CARRY
            else: mpu.p &= ~mpu.CARRY
            m.rts()
        elif pc == sim.PADSTATE:
            mpu.a = m.pad; m.rts()
        elif pc == sim.MENU:
            m.exited = True
        else:
            mpu.step()
run_until(N)
A = np.array([[1, r[1], r[2], r[3], r[5]] for r in rows], float)
y = np.array([r[0] for r in rows], float)
k, *_ = np.linalg.lstsq(A, y, rcond=None)
pred = A @ k
print('frames', len(rows), 'cycles: mean %.0f max %.0f' % (y.mean(), y.max()))
print('cycles = %.0f + %.1f * bytes + %.1f * compared + %.1f * sprite cells + %.0f * scrolled' % tuple(k))
print('error: mean %.0f, worst %.0f' % (np.abs(pred - y).mean(), np.abs(pred - y).max()))
for r in sorted(rows)[-5:]: print(r)

def est(b, c, cells, scr):
    """the integer model in pace: ms of 6502 work at 1 MHz (the terminal scrolling)"""
    b8 = b >> 3
    return (b8 >> 1) + (b8 >> 2) + (c >> 5) + (cells >> 1) + (5 if scr else 0) + 6
e = np.array([est(r[1], r[2], r[3], r[5]) * 1000 for r in rows], float)
print('means: bytes %.0f compared %.0f cells %.1f scrolled %.2f' % tuple(np.array([r[1:4] + (r[5],) for r in rows], float).mean(0)))
print('integer model: mean error %.0f cycles (%.0f%% of the mean), worst %.0f, average bias %.0f' % (
    np.abs(e - y).mean(), 100 * np.abs(e - y).mean() / y.mean(), np.abs(e - y).max(), (e - y).mean()))
