"""gen_colours.py - the colour tables for DOOM on the PICO9918 -> colours.inc

TMS9918 colours: 1 black, 2 medium green, 3 light green, 4 dark blue,
5 light blue, 6 dark red, 7 cyan, 8 medium red, 9 light red, A dark yellow,
B light yellow, C dark green, D magenta, E grey, F white.
Change the numbers below, run  python gen_colours.py , rebuild.
Colours 7 (cyan) and 13/9 (unless the palette is used) are free."""

# walls: for each style, (pixels, gaps) of the side facing x, then of the
# side facing y (darker).  The walls are dithered: the gaps get a darker
# shade of the same colour.
WALL = {0: ((15, 1), (15, 1)),    # (unused)
        1: ((8, 1), (6, 1)),      # brick: red dots on black
        2: ((5, 4), (4, 1)),      # tech: blue
        3: ((15, 14), (14, 1)),   # stone: white / grey
        4: ((11, 10), (10, 1)),   # door: yellow
        5: ((3, 2), (2, 12))}     # exit switch: green
THING = {0: 15, 1: 3,    # grunt: light green
         2: 8,           # brute: red
         3: 15,          # medkit: white
         4: 11}          # ammo: yellow
DEAD, GUN, FLASH = 6, 14, 11

# the ceiling and the floor: three choices, picked by the byte at $0806.
# Each is a list of (first pixel row, colour of its first screen line, colour
# of its second) up to the horizon (row 36) and on to the bottom (row 72);
# two different colours make stripes.
GROUND = [
    # 0: black
    [(0, 1, 1)],
    # 1: solid dark colours (made with the palette, below), a line of black
    #    between them and the horizon
    [(0, 13, 13), (32, 13, 1), (36, 1, 1), (38, 1, 9), (40, 9, 9)],
    # 2: stripes: blue at the top, grey at the bottom
    [(0, 4, 1), (15, 1, 1), (57, 14, 1)],
]
# style 1 redefines two colours DOOM doesn't otherwise use (F18A palette;
# 0-15 each for red, green, blue).  Quitting puts the defaults back.
PALETTE = {13: (2, 2, 3),        # magenta -> dark slate (the ceiling)
           9: (4, 3, 2)}         # light red -> dark brown (the floor)
PAL_DEFAULT = {13: (12, 5, 12), 9: (15, 7, 6)}    # the F18A's defaults

out = ["; colours.inc - made by gen_colours.py", ""]
def tab(name, vals):
    out.append(name + ":")
    for i in range(0, len(vals), 16):
        out.append("        .byte   " + ", ".join("$%02X" % v for v in vals[i:i + 16]))
out.append("C_DEAD = $%X0" % DEAD)
out.append("C_GUN = $%X0" % GUN)
out.append("C_FLASH = $%X0" % FLASH)
tab("wall_col", [f << 4 | b for s in range(6) for f, b in WALL[s]])
tab("thing_col", [THING[t] << 4 for t in range(5)])
# the ground segments: end row, colour A, colour B (with white "ink")
seg = []; start = []
for style in GROUND:
    start.append(len(seg))
    for i, (r, c1, c2) in enumerate(style):
        end = style[i + 1][0] if i + 1 < len(style) else 72
        seg += [end, 0xF0 | c1, 0xF0 | c2]
tab("gseg", seg); tab("gseg_start", start)
out.append("GROUND_N = %d" % len(GROUND))
def pal(d):
    return [b for i in (9, 13) for b in (d[i][0], d[i][1] << 4 | d[i][2])]
tab("pal_dark", pal(PALETTE)); tab("pal_def", pal(PAL_DEFAULT))
# cells: 8 characters (3 pixels each) make 3 cells; cell k of a group spans
# characters 0-2, 2-5, 5-7; its wall is the one in character 1, 3, 6
rep = []; first = []; last = []
for n in range(30):
    g, k = divmod(n, 3)
    rep.append(g * 8 + (1, 3, 6)[k])
    first.append(g * 8 + (0, 2, 5)[k])
    last.append(g * 8 + (2, 5, 7)[k])
tab("cellrep", rep); tab("cellfirst", first); tab("celllast", last)
# the gun's top pixel row in each cell ($FF: none).  It covers columns 37-42:
# from row 60 (39, 40), 64 (38, 41), 68 (37, 42); firing, the flash makes
# all of them start at row 56
top = {37: 68, 38: 64, 39: 60, 40: 60, 41: 64, 42: 68}
def gun_cells(fire):
    out_ = []
    for n in range(30):
        t = [56 if fire else top[c] for c in range(first[n], last[n] + 1) if c in top]
        out_.append(min(t) if t else 0xFF)
    return out_
tab("gun_cell", gun_cells(False)); tab("gun_cellf", gun_cells(True))
open("colours.inc", "w").write("\n".join(out) + "\n")
print("colours.inc written")
