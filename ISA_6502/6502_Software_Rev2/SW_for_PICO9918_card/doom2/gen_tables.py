#!/usr/bin/env python3
"""gen_tables.py - tables.inc for DOOM2 (the hi-res 6502 DOOM).
   python3 gen_tables.py            (python3 gen_tables.py png: art.png)

The view is 240 x 144 screen pixels (Graphics II, cell columns 1-30, rows
0-17): 120 columns of 2 pixels, a ray each (or between two rays on the same
wall face), drawn at single line precision.  Walls are textured (16 x 32
texels, two colours a line: the wall's and the dark of the ceiling or floor
behind it), things are 32 x 48 pictures scaled to their distance, the gun is
ECM2 sprites.
"""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font

COLS = 120                  # 2 pixel columns
VH = 144                    # lines
HORIZON = 72
FOV = 66.0
HALF_TAN = math.tan(math.radians(FOV / 2))
FOCAL = (COLS / 2) / HALF_TAN       # columns per unit of lateral / depth (92)
WALL_K = 120.0              # wall height in lines at 1 tile
ANG = 1024
ART_W, ART_H = 32, 48       # a thing's picture
TEX_W, TEX_H = 16, 32       # a wall's

def col_angle(c):
    x = ((c + 0.5) - COLS / 2) / (COLS / 2)
    return math.atan(x * HALF_TAN)

def wall_h(idx):            # idx = perpendicular distance in 1/32 tile
    if idx == 0: return VH
    return min(VH, int(round(WALL_K * 32 / idx)))

def bl(vals, per=16):
    return '\n'.join('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + per])
                     for i in range(0, len(vals), per))

# ---- the palette (Graphics II colours 0-15; sprites' groups from 16) --------------
PAL16 = [
    (0, 0, 0), (0, 0, 0),                   # 0 (see-through), 1 black
    (1, 1, 2), (3, 3, 5),                   # 2, 3 the ceiling: dark, lighter
    (2, 1, 1), (5, 3, 2),                   # 4, 5 the floor
    (12, 4, 2), (7, 2, 1),                  # 6, 7 brick
    (5, 8, 14), (2, 4, 9),                  # 8, 9 tech
    (11, 11, 10), (6, 6, 6),                # 10, 11 stone
    (11, 7, 3), (6, 4, 2),                  # 12, 13 wood
    (15, 12, 2), (3, 12, 3),                # 14 yellow, 15 green
]
C_BLACK, C_CEIL0, C_CEIL1, C_FLOOR0, C_FLOOR1 = 1, 2, 3, 4, 5
C_BRICK, C_BRICKD, C_TECH, C_TECHD, C_STONE, C_STONED, C_WOOD, C_WOODD, C_YELLOW, C_GREEN = range(6, 16)
GROUPS = {          # sprite colour groups (ECM2): 4 entries each, from 16
    4: [(0, 0, 0), (1, 1, 1), (7, 7, 8), (13, 13, 14)],     # the gun's metal
    5: [(0, 0, 0), (3, 1, 0), (10, 6, 4), (14, 10, 7)],     # the hand
    6: [(0, 0, 0), (14, 3, 0), (15, 9, 0), (15, 15, 8)],    # the flash
}
PS_GUN, PS_HAND, PS_FLASH = 4, 5, 6

# ---- walls: styles 1-7, 16 x 32 texels ('#' the wall, '.' the dark) ---------------------
def tex_brick():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            r = v // 8
            mortar = (v % 8 == 7) or (u == (0 if r % 2 == 0 else 8))
            row += '.' if mortar else '#'
        t.append(row)
    return t

def tex_tech():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            edge = u in (0,) or v in (0, 15, 16)
            light = (v in (5, 6) and u in (4, 5, 10, 11)) or (v in (24, 25, 26) and 3 <= u <= 12 and (u % 3) == 0)
            row += '.' if edge or light else '#'
        t.append(row)
    return t

def tex_stone():
    # irregular blocks: rows of different heights, joints in different places
    rows = [(0, 9, (0, 9)), (9, 19, (5, 13)), (19, 26, (2, 10)), (26, 32, (7, 15))]
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            m = False
            for (a, b, joints) in rows:
                if a <= v < b:
                    m = (v == b - 1) or (u in joints)
            if (u * 7 + v * 3) % 23 == 0: m = True      # pits
            row += '.' if m else '#'
        t.append(row)
    return t

