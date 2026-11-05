# usage (from the grabber folder):  PY65=... python3 test/features.py OUTDIR
"""Set pieces: the pit is set up by hand, the grabber aimed, and the game
must react: catching and its pay, a gopher with a gem, double gems, TNT and
its chain, a bomb on a rock, strength, the edge, time running out (the goal
met or not), and the shop.  The field is checked every frame as in play.py."""
from gtest import *

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
results = []
def check(what, ok):
    results.append(ok); print('%-60s %s' % (what, 'ok' if ok else 'FAILED'))

class Scene:
    def __init__(self, name):
        self.name = name
        self.g = g = Game(pad=False, speed=0); self.mc = g.mc
        self.ck = Checker(g)
        self.f = -1; self.todo = []; self.n = 0; self.keys = []
        g.mc.run(3_000_000); g.mc.keys.append(ord(' '))
        self.frames(3)                       # (into the level)
    def poll(self, m):
        g = self.g; mem = g.mem
        ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
        if not (syms['read_input'] <= ret < syms['handle_key']): return
        if g.v('frame') == self.f: return
        self.f = g.v('frame'); self.n += 1
        if self.n > 1 and not self.fresh: self.ck.check('%s frame %d' % (self.name, self.n))
        self.fresh = False
        for f in self.todo: f()
        if self.todo: self.fresh = True; self.ck.reset()
        self.todo = []
        m.keys.extend(self.keys); self.keys = []
        if self.cond and self.cond(): self.hit = True
    fresh = True
    def frames(self, k):
        end = self.n + k; guard = 0
        while self.n < end and not self.mc.exited and guard < 50 * k + 100:
            self.mc.run(20_000, self.poll); guard += 1
    def wait(self, cond, limit):
        """run frames until cond() holds at the start of a frame"""
        end = self.n + limit; guard = 0
        self.cond, self.hit = cond, False
        while self.n < end and guard < 50 * limit + 100 and not self.hit:
            guard += 1
            self.mc.run(5_000, self.poll)
        self.cond = None
        return self.hit
    cond = None
    def setup(self, items, **pokes):
        items = items + [dict(k=4, x=150, y=84, v=11)]    # (something left: the level goes on)
        def f():
            set_items(self.g, items)
            for n, v in pokes.items():
                vals = v if isinstance(v, (list, tuple)) else [v]
                for i, x in enumerate(vals): self.g.mem[syms[n] + i] = x
        self.todo.append(f); self.frames(1)
    def aim(self, idx):
        """swing the grabber to point at item idx and fire"""
        g = self.g
        its = g.items()
        a = [a for a in range(65) if ray(its, a)[0] and ray(its, a)[0]['i'] == idx]
        assert a, 'no angle reaches item %d' % idx
        a = a[len(a) // 2]
        def f():
            for n, v in (('ang', 0), ('ang', 1), ('angv', 0), ('angv', 1)): pass
            g.mem[syms['ang']] = 0; g.mem[syms['ang'] + 1] = a
            g.mem[syms['angv']] = 0; g.mem[syms['angv'] + 1] = 0
            self.mc.keys.append(ord(' '))
        self.todo.append(f); self.frames(1)
        return a
    def home(self, limit=600):
        return self.wait(lambda: self.g.v('hst') == 0, limit)
    def shot(self, tag): self.mc.term.png('%s/%s_%s.png' % (OUT, self.name, tag))

# ---- a catch: a chest, paid at the top --------------------------------------------
s = Scene('catch'); g = s.g
s.setup([dict(k=2, x=100, y=60, v=230), dict(k=4, x=30, y=40, v=12)], money=[0, 0, 0], tsec=60)
s.aim(0)
ok = s.wait(lambda: g.v('carry') == 1, 60)
s.frames(2); s.shot('reel')
check('the chest is caught, the claw shut, the winch turning', ok and g.v('ck') == 2 and g.v('hst') == 2)
check('it left the pit (and bg)', all(it['k'] != 2 for it in g.items()))
s.home()
check('at the top: $230, "+$230" on the status line', g.n3('money') == 230 and '+$230' in g.text())
s.aim(1); s.home()
check('then the small rock: $12 more', g.n3('money') == 242)
s.frames(45)
check('the "+$" goes after a while', '+$' not in g.text())
check('the field right every frame', not s.ck.problems)

# ---- a gopher with a gem; double gems ------------------------------------------------
s = Scene('gopher'); g = s.g
s.setup([dict(k=7, x=70, y=50, v=7, gem=1, x0=40, x1=120, dir=0), dict(k=1, x=40, y=70, v=250)], money=[0, 0, 0], gx2=1)
s.frames(20)
x0 = g.v('it_x', 0); s.frames(30)
check('the gopher runs along', g.v('it_x', 0) != x0)
s.shot('gopher')
s.aim(0)
s.wait(lambda: g.v('carry') == 1, 60); s.home()
check('a gopher with a gem: $7 + $500 (double gems)', g.n3('money') == 507)
s.aim(1); s.home()
check('a gem: $500 with double gems', g.n3('money') == 1007)
check('the field right every frame', not s.ck.problems)

# ---- TNT: a bang, and what's near it goes; more TNT goes off too -------------------
s = Scene('tnt'); g = s.g
items = [dict(k=6, x=76, y=50), dict(k=1, x=64, y=52, v=250), dict(k=6, x=94, y=54), dict(k=2, x=108, y=56, v=200),
         dict(k=5, x=20, y=78, v=25)]
s.setup(items, money=[0, 0, 0])
s.aim(0)
ok = s.wait(lambda: any(g.v('ex_t', e) for e in range(6)), 40)
s.frames(2); s.shot('bang')
check('the grabber hits TNT: a bang', ok and g.v('carry') == 0 and g.v('hst') == 2)
s.frames(12); s.shot('chain')
left = {it['k'] for it in g.items()}
check('the gem, the other TNT and the chest beside it are gone', left == {4, 5})
check('the big rock far off is still there', [it['x'] for it in g.items() if it['k'] == 5] == [20])
s.home()
check('nothing paid', g.n3('money') == 0)
check('the field right every frame', not s.ck.problems)

# ---- a bomb: a big rock held, B blows it up ----------------------------------------
s = Scene('bomb'); g = s.g
s.setup([dict(k=5, x=100, y=75, v=27), dict(k=5, x=40, y=75, v=27)], money=[0, 0, 0], bombs=2)
s.aim(0)
s.wait(lambda: g.v('carry') == 1, 80)
s.frames(5)
s.keys.append(ord('B')); s.frames(2); s.shot('bomb')
check('B: the rock blows up, a bomb used', g.v('carry') == 0 and g.v('bombs') == 1 and any(g.v('ex_t', e) for e in range(6)))
n0 = s.n; s.home()
check('back up fast, and nothing paid', s.n - n0 < 30 and g.n3('money') == 0)
s.keys.append(ord('B')); s.frames(2)
check('B with nothing held: no bomb used', g.v('bombs') == 1)
check('the field right every frame', not s.ck.problems)

# ---- strength: the same rock comes up half as fast again ------------------------------
times = []
for strong in (0, 1):
    s = Scene('strength%d' % strong); g = s.g
    s.setup([dict(k=5, x=74, y=78, v=27)], money=[0, 0, 0], strong=strong)
    s.aim(0); s.wait(lambda: g.v('carry') == 1, 80)
    n0 = s.n; s.home(); times.append(s.n - n0)
check('strength: the big rock up in %d frames, not %d' % (times[1], times[0]), 1.35 < times[0] / times[1] < 1.65)

# ---- the edge: out to it and back with nothing -------------------------------------------
s = Scene('edge'); g = s.g
s.setup([dict(k=1, x=78, y=80, v=250)], money=[0, 0, 0])
def f():
    g.mem[syms['ang']] = 0; g.mem[syms['ang'] + 1] = 2; g.mem[syms['angv']] = 0; g.mem[syms['angv'] + 1] = 0
    s.mc.keys.append(ord(' '))
s.todo.append(f); s.frames(1)
ok = s.wait(lambda: g.v('hst') == 2, 80)
check('far to the left: it reaches the edge and comes back (%d, %d)' % (g.v('hx'), g.v('hy')), ok and g.v('carry') == 0 and g.v('hx') <= 6)
s.home()
check('nothing paid', g.n3('money') == 0)

# ---- the time runs out: the goal not met, game over ----------------------------------
s = Scene('timeout'); g = s.g
s.setup([dict(k=1, x=78, y=80, v=250)], money=[0, 0, 0], tsec=2, target=[100, 0, 0])
for k in range(100):
    s.mc.run(200_000, s.poll)
    if 'GAME  OVER' in g.text(): break
s.mc.run(500_000); s.shot('over')
check('time up, $0 of $100: game over', 'GAME  OVER' in g.text() and 'THE GOAL WAS $100' in g.text())
s.mc.keys.append(ord(' ')); s.mc.run(4_000_000)
check('space: a new game', g.v('level') == 1 and g.n3('money') == 0)

# ---- the goal met: the shop ----------------------------------------------------------------
s = Scene('shop'); g = s.g
s.setup([dict(k=1, x=78, y=80, v=250)], money=[0x10, 0x27, 0], tsec=2, target=[100, 0, 0], bombs=8)
for k in range(100):
    s.mc.run(200_000, s.poll)
    if 'THE SHOP' in g.text(): break
s.mc.run(1_000_000); s.shot('shop')
check('time up, $10000 of $100: goal reached, the shop', 'THE SHOP' in g.text() and 'GOAL REACHED' not in g.text())
def buy(k):
    m0 = g.n3('money'); price = g.v('sh_pl', k) | g.v('sh_ph', k) << 8
    g.mem[syms['sh_av'] + k] = 1
    s.mc.keys.append(ord('1') + k); s.mc.run(1_000_000)
    return m0 - g.n3('money'), price
paid, price = buy(2)
check('a bomb: paid $%d, 9 now' % price, paid == price and g.v('bombs') == 9 and 'BOUGHT' in g.text())
paid, price = buy(2)
check('no more than 9 bombs', paid == 0 and 'CARRY MORE' in g.text())
paid, price = buy(0)
check('strength: paid $%d' % price, paid == price and g.v('strong') == 1)
paid, price = buy(1)
check('double gems: paid $%d' % price, paid == price and g.v('gx2') == 1)
g.mem[syms['money']:syms['money'] + 3] = [0x10, 0x27, 0]
paid, price = buy(3)
check('the laser pointer: paid $%d' % price, paid == price and g.v('has_laser') == 1)
prices = []
for k in range(4):
    prices.append(g.v('sh_pl', k) | g.v('sh_ph', k) << 8)
check('prices in range: %s' % prices, 60 <= prices[0] <= 160 and 115 <= prices[1] <= 265 and 35 <= prices[2] <= 105 and 275 <= prices[3] <= 475)
g.mem[syms['money']:syms['money'] + 3] = [5, 0, 0]
g.mem[syms['sh_av']] = 1
paid, price = buy(0)
check('not enough money: nothing bought', paid == 0 and 'NOT ENOUGH' in g.text())
s.mc.keys.append(ord('N')); s.mc.run(4_000_000)
check('N: on to level 2, with strength, double gems and the laser', g.v('level') == 2 and 'LASER POINTER' in g.text() and g.v('strong') and g.v('gx2') and g.v('has_laser'))
s.mc.run(4_000_000)
check('the status line shows them', 'STR' in g.text() and 'GEMX2' in g.text() and 'LASER' in g.text())

# ---- the laser pointer: dots to where the grabber would grab -----------------------------
s = Scene('laser'); g = s.g
s.setup([dict(k=3, x=100, y=60, v=500), dict(k=5, x=40, y=70, v=25), dict(k=1, x=76, y=40, v=250)], has_laser=1, tsec=50)
s.frames(30)
s.shot('laser')
seen = set()
for k in range(60):
    s.frames(1)
    t = laser(g.items(), g.v('ang', 1))
    if t and isinstance(t[-1][0], str) and 'shot' not in seen: s.shot('target'); seen.add('shot')
    if t and isinstance(t[-1][0], str): seen.add(hit_at(g.items(), (t[-1][1] + 2) & 255, (t[-1][2] + 2) & 255)['k'])
    if k == 20: s.shot('laser2')
seen.discard('shot')
check('the laser marks what it would grab as it swings: %s' % sorted(seen), {1, 3} <= seen)
check('LASER on the status line', 'LASER' in g.text())
check('the field (dots and all) right every frame', not s.ck.problems)
s.poke = None
def f(): g.mem[syms['tsec']] = 30; g.mem[syms['tfr']] = 1
s.todo.append(f); s.frames(3)
check('half way through the level: off', g.v('tsec') == 29 and 'LASER' not in g.text())
check('the field right every frame', not s.ck.problems)

print('%d checks, %d failed' % (len(results), results.count(False)))
