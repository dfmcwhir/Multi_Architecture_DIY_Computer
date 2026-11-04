#!/usr/bin/env python3
"""
bas2tb.py - prepare an ASCII BASIC source file for LOAD on the 8085 Tiny BASIC.

The 8085 Tiny BASIC stores programs as text, and LOAD reads plain text lines
that start with a line number, so no binary "tokenizing" is needed.  What this
script does instead is everything that is tedious by hand:

  * line numbers are optional: unnumbered lines are numbered automatically
    (--start/--step); numbered lines keep their numbers
  * symbolic labels:  a line that starts with  .name  defines a label for the
    line it sits on (or the next line, if the label is alone), and  .name  can
    be used wherever a line number is expected:
          .loop   PRINT I
                  I = I + 1
                  IF I < 10 THEN .loop
          GOSUB .printit
  * whole-line source comments (lines starting with ' or ; or //) and blank
    lines are dropped, so they cost no program memory; REM lines are kept
  * everything outside quotes is upper-cased, as the ROM does on input
  * memory-mapped hardware: .poke / .peek directives turn POKE and PEEK of
    fixed addresses into OUT and IN on I/O ports (see below)
  * checks: line length, line numbers in order and in range, undefined labels,
    GOTO/GOSUB/THEN targets that do not exist, statements the interpreter does
    not have (DATA, READ, ON, string variables, SIN, MOD, AND, OR ...), and
    non-ASCII characters
  * output uses CR+LF line endings and a DOS 8.3 file name, ready to copy to
    the USB stick and  LOAD "NAME"

Memory-mapped I/O.  Put directives at the top of the source (they are not
copied to the output):

    .poke 32545 = out 34          POKE 32545,V   ->  OUT 34,V
    .peek 32545 = in  34          PEEK(32545)    ->  IN(34)
    .poke $D000..$D00F = out $40  POKE $D003,V   ->  OUT $43,V   (a block of
    .peek $D000..$D00F = in  $40  PEEK($D003)    ->  IN($43)     addresses maps
                                                                 to consecutive ports)

Addresses and ports can be decimal, $hex, &Hhex or 0xhex.  Only POKE and PEEK
with a literal address are converted.  A POKE/PEEK whose address is a
variable or an expression is left alone with a warning, and so is a literal
address that no directive covers, because on this board those really write
or read memory.

Usage:
    python3 bas2tb.py game.txt                 # writes GAME.BAS
    python3 bas2tb.py game.txt -o PLAY.BAS
    python3 bas2tb.py game.txt --check         # only check, write nothing
    python3 bas2tb.py game.txt --list          # also print the result
"""
import argparse
import os
import re
import sys

FREE_BYTES = 28670          # what the ROM reports at power-up
SOFT_LEN = 79               # longest line you can type or edit on the board
HARD_LEN = 89               # longest line LOAD accepts (number + space + text)

STATEMENTS = ["LET", "IF", "GOTO", "GOSUB", "RETURN", "FOR", "NEXT", "PRINT",
              "INPUT", "REM", "END", "STOP", "RUN", "LIST", "NEW", "POKE",
              "OUT", "SAVE", "LOAD", "DIR", "ERASE", "CLS", "MON",
              "SETISR", "CLRISR", "SEND"]
FUNCTIONS = ["ABS", "RND", "SIZE", "PEEK", "IN", "USR", "IFR", "INKEY", "NOT"]
OTHER = ["TO", "STEP", "THEN", "AND", "OR", "XOR", "CHR$"]
SUPPORTED = sorted(STATEMENTS + FUNCTIONS + OTHER, key=len, reverse=True)

UNSUPPORTED = sorted([
    "DATA", "READ", "RESTORE", "ON", "DIM", "DEF", "FN", "SQR", "SIN", "COS",
    "TAN", "ATN", "LOG", "EXP", "INT", "SGN", "LEN", "VAL", "ASC",
    "STR", "LEFT", "MID", "RIGHT", "TAB", "SPC", "POS", "MOD",
    "GET", "OPEN", "CLOSE", "CLR", "CALL", "SYS", "WAIT",
    "RANDOMIZE", "WHILE", "WEND", "REPEAT", "UNTIL", "ELSE", "CLEAR", "CONT",
    "DELETE", "RENUM", "TRON", "TROFF", "SWAP", "PRINT#", "LPRINT",
], key=len, reverse=True)


def parse_num(tok):
    """Decimal, $hex, &Hhex or 0xhex -> int, or None."""
    t = tok.strip().upper()
    try:
        if t.startswith("$"):
            return int(t[1:], 16)
        if t.startswith("&H"):
            return int(t[2:], 16)
        if t.startswith("0X"):
            return int(t[2:], 16)
        if re.fullmatch(r"\d+", t):
            return int(t)
    except ValueError:
        pass
    return None


