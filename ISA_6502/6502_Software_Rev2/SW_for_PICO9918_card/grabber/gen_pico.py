#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for GOLD GRABBER (the hi-res version)
-> grabber_gfx.inc.   python gen_pico.py   (python gen_pico.py png: sheet.png)

Everything is drawn at the screen's own resolution in the F18A's enhanced
colour mode ECM2: 2 bits a pixel, each pattern and sprite 3 colours (and see-
through) from one of 16 groups of 4 palette entries.

  - layer 1 (still): the field's background, the sky, the grass and the dirt.
  - layer 2 (on top): the miner, the platform and the winch, and the things
    in the pit: the game draws those into patterns of their own when a
    level starts (the "compose" pictures here, a row at a time).  Text.
  - sprites: the claw, what it holds, the gophers, the bangs, the target
    ring; the rope and the laser are drawn into a pattern by the game.

A game pixel is 1.5 x 2 screen pixels: screen x = 8 + x + x / 2, y = 8 + 2y.
"""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
import gen
from fontgen import bold_font

FLIPX = 0x40
TRANS = 0x10

# ---- the palette: 16 groups of 4 (red, green, blue 0-15) -------------------------
PS = {}
PAL = []
def group(name, cols):
    PS[name] = len(PAL)
    PAL.append(cols)
group('TEXT',  [(0, 0, 0), (5, 5, 5), (10, 10, 10), (15, 15, 15)])     # white on black
group('RV',    [(2, 3, 10), (4, 5, 12), (8, 9, 14), (15, 15, 15)])     # white on blue
group('SKY',   [(3, 6, 12), (5, 9, 14), (8, 12, 15), (14, 15, 15)])
DIRT = [(6, 3, 1), (4, 2, 1), (8, 5, 2), (7, 6, 5)]
group('DIRT',  DIRT)
group('GRASS', [DIRT[0], (1, 6, 1), (4, 11, 2), DIRT[1]])
group('HEAD',  [(0, 0, 0), (1, 1, 1), (15, 12, 0), (14, 10, 7)])       # helmet, skin
group('BODY',  [(0, 0, 0), (1, 1, 1), (3, 5, 12), (14, 10, 7)])        # overalls, skin
group('WOOD',  [(0, 0, 0), (4, 2, 1), (10, 6, 3), (9, 9, 10)])
group('CHEST', [(0, 0, 0), (3, 1, 0), (9, 5, 2), (15, 12, 2)])
group('GEM',   [(0, 0, 0), (0, 4, 8), (2, 12, 14), (15, 15, 15)])
group('ROCK',  [(0, 0, 0), (4, 4, 4), (8, 8, 8), (12, 12, 11)])
group('TNT',   [(0, 0, 0), (6, 0, 0), (13, 2, 1), (15, 14, 10)])
group('GOPHER', [(0, 0, 0), (3, 2, 1), (11, 7, 3), (15, 15, 14)])
group('ROPE',  [(0, 0, 0), (5, 3, 1), (12, 9, 5), (15, 13, 9)])
group('CLAW',  [(0, 0, 0), (3, 3, 4), (9, 9, 10), (15, 15, 15)])
group('BOOM',  [(0, 0, 0), (13, 1, 0), (15, 8, 0), (15, 15, 4)])
assert len(PAL) == 16


def sx(x): return 8 + x + x // 2        # game -> screen
def sy(y): return 8 + 2 * y


# ---- drawing helpers -------------------------------------------------------------
def canvas(w, h): return [[0] * w for _ in range(h)]
def from_rows(rows, key):
    return [[key[c] for c in r] for r in rows]
def outline(g):
    """1 on every empty pixel next to a filled one? no: filled pixels on the
    edge become 1"""
    h, w = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] and any(not (0 <= x + dx < w and 0 <= y + dy < h) or not g[y + dy][x + dx]
                               for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 1
    return out


def rock(w, h, seed):
    g = canvas(w, h)
    cx, cy = (w - 1) / 2, (h - 1) / 2 + 0.3
    for y in range(h):
        for x in range(w):
            a = math.atan2(y - cy, x - cx)
            r = 1 + 0.10 * math.sin(3 * a + seed) + 0.07 * math.sin(5 * a + 2 * seed)
            d = ((x - cx) / (w / 2)) ** 2 + ((y - cy) / (h / 2)) ** 2
            if d <= r * r * 0.98:
                # light from the top left
                l = -(x - cx) / w - (y - cy) / h
                g[y][x] = 3 if l > 0.18 else 2 if l > -0.25 else 1
    g = outline(g)
    # a crack or two
    for k in range(2):
        x, y = int(cx + (k - 0.5) * w / 4), int(cy - h / 6)
        for s in range(max(2, h // 4)):
            if 0 < x < w - 1 and 0 < y < h - 1 and g[y][x] > 1: g[y][x] = 1
            y += 1; x += (1 if (s + k + seed) % 3 == 0 else 0) * (1 if k else -1)
    return g


def chest(w, h):
    g = canvas(w, h)
    lid = max(4, h * 2 // 5)
    for y in range(h):
        for x in range(w):
            if y < lid:     # a rounded lid
                inset = [3, 1, 0, 0, 0, 0, 0][y] if y < 7 else 0
                if w > 16: inset = [4, 2, 1, 0, 0, 0, 0][y] if y < 7 else 0
                if inset <= x < w - inset: g[y][x] = 2
            else:
                g[y][x] = 2
    g = outline(g)
    for x in range(1, w - 1):             # the gold band where the lid shuts
        g[lid][x] = 3
        g[lid - 1][x] = 1
    for y in range(lid + 2, h - 1, 3):    # planks
        for x in range(1, w - 1):
            if g[y][x] == 2: g[y][x] = 1
    for x in (2, w - 3):                  # gold corner bands
        for y in range(h):
            if g[y][x] == 2: g[y][x] = 3
    lx = w // 2 - 2                       # the lock
    for y in range(lid - 1, lid + 4):
        for x in range(lx, lx + 4):
            g[y][x] = 3
    g[lid + 1][lx + 1] = 1; g[lid + 1][lx + 2] = 1; g[lid + 2][lx + 1] = 1
    for x in range(2, w - 2):             # a glint on the lid
        if g[1][x] == 2 and x < w // 2: g[1][x] = 3
    return g


def gem(w, h):
    g = canvas(w, h)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    for y in range(h):
        for x in range(w):
            if abs(x - cx) / (w / 2) + abs(y - cy) / (h / 2) <= 1.0:
                g[y][x] = 3 if (x < cx and y < cy) else 2 if (x <= cx + 1 or y < cy) else 1
    g = outline(g)
    if h > 6: g[int(cy) - 1][int(cx) - 1] = 3
    return g


TNT_ROWS = [
    "......33....",
    ".....3.3....",
    "......1.....",
    ".....1......",
    "....1.......",
    ".11..1..11..",
    "1221.1.1221.",
    "12211111221.",
    "12212212221.",
    "12212212221.",
    "33333333333.",
    "31313133131.",
    "33333333333.",
    "12212212221.",
    "12212212221.",
    "12212212221.",
    "12212212221.",
    "12212212221.",
    ".11.1111.11.",
    "............",
]
GOPHER_ROWS = [
    "..........111...",
    ".........12221..",
    "...111111223121.",
    "..12222222222221",
    ".122222222222111",
    "12222222222223..",
    "12222222222221..",
    "1222222222221...",
    ".12222222222121.",
    "..11211112111...",
]
GOPHER_LEGS = [["...121.....121..", "...11......11..."],
               ["..121.....121...", "..11......11...."]]
MINER_ROWS = [      # K black, Y yellow, S skin, B blue; 24 x 24
    "........KKKKKK..........",
    "......KKYYYYYYKK........",
    ".....KYYYYYYYYYYK.......",
    ".....KYYYYYYYYYYYKKK....",
    "....KKKKKKKKKKKKKKKYK...",
    "......KSSSSSSSSKKKK.....",
    "......KSSSSSKSSK........",
    "......KSSSSSSSSSK.......",
    "......KSSSSSSSSK........",
    "......KKSKKKKSK.........",
    ".......KSSSSSSK.........",
    "........KKKKKK..........",
    ".....KKBBBBBBBBKK.......",
    "....KBBBBBBBBBBBBKKK....",
    "....KBBKBBBBBBBBBBSSK...",
    "....KBBKBBBBBBBKKKSSK...",
    "....KSSKBBBBBBBK..KK....",
    ".....KK.KBBBBBBK........",
    "........KBBBBBBK........",
    "........KBBKKBBK........",
    "........KBBK.KBBK.......",
    "........KBBK..KBBK......",
    ".......KKKKK..KKKKK.....",
    ".......KKKKK..KKKKK.....",
]
WINCH_ROWS = [      # D dark, W wood, G grey; 16 x 16, two frames (the crank)
    ["................",
     "................",
     "................",
     "........GG......",
     "......GGWWGG....",
     ".....GWWWWWWG...",
     ".GG.GWDWDWDWWG..",
     ".GGGGWDWDWDWWG..",
     "..GGGWDWDWDWWG..",
     ".....GWWWWWWG...",
     "......GGWWGG....",
     ".......DGGD.....",
     "......DW..WD....",
     ".....DW....WD...",
     "....DW......WD..",
     "...DDD......DDD."],
    ["................",
     "................",
     "................",
     "........GG......",
     "......GGWWGG....",
     ".....GWWWWWWG...",
     "....GWDWDWDWWG..",
     "..GGGWDWDWDWWG..",
     ".GGGGWDWDWDWWG..",
     ".GG..GWWWWWWG...",
     "......GGWWGG....",
     ".......DGGD.....",
     "......DW..WD....",
     ".....DW....WD...",
     "....DW......WD..",
     "...DDD......DDD."],
]


def boom(f):
    g = canvas(24, 24)
    c = 11.5
    for y in range(24):
        for x in range(24):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            spikes = 0.75 + 0.25 * math.cos(8 * a + f * 0.7) + 0.1 * math.sin(13 * a)
            R = (8.5 if f == 0 else 11) * spikes
            if r <= R:
                q = r / R
                if f == 0: g[y][x] = 3 if q < 0.45 else 2 if q < 0.8 else 1
                else:      g[y][x] = 2 if q < 0.35 else 1 if q < 0.75 else (1 if (x + y) % 2 else 0)
    if f == 1:      # bits flying
        for (x, y) in ((2, 3), (21, 2), (1, 19), (22, 20), (11, 0), (12, 23), (0, 11), (23, 12)):
            g[y][x] = 3
    return g


def ring():
    g = canvas(8, 10)
    for y in range(10):
        for x in range(8):
            d = math.hypot((x - 3.5) / 3.6, (y - 4.5) / 4.4)
            if 0.62 <= d <= 1.0: g[y][x] = 3 if y < 4 else 2
    return g


CLAW_ART = [
    ["......3.2.......",
     "......322.......",
     "......322.......",
     ".....33221......",
     "....3222221.....",
     "....3222221.....",
     "...321222121....",
     "..321.....121...",
     ".321.......121..",
     ".21.........12..",
     ".21.........12..",
     ".321.......121..",
     "..32.......21...",
     "...3.......1....",
     "................",
     "................"],
    ["......3.2.......",
     "......322.......",
     "......322.......",
     ".....33221......",
     "....3222221.....",
     "....3222221.....",
     "....3212121.....",
     "...321...121....",
     "...21.....12....",
     "..321.....121...",
     "..21.......12...",
     "..321.....121...",
     "...321...121....",
     "....3.....1.....",
     "................",
     "................"],
]
CLAW_ANCHOR = (7, 0)


def claw_anchor(angle):
    """where the rope's end is in the claw's 16 x 16 box: so that the claw's
    middle (6.5 pixels on) is the box's"""
    a = math.radians(angle)
    return 8 - 6.5 * math.sin(a), 8 - 6.5 * math.cos(a)


