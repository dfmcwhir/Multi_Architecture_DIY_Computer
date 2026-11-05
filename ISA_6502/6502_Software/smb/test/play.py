# usage (from the smb folder):  sh b.sh   (builds with a label file), then
#   PY65=path/to/py65 python3 test/play.py OUTDIR
#   environment: LEVELS=n how many levels to play (default 3), GARBAGE=n random
#                RAM at power-up, CPU_MHZ=1 for a 1 MHz build, MAXF=n frame limit,
#                START=n start at level n (0-2), LIVES=n keep at least n lives
"""Play SUPER MOS BROS. with the planning bot (gamepad) and check, every frame:
  - the terminal shows exactly what the game's screen copy (shown) holds
  - the game's view buffer holds exactly the map at the scroll position with
    the sprites drawn over it, drawn here in Python from the game's state
and that the levels can be finished."""
import sys, os, time
sys.path.insert(0, os.path.dirname(__file__))
from smbtest import *
import phys, bot

OUT = sys.argv[1] if len(sys.argv) > 1 else 'shots'
os.makedirs(OUT, exist_ok=True)
NLEV = int(os.environ.get('LEVELS', '3'))
MAXF = int(os.environ.get('MAXF', '9000'))
g = Game(pad=True)
mc = g.mc
problems = []
st = dict(f=-1, n=0, checked=0, cur=(0, 0, 0), queue=[], deaths=0, lives=None, levels=[], lvl=None,
          stomps=0, coins=0, big=0, t0=time.time(), maxbytes=0, bytes=0, scrollf=0)

def check():
    md, view, sc, sh = g.model(), g.want(), g.screen(), g.shown()
    if view != md:
        bad = [(r, c) for r in range(22) for c in range(80) if view[r][c] != md[r][c]]
        problems.append('frame %d: view differs from the model at %d cells, e.g. %s' % (st['n'], len(bad), bad[:3]))
        if os.environ.get('DEBUG') and len(problems) < 3:
            r, c = bad[0]
            print('frame', st['n'], 'cell', r, c, 'view %02X model %02X' % (view[r][c], md[r][c]), 'scroll', g.w('scroll'))
            for i in range(8):
                if g.v('o_kind', i): print('  obj', i, 'kind', g.v('o_kind', i), 'x', g.ox(i), 'y', g.s8('o_y', i), 'vx', g.vx(i), 't', g.v('o_t', i))
            print('  rects', [(g.v('rc_cl', i) | g.v('rc_ch', i) << 8, g.s8('rc_r', i), g.v('rc_w', i), g.v('rc_h', i)) for i in range(g.v('nrect'))])
    if sc != sh:
        bad = [(r, c) for r in range(22) for c in range(80) if sc[r][c] != sh[r][c]]
        problems.append('frame %d: terminal differs from shown at %d cells, e.g. %s' % (st['n'], len(bad), bad[:3]))
        if os.environ.get('DEBUG2') and len(problems) < 4:
            r, c = bad[0]; vw = g.want()
            print('frame', st['n'], 'cell', r, c, 'term %02X shown %02X want %02X' % (sc[r][c], sh[r][c], vw[r][c]), 'scroll', g.w('scroll'),
                  'heal', [(g.v('hl_c', i), g.v('hl_r', i), g.v('hl_t', i)) for i in range(6)])
        if os.environ.get('ALLP') and len(problems) < 400 and (not problems[:-1] or 'frame %d:' % (st['n'] - 1) not in problems[-2]):
            print('frame', st['n'], 'bad', bad[:6], 'scroll', g.w('scroll'), 'sprites', g.sprites())
    if not SOFT:                        # (SMB.BIN: everything it wants shown was sent)
        shb = g.shown_bg()
        if view != shb:
            bad = [(r, c) for r in range(22) for c in range(80) if view[r][c] != shb[r][c]]
            problems.append('frame %d: not sent at %d cells, e.g. %s' % (st['n'], len(bad), bad[:3]))
    st['checked'] += 1

