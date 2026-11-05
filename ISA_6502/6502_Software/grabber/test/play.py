# usage (from the grabber folder):  sh b.sh  (builds with a label file), then
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: PAD=0 play with the keyboard, LEVELS=n how far to go,
#                GARBAGE=n random RAM at power-up, CPU_MHZ=1 for a 1 MHz build
"""A bot plays GOLD GRABBER: it fires when the grabber points at the best
thing it can reach, bombs big rocks if it has a bomb, and buys in the shop.
Every frame it checks:
  - bg holds exactly the platform, the miner, the dirt and the still things
  - fb holds exactly bg with the moving things over it (drawn here from the
    game's own state)
  - the terminal shows exactly fb
and that the money adds up: each catch pays its value, the goals go up by
50-70% of what's in each pit, the shop takes its prices."""
from gtest import *
import math, collections

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
PAD = os.environ.get('PAD', '1') == '1'
LEVELS = int(os.environ.get('LEVELS', '4'))
SX, CY = gen.dirs()
K_SPD = [0, 0x300, 0x1C0, 0xC0, 0x140, 0x80, 0x400, 0x280]
KW = [0, 5, 9, 13, 7, 12, 8, 11]; KH = [0, 5, 7, 9, 5, 9, 10, 6]

g = Game(pad=PAD, speed=0); mc = g.mc
problems = []
st = collections.Counter()
info = dict(f=-1, dirt=None, lvl=0, money=0, target=0, held=None, shots=0)
log = []

def next_ang(n=1):
    """the angle after n more frames of swinging (as hook_update does it)"""
    ang = g.w('ang'); angv = g.w('angv')
    for i in range(n):
        d = 32 - (ang >> 8)
        angv = (angv + 3 * d + (d >> 3)) & 0xFFFF
        ang = (ang + angv) & 0xFFFF
        if ang >> 8 >= 128: ang, angv = 0, 0
        elif ang >> 8 > 64: ang, angv = 64 << 8, 0
    return ang >> 8

def worth(it, L):
    if it is None: return 0
    k = it['k']
    if k == 6: return 0.01
    v = it['v'] + (250 if it['gem'] else 0)
    if k == 1 and g.v('gx2'): v *= 2
    spd = K_SPD[k] * (1.5 if g.v('strong') else 1)
    return v / (L / 3 + L * 256 / spd + 10)

ck = Checker(g)
def check_frame():
    ck.check('frame %d' % st['frames'])

