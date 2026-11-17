#!/usr/bin/env python3
"""sound.py - SUPER MOS BROS.' music and sound effects, for ../ay/sfx.s:
    python sound.py > smb_sound.inc

The tunes are original (written for this game).  Music is written as notes:
    c5 e5 g#4 bb3     a note (octave 4 has A4 = 440 Hz); r = a rest
    /n                a length in 16ths for this note and the ones after it
Each tune has a melody (channel A) and a bass (channel B), the same length;
they repeat.  Effects are short scripts (sfx.s's commands), mostly on
channel C, over the music.

Voices (sfx.s): 0-2 background (the music: 0 melody, 1 bass), 3-5
foreground (effects and jingles; they're heard instead of the music on their
channel while they play).
"""
import sys

NOTE = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11}
END, PER, VOL, NOISE, MIX, SWEEP, DECAY, LOOP, NEXT, JUMP, REST, LEN = range(12)


def wait(t):
    out = []
    while t > 0:
        k = min(t, 128)
        out.append(0x80 + k - 1)
        t -= k
    return out


def per(p): return [PER, p & 255, p >> 8]
def sweep(d): return [SWEEP, d & 255, (d >> 8) & 255]


def notes(text, tick):
    """note text -> bytes (LEN + one byte a note), and its length in 16ths.
    [ ... ]n plays the part in brackets n times (not nested)"""
    out, ln, cur, total = [], 2, None, 0
    mark = None
    for tok in text.replace('[', ' [ ').replace(']', ' ]').split():
        if tok == '[':
            out += [LOOP, 0]
            mark = (len(out) - 1, total)
            cur = None              # (each time round starts with its LEN)
            continue
        if tok.startswith(']'):
            n = int(tok[1:])
            out[mark[0]] = n
            out.append(NEXT)
            total += (total - mark[1]) * (n - 1)
            cur = None              # (the LEN after the loop isn't known: set it again)
            continue
        if '/' in tok:
            tok, l = tok.split('/')
            ln = int(l)
        if ln * tick != cur:
            cur = ln * tick
            assert cur < 256, tok
            out += [LEN, cur]
        total += ln
        if tok == 'r' or tok == '':
            out.append(REST)
            continue
        n = NOTE[tok[0]]
        i = 1
        while tok[i] in '#b':
            n += 1 if tok[i] == '#' else -1
            i += 1
        octave = int(tok[i:])
        k = (octave - 1) * 12 + n
        assert 0 <= k < 96, tok
        out.append(0x20 + k)
    return out, total


# ---- music: (name, ticks a 16th, melody (vol, decay, notes), bass (...)) ----------------
MUSIC = [
    ('over', 5,                     # (upbeat: 8th note skips, an octave bass)
     (11, 3, """
        [c5/2 r/1 c5 e5/2 g5 a5 g5 e5 c5        d5/2 r/1 d5 f5/2 a5 g5/4 r
         c5/2 r/1 c5 e5/2 g5 c6 b5 a5 g5        f5 a5 g5 e5 d5/4 g4]2
        a5/3 g5/1 f5/2 e5 f5 g5 a5/4            g5/3 f5/1 e5/2 d5 e5 f5 g5/4
        f5/2 e5 d5 c5 d5 e5 f5 d5               e5 c5 d5 b4 c5/4 r"""),
     (12, 4, """
        [c3/4 c4 g2 g3   d3 d4 g2 b2   c3 c4 e3 g3   f2 f3 g2 g3]2
        f2 f3 c3 c4      c3 c4 e3 g3   d3 d4 g2 g3   c3 g2 c3 r""")),
    ('under', 7,                    # (under the bricks, the bonus rooms, the coolant)
     (10, 2, """
        a3/2 r c4 r e4 d#4 e4/4         g3/2 r b3 r d4 c#4 d4/4
        f3/2 r a3 r c4 b3 c4 e4         e4 d4 c4 b3 g#3/4 r/4"""),
     (12, 3, """
        a2/4 e2 a2 e2                   g2 d2 g2 d2
        f2 c2 f2 c2                     e2 b1 e2 e2""")),
    ('castle', 5,
     (9, 2, """
        [a4/1 c5 d#5 c5]2 [a#4/1 c#5 e5 c#5]2
        [b4/1 d5 f5 d5]2 [a#4/1 c#5 e5 c#5]2"""),
     (12, 3, """
        a2/4 a2 a#2 a#2        b2 b2 a#2 a#2""")),
    ('star', 5,
     (11, 3, """
        c5/2 e5 g5 c6 g5 e5 c5 e5       d5 f5 a5 d6 a5 f5 d5 f5
        c5 e5 g5 c6 g5 e5 c5 e5         b4 d5 g5 b5 g5 d5 b4 g4"""),
     (12, 2, """
        [c3/2 c4]4 [d3/2 d4]4 [c3/2 c4]4 [g2/2 g3]4""")),
]


def jingle(t, vol, dec, text):
    b, _ = notes(text, t)
    return [VOL, vol, DECAY, dec] + b + [END]


