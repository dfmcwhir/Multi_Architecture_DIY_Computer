#!/usr/bin/env python3
"""
genfont.py - build FontsExt.h for the PIC32 VT100 terminal.

Generates extra glyph tables that sit alongside the original fontOne / fontTwo
tables in Fonts.h (which are left untouched):

    fontOneX437[128][6]   fontTwoX437[128][13]   IBM code page 437, 0x80-0xFF
    fontOneXL1 [ 96][6]   fontTwoXL1 [ 96][13]   ISO 8859-1,        0xA0-0xFF
    fontOneXDEC[ 32][6]   fontTwoXDEC[ 32][13]   DEC special graphics 0x5F-0x7E

Glyph format is identical to the original tables: one unsigned int per pixel
column, bit k of the word = pixel row k (row 0 = top of the character cell).

Glyph sources
  * accented letters  - the original glyph is copied, capitals are squashed by
                        a few rows to make room, and an accent overlay is added
  * box / block chars - drawn procedurally so they join up across cells
  * everything else   - DejaVu Sans Mono, rasterised to the glyph size
"""
import re, sys, unicodedata
import numpy as np
from PIL import Image, ImageDraw, ImageFont

DEJAVU = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'

# --------------------------------------------------------------------------
# font geometry
# --------------------------------------------------------------------------
class Geo:
    pass

F1 = Geo()
F1.name, F1.W, F1.H = 'One', 6, 12
F1.cap_top, F1.base, F1.xh_top = 1, 7, 3
F1.squash = 1                         # rows removed from a capital that gets an accent
F1.acc_scale = 1
F1.acc_row_lower, F1.acc_row_cap = 0, 0
F1.cedilla = [(0, 0), (1, -1), (1, 0)]    # (row below baseline, dcol)
F1.vb = {1: [(2, 1)], 2: [(1, 1), (3, 1)]}      # vertical line bands  (start, width)
F1.hb = {1: [(5, 1)], 2: [(4, 1), (6, 1)]}      # horizontal line bands
F1.vcentre = 2.0
F1.hl = 1                                      # thickness of scan lines
F1.sym_cols = (0, 5)                           # glyph box for rasterised symbols

F2 = Geo()
F2.name, F2.W, F2.H = 'Two', 13, 20
F2.cap_top, F2.base, F2.xh_top = 2, 15, 7
F2.squash = 3
F2.acc_scale = 2
F2.acc_row_lower, F2.acc_row_cap = 2, 0
F2.cedilla = [(0, 0), (1, -1), (1, 0)]
F2.vb = {1: [(5, 2)], 2: [(3, 2), (7, 2)]}
F2.hb = {1: [(9, 2)], 2: [(7, 2), (11, 2)]}
F2.vcentre = 5.5
F2.hl = 2
F2.sym_cols = (1, 10)

# --------------------------------------------------------------------------
# read the original fonts
# --------------------------------------------------------------------------
def parse_font(src, name):
    m = re.search(r'const unsigned int ' + name + r'\[\d+\]\[\d+\]\s*=\s*\{(.*?)\n\};', src, re.S)
    rows = re.findall(r'\{([^{}]*)\}', m.group(1))
    return [[int(x, 16) for x in r.split(',') if x.strip()] for r in rows]

def cols_to_rows(cols, H):
    return [[(c >> r) & 1 for c in cols] for r in range(H)]

def rows_to_cols(rows):
    H, W = len(rows), len(rows[0])
    return [sum(rows[r][c] << r for r in range(H)) for c in range(W)]

def blank(g):
    return [[0] * g.W for _ in range(g.H)]

# --------------------------------------------------------------------------
# accented letters
# --------------------------------------------------------------------------
# accent shapes in "units": (row, dcol).  Font two draws each unit as a 2x2 block.
ACCENTS = {
    '́': [(0, 1), (1, 0)],                                  # acute
    '̀': [(0, -1), (1, 0)],                                 # grave
    '̂': [(0, 0), (1, -1), (1, 1)],                         # circumflex
    '̃': [(0, -1), (0, 1), (1, -2), (1, 0)],                # tilde
    '̈': [(1, -1), (1, 1)],                                 # diaeresis
    '̊': [(0, -1), (0, 0), (0, 1), (1, -1), (1, 1)],        # ring
}
CEDILLA = '̧'

