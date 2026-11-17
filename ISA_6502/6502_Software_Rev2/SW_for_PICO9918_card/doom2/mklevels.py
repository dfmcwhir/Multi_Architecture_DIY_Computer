#!/usr/bin/env python3
"""mklevels.py - the maps for 6502 DOOM2: MAP01.LVL .. MAP05.LVL.
   python3 mklevels.py            (python3 mklevels.py show: print them)

The level file is the first DOOM's (the engine is the same); DOOM2 adds two
wall styles: 6 wood, 7 metal.

Map legend (32 x 32, the edge must be wall):
  #  brick   %  tech   @  stone   W  wood   M  metal
  D  door (USE opens it)          X  exit switch (USE it to finish)
  .  floor   P  the player's start
  g  grunt   B  brute   +  medkit   a  ammo

Level file layout:
  0   "D6"           magic
  2   1              version
  3   start x, start y (tiles), start angle (0-255: 0 east, 64 south)
  6   name           16 characters
  22  next level     12 characters, zero padded ("" = the last level)
  34  thing count
  64  map            32 x 32 tiles: 0 floor, 1 brick, 2 tech, 3 stone, 4 door,
                     5 exit, 6 wood, 7 metal
  1088 things        4 bytes each: type (1 grunt, 2 brute, 3 medkit, 4 ammo), x, y, 0
"""
import collections, random, sys

TILE = {'.': 0, '#': 1, '%': 2, '@': 3, 'D': 4, 'X': 5, 'W': 6, 'M': 7}
THING = {'g': 1, 'B': 2, '+': 3, 'a': 4}
WALLS = '#%@WMX'


