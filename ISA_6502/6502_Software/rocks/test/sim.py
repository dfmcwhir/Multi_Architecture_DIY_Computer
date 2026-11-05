import os
"""Run a game .BIN in a 6502 emulator with a model of the PIC32 terminal's
control code mode (terminal v1.4: repeat attribute bits 3-6, 19 SET TILE,
0B SEND TILE, 16/17 sideways scrolling of the ESC [ t;b r region), and render the screen to PNG.

Set GARBAGE=<seed> to start with random RAM, as on the real board.
The ROM entry points from sbc_api.inc are trapped: CHRIN $FE00, CHROUT $FE03,
MENU $FE06 (where "quit" ends up), PADSTATE $FE12 and, after set_disk(),
SBC_LOAD $FE15.  The gamepad model also
types W A S D / space on a new press, like the real driver."""
import sys, os
sys.path.insert(0, os.environ.get('PY65', ''))
from py65.devices.mpu6502 import MPU
from PIL import Image, ImageDraw, ImageFont

CHRIN, CHROUT, MENU, PADSTATE, LOAD = 0xFE00, 0xFE03, 0xFE06, 0xFE12, 0xFE15
RESET = 0xF010
CPU_MHZ = int(os.environ.get('CPU_MHZ', '2'))     # the clock the game was built for
SPRITES = os.environ.get('NOSPRITES') is None    # a terminal with the sprite layer (1C)
PAD_KEYS = {0x10: ord('W'), 0x40: ord('A'), 0x20: ord('S'), 0x80: ord('D'), 0x01: ord(' ')}