NUM = r"(?:\$[0-9A-Fa-f]+|&[Hh][0-9A-Fa-f]+|0[xX][0-9A-Fa-f]+|\d+)"


class Mapper:
    """The .poke / .peek rules: memory addresses that are really I/O ports."""
    def __init__(self):
        self.rules = {"poke": [], "peek": []}     # (lo, hi, port_base, port_text)
        self.used = {"poke": 0, "peek": 0}

    def add(self, kind, lo, hi, port, ptext):
        self.rules[kind].append((lo, hi, port, ptext))

    def lookup(self, kind, addr):
        for lo, hi, port, ptext in self.rules[kind]:
            if lo <= addr <= hi:
                self.used[kind] += 1
                off = addr - lo
                if off == 0 and lo == hi:
                    return ptext                      # keep the notation the user typed
                return str(port + off)
        return None


def parse_directive(text, ln, mapper, prob):
    """.poke ADDR[..ADDR] = out PORT   /   .peek ADDR[..ADDR] = in PORT"""
    m = re.match(r"\.(poke|peek)\s+(%s)(?:\s*\.\.\s*(%s))?\s*=\s*(out|in)\s+(%s)\s*(?:['';].*)?$"
                 % (NUM, NUM, NUM), text, re.I)
    if not m:
        prob.error(ln, "bad directive (expected  .poke ADDR[..ADDR] = out PORT  or  "
                       ".peek ADDR[..ADDR] = in PORT): %s" % text)
        return
    kind, a1, a2, word, ptok = m.group(1).lower(), m.group(2), m.group(3), m.group(4).lower(), m.group(5)
    if (kind, word) not in (("poke", "out"), ("peek", "in")):
        prob.error(ln, ".poke must be followed by 'out' and .peek by 'in'")
        return
    lo = parse_num(a1)
    hi = parse_num(a2) if a2 else lo
    port = parse_num(ptok)
    if lo is None or hi is None or port is None or hi < lo:
        prob.error(ln, "bad address range or port in directive")
        return
    if not (0 <= lo and hi <= 65535):
        prob.error(ln, "address out of range 0..65535")
        return
    if not (0 <= port and port + (hi - lo) <= 255):
        prob.error(ln, "port out of range 0..255")
        return
    for lo2, hi2, _, _ in mapper.rules[kind]:
        if lo <= hi2 and lo2 <= hi:
            prob.error(ln, "this address range overlaps an earlier .%s rule" % kind)
            return
    mapper.add(kind, lo, hi, port, ptok.strip())


class Problems:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, ln, msg):
        self.errors.append("line %s: ERROR: %s" % (ln, msg))

    def warn(self, ln, msg):
        self.warnings.append("line %s: warning: %s" % (ln, msg))


def split_strings(text):
    """Split into [(is_string, text)] so quoted strings are left alone."""
    parts, cur, in_q = [], "", False
    for ch in text:
        if ch == '"':
            if in_q:
                cur += ch
                parts.append((True, cur))
                cur, in_q = "", False
            else:
                if cur:
                    parts.append((False, cur))
                cur, in_q = ch, True
        else:
            cur += ch
    if cur:
        parts.append((in_q, cur))
    return parts, in_q


def map_code(text, fn):
    """Apply fn to the parts of a line outside quotes."""
    parts, _ = split_strings(text)
    return "".join(t if is_str else fn(t) for is_str, t in parts)


def code_only(text):
    parts, _ = split_strings(text)
    return "".join(t for is_str, t in parts if not is_str)


