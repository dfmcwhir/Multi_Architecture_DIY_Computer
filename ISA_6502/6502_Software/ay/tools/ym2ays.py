#!/usr/bin/env python3
"""ym2ays.py - convert .YM music files (Atari ST / Amstrad / Spectrum chip
music) into .AYS files that YMPLAY on the 6502 SBC streams from the USB
drive.

    python ym2ays.py SONG.YM [OUT.AYS]        one file
    python ym2ays.py *.ym                     many (each to NAME.AYS)

Why a conversion: .YM files are packed with LHA (-lh5-), and YM5/YM6 keep
each register's values for the whole song together ("interleaved").  Both
need far more RAM than the SBC has to undo.  An .AYS file is the plain
register values, 14 bytes a frame, in playing order, so the 6502 just reads
and writes them.

Reads YM2!, YM3!, YM3b, YM5! and YM6!, packed or not.  The register values
are rescaled from the song's chip clock to the SBC's (2 MHz unless --clock
says otherwise), and the bits the YM5/YM6 special effects (SID voices,
digidrums, sync buzzer) keep in unused register bits are cleared: those
effects need a CPU timer interrupt thousands of times a second, so they are
left out, and songs that rely on them sound plainer.

The .AYS format (all numbers little endian):
    0   "AYS1"
    4   frames a second (usually 50)
    5   0 (reserved)
    6   number of frames (4 bytes)
    10  loop frame: where the song goes back to at the end (4 bytes)
    14  0, 0
    16  title, 32 bytes, padded with zeros
    48  author, 32 bytes, padded with zeros
    80  zeros up to 128
    128 the frames: registers 0-13 each; register 13 (envelope shape) is
        $FF when it is not to be written (writing it restarts the envelope)
"""
import glob, os, re, struct, sys

AYS_CLOCK = 2000000                 # the SBC's AY-3-8910 clock (--clock to change)


# ---- LHA -lh5- decoding (the standard LZSS + static Huffman scheme) ---------------
class BitReader:
    def __init__(self, data):
        self.data, self.pos, self.buf, self.n = data, 0, 0, 0

    def peek(self, k):
        while self.n < k:
            b = self.data[self.pos] if self.pos < len(self.data) else 0
            self.pos += 1
            self.buf = (self.buf << 8) | b
            self.n += 8
        return (self.buf >> (self.n - k)) & ((1 << k) - 1)

    def get(self, k):
        if k == 0: return 0
        v = self.peek(k)
        self.n -= k
        self.buf &= (1 << self.n) - 1
        return v


class Huffman:
    """canonical code from code lengths; decode one bit at a time"""
    def __init__(self, lengths, single=None):
        self.single = single
        self.codes = {}
        if single is not None: return
        code = 0
        for ln in range(1, 17):
            for sym, l in enumerate(lengths):
                if l == ln:
                    self.codes[(ln, code)] = sym
                    code += 1
            code <<= 1

    def decode(self, br):
        if self.single is not None: return self.single
        code = ln = 0
        while ln < 17:
            code = (code << 1) | br.get(1); ln += 1
            s = self.codes.get((ln, code))
            if s is not None: return s
        raise ValueError('bad Huffman code')


def lh5_decode(data, size):
    NC, NT, NP, CBIT, TBIT, PBIT = 510, 19, 14, 9, 5, 4
    br = BitReader(data)
    out = bytearray()

    def read_pt(nn, nbit, special):
        n = br.get(nbit)
        if n == 0:
            return Huffman(None, br.get(nbit))
        lens = []
        while len(lens) < n:
            c = br.peek(3)
            if c == 7:
                br.get(3)
                while br.get(1): c += 1
            else:
                br.get(3)
            lens.append(c)
            if len(lens) == special:
                lens += [0] * br.get(2)
        return Huffman(lens + [0] * (nn - len(lens)))

    def read_c(pt):
        n = br.get(CBIT)
        if n == 0:
            return Huffman(None, br.get(CBIT))
        lens = []
        while len(lens) < n:
            c = pt.decode(br)
            if c == 0: lens += [0]
            elif c == 1: lens += [0] * (br.get(4) + 3)
            elif c == 2: lens += [0] * (br.get(CBIT) + 20)
            else: lens.append(c - 2)
        return Huffman(lens + [0] * (NC - len(lens)))

    left = 0
    while len(out) < size:
        if left == 0:
            left = br.get(16)
            pt = read_pt(NT, TBIT, 3)
            ct = read_c(pt)
            pp = read_pt(NP, PBIT, -1)
        left -= 1
        c = ct.decode(br)
        if c < 256:
            out.append(c)
        else:
            length = c - 253
            j = pp.decode(br)
            if j: j = (1 << (j - 1)) + br.get(j - 1)
            start = len(out) - j - 1
            for k in range(length):
                out.append(out[start + k])
    return bytes(out[:size])


def unpack(raw):
    """a .YM file's contents: the LHA archive's one member unpacked, or the file
    as it is when it isn't packed"""
    if len(raw) > 22 and raw[2:7] == b'-lh5-':
        hsize, level = raw[0], raw[20]
        packed, original = struct.unpack_from('<II', raw, 7)
        if level == 0:
            start = hsize + 2
        elif level == 1:
            start = hsize + 2
            nxt = struct.unpack_from('<H', raw, start - 2)[0]
            while nxt:
                packed -= nxt
                start += nxt
                nxt = struct.unpack_from('<H', raw, start - 2)[0]
        else:
            raise ValueError('LHA header level %d is not supported' % level)
        return lh5_decode(raw[start:start + packed], original)
    if len(raw) > 7 and raw[2:5] == b'-lh' and raw[6:7] == b'-':
        raise ValueError('packed with %s, only -lh5- is supported' % raw[2:7].decode('latin-1'))
    return raw


