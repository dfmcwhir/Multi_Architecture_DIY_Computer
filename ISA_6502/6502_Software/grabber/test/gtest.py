"""Shared set-up for the GOLD GRABBER tests: the emulator, the game's labels,
and a model of the field drawn in Python from the game's own state."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import math
import sim
from sim import Machine
import gen

syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('grabber.lbl')) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('grabber.map').read()).group(1), 16)
SP = {n: i for i, n in enumerate(gen.ORDER)}
PIX = {n: {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == '#'} for n, rows in gen.SPR.items()}
K_NAMES = [None, 'GEM', 'CHEST_S', 'CHEST_L', 'ROCK_S', 'ROCK_L', 'TNT', 'GOPHER']
FW, FH = 160, 92
NITEM, NEXP = 24, 6
PIVX, PIVY = 80, 17

def line(x0, y0, x1, y1):
    """the same line as the game's rope"""
    dx, dy = abs(x1 - x0), y1 - y0; sx = 1 if x1 >= x0 else -1
    pts = []; x, y = x0, y0
    if dx >= dy:
        err = dx // 2
        for i in range(dx + 1):
            pts.append((x, y)); x += sx
            err -= dy
            if err < 0: err += dx; y += 1
    else:
        err = dy // 2
        for i in range(dy + 1):
            pts.append((x, y)); y += 1
            err -= dx
            if err < 0: err += dy; x += sx
    return pts