def tex_door():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            m = u in (0, 15) or v in (0, 31) or (u in (5, 10) and not 13 <= v <= 18) or v in (13, 18)
            if 14 <= v <= 17 and u in (7, 8): m = True       # the handle slot
            row += '.' if m else '#'
        t.append(row)
    return t

def tex_exit():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            m = (v % 4 == 3) or u in (0, 15)
            if 10 <= v <= 20 and 5 <= u <= 10: m = not (11 <= v <= 19 and 6 <= u <= 9) or (v == 15)  # the switch
            row += '.' if m else '#'
        t.append(row)
    return t

def tex_wood():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            m = u in (0, 8) or (u in (3, 12) and (v * 5 + u) % 9 < 2) or ((u - 5) ** 2 + (v - 20) ** 2 <= 2)
            row += '.' if m else '#'
        t.append(row)
    return t

def tex_metal():
    t = []
    for v in range(32):
        row = ''
        for u in range(16):
            m = u == 0 or v in (0, 16) or (u in (2, 13) and v in (3, 12, 19, 28)) or (v == 8 and 4 <= u <= 11)
            row += '.' if m else '#'
        t.append(row)
    return t

TEX = {1: tex_brick(), 2: tex_tech(), 3: tex_stone(), 4: tex_door(), 5: tex_exit(), 6: tex_wood(), 7: tex_metal()}
NSTYLE = 7
# colour by style: (lit side, dark side)
WCOL = {1: (C_BRICK, C_BRICKD), 2: (C_TECH, C_TECHD), 3: (C_STONE, C_STONED), 4: (C_YELLOW, C_WOODD),
        5: (C_GREEN, C_TECHD), 6: (C_WOOD, C_WOODD), 7: (C_STONE, C_STONED)}

def runs(col):
    """'.' runs in a texel column -> [(v0, v1), ...]"""
    out = []; v = 0
    while v < len(col):
        if col[v] == '.':
            s = v
            while v < len(col) and col[v] == '.': v += 1
            out.append((s, v))
        else:
            v += 1
    return out

# ---- the ceiling and floor: a dithered fade to black at the horizon ------------------
BAYER8 = [0, 32, 8, 40, 2, 34, 10, 42]
def bg_line(y):
    """-> (pattern, colour byte fg/bg, the dark (bg) colour)"""
    if y < HORIZON:
        t = 1 - y / (HORIZON - 1)           # 1 at the top: light
        shades = [C_BLACK, C_CEIL0, C_CEIL1]
    else:
        t = (y - HORIZON) / (VH - 1 - HORIZON)
        shades = [C_BLACK, C_FLOOR0, C_FLOOR1]
    t = max(0.0, min(1.0, t)) ** 1.3 * 2.0
    lo = min(1, int(t)); fr = t - lo
    a, b = shades[lo + 1], shades[lo]       # fg (lighter), bg (darker)
    # an ordered dither across the line: fr of the pixels in a
    m = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    p = 0
    for x in range(8):
        if fr > (m[y & 3][x & 3] + 0.5) / 16: p |= 0x80 >> x
    return p, (a << 4) | b, b

# ---- things: 32 x 48, '#' body (the thing's colour), '+' dark, '.' see-through --------
def canvas(): return [['.'] * ART_W for _ in range(ART_H)]
def ell(g, cx, cy, rx, ry, ch='#'):
    for y in range(ART_H):
        for x in range(ART_W):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1: g[y][x] = ch
def rect(g, x0, y0, x1, y1, ch='#'):
    for y in range(max(0, y0), min(ART_H, y1 + 1)):
        for x in range(max(0, x0), min(ART_W, x1 + 1)): g[y][x] = ch
