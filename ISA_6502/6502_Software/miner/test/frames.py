"""frame times in real ms (at the clock in CPU_MHZ) and bytes a frame, playing
room 1 with its plan"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
import sim, model
from sim import Machine
HERE = os.path.dirname(os.path.abspath(__file__))
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open('miner.lbl')) if m}
mc = Machine('MINER.BIN', ctrl=1); mpu = mc.mpu; mem = mpu.memory
plan = [tuple(int(a) for a in l.split()) for l in open(os.path.join(HERE, 'plans', 'room1.txt'))]
mc.run(3_000_000 * sim.CPU_MHZ); mc.set_pad(0x08); mc.run(100_000); mc.set_pad(0)
cnt = [0]
def pad_fn(m):
    ret = mem[0x100 + ((m.mpu.sp + 3) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 4) & 0xFF)] << 8
    if not (syms['read_input'] <= ret < syms['handle_key']): return m.pad
    d, j = plan[cnt[0]] if cnt[0] < len(plan) else (0, 0)
    cnt[0] += 1
    return model.pad_of(d, j)
mc.pad_fn = pad_fn
marks = []; nb = []; orig = mpu.step
def step():
    if mpu.pc == syms['game_loop']: marks.append(mpu.processorCycles); nb.append(mc.term.nbytes)
    orig()
mpu.step = step
while cnt[0] < min(len(plan), 300): mc.run(100_000)
ms = sorted((b - a) / (1000 * sim.CPU_MHZ) for a, b in zip(marks[5:], marks[6:]))
bb = sorted(b - a for a, b in zip(nb[5:], nb[6:]))
print('CPU_MHZ=%d: %d frames, frame ms: median %.1f, 10%% %.1f, 90%% %.1f, max %.1f; bytes a frame: median %d, max %d' % (
    sim.CPU_MHZ, len(ms), ms[len(ms)//2], ms[len(ms)//10], ms[len(ms)*9//10], ms[-1], bb[len(bb)//2], bb[-1]))
