"""screen.py - the display card as EDIT uses it: an 80 x 24 ANSI screen.

    ESC [ r ; c H   ESC [ K   ESC [ 2 J   ESC [ n m (0 1 4 7)
    ESC [ L  ESC [ M (insert / delete a line at the cursor's row)
    ESC [ D   CR   LF
Characters are kept with their attributes (1 bold, 2 underline, 4 reverse).
Writing the last column, or anything the display would take as one of its
own control codes (01-1F other than CR LF ESC), is logged as a problem.
"""
ROWS, COLS = 24, 80


class Screen:
    def __init__(self):
        self.cells = [[(' ', 0)] * COLS for _ in range(ROWS)]
        self.r = self.c = 0
        self.attr = 0
        self.problems = []
        self.esc = None

    def feed(self, data):
        for b in data:
            self.byte(b)

    def byte(self, b):
        if self.esc is not None:
            self.esc += chr(b)
            if self.esc == '[':
                return
            if not self.esc.startswith('['):
                self.problems.append('ESC %r' % self.esc)
                self.esc = None
                return
            if 0x40 <= b <= 0x7E and len(self.esc) > 1:
                self.csi(self.esc[1:-1], chr(b))
                self.esc = None
            return
        if b == 27:
            self.esc = ''
        elif b == 13:
            self.c = 0
        elif b == 10:
            self.r += 1
            if self.r >= ROWS:
                self.r = ROWS - 1
                self.cells = self.cells[1:] + [[(' ', 0)] * COLS]
        elif b < 32 or b == 127:
            self.problems.append('control code %02X' % b)
        else:
            if self.c >= COLS - 1:
                self.problems.append('wrote column %d of row %d' % (self.c + 1, self.r + 1))
            if self.c < COLS:
                self.cells[self.r][self.c] = (chr(b), self.attr)
            self.c = min(self.c + 1, COLS - 1)

    def csi(self, p, f):
        ps = [int(x) if x else 0 for x in p.split(';')] if p else []
        if f == 'H':
            r = (ps[0] if ps else 1) or 1
            c = (ps[1] if len(ps) > 1 else 1) or 1
            self.r, self.c = r - 1, c - 1
        elif f == 'K':
            for c in range(self.c, COLS):
                self.cells[self.r][c] = (' ', 0)
        elif f == 'J':
            self.cells = [[(' ', 0)] * COLS for _ in range(ROWS)]
        elif f == 'm':
            for x in ps or [0]:
                if x == 0: self.attr = 0
                elif x == 1: self.attr |= 1
                elif x == 4: self.attr |= 2
                elif x == 7: self.attr |= 4
                else: self.problems.append('SGR %d' % x)
        elif f == 'L':
            self.cells.insert(self.r, [(' ', 0)] * COLS)
            self.cells.pop()
        elif f == 'M':
            self.cells.pop(self.r)
            self.cells.append([(' ', 0)] * COLS)
        elif f == 'D':
            self.c = max(0, self.c - (ps[0] if ps else 1))
        else:
            self.problems.append('CSI %r %s' % (p, f))

    def row(self, r):
        return ''.join(ch for ch, a in self.cells[r]).rstrip()

    def attrs(self, r):
        return [a for ch, a in self.cells[r]]

    def text(self, rows=ROWS - 1):
        return [self.row(r) for r in range(rows)]

    def dump(self):
        for r in range(ROWS):
            print('%2d|%s' % (r, self.row(r)))
