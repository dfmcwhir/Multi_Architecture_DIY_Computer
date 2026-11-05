#!/usr/bin/env python3
"""
ebtok.py - tokenize an ASCII BASIC program into an EhBASIC 2.22 program file
that the SBC's  LOAD "NAME"  command can read from the CH376 drive.

    python3 ebtok.py hello.bas                 -> HELLO.BAS  (next to the source)
    python3 ebtok.py game.txt -o GAME.BAS
    python3 ebtok.py prog.bas --upper          # upper-case keywords/variables for you
    python3 ebtok.py --list-tokens             # dump the keyword table

Copy the output to the ROOT of the USB/SD drive.  Name it 8.3 UPPERCASE (the
default does this for you).  LOAD "GAME" finds GAME.BAS.

It mirrors EhBASIC's own line "crunch" routine (LAB_13A6 in basic.s):
  * every line must start with a line number; blank lines are ignored
  * spaces after the line number are dropped, other spaces are kept
  * keywords are matched greedily, with NO word boundaries (as in the real
    thing: TOTAL becomes TO + "TAL").  Keywords must be UPPER CASE
    (anything >= "_" is never tokenized, so "print" stays plain text).
  * text inside "quotes" and after REM is copied untouched
  * after DATA nothing is tokenized until the next ":" (quotes still copied)
  * "?" becomes PRINT

File format = EhBASIC's in-memory program, exactly what SAVE writes:
  per line:  next-line pointer (2)  line number (2)  tokenized text  $00
  end:       $00 $00
The pointers assume the program starts at 0501h (Smeml with Ram_base=$0500)
but LOAD rebuilds all links anyway, so they only need to be non-zero.
"""
import argparse, os, re, sys

# ---------------------------------------------------------------------------
# Generated from basic.s (TAB_1STC / TAB_CHRT / TAB_xxxx tables and TK_ values):
# first character -> list of (rest of keyword, token) in EhBASIC's match order.
# ---------------------------------------------------------------------------
KEYWORDS = {
    '*': [('', 0xC4)],
    '+': [('', 0xC2)],
    '-': [('', 0xC3)],
    '/': [('', 0xC5)],
    '<': [('<', 0xCB), ('', 0xCE)],
    '=': [('', 0xCD)],
    '>': [('>', 0xCA), ('', 0xCC)],
    '?': [('', 0x9F)],
    'A': [('BS(', 0xD1), ('ND', 0xC7), ('SC(', 0xE3), ('TN(', 0xDC)],
    'B': [('IN$(', 0xE8), ('ITCLR', 0xA8), ('ITSET', 0xA7), ('ITTST(', 0xE9)],
    'C': [('ALL', 0x9C), ('HR$(', 0xE6), ('LEAR', 0xA2), ('ONT', 0xA0), ('OS(', 0xD9)],
    'D': [('ATA', 0x83), ('EC', 0x88), ('EEK(', 0xDE), ('EF', 0x99), ('IM', 0x85), ('OKE', 0x9B), ('O', 0x9D)],
    'E': [('LSE', 0xB8), ('ND', 0x80), ('OR', 0xC8), ('XP(', 0xD8)],
    'F': [('N', 0xBA), ('OR', 0x81), ('RE(', 0xD3)],
    'G': [('ET', 0xA5), ('OSUB', 0x8D), ('OTO', 0x89)],
    'H': [('EX$(', 0xE7)],
    'I': [('F', 0x8B), ('NC', 0x95), ('NPUT', 0x84), ('NT(', 0xD0), ('2CINIT', 0xAB), ('2CREAD(', 0xF2), ('2CWRITE', 0xAC), ('RQ', 0xA9)],
    'L': [('CDCLS', 0xB1), ('CDCMD', 0xAF), ('CDINIT', 0xAD), ('CDPOS', 0xB0), ('CDPRINT', 0xAE), ('CASE$(', 0xE5), ('EFT$(', 0xEF), ('EN(', 0xE0), ('ET', 0x87), ('IST', 0xA1), ('OADARR', 0xB4), ('OADRAW', 0xB2), ('OAD', 0x97), ('OG(', 0xD7), ('OOP', 0x9E)],
    'M': [('AX(', 0xEA), ('ID$(', 0xF1), ('IN(', 0xEB)],
    'N': [('EW', 0xA3), ('EXT', 0x82), ('MI', 0xAA), ('OT', 0xBD), ('ULL', 0x94)],
    'O': [('FF', 0xC1), ('N', 0x93), ('R', 0xC9)],
    'P': [('ADKEY', 0xB6), ('EEK(', 0xDD), ('I', 0xEC), ('OKE', 0x9A), ('OS(', 0xD4), ('RINT', 0x9F)],
    'R': [('EAD', 0x86), ('EM', 0x91), ('ESTORE', 0x8C), ('ETIRQ', 0x8E), ('ETNMI', 0x8F), ('ETURN', 0x90), ('IGHT$(', 0xF0), ('ND(', 0xD6), ('UN', 0x8A)],
    'S': [('ADD(', 0xDF), ('AVEARR', 0xB5), ('AVERAW', 0xB3), ('AVE', 0x98), ('GN(', 0xCF), ('IN(', 0xDA), ('PC(', 0xBB), ('QR(', 0xD5), ('TEP', 0xBE), ('TOP', 0x92), ('TR$(', 0xE1), ('WAP', 0xA6)],
    'T': [('AB(', 0xB7), ('AN(', 0xDB), ('HEN', 0xBC), ('O', 0xB9), ('WOPI', 0xED)],
    'U': [('CASE$(', 0xE4), ('NTIL', 0xBF), ('SR(', 0xD2)],
    'V': [('AL(', 0xE2), ('ARPTR(', 0xEE)],
    'W': [('AIT', 0x96), ('HILE', 0xC0), ('IDTH', 0xA4)],
    '^': [('', 0xC6)],
}

