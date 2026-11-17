#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for BYTE BREAKER -> breaker_gfx.inc
    python gen_pico.py

The screen is Graphics II used as tiles: each third (8 text rows) has its own
256 patterns, and every pattern line its own two colours.  The game still
plays in the terminal's 160 x 96 pixels; a game pixel is 1.5 x 2 screen
pixels (screen x = 8 + x * 3 / 2, screen y = y * 2), so a text row is a tile
row and the field is 240 x 192.

Patterns (in every third):
  $00          blank
  $01          the top wall (row 1)
  $02, $03     the left wall (column 0), the right wall (column 31)
  $06          a ball, for the status line
  $20-$5F      the font (the console's, made bold), white on black
  $C0-$FF      the font again, white on blue (highlighted), thirds 0 and 2
  $60 ...      the bricks: thirds 0 (brick rows 0-3) and 1 (rows 4-9), 21
               patterns a row (see brick_names)

Bricks are 12 x 8 (10 x 6 drawn); brick c starts at screen x 14 + 12 c, so
three tiles hold two bricks.  Tile column t (1-30), k = (t - 1) / 3:
  phase 0 (t = 1 + 3k): the end of brick 2k-1 and the start of brick 2k
  phase 1 (t = 2 + 3k): the middle of brick 2k
  phase 2 (t = 3 + 3k): the start of brick 2k+1
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font

# ---- colours (TMS9918: 1 black, 2 green, 3 light green, 4 dark blue,
# 5 light blue, 6 dark red, 7 cyan, 8 red, 9 light red, A dark yellow,
# B yellow, C dark green, D magenta, E grey, F white) ----------------------
ROW_COL = [8, 0xA, 0xB, 3, 2, 7, 5, 4, 0xD, 6]   # brick rows 0-9 (top first)
HILITE = 0xF                                     # each brick's top line
STEEL, STEEL_HI = 0xE, 0xF
TEXT = 0xF1
TEXT_HI = 0xF4                                   # highlighted: white on blue
WALL_COLS = [0xF, 0xE, 0xE, 0xE, 0xE, 0xE, 0xE, 0x4]   # the top wall, by line
SIDE_COL = 0xE
BALL_COL = 0xF
SHOT_COL = 0xB
PAD_COL = 0xE                                    # the paddle's body
END_COL = [8, 8, 0xB, 3]       # its ends by power: none, wide, laser, catch
CAP_COL = [5, 7, 0xA, 8, 3, 0xE]                 # capsules W M S L C X
SIGN_COL = 0xF

# ---- bricks (10 x 6 drawn in a 12 x 8 cell) -------------------------------
B1 = ['##########'] * 6                                      # one hit
B2 = ['##########'] + ['#........#'] * 4 + ['##########']    # two hits
B3 = ['#.#.#.#.#.', '.#.#.#.#.#'] * 3                         # steel
SHAPES = [None, B1, B2, B3]

def brick_line(kind, y):
    """12 pixels of row y (0-7) of a brick of this kind"""
    if kind == 0 or y >= 6:
        return [0] * 12
    return [1 if ch == '#' else 0 for ch in SHAPES[kind][y]] + [0, 0]

def tile_bits(phase, a, b):
    """8 x 8 bits of a tile: (phase, left kind a, right kind b)"""
    rows = []
    for y in range(8):
        if phase == 0:      # brick a's pixels 6-11, then brick b's 0-1
            px = brick_line(a, y)[6:12] + brick_line(b, y)[0:2]
        elif phase == 1:    # brick a's pixels 2-9
            px = brick_line(a, y)[2:10]
        else:               # gap, then brick a.s pixels 0-5
            px = [0, 0] + brick_line(a, y)[0:6]   # gap, then brick a's 0-5
        rows.append(sum(0x80 >> i for i in range(8) if px[i]))
    return rows

def tile_cols(row, phase, a, b):
    kinds = {a, b} - {0}
    if kinds == {3}:                       # steel only: grey
        main, hi = STEEL, STEEL_HI
    else:
        main, hi = ROW_COL[row], HILITE
    return [(hi if y == 0 else main) << 4 | 1 for y in range(8)]

# the tiles of one brick row: (phase, a, b) -> pattern offset; blank -> none
COMBOS = []
for k in (1, 2, 3):
    COMBOS.append((1, k, 0))
for k in (1, 2, 3):
    COMBOS.append((2, k, 0))
for a in range(4):
    for b in range(4):
        if (a, b) != (0, 0):
            COMBOS.append((0, a, b))
assert len(COMBOS) == 21
P_BRICK = 0x60

def brick_name_table():
    """48 entries: phase * 16 + a * 4 + b -> offset from the row's base, or
    $FF for blank"""
    t = [0xFF] * 48
    for i, (p, a, b) in enumerate(COMBOS):
        t[p * 16 + a * 4 + b] = i
    return t

# ---- the walls, the ball icon ---------------------------------------------
TOP_WALL = [0xFF] * 8
LEFT_WALL = [0x07] * 8          # screen x 5-7
RIGHT_WALL = [0xE0] * 8         # screen x 248-250
BALL_ICON = [0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x00]

# ---- sprites (16 x 16; drawn at the screen's size) -------------------------
def pad_rows(w, laser=False):
    """the paddle w screen pixels wide, 6 tall: (body, ends)"""
    body, ends = [], []
    for y in range(6):
        b = ['.'] * w; e = ['.'] * w
        for x in range(w):
            end = x < 4 or x >= w - 4
            corner = (y in (0, 5)) and (x == 0 or x == w - 1)
            if corner:
                continue
            if laser and y == 0 and not (x < 3 or x >= w - 3):
                continue                     # (the cannons stand up)
            if end:
                e[x] = '#'
            else:
                b[x] = '#'
        body.append(''.join(b)); ends.append(''.join(e))
    return body, ends

BALL = ['.##.', '####', '####', '.##.'][:4]
BALL = ['.#.', '###', '###', '.#.']
SHOT = ['##'] * 6
CAPSULE = ['..######..', '.########.'] + ['##########'] * 6 + ['.########.', '..######..']
SIGNS = {'W': ['#.#', '###', '#.#'], 'M': ['#.#', '...', '.#.'], 'S': ['...', '###', '...'],
         'L': ['#.#', '#.#', '#.#'], 'C': ['#.#', '#.#', '###'], 'X': ['.#.', '###', '.#.']}

def sign_rows(s):
    g = SIGNS[s]
    rows = ['..........'] * 10
    rows = [list(r) for r in rows]
    for y in range(3):
        for x in range(3):
            if g[y][x] == '#':
                for dy in (0, 1):
                    for dx in (0, 1):
                        rows[2 + y * 2 + dy][2 + x * 2 + dx] = '#'
    return [''.join(r) for r in rows]

def sprite_bytes(rows, x0=0):
    """a 16 x 16 sprite from rows, starting at column x0 of them"""
    g = [[0] * 16 for _ in range(16)]
    for y, r in enumerate(rows):
        for x in range(16):
            if 0 <= x0 + x < len(r) and r[x0 + x] == '#':
                g[y][x] = 1
    out = []
    for half in (0, 8):
        for y in range(16):
            out.append(sum(0x80 >> i for i in range(8) if g[y][half + i]))
    return out

SPRITES = []            # (name, 32 bytes)
def add(name, rows, x0=0):
    SPRITES.append((name, sprite_bytes(rows, x0)))

nb, ne = pad_rows(24)
wb, we = pad_rows(36)
lb, le = pad_rows(24, laser=True)
for i in range(2): add('S_PAD%d' % i, nb, 16 * i)
for i in range(2): add('S_PADE%d' % i, ne, 16 * i)
for i in range(3): add('S_WIDE%d' % i, wb, 16 * i)
for i in range(3): add('S_WIDEE%d' % i, we, 16 * i)
for i in range(2): add('S_LAS%d' % i, lb, 16 * i)
for i in range(2): add('S_LASE%d' % i, le, 16 * i)
add('S_BALL', BALL)
add('S_SHOT', SHOT)
add('S_CAP', CAPSULE)
for s in 'WMSLCX': add('S_SIGN_' + s, sign_rows(s))

# ---- output ----------------------------------------------------------------
out = ['; breaker_gfx.inc - made by gen_pico.py', '']
def tab(name, vals):
    out.append(name + ':')
    for i in range(0, len(vals), 16):
        out.append('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + 16]))

out.append('P_BRICK = $%02X' % P_BRICK)
out.append('NBRICKPAT = %d' % len(COMBOS))
for i, (n, _) in enumerate(SPRITES):
    out.append('%s = %d' % (n, i * 4))          # sprite pattern numbers
out.append('NSPRPAT = %d' % len(SPRITES))
out.append('C_BALL = $%X' % BALL_COL)
out.append('C_SHOT = $%X' % SHOT_COL)
out.append('C_PAD = $%X' % PAD_COL)
out.append('C_SIGN = $%X' % SIGN_COL)
tab('end_col', END_COL)
tab('cap_col', CAP_COL)
tab('brick_names', brick_name_table())

# tile column tables (0-31): phase, the left brick's column, the right's
tph, tca, tcb = [], [], []
for t in range(32):
    if 1 <= t <= 30:
        k, p = divmod(t - 1, 3)
        if p == 0:
            a = 2 * k - 1 if k >= 1 else 0xFF
            b = 2 * k if 2 * k <= 18 else 0xFF
        elif p == 1:
            a, b = 2 * k, 0xFF
        else:
            a = 2 * k + 1 if 2 * k + 1 <= 18 else 0xFF
            b = 0xFF
    else:
        p, a, b = 0, 0xFF, 0xFF
    tph.append(p * 16); tca.append(a); tcb.append(b)
tab('tc_phase', tph); tab('tc_a', tca); tab('tc_b', tcb)
# the brick rows' first pattern (thirds 0 and 1)
tab('row_base', [P_BRICK + NB * 21 for NB in (0, 1, 2, 3, 0, 1, 2, 3, 4, 5)])

# pattern data
tab('font', [b for ch in bold_font() for b in ch] if isinstance(bold_font()[0], list) else bold_font())
tab('wall_pats', TOP_WALL + LEFT_WALL + RIGHT_WALL)
tab('wall_cols', [c << 4 | 1 for c in WALL_COLS] + [SIDE_COL << 4 | 1] * 16)
tab('ball_icon', BALL_ICON)
for third, rows in ((0, range(0, 4)), (1, range(4, 10))):
    pats, cols = [], []
    for r in rows:
        for (p, a, b) in COMBOS:
            pats += tile_bits(p, a, b)
            cols += tile_cols(r, p, a, b)
    tab('bricks%d_pat' % third, pats)
    tab('bricks%d_col' % third, cols)
    out.append('BRICKS%d_LEN = %d' % (third, len(pats)))
tab('spr_pats', [b for _, s in SPRITES for b in s])
out.append('SPR_PATS_LEN = %d' % (32 * len(SPRITES)))

open(os.path.join(HERE, 'breaker_gfx.inc'), 'w').write('\n'.join(out) + '\n')
print('breaker_gfx.inc:', len(SPRITES), 'sprite patterns')
