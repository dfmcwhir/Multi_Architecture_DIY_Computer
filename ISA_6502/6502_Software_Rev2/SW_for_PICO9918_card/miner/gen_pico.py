#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for MINER MOS -> miner_gfx.inc
    python gen_pico.py
The pictures are gen.py's.  Here: each picture drawn at the screen's scale
(a game pixel is 1.5 x 2 screen pixels) as 16 x 16 sprites, in 4 versions:
facing right / left (mirrored) and at an even / odd game x (1.5 x is whole
or half way); their colours; the tiles' colours; the font; the tables that
spread block graphics characters over the bitmap."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
sys.path.insert(0, HERE)
from fontgen import bold_font
import gen

# colours: 1 black, 2 green, 3 light green, 4 dark blue, 5 light blue,
# 6 dark red, 7 cyan, 8 red, 9 light red, A dark yellow, B yellow,
# C dark green, D magenta, E grey, F white
WILLY_COL = 0xF
GUARD_COL = {'ROBOT': 7, 'BIRD': 0xB, 'BLOB': 3, 'SPIN': 0xD, 'SKULL': 0xE, 'JELLY': 5}
PORTAL_COL = [0xE, 0xB, 8]          # shut; flashing (two frames)
ROOM_COL = [(8, 6), (5, 4), (3, 0xC), (0xB, 0xA), (0xD, 6), (7, 4), (0xE, 0xC), (8, 0xA)]  # floor, wall
CONV_COL, HAZARD_COL, KEY_COL = 0xE, 2, 0xB
AIR_COL = 0xF1
TEXT, TEXT_HI = 0xF1, 0xF4

def scaled(rows, face, par):
    if face: rows = [r[::-1] for r in rows]
    w = len(rows[0])
    g = [[0] * 16 for _ in range(16)]
    base = (3 * par) // 2
    for y, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch != '#': continue
            a = (3 * (i + par)) // 2 - base
            b = (3 * (i + par + 1)) // 2 - base
            for x in range(a, b):
                if x < 16:
                    g[2 * y][x] = g[2 * y + 1][x] = 1
    out = []
    for half in (0, 8):
        for y in range(16):
            out.append(sum(0x80 >> i for i in range(8) if g[y][half + i]))
    return out

o = ['; miner_gfx.inc - made by gen_pico.py', '']
def tab(name, vals):
    o.append(name + ':')
    for i in range(0, len(vals), 16):
        o.append('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + 16]))
data, cols = [], []
for name, rows in gen.PICS:
    for face in (0, 1):
        for par in (0, 1):
            data += scaled(rows, face, par)
    if name == 'PIC_WILLY': cols.append(WILLY_COL)
    elif name == 'PIC_PORTAL': cols.append(None)
    else: cols.append(GUARD_COL[name[4:]])
pi = 0
for i, (name, rows) in enumerate(gen.PICS):
    if name == 'PIC_PORTAL': cols[i] = PORTAL_COL[pi]; pi += 1
tab('pic_col', cols)
o.append('; each picture: 4 versions of 32 bytes (face 0/1, x even/odd)')
tab('spr_vers', data)
tab('room_floor', [f for f, w in ROOM_COL])
tab('room_wall', [w for f, w in ROOM_COL])
o.append('CONV_COL = $%X' % CONV_COL)
o.append('HAZARD_COL = $%X' % HAZARD_COL)
o.append('KEY_COL = $%X' % KEY_COL)
o.append('AIR_COL = $%02X' % AIR_COL)
o.append('C_TEXT = $%02X' % TEXT)
o.append('C_TEXT_HI = $%02X' % TEXT_HI)
tab('font', bold_font())
def pix(i, odd):
    L, R = i & 1, (i >> 1) & 1
    return [L, R, R] if odd else [L, L, R]
def spread(name, odd, first, count, top):
    vals = []
    for i in range(4):
        v = 0
        for j, b in enumerate(pix(i, odd)[first:first + count]):
            if b: v |= 1 << (top - j)
        vals.append(v)
    tab(name, vals)
spread('ev_75', 0, 0, 3, 7); spread('od_42', 1, 0, 3, 4); spread('ev_10', 0, 0, 2, 1)
spread('ev_7', 0, 2, 1, 7); spread('od_64', 1, 0, 3, 6); spread('ev_31', 0, 0, 3, 3)
spread('od_0', 1, 0, 1, 0); spread('od_76', 1, 1, 2, 7); spread('ev_53', 0, 0, 3, 5)
spread('od_20', 1, 0, 3, 2)
open(os.path.join(HERE, 'miner_gfx.inc'), 'w').write('\n'.join(o) + '\n')
print('miner_gfx.inc:', len(gen.PICS), 'pictures,', len(data), 'bytes of sprite versions')
