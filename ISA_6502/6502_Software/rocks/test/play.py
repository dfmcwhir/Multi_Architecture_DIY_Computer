# usage (from the rocks folder):  sh b.sh   (builds with a label file), then
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: PAD=1 play with the gamepad, GARBAGE=n random RAM at power-up,
#                FRAMES=n how long to play, CPU_MHZ=1 for a 1 MHz build,
#                IDLE=1 sit still (to test crashes, coming back and game over)
"""Play SPACE ROCKS with a bot (turn to the nearest rock, shoot, hyperspace out
of trouble) and check, every frame:
  - the terminal shows exactly what the game's screen buffer (fb) holds
  - fb holds exactly the ship, rocks, bullets and debris, drawn here in Python
    from the game's own object table
and that rocks split and score the right points."""
import sys, os, re, math, collections
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import sim
from sim import Machine
import gen

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
PAD = os.environ.get('PAD') == '1'
FRAMES = int(os.environ.get('FRAMES', '1500'))
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('rocks.map').read()).group(1), 16)
mc = Machine('ROCKS.BIN', code_end=code_end, ctrl=1 if PAD else 0)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
FW, FH = 160, 92
NOBJ = 48
SHAPES = [px for name, px in gen.SHAPES]
problems = []

def fb_pixels():
    s = set()
    fb = syms['fb']
    for r in range(23):
        for c in range(80):
            b = mem[fb + r * 80 + c]
            for i in range(8):
                if b >> i & 1: s.add((c * 2 + (i & 1), r * 4 + i // 2))
    return s

PICS = gen.pictures()
PIC_OF = {sh: n for n, sh in enumerate(gen.PIC_SHAPES)}

def sprite_objs():
    return {i for i in range(NOBJ) if v('o_sl', i)}

def s16(lo, hi): x = lo | hi << 8; return x - 65536 if x > 32767 else x

def half_d(i):
    """how far object i moves in half a frame (whole pixels, as the game works it out)"""
    hx = ((v('o_x_hi', i) << 8 | v('o_x_lo', i)) + (s16(v('o_vx_lo', i), v('o_vx_hi', i)) >> 1)) >> 8
    hy = ((v('o_y_hi', i) << 8 | v('o_y_lo', i)) + (s16(v('o_vy_lo', i), v('o_vy_hi', i)) >> 1)) >> 8
    return hx - v('o_x_hi', i), hy - v('o_y_hi', i)

def pic_of(i):
    k = v('o_kind', i)
    if k == 1: return v('sdir') >> 3
    if k in (2, 6): return PIC_OF['dot']
    return PIC_OF[v('o_shape', i)]

def want_sprites():
    """the terminal's sprites as they should be after the half-way frame:
    (slot, picture, x, y, flags), from the game's slot tables; and checks
    that each sprite thing has all the slots it needs"""
    out = []
    owners = {}
    if v('o_sl', 0) and not v('inv_t') & 4: owners[15] = (0, 0)
    if v('o_sl', 45): owners[14] = (45, 0)
    for sl in range(14):
        if v('sl_obj', sl): owners[sl] = (v('sl_obj', sl) - 1, v('sl_part', sl))
    for sl, (i, part) in owners.items():
        n = pic_of(i); ox, oy, w, h, rows = PICS[n]
        x, y = v('o_x_hi', i) - ox, v('o_y_hi', i) - oy
        if part:
            if x < 0: x += FW
            elif x + w > FW: x -= FW
            if y < 0: y += FH
            elif y + h > FH: y -= FH
        dx, dy = half_d(i) if HALF else (0, 0)
        out.append((sl, n, x + dx, y + 4 + dy, 0))
    for i in sprite_objs():
        if i in (0, 45): continue
        n = pic_of(i); ox, oy, w, h, rows = PICS[n]
        x, y = v('o_x_hi', i) - ox, v('o_y_hi', i) - oy
        cx, cy = x < 0 or x + w > FW, y < 0 or y + h > FH
        parts = sorted(p for sl, (o, p) in owners.items() if o == i)
        if (cx and cy) or parts != ([0, 1] if cx or cy else [0]):
            problems.append('frame %d: object %d has slots for parts %s' % (st['frames'], i, parts))
    return sorted(out)

def model_pixels(skip=()):
    s = set()
    for i in range(NOBJ):
        k = v('o_kind', i)
        if not k: continue
        x, y = v('o_x_hi', i), v('o_y_hi', i)
        if k in (2, 4, 6):                              # bullets, debris, saucer bullets
            if i not in skip: s.add((x, y))
            continue
        if k == 1:
            if v('inv_t') & 4: continue
            d = v('sdir') >> 3
            sh = ([] if i in skip else [SHAPES[d]]) + ([SHAPES[32 + d]] if v('flame') and (v('frame') - 1) & 1 else [])   # (frame counts on after drawing)
        elif i in skip:
            continue
        else:
            sh = [SHAPES[v('o_shape', i)]]
        for px in sh:
            for dx, dy in px: s.add(((x + dx) % FW, (y + dy) % FH))
    return s

def screen_pixels():
    return {(x, y - 4) for y in range(4, 96) for x in range(160) if mc.term.pix[y][x]}

ufo = dict(seen=0, big=0, small=0, shot=0, ebul=0, last=0)
st = dict(frame=-1, frames=0, checked=0, score_seen=0, waves=set(), deaths=0, shots=0, lives=None, hits=collections.Counter(), over=False)

def bcd(n): return int(''.join('%02X' % v(n, i) for i in (2, 1, 0)))

def seen_pixels():
    """what the field looks like on the terminal: its pixels with the sprites over them"""
    comp = mc.term.composite()
    return {(x, y - 4) for y in range(4, 96) for x in range(160) if comp[y][x]}

def look_pixels():
    """what it should look like: every object, the sprites half a frame on"""
    sp = sprite_objs()
    out = model_pixels(sp)
    for i in sp:
        if i == 0 and v('inv_t') & 4: continue
        n = pic_of(i); ox, oy, w, h, rows = PICS[n]
        dx, dy = half_d(i)
        x0, y0 = v('o_x_hi', i) - ox, v('o_y_hi', i) - oy
        wx, wy = x0 < 0 or x0 + w > FW, y0 < 0 or y0 + h > FH    # (a copy round that edge; the other edge clips)
        for yy in range(h):
            for xx in range(w):
                if rows[yy * ((w + 7) // 8) + xx // 8] >> (7 - xx % 8) & 1:
                    X, Y = x0 + xx + dx, y0 + yy + dy
                    if wx: X %= FW
                    if wy: Y %= FH
                    if 0 <= X < FW and 0 <= Y < FH: out.add((X, Y))
    return out

HALF = True
def check():
    fbp = fb_pixels(); want = model_pixels(sprite_objs()); scr = screen_pixels()
    if mc.term.sprites:
        ws, ts = want_sprites(), sorted(mc.term.visible())
        if ws != ts:
            problems.append('frame %d: sprites differ: want %s, terminal %s' % (st['frames'], [w for w in ws if w not in ts][:3], [t for t in ts if t not in ws][:3]))
        st['spr'] = st.get('spr', 0) + len(ts)
        if seen_pixels() != look_pixels():
            st['look'] = st.get('look', 0) + 1
            if st['look'] <= 3: problems.append('frame %d: the screen does not look right (%d pixels)' % (st['frames'], len(seen_pixels() ^ look_pixels())))
            if os.environ.get('DEBUG'):
                d = seen_pixels() ^ look_pixels()
                print('frame', st['frames'], 'seen-only', sorted(seen_pixels() - look_pixels())[:6], 'want-only', sorted(look_pixels() - seen_pixels())[:6])
                for i in range(NOBJ):
                    if v('o_kind', i): print('  obj', i, 'kind', v('o_kind', i), 'at', v('o_x_hi', i), v('o_y_hi', i), 'sl', v('o_sl', i), 'd', half_d(i))
    if fbp != want:
        problems.append('frame %d: buffer differs from the objects (%d extra, %d missing)' % (st['frames'], len(fbp - want), len(want - fbp)))
    if scr != fbp:
        problems.append('frame %d: screen differs from the buffer (%d extra, %d missing)' % (st['frames'], len(scr - fbp), len(fbp - scr)))
    st['checked'] += 1

def wdelta(a, b, m):
    d = (b - a) % m
    return d - m if d > m // 2 else d

PADK = dict(A=0x40, D=0x80, W=0x10, F=0x01, S=0x02)
def act(keys):
    if PAD:
        b = 0
        for k in keys: b |= PADK[k]
        if b & 0x01 and mc.pad & 0x01: b &= ~0x01      # fire is a new press each time
        mc.set_pad(b)
    else:
        for k in keys: mc.keys.append(ord({'F': ' '}.get(k, k)))

def bot(m):
    f = v('frame')
    if f == st['frame'] or v('quit'): return
    # only at the top of the frame loop's read_input (getc from read_input)
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if syms['getc'] <= ret < syms['getc'] + 32:     # (through getc, which keeps out the terminal's answers)
        ret = mem[0x100 + ((m.mpu.sp + 3) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 4) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']): return
    st['frame'] = f; st['frames'] += 1
    check()
    if v('o_kind', 45) == 5:
        if not ufo['last']: ufo['seen'] += 1; ufo['small' if v('o_size', 45) else 'big'] += 1
        ufo['last'] = 1
    else:
        ufo['last'] = 0
    ufo['ebul'] += sum(1 for i in (46, 47) if v('o_kind', i) == 6 and v('o_t', i) == 29)
    if st['frames'] % 300 == 0: mc.term.png('%s/f%05d.png' % (OUT, st['frames']))
    st['waves'].add(v('wave'))
    if st['lives'] is not None and v('lives') < st['lives']: st['deaths'] += 1
    st['lives'] = v('lives')
    if not v('o_kind', 0) or os.environ.get('IDLE'): act([]); return
    sx, sy = v('o_x_hi', 0), v('o_y_hi', 0)
    best = None
    for i in list(range(5, 29)) + [45]:
        if v('o_kind', i) in (3, 5):
            dx, dy = wdelta(sx, v('o_x_hi', i), FW), wdelta(sy, v('o_y_hi', i), FH)
            d = math.hypot(dx, dy)
            if best is None or d < best[0]: best = (d, dx, dy, v('o_size', i) if v('o_kind', i) == 3 else 1)
    if not best: act([]); return
    d, dx, dy, size = best
    if d < [9, 6, 4][size] + 3 and not v('inv_t'):
        act(['S']); return                      # hyperspace out
    want = (math.atan2(dy, dx) / (2 * math.pi) * 32) % 32
    have = v('sdir') / 8
    diff = (want - have + 16) % 32 - 16
    keys = []
    if diff > 0.7: keys.append('D')
    elif diff < -0.7: keys.append('A')
    if abs(diff) < 1.5 and st['frames'] % 2 == 0: keys.append('F'); st['shots'] += 1
    if d > 50 and st['frames'] % 9 == 0: keys.append('W')
    act(keys)

def text():
    return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))

mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
if PAD:
    mc.set_pad(0x08); mc.run(200_000); mc.set_pad(0); mc.run(200_000)
else:
    mc.keys.append(ord(' '))
mc.run(1_000_000)
while st['frames'] < FRAMES:
    mc.run(200_000, bot)
    if 'GAME  OVER' in text():
        st['over'] = True; mc.term.png(OUT + '/over.png'); break
mc.term.png(OUT + '/last.png')
print('frames %d checked %d score %d waves %s deaths %d lives %d high %d game over %s' % (
    st['frames'], st['checked'], bcd('score'), sorted(st['waves']), st['deaths'], v('lives'), bcd('hiscore'), st['over']))
print('saucers: %d (big %d, small %d); saucer bullets fired %d' % (ufo['seen'], ufo['big'], ufo['small'], ufo['ebul']))
print('sprites a frame: %.1f; frames that did not look right: %d' % (st.get('spr', 0) / max(1, st['checked']), st.get('look', 0)))
print('terminal errors', mc.term.errors[:5])
print('problems', len(problems), problems[:8])
