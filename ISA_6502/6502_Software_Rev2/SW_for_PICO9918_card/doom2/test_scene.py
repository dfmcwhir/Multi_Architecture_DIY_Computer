"""DOOM2: put the player somewhere, facing an angle, and take a picture.
   python3 test_scene.py X Y ANGLE(0-1023) name [fire]"""
import sys
sys.path.insert(0, '/home/claude/tools')
import emu6502
x, y, a, name = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
m = emu6502.Machine(4); m.load('DOOM2.BIN', 0x800); L = m.load_labels('doom2.lbl')
def v(n, i=0): return m.mem[L[n] + i]
m.run(frames=60); m.pad = 0x08; m.run(frames=2); m.pad = 0; m.run(frames=40)
m.mem[L['px_hi']] = x; m.mem[L['py_hi']] = y; m.mem[L['px_lo']] = 0x80; m.mem[L['py_lo']] = 0x80
m.mem[L['pa_lo']] = a & 255; m.mem[L['pa_hi']] = a >> 8
for i in range(32):               # (things stay where they are)
    if m.mem[L['t_state'] + i] in (2, 3): m.mem[L['t_state'] + i] = 1
m.mem[L['force']] = 1
if len(sys.argv) > 5: m.pad = 0x01
m.run(frames=14); m.pad = 0
m.vdp.save_png('shots/%s.png' % name)
print('nvis', v('nvis'))
