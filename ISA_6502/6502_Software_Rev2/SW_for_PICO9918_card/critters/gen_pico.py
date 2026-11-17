#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for CRITTERS -> critters_gfx.inc
    python gen_pico.py

The playfield is the Graphics II bitmap: a game pixel is 1.5 x 2 screen
pixels (screen x = 8 + 1.5 x, y = 2 y), as in DOOM and BREAKER.  The game's
block graphics characters (2 x 4 pixels) become 3 x 8 screen pixels: eight
make three cells, spread with the tables below.  Text is drawn into the
bitmap with the font.  The critters, the selection mark and the mouse
pointer are 8 x 8 sprites."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font

# ---- colours (1 black, 2 green, 3 light green, 4 dark blue, 5 light blue,
# 6 dark red, 7 cyan, 8 red, 9 light red, A dark yellow, B yellow,
# C dark green, D magenta, E grey, F white) --------------------------------
TEXT, TEXT_HI = 0xF1, 0xF4          # text; highlighted (white on blue)
LEVEL_COL = [0xA, 0x6, 0xC, 0xE, 0xA, 0x6]   # the terrain, by level
HATCH, DOOR = 0x5, 0xB              # the hatch and the exit (their cells)
# the critters' colour by state: none walk fall float climb block build
# bash dig splat gone
STATE_COL = [3, 3, 3, 5, 3, 8, 0xB, 0xD, 7, 6, 3]
ABILITY_COL = 0xF                   # a walker / faller / climber with a skill
MARK_COL, POINTER_COL = 0xB, 0xF

# ---- sprites: 8 x 8; a critter's feet are rows 6-7, columns 3-4 ----------
SPR = {
    'P_POINTER': ['#.......', '##......', '###.....', '####....', '#####...', '###.....', '#.##....', '...##...'],
    'P_WALK':  ['........'] * 4 + ['...##...'] * 4,
    'P_FLOAT': ['..####..', '..####..', '....#...', '....#...'] + ['...##...'] * 4,
    'P_BLOCK': ['........'] * 4 + ['.######.'] * 2 + ['...##...'] * 2,
    'P_SPLAT': ['........'] * 6 + ['..####..'] * 2,
    'P_MARK':  ['........'] * 5 + ['..####..', '..####..', '...##...'],
}
ORDER = ['P_POINTER', 'P_WALK', 'P_FLOAT', 'P_BLOCK', 'P_SPLAT', 'P_MARK']
STATE_SPR = ['P_WALK', 'P_WALK', 'P_WALK', 'P_FLOAT', 'P_WALK', 'P_BLOCK',
             'P_WALK', 'P_WALK', 'P_WALK', 'P_SPLAT', 'P_WALK']
ABILITY_STATES = [1, 2, 4]          # walk, fall, climb

o = ['; critters_gfx.inc - made by gen_pico.py', '']
def tab(name, vals):
    o.append(name + ':')
    for i in range(0, len(vals), 16):
        o.append('        .byte   ' + ', '.join('$%02X' % (v & 0xFF) for v in vals[i:i + 16]))
o.append('C_TEXT = $%02X' % TEXT)
o.append('C_TEXT_HI = $%02X' % TEXT_HI)
o.append('C_HATCH = $%X1' % HATCH)
o.append('C_DOOR = $%X1' % DOOR)
o.append('C_MARK = $%X' % MARK_COL)
o.append('C_POINTER = $%X' % POINTER_COL)
for i, n in enumerate(ORDER):
    o.append('%s = %d' % (n, i))
o.append('NSPR = %d' % len(ORDER))
tab('lv_col', [c << 4 | 1 for c in LEVEL_COL])
tab('st_spr', [ORDER.index(n) for n in STATE_SPR])
tab('st_col', STATE_COL)
tab('st_abl', [1 if s in ABILITY_STATES else 0 for s in range(11)])
o.append('ABILITY_COL = $%X' % ABILITY_COL)
tab('spr_pats', [sum(0x80 >> i for i in range(8) if r[i] == '#') for n in ORDER for r in SPR[n]])
tab('font', bold_font())
# a character's 2 pixels at row k (index: 1 = left, 2 = right) as 3 screen
# pixels: even column L L R, odd column L R R; each table puts some of those
# pixels at some bits of a byte (bit 7 = left)   (the same as DOOM's)
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
open(os.path.join(HERE, 'critters_gfx.inc'), 'w').write('\n'.join(o) + '\n')
print('critters_gfx.inc written')
