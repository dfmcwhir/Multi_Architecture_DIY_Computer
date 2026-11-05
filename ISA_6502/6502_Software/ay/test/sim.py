"""sim.py - run AYTEST / YMPLAY in a 6502 emulator (py65) with models of the
SBC's I/O page:

  AY card   $7F22 address latch, $7F23 data (write only): every register write
            is logged with its cycle time; reading either address is an error
            (the card would latch on it)
  VIA       timer 2 (one shot, IFR bit 5), ACR and IER; the rest is RAM-like
  CH376     $7F20 data, $7F21 command/status: the commands ch376r.s uses, with
            the files of a host folder as the drive's top folder, and a delay
            before each interrupt (longer when a read crosses a 512 byte sector)

The ROM entry points are trapped: CHRIN $FE00 (keys from a script), CHROUT
$FE03 (logged), MENU $FE06 (ends the run).

    PY65=path/to/py65 python3 test/sim.py   (used by test_ay.py)
"""
import os, sys
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices.mpu6502 import MPU

CHRIN, CHROUT, MENU = 0xFE00, 0xFE03, 0xFE06
SBC_CWD = 0xFE18                # A/Y = the monitor's current folder (newer ROMs)
CWD_AT = 0x0300                 # (where this emulator keeps it)
CPU_HZ = 2000000


class Via:
    def __init__(self, m):
        self.m = m
        self.t2_latch = 0
        self.t2_start = None        # cycle T2 started
        self.t2_count = 0
        self.t2_flag_read = False
        self.acr = 0
        self.ier = 0
        self.regs = [0] * 16
        self.t2_starts = []

    def t2_flag(self):
        if self.t2_start is None or self.t2_flag_read:
            return False
        return self.m.now() - self.t2_start >= self.t2_count + 2

    def read(self, r):
        if r == 0x8:                # T2CL: clears the flag
            v = 0
            if self.t2_start is not None:
                v = (self.t2_count - (self.m.now() - self.t2_start)) & 0xFF
            self.t2_flag_read = True
            return v
        if r == 0x9:
            if self.t2_start is None: return 0
            return ((self.t2_count - (self.m.now() - self.t2_start)) >> 8) & 0xFF
        if r == 0xB: return self.acr
        if r == 0xD: return (0xA0 if self.t2_flag() else 0)
        if r == 0xE: return self.ier | 0x80
        return self.regs[r]

    def write(self, r, v):
        if r == 0x8:
            self.t2_latch = v
        elif r == 0x9:
            self.t2_count = self.t2_latch | (v << 8)
            self.t2_start = self.m.now()
            self.t2_flag_read = False
            self.t2_starts.append((self.t2_start, self.t2_count))
        elif r == 0xB:
            self.acr = v
        elif r == 0xD:
            if v & 0x20: self.t2_flag_read = True
        elif r == 0xE:
            if v & 0x80: self.ier |= v & 0x7F
            else: self.ier &= ~v & 0x7F
        else:
            self.regs[r] = v