class Map:
    def __init__(self, base):
        self.g = [[base] * 32 for _ in range(32)]
    def room(self, x0, y0, x1, y1, style, force=False):
        """walls on the edge (in this style where there is wall), floor inside"""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if x in (x0, x1) or y in (y0, y1):
                    if force or self.g[y][x] in WALLS: self.g[y][x] = style
                else:
                    self.g[y][x] = '.'
    def floor(self, x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.g[y][x] = '.'
    def wall(self, x0, y0, x1, y1, style):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.g[y][x] = style
    def put(self, x, y, ch): self.g[y][x] = ch
    def puts(self, ch, *places):
        for x, y in places: self.g[y][x] = ch
    def rows(self): return [''.join(r) for r in self.g]


def map01():
    """THE GATEHOUSE: a wooden hall, a stone yard, the barracks, the store,
    and the metal gate hall with the exit"""
    m = Map('@')
    m.room(1, 1, 10, 9, 'W')                    # the hall
    m.floor(11, 5, 15, 5)                       # a passage east
    m.room(15, 1, 30, 12, '@')                  # the yard, with pillars
    m.puts('@', (19, 4), (24, 4), (19, 8), (24, 8), (27, 6))
    m.put(10, 5, 'D')
    m.room(15, 12, 30, 20, '#')                 # the barracks
    m.put(22, 12, 'D')
    m.wall(18, 15, 19, 17, '#'); m.wall(25, 15, 26, 17, '#')   # bunks
    m.room(1, 11, 15, 20, 'W')                  # the store
    m.put(15, 16, 'D')
    m.wall(4, 13, 5, 14, 'W'); m.wall(9, 16, 11, 17, 'W')      # crates
    m.room(1, 20, 30, 30, 'M')                  # the gate hall
    m.put(8, 20, 'D')
    m.wall(10, 23, 11, 27, 'M'); m.wall(20, 23, 21, 27, 'M')
    m.put(30, 25, 'X')
    m.put(4, 5, 'P')
    m.puts('a', (7, 3))
    m.puts('g', (20, 6), (26, 3), (22, 10))
    m.puts('a', (28, 10))
    m.puts('g', (17, 18), (28, 14)); m.puts('B', (22, 18)); m.puts('+', (28, 18))
    m.puts('g', (3, 17)); m.puts('a', (13, 12)); m.puts('+', (2, 19))
    m.puts('g', (6, 25), (15, 28), (25, 22)); m.puts('B', (27, 27))
    m.puts('a', (15, 22)); m.puts('+', (5, 29))
    return dict(file='MAP01.LVL', name='THE GATEHOUSE', next='MAP02.LVL', angle=0, map=m.rows())


def map02():
    """THE FOUNDRY: a long metal hall, workshops off it, the brick furnace
    room at the end"""
    m = Map('M')
    m.room(1, 13, 30, 18, 'M')                  # the hall, west to east
    m.puts('M', (6, 15), (6, 16), (12, 15), (12, 16), (18, 15), (18, 16), (24, 15), (24, 16))
    for i, x0 in enumerate((1, 9, 17)):         # workshops north
        m.room(x0, 3, x0 + 8, 13, '%')
        m.put(x0 + 4, 13, 'D')
    for i, x0 in enumerate((1, 11)):            # stores south
        m.room(x0, 18, x0 + 10, 27, 'W')
        m.put(x0 + 5, 18, 'D')
    m.room(21, 18, 30, 30, '#')                 # the furnace room
    m.put(26, 18, 'D')
    m.wall(24, 22, 27, 25, '#')                 # the furnace
    m.room(25, 1, 30, 13, '%')                  # the control room
    m.put(27, 13, 'D')
    m.put(28, 1, 'X')
    m.put(2, 15, 'P')
    m.puts('g', (9, 14), (15, 17), (21, 14), (27, 16))
    m.puts('g', (3, 6), (7, 10)); m.puts('a', (5, 4))
    m.puts('g', (11, 7)); m.puts('B', (14, 5)); m.puts('+', (15, 11))
    m.puts('g', (19, 9), (23, 5)); m.puts('a', (21, 4))
    m.puts('g', (3, 24)); m.puts('+', (8, 26)); m.puts('a', (2, 20))
    m.puts('g', (13, 22), (19, 25)); m.puts('a', (16, 26))
    m.puts('B', (23, 28), (29, 21)); m.puts('g', (28, 28)); m.puts('+', (22, 20)); m.puts('a', (29, 29))
    m.puts('g', (26, 4), (29, 9)); m.puts('+', (28, 11))
    return dict(file='MAP02.LVL', name='THE FOUNDRY', next='MAP03.LVL', angle=0, map=m.rows())


def map03():
    """THE CATACOMBS: a stone maze (made, then checked), with crypts"""
    rnd = random.Random(31)
    m = Map('@')
    # a maze of 2-wide cells: cell (i, j) at 1 + 2i, 1 + 2j, 15 x 15
    N = 15
    seen = {(0, 0)}; stack = [(0, 0)]
    m.put(1, 1, '.')
    while stack:
        i, j = stack[-1]
        nb = [(i + di, j + dj) for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1))
              if 0 <= i + di < N and 0 <= j + dj < N and (i + di, j + dj) not in seen]
        if not nb:
            stack.pop(); continue
        a, b = rnd.choice(nb)
        m.put(1 + 2 * a, 1 + 2 * b, '.')
        m.put(1 + i + a, 1 + j + b, '.')
        seen.add((a, b)); stack.append((a, b))
    for _ in range(40):                          # some loops
        x, y = rnd.randrange(2, 29), rnd.randrange(2, 29)
        if (x + y) % 2 == 1 and m.g[y][x] == '@': m.put(x, y, '.')
    # crypts: wooden rooms opened up into the maze
    for (x0, y0) in ((5, 5), (19, 7), (7, 19), (21, 21)):
        m.room(x0, y0, x0 + 5, y0 + 5, 'W', True)
        m.put(x0 + 2, y0, 'D'); m.put(x0 + 2, y0 + 5, 'D')
        m.put(x0 + 2, y0 - 1, '.'); m.put(x0 + 2, y0 + 6, '.')
    m.put(31, 29, 'X'); m.put(30, 29, '.')
    # the crypts' walls cut some of the maze off: open the stone walls
    # between a reached place and one not reached, until all are reached
    while True:
        seen = {(1, 1)}; q = [(1, 1)]
        while q:
            x, y = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in seen and m.g[n[1]][n[0]] in '.D':
                    seen.add(n); q.append(n)
        lost = [(x, y) for y in range(1, 31) for x in range(1, 31) if m.g[y][x] == '.' and (x, y) not in seen]
        if not lost: break
        done = False
        for y in range(1, 31):
            for x in range(1, 31):
                if m.g[y][x] == '@' and not done:
                    a = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                    if any(p in seen for p in a) and any(p in lost for p in a):
                        m.put(x, y, '.'); done = True
        assert done
    m.put(1, 1, 'P')
    m.puts('+', (7, 7)); m.puts('B', (8, 9)); m.puts('a', (9, 7))
    m.puts('g', (21, 9), (23, 11)); m.puts('+', (22, 10))
    m.puts('B', (9, 21)); m.puts('a', (10, 22)); m.puts('g', (8, 23))
    m.puts('B', (23, 23), (24, 24)); m.puts('+', (22, 24)); m.puts('a', (25, 22))
    places = [(x, y) for y in range(1, 31) for x in range(1, 31) if m.g[y][x] == '.'
              and abs(x - 1) + abs(y - 1) > 8]
    rnd.shuffle(places)
    for (x, y) in places[:12]: m.put(x, y, 'g')
    for (x, y) in places[12:15]: m.put(x, y, 'a')
    for (x, y) in places[15:17]: m.put(x, y, '+')
    return dict(file='MAP03.LVL', name='THE CATACOMBS', next='MAP04.LVL', angle=64, map=m.rows())


