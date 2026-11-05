"""test_term.py - TERM in the emulator (sim.py).

    PY65=path/to/py65 python3 test/test_term.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sim import Machine, CPU_HZ

BIN = os.path.join(HERE, '..', 'TERM.BIN')
ESC = '\x1b'
fails = []


def check(cond, msg):
    print(('ok    ' if cond else 'FAIL  ') + msg)
    if not cond: fails.append(msg)


def new():
    m = Machine(BIN)
    m.run(0.3)
    return m


def after_start(m):
    return m.now() / CPU_HZ


# starting up
m = new()
s = m.screen_bytes()
check(b'TERM - A TERMINAL' in s and b'[TERM: PORT 1200 8N1]' in s, 'the banner, at 1200 8N1')
check(m.mdm_ctrl == 0x18 and m.dsp_cmd == 0x8B and not m.via.ier & 0x40,
      'the port at 1200 8N1; the keyboard read directly; the gamepad interrupt off')

# typing goes to the Zimodem, a byte time (8.3 ms at 1200) apart
m = new()
m.type_at(0.35, 'ATZ\r', gap=0.001)          # (typed faster than 1200 baud)
m.run(0.3)
mb = m.modem_bytes()
times = [t for t, b in m.modem]
gaps = [b - a for a, b in zip(times, times[1:])]
check(mb == b'ATZ\r' and gaps and min(gaps) >= CPU_HZ * 10 // 1200, 'keys to the modem: %r, %.1f ms apart' % (mb, min(gaps) / CPU_HZ * 1000))
check(not m.screen_bytes(0.34), 'no local echo by default')

# what the BBS sends: text and the control codes
m = new()
t0 = after_start(m)
m.bbs_at(t0, 'Hi\r\nA\x01\x10B\x07\x7f\x00\x0cZ')
m.run(0.4)
s = m.screen_bytes(t0)
check(s == b'Hi\r\nA\x1a\x01\x1a\x10B\x1a\x7f\x0cZ', 'text; CR LF FF passed; 01, 10, 7F shown as characters (1A n); NUL dropped: %r' % s)
check((8, 12) in m.ay and m.ay[-1] == (7, 0x3F), 'BEL: a beep on the AY card, then quiet')

# ANSI: passed on, except the colours
m = new()
t0 = after_start(m)
m.bbs_at(t0, ESC + '[2J' + ESC + '[10;5H' + ESC + '[K' + ESC + '7' + ESC + '(0q' + ESC + '(B' + ESC + '[?25l')
m.run(0.6)
s = m.screen_bytes(t0)
check(s == (ESC + '[2J' + ESC + '[10;5H' + ESC + '[K' + ESC + '7' + ESC + '(0q' + ESC + '(B' + ESC + '[?25l').encode(),
      'cursor, erase, ESC 7, character sets, private modes: passed on as they are')

def sgr(seq):
    m = new()
    t0 = after_start(m)
    m.bbs_at(t0, ESC + '[' + seq + 'mX')
    m.run(0.5)                              # (27 bytes take 0.23 s at 1200)
    return m.screen_bytes(t0).decode('latin-1')

check(sgr('1;37;44') == ESC + '[0;1mX', 'bright white on blue: bold')
check(sgr('30;46') == ESC + '[0;7mX', 'black on cyan: reverse (it would vanish)')
check(sgr('34;47') == ESC + '[0;7mX', 'blue on white: reverse')
check(sgr('33;41') == 'X', 'yellow on red: as normal text (nothing to send)')
check(sgr('7') == ESC + '[0;7mX', 'reverse asked for: reverse')
check(sgr('30;47;7') == 'X', 'black on white, reversed: white on black (normal)')
check(sgr('4;38;5;196;48;2;10;20;30') == ESC + '[0;4mX', '256 colour and RGB codes skipped; underline kept')
check(sgr('') == 'X', 'ESC [ m: reset (nothing changes)')
check(sgr('3') == 'X', 'italic dropped (on this display SGR 3 changes the font)')
check(sgr('0;5;30;44') == ESC + '[0;7mX', 'blink + blue background (iCE: bright blue) behind black: reverse')

# the attributes only sent when they change
m = new()
t0 = after_start(m)
m.bbs_at(t0, ESC + '[1;37mA' + ESC + '[1;33mB' + ESC + '[0mC')
m.run(0.4)
check(m.screen_bytes(t0) == (ESC + '[0;1mAB' + ESC + '[0mC').encode(), 'repeated attributes not sent again')

# Ctrl-A C: colours passed on as they are
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01C')
m.run(0.3)
t1 = after_start(m)
m.bbs_at(t1, ESC + '[1;31;44mX')
m.run(0.3)
check(m.screen_bytes(t1) == (ESC + '[1;31;44mX').encode(), 'Ctrl-A C: the colour codes passed on unchanged')

# a cursor position report from the display (back to back at 115200) goes
# to the BBS whole, even while the screen is busy
m = new()
t0 = after_start(m)
m.bbs_at(t0, ESC + '[6n' + 'x' * 200, baud=19200)
m.burst_at(t0 + 0.01, ESC + '[24;80R')
m.run(0.4)
check(m.modem_bytes(t0) == (ESC + '[24;80R').encode() and m.kb_lost == 0,
      'a CPR reply (9 bytes at 115200) during a busy screen: all of it to the BBS, none lost')
check(not m.errors, 'at 19200 the ROM buffer keeps up')

# Ctrl-A D: dial
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01Dbbs.example.com\r')
m.run(1.5)
check(m.modem_bytes(t0) == b'ATDT"bbs.example.com:23"\r', 'Ctrl-A D: ATDT"host:23" (port 23 added)')
m.type_at(after_start(m), '\x01Dhost.net:6400\r')
m.run(1.5)
check(m.modem_bytes(t0).endswith(b'ATDT"host.net:6400"\r'), 'with a port: as typed')

# Ctrl-A X: hang up: a second of nothing, +++, a second, ATH
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01X')
m.run(3)
mb = [(t / CPU_HZ, b) for t, b in m.modem if t >= t0 * CPU_HZ]
check(bytes(b for t, b in mb) == b'+++ATH\r' and mb[0][0] - t0 > 1.0 and mb[3][0] - mb[2][0] > 1.0,
      'Ctrl-A X: +++ after 1 s, ATH after another')

# Ctrl-A S: the set-up screen
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01S')
m.run(0.5)
sc = m.screen_bytes(t0)
check(b'TERM SET-UP' in sc and b'BAUD RATE' in sc and b'1200' in sc and b'PARITY' in sc and b'NONE' in sc,
      'Ctrl-A S: the set-up screen (baud 1200, parity none ...)')
# 1: the next rate (1800), 3: parity odd; Enter: tell the Zimodem? Y:
# ATB"1800,8O1" at 1200, then the port changes
m.type_at(after_start(m), '13\r', gap=0.3)
m.run(1.5)
mb = m.modem_bytes(t0)
check(b'ATB"1800,8O1"' in m.screen_bytes(t0) and not mb, 'Enter: it shows ATB"1800,8O1" and asks first')
t1 = after_start(m)
m.type_at(t1, 'Y')
m.run(1.5)
times = [t for t, b in m.modem if t >= t1 * CPU_HZ]
check(m.modem_bytes(t1) == b'ATB"1800,8O1"\r' and min(b - a for a, b in zip(times, times[1:])) >= CPU_HZ * 10 // 1200,
      'Y: ATB"1800,8O1" sent at 1200')
check(m.mdm_ctrl == 0x19 and m.mdm_cmd == 0x29 and b'[TERM: PORT 1800 8O1]' in m.screen_bytes(t1),
      'then the port: 1800 (control $19), odd parity, RTS, DTR (command $29)')
# every rate's control register, the data bits and 2 stop bits
m = new()
m.type_at(after_start(m), '\x01S' + '1' * 6 + '22' + '4' + '\rN', gap=0.15)
m.run(4)
check(m.mdm_ctrl == 0x9E | 0x40 and m.mdm_cmd == 0x09, '9600, 6 data bits, 2 stop bits: control $DE; command $09 (N: not told)')
m = new()
m.type_at(after_start(m), '\x01S' + '1' * 8 + '\rN', gap=0.15)
m.run(4)
check(m.mdm_ctrl == 0x10, '115200: the 16x external clock (control $10)')

# DTR and RTS: 5 DTR off, 6 RTS off, again: flow control
m = new()
m.type_at(after_start(m), '\x01S56\r', gap=0.2)
m.run(1.5)
check(m.mdm_cmd == 0x00 and not m.modem_bytes(), 'DTR off, RTS off: command $00 (and no ATB: the rate is the same)')
m.type_at(after_start(m), '\x01S56\r', gap=0.2)
m.run(1.5)
check(m.mdm_cmd == 0x09 and b'RTS FLOW' in m.screen_bytes(), 'RTS: flow control (asserted while the buffer is low)')
m.hold_ptrs = True
list.__setitem__(m.mem, 0xE2, 10); list.__setitem__(m.mem, 0xE3, 210)
m.run(0.1)
c1 = m.mdm_cmd
list.__setitem__(m.mem, 0xE3, 50)
m.run(0.1)
check(c1 == 0x01 and m.mdm_cmd == 0x09, 'flow: RTS let go at 200 waiting ($01), asserted again at 40 ($09)')

# TERM.CFG: S saves; the next start reads it
import tempfile, shutil
d = tempfile.mkdtemp()
m = Machine(BIN, d)
m.run(0.5)
m.type_at(after_start(m), '\x01S78S', gap=0.2)
m.run(2)
f = os.path.join(d, 'TERM.CFG')
data = open(f, 'rb').read() if os.path.exists(f) else b''
check(data == b'TCF1' + bytes([4, 0, 0, 0, 1, 0, 1, 1, 1, 0]) and b'SAVED IN TERM.CFG' in m.screen_bytes(),
      'S: TERM.CFG saved (echo and LF after CR on)')
m.type_at(after_start(m), '\r')
m.run(0.5)
m = Machine(BIN, d)
m.run(0.8)
m.bbs_at(after_start(m), 'a\r')
m.type_at(after_start(m) + 0.2, 'x')
m.run(0.5)
check(b'SETTINGS FROM TERM.CFG' in m.screen_bytes() and m.screen_bytes().endswith(b'a\r\nx'),
      'the next start: the settings read (LF after the CR, and the key echoed)')
shutil.rmtree(d)

# Ctrl-A E: local echo; Ctrl-A K: Backspace sends BS
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01E')
m.run(0.3)
t1 = after_start(m)
m.type_at(t1, 'ok\x7f')
m.run(0.3)
check(m.screen_bytes(t1) == b'ok\x1a\x7f' and m.modem_bytes(t1) == b'ok\x7f', 'Ctrl-A E: what is typed shown too')
m.type_at(after_start(m), '\x01K\x7f\x01\x01')
m.run(0.5)
check(m.modem_bytes(t1).endswith(b'\x08\x01'), 'Ctrl-A K: DEL sent as BS; Ctrl-A Ctrl-A sends Ctrl-A')

# Ctrl-A Q: asks; Y quits and puts things back
m = new()
t0 = after_start(m)
m.type_at(t0, '\x01Qn')
m.run(0.4)
check(not m.exited, 'Ctrl-A Q, N: still running')
m.type_at(after_start(m), '\x01Qy')
m.run(0.4)
check(m.exited and m.mdm_ctrl == 0x1A and m.mdm_cmd == 0x89 and m.dsp_cmd == 0x89 and m.via.ier & 0x40,
      'Ctrl-A Q, Y: back to the menu; the port at 2400 with its interrupt, the keyboard by interrupt, the gamepad on')
check(not m.errors, 'no errors (%s)' % m.errors[:3])

print('\n%d failed' % len(fails) if fails else '\nall passed')
sys.exit(1 if fails else 0)
