"""slowterm.py - SPACE ROCKS against a terminal that takes time, as the real
PIC32 one does (sim.py's terminal does everything at once):

  - bytes arrive at 115200 baud and wait in a receive buffer of RXBUF bytes;
    when it is full, new bytes are dropped (as the firmware does)
  - each byte takes BYTE_US to handle; a SHOW (1C 0A) waits for the next
    vertical blank (60 Hz) and then takes SPR_MS for each sprite change since
    the HOLD; the IDENTIFY answer goes back when the terminal gets to it

It plays (the bot from play.py is not needed: the rocks move, saucers come)
and reports the bytes dropped, how far behind the terminal fell, and whether
the terminal's sprites still match the game's at the end.

    PY65=... python3 test/slowterm.py [SPR_MS] [FRAMES]
"""
import sys, os, re, collections
sys.path.insert(0, os.path.dirname(__file__))
import sim
from sim import Machine, CHRIN, CHROUT, MENU, PADSTATE, LOAD, RESET, CPU_MHZ

SPR_MS = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
FRAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 2500
RXBUF = int(os.environ.get('RXBUF', '6144'))
LOSS = float(os.environ.get('LOSS', '0'))       # each answer character lost with this chance
SLOW_EVERY = int(os.environ.get('SLOW_EVERY', '0'))   # every n-th SHOW takes SLOW_MS more
SLOW_MS = float(os.environ.get('SLOW_MS', '80'))
import random
rnd = random.Random(7)
BYTE_US = float(os.environ.get('BYTE_US', '15'))
HZ = CPU_MHZ * 1_000_000
VBL = HZ / 60


class SlowMachine(Machine):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.q = collections.deque()          # (arrival cycle, byte)
        self.t_free = 0                         # when the terminal is done with what it took
        self.late = []                          # (cycle, byte): answers on their way
        self.dropped = 0
        self.peak = 0
        self.prev = None
        self.in_cmd = None
        self.changes = 0
        self.lag_max = 0

    def term_until(self, now):
        while self.q and max(self.t_free, self.q[0][0]) <= now:
            t, b = self.q.popleft()
            start = max(self.t_free, t)
            cost = BYTE_US * HZ / 1e6
            if self.prev == 0x1C:
                if b in (2, 3, 4, 5, 6):
                    self.changes += 1
                if b == 0x0A:                   # SHOW: the next vertical blank, then the sprites
                    nxt = (int(start // VBL) + 1) * VBL
                    cost += (nxt - start) + self.changes * SPR_MS * HZ / 1000
                    self.changes = 0
                    self.nshow = getattr(self, 'nshow', 0) + 1
                    if SLOW_EVERY and self.nshow % SLOW_EVERY == 0:
                        cost += SLOW_MS * HZ / 1000
            self.prev = None if (self.prev == 0x1C) else b
            self.term.put(b)
            self.t_free = start + cost
            self.lag_max = max(self.lag_max, (self.t_free - t) / HZ)
            if self.term.reply:
                for c in self.term.reply:
                    if rnd.random() >= LOSS:
                        self.late.append((self.t_free, c))
                    else:
                        self.lost = getattr(self, 'lost', 0) + 1
                self.term.reply = []

    def run(self, cycles, poll=None):
        mpu = self.mpu
        end = mpu.processorCycles + cycles
        while mpu.processorCycles < end and not self.exited:
            pc = mpu.pc
            if pc == CHROUT:
                now = mpu.processorCycles
                self.term_until(now)
                if len(self.q) >= RXBUF:
                    self.dropped += 1
                else:
                    self.q.append((now, mpu.a))
                    self.peak = max(self.peak, len(self.q))
                mpu.processorCycles += 87 * CPU_MHZ
                self.rts()
            elif pc == CHRIN:
                now = mpu.processorCycles
                self.term_until(now)
                while self.late and self.late[0][0] <= now:
                    self.keys.append(self.late.pop(0)[1])
                if poll: poll(self)
                if self.keys:
                    mpu.a = self.keys.pop(0)
                    mpu.p |= mpu.CARRY
                else:
                    mpu.p &= ~mpu.CARRY
                self.rts()
            elif pc == PADSTATE:
                mpu.a = self.pad
                self.rts()
            elif pc == MENU or pc == RESET:
                self.exited = True
            elif not (0x500 <= pc < self.code_end):
                raise RuntimeError('PC wandered to %04X' % pc)
            else:
                mpu.step()


BIN = os.environ.get('BIN', 'ROCKS.BIN')
LBL = os.environ.get('LBL', 'rocks.lbl')
MAP = os.environ.get('MAP', 'rocks.map')
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open(LBL)) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open(MAP).read()).group(1), 16)
mc = SlowMachine(BIN, code_end=code_end)
mem = mc.mpu.memory
def v(n, i=0): return mem[syms[n] + i]
mc.run(3_000_000)
mc.keys.append(32)
mc.run(1_000_000)
mem[syms['lives']] = 99                  # (it plays on, whatever hits it)
f0 = v('frame')
frames = 0
last = f0
t0 = mc.mpu.processorCycles
while frames < FRAMES:
    mc.run(200_000)
    f = v('frame')
    frames += (f - last) & 255
    last = f
    mem[syms['lives']] = 99
    if os.environ.get('PROGRESS'):
        print('  %.1f s: frame %d, dropped %d, %d waiting, lost %d' % ((mc.mpu.processorCycles - t0) / HZ, frames, mc.dropped, len(mc.q), getattr(mc, 'lost', 0)), flush=True)
secs = (mc.mpu.processorCycles - t0) / HZ
mc.run(4_000_000 // 4)                 # (let it catch up)
mc.term_until(mc.mpu.processorCycles + 10 * HZ)
want = sorted((i, v('sl_n', i), v('sl_x', i) - 32, v('sl_y', i) - 32) for i in range(16) if v('sl_on', i))
got = sorted((i, n, x, y) for i, n, x, y, f in mc.term.visible())
print('sprite change cost %.1f ms: %d frames in %.1f s (%.1f a second); bytes dropped %d; the most waiting %d; '
      'the terminal at most %.2f s behind; errors %s' % (SPR_MS, frames, secs, frames / secs, mc.dropped, mc.peak, mc.lag_max, mc.term.errors[:3]))
print('answer characters lost %d' % getattr(mc, 'lost', 0))
print('the terminal\'s sprites at the end: %s (%d showing, the game has %d)' % ('right' if want == got else 'WRONG', len(got), len(want)))
