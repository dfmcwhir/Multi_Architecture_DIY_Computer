#!/usr/bin/env python3
"""gen_pico.py - the PICO9918 graphics for SUPER MOS BROS. (the hi-res
version): writes smb_pico.inc.

The art is art_hd.py's: every tile 16 x 16 screen pixels and every sprite
picture twice the game's size, in the F18A's enhanced colour mode ECM2 (2 bits
a pixel: each tile and sprite 3 colours of its own, from one of 16 groups of
4 palette entries).
  - tiles: each tile is 2 x 2 patterns; the patterns are shared where they
    are the same.  $20-$5F are the font (layer 2's text: white on black).
    The attribute table (one byte a pattern) gives each its colour group;
    pattern 0 and the tiles are see-through where they are 0.
  - sprites: each picture is cut into 16 x 16 parts (MOS: a second layer for
    his hair, eyes and shoes).  The parts (64 bytes each: plane 0, plane 1)
    are kept in the program (spr_parts); the game copies a part into a
    sprite's own pattern when that sprite's part changes.  The lists (a
    picture, both ways round: its parts' places, part numbers and colours)
    are in smb_pico.inc.
python gen_pico.py   (after art_hd.py, gen.py's tiles or pictures change)
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
import gen
import art_hd as A
from fontgen import bold_font

FLIPX = 0x40
TRANS = 0x10


def cell(g, cx, cy):
    """the 8 x 8 cell at cx, cy -> (plane 0, plane 1) 16 bytes"""
    p0 = [sum(0x80 >> i for i in range(8) if g[cy * 8 + y][cx * 8 + i] & 1) for y in range(8)]
    p1 = [sum(0x80 >> i for i in range(8) if g[cy * 8 + y][cx * 8 + i] & 2) for y in range(8)]
    return tuple(p0 + p1)


def part(g, x0, y0):
    """the 16 x 16 part at x0, y0 (outside: 0) -> 64 bytes: plane 0 (TMS 16 x
    16 order: left column of 8 x 8s, then the right), then plane 1"""
    h, w = len(g), len(g[0])
    def px(x, y): return g[y][x] if 0 <= x < w and 0 <= y < h else 0
    out = []
    for bit in (1, 2):
        for half in (0, 8):
            for y in range(16):
                out.append(sum(0x80 >> i for i in range(8) if px(x0 + half + i, y0 + y) & bit))
    return tuple(out)


def main():
    # ---- tiles
    T = A.tiles()
    castle = A.chip_castle()
    art = {}
    for i, (name, ch, solid, pic) in enumerate(gen.TILES):
        if name in T: art[i] = T[name]
    for ty, row in enumerate(gen.CHIP):
        for tx, t in enumerate(row):
            g = [r[tx * 16:tx * 16 + 16] for r in castle[ty * 16:ty * 16 + 16]]
            if t in art:
                if t not in T and art[t][0] != g: print('note: castle tile %d differs at %d,%d' % (t, tx, ty))
                continue
            art[t] = (g, A.PS_GREY)
    missing = [gen.TILES[i][0] for i in range(len(gen.TILES)) if i not in art]
    assert not missing, missing
    pat = {}                      # (planes, ps) -> number
    free = [n for n in range(1, 256) if not (0x20 <= n < 0x60)]
    tile_nm = []
    for i in range(len(gen.TILES)):
        g, ps = art[i]
        for cy in range(2):
            for cx in range(2):
                c = cell(g, cx, cy)
                if not any(c): tile_nm.append(0); continue
                k = (c, ps)
                if k not in pat: pat[k] = free.pop(0)
                tile_nm.append(pat[k])
    npat = max(list(pat.values()) + [0x5F]) + 1
    p0 = [0] * (npat * 8); p1 = [0] * (npat * 8); attr = [TRANS] * 256
    for (c, ps), n in pat.items():
        p0[n * 8:n * 8 + 8] = c[:8]; p1[n * 8:n * 8 + 8] = c[8:]
        attr[n] = TRANS | ps
    font = bold_font()
    for i in range(64):
        n = 0x20 + i
        p1[n * 8:n * 8 + 8] = font[i * 8:i * 8 + 8]      # value 2: white
        attr[n] = A.PS_TEXT                              # (opaque: black behind)
    # ---- sprites
    parts = []
    pidx = {}
    def pnum(b):
        if not any(b): return None
        if b not in pidx: pidx[b] = len(parts); parts.append(b)
        return pidx[b]
    EP = A.enemy_pics()
    def feet_down(rows):
        # move empty bottom rows to the top, so the feet stand on the
        # picture's bottom edge (= the ground in the game)
        n = 0
        while n < len(rows) and not rows[len(rows) - 1 - n].strip('.'): n += 1
        return [rows[0].__class__('.' * len(rows[0]))] * n + list(rows[:len(rows) - n]) if n else rows
    STANDS = ('AND1', 'AND2', 'AND_FLAT', 'OR1', 'OR2', 'OR_SHELL', 'MUSH', 'ONEUP',
              'FLOWER', 'PRINCESS')
    lists = []
    most = 0
    for name in gen.ORDER:
        orig = gen.SPR[name]
        wpic, hpic = 2 * len(orig[0]), 2 * len(orig)        # the picture's size on the screen
        layers = []                                         # (grid, ps)
        if name.startswith(('MOS_', 'BIG_', 'FIRE_')):
            key = name.replace('FIRE_', 'BIG_')
            rows = A.SPR_HD[key]
            if len(rows) == hpic and name not in ('MOS_DEAD',): rows = feet_down(rows)
            base = [[A.MOS_LET[c][1] if c != '.' and A.MOS_LET[c][0] == 0 else 0 for c in r] for r in rows]
            over = [[A.MOS_LET[c][1] if c != '.' and A.MOS_LET[c][0] == 1 else 0 for c in r] for r in rows]
            layers = [(over, A.PS_MOSD), (base, A.PS_FIRE if name.startswith('FIRE_') else A.PS_MOS)]
        else:
            rows, ps = EP[name]
            if name in STANDS and len(rows) == hpic: rows = feet_down(rows)
            g = [[0 if c == '.' else int(c) for c in r] for r in rows]
            layers = [(g, ps)]
        for mir in range(2):
            ent = []
            for g, ps in layers:
                H, W = len(g), len(g[0])
                for y0 in range(0, H, 16):
                    for x0 in range(0, W, 16):
                        b = part(g, x0, y0)
                        n = pnum(b)
                        if n is None: continue
                        dx = x0
                        if mir: dx = wpic - 16 - x0             # mirrored: the part flipped, its place too
                        ent.append((dx // 2, y0 // 2, n, ps | (FLIPX if mir else 0)))
            most = max(most, len(ent))
            lists.append(ent)
    # ---- write
    o = ['; smb_pico.inc - made by gen_pico.py (art_hd.py\'s art); run  python gen_pico.py\n']
    o.append('NTILE = %d\n' % len(gen.TILES))
    for i, t in enumerate(gen.TILES): o.append('T_%-8s = %d\n' % (t[0], i * 4))
    for i, n in enumerate(gen.ORDER): o.append('SP_%-12s = %d\n' % (n, i))
    o.append('NSPR = %d\n' % len(gen.ORDER))
    import levels
    o.append('NWORLDS = %d\n' % len(levels.WORLDS))
    o.append('NPART = %d                ; sprite parts (64 bytes each)\n' % len(parts))
    def rows(name, data, per=16):
        s = name + ':\n'
        for i in range(0, len(data), per):
            s += '        .byte   ' + ','.join('$%02X' % (v & 0xFF) for v in data[i:i + per]) + '\n'
        return s
    o.append('; by tile number * 4: solid (1)\n' + rows('tile_solid', sum([[t[2]] * 4 for t in gen.TILES], [])))
    o.append('; by tile number * 4: its 4 cells\' patterns (top left, top right, bottom left, bottom right)\n' + rows('tile_nm', tile_nm))
    o.append('; the tile patterns: plane 0, plane 1 (8 bytes a pattern, from 0)\n')
    o.append('NPAT = %d\n' % npat + rows('tile_p0', p0) + rows('tile_p1', p1))
    o.append('; the attribute of each pattern (both layers): TRANS, the colour group\n' + rows('tile_attr', attr))
    pal = []
    for grp in A.PAL:
        for c in grp: pal += [c >> 8, c & 0xFF]
    o.append('; the palette: 64 entries (0000RRRR, GGGGBBBB)\n' + rows('pal_data', pal))
    data = []; idx = []
    for ent in lists:
        idx.append(len(data))
        data.append(len(ent))
        for dx, dy, p, c in ent: data += [dx & 0xFF, dy, p, c]
    o.append('; sprite lists by picture * 2 + mirrored: count, then dx, dy (game pixels), part, attribute\n')
    o.append('sp_lo:\n' + ''.join('        .byte   <(sp_data+%d)\n' % k for k in idx))
    o.append('sp_hi:\n' + ''.join('        .byte   >(sp_data+%d)\n' % k for k in idx))
    o.append(rows('sp_data', data))
    o.append('; the sprite parts: 64 bytes each (plane 0, plane 1)\n' + rows('spr_parts', [b for p in parts for b in p]))
    open(os.path.join(HERE, 'smb_pico.inc'), 'w').write(''.join(o))
    print('smb_pico.inc: %d tiles -> %d patterns (up to $%02X); %d sprite parts (%d bytes); lists %d bytes; most parts in a picture %d'
          % (len(gen.TILES), len(pat), npat - 1, len(parts), 64 * len(parts), len(data), most))
    if len(sys.argv) > 1: sheet(art, parts)


def sheet(art, parts):
    from PIL import Image
    S = 3
    def rgb(c): return ((c >> 8) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17)
    im = Image.new('RGB', (16 * 18 * S, 14 * 18 * S), rgb(A.PAL[1][1]))
    px = im.load()
    for i, (g, ps) in sorted(art.items()):
        ox, oy = (i % 16) * 18 * S, (i // 16) * 18 * S
        for y in range(16):
            for x in range(16):
                if g[y][x]:
                    for a in range(S):
                        for b in range(S): px[ox + x * S + a, oy + y * S + b] = rgb(A.PAL[ps][g[y][x]])
    im.save(os.path.join(HERE, 'sheet.png'))


if __name__ == '__main__':
    main()
