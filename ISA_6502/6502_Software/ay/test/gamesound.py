"""gamesound.py - run a game's own bot test (its test/play.py) with the sound
card and the VIA's timer 2 modelled, and report on the sound:

    PY65=path/to/py65 python3 ../ay/test/gamesound.py GAME OUTDIR [SND_A SND_B ...]
    (from the game's folder, after sh b.sh; GAME is its name: snake, rocks ...)

It counts the sounds the game asked for (sfx_play: script and voice), checks
that the sound ran 50 times a second, that the card was only written to,
that timer 2's interrupt stayed off, and that each SND_ name given was
played at least once; it writes OUTDIR/GAME_sound.wav (the first 40 s).
The game's play.py runs as it always does (its environment settings too;
PLAYARGS=... gives it arguments before OUTDIR).
"""
import sys, os, re, runpy, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices import mpu6502
from aysnd import attach

game, OUT = sys.argv[1], sys.argv[2]
want = sys.argv[3:]
os.makedirs(OUT, exist_ok=True)
lbl = os.environ.get('LBL', game + '.lbl')
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open(lbl)) if m}
src = open(os.environ.get('SRC', game + '.s')).read()
import glob
for inc in glob.glob('*_sound.inc'):
    src += open(inc).read()
names = {int(v): k for k, v in re.findall(r'^((?:SND|MUS)_\w+)\s*=\s*(\d+)', src, re.M)}

# the game's emulator: every Machine gets the sound card
sys.path.insert(0, os.path.join(os.getcwd(), 'test'))
import sim
machines = []
orig_init = sim.Machine.__init__
def init(self, *a, **k):
    orig_init(self, *a, **k)
    self.snd = attach(self.mpu)
    machines.append(self)
sim.Machine.__init__ = init

plays = collections.Counter()
low = [0xFF]
SFX_PLAY = syms['sfx_play']
orig_step = mpu6502.MPU.step
def step(self):
    if self.pc == SFX_PLAY: plays[(self.a, self.x)] += 1
    if self.sp < low[0]: low[0] = self.sp
    return orig_step(self)
mpu6502.MPU.step = step

sys.argv = ['play.py'] + os.environ.get('PLAYARGS', '').split() + [OUT]   # (PLAYARGS: before OUTDIR)
try:
    runpy.run_path(os.path.join('test', 'play.py'), run_name='__main__')
except SystemExit:
    pass

fails = []
def check(ok, msg):
    print(('ok    ' if ok else 'FAIL  ') + msg)
    if not ok: fails.append(msg)

print('\n--- sound (%s)' % game)
s = machines[-1].snd
print('played (sound/voice count): ' + ', '.join('%s/%d %d' % (names.get(a, a), x, n) for (a, x), n in sorted(plays.items())))
check(not s.errors, 'only writes to the card %s' % s.errors[:2])
check(not (s.ier & 0x20), 'timer 2 interrupt left off')
t7 = [t for t, r, v in s.log if r == 7]
if len(t7) > 100:
    span = (t7[-1] - t7[0]) / 2e6
    rate = len(t7) / span
    gaps = [b - a for a, b in zip(t7, t7[1:])]
    late = sum(1 for g in gaps if g > 60000)
    big = sorted(((g, t7[i]) for i, g in enumerate(gaps) if g > 60000), reverse=True)[:5]
    if big: print('      longest gaps: ' + ', '.join('%.2f s at %.1f s' % (g / 2e6, t / 2e6) for g, t in big))
    check(abs(rate - 50) < 2.5, '%.1f ticks a second over %.0f s (%d gaps over 30 ms)' % (rate, span, late))
else:
    check(False, 'the sound hardly ran (%d ticks)' % len(t7))
check(low[0] >= 0x80, 'the stack stayed above $0180 ($01%02X)' % low[0])
got = collections.Counter()
for (a, x), n in plays.items(): got[names.get(a, a)] += n
for w in want:
    check(got[w] > 0, '%s played (%d)' % (w, got[w]))
if t7:
    s.wav(os.path.join(OUT, game + '_sound.wav'), end=t7[0] + 40 * 2000000)
print('\n%d failed' % len(fails) if fails else '\nall passed')
sys.exit(1 if fails else 0)
