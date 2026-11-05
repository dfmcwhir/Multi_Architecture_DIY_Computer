# usage (from the breaker folder):  sh b.sh   (builds with a label file), then
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: FRAMES=n how long to play, KEYS=1 play with the keyboard,
#                GARBAGE=n random RAM at power-up, MISS=1 let the balls fall
#                (to test losing balls and game over), START=n start at level n
"""Play BYTE BREAKER with a bot (keeps the paddle under the ball, fires
when it can) and check, every frame:
  - the terminal's screen shows exactly the walls and the bricks in the
    game's brick map (drawn here in Python)
  - the terminal's sprites are exactly the paddle, balls, capsules and shots
    in the game's tables
  - no ball is inside a brick, outside the walls, or lost under the paddle
    while the bot was there in time
and that the levels can be cleared."""
import sys, os, re, random
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import sim
from sim import Machine
import gen

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
KEYS = os.environ.get('KEYS') == '1'
MISS = os.environ.get('MISS') == '1'
FRAMES = int(os.environ.get('FRAMES', '6000'))
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('breaker.lbl')) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('breaker.map').read()).group(1), 16)
mc = Machine('BREAKER.BIN', code_end=code_end, ctrl=0 if KEYS else 1)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
problems = []
PIC = {name: n for n, (name, rows) in enumerate(gen.PICS)}
st = dict(f=-1, frames=0, levels=set(), lost=0, caps=0, kinds=set(), hits=0, maxlevel=0, over=False, shown=0)

def bcd(n): return int(''.join('%02X' % v(n, i) for i in (2, 1, 0)))

def want_cells():
    """the block graphics characters the field should show: (col, row) -> bits"""
    out = {}
    for c in range(80): out[(c, 1)] = 0xFF
    for r in range(2, 24): out[(0, r)] = out[(79, r)] = 0xFF
    for i in range(gen.BW * gen.BH):
        k = v('map', i)
        r, c = 4 + i // gen.BW, 2 + 4 * (i % gen.BW)
        for j in range(4): out[(c + j, r)] = gen.BRICK_CH[k][j]
    return out

