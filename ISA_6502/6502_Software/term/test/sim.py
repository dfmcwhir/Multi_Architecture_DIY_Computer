"""sim.py - run TERM.BIN in a 6502 emulator (py65) with models of:

  the serial port   $7F14-$7F17 (6551): bytes written are logged with their
                    cycle time; what the BBS sends comes in through the ROM's
                    buffer, i.e. from SBC_CHRIN (trapped), at the baud rate
  the display card  $7F18-$7F1B (6551): bytes written are the screen's; the
                    keyboard's bytes arrive at set times and, as on the real
                    chip, a byte not read before the next one comes is lost
  VIA timer 2       one shot, IFR bit 5;  IER (the gamepad's bit) kept
  the AY card       $7F22/$7F23 writes logged
  the USB drive     $7F20/$7F21: YMPLAY's CH376 model (ay/test/sim.py), with a
                    host folder as the drive, when one is given

    PY65=path/to/py65 python3 test/test_term.py
"""
import os, sys
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices.mpu6502 import MPU
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ay', 'test'))
import importlib.util
_spec = importlib.util.spec_from_file_location('aysim', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ay', 'test', 'sim.py'))
_aysim = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_aysim)

CHRIN, CHROUT, MENU = 0xFE00, 0xFE03, 0xFE06
CPU_HZ = 2000000


class Via:
    def __init__(self, m):
        self.m = m
        self.t2_latch = 0
        self.t2_start = None
        self.t2_count = 0
        self.t2_flag_read = False
        self.acr = 0
        self.ier = 0x40             # (the ROM's gamepad timer interrupt on)
        self.regs = [0] * 16

    def t2_flag(self):
        if self.t2_start is None or self.t2_flag_read:
            return False
        return self.m.now() - self.t2_start >= self.t2_count + 2

    def read(self, r):
        if r == 0x8:
            self.t2_flag_read = True
            return 0
        if r == 0xB: return self.acr
        if r == 0xD: return 0xA0 if self.t2_flag() else 0
        if r == 0xE: return self.ier | 0x80
        return self.regs[r]

    def write(self, r, v):
        if r == 0x8:
            self.t2_latch = v
        elif r == 0x9:
            self.t2_count = self.t2_latch | (v << 8)
            self.t2_start = self.m.now()
            self.t2_flag_read = False
        elif r == 0xB:
            self.acr = v
        elif r == 0xD:
            if v & 0x20: self.t2_flag_read = True
        elif r == 0xE:
            if v & 0x80: self.ier |= v & 0x7F
            else: self.ier &= ~v & 0x7F
        else:
            self.regs[r] = v


class IOMem(list):
    def __init__(self, m):
        super().__init__([0] * 65536)
        self.m = m

    def __getitem__(self, a):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF:
            return self.m.io_read(a)
        return list.__getitem__(self, a)

    def __setitem__(self, a, v):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF:
            self.m.io_write(a, v)
            return
        list.__setitem__(self, a, v)


