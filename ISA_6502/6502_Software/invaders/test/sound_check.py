"""sound_check.py - play INVADERS with the bot (test/play.py) with the sound
card modelled (SOUND=1), and count which sounds the game asked for.

    PY65=path/to/py65 python3 test/sound_check.py OUTDIR      (from the invaders folder)
"""
import sys, os, runpy, re, collections
os.environ['SOUND'] = '1'
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices import mpu6502
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('invaders.lbl')) if m}
plays = collections.Counter()
orig = mpu6502.MPU.step
def step(self):
    if self.pc == syms['sfx_play']: plays[(self.a, self.x)] += 1
    return orig(self)
mpu6502.MPU.step = step
OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
sys.argv = ['play.py', OUT]
g = runpy.run_path(os.path.join(os.path.dirname(__file__), 'play.py'), run_name='__main__')
names = {}
for l in open('invaders.s'):
    m = re.match(r'(SND_\w+)\s*= (\d+)', l)
    if m: names[int(m.group(2))] = m.group(1)
print('played (sound, voice): ' + ', '.join('%s/%d %d' % (names.get(a, a), x, n) for (a, x), n in sorted(plays.items())))
st = g['stats']
fails = []
def check(ok, msg):
    print(('ok    ' if ok else 'FAIL  ') + msg)
    if not ok: fails.append(msg)
k = lambda name, v: plays[(next(i for i, nm in names.items() if nm == name), v)]
check(sum(plays[(i, 0)] for i in range(4)) > 50, 'the march (voice 0)')
check(k('SND_SHOT', 4) > 10, 'shots (voice 4)')
check(k('SND_DEATH', 5) == k('SND_DEATH2', 3) > 0, 'deaths: noise and tone together')
s = g['mc'].snd
check(not s.errors and not (s.ier & 0x20), 'no card reads, timer 2 interrupt off')
print('\n%d failed' % len(fails) if fails else '\nall passed')