def poll(m):
    if not g.at_frame_start(m) or g.v('frame') == st['f']: return
    st['f'] = g.v('frame'); st['n'] += 1
    if g.v('full'):                       # (a level just started: nothing drawn yet)
        st['queue'] = []; st['cur'] = (0, 0, 0); m.set_pad(0); return
    check()
    if os.environ.get('WATCH'):
        wcol, wrow = map(int, os.environ['WATCH'].split(','))
        sc0 = g.w('scroll'); c = wcol - sc0
        if 0 <= c < 80:
            b = syms['wc'] + wrow * 256 + (wcol & 255); b2 = syms['sh'] + wrow * 256 + (wcol & 255)
            v = (g.mem[b], g.mem[b2], g.screen_bg()[wrow][c])
            if v != st.get('wv'): print('W frame', st['n'], 'col', c, 'wc %02X sh %02X term %02X' % v, 'tile', g.tile(wcol // 4, wrow // 2), 'map', g.mem[syms['map'] + (wrow//2) * 256 + wcol // 4]); st['wv'] = v
    nb = mc.term.nbytes - st.get('nb0', 0); st['nb0'] = mc.term.nbytes
    st['maxbytes'] = max(st['maxbytes'], nb); st['bytes'] += nb
    sy = mc.term.syncs - st.get('sy0', 0); st['sy0'] = mc.term.syncs
    st.setdefault('syh', {}); st['syh'][sy] = st['syh'].get(sy, 0) + 1
    sc = g.w('scroll'); d = sc - st.get('sc0', sc); st['sc0'] = sc
    st.setdefault('sdh', {}); st['sdh'][d] = st['sdh'].get(d, 0) + 1
    if st['n'] % 150 == 0: mc.term.png('%s/f%05d.png' % (OUT, st['n']))
    lv = (g.v('world'), g.v('lvl'))
    if lv != st['lvl']:
        st['lvl'] = lv; st['levels'].append(lv)
    if st['lives'] is not None and g.v('lives') < st['lives']: st['deaths'] += 1
    if os.environ.get('LIVES') and g.v('lives') < int(os.environ['LIVES']):     # (more lives, to see it all)
        g.mem[syms['lives']] = int(os.environ['LIVES'])
    st['lives'] = g.v('lives')
    st['big'] = max(st['big'], g.v('big'))
    if g.v('mstate') != 0:
        st['queue'] = []; st['cur'] = (0, 0, 0); m.set_pad(0); return
    if os.environ.get('TRACE') and g.ox(0) >= int(os.environ['TRACE']) and st.get('tr', 0) < 60:
        st['tr'] = st.get('tr', 0) + 1
        s, wd = phys.from_game(g)
        pred = s.copy(); phys.step(pred, wd, *st['cur'])
        print('n', st['n'], 'cur', st['cur'], 'x', g.ox(0), g.v('o_xf'), 'y', g.s8('o_y'), g.v('o_yf'), 'vx %.3f vy %.3f' % (g.vx(0), g.vy(0)), 'ong', g.v('onground'), 'jb', g.v('jump_buf'), 'hold', g.v('hold'), 'pad', g.v('pad'),
              '| model next x', pred.x, 'y', pred.ys, 'vy %.3f' % (phys.s16(pred.vy) / 256))
    if not st['queue']:
        s, wd = phys.from_game(g)
        d, r, ap = bot.plan(s, wd, st['cur'])
        st['queue'] = [(d, r, a) for a in ap]
    cur = st['queue'].pop(0)
    st['cur'] = cur
    m.set_pad(bot.pad_bits(*cur))

mc.run(3_000_000)
mc.term.png(OUT + '/title.png')
if os.environ.get('START') or os.environ.get('WORLD'): g.start_at(int(os.environ.get('START', '0')), int(os.environ.get('WORLD', '1')))
mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
while st['n'] < MAXF and not mc.exited:
    mc.run(200_000, poll)
    txt = g.text()
    if 'GAME  OVER' in txt:
        mc.term.png(OUT + '/over.png'); break
    if 'ANOTHER ROM' in txt:
        mc.term.png(OUT + '/castle.png')
    if len(st['levels']) > NLEV: break
mc.term.png(OUT + '/last.png')
print('x', g.ox(0), 'scroll', g.w('scroll'))
print('frames %d checked %d levels %s deaths %d lives %d score %d bits %d big %d  (%.0f s)' % (
    st['n'], st['checked'], st['levels'], st['deaths'], g.v('lives'), g.score(), g.v('bytes') * 8 + g.v('bits'), st['big'], time.time() - st['t0']))
print('bytes a frame: average %.0f, most %d' % (st['bytes'] / max(1, st['checked']), st['maxbytes']))
print('terminal errors', mc.term.errors[:5])
print('vertical blank waits a frame (terminal sprites):', dict(sorted(st.get('syh', {}).items())))
print('characters scrolled a frame:', dict(sorted(st.get('sdh', {}).items())))
print('problems', len(problems), problems if os.environ.get('ALLP') else problems[:8])
