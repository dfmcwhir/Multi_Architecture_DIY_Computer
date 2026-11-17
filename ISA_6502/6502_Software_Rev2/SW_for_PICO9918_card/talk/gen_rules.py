"""gen_rules.py - nrl_rules.json + words.txt -> rules.inc for talk.s

Phonemes are numbered (PH below; 0-3 are the pauses).  A rule group for each
first character ($20-$5A) holds its rules in order, each:
    left context, REVERSED (the 6502 reads it while stepping back), $00
    the text matched (all of it), $00
    right context, $00
    phonemes, $FF
and $FF ends the group.  Context classes (talk.s, ctx_*):
    ' ' not a letter   # 1+ vowels   ! 2+ vowels (was ##)   : 0+ consonants
    * 1+ consonants (was ^:)   ^ a consonant   . a voiced consonant
    + E, I or Y   % E... or ING (right only)   & S C G Z X J CH SH
    @ T S R D L Z N J TH CH SH   (vowels: AEIOUY)
The exception words: "WORD",$00, phonemes, $FF ... and $00 at the end."""
import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tts_ref import load_rules

PH = ('GAP COMMA STOP ASK IY IH EY EH AE AA AO OW UH UW ER AX AH AY AW OY '
      'Y P B T D K G F V TH DH S Z SH ZH HH CH JH M N NX L W WH R').split()
PID = {p: k for k, p in enumerate(PH)}

def words():
    d = []
    for l in open('words.txt'):
        l = l.split('#')[0].strip()
        if not l: continue
        w, p = [x.strip() for x in l.split('=')]
        d.append((w, p.split()))
    return d

def main():
    R = load_rules()
    out = ['; rules.inc - made by gen_rules.py from nrl_rules.json and words.txt (do not edit)',
           '; phoneme numbers: ' + ' '.join('%d %s' % (k, p) for k, p in enumerate(PH))]
    total = 0
    names = {}
    for c in range(0x20, 0x5B):
        ch = chr(c)
        if ch not in R: continue
        lab = 'rg_%02X' % c; names[c] = lab
        out.append(lab + ':        ; ' + repr(ch))
        for l, m, r, ph in R[ch]:
            b = [ord(x) for x in l[::-1]] + [0] + [ord(x) for x in m] + [0] + [ord(x) for x in r] + [0]
            b += [PID[p] for p in ph] + [0xFF]
            total += len(b)
            out.append('        .byte   ' + ', '.join('$%02X' % x for x in b) + '   ; %s[%s]%s' % (l, m, r))
        out.append('        .byte   $FF'); total += 1
    out.append('; the group of each character $20-$5A (0 = none)')
    out.append('rg_tab:')
    for c in range(0x20, 0x5B):
        out.append('        .word   %s' % names.get(c, '0'))
    out.append('dict_t:')
    for w, p in words():
        b = [ord(x) for x in w] + [0] + [PID[x] for x in p] + [0xFF]
        total += len(b)
        out.append('        .byte   ' + ', '.join('$%02X' % x for x in b) + '   ; ' + w)
    out.append('        .byte   0')
    out.append('; the phonemes\' names (for /P), 2 characters each')
    out.append('ph_name:')
    for p in PH:
        n = {'GAP': ' /', 'COMMA': ' ,', 'STOP': ' .', 'ASK': ' ?'}.get(p, p.ljust(2)[:2])
        out.append('        .byte   "%s"' % n)
    from tts_ref import AL
    out.append('; the SPO256 allophones\' names (for /P and /A), 3 characters each')
    out.append('al_name:')
    for a in AL:
        out.append('        .byte   "%s"' % a.ljust(3))
    from tts_ref import AL, CODE, SIMPLE, VOWELS, FRONTV, STOP_V, STOP_U, RCOL
    SPECIAL = ['UW', 'Y', 'B', 'D', 'T', 'K', 'G', 'N', 'R', 'HH', 'DH']
    out.append('; each phoneme: its allophone, or $80 + a choice (talk.s al_spec): ' + ' '.join(SPECIAL))
    out.append('ph_map:')
    for p in PH:
        if p in SIMPLE: v = CODE[SIMPLE[p]]
        elif p in SPECIAL: v = 0x80 + SPECIAL.index(p)
        else: v = 0                      # (the pauses: handled apart)
        out.append('        .byte   $%02X   ; %s' % (v, p))
    out.append('; each phoneme: 1 vowel, 2 front vowel, 4 voiced stop, 8 unvoiced stop')
    out.append('ph_kind:')
    for p in PH:
        v = (1 if p in VOWELS else 0) | (2 if p in FRONTV else 0) | (4 if p in STOP_V else 0) | (8 if p in STOP_U else 0)
        out.append('        .byte   %d   ; %s' % (v, p))
    out.append('; each phoneme: the R-coloured allophone it makes before R (0 none)')
    out.append('ph_rcol:')
    for p in PH:
        out.append('        .byte   %d   ; %s' % (CODE[RCOL[p]] if p in RCOL else 0, p))
    for a in AL:
        out.append('A_%s = %d' % (a, CODE[a]))
    out.append('PH_N = %d' % len(PH))
    for p in PH:
        out.append('P_%s = %d' % (p, PID[p]))
    open('rules.inc', 'w').write('\n'.join(out) + '\n')
    print('rules.inc: %d rule bytes + tables' % total)

if __name__ == '__main__':
    main()
