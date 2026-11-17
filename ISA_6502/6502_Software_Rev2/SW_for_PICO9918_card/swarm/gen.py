"""gen.py - the data for SWARM: the sine and arctangent tables and the
flight paths (the pictures are gen_pico.py's).      python gen.py > swarm_data.inc
                   python gen.py --png sheet.png   (a look at the pictures)"""
import math, sys

# ---- the art: 8 x 8, facing up (the way the player's ship goes) ------------
BEE = (['...##...',
        '..####..',
        '.#.##.#.',
        '########',
        '#.####.#',
        '..#..#..',
        '.#....#.'],
       ['...##...',
        '..####..',
        '...##...',
        '########',
        '#.####.#',
        '#.#..#.#',
        '..#..#..'])
BFLY = (['.#....#.',
         '..#..#..',
         '.######.',
         '##.##.##',
         '########',
         '##.##.##',
         '#..##..#'],
        ['.#....#.',
         '..#..#..',
         '..####..',
         '.#.##.#.',
         '########',
         '.######.',
         '..#..#..'])
BOSS = (['#..##..#',
         '#.####.#',
         '########',
         '.#.##.#.',
         '.######.',
         '#.####.#',
         '#..##..#'],
        ['...##...',
         '#.####.#',
         '########',
         '##.##.##',
         '.######.',
         '.#.##.#.',
         '#..##..#'])
HURT = (['#..##..#',             # a boss hit once: hollow
         '#.#..#.#',
         '##.##.##',
         '.#....#.',
         '.#.##.#.',
         '#.#..#.#',
         '#..##..#'],
        ['...##...',
         '#.#..#.#',
         '##.##.##',
         '#......#',
         '.#.##.#.',
         '.#.##.#.',
         '#..##..#'])
KINDS = [BEE, BFLY, BOSS, HURT]
SHIP = ['...#...',
        '...#...',
        '..###..',
        '#.###.#',
        '#######',
        '###.###',
        '##.#.##',
        '#..#..#']
BOOM = [['........',
         '........',
         '...#....',
         '..#.#...',
         '...#.#..',
         '....#...',
         '........',
         '........'],
        ['........',
         '.#...#..',
         '..#.#...',
         '.#.#.#..',
         '..#.#.#.',
         '.#...#..',
         '......#.',
         '........'],
        ['#..#...#',
         '.#....#.',
         '...#....',
         '#.....##',
         '.#..#...',
         '....#.#.',
         '.#.....#',
         '#...#...'],
        ['#......#',
         '........',
         '..#..#..',
         '........',
         '........',
         '..#..#..',
         '........',
         '#......#']]
PBOOM = [['...#....',
          '.#.#.#..',
          '..###...',
          '#######.',
          '..###...',
          '.#.#.#..',
          '...#....',
          '........'],
         ['#..#..#.',
          '.#.#.#..',
          '..#.#...',
          '###.###.',
          '..#.#...',
          '.#.#.#..',
          '#..#..#.',
          '........'],
         ['#...#...#'[:8],
          '........',
          '..#.#.#.',
          '#.......',
          '..#...#.',
          '........',
          '#.#.#.#.',
          '........']]


