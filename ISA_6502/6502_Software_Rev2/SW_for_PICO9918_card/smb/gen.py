"""Generate the data for SUPER MOS BROS.:

    python gen.py            writes smb_data.inc (tiles, sprites, title banner)
                             and WORLD1.SMB ... WORLD5.SMB (a file for each
                             world, loaded from the USB drive with SBC_LOAD as
                             each of its levels starts)

The levels themselves are designed in levels.py."""
import sys, os

# ---- tiles: 8 x 8 pixels = 4 x 2 block graphics characters ----------------------
# (name, map character, solid, picture).  Textures that repeat every 2 pixels
# across (the ground, bricks, walls) look the same after a scroll: cheap to send.
DITHER = ['#.#.#.#.', '.#.#.#.#']
TILES = [
    ('EMPTY', ' ', 0, ['........'] * 8),
    ('GROUND', '#', 1, ['########'] + DITHER * 3 + ['#.#.#.#.']),
    ('BRICK', 'B', 1, ['########', '........'] * 4),
    ('QCOIN', '?', 1, ['########', '#..##..#', '#.#..#.#', '#....#.#', '#...#..#', '#......#', '#...#..#', '########']),
    ('QMUSH', 'M', 1, ['########', '#..##..#', '#.#..#.#', '#....#.#', '#...#..#', '#......#', '#...#..#', '########']),
    ('USED', 'U', 1, ['########'] + ['#......#'] * 6 + ['########']),
    ('HARD', 'H', 1, ['########'] * 8),
    ('PIPETL', '[', 1, ['########', '#.......', '#.......', '#.......', '########', '.#......', '.#......', '.#......']),
    ('PIPETR', ']', 1, ['########', '.......#', '.......#', '.......#', '########', '......#.', '......#.', '......#.']),
    ('PIPEL', '{', 1, ['.#......'] * 8),
    ('PIPER', '}', 1, ['......#.'] * 8),
    ('COIN', 'o', 0, ['........', '..###...', '.#...#..', '.#.#.#..', '.#.#.#..', '.#...#..', '..###...', '........']),
    ('POLE', '|', 0, ['...##...'] * 8),
    ('POLETOP', '^', 0, ['..####..', '.######.', '.######.', '..####..', '...##...', '...##...', '...##...', '...##...']),
    ('LEDGE', 'L', 1, ['########', '########'] + DITHER * 2 + ['#.#.#.#.', '########']),
    ('HIDDEN', '*', 0, ['........'] * 8),        # solid only to a head from below
    ('WALL', 'W', 1, ['########', '........', '#.#.#.#.', '.#.#.#.#', '########', '........', '########', '.#.#.#.#']),
    ('LAVA', 'v', 0, ['........', '........', '........', '#.#.#.#.', '.#.#.#.#', '########', '########', '########']),
    ('BRIDGE', '=', 1, ['########', '.#.#.#.#', '########', '........', '........', '........', '........', '........']),
    ('RESET', 'R', 0, ['........', '..####..', '..#..#..', '.######.', '.######.', '########', '#.####.#', '########']),
    # scenery: a resistor and a capacitor in the sky, chips and transistors on the ground
    ('RESL', 'r', 0, ['........', '....#...', '...#.#..', '##.#..#.', '..#...#.', '......#.', '.......#', '........']),
    ('RESR', 's', 0, ['........', '..#.....', '.#.#....', '#...#.##', '#....#..', '#.......', '........', '........']),
    ('CAP', 'p', 0, ['........', '..#..#..', '..#..#..', '###..###', '..#..#..', '..#..#..', '........', '........']),
    ('DIPL', 'b', 0, ['........', '........', '.#######', '.#..####', '.#..####', '.#######', '.#.#.#.#', '.#.#.#.#']),
    ('DIPR', 'd', 0, ['........', '........', '#######.', '#######.', '#######.', '#######.', '.#.#.#..', '.#.#.#..']),
    # pipes into a bonus room (they look like any pipe), the overclock block,
    # and the liquid cooling levels: the surface, and heat sink fins
    ('PIPEINL', '<', 1, ['########', '#.......', '#.......', '#.......', '########', '.#......', '.#......', '.#......']),
    ('PIPEINR', '>', 1, ['########', '.......#', '.......#', '.......#', '########', '......#.', '......#.', '......#.']),
    ('QOC', 'O', 1, ['########', '#..##..#', '#.#..#.#', '#....#.#', '#...#..#', '#......#', '#...#..#', '########']),
    ('SURFACE', 'w', 0, ['........', '##....##', '..####..', '........', '........', '........', '........', '........']),
    ('FINS', 'f', 1, ['#.#.#.#.'] * 8),
    ('BUBBLE', 'u', 0, ['........', '......#.', '.....#.#', '......#.', '..#.....', '.#.#....', '..#.....', '........']),
    ('TRANS', 't', 0, ['........', '..####..', '.######.', '.######.', '.######.', '.######.', '..#.#.#.', '..#.#.#.']),
]