def parse_source(path, prob, mapper):
    """Return a list of logical lines: dicts with src, number, labels, text."""
    try:
        raw = open(path, "r", encoding="utf-8-sig").read()
    except UnicodeDecodeError:
        raw = open(path, "r", encoding="latin-1").read()
    lines, pending = [], []
    for i, line in enumerate(raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"), 1):
        s = line.strip().replace("\t", " ")
        if not s or s[0] in "';" or s.startswith("//"):
            continue
        if re.match(r"\.(poke|peek)\b", s, re.I):
            parse_directive(s, i, mapper, prob)
            continue
        number = None
        m = re.match(r"(\d+)\s*(.*)$", s)
        if m:
            number, s = int(m.group(1)), m.group(2)
        labels = list(pending)
        pending = []
        while True:                       # one or more  .label  at the start
            m = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$", s)
            if not m:
                break
            labels.append((m.group(1).upper(), i))
            s = m.group(2)
        if not s:                         # label(s) alone: belong to the next line
            if number is not None:
                prob.error(i, "line number %d has no statement" % number)
            pending = labels
            continue
        lines.append({"src": i, "number": number, "labels": labels, "text": s})
    for name, i in pending:
        prob.error(i, "label .%s at the end of the file has no line after it" % name)
    return lines


def apply_mapping(code, mapper, src, prob):
    """Rewrite POKE/PEEK with literal addresses according to the rules."""
    def poke(m):
        addr = parse_num(m.group(1))
        port = mapper.lookup("poke", addr) if addr is not None else None
        if port is None:
            prob.warn(src, "POKE %s is not covered by a .poke rule (writes real memory)"
                      % m.group(1))
            return m.group(0)
        return "OUT %s," % port

    def peek(m):
        addr = parse_num(m.group(1))
        port = mapper.lookup("peek", addr) if addr is not None else None
        if port is None:
            prob.warn(src, "PEEK(%s) is not covered by a .peek rule (reads real memory)"
                      % m.group(1))
            return m.group(0)
        return "IN(%s)" % port

    code = re.sub(r"\bPOKE\s*(%s)\s*," % NUM, poke, code, flags=re.I)
    code = re.sub(r"\bPEEK\s*\(\s*(%s)\s*\)" % NUM, peek, code, flags=re.I)
    # whatever is left uses a variable or an expression as the address
    for m in re.finditer(r"\b(POKE|PEEK)\b", code, re.I):
        rest = code[m.end():m.end() + 24]
        if m.group(1).upper() == "POKE" and not re.match(r"\s*%s\s*," % NUM, rest):
            prob.warn(src, "POKE with a variable/expression address left unchanged")
        elif m.group(1).upper() == "PEEK" and not re.match(r"\s*\(\s*%s\s*\)" % NUM, rest):
            prob.warn(src, "PEEK with a variable/expression address left unchanged")
    return code


def convert(lines, start, step, upper, prob, mapper=None):
    # assign line numbers
    nxt = start
    last = None
    labels = {}
    for ln in lines:
        if ln["number"] is None:
            ln["number"] = nxt
            ln["auto"] = True
        if not 1 <= ln["number"] <= 65535:
            prob.error(ln["src"], "line number %d out of range 1..65535" % ln["number"])
        if last is not None and ln["number"] <= last:
            prob.error(ln["src"], "line number %d is not greater than the previous line (%d)"
                       % (ln["number"], last))
        last = ln["number"]
        nxt = last + step
        for name, i in ln["labels"]:
            if name in labels:
                prob.error(i, "label .%s defined twice" % name)
            labels[name] = ln["number"]

    numbers = {ln["number"] for ln in lines}
    out = []
    for ln in lines:
        text = ln["text"]
        parts, open_q = split_strings(text)
        if open_q:
            prob.warn(ln["src"], "string is missing its closing quote")

        def fix(code):
            def lab(m):
                name = m.group(1).upper()
                if name not in labels:
                    prob.error(ln["src"], "undefined label .%s" % name)
                    return m.group(0)
                return str(labels[name])
            code = re.sub(r"\.([A-Za-z_][A-Za-z0-9_]*)", lab, code)
            code = code.upper() if upper else code
            if mapper is not None and (mapper.rules["poke"] or mapper.rules["peek"]):
                code = apply_mapping(code, mapper, ln["src"], prob)
            return code
        text = map_code(text, fix)
        text = text.rstrip()
        ln["out"] = text
        check_line(ln, text, numbers, prob)
        full = "%d %s" % (ln["number"], text)
        if len(full) > HARD_LEN:
            prob.error(ln["src"], "line is %d characters; LOAD accepts at most %d. Split it."
                       % (len(full), HARD_LEN))
        elif len(full) > SOFT_LEN:
            prob.warn(ln["src"], "line is %d characters; longer than the %d you can type or edit "
                      "on the board" % (len(full), SOFT_LEN))
        try:
            full.encode("ascii")
        except UnicodeEncodeError:
            prob.error(ln["src"], "non-ASCII character in line")
        out.append(full)
    return out


def check_line(ln, text, numbers, prob):
    code = code_only(text).upper()
    # statements the interpreter has
    for stmt in code.split(":"):
        s = stmt.strip()
        if not s:
            continue
        if any(s.startswith(k) for k in STATEMENTS) or s.startswith("?"):
            continue
        if re.match(r"[A-Z]\s*=", s) or re.match(r"@\s*\(", s):
            continue
        # IF/THEN allows a statement or line number after THEN; leave to the ROM
        prob.warn(ln["src"], "unrecognised statement start: %r" % s[:20])
    # words that exist in other BASICs but not here
    for run in re.finditer(r"[A-Z]+\$?|[A-Z]+#", code):
        word = run.group(0)
        i = 0
        while i < len(word):
            best_sup = max((k for k in SUPPORTED if word.startswith(k, i)), key=len, default="")
            best_uns = max((k for k in UNSUPPORTED if word.startswith(k, i)), key=len, default="")
            if len(best_uns) > len(best_sup):
                prob.warn(ln["src"], "%s is not supported by this BASIC" % best_uns)
                i += len(best_uns)
            elif best_sup:
                i += len(best_sup)
            else:
                i += 1                      # single letter variable
        if word.endswith("$") and not word.endswith("CHR$"):
            prob.warn(ln["src"], "string variables (%s) are not supported" % word)
    if re.search(r"\d\.\d|\d\.(?!\w)", code):
        prob.warn(ln["src"], "decimal fractions are not supported (16-bit integers only)")
    for m in re.finditer(r"\b(\d{5,})\b", code):
        if int(m.group(1)) > 32767 and not re.search(r"(GOTO|GOSUB|THEN)\s*$", code[:m.start()]):
            prob.warn(ln["src"], "%s is above 32767 and will wrap to a negative number" % m.group(1))
    # jump targets that are plain line numbers
    for m in re.finditer(r"(GOTO|GOSUB|THEN)\s*(\d+)\s*(?![\d+\-*/(])", code):
        if int(m.group(2)) not in numbers:
            prob.warn(ln["src"], "%s %s: there is no line %s" % (m.group(1), m.group(2), m.group(2)))


def dos_name(name):
    stem, ext = os.path.splitext(name)
    return len(stem) <= 8 and len(ext) <= 4 and stem.upper() == stem[:8].upper()


def main():
    ap = argparse.ArgumentParser(description="Prepare an ASCII BASIC file for LOAD on the 8085 Tiny BASIC.")
    ap.add_argument("source", help="ASCII BASIC source file")
    ap.add_argument("-o", "--output", help="output file (default: SOURCE name in upper case, .BAS)")
    ap.add_argument("--start", type=int, default=10, help="first automatic line number (default 10)")
    ap.add_argument("--step", type=int, default=10, help="automatic line number step (default 10)")
    ap.add_argument("--keep-case", action="store_true", help="do not upper-case the program text")
    ap.add_argument("--check", action="store_true", help="check only, write no file")
    ap.add_argument("--list", action="store_true", help="print the converted program")
    ap.add_argument("-q", "--quiet", action="store_true", help="only print errors")
    args = ap.parse_args()
    if args.step < 1 or args.start < 1:
        ap.error("--start and --step must be at least 1")

    prob = Problems()
    mapper = Mapper()
    lines = parse_source(args.source, prob, mapper)
    if not lines and not prob.errors:
        prob.error("-", "the file contains no program lines")
    out = convert(lines, args.start, args.step, not args.keep_case, prob, mapper)

    for msg in prob.errors:
        print(msg, file=sys.stderr)
    if not args.quiet:
        for msg in prob.warnings:
            print(msg, file=sys.stderr)
    if prob.errors:
        print("%d error(s): no output written." % len(prob.errors), file=sys.stderr)
        return 1

    if not args.quiet and (mapper.used["poke"] or mapper.used["peek"]):
        print("converted %d POKE and %d PEEK to OUT/IN."
              % (mapper.used["poke"], mapper.used["peek"]), file=sys.stderr)
    mem = sum(len(l.split(" ", 1)[1]) + 3 for l in out)       # 2 byte number + text + CR
    if not args.quiet:
        print("%d lines, about %d bytes of program memory (%d free at power-up)."
              % (len(out), mem, FREE_BYTES), file=sys.stderr)
    if mem > FREE_BYTES - 200:
        print("warning: the program is close to or over the available memory.", file=sys.stderr)

    if args.list:
        print("\n".join(out))
    if args.check:
        return 0

    if args.output:
        dest = args.output
    else:
        stem = os.path.splitext(os.path.basename(args.source))[0].upper()
        if len(stem) > 8:
            print("note: '%s' is longer than 8 characters; using '%s'" % (stem, stem[:8]),
                  file=sys.stderr)
            stem = stem[:8]
        dest = os.path.join(os.path.dirname(os.path.abspath(args.source)), stem + ".BAS")
    if not dos_name(os.path.basename(dest)):
        print("warning: '%s' is not an upper-case DOS 8.3 name; the CH376 may not find it."
              % os.path.basename(dest), file=sys.stderr)
    with open(dest, "wb") as f:
        f.write(("\r\n".join(out) + "\r\n").encode("ascii"))
    if not args.quiet:
        print("wrote %s  (LOAD \"%s\" on the board)"
              % (dest, os.path.splitext(os.path.basename(dest))[0]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