def claw(angle, shut):
    """the claw pointing along screen angle (0 = down, + = to the right),
    anchored (the rope's end) at (8, 2) in a 16 x 16 box"""
    src = [[int(c) if c != '.' else 0 for c in r] for r in CLAW_ART[shut]]
    ax, ay = CLAW_ANCHOR
    a = math.radians(angle)
    ux, uy = math.sin(a), math.cos(a)       # the claw's "down"
    vx, vy = uy, -ux                        # its "right"
    g = canvas(16, 16)
    S = 3
    cax, cay = claw_anchor(angle)
    for y in range(16):
        for x in range(16):
            votes = {}
            for j in range(S):
                for i in range(S):
                    wx = x + (i + 0.5) / S - cax
                    wy = y + (j + 0.5) / S - cay
                    px = wx * vx + wy * vy + ax + 0.5
                    py = wx * ux + wy * uy + ay + 0.5
                    xi, yi = math.floor(px), math.floor(py)
                    v = src[yi][xi] if 0 <= xi < 16 and 0 <= yi < 16 else 0
                    votes[v] = votes.get(v, 0) + 1
            best = max((k for k in votes if k), key=lambda k: votes[k], default=0)
            if best and votes[best] * 2 >= S * S: g[y][x] = best
    return g


def screen_dir(i):
    """the rope's direction i (0 .. NDIR-1) on the screen: unit vector"""
    t = math.radians((i - (gen.NDIR - 1) / 2) / ((gen.NDIR - 1) / 2) * gen.MAXDEG)
    x, y = 1.5 * math.sin(t), 2 * math.cos(t)
    n = math.hypot(x, y)
    return x / n, y / n


