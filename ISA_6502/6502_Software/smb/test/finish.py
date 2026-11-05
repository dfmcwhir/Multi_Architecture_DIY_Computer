# usage (from the smb folder):  PY65=... python3 test/finish.py OUTDIR
"""Each level, in the emulator, along a way to the flagpole found by test/reach.py
in the Python physics (the enemies are taken out).  The game must follow the
same path frame for frame and reach the flag; the screen is checked as in
play.py.  This shows the levels can be finished, and that phys.py matches."""
import sys, os, time
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import phys, bot, reach

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
ok_all = True
for li in [int(a) for a in os.environ.get('ONLY', '').split(',') if a] or range(len(reach.LEVELS)):
    found, nf, acts, n = reach.search(li)
    assert found, reach.LEVELS[li].name
    g = Game(pad=True, speed=0)
    mc = g.mc
    mc.run(3_000_000)
    g.start_at(li % 4, li // 4 + 1)
    mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
    st = dict(f=-1, i=0, diverged=None, flag=False, problems=0)
    def poll(m):
        if not g.at_frame_start(m) or g.v('frame') == st['f']: return
        st['f'] = g.v('frame')
        if g.v('mstate') != 0:
            st['flag'] = st['flag'] or g.v('mstate') in (1, 2, 3, 5)
            m.set_pad(0); return
        if not g.v('full'):
            md, wa, sc, sh = g.model(), g.want(), g.screen(), g.shown()
            if md != wa or sc != sh:
                st['problems'] += 1
                if st['problems'] < 4:
                    bad = [(r, c, '%02X/%02X' % (wa[r][c], md[r][c])) for r in range(22) for c in range(80) if md[r][c] != wa[r][c]]
                    bad2 = [(r, c) for r in range(22) for c in range(80) if sc[r][c] != sh[r][c]]
                    print('  frame', st['i'], 'view/model', bad[:4], 'screen/shown', bad2[:4], 'state', g.v('mstate'), 'scroll', g.w('scroll'),
                          [(i, g.v('o_kind', i), g.ox(i), g.s8('o_y', i), g.v('o_t', i)) for i in range(8) if g.v('o_kind', i)])
        for i in range(1, 7): g.mem[syms['o_kind'] + i] = 0      # no enemies
        i = st['i']
        if i < len(acts):
            m.set_pad(bot.pad_bits(*acts[i])); st['i'] += 1
        else:
            m.set_pad(0)
    while not mc.exited and not st['flag'] and st['i'] <= len(acts) + 5:
        mc.run(100_000, poll)

        if 'GAME  OVER' in g.text(): break
    # on to the castle
    for k in range(40):
        if g.v('lvl') != li % 4 or g.v('world') != li // 4 + 1: break
        mc.run(200_000, poll)
    mc.term.png('%s/finish%d.png' % (OUT, li))
    done = g.v('lvl') != li % 4 or g.v('world') != li // 4 + 1 or g.v('mstate') in (3, 5)
    done = done or (st['flag'] and g.v('lv_flags') & 4 and g.v('br_w') == 1)   # (the last: RESET, then the princess)
    ok_all &= done and st['problems'] == 0
    print('%s: path %d frames; the game %s (state %d, x %d, lives %d), screen problems %d' % (
        reach.LEVELS[li].name, len(acts), 'reached the flag' if st['flag'] else 'did NOT reach the flag',
        g.v('mstate'), g.ox(0), g.v('lives'), st['problems']))
print('all finished' if ok_all else 'FAILED')