def map04():
    """THE DATA CENTRE: tech rooms of server racks round a metal core"""
    m = Map('%')
    m.room(11, 11, 20, 20, 'M')                 # the core
    m.wall(14, 14, 17, 17, 'M')
    for (x0, y0, x1, y1) in ((1, 1, 11, 11), (20, 1, 30, 11), (1, 20, 11, 30), (20, 20, 30, 30)):
        m.room(x0, y0, x1, y1, '%')             # the four halls
        for x in range(x0 + 2, x1 - 1, 3):      # racks
            m.wall(x, y0 + 3, x, y1 - 3, '%')
    m.room(11, 1, 20, 11, 'M'); m.room(11, 20, 20, 30, 'M')
    m.room(1, 11, 11, 20, 'M'); m.room(20, 11, 30, 20, 'M')
    for (x, y) in ((11, 6), (20, 6), (11, 25), (20, 25), (6, 11), (6, 20), (25, 11), (25, 20),
                   (15, 11), (15, 20), (11, 15), (20, 15)):
        m.put(x, y, 'D')
    m.put(13, 13, '.'); m.put(18, 18, '.')
    m.put(30, 28, 'X')
    m.put(15, 3, 'P')
    m.puts('g', (3, 2), (9, 9), (6, 5)); m.puts('a', (2, 9))
    m.puts('g', (22, 2), (28, 9)); m.puts('B', (25, 6)); m.puts('+', (29, 2))
    m.puts('g', (3, 15), (8, 17)); m.puts('a', (9, 13))
    m.puts('g', (23, 14), (28, 18)); m.puts('+', (27, 13))
    m.puts('g', (13, 12), (18, 19)); m.puts('B', (12, 18))
    m.puts('g', (3, 22), (9, 28)); m.puts('a', (6, 24)); m.puts('+', (2, 29))
    m.puts('g', (14, 24), (17, 28)); m.puts('a', (16, 22))
    m.puts('B', (22, 23), (28, 27)); m.puts('g', (25, 29)); m.puts('+', (29, 22))
    return dict(file='MAP04.LVL', name='THE DATA CENTRE', next='MAP05.LVL', angle=64, map=m.rows())


