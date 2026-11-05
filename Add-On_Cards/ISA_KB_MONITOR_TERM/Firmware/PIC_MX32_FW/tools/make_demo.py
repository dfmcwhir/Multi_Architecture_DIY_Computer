#!/usr/bin/env python3
"""Creates demo_cp437.bin - a test file for the extended terminal.  Send it to the terminal with, for example
       cat demo_cp437.bin > /dev/ttyUSB0          (Linux, after setting the baud rate with stty)
or with any terminal program that can send a raw file.  Needs the terminal set to CP437 (set-up item I = 1, the default)
and a VGA (80 column) display."""
import sys
E = b'\x1b'
def csi(s): return E + b'[' + s.encode()
out = bytearray()
def w(b):
    out.extend(b if isinstance(b, (bytes, bytearray)) else b.encode('latin-1'))
def at(r, c): w(csi('%d;%dH' % (r, c)))

w(csi('2J')); w(csi('H'))
w(csi('1;4m')); w('Extended VT100 terminal demo'); w(csi('0m'))
at(3, 1); w('Attributes: normal '); w(csi('1m')); w('bold'); w(csi('0m')); w(' '); w(csi('4m')); w('underline'); w(csi('0m'))
w(' '); w(csi('7m')); w('reverse'); w(csi('0m')); w(' '); w(csi('1;4;7m')); w('all three'); w(csi('0m'))
at(4, 1); w('Accents (CP437): Caf'); w(b'\x82'); w(' na'); w(b'\x8b'); w('ve, '); w(b'\x81'); w('ber, ma'); w(b'\xa4'); w('ana, '); w(b'\x84\x94\x81\xe1')
at(6, 1); w('CP437 characters 0x80 - 0xFF:')
for row in range(8):
    at(7 + row, 1); w('%X0 ' % (8 + row))
    for col in range(16):
        w(bytes([0x80 + row * 16 + col])); w(' ')
at(16, 1); w('CP437 boxes:')
at(17, 1);  w(b'\xda' + b'\xc4' * 10 + b'\xbf')
at(18, 1);  w(b'\xb3 single   \xb3')
at(19, 1);  w(b'\xc0' + b'\xc4' * 10 + b'\xd9')
at(17, 16); w(b'\xc9' + b'\xcd' * 10 + b'\xbb')
at(18, 16); w(b'\xba double   \xba')
at(19, 16); w(b'\xc8' + b'\xcd' * 10 + b'\xbc')
at(17, 31); w(b'\xdb\xdb\xb2\xb2\xb1\xb1\xb0\xb0 shades')
at(18, 31); w(b'\xdf\xdc\xdd\xde \xfb \xf8 \xf1 \xe3 \xe4 \xea \xec')
at(16, 50); w('DEC line drawing (ESC ( 0):')
at(17, 50); w(E + b'(0'); w('lqqqqqqqqqqk'); w(E + b'(B')
at(18, 50); w(E + b'(0'); w('x'); w(E + b'(B'); w(' ESC ( 0  '); w(E + b'(0'); w('x'); w(E + b'(B')
at(19, 50); w(E + b'(0'); w('mqqqqqqqqqqj'); w(E + b'(B')
at(17, 66); w(E + b'(0'); w('a`fgyz{|}~'); w(E + b'(B')
at(18, 66); w('SO/SI: '); w(b'\x1b)0\x0e'); w('tnu'); w(b'\x0f')
at(20, 1); w('Scrolling region (lines 22-24), insert/delete:')
w(csi('22;24r'))
at(22, 1)
for n in ('one', 'two', 'three', 'four', 'five'):
    w('region line ' + n + '\r\n')
w(csi('r'))
at(21, 1); w('ABCDEFGH'); at(21, 3); w(csi('3@')); w('123'); at(21, 20); w('<- ICH 3 at column 3')
at(24, 60); w(csi('1m')); w('Done'); w(csi('0m'))
sys.stdout.buffer.write(bytes(out)) if len(sys.argv) < 2 else open(sys.argv[1], 'wb').write(bytes(out))
