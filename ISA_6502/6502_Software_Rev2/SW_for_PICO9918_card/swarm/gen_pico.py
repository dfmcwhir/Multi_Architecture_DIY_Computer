#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for SWARM -> swarm_gfx.inc
    python gen_pico.py              (python gen_pico.py png: also sheet.png)

Everything is drawn for the F18A's enhanced colour mode ECM2: 2 bits a
pixel, so each sprite and each tile has 3 colours of its own (pixel value
1-3) from a 4-colour sub-palette (value 0 is see-through).  A sub-palette
is chosen by the sprite's colour nibble (or the tile's attribute byte):
palette entries 4 PS .. 4 PS + 3.  The game sets entries 16-63 (PS 4-15).

  - the aliens: 16 x 16, drawn here facing up, turned to 9 headings (up to
    down on the right, every 22.5 degrees; the left side is the same
    mirrored), 2 wing positions, 4 kinds (bee, butterfly, boss, a boss hit
    once).  Facing down they are also the formation's tiles.
  - the ship, its shot, the aliens' bullets, explosions (4 frames), the
    ship's explosion (3 frames).
  - tiles: the font (white, and red: +$A0), the stars (32 places in a cell,
    bright and dim), the formation (4 kinds x 2 wing positions x 4 cells),
    the ship for the ships in reserve.

