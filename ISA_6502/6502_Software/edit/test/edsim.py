"""edsim.py - EDIT.BIN in the emulator: ay/test/sim.py's machine (keys, the
CH376 with a host folder as the drive, SBC_CWD) and the screen model."""
import os, sys, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location('aysim', os.path.join(HERE, '..', '..', 'ay', 'test', 'sim.py'))
aysim = importlib.util.module_from_spec(spec); spec.loader.exec_module(aysim)
from screen import Screen
BIN = os.path.join(HERE, '..', 'EDIT.BIN')
HZ = aysim.CPU_HZ


class Ed:
    def __init__(self, folder, cwd='', **ch):
        self.m = aysim.Machine(BIN, folder, rom_cwd=cwd, **ch)
        self.s = Screen()
        self.n = 0
        self.run(0.3)

    def sync(self):
        self.s.feed(self.m.out[self.n:])
        self.n = len(self.m.out)

    def run(self, secs):
        self.m.run(secs)
        self.sync()

    def keys(self, s, secs=0.6, gap=0.002):
        t = self.m.now() / HZ
        for i, ch in enumerate(s):
            self.m.type_at(t + i * gap, ch)
        self.run(secs + len(s) * gap)

    def status(self):
        return self.s.row(23)

    def mem(self, a):
        return list.__getitem__(self.m.mem, a)

UP, DN, RT, LT = '\x1b[A', '\x1b[B', '\x1b[C', '\x1b[D'
HOME, END, PGUP, PGDN, DEL = '\x1b[H', '\x1b[F', '\x1b[5~', '\x1b[6~', '\x1b[3~'
def ctl(c): return chr(ord(c.upper()) - 64)
