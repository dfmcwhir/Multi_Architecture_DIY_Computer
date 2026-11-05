"""aysnd.py - the sound card and the VIA's timer 2 for the games' emulators.

    from aysnd import attach
    snd = attach(mpu)          # after loading the program into mpu.memory

The memory becomes a copy whose I/O page models:
  $7F22/$7F23  the AY-3-8910 card: register writes are logged in snd.log as
               (cycle, register, value); reading the card is an error
  $7F08-$7F0E  the VIA's timer 2 (one shot), ACR, IFR, IER
Everything else in $7Fxx reads back what was written, as before.

snd.channels(t0, t1) sums up what each channel played between two times;
snd.wav(path) renders the whole log to a .WAV file (an AY model: square
tones, the noise generator, the envelope, the volume table).
"""
import struct, wave


class SoundIO:
    def __init__(self, mpu):
        self.mpu = mpu
        self.addr = 0
        self.regs = [0] * 16
        self.log = []
        self.errors = []
        self.t2_latch = 0
        self.t2_start = None
        self.t2_count = 0
        self.t2_done = False
        self.acr = 0
        self.ier = 0

    def now(self):
        return self.mpu.processorCycles

    def t2_flag(self):
        if self.t2_start is None or self.t2_done:
            return False
        return self.now() - self.t2_start >= self.t2_count + 2

    def read(self, a, mem):
        if a in (0x7F22, 0x7F23):
            self.errors.append('read of the AY card at %04X (PC %04X)' % (a, self.mpu.pc))
            return 0
        if a == 0x7F08:
            self.t2_done = self.t2_done or self.t2_flag()
            if self.t2_start is None: return 0
            return (self.t2_count - (self.now() - self.t2_start)) & 0xFF
        if a == 0x7F09:
            if self.t2_start is None: return 0
            return ((self.t2_count - (self.now() - self.t2_start)) >> 8) & 0xFF
        if a == 0x7F0B: return self.acr
        if a == 0x7F0D:
            return (0xA0 if self.t2_flag() else 0) | (list.__getitem__(mem, a) & 0x40)
        if a == 0x7F0E: return self.ier | 0x80
        return None

    def write(self, a, v):
        if a == 0x7F22:
            self.addr = v
        elif a == 0x7F23:
            if self.addr > 15:
                self.errors.append('AY register %d' % self.addr)
            else:
                self.regs[self.addr] = v
                self.log.append((self.now(), self.addr, v))
        elif a == 0x7F08:
            self.t2_latch = v
        elif a == 0x7F09:
            self.t2_count = self.t2_latch | v << 8
            self.t2_start = self.now()
            self.t2_done = False
        elif a == 0x7F0B:
            self.acr = v
        elif a == 0x7F0E:
            if v & 0x80: self.ier |= v & 0x7F
            else: self.ier &= ~v & 0x7F
        else:
            return False
        return True

    # ---- looking at what was played ----------------------------------------------------
    def states(self):
        """(cycle, the 14 registers after that write) for each write"""
        r = [0] * 16
        r[7] = 0x3F
        out = []
        for t, reg, v in self.log:
            r[reg] = v
            out.append((t, list(r)))
        return out

    def heard(self, t0=0, t1=None):
        """for each channel, the set of (tone period, volume, tone on, noise on)
        heard (volume > 0) at the writes between t0 and t1"""
        res = [set(), set(), set()]
        for t, r in self.states():
            if t < t0 or (t1 is not None and t > t1): continue
            for c in range(3):
                vol = r[8 + c]
                tone = not (r[7] >> c & 1)
                noise = not (r[7] >> (c + 3) & 1)
                if (vol & 15 or vol & 16) and (tone or noise):
                    res[c].add((r[c * 2] | (r[c * 2 + 1] & 15) << 8, vol, tone, noise))
        return res

    def wav(self, path, rate=22050, clock=2000000, cpu=2000000, start=0, end=None):
        """render the log (from cycle start to end) to a mono .WAV"""
        VOL = [0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369, 0.1691,
               0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0]
        log = [e for e in self.log if e[0] >= start and (end is None or e[0] <= end)]
        if not log: return
        end = end if end is not None else log[-1][0] + cpu // 2
        r = [0] * 16
        r[7] = 0x3F
        for t, reg, v in self.log:
            if t >= start: break
            r[reg] = v
        nsamp = int((end - start) / cpu * rate)
        step = clock / 8 / rate               # chip ticks (clock / 8) a sample
        tone_c = [0.0] * 3; tone_o = [1] * 3
        noise_c = 0.0; lfsr = 1; noise_o = 1
        env_c = 0.0; env_pos = 0
        out = bytearray()
        li = 0
        def env_level(shape, pos):
            at, alt = shape >> 2 & 1, shape >> 1 & 1
            if pos < 16:
                return pos if at else 15 - pos
            if not shape & 8: return 0
            if shape & 1: return 15 if at ^ alt else 0
            up = at ^ (alt & (pos // 16) & 1)
            return pos % 16 if up else 15 - pos % 16
        for i in range(nsamp):
            t = start + i * cpu / rate
            while li < len(log) and log[li][0] <= t:
                _, reg, v = log[li]
                r[reg] = v
                if reg == 13:
                    env_pos = 0; env_c = 0.0
                li += 1
            # the generators count in ticks of clock / 8: a tone's half wave
            # is its period, a noise step 2 x its period, an envelope step
            # 2 x its period
            for c in range(3):
                per = (r[c * 2] | (r[c * 2 + 1] & 15) << 8) or 1
                tone_c[c] += step
                if tone_c[c] >= per:
                    n = int(tone_c[c] // per)
                    tone_c[c] -= n * per
                    tone_o[c] ^= n & 1
            np_ = 2 * ((r[6] & 31) or 1)
            noise_c += step
            while noise_c >= np_:
                noise_c -= np_
                bit = (lfsr ^ (lfsr >> 3)) & 1
                lfsr = (lfsr >> 1) | (bit << 16)
                noise_o = lfsr & 1
            ep = 2 * ((r[11] | r[12] << 8) or 1)
            env_c += step
            if env_c >= ep:
                n = int(env_c // ep)
                env_c -= n * ep
                env_pos += n
                if env_pos > 47: env_pos = 16 + (env_pos - 16) % 32
            s = 0.0
            for c in range(3):
                tone_off = r[7] >> c & 1
                noise_off = r[7] >> (c + 3) & 1
                o = (tone_o[c] | tone_off) & (noise_o | noise_off)
                v = r[8 + c]
                lv = env_level(r[13] & 15, env_pos) if v & 16 else v & 15
                s += VOL[lv] * o
            out += struct.pack('<h', max(-32767, min(32767, int((s / 3 - 0.2) * 40000))))
        w = wave.open(path, 'wb')
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(bytes(out))
        w.close()


class IOMem(list):
    def __init__(self, data, io):
        super().__init__(data)
        self.io = io

    def __getitem__(self, a):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF:
            v = self.io.read(a, self)
            if v is not None:
                return v
        return list.__getitem__(self, a)

    def __setitem__(self, a, v):
        if isinstance(a, int) and 0x7F00 <= a <= 0x7FFF and self.io.write(a, v):
            return
        list.__setitem__(self, a, v)


def attach(mpu):
    io = SoundIO(mpu)
    mpu.memory = IOMem(list(mpu.memory), io)
    return io