class Term:
    """160x96 pixel grid (one pixel = one 2x4 block of a character cell) plus
    the text characters, drawn on top when rendering."""
    def __init__(self):
        self.pix = [[0] * 160 for _ in range(96)]
        self.txt = {}                # (col,row) -> (char, reverse)
        self.col = self.row = 0
        self.attr = 0
        self.pending = None
        self.args = []
        self.lit = False
        self.nbytes = 0
        self.errors = []
        self.tile_def = None
        self.esc = None                         # an ANSI sequence being read
        self.rv = False                         # reverse video (ESC [7m)
        self.top, self.bot = 0, 23              # the scrolling region (ESC [ t ; b r)
        self.scrolls = 0
        if not hasattr(self, 'tiles'):          # (they survive a clear screen)
            self.tiles = {}
            self.pool = bytearray(512)
        if not hasattr(self, 'pics'):           # the sprite layer's pictures (kept too)
            self.pics = {}
            self.reply = []                     # what the terminal sends back (IDENTIFY)
            self.sprites = SPRITES
        self.spr = None                         # a 1C command being read
        self.slots = [dict(on=0, n=0, x=0, y=0, f=0) for _ in range(16)]
        self.held = None                        # HOLD: the slots as they will be at SHOW
        self.clip = (0, 23)
        self.shows = 0
        self.syncs = getattr(self, 'syncs', 0)  # commands that wait for the vertical blank
        # STALE=1: model a terminal that saves the background of a cell when a
        # sprite covers it and puts that back when it leaves, missing drawing
        # done into the cell meanwhile (the worst case of the real firmware)
        self.stale = bool(os.environ.get('STALE'))
        self.cov = set(); self.saved = {}

    def put(self, b):
        self.nbytes += 1
        if self.spr is not None:                # 1C cmd args...: the sprite layer
            self.spr_byte(b)
            return
        if b == 0x1C and self.sprites and self.esc is None and self.pending is None and self.tile_def is None:
            self.spr = []
            return
        if self.esc is not None:                # ESC [ params final
            self.esc.append(b)
            if len(self.esc) == 1 and b != ord('['):
                self.esc = None; return
            if len(self.esc) > 1 and 0x40 <= b <= 0x7E:
                seq = bytes(self.esc[1:-1]).decode('latin-1'); self.esc = None
                if chr(b) == 'r':               # DECSTBM: the scrolling region
                    ps = [int(p) if p else 0 for p in seq.split(';')] if seq else []
                    t = ps[0] if len(ps) > 0 and ps[0] else 1
                    bt = ps[1] if len(ps) > 1 and ps[1] else 24
                    self.top, self.bot = t - 1, bt - 1
                    self.col = self.row = 0
                elif chr(b) == 'm':
                    for p in (seq.split(';') if seq else ['0']):
                        p = int(p or 0)
                        if p == 7: self.rv = True
                        elif p in (0, 27): self.rv = False
                else:
                    self.errors.append('unhandled ESC [%s%s' % (seq, chr(b)))
            return
        if b == 0x1B and self.pending is None and self.tile_def is None:
            self.esc = []
            return
        if self.tile_def is not None:           # 19 n c r data...: collecting the data
            self.tile_def[3].append(b)
            n, c, r, data = self.tile_def
            if len(data) == c * r:
                self.tile_def = None
                if c and r and n < 128 and (n + 1) * c * r <= 512:
                    self.tiles[n] = (c, r)          # the size; the data goes in the shared pool
                    self.pool[n * c * r:(n + 1) * c * r] = bytes(data)
                else:
                    self.errors.append('bad tile %d %dx%d' % (n, c, r))
            return
        if self.pending is not None:
            self.args.append(b)
            need = {0x02: 1, 0x05: 2, 0x06: 2, 0x0B: 1, 0x0E: 1, 0x0F: 1, 0x18: 1, 0x19: 3, 0x1A: 1}[self.pending]
            if len(self.args) < need:
                return
            c, a = self.pending, self.args
            self.pending, self.args = None, []
            if c == 0x05 or c == 0x06:
                x, y = a
                if x < 160 and y < 96:
                    self.pix[y][x] = 1 if c == 0x05 else 0
                    self.txt.pop((x // 2, y // 4), None)
                else:
                    self.errors.append('pixel off screen %d,%d' % (x, y))
            elif c == 0x0E:
                if a[0] > 79: self.errors.append('col %d' % a[0])
                self.col = a[0]
            elif c == 0x0F:
                if a[0] > 23: self.errors.append('row %d' % a[0])
                self.row = a[0]
            elif c == 0x18:
                self.attr = a[0]
                if a[0] & 7:
                    self.errors.append('attribute %02X: bits 0-2 pick big fonts (not reverse)' % a[0])
            elif c == 0x19:
                self.tile_def = [a[0], a[1], a[2], []]
                if a[1] * a[2] == 0:
                    self.tile_def = None; self.errors.append('empty tile')
            elif c == 0x1A:
                if not self.attr & 0x80:
                    self.errors.append('1A %02X in text mode' % a[0])
                self.draw_rep(a[0])
            elif c == 0x0B:
                self.send_tile(a[0])
            return
        if b in (0x02, 0x05, 0x06, 0x0B, 0x0E, 0x0F, 0x18, 0x19, 0x1A):
            self.pending = b
            return
        if b == 0x0C:
            self.__init__nbytes()
            return
        if b in (0x16, 0x17):
            self.scroll_side(1 if b == 0x16 else -1)
            return
        if b < 0x20 or b == 0x7F:
            self.errors.append('unexpected control %02X' % b)
            return
        self.draw_rep(b)

    def scroll_side(self, d):
        """16 / 17: the scrolling region one character left / right (with a
        repeat count of 0; 1-15 would be pixels, which this model doesn't do)"""
        px = (self.attr >> 3) & 15
        if px and px % 6:
            self.errors.append('16/17 by %d pixels (not whole characters) not modelled' % px)
            return
        self.scrolls += 1
        if any(t['on'] for t in self.slots): self.syncs += 1     # (it waits for the vertical blank)
        for k in range(px // 6 if px else 1):
            self.scroll_char(d)

    def scroll_char(self, d):
        if self.stale:                  # covered cells back, scroll, saved again
            cov = self.cov
            for (c, r) in cov:
                v = self.saved[(c, r)]
                for i in range(8): self.pix[r * 4 + i // 2][c * 2 + (i & 1)] = v[i]
            self._scroll(d)
            for (c, r) in cov:
                self.saved[(c, r)] = [self.pix[r * 4 + i // 2][c * 2 + (i & 1)] for i in range(8)]
            return
        self._scroll(d)

    def _scroll(self, d):
        for y in range(self.top * 4, self.bot * 4 + 4):
            row = self.pix[y]
            self.pix[y] = (row[2:] + [0, 0]) if d > 0 else ([0, 0] + row[:-2])
        moved = {}
        for (c, r), v in self.txt.items():
            if self.top <= r <= self.bot:
                c2 = c - d
                if 0 <= c2 < 80: moved[(c2, r)] = v
            else: moved[(c, r)] = v
        self.txt = moved

    def rep(self):
        return max(1, (self.attr >> 3) & 15)

    def draw_rep(self, b):
        for i in range(self.rep()):
            self.draw(b)

    def send_tile(self, n):
        if not self.attr & 0x80:
            self.errors.append('tile %d sent in text mode' % n)
        if n not in self.tiles:
            self.errors.append('tile %d not defined' % n); return
        c, r = self.tiles[n]
        data = self.pool[n * c * r:(n + 1) * c * r]
        col0, row0 = self.col, self.row
        if row0 + r > 24:
            self.errors.append('tile %d runs off the bottom' % n)
        for k in range(self.rep()):
            for j in range(r):
                for i in range(c):
                    x = col0 + k * c + i
                    if x > 79: continue
                    self.col, self.row = x, row0 + j
                    if self.row <= 23: self.draw(data[j * c + i], wrap=False)
        if col0 + self.rep() * c > 80:
            self.errors.append('tile %d runs off the right edge' % n)
        self.col, self.row = min(col0 + self.rep() * c, 79), row0   # (at the edge: position unclear)

    # ---- the sprite layer (control code 1C; see the sprite layer spec) ----
    NARGS = {1: 4, 2: 5, 3: 3, 4: 2, 5: 2, 6: 1, 7: 0, 8: 0, 9: 0, 10: 0, 11: 2, 12: 0, 13: 0}
    def spr_byte(self, b):
        c = self.spr
        c.append(b)
        cmd = c[0]
        need = 1 + self.NARGS.get(cmd, 0)
        if cmd == 1 and len(c) >= 5:
            n, w, h, f = c[1:5]
            if not (1 <= w <= 32 and 1 <= h <= 32):
                self.errors.append('DEFINE %d: size %dx%d' % (n, w, h)); self.spr = None; return
            need = 5 + h * ((w + 7) // 8) * (2 if f & 1 else 1)
        if len(c) < need: return
        self.spr = None
        a = c[1:]
        sl = self.held if self.held is not None else self.slots
        if cmd == 1:
            n, w, h, f = a[:4]; d = a[4:]; nb = (w + 7) // 8
            bits = [d[r * nb:(r + 1) * nb] for r in range(h)]
            mask = [d[(h + r) * nb:(h + r + 1) * nb] for r in range(h)] if f & 1 else bits
            if n < 64: self.pics[n] = (w, h, bits, mask)
            else: self.errors.append('DEFINE picture %d' % n)
            if sum(self.pic_bytes(k) for k in self.pics) > 1280: self.errors.append('sprite pool over 1280 bytes')
        elif cmd in (2, 3, 4, 5, 6):
            s = a[0]
            if s > 15: self.errors.append('slot %d' % s); return
            t = sl[s]
            if cmd == 2:
                t.update(n=a[1], x=a[2] - 32, y=a[3] - 32, f=a[4], on=0 if a[4] & 0x80 else 1)
                if a[1] not in self.pics: self.errors.append('PLACE: picture %d not defined' % a[1])
            elif cmd == 3: t.update(x=a[1] - 32, y=a[2] - 32)
            elif cmd == 4: t['n'] = a[1]
            elif cmd == 5: t.update(f=a[1], on=0 if a[1] & 0x80 else 1)
            else: t['on'] = 0
        elif cmd == 7:
            for t in sl: t['on'] = 0
        elif cmd == 8:
            self.pics = {}; self.held = None
            for t in self.slots: t.update(on=0, n=0, x=0, y=0, f=0)
        elif cmd == 9:
            if self.held is None: self.held = [dict(t) for t in self.slots]
        elif cmd == 10:
            if self.held is not None: self.slots, self.held = self.held, None
            self.shows += 1; self.syncs += 1
        elif cmd == 11:
            if a[0] <= a[1] <= 23: self.clip = (a[0], a[1])
            else: self.errors.append('CLIP %d %d' % tuple(a))
        elif cmd == 12:
            self.reply += [ord('S'), ord('P'), ord('1')]
        elif cmd == 13:                         # STATUS: "ST", lost (2 hex digits), peak (4)
            self.reply += list(b'ST000040')
            self.statuses = getattr(self, 'statuses', 0) + 1
        else:
            self.errors.append('unknown sprite command %02X' % cmd)
        if self.held is None:
            self.update_cover()
            if cmd in (2, 3, 4, 5, 6, 7): self.syncs += 1

    def cover_cells(self):
        out = set()
        for t in self.slots:
            if not t['on'] or t['n'] not in self.pics: continue
            w, h = self.pics[t['n']][:2]
            for r in range(max(self.clip[0], t['y'] // 4), min(self.clip[1], (t['y'] + h - 1) // 4) + 1):
                for c in range(max(0, t['x'] // 2), min(79, (t['x'] + w - 1) // 2) + 1):
                    out.add((c, r))
        return out

    def update_cover(self):
        if not self.stale: return
        new = self.cover_cells()
        for (c, r) in self.cov - new:
            v = self.saved.pop((c, r))
            for i in range(8): self.pix[r * 4 + i // 2][c * 2 + (i & 1)] = v[i]
        for (c, r) in new - self.cov:
            self.saved[(c, r)] = [self.pix[r * 4 + i // 2][c * 2 + (i & 1)] for i in range(8)]
        self.cov = new

    def pic_bytes(self, n):
        w, h, bits, mask = self.pics[n]
        return h * ((w + 7) // 8) * 2

    def visible(self):
        """the slots showing: (slot, picture, x, y, flags)"""
        return [(i, t['n'], t['x'], t['y'], t['f'] & 3) for i, t in enumerate(self.slots) if t['on']]

    def composite(self):
        """the screen as seen: the background with the sprites over it"""
        out = [row[:] for row in self.pix]
        y0, y1 = self.clip[0] * 4, self.clip[1] * 4 + 4
        for i, t in enumerate(self.slots):
            if not t['on'] or t['n'] not in self.pics: continue
            w, h, bits, mask = self.pics[t['n']]
            for v in range(h):
                for u in range(w):
                    x, y = t['x'] + u, t['y'] + v
                    if not (0 <= x < 160 and y0 <= y < y1): continue
                    uu = w - 1 - u if t['f'] & 1 else u
                    vv = h - 1 - v if t['f'] & 2 else v
                    if mask[vv][uu >> 3] >> (7 - (uu & 7)) & 1:
                        out[y][x] = bits[vv][uu >> 3] >> (7 - (uu & 7)) & 1
        return out

    def __init__nbytes(self):
        n, e, t, p, a, tb, sc = self.nbytes, self.errors, self.tiles, self.pool, self.attr, (self.top, self.bot), self.scrolls
        pics, reply = self.pics, self.reply
        self.__init__()
        self.nbytes, self.errors, self.tiles, self.pool, self.attr, (self.top, self.bot), self.scrolls = n, e, t, p, a, tb, sc
        self.pics, self.reply = pics, reply

    def draw(self, b, wrap=True):
        if self.col > 79 or self.row > 23:
            self.errors.append('draw outside screen %d,%d' % (self.col, self.row))
            return
        x0, y0 = self.col * 2, self.row * 4
        if self.attr & 0x80:            # block graphics
            self.txt.pop((self.col, self.row), None)
            for i in range(8):
                self.pix[y0 + i // 2][x0 + (i & 1)] = (b >> i) & 1
        else:
            for k in range(4):
                for j in range(2):
                    self.pix[y0 + k][x0 + j] = 0
            if b == 0x20 and not self.rv:
                self.txt.pop((self.col, self.row), None)
            else:
                self.txt[(self.col, self.row)] = (chr(b), self.rv)
        self.col += 1
        if self.col == 80 and wrap:
            self.col = 0
            self.row = min(self.row + 1, 23)

    def png(self, fn, scale=2):
        im = Image.new('RGB', (480, 288), (0, 0, 0))
        d = ImageDraw.Draw(im)
        pix = self.composite()
        for y in range(96):
            for x in range(160):
                if pix[y][x]:
                    d.rectangle([x * 3, y * 3, x * 3 + 2, y * 3 + 2], fill=(90, 255, 90))
        try:
            f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 10)
        except Exception:
            f = ImageFont.load_default()
        for (c, r), (ch, rv) in self.txt.items():
            if rv:
                d.rectangle([c * 6, r * 12, c * 6 + 5, r * 12 + 11], fill=(230, 230, 230))
            d.text((c * 6, r * 12), ch, font=f, fill=(0, 0, 0) if rv else (230, 230, 230))
        im = im.resize((480 * scale, 288 * scale), Image.NEAREST)
        im.save(fn)


class Machine:
    def __init__(self, binfile, speed=None, code_end=0x8000, ctrl=None):
        self.mpu = MPU()
        m = self.mpu.memory
        data = open(binfile, 'rb').read()
        for i, b in enumerate(data):
            m[0x500 + i] = b
        if os.environ.get('GARBAGE'):        # RAM is random at power-up on the real board
            import random
            rnd = random.Random(int(os.environ['GARBAGE']))
            for a in range(0x200, 0x8000):
                if not (0x500 <= a < 0x500 + len(data)):
                    m[a] = rnd.randrange(256)
        if speed is not None:
            m[0x503] = speed
        if ctrl is not None:
            m[0x504] = ctrl
        self.code_end = code_end
        self.pad = 0
        self.inject = True
        m[0xFFFC] = RESET & 0xFF
        m[0xFFFD] = RESET >> 8
        self.mpu.pc = 0x500
        self.term = Term()
        self.keys = []          # keys waiting to be read
        self.exited = False
        self.out_log = []
        self.disk = None        # folder of files for SBC_LOAD (None = ROM without it)
        self.loads = []

    def set_disk(self, folder):
        """give the ROM an SBC_LOAD entry that reads files from a host folder"""
        self.disk = folder
        self.mpu.memory[LOAD] = 0x4C            # the JMP the game looks for

    def do_load(self):
        """SBC_LOAD: A/Y = block (.word addr, .word max, name, 0)"""
        mpu, m = self.mpu, self.mpu.memory
        blk = mpu.a | (mpu.y << 8)
        addr = m[blk] | (m[blk + 1] << 8)
        mx = m[blk + 2] | (m[blk + 3] << 8)
        name = ''
        i = blk + 4
        while m[i] and len(name) < 12:
            name += chr(m[i]); i += 1
        path = os.path.join(self.disk, name)
        self.loads.append(name)
        if not os.path.isfile(path):
            mpu.a = 0x42                        # CH376 "file not found"
            mpu.p |= mpu.CARRY
        else:
            data = open(path, 'rb').read()[:mx]
            for j, b in enumerate(data):
                m[addr + j] = b
            mpu.x, mpu.y = len(data) & 0xFF, len(data) >> 8
            mpu.p &= ~mpu.CARRY
            mpu.processorCycles += 200000      # ~0.2 s for the disk
        self.rts()

    def set_pad(self, v):
        """buttons held; new presses also type characters, like the driver"""
        new = v & ~self.pad
        self.pad = v
        if self.inject:
            for bit, ch in PAD_KEYS.items():
                if new & bit:
                    self.keys.append(ch)

    def rts(self):
        mpu = self.mpu
        lo = mpu.memory[0x100 + ((mpu.sp + 1) & 0xFF)]
        hi = mpu.memory[0x100 + ((mpu.sp + 2) & 0xFF)]
        mpu.sp = (mpu.sp + 2) & 0xFF
        mpu.pc = ((hi << 8) | lo) + 1
        mpu.processorCycles += 6

    def run(self, cycles, poll=None):
        mpu = self.mpu
        end = mpu.processorCycles + cycles
        while mpu.processorCycles < end and not self.exited:
            pc = mpu.pc
            if pc == CHROUT:
                self.term.put(mpu.a)
                if self.term.reply:
                    self.keys += self.term.reply; self.term.reply = []
                mpu.processorCycles += 87 * CPU_MHZ   # ~ one byte at 115200 baud
                self.rts()
            elif pc == CHRIN:
                if poll:
                    poll(self)
                if self.keys:
                    mpu.a = self.keys.pop(0)
                    mpu.p |= mpu.CARRY
                else:
                    mpu.p &= ~mpu.CARRY
                self.rts()
            elif pc == PADSTATE:
                mpu.a = self.pad
                self.rts()
            elif pc == LOAD and self.disk:
                self.do_load()
            elif pc == MENU or pc == RESET:
                self.exited = True
            elif not (0x500 <= pc < self.code_end):
                raise RuntimeError('PC wandered to %04X' % pc)
            else:
                mpu.step()

    def sym(self, name, lst='invaders.map'):
        raise NotImplementedError
