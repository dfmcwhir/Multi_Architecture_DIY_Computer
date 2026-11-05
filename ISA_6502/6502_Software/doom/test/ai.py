import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
mc = Machine('DOOM.BIN', speed=0, code_end=code_end)
mc.set_disk('.')
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(2_000_000)
mem[syms['px_hi']] = 9; mem[syms['py_hi']] = 3
lf = -1
for k in range(400):
    mc.run(50000)
    if v('frame') != lf:
        lf = v('frame')
        print(lf, 'hp', v('health'), 'g1', v('t_state', 1), v('t_timer', 1), '%.2f,%.2f' % (v('t_x_hi',1)+v('t_x_lo',1)/256, v('t_y_hi',1)+v('t_y_lo',1)/256), 'edist', v('edist'))
