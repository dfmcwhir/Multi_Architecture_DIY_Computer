"""Test GUI.BIN in the emulator: a USB drive and a CF card made of folders here
(test_disk/), the install into the top bank, the list (sorted, scrolling),
folders in and out, a program run and back (SBC_MENU -> the shell), a BASIC
program, the text viewer, the mouse (double click, buttons, scroll bar),
the gamepad, the drives.   python test_gui.py"""
import sys, os, shutil
sys.path.insert(0, '/home/claude/tools')
import emu6502

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, 'test_disk')
shutil.rmtree(D, ignore_errors=True)
U, C = os.path.join(D, 'U'), os.path.join(D, 'C')
for p in ['GAMES', 'GAMES/SUB', 'MANY', 'DOCS']:
    os.makedirs(os.path.join(U, p))
os.makedirs(C)
# a program: inc $0F00, then back through SBC_MENU
prog = bytes([0xEE, 0x00, 0x0F, 0x4C, 0x06, 0xFE])
open(os.path.join(U, 'GAMES', 'HELLO.BIN'), 'wb').write(prog)
open(os.path.join(U, 'GAMES', 'ZAP.BIN'), 'wb').write(prog + bytes(26042))
open(os.path.join(U, 'GAMES', 'MAP01.LVL'), 'wb').write(bytes(1160))
open(os.path.join(U, 'GAMES', 'SUB', 'DEEP.TXT'), 'w').write('deep\r\n')
open(os.path.join(U, 'PRIMES.BAS'), 'w').write('10 PRINT "HI"\n')
txt = ''.join('Line %d\tof the README, a\ttab or two.\r\n' % i for i in range(1, 41))
txt += 'A long line: ' + 'x' * 150 + '\r\nlast line\r\n'
open(os.path.join(U, 'README.TXT'), 'w', newline='').write(txt)
open(os.path.join(U, 'BIG.DAT'), 'wb').write(bytes(123457))
for i in range(45):
    open(os.path.join(U, 'MANY', 'F%02d.TXT' % (44 - i)), 'w').write('file %d\n' % i)
open(os.path.join(C, 'ONCF.BIN'), 'wb').write(prog)
os.makedirs(os.path.join(C, 'WORK'))

m = emu6502.Machine(int(os.environ.get('MHZ', '4')))
m.drives = {'U': U, 'C': C}
m.load(os.path.join(HERE, 'GUI.BIN'), 0x800)
L = m.load_labels(os.path.join(HERE, 'gui.lbl'))
problems = []
def check(cond, what):
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond: problems.append(what)
def v(n, i=0): return m.mem[L[n] + i]
def row(r):
    """screen row r as text (font tiles back to ASCII; icons as #, bar as |)"""
    vr = m.vdp.vram; s = ''
    for c in range(32):
        t = vr[0x2000 + 32 * r + c]
        if 0x20 <= t < 0x60: s += chr(t)
        elif 0x60 <= t < 0xA0: s += chr(t - 0x40)
        elif 0xA0 <= t < 0xE0: s += chr(t - 0x80)
        elif t < 0x18: s += '#'
        else: s += '|'
    return s
def sel_row():
    vr = m.vdp.vram
    return [r for r in range(2, 22) if 0xA0 <= vr[0x2000 + 32 * r + 4] < 0xE0]
def frames(n=3): return m.run(frames=n)
def key(ch, n=4): m.key(ch); return frames(n)
def screen(name): m.vdp.save_png(os.path.join(HERE, 'shots', name))
def listing(): return [row(r)[3:26].rstrip() for r in range(2, 22) if row(r).strip(' |')]

r = frames(30)
check(m.shell == 3 and m.bank == 3, 'installed in bank 3 and registered (shell %d, bank %d)' % (m.shell, m.bank))
check(row(0).startswith(' U:\\'), 'title: ' + row(0))
print('\n'.join(row(k) for k in range(24)))
lst = listing()
check([x.split()[0] for x in lst[:3]] == ['DOCS', 'GAMES', 'MANY'], 'folders first, sorted: %s' % lst[:3])
check(any('README.TXT' in x and '1' in x for x in lst), 'README.TXT listed')
check(any('BIG.DAT' in x and '123457' in x for x in lst), 'size 123457 shown')
check('6 ITEMS' in row(22), 'status: ' + row(22))
screen('top.png')

# into GAMES (down, Enter)
key(emu6502.__dict__.get('KEY_DOWN', 0x18)); key(0x0D, 10)
check(m.cwd() == '/GAMES', 'Enter on GAMES: cwd ' + m.cwd())
lst = listing()
check(lst[0].strip() == '..', '".." first: %s' % lst[:2])
check('SUB' in lst[1], 'SUB folder next')
screen('games.png')
# run HELLO.BIN (down to it): row 2 is "..", 3 SUB, then HELLO, MAP01, ZAP
key(0x18); key(0x18)
check('HELLO.BIN' in row(sel_row()[0]), 'HELLO selected: ' + row(sel_row()[0]))
m.mem[0x0F00] = 0
key(0x0D, 20)
check(m.ran and m.ran[-1] == (0, 'U', '/GAMES', 'HELLO.BIN'), 'SBC_RUN asked for HELLO.BIN: %s' % (m.ran[-1:],))
check(m.mem[0x0F00] == 1, 'the program ran')
frames(20)
check(m.bank == 3 and 'HELLO.BIN' in row(sel_row()[0]), 'back in the GUI after SBC_MENU, HELLO still selected')
check(m.cwd() == '/GAMES', 'still in GAMES')