def digit_flag():
    """the flag: 16 x 8, "6502" cut out of it"""
    font = {'6': ['###', '#..', '###', '#.#', '###'], '5': ['###', '#..', '###', '..#', '###'],
            '0': ['###', '#.#', '#.#', '#.#', '###'], '2': ['###', '..#', '###', '#..', '###']}
    rows = [['#'] * 16 for _ in range(7)] + [['.'] * 16]
    for i, d in enumerate('6502'):
        for y in range(5):
            for x in range(3):
                if font[d][y][x] == '#': rows[1 + y][1 + i * 4 + x] = '.'
    rows = [''.join(r) for r in rows]
    return [r[:8] for r in rows], [r[8:] for r in rows]
fl, fr = digit_flag()
TILES += [('FLAGL', 'F', 0, fl), ('FLAGR', 'G', 0, fr)]

def chip_castle():
    """the end of a level: a 40 pin chip, 40 x 40 pixels, with "6502" on it and a door"""
    W = H = 40
    p = [['.'] * W for _ in range(H)]
    for y in range(4, H):                       # the body
        for x in range(6, 34): p[y][x] = '#'
    for y in range(6, H - 1, 4):                # the pins
        for x in list(range(1, 6)) + list(range(34, 39)):
            p[y][x] = p[y + 1][x] = '#'
    for y in range(4, 7):                       # the notch
        for x in range(18, 22):
            if (x - 19.5) ** 2 + (y - 4) ** 2 < 6: p[y][x] = '.'
    font = {'6': ['###', '#..', '###', '#.#', '###'], '5': ['###', '#..', '###', '..#', '###'],
            '0': ['###', '#.#', '#.#', '#.#', '###'], '2': ['###', '..#', '###', '#..', '###']}
    for i, d in enumerate('6502'):              # the label, cut out
        for y in range(5):
            for x in range(3):
                if font[d][y][x] == '#': p[12 + y][12 + i * 4 + x] = '.'
    for y in range(26, H):                      # the door: an arch, framed
        for x in range(17, 23):
            if y > 27 or 18 <= x <= 21: p[y][x] = '.'
    return [''.join(r) for r in p]
CASTLE = chip_castle()
CHIP = []                                       # 5 x 5 tile numbers
for ty in range(5):
    row = []
    for tx in range(5):
        pic = [CASTLE[ty * 8 + y][tx * 8:tx * 8 + 8] for y in range(8)]
        name = 'DOOR' if (tx, ty) == (2, 4) else None
        for i, t in enumerate(TILES):
            if t[3] == pic and name is None and (t[0].startswith('CHIP') or t[0] == 'EMPTY'):
                row.append(i); break
        else:
            TILES.append((name or 'CHIP%d' % len(TILES), None, 0, pic))
            row.append(len(TILES) - 1)
    CHIP.append(row)
TCHAR = {t[1]: i for i, t in enumerate(TILES) if t[1]}
T = {t[0]: i for i, t in enumerate(TILES)}
assert len(TILES) <= 64, len(TILES)

def tile_chars(rows):
    """8 x 8 pixels -> 8 characters: row 0 (4 chars) then row 1"""
    out = []
    for cr in range(2):
        for cc in range(4):
            b = 0
            for k in range(4):
                for j in range(2):
                    if rows[cr * 4 + k][cc * 2 + j] == '#': b |= 1 << (2 * k + j)
            out.append(b)
    return out

