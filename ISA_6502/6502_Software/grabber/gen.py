"""Generate the data for GOLD GRABBER:  python gen.py > grabber_data.inc

The pictures (drawn here as text, '#' = a pixel), the hook's directions and a
table of squares."""
import math

# ---- pictures --------------------------------------------------------------------
SPR = {
    'GEM':      ['..#..',
                 '.###.',
                 '##.##',
                 '.###.',
                 '..#..'],
    'CHEST_S':  ['.#######.',
                 '#.......#',
                 '#########',
                 '#...#...#',
                 '#..###..#',
                 '#.......#',
                 '#########'],
    'CHEST_L':  ['..#########..',
                 '.#.........#.',
                 '#...........#',
                 '#############',
                 '#.....#.....#',
                 '#....###....#',
                 '#.....#.....#',
                 '#...........#',
                 '#############'],
    'ROCK_S':   ['..###..',
                 '.##.##.',
                 '###.###',
                 '#######',
                 '.#####.'],
    'ROCK_L':   ['...#####....',
                 '..###.####..',
                 '.#########..',
                 '#####.#####.',
                 '############',
                 '###.########',
                 '.######.####',
                 '..#########.',
                 '....#####...'],
    'GOPHER_R1':['.......###.',
                 '......##.##',
                 '.#########.',
                 '##########.',
                 '.########..',
                 '..#....#...'],
    'GOPHER_R2':['.......###.',
                 '......##.##',
                 '.#########.',
                 '##########.',
                 '.########..',
                 '.#....#....'],
    'TNT':      ['......#.',
                 '.....#.#',
                 '....#...',
                 '..####..',
                 '.######.',
                 '##.#####',
                 '#.######',
                 '########',
                 '.######.',
                 '..####..'],
    'BOOM1':    ['.....#...#.....',
                 '..#...#.#...#..',
                 '...#.#####.#...',
                 '....#######....',
                 '#.#####.#####.#',
                 '..####...####..',
                 '#.#####.#####.#',
                 '....#######....',
                 '...#.#####.#...',
                 '..#...#.#...#..',
                 '.....#...#.....'],
    'BOOM2':    ['#......#......#',
                 '..#.#.....#.#..',
                 '.#....###....#.',
                 '...#.#...#.#...',
                 '#...#.....#...#',
                 '.#.#...#...#.#.',
                 '#...#.....#...#',
                 '...#.#...#.#...',
                 '.#....###....#.',
                 '..#.#.....#.#..',
                 '#......#......#'],
    'TARGET':   ['..#..',
                 '.#.#.',
                 '#...#',
                 '.#.#.',
                 '..#..'],
    'MINER':    ['....####....',
                 '...######...',
                 '.##########.',
                 '...#.##.#...',
                 '...######...',
                 '....#..#....',
                 '..########..',
                 '.#.######.#.',
                 '#..######..#',
                 '...######...',
                 '...##..##...',
                 '...##..##...',
                 '..###..###..'],
    'WINCH1':   ['..####..',
                 '.#..#.#.',
                 '#...#..#',
                 '#...#..#',
                 '#...#..#',
                 '.#..#.#.',
                 '..####..'],
    'WINCH2':   ['..####..',
                 '.#....#.',
                 '#......#',
                 '########',
                 '#......#',
                 '.#....#.',
                 '..####..'],
    'PLATFORM': ['########################################',
                 '#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.##',
                 '########################################'],
}
# the gophers going left (mirrored) and carrying a gem
for f in ('1', '2'):
    SPR['GOPHER_L' + f] = [r[::-1] for r in SPR['GOPHER_R' + f]]
    rows = [r + '...' for r in SPR['GOPHER_R' + f]]
    for y, g in ((1, '.#.'), (2, '#.#'), (3, '.#.')):
        rows[y] = rows[y][:11] + g
    SPR['GOPHERG_R' + f] = rows
    SPR['GOPHERG_L' + f] = [r[::-1] for r in rows]

NDIR = 65               # the hook's directions: -75 .. +75 degrees from straight down
MAXDEG = 75

# the claw at the rope's end, turned the way the rope points: straight down,
# 45 degrees and sideways, and those mirrored.  'A' is where the rope ends.
CLAW_PICS = {
    '0':   (['..A..',
             '.###.',
             '#...#',
             '#...#'],
            ['.A.',
             '###',
             '#.#',
             '.#.']),
    '45':  (['A.#..',
             '.#.#.',
             '#...#',
             '.#...',
             '..#..'],
            ['A.#',
             '.##',
             '###']),
    '90':  (['..##',
             '.#..',
             'A#..',
             '.#..',
             '..##'],
            ['.##.',
             'A#.#',
             '.##.']),
}
NCLAW = 5               # left 90, left 45, down, right 45, right 90
TIP = 3                 # what it grabs with: this far along the rope
CLAW_OFS = {}
def claw_rows(rows, mirror):
    rows = [r[::-1] for r in rows] if mirror else rows
    for y, r in enumerate(rows):
        if 'A' in r: ox, oy = -r.index('A'), -y
    return [r.replace('A', '#') for r in rows], ox, oy