prev = dict(items=None, money=0, carry=0, hst=0)
def poll(m):
    mem = g.mem
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']):
        return
    if g.v('frame') == info['f']: return
    info['f'] = g.v('frame'); st['frames'] += 1
    if g.v('level') != info['lvl']:                 # a new level: the goal and the pit
        info['lvl'] = g.v('level'); ck.reset(); info['fresh'] = True
        items = g.items()
        tot = sum(it['v'] + (250 if it['gem'] else 0) for it in items)
        pct = g.v('pct')
        ok = tot == g.w('total') and 50 <= pct <= 70 and g.n3('target') == info['target'] + tot * pct // 100
        if not ok: problems.append('level %d: goal %d, expected %d + %d * %d%%' % (info['lvl'], g.n3('target'), info['target'], tot, pct))
        info['target'] = g.n3('target')
        info['money'] = g.n3('money')
        kinds = collections.Counter(K_NAMES[it['k']] for it in items)
        log.append('level %d: %d things worth $%d, goal $%d (+%d%%), money $%d: %s' % (info['lvl'], len(items), tot, info['target'], pct, info['money'], dict(kinds)))
        if info['lvl'] <= 3: mc.term.png('%s/level%d.png' % (OUT, info['lvl']))
    if not info.pop('fresh', False): check_frame()     # (the first frame: nothing drawn yet)
    # the money: a catch pays what it was worth
    money = g.n3('money')
    if money != info['money']:
        got = money - info['money']
        if info['held'] is None or got != info['held']:
            problems.append('frame %d: money went up %d, expected %s' % (st['frames'], got, info['held']))
        st['catches'] += 1; info['money'] = money
    if g.v('carry') and info['held'] is None:     # just grabbed: what is it worth?
        gone = [it for it in prev['items'] if it['i'] not in {j['i'] for j in g.items()}]
        cand = [it for it in gone if it['k'] != 6]
        if len(cand) == 1:
            it = cand[0]; k = it['k']
            v = it['v'] * (2 if k == 1 and g.v('gx2') else 1) + (250 * (2 if g.v('gx2') else 1) if it['gem'] else 0)
            info['held'] = v
            if g.w('cval') != v: problems.append('frame %d: holding %s worth %d, cval %d' % (st['frames'], K_NAMES[k], v, g.w('cval')))
            st['grab_' + K_NAMES[k]] += 1
    if not g.v('carry') and g.v('hst') == 0: info['held'] = None
    if g.v('carry') == 0 and prev['carry'] and g.v('hst') == 2: st['bombed'] += 1; info['held'] = None
    prev.update(items=g.items(), carry=g.v('carry'), hst=g.v('hst'))
    # the bot
    pad = 0
    if g.v('hst') == 0 and g.v('tsec') > 0:
        items = g.items()
        a = next_ang(2 if PAD else 1)     # (the pad is read before the bot presses)
        if st['frames'] % 6 == 0 or 'best' not in info:   # (the best shot: now and then)
            info['best'] = max(worth(*ray(items, b)) for b in range(65))
        best = info['best']
        it, L = ray(items, a)
        if best > 0 and worth(it, L) >= best * 0.8:
            pad = 0x01; info['shots'] += 1
    if g.v('carry') and g.v('ck') == 5 and g.v('bombs'):
        pad = 0x02
    if PAD:
        m.set_pad(pad)
    else:
        if pad & 1: m.keys.append(ord(' '))
        if pad & 2: m.keys.append(ord('B'))
        m.set_pad(0)

def shop():
    """buy what's affordable, now and then; check the money it takes"""
    mc.run(1_000_000)
    for k in range(4):
        av, price = g.v('sh_av', k), g.v('sh_pl', k) | g.v('sh_ph', k) << 8
        if av and g.n3('money') >= price + 100 and (info['lvl'] + k) % 2 == 0:
            m0 = g.n3('money'); b0 = g.v('bombs')
            mc.keys.append(ord('1') + k); mc.run(1_500_000)
            ok = g.n3('money') == m0 - price and 'BOUGHT' in g.text()
            if not ok: problems.append('shop: item %d price %d: money %d -> %d' % (k, price, m0, g.n3('money')))
            st['bought_%d' % k] += 1
            log.append('  bought %s for $%d' % (['strength', 'double gems', 'a bomb', 'the laser pointer'][k], price))
    info['money'] = g.n3('money')
    mc.keys.append(ord('N')); mc.run(400_000)

mc.run(3_000_000)
if PAD: mc.set_pad(0x08); mc.run(50_000); mc.set_pad(0)
else: mc.keys.append(ord(' '))
over = False
for step in range(100000):
    mc.run(100_000, poll)
    t = g.text()
    if 'THE SHOP' in t and 'N: NEXT LEVEL' in t and info.get('shopped') != info['lvl']:
        info['shopped'] = info['lvl']
        if info['lvl'] == 1: mc.term.png(OUT + '/shop.png')
        log.append('  level %d done: money $%d (goal $%d)' % (info['lvl'], g.n3('money'), g.n3('target')))
        if info['lvl'] >= LEVELS: break
        shop()
    if 'GAME  OVER' in t:
        mc.term.png(OUT + '/over.png'); over = True
        log.append('  game over at level %d: money $%d, goal $%d' % (info['lvl'], g.n3('money'), g.n3('target')))
        ok = g.n3('money') < g.n3('target')
        if not ok: problems.append('game over with the goal met')
        break
for l in log: print(l)
print('frames %d checked %d, shots %d, %s' % (st['frames'], ck.n, info['shots'], {k: v for k, v in st.items() if k not in ('frames', 'checked')}))
print('terminal errors', mc.term.errors[:3])
problems += ck.problems
print('problems: %d' % len(problems))
for p in problems[:15]: print(' ', p)
