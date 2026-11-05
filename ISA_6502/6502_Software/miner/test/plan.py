"""MINER MOS: find a way through each room, guardians and all: a beam search
over frames with the exact model (model.py), steered by the distance to the
nearest key left (or the portal) in Willy's moves without the guardians.
Writes test/plans/roomN.txt (one input a line: -1 / 0 / 1 and jump 0 / 1).
    python3 test/plan.py [room numbers, from 1]"""
import os, sys, time
from collections import deque
sys.path.insert(0, os.path.dirname(__file__))
import model, phys, rooms
from model import Room

BEAM = int(os.environ.get('BEAM', '1500'))
HERE = os.path.dirname(os.path.abspath(__file__))
INPUTS_STAND = [(d, j) for j in (0, 1) for d in (-1, 0, 1)]

def gkey(w):
    return w.key()[:6]

def graph(r):
    """Willy's moves in the room without the guardians (crumbling floors as
    floors): the states, and the edges backwards"""
    m = [phys.FLOOR if t in (phys.CR0, phys.CR1, phys.CR2) else t for t in r.map]
    w0 = r.w.copy()
    seen = {gkey(w0)}
    back = {}
    touch = {}
    q = deque([w0])
    while q:
        w = q.popleft()
        k = gkey(w)
        for d, j in (INPUTS_STAND if w.mode == phys.STAND else [(0, 0)]):
            w2 = w.copy()
            phys.step(m, w2, d, j)
            if w2.dead: continue
            ts = phys.touches(m, w2)
            if any(phys.tile(m, c, rr) == phys.HAZARD for c, rr in ts): continue
            k2 = gkey(w2)
            back.setdefault(k2, set()).add(k)
            if k2 not in seen:
                seen.add(k2); q.append(w2)
                touch[k2] = (ts, w2.x, w2.y)
    touch[gkey(w0)] = (phys.touches(m, w0), w0.x, w0.y)
    return seen, back, touch

def dist_to(back, goal_nodes):
    dist = {k: 0 for k in goal_nodes}
    q = deque(goal_nodes)
    while q:
        k = q.popleft()
        for p in back.get(k, ()):
            if p not in dist:
                dist[p] = dist[k] + 1; q.append(p)
    return dist

def plan(n):
    r0 = Room(n)
    t0 = time.time()
    seen, back, touch = graph(r0)
    keys = [(i % phys.COLS, i // phys.COLS) for i, t in enumerate(r0.map) if t == phys.KEY]
    kdist = {}
    for kt in keys:
        kdist[kt] = dist_to(back, [k for k in seen if kt in touch[k][0]])
    pdist = dist_to(back, [k for k in seen if touch[k][1] + 5 >= r0.px and touch[k][1] <= r0.px + 7 and touch[k][2] + 7 >= r0.py and touch[k][2] <= r0.py + 7])
    crum = [i for i, t in enumerate(r0.map) if t in (phys.CR0, phys.CR1, phys.CR2)]
    BIG = 10 ** 6

    def score(r):
        k = gkey(r.w)
        left = [kt for kt in keys if r.map[kt[1] * phys.COLS + kt[0]] == phys.KEY]
        if left:
            h = min(kdist[kt].get(k, BIG) for kt in left)
        else:
            h = pdist.get(k, BIG)
        return (len(left), h)

    nodes = [(None, None)]                  # (parent index, input)
    layer = [(r0, 0)]
    for t in range(r0.air * model.AIR_RATE + 5):
        nxt = {}
        for r, ni in layer:
            for d, j in (INPUTS_STAND if r.w.mode == phys.STAND else [(0, 0)]):
                r2 = r.copy()
                r2.frame(d, j)
                if r2.w.dead: continue
                nodes.append((ni, (d, j)))
                idx = len(nodes) - 1
                if r2.done:
                    seq = []
                    while nodes[idx][0] is not None:
                        seq.append(nodes[idx][1]); idx = nodes[idx][0]
                    seq.reverse()
                    print('room %d %-22s solved in %d frames (air left %d), %.0f s' % (n + 1, rooms.ROOMS[n]['name'], len(seq), r2.air, time.time() - t0))
                    return seq
                key = (r2.w.key(), tuple(r2.map[i] for i in crum), r2.keys)
                if key not in nxt:
                    nxt[key] = (r2, idx)
        if not nxt:
            break
        cand = sorted(nxt.values(), key=lambda e: score(e[0]))
        layer = cand[:BEAM]
        if os.environ.get('DEBUG') and t % 50 == 0:
            b = layer[0][0]
            print('  t %d: %d states, best %s at %d,%d mode %d key %s ytop %d left %s' % (t, len(nxt), score(b), b.w.x, b.w.y, b.w.mode, b.w.key(), b.w.ytop, [kt for kt in keys if b.map[kt[1] * phys.COLS + kt[0]] == phys.KEY]))
            if t == 300:
                from collections import Counter
                print('   ', Counter((e[0].w.x // 8, e[0].w.y // 8, e[0].w.mode) for e in layer).most_common(8))
    print('room %d %-22s NOT SOLVED (%.0f s)' % (n + 1, rooms.ROOMS[n]['name'], time.time() - t0))
    return None

if __name__ == '__main__':
    want = [int(a) for a in sys.argv[1:]] or range(1, len(rooms.ROOMS) + 1)
    os.makedirs(os.path.join(HERE, 'plans'), exist_ok=True)
    bad = 0
    for n in want:
        seq = plan(n - 1)
        if seq is None: bad += 1; continue
        with open(os.path.join(HERE, 'plans', 'room%d.txt' % n), 'w') as f:
            for d, j in seq: f.write('%d %d\n' % (d, j))
    sys.exit(1 if bad else 0)