for k, (a, m) in enumerate((('90', 1), ('45', 1), ('0', 0), ('45', 0), ('90', 0))):
    for shut in (0, 1):
        name = 'CLAW%s%d' % ('S' if shut else '', k)
        rows, ox, oy = claw_rows(CLAW_PICS[a][shut], m)
        SPR[name] = rows; CLAW_OFS[name] = (ox, oy)
def dir_claw(i):
    """which claw picture for rope direction i"""
    deg = (i - (NDIR - 1) / 2) / ((NDIR - 1) / 2) * MAXDEG
    return 0 if deg < -57 else 1 if deg < -20 else 2 if deg <= 20 else 3 if deg <= 57 else 4

ORDER = ['GEM', 'CHEST_S', 'CHEST_L', 'ROCK_S', 'ROCK_L', 'TNT',
         'GOPHER_R1', 'GOPHER_R2', 'GOPHER_L1', 'GOPHER_L2',
         'GOPHERG_R1', 'GOPHERG_R2', 'GOPHERG_L1', 'GOPHERG_L2',
         'BOOM1', 'BOOM2', 'TARGET', 'MINER', 'WINCH1', 'WINCH2', 'PLATFORM'] + \
        ['CLAW%d' % k for k in range(NCLAW)] + ['CLAWS%d' % k for k in range(NCLAW)]
assert sorted(ORDER) == sorted(SPR)

def sprite_bytes(rows):
    w, h = len(rows[0]), len(rows)
    assert all(len(r) == w for r in rows)
    nb = (w + 7) // 8
    out = [w, h, nb]
    for r in rows:
        bits = r.ljust(nb * 8, '.')
        for k in range(nb):
            v = 0
            for i, ch in enumerate(bits[k * 8:k * 8 + 8]):
                if ch == '#': v |= 0x80 >> i
            out.append(v)
    return out

SP_ORD = {n: i for i, n in enumerate(ORDER)}
def tdirs(): return [math.radians((i - (NDIR - 1) / 2) / ((NDIR - 1) / 2) * MAXDEG) for i in range(NDIR)]
def dirs():
    sx, cy = [], []
    for i in range(NDIR):
        t = math.radians((i - (NDIR - 1) / 2) / ((NDIR - 1) / 2) * MAXDEG)
        sx.append(round(math.sin(t) * 127)); cy.append(round(math.cos(t) * 127))
    return sx, cy

def bl(vals): return ', '.join('$%02X' % (v & 255) for v in vals)
def lines(name, vals, per=16, comment=''):
    print('%s:%s' % (name, ('   ; ' + comment) if comment else ''))
    for i in range(0, len(vals), per): print('        .byte   ' + bl(vals[i:i + per]))

def main():
    print('; generated by gen.py')
    for i, n in enumerate(ORDER): print('SP_%-10s = %d' % (n, i))
    print('NSPR = %d' % len(ORDER))
    data = []; idx = []
    for n in ORDER:
        idx.append(len(data)); data += sprite_bytes(SPR[n])
    print('spr_lo:'); print('        .byte   ' + ', '.join('<(spr_data+%d)' % k for k in idx))
    print('spr_hi:'); print('        .byte   ' + ', '.join('>(spr_data+%d)' % k for k in idx))
    lines('spr_data', data, comment='width, height, bytes a row, then the rows (bit 7 = the left pixel)')
    sx, cy = dirs()
    print('NDIR = %d' % NDIR)
    lines('dir_sx', [abs(v) for v in sx], comment='|sin| * 127 of each direction')
    lines('dir_neg', [1 if v < 0 else 0 for v in sx], comment='1: to the left')
    lines('dir_cy', cy, comment='cos * 127')
    print('NCLAW = %d' % NCLAW)
    lines('dir_claw', [SP_ORD['CLAW%d' % dir_claw(i)] for i in range(NDIR)], comment="the claw's picture (open; shut: + NCLAW)")
    claws = [n for n in ORDER if n.startswith('CLAW')]
    assert claws == ORDER[SP_ORD['CLAW0']:SP_ORD['CLAW0'] + 2 * NCLAW]
    lines('claw_ox', [CLAW_OFS[n][0] for n in claws], comment='its top left from the rope end, by picture - SP_CLAW0')
    lines('claw_oy', [CLAW_OFS[n][1] for n in claws])
    lines('tip_dx', [round(TIP * math.sin(t)) for t in tdirs()], comment='what it grabs with: the rope end + this')
    lines('tip_dy', [round(TIP * math.cos(t)) for t in tdirs()])
    sq = [k * k for k in range(32)]
    lines('sq_lo', [v & 255 for v in sq], comment='squares 0..31')
    lines('sq_hi', [v >> 8 for v in sq])

if __name__ == '__main__': main()
