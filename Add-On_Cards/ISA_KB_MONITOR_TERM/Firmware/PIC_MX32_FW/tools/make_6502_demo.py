#!/usr/bin/env python3
"""Wraps a raw terminal stream (e.g. demo_sprites.bin) in a tiny 6502 program that sends every byte to the terminal through
SBC_CHROUT ($FE03) and then returns to the monitor ($FF00).  Load it with  L DEMOSPR 0500  and run it with  R .
usage: make_6502_demo.py input.bin output.bin"""
import sys
data = open(sys.argv[1], 'rb').read()
base, data_at = 0x0500, 0x0520
end = data_at + len(data)
assert end < 0xF000
code = bytes([
    0xAD, data_at & 255, data_at >> 8,      # 0500 LOOP: LDA data        (this operand is the pointer, it is incremented below)
    0x20, 0x03, 0xFE,                       # 0503       JSR SBC_CHROUT
    0xEE, 0x01, 0x05,                       # 0506       INC $0501
    0xD0, 0x03,                             # 0509       BNE +3
    0xEE, 0x02, 0x05,                       # 050B       INC $0502
    0xAD, 0x01, 0x05,                       # 050E       LDA $0501
    0xC9, end & 255,                        # 0511       CMP #<END
    0xD0, 0xEB,                             # 0513       BNE LOOP
    0xAD, 0x02, 0x05,                       # 0515       LDA $0502
    0xC9, end >> 8,                         # 0518       CMP #>END
    0xD0, 0xE4,                             # 051A       BNE LOOP
    0x4C, 0x00, 0xFF,                       # 051C       JMP $FF00  (the monitor)
])
code += bytes(data_at - base - len(code))
open(sys.argv[2], 'wb').write(code + data)
print(len(code + data), 'bytes, loads at $0500, ends at $%04X' % (end - 1))
