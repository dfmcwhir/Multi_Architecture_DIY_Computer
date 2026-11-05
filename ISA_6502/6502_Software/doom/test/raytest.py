"""Compare the 6502 ray caster with a floating point one at random places
in each level: wall height per column, which block and which face."""
import sys, os, re, math, random
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, '.')
from sim import Machine
import gen_tables as G
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
mc = Machine('DOOM.BIN', speed=0)
mpu = mc.mpu; mem = mpu.memory
def call(name):
    mem[0x400] = 0x20; mem[0x401] = syms[name] & 255; mem[0x402] = syms[name] >> 8; mem[0x403] = 0xDB
    mpu.pc = 0x400; mpu.sp = 0xFF
    while mem[mpu.pc] != 0xDB: mpu.step()
def S(n, v): mem[syms[n]] = v & 255
MAP = 0x5040
offs = [int(round(G.col_angle(c) * G.ANG / (2 * math.pi))) for c in range(G.COLS)]
rnd = random.Random(7)
tot = bad_h = bad_t = 0
worst = []
for lvl in ('E1M1.LVL', 'E1M2.LVL', 'E1M3.LVL'):
    data = open(lvl, 'rb').read()
    for i, b in enumerate(data): mem[0x5000 + i] = b
    tiles = data[64:64 + 1024]
    for trial in range(25):
        while True:
            x = rnd.randrange(32 * 256); y = rnd.randrange(32 * 256)
            if tiles[(y >> 8) * 32 + (x >> 8)] == 0: break
        a = rnd.randrange(1024)
        S('px_lo', x); S('px_hi', x >> 8); S('py_lo', y); S('py_hi', y >> 8); S('pa_lo', a); S('pa_hi', a >> 8)
        call('render_view')
        for c in range(0, 80):
            ang = (a + offs[c]) % 1024 * 2 * math.pi / 1024
            dx, dy = math.cos(ang), math.sin(ang)
            # float DDA
            px, py = x / 256, y / 256
            mx, my = int(px), int(py)
            ddx = abs(1 / dx) if dx else 1e9; ddy = abs(1 / dy) if dy else 1e9
            sx = (mx + 1 - px) * ddx if dx > 0 else (px - mx) * ddx
            sy = (my + 1 - py) * ddy if dy > 0 else (py - my) * ddy
            while True:
                if sx < sy: d = sx; sx += ddx; mx += 1 if dx > 0 else -1; side = 0
                else: d = sy; sy += ddy; my += 1 if dy > 0 else -1; side = 1
                if tiles[my * 32 + mx]: break
            perp = d * math.cos(offs[c] * 2 * math.pi / 1024)
            want = G.wall_h(min(1023, int(perp * 32)))
            got = mem[syms['c_hgt'] + c]
            cell = mem[syms['c_mplo'] + c] | mem[syms['c_mphi'] + c] << 8
            gcell = MAP + my * 32 + mx
            pidx = mem[syms['c_pidx'] + c]
            tot += 1
            if abs(got - want) > max(2, want * 0.08):
                bad_h += 1; worst.append((abs(got - want), lvl, x / 256, y / 256, a, c, got, want))
            if cell != gcell or (pidx >> 2 & 1) != side or pidx >> 3 != tiles[my * 32 + mx]:
                bad_t += 1
print('columns', tot, 'height off', bad_h, 'block/face differs', bad_t)
for w in sorted(worst, reverse=True)[:8]: print(w)
