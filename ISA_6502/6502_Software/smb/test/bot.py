"""The test bot: plans a few frames ahead with the Python physics (phys.py) by
beam search over pad inputs, from the game's own state, every 4 frames."""
import phys

DIRS = [(1, 1), (1, 0), (0, 0), (-1, 0), (-1, 1)]
APAT = [(0, 0, 0, 0), (1, 1, 1, 1), (0, 1, 1, 1), (1, 0, 0, 0)]
OPTS = [(d, r, a) for d, r in DIRS for a in APAT]

def doomed(s, wd):
    """True if none of a few simple ways on from s (running or walking either
    way, holding the jump or not, or stopping) keeps MOS alive for 40 frames"""
    if s.done: return False
    for d, r, a in ((1, 1, 1), (1, 1, 0), (1, 0, 1), (0, 0, 0), (-1, 0, 1), (-1, 1, 0)):
        t = s.copy()
        for f in range(40):
            phys.step(t, wd, d, r, a)
            if t.dead or t.done: break
        if not t.dead: return False
    return True

def score(s, wd):
    v = s.x - s.ys / 4.0          # (higher is a little better: to get over things)
    if s.done: v += 10000
    if s.hurt: v -= 400
    return v

def plan(s, wd, cur, depth=8, beam=20):
    """s: the state at the top of this frame; cur: (d, run, A) already read for
    this frame.  Returns the option (d, run, Apattern) for the next 4 frames."""
    phys.step(s, wd, *cur)
    if s.dead: return (1, 1, (0, 0, 0, 0))
    states = [(score(s, wd), s, None)]
    for k in range(depth):
        nxt = {}
        for sc, st, first in states:
            if st.done:
                key = ('done',)
                if key not in nxt or nxt[key][0] < sc: nxt[key] = (sc, st, first)
                continue
            for o in OPTS:
                d, r, ap = o
                if not st.onground and ap == (0, 1, 1, 1) and st.prevA == 0: continue
                s2 = st.copy()
                for f in range(4):
                    phys.step(s2, wd, d, r, ap[f])
                    if s2.dead or s2.done: break
                if s2.dead: continue
                sc2 = score(s2, wd)
                key = (s2.x >> 1, s2.y >> 1, phys.s16(s2.vx) >> 6, phys.s16(s2.vy) >> 7, s2.onground, s2.big, s2.prevA)
                if key not in nxt or nxt[key][0] < sc2:
                    nxt[key] = (sc2, s2, first or o)
        if not nxt: break
        states = []                     # the best that aren't doomed
        for t in sorted(nxt.values(), key=lambda t: -t[0]):
            if t[1].done or (t[1].onground and not t[1].hurt) or not doomed(t[1], wd):
                states.append(t)
                if len(states) == beam: break
        if not states: break
        if states[0][1].done: break
    for sc, st, first in states:            # the best that isn't falling into a pit
        if first is not None and (st.done or not doomed(st, wd)): return first
    return (1, 0, (0, 0, 0, 0))

def pad_bits(d, run, a):
    return (0x80 if d > 0 else 0x40 if d < 0 else 0) | (0x02 if run else 0) | (0x01 if a else 0)