Sprite pictures are kept in the program (64 bytes each: plane 0's 32 bytes,
then plane 1's) and copied into a sprite's own pattern when it changes."""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
from fontgen import bold_font

# ---- the sub-palettes (entries 4 PS + 1 .. 3; 12-bit RGB) ---------------------
PAL = {
    4: [0x000, 0xFD0, 0x25F, 0xF22],     # bee: yellow, blue, red
    5: [0x000, 0xE11, 0xFFF, 0x36F],     # butterfly: red, white, blue
    6: [0x000, 0x2C4, 0xB3E, 0xFE2],     # boss: green, purple, yellow
    7: [0x000, 0x93D, 0x47F, 0xFE2],     # boss hit once: purple, blue, yellow
    8: [0x000, 0xEEE, 0xE22, 0x35F],     # the ship: white, red, blue
    9: [0x000, 0xFFF, 0xF33, 0xFE0],     # its shot
    10: [0x000, 0xF44, 0xFFF, 0xFE0],    # the aliens' bullets
    11: [0x000, 0xFE0, 0xF40, 0xFFF],    # explosions
    12: [0x000, 0xF30, 0xFD0, 0xFFF],    # the ship's explosion
    13: [0x000, 0xFFF, 0xF33, 0x4EF],    # text: white, red, cyan
    14: [0x000, 0xDDF, 0x000, 0x669],    # stars: bright, -, dim
    15: [0x000, 0x000, 0x000, 0x000],
}
PS_KIND = [4, 5, 6, 7]
PS_SHIP, PS_SHOT, PS_EBUL, PS_BOOM, PS_PBOOM, PS_TEXT, PS_STAR = 8, 9, 10, 11, 12, 13, 14

# ---- the art: 16 x 16, facing up; . = see-through, 1-3 the colours ------------
BEE = ([
    "................",
    ".......33.......",
    "......1111......",
    ".....311113.....",
    "..2..111111..2..",
    ".222.111111.222.",
    ".22221111112222.",
    ".222.222222.222.",
    "..22.111111.22..",
    "...2.222222.2...",
    ".....111111.....",
    "......2222......",
    "......1111......",
    ".......33.......",
    "................",
    "................"], [
    "................",
    ".......33.......",
    "......1111......",
    ".....311113.....",
    ".....111111.....",
    "...2.111111.2...",
    "..2221111112222.",
    ".222.222222.222.",
    ".222.111111.222.",
    ".22..222222..22.",
    ".2...111111...2.",
    "......2222......",
    "......1111......",
    ".......33.......",
    "................",
    "................"])
BFLY = ([
    "................",
    ".....3....3.....",
    "......3..3......",
    "......3333......",
    "..111.3223.111..",
    ".12221.33.12221.",
    ".12222.33.22221.",
    ".12221.33.12221.",
    "..1111.33.1111..",
    "...11..33..11...",
    ".......33.......",
    "......3..3......",
    "................",
    "................",
    "................",
    "................"], [
    "................",
    ".....3....3.....",
    "......3..3......",
    "......3333......",
    "......3223......",
    "...11..33..11...",
    "..1221.33.1221..",
    ".12221.33.12221.",
    "..1221.33.1221..",
    "...11..33..11...",
    ".......33.......",
    "......3..3......",
    "................",
    "................",
    "................",
    "................"])
BOSS = ([
    "....1......1....",
    ".....1....1.....",
    "......1111......",
    ".....131131.....",
    "....11111111....",
    ".2.1112222111.2.",
    ".22112222221122.",
    ".22211222211222.",
    ".22111111111122.",
    ".2..11111111..2.",
    "......1..1......",
    ".....1....1.....",
    "................",
    "................",
    "................",
    "................"], [
    "....1......1....",
    ".....1....1.....",
    "......1111......",
    ".....131131.....",
    "....11111111....",
    "...1112222111...",
    "..211222222112..",
    ".22211222211222.",
    ".22111111111122.",
    ".22.11111111.22.",
    "......1..1......",
    ".....1....1.....",
    "................",
    "................",
    "................",
    "................"])
HURT = ([r.replace('1', 'h') for r in BOSS[0]], [r.replace('1', 'h') for r in BOSS[1]])
# (the boss hit once: the same drawing, its own palette; 'h' = 1)
HURT = ([r.replace('h', '1') for r in HURT[0]], [r.replace('h', '1') for r in HURT[1]])
KINDS = [BEE, BFLY, BOSS, HURT]
SHIP = [
    "................",
    ".......11.......",
    ".......11.......",
    ".......11.......",
    "......1111......",
    "...2..1111..2...",
    "...2..1331..2...",
    "...1.113311.1...",
    "...1111111111...",
    ".2.1112112111.2.",
    ".1111122221111.1"[:16],
    ".111111111111111"[:16],
    ".11.11.11.11.11.",
    ".1...1....1...1.",
    "................",
    "................"]
SHIP[10] = ".11111222211111."
SHIP[11] = ".11111111111111."
# where a picture's wire point sits: the sprite's top left is 2 screen pixels
# left of the wire point (an 8-pixel-wide picture becomes 12 of the 16)
SHOT = ["................"] * 16
SHOT = [("..21............" if y in (0, 1) else "..11............") if y < 8 else "................" for y in range(16)]
EBUL = ["..3.............", ".313............", ".111............", "..1............."] + ["................"] * 12


def grid(rows):
    return [[0 if c == '.' else int(c) for c in r.ljust(16, '.')[:16]] for r in (rows + ["."] * 16)[:16]]


def rotate(g, deg):
    """g turned deg clockwise about its middle (7.5, 6.5): each screen pixel
    takes the colour most of its 4 x 4 sub-pixels map to (if over 40% are
    drawn).  A screen pixel is 1 wide and 1 high here; the game's own
    pixels are 1.5 x 2, but the art is drawn for the screen."""
    if deg == 0: return [r[:] for r in g]
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = 7.5, 7.0
    out = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            votes = {}
            for sy in range(4):
                for sx in range(4):
                    px, py = x + (sx + 0.5) / 4 - 0.5 - cx, y + (sy + 0.5) / 4 - 0.5 - cy
                    # back to the original: turn by -deg
                    ox = px * ca + py * sa + cx
                    oy = -px * sa + py * ca + cy
                    ix, iy = int(math.floor(ox + 0.5)), int(math.floor(oy + 0.5))
                    v = g[iy][ix] if 0 <= ix < 16 and 0 <= iy < 16 else 0
                    votes[v] = votes.get(v, 0) + 1
            drawn = 16 - votes.get(0, 0)
            if drawn >= 7:
                votes.pop(0, None)
                out[y][x] = max(votes, key=votes.get)
    return out


def planes(g):
    """16 x 16 -> 64 bytes: plane 0 (the TMS 16 x 16 order: left column of
    8 x 8s top then bottom, then the right), then plane 1"""
    out = []
    for bit in (0, 1):
        for half in (0, 8):
            for y in range(16):
                out.append(sum(0x80 >> i for i in range(8) if g[y][half + i] >> bit & 1))
    return out


def boom(n):
    """explosion frame n (0-3): a ring of sparks"""
    g = [[0] * 16 for _ in range(16)]
    r = [2, 4, 6, 7][n]
    for k in range(16):
        a = 2 * math.pi * k / 16 + n * 0.3
        for rr, v in ((r, 1 if n < 2 else 2), (r * 0.6, 3 if n < 2 else 1)):
            x, y = int(round(7.5 + rr * math.cos(a))), int(round(7 + rr * math.sin(a)))
            if 0 <= x < 16 and 0 <= y < 16 and (n < 3 or k % 2): g[y][x] = v
    if n == 0:
        for y in range(5, 10):
            for x in range(5, 11):
                if (x - 7.5) ** 2 + (y - 7) ** 2 < 6: g[y][x] = 3
    return g


def pboom(n):
    g = [[0] * 16 for _ in range(16)]
    r = [3, 5, 7][n]
    for k in range(24):
        a = 2 * math.pi * k / 24
        rr = r * (1 if k % 2 else 0.6)
        for t in range(int(rr) + 1):
            x, y = int(round(7.5 + t * math.cos(a))), int(round(7.5 + t * math.sin(a)))
            if 0 <= x < 16 and 0 <= y < 16: g[y][x] = 3 if t < r * 0.3 else (2 if t < r * 0.65 else 1)
    return g


def pictures():
    """-> list of (name, grid, PS)"""
    P = []
    for k, kind in enumerate(KINDS):
        for f in range(2):
            g = grid(kind[f])
            for d in range(9):
                P.append(('A%d_%d_%d' % (k, f, d), rotate(g, 22.5 * d), PS_KIND[k]))
    P.append(('SHIP', grid(SHIP), PS_SHIP))
    P.append(('SHOT', grid(SHOT), PS_SHOT))
    P.append(('EBUL', grid(EBUL), PS_EBUL))
    for n in range(4): P.append(('BOOM%d' % n, boom(n), PS_BOOM))
    for n in range(3): P.append(('PBOOM%d' % n, pboom(n), PS_PBOOM))
    return P


def cell_planes(g, cx, cy):
    """the 8 x 8 cell at cx, cy of a 16 x 16 grid -> 16 bytes (plane 0, plane 1)"""
    return [sum(0x80 >> i for i in range(8) if g[cy * 8 + y][cx * 8 + i] >> bit & 1)
            for bit in (0, 1) for y in range(8)]


def main():
    o = ['; generated by gen_pico.py - do not edit', '']
    def tab(name, vals, per=16):
        o.append('%s:' % name)
        for i in range(0, len(vals), per):
            o.append('        .byte   ' + ', '.join('$%02X' % (v & 255) for v in vals[i:i + per]))
    P = pictures()
    names = [n for n, g, ps in P]
    for n in ('SHIP', 'SHOT', 'EBUL', 'BOOM0', 'PBOOM0'):
        o.append('PIC_%-8s = %d' % (n, names.index(n)))
    o.append('PIC_ALIEN     = 0             ; + kind * 18 + wings * 9 + heading (0 up .. 8 down)')
    o.append('NPIC          = %d' % len(P))
    o.append('; the pictures: 64 bytes each')
    o.append('pic_lo:')
    o.append('        .byte   ' + ', '.join('<(pics + %d)' % (64 * i) for i in range(len(P))))
    o.append('pic_hi:')
    o.append('        .byte   ' + ', '.join('>(pics + %d)' % (64 * i) for i in range(len(P))))
    tab('pic_ps', [ps for n, g, ps in P])
    data = []
    for n, g, ps in P: data += planes(g)
    tab('pics', data)
    # palette entries 16-63: 2 bytes each (0000RRRR, GGGGBBBB)
    pal = []
    for ps in range(4, 16):
        for c in PAL[ps]:
            pal += [c >> 8, c & 0xFF]
    tab('pal_game', pal)
    # ---- tiles: 2 planes each.  $20-$5F font (white), $60-$7F stars
    # bright, $80-$9F stars dim, $A0-$BF the formation, $01-$04 the ship,
    # $C0-$FF the red font
    T = {}
    f = bold_font()
    for i in range(64):
        g = f[i * 8:i * 8 + 8]
        T[0x20 + i] = (g + [0] * 8, PS_TEXT)          # value 1: white
        T[0xC0 + i] = ([0] * 8 + g, PS_TEXT)          # value 2: red
    for v, base in ((1, 0x60), (3, 0x80)):            # stars: value 1 bright, 3 dim
        for yy in range(4):
            for xx in range(8):
                p0 = [0] * 8; p1 = [0] * 8
                y = yy * 2
                p0[y] = 0x80 >> xx
                if v == 3: p1[y] = 0x80 >> xx
                T[base + yy * 8 + xx] = (p0 + p1, PS_STAR)
    for k in range(4):
        for fl in range(2):
            g = rotate(grid(KINDS[k][fl]), 180)
            for c, (cx, cy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                T[0xA0 + (k * 2 + fl) * 4 + c] = (cell_planes(g, cx, cy), PS_KIND[k])
    gs = grid(SHIP)
    for c, (cx, cy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
        T[0x01 + c] = (cell_planes(gs, cx, cy), PS_SHIP)
    p0, p1, attr = [], [], []
    for n in range(256):
        d, ps = T.get(n, ([0] * 16, PS_TEXT))
        p0 += d[:8]; p1 += d[8:]
        attr.append(0x10 | ps)                       # TRANS: value 0 see-through
    tab('tile_p0', p0)
    tab('tile_p1', p1)
    tab('tile_attr', attr)
    o.append('FM_PAT0       = $A0           ; the formation: + (kind * 2 + wings) * 4: TL TR BL BR')
    o.append('STAR_PAT0     = $60           ; + (y & 7) / 2 * 8 + (x & 7); dim + $20')
    o.append('LIFE_PAT0     = $01           ; TL TR BL BR')
    o.append('RED_FONT      = $A0           ; added to a character: red')
    # two thirds, rounded: wire x from a formation place's screen x
    tab('two3', [round(v * 2 / 3) for v in range(256)])
    open(os.path.join(HERE, 'swarm_gfx.inc'), 'w').write('\n'.join(o) + '\n')
    print('swarm_gfx.inc: %d pictures (%d bytes), tiles' % (len(P), len(data)))
    if len(sys.argv) > 1: sheet(P)


def sheet(P):
    from PIL import Image
    S = 4
    cols = 18
    im = Image.new('RGB', (cols * 18 * S, ((len(P) + cols - 1) // cols) * 18 * S), (20, 20, 30))
    pxl = im.load()
    for i, (n, g, ps) in enumerate(P):
        ox, oy = (i % cols) * 18 * S, (i // cols) * 18 * S
        for y in range(16):
            for x in range(16):
                v = g[y][x]
                if not v: continue
                c = PAL[ps][v]
                rgb = ((c >> 8) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17)
                for a in range(S):
                    for b in range(S):
                        pxl[ox + x * S + a, oy + y * S + b] = rgb
    im.save(os.path.join(HERE, 'sheet.png'))


if __name__ == '__main__':
    main()
