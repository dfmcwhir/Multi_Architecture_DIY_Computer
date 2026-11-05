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
cnt = {n: 0 for n in sys.argv[1:]}
addr = {syms[n]: n for n in cnt}
for h in os.environ.get('HEX','').split():
    cnt[h]=0; addr[int(h,16)]=h
orig = mpu.step
def step():
    n = addr.get(mpu.pc)
    if n: cnt[n] += 1
    orig()
mpu.step = step
seq = list('DDDDWWWW')
def poll(m):
    if not m.keys and seq and mpu.processorCycles % 3 == 0: m.keys.append(ord(seq.pop(0)))
mc.run(6_000_000, poll)
print(cnt)
