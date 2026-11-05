"""Generate breaker_data.inc for BYTE BREAKER: the sprite pictures (sent to
the terminal at start), the ball's speeds, the brick characters and the
levels.
    python gen.py > breaker_data.inc"""
import math

# ---- the pictures (the terminal's sprite layer, control code 1C) ----------
PAD = ['.##############.',
       '################',
       '.##############.']
WIDE = ['.######################.',
        '########################',
        '.######################.']
LASER = ['##............##',
         '################',
         '.##############.']
BALL = ['##',
        '##']
SHOT = ['#', '#', '#']
# capsules: an outline with a sign in it (wide, multi-ball, slow, laser,
# catch, extra ball)
SIGNS = {'W': ['#.#', '###', '#.#'],        # a wide bar  |-|
         'M': ['#.#', '...', '.#.'],        # three balls
         'S': ['...', '###', '...'],        # a calm line
         'L': ['#.#', '#.#', '#.#'],        # two beams
         'C': ['#.#', '#.#', '###'],        # a cup
         'X': ['.#.', '###', '.#.']}        # plus one
CAPS = 'WMSLCX'
def capsule(sign):
    g = SIGNS[sign]
    return ['.#####.'] + ['#.' + r + '.#' for r in g] + ['.#####.']

PICS = [('PIC_PAD', PAD), ('PIC_WIDE', WIDE), ('PIC_LASER', LASER), ('PIC_BALL', BALL), ('PIC_SHOT', SHOT)] + \
       [('PIC_CAP_' + c, capsule(c)) for c in CAPS]

def rows_bytes(rows):
    w = len(rows[0]); nb = (w + 7) // 8
    out = []
    for r in rows:
        r = r.ljust(nb * 8, '.')
        for k in range(nb):
            out.append(sum(0x80 >> i for i in range(8) if r[k * 8 + i] == '#'))
    return out

# ---- the ball's speeds: 8 speeds x 4 angles (30, 45, 60, 72 degrees from
# level), as x and y parts in 8.8 pixels a frame (signs are the game's) -----
NSPEED = 8
ANGLES = [30, 45, 60, 72]
def speed(l): return 1.3 + 0.16 * l

# ---- bricks: 4 characters each (block graphics: bit 0 top left, bit 1 top
# right, ... bit 7 bottom right); the bottom row and the last column are a gap
BRICK_CH = [[0x00, 0x00, 0x00, 0x00],       # 0 none
            [0x3F, 0x3F, 0x3F, 0x15],       # 1 one hit
            [0x37, 0x33, 0x33, 0x15],       # 2 two hits (an outline)
            [0x19, 0x26, 0x19, 0x11]]       # 3 steel (a check), never breaks
BW, BH = 19, 10                             # bricks across, rows

