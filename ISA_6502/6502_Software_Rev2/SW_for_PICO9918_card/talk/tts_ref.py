"""tts_ref.py - text to SPO256 allophones, in Python: the reference that
talk.s follows step by step (same normalising, same greedy rule matcher,
same allophone choice).   python tts_ref.py "some text"
The rules: nrl_rules.json (NRL Report 7948, Elovitz et al. 1976, as typed
up by Greg Kennedy, public domain)."""
import json, re, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
VOW = set('AEIOUY'); CONS = set('BCDFGHJKLMNPQRSTVWXZ'); VOICED = set('BDVGJLMNRWZ')
FRONT = set('EIY')
RULE_RE = re.compile(r"^([#:.%&@^+ A-Z']*)\[([^]]+)\]([#:.%&@^+ A-Z']*)=(.+)$")

def rewrite(ctx):
    # greedy-safe classes: '*' = one or more consonants, '!' = two or more vowels
    return ctx.replace('^:', '*').replace('##', '!')

def load_rules():
    r = json.load(open(os.path.join(HERE, 'nrl_rules.json')))
    groups = {}
    for key, lines in r.items():
        for line in lines:
            l, c, rr, o = RULE_RE.match(line).groups()
            ph = []
            for p in re.findall(r'/([^/]*)/', o):
                p = p.strip()
                if p.startswith('<'):
                    ph.append({'< >': 'GAP', '<,>': 'COMMA', '<.>': 'STOP', '<?>': 'ASK', '<->': 'COMMA'}[p])
                else:
                    ph += p.split()
            groups.setdefault(c[0], []).append((rewrite(l), c, rewrite(rr), ph))
    return groups

def letter(ch): return 'A' <= ch <= 'Z'

def left_ok(pat, t, i):
    """pat matched backwards ending just before position i"""
    for p in reversed(pat):
        ch = t[i] if i >= 0 else '\0'
        if p == ' ':
            if letter(ch): return False
            i -= 1
        elif p == '#' or p == '!':
            n = 0
            while i >= 0 and t[i] in VOW: i -= 1; n += 1
            if n < (2 if p == '!' else 1): return False
        elif p == ':':
            while i >= 0 and t[i] in CONS: i -= 1
        elif p == '*':
            n = 0
            while i >= 0 and t[i] in CONS: i -= 1; n += 1
            if not n: return False
        elif p == '^':
            if ch not in CONS: return False
            i -= 1
        elif p == '.':
            if ch not in VOICED: return False
            i -= 1
        elif p == '+':
            if ch not in FRONT: return False
            i -= 1
        elif p == '&':
            if ch == 'H' and i > 0 and t[i - 1] in 'CS': i -= 2
            elif ch in 'SCGZXJ': i -= 1
            else: return False
        elif p == '@':
            if ch == 'H' and i > 0 and t[i - 1] in 'TCS': i -= 2
            elif ch in 'TSRDLZNJ': i -= 1
            else: return False
        else:
            if ch != p: return False
            i -= 1
    return True

def right_ok(pat, t, i):
    n = len(t)
    def at(k): return t[k] if k < n else '\0'
    for p in pat:
        ch = at(i)
        if p == ' ':
            if letter(ch): return False
            i += 1
        elif p == '#' or p == '!':
            k = 0
            while at(i) in VOW: i += 1; k += 1
            if k < (2 if p == '!' else 1): return False
        elif p == ':':
            while at(i) in CONS: i += 1
        elif p == '*':
            k = 0
            while at(i) in CONS: i += 1; k += 1
            if not k: return False
        elif p == '^':
            if ch not in CONS: return False
            i += 1
        elif p == '.':
            if ch not in VOICED: return False
            i += 1
        elif p == '+':
            if ch not in FRONT: return False
            i += 1
        elif p == '%':
            if t[i:i + 3] == 'ING': i += 3
            elif ch == 'E': i += 1          # (E, ER, ES, ED, ELY: % is always last)
            else: return False
        elif p == '&':
            if t[i:i + 2] in ('CH', 'SH'): i += 2
            elif ch in 'SCGZXJ': i += 1
            else: return False
        elif p == '@':
            if t[i:i + 2] in ('TH', 'CH', 'SH'): i += 2
            elif ch in 'TSRDLZNJ': i += 1
            else: return False
        else:
            if ch != p: return False
            i += 1
    return True

