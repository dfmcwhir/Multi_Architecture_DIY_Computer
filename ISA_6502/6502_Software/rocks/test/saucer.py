"""Sit still and let saucers come: check they fire, that the small one aims
at the ship, and that its bullets can destroy the ship."""
import sys, os, re, math
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('rocks.lbl')) if m}
mc = Machine('ROCKS.BIN'); mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
mc.run(6_000_000); mc.keys.append(32); mc.run(2_000_000)
for i in range(29, 45): mem[syms['o_kind'] + i] = 0
mem[syms['score'] + 2] = 1              # 10000 points: small saucers possible
for i in range(5, 29): mem[syms['o_kind'] + i] = 0      # no rocks in the way
mem[syms['o_kind'] + 5] = 3; mem[syms['o_x_hi'] + 5] = 5; mem[syms['o_y_hi'] + 5] = 5   # (one far away, so the wave goes on)
for k in ('o_vx_lo', 'o_vx_hi', 'o_vy_lo', 'o_vy_hi'): mem[syms[k] + 5] = 0
mem[syms['lives']] = 9
FW, FH = 160, 92
def wd(a, b, m):
    d = (b - a) % m
    return d - m if d > m // 2 else d
seen = set(); shots = []; deaths = 0; lives = v('lives'); small = big = 0; last = 0
for step in range(4000):
    mem[syms['inv_t']] = 0
    if v('o_kind', 45) != 5 and v('ufo_wait') < v('ufo_next') - 2: mem[syms['ufo_wait']] = v('ufo_next') - 1
    mc.run(20_000)
    if v('o_kind', 45) == 5 and not last:
        if v('o_size', 45): small += 1
        else: big += 1
    last = v('o_kind', 45) == 5
    for i in (46, 47):
        if v('o_kind', i) == 6 and (i, v('o_t', i)) not in seen and v('o_t', i) >= 28 and v('o_kind', 0) == 1:
            seen.add((i, v('o_t', i)))
            vx = (v('o_vx_hi', i) << 8 | v('o_vx_lo', i)); vx -= 65536 if vx > 32767 else 0
            vy = (v('o_vy_hi', i) << 8 | v('o_vy_lo', i)); vy -= 65536 if vy > 32767 else 0
            dx, dy = wd(v('o_x_hi', i), v('o_x_hi', 0), FW), wd(v('o_y_hi', i), v('o_y_hi', 0), FH)
            err = abs((math.degrees(math.atan2(vy, vx) - math.atan2(dy, dx)) + 180) % 360 - 180)
            shots.append((v('o_size', 45), err))
    for i in (46, 47):
        if v('o_t', i) < 28: seen.discard((i, v('o_t', i) + 1))
    if v('lives') < lives: deaths += 1
    lives = v('lives')
    if deaths >= 4: break
sm = [e for s, e in shots if s == 1]; bg = [e for s, e in shots if s == 0]
print('saucers: big %d small %d; shots: big %d, small %d; deaths %d' % (big, small, len(bg), len(sm), deaths))
if sm: print('small saucer aim error: median %.0f deg, worst %.0f deg' % (sorted(sm)[len(sm) // 2], max(sm)))
if bg: print('big saucer shot directions spread: %.0f deg median error (random)' % sorted(bg)[len(bg) // 2])
print('errors', mc.term.errors[:3])
mc.term.png(sys.argv[1] + '/saucer.png')
