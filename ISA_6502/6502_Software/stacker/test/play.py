# usage (from the stacker folder):
#   ca65 -g stacker.s -o t.o ; ld65 -C stacker.cfg t.o -o STACKER.BIN -Ln stacker.lbl
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: PAD=1 play with the gamepad, GARBAGE=n random RAM at power-up,
#                PIECES=n stop after n pieces, BAD=1 just drop every piece (to reach game over),
#                LEVEL=n starting level
"""Play STACKER with a bot.  For each piece it tries every rotation and
column, picks the best (few holes, low and flat), and plays it with real key
presses.  It keeps its own model of the board and checks the game's board,
lines and level against it after every piece, and checks every square on the
terminal against what the game says it shows."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from sim import Machine
import gen

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
PAD = os.environ.get('PAD') == '1'
BAD = os.environ.get('BAD') == '1'
NPIECES = int(os.environ.get('PIECES', '150'))
syms = {}
for line in open('stacker.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('stacker.map').read()).group(1), 16)
mc = Machine('STACKER.BIN', code_end=code_end, ctrl=1 if PAD else 0)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
def bcd(n, k): return int(''.join('%02X' % v(n, i) for i in reversed(range(k))))
W, H, HID = 10, 22, 2
CELLS = [rots for name, rots in gen.PIECES]
GL = [gen.chars(r) for r in gen.GLYPHS]

def board():
    return [[v('board', r * W + c) for c in range(W)] for r in range(H)]
def fits(b, t, x, y, r):
    for dx, dy in CELLS[t][r]:
        c, rr = x + dx, y + dy
        if not (0 <= c < W and rr < H) or b[rr][c]: return False
    return True
def drop(b, t, x, y, r):
    while fits(b, t, x, y + 1, r): y += 1
    return y
def place(b, t, x, y, r):
    b = [row[:] for row in b]
    for dx, dy in CELLS[t][r]: b[y + dy][x + dx] = t + 1
    full = [i for i in range(H) if all(b[i])]
    b = [[0] * W for _ in full] + [row for i, row in enumerate(b) if i not in full]
    return b, len(full)
def rotate_from(b, t, x, y, r0, r1):
    for k in ([0, -1, 1, -2, 2] if t == 0 else [0, -1, 1]):
        if fits(b, t, x + k, y, r1): return x + k
    return None
def score_board(b, n):
    hs = []
    holes = 0
    for c in range(W):
        h = 0
        for r in range(H):
            if b[r][c]: h = H - r; break
        hs.append(h)
        seen = False
        for r in range(H):
            if b[r][c]: seen = True
            elif seen: holes += 1
    bump = sum(abs(hs[i] - hs[i + 1]) for i in range(W - 1))
    return n * 8 - holes * 7.5 - sum(hs) * 0.5 - bump * 0.35 - max(hs) * 0.3
def plan(b, t, x0, y0, r0):
    """-> (keys, rotation, x) of the best placement reachable by turning at the top, then sliding"""
    best = None
    for nrot in range(4):
        r, x = r0, x0; ok = True; keys = []
        for i in range(nrot):
            nr = (r + 1) & 3
            nx = rotate_from(b, t, x, y0, r, nr)
            if nx is None: ok = False; break
            r, x = nr, nx; keys.append('ROT')
        if not ok: continue
        for d in (-1, 1):
            xx, ks = x, list(keys)
            while True:
                y = drop(b, t, xx, y0, r)
                nb, n = place(b, t, xx, y, r)
                s = score_board(nb, n)
                if best is None or s > best[0]: best = (s, ks + ['DROP'], r, xx, y)
                if not fits(b, t, xx + d, y0, r): break
                xx += d; ks = ks + ['L' if d < 0 else 'R']
    return best

problems = []
def say(*a): print(*a)
def screen_cell(col, row):
    b = 0
    for i in range(8): b |= mc.term.pix[row * 4 + i // 2][col * 2 + (i & 1)] << i
    return b
def check_screen():
    bad = 0
    for i in range(200):
        sh = v('shown', i)
        if sh == 0xFF: continue
        r, c = divmod(i, 10)
        col, row = 30 + 2 * c, 2 + r
        if [screen_cell(col, row), screen_cell(col + 1, row)] != GL[sh]: bad += 1
    if bad: problems.append('%d squares on the screen differ (piece %d)' % (bad, st['pieces']))

st = dict(pieces=0, keys=[], lasty=-1, lastt=None, model=None, lines=0, pending=0, expect=None, tick=-1, waitrel=False, over=False)
KEYMAP = {'ROT': 'W', 'L': 'A', 'R': 'D', 'DROP': ' '}
PADMAP = {'ROT': 0x01, 'L': 0x40, 'R': 0x80, 'DROP': 0x10}

def bot(m):
    if v('ticks') == st['tick']: return     # once per game tick
    st['tick'] = v('ticks')
    if PAD and st['waitrel']:          # release the button between presses
        mc.set_pad(0); st['waitrel'] = False; return
    if v('need_lock') or v('dead'): return
    t, x, y, r = v('ptype'), v('px'), v('py'), v('prot')
    if x >= 128: x -= 256
    new = v('npieces') != st['lasty']
    st['lasty'] = v('npieces')
    if new and not st['keys']:
        b = board()
        st['lines'] += st['pending']; st['pending'] = 0
        if st['expect'] is not None:     # the last piece: the board must be what the model says
            if b != st['expect']:
                problems.append('board differs after piece %d' % st['pieces'])
                if os.environ.get('DEBUG'):
                    for a, e in zip(b, st['expect']): print(''.join('.#'[bool(q)] for q in a), ''.join('.#'[bool(q)] for q in e))
                st['expect'] = None
        st['pieces'] += 1
        if v('dirty') == 0: check_screen()
        if st['pieces'] % 25 == 0: mc.term.png('%s/p%04d.png' % (OUT, st['pieces']))
        if BAD:
            st['keys'] = ['DROP']; y1 = drop(b, t, x, y, r)
            st['expect'], n = place(b, t, x, y1, r)
        else:
            best = plan(b, t, x, y, r)
            st['keys'] = list(best[1])
            st['expect'], n = place(b, t, best[3], best[4], best[2])
        st['pending'] = n
    if st['keys']:
        k = st['keys'].pop(0)
        if os.environ.get('DEBUG'): print('tick', st['tick'], 'piece', st['pieces'], k, 'x', x, 'y', y, 'r', r)
        if PAD:
            mc.set_pad(PADMAP[k]); st['waitrel'] = True
        else:
            mc.keys.append(ord(KEYMAP[k]))

def text():
    return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))

mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
if os.environ.get('LEVEL'):
    mc.keys.append(ord(os.environ['LEVEL'])); mc.run(500_000)
if PAD:
    mc.set_pad(0x08); mc.run(200_000); mc.set_pad(0); mc.run(200_000)
else:
    mc.keys.append(ord(' '))
mc.run(1_000_000)
while st['pieces'] < NPIECES:
    mc.run(500_000, bot)
    if 'GAME  OVER' in text():
        st['over'] = True; break
lines_end = bcd('lines', 2)     # (before the next piece, which no model follows)
mc.run(2_000_000)
mc.term.png(OUT + '/last.png')
say('pieces', st['pieces'], 'model lines', st['lines'], 'game lines', bcd('lines', 2), 'level', v('level'),
    'score', bcd('score', 3), 'high', bcd('hiscore', 3), 'game over', st['over'])
if lines_end not in (st['lines'], st['lines'] + st['pending']) and not st['over']:  # (lines being cleared: either)
    problems.append('lines %d, model %d (+%d)' % (lines_end, st['lines'], st['pending']))
lvl0 = int(os.environ.get('LEVEL', '0'))
if v('level') != lvl0 + bcd('lines', 2) // 10: problems.append('level %d for %d lines' % (v('level'), bcd('lines', 2)))
say('bytes sent', mc.term.nbytes, '(%.1f per piece)' % (mc.term.nbytes / max(1, st['pieces'])))
say('terminal errors', mc.term.errors[:5])
say('problems', len(problems), problems[:8])
