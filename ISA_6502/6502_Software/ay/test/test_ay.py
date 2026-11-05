"""test_ay.py - tests of AYTEST, YMPLAY, PIANO and SEQ in the emulator (sim.py).

    PY65=path/to/py65 python3 test/test_ay.py [YMFOLDER]

YMPLAY is run on made-up .AYS songs whose register values say which song and
frame they are, so every register write can be checked: the right values, in
order, none missing, register 13 only when it isn't $FF, and 1/50 s apart.
With YMFOLDER, real .YM songs are converted with ym2ays.py and played too.
"""
import os, sys, struct, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from sim import Machine, CPU_HZ
import ym2ays

AY = os.path.join(HERE, '..')
LABEL_ROW = 13
fails = []


def check(cond, msg):
    print(('ok    ' if cond else 'FAIL  ') + msg)
    if not cond: fails.append(msg)


def ays(frames, rate=50, loop=0, title='', author=''):
    head = b'AYS1' + bytes([rate, 0]) + struct.pack('<II', len(frames), loop) + bytes(2)
    head += title.encode().ljust(32, b'\0') + author.encode().ljust(32, b'\0')
    head += bytes(128 - len(head))
    return head + b''.join(bytes(f) for f in frames)


def song(sid, n):
    """frame f: R0/R1 = f, R2 = sid, R13 = f & 15 every 7th frame, else $FF"""
    fr = []
    for f in range(n):
        r = [f & 255, (f >> 8) & 15, sid, (f >> 12) & 15, (f * 3) & 255, 0, f & 31, 0x38, 15, 14, 16, f & 255, 1, 0xFF]
        if f % 7 == 0: r[13] = f & 15
        fr.append(r)
    return fr


def frames_written(log):
    """the AY writes grouped into frames: a frame starts at each R0 write"""
    out = []
    for t, r, v in log:
        if r == 0 or (out and r in out[-1][1]):
            out.append([t, {}])
        if out:
            out[-1][1][r] = v
    return out


# ---- AYTEST ------------------------------------------------------------------------------
def test_aytest():
    print('--- AYTEST')
    for k in '12345678':
        m = Machine(os.path.join(AY, 'AYTEST.BIN'))
        m.type_at(0.05, k)
        m.run(60, until=lambda m: m.text().count('CHOOSE: ') >= 2)
        secs = m.now() / CPU_HZ
        regs = sorted(set(r for _, r, _ in m.ay_log))
        bad7 = [v for _, r, v in m.ay_log if r == 7 and v & 0xC0]
        check(m.text().count('CHOOSE: ') >= 2 and not m.errors and not bad7, 'test %s: %d writes in %.1f s, registers %s, no card reads, ports kept inputs' % (k, len(m.ay_log), secs, regs))
    # a key stops a test; Q quits
    m = Machine(os.path.join(AY, 'AYTEST.BIN'))
    m.type_at(0.05, '9')
    m.type_at(3.0, 'X')
    m.type_at(4.0, 'Q')
    m.run(10)
    t = m.text()
    check(m.exited and 'STOPPED' in t, 'test 9 stopped by a key, Q goes back to the menu')
    last = {}
    for _, r, v in m.ay_log: last[r] = v
    check(last.get(8) == 0 and last.get(9) == 0 and last.get(10) == 0 and last.get(7) == 0x3F, 'silent at the end')


# ---- YMPLAY ------------------------------------------------------------------------------
def play_check(m, sid, n, once=False):
    """the frames written for song sid: in order from start_frame, each right"""
    fr = [f for f in frames_written(m.ay_log) if f[1].get(2) == sid and len(f[1]) >= 13]
    ok = True
    expect = song(sid, n)
    idx = []
    for k, (t, regs) in enumerate(fr):
        f = regs[0] | regs[1] << 8 | regs[3] << 12
        if idx and f < idx[-1] and once:
            break
        idx.append(f)
        e = expect[f]
        for r in range(13):
            if regs.get(r) != e[r]:
                ok = False
        if (13 in regs) != (e[13] != 0xFF) or (13 in regs and regs[13] != e[13]):
            ok = False
    return fr[:len(idx)], idx, ok


