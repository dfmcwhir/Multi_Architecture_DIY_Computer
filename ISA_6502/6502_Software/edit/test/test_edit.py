"""test_edit.py - EDIT in the emulator.

    PY65=path/to/py65 python3 test/test_edit.py
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
        p = os.path.join(d, *name.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(data)
    return d


def redrawn_same(e):
    """the screen as drawn bit by bit = the screen drawn whole (^G, a key)"""
    before = e.s.text()
    cur = (e.s.r, e.s.c)
    e.keys(ctl('g'), 0.6)
    e.keys('x', 1.0)
    after = e.s.text()
    if before != after:
        for r in range(23):
            if before[r] != after[r]:
                print('   row %d: %r / %r' % (r, before[r], after[r]))
    return before == after and cur == (e.s.r, e.s.c)


def read(d, name):
    return open(os.path.join(d, *name.split('/')), 'rb').read()


NOTES = b'# Notes\r\n\r\nSome *text* here.\r\n- one\r\n- two\r\n'

# ---- opening a file ---------------------------------------------------------------
d = folder({'NOTES.MD': NOTES, 'A.TXT': b'alpha\nbeta\n', 'DOCS/IN.TXT': b'inside\n'})
e = Ed(d)
check('Open file' in e.status(), 'the start: asks which file')
e.keys('?\r', 1.5)
scr = '\n'.join(e.s.text())
check('NOTES.MD' in scr and 'A.TXT' in scr and 'DOCS/' in scr, '? lists the folder (DOCS/ a folder)')
e.keys('notes.md\r', 1.5)
check(e.s.text()[:5] == ['# Notes', '', 'Some *text* here.', '- one', '- two'], 'notes.md read and shown')
e.keys('x', 0.4)
check('NOTES.MD' in e.status() and 'Line 1/6' in e.status() and 'Col 2' in e.status() and 'changed' in e.status(),
      'status: name, (changed), line 1/6, column: %r' % e.status())
check((e.s.r, e.s.c) == (0, 1), 'the cursor after the x')

# ---- moving and typing ------------------------------------------------------------
e.keys(DN + DN + END + ' More.', 0.6)
check(e.s.row(2) == 'Some *text* here. More.', 'Down Down End, typing at the line end')
e.keys(UP, 0.4)
check((e.s.r, e.s.c) == (1, 0), 'up onto the empty line: column 0')
e.keys(UP + END + LT + LT + LT + '!', 0.6)
check(e.s.row(0) == 'x# No!tes', 'Left x3 then typing: %r' % e.s.row(0))
e.keys('\x7f\x7f', 0.4)
check(e.s.row(0) == 'x# Ntes', 'Backspace x2')
e.keys(HOME + DEL, 0.4)
check(e.s.row(0) == '# Ntes', 'Home, Del')
e.keys(END + '\r' + 'new line', 0.8)
check(e.s.text()[:4] == ['# Ntes', 'new line', '', 'Some *text* here. More.'] and 'Line 2/7' in e.status(),
      'Enter splits: a new line 2 (7 lines)')
e.keys(HOME + '\x7f', 0.6)
check(e.s.text()[:3] == ['# Ntesnew line', '', 'Some *text* here. More.'] and 'Line 1/6' in e.status(),
      'Backspace at a line start joins the lines')
check(redrawn_same(e), 'the screen as updated = drawn whole')
e.keys(ctl('s'), 1.5)
check(read(d, 'NOTES.MD') == b'# Ntesnew line\r\n\r\nSome *text* here. More.\r\n- one\r\n- two\r\n' and 'Saved' in e.status(),
      '^S: saved, with CR LF as it was read: %r' % read(d, 'NOTES.MD')[:40])

# ---- tab, cut and paste, find, go to ------------------------------------------------
e.keys(ctl('t') + '\t' + 'T', 0.6)
check(e.s.row(0).startswith('    T#') or e.s.row(0).startswith('    xT'), 'Tab: 4 spaces: %r' % e.s.row(0))
e.keys(ctl('l') + '4\r', 0.8)
check('Line 4/' in e.status(), '^L 4: line 4')
e.keys(ctl('k') + ctl('k'), 0.8)
check(e.s.text()[2:5] == ['', '', ''] or e.s.row(3) == '', '^K ^K: two lines cut: %r' % e.s.text()[:5])
e.keys(ctl('t') + ctl('u'), 1.0)
check(e.s.text()[:2] == ['- one', '- two'], '^T ^U: pasted at the top: %r' % e.s.text()[:3])
e.keys(ctl('f') + 'MORE\r', 1.5)
check('Line 5/' in e.status() and e.s.c == 18, '^F MORE (any case): found on line 5, column 19: %r %d' % (e.status(), e.s.c))
e.keys(ctl('n'), 1.5)
check('Line 5/' in e.status(), '^N: the only one, found again')
e.keys(ctl('f') + '\x7f\x7f\x7f\x7fzzz\r', 1.5)
check('Not found' in e.status() and 'Line 5' not in e.status(), '^F zzz: not found (the cursor stays)')
e.keys('q', 0.5)
check('Line 5/' in e.status(), '... on line 5')
check(redrawn_same(e), 'the screen as updated = drawn whole')

# ---- quitting ----------------------------------------------------------------------
e.keys(ctl('q'), 0.5)
check('Save it first' in e.status() and not e.m.exited, '^Q with changes: asks')
e.keys('\x1b', 0.5)
check(not e.m.exited, 'Esc: back to editing')
e.keys(ctl('q') + 'n', 0.8)
check(e.m.exited, 'N: quits (to the menu)')
shutil.rmtree(d)

# ---- a new file, in a folder; LF files stay LF -------------------------------------------
d = folder({'DOCS/OLD.TXT': b'one\ntwo\n'})
e = Ed(d, cwd='/DOCS')
e.keys('old.txt\r', 1.5)
check(e.s.text()[:2] == ['one', 'two'], 'in the monitor\'s folder /DOCS: OLD.TXT read')
e.keys(ctl('b') + 'three', 0.6)
e.keys(ctl('s'), 1.5)
check(read(d, 'DOCS/OLD.TXT') == b'one\ntwo\nthree', 'LF kept as LF; ^B (bottom) then typed: %r' % read(d, 'DOCS/OLD.TXT'))
e.keys(ctl('o') + 'new.md\r', 1.5)
check('new file' in e.status() and e.s.text()[0] == '', '^O new.md: a new file')
e.keys('Hello\rWorld', 0.8)
e.keys(ctl('s'), 1.5)
check(read(d, 'DOCS/NEW.MD') == b'Hello\r\nWorld', 'a new file: saved with CR LF')
e.keys(ctl('o') + '/top.txt\r', 1.5)
e.keys('at the top' + ctl('s'), 1.5)
check(read(d, 'TOP.TXT') == b'at the top', '/TOP.TXT: a path from the top folder')
e.keys(ctl('w') + '\x7f' * 10 + 'COPY.TXT\r', 1.5)
e.keys(LT, 0.5)
check(read(d, 'DOCS/COPY.TXT') == b'at the top' and 'COPY.TXT' in e.status(), '^W: save as COPY.TXT (now the name)')
shutil.rmtree(d)

# ---- a long file: scrolling ---------------------------------------------------------------
lines = ['line %d %s' % (i, 'x' * (i % 50)) for i in range(1, 201)]
d = folder({'LONG.TXT': ('\n'.join(lines) + '\n').encode()})
e = Ed(d)
e.keys('long.txt\r', 2.0)
check(e.s.text() == lines[:23], 'the first 23 lines shown')
e.keys(DN * 22, 1.0)
check(e.s.text() == lines[:23] and e.s.r == 22, 'down to the last row: no scroll yet')
n0 = e.n
e.keys(DN, 0.6)
check(e.s.text() == lines[1:24] and b'\x1b[M' in bytes(e.m.out[n0:]) and len(e.m.out) - n0 < 300,
      'one more: scrolled a row (ESC [ M, %d bytes sent)' % (len(e.m.out) - n0))
e.keys(PGDN, 1.0)
check(e.s.text() == lines[23:46] and 'Line 46/201' in e.status(), 'PgDn: a page on, the cursor too: %r' % e.status())
e.keys(PGUP + PGUP, 1.5)
check(e.s.text()[0] == lines[0] and 'Line 2/201' in e.status(), 'PgUp x2: back at the top: %r' % e.status())
e.keys(ctl('l') + '150\r', 1.5)
check('Line 150/' in e.status() and e.s.row(e.s.r) == lines[149].rstrip(), '^L 150: line 150, on the screen')
e.keys(ctl('b'), 1.5)
check('Line 201/201' in e.status() and e.s.row(e.s.r) == '', '^B: the end (the empty line after the last LF)')
e.keys(UP * 30, 2.0)
check(e.s.row(e.s.r) == lines[170].rstrip() and redrawn_same(e), 'Up x30: line 171; screen right')
# a long line: the columns scroll
e.keys(ctl('t') + END + 'y' * 80, 2.0)
check(e.s.c < 79 and e.s.row(0).endswith('y' * 40), 'a line longer than the screen: its columns scroll')
e.keys(HOME, 0.8)
check(e.s.row(0) == ('line 1 x' + 'y' * 80)[:79] and e.s.c == 0, 'Home: back to column 1')
check(not e.s.problems, 'nothing sent that the display would misread (%s)' % e.s.problems[:3])
shutil.rmtree(d)

# ---- UTF-8 shown as CP437 ---------------------------------------------------------------
d = folder({'U.TXT': 'café — “q” ½ • x\n'.encode('utf-8')})
e = Ed(d)
e.keys('u.txt\r', 1.5)
check(e.s.row(0) == 'caf\x82 - "q" \xab \xf9 x', 'UTF-8: e acute, dash, quotes, half, bullet: %r' % e.s.row(0))
e.keys(END + LT * 4 + '!', 0.8)
check(e.s.row(0) == 'caf\x82 - "q" \xab! \xf9 x', 'Left over the multi-byte characters: one each')
e.keys(ctl('s'), 1.5)
check(read(d, 'U.TXT') == 'café — “q” ½! • x\n'.encode('utf-8'), 'saved: the UTF-8 kept')
shutil.rmtree(d)

# ---- view mode: markdown ---------------------------------------------------------------
MD = '''# Title
## Sub heading
Plain **bold** and *em* and `code` and [a link](http://x.y/z) end.
- item one
- item two that is long enough to wrap onto the next row of the screen because it goes on and on
  1. nested
> a quote
---
```
code  *not* bold
```
| a | b |
|---|---|
| 1 | 2 |
snake_case_word stays
'''
d = folder({'R.MD': MD.encode()})
e = Ed(d)
e.keys('r.md\r', 1.5)
e.keys(ctl('r'), 2.0)
t = e.s.text()
check('VIEW' in e.status() and 'markdown' in e.status(), '^R: view mode (markdown)')
check(t[0] == 'Title' and set(e.s.attrs(0)[:5]) == {1 | 4}, '# : bold reverse, the # gone')
check(t[1] == 'Sub heading' and set(e.s.attrs(1)[:3]) == {1 | 2}, '## : bold underlined')
r2 = t[2]
check(r2 == 'Plain bold and em and code and a link end.', 'inline: markers and the address gone: %r' % r2)
a2 = e.s.attrs(2)
check(a2[r2.index('bold')] == 1 and a2[r2.index('em ')] == 2 and a2[r2.index('code')] == 4 and a2[r2.index('a link')] == 2
      and a2[0] == 0, 'bold, emphasis (underlined), code (reverse), link (underlined)')
check(t[3] == '\xf9 item one', 'a bullet item: %r' % t[3])
check(t[4].startswith('\xf9 item two') and len(t[4]) <= 79 and t[5].startswith('  ') and not t[5].startswith('   '),
      'a long item wrapped at a word, the next row indented under it: %r / %r' % (t[4][-20:], t[5][:20]))
words = (t[4] + ' ' + t[5].strip()).split()
check(' '.join(words) == '\xf9 item two that is long enough to wrap onto the next row of the screen because it goes on and on',
      'no word lost or split in the wrap')
check(t[6] == '  1. nested', 'a numbered item, indented: %r' % t[6])
check(t[7] == '\xb3 a quote', 'a quote: a bar: %r' % t[7])
check(t[8] == '\xc4' * 79, '--- : a rule across')
check(t[9] == '' and t[10] == '  code  *not* bold' and set(e.s.attrs(10)) == {0} and t[11] == '',
      'a code block: as it is, indented: %r' % t[10])
check(t[12] == '\xb3 a \xb3 b \xb3' and t[13] == '\xc5\xc4\xc4\xc4\xc5\xc4\xc4\xc4\xc5' and t[14] == '\xb3 1 \xb3 2 \xb3',
      'a table: lines drawn: %r %r' % (t[12], t[13]))
check(t[15] == 'snake_case_word stays', '_ inside a word: not emphasis')
e.keys('m', 1.5)
check(e.s.row(0) == '# Title' and 'plain' in e.status(), 'M: markdown off (as it is, wrapped)')
e.keys('m\x1b', 1.5)
check('VIEW' not in e.status() and e.s.row(0) == '# Title', 'Esc: back to editing')
shutil.rmtree(d)

# view mode: scrolling a long markdown file, back to the line shown
paras = ['Paragraph %d. ' % i + ' '.join('word%d' % j for j in range(40)) for i in range(1, 41)]
d = folder({'P.MD': '\n\n'.join(paras).encode()})
e = Ed(d)
e.keys('p.md\r', 2.0)
e.keys(ctl('r'), 2.5)
t = e.s.text()
check(t[0].startswith('Paragraph 1.') and all(len(r) <= 79 for r in t), 'long paragraphs wrapped to the screen')
first = t[:]
n0 = e.n
e.keys(DN, 1.5)
check(e.s.text()[:22] == first[1:23] and b'\x1b[M' in bytes(e.m.out[n0:]), 'Down: a row on (ESC [ M)')
e.keys(UP, 1.5)
check(e.s.text() == first, 'Up: back')
e.keys(PGDN * 3, 3.0)
p3 = e.s.text()
e.keys(PGUP * 3, 3.0)
check(e.s.text() == first, 'PgDn x3, PgUp x3: back at the top')
e.keys(END, 4.0)
t = e.s.text()
check(t[-1].startswith('word') or t[-1].endswith('word39'), 'End: the last row at the bottom: %r' % t[-1])
check(any(r.startswith('Paragraph 40.') for r in t), '... paragraph 40 shown')
e.keys(DN, 1.5)
check(e.s.text() == t, 'Down at the end: nothing')
e.keys(PGUP, 2.5)
top = e.s.text()[0]
e.keys('\x1b', 2.0)
check('VIEW' not in e.status() and e.s.r == 0, 'Esc after scrolling: editing, at the line that was on top')
check(not e.s.problems, 'nothing sent that the display would misread (%s)' % e.s.problems[:3])
shutil.rmtree(d)

# ---- the buffer's size ---------------------------------------------------------------------
d = folder({'BIG.TXT': b'x' * 40000})
e = Ed(d)
e.keys('big.txt\r', 3.0)
check('Too big' in e.status() and e.s.text()[0] == '', 'a file too big: said so (and an empty text)')
shutil.rmtree(d)


# ---- typing fast, the edges, ESC O keys ------------------------------------------------------
d = folder({})
e = Ed(d)
e.keys('\x1b', 0.5)
check('new file' in e.status(), 'Esc at the start: a new, empty text')
e.keys('\x7f' + DEL + UP + DN + LT + RT, 0.6)
check(e.s.text()[0] == '' and 'Line 1/1' in e.status(), 'Backspace, Del, the arrows in an empty text: nothing breaks')
text = ''.join('Row %02d: the quick brown fox jumps over the lazy dog.\r' % i for i in range(30))
e.keys(text, 4.0, gap=0.0004)          # (25 keys a 10 ms, faster than anyone types)
check('Line 31/31' in e.status(), 'typed fast: 30 lines (keys waiting: drawn once at the end)')
check(redrawn_same(e), 'the screen right after it')
e.keys('\x1bOA\x1bOA\x1bOH' + 'Z', 0.8)
check(e.s.row(e.s.r).startswith('ZRow 28'), 'ESC O A / ESC O H keys too')
e.keys(ctl('s') + 'FAST.TXT\r', 2.0)
want = ''.join('Row %02d: the quick brown fox jumps over the lazy dog.\r\n' % i for i in range(30)).replace('Row 28', 'ZRow 28')
check(read(d, 'FAST.TXT') == want.encode(), '^S with no name: asks for one, then saves')
shutil.rmtree(d)

# a .TXT file in view mode: not formatted
d = folder({'T.TXT': b'# not a heading\n*not em*\n'})
e = Ed(d)
e.keys('t.txt\r', 1.5)
e.keys(ctl('r'), 1.5)
check(e.s.text()[:2] == ['# not a heading', '*not em*'] and 'plain' in e.status(), 'a .TXT in view mode: as it is')
e.keys(ctl('g'), 0.8)
help_rows = [r.strip() for r in e.s.text()[:22]]
check(help_rows[0] == 'EDIT - the keys' and help_rows[2].startswith('Arrows, Home, End') and help_rows[12] == 'View mode'
      and help_rows[19].startswith('A file over 13 KB') and help_rows[21] == 'Press a key', '^G: the keys, every line whole: %r' % help_rows[:3])
e.keys('x', 1.0)
check(e.s.text()[0] == '# not a heading' and 'VIEW' in e.status(), 'a key: back to the view')
shutil.rmtree(d)


# nested list items 4 spaces in (not code), and real indented code
d = folder({'N.MD': b'- top\n    - nested\n\nPara\n\n    indented code\n'})
e = Ed(d)
e.keys('n.md\r', 1.5)
e.keys(ctl('r'), 1.5)
t = e.s.text()
check(t[:6] == ['\xf9 top', '    \xf9 nested', '', 'Para', '', '  indented code'], 'a nested item 4 spaces in; code 4 spaces in: %r' % t[:6])
shutil.rmtree(d)

# ---- how long things take (2 MHz) ------------------------------------------------------------
big = '\n\n'.join('## Part %d\n\n' % i + ' '.join('word%d' % j for j in range(60)) for i in range(30))
d = folder({'BIGDOC.MD': big.encode()})
e = Ed(d)
t0 = e.m.now()
e.keys('bigdoc.md\r', 0.0)
for _ in range(200):
    if 'Lines read' in e.status(): break
    e.run(0.05)
t_open = (e.m.now() - t0) / HZ - 0.02
def took(keys, done):
    t0 = e.m.now()
    e.keys(keys, 0.0)
    n = e.n
    for _ in range(300):
        e.run(0.02)
        if done(): break
    return (e.m.now() - t0) / HZ
t_key = took('a', lambda: e.s.row(0).startswith('a##'))
t_view = took(ctl('r'), lambda: 'VIEW' in e.status())
t_pg = took(PGDN, lambda: 'Line 1/' not in e.status())
t_back = took('\x1b', lambda: 'VIEW' not in e.status())
print('      timings: open %d KB %.2f s, a key %.3f s, ^R %.2f s, PgDn in view %.2f s, back %.2f s'
      % (len(big) // 1024, t_open, t_key, t_view, t_pg, t_back))
check(t_key < 0.1 and t_view < 1.5 and t_pg < 1.0, 'quick enough')
shutil.rmtree(d)

print('\n%d failed' % len(fails) if fails else '\nall passed')
sys.exit(1 if fails else 0)
