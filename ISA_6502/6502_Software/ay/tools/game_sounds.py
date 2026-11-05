#!/usr/bin/env python3
"""game_sounds.py - the music and sound effects of the games that use
../sfx.s, written as notes and effect scripts; it writes each game's
<game>_sound.inc into its folder:

    python game_sounds.py              all of them
    python game_sounds.py stacker      one

(INVADERS and SNAKE have theirs written in their .s files, and SMB in
smb/sound.py.)  Voices: 0-2 background (music: 0 melody on channel A, 1 bass
on B), 3-5 foreground on channels A-C (heard over the music's channel while
they play).  Tunes are original unless a note says otherwise.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sndgen import *

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
GAMES = {}


def game(f):
    GAMES[f.__name__] = f
    return f


@game
def stacker():
    music = [
        # "Korobeiniki", a Russian folk song (1861, public domain)
        ('theme', 6,
         (10, 2, """
            e5/4 b4/2 c5 d5/4 c5/2 b4       a4/4 a4/2 c5 e5/4 d5/2 c5
            b4/6 c5/2 d5/4 e5               c5/4 a4 a4/8
            r/2 d5/4 f5/2 a5/4 g5/2 f5      e5/6 c5/2 e5/4 d5/2 c5
            b4/4 b4/2 c5 d5/4 e5            c5/4 a4 a4 r"""),
         (11, 3, """
            [e2/2 e3]4 [a2/2 a3]4 [e2/2 e3]4 [a2/2 a3]4
            [d2/2 d3]4 [c2/2 c3]4 [e2/2 e3]4 [a2/2 a3]4""")),
    ]
    sfx = [
        ('move',   1, 5, [VOL, 7, DECAY, 1] + per(120) + wait(2) + [END]),
        ('rotate', 2, 5, [VOL, 9, DECAY, 1] + per(160) + sweep(-20) + wait(3) + [END]),
        ('lock',   3, 5, [MIX, 3, NOISE, 30, VOL, 11, DECAY, 1] + per(1200) + wait(5) + [END]),
        ('drop',   4, 5, [MIX, 3, NOISE, 12, VOL, 13, DECAY, 1] + per(300) + sweep(60) + wait(10) + [END]),
        ('line',   6, 5, jingle(3, 13, 1, 'c6/1 e6 g6 c7/3')),
        ('lines',  7, 5, jingle(3, 13, 1, 'c6/1 e6 g6 c7 e6 g6 c7 e7 g6 c7 e7 g7/4')),
        ('level',  7, 3, jingle(4, 12, 1, 'g5/1 c6 e6 g6/2 e6/1 g6/4')),
        ('overA',  9, 3, jingle(7, 11, 1, 'e5/2 c5 a4 e4 f4 d4 b3/4 a3/8')),
        ('overB',  9, 4, jingle(7, 11, 2, 'a2/4 f2 e2 a1/8')),
    ]
    return music, sfx


@game
def muncher():
    sfx = [
        # the siren while the ghosts hunt, and the faster one while they run
        ('siren',  1, 0, [VOL, 6, LOOP, 0] + per(300) + sweep(-6) + wait(12) + sweep(6) + wait(12) + [NEXT]),
        ('fright', 1, 0, [VOL, 7, LOOP, 0] + per(700) + sweep(-70) + wait(6) + [NEXT]),
        ('waka1',  2, 5, [VOL, 10, DECAY, 2] + per(420) + sweep(-45) + wait(4) + [END]),
        ('waka2',  2, 5, [VOL, 10, DECAY, 2] + per(240) + sweep(45) + wait(4) + [END]),
        ('pill',   3, 5, [VOL, 12, DECAY, 1] + per(500) + sweep(-30) + wait(12) + [END]),
        ('ghost',  5, 4, [VOL, 12, DECAY, 1] + per(500) + sweep(-28) + wait(14) + [END]),
        ('die',    9, 3, [VOL, 12, DECAY, 0, LOOP, 4] + per(160) + sweep(22) + wait(14) + [NEXT, DECAY, 1]
                          + per(800) + sweep(-60) + wait(12) + [END]),
        ('introA', 8, 3, jingle(3, 12, 2, 'e5/2 g5 c6 g5 a5 g5 e5/4 c5/2 e5 g5 c6 e6/4 c6')),
        ('introB', 8, 4, jingle(3, 12, 3, 'c3/4 g3 c3 g3 f2 g2 c3/8')),
        ('clear',  8, 3, jingle(3, 12, 1, 'c6/1 e6 g6 c7/2 g6/1 c7/6')),
        ('over',   8, 3, jingle(7, 11, 2, 'e4/4 d4 c4/8')),
    ]
    return [], sfx


@game
def breaker():
    brick = lambda p: [VOL, 12, DECAY, 2] + per(p) + wait(7) + [END]
    sfx = [
        ('wall',    1, 5, [VOL, 8, DECAY, 2] + per(500) + wait(3) + [END]),
        ('paddle',  2, 5, [VOL, 11, DECAY, 2] + per(380) + wait(5) + [END]),
        ('brick0',  3, 5, brick(95)),       # (by the brick's row, 2 rows each: high at the top)
        ('brick1',  3, 5, brick(119)),
        ('brick2',  3, 5, brick(142)),
        ('brick3',  3, 5, brick(179)),
        ('brick4',  3, 5, brick(213)),
        ('clank',   3, 5, [MIX, 3, NOISE, 3, VOL, 12, DECAY, 2] + per(60) + wait(6) + [END]),
        ('laser',   2, 4, [VOL, 10, DECAY, 2] + per(40) + sweep(12) + wait(6) + [END]),
        ('capsule', 5, 4, jingle(2, 12, 1, 'c5/1 e5 g5 c6 e6 g6/2')),
        ('life',    6, 4, jingle(3, 12, 1, 'g5/1 c6 e6 g6 e6 g6/3')),
        ('lost',    7, 3, [VOL, 12, DECAY, 3] + per(200) + sweep(14) + wait(40) + [END]),
        ('start',   7, 3, jingle(4, 11, 2, 'c5/1 e5 g5 c6/3')),
        ('clear',   8, 3, jingle(4, 12, 1, 'g5/1 c6 e6 g6/2 e6/1 g6 c7/6')),
        ('over',    8, 3, jingle(7, 11, 2, 'c5/2 g4 e4 c4/8')),
    ]
    return [], sfx


@game
def rocks():
    bang = lambda n, v, d, t: [MIX, 2, NOISE, n, VOL, v, DECAY, d] + wait(t) + [END]
    hum = lambda p, d: [VOL, 8, LOOP, 0] + per(p) + sweep(d) + wait(5) + sweep(-d) + wait(5) + [NEXT]
    sfx = [
        ('beat1',   1, 0, [VOL, 13, DECAY, 1] + per(1700) + wait(8) + [END]),   # the heartbeat
        ('beat2',   1, 0, [VOL, 13, DECAY, 1] + per(1900) + wait(8) + [END]),
        ('ufobig',  1, 1, hum(260, -10)),   # the saucers' hum, while one is there
        ('ufosmall', 1, 1, hum(110, -6)),
        ('fire',    2, 5, [VOL, 11, DECAY, 2] + per(50) + sweep(14) + wait(8) + [END]),
        ('hyper',   3, 5, [VOL, 11, DECAY, 1] + per(600) + sweep(-35) + wait(14) + [END]),
        ('thrust',  1, 4, [MIX, 2, NOISE, 28, VOL, 9] + wait(4) + [END]),
        ('bang0',   4, 4, bang(24, 15, 3, 45)),     # rocks: big, medium, small
        ('bang1',   4, 4, bang(16, 14, 2, 28)),
        ('bang2',   4, 4, bang(8, 13, 1, 14)),
        ('boom',    8, 3, [MIX, 3, NOISE, 30, VOL, 15, DECAY, 5] + per(1500) + sweep(20) + wait(75) + [END]),
        ('life',    6, 3, jingle(4, 12, 1, 'c6/1 e6 g6 c7/2 g6/1 c7/4')),
        ('over',    9, 3, jingle(7, 11, 2, 'g4/4 e4 c4 g3/8')),
    ]
    return [], sfx


@game
def grabber():
    sfx = [
        ('shoot',  2, 4, [VOL, 10, DECAY, 3] + per(150) + sweep(12) + wait(12) + [END]),
        ('reel',   1, 4, [VOL, 7, DECAY, 1] + per(900) + wait(2) + [END]),      # (a click as it winds)
        ('grab',   3, 5, [MIX, 3, NOISE, 20, VOL, 12, DECAY, 2] + per(1000) + wait(8) + [END]),
        ('gem',    3, 5, jingle(2, 12, 1, 'e6/1 b6 e7/2')),
        ('cash',   4, 3, jingle(3, 12, 1, 'c6/1 g6/1 c7/4')),
        ('boom',   5, 5, [MIX, 2, NOISE, 31, VOL, 15, DECAY, 3] + wait(45) + [END]),
        ('tick',   2, 3, [VOL, 9, DECAY, 2] + per(120) + wait(3) + [END]),     # the last 10 seconds
        ('buy',    4, 5, jingle(3, 12, 2, 'g5/1 c6/3')),
        ('no',     4, 5, [VOL, 11, DECAY, 1] + per(1500) + wait(10) + [END]),
        ('met',    8, 3, jingle(4, 12, 1, 'c5/1 e5 g5 c6/2 g5/1 c6/6')),
        ('over',   8, 3, jingle(7, 11, 2, 'c5/2 b4 a4 g4 e4/4 c4/8')),
    ]
    return [], sfx


@game
def miner():
    music = [
        # "In the Hall of the Mountain King" (Grieg, 1875: public domain)
        ('hall', 5,
         (10, 3, """
            a4/2 b4 c5 d5 e5 c5 e5/4        d#5/2 b4 d#5/4 d5/2 a#4 d5/4
            a4/2 b4 c5 d5 e5 c5 e5 a5       g5 e5 c5 e5 g5/8"""),
         (11, 3, """
            a2/4 e3 a2 e3                   b2 f#3 a#2 f3
            a2 e3 a2 e3                     c3 g3 c3/8""")),
    ]
    sfx = [
        ('jump',   2, 5, [VOL, 10, DECAY, 0] + per(400) + sweep(-25) + wait(8) + sweep(25) + wait(8) + [END]),
        ('land',   1, 5, [VOL, 9, DECAY, 2] + per(1400) + wait(4) + [END]),
        ('key',    4, 5, jingle(2, 13, 1, 'c7/1 g7/3')),
        ('airtick', 2, 5, [VOL, 9, DECAY, 1] + per(80) + wait(2) + [END]),
        ('dieA',   9, 3, [VOL, 13, DECAY, 3] + per(100) + sweep(10) + wait(45) + [END]),
        ('dieC',   9, 5, [MIX, 2, NOISE, 16, VOL, 14, DECAY, 3] + wait(45) + [END]),
        ('room',   8, 3, jingle(3, 12, 1, 'a5/1 c6 e6 a6/4')),
        ('allA',   9, 3, jingle(5, 12, 1, 'a4/2 c5 e5 a5/4 g5/2 a5/8')),
        ('allB',   9, 4, jingle(5, 12, 2, 'a2/4 e2 c3/2 e3 a2/8')),
        ('over',   9, 3, jingle(7, 11, 2, 'e5/2 c5 a4 e4 a3/8')),
    ]
    return music, sfx


@game
def critters():
    music = [
        ('stroll', 7,
         (8, 3, """
            f5/2 a5 c6 a5 g5/4 f5           e5/2 g5 c6 g5 f5/4 e5
            d5/2 f5 a5 f5 e5 g5 c6/4        f5/4 c5 f5/8"""),
         (9, 3, """
            f2/4 c3 f2 c3                   c2 g2 c2 g2
            d2 a2 c2 g2                     f2 c3 f2/8""")),
    ]
    sfx = [
        ('drop',   1, 4, [VOL, 8, DECAY, 1] + per(200) + sweep(14) + wait(8) + [END]),  # out of the hatch
        ('assign', 3, 4, [VOL, 11, DECAY, 2] + per(120) + wait(3) + [END]),
        ('brick',  1, 4, [VOL, 7, DECAY, 2] + per(700) + wait(2) + [END]),
        ('dig',    1, 4, [MIX, 2, NOISE, 12, VOL, 8, DECAY, 2] + wait(3) + [END]),
        ('saved',  4, 5, jingle(2, 12, 1, 'c6/1 e6 g6/2')),
        ('splat',  5, 5, [MIX, 3, NOISE, 26, VOL, 13, DECAY, 2] + per(1200) + wait(8) + [END]),
        ('nuke',   7, 3, [MIX, 3, NOISE, 31, VOL, 15, DECAY, 4] + per(300) + sweep(30) + wait(60) + [END]),
        ('start',  6, 3, jingle(3, 12, 2, 'c5/1 f5 a5 c6/3')),
        ('well',   8, 3, jingle(4, 12, 1, 'f5/1 a5 c6 f6/2 c6/1 f6/6')),
        ('fail',   8, 3, jingle(7, 11, 2, 'c5/2 a4 f4 c4/8')),
    ]
    return music, sfx


@game
def doom():
    music = [
        ('dread', 6,
         (7, 2, """
            r/8 e4/4 d4                     c4/8 b3/4 g#3"""),
         (10, 2, """
            a2/2 a2 c3 a2 g2 g2 b2 g2       f2 f2 a2 f2 e2 e2 g#2 b2""")),
    ]
    sfx = [
        ('pistol', 3, 5, [MIX, 3, NOISE, 6, VOL, 15, DECAY, 1] + per(900) + sweep(80) + wait(12) + [END]),
        ('click',  2, 5, [VOL, 10, DECAY, 3] + per(60) + wait(2) + [END]),
        ('door',   3, 5, [MIX, 3, NOISE, 30, VOL, 12, DECAY, 0] + per(2500) + sweep(-40) + wait(25) + [END]),
        ('wake',   2, 4, [VOL, 11, DECAY, 2] + per(1800) + sweep(-50) + wait(14) + [END]),   # an enemy sees you
        ('eshoot', 3, 4, [MIX, 2, NOISE, 10, VOL, 13, DECAY, 2] + wait(10) + [END]),
        ('pain',   4, 4, [VOL, 12, DECAY, 2] + per(700) + sweep(60) + wait(8) + [END]),
        ('kill',   5, 4, [MIX, 3, NOISE, 24, VOL, 14, DECAY, 3] + per(500) + sweep(45) + wait(35) + [END]),
        ('ouch',   5, 3, [VOL, 13, DECAY, 2] + per(1200) + sweep(-60) + wait(10) + [END]),
        ('pickup', 4, 3, jingle(2, 12, 1, 'e5/1 a5 e6/2')),
        ('done',   8, 3, jingle(5, 12, 1, 'a4/2 c5 e5 a5/4 g5/2 a5/8')),
        ('died',   9, 3, [VOL, 13, DECAY, 4] + per(300) + sweep(16) + wait(60) + [END]),
    ]
    return music, sfx


def main(which):
    for name in which or sorted(GAMES):
        music, sfx = GAMES[name]()
        path = os.path.join(ROOT, name, name + '_sound.inc')
        n = emit(path, name.upper(), music, sfx)
        print('%s: %d bytes of scripts' % (path, n))


if __name__ == '__main__':
    main(sys.argv[1:])
