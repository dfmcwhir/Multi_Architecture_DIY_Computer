"""The levels of SUPER MOS BROS.  gen.py turns them into the game's data:
every world is a file, WORLD1.SMB ... WORLD5.SMB.

Each level is 11 rows of tiles; row 10 is the ground, MOS stands on it in
row 9.  A world is 4 levels: x-1 outdoors, x-2 under a brick ceiling (with
a few fans), x-3 up on ledges (with fans) or under the coolant (swimming), x-4 a castle with
KIL the dragon at the end.  5-4, the last, ends with Princess Graphics Card.
A level may have a bonus room after its end (see L.bonus)."""
import random
import gen

class L:
    def __init__(self, name, w, time=300, castle=False):
        self.name, self.w, self.time, self.castle = name, w, time, castle
        self.water = self.final = False
        self.room = self.out = 0                # a bonus room: its first column; the exit pipe
        self.g = [[0] * w for _ in range(11)]
        self.en = []
        self.start = (2, 9)
        self.put(0, 10, ('W' if castle else '#') * w)
        if castle: self.put(0, 0, 'W' * w)
    # ---- tiles
    def put(self, x, y, s):
        for i, ch in enumerate(s):
            if ch != '.' and 0 <= x + i < len(self.g[y]): self.g[y][x + i] = gen.TCHAR[ch]
    def at(self, x, y): return self.g[y][x]
    def pit(self, x, n):
        self.put(x, 10, ('v' if self.castle else ' ') * n)
    def pipe(self, x, h):                   # h tiles tall, standing on the ground
        self.put(x, 10 - h, '[]')
        for y in range(11 - h, 10): self.put(x, y, '{}')
    def col(self, x, h, top=9, ch='H'):      # a column of h blocks with its top at row top
        for y in range(top, top + h): self.put(x, y, ch)
    def post(self, x, h, ch='H'):            # a column h blocks tall on the ground
        self.col(x, h, 10 - h, ch)
    def stairs(self, x, n, up=True, base=9, ch='H'):
        for i in range(n):
            h = i + 1 if up else n - i
            self.col(x + i, h, base - h + 1, ch)
    def hidden(self, x, y): self.put(x, y, '*')         # an invisible block: a 1UP
    def bonus(self, x, out, h=3, out_h=2, seed=0):
        """a pipe at x to go down (press down on it) into a bonus room full of
        bits; its exit pipe comes back up on top of the pipe at out"""
        r = random.Random(seed)
        self.put(x, 10 - h, '<>')
        for y in range(11 - h, 10): self.put(x, y, '{}')
        self.pipe(out, out_h)
        self.out = out
        c = self.w + 4                          # the room: one screen, after the level
        for row in self.g: row += [0] * (c + 20 - len(row))
        self.room = c
        self.put(c, 0, 'B' * 20)
        self.put(c, 10, '#' * 20)
        for y in range(1, 10): self.put(c, y, 'B'); self.put(c + 19, y, 'B')
        for k in range(3):                      # bits in rows, on bricks
            y = 3 + k * 2
            x0 = c + 2 + r.randrange(3)
            self.put(x0, y, 'o' * r.randrange(6, 11))
        self.put(c + 3, 8, 'BBBB'); self.put(c + 3, 7, 'oooo')
        self.put(c + 9, 9, 'oooo')
        self.put(c + 15, 8, '<>'); self.put(c + 15, 9, '{}')   # the way out
    def fan(self, x, y=7, hi=False):           # hi: flies right up to near the top
        self.en.append((x, y, 'fanhi' if hi else 'fan'))
    def fish(self, x, y, wave=False):          # wave: swims up and down 12 pixels as it goes
        self.en.append((x, y, 'wfish' if wave else 'fish'))
    def cloud(self, x): self.en.append((x, 1, 'cloud'))
    def princess(self, x): self.en.append((x, 7, 'princess'))
    # ---- scenery
    def resistor(self, x, y): self.put(x, y, 'rs')
    def cap(self, x, y): self.put(x, y, 'p')
    def chip(self, x): self.put(x, 9, 'bd')
    def trans(self, x): self.put(x, 9, 't')
    def scenery(self, step=19, seed=1, until=None, ground=True):
        r = random.Random(seed)
        until = until or self.w - 20
        for x in range(5, until, step):
            if r.random() < 0.6: self.resistor(x + r.randrange(4), 1 + r.randrange(2))
            else: self.cap(x + r.randrange(4), 1 + r.randrange(3))
        for x in range(9, until if ground else 0, step + 4):
            gx = x + r.randrange(5)
            if all(self.g[9][gx + k] == 0 and self.g[10][gx + k] == gen.T['GROUND'] for k in range(2)):
                if r.random() < 0.6: self.chip(gx)
                else: self.trans(gx)
    # ---- enemies
    def andg(self, x, y=9): self.en.append((x, y, 'and'))
    def org(self, x, y=9): self.en.append((x, y, 'or'))
    # ---- the end of a level
    def finish(self, p):
        """the flagpole in column p (its flag says 6502), then a 6502 to walk into"""
        self.put(p, 1, '^')
        for y in range(2, 9): self.put(p, y, '|')
        self.put(p - 2, 2, 'FG')
        self.put(p, 9, 'H')
        for ty in range(5):
            for tx in range(5): self.g[5 + ty][p + 4 + tx] = gen.CHIP[ty][tx]
    def castle_end(self, x, bridge=12):
        """a bridge over lava with KIL the dragon on it, and the RESET button"""
        self.put(x - 4, 9, 'WWWW')
        self.put(x, 10, 'v' * bridge)
        self.put(x, 9, '=' * bridge)
        self.en.append((x + bridge - 4, 7, 'dragon'))
        e = x + bridge
        self.put(e, 9, 'W' * (self.w - e))
        self.put(e + 1, 8, 'R')
        for y in range(1, 8): self.put(self.w - 1, y, 'W')
        if self.final: self.princess(e + 6)
    def rows(self):
        names = {i: t[1] or '%' for i, t in enumerate(gen.TILES) if t[1]}
        names = {i: names.get(i, '%') for i in range(len(gen.TILES))}
        return [''.join(names[t] for t in r) for r in self.g]