# ---- effects: (name, priority, voice, script bytes) ------------------------------------
SFX = [
    ('jump',    2, 5, [VOL, 11, DECAY, 3] + per(320) + sweep(-14) + wait(10) + [END]),
    ('jumpbig', 2, 5, [VOL, 11, DECAY, 3] + per(420) + sweep(-16) + wait(12) + [END]),
    ('swim',    1, 5, [VOL, 8, DECAY, 2] + per(300) + sweep(-24) + wait(5) + [END]),
    ('coin',    4, 5, [VOL, 12, DECAY, 3] + notes('e6/1 a6/5', 3)[0] + [END]),
    ('stomp',   3, 5, [VOL, 13, DECAY, 2] + per(700) + sweep(-60) + wait(7) + [END]),
    ('kick',    3, 5, [VOL, 12, DECAY, 2] + per(180) + sweep(25) + wait(5) + [END]),
    ('bump',    2, 5, [MIX, 3, NOISE, 28, VOL, 13, DECAY, 1] + per(1600) + wait(6) + [END]),
    ('break',   4, 5, [MIX, 2, NOISE, 18, VOL, 15, DECAY, 1] + wait(14) + [END]),
    ('sprout',  4, 5, [VOL, 10, DECAY, 0] + per(500) + sweep(-14) + wait(16) + [END]),
    ('fire',    2, 5, [VOL, 11, DECAY, 2] + per(90) + sweep(28) + wait(6) + [END]),
    ('powerup', 6, 5, jingle(2, 12, 0, 'c4/1 e4 g4 c5 e5 g5 c6 e5 g5 c6 e6 g6 c7/2')),
    ('oneup',   6, 5, jingle(4, 12, 2, 'c6/1 g5 c6 e6 g6/3')),
    ('hurt',    6, 5, [VOL, 12, DECAY, 2] + per(60) + sweep(16) + wait(18) + [END]),
    ('pipe',    6, 5, [VOL, 12, DECAY, 2] + notes('c3/2 r/1 c3/2 r/1 c3/2', 3)[0] + [END]),
    ('slide',   7, 5, [VOL, 11, DECAY, 0] + per(110) + sweep(10) + wait(48) + [END]),
    ('tick',    2, 5, [VOL, 8, DECAY, 1] + per(90) + wait(2) + [END]),
    ('hit',     5, 5, [MIX, 3, NOISE, 10, VOL, 14, DECAY, 1] + per(400) + sweep(40) + wait(10) + [END]),
    ('breath',  2, 5, [MIX, 2, NOISE, 4, VOL, 10, DECAY, 2] + sweep(0) + wait(12) + [END]),
    ('crumble', 3, 5, [MIX, 2, NOISE, 26, VOL, 12, DECAY, 1] + wait(5) + [END]),
    ('kildie',  7, 5, [MIX, 3, NOISE, 20, VOL, 15, DECAY, 6] + per(300) + sweep(14) + wait(90) + [END]),
    ('hurry',   7, 3, jingle(3, 12, 1, '[c6/1 c#6]6')),
    # jingles on the music's channels A and B (the music has stopped)
    ('dieA',    9, 3, jingle(6, 12, 2, 'e5/2 d#5 d5 c#5 c5/8')),
    ('dieB',    9, 4, jingle(6, 12, 3, 'a3/4 g#3 g3/8')),
    ('clearA',  8, 3, jingle(5, 12, 1, 'c5/1 e5 g5 c6/3 r/1 g5/1 c6/2 e6/2 d6/2 c6/6')),
    ('clearB',  8, 4, jingle(5, 12, 1, 'c3/4 e3/4 g3/4 c4/6')),
    ('goverA',   9, 3, jingle(7, 11, 1, 'e5/4 c5 a4 f4 g4/2 e4 c4/8')),
    ('goverB',   9, 4, jingle(7, 11, 2, 'a2/4 f2 d2 d2 g2 g2 c2/8')),
]


def main():
    o = ['; generated by sound.py: SUPER MOS BROS.\' music and sound effects (for ../ay/sfx.s)', '']
    names, prio, voice, bodies = [], [], [], []
    for name, tick, mel, bas in MUSIC:
        tracks = []
        for part, (v, d, txt) in (('A', mel), ('B', bas)):
            b, total = notes(txt, tick)
            tracks.append(total)
            lab = 's_%s%s' % (name, part)
            names.append(lab); prio.append(0); voice.append(0 if part == 'A' else 1)
            bodies.append((lab, [VOL, v, DECAY, d], b, True))
        assert tracks[0] == tracks[1], (name, tracks)
    first_sfx = len(names)
    for name, p, v, b in SFX:
        lab = 's_' + name
        names.append(lab); prio.append(p); voice.append(v)
        bodies.append((lab, [], b, False))
    for i, (name, *_ ) in enumerate(MUSIC):
        o.append('MUS_%s = %d' % (name.upper(), i * 2))
    for i, (name, *_ ) in enumerate(SFX):
        o.append('SND_%s = %d' % (name.upper(), first_sfx + i))
    o.append('')
    o.append('sfx_scripts:')
    for i in range(0, len(names), 6):
        o.append('        .word   ' + ', '.join(names[i:i + 6]))
    o.append('sfx_prio:                       ; the voice x 16 + the priority (each')
    o.append('        .byte   ' + ', '.join('$%02X' % (v * 16 + p) for v, p in zip(voice, prio)))
    o.append('                                ; plays on its own voice)')
    size = 0
    for lab, head, body, loop in bodies:
        o.append('%s:' % lab)
        data = head + body
        if loop:
            o.append('        .byte   ' + ', '.join('$%02X' % x for x in head))
            o.append('%s_l:' % lab)
            data = body
        for i in range(0, len(data), 16):
            o.append('        .byte   ' + ', '.join('$%02X' % x for x in data[i:i + 16]))
        if loop:
            o.append('        .byte   $%02X' % JUMP + ', <%s_l, >%s_l' % (lab, lab))
            size += len(head) + len(body) + 3
        else:
            size += len(data)
    o.append('; (%d bytes of scripts)' % size)
    print('\n'.join(o))


if __name__ == '__main__':
    main()
