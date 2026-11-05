"""Shared set-up for the SUPER MOS BROS. tests: the emulator, the game's
labels, and a model of the view drawn in Python from the game's own state
(the map in RAM, the scroll position and the object table)."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import sim
from sim import Machine
import gen

# SOFT=1: test SMBSW.BIN, which draws the sprites itself; else SMB.BIN, whose
# sprites the terminal draws (its sprite layer, modelled in sim.py)
SOFT = bool(os.environ.get('SOFT'))
BIN, LBL, MAP = ('SMBSW.BIN', 'smbsw.lbl', 'smbsw.map') if SOFT else ('SMB.BIN', 'smb.lbl', 'smb.map')
syms = {m.group(2): int(m.group(1), 16) for m in (re.match(r'al ([0-9A-F]+) \.(\w+)', l) for l in open(LBL)) if m}
code_end = int(re.search(r'RODATA\s+([0-9A-F]+)', open(MAP).read()).group(1), 16)

# the sprite frames, in gen's order (the game mirrors them)
FRAMES = [gen.SPR[n] for n in gen.ORDER]
SP = {n: i for i, n in enumerate(gen.ORDER)}
TOP = [gen.tile_chars(t[3])[:4] for t in gen.TILES]
BOT = [gen.tile_chars(t[3])[4:] for t in gen.TILES]
(K_MOS, K_BUG, K_FLAT, K_SHELLY, K_SHELL, K_MUSH, K_COIN, K_ONEUP, K_FLOWER, K_FIRE,
 K_DRAGON, K_BREATH, K_OC, K_FISH, K_FAN, K_CLOUD, K_PRINCESS) = range(1, 18)
REVIVE = 160
KIND_PIC = {K_FLAT: 'AND_FLAT', K_SHELL: 'OR_SHELL', K_MUSH: 'MUSH', K_COIN: 'COINPOP', K_ONEUP: 'ONEUP', K_FLOWER: 'FLOWER',
            K_OC: 'OC', K_CLOUD: 'CLOUD', K_PRINCESS: 'PRINCESS'}

class Game:
    def __init__(self, pad=False, speed=None):
        self.mc = Machine(BIN, code_end=code_end, ctrl=1 if pad else 0, speed=speed)
        self.mem = self.mc.mpu.memory
        if os.environ.get('NOSCROLL'):            # the old way: redraw, no terminal scrolling
            self.mem[0x505] = 1
        for env, name in (('NOSHIFT', 'shift_marks'), ('NOHEAL', 'heal_add')):    # (to show what they fix)
            if os.environ.get(env) and name in syms: self.mem[syms[name]] = 0x60
        if os.environ.get('NOUNC'):               # (without hiding sprites over changed tiles)
            if 'unc_tiles' in syms: self.mem[syms['unc_tiles']] = 0x60
        if not os.environ.get('NODISK'):          # WORLD1.SMB ... from this folder
            self.mc.set_disk('.')
    def start_at(self, lvl, world=1):
        """make new_game start at level lvl (0..) of world (1..): its "sta lvl"
        and "sta wsrc" are pointed elsewhere"""
        a = syms['new_game']
        for name, val in (('lvl', lvl), ('wsrc', world), ('world', world)):
            l = syms[name]
            for i in range(a, a + 60):
                if self.mem[i] == 0x8D and self.mem[i + 1] | self.mem[i + 2] << 8 == l:
                    t = syms['tmp']
                    self.mem[i + 1], self.mem[i + 2] = t & 255, t >> 8
                    break
            else: raise RuntimeError('sta %s not found' % name)
            self.mem[l] = val
    def v(self, n, i=0): return self.mem[syms[n] + i]
    def s8(self, n, i=0):
        x = self.v(n, i); return x - 256 if x > 127 else x
    def w(self, n): return self.v(n) | self.v(n, 1) << 8
    def bcd(self, n, k=3): return int(''.join('%02X' % self.v(n, i) for i in reversed(range(k))))
    def ox(self, i): return self.v('o_xl', i) | self.v('o_xh', i) << 8
    def vx(self, i):
        x = self.v('o_vxl', i) | self.v('o_vxh', i) << 8
        return (x - 65536 if x > 32767 else x) / 256
    def vy(self, i):
        x = self.v('o_vyl', i) | self.v('o_vyh', i) << 8
        return (x - 65536 if x > 32767 else x) / 256
    def tile(self, c, r):
        return self.mem[syms['map'] + r * 256 + c] // 4 if 0 <= r < 11 else 0
    def want(self):
        """the game's view buffer (a page a row, by world column), at the scroll position"""
        s = self.w('scroll'); b = syms['wc']
        return [[self.mem[b + r * 256 + ((s + c) & 255)] for c in range(80)] for r in range(22)]
    def shown_bg(self):
        """the game's copy of what the terminal shows (by world column), at the scroll position"""
        s = self.w('scroll'); b = syms['sh']
        return [[self.mem[b + r * 256 + ((s + c) & 255)] for c in range(80)] for r in range(22)]
    def score(self):
        return self.v('score') | self.v('score', 1) << 8 | self.v('score', 2) << 16
    def sprites(self):
        """the sprites the terminal should show: (slot, picture, x, y, mirrored)"""
        out = []
        sc2 = self.w('scroll') * 2
        for i in range(10):
            if not self.v('o_kind', i): continue
            fm = self.mos_frame() if i == 0 else self.obj_frame(i)
            if fm is None: continue
            x = self.ox(i) - sc2; y = self.s8('o_y', i)
            if not (-32 <= x < 224 and y >= -40): continue
            out.append((15 if i == 0 else i, fm[0], x, y + 8, int(fm[1])))
        return sorted(out)
    def screen(self):
        """the terminal's view rows as characters (from its pixels; its sprites
        as a last row, when it draws them)"""
        rows = self.screen_bg()
        if not SOFT: rows.append(sorted(self.mc.term.visible()))
        return rows
    def shown(self):
        """the game's copy of what the terminal shows (and the sprites it should)"""
        rows = self.shown_bg()
        if not SOFT: rows.append(self.sprites())
        return rows
    def screen_bg(self):
        pix = self.mc.term.pix
        out = []
        for r in range(22):
            row = []
            for c in range(80):
                b = 0
                for i in range(8):
                    if pix[(r + 2) * 4 + i // 2][c * 2 + (i & 1)]: b |= 1 << i
                row.append(b)
            out.append(row)
        return out
    def mos_frame(self):
        """(picture, mirrored) or None"""
        st = self.v('mstate')
        if st == 3: return None
        if st == 4: return SP['MOS_DEAD'], False
        if self.v('inv_t') & 2: return None
        oc = self.v('oc_t')
        if oc:
            fr = (self.v('frame') - 1) & 255
            if (fr if oc >= 40 else fr >> 1) & 2: return None
        base = SP['MOS_STAND']
        if self.v('big'): base = SP['FIRE_STAND'] if self.v('fire') else SP['BIG_STAND']
        if self.v('duck'):
            return {SP['MOS_STAND']: SP['MOS_DUCK'], SP['BIG_STAND']: SP['BIG_DUCK'], SP['FIRE_STAND']: SP['FIRE_DUCK']}[base], bool(self.v('facing'))
        if st in (1, 5): f = base
        elif not self.v('onground'):
            if self.v('lv_flags') & 2:              # swimming
                if self.v('sw_t'): f = base
                else: f = SP['MOS_SWIM'] + (2 if self.v('fire') else 1 if self.v('big') else 0)
            else: f = base + 3
        elif self.v('o_vxl') == 0 and self.v('o_vxh') == 0: f = base
        else: f = base + (2 if self.v('anim', 1) & 4 else 1)
        return f, bool(self.v('facing'))
    def obj_frame(self, i):
        k = self.v('o_kind', i)
        fr = (self.v('frame') - 1) & 255          # (counted on after drawing)
        if k == K_BUG: return SP['AND1'] + ((fr >> 3) & 1), False
        if k == K_SHELLY: return SP['OR1'] + ((fr >> 2) & 1), False
        if k == K_FIRE: return SP['FIREBALL1'] + ((fr >> 1) & 1), False
        if k == K_DRAGON:
            if self.v('dr_flash') & 2: return None
            return SP['DRAGON1'] + ((fr >> 3) & 1), bool(self.v('dr_face'))
        if k == K_BREATH: return SP['BREATH'], not (self.v('o_vxh', i) & 0x80)
        if k == K_SHELL and self.v('o_r', i) >= REVIVE - 40 and fr & 4: return SP['OR1'], False
        if k == K_FISH: return SP['FISH1'] + ((fr >> 3) & 1), not (self.v('o_vxh', i) & 0x80)
        if k == K_FAN: return SP['FAN1'] + ((fr >> 1) & 1), False
        return SP[KIND_PIC[k]], False
    def model(self):
        """the view as it should be: the map at the scroll position, then the sprites"""
        sc = self.w('scroll')
        out = []
        for r in range(22):
            T = BOT if r & 1 else TOP
            out.append([T[self.tile((sc + c) // 4, r // 2)][(sc + c) % 4] for c in range(80)])
        sc2 = sc * 2
        if not SOFT: return out                    # (the terminal draws the sprites)
        order = [i for i in range(1, 10) if self.v('o_kind', i)]
        if self.v('o_kind', 0): order.append(0)
        for i in order:
            fm = self.mos_frame() if i == 0 else self.obj_frame(i)
            if fm is None: continue
            f, mir = fm
            sx = self.ox(i) - sc2; sy = self.s8('o_y', i)
            if not (-32 <= sx < 160 and -16 <= sy < 88): continue
            rows = FRAMES[f]
            if mir: rows = [r[::-1] for r in rows]
            sil = gen.silhouette(rows)
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    px, py = sx + x, sy + y
                    if 0 <= px < 160 and 0 <= py < 88 and sil[y][x] == '#':
                        bit = 1 << ((py & 3) * 2 + (px & 1))
                        if ch == '#': out[py >> 2][px >> 1] |= bit
                        else: out[py >> 2][px >> 1] &= ~bit
        return out
    def text(self):
        return '\n'.join(''.join(self.mc.term.txt.get((c, r), (' ', 0))[0] for c in range(80)) for r in range(24))
    def at_frame_start(self, m):
        """True when called from read_input (the top of the frame loop)"""
        mem = self.mem
        ret = mem[0x100 + ((m.mpu.sp + 1) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 2) & 0xFF)] << 8
        if 'getc' in syms and syms['getc'] <= ret < syms['getc'] + 32:    # (SMB.BIN: through its getc)
            ret = mem[0x100 + ((m.mpu.sp + 3) & 0xFF)] | mem[0x100 + ((m.mpu.sp + 4) & 0xFF)] << 8
        return syms['read_input'] <= ret < syms['handle_key']
