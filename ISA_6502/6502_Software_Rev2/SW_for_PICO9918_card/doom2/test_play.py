"""DOOM2 in the emulator: a bot plays each map for a while (health kept up),
then the level is ended and the next one loaded.  Screenshots shots/mNN_k.png.
   python3 test_play.py [frames per map]"""
import sys, os, random
sys.path.insert(0, '/home/claude/tools')
import emu6502
random.seed(int(os.environ.get('SEED', '1')))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 900
m = emu6502.Machine(int(os.environ.get('MHZ', '4'))); m.load('DOOM2.BIN', 0x800); L = m.load_labels('doom2.lbl')
def v(n, i=0): return m.mem[L[n] + i]
cur = [0]; loops = [0]
def bot(mm):
    mm.mem[L['health']] = 100
    if mm.frames % 20 == 0:
        cur[0] = random.choice([0x10, 0x10, 0x10, 0x40, 0x80, 0x10 | 0x01, 0x02, 0x20, 0x04 | 0x40, 0x01])
    mm.pad = cur[0]
def at(mm): loops[0] += 1
m.run(frames=60); m.pad = 0x08; m.run(frames=2); m.pad = 0; m.run(frames=60)
for lvl in range(5):
    name = bytes(m.mem[L['lp_name']:L['lp_name'] + 9]).decode(errors='replace')
    f0 = m.frames; loops[0] = 0
    k = 0
    while m.frames - f0 < N:
        r = m.run(frames=150, hook=bot, at=(L['game_loop'], at))
        if r != 'frames': print('stopped', r); sys.exit(1)
        m.vdp.save_png('shots/m%d_%d.png' % (lvl + 1, k)); k += 1
    print('%s frames %d game loops %d kills %d/%d items %d/%d ammo %d' % (name, m.frames - f0, loops[0],
          v('kills'), v('kills_max'), v('items'), v('items_max'), v('ammo')))
    m.pad = 0
    m.mem[L['done']] = 1               # the level over
    m.run(frames=120)
    m.vdp.save_png('shots/done%d.png' % (lvl + 1))
    for _ in range(3): m.pad = 0x08; m.run(frames=3); m.pad = 0; m.run(frames=30)
    m.run(frames=60)