def px(rows): return {(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == '#'}


def rot45(p):
    """turned 45 degrees clockwise, by three shears (keeps the pixels)"""
    t, s = -math.tan(math.pi / 8), math.sin(math.pi / 4)
    out = set()
    for x, y in p:
        x, y = x - 3.5, y - 3.5
        x = round(x + t * y + 0.5) - 0.5
        y = round(y + s * x + 0.5) - 0.5
        x = round(x + t * y + 0.5) - 0.5
        X, Y = int(x + 3.5), int(y + 3.5)
        if 0 <= X < 8 and 0 <= Y < 8: out.add((X, Y))
    return out


def rot90(p): return {(7 - y, x) for x, y in p}
def vflip(p): return {(x, 7 - y) for x, y in p}
def vflip7(p): return {(x, 6 - y) for x, y in p}     # (7 rows: the gap stays at the bottom)


def dirs(p):
    """up, up-right, right, down-right, down"""
    ur = rot45(p)
    return [p, ur, rot90(p), vflip(ur), vflip7(p)]


# ---- the sprite pictures ---------------------------------------------------
PICS = []            # (name, w, h, pixel set)
for k, kind in enumerate(KINDS):
    for f in range(2):
        for d, q in enumerate(dirs(px(kind[f]))):
            PICS.append(('A%d_%d_%d' % (k, f, d), 8, 8, q))
PIC_ALIEN = 0
PICS.append(('SHIP', 7, 8, px(SHIP)))
PICS.append(('SHOT', 1, 4, {(0, y) for y in range(4)}))
PICS.append(('EBUL', 1, 3, {(0, y) for y in range(3)}))
for i, b in enumerate(BOOM): PICS.append(('BOOM%d' % i, 8, 8, px(b)))
for i, b in enumerate(PBOOM): PICS.append(('PBOOM%d' % i, 8, 8, px(b)))
PIC = {n: i for i, (n, w, h, q) in enumerate(PICS)}

# ---- the tiles: 6 x 2 characters (12 x 8 pixels), an alien facing down in
# the middle 8 columns.  0 blank, 1 + kind * 2 + frame, then the ship (the
# lives on row 23)
def tile(p, ox=2):
    cells = [0] * 12
    for x, y in p:
        X = x + ox
        cells[(y // 4) * 6 + X // 2] |= 1 << ((y % 4) * 2 + (X % 2))
    return cells
TILES = [[0] * 12]
for kind in KINDS:
    for f in range(2):
        TILES.append(tile(vflip7(px(kind[f]))))
TILES.append(tile(px(SHIP), 2))

# ---- flight paths: (frames, turn a frame) pieces, then what to do --------
# heading 0-63: 0 up, 16 right, 32 down, 48 left.  The second of each pair
# flies the mirror image (turns the other way, from the other side).
P_HOME, P_ATTACK, P_EXIT = 0xFF, 0xFE, 0xFD
PATHS = {
    # waves: coming in to the formation
    'top':    [(14, 0), (16, 2), (12, 1), P_HOME],          # down from the top, a loop out
    'side':   [(14, 0), (16, -2), P_HOME],         # in from low on the side, up round
    # leaving the formation to attack
    'dive':   [(4, 0), (16, -2), P_ATTACK],                  # up, over and down
    'dive2':  [(6, -1), (10, -3), (6, 0), P_ATTACK],
    # the challenging stage: across and away
    'b_loop': [(18, 0), (32, 2), (30, 0), P_EXIT],
    'b_wave': [(8, 0), (8, 2), (8, -2), (8, -2), (8, 2), (8, 2), (8, -2), (8, -2), (8, 2), (30, 0), P_EXIT],
    'b_dip':  [(16, 0), (16, -1), (20, 2), (40, 0), P_EXIT],
    'b_arc':  [(10, 0), (32, 1), (40, 0), P_EXIT],
}
# where each path starts (x, y in wire coordinates: + 32; the field's
# pixels are x 32-191, y 36-127) and its heading; the mirror starts at
# 2 * 112 - x - 8 (the field's middle is x 112), heading 64 - h
START = {
    'top':    (96, 20, 32),
    'side':   (16, 104, 16),
    'b_loop': (96, 20, 32),
    'b_wave': (12, 50, 18),
    'b_dip':  (60, 20, 36),
    'b_arc':  (12, 100, 4),
}


def bl(v): return ', '.join('$%02X' % (x & 255) for x in v)


def main():
    print('; generated by gen.py')
    print('sin_tab:        ; sin(2 pi h / 64) * 127, h = 0 .. 79 (cos h = sin(h + 16))')
    s = [round(127 * math.sin(2 * math.pi * h / 64)) for h in range(80)]
    for i in range(0, 80, 16): print('        .byte   ' + bl(s[i:i + 16]))
    print('atan_tab:       ; atan(t / 16) in 64ths of a turn, t = 0 .. 16')
    print('        .byte   ' + bl([round(math.atan(t / 16) * 64 / (2 * math.pi)) for t in range(17)]))
    # (the pictures and tiles for the old terminal's sprite layer are gone: the
    # PICO9918 version's are in gen_pico.py)
    # paths
    names = list(PATHS)
    print('; flight paths: frames, turn ... then $FF home, $FE attack, $FD away')
    for i, n in enumerate(names): print('PATH_%-8s = %d' % (n.upper(), i))
    print('path_lo:        .byte   ' + ', '.join('<path_%s' % n for n in names))
    print('path_hi:        .byte   ' + ', '.join('>path_%s' % n for n in names))
    for n in names:
        b = []
        for p in PATHS[n]:
            b += [p] if isinstance(p, int) else [p[0], p[1]]
        print('path_%s:  .byte   %s' % (n, bl(b)))
    sn = [n for n in names if n in START]
    print('path_sx:        .byte   ' + bl([START[n][0] if n in START else 0 for n in names]))
    print('path_sy:        .byte   ' + bl([START[n][1] if n in START else 0 for n in names]))
    print('path_sh:        .byte   ' + bl([START[n][2] if n in START else 0 for n in names]))


def sheet(fn):
    from PIL import Image, ImageDraw
    S = 6
    im = Image.new('RGB', (10 * 10 * S, 8 * 12 * S), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, (n, w, h, q) in enumerate(PICS):
        ox, oy = (i % 10) * 10 * S, (i // 10) * 10 * S
        d.rectangle([ox - 1, oy - 1, ox + 8 * S, oy + 8 * S], outline=(60, 60, 60))
        for x, y in q: d.rectangle([ox + x * S, oy + y * S, ox + x * S + S - 1, oy + y * S + S - 1], fill=(90, 255, 90))
    for i, t in enumerate(TILES):
        ox, oy = (i % 6) * 14 * S, 60 * S + (i // 6) * 10 * S
        for c in range(12):
            for b in range(8):
                if t[c] >> b & 1:
                    x, y = (c % 6) * 2 + (b & 1), (c // 6) * 4 + b // 2
                    d.rectangle([ox + x * S, oy + y * S, ox + x * S + S - 1, oy + y * S + S - 1], fill=(255, 200, 90))
        d.rectangle([ox - 1, oy - 1, ox + 12 * S, oy + 8 * S], outline=(60, 60, 60))
    im.save(fn)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--png': sheet(sys.argv[2])
    else: main()