LEVELS = [
    ['...................',
     '...................',
     '1111111111111111111',
     '1111111111111111111',
     '1111111111111111111',
     '1111111111111111111',
     '1111111111111111111'],
    ['...................',
     '2222222222222222222',
     '1111111111111111111',
     '1111111111111111111',
     '.1111111111111111..',
     '..111111111111111..',
     '...1111111111111...',
     '....11111111111....'],
    ['...................',
     '1.1.1.1.1.1.1.1.1.1',
     '.1.1.1.1.1.1.1.1.1.',
     '2.2.2.2.2.2.2.2.2.2',
     '.1.1.1.1.1.1.1.1.1.',
     '1.1.1.1.1.1.1.1.1.1',
     '.2.2.2.2.2.2.2.2.2.',
     '1.1.1.1.1.1.1.1.1.1'],
    ['...................',
     '3333333.....3333333',
     '1111111.....1111111',
     '2222222.....2222222',
     '1111111.....1111111',
     '.......11111.......',
     '.......22222.......',
     '.......11111.......'],
    ['.........1.........',
     '........121........',
     '.......12221.......',
     '......1222221......',
     '.....122232221.....',
     '......1222221......',
     '.......12221.......',
     '........121........',
     '.........1.........'],
    ['2222222222222222222',
     '1.................1',
     '1.111111111111111.1',
     '1.1.............1.1',
     '1.1.11111111111.1.1',
     '1.1.1.........1.1.1',
     '1.1.1.3333333.1.1.1',
     '1...1.........1...1',
     '33333.........33333'],
    ['...................',
     '11..11..11..11..111',
     '11..11..11..11..111',
     '..22..22..22..22...',
     '..22..22..22..22...',
     '11..11..11..11..111',
     '11..11..11..11..111',
     '..33..........33...'],
    ['1111111111111111111',
     '2222222222222222222',
     '1111111111111111111',
     '3.....1.1.1.1.....3',
     '1111111111111111111',
     '2222222222222222222',
     '1111111111111111111',
     '...................',
     '...333.......333...'],
    ['...2...2...2...2...',
     '..212.212.212.212..',
     '.21112111211121112.',
     '..212.212.212.212..',
     '...2...2...2...2...',
     '...................',
     '1111111111111111111',
     '2222222222222222222',
     '3.3.3.3.3.3.3.3.3.3'],
    ['2222222222222222222',
     '2111111111111111112',
     '2122222222222222212',
     '2121111111111111212',
     '2121222222222221212',
     '2121211111111121212',
     '2121212222222121212',
     '2121212111112121212',
     '33.....33.33.....33'],
]
NLEVEL = len(LEVELS)

def level_bytes(lv):
    rows = lv + ['.' * BW] * (BH - len(lv))
    out = []
    for r in rows:
        assert len(r) == BW, r
        out += ['.123'.index(c) for c in r]
    return out

def bl(vals):
    return ', '.join('$%02X' % (v & 0xFF) for v in vals)

if __name__ == '__main__':
    print('; generated by gen.py')
    stream = [0x1C, 0x08]                   # CLEAR, then DEFINE each picture (no mask)
    for n, (name, rows) in enumerate(PICS):
        print('%-12s = %d' % (name, n))
        stream += [0x1C, 0x01, n, len(rows[0]), len(rows), 0] + rows_bytes(rows)
    print('PIC_CAP     = PIC_CAP_W')
    print('NCAPTYPE    = %d' % len(CAPS))
    print('SPR_DEFS    = %d' % len(stream))
    print('spr_defs:')
    for i in range(0, len(stream), 16): print('        .byte   ' + bl(stream[i:i + 16]))
    print('NSPEED      = %d' % NSPEED)
    vx = [round(speed(l) * math.cos(math.radians(a)) * 256) for l in range(NSPEED) for a in ANGLES]
    vy = [round(speed(l) * math.sin(math.radians(a)) * 256) for l in range(NSPEED) for a in ANGLES]
    print('; the ball: speed * 4 + angle -> x and y parts (8.8 pixels a frame)')
    print('vx_lo:  .byte   ' + bl([v & 255 for v in vx]))
    print('vx_hi:  .byte   ' + bl([v >> 8 for v in vx]))
    print('vy_lo:  .byte   ' + bl([v & 255 for v in vy]))
    print('vy_hi:  .byte   ' + bl([v >> 8 for v in vy]))
    print('brick_ch:   ; 4 characters for each kind of brick')
    for b in BRICK_CH: print('        .byte   ' + bl(b))
    print('BW          = %d' % BW)
    print('BH          = %d' % BH)
    print('NBRICK      = %d' % (BW * BH))
    print('NLEVEL      = %d' % NLEVEL)
    print('lv_lo:  .byte   ' + ', '.join('<(levels + %d)' % (i * BW * BH) for i in range(NLEVEL)))
    print('lv_hi:  .byte   ' + ', '.join('>(levels + %d)' % (i * BW * BH) for i in range(NLEVEL)))
    print('levels:     ; %d levels of %d x %d bricks (0 none, 1 one hit, 2 two hits, 3 steel)' % (NLEVEL, BW, BH))
    for lv in LEVELS:
        b = level_bytes(lv)
        for i in range(0, len(b), BW): print('        .byte   ' + ', '.join(str(x) for x in b[i:i + BW]))
