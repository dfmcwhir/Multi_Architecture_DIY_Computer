# usage (from the muncher folder):
#   ca65 -g muncher.s -o t.o ; ld65 -C muncher.cfg t.o -o t.bin -Ln muncher.lbl
#   PY65=path/to/py65 python3 test/play.py OUTDIR        (PAD=1: play with the gamepad)
"""Play MUNCHER with a bot and check every tile on screen against the game state."""
import sys, os, re, collections
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from sim import Machine
import gen  # noqa  (sprite drawings)

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
PAD = os.environ.get('PAD') == '1'
syms = {}
for line in open('muncher.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('muncher.map').read()).group(1), 16)
mc = Machine('MUNCHER.BIN', speed=0, code_end=code_end)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
W, H = 39, 21
SPR = {name: gen.mosaic(rows) for name, rows in gen.SPRITES}
SPR_BY_OFS = {i * 2: gen.mosaic(rows) for i, (name, rows) in enumerate(gen.SPRITES)}
TILEG = [gen.mosaic(rows) for name, rows in gen.TILES]
DX = [0, -1, 0, 1]; DY = [-1, 0, 1, 0]

def tile(x, y): return mem[syms['maze'] + y * 40 + x]
def is_open(x, y):
    if not (0 <= x < W and 0 <= y < H): return True
    return tile(x, y) not in (3, 4)
NB = [((0, -1), 0x03, 0x03), ((0, 1), 0xC0, 0xC0), ((-1, 0), 0x55, 0), ((1, 0), 0, 0xAA),
      ((-1, -1), 0x01, 0), ((1, -1), 0, 0x02), ((-1, 1), 0x40, 0), ((1, 1), 0, 0x80)]
def tile_gfx(x, y):
    t = tile(x, y)
    if t != 3: return TILEG[t]
    a = b = 0
    for (dx, dy), ml, mr in NB:
        if is_open(x + dx, y + dy): a |= ml; b |= mr
    return [a, b]
def screen_cell(col, row):
    b = 0
    for i in range(8):
        b |= mc.term.pix[row * 4 + i // 2][col * 2 + (i & 1)] << i
    return b

problems = []
def check():
    want = collections.defaultdict(list)    # drawn actors (when two share a tile either may be on top)
    for i in range(5):
        if v('adrawn', i): want[(v('adx', i), v('ady', i))].append(list(SPR_BY_OFS[v('aspr', i)]))
    if v('adrawn', 0):                      # ...but the muncher is always on top
        want[(v('adx', 0), v('ady', 0))] = [list(SPR_BY_OFS[v('aspr', 0)])]
    bad = 0
    for y in range(H):
        for x in range(W):
            ok = want.get((x, y)) or [list(tile_gfx(x, y))]
            w = ok[0]
            got = [screen_cell(2 * x, y), screen_cell(2 * x + 1, y)]
            if got not in ok:
                bad += 1
                if bad <= 2: problems.append('tick %d tile %d,%d screen %s want %s' % (ticks, x, y, got, w))

def ghosts():
    return [(v('ax', i), v('ay', i), v('gst', i), v('gfr', i)) for i in range(1, 5)]
def passable(x, y): return 0 <= y < H and tile(x % W, y) <= 2
def bfs(sx, sy, goal, avoid):
    prev = {(sx, sy): None}; q = collections.deque([(sx, sy)])
    while q:
        p = q.popleft()
        if p != (sx, sy) and goal(*p):
            while prev[p] != (sx, sy) and prev[p] is not None: p = prev[p]
            return p
        for d in range(4):
            n = ((p[0] + DX[d]) % W, p[1] + DY[d])
            if n not in prev and passable(*n) and n not in avoid:
                prev[n] = p; q.append(n)
    return None

ticks = 0; last = {}; stats = collections.Counter(); prev_state = {}
def bot(m):
    global ticks
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']) or m.keys: return
    if m.mpu.processorCycles - last.get('c', 0) < 1500: return
    last['c'] = m.mpu.processorCycles
    ticks += 1
    if ticks % 5 == 0: check()
    if ticks in (30, 400, 1500): m.term.png('%s/t%05d.png' % (OUT, ticks))
    px, py = v('ax'), v('ay')
    gs = ghosts()
    danger = set()
    for gx, gy, st, fr in gs:
        if st == 2 and not fr:
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    if abs(dx) + abs(dy) <= 2: danger.add(((gx + dx) % W, gy + dy))
    prey = {(gx, gy) for gx, gy, st, fr in gs if st == 2 and fr}
    step = None
    if prey and v('fr_t') > 40: step = bfs(px, py, lambda x, y: (x, y) in prey, danger)
    if not step: step = bfs(px, py, lambda x, y: tile(x, y) in (1, 2), danger)
    if not step: step = bfs(px, py, lambda x, y: tile(x, y) in (1, 2), set())
    if not step:
        if PAD: m.set_pad(0)
        return
    for d in range(4):
        if ((px + DX[d]) % W, py + DY[d]) == step: break
    if PAD:
        m.set_pad({0: 0x10, 1: 0x40, 2: 0x20, 3: 0x80}[d])
    elif v('want') != d:
        m.keys.append(ord('wasd'[d]))

mc.run(2500000)
mc.term.png(OUT + '/title.png')
if PAD:
    mc.set_pad(0x08); mc.run(60000); mc.set_pad(0)
else:
    mc.keys.append(ord(' '))
mc.run(3000000)
mc.term.png(OUT + '/ready.png')
import time; t0 = time.time()
levels = 0; lv = v('level'); lives = v('lives'); deaths = 0; eaten = 0
for step in range(int(os.environ.get('STEPS', '3000'))):
    mc.run(300000, poll=bot)
    if v('level') != lv:
        levels += 1; lv = v('level'); print('level cleared at tick', ticks, 'score %02X%02X%02X' % (v('score', 2), v('score', 1), v('score')), flush=True)
        mc.term.png('%s/level%d.png' % (OUT, lv))
    if v('lives') != lives:
        if v('lives') < lives: deaths += 1; print('lost a life at tick', ticks, 'dots left', v('dots') + 256 * v('dots', 1), flush=True)
        lives = v('lives')
    if lives == 0 or levels >= int(os.environ.get('LEVELS', '2')) or mc.exited: break
    if step % 50 == 0: print('step', step, 'tick', ticks, 'dots', v('dots') + 256 * v('dots', 1), '%.0fs' % (time.time() - t0), flush=True)
# the last check: at the start of a game tick (when the game reads the
# keys), so nothing is half drawn
done_check = []
def at_tick(m):
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not done_check and syms['read_input'] <= ret < syms['handle_key']:
        done_check.append(1); check()
for k in range(400):
    if done_check or mc.exited: break
    mc.run(5000, poll=at_tick)
mc.term.png(OUT + '/end.png')
print('ticks %d, levels cleared %d, lives lost %d, score %02X%02X%02X, eat_n now %d' % (ticks, levels, deaths, v('score', 2), v('score', 1), v('score'), v('eat_n')))
print('terminal errors:', mc.term.errors[:5])
print('screen mismatches:', len(problems)); print('\n'.join(problems[:10]))
if os.environ.get('DEBUGACT'):
    for i in range(5): print('actor', i, 'at', v('ax', i), v('ay', i), 'drawn', v('adrawn', i), 'at', v('adx', i), v('ady', i), 'spr', v('aspr', i))
    print('cur', v('cur_x'), v('cur_y'), 'attr %02X rep %d' % (v('attr'), v('cur_rep')), 'level', v('level'))