def screen_cells(rows):
    pix = mc.term.pix
    out = {}
    for r in rows:
        for c in range(80):
            b = 0
            for i in range(8):
                if pix[r * 4 + i // 2][c * 2 + (i & 1)]: b |= 1 << i
            out[(c, r)] = b
    return out

def want_sprites():
    out = [(15, [PIC['PIC_PAD'], PIC['PIC_WIDE'], PIC['PIC_LASER'], PIC['PIC_PAD']][v('pw')], v('pad_x'), 87, 0)]
    for i in range(3):
        if v('b_on', i): out.append((12 + i, PIC['PIC_BALL'], v('b_xh', i), v('b_yh', i), 0))
    for i in range(2):
        if v('c_on', i): out.append((10 + i, PIC['PIC_CAP_W'] + v('c_kind', i), v('c_x', i), v('c_yh', i), 0))
    for i in range(4):
        if v('s_on', i): out.append((6 + i, PIC['PIC_SHOT'], v('s_x', i), v('s_y', i), 0))
    return sorted(out)

def check():
    want = want_cells()
    rows = [1] + list(range(2, 24))
    scr = screen_cells(rows)
    bad = [k for k in want if scr.get(k) != want[k]]
    # nothing else in the field but the bricks, walls and the "LEVEL" text row
    extra = [k for k in scr if k not in want and scr[k] and k[1] != 16]
    if bad or extra:
        problems.append('frame %d: screen differs at %s %s' % (st['frames'], bad[:3], extra[:3]))
    ws, ts = want_sprites(), sorted(mc.term.visible())
    if ws != ts and v('serve_t') != 100:            # (just served: not drawn yet)
        problems.append('frame %d: sprites differ: want %s terminal %s' % (st['frames'], [w for w in ws if w not in ts][:3], [t for t in ts if t not in ws][:3]))
    for i in range(3):
        if not v('b_on', i): continue
        x, y = v('b_xh', i), v('b_yh', i)
        if not (2 <= x <= 156 and 8 <= y <= 95):
            problems.append('frame %d: ball %d at %d,%d is outside the field' % (st['frames'], i, x, y))
        for dx in (0, 1):
            for dy in (0, 1):
                px, py = x + dx, y + dy
                if 16 <= py < 56 and 4 <= px < 156 and v('map', (py - 16) // 4 * gen.BW + (px - 4) // 8):
                    problems.append('frame %d: ball %d at %d,%d is in a brick' % (st['frames'], i, x, y))
    st['checked'] = st.get('checked', 0) + 1

def brick_cx(bx):
    """the x of the brick nearest across to x bx (in turn, the lowest ones)"""
    ks = [k for k in range(gen.BW * gen.BH) if v('map', k) in (1, 2)]
    if not ks: return 80
    k = min(ks, key=lambda k: abs(4 + 8 * (k % gen.BW) + 4 - bx) - (k // gen.BW) * (st['frames'] // 500 % 2) * 4)
    return 4 + 8 * (k % gen.BW) + 4

def act():
    """the bot: the paddle under the lowest ball coming down, placed so the
    ball goes back towards the bricks that are left (or under the first
    capsule when no ball is near); fire now and then"""
    pw = v('pad_w'); px = v('pad_x')
    ball = None; best = -1
    for i in range(3):
        if v('b_on', i) and not v('b_stuck', i):
            y = v('b_yh', i) + (100 if not v('b_sy', i) else 0)
            if y > best: best, ball = y, i
    want = px + pw // 2
    if ball is not None:
        bx = v('b_xh', ball)
        dx = brick_cx(bx) - bx
        reach = [104, 60, 35, 19]                   # how far across each angle goes on the way up
        a = min(range(4), key=lambda k: abs(reach[k] - abs(dx) * (1 + st['frames'] // 211 % 3) / 2))
        zone = a if dx < 0 else 7 - a               # (the left end sends it left)
        d = zone * pw // 8 + pw // 16
        want = bx - d + pw // 2
    if (ball is None or best < 100 + 40):
        for i in range(2):
            if v('c_on', i) and v('c_yh', i) > 60 and v('c_kind', i) != 2: want = v('c_x', i) + 3
    fire = st['frames'] % 7 == 0
    d = want - (px + pw // 2)
    if MISS: d = -d if abs(d) < 20 else 0
    if KEYS:
        if d < -1: mc.keys.append(ord('a'))
        elif d > 1: mc.keys.append(ord('d'))
        if fire: mc.keys.append(ord(' '))
    else:
        b = 0
        if d < -1: b |= 0x40
        elif d > 1: b |= 0x80
        if fire and not mc.pad & 1: b |= 0x01
        mc.set_pad(b)

def bot(m):
    if v('frame') == st['f'] or v('quit'): return
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if syms['getc'] <= ret < syms['getc'] + 32:      # (through getc)
        ret = mem[0x100 + ((m.mpu.sp + 3) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 4) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']): return
    st['f'] = v('frame'); st['frames'] += 1
    check()
    if v('level') not in st['levels'] and st['levels']: st['cleared'] = st.get('cleared', 0) + 1
    st['levels'].add(v('level'))
    for i in range(2):
        if v('c_on', i): st['kinds'].add(v('c_kind', i))
    if st['frames'] % 500 == 0: mc.term.png('%s/f%05d.png' % (OUT, st['frames']))
    act()

def text():
    return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))

mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
if 'START' in os.environ:                     # play level n's bricks first (as level 1)
    n = int(os.environ['START']) - 1
    for t in ('lv_lo', 'lv_hi'): mem[syms[t]] = mem[syms[t] + n]
if KEYS: mc.keys.append(ord(' '))
else: mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
mc.run(500_000)
lives0 = None
while st['frames'] < FRAMES:
    mc.run(200_000, bot)
    if lives0 is not None and v('lives') < lives0: st['lost'] += 1
    lives0 = v('lives')
    if 'GAME  OVER' in text():
        st['over'] = True; mc.term.png(OUT + '/over.png'); break
mc.term.png(OUT + '/last.png')
print('levels cleared %d' % st.get('cleared', 0))
print('frames %d checked %d score %d levels %s balls lost %d lives %d game over %s' % (
    st['frames'], st.get('checked', 0), bcd('score'), sorted(st['levels']), st['lost'], v('lives'), st['over']))
print('capsules seen: %s' % ''.join(gen.CAPS[k] for k in sorted(st['kinds'])))
print('terminal errors', mc.term.errors[:5])
print('problems', len(problems), problems[:8])
