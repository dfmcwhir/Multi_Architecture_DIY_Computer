"""A Python copy of MOS's physics (same fixed point arithmetic as smb.s), with
rough enemies, for the test bot to plan with.  The emulator is the real
thing: the bot plans from the game's own state every few frames."""
import os, re, copy
sys_dir = os.path.dirname(__file__)
import gen

NOSCROLL = bool(os.environ.get('NOSCROLL'))
C = {m.group(1): int(m.group(2), 16) for m in re.finditer(r'^(\w+)\s*=\s*\$([0-9A-F]+)', open(os.path.join(sys_dir, '..', 'smb.s')).read(), re.M)}
SOLID = [t[2] for t in gen.TILES]
T = {t[0]: i for i, t in enumerate(gen.TILES)}

def s16(v):
    v &= 0xFFFF
    return v - 65536 if v >= 32768 else v

class World:
    """the map (tile numbers), width, scroll limit"""
    def __init__(self, grid, w, max_sc, water=False):
        self.grid, self.w, self.max_sc, self.water = grid, w, max_sc, water
    def solid_at(self, ptx, pty):
        pty &= 255
        if pty >= 88: return False, 0, None, None
        tc = (ptx & 0xFFFF) >> 3
        if tc >= 256 or tc >= self.w: return True, T['HARD'], tc, pty >> 3
        t = self.grid[pty >> 3][tc]
        return bool(SOLID[t]), t, tc, pty >> 3

class State:
    __slots__ = ('x', 'xf', 'y', 'yf', 'vx', 'vy', 'onground', 'big', 'jump_buf', 'scroll', 'en', 'dead', 'done', 'grid', 'prevA', 'hurt')
    def copy(self):
        s = State()
        for k in State.__slots__: setattr(s, k, getattr(self, k))
        s.en = [list(e) for e in self.en]
        return s
    @property
    def mh(self): return 16 if self.big else 8
    @property
    def ys(self): return self.y - 256 if self.y >= 128 else self.y

def tile_at(wd, x, y, a, dy):
    return wd.solid_at((x + a) & 0xFFFF, (y + dy) & 255)

def control(s, d, run, onground, water=False):
    vmax = C['WATER_MAX'] if water else C['RUN_MAX'] if run else C['WALK_MAX']
    vx = s16(s.vx)
    if d == 0:
        if onground and vx != 0:
            sg = 1 if vx > 0 else -1
            m = abs(vx) - C['DECEL']
            vx = sg * max(m, 0)
        s.vx = vx & 0xFFFF
        return
    v = vx * d
    if v < 0:
        v += C['SKID']
    elif v < vmax:
        v += C['ACCEL']
        if v >= vmax: v = vmax
    else:
        if onground:
            v -= C['DECEL']
            if v < vmax: v = vmax
    s.vx = (v * d) & 0xFFFF

def jump(s, hold):
    if s.jump_buf:
        s.jump_buf -= 1
        if s.onground:
            s.jump_buf = 0; s.onground = 0
            t = abs(s16(s.vx)) >> 3
            s.vy = (-(C['JUMP_V'] + t)) & 0xFFFF
            return
    vy = s16(s.vy)
    g = C['GRAV_HOLD'] if (vy < 0 and hold) else C['GRAV']
    v = (s.vy + g) & 0xFFFF
    if v < 0x8000 and (v >> 8) >= (C['MAX_FALL'] >> 8): v = C['MAX_FALL']
    s.vy = v

def swim(s):
    if s.jump_buf:
        s.jump_buf = 0; s.onground = 0
        s.vy = (-C['SWIM_V']) & 0xFFFF
        return
    v = (s.vy + C['GRAV_W']) & 0xFFFF
    if v < 0x8000 and (v >> 8) >= (C['MAX_FALL_W'] >> 8): v = C['MAX_FALL_W']
    s.vy = v

def move(s, wd):
    X = ((s.x << 8) | s.xf) + s16(s.vx)
    X &= 0xFFFFFF
    s.x, s.xf = X >> 8, X & 255
    sc2 = s.scroll * 2
    if s.x < sc2:
        s.x, s.xf, s.vx = sc2, 0, 0
    vx = s16(s.vx)
    mh = s.mh
    def side(a):
        rows = [1] + ([8] if s.big else []) + [mh - 2]
        for dy in rows:
            so, t, tc, tr = tile_at(wd, s.x, s.y, a, dy)
            if so: return (s.x + a) & 0xFFFF
        return None
    if vx < 0:
        p = side(1)
        if p is not None: s.x, s.xf, s.vx = p | 7, 0, 0
    elif vx > 0:
        p = side(6)
        if p is not None: s.x, s.xf, s.vx = ((p & 0xFFF8) - 7) & 0xFFFF, 0, 0
    Y = ((s.y << 8) | s.yf) + s.vy
    Y &= 0xFFFF
    s.y, s.yf = Y >> 8, Y & 255
    s.onground = 0
    if s16(s.vy) >= 0:
        for a in (1, 6):
            so, t, tc, tr = tile_at(wd, s.x, s.y, a, mh - 1)
            if so:
                s.y, s.yf, s.vy, s.onground = (tr * 8 - mh) & 255, 0, 0, 1
                return
    else:
        for a in (3, 5, 2):
            so, t, tc, tr = tile_at(wd, s.x, s.y, a, 0)
            if so or t == T['HIDDEN']:
                s.y, s.yf, s.vy = (tr * 8 + 8) & 255, 0, 0
                bump(s, wd, t, tc, tr)
                return

