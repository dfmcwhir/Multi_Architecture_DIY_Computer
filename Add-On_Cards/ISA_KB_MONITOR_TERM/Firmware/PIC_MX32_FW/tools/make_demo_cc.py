#!/usr/bin/env python3
"""Creates demo_controlcodes.bin - a demo of the control code mode (set-up item J = ON).  Send it raw to the terminal
(VGA, 80 columns) e.g.  cat demo_controlcodes.bin > /dev/ttyUSB0"""
import math
out = bytearray()
def csi(s): return b'\x1b[' + s.encode()
def w(b): out.extend(b if isinstance(b, (bytes, bytearray)) else b.encode('latin-1'))
def col(n): w(bytes([0x0e, n]))
def row(n): w(bytes([0x0f, n]))
def at(r, c): col(c); row(r)                      # 0 based like the control codes
def attr(n): w(bytes([0x18, n]))
def lit(n): w(bytes([0x1a, n]))
def pix(x, y): w(bytes([0x05, x, y]))
def unpix(x, y): w(bytes([0x06, x, y]))

w(b'\x0c')                                                    # clear screen, home
w(csi('4m')); w('Control code mode demo'); w(csi('0m'))
at(2, 0); w('Cursor: 0E/0F position, 1D-1F move, 01 home.   Erase: 10-13.   Scroll: 14-17.')
at(4, 0); w('PC symbols with 1A: ')
for n in range(1, 32): lit(n); w(' ')
at(6, 0); w('Attributes: ')
attr(0x02); w('bold '); attr(0x00); w('normal ');  w(csi('4m')); w('underline '); w(csi('7m')); w('reverse '); w(csi('0m')); w('(underline and reverse use ESC [ 4 m and 7 m)')
def blk(n):                                                   # patterns that look like control codes need the 1A prefix
    if n < 0x20 or n == 0x7f: lit(n)
    else: w(bytes([n]))
at(8, 0); w('Block graphics: 18 80, then each byte is a 2x4 block pattern (use 1A for 00-1F, 7F)')
at(9, 2); attr(0x80)
for n in (0xB1, 0xFF, 0x0F, 0xF0, 0x55, 0xAA, 0x3C, 0xC3, 0x81, 0x7E, 0xDB, 0x24):
    blk(n)
# a little picture made of block characters: a heart from 2x4 blocks
pic = [(0x00, 0xB0, 0xB0 , 0x00), (0x7C, 0xFF, 0xFF, 0x3E), (0x7F, 0xFF, 0xFF, 0xBF), (0x0F, 0xFF, 0xFF, 0x0F)]
pic = [[0x58, 0xAC], [0xFF, 0xFF], [0xFC, 0xF3], [0xF0, 0x0F]]
for r, line in enumerate(pic):
    at(11 + r, 2)
    for n in line: blk(n)
attr(0x00)
at(9, 40); w('Pixels: 05 x y / 06 x y')
for x in range(95, 155):
    pix(x, int(50 + 8 * math.sin((x - 95) / 6.0)))
for x in range(95, 155): pix(x, 60); pix(x, 66)
for y in range(60, 67): pix(95, y); pix(154, y)
for x in range(110, 130): unpix(x, 60)                          # reset pixel cuts a gap in the frame
at(14, 0); w('Cursor: 02 n defines it (here 0xDB, a block).  03 blink, 04 solid.')
w(b'\x02\xdb\x03')
at(16, 0); w('Scroll left/right (16/17) shift the whole screen one character.')
at(18, 0); w('Delete char (7F): abcXdef -> '); w('abcXdef'); w(bytes([0x0e, 31 + 3 + 0]) if False else b'')
w(bytes([0x1d] * 4)); w(b'\x7f')
at(19, 0); w('Repeat (18, bits 3-6): '); attr(0x08 * 5); w('=-'); attr(0x00); w('  tiles (19 n c r data, 0B n):')
w(bytes([0x19, 1, 2, 4, 0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB, 0x19, 2, 2, 4, 0xFF, 0xF0, 0x0F, 0xFF, 0x3C, 0xC3, 0x81, 0x7E]))   # SET TILE 1 and 2
at(20, 62); attr(0x80)
for t in (1, 2, 1, 2, 1): w(bytes([0x0b, t]))
attr(0x00)
at(20, 0); w('Done.')
open('demo_controlcodes.bin', 'wb').write(out)
print(len(out), 'bytes')
