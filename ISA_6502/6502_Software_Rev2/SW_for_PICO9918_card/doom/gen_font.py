#!/usr/bin/env python3
"""gen_font.py - font.inc for the PICO9918 DOOM: the font (the console's,
made bold: ../lib/fontgen.py) and the tables present uses to spread block
graphics characters over the bitmap.   python gen_font.py"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font
f = bold_font()
o = ['; font.inc - made by gen_font.py\n', 'font:   ; $20-$5F, 8 bytes each\n']
for i in range(0, len(f), 8):
    o.append('        .byte   ' + ','.join('$%02X' % b for b in f[i:i + 8]) + '\n')
# a character's 2 pixels at row k (index: 1 = left, 2 = right) as 3 screen
# pixels: even column L L R, odd column L R R; each table puts some of
# those pixels at some bits of a byte (bit 7 = left)
def pix(i, odd):
    L, R = i & 1, (i >> 1) & 1
    return [L, R, R] if odd else [L, L, R]
def table(name, odd, first, count, top):
    vals = []
    for i in range(4):
        p = pix(i, odd)[first:first + count]
        v = 0
        for j, b in enumerate(p):
            if b: v |= 1 << (top - j)
        vals.append(v)
    o.append('%-8s.byte   %s\n' % (name + ':', ', '.join('$%02X' % v for v in vals)))
table('ev_75', 0, 0, 3, 7)
table('od_42', 1, 0, 3, 4)
table('ev_10', 0, 0, 2, 1)
table('ev_7', 0, 2, 1, 7)
table('od_64', 1, 0, 3, 6)
table('ev_31', 0, 0, 3, 3)
table('od_0', 1, 0, 1, 0)
table('od_76', 1, 1, 2, 7)
table('ev_53', 0, 0, 3, 5)
table('od_20', 1, 0, 3, 2)
open(os.path.join(HERE, 'font.inc'), 'w').write(''.join(o))
print('font.inc written')