def hamming(a, b):
    return sum(x != y for x, y in zip(a, b))

def squash(rows, top, bot, k):
    """remove k similar rows from rows[top..bot], keep the bottom on the baseline"""
    body = list(range(top, bot + 1))
    for _ in range(k):
        best = None
        for i in range(1, len(body) - 1):
            d = min(hamming(rows[body[i]], rows[body[i - 1]]), hamming(rows[body[i]], rows[body[i + 1]]))
            key = (d, abs(i - len(body) / 2))
            if best is None or key < best[0]:
                best = (key, i)
        del body[best[1]]
    out = [r[:] for r in rows]
    for r in range(top, bot + 1):
        out[r] = [0] * len(rows[0])
    n = len(body)
    for j, src in enumerate(body):
        out[bot - (n - 1) + j] = rows[src][:]
    return out

def compose(g, base_cols, mark, upper, is_i):
    rows = cols_to_rows(base_cols, g.H)
    if mark == CEDILLA:
        ink = [c for c in range(g.W) if any(rows[r][c] for r in range(g.H))]
        c0 = (min(ink) + max(ink)) // 2
        for (r, dc) in g.cedilla:
            for a in range(g.acc_scale):
                for b in range(g.acc_scale):
                    rr = g.base + 1 + r * g.acc_scale + a
                    cc = c0 + dc * g.acc_scale + b
                    if 0 <= rr < g.H and 0 <= cc < g.W:
                        rows[rr][cc] = 1
        return rows
    top = g.cap_top if upper else g.xh_top
    if is_i:                                            # remove the dot of an i
        for r in range(0, g.xh_top):
            rows[r] = [0] * g.W
    if upper:
        rows = squash(rows, g.cap_top, g.base, g.squash)
        top = g.cap_top + g.squash
    ink = [c for c in range(g.W) if any(rows[r][c] for r in range(top, g.base + 1))]
    c0 = (min(ink) + max(ink)) // 2
    r0 = g.acc_row_cap if upper else g.acc_row_lower
    s = g.acc_scale
    for (r, dc) in ACCENTS[mark]:
        for a in range(s):
            for b in range(s):
                rr = r0 + r * s + a
                cc = c0 + dc * s + b
                if 0 <= rr < g.H and 0 <= cc < g.W:
                    rows[rr][cc] = 1
    return rows

# --------------------------------------------------------------------------
# box drawing / blocks
# --------------------------------------------------------------------------
# (up, down, left, right) line style: 0 none, 1 single, 2 double
BOX = {
 '─':(0,0,1,1),'│':(1,1,0,0),'┌':(0,1,0,1),'┐':(0,1,1,0),'└':(1,0,0,1),'┘':(1,0,1,0),
 '├':(1,1,0,1),'┤':(1,1,1,0),'┬':(0,1,1,1),'┴':(1,0,1,1),'┼':(1,1,1,1),
 '═':(0,0,2,2),'║':(2,2,0,0),'╔':(0,2,0,2),'╗':(0,2,2,0),'╚':(2,0,0,2),'╝':(2,0,2,0),
 '╠':(2,2,0,2),'╣':(2,2,2,0),'╦':(0,2,2,2),'╩':(2,0,2,2),'╬':(2,2,2,2),
 '╒':(0,1,0,2),'╓':(0,2,0,1),'╕':(0,1,2,0),'╖':(0,2,1,0),'╘':(1,0,0,2),'╙':(2,0,0,1),
 '╛':(1,0,2,0),'╜':(2,0,1,0),'╞':(1,1,0,2),'╟':(2,2,0,1),'╡':(1,1,2,0),'╢':(2,2,1,0),
 '╤':(0,1,2,2),'╥':(0,2,1,1),'╧':(1,0,2,2),'╨':(2,0,1,1),'╪':(1,1,2,2),'╫':(2,2,1,1),
}

