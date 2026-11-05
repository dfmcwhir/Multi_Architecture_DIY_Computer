# ---- NEW: a pipe down into the bonus room, and back out -------------------------
# (the scenes of the newer features; run with test/runf.py, which puts
#  features.py's set-up in front)
s = Scene('pipe', spawn=False); g = s.g
lv = levels.WORLDS[0][0]
s.frames(2)
s.put(lv.room and 38 * 8 + 4, 40)               # on the pipe at 38 (3 high: top row 7)
s.wait(lambda: g.v('onground'), 30, 0)
s.check('standing on the pipe', g.v('onground') and g.tile(38, 7) == T['PIPEINL'])
ok = s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
s.check('down: into the pipe', ok)
ok = s.wait(lambda: g.v('in_room') == 1 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
s.frames(10, 0); s.shot('room')
s.check('the bonus room: the view on it', ok and g.w('scroll') == lv.room * 4 and lv.room * 8 < g.ox(0) < (lv.room + 20) * 8)
b0 = g.v('bits') + 8 * g.v('bytes')
s.put((lv.room + 9) * 8 + 4, 60)                 # through the bits on row 9
s.frames(30, R)
s.check('bits in it', g.v('bits') + 8 * g.v('bytes') > b0)
s.check('the view stays put', g.w('scroll') == lv.room * 4)
s.put((lv.room + 15) * 8 + 4, 40)                # on the way out
s.wait(lambda: g.v('onground'), 30, 0)
ok = s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
ok = ok and s.wait(lambda: g.v('in_room') == 0 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
s.frames(5, 0); s.shot('out')
top = 10 - 4                                    # (the exit pipe at 58 is 4 high)
s.check('out on top of the pipe at 58', ok and g.ox(0) == lv.out * 8 + 4 and g.s8('o_y') + g.v('mh') in (top * 8, top * 8 + 1))   # (read mid-frame: +1 while it falls back onto it)
s.check('the level as before', g.v('lv_w') == lv.w and g.w('scroll') <= g.w('max_sc'))
s.frames(20, R)
s.check('walking on', g.v('mstate') == 0 and g.ox(0) > lv.out * 8 + 10)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: the enemies are still there after the bonus room; out under a ceiling -----
s = Scene('pipe2'); g = s.g
lv = levels.WORLDS[0][0]
s.frames(2)
s.put(38 * 8 + 4, 40)
s.wait(lambda: g.v('onground'), 30, 0)
s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
s.wait(lambda: g.v('in_room') == 1 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
s.frames(20, 0)
ei = g.v('en_i')
s.put((lv.room + 15) * 8 + 4, 40)
s.wait(lambda: g.v('onground'), 30, 0)
s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
s.wait(lambda: g.v('in_room') == 0 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
s.check('in the room no enemies were used up', ei < 3 * len(lv.en) and g.v('en_i') < 3 * len(lv.en))
seen = set()
s.poke('inv_t', 255)
for k in range(400):
    s.frames(1, R | (A if k % 30 < 12 else 0))
    if g.v('inv_t') < 30: s.poke('inv_t', 255)
    for i in range(1, 7):
        if g.v('o_kind', i) in (K_BUG, K_SHELLY): seen.add(g.ox(i) // 8 // 4)
    if g.v('mstate'): break
s.check('gates further on still come', len(seen) >= 2)
for wi in range(5):
    lv = levels.WORLDS[wi][1]
    if lv.room: break
s = Scene('pipe3', level=1, world=wi + 1, spawn=False); g = s.g
s.frames(2)
x = [c for c in range(lv.w) if any(lv.g[r][c] == T['PIPEINL'] for r in range(11))][0]
top = [r for r in range(11) if lv.g[r][x] == T['PIPEINL']][0]
s.put(x * 8 + 4, top * 8 - 8)
s.wait(lambda: g.v('onground'), 30, 0)
s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
s.wait(lambda: g.v('in_room') == 1 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
s.put((lv.room + 15) * 8 + 4, 40)
s.wait(lambda: g.v('onground'), 30, 0)
s.wait(lambda: g.v('mstate') == 6, 10, 0x20)
ok = s.wait(lambda: g.v('in_room') == 0 and g.v('mstate') == 0 and not g.v('full'), 60, 0)
otop = [r for r in range(11) if lv.g[r][lv.out] == T['PIPETL']][0]
s.frames(3, 0); s.shot('out')
s.check('%s: out on top of the pipe, under the ceiling' % lv.name, ok and g.s8('o_y') + g.v('mh') == otop * 8 and g.v('onground'))
s.check('screen right every frame', s.problems == 0)

# ---- NEW: the overclock device ---------------------------------------------------
s = Scene('oc', spawn=False); g = s.g
s.frames(2)

g.mem[syms['map'] + 6 * 256 + 16] = T['QOC'] * 4
s.put(16 * 8 - 3, 72)
s.frames(3, 0)
s.frames(1, A); s.wait(lambda: g.tile(16, 6) == T['USED'], 30, A)
s.check('the OC block gives an OC device', any(g.v('o_kind', i) == K_OC for i in range(1, 7)))
s.frames(12, 0); s.shot('oc')
sc0 = g.score()
ok = s.wait(lambda: g.v('oc_t') > 0, 200, R)
s.check('catching it: overclocked, 1000', ok and g.score() - sc0 == 1000)
s.frames(10, R)
s.check('always running', g.v('in_run') == 1 and abs(g.vx(0)) > 1.6)
s.obj(1, K_BUG, g.ox(0) + 24, 72, -0.625)
ok = s.wait(lambda: g.v('o_kind', 1) == 0, 40, 0)
s.check('touching a gate knocks it out', ok and g.v('mstate') == 0 and g.v('big') == 0)
hid = 0
for k in range(16):
    s.frames(1, 0)
    if g.mos_frame() is None: hid += 1
s.check('MOS flashes', 3 < hid < 13)
s.wait(lambda: g.v('oc_t') == 0, 250, 0)
s.obj(1, K_BUG, g.ox(0) + 24, 72, -0.625)
ok = s.wait(lambda: g.v('mstate') == 4, 60, 0)
s.check('then it wears off', ok)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: the fans, flying up and down -------------------------------------------
s = Scene('fan', level=1, spawn=False); g = s.g
s.frames(2)
s.put(40, 72)
s.obj(1, K_FAN, 120, 64)
s.poke('o_t', 0, 64); s.poke('o_r', 0, 32)
ys = []
for k in range(160):
    s.frames(1, 0); ys.append(g.s8('o_y', 1))
s.shot('fan')
s.check('a fan flies up 32 and back down', min(ys) <= 33 and max(ys) in (63, 64) and g.v('o_kind', 1) == K_FAN)
s.poke('big', 1); s.poke('fire', 1)
s.put(90, 64); s.frames(3, 0)
s.obj(1, K_FAN, 130, 72); s.poke('o_t', 0, 72); s.poke('o_r', 0, 40)
ok = s.wait(lambda: g.v('o_kind', 1) != K_FAN, 40, B)
s.check('an electron knocks it out', ok)
s.check('screen right every frame', s.problems == 0)
s = Scene('fanstomp', spawn=False); g = s.g
s.frames(2)
s.put(150, 20)
s.obj(1, K_FAN, 150, 64); s.poke('o_t', 0, 64); s.poke('o_r', 0, 32)
ok = s.wait(lambda: g.v('o_kind', 1) != K_FAN or g.v('mstate'), 40, 0)
s.check('stomped: knocked out, MOS bounces', ok and g.v('mstate') == 0 and g.v('o_kind', 1) == 0 and g.vy(0) < 0)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: liquid cooling: swimming, and the fish ------------------------------------
wl = [i for i, v in enumerate(levels.WORLDS[1]) if v.water][0]
s = Scene('swim', level=wl, world=2, spawn=False); g = s.g
s.frames(2)
s.check('a liquid cooling level', g.v('lv_flags') & 2)
s.put(40, 40)
s.frames(20, 0)
s.check('MOS sinks slowly', 0 < g.vy(0) <= 1.0 or g.v('onground'))
y0 = g.s8('o_y')
s.frames(1, A); s.frames(8, 0)
s.check('A: a stroke up', g.s8('o_y') < y0 - 4)
s.frames(10, 0)
s.check('swimming: legs together', not g.v('onground') and g.mos_frame()[0] == SP['MOS_SWIM'])
s.frames(1, A); s.frames(1, 0)
s.check('a stroke: a kick', g.mos_frame()[0] == SP['MOS_STAND'])
for k in range(30): s.frames(1, A if k % 3 == 0 else 0)
s.check('not out of the top', g.s8('o_y') >= 4)
s.shot('swim')
s.put(60, 40)
s.obj(1, K_FISH, 140, 40, -0.75)
xs = g.ox(1)
s.frames(20, 0)
s.check('a fish swims at MOS', g.ox(1) < xs - 10 and g.v('o_kind', 1) == K_FISH)
s.put(60, 20)
s.obj(1, K_FISH, 62, 30, 0)
ok = s.wait(lambda: g.v('mstate') == 4, 40, 0)
s.check('no stomping a fish: MOS is hurt', ok)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: the cloud throws gates ----------------------------------------------------
cw = [n for n, ws in enumerate(levels.WORLDS) if any(k == 'cloud' for x, y, k in ws[0].en)][0]
s = Scene('cloud', world=cw + 1, spawn=False); g = s.g
s.frames(2)
s.poke('inv_t', 255)
s.put(60, 72)
s.obj(1, K_CLOUD, 100, 8); s.poke('o_t', 0, 10)
ok = s.wait(lambda: any(g.v('o_kind', i) == K_BUG for i in range(2, 7)), 30, 0)
s.shot('cloud')
s.check('the cloud throws an AND gate down', ok)
s.frames(40, R)
s.check('it keeps above MOS', abs(g.ox(1) - g.ox(0)) < 40 and g.v('o_kind', 1) == K_CLOUD)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: KIL by world; the last level and Princess Graphics Card -------------------
s = Scene('final', level=3, world=5); g = s.g
lv = levels.WORLDS[4][3]
rc = [c for c in range(lv.w) if lv.g[8][c] == T['RESET']][0]
s.frames(2)
s.check('the last level', g.v('lv_flags') & 4)
s.put((rc - 6) * 8, 64)
s.frames(3, 0)                                  # (the view jumped: KIL and her again)
s.poke('en_i', 3 * sorted(lv.en).index([e for e in lv.en if e[2] == 'dragon'][0]))
ok = s.wait(lambda: any(g.v('o_kind', i) == K_DRAGON for i in range(1, 7)), 40, 0)
s.check('KIL livelier in world 5', ok and g.v('dr_spd') == 0x80 and g.v('dr_jb') == 20)
s.poke('inv_t', 255); s.put((rc - 2) * 8, 64, clear=False)
s.wait(lambda: g.v('onground'), 20, 0)
ok = s.wait(lambda: g.v('mstate') == 5, 60, R)
s.check('RESET pressed', ok)
ok = s.wait(lambda: g.v('mstate') == 0, 300, 0)
s.check('then on to the princess', ok)
ok = s.wait(lambda: g.v('mstate') == 7, 200, R)
s.check('meeting her', ok)
for k in range(150):
    s.mc.run(200_000, s.poll)
    if 'PRINCESS GRAPHICS CARD' in g.text(): break
s.shot('princess')
s.check('"HI MOS! I\'M PRINCESS GRAPHICS CARD"', 'PRINCESS GRAPHICS CARD' in g.text() and 'BETTER GRAPHICS IN THE FUTURE' in g.text())
for k in range(150):
    s.mc.run(200_000)
    if 'GAME  OVER' in g.text(): break
s.check('then the end of the game', 'GAME  OVER' in g.text())

# ---- NEW: OR gates turn back at an edge; a kicked shell goes over ---------------------
lv = levels.WORLDS[0][2]
s = Scene('ledge', level=2, spawn=False); g = s.g
s.frames(2)
x0, n, y = 30, 6, 7                                 # the ledge at 30..35, row 7
s.poke('inv_t', 255)
s.put(26 * 8, 64)                                   # (on the ledge before it, in view)
s.obj(1, K_SHELLY, 33 * 8, (y - 1) * 8, 0.625)       # walking right, to the edge
xs = []
for k in range(120):
    s.frames(1); xs.append(g.ox(1))
s.check('an OR gate walking to the end of a ledge turns back (x %d .. %d)' % (min(xs), max(xs)), g.v('o_kind', 1) == K_SHELLY and abs(g.s8('o_y', 1) - (y - 1) * 8) <= 1 and x0 * 8 - 2 <= min(xs) and max(xs) <= (x0 + n) * 8 - 6)
s.obj(1, K_BUG, 33 * 8, (y - 1) * 8, 0.625)
s.frames(40)
s.check('an AND gate walks off it', g.v('o_kind', 1) != K_BUG or g.s8('o_y', 1) > (y - 1) * 8)
s.obj(1, K_SHELL, 33 * 8, (y - 1) * 8, 2.5)
s.frames(20)
s.check('a kicked shell goes over the edge', g.v('o_kind', 1) != K_SHELL or g.s8('o_y', 1) > (y - 1) * 8)
s.check('screen right every frame', s.problems == 0)

# ---- NEW: a still shell comes back out ---------------------------------------------------
s = Scene('revive', spawn=False); g = s.g
s.frames(2)
s.put(40, 72)
s.obj(1, K_SHELL, 120, 72, 0)
s.poke('o_r', 0, 0)
ok = s.wait(lambda: g.v('o_r', 1) >= 125 and (g.v('frame') - 1) & 4, 200, 0)
s.frames(1); s.shot('legs')
s.check('a still shell: its legs show before it comes out', ok)
ok = s.wait(lambda: g.v('o_kind', 1) == K_SHELLY, 60, 0)
s.check('after 8 seconds: an OR gate again, walking at MOS', ok and g.vx(1) < 0)
s.obj(2, K_SHELL, 160, 72, 0); s.poke('o_r', 0, 0, 100)
s.frames(30)
s.obj(2, K_SHELL, 160, 72, 2.5)
s.frames(70)
s.check('a moving shell keeps going', g.v('o_kind', 2) in (K_SHELL, 0))
s.check('screen right every frame', s.problems == 0)

# ---- NEW: the high fans in the ledge levels --------------------------------------------
s = Scene('fanhi', level=2, spawn=False); g = s.g
s.frames(2)
s.poke('inv_t', 255)
s.put(10, 72)
s.obj(1, K_FAN, 160, 72); s.poke('o_t', 0, 72); s.poke('o_r', 0, 12)
ys = []
for k in range(260):
    s.frames(1); ys.append(g.s8('o_y', 1))
    if g.v('inv_t') < 30: s.poke('inv_t', 255)
s.check('a high fan flies from row 9 up to the top (%d .. %d)' % (min(ys), max(ys)), min(ys) <= 13 and max(ys) == 72)
s.check('screen right every frame', s.problems == 0)
hi = [(v.name, x, y) for ws in levels.WORLDS for v in ws for x, y, k in v.en if k == 'fanhi']
s.check('the ledge levels have high fans (%d)' % len(hi), len(hi) >= 10)

# ---- NEW: fish: faster, and wavy ones ------------------------------------------------------
wl = [i for i, v in enumerate(levels.WORLDS[1]) if v.water][0]
s = Scene('wfish', level=wl, world=2, spawn=False); g = s.g
s.frames(2)
s.poke('inv_t', 255)
s.put(20, 70)
s.obj(1, K_FISH, 150, 40, -1.0); s.poke('o_t', 0, 40); s.poke('o_r', 0, 1)
ys, xs = [], []
for k in range(100):
    s.frames(1); ys.append(g.s8('o_y', 1)); xs.append(g.ox(1))
    if g.v('inv_t') < 30: s.poke('inv_t', 255)
s.shot('wave')
s.check('a wavy fish swims up and down 12 (%d .. %d)' % (min(ys), max(ys)), min(ys) == 28 and max(ys) == 52)
s.check('a pixel a frame', xs[0] - xs[-1] >= 93)
s.check('screen right every frame', s.problems == 0)
wl2 = levels.WORLDS[1][wl]
nf = sum(1 for x, y, k in wl2.en if k in ('fish', 'wfish'))
s.check('%s: %d fish (%d wavy)' % (wl2.name, nf, sum(1 for x, y, k in wl2.en if k == 'wfish')), nf >= 14)

# ---- NEW: OR gates in front of AND gates ---------------------------------------------
bad = []
for ws in levels.WORLDS:
    for v in ws:
        en = sorted((x, y, k) for x, y, k in v.en if k in ('and', 'or'))
        for (x1, y1, k1), (x2, y2, k2) in zip(en, en[1:]):
            if y1 == y2 and x2 - x1 <= 4 and k1 == 'and' and k2 == 'or': bad.append((v.name, x1))
print('%-8s %-45s %s' % ('order', 'OR gates in front of the AND gates beside them', 'ok' if not bad else 'FAILED %s' % bad))
if bad: results.append(('order', 'or first', False))

# ---- NEW: the terminal's sprite layer: no answer, no pictures (Scene('sprlayer') not used) ---
if not SOFT:
    os.environ['NOSPRITES'] = '1'; sim.SPRITES = False
    g = Game(pad=True, speed=0)
    sim.SPRITES = True; del os.environ['NOSPRITES']
    g.mc.run(3_000_000)
    ok = 'NEEDS THE TERMINAL' in g.text() and 'SMBSW.BIN' in g.text()
    results.append(('sprlayer', 'an old terminal (no answer): a message', ok)); print('sprlayer an old terminal (no answer): a message', ok)
    g = Game(pad=True, speed=0)
    g.mc.run(2_000_000)
    t = g.mc.term
    g.mc.set_pad(0x08); g.mc.run(100_000); g.mc.set_pad(0); g.mc.run(5_000_000)
    ok = len(t.pics) == len(gen.ORDER) and not t.errors and t.clip == (2, 23) and t.visible()
    results.append(('sprlayer', 'the pictures sent (%d), the sprites clipped to the view' % len(t.pics), ok)); print('sprlayer the pictures sent, clipped to the view', ok)