# ---- sprites ('#' drawn, '+' part of the shape but black) ---------------------------
# They face right (the dragon and its fire: left); the game mirrors them.
SPR = {
    'MOS_STAND': ['...###..', '..#####.', '..##+#+.', '..#####.', '...##...', '..####..', '..#++#..', '.##..##.'],
    'MOS_WALK1': ['...###..', '..#####.', '..##+#+.', '..#####.', '...##...', '..####..', '.##++#..', '.#...##.'],
    'MOS_WALK2': ['...###..', '..#####.', '..##+#+.', '..#####.', '...##...', '..####..', '..#++##.', '..##.#..'],
    'MOS_JUMP':  ['...###.#', '..######', '..##+#+.', '..#####.', '.####...', '#.###...', '..#++#..', '.##...#.'],
    'MOS_DEAD':  ['..####..', '.######.', '.#+##+#.', '.######.', '#.####.#', '#.####.#', '..#..#..', '.##..##.'],
    'BIG_STAND': ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '..####..', '...##...', '.######.',
                  '#.####.#', '#.####.#', '..####..', '..#++#..', '..#..#..', '..#..#..', '.##..##.', '.##..##.'],
    'BIG_WALK1': ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '..####..', '...##...', '.######.',
                  '#.####.#', '..####.#', '..####..', '.##++#..', '.##..##.', '.#....#.', '##....##', '#......#'],
    'BIG_WALK2': ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '..####..', '...##...', '.######.',
                  '#.####.#', '#.####..', '..####..', '..#++##.', '..##.#..', '..##.#..', '..##.##.', '...#....'],
    'BIG_JUMP':  ['...###.#', '..######', '.#######', '..##+#+.', '..#####.', '..####..', '.###....', '#.####..',
                  '..####..', '..####..', '..####..', '..#++#..', '.##..##.', '##....#.', '#.....##', '.......#'],
    # the enemies: an AND gate and an OR gate, output up, walking on their input pins
    'AND1':      ['...##...', '..####..', '.#++++#.', '#+#++#+#', '#++++++#', '########', '.#....#.', '.#......'],
    'AND2':      ['...##...', '..####..', '.#++++#.', '#+#++#+#', '#++++++#', '########', '.#....#.', '......#.'],
    'AND_FLAT':  ['........', '........', '........', '........', '........', '..####..', '#+#++#+#', '########'],
    'OR1':       ['...##...', '..#++#..', '.#++++#.', '#+#++#+#', '#++++++#', '##+##+##', '#..##..#', '.#......'],
    'OR2':       ['...##...', '..#++#..', '.#++++#.', '#+#++#+#', '#++++++#', '##+##+##', '#..##..#', '......#.'],
    'OR_SHELL':  ['........', '........', '...##...', '..#++#..', '.#+##+#.', '#++++++#', '##+##+##', '#......#'],
    'MUSH':      ['..####..', '.#+##+#.', '########', '#+#..#+#', '.######.', '..#..#..', '..#..#..', '..####..'],
    'ONEUP':     ['..####..', '.##++##.', '##++++##', '########', '.######.', '..#..#..', '..#..#..', '..####..'],
    'FLOWER':    ['.##..##.', '#+#..#+#', '.######.', '..####..', '...##...', '##.##.##', '.#.##.#.', '..####..'],
    'COINPOP':   ['..##....', '.#..#...', '.#.##...', '.#.##...', '.#.##...', '.#.##...', '.#..#...', '..##....'],
    'FIREBALL1': ['.##.', '####', '####', '.##.'],
    'FIREBALL2': ['#..#', '.##.', '.##.', '#..#'],
    'DRAGON1':   ['....##..........', '...####.........', '..##+###........', '.#######...#....',
                  '########..###...', '#..#####.#####..', '....###########.', '...#############',
                  '..##############', '..#############.', '..############..', '...##########...',
                  '...###....###...', '...##......##...', '..###.....###...', '..###.....###...'],
    'DRAGON2':   ['....##..........', '...####.........', '..##+###........', '.#######...#....',
                  '#######...###...', '........######..', '#...############', '...#############',
                  '..##############', '..#############.', '..############..', '...##########...',
                  '....###..###....', '....##....##....', '...###...###....', '...###...###....'],
    'BREATH':    ['...#####', '.#######', '########', '..######'],
    # liquid cooling: the gates swim on their sides; fans fly; the cloud throws gates
    'FISH1':     ['..####..', '.#+++#..', '##+#+###', '.#+++#..', '.#+++###', '..####..'],
    'FISH2':     ['..####..', '.#+++#.#', '##+#+##.', '.#+++#..', '.#+++##.', '..####.#'],
    'FAN1':      ['.######.', '#..##..#', '#..##..#', '########', '########', '#..##..#', '#..##..#', '.######.'],
    'FAN2':      ['.######.', '##....##', '#.#..#.#', '#..##..#', '#..##..#', '#.#..#.#', '##....##', '.######.'],
    'CLOUD':     ['....#####.......', '..#########.###.', '.##+#####+######', '################',
                  '#####++++#######', '.##############.', '..############..', '....#..#..#..#..'],
    'OC':        ['.#.#.#.#', '########', '#++#+++#', '#+#++++#', '#++++#+#', '#+++#++#', '########', '.#.#.#.#'],
    'PRINCESS':  ['#.#.#.#.', '#######.', '.#####..', '.#+#+#..', '.#####..', '..###...', '.#####..', '#######.',
                  '#.###.#.', '.#####..', '#######.', '#+#+#+#.', '#######.', '########', '########', '.#...#..'],
    # ducking
    # swimming: arms out, legs together (the stand picture for a kick)
    'MOS_SWIM':  ['...###..', '..#####.', '..##+#+.', '..#####.', '#.####.#', '.######.', '..#++#..', '...##...'],
    'BIG_SWIM':  ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '..####..', '...##...', '.######.',
                  '#.####.#', '#.####.#', '..####..', '..#++#..', '..####..', '...##...', '...##...', '..####..'],
    'MOS_DUCK':  ['...###..', '..##+#+.', '..#####.', '.######.', '.##..##.'],
    'BIG_DUCK':  ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '#.####.#', '.######.', '.##..##.'],
    'FIRE_DUCK': ['...###..', '..#####.', '.#######', '..##+#+.', '..#####.', '#.#++#.#', '.##++##.', '.##..##.'],
}
# the fire flower's MOS: big, with dark overalls
for k in ('STAND', 'WALK1', 'WALK2', 'JUMP', 'SWIM'):
    rows = [list(r) for r in SPR['BIG_' + k]]
    for y in range(8, 11):
        for x in (3, 4):
            if rows[y][x] == '#': rows[y][x] = '+'
    SPR['FIRE_' + k] = [''.join(r) for r in rows]