class Machine:
    def __init__(self, binfile, folder=None):
        self.mem = IOMem(self)
        self.ch = _aysim.CH376(self, folder, cwd='' if folder else None)
        self.hold_ptrs = False      # (a test sets the ROM's buffer pointers itself)
        self.mpu = MPU(memory=self.mem)
        for i, b in enumerate(open(binfile, 'rb').read()):
            list.__setitem__(self.mem, 0x500 + i, b)
        self.mpu.pc = 0x500
        self.via = Via(self)
        self.screen = []            # (cycle, byte) to the display
        self.modem = []             # (cycle, byte) to the serial port
        self.ay = []                # (register, value)
        self.ay_addr = 0
        self.mdm_ctrl = 0x1A        # (as the ROM leaves them)
        self.mdm_cmd = 0x89
        self.dsp_cmd = 0x89
        self.ctrl_log = []
        self.keys = []              # (cycle, byte) the keyboard sends
        self.kb_pending = None
        self.kb_lost = 0
        self.rx = []                # (cycle, byte) from the BBS
        self.rx_buf = []            # the ROM's buffer
        self.exited = False
        self.errors = []

    def now(self):
        return self.mpu.processorCycles

    # the keyboard: a byte arriving while one is unread is lost (overrun)
    def kb_update(self):
        while self.keys and self.keys[0][0] <= self.now():
            b = self.keys.pop(0)[1]
            if self.kb_pending is not None:
                self.kb_lost += 1
            self.kb_pending = b

    def type_at(self, secs, s, gap=0.05):
        """keys typed (gap seconds apart)"""
        t = int(secs * CPU_HZ)
        for ch in s:
            self.keys.append((t, ord(ch) if isinstance(ch, str) else ch))
            t += int(gap * CPU_HZ)
        self.keys.sort(key=lambda k: k[0])

    def burst_at(self, secs, s):
        """bytes from the display card back to back at 115200 (87 us apart),
        as the terminal sends a cursor position report or an arrow key"""
        t = int(secs * CPU_HZ)
        for ch in s:
            self.keys.append((t, ord(ch) if isinstance(ch, str) else ch))
            t += int(CPU_HZ * 10 / 115200)
        self.keys.sort(key=lambda k: k[0])

    def bbs_at(self, secs, data, baud=1200):
        t = int(secs * CPU_HZ)
        for b in (data.encode('latin-1') if isinstance(data, str) else data):
            self.rx.append((t, b))
            t += int(CPU_HZ * 10 / baud)
        self.rx.sort(key=lambda k: k[0])

    def io_read(self, a):
        if a == 0x7F19:
            self.kb_update()
            return 0x10 | (0x08 if self.kb_pending is not None else 0)
        if a == 0x7F18:
            self.kb_update()
            b = self.kb_pending
            self.kb_pending = None
            return b if b is not None else 0
        if a == 0x7F15: return 0x10
        if a == 0x7F20: return self.ch.read_data() if self.ch.folder else 0xFF
        if a == 0x7F21: return self.ch.read_status() if self.ch.folder else 0xFF
        if 0x7F00 <= a <= 0x7F0F: return self.via.read(a & 15)
        if a in (0x7F22, 0x7F23):
            self.errors.append('AY read')
        return 0xFF

    def io_write(self, a, v):
        if a == 0x7F18: self.screen.append((self.now(), v))
        elif a == 0x7F14: self.modem.append((self.now(), v))
        elif a == 0x7F17: self.mdm_ctrl = v; self.ctrl_log.append(v)
        elif a == 0x7F16: self.mdm_cmd = v
        elif a == 0x7F1A: self.dsp_cmd = v
        elif a == 0x7F20:
            if self.ch.folder: self.ch.write_data(v)
        elif a == 0x7F21:
            if self.ch.folder: self.ch.write_cmd(v)
        elif a == 0x7F22: self.ay_addr = v
        elif a == 0x7F23: self.ay.append((self.ay_addr, v))
        elif 0x7F00 <= a <= 0x7F0F: self.via.write(a & 15, v)

    def rts(self):
        mpu = self.mpu
        lo = list.__getitem__(self.mem, 0x100 + ((mpu.sp + 1) & 0xFF))
        hi = list.__getitem__(self.mem, 0x100 + ((mpu.sp + 2) & 0xFF))
        mpu.sp = (mpu.sp + 2) & 0xFF
        mpu.pc = ((hi << 8) | lo) + 1
        mpu.processorCycles += 6

    def run(self, secs):
        mpu = self.mpu
        end = self.now() + int(secs * CPU_HZ)
        while self.now() < end and not self.exited:
            pc = mpu.pc
            if pc == CHRIN:
                while self.rx and self.rx[0][0] <= self.now():
                    self.rx_buf.append(self.rx.pop(0)[1])
                if len(self.rx_buf) > 255:
                    self.errors.append('the ROM buffer overflowed')
                if self.rx_buf:
                    mpu.a = self.rx_buf.pop(0)
                    mpu.p |= mpu.CARRY
                else:
                    mpu.a = 0
                    mpu.p &= ~mpu.CARRY
                if not self.hold_ptrs:      # the ROM's pointers: what is waiting
                    list.__setitem__(self.mem, 0xE2, 0)
                    list.__setitem__(self.mem, 0xE3, len(self.rx_buf) & 0xFF)
                mpu.processorCycles += 40
                self.rts()
            elif pc == MENU:
                self.exited = True
            elif pc == CHROUT:
                self.errors.append('SBC_CHROUT used')
                self.rts()
            elif not (0x500 <= pc < 0x7000):
                raise RuntimeError('PC wandered to %04X' % pc)
            else:
                mpu.step()
        return self.exited

    def screen_bytes(self, after=0):
        return bytes(b for t, b in self.screen if t >= after * CPU_HZ)

    def modem_bytes(self, after=0):
        return bytes(b for t, b in self.modem if t >= after * CPU_HZ)