TK_DATA = 0x83
TK_REM = 0x91
MAX_LINE = 63999          # EhBASIC rejects line numbers above $F9FF
TYPED_LIMIT = 0x47        # longest line EhBASIC's INPUT buffer accepts (typed, not loaded)


class TokError(Exception):
    pass


def crunch(text, upper=False):
    """Tokenize the text of one line (after the line number). Returns bytes."""
    s = text.encode('latin-1', errors='strict')
    if any(b >= 0x80 for b in s):
        raise TokError("non-ASCII character")
    out = bytearray()
    i = 0
    n = len(s)
    data = False                      # EhBASIC's "Oquote" b6 (inside DATA)
    in_text_upper = upper
    while i < n:
        c = s[i]
        # ---- decide: raw, quote, or try keyword (same ranges as LAB_13AC)
        if c >= 0x5F:                                  # "_" and above: raw
            raw = True
        elif c >= 0x3C:                                # < = > ? @ A-Z [ \ ] ^ : try
            raw = False
        elif c >= 0x30:                                # 0-9 : ;  raw
            raw = True
        elif c == 0x22:                                # quote: copy the string
            out.append(c); i += 1
            while i < n and s[i] != 0x22:
                out.append(s[i]); i += 1
            if i < n:                                  # closing quote
                out.append(0x22); i += 1
            continue
        elif c < 0x2A:                                 # space ! # $ % & ' ( )  raw
            raw = True
        else:                                          # * + , - . /  try
            raw = False

        if not raw and not data:
            ch = chr(c)
            if upper and ch.isalpha():
                ch = ch.upper()
            tok = None
            for rest, t in KEYWORDS.get(ch, ()):
                if s[i + 1:i + 1 + len(rest)].decode('latin-1') == rest or \
                   (upper and s[i + 1:i + 1 + len(rest)].decode('latin-1').upper() == rest):
                    tok = (len(rest) + 1, t)
                    break
            if tok:
                out.append(tok[1]); i += tok[0]
                if tok[1] == TK_DATA:
                    data = True
                elif tok[1] == TK_REM:                 # rest of line copied raw
                    out += s[i:]
                    i = n
                continue
        # raw byte
        if upper and 0x61 <= c <= 0x7A:
            c -= 0x20
        out.append(c); i += 1
        if c == 0x3A:                                  # ":" ends DATA mode
            data = False
    if 0 in out:
        raise TokError("NUL character in line")
    return bytes(out)


def tokenize(source, base=0x0501, upper=False, warn=print):
    lines = {}
    for ln, raw in enumerate(source.splitlines(), 1):
        t = raw.strip(' \t')
        if not t:
            continue
        m = re.match(r'(\d+)', t)
        if not m:
            raise TokError("line %d: missing line number: %r" % (ln, raw))
        num = int(m.group(1))
        if num > MAX_LINE:
            raise TokError("line %d: line number %d too large (max %d)" % (ln, num, MAX_LINE))
        body = t[m.end():].lstrip(' \t')
        if not body:
            warn("line %d: %d has no statements - skipped (would delete the line)" % (ln, num))
            continue
        if len(t) > TYPED_LIMIT:
            warn("line %d: %d is %d characters; it will LOAD and RUN fine, but can't be"
                 " retyped/edited at the prompt (limit %d)" % (ln, num, len(t), TYPED_LIMIT))
        try:
            lines[num] = crunch(body, upper)
        except TokError as e:
            raise TokError("line %d: %s" % (ln, e))
    img = bytearray()
    addr = base
    for num in sorted(lines):
        body = lines[num]
        nxt = addr + 4 + len(body) + 1
        img += bytes([nxt & 0xFF, nxt >> 8, num & 0xFF, num >> 8]) + body + b'\x00'
        addr = nxt
    img += b'\x00\x00'
    return bytes(img), len(lines)


def default_out(src):
    stem = os.path.splitext(os.path.basename(src))[0].upper()[:8]
    return os.path.join(os.path.dirname(src), stem + '.BAS')


def main():
    ap = argparse.ArgumentParser(description="ASCII BASIC -> EhBASIC LOAD file")
    ap.add_argument('source', nargs='?', help="ASCII BASIC source (numbered lines)")
    ap.add_argument('-o', '--output', help="output file (default: SOURCE name, upper-cased, .BAS)")
    ap.add_argument('--upper', action='store_true',
                    help="upper-case letters outside strings/REM/DATA so lower-case source works")
    ap.add_argument('--base', type=lambda x: int(x, 0), default=0x0501,
                    help="program start address used for the link words (default 0x0501)")
    ap.add_argument('--list-tokens', action='store_true', help="print the keyword table and exit")
    a = ap.parse_args()
    if a.list_tokens:
        for ch, ents in KEYWORDS.items():
            for rest, t in ents:
                print("%02X  %s" % (t, ch + rest))
        return 0
    if not a.source:
        ap.error("source file required")
    with open(a.source, encoding='latin-1', newline='') as f:
        src = f.read()
    try:
        img, n = tokenize(src, a.base, a.upper, lambda m: print("warning: " + m, file=sys.stderr))
    except TokError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    out = a.output or default_out(a.source)
    with open(out, 'wb') as f:
        f.write(img)
    print("%s: %d lines, %d bytes" % (out, n, len(img)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
