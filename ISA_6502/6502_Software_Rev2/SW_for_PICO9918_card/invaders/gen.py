#!/usr/bin/env python3
"""gen.py - makes invaders_gfx.inc: the PICO9918 / TMS9918 patterns, colours
and sprites for INVADERS.  Run it after changing a picture:  python gen.py

Patterns (Graphics I, 8 x 8 each):
  $00          blank
  $20-$5F      the font (the console's 5 x 8 font, made bold)
  $60-$77      the 4 shields, 3 x 2 each (the game rewrites them as they wear)
  $78          the ground line,  $79-$7A  a cannon (lives)
  $80-$C7      the invaders: 3 kinds x 2 frames x 4 positions (0, 2, 4, 6
               pixels to the right) x 3 patterns side by side
Sprites (16 x 16, 4 patterns each): cannon, shot, bomb x 2, saucer,
explosion, cannon explosion x 2.
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))

import sys
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font as font

INV = {
 'squid': (["...##...",
            "..####..",
            ".######.",
            "##.##.##",
            "########",
            "..#..#..",
            ".#.##.#.",
            "#.#..#.#"],
           ["...##...",
            "..####..",
            ".######.",
            "##.##.##",
            "########",
            ".#.##.#.",
            "#......#",
            ".#....#."]),
 'crab':  (["..#.....#..",
            "...#...#...",
            "..#######..",
            ".##.###.##.",
            "###########",
            "#.#######.#",
            "#.#.....#.#",
            "...##.##..."],
           ["..#.....#..",
            "#..#...#..#",
            "#.#######.#",
            "###.###.###",
            "###########",
            ".#########.",
            "..#.....#..",
            ".#.......#."]),
 'octo':  (["....####....",
            ".##########.",
            "############",
            "###..##..###",
            "############",
            "...##..##...",
            "..##.##.##..",
            "##........##"],
           ["....####....",
            ".##########.",
            "############",
            "###..##..###",
            "############",
            "..###..###..",
            ".##..##..##.",
            "..##....##.."]),
}
KINDS = ['squid', 'crab', 'octo']

def inv_patterns():
    out = []
    offs = {}
    for k in KINDS:
        w = len(INV[k][0][0])
        ox = (16 - w) // 2                      # centred in the first 16 pixels
        offs[k] = (ox, w)
        for fr in range(2):
            pic = INV[k][fr]
            for ph in range(4):
                for t in range(3):
                    for y in range(8):
                        b = 0
                        for x in range(8):
                            px = t * 8 + x - ph * 2 - ox
                            if 0 <= px < w and pic[y][px] == '#':
                                b |= 0x80 >> x
                        out.append(b)
    return out, offs

SHIELD = ["....################....",
          "...##################...",
          "..####################..",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".######################.",
          ".#######........#######.",
          ".######..........######.",
          ".#####............#####.",
          ".#####............#####."]

def rowbytes(s):
    s = s.ljust(len(s) + (-len(s)) % 8, '.')
    return [int(''.join('1' if c == '#' else '0' for c in s[i:i + 8]), 2) for i in range(0, len(s), 8)]

CANNON = ["......#......",
          ".....###.....",
          ".....###.....",
          ".###########.",
          "#############",
          "#############",
          "#############",
          "#############"]

SPRITES = {
 'cannon': ["." + r for r in CANNON],
 'shot':   [".......#"] * 4,
 'bomb0':  [".#.", "#..", ".#.", "..#", ".#.", "#..", ".#."],
 'bomb1':  [".#.", "..#", ".#.", "#..", ".#.", "..#", ".#."],
 'saucer': [".....######.....",
            "...##########...",
            "..############..",
            ".##.##.##.##.##.",
            "################",
            "..###..##..###..",
            "...#........#..."],
 'expl':   ["....#...#....",
            ".#...#.#...#.",
            "..#.......#..",
            "...#.....#...",
            "##.........##",
            "...#.....#...",
            "..#.#...#.#..",
            ".#...#.#...#."],
 'pexpl0': [".....#..........",
            "..#......#..#...",
            ".....#.##.#.....",
            ".#..#######..#..",
            "...##########...",
            "..############..",
            "..############..",
            ".##############."],
 'pexpl1': ["#.....#...#....#",
            "...#.....#...#..",
            ".#..##.#..#.#...",
            "...#.###.##..#..",
            "#.##########.#.#",
            "..############..",
            ".##############.",
            "################"],
}
SPR_ORDER = ['cannon', 'shot', 'bomb0', 'bomb1', 'saucer', 'expl', 'pexpl0', 'pexpl1']

def sprite16(pic):
    rows = [r.ljust(16, '.') for r in pic] + ['.' * 16] * (16 - len(pic))
    left = [int(''.join('1' if c == '#' else '0' for c in r[:8]), 2) for r in rows]
    right = [int(''.join('1' if c == '#' else '0' for c in r[8:16]), 2) for r in rows]
    return left + right

def hexrows(name, data, per=8, comment=None):
    s = '%s:\n' % name
    for i in range(0, len(data), per):
        s += '        .byte   ' + ','.join('$%02X' % b for b in data[i:i + per]) + '\n'
    return s

def main():
    f = font()
    inv, offs = inv_patterns()
    sh = []
    for r in SHIELD:
        sh += rowbytes(r)
    ground = [0, 0, 0, 0, 0xFF, 0, 0, 0]
    life = []
    rows = [r.ljust(16, '.') for r in ["." + r for r in CANNON]]
    for t in range(2):
        for y in range(8):
            life.append(int(''.join('1' if c == '#' else '0' for c in rows[y][t * 8:t * 8 + 8]), 2))
    spr = []
    for k in SPR_ORDER:
        spr += sprite16(SPRITES[k])
    # colour table: 32 groups of 8 patterns, high nibble = foreground
    col = [0x00] * 32
    for g in range(4, 12): col[g] = 0xF0        # $20-$5F text: white
    for g in range(12, 16): col[g] = 0x20       # $60-$7F shields, ground: green
    for g in range(16, 19): col[g] = 0x70       # squids: cyan
    for g in range(19, 22): col[g] = 0xD0       # crabs: magenta
    for g in range(22, 25): col[g] = 0xB0       # octopuses: yellow
    out = ['; invaders_gfx.inc - made by gen.py; don\'t edit, run  python gen.py\n']
    out.append(hexrows('gfx_font', f))
    out.append(hexrows('gfx_inv', inv))
    out.append('; the shield (24 x 16 pixels, 3 bytes a line)\n' + hexrows('gfx_shield', sh, 3))
    out.append(hexrows('gfx_ground', ground))
    out.append(hexrows('gfx_life', life))
    out.append(hexrows('gfx_colours', col))
    out.append(hexrows('gfx_sprites', spr))
    out.append('; each kind of invader: its left pixel in its 24 pixel cell, its width\n')
    out.append('inv_ox: .byte   ' + ', '.join(str(offs[k][0]) for k in KINDS) + '\n')
    out.append('inv_w:  .byte   ' + ', '.join(str(offs[k][1]) for k in KINDS) + '\n')
    with open(os.path.join(HERE, 'invaders_gfx.inc'), 'w') as fo:
        fo.write(''.join(out))
    print('invaders_gfx.inc: %d bytes of patterns, %d of sprites' % (len(f) + len(inv) + len(sh) + 24, len(spr)))

main()