# =============================================================================
# world 1: laid out by hand
# =============================================================================
def w1_1():
    v = L('1-1', 216)
    v.scenery(seed=11, until=180)
    v.put(16, 6, '?')
    v.put(20, 6, 'BMB?B')
    v.put(22, 2, '?')
    v.andg(23)
    v.pipe(29, 2)
    v.andg(41)
    v.pipe(47, 4)
    v.andg(51); v.andg(53)
    v.bonus(38, 58, h=3, out_h=4, seed=11)
    v.hidden(64, 6)
    v.pit(69, 2)
    v.put(76, 6, 'B?B')
    v.put(79, 2, 'BBBBBBBB')
    v.andg(80, 1); v.andg(82, 1)
    v.pit(86, 3)
    v.put(91, 2, 'BBB?')
    v.put(94, 6, '?')
    v.andg(97); v.andg(99)
    v.put(100, 6, 'BB')
    v.put(106, 6, '?')
    v.put(109, 6, '?')
    v.put(109, 2, 'O')
    v.put(112, 6, '?')
    v.org(110)
    v.andg(114); v.andg(116)
    v.put(118, 6, 'B')
    v.put(121, 2, 'BBB')
    v.put(128, 2, 'B??B')
    v.put(129, 6, 'BB')
    v.andg(124); v.andg(126); v.andg(130); v.andg(132)
    v.stairs(135, 4)
    v.stairs(141, 4, up=False)
    v.stairs(149, 4)
    v.col(153, 4, 6)
    v.pit(154, 2)
    v.stairs(156, 4, up=False)
    v.pipe(164, 2)
    v.put(168, 6, 'BB?B')
    v.andg(172); v.andg(174)
    v.pipe(180, 2)
    v.stairs(182, 8)
    v.col(190, 8, 2)
    v.finish(199)
    return v

