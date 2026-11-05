import sys, os, re, math
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
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(3_000_000)
mc.keys.extend(map(ord, sys.argv[1] if len(sys.argv) > 1 else 'DDDDWWWW'))
mc.run(6_000_000)
px = v('px_hi') + v('px_lo') / 256; py = v('py_hi') + v('py_lo') / 256
pa = v('pa_hi') * 256 + v('pa_lo')
print('player %.2f %.2f angle %d (%.1f deg)' % (px, py, pa, pa * 360 / 1024))
for i in range(32):
    if v('t_state', i):
        x = v('t_x_hi', i) + v('t_x_lo', i) / 256; y = v('t_y_hi', i) + v('t_y_lo', i) / 256
        print(i, 'type', v('t_type', i), 'state', v('t_state', i), '%.2f %.2f' % (x, y))
print('nvis', v('nvis'), [(v('v_t', k), v('v_sx_lo', k) + 256 * v('v_sx_hi', k), v('v_h', k)) for k in range(v('nvis'))])
mc.term.png('/tmp/claude-0/-home-claude/fa5eb55c-5553-5f15-b7c1-9f6f2d68bb44/scratchpad/d_dbg.png')
