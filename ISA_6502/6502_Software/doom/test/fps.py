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
# profile: cycles spent in each top routine called from game_loop
names = os.environ.get('NAMES','read_input move_player do_use pickups update_things render_view render_things do_fire draw_gun present hud_update').split()
addr = {syms[n]: n for n in names}
mpu = mc.mpu
prof = {n: 0 for n in names}
cur = None; t0 = 0; depth_sp = None
frames = 0
start = mpu.processorCycles
orig_step = mpu.step
def step():
    global cur, t0, depth_sp, frames
    pc = mpu.pc
    if cur is None and pc in addr:
        cur = addr[pc]; t0 = mpu.processorCycles; depth_sp = mpu.sp
        if cur == 'render_view': frames += 1
    orig_step()
    if cur is not None and mpu.sp == (depth_sp + 2) & 0xFF and mpu.memory[pc] == 0x60:
        prof[cur] += mpu.processorCycles - t0; cur = None
mpu.step = step
keys = os.environ.get('KEYS', 'D'*0)
def poll(m):
    pass
seq=list(os.environ.get('SEQ','DDDWWW'))
def poll(m):
    if not m.keys and seq: m.keys.append(ord(seq.pop(0)))
mc.run(3_000_000, poll)
start=mpu.processorCycles; frames=0
for n in names: prof[n]=0
mc.run(3_000_000)
tot = mpu.processorCycles - start
print('frames', frames, 'cycles/frame', tot // max(frames, 1), 'fps %.2f' % (frames / (tot / 1e6)))
for n in names: print('%-14s %8d' % (n, prof[n] // max(frames, 1)))
print(mc.term.errors[:5], mc.term.nbytes)
mc.term.png('/tmp/claude-0/-home-claude/fa5eb55c-5553-5f15-b7c1-9f6f2d68bb44/scratchpad/d_fps.png')
