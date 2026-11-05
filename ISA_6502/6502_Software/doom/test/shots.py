"""screenshots of the sprites: put the player somewhere and look"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
OUT = sys.argv[1]
for name, x, y, a, extra in [('grunt', 9.5, 3.5, 0, 0), ('grunt_near', 11.0, 3.5, 0, 0), ('brute', 19.5, 11.5, 0, 0),
                             ('items', 1.5, 2.5, 40, 0), ('fire', 9.5, 3.5, 0, 1),
                             ('door', 2.5, 2.0, 40, 0), ('exit', 28.5, 11.0, 200, 0), ('start', 1.5, 1.5, 0, 0)]:
    mc = Machine('DOOM.BIN', speed=0, code_end=code_end); mc.set_disk('.')
    mem = mc.mpu.memory
    mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(1_500_000)
    for n, val in (('px', int(x * 256)), ('py', int(y * 256)), ('pa', a)):
        mem[syms[n + '_lo']] = val & 255; mem[syms[n + '_hi']] = val >> 8
    for i in range(32): # keep them asleep for the picture
        if mem[syms['t_state'] + i] == 1: mem[syms['t_timer'] + i] = 0
    mc.run(1_500_000)
    if extra:
        mc.keys.append(ord(' ')); f = mem[syms['frame']]
        while (mem[syms['frame']] - f) & 255 < 2: mc.run(2000)
        print('ammo', mem[syms['ammo']], 'gun_t', mem[syms['gun_t']])
    mc.term.png('%s/%s.png' % (OUT, name))
