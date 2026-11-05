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
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(3_000_000)
mpu = mc.mpu
rv = syms['hud_update']; last = [None]; times = []; nb = [0]
orig = mpu.step
def step():
    if mpu.pc == rv:
        if last[0] is not None: times.append((mpu.processorCycles - last[0], mc.term.nbytes - nb[0], cur[0]))
        last[0] = mpu.processorCycles; nb[0] = mc.term.nbytes
    orig()
mpu.step = step
cur = ['-']
for k in sys.argv[1]:
    cur[0] = k
    if k != '-': mc.keys.append(ord(k))
    n = len(times)
    while len(times) == n: mc.run(20000)
for t, b, k in times: print(k, t, 'bytes', b)