def bump(s, wd, t, tc, tr):
    pass        # (blocks change, but stay solid; a big MOS breaks bricks: the plan doesn't count on it)

def walk_obj(e, wd):
    k, x, xf, y, yf, vx, vy = e
    X = ((x << 8) | xf) + s16(vx); X &= 0xFFFFFF
    nx, nxf = X >> 8, X & 255
    sv = s16(vx)
    if sv != 0:
        so, *_ = tile_at(wd, nx, y, 7 if sv > 0 else 0, 4)
        if not so and k == 4 and vy == 0:          # an OR gate: not over an edge
            so = not tile_at(wd, nx, y, 7 if sv > 0 else 0, 8)[0]
        if so: nx, nxf, vx = x, xf, (-sv) & 0xFFFF
    x, xf = nx, nxf
    v = (vy + C['OBJ_GRAV']) & 0xFFFF
    if (v >> 8) >= (C['MAX_FALL'] >> 8) and v < 0x8000: v = C['MAX_FALL']
    vy = v
    Y = (((y << 8) | yf) + vy) & 0xFFFF
    y, yf = Y >> 8, Y & 255
    for a in (1, 6):
        so, t, tc, tr = tile_at(wd, x, y, a, 7)
        if so:
            y, yf, vy = (tr * 8 - 8) & 255, 0, 0
            break
    e[:] = [k, x, xf, y, yf, vx, vy]

def step(s, wd, d, run, A):
    """one frame with the pad: direction d (-1/0/1), B (run), A (jump button)"""
    if s.dead or s.done: return
    press = A and not s.prevA
    s.prevA = A
    if press: s.jump_buf = 4
    control(s, d, run, s.onground, wd.water)
    if wd.water: swim(s)
    else: jump(s, A)
    move(s, wd)
    if wd.water and (s.y < 4 or s.y >= 0xC0): s.y, s.vy = 4, 0
    ys = s.ys
    if 0 <= ys and ys >= 96: s.dead = True; return
    mh = s.mh
    for a, dy in ((6, 2), (6, mh - 2)):
        so, t, tc, tr = tile_at(wd, s.x, s.y, a, dy)
        if t in (T['POLE'], T['POLETOP'], T['RESET']): s.done = True; return
    # enemies
    for e in s.en:
        if e[0] in (2, 4, 5, 6, 8): walk_obj(e, wd)
        elif e[0] == 12: e[1] = (e[1] + (s16(e[5]) >> 8)) & 0xFFFF      # KIL's fire (roughly)
    for e in s.en:
        k = e[0]
        if k == 11:                                     # KIL: keep clear
            dx = s16(e[1] - s.x); dy = (e[3] - s.y + 128) % 256 - 128
            if -12 <= dx <= 4 and -15 <= dy <= mh - 3:
                s.hurt = True
                if s.big: s.big = 0; s.y = (s.y + 8) & 255
                else: s.dead = True; return
            continue
        if k not in (2, 4, 5, 6, 9, 12): continue
        dx = s16(e[1] - s.x)
        if not -5 <= dx <= 5: continue
        dy = (e[3] - s.y + 128) % 256 - 128
        if not (-7 <= dy <= mh - 2): continue
        if k in (6, 9):
            e[0] = 0
            if not s.big: s.big = 1; s.y = (s.y - 8) & 255
            continue
        if k == 12:
            s.hurt = True
            if s.big: s.big = 0; s.y = (s.y + 8) & 255
            else: s.dead = True; return
            continue
        vy = s16(s.vy)
        if k == 5 and s16(e[5]) == 0:
            e[5] = C['SHELL_V'] if dx >= 0 else (-C['SHELL_V']) & 0xFFFF
            continue
        if vy > 0 and 0 <= (s.y + mh - e[3] - 1) & 255 < 7:
            e[0] = 3 if k == 2 else 5; e[5] = 0
            s.vy = (-C['STOMP_V']) & 0xFFFF
            continue
        s.hurt = True
        if s.big: s.big = 0; s.y = (s.y + 8) & 255
        else: s.dead = True; return
    # camera
    if s.x >= 64:
        t = ((s.x - 64) >> 1) & (~1 if NOSCROLL else ~0)
        if t > s.scroll: s.scroll = min(t, wd.max_sc)

def from_game(g):
    """the planning state from the emulator's memory"""
    s = State()
    s.x, s.xf = g.ox(0), g.v('o_xf')
    s.y, s.yf = g.v('o_y'), g.v('o_yf')
    s.vx = g.v('o_vxl') | g.v('o_vxh') << 8
    s.vy = g.v('o_vyl') | g.v('o_vyh') << 8
    s.onground, s.big, s.jump_buf = g.v('onground'), g.v('big'), g.v('jump_buf')
    s.scroll = g.w('scroll')
    s.dead = s.done = s.hurt = False
    s.prevA = bool(g.v('padold') & 1)
    s.en = []
    for i in range(1, 7):
        k = g.v('o_kind', i)
        if k: s.en.append([k, g.ox(i), g.v('o_xf', i), g.v('o_y', i), g.v('o_yf', i),
                           g.v('o_vxl', i) | g.v('o_vxh', i) << 8, g.v('o_vyl', i) | g.v('o_vyh', i) << 8])
    w = g.v('lv_w')
    s.grid = [[g.tile(c, r) for c in range(256)] for r in range(11)]
    wd = World(s.grid, w, g.w('max_sc'), bool(g.v('lv_flags') & 2))
    return s, wd
