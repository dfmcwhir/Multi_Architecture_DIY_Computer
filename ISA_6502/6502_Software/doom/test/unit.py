"""unit tests of the maths routines: call them in the emulator, compare with Python"""
import sys, os, re, random
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
mc = Machine('DOOM.BIN', speed=0)
mpu = mc.mpu; mem = mpu.memory
def call(name, a=0, x=0, y=0):
    mem[0x400] = 0x20; mem[0x401] = syms[name] & 255; mem[0x402] = syms[name] >> 8; mem[0x403] = 0xDB
    mpu.pc = 0x400; mpu.a, mpu.x, mpu.y = a, x, y; mpu.sp = 0xFF
    while mem[mpu.pc] != 0xDB: mpu.step()
def setw(n, v): mem[syms[n]] = v & 255; mem[syms[n] + 1] = 0  # 
def w16(lo, hi, v): mem[syms[lo]] = v & 255; mem[syms[hi]] = (v >> 8) & 255
def r16(lo, hi): return mem[syms[lo]] | mem[syms[hi]] << 8
rnd = random.Random(1); bad = 0
for i in range(3000):
    a = rnd.randrange(256); w = rnd.randrange(65536)
    w16('w_lo', 'w_hi', w); call('mul8x16', a)
    if r16('r_lo', 'r_hi') != (a * w) >> 8: bad += 1; print('mul8x16', a, w, r16('r_lo', 'r_hi'), (a * w) >> 8) if bad < 5 else 0
for i in range(2000):
    a = rnd.randrange(256); b = rnd.randrange(256)
    call('mul8', a, 0, b)
    if r16('m_lo', 'm_hi') != a * b: bad += 1; print('mul8', a, b)
print('bad', bad)