ONES = 'ZERO ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN ELEVEN TWELVE THIRTEEN FOURTEEN FIFTEEN SIXTEEN SEVENTEEN EIGHTEEN NINETEEN'.split()
TENS = 'TWENTY THIRTY FORTY FIFTY SIXTY SEVENTY EIGHTY NINETY'.split()
def num_words(v):
    """0 .. 65535 (as talk.s)"""
    if v == 0: return 'ZERO'
    w = []
    if v >= 1000: w += num_words(v // 1000).split() + ['THOUSAND']; v %= 1000
    if v >= 100: w += [ONES[v // 100], 'HUNDRED']; v %= 100
    if v >= 20: w.append(TENS[v // 10 - 2]); v %= 10
    if v: w.append(ONES[v])
    return ' '.join(w)

def normalise(s):
    """as talk.s: upper case; digit runs (up to 5 digits, <= 65535) as words,
    longer ones digit by digit; , ; : -> ','  . ! -> '.'  ? -> '?'  - kept;
    ' kept; anything else a space.  Punctuation gets spaces round it."""
    out = ' '; i = 0; s = s.upper()
    while i < len(s):
        ch = s[i]
        if ch.isdigit():
            j = i
            while j < len(s) and s[j].isdigit(): j += 1
            d = s[i:j]
            if len(d) <= 5 and int(d) <= 65535: out += ' ' + num_words(int(d)) + ' '
            else: out += ' ' + ' '.join(ONES[int(c)] for c in d) + ' '
            i = j; continue
        if letter(ch) or ch == "'": out += ch
        elif ch in ',;:': out += ' , '
        elif ch in '.!': out += ' . '
        elif ch == '?': out += ' ? '
        elif ch == '-': out += ' - '
        else: out += ' '
        i += 1
    out = re.sub(' +', ' ', out)
    if not out.endswith(' '): out += ' '
    return out

def load_words():
    d = {}
    for l in open(os.path.join(HERE, 'words.txt')):
        l = l.split('#')[0].strip()
        if l:
            w, p = [x.strip() for x in l.split('=')]
            d[w] = p.split()
    return d
WORDS = None

def to_phonemes(text, rules=None):
    global WORDS
    rules = rules or load_rules()
    if WORDS is None: WORDS = load_words()
    t = normalise(text); i = 1; out = []
    while i < len(t):
        if t[i - 1] == ' ' and letter(t[i]):      # the exception words first
            j = i
            while j < len(t) and (letter(t[j]) or t[j] == "'"): j += 1
            if t[i:j] in WORDS:
                out += WORDS[t[i:j]]; i = j; continue
        for l, c, r, ph in rules.get(t[i], []):
            if t.startswith(c, i) and left_ok(l, t, i - 1) and right_ok(r, t, i + len(c)):
                out += ph; i += len(c); break
        else:
            i += 1                      # (no rule: skipped)
    return t, out

# ---- allophones
AL = ('PA1 PA2 PA3 PA4 PA5 OY AY EH KK3 PP JH NN1 IH TT2 RR1 AX MM TT1 DH1 IY EY DD1 UW1 AO AA YY2 AE HH1 '
      'BB1 TH UH UW2 AW DD2 GG3 VV GG1 SH ZH RR2 FF KK2 KK1 ZZ NG LL WW XR WH YY1 CH ER1 ER2 OW DH2 SS NN2 '
      'HH2 OR AR YR GG2 EL BB2').split()
CODE = {n: k for k, n in enumerate(AL)}
VOWELS = set('IY IH EY EH AE AA AO OW UH UW ER AX AH AY AW OY'.split())
FRONTV = set('IY IH EY EH AE'.split())
SIMPLE = {'IY': 'IY', 'IH': 'IH', 'EY': 'EY', 'EH': 'EH', 'AE': 'AE', 'AA': 'AA', 'AO': 'AO', 'OW': 'OW',
          'UH': 'UH', 'AX': 'AX', 'AH': 'AX', 'AY': 'AY', 'AW': 'AW', 'OY': 'OY', 'ER': 'ER1',
          'P': 'PP', 'F': 'FF', 'V': 'VV', 'TH': 'TH', 'S': 'SS', 'Z': 'ZZ', 'SH': 'SH', 'ZH': 'ZH',
          'CH': 'CH', 'JH': 'JH', 'M': 'MM', 'NX': 'NG', 'L': 'LL', 'W': 'WW', 'WH': 'WH'}
GAPS = {'GAP': ['PA3'], 'COMMA': ['PA4'], 'STOP': ['PA5'], 'ASK': ['PA5']}
STOP_V = set('B D G JH'.split()); STOP_U = set('P T K CH'.split())
RCOL = {'AA': 'AR', 'AO': 'OR', 'OW': 'OR', 'EH': 'XR', 'AE': 'XR', 'IY': 'YR', 'IH': 'YR'}

def allophones(ph):
    """the choices talk.s makes (see its notes)"""
    out = []; n = len(ph); k = 0
    def is_gap(p): return p in GAPS
    while k < n:
        p = ph[k]
        prev = ph[k - 1] if k else 'GAP'
        nxt = ph[k + 1] if k + 1 < n else 'GAP'
        nxt2 = ph[k + 2] if k + 2 < n else 'GAP'
        start = is_gap(prev)
        if is_gap(p):
            if out and out[-1].startswith('PA'): out[-1] = max(out[-1], GAPS[p][0])
            else: out += GAPS[p]
            k += 1; continue
        if p not in VOWELS and p == prev:                     # PP -> P
            k += 1; continue
        # a stop inside a word: a short pause first
        if not start and (p in STOP_V or p in STOP_U) and out and not out[-1].startswith('PA'):
            out.append('PA1' if p in STOP_V else 'PA2')
        if p in RCOL and nxt == 'R' and nxt2 not in VOWELS:   # R-coloured vowels
            out.append(RCOL[p]); k += 2; continue
        if p == 'AX' and nxt == 'L' and is_gap(nxt2):         # final -le
            out.append('EL'); k += 2; continue
        if p in SIMPLE: a = SIMPLE[p]
        elif p == 'UW': a = 'UW1' if prev == 'Y' else 'UW2'
        elif p == 'Y': a = 'YY2' if start else 'YY1'
        elif p == 'B': a = 'BB2' if start else 'BB1'
        elif p == 'D': a = 'DD2' if nxt in VOWELS else 'DD1'
        elif p == 'T': a = 'TT2' if nxt in VOWELS else 'TT1'
        elif p == 'K': a = 'KK1' if nxt in FRONTV else ('KK3' if nxt in VOWELS else 'KK2')
        elif p == 'G': a = 'GG1' if nxt in FRONTV else ('GG2' if nxt in VOWELS else 'GG3')
        elif p == 'N': a = 'NN2' if start else 'NN1'
        elif p == 'R': a = 'RR2' if (prev not in VOWELS and not start) else 'RR1'
        elif p == 'HH': a = 'HH1' if nxt in FRONTV else 'HH2'
        elif p == 'DH': a = 'DH1' if start else 'DH2'
        else: raise ValueError(p)
        out.append(a); k += 1
    while out and out[0].startswith('PA'): out.pop(0)
    return out

if __name__ == '__main__':
    text = ' '.join(sys.argv[1:]) or 'Hello world, this is the 6502 talking. It is 1984!'
    t, ph = to_phonemes(text)
    print(repr(t)); print(' '.join(ph)); print(' '.join(allophones(ph)))
