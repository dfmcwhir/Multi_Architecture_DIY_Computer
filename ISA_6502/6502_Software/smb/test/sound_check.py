"""sound_check.py - play SUPER MOS BROS. with the bot (test/play.py) with the
sound card modelled, then check what it was told:
  - the sound ran 50 times a second (the gaps between ticks)
  - the effects were heard: jumps, coins, stomps, the level's music ...
  - the stack stayed clear of the engine's variables at $0100-$017A
and write a .WAV of the first 40 seconds to listen to.

    PY65=path/to/py65 python3 test/sound_check.py OUTDIR    (from the smb folder)
"""
import sys, os, runpy, re, collections
os.environ['SOUND'] = '1'
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices import mpu6502

low = [0xFF]
plays = collections.Counter()           # sfx_play calls: script number
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('smb.lbl')) if m}
SFX_PLAY = syms['sfx_play']
orig = mpu6502.MPU.step
def step(self):
    if self.sp < low[0]: low[0] = self.sp
    if self.pc == SFX_PLAY: plays[self.a] += 1
    return orig(self)
mpu6502.MPU.step = step

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
sys.argv = ['play.py', OUT]
g = runpy.run_path(os.path.join(os.path.dirname(__file__), 'play.py'), run_name='__main__')
mc = g['mc']
s = mc.snd

fails = []
def check(ok, msg):
    print(('ok    ' if ok else 'FAIL  ') + msg)
    if not ok: fails.append(msg)

print('\n--- sound')
check(not s.errors, 'no reads of the card, no bad registers %s' % s.errors[:2])
check(not (s.ier & 0x20), 'timer 2 interrupt left off')
t7 = [t for t, r, v in s.log if r == 7]
gaps = [b - a for a, b in zip(t7, t7[1:])]
c = collections.Counter(min(x // 4000, 30) for x in gaps)
span = (t7[-1] - t7[0]) / 2e6
print('      ticks %d in %.1f s (%.1f a second); gaps in 2 ms steps: %s' % (len(t7), span, len(t7) / span, sorted(c.items())))
check(abs(len(t7) / span - 50) < 2.5, 'about 50 ticks a second')
check(low[0] >= 0x80, 'the stack went no lower than $01%02X (the engine has $0100-$017A)' % low[0])
# what was heard: tone periods on each channel
heard = s.heard()
pers = [set(p for p, v, t, n in h if t) for h in heard]
noise = [any(n for p, v, t, n in h) for h in heard]
def note_per(n):    # sfx.s's period for note n (C1 = 0)
    B = [3822, 3608, 3405, 3214, 3034, 2863, 2703, 2551, 2408, 2273, 2145, 2025]
    k, b = n // 12, B[n % 12]
    return (b >> k) + ((b >> (k - 1)) & 1 if k else 0)
c5, g3 = note_per(48), note_per(31)
check(c5 in pers[0], 'the outdoor tune\'s melody on A (C5 = period %d)' % c5)
check(g3 in pers[1], 'its bass on B (G3 = period %d)' % g3)
check(320 in pers[2] or 420 in pers[2], 'a jump on C (period 320/420, then sweeping)')
names = {}
for l in open('smb_sound.inc'):
    m = re.match(r'(SND|MUS)_(\w+) = (\d+)', l)
    if m: names[int(m.group(3))] = m.group(1) + '_' + m.group(2)
print('      played: ' + ', '.join('%s %d' % (names.get(k, k), n) for k, n in sorted(plays.items())))
ids = {v: k for k, v in names.items()}
lv = len(g['st']['levels'])
if plays[ids['SND_COIN']]:
    check(note_per(64) in pers[2] and note_per(69) in pers[2], 'bits heard on C (E6, A6)')
check(plays[ids['MUS_OVER']] >= 1, 'the outdoor music was started (%d times)' % plays[ids['MUS_OVER']])
check(plays[ids['MUS_OVER']] == plays[ids['MUS_OVER'] + 1], '... with its bass each time')
check(plays[ids['SND_CLEARA']] <= lv + 1, 'the level fanfare: no more often than levels were finished (%d, %d levels)' % (plays[ids['SND_CLEARA']], lv))
check(plays[ids['SND_DIEA']] == g['st']['deaths'], 'the death jingle once a death (%d, %d deaths)' % (plays[ids['SND_DIEA']], g['st']['deaths']))
print('      MOS: stomps %d, coins %d' % (g['st']['stomps'], g['st']['coins']))
s.wav(os.path.join(OUT, 'smb_sound.wav'), end=t7[0] + 40 * 2000000)
print('wrote', os.path.join(OUT, 'smb_sound.wav'))
print('\n%d failed' % len(fails) if fails else '\nall passed')