class CH376:
    """the CH376 in parallel mode, enough of it for ch376r.s.  The drive is a
    host folder (with sub-folders).  The chip keeps a current folder: names
    without a "/" are found there, and opening a folder makes it the current
    one.  Opening a file loses it, as on the real chip: then names without a
    "/" find nothing (and "*" lists nothing) until a folder is opened again.
    cwd: None = the drive starts unmounted (it needs SET_USB_MODE and
    DISK_MOUNT); a folder ('' the top) = mounted, in that folder; 'lost' =
    mounted, after a file was opened (as the monitor leaves it when it has
    loaded a program)."""
    def __init__(self, m, folder=None, latency=400, sector_latency=3000, cwd=None):
        self.m = m
        self.folder = folder
        self.latency, self.sector_latency = latency, sector_latency
        self.cmd = None
        self.args = []
        self.out = []
        self.int_at = None          # cycle the interrupt shows up
        self.status = 0
        self.name = b''
        self.file = None            # (data, pos)
        self.enum = None
        self.req = 0                # bytes left of a BYTE_READ
        self.chunk = b''
        self.mounted = cwd is not None and folder is not None
        self.cwd = None if cwd == 'lost' else (cwd or '')   # the current folder (None: lost)
        self.log = []
        self.opened = []            # the files opened (paths on the drive)
        self.written = []           # the files written (closed with their length)
        self.wtake = 0
        self.reads = 0

    def real(self, rel):
        return os.path.join(self.folder, *[p for p in rel.split('/') if p])

    def find(self, d, name):
        """the entry called name (any case) in drive folder d, or None"""
        try:
            for f in os.listdir(self.real(d)):
                if f.upper() == name.upper(): return f
        except OSError:
            pass
        return None

    def entries(self, d):
        """(name, is_folder) of drive folder d, as the chip lists them"""
        out = [('.', True), ('..', True)] if d else []
        for f in sorted(os.listdir(self.real(d))):
            out.append((f, os.path.isdir(os.path.join(self.real(d), f))))
        return out

    def interrupt(self, status, delay=None):
        self.status = status
        self.int_at = self.m.now() + (self.latency if delay is None else delay)

    def read_status(self):
        v = 0x80
        if self.int_at is not None and self.m.now() >= self.int_at:
            v = 0
        return v

    def write_cmd(self, c):
        self.cmd = c
        self.args = []
        self.out = []
        self.log.append(c)
        if c == 0x22:               # GET_STATUS
            self.out = [self.status]
            self.int_at = None
        elif c == 0x30:             # DISK_CONNECT
            self.interrupt(0x14 if self.folder else 0x15)
        elif c == 0x31:             # DISK_MOUNT: the top folder
            self.mounted = bool(self.folder)
            self.cwd = ''
            self.interrupt(0x14 if self.folder else 0x1F, 20000)
        elif c == 0x2F:             # SET_FILE_NAME
            self.name = b''
        elif c == 0x32:             # FILE_OPEN
            self.file_open()
        elif c == 0x33:             # FILE_ENUM_GO
            self.enum_next()
        elif c == 0x27:             # RD_USB_DATA0
            self.out = [len(self.chunk)] + list(self.chunk)
            self.chunk = b''
        elif c == 0x3B:             # BYTE_RD_GO
            self.next_chunk()
        elif c == 0x34:             # FILE_CREATE: a new (or emptied) file
            self.file_create()
        elif c == 0x2D:             # WR_REQ_DATA: how many bytes it takes now
            n = min(64, self.req)
            self.out = [n]
            self.wtake = n
        elif c == 0x3D:             # BYTE_WR_GO
            self.interrupt(0x1E if self.req else 0x14, 2000)

    def write_data(self, v):
        c = self.cmd
        self.args.append(v)
        if c == 0x06:
            self.out = [v ^ 0xFF]
        elif c == 0x15:             # SET_USB_MODE: the drive must be mounted again
            self.out = [0x51]
            self.mounted = False
            self.cwd = ''
        elif c == 0x2F:
            if v: self.name += bytes([v])
        elif c == 0x36:             # FILE_CLOSE (1: with the length: written)
            if v and self.file is not None and len(self.file) > 2:
                open(self.file[2], 'wb').write(bytes(self.file[0]))
                self.written.append(self.file[3])
            self.file = None
            self.req = 0
            self.interrupt(0x14)
        elif c == 0x39 and len(self.args) == 4:     # BYTE_LOCATE
            pos = self.args[0] | self.args[1] << 8 | self.args[2] << 16 | self.args[3] << 24
            if self.file is None:
                self.interrupt(0x41)
            else:
                self.file[1] = min(pos, len(self.file[0]))
                self.interrupt(0x14, 2000)
        elif c == 0x3C and len(self.args) == 2:     # BYTE_WRITE
            self.req = self.args[0] | self.args[1] << 8
            if self.file is None or len(self.file) < 3:
                self.interrupt(0x41); return
            self.interrupt(0x1E if self.req else 0x14, 2000)
        elif c == 0x2D:             # the data for WR_REQ_DATA
            if self.wtake > 0:
                self.file[0].append(v)
                self.wtake -= 1
                self.req -= 1
        elif c == 0x0C and v == 0x68:               # GET_FILE_SIZE: 4 bytes
            n = len(self.file[0]) if self.file is not None else 0
            self.out = list(n.to_bytes(4, 'little'))
        elif c == 0x3A and len(self.args) == 2:     # BYTE_READ
            self.req = self.args[0] | self.args[1] << 8
            self.next_chunk()

    def read_data(self):
        if self.out:
            return self.out.pop(0)
        return 0

    def file_open(self):
        if not self.mounted:
            self.interrupt(0x82)        # ERR_DISK_DISCON
            return
        name = self.name.decode('latin-1').replace('\\', '/')
        d = '' if name.startswith('/') else self.cwd
        if d is None:                   # (no current folder: nothing found)
            self.interrupt(0x42); return
        parts = [p for p in name.split('/') if p]
        for p in parts[:-1]:            # the folders on the way
            f = self.find(d, p)
            if f is None or not os.path.isdir(os.path.join(self.real(d), f)):
                self.interrupt(0x42); return
            d = d + '/' + f if d else f
        last = parts[-1] if parts else ''
        if last == '*':                 # list the folder
            self.enum = [(f, isd, d) for f, isd in self.entries(d)]
            self.enum_next()
            return
        if last == '':                  # "/": the top folder
            self.cwd = ''
            self.interrupt(0x41); return
        f = self.find(d, last)
        if f is None:
            self.interrupt(0x42); return
        path = os.path.join(self.real(d), f)
        if os.path.isdir(path):         # a folder: the current one now
            self.cwd = d + '/' + f if d else f
            self.interrupt(0x41)        # ERR_OPEN_DIR
            return
        self.cwd = None                 # a file: the current folder is lost
        self.file = [open(path, 'rb').read(), 0]
        self.opened.append((d + '/' + f) if d else f)
        self.interrupt(0x14, 3000)

    def file_create(self):
        if not self.mounted:
            self.interrupt(0x82); return
        name = self.name.decode('latin-1')
        d = '' if name.startswith('/') else self.cwd
        parts = [p for p in name.split('/') if p]
        if d is None or not parts:
            self.interrupt(0x42); return
        for p in parts[:-1]:
            f = self.find(d, p)
            if f is None: self.interrupt(0x42); return
            d = d + '/' + f if d else f
        f = self.find(d, parts[-1]) or parts[-1].upper()
        self.cwd = None
        self.file = [bytearray(), 0, os.path.join(self.real(d), f), (d + '/' + f) if d else f]
        self.interrupt(0x14, 5000)

    def enum_next(self):
        if not self.enum:
            self.enum = None
            self.interrupt(0x42)
            return
        f, isd, d = self.enum.pop(0)
        if f in ('.', '..'):
            base, ext = f, ''
        else:
            base, _, ext = f.upper().partition('.')
        ent = bytearray(32)
        ent[0:8] = base[:8].ljust(8).encode()
        ent[8:11] = ext[:3].ljust(3).encode()
        ent[11] = 0x10 if isd else 0x20
        if not isd:
            ent[28:32] = os.path.getsize(os.path.join(self.real(d), f)).to_bytes(4, 'little')
        self.chunk = bytes(ent)
        self.interrupt(0x1D)

    def next_chunk(self):
        data, pos = self.file
        n = min(64, self.req, len(data) - pos)
        if n <= 0:
            self.req = 0
            self.interrupt(0x14)
            return
        self.chunk = data[pos:pos + n]
        delay = self.sector_latency if pos % 512 == 0 else self.latency
        self.file[1] = pos + n
        self.req -= n
        self.reads += n
        self.interrupt(0x1D, delay)


