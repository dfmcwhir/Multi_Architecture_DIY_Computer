"""fontgen.py - the games' text font: the console's 5 x 8 font
(font5x8.inc), with a few letters redrawn 5 pixels wide, made bold.
    from fontgen import bold_font;  bold_font()  -> 64 x 8 bytes, $20-$5F"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))

# letters redrawn (the font's own are 4 pixels wide and turn solid in bold)
OVER = {
    '0': [".....", ".###.", "#...#", "#...#", "#...#", "#...#", ".###.", "....."],
    'M': [".....", "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "....."],
    'W': [".....", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#", "....."],
    'N': [".....", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "....."],
}

def bold_font():
    src = open(os.path.join(HERE, 'font5x8.inc')).read()
    rows = re.findall(r'\.byte\s+((?:\$[0-9A-F]{2},?)+)', src)
    out = []
    for i, r in enumerate(rows[:64]):
        ch = chr(0x20 + i)
        if ch in OVER:
            vals = [int(row.replace('#', '1').replace('.', '0'), 2) << 3 for row in OVER[ch]]
        else:
            vals = [int(b.strip()[1:], 16) for b in r.split(',')]
        for v in vals:
            v = (v | ((v >> 1) & ~(v << 1))) & 0xFF     # bold, keeping 1 pixel gaps
            out.append(v >> 1)                          # one pixel in: centred
    return out
