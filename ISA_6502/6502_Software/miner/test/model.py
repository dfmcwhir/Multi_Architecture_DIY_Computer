"""MINER MOS: a whole room as miner.s plays it, a frame at a time (phys.py
for Willy and the guardians), for the planner and the tests."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import phys, rooms
from check_rooms import parse

AIR_RATE = 12
LEFT, RIGHT, JUMP = 0x40, 0x80, 0x01         # gamepad bits for an input


class Room:
    def __init__(self, n):
        r = rooms.ROOMS[n]
        self.n = n
        self.map, start, portal = parse(r)
        self.w = phys.Willy(*start)
        self.px, self.py = portal[0] * 4, portal[1] * 4
        self.guards = [phys.Guard(k, ax, c * 4, rr * 4, lo * 4, hi * 4, slow, 1) for (k, ax, c, rr, lo, hi, slow) in r['guards']]
        self.keys = sum(1 for t in self.map if t == phys.KEY)
        self.air, self.air_t, self.t = r['air'], 0, 0
        self.done = False

    def copy(self):
        o = Room.__new__(Room)
        o.n, o.map, o.w, o.px, o.py = self.n, self.map[:], self.w.copy(), self.px, self.py
        o.guards = [g.copy() for g in self.guards]
        o.keys, o.air, o.air_t, o.t, o.done = self.keys, self.air, self.air_t, self.t, self.done
        return o

    def frame(self, d, j, changed=None):
        """one frame, in the game's order: the guardians, Willy, what he
        touches, the guardians again (hits), the air, the portal"""
        for g in self.guards: g.step()
        w = self.w
        phys.step(self.map, w, d, j, changed)
        for c, r in phys.touches(self.map, w):
            t = phys.tile(self.map, c, r)
            if t == phys.HAZARD: w.dead = True
            elif t == phys.KEY:
                self.map[r * phys.COLS + c] = phys.EMPTY
                self.keys -= 1
                if changed is not None: changed.append((c, r))
        if any(phys.hits(w, g) for g in self.guards): w.dead = True
        self.air_t += 1
        if self.air_t >= AIR_RATE:
            self.air_t = 0
            if self.air == 0: w.dead = True
            else:
                self.air -= 1
                if self.air == 0: w.dead = True
        self.t += 1
        if not w.dead and self.keys == 0 and w.x + 5 >= self.px and w.x <= self.px + 7 and w.y + 7 >= self.py and w.y <= self.py + 7:
            self.done = True


def pad_of(d, j):
    return (LEFT if d < 0 else RIGHT if d > 0 else 0) | (JUMP if j else 0)
