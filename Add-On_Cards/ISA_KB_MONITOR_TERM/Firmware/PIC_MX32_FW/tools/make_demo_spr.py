#!/usr/bin/env python3
"""Creates demo_sprites.bin - a demo of the sprite layer (VGA, control code mode on).  Send it raw to the terminal.  It draws a
background of block graphics and dots, defines three pictures and moves four sprites over the background with HOLD / SHOW."""
import math
out = bytearray()
def w(b): out.extend(b if isinstance(b, (bytes, bytearray)) else b.encode('latin-1'))
def sp(*a): w(bytes([0x1c] + list(a)))
def define(n, rows, mask=None):
    wd = len(rows[0]); h = len(rows)
    def pack(rr):
        data = bytearray()
        for r in rr:
            for i in range(0, wd, 8):
                v = 0
                for b in range(8):
                    if i + b < wd and r[i + b] not in '. ': v |= 0x80 >> b
                data.append(v)
        return data
    sp(1, n, wd, h, 1 if mask else 0); w(pack(rows))
    if mask: w(pack(mask))
def pix(x, y): w(bytes([0x05, x, y]))

ball = ['....XXXX....', '..XXXXXXXX..', '.XXXXXXXXXX.', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', '.XXXXXXXXXX.', '..XXXXXXXX..', '....XXXX....']
ballm = ['....XXXX....', '..XXXXXXXX..', '.XXXXXXXXXX.', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', '.XXXXXXXXXX.', '..XXXXXXXX..', '....XXXX....']
# the ball has a dark spot (bit 0, mask 1) so the background is cut out
ball[3] = 'XXXX..X..XXX'
ship = ['.....XX.....', '....XXXX....', '...XXXXXX...', '.XXXXXXXXXX.', 'XXXXXXXXXXXX', 'XX..XXXX..XX', 'X....XX....X']
tank = ['....XX......', '....XXXXXX..', 'XXXXXXXXXXXX', 'XXXXXXXXXXXX', '.X.X.X.X.X.X']
w(b'\x0c'); w(b'\x1b[?25l')
w(bytes([0x0e, 0, 0x0f, 0])); w('Sprite layer demo: 1C commands (the text on row 0 is outside CLIP 2 23)')
# background: dots every 6 pixels
for y in range(12, 90, 6):
    for x in range(2, 158, 6): pix(x, y)
w(bytes([0x0e, 0, 0x0f, 12, 0x18, 0x80])); w(bytes([0xff, 0xa5, 0x5a, 0xc3]) * 10); w(bytes([0x18, 0x00]))
sp(8)                    # CLEAR
define(0, ball, ballm); define(1, ship); define(2, tank)
sp(0x0b, 2, 23)          # CLIP rows 2 to 23
# PLACE slot, picture, x + 32, y + 32, flags (coordinates on the wire have 32 added so a sprite can hang off the left or top)
sp(2, 0, 0, 32 + 40, 32 + 40, 0)
sp(2, 1, 1, 32 + 100, 32 + 60, 0)
sp(2, 2, 2, 32 + 20, 32 + 80, 0)
sp(2, 3, 1, 32 + 60, 32 + 30, 3)   # mirrored and flipped ship
for f in range(300):
    t = f / 20.0
    sp(9)                                                     # HOLD
    sp(3, 0, 32 + int(70 + 60 * math.sin(t)), 32 + int(45 + 30 * math.sin(t * 1.7)))
    sp(3, 1, 32 + int(70 + 70 * math.cos(t * 0.6)), 32 + 25)
    sp(3, 2, 32 + (f % 140), 32 + 80)
    if f % 10 == 0: sp(4, 1, 1)
    sp(5, 3, (f // 15 % 4) & 3)                               # FLAGS: mirror / flip cycle
    sp(0x0a)                                                  # SHOW
sp(7)                                                         # HIDE ALL
w(bytes([0x0e, 0, 0x0f, 23])); w('Done.  The background was not disturbed.')
open('demo_sprites.bin', 'wb').write(out)
print(len(out), 'bytes')
