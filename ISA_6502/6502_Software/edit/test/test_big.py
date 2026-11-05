"""test_big.py - large files in EDIT: viewed through a window.

    PY65=path/to/py65 python3 test/test_big.py
"""
import os, sys, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from edsim import *

fails = []
def check(cond, msg):
    print(('ok    ' if cond else 'FAIL  ') + msg)
    if not cond: fails.append(msg)

def folder(files):
    d = tempfile.mkdtemp()
    for name, data in files.items():
        open(os.path.join(d, name), 'wb').write(data)
    return d

# numbered lines, all shorter than a row: each screen row = one line
lines = ['%05d ' % i + 'abcdefghij' * (i % 7) for i in range(1, 3001)]
shown = [l.rstrip() for l in lines] + ['']      # (the empty line after the last line break)
LAST = len(shown) - 22
data = ('\r\n'.join(lines) + '\r\n').encode()          # (CR LF, ~110 KB)
d = folder({'BIG.TXT': data})
e = Ed(d)
e.keys('big.txt\r', 1.0)
check('Too big to edit' in e.status(), 'a %d KB file: offered as view only' % (len(data) // 1024))
e.keys('y', 3.0)
t = e.s.text()
check(t == shown[:23] and 'VIEW' in e.status() and 'Line 1' in e.status() and '/%d KB' % (len(data) // 1024) in e.status(),
      'Y: the start shown, the status: %r' % e.status())

def top():
    r = e.s.row(0)
    return int(r[:5]) if r[:5].isdigit() else None

def screen_ok():
    t = e.s.text()
    n = top()
    return n is not None and all(t[i] == shown[n - 1 + i] for i in range(23) if n - 1 + i < len(shown))

# PgDn through it all: each screen right, a page on each time, the window
# moved as it goes
seen, bad = [], 0
for i in range(200):
    e.keys(PGDN, 1.2)
    n = top()
    if not screen_ok(): bad += 1
    seen.append(n)
    if n is not None and n >= LAST: break
steps = [b - a for a, b in zip(seen, seen[1:])]
check(bad == 0, 'PgDn to the end: every screen the right 23 lines (%d wrong)' % bad)
check(all(s == 22 for s in steps[:-1]) and seen[-1] == LAST, 'a page (22 lines) each time, to the last page: %r' % seen[-3:])
check(shown[-2] == e.s.row(21) and e.s.row(22) == '', 'the last line at the bottom (then the empty one)')
check(('Line %d' % seen[-1]) in e.status(), 'line numbers counted all the way: %r' % e.status())
e.keys(DN, 1.0)
check(top() == seen[-1], 'Down at the end: nothing')
# back up a row at a time across a window edge, then pages
for i in range(40):
    e.keys(UP, 0.4)
check(screen_ok() and top() == seen[-1] - 40, 'Up x40: one line each, screens right')
seen2, bad = [], 0
for i in range(200):
    e.keys(PGUP, 1.2)
    if not screen_ok(): bad += 1
    seen2.append(top())
    if top() == 1: break
check(bad == 0 and seen2[-1] == 1, 'PgUp back to the start: every screen right (%d wrong)' % bad)
check('Line 1 ' in e.status() or 'Line 1' in e.status(), 'line 1 again')
e.keys(END, 4.0)
check(screen_ok() and e.s.row(21) == shown[-2] and 'Line ?' in e.status(), 'End: the last page (the line number not known): %r' % e.status())
for i in range(25):
    e.keys(UP, 0.4)
check(screen_ok() and top() == LAST - 25, 'Up from there: right')
e.keys(HOME, 4.0)
check(screen_ok() and top() == 1 and 'Line 1' in e.status(), 'Home: the start, line 1 again')
e.keys('\x1b', 0.6)
check('view only' in e.status(), 'Esc: says it is view only')
e.keys(ctl('s'), 0.6)
check('view only' in e.status(), '^S: view only, nothing saved')
check(not e.s.problems, 'nothing the display would misread (%s)' % e.s.problems[:3])
check(open(os.path.join(d, 'BIG.TXT'), 'rb').read() == data, 'the file untouched')
e.keys(ctl('o') + 'n', 1.0)
e.keys('\x1b', 1.0)
e.keys(ctl('q'), 1.0)
check(e.m.exited, '^Q quits')
shutil.rmtree(d)

# N: not opened; the text before is kept
d = folder({'BIG.TXT': data, 'S.TXT': b'small\n'})
e = Ed(d)
e.keys('s.txt\r', 1.5)
e.keys(ctl('o') + 'big.txt\r', 1.0)
e.keys('n', 1.0)
check('Too big' in e.status() and e.s.row(0) == 'small', 'N: not opened, the text there before kept')
shutil.rmtree(d)

# a large markdown file: wrapped paragraphs, formatted; in order through the windows
paras = ['## Part %d\n\n' % i + ' '.join('w%d_%d' % (i, j) for j in range(70)) for i in range(1, 121)]
d = folder({'BIG.MD': '\n\n'.join(paras).encode()})
e = Ed(d)
e.keys('big.md\r', 1.0)
e.keys('y', 3.0)
parts, bad = [], 0
for i in range(300):
    t = e.s.text()
    for r, row in enumerate(t):
        if row.startswith('Part '):
            parts.append(int(row[5:]))
            if e.s.attrs(r)[0] != 3: bad += 1
    if 'Part 120' in t: break
    e.keys(PGDN, 1.2)
order = sorted(set(parts))
check(order == list(range(1, 121)) and bad == 0, 'BIG.MD: every heading, in order, formatted (%d..%d, %d bad)' % (order[0], order[-1], bad))
e.keys(END, 4.0)
words = ' '.join(e.s.text())
check(words.rstrip().endswith('w120_69'), 'End: the last word at the end')
shutil.rmtree(d)

print('\n%d failed' % len(fails) if fails else '\nall passed')
sys.exit(1 if fails else 0)
