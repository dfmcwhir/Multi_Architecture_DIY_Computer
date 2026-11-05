import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from sim import Machine
syms = {}
for line in open('doom.lbl'):
    m = re.match(r'al ([0-9A-F]+) \.(\w+)', line)
    if m: syms[m.group(2)] = int(m.group(1), 16)
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open('doom.map').read()).group(1), 16)
mc = Machine('DOOM.BIN', speed=0, code_end=code_end)
if os.environ.get('DISK'): mc.set_disk('.')
mc.run(3_000_000)
print(mc.term.errors[:5], mc.loads)
mc.term.png('/tmp/claude-0/-home-claude/fa5eb55c-5553-5f15-b7c1-9f6f2d68bb44/scratchpad/d_title.png')
mc.keys.append(ord(' '))
mc.run(4_000_000)
print(mc.term.errors[:5], mc.loads, hex(mc.mpu.pc))
mc.term.png('/tmp/claude-0/-home-claude/fa5eb55c-5553-5f15-b7c1-9f6f2d68bb44/scratchpad/d_play.png')
