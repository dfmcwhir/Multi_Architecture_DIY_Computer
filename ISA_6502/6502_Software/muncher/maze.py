# The maze: left half (columns 0-19, column 19 is the centre), mirrored to 39.
#  # wall   . dot   o power pellet   space empty (no dot)   - ghost door   H ghost house
HALF = [
  # 01234567890123456789
    "####################",  # 0
    "#o.......#.........#",  # 1
    "#.###.##.#.#######.#",  # 2
    "#...................",  # 3
    "#.###.#.#####.######",  # 4
    "#.....#.......##....",  # 5
    "#####.###.###.##.###",  # 6
    "#####...............",  # 7
    "#####.#######.#####-",  # 8   ghost door at the centre
    "     .........##HHHH",  # 9   tunnel row
    "#####.#######.######",  # 10
    "#####...............",  # 11
    "#####.###.###.###.##",  # 12
    "#.........#.........",  # 13
    "#.###.###.#.###.###.",  # 14
    "#o..#...........#...",  # 15
    "###.#.#.#####.#.#.##",  # 16
    "#.....#...#...#.....",  # 17
    "#.#######.#.#######.",  # 18
    "#...................",  # 19
    "####################",  # 20
]
def full():
    rows = []
    for h in HALF:
        assert len(h) == 20, (h, len(h))
        rows.append(h + h[18::-1])
    return rows

def check(M):
    H, W = len(M), len(M[0])
    def walk(y, x, ghost=False):
        c = M[y][x]
        return c not in '#-' and c != 'H'
    probs = []
    opens = [(y, x) for y in range(H) for x in range(W) if walk(y, x)]
    def nb(y, x):
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y+dy, (x+dx) % W
            if 0 <= ny < H and walk(ny, nx): yield ny, nx
    for y, x in opens:
        n = len(list(nb(y, x)))
        if n < 2: probs.append('dead end at row %d col %d' % (y, x))
    # connectivity
    seen = {opens[0]}; st = [opens[0]]
    while st:
        p = st.pop()
        for q in nb(*p):
            if q not in seen: seen.add(q); st.append(q)
    if len(seen) != len(opens): probs.append('%d tiles not reachable: %s' % (len(opens)-len(seen), sorted(set(opens)-seen)[:8]))
    # 2x2 open blocks look odd
    for y in range(H-1):
        for x in range(W-1):
            if all(walk(y+a, x+b) for a in (0,1) for b in (0,1)): probs.append('2x2 open at %d,%d' % (y, x))
    return probs

if __name__ == '__main__':
    M = full()
    for i, r in enumerate(M): print('%2d %s' % (i, r))
    print('\n'.join(check(M)) or 'OK')
