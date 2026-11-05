"""Make the level files for 6502 DOOM from the ASCII maps below.

  python3 mklevels.py            writes E1M1.LVL, E1M2.LVL, E1M3.LVL and
                                 builtin.inc (a copy of E1M1 for ROMs
                                 without SBC_LOAD)

Map legend (32 x 32, the edge must be wall):
  #  brick wall      %  tech wall       @  stone wall
  D  door (open it with USE)             X  exit switch (USE it to finish)
  .  floor           P  player start
  g  grunt           B  brute           +  medkit        a  ammo

Level file layout (all levels are loaded to the same place by the engine):
  0   "D6"           magic
  2   1              version
  3   start x, start y (tiles), start angle (0-255, 64 = facing down/south)
  6   name           16 characters
  22  next level     12 characters, zero padded ("" = the last level)
  34  thing count
  35  (unused up to 64)
  64  map            32 x 32 tiles: 0 floor, 1 brick, 2 tech, 3 stone, 4 door, 5 exit
  1088 things        4 bytes each: type (1 grunt, 2 brute, 3 medkit, 4 ammo), x, y, 0
"""
import collections

TILE = {'.': 0, '#': 1, '%': 2, '@': 3, 'D': 4, 'X': 5}
THING = {'g': 1, 'B': 2, '+': 3, 'a': 4}

LEVELS = [
    dict(file='E1M1.LVL', name='THE AIRLOCK', next='E1M2.LVL', angle=0, map=[
        "################################",
        "#P.....#..........%%%%%%%%%%%%%#",
        "#......#..........%...........%#",
        "#..a...D....g.....D.....g.....%#",
        "#......#..........%...........%#",
        "#......#..........%%%%%D%%%%%%%#",
        "###D####...............#......##",
        "#......#.....+.........#..g...##",
        "#..g...#...............#......##",
        "#......###########D#####......##",
        "#......#.........#............##",
        "#......#...g.....#.....B......##",
        "#..+...#.........#.............#",
        "#......D.........#############X#",
        "#......#.........#............##",
        "########.........D.....g......##",
        "#......#.........#..........a.##",
        "#..a...###D#######............##",
        "#......#.........#..+.........##",
        "#......D....g....###############",
        "#......#.........#.............#",
        "################.###.@@@@@@@@@@#",
        "#..............#.###.@........@#",
        "#..g...........#.....D...g....@#",
        "#..............#.###.@........@#",
        "#......+.......#.###.@@@@@@@@@@#",
        "#..............D.###...........#",
        "#..............#.###.....a.....#",
        "#..............#.###...........#",
        "#.....a........#.###...........#",
        "#..............#...............#",
        "################################",
    ]),
    dict(file='E1M2.LVL', name='TOXIC REFINERY', next='E1M3.LVL', angle=192, map=[
        "################################",
        "%%%%%%%%%%%%%%%%#..............#",
        "%..............%#..g.......g...#",
        "%..g.......a...%#..............#",
        "%..............D.......B.......#",
        "%..............%#..............#",
        "%%%%%%%D%%%%%%%%#.....+........#",
        "#.......#.......####D###########",
        "#.......#..g....#..............#",
        "#...+...D.......D..............#",
        "#.......#.......#.....a........#",
        "#.......#########.......g......#",
        "####D####.......#..............#",
        "#.......#...B...#######D########",
        "#.......D.......#......#.......#",
        "#...g...#.......#..g...D...+...#",
        "#.......#####D###......#.......#",
        "#.......#..............#.......#",
        "#.......#....a.........#####D###",
        "#.......#..............#.......#",
        "####D####..............#...B...#",
        "#.......#####@@@@@@@@@@#.......#",
        "#.......#...@..........#.......#",
        "#..+....D...@...g......#...a...#",
        "#.......#...@..........###D#####",
        "#.......#...@@@@@D@@@@@#.......#",
        "#..a....#..............D...g...#",
        "#.......#..............#.......#",
        "#.......#...g......+...#.......#",
        "#.......#..............#.....X##",
        "#.P.....#..............#.......#",
        "################################",
    ]),
    dict(file='E1M3.LVL', name='COMMAND CENTER', next='', angle=0, map=[
        "################################",
        "#P........#......@@@@@@@@@@@@@@#",
        "#.........#......@............@#",
        "#....+....D..g...D..B......g..@#",
        "#.........#......@............@#",
        "#.........#......@@@@@@D@@@@@@@#",
        "#####D#####...........#.......##",
        "#.........#....a......#..g....##",
        "#..g......#...........#.......##",
        "#.........######D######.......##",
        "#.........%%%%%%.%%%%%%.......##",
        "#....a....%............%..+...##",
        "#.........%..g......g..D......##",
        "#####D#####............%......##",
        "#.........%%%%%%D%%%%%%%%%%%%%%#",
        "#..+......#....................#",
        "#.........#........B...........#",
        "#....g....D....................#",
        "#.........#.........a..........#",
        "#.........####################D#",
        "#.........#..........#.........#",
        "#####D#####...g......D....g....#",
        "#.........#..........#.........#",
        "#....a....#..........#####D#####",
        "#.........#####D######.........#",
        "#..g......#..........#....+....#",
        "#.........D....B.....#.........#",
        "#.........#..........#.........#",
        "#.....+...#.....a....#....B....#",
        "#.........#..........#.........#",
        "#.........#..........#........X#",
        "################################",
    ]),
]

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
            if (x in (0, 31) or y in (0, 31)) and ch not in '#%@X':
                raise SystemExit('%s: open edge at %d,%d' % (lv['file'], x, y))
    assert start and exits, lv['file']
    assert len(things) <= 32, (lv['file'], len(things))
    # everything reachable from the start (doors count as open), the exit switch next to a reachable tile
    seen = {start}; q = collections.deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in seen and tiles[n[1] * 32 + n[0]] in (0, 4):
                seen.add(n); q.append(n)
    for t, x, y in things:
        assert (x, y) in seen, '%s: thing at %d,%d unreachable' % (lv['file'], x, y)
    for ex, ey in exits:
        assert any((ex + dx, ey + dy) in seen for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))), lv['file'] + ': exit unreachable'
    hdr = bytearray(64)
    hdr[0:2] = b'D6'; hdr[2] = 1
    hdr[3], hdr[4] = start; hdr[5] = lv['angle']
    hdr[6:22] = lv['name'].ljust(16).encode()
    hdr[22:34] = lv['next'].encode().ljust(12, b'\0')
    hdr[34] = len(things)
    body = bytes(tiles) + b''.join(bytes([t, x, y, 0]) for t, x, y in things)
    data = bytes(hdr) + body
    return data, len(seen), len(things)

if __name__ == '__main__':
    for lv in LEVELS:
        data, reach, n = build(lv)
        open(lv['file'], 'wb').write(data)
        print('%s: %-16s %d bytes, %d things, %d reachable tiles' % (lv['file'], lv['name'], len(data), n, reach))
    data, _, _ = build(LEVELS[0])
    with open('builtin.inc', 'w') as f:
        f.write('; generated by mklevels.py: a copy of E1M1.LVL, used when the ROM has no SBC_LOAD\n')
        f.write('builtin_level:\n')
        for i in range(0, len(data), 16):
            f.write('        .byte   ' + ', '.join('$%02X' % b for b in data[i:i + 16]) + '\n')
        f.write('BUILTIN_LEN = %d\n' % len(data))