def line(g, x0, y0, x1, y1, ch='+', w=1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n; y = y0 + (y1 - y0) * i / n
        for dx in range(w):
            for dy in range(w):
                xx, yy = int(round(x)) + dx, int(round(y)) + dy
                if 0 <= xx < ART_W and 0 <= yy < ART_H: g[yy][xx] = ch
def outline_dark(g):
    """body pixels next to see-through become dark: an outline"""
    h = [r[:] for r in g]
    for y in range(ART_H):
        for x in range(ART_W):
            if g[y][x] == '#':
                for dx, dy in ((1, 0), (-1, 0), (0, 1)):
                    xx, yy = x + dx, y + dy
                    if not (0 <= xx < ART_W and 0 <= yy < ART_H) or g[yy][xx] == '.':
                        h[y][x] = '+'; break
    return h

def grunt(frame):
    g = canvas()
    ell(g, 16, 6, 4.6, 5.2)                     # the head, a helmet
    rect(g, 11, 2, 21, 3)
    line(g, 13, 6, 14, 6); line(g, 18, 6, 19, 6)   # eyes
    line(g, 14, 9, 18, 9)                       # the mouth
    rect(g, 14, 11, 18, 12)                     # the neck
    ell(g, 16, 20, 8.5, 9)                      # the chest
    rect(g, 9, 15, 23, 29)
    line(g, 16, 14, 16, 27)                     # armour seam
    line(g, 9, 27, 23, 27)                      # the belt
    if frame < 2:
        rect(g, 5, 15, 8, 28); rect(g, 24, 15, 27, 28)      # arms down
        line(g, 6, 26, 24, 18, '+', 2)          # the rifle across
        lx = (10, 12) if frame == 0 else (8, 13)
        rx = (18, 20) if frame == 0 else (19, 15)
        rect(g, lx[0], 30, lx[0] + 4, 44); rect(g, rx[0], 30, rx[0] + 4, 44)
        rect(g, lx[0] - 1, 45, lx[0] + 5, 47); rect(g, rx[0] - 1, 45, rx[0] + 5, 47)
    else:
        rect(g, 7, 15, 10, 22); rect(g, 22, 15, 25, 22)     # arms forward
        rect(g, 11, 19, 21, 23)
        line(g, 16, 22, 16, 15, '+', 2)         # the rifle at you
        ell(g, 16, 13, 4.5, 3.5)                # the flash
        line(g, 16, 8, 16, 11, '#'); line(g, 11, 13, 13, 13, '#'); line(g, 19, 13, 21, 13, '#')
        rect(g, 10, 30, 14, 44); rect(g, 18, 30, 22, 44)
        rect(g, 9, 45, 15, 47); rect(g, 17, 45, 23, 47)
    return outline_dark(g)

def brute(frame):
    g = canvas()
    ell(g, 16, 8, 6.5, 6.5)                     # a big head
    line(g, 10, 4, 6, 0, '#', 2); line(g, 21, 4, 25, 0, '#', 2)   # horns
    line(g, 12, 7, 14, 8); line(g, 18, 8, 20, 7)   # eyes
    line(g, 12, 12, 20, 12); line(g, 13, 13, 19, 13)   # teeth
    ell(g, 16, 23, 13, 10)                      # shoulders and chest
    rect(g, 6, 22, 26, 33)
    line(g, 12, 20, 16, 24); line(g, 20, 20, 16, 24)   # chest marks
    if frame < 2:
        rect(g, 1, 18, 5, 33); rect(g, 27, 18, 31, 33)     # long arms
        line(g, 1, 34, 1, 36, '#'); line(g, 3, 34, 3, 37, '#'); line(g, 28, 34, 28, 37, '#'); line(g, 30, 34, 30, 36, '#')
        lx, rx = ((8, 19) if frame == 0 else (6, 21))
        rect(g, lx, 34, lx + 5, 45); rect(g, rx, 34, rx + 5, 45)
        rect(g, lx - 1, 45, lx + 6, 47); rect(g, rx - 1, 45, rx + 6, 47)
    else:
        line(g, 6, 20, 1, 6, '#', 4); line(g, 26, 20, 30, 6, '#', 4)   # arms up
        for x in (0, 3, 28, 31): line(g, x, 0, x, 5, '#')
        ell(g, 16, 30, 3, 2, '+')               # a roar
        rect(g, 8, 34, 13, 45); rect(g, 19, 34, 24, 45)
        rect(g, 7, 45, 14, 47); rect(g, 18, 45, 25, 47)
    return outline_dark(g)

def dead():
    g = canvas()
    ell(g, 16, 43, 15, 4.5)
    ell(g, 7, 41, 4, 3)
    line(g, 4, 46, 28, 46, '+')
    line(g, 12, 41, 20, 44, '+')
    return outline_dark(g)

def medkit():
    g = canvas()
    rect(g, 3, 22, 28, 46)
    rect(g, 12, 18, 19, 22)                     # the handle
    rect(g, 13, 19, 18, 21, '.')
    rect(g, 13, 26, 18, 42, '+'); rect(g, 7, 31, 24, 37, '+')    # the cross
    return outline_dark(g)

def ammo():
    g = canvas()
    rect(g, 2, 28, 29, 46)
    for x in (6, 12, 18, 24):                   # shells sticking out
        rect(g, x, 18, x + 3, 27)
        rect(g, x, 18, x + 3, 19, '+')
    line(g, 2, 36, 29, 36, '+'); line(g, 2, 37, 29, 37, '+')
    return outline_dark(g)

THINGS = [('SPR_GRUNT1', grunt(0)), ('SPR_GRUNT2', grunt(1)), ('SPR_GRUNTF', grunt(2)),
          ('SPR_BRUTE1', brute(0)), ('SPR_BRUTE2', brute(1)), ('SPR_BRUTEF', brute(2)),
          ('SPR_DEAD', dead()), ('SPR_MEDKIT', medkit()), ('SPR_AMMO', ammo())]

def art_planes(g):
    """-> cover (192 bytes: 48 rows x 4) and body: bit 7 of byte 0 = column 0"""
    cov = []; body = []
    for y in range(ART_H):
        for b in range(4):
            c = d = 0
            for i in range(8):
                ch = g[y][b * 8 + i]
                if ch != '.': c |= 0x80 >> i
                if ch == '#': d |= 0x80 >> i
            cov.append(c); body.append(d)
    return cov, body

# ---- the gun: ECM2 sprites (64 x 48 at the bottom of the view) --------------------
def gun_pic(fire):
    W, H = 64, 64           # (16 above the gun for the flash)
    g = [[(0, 0)] * W for _ in range(H)]          # (group, value)
    def put(x, y, grp, v):
        if 0 <= x < W and 0 <= y < H: g[y][x] = (grp, v)
    # the pistol from behind: the slide (wider lower down), its rear sight
    for y in range(22, 50):
        w = 5 + (y - 22) * 2 // 27
        for x in range(32 - w, 32 + w):
            v = 2
            if x in (32 - w, 32 + w - 1) or y == 22: v = 1
            elif x < 32 - w + 3 or y < 25: v = 3
            if 28 <= y <= 32 and 33 <= x <= 36: v = 1          # the port
            put(x, y, PS_GUN, v)
    for x in (28, 29, 34, 35):
        put(x, 20, PS_GUN, 1); put(x, 21, PS_GUN, 2)
    # the hand: a fist round the grip, fingers to the right, the thumb up
    # the left of the slide, the wrist going off the bottom
    for y in range(44, 64):
        l = 22 - (y - 44) * 2 // 3
        r = 42 + (y - 44) * 2 // 3
        for x in range(l, r + 1):
            if g[y][x][0] == PS_GUN and g[y][x][1]: continue
            v = 2
            if x - l < 3: v = 3                                 # light on the left
            if r - x < 2: v = 1
            if y == 44 and x > 30: v = 1
            put(x, y, PS_HAND, v)
    for k in range(4):                                          # fingers
        cy = 46 + k * 4
        for y in range(cy - 2, cy + 2):
            for x in range(37, 47 + k):
                d = ((x - (40 + k)) / (6.5 + k)) ** 2 + ((y - cy) / 2.2) ** 2
                if d <= 1: put(x, y, PS_HAND, 1 if d > 0.6 or y == cy + 1 else 2)
    for y in range(32, 50):                                     # the thumb
        for x in range(18, 28):
            d = ((x - 23) / 4.2) ** 2 + ((y - 41) / 8.5) ** 2
            if d <= 1: put(x, y, PS_HAND, 1 if d > 0.7 else 3 if x < 23 else 2)
    for y in range(58, 64):                                     # the sleeve
        for x in range(10, 54):
            if g[y][x][1] and g[y][x][0] == PS_HAND:
                put(x, y, PS_GUN, 1 if y == 58 else 2)
    if fire:
        for y in range(0, 26):
            for x in range(14, 50):
                d = math.hypot((x - 32) / 1.0, (y - 12) / 1.15)
                a = math.atan2(y - 12, x - 32)
                r = 9 + 3.5 * math.cos(6 * a)
                if d <= r:
                    put(x, y, PS_FLASH, 3 if d < r * 0.4 else 2 if d < r * 0.75 else 1)
    return g

def gun_parts(g):
    """16 x 16 parts, one group each (the group most of its pixels have);
    -> [(dx, dy, ps, 64 bytes)]"""
    out = []
    for y0 in range(0, 64, 16):
        for x0 in range(0, 64, 16):
            px = [g[y0 + y][x0 + x] for y in range(16) for x in range(16)]
            grps = [p[0] for p in px if p[1]]
            if not grps: continue
            for grp in sorted(set(grps)):
                b = []
                for bit in (1, 2):
                    for half in (0, 8):
                        for y in range(16):
                            v = 0
                            for i in range(8):
                                p = g[y0 + y][x0 + half + i]
                                if p[0] == grp and p[1] & bit: v |= 0x80 >> i
                            b.append(v)
                out.append((x0, y0, grp, b))
    return out

# ---- the title: "DOOM II", 240 x 48 ----------------------------------------------------
BIG = {
    'D': ['#####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '#####.'],
    'O': ['.####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    'M': ['##..##', '######', '######', '##..##', '##..##', '##..##', '##..##', '##..##'],
    'I': ['######', '..##..', '..##..', '..##..', '..##..', '..##..', '..##..', '######'],
    ' ': ['......'] * 8,
}
def logo():
    W, H = 240, 48
    px = [[0] * W for _ in range(H)]
    text = 'DOOM II'
    sx, sy = 5, 6           # letters 30 x 48, 4 apart
    x0 = (W - len(text) * 34 + 4) // 2
    for k, ch in enumerate(text):
        art = BIG[ch]
        for y in range(H):
            row = art[y // sy]
            for x in range(6 * sx):
                if row[x // sx] == '#':
                    # bevel: a dark line at the bottom of each block row
                    if y % sy == sy - 1 and (y // sy == 7 or art[y // sy + 1][x // sx] != '#'): continue
                    if x % sx == sx - 1 and (x // sx == 5 or row[x // sx + 1] != '#'): continue
                    xx = x0 + k * 34 + x
                    if 0 <= xx < W: px[y][xx] = 1
    return px

def logo_colours():
    """fg by line: yellow -> orange -> red (Graphics II colours 14, 6, 7)"""
    out = []
    for y in range(48):
        c = C_YELLOW if y < 14 else C_BRICK if y < 34 else C_BRICKD
        out.append((c << 4) | C_BLACK)
    return out


def main():
    o = ['; tables.inc - made by gen_tables.py (python3 gen_tables.py) - do not edit', '']
    P = lambda s: o.append(s)
    for k, v in (('COLS', COLS), ('VH', VH), ('HORIZON', HORIZON), ('FOCAL', round(FOCAL)),
                 ('NSTYLE', NSTYLE), ('ART_H', ART_H), ('ART_W', ART_W)):
        P('%-8s = %d' % (k, v))
    for k, v in (('C_BLACK', C_BLACK), ('C_YELLOW', C_YELLOW), ('C_GREEN', C_GREEN), ('C_BRICK', C_BRICK),
                 ('C_BRICKD', C_BRICKD), ('C_STONE', C_STONE)):
        P('%-8s = %d' % (k, v))
    P('PS_GUN   = %d' % PS_GUN); P('PS_HAND  = %d' % PS_HAND); P('PS_FLASH = %d' % PS_FLASH)
    P('; sin, 1024 steps per circle, signed, 127 = 1.0')
    P('sin_tab:'); P(bl([int(round(127 * math.sin(2 * math.pi * a / ANG))) for a in range(ANG)]))
    inv = []
    for r in range(257):
        c = math.cos(2 * math.pi * r / ANG)
        inv.append(0x7FFF if c < 1e-6 else min(0x7FFF, int(round(256 / c))))
    P('invc_lo:'); P(bl([v & 0xFF for v in inv])); P('invc_hi:'); P(bl([v >> 8 for v in inv]))
    offs = [int(round(col_angle(c) * ANG / (2 * math.pi))) for c in range(COLS)]
    P('coloff_lo:'); P(bl([o_ & 0xFF for o_ in offs])); P('coloff_hi:'); P(bl([(o_ >> 8) & 0xFF for o_ in offs]))
    P('cosfix:'); P(bl([min(255, int(round(256 * math.cos(2 * math.pi * o_ / ANG)))) for o_ in offs]))
    P('; wall height in lines for a distance in 1/32 tile (0..1023)')
    P('htab:'); P(bl([wall_h(i) for i in range(1024)]))
    sq = [n * n // 4 for n in range(512)]
    P('sq_lo:'); P(bl([v & 0xFF for v in sq[:256]])); P('sq_hi:'); P(bl([v >> 8 for v in sq[:256]]))
    P('sq2_lo:'); P(bl([v & 0xFF for v in sq[256:]])); P('sq2_hi:'); P(bl([v >> 8 for v in sq[256:]]))
    P('; texel rows per line for a thing H lines high: 48 * 256 / H (8.8)')
    rec = [0xFFFF] + [min(0xFFFF, int(round(ART_H * 256 / n))) for n in range(1, 256)]
    P('rec_lo:'); P(bl([v & 0xFF for v in rec])); P('rec_hi:'); P(bl([v >> 8 for v in rec]))
    P('; texel columns per column: 32 * 3 * 256 / H (the picture is H / 3 columns wide)')
    rcw = [0xFFFF] + [min(0xFFFF, int(round(ART_W * 3 * 256 / n))) for n in range(1, 256)]
    P('rcw_lo:'); P(bl([v & 0xFF for v in rcw])); P('rcw_hi:'); P(bl([v >> 8 for v in rcw]))
    P('; n / 3 for n = 0..255')
    P('d3_0:'); P(bl([n // 3 for n in range(256)]))
    P('; (n * n / 4) / 32 for n = 0..176: v * h / 32 = sq5(h + v) - sq5(h - v), to a line')
    P('sq5:'); P(bl([(n * n // 4) >> 5 for n in range(177)]))
    # wall colours by pidx = style * 8 + side * 4 + band
    wc = []
    for s in range(NSTYLE + 1):
        for side in range(2):
            for band in range(4):
                if s == 0: wc.append(C_STONE << 4); continue
                lit, dk = WCOL[s]
                c = dk if side or band >= 2 else lit
                if s in (4, 5) and side == 0: c = lit      # doors and the exit stay bright
                wc.append(c << 4)
    P('; the wall\'s colour (high nibble) by style * 8 + side * 4 + band')
    P('wallcol:'); P(bl(wc))
    # textures: dark runs per (style, u): pairs v0, v1 (texels), then $FF
    lst = []; ofs = []
    for s in range(NSTYLE + 1):
        for u in range(TEX_W):
            ofs.append(len(lst))
            if s:
                col = [TEX[s][v][u] for v in range(TEX_H)]
                for a, b in runs(col): lst += [a, b]
            lst.append(0xFF)
    P('; the dark texel runs of each texture column (style * 16 + u): v0, v1 .. $FF')
    P('tx_lo:'); P(bl([0] * 0) if False else '        .byte   ' + ', '.join('<(tx_data+%d)' % k for k in ofs[:64]))
    P('        .byte   ' + ', '.join('<(tx_data+%d)' % k for k in ofs[64:]))
    P('tx_hi:'); P('        .byte   ' + ', '.join('>(tx_data+%d)' % k for k in ofs[:64]))
    P('        .byte   ' + ', '.join('>(tx_data+%d)' % k for k in ofs[64:]))
    P('tx_data:'); P(bl(lst))
    # the ceiling and the floor
    bgs = [bg_line(y) for y in range(VH)]
    P('; the ceiling and floor by line: pattern, colours, the dark colour')
    P('bg_pat:'); P(bl([p for p, c, d in bgs])); P('bg_col:'); P(bl([c for p, c, d in bgs]))
    P('bg_dark:'); P(bl([d for p, c, d in bgs]))
    # things
    P('; things: 32 x 48, cover then body, 4 bytes a row (bit 7 = column 0)')
    for i, (n, g) in enumerate(THINGS): P('%s = %d' % (n, i))
    P('art_lo:'); P('        .byte   ' + ', '.join('<art_%d' % i for i in range(len(THINGS))))
    P('art_hi:'); P('        .byte   ' + ', '.join('>art_%d' % i for i in range(len(THINGS))))
    for i, (n, g) in enumerate(THINGS):
        c, b = art_planes(g)
        P('art_%d:   ; %s' % (i, n)); P(bl(c)); P(bl(b))
    # the gun
    gparts = []; glist = []
    for fire in (0, 1):
        pl = gun_parts(gun_pic(fire))
        ent = []
        for (x0, y0, grp, b) in pl:
            if b not in gparts: gparts.append(b)
            ent.append((x0, y0, gparts.index(b), grp))
        glist.append(ent)
    P('NGUNPART = %d' % len(gparts))
    P('gun_parts:'); P(bl([v for b in gparts for v in b]))
    for f in (0, 1):
        P('GUN%d_N = %d' % (f, len(glist[f])))
        P('gun%d_list:   ; x, y (from the picture\'s top left), part, group' % f)
        P(bl([v for e in glist[f] for v in e]))
    # the palette: 16, then the sprite groups (entries 16-63)
    pal = [0] * 128
    for i, (r, g, b) in enumerate(PAL16): pal[2 * i] = r; pal[2 * i + 1] = g << 4 | b
    for ps, cols in GROUPS.items():
        for k, (r, g, b) in enumerate(cols):
            i = ps * 4 + k
            pal[2 * i] = r; pal[2 * i + 1] = g << 4 | b
    P('pal_data:'); P(bl(pal))
    # the title logo: 30 cell columns x 48 lines (column by column)
    L = logo()
    data = []
    for cx in range(30):
        for y in range(48):
            v = 0
            for i in range(8):
                if L[y][cx * 8 + i]: v |= 0x80 >> i
            data.append(v)
    P('logo_col:'); P(bl(logo_colours()))
    rle = []            # (count, byte) runs, none across a column's 48
    for cx in range(30):
        col = data[cx * 48:(cx + 1) * 48]
        i = 0
        while i < 48:
            j = i
            while j < 48 and col[j] == col[i]: j += 1
            rle += [j - i, col[i]]; i = j
    P('; the logo, 30 cell columns of 48 lines, as runs: count, byte')
    P('logo_rle:'); P(bl(rle))
    print('logo runs', len(rle))
    P('font:   ; $20-$5F'); P(bl(bold_font()))
    open(os.path.join(HERE, 'tables.inc'), 'w').write('\n'.join(o) + '\n')
    print('tables.inc written; gun parts', len(gparts), [len(x) for x in glist])
    return gparts, glist


def png():
    from PIL import Image
    main()
    W = 16 * 8 + 10 + len(THINGS) * 36 + 70
    im = Image.new('RGB', (W, 240), (40, 40, 40))
    def rgb(c): r, g, b = PAL16[c]; return (r * 17, g * 17, b * 17)
    x0 = 2
    for s in range(1, NSTYLE + 1):          # textures
        for v in range(32):
            for u in range(16):
                c = WCOL[s][0] if TEX[s][v][u] == '#' else C_BLACK
                im.putpixel((x0 + u, 2 + v), rgb(c))
        x0 += 18
    x0 = 2
    for i, (n, g) in enumerate(THINGS):
        col = [C_GREEN, C_GREEN, C_GREEN, C_BRICK, C_BRICK, C_BRICK, C_BRICKD, C_STONE, C_YELLOW][i]
        for y in range(48):
            for x in range(32):
                ch = g[y][x]
                if ch != '.': im.putpixel((x0 + x, 40 + y), rgb(col) if ch == '#' else (0, 0, 0))
        x0 += 36
    for f in (0, 1):
        g = gun_pic(f)
        for y in range(64):
            for x in range(64):
                grp, v = g[y][x]
                if v:
                    r, gg, b = GROUPS[grp][v]; im.putpixel((2 + f * 70 + x, 100 + y), (r * 17, gg * 17, b * 17))
    L = logo(); lc = logo_colours()
    for y in range(48):
        for x in range(240):
            if L[y][x]: im.putpixel((150 + x // 2, 180 + y // 2), rgb(lc[y] >> 4))
    im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
    im.save(os.path.join(HERE, 'art.png'))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'png': png()
    else: main()
