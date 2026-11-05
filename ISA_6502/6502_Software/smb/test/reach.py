# python3 test/reach.py [level ...]: can MOS get from the start to the flagpole?
# A best-first search over the pad's inputs, frame by frame, in the Python
# physics (phys.py), without enemies.  Prints the inputs it took, in short.
import sys, os, heapq, time
sys.path.insert(0, os.path.dirname(__file__)); sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import gen, phys, levels
LEVELS = [v for ws in levels.WORLDS for v in ws]

ACTS = [(1, 1, 1), (1, 1, 0), (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0), (-1, 0, 1), (-1, 0, 0), (-1, 1, 1)]
if os.environ.get('WALK'):      # walking only (the keyboard's default)
    ACTS = [a for a in ACTS if not a[1]]

def search(li, limit=400000):
    acts_all = ACTS
    v = LEVELS[li]
    w, start = v.w, v.start
    grid = [r + [0] * (256 - w) for r in v.g]
    wd = phys.World([r[:256] for r in grid], w, w * 4 - 80, v.water)
    s = phys.State()
    s.x, s.xf, s.y, s.yf, s.vx, s.vy = start[0] * 8, 0, start[1] * 8, 0, 0, 0
    s.onground, s.big, s.jump_buf, s.scroll = 1, 0, 0, 0
    s.dead = s.done = s.hurt = False; s.prevA = False; s.grid = grid; s.en = []
    phys.step(s, wd, 0, 0, 0)       # (the game's first frame: the pad not yet pressed)
    seen = set()
    n = 0
    heap = [(0, 0, n, s, None)]
    parent = {}
    best = s.x
    while heap and n < limit:
        pr, f, _, st, path = heapq.heappop(heap)
        for a in ACTS:
            t = st.copy()
            phys.step(t, wd, *a)
            if t.dead: continue
            key = (t.x, t.y, phys.s16(t.vx) >> 5, phys.s16(t.vy) >> 6, t.onground, t.prevA, t.jump_buf, t.scroll >> 3)
            if key in seen: continue
            seen.add(key)
            n += 1
            p = (a, path)
            if t.done:
                acts = []
                while p: acts.append(p[0]); p = p[1]
                return True, f + 1, acts[::-1], n
            best = max(best, t.x)
            heapq.heappush(heap, (-t.x * 4 + t.ys, f + 1, n, t, p))
    return False, best, None, n

def main():
  for li in [int(a) for a in sys.argv[1:]] or range(len(LEVELS)):
    t0 = time.time()
    ok, f, acts, n = search(li)
    name = LEVELS[li].name
    if ok: print('%s: reached the flagpole in %d frames (%d states, %.0f s)' % (name, f, n, time.time() - t0))
    else: print('%s: NOT reached; got to x = %d (column %d) (%d states)' % (name, f, f // 8, n))

if __name__ == '__main__': main()
