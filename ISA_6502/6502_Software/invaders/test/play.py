# usage (from the invaders folder): ca65 -g invaders.s -o t.o
#   ld65 -C invaders.cfg t.o -o t.bin -Ln invaders.lbl ; PY65=path/to/py65 python3 test/play.py shots
#   PAD=1 plays with the gamepad
#   MODE=cheat (infinite lives, no shields) or MODE=idle (never shoots) for the other tests
"""Play the game with a simple bot and check the screen against the game state."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)

syms = {}
for line in open('invaders.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m:
        syms[m.group(2)] = int(m.group(1), 16)

SPR = [0x98, 0x3F, 0x64, 0x58, 0x3F, 0xA4, 0x9D, 0x3C, 0x6E, 0x5E, 0x3C, 0xAD,
       0x76, 0x3F, 0xB9, 0xB6, 0x3F, 0x79]
ROWTYPE = [0, 6, 6, 12, 12]

import re as _re
code_end = int(_re.search(r'RODATA\s+([0-9A-F]+)', open('invaders.map').read()).group(1), 16)
mc = Machine('INVADERS.BIN', speed=int(os.environ.get('SPEED', '2')), code_end=code_end)
mem = mc.mpu.memory
def v(name, i=0): return mem[syms[name] + i]

def cell(col, row):
    b = 0
    for i in range(8):
        b |= mc.term.pix[row * 4 + i // 2][col * 2 + (i & 1)] << i
    return b

problems = []
def check():
    """every live invader is on screen with its current sprite; dead slots blank"""
    for r in range(5):
        al = v('alive', r)
        if not al: continue
        x, y, f = v('rowx', r), v('rowy', r), v('rowfrm', r)
        if y > 23:
            problems.append('tick %d row %d off screen x=%d y=%d alive=%02X dir=%d drop=%d' % (ticks, r, x, y, al, v('dir'), v('dropping'))); continue
        for s in range(8):
            if (x + 4 * s) & 255 > 77: continue   # unused slot outside the screen
            if (x + 4 * s + 2) & 255 > 79 or (x+4*s)&255 > (x+4*s+2)&255:
                problems.append('tick %d row %d slot %d alive=%02X x=%d (wraps)' % (ticks, r, s, al, x)); continue
            got = [cell((x + 4 * s + k) & 255, y) for k in range(3)]
            if al >> s & 1:
                want = SPR[ROWTYPE[r] + f: ROWTYPE[r] + f + 3]
                if got != want:
                    problems.append('tick %d row %d slot %d: %s != %s' % (ticks, r, s, got, want))
            else:
                expl = v('expl_t') and v('expl_r') == r and v('expl_col') == (x + 4 * s) & 255 and v('expl_row') == y
                if not expl and any(got):
                    # a bullet or bomb pixel passing through is fine
                    if sum(bin(g).count('1') for g in got) > 2:
                        problems.append('tick %d row %d dead slot %d not blank %s' % (ticks, r, s, got))


MODE = os.environ.get('MODE', 'normal')
PAD = os.environ.get('PAD') == '1'
ticks = 0
stats = {'kills': 0, 'deaths': 0, 'waves': 0, 'ufo': 0}
last = {}
def bot(m):
    global ticks
    # read_keys is called once per tick; only act on its first getc call
    ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
    if not (syms['read_keys'] <= ret < syms['handle_key']):     # getc called from read_keys
        return
    if m.keys or m.mpu.processorCycles - last.get('c', 0) < 1500: return
    last['c'] = m.mpu.processorCycles
    ticks += 1
    if ticks % 3 == 0: check()
    if ticks in (5, 400, 1500): m.term.png('%s/tick%05d.png' % (OUT, ticks))
    if MODE == 'cheat':
        mem[syms['lives']] = 9
        for i in range(24): mem[syms['shields']+i] = 0
    if MODE == 'idle':
        mem[syms['lives']] = 9
        if ticks % 200 == 0: m.term.png('%s/idle%05d.png' % (OUT, ticks))
        return
    # aim at the lowest live invader nearest to the player
    px = v('px'); best = None
    for r in range(4, -1, -1):
        al = v('alive', r)
        for s in range(8):
            if al >> s & 1:
                col = v('rowx', r) + 4 * s
                d = abs(col - px)
                if best is None or d < best[0]: best = (d, col)
        if best: break
    if not best:
        if PAD: m.set_pad(0)
        return
    if PAD:     # hold the d-pad towards the target, hold A when lined up
        b = 0x80 if best[1] > px else 0x40 if best[1] < px else 0
        if abs(best[1] - px) <= 1: b |= 0x01
        if ticks % 2: b &= ~0x01        # release A now and then (a new press each shot)
        m.set_pad(b)
        return
    if best[1] > px: m.keys.append(ord('d'))
    elif best[1] < px: m.keys.append(ord('a'))
    if abs(best[1] - px) <= 1: m.keys.append(ord(' '))

def snapshot_state():
    return dict(score=v('score') | v('score', 1) << 8, lives=v('lives'), wave=v('wave'), alive=v('alive_count'))

# title screen
mc.run(400000)
mc.term.png(OUT + '/title.png')
assert not mc.term.errors, mc.term.errors
if PAD:     # Start on the pad starts the game in gamepad mode
    mc.set_pad(0x08); mc.run(100000); mc.set_pad(0); mc.run(100000)
    print('controls after Start:', 'gamepad' if v('ctrl') else 'keyboard')
else:
    mc.keys.append(ord(' '))
prev = snapshot_state()
import time; t0=time.time()
for step in range(int(os.environ.get('STEPS','4000'))):
    mc.run(200000, poll=bot)
    st = snapshot_state()
    if st['wave'] != prev['wave']:
        print('wave cleared at tick', ticks, st)
        mc.term.png('%s/wave%d.png' % (OUT, st['wave']))
    if st['lives'] < prev['lives']:
        print('lost a life at tick', ticks, st)
    prev = st
    if step % 20 == 0: print('step', step, 'tick', ticks, st, '%.0fs' % (time.time()-t0), flush=True)
    if mem[syms['lives']] == 0 or (st['wave'] >= 2) or (MODE=='idle' and mem[syms['invaded']]):
        break
mc.run(3000000)
mc.term.png(OUT + '/end.png')
print('final', snapshot_state(), 'ticks', ticks, 'bytes sent', mc.term.nbytes, 'cycles', mc.mpu.processorCycles)
print('terminal errors:', mc.term.errors[:10])
print('screen/state mismatches:', len(problems)); print('\n'.join(problems[:15]))
if mc.snd:      # SOUND=1: what the sound card was told
    s = mc.snd
    print('sound: %d register writes, errors %s, timer 2 interrupt %s' % (len(s.log), s.errors[:3], 'ON' if s.ier & 0x20 else 'off'))
    for c, h in enumerate(s.heard()):
        pers = sorted(set(p for p, v, t, n in h if t))
        print('  channel %s: %d tone periods %s%s, noise %s' % ('ABC'[c], len(pers), pers[:12], '...' if len(pers) > 12 else '', any(n for p, v, t, n in h)))
    import pickle; pickle.dump(s.log, open(OUT + '/sound.pkl', 'wb'))
    if os.environ.get('WAV'):
        s.wav(os.environ['WAV'], end=min(s.log[-1][0], 30 * 2000000))
        print('wrote', os.environ['WAV'])