# ---- YM formats ----------------------------------------------------------------
def cstr(b, i):
    j = b.index(0, i)
    return b[i:j].decode('latin-1'), j + 1


def parse_ym(data):
    """-> dict(frames=[16 register values], rate, clock, loop, title, author, kind)"""
    tag = data[:4]
    info = dict(title='', author='', rate=50, clock=2000000, loop=0, kind=tag.decode('latin-1'))
    if tag in (b'YM2!', b'YM3!', b'YM3b'):
        body = data[4:]
        n = len(body) // 14
        if tag == b'YM3b':
            n = (len(body) - 4) // 14
            info['loop'] = struct.unpack_from('<I', body, n * 14)[0]
        regs = [body[r * n:(r + 1) * n] for r in range(14)]      # interleaved
        frames = [[regs[r][f] for r in range(14)] + [0, 0] for f in range(n)]
        if tag == b'YM2!':                                        # Mad Max: its own envelope use
            for fr in frames:
                if fr[13] != 0xFF:
                    fr[12], fr[13] = 0, 10
                if fr[10] & 0x80: fr[10] = 0                      # (a digidrum: left out)
        info['frames'] = frames
        return info
    if tag in (b'YM5!', b'YM6!'):
        if data[4:12] != b'LeOnArD!':
            raise ValueError('not a YM file (no LeOnArD! mark)')
        n, attr, ndrum, clock, rate, loop, skip = struct.unpack_from('>IIHIHIH', data, 12)
        i = 34 + skip
        for d in range(ndrum):
            sz = struct.unpack_from('>I', data, i)[0]
            i += 4 + sz
        info['title'], i = cstr(data, i)
        info['author'], i = cstr(data, i)
        _, i = cstr(data, i)                                      # comment
        body = data[i:]
        info.update(clock=clock, rate=rate or 50, loop=loop)
        if attr & 1:                                              # interleaved
            frames = [[body[r * n + f] for r in range(16)] for f in range(n)]
        else:
            frames = [list(body[f * 16:(f + 1) * 16]) for f in range(n)]
        info['frames'] = frames
        return info
    if tag == b'YM4!':
        raise ValueError('YM4 files are not supported (an old format; YM5 replaced it)')
    raise ValueError('not a YM2/YM3/YM5/YM6 file (it starts %r)' % tag)


def to_chip(fr, scale):
    """one frame's registers for the SBC's AY: periods rescaled to its clock,
    the effect bits cleared, the I/O ports left as inputs"""
    def per(v, mx):
        if scale == 1.0: return v
        return max(0, min(mx, int(round(v * scale))))
    out = [0] * 14
    for ch in range(3):
        p = per(fr[ch * 2] | (fr[ch * 2 + 1] & 0x0F) << 8, 4095)
        out[ch * 2], out[ch * 2 + 1] = p & 0xFF, p >> 8
    out[6] = per(fr[6] & 0x1F, 31)
    out[7] = fr[7] & 0x3F
    for r in (8, 9, 10): out[r] = fr[r] & 0x1F
    e = per(fr[11] | fr[12] << 8, 65535)
    out[11], out[12] = e & 0xFF, e >> 8
    out[13] = 0xFF if fr[13] == 0xFF else fr[13] & 0x0F
    return out


def convert(raw, clock=AYS_CLOCK):
    info = parse_ym(unpack(raw))
    scale = clock / info['clock'] if info['clock'] else 1.0
    frames = [to_chip(f, scale) for f in info['frames']]
    n = len(frames)
    loop = info['loop'] if info['loop'] < n else 0
    def field(s):
        s = s.encode('ascii', 'replace')[:32]
        return s + bytes(32 - len(s))
    head = b'AYS1' + bytes([min(255, info['rate']), 0]) + struct.pack('<II', n, loop) + bytes(2)
    head += field(info['title']) + field(info['author'])
    head += bytes(128 - len(head))
    return head + bytes(b for f in frames for b in f), info, n


def ays_name(path):
    """an 8.3 name for the USB drive: letters and digits of the file's name"""
    base = re.sub(r'[^A-Z0-9]', '', os.path.splitext(os.path.basename(path))[0].upper())[:8] or 'SONG'
    return base + '.AYS'


def main(argv):
    clock = AYS_CLOCK
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == '--clock':
            clock = int(argv[i + 1]); i += 2
        elif any(c in argv[i] for c in '*?'):   # (Windows doesn't expand *.ym)
            args += sorted(glob.glob(argv[i])) or [argv[i]]; i += 1
        else:
            args.append(argv[i]); i += 1
    if not args:
        print(__doc__); return 1
    if len(args) == 2 and args[1].upper().endswith('.AYS'):
        pairs = [(args[0], args[1])]
    else:
        pairs, used = [], set()
        for a in dict.fromkeys(args):               # (each once)
            nm = ays_name(a)
            base, k = nm[:-4], 2
            while nm in used:                       # two songs, one 8 letter name:
                nm = base[:8 - len(str(k))] + str(k) + '.AYS'   # VIRTUALE, VIRTUAL2
                k += 1
            used.add(nm)
            pairs.append((a, os.path.join(os.path.dirname(a), nm)))
    bad = 0
    for src, dst in pairs:
        try:
            out, info, n = convert(open(src, 'rb').read(), clock)
        except Exception as e:
            print('%s: %s' % (src, e)); bad += 1; continue
        open(dst, 'wb').write(out)
        secs = n // max(1, info['rate'])
        print('%s -> %s: %s, %d frames at %d Hz (%d:%02d), chip clock %d Hz, "%s" by %s' % (
            src, dst, info['kind'], n, info['rate'], secs // 60, secs % 60, info['clock'], info['title'], info['author']))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