# ---- the field: layer 1 (opaque) and layer 2's still things --------------------------
def bayer(x, y):
    m = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    return (m[y & 3][x & 3] + 0.5) / 16


def field_layers():
    W, H = 256, 192
    L1 = [[(PS['TEXT'], 0)] * W for _ in range(H)]          # row 0: black
    # the sky: rows 1-5 (y 8-47), a gradient of 3 blues, and two clouds
    clouds = [(44, 21, 14, 4), (206, 18, 9, 3)]
    for y in range(8, 48):
        t = (y - 8) / 39 * 2.0
        for x in range(W):
            lo = int(t); fr = t - lo
            v = min(2, lo + (1 if fr > bayer(x, y) else 0))
            for (cx, cy, rx, ry) in clouds:
                d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                puff = 0.18 * math.sin(x * 0.7)
                if d <= 1 + puff:
                    v = 3 if (y - cy) < ry * 0.25 + 0.6 * math.sin(x * 0.5) else 2
            L1[y][x] = (PS['SKY'], v)
    # the dirt: a 16 x 16 texture, two kinds by a hash of the place
    def dirt(x, y, kind):
        h = (x * 7 + y * 13 + kind * 5) % 16
        hx = ((x * 37 + y * 11 + kind * 29) * 2654435761) >> 16 & 255
        if hx < 14: return 2                     # light specks
        if hx < 30: return 1                     # dark spots
        if kind and ((x - 5) % 16) ** 2 + ((y - 9) % 16) ** 2 <= 2: return 3     # a pebble
        return 0
    for y in range(48, H):
        for x in range(W):
            cx, cy = x // 16, y // 16
            kind = ((cx * 5 + cy * 3) * 7 % 11) % 2
            L1[y][x] = (PS['DIRT'], dirt(x % 16, y % 16, kind))
    # the grass: the top of row 6 (y 48-55)
    for x in range(W):
        top = 48 + (1 if (x * 5 % 7) < 3 else 0) + (1 if x % 16 == 3 else 0) if 0 else 48 + [0,1,0,0,1,1,0,1,0,0,0,1,0,1,1,0][x % 16]
        for y in range(48, 56):
            base = L1[y][x][1]
            if y < top: v = 0
            elif y < 51: v = 2 if (x + y) % 4 else 1
            elif y < 52 + (x % 4 == 0): v = 1
            else: v = {0: 0, 1: 3, 2: 0, 3: 0}[base]
            L1[y][x] = (PS['GRASS'], v)
        if L1[48][x][1] == 0:       # the sky behind the grass tips: dirt colour is wrong; grass instead
            L1[48][x] = (PS['GRASS'], 2)
    # layer 2: the miner (rows 1-3), the winch, the platform (row 4), its
    # posts and the pulley (row 5)
    L2 = [[None] * W for _ in range(H)]
    KEY_M = {'.': None, 'K': 1, 'Y': 2, 'S': 3, 'B': 2}
    for y, r in enumerate(MINER_ROWS):
        for x, c in enumerate(r):
            if c == '.': continue
            g = PS['HEAD'] if y < 8 else PS['BODY']
            L2[8 + y][104 + x] = (g, KEY_M[c])
    PX0, PX1 = 96, 160
    for x in range(PX0, PX1):
        for y in range(32, 39):
            v = 1 if y in (32, 38) else 2
            if (x - PX0) % 16 == 15: v = 1
            if y == 33 and v == 2: v = 3 if 0 else 2
            L2[y][x] = (PS['WOOD'], v)
        if x in (PX0, PX1 - 1):
            for y in range(32, 39): L2[y][x] = (PS['WOOD'], 1)
    for px in (99, 155):
        for y in range(39, 48):
            for x in range(px, px + 3):
                L2[y][x] = (PS['WOOD'], 1 if x != px + 1 else 2)
    for y in range(39, 46):        # the pulley the rope comes out of
        for x in range(124, 132):
            d = math.hypot(x - 127.5, y - 42)
            if d <= 3.6: L2[y][x] = (PS['WOOD'], 1 if d > 2.6 else 3 if d > 1.0 else 1)
    L2w = []
    KEY_W = {'.': None, 'D': 1, 'W': 2, 'G': 3}
    for f in range(2):
        g = [row[:] for row in L2]
        for y, r in enumerate(WINCH_ROWS[f]):
            for x, c in enumerate(r):
                if c != '.': g[16 + y][128 + x] = (PS['WOOD'], KEY_W[c])
        L2w.append(g)
    return L1, L2w


