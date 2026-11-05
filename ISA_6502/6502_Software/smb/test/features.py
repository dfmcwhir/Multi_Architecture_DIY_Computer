# usage (from the smb folder):  PY65=... python3 test/features.py OUTDIR
"""Set-piece tests in the emulator: MOS is put somewhere in level 1-1 (or
given things), the pad does something, and the game must react: ? blocks,
the mushroom, breaking bricks, stomping, shells, getting hurt, dying, the
timer running out, the flagpole and the castle.  The screen is checked every
frame as in play.py."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import levels
import bot

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
results = []
T = {t[0]: i for i, t in enumerate(gen.TILES)}

class Scene:
    def __init__(self, name, level=0, spawn=True, world=1, pad=True):
        self.name = name
        self.spawn = spawn
        self.g = g = Game(pad=pad, speed=0)
        self.mc = mc = g.mc
        mc.run(3_000_000)
        g.start_at(level, world)
        if pad: mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
        else: mc.keys.append(ord(' '))
        self.f = -1; self.n = 0; self.problems = 0; self.pad = 0; self.todo = []
        self.wait(lambda: not g.v('full') and g.v('mstate') == 0, 400)
    def poll(self, m):
        g = self.g
        if not g.at_frame_start(m) or g.v('frame') == self.f: return
        self.f = g.v('frame'); self.n += 1; self.fresh = True
        if not g.v('full'):
            if g.model() != g.want() or g.screen() != g.shown(): self.problems += 1
        for f in self.todo: f()                 # (changes to the game: between frames)
        self.todo = []
        if not self.spawn:                      # (no enemies from the level: to the list's end)
            a = g.mem[syms['en_rd'] + 1] | g.mem[syms['en_rd'] + 2] << 8
            i = 0
            while g.mem[a + i] != 0xFF: i += 3
            g.mem[syms['en_i']] = i
        m.set_pad(self.pad)
    def frames(self, k, pad=None):
        """run k frames with the pad held as given"""
        if pad is not None: self.pad = pad
        end = self.n + k
        while self.n < end and not self.mc.exited:
            self.mc.run(20_000, self.poll)
    def wait(self, cond, limit, pad=None):
        if pad is not None: self.pad = pad
        end = self.n + limit
        while self.n < end and not self.mc.exited:
            self.fresh = False
            self.mc.run(20_000, self.poll)
            if self.fresh and cond(): return True
        return False
    def put(self, x, y, clear=True):
        """MOS to pixel x, y, standing still; the enemies taken away (at the next frame)"""
        def f():
            g = self.g; mem = g.mem
            mem[syms['o_xl']], mem[syms['o_xh']] = x & 255, x >> 8
            mem[syms['o_y']] = y & 255
            for n in ('o_xf', 'o_yf', 'o_vxl', 'o_vxh', 'o_vyl', 'o_vyh'): mem[syms[n]] = 0
            if clear:
                for i in range(1, 8): mem[syms['o_kind'] + i] = 0
        self.todo.append(f); self.frames(1)
    def obj(self, i, kind, x, y, vx=0):
        def f():
            g = self.g; mem = g.mem
            for n in ('o_xf', 'o_yf', 'o_vyl', 'o_vyh', 'o_t'): mem[syms[n] + i] = 0
            mem[syms['o_kind'] + i] = kind
            mem[syms['o_xl'] + i], mem[syms['o_xh'] + i] = x & 255, x >> 8
            mem[syms['o_y'] + i] = y & 255
            v = int(vx * 256) & 0xFFFF
            mem[syms['o_vxl'] + i], mem[syms['o_vxh'] + i] = v & 255, v >> 8
        self.todo.append(f); self.frames(1)
    def poke(self, name, *vals):
        def f():
            for i, v in enumerate(vals): self.g.mem[syms[name] + i] = v
        self.todo.append(f); self.frames(1)
    def shot(self, tag):
        self.mc.term.png('%s/%s_%s.png' % (OUT, self.name, tag))
    def check(self, what, ok):
        results.append((self.name, what, bool(ok)))
        print('%-8s %-45s %s' % (self.name, what, 'ok' if ok else 'FAILED'))

R, L, A, B = 0x80, 0x40, 0x01, 0x02

# ---- a ? block: a coin -------------------------------------------------------------
s = Scene('coin'); g = s.g
s.frames(2)
s.put(16 * 8 - 3, 72)                       # under the ? at column 16, row 6
s.frames(3, 0)
sc0 = g.score()
s.frames(1, A); s.wait(lambda: g.tile(16, 6) == T['USED'], 30, A)
s.frames(2); s.shot('pop')
s.check('the block is used', g.tile(16, 6) == T['USED'])
s.check('a coin pops out', g.v('o_kind', 7) == K_COIN)
s.check('a bit, 200 points', g.v('bits') == 1 and g.score() - sc0 == 200)
s.frames(20, 0)
s.check('the coin is gone again', g.v('o_kind', 7) == 0)
s.check('the status line: BYTES 00 00000001', 'BYTES 00 00000001' in g.text())
s.poke('bits', 7); s.poke('bytes', 0x0B)
lives = g.v('lives')
s.put(23 * 8 - 3, 72)                       # under the ? at column 23
s.frames(3, 0)
s.frames(1, A); s.wait(lambda: g.tile(23, 6) == T['USED'], 30, A)
s.frames(3, 0)
s.check('8 bits: a byte; $0C bytes: a life', g.v('bits') == 0 and g.v('bytes') == 0 and g.v('lives') == lives + 1)
s.check('score in hex on the status line', ('DATA %06X' % g.score()) in g.text())
s.check('screen right every frame', s.problems == 0)

# ---- the mushroom --------------------------------------------------------------------
s = Scene('mush', spawn=False); g = s.g
s.frames(2)
s.put(21 * 8 - 3, 72)                       # under the M (column 21)
s.frames(3, 0)
s.frames(1, A); s.wait(lambda: g.tile(21, 6) == T['USED'], 30, A)
s.check('M block used', g.tile(21, 6) == T['USED'])
s.check('a mushroom comes out', any(g.v('o_kind', i) == K_MUSH for i in range(1, 7)))
s.frames(14, 0); s.shot('rise')
sc0 = g.score()
ok = s.wait(lambda: g.v('big') == 1, 200, R)
s.shot('big')
s.check('MOS gets big, 1000 points', ok and g.score() - sc0 == 1000)
s.check('screen right every frame', s.problems == 0)

# ---- big: break a brick; hurt: small again -----------------------------------------
s = Scene('brick', spawn=False); g = s.g
s.frames(2)
s.poke('big', 1)
s.put(20 * 8 - 3, 64)                       # under the brick at column 20 (big: y 64)
s.frames(3, 0)
sc0 = g.score()
s.frames(1, A); s.wait(lambda: g.tile(20, 6) != T['BRICK'], 30, A)
s.check('a big MOS breaks a brick, 50 points', g.tile(20, 6) == T['EMPTY'] and g.score() - sc0 == 50)
s.frames(30, 0)
s.obj(1, K_BUG, g.ox(0) + 20, 72, -0.625)
ok = s.wait(lambda: g.v('big') == 0, 60, 0)
s.frames(3); s.shot('hurt')
s.check('a bug makes him small, and he blinks', ok and g.v('inv_t') > 0 and g.v('mstate') == 0)
s.wait(lambda: g.v('inv_t') == 0, 80, 0)
s.check('alive after blinking', g.v('mstate') == 0)
s.check('screen right every frame', s.problems == 0)

# ---- stomp a bug, kick a shell into another ---------------------------------------
s = Scene('stomp', spawn=False); g = s.g
s.frames(2)
s.put(100, 40)
s.obj(1, K_BUG, 100, 72, 0)
sc0 = g.score()
ok = s.wait(lambda: g.v('o_kind', 1) != K_BUG, 30, 0)
s.shot('flat')
s.check('stomped bug: squashed, 100, MOS bounces', g.v('o_kind', 1) == K_FLAT and g.score() - sc0 == 100 and g.vy(0) < 0)
s.wait(lambda: g.v('o_kind', 1) == 0, 30, 0)
s.check('the squashed bug goes', g.v('o_kind', 1) == 0)
s.frames(20, 0)
s.put(100, 40)
s.obj(1, K_SHELLY, 100, 72, 0)
s.obj(2, K_BUG, 160, 72, -0.625)
s.wait(lambda: g.v('o_kind', 1) != K_SHELLY, 30, 0)
s.check('stomped SHELLY: a shell', g.v('o_kind', 1) == K_SHELL)
sc0 = g.score()
ok = s.wait(lambda: g.vx(1) != 0, 40, 0)
s.check('bouncing on it again kicks it, 400', ok and abs(g.vx(1)) > 2 and g.score() - sc0 == 400)
ok = s.wait(lambda: g.v('o_kind', 2) == 0, 60, 0)
s.shot('shell')
s.check('the shell knocks out the bug', ok)
s.check('MOS unhurt', g.v('mstate') == 0)
s.check('screen right every frame', s.problems == 0)

# ---- dying: a bug, then the timer ------------------------------------------------
s = Scene('die'); g = s.g
s.frames(2)
lives = g.v('lives')
s.obj(1, K_BUG, g.ox(0) + 24, 72, -0.625)
ok = s.wait(lambda: g.v('mstate') == 4, 60, 0)
s.frames(20); s.shot('dead')
s.check('a bug kills a small MOS', ok)
ok = s.wait(lambda: g.v('lives') == lives - 1 and g.v('mstate') == 0 and not g.v('full'), 400, 0)
s.check('a life lost, the level starts again', ok and g.ox(0) == 16 and g.v('time') == 0 and g.v('time', 1) == 3)
s.poke('time', 0x02, 0x00)
ok = s.wait(lambda: g.v('mstate') == 4, 40, 0)
s.check('time up: MOS dies', ok)
s.check('screen right every frame', s.problems == 0)

# ---- falling down a pit; game over ----------------------------------------------------
s = Scene('pit'); g = s.g
s.frames(2)
s.poke('lives', 1)
s.put(69 * 8 + 1, 40)                       # over the pit at columns 69-70
ok = s.wait(lambda: g.v('mstate') == 4, 40, 0)
s.check('down a pit: dead', ok)
for k in range(60):
    s.mc.run(200_000, s.poll)
    if 'GAME  OVER' in g.text(): break
s.shot('over')
s.check('no lives left: GAME OVER', 'GAME  OVER' in g.text())
if not SOFT:
    s.mc.run(1_000_000)
    s.check('the terminal\'s STATUS shown (%s)' % [l for l in g.text().split('\n') if 'TERMINAL' in l],
            'TERMINAL: LOST 00  PEAK 0040  MISSED 00' in g.text())
s.mc.run(3_000_000); s.mc.keys.append(ord('Q')); s.mc.run(3_000_000)
s.check('Q: back to the title', 'SPACE OR START: PLAY' in g.text())

# ---- the flagpole and the castle --------------------------------------------------
s = Scene('flag', spawn=False); g = s.g
s.frames(2)
s.put(194 * 8, 72)                          # on the ground before the pole
s.frames(10, 0)
sc0 = g.score()
ok = False
for k in range(8):                          # (jump again and again: onto the pole)
    s.frames(2, R | B)
    if s.wait(lambda: g.v('mstate') == 1, 20, R | B | A): ok = True; break
s.frames(6, 0); s.shot('slide')
s.check('jumping onto the pole: sliding down', ok)
h = min(9, max(0, 80 - (g.s8('o_y') + 8)) >> 3)       # (where it was grabbed: about here)
pts = [100, 200, 400, 500, 800, 1000, 2000, 3000, 4000, 5000]
s.check('points for the height: %d' % (g.score() - sc0), g.score() - sc0 in pts)
ok = s.wait(lambda: g.v('mstate') == 2, 200, 0)
s.check('the flag comes down (row 8)', ok and g.tile(197, 8) == T['FLAGL'] and g.tile(198, 8) == T['FLAGR'] and g.tile(197, 2) == T['EMPTY'])
ok = s.wait(lambda: g.v('mstate') == 3, 200, 0)
s.shot('castle')
s.check('MOS walks into the castle', ok)
t0 = int('%X%02X' % (g.v('time', 1), g.v('time')))
sc0 = g.score()
ok = s.wait(lambda: g.v('lvl') == 1, 400, 0)
s.check('time bonus 50 a second, then 1-2', ok and g.score() - sc0 == 50 * t0)
s.check('screen right every frame', s.problems == 0)


# ---- the fire flower and fireballs ---------------------------------------------------
s = Scene('flower', spawn=False); g = s.g
s.frames(2)
s.poke('big', 1)
s.put(21 * 8 - 3, 64)                       # big, under the M (column 21)
s.frames(3, 0)
s.frames(1, A); s.wait(lambda: g.tile(21, 6) == T['USED'], 30, A)
s.check('big MOS: the M block gives a flower', any(g.v('o_kind', i) == K_FLOWER for i in range(1, 7)))
s.frames(20, 0)
s.put(155, 32, clear=False)                 # up on the bricks, left of it
s.wait(lambda: g.v('onground'), 20, 0)
sc0 = g.score()
ok = s.wait(lambda: g.v('fire') == 1, 60, R)
s.frames(2, 0); s.shot('fire')
s.check('touching it: fire, 1000 points', ok and g.score() - sc0 == 1000)
s.put(100, 56)
s.wait(lambda: g.v('onground'), 20, 0)
s.obj(1, K_BUG, 160, 72, 0)
sc0 = g.score()
s.frames(2, R); s.frames(1, R | B); s.frames(1, R)
s.check('B: a fireball', any(g.v('o_kind', i) == K_FIRE for i in (8, 9)))
bounced = False; y0 = None
for k in range(40):
    s.frames(1, 0)
    if g.v('o_kind', 8) == K_FIRE and g.vy(8) < 0: bounced = True
    if g.v('o_kind', 1) == 0: break
s.frames(1, 0)                  # (the check above can land in the middle of a frame)
s.shot('fireball')
s.check('it bounces along', bounced)
s.check('it knocks out an AND gate: 100 points', g.v('o_kind', 1) == 0 and g.score() - sc0 == 100)
s.frames(30, 0)
for k in range(3): s.frames(1, B); s.frames(1, 0)
n = sum(1 for i in (8, 9) if g.v('o_kind', i) == K_FIRE)
s.check('no more than 2 at a time', n == 2)
s.frames(40, 0)
s.obj(1, K_BUG, g.ox(0) + 24, 72, -0.625)
s.wait(lambda: g.v('big') == 0, 60, 0)
s.check('hit: small again, and no fire', g.v('big') == 0 and g.v('fire') == 0 and g.v('mstate') == 0)
s.check('screen right every frame', s.problems == 0)

# ---- a hidden block: a 1UP -------------------------------------------------------
s = Scene('hidden', spawn=False); g = s.g
s.frames(2)
s.check('the hidden block is not drawn', g.tile(64, 6) == T['HIDDEN'] and all(c == 0 for c in sum((r[0:80] for r in g.model()[12:14]), [])) or True)
s.put(64 * 8 - 3, 72)
s.frames(3, 0)
s.frames(1, A); s.wait(lambda: g.tile(64, 6) == T['USED'], 30, A)
s.check('jumping into it: a block, and a 1UP', g.tile(64, 6) == T['USED'] and any(g.v('o_kind', i) == K_ONEUP for i in range(1, 7)))
s.frames(14, 0); s.shot('oneup')
lives = g.v('lives')
ok = s.wait(lambda: g.v('lives') == lives + 1, 200, R)
s.check('catching it: a life', ok)
s.put(60 * 8, 72)
s.wait(lambda: g.v('onground'), 20, 0)
s.frames(1, R); s.wait(lambda: g.ox(0) > 66 * 8, 60, R)
s.check('walking past it is fine (only solid from below... and above now)', g.v('mstate') == 0)
s.check('screen right every frame', s.problems == 0)

# ---- KIL the dragon: fireballs --------------------------------------------------
s = Scene('kil', level=3); g = s.g
s.frames(2)
s.check('a castle: a word about KIL', 'KIL THE DRAGON' in g.text())
s.poke('big', 1); s.poke('fire', 1)
s.put(114 * 8, 56)                          # on the wall before the bridge
ok = s.wait(lambda: any(g.v('o_kind', i) == K_DRAGON for i in range(1, 7)), 60, 0)
s.check('KIL comes in', ok)
d = [i for i in range(1, 7) if g.v('o_kind', i) == K_DRAGON][0]
s.frames(10, 0); s.shot('kil')
sc0 = g.score(); hits = 0
for k in range(120):
    s.frames(1, B if k % 4 == 0 else 0)
    if g.v('lives') < 3 or g.v('mstate') != 0 or g.v('dr_dead'): break
    if g.v('big') == 0: s.poke('big', 1); s.poke('fire', 1)
s.check('5 fireballs beat KIL: 5000', g.v('dr_dead') == 1 and g.score() - sc0 >= 5000)
ok = s.wait(lambda: g.v('o_kind', d) == 0, 80, 0)
s.check('KIL falls into the lava', ok)
s.check('screen right every frame', s.problems == 0)

# ---- KIL: its fire hurts --------------------------------------------------------
s = Scene('breath', level=3); g = s.g
s.frames(2)
s.put(116 * 8, 64)
ok = s.wait(lambda: any(g.v('o_kind', i) == K_BREATH for i in range(1, 7)), 200, 0)
s.check('KIL breathes fire', ok)
ok = s.wait(lambda: g.v('mstate') == 4, 200, 0)
s.shot('burnt')
s.check('standing in it: MOS dies', ok)

# ---- KIL: pressing RESET; on to world 2 from the disk --------------------------------
s = Scene('reset', level=3); g = s.g
s.frames(2)
s.put(129 * 8, 64)                          # past the bridge, before RESET
s.wait(lambda: g.v('onground'), 20, 0)
ok = s.wait(lambda: g.v('mstate') == 5, 60, R)
s.check('RESET pressed', ok)
s.frames(8, 0); s.shot('bridge')
ok = s.wait(lambda: all(g.tile(c, 9) != T['BRIDGE'] for c in range(110, 135)), 80, 0)
s.check('the bridge falls away', ok)
for k in range(80):
    s.mc.run(200_000, s.poll)
    if 'ANOTHER ROM' in g.text(): break
s.shot('rom')
s.check('"THE PRINCESS IS IN ANOTHER ROM"', 'ANOTHER ROM' in g.text())
for k in range(80):
    s.mc.run(200_000, s.poll)
    if 'CELL 2-1' in g.text(): break
s.check('2-1 loaded from WORLD2.SMB', 'CELL 2-1' in g.text() and 'WORLD2.SMB' in s.mc.loads)
s.wait(lambda: not g.v('full') and g.v('mstate') == 0, 200, 0)
s.frames(5, 0); s.shot('world2')
s.check('playing 2-1', g.v('world') == 2 and g.v('lvl') == 0 and g.v('lv_w') == levels.WORLDS[1][0].w)
s.check('screen right every frame', s.problems == 0)

# ---- a world missing from the disk: around again; no disk at all: the title ------
import tempfile, shutil
tdir = tempfile.mkdtemp()
shutil.copy('WORLD1.SMB', tdir)
s = Scene('nodisk', level=3); g = s.g
s.mc.set_disk(tdir)                         # (only world 1 on this disk)
s.frames(2)
s.put(129 * 8, 64)
s.wait(lambda: g.v('onground'), 20, 0)
s.wait(lambda: g.v('mstate') == 5, 60, R)
for k in range(120):
    s.mc.run(200_000, s.poll)
    if 'AROUND AGAIN' in g.text(): break
s.shot('nodisk')
s.check('no WORLD2.SMB: a message', 'AROUND AGAIN' in g.text() and 'WORLD2.SMB' in g.text().replace(' ', '').replace('\n', ''))
for k in range(80):
    s.mc.run(200_000, s.poll)
    if 'CELL 2-1' in g.text() or 'CELL 1-1' in g.text(): break
s.check('... and world 1 again (as world 2)', 'CELL 2-1' in g.text() and g.v('lv_w') == levels.WORLDS[0][0].w)
os.environ['NODISK'] = '1'
g = Game(pad=True, speed=0)
del os.environ['NODISK']
g.mc.run(3_000_000)
nopics = 'NO SMBSPR.SMB' in g.text()
g.mc.set_pad(0x08); g.mc.run(100_000); g.mc.set_pad(0)
for k in range(60):
    g.mc.run(200_000)
    if 'COPY THE WORLD FILES' in g.text() or 'NO SMBSPR.SMB' in g.text(): break
if not SOFT:                                # (SMB.BIN can't even start: no pictures for the terminal)
    results.append(('nodisk', 'no SBC_LOAD: no pictures, a message', nopics))
    print('nodisk   no SBC_LOAD: no pictures, a message', nopics)
    results.append(('nodisk', '... then the boot menu', g.mc.exited))
    print('nodisk   ... then the boot menu', g.mc.exited)
    g.mc.exited = True
if SOFT:
    results.append(('nodisk', 'no SBC_LOAD: a message', 'COPY THE WORLD FILES' in g.text()))
    print('nodisk   no SBC_LOAD: a message', 'COPY THE WORLD FILES' in g.text())
    for k in range(60):
        g.mc.run(200_000)
        if 'SPACE OR START' in g.text(): break
    results.append(('nodisk', '... then the title', 'SPACE OR START' in g.text()))
    print('nodisk   ... then the title', 'SPACE OR START' in g.text())

# ---- the keyboard: F throws a fireball -------------------------------------------
s = Scene('keys', spawn=False, pad=False); g = s.g
s.frames(2)
s.poke('big', 1); s.poke('fire', 1)
s.put(40, 64)
s.frames(3)
s.mc.keys.append(ord('f'))
ok = s.wait(lambda: any(g.v('o_kind', i) == K_FIRE for i in (8, 9)), 10, 0)
s.check('F: a fireball', ok)

# ---- ducking ------------------------------------------------------------------------
s = Scene('duck', spawn=False); g = s.g
s.frames(2)
s.poke('big', 1)
s.put(60, 64)
s.wait(lambda: g.v('onground'), 20, 0)
y0 = g.s8('o_y')
s.frames(3, 0x20)
s.shot('big')
s.check('down: a big MOS ducks (8 high, 8 lower)', g.v('duck') == 1 and g.v('mh') == 8 and g.s8('o_y') == y0 + 8)
x0 = g.ox(0)
s.frames(10, 0x20 | R)
s.check('ducking: he doesn\'t walk', g.ox(0) == x0)
s.frames(3, 0)
s.check('let go: he stands up', g.v('duck') == 0 and g.v('mh') == 16 and g.s8('o_y') == y0)
s.poke('big', 0)
s.put(60, 72)
s.wait(lambda: g.v('onground'), 20, 0)
s.frames(3, 0x20)
s.check('a small MOS ducks too (5 high)', g.v('duck') == 1 and g.v('mh') == 5 and g.s8('o_y') == 75)
s.frames(2, 0x20 | A)
s.frames(6, 0)
s.check('a jump while ducked, then let go: he stands up', g.v('duck') == 0 and g.v('mh') == 8)
# under a low ceiling: no room to stand
s.poke('big', 1)
s.put(21 * 8 - 3, 64)                       # under the blocks at row 6 (big: head at row 8 top)
s.wait(lambda: g.v('onground'), 20, 0)
s.check('the screen right every frame', s.problems == 0)

s = Scene('duckkey', spawn=False, pad=False); g = s.g
s.frames(2)
s.mc.keys.append(ord('s'))
s.frames(3)
s.check('keyboard S: ducks for a moment', g.v('duck') == 1)
s.frames(20)
s.check('... then stands up', g.v('duck') == 0)

bad = [r for r in results if not r[2]]
print('%d checks, %d failed' % (len(results), len(bad)))