# up a folder with Backspace: GAMES selected
key(0x08, 10)
check(m.cwd() == '' and 'GAMES' in row(sel_row()[0]), 'Backspace: up, GAMES selected')

# MANY: 45 files, scrolling, sorted
key(0x18); key(0x0D, 40)
check(m.cwd() == '/MANY', 'into MANY')
lst = listing()
check(lst[1].split()[0] == 'F00.TXT' and lst[19].split()[0] == 'F18.TXT', 'sorted F00..: %s .. %s' % (lst[1], lst[19]))
check(row(2)[31] == '|' and m.vdp.vram[0x2000 + 32 * 3 + 31] == 0xE3, 'scroll thumb at the top')
for i in range(25): m.key(0x18)
frames(60)
check('F24.TXT' in row(sel_row()[0]), 'down 25: F24 selected: ' + row(sel_row()[0]))
check(v('top') > 0, 'scrolled (top %d)' % v('top'))
screen('many.png')
key('>', 6)
check(v('top') == 26, 'page down: top %d (the last screen)' % v('top'))
thumb = [r for r in range(3, 21) if m.vdp.vram[0x2000 + 32 * r + 31] == 0xE3]
check(thumb == [20], 'thumb at the bottom: %s' % thumb)

# the gamepad: B = up a folder
m.pad = 0x02; frames(2); m.pad = 0; frames(10)
check(m.cwd() == '' and 'MANY' in row(sel_row()[0]), 'pad B: up, MANY selected')

# the text viewer: README.TXT (pad down x?, then A)
names = [row(r)[4:16].strip() for r in range(2, 22)]
k = names.index('README.TXT') - names.index('MANY')
for i in range(k):
    m.pad = 0x20; frames(2); m.pad = 0; frames(2)
check('README.TXT' in row(sel_row()[0]), 'pad down to README.TXT')
m.out = []
m.pad = 0x01; frames(2); m.pad = 0; frames(10)
out = bytes(m.out).decode('latin1')
check(out.startswith('README.TXT     page 1'), 'viewer header: %r' % out[:30])
check('Line 1  of the README, a        tab or two.' in out, 'tabs to 8 columns')
check('Line 21' in out and 'Line 22' not in out, 'a page is 21 lines')
check(out.rstrip().endswith('close --'), 'the prompt')
m.out = []; key(' ', 6); out = bytes(m.out).decode('latin1')
check('page 2' in out and 'Line 22' in out and 'Line 42' not in out, 'Space: page 2')
p2 = out.split('\r\n')
check('A long line: ' + 'x' * 66 in p2 and 'x' * 79 in p2, 'a long line wraps at 79')
m.out = []; key(' ', 6); out = bytes(m.out).decode('latin1')
lines = out.split('\r\n')
check('x' * 5 in lines and 'last line' in out and '-- end --' in out, 'page 3: the rest, the end')
m.out = []; key(0x05, 6); out = bytes(m.out).decode('latin1')
check('page 2' in out, 'Up: back to page 2')
key('Q', 30)
check(m.vdp.reg[49] == 0x22 and 'README.TXT' in row(sel_row()[0]), 'Q: back to the list, README selected')

# a BASIC program
names = [row(r)[4:16].strip() for r in range(2, 22)]
key(0x05, 4)
check('PRIMES.BAS' in row(sel_row()[0]), 'PRIMES.BAS selected (up one)')
r = key(0x0D, 10)
check(r == 'basic PRIMES.BAS' and m.ran[-1] == (1, 'U', '', 'PRIMES.BAS'), 'Enter: SBC_RUN BASIC %r' % (r,))

# again, with the mouse: re-enter through SBC_MENU (the shell)
m.cpu.pc = 0xFE06; m.stopped = None
frames(20)
check(m.bank == 3 and m.vdp.reg[49] == 0x22, 're-entered')
def move_to(x, y):
    while (v('m_x'), v('m_y')) != (x, y):
        dx = max(-100, min(100, x - v('m_x'))); dy = max(-100, min(100, y - v('m_y')))
        m.mouse_move(dx, dy); frames(2)
def click(b=1):
    m.set_buttons(b); frames(2); m.set_buttons(0); frames(2)
