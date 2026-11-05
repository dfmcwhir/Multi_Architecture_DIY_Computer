# usage (from the snake folder): ca65 -g snake.s -o t.o ; ld65 -C snake.cfg t.o -o t.bin -Ln snake.lbl
#   PY65=path/to/py65 python3 test/play.py shots
"""Play Snake with a bot and check the screen against the grid in RAM after every move."""
import sys, os, re, random
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
syms = {}
for line in open('snake.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)

GW, GH = 79, 45
DX = {1: 0, 2: 1, 3: 0, 4: -1}; DY = {1: -1, 2: 0, 3: 1, 4: 0}
KEY = {1: 'w', 2: 'd', 3: 's', 4: 'a'}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('snake.map').read()).group(1), 16)
PAD = os.environ.get('PAD') == '1'
mc = Machine('SNAKE.BIN', speed=3, code_end=code_end)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
def g(x, y): return mem[syms['grid'] + y * GW + x]

problems = []
def check():
    pix = mc.term.pix
    fx, fy = v('food_x'), v('food_y')
    n = 0
    for y in range(GH):
        for x in range(GW):
            px, py = 1 + 2 * x, 5 + 2 * y
            got = (pix[py][px], pix[py][px + 1], pix[py + 1][px], pix[py + 1][px + 1])
            occ = g(x, y) != 0
            n += occ
            if occ: want = (1, 1, 1, 1)
            elif (x, y) == (fx, fy): want = (1, 0, 0, 1)
            else: want = (0, 0, 0, 0)
            if got != want and not (v('dead') and (x, y) == (v('head_x'), v('head_y'))):
                # (after a crash the head flashes on and off)
                problems.append('move %d cell %d,%d grid=%d screen %s want %s' % (moves, x, y, g(x, y), got, want))
    # border
    for x in range(160):
        if not (pix[4][x] and pix[95][x]): problems.append('border gap at x %d' % x); break
    for y in range(4, 96):
        if not (pix[y][0] and pix[y][159]): problems.append('border gap at y %d' % y); break
    # follow the body from the tail: it must reach the head and cover every occupied cell
    x, y, k = v('tail_x'), v('tail_y'), 1
    while (x, y) != (v('head_x'), v('head_y')) and k <= n:
        d = g(x, y)
        if d not in DX: problems.append('move %d: broken body at %d,%d' % (moves, x, y)); break
        x, y, k = x + DX[d], y + DY[d], k + 1
    if k != n: problems.append('move %d: body length %d but %d cells occupied' % (moves, k, n))
    return n

moves = 0; last = {}; maxlen = 0; games = []
def safe(x, y): return 0 <= x < GW and 0 <= y < GH and g(x, y) == 0
def bot(m):
    global moves, maxlen
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not (syms['read_keys'] <= ret < syms['handle_key']) or m.keys: return     # getc from read_keys
    if m.mpu.processorCycles - last.get('c', 0) < 1500: return
    last['c'] = m.mpu.processorCycles
    moves += 1
    if moves % 5 == 0:
        maxlen = max(maxlen, check())
    if moves in (40, 600): m.term.png('%s/move%04d.png' % (OUT, moves))
    hx, hy, fx, fy, d = v('head_x'), v('head_y'), v('food_x'), v('food_y'), v('dir')
    if PAD and v('kq_n') == 0:        # the press is read next tick: aim from where the head will be
        hx, hy = hx + DX[d], hy + DY[d]
        if not (0 <= hx < GW and 0 <= hy < GH): hx, hy = hx - DX[d], hy - DY[d]
    opts = []
    for nd in (1, 2, 3, 4):
        if nd == {1: 3, 3: 1, 2: 4, 4: 2}[d]: continue
        nx, ny = hx + DX[nd], hy + DY[nd]
        if safe(nx, ny):
            free = sum(safe(nx + DX[e], ny + DY[e]) for e in DX)
            opts.append((abs(nx - fx) + abs(ny - fy) - free * 0.3 + random.random() * 0.1, nd))
    if mode_crash and moves > 300:          # let it hit something
        if PAD: m.set_pad(0)
        return
    if PAD: m.set_pad(0)       # release, so the next press is a new one
    if opts:
        nd = min(opts)[1]
        if nd != d:
            if PAD: m.set_pad({1: 0x10, 2: 0x80, 3: 0x20, 4: 0x40}[nd])
            else: m.keys.append(ord(KEY[nd]))

random.seed(1)
mode_crash = False
mc.run(600000); mc.term.png(OUT + '/title.png')
if PAD:
    mc.set_pad(0x08); mc.run(100000); mc.set_pad(0); mc.run(100000)
    print('controls after Start:', 'gamepad' if v('ctrl') else 'keyboard')
else:
    mc.keys.append(ord(' '))
for game in range(2):
    mode_crash = game == 1
    while not v('dead') and moves < int(os.environ.get('MAXMOVES', '100000')):
        mc.run(300000, poll=bot)
        if moves >= int(os.environ.get('MAXMOVES', '100000')) and not v('dead'): mode_crash = True
    check()
    games.append((v('score') | v('score', 1) << 8, moves))
    mc.run(3000000)
    while mc.keys: mc.keys.pop()
    mc.term.png('%s/over%d.png' % (OUT, game))
    print('game %d over: score %04X, moves %d, longest snake %d, hiscore %04X' % (game, games[-1][0], moves, maxlen, v('hiscore') | v('hiscore', 1) << 8), flush=True)
    moves = 0
    if game == 0:
        if PAD:
            mc.set_pad(0x01); mc.run(50000); mc.set_pad(0)
        else:
            mc.keys.append(ord(' '))
        while v('dead'): mc.run(20000)
mc.run(500000)
mc.keys.append(ord('q'))
mc.run(3000000, poll=None)
print('quit -> back through reset vector:', mc.exited)
print('terminal errors:', mc.term.errors[:10])
print('screen/state mismatches:', len(problems)); print('\n'.join(problems[:15]))