def test_ymplay(extra=None):
    print('--- YMPLAY')
    d = tempfile.mkdtemp()
    open(os.path.join(d, 'ALPHA.AYS'), 'wb').write(ays(song(1, 400), title='ALPHA SONG', author='TESTER'))
    open(os.path.join(d, 'BETA.AYS'), 'wb').write(ays(song(2, 120), loop=100, title='BETA'))
    open(os.path.join(d, 'GAMMA.AYS'), 'wb').write(ays(song(3, 3000), rate=60, title='GAMMA AT 60'))
    open(os.path.join(d, 'README.TXT'), 'w').write('not a song')
    open(os.path.join(d, 'JUNK.AYS'), 'wb').write(b'hello there' * 20)
    big = os.path.join(AY, 'YMPLAY.BIN')

    # the list
    m = Machine(big, d)
    m.run(3, until=lambda m: 'QUITS' in m.text())
    t = m.text()
    check('ALPHA.AYS' in t and 'BETA.AYS' in t and 'GAMMA.AYS' in t and 'README' not in t, 'list shows the .AYS files only')

    # play song 1 whole, then it goes on to song 2 (BETA, 120 frames, loop at 100)
    m = Machine(big, d)
    m.type_at(0.5, ' ')
    m.run(12)
    t = m.text()
    fr, idx, ok = play_check(m, 1, 400)
    check(ok and idx == list(range(400)), 'ALPHA: all 400 frames, in order, right values (%d written)' % len(idx))
    times = [f[0] for f in fr]
    gaps = [b - a for a, b in zip(times, times[1:])]
    check(gaps and min(gaps) > 39800 and max(gaps) < 40200, 'ALPHA: frames %d..%d cycles apart (40000 = 1/50 s)' % (min(gaps), max(gaps)))
    total = (times[-1] - times[0]) / CPU_HZ
    check(abs(total - 399 / 50) < 0.01, 'ALPHA: 400 frames took %.3f s (7.98 expected)' % total)
    check('ALPHA SONG' in t and 'TESTER' in t and '00:08' in t, 'title, author and length shown')
    fr2, idx2, ok2 = play_check(m, 2, 120)
    check(ok2 and idx2[:120] == list(range(120)), 'then BETA plays (%d frames)' % len(idx2))
    check(m.via.ier == 0 and not m.errors, 'timer 2 interrupt left off; no card reads')
    print('      max ring fill / reads:', m.ch.reads)

    # loop: BETA with L: 0..119 then 100..119 again and again
    m = Machine(big, d)
    m.type_at(0.3, 'S ')
    m.type_at(0.8, 'L')
    m.run(8)
    fr, idx, ok = play_check(m, 2, 120)
    exp = list(range(120)) + list(range(100, 120)) * 20
    check(ok and len(idx) > 200 and idx == exp[:len(idx)], 'BETA looped from frame 100 (%d frames played)' % len(idx))
    check('LOOP' in m.text(), 'LOOP shown')

    # 60 Hz song, pause, next, previous, back to the list, quit
    m = Machine(big, d)
    m.type_at(0.3, '3 ')
    m.type_at(2.0, ' ')
    m.type_at(3.0, ' ')
    m.run(4.5)
    fr, idx, ok = play_check(m, 3, 3000)
    times = [f[0] for f in fr]
    gaps = [b - a for a, b in zip(times, times[1:])]
    big_gaps = [g for g in gaps if g > 40000]
    check(ok and idx == list(range(len(idx))), 'GAMMA (60 Hz): %d frames in order' % len(idx))
    norm = [g for g in gaps if g < 40000]
    check(norm and min(norm) > 33100 and max(norm) < 33500, 'GAMMA: frames %d..%d cycles apart (33333 = 1/60 s)' % (min(norm), max(norm)))
    check(len(big_gaps) == 1 and 0.9 < big_gaps[0] / CPU_HZ < 1.1, 'pause held it for %.2f s' % (big_gaps[0] / CPU_HZ if big_gaps else 0))
    vols = [(t_, v) for t_, r, v in m.ay_log if r in (8, 9, 10) and 2.05 * CPU_HZ < t_ < 2.95 * CPU_HZ]
    check(all(v == 0 for _, v in vols), 'silent while paused')
    m.type_at(m.now() / CPU_HZ, 'N')
    m.run(1)
    check('PLAYING JUNK.AYS' in m.text() and 'NOT AN .AYS FILE' in m.text(), 'N: next song (JUNK.AYS: rejected)')
    m.run(1)
    m.type_at(m.now() / CPU_HZ, 'A')
    m.run(1)
    m.type_at(m.now() / CPU_HZ, 'S')
    m.run(0.5)
    tail = m.text()[-400:]
    check('SONGS IN /:' in tail, 'S: back to the list')
    m.type_at(m.now() / CPU_HZ, 'Q')
    m.run(1)
    last = {}
    for _, r, v in m.ay_log: last[r] = v
    check(m.exited and last.get(7) == 0x3F and last.get(8) == 0, 'Q quits, silent')
    check(m.ch.file is None, 'the file was closed')

    # the level bars: drawn in block graphics while playing, the envelope
    # followed; V turns them off (no more graphics sent)
    fr = []
    for f in range(400):
        fr.append([100, 1, 200, 0, 50, 0, 5, 0x38, [0, 8, 15, 4][f // 25 % 4], 16, 0, 0, 0x30, 0 if f % 25 == 0 else 0xFF])
    d3 = tempfile.mkdtemp()
    open(os.path.join(d3, 'BARS.AYS'), 'wb').write(ays(fr))
    m = Machine(big, d3)
    m.type_at(0.3, ' ')
    m.run(3)
    t = m.out
    g = t.count(bytes([0x18, 0xD0]))
    check(g > 20 and t.count(bytes([0x18, 0])) >= g, 'bars: %d updates in block graphics, each back to text after' % g)
    check(bytes([0x0E, 14, 0x0F, LABEL_ROW]) + b'T.E' in t or b'T.E' in t, 'bars: the flags under B show tone and envelope')
    n0 = len(m.out)
    m.type_at(m.now() / CPU_HZ, 'V')
    m.run(1.5)
    after = m.out[n0:]
    check(bytes([0x18, 0xD0]) not in after[after.find(12) + 1:], 'V: the bars off (nothing drawn after the screen is cleared)')
    regs = [f for f in frames_written(m.ay_log) if len(f[1]) >= 13 and f[1].get(2) == 200]
    times = [f[0] for f in regs]
    gaps = [b - a for a, b in zip(times, times[1:])]
    check(gaps and min(gaps) > 39800 and max(gaps) < 40200, 'bars: frames still %d..%d cycles apart' % (min(gaps), max(gaps)))
    shutil.rmtree(d3)

    # no drive
    m = Machine(big, None)
    m.run(30)
    check(m.exited is False and 'NO DRIVE' in m.text(), 'no drive: says so')

    # slow drive: every 512 bytes takes 15 ms
    m = Machine(big, d, sector_latency=30000)
    m.type_at(0.3, '3 ')
    m.run(5)
    fr, idx, ok = play_check(m, 3, 3000)
    times = [f[0] for f in fr]
    gaps = [b - a for a, b in zip(times, times[1:])]
    check(ok and idx == list(range(len(idx))) and max(gaps) < 33500, 'slow drive (15 ms a sector): still on time (%d frames, max gap %d)' % (len(idx), max(gaps)))

    # a long song: more than one BYTE_READ ($F000 bytes each), 32 bit counts;
    # at 200 frames a second to get there sooner
    d2 = tempfile.mkdtemp()
    open(os.path.join(d2, 'LONG.AYS'), 'wb').write(ays(song(4, 4500), rate=200))
    m = Machine(big, d2)
    reqs = []
    orig = m.ch.write_data
    def wd(v):
        orig(v)
        if m.ch.cmd == 0x3A and len(m.ch.args) == 2: reqs.append(m.ch.args[0] | m.ch.args[1] << 8)
    m.ch.write_data = wd
    m.type_at(0.3, ' ')
    m.run(23.5)
    fr, idx, ok = play_check(m, 4, 4500, once=True)
    times = [f[0] for f in fr]
    gaps = [b - a for a, b in zip(times, times[1:])]
    check(ok and idx == list(range(4500)), 'LONG: all 4500 frames in order (%d)' % len(idx))
    check(reqs[:3] == [128, 0xF000, 4500 * 14 - 0xF000], 'LONG: read in 2 parts %s' % reqs)
    check(min(gaps) > 9980 and max(gaps) < 10020, 'LONG (200 Hz): frames %d..%d cycles apart' % (min(gaps), max(gaps)))
    # a slow song: 20 frames a second is more than timer 2 holds (100000 cycles)
    open(os.path.join(d2, 'LONG.AYS'), 'wb').write(ays(song(5, 50), rate=20))
    m = Machine(big, d2)
    m.type_at(0.3, ' ')
    m.run(3.2)
    fr, idx, ok = play_check(m, 5, 50, once=True)
    times = [f[0] for f in fr]
    gaps = [b - a for a, b in zip(times, times[1:])]
    check(ok and idx == list(range(len(idx))) and min(gaps) > 99950 and max(gaps) < 100050, 'SLOW (20 Hz): frames %d..%d cycles apart' % (min(gaps), max(gaps)))
    shutil.rmtree(d2)

    if extra:
        test_real(extra)
    shutil.rmtree(d)


def test_folders():
    """YMPLAY lists the monitor's current folder, which it gets from the ROM
    (SBC_CWD).  The emulated CH376 loses its current folder when a file is
    opened (as the real one does: the monitor has just loaded YMPLAY), so
    YMPLAY enters the folder a level at a time before the list and each song"""
    print('--- YMPLAY: folders')
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, 'MUSIC', 'DEEP'))
    put = lambda path, data: open(os.path.join(d, *path.split('/')), 'wb').write(data)
    put('ROOT1.AYS', ays(song(6, 50)))
    put('ALPHA.AYS', ays(song(7, 50)))              # (the same name in two folders)
    put('MUSIC/ALPHA.AYS', ays(song(8, 50)))
    put('MUSIC/SONGB.AYS', ays(song(9, 50)))
    put('MUSIC/NOTES.TXT', b'not a song')
    put('MUSIC/DEEP/INNER.AYS', ays(song(10, 50)))
    big = os.path.join(AY, 'YMPLAY.BIN')

    def run(rom_cwd, cwd='lost', secs=2):
        m = Machine(big, d, rom_cwd=rom_cwd, cwd=cwd)
        m.run(3, until=lambda m: 'QUITS' in m.text() or 'NO .AYS' in m.text())
        listed = m.text()
        m.type_at(m.now() / CPU_HZ, ' ')
        m.run(secs)
        return m, listed

    m, t = run('/MUSIC', secs=3)
    check('SONGS IN /MUSIC:' in t and 'ALPHA.AYS' in t and 'SONGB.AYS' in t and 'ROOT1' not in t
          and 'DEEP' not in t and 'NOTES' not in t,
          'in /MUSIC (the chip having lost its folder): MUSIC\'s songs are listed')
    check(0x15 not in m.ch.log and 0x31 not in m.ch.log, '... the drive used as it was (not started again)')
    fr, idx, ok = play_check(m, 8, 50)
    check(ok and len(idx) > 20, '... MUSIC\'s ALPHA.AYS plays, not the top folder\'s')
    check(m.ch.opened[:2] == ['MUSIC/ALPHA.AYS', 'MUSIC/SONGB.AYS'], '... and the next song after it (%s)' % m.ch.opened[:2])

    m, t = run('/MUSIC/DEEP')
    fr, idx, ok = play_check(m, 10, 50)
    check('INNER.AYS' in t and 'ALPHA' not in t and ok and len(idx) > 20, 'in /MUSIC/DEEP: INNER.AYS listed and played')

    m, t = run('')
    fr, idx, ok = play_check(m, 7, 50)
    check('SONGS IN /:' in t and 'ROOT1.AYS' in t and 'SONGB' not in t and ok and m.ch.opened[:1] == ['ALPHA.AYS'],
          'in the top folder: its songs')

    m, t = run(None)
    check('ROOT1.AYS' in t and 'SONGB' not in t, 'a ROM without SBC_CWD: the top folder')

    m, t = run('/MUSIC', cwd=None)
    check(0x15 in m.ch.log and 'SONGB.AYS' in t and 'ROOT1' not in t, 'drive not ready: started afresh, then into /MUSIC')

    m, t = run('/NOPE')
    check('NO .AYS FILES IN /NOPE' in m.text(), 'a folder that isn\'t there: says so')
    shutil.rmtree(d)


def test_real(src):
    print('--- real songs from', src)
    d = tempfile.mkdtemp()
    names = []
    for f in sorted(os.listdir(src)):
        if not f.lower().endswith('.ym'): continue
        try:
            out, info, n = ym2ays.convert(open(os.path.join(src, f), 'rb').read())
        except Exception as e:
            print('      skip', f, e); continue
        nm = ym2ays.ays_name(f)
        open(os.path.join(d, nm), 'wb').write(out)
        names.append((nm, out))
    m = Machine(os.path.join(AY, 'YMPLAY.BIN'), d)
    m.type_at(0.5, ' ')
    m.run(6)
    nm, data = names[0]
    n = struct.unpack_from('<I', data, 6)[0]
    frames = [data[128 + i * 14:128 + i * 14 + 14] for i in range(n)]
    got = [g for g in frames_written(m.ay_log) if len(g[1]) >= 13]
    def same(regs, e):
        return all(regs.get(r) == e[r] for r in range(13)) and ((13 in regs) == (e[13] != 0xFF))
    while got and not same(got[0][1], frames[0]):     # (the silencing before it)
        got.pop(0)
    good = 0
    for i, (t, regs) in enumerate(got):
        e = frames[i]
        if same(regs, e):
            good += 1
    check(good == len(got) and len(got) > 250, '%s: %d frames written, all match the file' % (nm, len(got)))
    shutil.rmtree(d)


# ---- PIANO -------------------------------------------------------------------------------
def test_piano():
    print('--- PIANO')
    big = os.path.join(AY, 'PIANO.BIN')
    def vol_at(m, ch, secs):
        """channel ch's volume register as it was at secs"""
        v = 0
        for t_, r, x in m.ay_log:
            if t_ > secs * CPU_HZ: break
            if r == 8 + ch: v = x
        return v
    def per(m, c):
        return m.ay[2 * c] | m.ay[2 * c + 1] << 8
    def ch_of(m, period):
        for c in range(3):
            if per(m, c) == period: return c
    # a chord: three channels, the right periods, and they fade by themselves
    m = Machine(big)
    m.type_at(0.3, 'ZCB')
    m.run(0.4)
    ps = sorted(per(m, c) for c in range(3))
    check(ps == [638, 758, 956] and min(m.ay[8:11]) > 10, 'Z C B: C3 E3 G3 on three channels, loud (%s)' % ps)
    m.run(3)
    check(m.ay[8:11] == [0, 0, 0] and not m.errors, 'PIANO notes fade out by themselves')
    # a fourth note takes the channel that has sounded longest
    m = Machine(big)
    m.type_at(0.3, 'Z'); m.type_at(0.4, 'C'); m.type_at(0.5, 'B'); m.type_at(0.6, 'N')
    m.run(0.65)
    ps = sorted(per(m, c) for c in range(3))
    check(ps == [568, 638, 758], "a 4th note (A3) takes the oldest channel (C3's): %s" % ps)
    # ORGAN: alone it stops after its sustain; held (the key repeating) it goes on
    for held in (False, True):
        m = Machine(big)
        m.type_at(0.2, ']]')                     # ORGAN
        m.type_at(0.5, 'Z')
        if held:
            for k in range(60):                  # repeats from 0.5 s after, 30 a second
                m.type_at(1.0 + k / 30, 'Z')
        m.run(3.5)
        c = [c for c in range(3) if any(r == 2 * c and x == 0xBC for t_, r, x in m.ay_log)][0]
        v25 = vol_at(m, c, 2.5)
        if held:
            check(v25 >= 12, 'ORGAN held by key repeats: still sounding at 2.5 s (volume %d)' % v25)
        else:
            check(v25 == 0, 'ORGAN not held: over by 2.5 s')
    # PIANO with the key repeating fast: not struck again and again
    m = Machine(big)
    m.type_at(0.3, 'Z')
    for k in range(40): m.type_at(0.8 + k / 30, 'Z')
    m.run(2.5)
    c = [c for c in range(3) if any(r == 2 * c and x == 0xBC for t_, r, x in m.ay_log)][0]
    jumps = 0; last = 0
    for t_, r, x in m.ay_log:
        if r == 8 + c:
            if x > last + 2: jumps += 1
            last = x
    check(jumps <= 2, 'PIANO, key repeating: struck %d times (the press and the first repeat at most)' % jumps)
    # DRUMS: the kick falls in pitch; the hi-hat is noise only, noise period 1
    m = Machine(big)
    m.type_at(0.2, '[')                          # (back round to DRUMS)
    m.type_at(0.4, 'Z')
    to = lambda t: m.run(t - m.now() / CPU_HZ)
    to(0.43)
    c = [c for c in range(3) if m.ay[8 + c]][0]
    p1 = per(m, c)
    to(0.53)
    p2 = per(m, c)
    check(p2 > p1 * 2, 'DRUMS, Z: the kick falls in pitch (period %d to %d)' % (p1, p2))
    m.type_at(0.6, 'C')
    to(0.63)
    hat = [c for c in range(3) if m.ay[8 + c] and not (m.ay[7] >> (c + 3)) & 1]
    check(hat and (m.ay[7] >> hat[0]) & 1 and m.ay[6] == 1, 'DRUMS, C: the hi-hat is noise only, noise period 1')
    # BUZZ: the envelope as a saw at the note (period / 16), shape 8
    m = Machine(big)
    m.type_at(0.2, '[['); m.type_at(0.5, 'Z')
    m.run(0.6)
    check(m.ay[8] == 16 and m.ay[11] | m.ay[12] << 8 == (956 + 8) // 16 and m.ay[13] == 8 and m.ay[7] & 1,
          'BUZZ: channel A on the envelope, period %d (956 / 16), its tone off' % (m.ay[11] | m.ay[12] << 8))
    # CHORD: the notes of a major chord, a frame each
    m = Machine(big)
    m.type_at(0.2, ']]]]]'); m.type_at(0.5, 'Z')
    m.run(0.52)
    n0 = len(m.ay_log)
    m.run(0.7)
    lows = set(x for t_, r, x in m.ay_log[n0:] if r in (0, 2, 4))
    check({0xBC, 0xF6, 0x7E} <= lows, 'CHORD: C3, E3 and G3 in turn')
    # octave up, then quit with Esc: silent, back to the menu
    m = Machine(big)
    m.type_at(0.2, '='); m.type_at(0.3, 'Z'); m.type_at(0.8, chr(27))
    m.run(0.4)
    check(ch_of(m, 478) is not None, '=: an octave up (Z = C4)')
    m.run(1.5)
    check(m.exited and m.ay[8:11] == [0, 0, 0] and not m.errors, 'Esc: quiet, back to the menu')


# ---- SEQ ---------------------------------------------------------------------------------
def test_seq():
    print('--- SEQ')
    big = os.path.join(AY, 'SEQ.BIN')
    R, D = '\x1b[C', '\x1b[B'
    class Keys:
        def __init__(self, m, t=0.3): self.m, self.t = m, t
        def __call__(self, *seq, gap=0.05):
            for s_ in seq:
                for ch in ([s_] if s_.startswith('\x1b') else s_):
                    self.m.type_at(self.t, ch); self.t += gap
        def run(self, extra=0.0):
            self.m.run(self.t + extra - self.m.now() / CPU_HZ)
            self.t = self.m.now() / CPU_HZ
    def hits(m, after):
        """channel C's drum hits after a time: (seconds, noise on: from the
        mixer written just after the volume)"""
        out = []; prev = 0; want = None
        for tt, r, v in m.ay_log:
            if r == 7 and want is not None:
                out.append((want, not (v >> 5) & 1)); want = None
            if r == 10:
                if v == 15 and prev != 15 and tt / CPU_HZ > after:    # (drums start at 15)
                    want = tt / CPU_HZ
                prev = v
        return out
    d = tempfile.mkdtemp()
    os.mkdir(os.path.join(d, 'MUSIC'))
    # a beat: kick on 1, 5, 9, 13, hi-hat on every other step (with the kick
    # on the same step: the kick wins); played at 120: 8ths 0.25 s apart
    m = Machine(big, d, rom_cwd='/MUSIC', cwd='lost')
    k = Keys(m)
    for st in range(16):
        if st % 4 == 0: k('Z')
        k(R)
    k(D, D)
    for st in range(16):
        if st % 2 == 0: k(' ')
        k(R)
    k('\r')
    t0 = k.t - 0.06                     # (just before Enter)
    k.run(4.2)
    h = hits(m, t0)
    gaps = [b[0] - a[0] for a, b in zip(h, h[1:])]
    check(len(h) >= 14 and all(abs(g - 0.25) < 0.012 for g in gaps), 'a beat at 120: %d hits 0.25 s apart (%.3f..%.3f)' % (len(h), min(gaps), max(gaps)))
    kick = [n for t_, n in h[0::2]]; hat = [n for t_, n in h[1::2]]
    check(not any(kick) and all(hat), 'the kick (no noise) wins over the hi-hat on its steps; the hats between are noise')
    # tempo up 4 x 5 = 140: steps 60 / 560 s apart
    k('====')
    t0 = k.t + 0.3
    k.run(2.5)
    h = hits(m, t0)
    gaps = [b[0] - a[0] for a, b in zip(h, h[1:])]
    check(gaps and all(abs(g - 120 / 560) < 0.012 for g in gaps), 'tempo 140: hits %.3f s apart (0.214 expected)' % (sum(gaps) / len(gaps)))
    # saved in the monitor's folder (MUSIC), cleared, loaded back
    k('\r', 'F', 'S', '1')
    k.run(1)
    saved = os.path.join(d, 'MUSIC', 'BEAT1.SEQ')
    check(os.path.exists(saved) and len(open(saved, 'rb').read()) == 200 and open(saved, 'rb').read()[:5] == b'SEQ1\x8c',
          'F S 1: BEAT1.SEQ saved in /MUSIC (200 bytes, tempo 140)')
    k('F', 'N', 'Y')
    k.run(0.5)
    k('F', 'L', '1')
    k.run(1)
    k('\r')
    t0 = k.t - 0.06                     # (just before Enter)
    k.run(2.2)
    h = hits(m, t0)
    check(len(h) >= 8 and 'LOADED BEAT1.SEQ IN /MUSIC' in m.text(), 'F N Y then F L 1: loaded back, it plays again (%d hits)' % len(h))
    k('\r'); k.run(0.3)
    # patterns: A has a kick on step 1, B a snare on step 1: they take turns;
    # ";" keeps it on the one on screen
    m = Machine(big, d, cwd='')
    k = Keys(m)
    k('Z', 'L', D, 'Z', 'K', '\r')        # (the cursor stays on step 1)
    t0 = k.t - 0.06
    k.run(8.3)
    h = hits(m, t0)
    check(len(h) >= 4 and [n for _, n in h[:4]] == [False, True, False, True] and abs(h[1][0] - h[0][0] - 2.0) < 0.02,
          'A then B then A: kick, snare, kick, snare, 2 s apart (%d hits)' % len(h))
    k(';')
    t0 = k.t
    k.run(4.2)
    h = hits(m, t0)
    check(len(h) == 2 and not any(n for _, n in h), '";": only this pattern (A) now: kicks only')
    # Esc asks, Y quits, silent
    k('\r', '\x1b'); k.run(0.3)
    check('QUIT (Y)?' in m.text() and not m.exited, 'Esc asks first')
    k('Y'); k.run(0.5)
    check(m.exited and m.ay[8:11] == [0, 0, 0] and not m.errors, 'Y: quiet, back to the menu')
    shutil.rmtree(d)


if __name__ == '__main__':
    test_aytest()
    test_ymplay(sys.argv[1] if len(sys.argv) > 1 else None)
    test_folders()
    test_piano()
    test_seq()
    print('\n%d failed' % len(fails) if fails else '\nall passed')
    sys.exit(1 if fails else 0)
