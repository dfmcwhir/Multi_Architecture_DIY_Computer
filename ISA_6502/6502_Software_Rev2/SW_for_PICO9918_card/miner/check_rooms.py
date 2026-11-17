"""Check the rooms: sizes, and that every key and the portal can be reached
(a search over Willy's moves with phys.py; guardians and crumbling left out,
crumbling floors count as floors).  python3 check_rooms.py [room numbers]"""
import sys
from collections import deque
import phys, rooms

CH = {'.': 0, '=': 1, '#': 2, '<': 3, '>': 4, '~': 5, '^': 8, 'k': 9, 'P': 0, 'W': 0}

def parse(r):
    rows = r['rows']
    assert len(rows) == 19, (r['name'], len(rows))
    m = [phys.WALL] * phys.COLS          # row 0
    start = portal = None
    for i, s in enumerate(rows):
        assert len(s) == 38, (r['name'], i + 1, len(s), s)
        m += [phys.WALL] + [CH[c] for c in s] + [phys.WALL]
        for j, c in enumerate(s):
            if c == 'W': start = ((j + 1) * 4, (i + 1) * 4)
            if c == 'P': portal = (j + 1, i + 1)
    assert start and portal, r['name']
    return m, start, portal

def search(m, start):
    m2 = [phys.FLOOR if t in (phys.CR0, phys.CR1, phys.CR2) else t for t in m]
    w0 = phys.Willy(*start)
    seen = {w0.key(): None}
    q = deque([w0])
    touched = set()
    while q:
        w = q.popleft()
        for d in (-1, 0, 1):
            for j in ((0, 1) if w.mode == phys.STAND else (0,)):
                w2 = w.copy()
                phys.step(m2, w2, d, j)
                if w2.dead: continue
                ts = phys.touches(m2, w2)
                if any(phys.tile(m2, c, r) == phys.HAZARD for c, r in ts): continue
                touched.update(ts)
                k = w2.key()
                if k not in seen:
                    seen[k] = (w.key(), d, j)
                    q.append(w2)
    return touched, len(seen)

def start_safe(n, frames=250):
    """None if Willy can stand still at the start for this many frames (10 s),
    guardians and air and all; else the frame he dies"""
    sys.path.insert(0, 'test')
    from model import Room
    r = Room(n - 1)
    for t in range(frames):
        r.frame(0, 0)
        if r.w.dead: return t
    return None

def main():
    want = [int(a) for a in sys.argv[1:]] or range(1, len(rooms.ROOMS) + 1)
    bad = 0
    for n in want:
        r = rooms.ROOMS[n - 1]
        m, start, portal = parse(r)
        touched, ns = search(m, start)
        keys = [(i % phys.COLS, i // phys.COLS) for i, t in enumerate(m) if t == phys.KEY]
        miss = [k for k in keys if k not in touched]
        pc, pr = portal
        port = any((c, rr) in touched for c in (pc, pc + 1) for rr in (pr, pr + 1))
        safe = start_safe(n)
        print('%d %-22s states %6d keys %d, not reached %s, portal %s, standing still at the start %s' % (
            n, r['name'], ns, len(keys), miss, 'ok' if port else 'NOT REACHED', 'safe' if safe is None else 'KILLED AT FRAME %d' % safe))
        bad += len(miss) + (not port) + (safe is not None)
    return bad

if __name__ == '__main__':
    sys.exit(1 if main() else 0)

def show(n):
    """the room with the tiles Willy can touch marked ':'"""
    r = rooms.ROOMS[n - 1]
    m, start, portal = parse(r)
    touched, ns = search(m, start)
    inv = {v: k for k, v in CH.items() if k not in 'PW'}
    for rr in range(phys.ROWS):
        line = ''
        for c in range(phys.COLS):
            t = m[rr * phys.COLS + c]
            ch = inv[t]
            if t == 0 and (c, rr) in touched: ch = ':'
            if (c, rr) == portal: ch = 'P'
            line += ch
        print('%2d %s' % (rr, line))

def traps(n):
    """standing places Willy can get to but can't get from to the portal
    (keys aside): (column, row) of his feet"""
    sys.path.insert(0, 'test')
    import plan
    from model import Room
    r = Room(n - 1)
    seen, back, touch = plan.graph(r)
    pd = plan.dist_to(back, [k for k in seen if touch[k][1] + 5 >= r.px and touch[k][1] <= r.px + 7 and touch[k][2] + 7 >= r.py and touch[k][2] <= r.py + 7])
    bad = sorted({((k[0] + 3) >> 2, (k[1] + 8) >> 2) for k in seen if k[2] == phys.STAND and k not in pd})
    return bad

def show_traps(n):
    r = rooms.ROOMS[n - 1]
    m, start, portal = parse(r)
    t = set(traps(n))
    inv = {v: k for k, v in CH.items() if k not in 'PW'}
    for rr in range(phys.ROWS):
        line = ''
        for c in range(phys.COLS):
            ch = inv[m[rr * phys.COLS + c]]
            if (c, rr) == portal: ch = 'P'
            if (c, rr) in t: ch = 'T'
            line += ch
        print('%2d %s' % (rr, line))