def w1_2():
    v = L('1-2', 200)
    v.put(8, 0, 'B' * 177)                      # a ceiling
    v.resistor(1, 1); v.cap(5, 2)
    v.col(8, 6, 1, 'B')                         # a wall to go under
    v.put(14, 6, '?M???')
    v.andg(18); v.andg(20)
    v.stairs(26, 2)
    v.put(32, 5, 'BBBBBB'); v.put(32, 4, 'oooooo')
    v.org(34); v.andg(37)                       # (OR gates in front: kick them into the rest)
    v.pipe(42, 3)
    v.pit(48, 3)
    v.put(52, 7, 'BBBB')
    v.put(53, 3, 'oo')
    v.andg(56); v.andg(58)
    v.col(62, 3, 7); v.col(63, 3, 7); v.col(64, 5, 5); v.col(65, 5, 5)
    v.put(64, 4, 'oo')
    v.pit(69, 3)
    v.put(73, 6, 'B?BB?B')
    v.put(73, 2, 'oooooo')
    v.org(78)
    v.pipe(84, 2)
    v.andg(88); v.andg(90)
    v.fan(80, 7)
    v.put(99, 5, 'HHHHH')
    v.put(99, 4, 'ooooo')
    v.pit(100, 3)
    v.org(106); v.andg(108); v.andg(110)
    v.put(114, 6, 'BBOBB')
    v.hidden(119, 5)
    v.put(122, 6, 'BBBBBB')
    v.put(122, 5, 'oooooo')
    v.andg(124)
    v.pit(131, 2)
    v.put(136, 6, '???')
    v.andg(140); v.andg(142)
    v.bonus(94, 146, h=4, out_h=2, seed=12)
    v.pipe(152, 3)
    v.pipe(158, 4)
    v.pit(163, 2)
    v.stairs(166, 6)
    v.col(172, 6, 4)
    v.put(173, 0, ' ' * 27)
    v.finish(182)
    return v

def w1_3():
    v = L('1-3', 196)
    v.scenery(step=17, seed=13, until=176, ground=False)
    v.put(12, 10, ' ' * 168)                    # no ground: ledges
    plat = [(12, 4, 8), (18, 5, 6), (25, 3, 9), (30, 6, 7), (38, 4, 5), (44, 5, 8), (51, 3, 6),
            (56, 7, 8), (65, 4, 6), (71, 4, 4), (77, 6, 7), (85, 3, 5), (90, 5, 8), (97, 4, 6),
            (103, 6, 9), (111, 3, 7), (116, 5, 5), (123, 4, 7), (129, 6, 8), (137, 3, 6),
            (142, 5, 9), (149, 4, 7), (155, 8, 9), (165, 4, 6), (171, 9, 9)]
    for x, n, y in plat: v.put(x, y, 'L' * n)
    v.put(27, 5, '?')
    v.put(46, 2, 'ooo')
    v.put(57, 4, 'M')
    v.put(66, 1, 'oooo')
    v.put(78, 3, 'oooo')
    v.put(92, 1, 'ooo')
    v.put(104, 2, 'oooo')
    v.put(118, 3, '???')
    v.put(130, 2, 'oooo')
    v.put(143, 1, 'oo?oo')
    v.put(157, 4, 'oooooo')
    v.andg(27, 2); v.org(46, 4); v.org(58, 7); v.andg(60, 7); v.andg(80, 5)
    v.org(92, 4); v.org(105, 5); v.andg(107, 5); v.andg(125, 6); v.org(132, 5)
    v.org(145, 4); v.andg(158, 7); v.andg(161, 7)    # (OR gates turn back at the edges)
    for x in (50, 89, 122, 154): v.fan(x, 9, hi=True)    # fans rising from the gaps
    v.put(180, 10, '#' * 16)
    v.finish(183)
    return v

def w1_4():
    v = L('1-4', 150, castle=True)
    v.put(1, 1, 'WWWW')
    v.put(10, 6, '?M?')
    v.pit(18, 2)
    v.post(24, 2); v.post(25, 3); v.post(26, 2)
    v.andg(30); v.andg(32)
    v.pit(36, 3)
    v.put(40, 6, 'WWWWWW'); v.col(40, 5, 1, 'W'); v.col(45, 5, 1, 'W')
    v.put(41, 5, 'oooo')
    v.pit(48, 2)
    v.stairs(52, 3)
    v.pit(55, 3)
    v.stairs(58, 3, up=False)
    v.org(64)
    v.put(66, 6, 'B?B')
    v.pit(72, 3)
    v.post(76, 3); v.post(77, 3)
    v.pit(78, 2)
    v.post(80, 4); v.post(81, 4)
    v.pit(82, 3)
    v.post(85, 3)
    v.andg(90); v.andg(93)
    v.put(96, 1, 'WWWWWWWW'); v.col(96, 4, 2, 'W'); v.col(103, 4, 2, 'W')
    v.hidden(99, 6)
    v.pit(106, 3)
    v.put(110, 6, '?')
    v.castle_end(118)
    return v