def map05():
    """THE PIT: a brick arena of pillars, wooden pens round it, brutes"""
    m = Map('#')
    m.room(5, 5, 26, 26, '#')                   # the arena
    for y in (9, 15, 21):
        for x in (9, 15, 21):
            m.wall(x, y, x + 1, y + 1, '@')
    m.room(1, 1, 30, 5, 'W')                    # pens round it
    m.room(1, 26, 30, 30, 'W')
    m.room(1, 5, 5, 26, 'W'); m.room(26, 5, 30, 26, 'W')
    for (x, y) in ((15, 5), (5, 15), (26, 15), (15, 26), (8, 5), (23, 26)):
        m.put(x, y, 'D')
    m.put(30, 28, '.'); m.put(31, 28, 'X')
    m.put(15, 3, 'P')
    m.puts('a', (3, 2), (28, 2)); m.puts('+', (5, 3))
    m.puts('g', (12, 2), (20, 3), (26, 2))
    m.puts('B', (8, 8), (23, 8), (8, 23), (23, 23), (15, 13))
    m.puts('g', (12, 12), (19, 12), (12, 19), (19, 19), (15, 24))
    m.puts('+', (12, 15), (19, 15)); m.puts('a', (15, 18))
    m.puts('g', (3, 9), (3, 20)); m.puts('a', (2, 14))
    m.puts('g', (28, 9), (28, 20)); m.puts('+', (29, 14))
    m.puts('B', (10, 28), (20, 28)); m.puts('g', (5, 28), (25, 29)); m.puts('a', (15, 29))
    return dict(file='MAP05.LVL', name='THE PIT', next='', angle=64, map=m.rows())


LEVELS = [map01(), map02(), map03(), map04(), map05()]


def build(lv):
    m = lv['map']
    assert len(m) == 32, (lv['file'], len(m))
    tiles = []; things = []; start = None; exits = []
    for y, row in enumerate(m):
        assert len(row) == 32, (lv['file'], y, len(row), row)
        for x, ch in enumerate(row):
            if ch == 'P': start = (x, y); tiles.append(0)
            elif ch in THING: things.append((THING[ch], x, y)); tiles.append(0)
            else: tiles.append(TILE[ch])
            if ch == 'X': exits.append((x, y))
            if (x in (0, 31) or y in (0, 31)) and ch not in WALLS:
                raise SystemExit('%s: open edge at %d,%d' % (lv['file'], x, y))
    assert start and exits, lv['file']
    assert len(things) <= 32, (lv['file'], len(things))
    seen = {start}; q = collections.deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < 32 and 0 <= n[1] < 32 and n not in seen and tiles[n[1] * 32 + n[0]] in (0, 4):
                seen.add(n); q.append(n)
    for t, x, y in things:
        assert (x, y) in seen, '%s: thing at %d,%d unreachable' % (lv['file'], x, y)
    for ex, ey in exits:
        assert any((ex + dx, ey + dy) in seen for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))), lv['file'] + ': exit unreachable'
    # doors: a wall on two opposite sides (so it shows as a door)
    for y in range(32):
        for x in range(32):
            if m[y][x] == 'D':
                ns = m[y - 1][x] in WALLS + 'D' and m[y + 1][x] in WALLS + 'D'
                ew = m[y][x - 1] in WALLS + 'D' and m[y][x + 1] in WALLS + 'D'
                assert ns or ew, '%s: door at %d,%d not in a wall' % (lv['file'], x, y)
    hdr = bytearray(64)
    hdr[0:2] = b'D6'; hdr[2] = 1
    hdr[3], hdr[4] = start; hdr[5] = lv['angle']
    hdr[6:22] = lv['name'].ljust(16).encode()
    hdr[22:34] = lv['next'].encode().ljust(12, b'\0')
    hdr[34] = len(things)
    body = bytes(tiles) + b''.join(bytes([t, x, y, 0]) for t, x, y in things)
    return bytes(hdr) + body, len(seen), len(things)


if __name__ == '__main__':
    for lv in LEVELS:
        data, reach, n = build(lv)
        open(lv['file'], 'wb').write(data)
        print('%s: %-16s %d bytes, %d things, %d reachable tiles' % (lv['file'], lv['name'], len(data), n, reach))
        if len(sys.argv) > 1 and sys.argv[1] == 'show':
            print('\n'.join(lv['map']))
