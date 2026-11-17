#!/usr/bin/env python3
"""gen.py - makes stacker_data.inc for the PICO9918 STACKER: the pieces,
the square patterns and colours, and the title banner.  python gen.py

Patterns (Graphics I):
  $00          blank
  $20-$5F      the font (the console's 5 x 8 font, made bold)
  $60 + g * 8  square g (one pattern in each colour group): 0 empty well,
               1-7 the pieces, 8 the ghost, 9 flash / game over fill
  $C0, $C8     the well's side and floor
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))

PIECES = [
    ('I', [[(0,1),(1,1),(2,1),(3,1)], [(2,0),(2,1),(2,2),(2,3)], [(0,2),(1,2),(2,2),(3,2)], [(1,0),(1,1),(1,2),(1,3)]]),
    ('O', [[(1,0),(2,0),(1,1),(2,1)]] * 4),
    ('T', [[(1,0),(0,1),(1,1),(2,1)], [(1,0),(1,1),(2,1),(1,2)], [(0,1),(1,1),(2,1),(1,2)], [(1,0),(0,1),(1,1),(1,2)]]),
    ('S', [[(1,0),(2,0),(0,1),(1,1)], [(1,0),(1,1),(2,1),(2,2)], [(1,1),(2,1),(0,2),(1,2)], [(0,0),(0,1),(1,1),(1,2)]]),
    ('Z', [[(0,0),(1,0),(1,1),(2,1)], [(2,0),(1,1),(2,1),(1,2)], [(0,1),(1,1),(1,2),(2,2)], [(1,0),(0,1),(1,1),(0,2)]]),
    ('J', [[(0,0),(0,1),(1,1),(2,1)], [(1,0),(2,0),(1,1),(1,2)], [(0,1),(1,1),(2,1),(2,2)], [(1,0),(1,1),(0,2),(1,2)]]),
    ('L', [[(2,0),(0,1),(1,1),(2,1)], [(1,0),(1,1),(1,2),(2,2)], [(0,1),(1,1),(2,1),(0,2)], [(0,0),(1,0),(1,1),(1,2)]]),
]

SQUARE = ["#######.",
          "#.#####.",
          "##.####.",
          "#######.",
          "#######.",
          "#######.",
          "#######.",
          "........"]
EMPTY  = ["........", "........", "........", "...#....", "........", "........", "........", "........"]
GHOST  = ["#.#.#.#.", "........", "#.....#.", "........", "#.....#.", "........", "#.#.#.#.", "........"]
FLASH  = ["########"] * 8
WALL   = ["###.####", "###.####", "###.####", "........", "#######.", "#######.", "#######.", "........"]
FLOOR  = ["###.####", "###.####", "###.####", "........", "........", "........", "........", "........"]
# the colours: empty, I O T S Z J L, ghost, flash
COLOURS = [0x40, 0x70, 0xB0, 0xD0, 0x30, 0x90, 0x50, 0xA0, 0xE0, 0xF0]
FONT3 = {
    'S': ['###', '#..', '###', '..#', '###'],
    'T': ['###', '.#.', '.#.', '.#.', '.#.'],
    'A': ['###', '#.#', '###', '#.#', '#.#'],
    'C': ['###', '#..', '#..', '#..', '###'],
    'K': ['#.#', '#.#', '##.', '#.#', '#.#'],
    'E': ['###', '#..', '##.', '#..', '###'],
    'R': ['##.', '#.#', '##.', '#.#', '#.#'],
}

def pat(rows):
    return [int(r.replace('#', '1').replace('.', '0'), 2) for r in rows]

import sys
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font as font

def bl(vals):
    return ', '.join('$%02X' % v for v in vals)

def rows8(name, data):
    s = name + ':\n'
    for i in range(0, len(data), 8):
        s += '        .byte   ' + bl(data[i:i + 8]) + '\n'
    return s

def main():
    o = ['; stacker_data.inc - made by gen.py; don\'t edit, run  python gen.py\n']
    for n in ('x', 'y'):
        o.append('pc_%s:   ; [piece * 16 + rotation * 4 + square]\n' % n)
        for name, rots in PIECES:
            o.append('        .byte   ' + bl([p[0 if n == 'x' else 1] for r in rots for p in r]) + '   ; ' + name + '\n')
    o.append(rows8('gfx_font', font()))
    sq = []
    for g in range(10):
        sq += pat(EMPTY if g == 0 else GHOST if g == 8 else FLASH if g == 9 else SQUARE)
    o.append('; the squares: one pattern each, 8 apart ($60, $68 ... $A8)\n' + rows8('gfx_squares', sq))
    o.append(rows8('gfx_well', pat(WALL) + pat(FLOOR)))
    col = [0] * 32
    for g in range(4, 12): col[g] = 0xF0
    for g in range(10): col[12 + g] = COLOURS[g]
    col[24] = 0xE0              # the well: grey
    o.append(rows8('gfx_colours', col))
    word = 'STACKER'
    rows = []
    for y in range(5):
        row = []
        for i, ch in enumerate(word):
            for x in range(3):
                row.append(1 + i % 7 if FONT3[ch][y][x] == '#' else 10)
            if i < len(word) - 1: row.append(10)
        rows.append(row)
    o.append('BANNER_W = %d          ; squares\nBANNER_H = 5\nbanner:  ; square numbers, row by row (10 = blank)\n' % len(rows[0]))
    for r in rows: o.append('        .byte   ' + bl(r) + '\n')
    open(os.path.join(HERE, 'stacker_data.inc'), 'w').write(''.join(o))
    print('stacker_data.inc written')

main()