class Game:
    def __init__(self, pad=True, speed=None):
        self.mc = Machine('GRABBER.BIN', code_end=code_end, ctrl=1 if pad else 0, speed=speed)
        self.mem = self.mc.mpu.memory
    def v(self, n, i=0): return self.mem[syms[n] + i]
    def w(self, n): return self.v(n) | self.v(n, 1) << 8
    def n3(self, n): return self.v(n) | self.v(n, 1) << 8 | self.v(n, 2) << 16
    def text(self):
        return '\n'.join(''.join(self.mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
    def buf(self, name):
        b = syms[name]; s = set()
        for r in range(23):
            for c in range(80):
                v = self.mem[b + r * 80 + c]
                for i in range(8):
                    if v >> i & 1: s.add((c * 2 + (i & 1), r * 4 + i // 2))
        return s
    def screen(self):
        return {(x, y - 4) for y in range(4, 96) for x in range(160) if self.mc.term.pix[y][x]}
    def items(self):
        return [dict(i=i, k=self.v('it_k', i), x=self.v('it_x', i), y=self.v('it_y', i), gem=self.v('it_gem', i),
                     dir=self.v('it_dir', i), v=self.v('it_vl', i) | self.v('it_vh', i) << 8)
                for i in range(NITEM) if self.v('it_k', i)]
    def put(self, s, name, x, y):
        for dx, dy in PIX[name]:
            px, py = (x + dx) & 255, (y + dy) & 255
            if px < FW and py < FH: s.add((px, py))
    def bg_model(self, dirt):
        """what bg should hold: the platform, the miner, the dirt, the still things"""
        s = set(dirt)
        self.put(s, 'PLATFORM', 60, 14); self.put(s, 'MINER', 68, 1)
        for it in self.items():
            if it['k'] != 7: self.put(s, K_NAMES[it['k']], it['x'], it['y'])
        return s
    def fb_model(self, bg, fr):
        """fb: bg with the moving things over it (fr: the frame number it was drawn at)"""
        s = set(bg)
        st = self.v('hst')
        self.put(s, 'WINCH' + str(1 + ((fr >> 1) & 1) if st == 2 else 1), 84, 6)
        for it in self.items():
            if it['k'] == 7: self.put(s, self.gopher_pic(it, fr), it['x'], it['y'])
        for e in range(NEXP):
            t = self.v('ex_t', e)
            if t: self.put(s, 'BOOM1' if not t & 2 else 'BOOM2', self.v('ex_x', e), self.v('ex_y', e))
        hx, hy = self.v('hx'), self.v('hy')
        for p in line(PIVX, PIVY, hx, hy):
            if p[0] < FW and p[1] < FH: s.add(p)
        a = self.v('ang', 1)
        name = 'CLAW%s%d' % ('S' if self.v('carry') else '', gen.dir_claw(a))
        ox, oy = gen.CLAW_OFS[name]
        self.put(s, name, (hx + ox) & 255, (hy + oy) & 255)
        if self.v('carry'):
            cw, ch = self.v('cw'), self.v('ch')
            r = ch // 2 + 3
            m = ((r * abs(SX[a])) >> 7) & 255
            x = (hx - m if SX[a] < 0 else hx + m) - cw // 2
            y = hy + (((r * CY[a]) >> 7) & 255) - ch // 2
            self.put(s, gen.ORDER[self.v('cspr')], x & 255, y & 255)
        if st == 0 and self.v('has_laser') and self.v('tsec') >= 30:
            for p in laser(self.items(), a): self.put(s, *p) if isinstance(p[0], str) else s.add(p)
        return s
    def gopher_pic(self, it, fr):
        return 'GOPHER%s_%s%d' % ('G' if it['gem'] else '', 'L' if it['dir'] else 'R', 1 + ((fr >> 2) & 1))

SX, CY = gen.dirs()
KW = [0, 5, 9, 13, 7, 12, 8, 11]; KH = [0, 5, 7, 9, 5, 9, 10, 6]

def hook_at(ang, L):
    """the grabber's place, as calc_hook works it out: (hx, hy, at an edge)"""
    s, c = abs(SX[ang]), CY[ang]
    m = ((L * s) >> 7) & 255; edge = False
    if SX[ang] >= 0:
        if m >= 78: m, edge = 78, True
        hx = 80 + m
    else:
        if m >= 79: m, edge = 79, True
        hx = 80 - m
    hy = 17 + (((L * c) >> 7) & 255)
    if hy >= 88: hy, edge = 88, True
    return hx, hy, edge

TIPS = [(round(gen.TIP * math.sin(t)), round(gen.TIP * math.cos(t))) for t in gen.tdirs()]

def hit_at(items, tx, ty):
    """what the claw's tip at tx, ty touches (as hook_hit)"""
    for it in sorted(items, key=lambda t: -t['i']):
        k = it['k']
        d = ((tx + 2) & 255) - it['x']
        if (tx + 2) > 255 or d < 0 or d >= KW[k] + 4: continue
        u = ty - it['y']
        if u < 0 or u >= KH[k]: continue
        return it
    return None

def ray(items, ang):
    """what the grabber would hit going out at this angle: (item, length) or (None, length)"""
    L = 4 << 8
    while True:
        L += 0x300
        hx, hy, edge = hook_at(ang, L >> 8)
        if edge: return None, L >> 8
        it = hit_at(items, (hx + TIPS[ang][0]) & 255, (hy + TIPS[ang][1]) & 255)
        if it: return it, L >> 8

def laser(items, a):
    """the laser pointer's dots, and ('TARGET', x, y) where it would grab"""
    s = abs(SX[a]); c = CY[a]
    x88, y88, step, out = 14 * s, 14 * c, 0, []
    while True:
        m = x88 >> 8
        if SX[a] >= 0:
            if m >= 78: return out
            px = 80 + m
        else:
            if m >= 79: return out
            px = 80 - m
        py = 17 + (y88 >> 8)
        if py >= 88: return out
        tx, ty = (px + TIPS[a][0]) & 255, (py + TIPS[a][1]) & 255
        if hit_at(items, tx, ty):
            out.append(('TARGET', (tx - 2) & 255, (ty - 2) & 255)); return out
        if step >= 2: out.append((px, py))
        step += 1
        x88 += 6 * s; y88 += 6 * c

def render(pixels):
    """pixels -> the 23 x 80 block characters the game keeps"""
    b = bytearray(23 * 80)
    for x, y in pixels:
        b[(y >> 2) * 80 + (x >> 1)] |= 1 << ((y & 3) * 2 + (x & 1))
    return b

class Checker:
    """every frame fb against the model (bg with the moving things drawn over
    it); every few frames, and when the pit changes, bg against the model and
    the terminal against fb"""
    EVERY = 6
    def __init__(self, g):
        self.g, self.dirt, self.problems, self.n = g, None, [], 0
        self.last_items = None
    def reset(self): self.dirt = None
    def mem(self, name):
        a = syms[name]; return bytes(self.g.mem[a:a + 23 * 80])
    def check(self, tag=''):
        g = self.g
        fr = (g.v('frame') - 1) & 255
        bgm = self.mem('bg')
        items = [(it['k'], it['x'], it['y']) for it in g.items() if it['k'] != 7]
        if self.dirt is None:
            self.dirt = g.buf('bg') - g.bg_model(set())
        if items != self.last_items or self.n % self.EVERY == 0:
            self.last_items = items
            if render(g.bg_model(self.dirt)) != bgm:
                self.problems.append('%s: bg differs from the model' % tag)
        want = bytearray(bgm)
        for k, v in enumerate(render(g.fb_model(set(), fr))): want[k] |= v
        fbm = self.mem('fb')
        if fbm != bytes(want):
            bad = [k for k in range(len(want)) if want[k] != fbm[k]]
            self.problems.append('%s: fb differs in %d characters (row %d col %d) hst %d' % (tag, len(bad), bad[0] // 80, bad[0] % 80, g.v('hst')))
        if self.n % self.EVERY == 0:
            if render(g.screen()) != fbm:
                self.problems.append('%s: the screen differs from fb' % tag)
        self.n += 1

def call(g, name):
    """run the game's subroutine name (between frames), then carry on where it was"""
    mpu, m = g.mc.mpu, g.mem
    saved = (mpu.pc, mpu.a, mpu.x, mpu.y, mpu.sp, mpu.p)
    stub = 0x7F00; a = syms[name]
    m[stub:stub + 6] = [0x20, a & 255, a >> 8, 0x4C, (stub + 3) & 255, (stub + 3) >> 8]
    mpu.pc = stub
    code_end = g.mc.code_end; g.mc.code_end = 0x8000
    while mpu.pc != stub + 3:
        g.mc.run(500)
    g.mc.code_end = code_end
    mpu.pc, mpu.a, mpu.x, mpu.y, mpu.sp, mpu.p = saved

def set_items(g, items):
    """put these things in the pit: dicts of k, x, y (and v, gem, x0, x1, dir); then bg again"""
    m = g.mem
    for n in ('it_k', 'it_fuse', 'it_gem', 'it_xf', 'it_dir'):
        for i in range(NITEM): m[syms[n] + i] = 0
    for i, it in enumerate(items):
        k = it['k']
        x0 = it.get('x0', it['x']); x1 = it.get('x1', it['x'])
        vals = dict(it_k=k, it_x=it['x'], it_y=it['y'], it_bx=x0, it_bw=KW[k] + x1 - x0, it_vl=it.get('v', 0) & 255,
                    it_vh=it.get('v', 0) >> 8, it_gem=it.get('gem', 0), it_dir=it.get('dir', 0), it_x0=x0, it_x1=x1)
        for n, val in vals.items(): m[syms[n] + i] = val
    for a in range(syms['bg'], syms['bg'] + 2048): m[a] = 0
    call(g, 'draw_bg'); call(g, 'show_all')
