"""DOOM2 screenshots: the title, then the first map a few steps in.
   python3 test_look.py"""
import sys
sys.path.insert(0, '/home/claude/tools')
import emu6502
m = emu6502.Machine(4); m.load('DOOM2.BIN', 0x800); L = m.load_labels('doom2.lbl')
def v(n, i=0): return m.mem[L[n] + i]
m.run(frames=60); m.vdp.save_png('shots/title.png')
m.pad = 0x08; m.run(frames=2); m.pad = 0
m.run(frames=60); m.vdp.save_png('shots/v0.png')
for k, p in enumerate([0x80, 0x10, 0x40, 0x10 | 0x01]):
    m.pad = p; m.run(frames=40); m.pad = 0; m.run(frames=10)
    m.vdp.save_png('shots/v%d.png' % (k + 1))
print('frame', v('frame'), 'nvis', v('nvis'), 'pc %04X' % m.cpu.pc)
