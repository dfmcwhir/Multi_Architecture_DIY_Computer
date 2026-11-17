"""MINER MOS: the rules of movement, exactly as miner.s does them, for the
room checks in gen.py and the tests.  Positions are the sprite layer's
pixels; a tile is 4 x 4 pixels; a room is 40 x 20 tiles (160 x 80 pixels).

Tiles: 0 empty, 1 floor, 2 wall, 3 conveyor left, 4 conveyor right,
5-7 crumbling floor (stages), 8 hazard, 9 key."""

COLS, ROWS = 40, 20
EMPTY, FLOOR, WALL, CONV_L, CONV_R, CR0, CR1, CR2, HAZARD, KEY = range(10)
SOLID_TOP = {FLOOR, WALL, CONV_L, CONV_R, CR0, CR1, CR2}
W, H = 6, 8                     # Willy's box
JTAB = [-3, -2, -2, -2, -1, -1, -1, 0, 0, 1, 1, 1, 2, 2, 2, 3]   # up 12 pixels (3 tiles), 16 frames
FALL_MAX = 24                   # a fall (from the highest point) longer than this kills
CRUMBLE_T = 6                   # frames standing on a crumbling floor per stage
STAND, JUMP, FALL = 0, 1, 2


class Willy:
    __slots__ = ('x', 'y', 'mode', 'jt', 'jdx', 'ytop', 'face', 'anim', 'crt', 'dead')

    def __init__(self, x, y):
        self.x, self.y = x, y
        self.mode, self.jt, self.jdx, self.ytop = STAND, 0, 0, y
        self.face, self.anim, self.crt, self.dead = 1, 0, 0, False

    def key(self):
        """what decides his future (standing: not the last jump; falling: only
        where he fell from)"""
        if self.mode == STAND: return (self.x, self.y, 0, 0, 0, 0, self.crt)
        if self.mode == FALL: return (self.x, self.y, FALL, 0, 0, self.ytop, self.crt)
        return (self.x, self.y, self.mode, self.jt, self.jdx, self.ytop, self.crt)

    def copy(self):
        w = Willy(0, 0)
        for k in self.__slots__: setattr(w, k, getattr(self, k))
        return w


def tile(m, c, r):
    if r < 0 or r >= ROWS or c < 0 or c >= COLS: return EMPTY
    return m[r * COLS + c]


def support(m, x, y):
    r = (y + H) >> 2
    if r >= ROWS: return False
    return any(tile(m, c, r) in SOLID_TOP for c in range(x >> 2, ((x + W - 1) >> 2) + 1))


def conveyor(m, x, y):
    r = (y + H) >> 2
    for c in range(x >> 2, ((x + W - 1) >> 2) + 1):
        t = tile(m, c, r)
        if t == CONV_L: return -1
        if t == CONV_R: return 1
    return 0


def wall_in_rows(m, c, y):
    return any(tile(m, c, r) == WALL for r in range(y >> 2, ((y + H - 1) >> 2) + 1))


def try_move_x(m, w, d):
    nx = w.x + d
    if nx < 0 or nx + W - 1 > COLS * 4 - 1: return False
    c = (nx + W - 1) >> 2 if d > 0 else nx >> 2
    if wall_in_rows(m, c, w.y): return False
    w.x = nx
    return True


def head_blocked(m, x, ny):
    r = ny >> 2
    if ny < 0: return True
    return any(tile(m, c, r) == WALL for c in range(x >> 2, ((x + W - 1) >> 2) + 1))


def land(w):
    w.mode = STAND
    if w.y - w.ytop > FALL_MAX: w.dead = True


def step(m, w, d, jump, changed=None):
    """one frame of Willy: d = -1 / 0 / 1 (left, none, right), jump pressed.
    m (the room's tiles) changes when a crumbling floor goes; changed gets
    the tiles that did."""
    if w.mode == STAND:
        if not support(m, w.x, w.y):
            w.mode, w.ytop = FALL, w.y
            return
        conv = conveyor(m, w.x, w.y)
        if conv: d = conv
        if jump:
            w.mode, w.jt, w.jdx, w.ytop = JUMP, 0, d, w.y
            if d: w.face = d
        else:
            if d:
                w.face = d
                if try_move_x(m, w, d): w.anim = (w.anim + 1) & 7
            # crumbling floor under the feet
            r = (w.y + H) >> 2
            under = [c for c in range(w.x >> 2, ((w.x + W - 1) >> 2) + 1) if tile(m, c, r) in (CR0, CR1, CR2)]
            if under:
                w.crt += 1
                if w.crt >= CRUMBLE_T:
                    w.crt = 0
                    for c in under:
                        t = m[r * COLS + c]
                        m[r * COLS + c] = EMPTY if t == CR2 else t + 1
                        if changed is not None: changed.append((c, r))
            return
    if w.mode == JUMP:
        dy = JTAB[w.jt]; w.jt += 1
        if w.jdx and not try_move_x(m, w, w.jdx): w.jdx = 0
        if dy < 0:
            for i in range(-dy):
                if head_blocked(m, w.x, w.y - 1):
                    w.mode = FALL
                    return
                w.y -= 1; w.ytop = w.y
        elif dy > 0:
            for i in range(dy):
                if (w.y + H) & 3 == 0 and support(m, w.x, w.y):
                    land(w); return
                w.y += 1
        if w.jt == len(JTAB): w.mode = FALL
        return
    if w.mode == FALL:
        for i in range(2):
            if (w.y + H) & 3 == 0 and support(m, w.x, w.y):
                land(w); return
            w.y += 1
        if w.y + H > ROWS * 4: w.dead = True


def touches(m, w):
    """the tiles Willy's box is on"""
    return [(c, r) for r in range(w.y >> 2, ((w.y + H - 1) >> 2) + 1) for c in range(w.x >> 2, ((w.x + W - 1) >> 2) + 1)]


# ---- guardians ---------------------------------------------------------------------
class Guard:
    """g = (type, axis 'h' / 'v', x, y, lo, hi, slow, dir): it moves 1 pixel a
    frame (every second frame if slow) between lo and hi on its axis"""
    __slots__ = ('kind', 'axis', 'x', 'y', 'lo', 'hi', 'slow', 'dir', 't')

    def __init__(self, kind, axis, x, y, lo, hi, slow, d):
        self.kind, self.axis, self.x, self.y, self.lo, self.hi, self.slow, self.dir, self.t = kind, axis, x, y, lo, hi, slow, d, 0

    def copy(self):
        g = Guard(0, 'h', 0, 0, 0, 0, 0, 1)
        for k in self.__slots__: setattr(g, k, getattr(self, k))
        return g

    def step(self):
        self.t ^= 1
        if self.slow and self.t: return
        p = self.x if self.axis == 'h' else self.y
        if self.dir > 0 and p >= self.hi: self.dir = -1
        elif self.dir < 0 and p <= self.lo: self.dir = 1
        p += self.dir
        if self.axis == 'h': self.x = p
        else: self.y = p


def hits(w, g):
    """Willy's box against a guardian's (8 x 8, 1 pixel in from each side)"""
    return w.x + W - 1 >= g.x + 1 and w.x <= g.x + 6 and w.y + H - 1 >= g.y + 1 and w.y <= g.y + 6
