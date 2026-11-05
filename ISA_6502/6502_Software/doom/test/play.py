# usage (from the doom folder, after:  sh b.sh   which also writes doom.lbl):
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: PAD=1 play with the gamepad, NODISK=1 a ROM without SBC_LOAD,
#                GARBAGE=n random RAM at power-up, START=E1M2.LVL begin on that map,
#                CHEAT=1 never run short of ammo (the bot doesn't go looking for it)
"""Play 6502 DOOM with a bot: walk each map to the exit switch (opening doors,
shooting whatever shoots back), and check every frame that what the
terminal shows matches the engine's frame buffer."""
import sys, os, re, math, collections
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
PAD = os.environ.get('PAD') == '1'
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
mc = Machine('DOOM.BIN', speed=0, code_end=code_end, ctrl=1 if PAD else 0)
if not os.environ.get('NODISK'): mc.set_disk('.')
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
MAP, FB = 0x5040, 0x5600
def tile(x, y): return mem[MAP + y * 32 + x]

def screen_cell(col, row):
    b = 0
    for i in range(8):
        b |= mc.term.pix[row * 4 + i // 2][col * 2 + (i & 1)] << i
    return b

problems = []
log = []
def say(*a):
    s = ' '.join(str(x) for x in a); print(s); log.append(s)

def player():
    return (v('px_hi') + v('px_lo') / 256, v('py_hi') + v('py_lo') / 256, v('pa_hi') * 256 + v('pa_lo'))

def los(x0, y0, x1, y1):
    n = int(max(abs(x1 - x0), abs(y1 - y0)) * 4) + 1
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n; y = y0 + (y1 - y0) * i / n
        if tile(int(x), int(y)): return False
    return True

def angle_to(px, py, pa, tx, ty):
    want = math.atan2(ty - py, tx - px) * 1024 / (2 * math.pi)
    d = (want - pa + 512) % 1024 - 512
    return d

def path_to_exit(px, py):
    start = (int(px), int(py))
    prev = {start: None}; q = collections.deque([start]); goal = None
    while q:
        c = q.popleft()
        x, y = c
        if any(tile(x + dx, y + dy) == 5 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            goal = c; break
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in prev and tile(*n) in (0, 4):
                prev[n] = c; q.append(n)
    if goal is None: return None
    p = [goal]
    while prev[p[-1]]: p.append(prev[p[-1]])
    return p[::-1]

st = dict(last_frame=-1, frames=0, stuck=0, lastpos=None, deaths=0, levels=[], shots=0, wiggle=0, mode='', checked=0)
PADBITS = dict(W=0x10, S=0x20, A=0x40, D=0x80, F=0x01, E=0x02)

def act(key):
    if os.environ.get('TRACE'): print('act', key, '%.2f %.2f %d' % player())
    if PAD:
        mc.set_pad(PADBITS[key] if key else 0)
    else:
        if key: mc.keys.append(ord({'F': ' '}.get(key, key)))

def check_screen():
    bad = 0
    for r in range(18):
        for c in range(80):
            if screen_cell(c, r) != mem[FB + r * 80 + c]: bad += 1
    if bad:
        problems.append('frame %d: %d cells differ from the frame buffer' % (st['frames'], bad))
    st['checked'] += 1
    # the status line shows the real numbers
    txt = ''.join(mc.term.txt.get((c, 19), (' ', 0))[0] for c in range(80))
    m = re.search(r'HEALTH\s+(\d+)\s+AMMO\s+(\d+)\s+KILLS\s+(\d+)/(\d+)', txt)
    if not m or int(m.group(1)) != v('health') or int(m.group(2)) != v('ammo') or int(m.group(3)) != v('kills'):
        problems.append('frame %d: status line %r health %d ammo %d kills %d' % (st['frames'], txt.strip(), v('health'), v('ammo'), v('kills')))

def bot(m):
    f = v('frame')
    if f == st['last_frame']: return
    st['last_frame'] = f; st['frames'] += 1
    if st['frames'] > 3 and not v('done') and v('health'): check_screen()
    if os.environ.get('CHEAT') and v('ammo') < 20: mem[syms['ammo']] = 20   # (the bot doesn't look for ammo)
    if st['frames'] % 150 == 0:
        mc.term.png('%s/f%05d.png' % (OUT, st['frames'])); say('frame', st['frames'], 'at %.2f %.2f %d' % player(), 'health', v('health'))
    px, py, pa = player()
    # stuck?
    pos = (round(px, 2), round(py, 2), pa)
    if pos == st['lastpos']: st['stuck'] += 1
    else: st['stuck'] = 0
    st['lastpos'] = pos
    if st['wiggle']:
        st['wiggle'] -= 1; act('S' if st['wiggle'] > 2 else 'A'); return
    if st['stuck'] > 25:
        st['stuck'] = 0; st['wiggle'] = 5; return
    # enemies: the nearest one that is awake or in sight
    best = None
    for i in range(32):
        s, t = v('t_state', i), v('t_type', i)
        if t in (1, 2) and s in (1, 2, 3):
            tx = v('t_x_hi', i) + v('t_x_lo', i) / 256; ty = v('t_y_hi', i) + v('t_y_lo', i) / 256
            d = math.hypot(tx - px, ty - py)
            if d < 10 and los(px, py, tx, ty) and (s != 1 or d < 8):
                if best is None or d < best[0]: best = (d, tx, ty)
    if best and v('ammo'):
        d, tx, ty = best
        a = angle_to(px, py, pa, tx, ty)
        tol = max(6, 60 / max(d, 0.5))
        if abs(a) > tol: act('D' if a > 0 else 'A')
        else: act('F'); st['shots'] += 1
        return
    path = path_to_exit(px, py)
    if path is None:
        problems.append('no path to the exit'); act(None); return
    if len(path) == 1:      # next to the exit switch
        x, y = path[0]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if tile(x + dx, y + dy) == 5: tx, ty = x + dx + 0.5, y + dy + 0.5
        a = angle_to(px, py, pa, tx, ty)
        if abs(a) > 20: act('D' if a > 0 else 'A')
        elif abs(px - x - .5) > .3 or abs(py - y - .5) > .3: act('W')
        else: act('E')
        return
    nx, ny = path[1]
    if tile(nx, ny) == 4:   # a closed door next
        a = angle_to(px, py, pa, nx + .5, ny + .5)
        if abs(a) > 24: act('D' if a > 0 else 'A')
        elif math.hypot(nx + .5 - px, ny + .5 - py) > 1.2: act('W')
        else: act('E')
        return
    # aim for the tile after next if it is in a straight line (smoother)
    tx, ty = nx + .5, ny + .5
    if len(path) > 2 and tile(*path[2]) == 0 and los(px, py, path[2][0] + .5, path[2][1] + .5):
        tx, ty = path[2][0] + .5, path[2][1] + .5
    a = angle_to(px, py, pa, tx, ty)
    if abs(a) > 40: act('D' if a > 0 else 'A')
    else: act('W')

def at_text(s):
    return s in ''.join(ch for (c, r), (ch, rv) in sorted(mc.term.txt.items(), key=lambda k: (k[0][1], k[0][0])))

def screen_text():
    rows = collections.defaultdict(dict)
    for (c, r), (ch, rv) in mc.term.txt.items(): rows[r][c] = ch
    return '\n'.join(''.join(rows[r].get(c, ' ') for c in range(80)).rstrip() for r in range(24))

def press_go():
    if PAD:
        mc.set_pad(0x08); mc.run(300000); mc.set_pad(0); mc.run(300000)
    else:
        mc.keys.append(ord(' ')); mc.run(600000)

# title -> new game
if os.environ.get('START'):     # begin on another map
    for i, ch in enumerate(os.environ['START'].encode() + b'\0'): mem[syms['first_name'] + i] = ch
mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
press_go()
total = 0
while total < 400_000_000:
    mc.run(2_000_000, bot)
    total += 2_000_000
    if mc.exited: break
    t = screen_text()
    if 'FINISHED' in t:
        say('finished', re.search(r'FINISHED (\S+)', t).group(1), 'frames', st['frames'], 'kills', v('kills'), '/', v('kills_max'), 'health', v('health'), 'ammo', v('ammo'))
        st['levels'].append(re.search(r'FINISHED (\S+)', t).group(1))
        mc.term.png('%s/done_%d.png' % (OUT, len(st['levels'])))
        mc.set_pad(0)
        mc.run(3_000_000)       # the pause before keys count
        if 'YOU WIN' in t:
            say('won'); break
        press_go(); mc.run(2_000_000)
        mc.term.png('%s/start_%d.png' % (OUT, len(st['levels'])))
        st['lastpos'] = None
    elif 'YOU DIED' in t:
        st['deaths'] += 1; say('died at frame', st['frames'], 'level', v('lp_name', 0) and bytes(mem[syms['lp_name']:syms['lp_name'] + 8]).decode())
        mc.term.png('%s/died_%d.png' % (OUT, st['deaths']))
        mc.set_pad(0); mc.run(3_000_000); press_go()
        if st['deaths'] > 6: break
    elif 'PRESS A KEY' in t or 'NO SBC_LOAD' in t:
        say('load message:', [l for l in t.split('\n') if l.strip()][:4]); mc.term.png(OUT + '/loadmsg.png'); break
say('levels', st['levels'], 'deaths', st['deaths'], 'frames', st['frames'], 'checked', st['checked'], 'loads', mc.loads)
say('terminal errors', mc.term.errors[:5])
say('problems', len(problems), problems[:10])
mc.term.png(OUT + '/last.png')
open(OUT + '/log.txt', 'w').write('\n'.join(log) + '\n')