def box(g, u, d, l, r):
    H, W = g.H, g.W
    px = blank(g)
    Yl, Yr = g.hb.get(l, []), g.hb.get(r, [])
    Yall = Yl + Yr
    def first(b): return b[0]
    def last(b): return b[0] + b[1] - 1
    vlines = []                                   # (xs, w, up_end or None, down_start or None)
    def side(band):
        m = band[0] + (band[1] - 1) / 2.0
        return -1 if m < g.vcentre - 0.01 else (1 if m > g.vcentre + 0.01 else 0)
    ctr = H // 2
    for style, is_up in ((u, True), (d, False)):
        for band in g.vb.get(style, []):
            s = side(band)
            if s == 0:
                if Yall:
                    pos = last(max(Yall)) if is_up else first(min(Yall))
                else:
                    pos = ctr - 1 if is_up else ctr
            else:
                Ys, Yo = (Yl, Yr) if s < 0 else (Yr, Yl)
                if Ys:   pos = last(min(Ys)) if is_up else first(max(Ys))
                elif Yo: pos = last(max(Yo)) if is_up else first(min(Yo))
                else:    pos = ctr - 1 if is_up else ctr
            rng = range(0, pos + 1) if is_up else range(pos, H)
            for y in rng:
                for x in range(band[0], band[0] + band[1]):
                    px[y][x] = 1
            vlines.append(band)
    lines = sorted(set(vlines))
    def touching(b, band):
        return any(px[y][b[0]] for y in range(band[0], band[0] + band[1]))
    def cover(b, y):
        return 0 <= y < H and px[y][b[0]]
    bands_all = sorted(set(Yl + Yr))
    for band in bands_all:
        inl, inr = band in Yl, band in Yr
        both = inl and inr
        T, C = [], []
        for b in lines:
            if not touching(b, band): continue
            above, below = cover(b, band[0] - 1), cover(b, band[0] + band[1])
            (C if (above and below) else T).append(b)
        left_end = right_start = None
        if T:
            if both:
                right_start = max(T)[0]
                left_end = min(T)[0] + min(T)[1] - 1
            else:
                right_start = min(T)[0]
                left_end = max(T)[0] + max(T)[1] - 1
        elif both:
            left_end, right_start = W - 1, 0               # runs straight through
        elif C:
            right_start = max(C)[0]
            left_end = min(C)[0] + min(C)[1] - 1
        else:
            right_start = left_end = int(g.vcentre)
        for y in range(band[0], band[0] + band[1]):
            if inl:
                for x in range(0, left_end + 1): px[y][x] = 1
            if inr:
                for x in range(right_start, W): px[y][x] = 1
    return px

def block(g, ch):
    H, W = g.H, g.W
    px = blank(g)
    for y in range(H):
        for x in range(W):
            v = 0
            if ch == '█': v = 1
            elif ch == '▀': v = y < H // 2
            elif ch == '▄': v = y >= H // 2
            elif ch == '▌': v = x < (W + 1) // 2
            elif ch == '▐': v = x >= (W + 1) // 2
            elif ch == '░': v = (x % 2 == 0 and y % 2 == 0)
            elif ch == '▒': v = ((x + y) % 2 == 0)
            elif ch == '▓': v = not (x % 2 == 1 and y % 2 == 1)
            px[y][x] = 1 if v else 0
    return px

def scanline(g, n):
    """DEC scan lines 1,3,5,7,9 (n = 0..4)"""
    cy = g.hb[1][0][0]
    pos = [0, round(cy / 2), cy, round((cy + g.H - g.hl) / 2), g.H - g.hl][n]
    px = blank(g)
    for y in range(pos, pos + g.hl):
        for x in range(g.W): px[y][x] = 1
    return px

# --------------------------------------------------------------------------
# rasterised symbols
# --------------------------------------------------------------------------
_big = ImageFont.truetype(DEJAVU, 200, layout_engine=ImageFont.Layout.BASIC)
_small = ImageFont.truetype(DEJAVU, 9, layout_engine=ImageFont.Layout.BASIC)

def has_glyph(ch):
    from fontTools.ttLib import TTFont
    global _cmap
    try: _cmap
    except NameError: _cmap = TTFont(DEJAVU).getBestCmap()
    return ord(ch) in _cmap

def symbol_one(ch):
    asc = _small.getmetrics()[0]
    img = Image.new('1', (6, 12), 0)
    d = ImageDraw.Draw(img); d.fontmode = '1'
    d.text((0, F1.base + 1 - asc), ch, font=_small, fill=1)
    px = np.array(img, dtype=int).tolist()
    for y in range(12): px[y][5] = 0                  # keep the spacing column clear
    return px

