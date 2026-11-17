"""Generate tables.inc for the 6502 DOOM engine: maths tables, wall shading
patterns and sprites.  Run:  python3 gen_tables.py > tables.inc"""
import math

COLS = 80                   # screen columns (one ray each)
VROWS = 18                  # text rows in the 3D view
VH = VROWS * 4              # view height in pixels (72)
HORIZON = VH // 2           # 36
FOV = 66.0                  # degrees
HALF_TAN = math.tan(math.radians(FOV / 2))
FOCAL = (COLS / 2) / HALF_TAN   # columns per unit of lateral/depth (~61.6)
WALL_K = 60.0               # wall height in pixels at a distance of 1 tile
ANG = 1024                  # angle units per circle

def col_angle(c):
    x = ((c + 0.5) - COLS / 2) / (COLS / 2)
    return math.atan(x * HALF_TAN)

def wall_h(idx):            # idx = perpendicular distance in 1/32 tile
    if idx == 0: return VH
    return min(VH, int(round(WALL_K * 32 / idx)))

def mosaic(rows):
    """4x4 drawing (2 characters) or 2x4 drawing (1 character) -> bytes"""
    w = len(rows[0]); out = []
    for c in range(w // 2):
        b = 0
        for k in range(4):
            if rows[k][2 * c] == '#': b |= 1 << (2 * k)
            if rows[k][2 * c + 1] == '#': b |= 1 << (2 * k + 1)
        out.append(b)
    return out

def bytes_line(vals, per=16):
    out = []
    for i in range(0, len(vals), per):
        out.append('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + per]))
    return '\n'.join(out)

# ---- wall patterns: [style][side][band] (one character, 2x4 pixels) ---------
# bands by distance: 0 near ... 3 far.  Side 1 (walls facing north/south) is
# drawn a shade lighter than side 0 so corners read.
P = lambda *rows: mosaic(list(rows))[0]
# Walls are kept plain so that doors and the exit stand out: every wall type
# is the same dither, lighter on side 1 and sparser with distance.  Doors are
# solid, the exit switch is solid with dark horizontal bars.
CHECK = P('#.', '.#', '#.', '.#')       # 50 %
DOTS = P('#.', '..', '.#', '..')        # 25 %
FEW = P('#.', '..', '..', '..')         # 12 %
WALL = [[CHECK, CHECK, DOTS, FEW],      # side 0, bands near .. far
        [DOTS, DOTS, FEW, FEW]]         # side 1
SOLID = P('##', '##', '##', '##')
BARS = P('##', '..', '##', '..')
PAT = {
    1: WALL, 2: WALL, 3: WALL,
    4: [[SOLID] * 4, [SOLID] * 4],      # door
    5: [[BARS] * 4, [BARS] * 4],        # exit switch
}
NSTYLE = 5
FLOOR = [0] * VROWS            # plain black floor and ceiling

# ---- sprites: 8x8 shape mask + fill, per frame ------------------------------
def sprite(art):
    """art: 8 strings of 8: '#' lit, '+' dark but solid (part of the shape), '.' see-through"""
    mask = []; fill = []
    for row in art:
        m = f = 0
        for i, ch in enumerate(row):
            if ch in '#+': m |= 1 << i
            if ch == '#': f |= 1 << i
        mask.append(m); fill.append(f)
    return mask, fill

SPRITES = [  # index = sprite number
    ('SPR_GRUNT1', ['..####..', '.#+##+#.', '..####..', '.######.', '#.####.#', '#.####.#', '..#..#..', '.##..##.']),
    ('SPR_GRUNT2', ['..####..', '.#+##+#.', '..####..', '.######.', '#.####.#', '#.####.#', '..#..#..', '..#..##.']),
    ('SPR_GRUNTF', ['..####..', '.#+##+#.', '..####..', '########', '..####.#', '..####..', '..#..#..', '.##..##.']),
    ('SPR_BRUTE1', ['.######.', '##+##+##', '########', '#.####.#', '########', '########', '.##..##.', '.##..##.']),
    ('SPR_BRUTE2', ['.######.', '##+##+##', '########', '#.####.#', '########', '########', '.##..##.', '##....##']),
    ('SPR_BRUTEF', ['.######.', '##+##+##', '###++###', '#.####.#', '########', '########', '.##..##.', '.##..##.']),
    ('SPR_DEAD',   ['........', '........', '........', '........', '........', '..#..#..', '.######.', '########']),
    ('SPR_MEDKIT', ['........', '........', '........', '.######.', '.##++##.', '.#++++#.', '.##++##.', '.######.']),
    ('SPR_AMMO',   ['........', '........', '........', '........', '.#.#.#..', '.#.#.#..', '.#####..', '.#####..']),
]

# ---- the gun (8 characters x 4 rows = 16 x 16 pixels) -------------------------
GUN = [
    ['................', '................', '................', '................',
     '................', '.......##.......', '.......##.......', '......####......',
     '......####......', '.....##++##.....', '.....######.....', '....##++++##....',
     '....########....', '...####++####...', '...##########...', '..############..'],
    ['......#..#......', '...#..####..#...', '....########....', '..#..######..#..',
     '....##....##....', '.......##.......', '.......##.......', '......####......',
     '......####......', '.....##++##.....', '.....######.....', '....##++++##....',
     '....########....', '...####++####...', '...##########...', '..############..'],
]

def gun_cells(art):
    """-> list of (mask, fill) for 4 rows x 8 columns of characters"""
    cells = []
    for r in range(4):
        for c in range(8):
            m = f = 0
            for k in range(4):
                for j in range(2):
                    ch = art[r * 4 + k][c * 2 + j]
                    bit = 1 << (2 * k + j)
                    if ch in '#+': m |= bit
                    if ch == '#': f |= bit
            cells.append((m, f))
    return cells

# ---- big title letters (my own blocky font, 6x8 pixels per letter) ------------
FONT = {
    'D': ['#####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '#####.'],
    'O': ['.####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    'M': ['#....#', '##..##', '######', '##..##', '##..##', '##..##', '##..##', '##..##'],
    '6': ['.####.', '##....', '##....', '#####.', '##..##', '##..##', '##..##', '.####.'],
    '5': ['######', '##....', '##....', '#####.', '....##', '....##', '##..##', '.####.'],
    '0': ['.####.', '##..##', '##.###', '######', '###.##', '##..##', '##..##', '.####.'],
    '2': ['.####.', '##..##', '....##', '...##.', '..##..', '.##...', '##....', '######'],
    ' ': ['......'] * 8,
}

def banner(text, scale=2):
    """text -> rows of characters (block graphics), each letter 6x8 px scaled"""
    px = []
    for y in range(8 * scale):
        line = ''
        for ch in text:
            row = FONT[ch][y // scale]
            line += ''.join(c * scale for c in row) + '.' * scale
        px.append(line)
    w = len(px[0]) + (len(px[0]) % 2)
    px = [p.ljust(w, '.') for p in px]
    rows = []
    for r in range(len(px) // 4):
        rows.append(mosaic(px[r * 4:r * 4 + 4]))
    return rows

def main():
    print('; generated by gen_tables.py - do not edit')
    print('COLS = %d' % COLS)
    print('VROWS = %d' % VROWS)
    print('VH = %d' % VH)
    print('HORIZON = %d' % HORIZON)
    print('FOCAL = %d' % round(FOCAL))
    print('NSTYLE = %d' % NSTYLE)
    print()
    print('; sin, 1024 steps per circle, signed, 127 = 1.0')
    print('sin_tab:')
    print(bytes_line([int(round(127 * math.sin(2 * math.pi * a / ANG))) for a in range(ANG)]))
    print('; |1/cos| for 0..90 degrees (257 entries), 8.8 fixed point, capped')
    inv = []
    for r in range(257):
        c = math.cos(2 * math.pi * r / ANG)
        v = 0x7FFF if c < 1e-6 else min(0x7FFF, int(round(256 / c)))
        inv.append(v)
    print('invc_lo:'); print(bytes_line([v & 0xFF for v in inv]))
    print('invc_hi:'); print(bytes_line([v >> 8 for v in inv]))
    offs = [int(round(col_angle(c) * ANG / (2 * math.pi))) for c in range(COLS)]
    print('; angle offset of each column (signed, 1024 units)')
    print('coloff_lo:'); print(bytes_line([o & 0xFF for o in offs]))
    print('coloff_hi:'); print(bytes_line([(o >> 8) & 0xFF for o in offs]))
    print('; cos of each column offset, 0..255 (fish-eye correction)')
    print('cosfix:'); print(bytes_line([min(255, int(round(256 * math.cos(2 * math.pi * o / ANG)))) for o in offs]))
    print('; wall height in pixels for a distance in 1/32 tile (0..1023)')
    print('htab:'); print(bytes_line([wall_h(i) for i in range(1024)]))
    print('; quarter squares for multiplying: n*n/4 for n = 0..511')
    sq = [n * n // 4 for n in range(512)]
    print('sq_lo:'); print(bytes_line([v & 0xFF for v in sq[:256]]))
    print('sq_hi:'); print(bytes_line([v >> 8 for v in sq[:256]]))
    print('sq2_lo:'); print(bytes_line([v & 0xFF for v in sq[256:]]))
    print('sq2_hi:'); print(bytes_line([v >> 8 for v in sq[256:]]))
    print('; 8*256/n for scaling 8 pixel sprites (n = 1..255; 0 -> max)')
    rec = [0xFFFF] + [min(0xFFFF, int(round(8 * 256 / n))) for n in range(1, 256)]
    print('rec_lo:'); print(bytes_line([v & 0xFF for v in rec]))
    print('rec_hi:'); print(bytes_line([v >> 8 for v in rec]))
    print('; wall patterns [style 1..5][side][band 0..3] (style 0 unused)')
    print('wallpat:')
    print(bytes_line([0] * 8))
    for s in range(1, NSTYLE + 1):
        print(bytes_line(PAT[s][0] + PAT[s][1]))
    print('floorpat:'); print(bytes_line(FLOOR))
    print('; sprites: 8 rows of shape mask then 8 rows of fill, bit 0 = left')
    for i, (name, art) in enumerate(SPRITES):
        print('%s = %d' % (name, i))
    print('spr_data:')
    for name, art in SPRITES:
        m, f = sprite(art)
        print(bytes_line(m + f) + '   ; ' + name)
    for g, art in enumerate(GUN):
        cells = gun_cells(art)
        print('gun%d_mask:' % g); print(bytes_line([m for m, f in cells], 8))
        print('gun%d_fill:' % g); print(bytes_line([f for m, f in cells], 8))
    rows = banner('DOOM')
    print('BANNER_W = %d' % len(rows[0]))
    print('BANNER_H = %d' % len(rows))
    print('banner:')
    for r in rows: print(bytes_line(r, 40))

if __name__ == '__main__':
    main()