# =============================================================================
# worlds 2 to 5: built from pieces, with a seed for each level
# =============================================================================
def outdoor(name, seed, w=200, hard=0, under=False, cloud=False, bonus=True):
    r = random.Random(seed)
    v = L(name, w)
    if cloud: v.cloud(18)
    if under:
        v.put(8, 0, 'B' * (w - 30))
        v.col(8, 6, 1, 'B')
    else:
        v.scenery(seed=seed, until=w - 30)
    x = 14
    while x < w - 40:
        k = r.choice(['blocks', 'pipes', 'pit', 'stairs', 'gates', 'coins', 'bricks'])
        if k == 'blocks':
            n = r.randrange(3, 6)
            s = ''.join(r.choice('B?B?') for _ in range(n))
            p = r.random()
            if p < 0.15: s = s[:n // 2] + 'M' + s[n // 2 + 1:]
            elif p < 0.25: s = s[:n // 2] + 'O' + s[n // 2 + 1:]
            v.put(x, 6, s)
            if r.random() < 0.5: v.put(x + 1, 2, 'B' * r.randrange(2, 5))
            if hard and r.random() < 0.5: v.org(x + n + 1); v.andg(x + n + 3)    # (the OR gate in front)
            else: v.andg(x + n + 1)
            x += n + 6
        elif k == 'pipes':
            for i in range(r.randrange(2, 4)):
                v.pipe(x, r.randrange(2, 5 if hard else 4))
                if r.random() < 0.6: v.andg(x + 4)
                x += r.randrange(6, 10)
        elif k == 'pit':
            n = r.randrange(2, 4 + hard)
            v.pit(x, n)
            if n >= 3: v.put(x, 5, 'o' * n)
            x += n + 4
        elif k == 'stairs':
            n = r.randrange(3, 5)
            v.stairs(x, n)
            gap = r.randrange(0, 3) if hard else 0
            if gap: v.pit(x + n, gap)
            v.stairs(x + n + gap, n, up=False)
            x += 2 * n + gap + 4
        elif k == 'gates':
            kinds = [r.random() < 0.3 + 0.2 * hard for i in range(r.randrange(2, 4 + hard))]
            for i, o in enumerate(sorted(kinds, reverse=True)):     # (OR gates in front)
                (v.org if o else v.andg)(x + i * 2)
            x += 10
        elif k == 'coins':
            v.put(x, 7, 'BBBB')
            v.put(x, 6, 'oooo')
            if r.random() < 0.5: v.hidden(x + 6, 6)
            x += 9
        elif k == 'bricks':
            v.put(x, 6, 'BBB')
            v.put(x + 3, 3, 'BB?BB')
            v.andg(x + 4, 2)
            x += 11
    if under:
        v.put(w - 30, 0, ' ' * 30)
        for x in range(50, w - 50, 48 - 8 * hard): v.fan(x + r.randrange(6), 7 - r.randrange(2))
    if bonus:                                   # a pipe down to a bonus room, in a clear stretch
        for x in range(40, w - 70):
            if all(v.at(x + k, y) == 0 for k in range(-2, 4) for y in range(5, 10)) and \
               all(v.at(x + 14 + k, y) == 0 for k in range(-2, 4) for y in range(6, 10)) and \
               all(v.at(x + k, 10) for k in range(-2, 18)):
                v.bonus(x, x + 14, h=3, out_h=2, seed=seed)
                break
    v.stairs(w - 34, 6)
    v.col(w - 28, 6, 4)
    v.finish(w - 18)
    return v

def water(name, seed, w=180, hard=0):
    """liquid cooling: under the coolant, MOS swims (A or W again and again);
    fins stand up from the floor and hang from the top; gates swim at him"""
    r = random.Random(seed)
    v = L(name, w)
    v.water = True
    v.put(0, 0, 'w' * w)
    x = 14
    while x < w - 30:
        k = r.choice(['up', 'down', 'both', 'bits', 'bubbles'])
        if k in ('up', 'both'): v.post(x, r.randrange(2, 5 + hard), 'f')
        if k in ('down', 'both'):
            h = r.randrange(2, 4 + hard)
            v.col(x + (2 if k == 'both' else 0), h, 1, 'f')
        if k == 'bits': v.put(x, r.randrange(3, 8), 'o' * r.randrange(3, 6))
        if k == 'bubbles': v.put(x, r.randrange(2, 8), 'u')
        if r.random() < 0.8 + 0.1 * hard:           # fish, and some wavy ones
            if r.random() < 0.4: v.fish(x + 4, r.randrange(3, 8), wave=True)
            else: v.fish(x + 4, r.randrange(2, 9))
        if r.random() < 0.25 + 0.15 * hard: v.fish(x + 7, r.randrange(2, 9), wave=r.random() < 0.5)
        if r.random() < 0.2: v.put(x + 3, 6, '?' if r.random() < 0.7 else 'M')
        x += r.randrange(7, 11)
    v.finish(w - 14)
    return v

def ledges(name, seed, w=190, hard=0):
    r = random.Random(seed)
    v = L(name, w)
    v.scenery(step=17, seed=seed, until=w - 24, ground=False)
    v.put(12, 10, ' ' * (w - 28))
    x, y = 12, 8
    while x < w - 30:
        n = r.randrange(3, 8 - hard)
        v.put(x, y, 'L' * n)
        if r.random() < 0.4: v.put(x + 1, y - 3, 'o' * (n - 1))
        if n >= 5 and r.random() < 0.6: (v.org if r.random() < 0.5 + 0.2 * hard else v.andg)(x + n - 2, y - 1)
        if r.random() < 0.15: v.put(x + 1, y - 4, '?')
        gap = r.randrange(2, 4 + (1 if hard else 0))
        if x > 30 and r.random() < 0.3 + 0.1 * hard: v.fan(x + n + gap // 2, 9, hi=True)    # a fan in the gap
        x += n + gap
        y = max(4, min(9, y + r.randrange(-2, 3)))
    v.put(x, 9, 'L' * (w - 28 - x)) if x < w - 28 else None
    v.put(w - 16, 10, '#' * 16)
    v.put(w - 28, 10, '#' * 12)
    v.finish(w - 13)
    return v

def castle(name, seed, w=160, hard=0, final=False):
    r = random.Random(seed)
    v = L(name, w, castle=True)
    v.final = final
    v.put(1, 1, 'WWWW')
    v.put(8, 6, '?M?')
    x = 16
    while x < w - 50:
        k = r.choice(['lava', 'pillars', 'room', 'steps', 'gates'])
        if k == 'lava':
            n = r.randrange(2, 4 + hard)
            v.pit(x, n)
            x += n + 3
        elif k == 'pillars':
            for i in range(r.randrange(2, 4)):
                v.post(x, r.randrange(1, 4))
                v.pit(x + 1, 2)
                x += 3
            x += 2
        elif k == 'room':
            v.put(x, 1, 'W' * 8); v.col(x, 4, 2, 'W'); v.col(x + 7, 4, 2, 'W')
            v.put(x + 2, 6, '?B?' if r.random() < 0.7 else 'BMB')
            if r.random() < 0.4: v.hidden(x + 5, 5)
            x += 11
        elif k == 'steps':
            v.stairs(x, 3)
            v.pit(x + 3, 2 + hard)
            v.stairs(x + 3 + 2 + hard, 3, up=False)
            x += 10 + hard
        elif k == 'gates':
            if hard: v.org(x); v.andg(x + 3); v.andg(x + 6)
            else: v.andg(x); v.andg(x + 3)
            x += 9
    v.castle_end(w - 32, bridge=12 + 2 * hard)
    return v

WORLDS = [
    [w1_1(), w1_2(), w1_3(), w1_4()],
    [outdoor('2-1', 21), outdoor('2-2', 22, under=True), water('2-3', 23), castle('2-4', 24)],
    [outdoor('3-1', 31, hard=1), outdoor('3-2', 32, under=True, hard=1), ledges('3-3', 33), castle('3-4', 34, hard=1)],
    [outdoor('4-1', 41, hard=1, cloud=True), outdoor('4-2', 42, under=True, hard=1), water('4-3', 43, hard=1), castle('4-4', 44, hard=1)],
    [outdoor('5-1', 51, hard=1, cloud=True), outdoor('5-2', 52, under=True, hard=1), ledges('5-3', 53, hard=1),
     castle('5-4', 54, hard=1, final=True)],
]

if __name__ == '__main__':
    import sys
    for ws in WORLDS:
        for v in ws:
            if sys.argv[1:] and v.name not in sys.argv[1:]: continue
            print(v.name)
            for r in v.rows(): print(r)