# click DOCS (row 2 is DOCS at the top)
move_to(60, 8 * 2 + 3); click()
check('DOCS' in row(sel_row()[0]), 'click selects DOCS')
screen('mouse.png')
click(); frames(1); click(); frames(10)
check(m.cwd() == '/DOCS', 'double click opens DOCS: cwd %r' % m.cwd())
check('EMPTY' in row(22), 'empty folder: ' + row(22))
click(2); frames(10)
check(m.cwd() == '', 'right click: up')
# the C: button
move_to(29 * 8 + 2, 3); click(); frames(10)
check(m.dev == 'C' and row(0).startswith(' C:\\'), 'C: button: ' + row(0))
lst = listing()
check('WORK' in lst[0] and 'ONCF.BIN' in lst[1], 'the CF card: %s' % lst)
# a drive that isn't there
m.drives['C'] = None
key('R', 10)
check('?' in row(22), 'no C: drive: ' + row(22))
m.drives['C'] = C
move_to(25 * 8, 3); click(); frames(10)
check(row(0).startswith(' U:\\'), 'U: button')
# the scroll bar in MANY: down arrow
key(0x18); key(0x18); key(0x0D, 40)
move_to(31 * 8 + 2, 21 * 8 + 2); click(); click()
check(v('top') == 2, 'scroll bar arrow x2: top %d' % v('top'))
move_to(31 * 8 + 2, 15 * 8 + 2); click()
check(v('top') == 22, 'track below the thumb: page down, top %d' % v('top'))
screen('scroll.png')

# ---- copy, paste, delete
def go_top():
    while m.cwd():
        key(0x08, 15)
def select(name):
    for _ in range(4): key('<', 3)
    for _ in range(60):
        r = sel_row()
        if r and name in row(r[0]): return True
        key(0x18, 3)
    return False
def status(): return row(22).strip()
go_top()
check(select('README.TXT'), 'README selected for copying')
key('K', 4)
check(status().startswith('TO PASTE: README.TXT'), 'K: ' + status())
key('P', 6)
check('ALREADY' in status(), 'paste into the same folder refused: ' + status())
check(select('GAMES'), 'GAMES'); key(0x0D, 15)
key('P', 30)
check(os.path.exists(os.path.join(U, 'GAMES', 'README.TXT')), 'pasted into GAMES')
check(m.copies[-1] == ('U', '/README.TXT', 'U', '/GAMES/README.TXT'), 'SBC_COPY block: %s' % (m.copies[-1],))
check('README.TXT' in row(sel_row()[0]) and 'COPIED README.TXT' in status(), 'the copy selected, ' + status())
check(m.bank == 3, 'still in bank 3')
# again: replace? NO, then YES (by mouse)
n0 = len(m.copies)
key('P', 6)
check(status().startswith('REPLACE README.TXT?') and 'YES  NO' in row(22), 'asks: ' + row(22))
key('N', 6)
check(len(m.copies) == n0, 'N: not copied')
m.key(KEY_F6 := 134); frames(6)
check(status().startswith('REPLACE'), 'F6 pastes too (asks)')
move_to(25 * 8, 22 * 8 + 3); click(); frames(30)
check(len(m.copies) == n0 + 1 and 'COPIED' in status(), 'YES clicked: copied, ' + status())
# delete it: the DEL button, pad A for yes
move_to(12 * 8, 23 * 8 + 2); click(); frames(4)
check(status().startswith('DELETE README.TXT?'), 'DEL asks: ' + status())
m.pad = 1; frames(2); m.pad = 0; frames(20)
check(not os.path.exists(os.path.join(U, 'GAMES', 'README.TXT')) and m.deletes[-1] == ('U', '/GAMES/README.TXT'), 'deleted: %s' % (m.deletes[-1:],))
check(status() == 'DELETED' and 'README' not in ''.join(row(r) for r in range(2, 22)), 'gone from the list, ' + status())
# a folder can't be copied or deleted
check(select('SUB'), 'SUB'); key('X', 4)
check('NOT A FOLDER' in status(), 'X on a folder: ' + status())
# to the CF card, and a drive that can't delete
key('C', 20)
check(m.dev == 'C', 'on C:')
key('P', 30)
check(os.path.exists(os.path.join(C, 'README.TXT')), 'pasted onto C: (the copy from U: is still remembered)')
check(m.copies[-1] == ('U', '/README.TXT', 'C', '/README.TXT'), 'U: -> C: %s' % (m.copies[-1],))
m.no_delete = ('C',)
check(select('README.TXT'), 'README on C:'); key('X', 4); key('Y', 20)
check('CANNOT DELETE' in status() and os.path.exists(os.path.join(C, 'README.TXT')), 'C: delete not set up: ' + status())
m.no_delete = ()
# too big (BIG.DAT 123457 > 3 banks)
key('U', 20)
check(select('BIG.DAT'), 'BIG.DAT'); key(133, 4); key('C', 20); key('P', 30)
check('TOO BIG' in status(), 'too big: ' + status())
screen('copy.png')
key('U', 20)
select('MANY'); key(0x0D, 40)
# the MONITOR button
r = None
move_to(25 * 8, 23 * 8 + 2); m.set_buttons(1); r = frames(4)
check(r == 'monitor' and m.bank == 0, 'MONITOR button: %r, bank %d' % (r, m.bank))
check(m.mem[0x0600:0x0606] == b'/MANY\0', 'the ROM folder kept: %r' % bytes(m.mem[0x0600:0x0606]))

print(repr(bytes(m.out)[:200])) if False else None
print('\n%d problems' % len(problems))
for p in problems: print('  ' + p)
