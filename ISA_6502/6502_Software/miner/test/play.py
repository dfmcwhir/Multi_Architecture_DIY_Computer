# usage (from the miner folder):  sh b.sh   (builds with a label file), then
#   python3 test/plan.py          (finds a way through each room: test/plans)
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: ROOMS=n how many rooms to play (default all), START=n start
#                at room n, GARBAGE=n random RAM at power-up
"""Play MINER MOS with the planned inputs (test/plans/roomN.txt, from plan.py)
on the gamepad, and check every frame that the game does exactly what the
model (model.py, phys.py) does: Willy's place and state, the guardians, the
keys, the air; that the terminal's sprites are Willy, the guardians and the
portal as they should be; and (every 8 frames, and after a tile changes)
that the screen shows the room's tiles as the model has them.  Every room
must be finished without losing a life."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import sim
from sim import Machine
import gen, phys, rooms, model

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
NR = len(rooms.ROOMS)
START = int(os.environ.get('START', '1')) - 1
NPLAY = int(os.environ.get('ROOMS', str(NR - START)))
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('miner.lbl')) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('miner.map').read()).group(1), 16)
mc = Machine('MINER.BIN', code_end=code_end, ctrl=1)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
def s8(x): return x - 256 if x > 127 else x

plans = {}
for n in range(NR):
    p = os.path.join(HERE, 'plans', 'room%d.txt' % (n + 1))
    if os.path.exists(p):
        plans[n] = [tuple(int(a) for a in l.split()) for l in open(p)]

PIC = {}
for i, (name, rows) in enumerate(gen.PICS): PIC.setdefault(name, i)
GPIC = [PIC['PIC_' + k] for k in gen.GKINDS]
TCH = {t: gen.tile_chars(gen.TILES[t]) for t in range(10)}

problems = []
st = dict(k=0, room=None, frames=0, rooms_done=[], deaths=0, last_f=None, checked=0, screens=0)
cur = {}

def want_sprites(r, frame):
    w = r.w
    out = [(15, PIC['PIC_WILLY'] + ((w.anim >> 1) & 3), w.x, w.y, 1 if w.face < 0 else 0)]
    pn = PIC['PIC_PORTAL'] if r.keys else PIC['PIC_PORTAL'] + 1 + ((frame >> 2) & 1)
    out.append((0, pn, r.px, r.py, 0))
    for i, g in enumerate(r.guards):
        pos = g.x if g.axis == 'h' else g.y
        out.append((8 + i, GPIC[g.kind] + ((pos >> 2) & 1), g.x, g.y, 1 if g.axis == 'h' and g.dir < 0 else 0))
    return sorted(out)

def screen_tiles():
    pix = mc.term.pix
    out = []
    for r in range(phys.ROWS):
        for c in range(phys.COLS * 2):
            b = 0
            for i in range(8):
                if pix[r * 4 + i // 2][c * 2 + (i & 1)]: b |= 1 << i
            out.append(b)
    return out

def check_screen(r, why):
    scr = screen_tiles()
    bad = []
    for i, t in enumerate(r.map):
        rr, c = divmod(i, phys.COLS)
        if scr[rr * 80 + c * 2] != TCH[t][0] or scr[rr * 80 + c * 2 + 1] != TCH[t][1]: bad.append((c, rr))
    st['screens'] += 1
    if bad: problems.append('room %d frame %d (%s): screen tiles differ at %s' % (r.n + 1, r.t, why, bad[:4]))

def check(r):
    """the game against the model, at the top of a frame"""
    w = r.w
    game = (v('w_x'), v('w_y'), v('w_mode'), v('keys_left'), v('air'), v('w_dead'))
    want = (w.x, w.y, w.mode, r.keys, r.air, int(w.dead))
    if game != want:
        problems.append('room %d frame %d: game %s model %s' % (r.n + 1, r.t, game, want))
    gg = [(v('g_x', i), v('g_y', i)) for i in range(v('ng'))]
    gm = [(g.x, g.y) for g in r.guards]
    if gg != gm: problems.append('room %d frame %d: guardians %s model %s' % (r.n + 1, r.t, gg, gm))
    ws, ts = want_sprites(r, (r.t - 1) & 255), sorted(mc.term.visible())
    if r.t > 0 and ws != ts:
        problems.append('room %d frame %d: sprites want %s terminal %s' % (r.n + 1, r.t, [x for x in ws if x not in ts][:3], [x for x in ts if x not in ws][:3]))
    st['checked'] += 1

def pad_fn(m):
    """the gamepad, read by read_pad: in the frame loop, the plan's input"""
    ret = mem[0x100 + ((m.mpu.sp + 3) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 4) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']):
        return m.pad
    room, f = v('room'), v('frame')
    r = cur.get('r')
    if r is None or room != r.n or (f == 0 and r.t & 255 != 0) or v('w_dead'):
        if r is not None and room == r.n and not r.done:
            st['deaths'] += 1
            problems.append('room %d: a life lost at frame %d' % (room + 1, r.t))
        r = cur['r'] = model.Room(room)
        st['room'] = room
    if r.t & 255 != f:
        problems.append('room %d: frame counter %d, model %d' % (room + 1, f, r.t))
    check(r)
    if r.t % 8 == 0 or cur.get('changed'):
        check_screen(r, 'tile changed' if cur.get('changed') else 'every 8')
        cur['changed'] = False
    if r.t % 200 == 0: mc.term.png('%s/room%d_%04d.png' % (OUT, room + 1, r.t))
    seq = plans.get(room, [])
    d, j = seq[r.t] if r.t < len(seq) else (0, 0)
    changed = []
    r.frame(d, j, changed)
    if changed: cur['changed'] = True
    if r.done and room not in st['rooms_done']:
        st['rooms_done'].append(room)
        mc.term.png('%s/room%d_done.png' % (OUT, room + 1))
    st['frames'] += 1
    return model.pad_of(d, j)

def text():
    return '\n'.join(''.join(mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))

mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
if START:                                   # start at another room: new_game's "sta room" is changed
    a = syms['new_game']
    for i in range(a, a + 40):
        if mem[i] == 0x8D and mem[i + 1] | mem[i + 2] << 8 == syms['room']:
            mem[i], mem[i + 1], mem[i + 2] = 0xEA, 0xEA, 0xEA        # (nop it)
            break
    mem[syms['room']] = START
mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
mc.pad_fn = pad_fn
limit = sum(len(plans.get(n, [])) + 400 for n in range(START, START + NPLAY)) * 120_000
used = 0
while used < limit and len(st['rooms_done']) < NPLAY:
    mc.run(500_000); used += 500_000
    if 'GAME  OVER' in text(): problems.append('game over'); break
mc.run(2_000_000)
mc.term.png(OUT + '/last.png')
print('rooms finished %s of %d, frames %d checked %d (screens %d), lives lost %d, score %s' % (
    [n + 1 for n in st['rooms_done']], NPLAY, st['frames'], st['checked'], st['screens'], st['deaths'],
    ''.join('%02X' % v('score', i) for i in (2, 1, 0))))
print('terminal errors', mc.term.errors[:5])
print('problems', len(problems), problems[:10])
