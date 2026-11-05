# usage (from the critters folder):
#   ca65 -g critters.s -o t.o ; ld65 -C critters.cfg t.o -o t.bin -Ln critters.lbl
#   PY65=path/to/py65 python3 test/play.py LEVEL OUTDIR     (the bin is read from CRITTERS.BIN)
"""Play one level of CRITTERS with a scripted player that uses the real keys,
and check the screen against the terrain bitmap + creatures every few ticks."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine

LEVEL = int(sys.argv[1])
OUT = sys.argv[2] if len(sys.argv) > 2 else 'shots'
os.makedirs(OUT, exist_ok=True)
syms = {}
for line in open('critters.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)

code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('critters.map').read()).group(1), 16)
PAD = os.environ.get('PAD') == '1'
mc = Machine('CRITTERS.BIN', speed=0, code_end=code_end)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
MAXC = 20
WALK, FALL, FLOAT, CLIMB, BLOCK, BUILD, BASH, DIG, SPLAT, GONE = range(1, 11)
SHAPES = {0: [(0, 0), (0, -1)], 1: [(0, 0), (0, -1), (0, -2), (-1, -3), (0, -3), (1, -3)],
          2: [(0, 0), (0, -1), (-1, -1), (1, -1)], 3: [(-1, 0), (0, 0), (1, 0)], 4: [(0, -5)]}

def tbit(x, y):
    return (mem[syms['terrain'] + y * 20 + x // 8] >> (7 - x % 8)) & 1

def decor():
    hx, hy, ex, ey = v('hx'), v('hy'), v('ex'), v('ey')
    p = set()
    for i in range(7): p.add((hx - 3 + i, hy - 7)); p.add((ex - 3 + i, ey - 7))
    for i in range(3): p.add((hx - 3, hy - 6 + i)); p.add((hx + 3, hy - 6 + i))
    for i in range(4): p.add((ex - 3, ey - 6 + i)); p.add((ex + 3, ey - 6 + i))
    p |= {(ex, ey - 8), (ex, ey - 9), (ex + 1, ey - 9)}
    return p

problems = []
def check():
    want = set(decor())
    for i in range(MAXC):
        on = v('d_on', i)
        if not on: continue
        x, y = v('d_x', i), v('d_y', i)
        for dx, dy in SHAPES[v('d_shp', i)] + (SHAPES[4] if on & 2 else []):
            want.add((x + dx, y + dy))
    bad = 0
    for y in range(88):
        for x in range(160):
            w = 1 if (tbit(x, y) or (x, y) in want) else 0
            if mc.term.pix[y][x] != w:
                bad += 1
                if bad <= 3: problems.append('tick %d pixel %d,%d screen %d want %d' % (ticks, x, y, mc.term.pix[y][x], w))
    # the creatures must never be inside terrain
    for i in range(MAXC):
        st = v('c_st', i)
        if WALK <= st <= DIG:
            x, y = v('c_x', i), v('c_y', i)
            if tbit(x, y) or tbit(x, y - 1):
                problems.append('tick %d creature %d (state %d) inside terrain at %d,%d' % (ticks, i, st, x, y))

# ---- scripted players, one per level -------------------------------------------
done = set()
def give(i, skill, keys):
    """select creature i with the . key, then press the skill number"""
    if v('sel') != i:
        # press '.' until selected (each press moves one to the right, wrapping)
        n = sum(1 for j in range(MAXC) if WALK <= v('c_st', j) <= DIG)
        keys += ['.'] * (n + 1)
        want_sel[0] = (i, skill)
        return
    keys.append(str(skill))

want_sel = [None]
def policy(keys):
    c = [(i, v('c_x', i), v('c_y', i), v('c_st', i), v('c_dir', i), v('c_fl', i)) for i in range(MAXC)]
    def first(cond):
        for i, x, y, st, d, fl in c:
            if cond(i, x, y, st, d, fl): return i
    if LEVEL == 1:      # dig through the upper floor
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 29 and 70 <= x <= 100)
        if i is not None and 'dig' not in done: plan(i, 6, 'dig')
    if LEVEL == 2:      # a blocker before the cliff
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 59 and 88 <= x <= 95 and d == 1)
        if i is not None and 'block' not in done: plan(i, 3, 'block')
    if LEVEL == 3:      # bash through the rock
        i = first(lambda i, x, y, st, d, fl: st == WALK and 51 <= y <= 56 and 64 <= x <= 68 and d == 1)
        if i is not None and 'bash' not in done: plan(i, 5, 'bash')
    if LEVEL == 4:      # bridge the gap
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 49 and 54 <= x <= 58 and d == 1)
        if i is not None and 'build' not in done: plan(i, 4, 'build')
    if LEVEL == 5:      # everyone gets climber + floater
        for i, x, y, st, d, fl in c:
            if st == WALK and not fl & 1 and ('c%d' % i) not in done: plan(i, 1, 'c%d' % i); break
            if st in (WALK, CLIMB) and not fl & 2 and ('f%d' % i) not in done: plan(i, 2, 'f%d' % i); break
    if LEVEL == 6:      # bridge, bash the rock, dig down
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 29 and 42 <= x <= 46 and d == 1)
        if i is not None and 'build' not in done: plan(i, 4, 'build')
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 29 and 85 <= x <= 88 and d == 1)
        if i is not None and 'bash' not in done: plan(i, 5, 'bash')
        i = first(lambda i, x, y, st, d, fl: st == WALK and y == 29 and 105 <= x <= 115)
        if i is not None and 'dig' not in done and 'bash' in done: plan(i, 6, 'dig')

pending = []
def plan(i, skill, tag):
    if not pending:
        pending.append((i, skill, tag))

ticks = 0; last = {}
def bot(m):
    global ticks
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not (syms['read_keys'] <= ret < syms['handle_key']) or m.keys: return      # getc from read_keys
    if m.mpu.processorCycles - last.get('c', 0) < 1500: return
    last['c'] = m.mpu.processorCycles
    ticks += 1
    if ticks % 7 == 0: check()
    if ticks in (60, 250, 600): m.term.png('%s/L%d_t%04d.png' % (OUT, LEVEL, ticks))
    keys = []
    if PAD:
        if m.pad:                      # release between presses
            m.set_pad(0); return
        if pending:
            i, skill, tag = pending[0]
            if not (WALK <= v('c_st', i) <= DIG):
                pending.pop(0)
            elif v('sel') != i:
                m.set_pad(0x80)        # right: next critter
            elif v('cur_skill') != skill - 1:
                m.set_pad(0x20 if v('cur_skill') < skill - 1 else 0x10)   # down / up: skill
            else:
                m.set_pad(0x01); done.add(tag); pending.pop(0)            # A: give it
        else:
            policy(keys)
            if not pending:            # meanwhile get the next skill ready on the bar
                want = {1: 6, 2: 3, 3: 5, 4: 4, 5: 1, 6: (4 if 'build' not in done else 5 if 'bash' not in done else 6)}[LEVEL]
                lead = [i for i in range(MAXC) if v('c_st', i) in (WALK, FALL)]
                if v('cur_skill') != want - 1:
                    m.set_pad(0x20 if v('cur_skill') < want - 1 else 0x10)
                elif LEVEL != 5 and lead and v('sel') != lead[0]:
                    m.set_pad(0x80)    # and select the leading critter early
        return
    if pending:
        i, skill, tag = pending[0]
        if not (WALK <= v('c_st', i) <= DIG):
            pending.pop(0)
        elif v('sel') != i:
            keys.append('.')           # one step right per tick until it is selected
            last.setdefault('presses', 0); last['presses'] += 1
        else:
            keys.append(str(skill)); done.add(tag); pending.pop(0)
    else:
        policy(keys)
    m.keys += [ord(k) for k in keys]

mc.run(1500000)
if LEVEL == 1: mc.term.png(OUT + '/title.png')
if PAD:     # up to the level, Start to play, then A on the level's page
    for k in range(LEVEL - 1):
        mc.set_pad(0x10); mc.run(60000); mc.set_pad(0); mc.run(60000)
    mc.set_pad(0x08); mc.run(60000); mc.set_pad(0); mc.run(4000000)
    print('controls:', 'gamepad' if v('ctrl') else 'keyboard', ' level', v('level') + 1)
    mc.term.png('%s/L%d_intro.png' % (OUT, LEVEL))
    mc.set_pad(0x01); mc.run(60000); mc.set_pad(0)
else:
    mc.keys.append(ord(str(LEVEL)))
    mc.run(4000000)
    mc.term.png('%s/L%d_intro.png' % (OUT, LEVEL))
    mc.keys.append(ord(' '))
while ticks < 3: mc.run(20000, poll=bot)
mc.term.png('%s/L%d_start.png' % (OUT, LEVEL))
for step in range(4000):
    mc.run(400000, poll=bot)
    if v('released') == v('total') and v('out') == v('nblock') and ticks > 5: break
    if v('time_bcd') == 0 and v('time_bcd', 1) == 0: break
    if ticks > 6000: break
# check when the game gets to level_end: by then the last tick's screen
# changes have been sent (they go at the end of each tick, not pixel by pixel)
seen = []
ostep = mc.mpu.step
def step():
    if mc.mpu.pc == syms['level_end'] and not seen:
        seen.append(1); check()
    ostep()
mc.mpu.step = step
for k in range(400):
    if seen: break
    mc.run(20000)
mc.mpu.step = ostep
mc.term.png('%s/L%d_final.png' % (OUT, LEVEL))
mc.run(3000000)
mc.term.png('%s/L%d_end.png' % (OUT, LEVEL))
print('level %d: saved %d of %d (need %d), ticks %d, skills left %s, done %s' % (
    LEVEL, v('saved'), v('total'), v('need'), ticks, [v('skills', k) for k in range(6)], sorted(done)))
print('  terminal errors:', mc.term.errors[:5])
print('  screen mismatches:', len(problems)); print('  ' + '\n  '.join(problems[:8]))
