#!/usr/bin/env python3
"""
gen_keywords.py - regenerate the KEYWORDS table inside ebtok.py from basic.s.

Run this whenever you add or change BASIC keywords/tokens in basic.s:
    python3 gen_keywords.py basic.s ebtok.py
It reads the TK_xxx token values and the TAB_xxxx tokenizer tables from basic.s
and rewrites the  KEYWORDS = { ... }  block of ebtok.py in place.
"""
import re, sys

def parse(basic):
    src = basic.replace('\r', '').split('\n')
    tk = {}
    for l in src:
        m = re.match(r'^(TK_\w+)\s*=\s*(\$[0-9A-Fa-f]+|TK_\w+\+1)', l)
        if m:
            v = m.group(2)
            tk[m.group(1)] = int(v[1:], 16) if v.startswith('$') else tk[v[:-2]] + 1
    i1 = src.index('TAB_1STC')
    first = []
    for l in src[i1 + 1:]:
        m = re.match(r'\s*\.byte\s+"(.)"', l)
        if m: first.append(m.group(1))
        elif re.match(r'\s*\.byte\s+\$00', l): break
    ichr = src.index('TAB_CHRT')
    order = []
    for l in src[ichr + 1:]:
        m = re.match(r'\s*\.word\s+(TAB_\w+)', l)
        if m: order.append(m.group(1))
        elif l.strip() and not l.strip().startswith(';'): break
    assert len(order) == len(first), (len(order), len(first))
    tabs, cur = {}, None
    for l in src[src.index('TAB_STAR'):]:
        if l.startswith('LAB_KEYT'): break
        m = re.match(r'^(TAB_\w+)', l)
        if m: cur = m.group(1); tabs[cur] = []; continue
        code = l.split(';')[0]
        m = re.match(r'\s*\.byte\s+(.*)$', code)
        if m and cur:
            tabs[cur].append(re.findall(r'"[^"]*"|[^,\s]+', m.group(1)))
    res = {}
    for ch, t in zip(first, order):
        entries, buf = [], []
        for parts in tabs[t]:
            for p in parts:
                if p.startswith('"'): buf += [ord(c) for c in p[1:-1]]
                elif p.startswith('TK_'):
                    buf.append(tk[p]); entries.append((bytes(buf[:-1]).decode(), buf[-1])); buf = []
                elif p == '$00': assert not buf
                else: raise SystemExit("cannot parse table item %r" % p)
        res[ch] = entries
    return first, res

def main():
    basic, tool = sys.argv[1], sys.argv[2]
    first, res = parse(open(basic, newline='').read())
    out = "KEYWORDS = {\n"
    for ch in first:
        out += "    %r: [%s],\n" % (ch, ", ".join("(%r, 0x%02X)" % e for e in res[ch]))
    out += "}\n"
    t = open(tool).read()
    t2, n = re.subn(r'KEYWORDS = \{\n.*?\n\}\n', lambda m: out, t, count=1, flags=re.S)
    assert n == 1, "KEYWORDS block not found in " + tool
    open(tool, 'w').write(t2)
    print("%d keywords written to %s" % (sum(len(v) for v in res.values()), tool))

main()