def cells_of(img, opaque):
    """the 8 x 8 cells of a 256 x 192 picture of (group, value) -> {(cx, cy):
    (bytes16, group)}; None cells (layer 2) left out"""
    out = {}
    for cy in range(24):
        for cx in range(32):
            px = [img[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
            if not opaque and all(p is None for p in px): continue
            groups = {p[0] for p in px if p is not None and (opaque or p[1])}
            if len(groups) > 1:
                raise SystemExit('cell %d,%d has groups %s' % (cx, cy, groups))
            gr = groups.pop() if groups else 0
            p0 = []; p1 = []
            for y in range(8):
                b0 = b1 = 0
                for x in range(8):
                    p = img[cy * 8 + y][cx * 8 + x]
                    v = p[1] if p else 0
                    if v & 1: b0 |= 0x80 >> x
                    if v & 2: b1 |= 0x80 >> x
                p0.append(b0); p1.append(b1)
            out[(cx, cy)] = (tuple(p0 + p1), gr)
    return out


def bits(g, x0, y0, w, h):
    """rows of g from x0 (w wide) packed for the compose routine"""
    nb = (w + 7) // 8
    rows = []
    for y in range(h):
        for bit in (1, 2):
            for k in range(nb):
                v = 0
                for i in range(8):
                    x = x0 + k * 8 + i
                    if x < x0 + w and 0 <= y0 + y < len(g) and x < len(g[0]) and g[y0 + y][x] & bit:
                        v |= 0x80 >> i
                rows.append(v)
    return nb, rows


def part(g, x0, y0):
    """the 16 x 16 part at x0, y0 -> 64 bytes: plane 0 (TMS order), plane 1"""
    h, w = len(g), len(g[0])
    def px(x, y): return g[y][x] if 0 <= x < w and 0 <= y < h else 0
    out = []
    for bit in (1, 2):
        for half in (0, 8):
            for y in range(16):
                out.append(sum(0x80 >> i for i in range(8) if px(x0 + half + i, y0 + y) & bit))
    return tuple(out)


def pictures():
    """name -> (grid of 0-3, group)"""
    P = {}
    P['GEM'] = (gem(8, 10), PS['GEM'])
    P['CHEST_S'] = (chest(14, 14), PS['CHEST'])
    P['CHEST_L'] = (chest(20, 18), PS['CHEST'])
    P['ROCK_S'] = (rock(11, 10, 1.0), PS['ROCK'])
    P['ROCK_L'] = (rock(18, 18, 2.3), PS['ROCK'])
    P['TNT'] = (from_rows(TNT_ROWS, {'.': 0, '1': 1, '2': 2, '3': 3}), PS['TNT'])
    for f in range(2):
        rows = GOPHER_ROWS + GOPHER_LEGS[f]
        P['GOPHER%d' % (f + 1)] = (from_rows(rows, {'.': 0, '1': 1, '2': 2, '3': 3}), PS['GOPHER'])
    P['BOOM1'] = (boom(0), PS['BOOM'])
    P['BOOM2'] = (boom(1), PS['BOOM'])
    P['TARGET'] = (ring(), PS['BOOM'])
    return P


def main():
    o = ['; grabber_gfx.inc - made by gen_pico.py (python gen_pico.py)', '']
    def tab(name, vals, comment=''):
        o.append(name + ':' + (('   ; ' + comment) if comment else ''))
        for i in range(0, len(vals), 16):
            o.append('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + 16]))
    for k, v in PS.items(): o.append('PS_%-8s = %d' % (k, v))
    pal = []
    for g in PAL:
        for (r, gg, b) in g: pal += [r, gg << 4 | b]
    tab('pal_data', pal, '64 palette entries: 0000RRRR, GGGGBBBB')
    tab('font', bold_font(), '$20-$5F, 8 bytes each (both planes)')

    # ---- tile patterns: 0 blank, $20-$5F the font, then the field's
    L1, L2w = field_layers()
    c1 = cells_of(L1, True)
    c2a = cells_of(L2w[0], False)
    c2b = cells_of(L2w[1], False)
    pats = {}           # (bytes, group, layer) -> number
    order = []
    nxt = [0x60]
    def pnum(key):
        if key[0] == tuple([0] * 16) and key[2] == 2: return 0
        if key not in pats:
            pats[key] = nxt[0]; order.append(key); nxt[0] += 1
        return pats[key]
    names1 = [pnum((c1[(cx, cy)][0], c1[(cx, cy)][1], 1)) if cy > 0 else 0
              for cy in range(24) for cx in range(32)]
    l2a = {k: pnum((v[0], v[1], 2)) for k, v in c2a.items()}
    l2b = {k: pnum((v[0], v[1], 2)) for k, v in c2b.items()}
    # the winch: layer 2 cells that differ between the frames
    wcells = sorted(k for k in set(l2a) | set(l2b) if l2a.get(k, 0) != l2b.get(k, 0))
    POOL = nxt[0]
    o.append('T_BASE   = $60')
    o.append('T_COUNT  = %d' % len(order))
    o.append('POOL     = $%02X' % POOL)
    # the pool: the patterns the things are drawn into: from POOL on, and the
    # font's letters the field's text never uses (the font is put back when
    # the field goes)
    FIELD_TXT = set(' !$+/0123456789:ABCDEGHILMNOPQRSTUVWY')
    free = [c for c in range(0x20, 0x60) if chr(c) not in FIELD_TXT]
    pool = list(range(POOL, 256)) + free         # (the letters last)
    o.append('NPOOL    = %d' % len(pool))
    tab('pool_pat', pool, "the pool's patterns")
    ix = [0] * 256
    for i, p in enumerate(pool): ix[p] = i + 1
    tab('pool_ix', ix, 'pattern -> its place in the pool + 1 (0: not one)')
    tab('t_pat0', [b for k in order for b in k[0][:8]])
    tab('t_pat1', [b for k in order for b in k[0][8:]])
    a1 = [PS['TEXT']] * 256; a2 = [TRANS] * 256
    for c in range(0x20, 0x60): a1[c] = PS['TEXT']; a2[c] = PS['RV']
    for k in order:
        n = pats[k]
        if k[2] == 1: a1[n] = k[1]
        else: a2[n] = TRANS | k[1]
    tab('attr1', a1, "layer 1's attribute table")
    tab('attr2', a2, "layer 2's")
    tab('field_l1', names1, "the field's layer 1 names")
    l2list = [(cy * 32 + cx, n) for (cx, cy), n in sorted(l2a.items())]
    o.append('N_L2  = %d' % len(l2list))
    tab('l2_lo', [a & 255 for a, n in l2list]); tab('l2_hi', [a >> 8 for a, n in l2list])
    tab('l2_nm', [n for a, n in l2list], "the field's layer 2 (the miner, platform, winch)")
    o.append('N_WINCH = %d' % len(wcells))
    tab('w_lo', [(cy * 32 + cx) & 255 for cx, cy in wcells]); tab('w_hi', [(cy * 32 + cx) >> 8 for cx, cy in wcells])
    tab('w_nm0', [l2a.get(k, 0) for k in wcells]); tab('w_nm1', [l2b.get(k, 0) for k in wcells], 'the winch turning')
    print('tile patterns: font 64, field %d (from $60), pool %d' % (len(order), len(pool)))

    # ---- the things: compose pictures (drawn into layer 2 by the game)
    P = pictures()
    comp = ['GEM', 'CHEST_S', 'CHEST_L', 'ROCK_S', 'ROCK_L', 'TNT', 'GOPHER1']
    cdata = []; cofs = []
    for n in comp:
        g, ps = P[n]
        h, w = len(g), len(g[0])
        nb, rows = bits(g, 0, 0, w, h)
        cofs.append(len(cdata)); cdata += [w, h, ps, nb] + rows
    for i, n in enumerate(comp): o.append('CP_%-8s = %d' % (n, i))
    o.append('cp_lo:\n        .byte   ' + ', '.join('<(cp_data+%d)' % k for k in cofs))
    o.append('cp_hi:\n        .byte   ' + ', '.join('>(cp_data+%d)' % k for k in cofs))
    tab('cp_w', [len(P[n][0][0]) for n in comp]); tab('cp_h', [len(P[n][0]) for n in comp])
    tab('cp_data', cdata, 'width, height, group, bytes a row; then each row: plane 0, plane 1')

    # ---- sprites: parts (64 bytes) and pictures (lists of parts)
    parts = []; pidx = {}
    def pn(b):
        if not any(b): return None
        if b not in pidx: pidx[b] = len(parts); parts.append(b)
        return pidx[b]
    pics = []               # (name, [(dx, dy, part, attr)])
    def pic(name, g, ps, dx0=0, dy0=0, flip=False):
        h, w = len(g), len(g[0])
        ent = []
        for y0 in range(0, h, 16):
            for x0 in range(0, w, 16):
                n = pn(part(g, x0, y0))
                if n is None: continue
                dx = x0
                if flip: dx = (16 * ((w + 15) // 16)) - 16 - x0 - ((16 * ((w + 15) // 16)) - w)
                ent.append((dx + dx0, y0 + dy0, n, ps | (FLIPX if flip else 0)))
        pics.append((name, ent))
    # by gen.py's SP_ numbers, where the game shows them as sprites
    SPN = {n: i for i, n in enumerate(gen.ORDER)}
    for n in ('GEM', 'CHEST_S', 'CHEST_L', 'ROCK_S', 'ROCK_L', 'TNT'):
        pic(n, *P[n])
    g1, gps = P['GOPHER1']; g2, _ = P['GOPHER2']; gm, gmps = P['GEM']
    pic('GOPHER_R1', g1, gps); pic('GOPHER_R2', g2, gps)
    pic('GOPHER_L1', g1, gps, flip=True); pic('GOPHER_L2', g2, gps, flip=True)
    # with a gem in its mouth: right: gem 16 to the right; left: gem first,
    # the gopher 4 further on (the game's picture is 14 pixels: 3 more)
    for f, gg in ((1, g1), (2, g2)):
        pics.append(('GOPHERG_R%d' % f, [(0, 0, pidx[part(gg, 0, 0)], gps), (15, 1, pidx[part(gm, 0, 0)], gmps)]))
    for f, gg in ((1, g1), (2, g2)):
        pics.append(('GOPHERG_L%d' % f, [(4, 0, pidx[part(gg, 0, 0)], gps | FLIPX), (-3, 1, pidx[part(gm, 0, 0)], gmps)]))
    pic('BOOM1', *P['BOOM1'], dx0=-1, dy0=-1)
    pic('BOOM2', *P['BOOM2'], dx0=-1, dy0=-1)
    pic('TARGET', *P['TARGET'])
    # the claw: 5 ways, open and shut; anchored at the rope's end (8, 2)
    cl_angles = [-60, -32, 0, 32, 60]
    for shut in (0, 1):
        for k, a in enumerate(cl_angles):
            g = claw(a, shut)
            ax, ay = claw_anchor(a)
            pics.append(('CLAW%s%d' % ('S' if shut else '', k), [(-round(ax), -round(ay), pn(part(g, 0, 0)), PS['CLAW'])]))
    byname = dict(pics)
    plist = []; pofs = []
    for n in gen.ORDER:
        ent = byname.get(n, [])
        pofs.append(len(plist))
        plist += [len(ent)]
        for dx, dy, p, a in ent: plist += [dx & 255, dy & 255, p, a]
    o.append('NPARTS = %d' % len(parts))
    o.append('pk_lo:\n        .byte   ' + ', '.join('<(pl_data+%d)' % k for k in pofs))
    o.append('pk_hi:\n        .byte   ' + ', '.join('>(pl_data+%d)' % k for k in pofs))
    tab('pl_data', plist, "by SP_ number: parts; then dx, dy (screen pixels), part, attribute")
    tab('spr_parts', [b for p in parts for b in p], '64 bytes a part: plane 0, plane 1 (16 x 16)')
    print('sprite parts', len(parts), '(%d bytes)' % (64 * len(parts)))

    # ---- the rope and the laser: by direction (0 .. 32, from straight down;
    # the left half mirrored): a 1 pixel step (8.8), and where it starts
    D = (gen.NDIR - 1) // 2
    ux = []; uy = []
    for d in range(D + 1):
        x, y = screen_dir(D + d)
        ux.append(round(x * 256)); uy.append(round(y * 256))
    o.append('RSTEP = 13          ; a rope sprite\'s length (pixels)')
    tab('rd_ux', [v & 255 for v in ux]); tab('rd_ux_hi', [v >> 8 for v in ux])
    tab('rd_uy', [v & 255 for v in uy]); tab('rd_uy_hi', [v >> 8 for v in uy], 'a 1 pixel step down the rope, 8.8')
    st = [round(13 * v) for v in ux]; tab('rs_x', [v & 255 for v in st]); tab('rs_x_hi', [v >> 8 for v in st])
    st = [round(13 * v) for v in uy]; tab('rs_y', [v & 255 for v in st]); tab('rs_y_hi', [v >> 8 for v in st], '... 13 pixels')

    open(os.path.join(HERE, 'grabber_gfx.inc'), 'w').write('\n'.join(o) + '\n')
    print('grabber_gfx.inc written')
    return L1, L2w, P, pics, parts


def sheet():
    from PIL import Image
    L1, L2w, P, pics, parts = main()
    def rgb(g, v): r, gg, b = PAL[g][v]; return (r * 17, gg * 17, b * 17)
    im = Image.new('RGB', (256 * 2 + 16, 192))
    for y in range(192):
        for x in range(256):
            g, v = L1[y][x]; c = rgb(g, v)
            p = L2w[0][y][x]
            if p and p[1]: c = rgb(*p)
            im.putpixel((x, y), c)
    # the things on dirt
    x0, y0 = 256 + 16, 0
    for y in range(192):
        for x in range(256): im.putpixel((x0 + x, y), rgb(PS['DIRT'], 0))
    cx = x0 + 4
    for n in ('GEM', 'CHEST_S', 'CHEST_L', 'ROCK_S', 'ROCK_L', 'TNT', 'GOPHER1', 'GOPHER2', 'BOOM1', 'BOOM2', 'TARGET'):
        g, ps = P[n]
        for y, r in enumerate(g):
            for x, v in enumerate(r):
                if v: im.putpixel((cx + x, 8 + y), rgb(ps, v))
        cx += len(g[0]) + 4
        if cx > x0 + 220: cx = x0 + 4; y0 += 0
    for k, a in enumerate([-60, -32, 0, 32, 60]):
        for shut in (0, 1):
            g = claw(a, shut)
            for y in range(16):
                for x in range(16):
                    if g[y][x]: im.putpixel((x0 + 4 + k * 20 + x, 40 + shut * 20 + y), rgb(PS['CLAW'], g[y][x]))
    im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
    im.save(os.path.join(HERE, 'sheet.png'))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'png': sheet()
    else: main()