def symbol_two(ch, thresh=0.38):
    adv = _big.getlength('M')
    asc = _big.getmetrics()[0]
    caph = asc - _big.getbbox('H')[1]
    sx = (F2.sym_cols[1] - F2.sym_cols[0] + 1) / adv
    sy = (F2.base - F2.cap_top + 1) / float(caph)
    big = Image.new('L', (int(adv * 2), 400), 0)
    ImageDraw.Draw(big).text((int(adv / 2), 20), ch, font=_big, fill=255)
    a = np.array(big, dtype=float) / 255.0
    x_off = adv / 2
    base_y = 20 + asc
    out = np.zeros((F2.H, F2.W))
    for r in range(F2.H):
        y0 = base_y + (r - (F2.base + 1)) / sy
        y1 = base_y + (r + 1 - (F2.base + 1)) / sy
        for c in range(F2.W):
            x0 = x_off + (c - F2.sym_cols[0]) / sx
            x1 = x_off + (c + 1 - F2.sym_cols[0]) / sx
            xa, xb, ya, yb = int(round(x0)), int(round(x1)), int(round(y0)), int(round(y1))
            if xb <= xa: xb = xa + 1
            if yb <= ya: yb = ya + 1
            if xa < 0 or ya < 0 or xb > a.shape[1] or yb > a.shape[0]: continue
            out[r][c] = a[ya:yb, xa:xb].mean()
    return (out >= thresh).astype(int).tolist()

# --------------------------------------------------------------------------
# build the sets
# --------------------------------------------------------------------------
BLANKS = {' ', '\u0080'}
DEC_BLANK = {0x62, 0x63, 0x64, 0x65, 0x68, 0x69}       # HT FF CR LF NL VT symbols: not drawn

def build_glyph(g, base_font, ch, notes):
    """return a pixel row matrix for unicode char ch"""
    if ch in BLANKS or ch == ' ':
        return blank(g)
    if ch == '­':                                   # soft hyphen shows as hyphen
        return cols_to_rows(base_font[ord('-') - 32], g.H)
    if ch in BOX:
        return box(g, *BOX[ch])
    if ch in '█▀▄▌▐░▒▓':
        return block(g, ch)
    nfd = unicodedata.normalize('NFD', ch)
    if len(nfd) == 2 and nfd[0].isascii() and nfd[0].isalpha() and (nfd[1] in ACCENTS or nfd[1] == CEDILLA):
        b = nfd[0]
        return compose(g, base_font[ord(b) - 32], nfd[1], b.isupper(), b == 'i')
    if not has_glyph(ch):
        notes.append('no glyph for U+%04X' % ord(ch))
        return blank(g)
    return symbol_one(ch) if g is F1 else symbol_two(ch)

def cp437_char(b): return bytes([b]).decode('cp437')
def latin1_char(b): return bytes([b]).decode('latin-1')

DEC = {0x5f:' ',0x60:'◆',0x61:'▒',0x66:'°',0x67:'±',0x6a:'┘',0x6b:'┐',0x6c:'┌',0x6d:'└',0x6e:'┼',
       0x71:'─',0x74:'├',0x75:'┤',0x76:'┴',0x77:'┬',0x78:'│',0x79:'≤',0x7a:'≥',0x7b:'π',0x7c:'≠',
       0x7d:'£',0x7e:'·'}

C0CHARS = '☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼'      # the PC (DOS) glyphs for codes 0x01-0x1F

def build_sets(g, base_font, notes):
    cp437 = [build_glyph(g, base_font, cp437_char(b), notes) for b in range(0x80, 0x100)]
    c0 = [build_glyph(g, base_font, C0CHARS[i], notes) for i in range(31)]
    dec = []
    for c in range(0x5f, 0x7f):
        if c in DEC_BLANK:
            dec.append(blank(g))
        elif c in (0x6f, 0x70, 0x72, 0x73):
            dec.append(scanline(g, {0x6f: 0, 0x70: 1, 0x72: 3, 0x73: 4}[c]))
        else:
            dec.append(build_glyph(g, base_font, DEC[c], notes))
    return cp437, c0, dec

# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------
def uname(ch):
    try: return unicodedata.name(ch).lower()
    except ValueError: return 'u+%04x' % ord(ch)

def pack_cols(cols, bits):
    """pack the pixel columns (each 'bits' wide, most significant bit first) into bytes"""
    acc, n = 0, 0
    for c in cols:
        assert c < (1 << bits)
        acc = (acc << bits) | c; n += bits
    pad = (-n) % 8
    acc <<= pad; n += pad
    return acc.to_bytes(n // 8, 'big')

def c_table(name, g, glyphs, labels):
    nb = (g.W * g.H + 7) // 8
    out = ['const unsigned char %s[%d][%d] = {' % (name, len(glyphs), nb)]
    for rows, lab in zip(glyphs, labels):
        cols = rows_to_cols(rows)
        out.append('\t{ ' + ', '.join('0x%02X' % b for b in pack_cols(cols, g.H)) + ' },     // ' + lab)
    out.append('};\n')
    return '\n'.join(out)

def preview(sets, g, path):
    scale = 4
    cw, ch = g.W + 1, g.H + 1
    nrows = sum((len(gl) + 15) // 16 for _, gl, _ in sets) + len(sets) - 1
    img = Image.new('RGB', (16 * cw * scale, nrows * ch * scale), (20, 20, 60))
    px = img.load()
    row0 = 0
    for title, glyphs, first in sets:
        for i, rows in enumerate(glyphs):
            ox = (i % 16) * cw * scale
            oy = (row0 + i // 16) * ch * scale
            for r in range(g.H):
                for c in range(g.W):
                    col = (240, 240, 200) if rows[r][c] else (0, 0, 0)
                    for a in range(scale - 1):
                        for b in range(scale - 1):
                            px[ox + c * scale + a, oy + r * scale + b] = col
        row0 += (len(glyphs) + 15) // 16 + 1
    img.save(path)

def main():
    src = open(sys.argv[1], encoding='latin-1').read()
    f1 = parse_font(src, 'fontOne')
    f2 = parse_font(src, 'fontTwo')
    notes = []
    result = {}
    for g, base in ((F1, f1), (F2, f2)):
        result[g.name] = build_sets(g, base, notes)
    hdr = ['/*', ' FontsExt.h - generated by tools/genfont.py.  Do not edit by hand; edit the generator and rerun.', '',
           ' Extra glyph tables that complement fontOne/fontTwo in Fonts.h.  To save flash each glyph is packed: the pixel',
           ' columns (bit k = pixel row k, 12 bits wide for font one, 20 for font two) are joined, first column first, most',
           ' significant bit first.  Video.c unpacks a glyph into the same form as Fonts.h when it is drawn.',
           '   X437  code page 437, characters 0x80-0xFF  (index = code - 0x80)',
           '   XC0   the PC (DOS) glyphs for codes 0x01-0x1F (index = code - 1), shown with ESC-free literal code 0x1A',
           '   XDEC  DEC special graphics, 0x5F-0x7E      (index = code - 0x5F)',
           '*/', '']
    body = []
    for g in (F1, F2):
        cp437, c0, dec = result[g.name]
        body.append(c_table('font%sXC0' % g.name, g, c0, ['0x%02X %s' % (1 + i, uname(C0CHARS[i])) for i in range(31)]))
        body.append(c_table('font%sX437' % g.name, g, cp437, ['0x%02X %s' % (0x80 + i, uname(cp437_char(0x80 + i))) for i in range(128)]))
        body.append(c_table('font%sXDEC' % g.name, g, dec, ['0x%02X %s' % (0x5f + i, uname(DEC.get(0x5f + i, ' ')) if (0x5f + i) in DEC else 'scan line / unused') for i in range(32)]))
    open(sys.argv[2], 'w', encoding='ascii').write('\n'.join(hdr) + '\n'.join(body))
    if len(sys.argv) > 3:
        for g in (F1, F2):
            cp437, c0, dec = result[g.name]
            preview([('cp437', cp437, 0x80), ('c0', c0, 1), ('dec', dec, 0x5f)], g, '%s_%s.png' % (sys.argv[3], g.name))
    for n in notes: print('NOTE:', n)
    print('ok')

if __name__ == '__main__':
    main()