class IOMem(list):
    def __init__(self, machine):
        super().__init__([0] * 0x10000)
        self.mach = machine

    def __getitem__(self, a):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF:
            return self.mach.io_read(a)
        return list.__getitem__(self, a)

    def __setitem__(self, a, v):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF:
            self.mach.io_write(a, v)
            return
        list.__setitem__(self, a, v)


class Machine:
    def __init__(self, binfile, folder=None, rom_cwd=None, **ch):
        self.mem = IOMem(self)
        self.mpu = MPU(memory=self.mem)
        data = open(binfile, 'rb').read()
        for i, b in enumerate(data):
            list.__setitem__(self.mem, 0x500 + i, b)
        self.mpu.pc = 0x500
        self.via = Via(self)
        self.ch = CH376(self, folder, **ch)
        self.rom_cwd = rom_cwd      # the ROM's SBC_CWD ($FE18): None = a ROM without it
        if rom_cwd is not None:
            list.__setitem__(self.mem, SBC_CWD, 0x4C)
            for i, c in enumerate(rom_cwd.encode() + b'\0'):
                list.__setitem__(self.mem, CWD_AT + i, c)
        else:
            list.__setitem__(self.mem, SBC_CWD, 0xFF)
        self.ay_addr = 0
        self.ay = [0] * 16
        self.ay_log = []            # (cycle, register, value)
        self.ay_reads = []          # registers read back
        self.errors = []
        self.out = bytearray()
        self.keys = []              # (cycle, key): typed when that time comes
        self.exited = False

    def now(self):
        return self.mpu.processorCycles

    def io_read(self, a):
        if a == 0x7F22:
            self.errors.append('read of the AY card at %04X (PC %04X)' % (a, self.mpu.pc))
            return 0
        if a == 0x7F23:             # (the new card: a register read back; the ports read $FF)
            self.ay_reads.append(self.ay_addr)
            return 0xFF if self.ay_addr in (14, 15) else self.ay[self.ay_addr & 15]
        if a == 0x7F20: return self.ch.read_data()
        if a == 0x7F21: return self.ch.read_status()
        if 0x7F00 <= a <= 0x7F0F: return self.via.read(a & 15)
        return 0xFF

    def io_write(self, a, v):
        if a == 0x7F22:
            self.ay_addr = v
        elif a == 0x7F23:
            if self.ay_addr > 15:
                self.errors.append('AY register %d' % self.ay_addr)
            else:
                self.ay[self.ay_addr] = v
                self.ay_log.append((self.now(), self.ay_addr, v))
        elif a == 0x7F20: self.ch.write_data(v)
        elif a == 0x7F21: self.ch.write_cmd(v)
        elif 0x7F00 <= a <= 0x7F0F: self.via.write(a & 15, v)

    def text(self):
        return self.out.decode('latin-1')

    def type_at(self, secs, s):
        for ch in s:
            self.keys.append((int(secs * CPU_HZ), ord(ch)))
        self.keys.sort(key=lambda k: k[0])

    def rts(self):
        mpu = self.mpu
        lo = list.__getitem__(self.mem, 0x100 + ((mpu.sp + 1) & 0xFF))
        hi = list.__getitem__(self.mem, 0x100 + ((mpu.sp + 2) & 0xFF))
        mpu.sp = (mpu.sp + 2) & 0xFF
        mpu.pc = ((hi << 8) | lo) + 1
        mpu.processorCycles += 6

    def run(self, secs, until=None):
        mpu = self.mpu
        end = mpu.processorCycles + int(secs * CPU_HZ)
        while mpu.processorCycles < end and not self.exited:
            pc = mpu.pc
            if pc == CHROUT:
                self.out.append(mpu.a)
                mpu.processorCycles += 87 * 2
                self.rts()
                if until and until(self): return True
            elif pc == CHRIN:
                if self.keys and self.keys[0][0] <= mpu.processorCycles:
                    mpu.a = self.keys.pop(0)[1]
                    mpu.p |= mpu.CARRY
                else:
                    mpu.p &= ~mpu.CARRY
                mpu.processorCycles += 30
                self.rts()
            elif pc == MENU:
                self.exited = True
            elif pc == SBC_CWD and self.rom_cwd is not None:
                mpu.a, mpu.y = CWD_AT & 255, CWD_AT >> 8
                mpu.processorCycles += 20
                self.rts()
            elif not (0x500 <= pc < 0x7000):
                raise RuntimeError('PC wandered to %04X' % pc)
            else:
                mpu.step()
        return self.exited