ORDER = ['MOS_STAND', 'MOS_WALK1', 'MOS_WALK2', 'MOS_JUMP', 'MOS_DEAD',
         'BIG_STAND', 'BIG_WALK1', 'BIG_WALK2', 'BIG_JUMP',
         'FIRE_STAND', 'FIRE_WALK1', 'FIRE_WALK2', 'FIRE_JUMP',
         'AND1', 'AND2', 'AND_FLAT', 'OR1', 'OR2', 'OR_SHELL', 'MUSH', 'ONEUP', 'FLOWER', 'COINPOP',
         'FIREBALL1', 'FIREBALL2', 'DRAGON1', 'DRAGON2', 'BREATH', 'MOS_DUCK', 'BIG_DUCK', 'FIRE_DUCK',
         'FISH1', 'FISH2', 'FAN1', 'FAN2', 'CLOUD', 'OC', 'PRINCESS', 'MOS_SWIM', 'BIG_SWIM', 'FIRE_SWIM']
assert sorted(ORDER) == sorted(SPR), set(SPR) ^ set(ORDER)

def silhouette(rows):
    """the mask: every pixel of the shape plus the holes inside it, row by row"""
    out = []
    for r in rows:
        xs = [i for i, ch in enumerate(r) if ch != '.']
        out.append(''.join('#' if xs and xs[0] <= i <= xs[-1] else '.' for i in range(len(r))))
    return out

# ---- the pictures for the terminal's sprite layer (SMB.BIN) ------------------------
# SMBSPR.SMB is sent to the terminal as it is: CLEAR (1C 08), then a DEFINE
# (1C 01 n w h 1, the bits, the mask) for each picture, n = its SP_ number.
# Bits: '#' lit; mask: the silhouette (inside it, '+' and '.' are dark).
def pic_rows(rows):
    nb = (len(rows[0]) + 7) // 8
    out = []
    for r in rows:
        r = r.ljust(nb * 8, '.')
        out += [sum(0x80 >> i for i, ch in enumerate(r[k * 8:k * 8 + 8]) if ch == '#') for k in range(nb)]
    return out

def spr_file():
    out = [0x1C, 0x08]
    for n, name in enumerate(ORDER):
        rows = SPR[name]
        out += [0x1C, 0x01, n, len(rows[0]), len(rows), 1] + pic_rows(rows) + pic_rows(silhouette(rows))
    for slot, trow, c0, cols, data in banner_tiles(BANNER):  # the title, as terminal tiles
        out += [0x19, slot, cols, 4] + data
    return out

