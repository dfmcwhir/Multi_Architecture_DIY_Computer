"""bytes sent to the terminal and cycles per frame for a fixed walk (turns, steps)"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
mc = Machine('DOOM.BIN', speed=0, code_end=code_end); mc.set_disk('.')
mpu = mc.mpu; mem = mpu.memory
mc.run(3_000_000); mc.keys.append(ord(' ')); mc.run(200_000)
seq = os.environ.get('SEQ', '-DDDDDDDDWWWWWWWWAAAAAAAAAAAADDDD....,,,,WWWW')
rv = syms['hud_update']; marks = []
orig = mpu.step
def step():
    if mpu.pc == rv: marks.append((mpu.processorCycles, mc.term.nbytes))
    orig()
mpu.step = step
for k in seq:
    if k != '-': mc.keys.append(ord(k))
    n = len(marks)
    while len(marks) == n: mc.run(20000)
n = len(marks)
while len(marks) == n: mc.run(20000)
ds = [(b[0] - a[0], b[1] - a[1]) for a, b in zip(marks, marks[1:])]
tb = sum(d[1] for d in ds[1:]); tc = sum(d[0] for d in ds[1:])
print('first frame bytes', ds[0][1], ' then %d frames: %d bytes (%.0f per frame), %.2f fps' % (len(ds) - 1, tb, tb / (len(ds) - 1), (len(ds) - 1) / (tc / 1e6)))
print('turning frames bytes', [d[1] for d in ds[1:10]])
print('errors', mc.term.errors[:3])
mc.term.png(os.environ.get('PNG', '/tmp/claude-0/-home-claude/fa5eb55c-5553-5f15-b7c1-9f6f2d68bb44/scratchpad/bytes.png'))