def pool_bytes():
    return sum(len(SPR[n]) * ((len(SPR[n][0]) + 7) // 8) * 2 for n in ORDER)

def render(rows, ax):
    """sprite at x alignment ax (0/1), top on a cell row -> w, h and
    (mask, bits) per cell, column by column (the game shifts it down 0-3 rows
    and mirrors it as it draws)"""
    sil = silhouette(rows)
    h, wpx = len(rows), len(rows[0])
    w = (ax + wpx + 1) // 2
    hh = (h + 3) // 4
    cells = []
    for cc in range(w):
        for cr in range(hh):
            m = b = 0
            for k in range(4):
                for j in range(2):
                    x, y = cc * 2 + j - ax, cr * 4 + k
                    if 0 <= x < wpx and 0 <= y < h:
                        bit = 1 << (2 * k + j)
                        if sil[y][x] == '#': m |= bit
                        if rows[y][x] == '#': b |= bit
            cells += [m, b]
    return w, hh, cells

def mirror_byte(b):
    """a block character mirrored left to right"""
    o = 0
    for k in range(4):
        if b >> (2 * k) & 1: o |= 1 << (2 * k + 1)
        if b >> (2 * k + 1) & 1: o |= 1 << (2 * k)
    return o

# ---- the title banner ------------------------------------------------------------
FONT = {
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
    'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
    ' ': ['.....'] * 7,
}

def banner(lines):
    """big letters (each font pixel 2 x 2) -> rows of block characters:
    (text row, first column, count, characters...) ... 0"""
    out = []
    for text, trow in lines:
        w = len(text) * 12 - 2
        pix = [[0] * w for _ in range(16)]
        for i, ch in enumerate(text):
            for y, r in enumerate(FONT[ch]):
                for x, c in enumerate(r):
                    if c == '#':
                        for dy in range(2):
                            for dx in range(2): pix[1 + y * 2 + dy][i * 12 + x * 2 + dx] = 1
        cols = (w + 1) // 2
        c0 = 40 - cols // 2
        for cr in range(4):
            chars = []
            for cc in range(cols):
                b = 0
                for k in range(4):
                    for j in range(2):
                        x = cc * 2 + j
                        if x < w and pix[cr * 4 + k][x]: b |= 1 << (2 * k + j)
                chars.append(b)
            out += [trow + cr, c0, len(chars)] + chars
    return out + [0]

BANNER = [('SUPER', 2), ('MOS BROS.', 7)]

def banner_tiles(lines):
    """SMB.BIN: each banner line is a terminal tile (19 SET TILE), sent with the
    sprite pictures in SMBSPR.SMB: (slot, text row, first column, columns,
    the characters row by row).  A slot starts at slot x its size in the
    terminal's 512 byte pool, so the slots are chosen not to overlap."""
    b = banner(lines)
    rows, i = [], 0
    while b[i]:
        rows.append((b[i], b[i + 1], b[i + 3:i + 3 + b[i + 2]]))
        i += 3 + b[i + 2]
    out, used = [], 0
    for k in range(0, len(rows), 4):
        trow, c0, _ = rows[k]
        data = [x for r in rows[k:k + 4] for x in r[2]]
        size = len(data)
        slot = (used + size - 1) // size
        used = (slot + 1) * size
        assert used <= 512 and slot < 128
        out.append((slot, trow, c0, len(rows[k][2]), data))
    return out

# ---- worlds: the level format (the same in RAM and in the files) ------------------
#   one file per world, WORLDn.SMB: "SM", 2, number of levels, then 2 byte
#   offsets of the levels from the start of the file, then the levels
#   level: width, start x, start y, time (BCD, 2 bytes), flags (1: castle,
#          2: under the coolant, 4: the last level, 8: the last of its world),
#          bonus room's first column, its exit pipe,
#          11 rows of (count, tile * 4) ... 0, then enemies (column, row, type) ... $FF
ENEMY_TYPES = {'and': 1, 'or': 2, 'dragon': 3, 'fish': 4, 'fan': 5, 'cloud': 6, 'princess': 7, 'fanhi': 8, 'wfish': 9}

def rle(row):
    out = []; i = 0
    while i < len(row):
        j = i
        while j < len(row) and row[j] == row[i] and j - i < 255: j += 1
        out += [j - i, row[i]]; i = j
    return out + [0]

def level_bytes(v, last=False):
    w = v.w
    assert w <= 255, v.name
    t = '%04d' % v.time
    flags = (1 if v.castle else 0) | (2 if v.water else 0) | (4 if v.final else 0) | (8 if last else 0)
    out = [w, v.start[0], v.start[1], int(t[2:], 16), int(t[:2], 16), flags, v.room, v.out]
    assert len(v.g[0]) <= 256, v.name
    for r in v.g: out += rle([x * 4 for x in r])
    assert len(v.en) * 3 < 256, v.name
    for x, y, k in sorted(v.en): out += [x, y, ENEMY_TYPES[k]]
    return out + [0xFF]

def world_bytes(levels):
    out = [ord('S'), ord('M'), 2, len(levels)]
    blocks = [level_bytes(v, i == len(levels) - 1) for i, v in enumerate(levels)]
    pos = 4 + 2 * len(levels)
    for b in blocks:
        out += [pos & 255, pos >> 8]; pos += len(b)
    for b in blocks: out += b
    return out

def bl(vals):
    return ', '.join('$%02X' % (v & 0xFF) for v in vals)

def lines(label, vals, per=16, f=sys.stdout):
    name, _, comment = label.partition(';')
    print(name.strip() + ':' + ('   ; ' + comment.strip() if comment else ''), file=f)
    for i in range(0, len(vals), per): print('        .byte   ' + bl(vals[i:i + per]), file=f)

def main():
    import levels
    WBUF = 22 * 256                     # the files are loaded into the view buffer
    f = open('smb_data.inc', 'w')
    print('; generated by gen.py from gen.py and levels.py', file=f)
    print('NTILE = %d' % len(TILES), file=f)
    for i, t in enumerate(TILES): print('T_%-8s = %d' % (t[0], i * 4), file=f)
    top = []; bot = []
    for t in TILES:
        g = tile_chars(t[3]); top += g[:4]; bot += g[4:]
    print('; the map holds tile number * 4: the index of its 4 characters here', file=f)
    lines('tile_top    ; the top text row of each tile (4 characters)', top, f=f)
    lines('tile_bot    ; the bottom row', bot, f=f)
    lines('tile_solid  ; (by tile number * 4)', sum([[t[2]] * 4 for t in TILES], []), f=f)
    # sprites
    data = []; idx = []
    for name in ORDER:
        for ax in range(2):
            w, h, cells = render(SPR[name], ax)
            idx.append(len(data))
            data += [w, h] + cells
    for i, name in enumerate(ORDER): print('SP_%-12s = %d' % (name, i), file=f)
    print('NSPR = %d' % len(ORDER), file=f)
    print('.if SOFT_SPRITES                ; (SMBSW.BIN: the 6502 draws the sprites)', file=f)
    print('; sprite pictures: (frame * 2 + x & 1) -> w, h, then (mask, bits) per cell, column by column', file=f)
    for nm, part in (('spr_lo', '<'), ('spr_hi', '>')):
        print(nm + ':', file=f)
        for i in range(0, len(idx), 8):
            print('        .byte   ' + ', '.join('%s(spr_data+%d)' % (part, k) for k in idx[i:i + 8]), file=f)
    lines('spr_data', data, f=f)
    print('SPR_BYTES = %d' % len(data), file=f)
    lines('mirror      ; a block character mirrored left to right', [mirror_byte(b) for b in range(256)], f=f)
    print('.endif', file=f)
    print('.if SOFT_SPRITES', file=f)
    lines('banner      ; text row, first column, count, characters; then 0', banner(BANNER), f=f)
    print('.else                           ; (SMB.BIN: terminal tiles, from SMBSPR.SMB)', file=f)
    for k, (slot, trow, c0, cols, data) in enumerate(banner_tiles(BANNER)):
        print('BAN%d_SLOT = %d\nBAN%d_ROW = %d\nBAN%d_COL = %d' % (k, slot, k, trow, k, c0), file=f)
    print('.endif', file=f)
    print('NWORLDS = %d' % len(levels.WORLDS), file=f)
    f.close()
    print('smb_data.inc: %d tiles, sprites %d bytes' % (len(TILES), len(data)))
    b = spr_file()
    open('SMBSPR.SMB', 'wb').write(bytes(b))
    print('SMBSPR.SMB: %d bytes, %d in the terminal\'s picture pool' % (len(b), pool_bytes()))
    import glob
    for old in glob.glob('WORLD*.SMB') + glob.glob('CELL*.SMB'): os.remove(old)
    for n, ws in enumerate(levels.WORLDS, 1):        # every world is a file
        b = world_bytes(ws)
        assert len(b) <= WBUF, (n, len(b))
        open('WORLD%d.SMB' % n, 'wb').write(bytes(b))
        print('WORLD%d.SMB: %d bytes, %s' % (n, len(b), ' '.join(v.name for v in ws)))

if __name__ == '__main__':
    main()
