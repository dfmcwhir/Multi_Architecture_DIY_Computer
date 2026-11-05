# AY-3-8910 sound card: driver, test program, music player, piano and step sequencer

For the AY-3-8910 card on the 6502 SBC:

- the address latch is at **$7F22** (BDIR = BC1 = 1)
- the data register is at **$7F23** (BDIR = 1, BC1 = 0)
- BC2 and A8 are tied high, A9 low
- the chip runs at 2 MHz, and the three channels are mixed to mono

There are four programs:

| Program | What it does |
|---|---|
| `AYTEST.BIN` | a menu of tests, each telling you what you should hear |
| `YMPLAY.BIN` | plays chip music (.YM songs, converted to .AYS) from the USB drive |
| `PIANO.BIN` | play the card from the keyboard, with 8 sounds |
| `SEQ.BIN` | a step sequencer: drum and note patterns that loop, saved to the USB drive |

All run from the monitor at $0500. AYTEST works with any terminal; YMPLAY's playing screen, PIANO and SEQ use the PIC32 terminal's cursor and block graphics codes.

## AYTEST

```
L AYTEST 0500
R
```

| Key | Test | You should hear |
|---|---|---|
| 1 | each channel on its own | the same 440 Hz note three times, from channels A, B and C. If one is missing, check that channel's output and mixing resistor. |
| 2 | a scale | C major up and down on channel A |
| 3 | chord and arpeggios | C E G together for 2 seconds, then fast arpeggios |
| 4 | noise | a low rumble rising to a high hiss |
| 5 | envelopes | the 8 envelope shapes, 2 seconds each, on a low C; each is named on screen as it plays |
| 6 | volume | 440 Hz rising from silence to full and back, in 16 steps that should sound even |
| 7 | effects | laser, explosion, siren and bells |
| 8 | sweep | a smooth tone from very low (30 Hz) to beyond hearing. This checks all 12 bits of the tone period. |
| 9 | all of them | tests 1 to 8 in turn |
| Q | quit | back to the boot menu |

Any key stops a test. The card can only be written to, so the program can't check itself: you have to listen.

What a fault usually sounds like:
- **Silence everywhere:** check the address decoding, the 2 MHz clock to the chip, and RESET (it must be high).
- **Wrong notes, or notes that jump about in test 8:** a data line is stuck or swapped.
- **Odd things in test 5:** check the envelope registers (11 to 13).

## YMPLAY

### 1. Convert the songs on the PC

.YM files (Atari ST, Amstrad CPC and ZX Spectrum chip music, easy to find online) are packed with LHA, which needs more memory to unpack than the SBC has. `tools/ym2ays.py` turns them into .AYS files, which hold the register values ready to play. It needs Python 3 and nothing else.

```
python tools\ym2ays.py SONG.YM              makes SONG.AYS next to it
python tools\ym2ays.py C:\music\*.ym        every song in a folder
python tools\ym2ays.py SONG.YM MYNAME.AYS   choose the name
```

**Names:** the drive needs 8.3 names, so each name is cut to its first 8 letters and digits, such as `VIRTUALE.AYS`. If two songs would get the same name, the second gets a number (`VIRTUAL2.AYS`).

**Formats:** it reads YM2!, YM3!, YM3b, YM5! and YM6!, whether packed or not.

**Effects:** YM5 and YM6 songs can use special effects (SID voices, digidrums, the sync buzzer). These need a timer interrupt thousands of times a second, so they are left out, and songs that use them sound plainer.

**Clock:** songs made for another chip clock (the Spectrum's is 1.77 MHz) are rescaled to 2 MHz so they stay in tune. For a card with a different clock, use `--clock 1000000` (for example).

**Not supported:** YM4, MIX1 and YMT1 files.

### 2. Play them

Put the .AYS files in a folder on the USB drive, with a copy of `YMPLAY.BIN`. Then go to that folder with the monitor's L command and start YMPLAY there:

```
L MUSIC
L YMPLAY 0500
R
```

YMPLAY lists the songs (up to 60) in the folder it was loaded from and plays the one you choose. It shows the title, the author, and the time played and the length. When a song ends, the next one starts; after the last, the list starts again.

**Folders:** YMPLAY plays the songs in the monitor's current folder (the one the L command last went into). Each folder of songs can have its own copy of `YMPLAY.BIN` (about 5 KB), or one copy can sit in the top folder and be loaded by its path.
- **How it finds the folder:** it asks the ROM through `SBC_CWD` ($FE18), which gives the monitor's current folder as text (`""` for the top one, or `/MUSIC/DEEP`). Before the list, and before each song, YMPLAY enters that folder a level at a time (`/MUSIC`, then `DEEP`), as the monitor does. It has to: the CH376 forgets its current folder as soon as a file is opened, and loading `YMPLAY.BIN` is a file being opened. That is why the first version said there were no songs.
- **Older ROMs:** if there's no `JMP` at $FE18, YMPLAY uses the top folder.
- **When the drive isn't ready:** YMPLAY starts the drive afresh and tries again.
- **When the folder has no songs**, it says so and names the folder.

**The ROM changes it needs** (in the monitor's source, then rebuild the ROM):

1. Add the entry to the jump table, right after `SBC_LOAD` at $FE15:
   ```
   SBC_CWD:  jmp sbc_cwd          ; $FE18
   ```
   and the routine, anywhere in the ROM:
   ```
   sbc_cwd:  lda #<mon_cwd        ; A/Y = the current folder, 0-ended
             ldy #>mon_cwd
             rts
   ```
2. Clear the current folder at reset, where the monitor sets up its variables:
   ```
             lda #0
             sta mon_cwd          ; "" = the top folder
   ```
   `mon_cwd` is in RAM, so at power-up it holds whatever was there, and the monitor starts "in" a folder that doesn't exist. That is the `?File not found` from `L` straight after power-up (after `L /` it was cleared, so it worked). It isn't what stopped YMPLAY, but with `SBC_CWD` YMPLAY would see the same garbage, so fix both together.

| Keyboard | Gamepad | In the list | While playing |
|---|---|---|---|
| W / S | up / down | choose a song | W: loop the song on/off; S: back to the list |
| 1-60 | | choose a song by its number | |
| Space or Enter | A | play the chosen song | pause / go on |
| N or D | right | | next song |
| P or A | left | | previous song |
| L | | | loop the song on/off |
| V | | | the level bars on/off |
| Esc | | | back to the list |
| Q | | quit | quit |

**The level bars:** while a song plays, a bar for each channel (A, B, C) jumps to its level and falls back slowly, with a peak mark that waits a moment, then drops. There is no sound to measure, so the levels come from the registers as they are written: a channel's volume, or for a channel on the envelope, the envelope's level, worked out from its shape and period. A very fast repeating envelope, such as a buzz bass, shows as a steady bar. Under each bar, `T`, `N` and `E` show whether the channel has its tone, noise and envelope on, with a `.` for each that is off.
- **Kept light:** only the cells that changed are sent, a few a frame. A typical song sends a few hundred bytes a second, so the frames stay on time even at 200 frames a second.
- **Plain text:** `V` turns the bars off.

**Looping:** with looping on (LOOP is shown), the song goes back to its loop point when it ends, as it would in the game or demo it came from, and plays until you move on.

### How it works

- **Reading:** the song is read from the drive into a 4 KB ring buffer ($6000-$6FFF), one 64-byte block per frame, so the drive is never waited on while the music plays.
- **Timing:** each frame (normally 1/50 s) is timed by the VIA's timer 2, polled, with its interrupt left off. The timer is read when it runs out, and a late frame is made up in the next one, so the tempo doesn't drift. Timer 1 and the gamepad are left alone.
- **USB code:** YMPLAY has its own small CH376 reading code (`ch376r.s`), because `SBC_LOAD` loads whole files and a song can be bigger than memory. It doesn't restart the drive unless it has to. `ch_enter` walks a folder path a level at a time.
- **Tests:** `test/test_ay.py` covers folders too. The emulated drive is a host folder with sub-folders, and like the real chip it forgets its current folder once a file is opened. The emulated ROM gives a folder through `SBC_CWD`. The tests check that YMPLAY started in `MUSIC` lists and plays only `MUSIC`'s songs, even when a song of the same name is in the top folder; that it works two levels down, in the top folder, and with an old ROM (no `SBC_CWD`); that it restarts the drive when it isn't ready; and that a missing folder is reported by name. They also check that the level bars are drawn in block graphics, that `V` turns them off, and that the frames stay on time with them on.

## PIANO

```
L PIANO 0500
R
```

Two rows of the keyboard are two octaves of a piano, laid out like a tracker's:

```
  S D   G H J          2 3   5 6 7   9 0
 Z X C V B N M ,      Q W E R T Y U I O P
 (C of the octave ...  Q is the same C as ",", up to E two octaves up)
```

The screen shows a piano keyboard with these letters on its keys, and each key lights up while its note sounds. Under it, the three channels show their notes and volumes.

| Key | |
|---|---|
| `[` `]` or Tab | choose the sound |
| `-` `=` | octave down / up (1-6; Z is C of it) |
| space | all notes off |
| Esc | quit (the arrow keys send Esc too, so leave them alone) |

**The sounds:**

| Sound | |
|---|---|
| PIANO | struck, then fades over about a second |
| HARP | a short pluck |
| ORGAN | steady while held, a quick release |
| STRINGS | swells in, with vibrato after a moment |
| CHIP | the octave above every other frame: the classic chip lead |
| CHORD | one key plays a major chord, a note a frame (an arpeggio) |
| BUZZ | the chip's envelope as a saw wave at the note: a buzzy bass. One note at a time, on channel A |
| DRUMS | each pair of keys is a drum: Z S kick, X D snare, C V closed hi-hat, G B open hi-hat, H N tom (its pitch follows the key), J M crash, and the same again up the keyboard |

- **Notes end by themselves:** the terminal says when a key is pressed, never when it is let go. So each sound has its own shape: an attack, a fall to a sustain level, how long that lasts, then the release.
- **Holding a key still holds the note:** the keyboard repeats a held key, and a repeat of a note that is still sounding keeps it going instead of starting it again. The first repeat comes about half a second after the press, so with PIANO, HARP, CHIP and CHORD it strikes the note once more; ORGAN, STRINGS and BUZZ allow for that and just carry on.
- **Three notes at once,** one for each channel. A new note takes a free channel, or the one that has been sounding longest.
- **Your own sounds:** they are in `ins_tab` in `piano.s`, 16 bytes each, with the meaning of each byte above the table.

## SEQ

```
L SEQ 0500
R
```

A small "Fruity Loops": a grid of 16 steps (16th notes) by 7 tracks. Five are drums (KICK, SNARE, HI-HAT, OPEN HAT, CRASH) and two play notes (BASS and LEAD), each with one of PIANO's sounds. There are 4 patterns, A to D. Playing goes through them from A to the last one with anything in it, then round again, so a song is just patterns in a row.

To hear one straight away, copy `BEAT1.SEQ` (a demo) next to `SEQ.BIN` on the drive, then press `F`, `L`, `1` and Enter.

| Key | |
|---|---|
| arrows | move: up/down the tracks, left/right the steps |
| note keys | on BASS or LEAD, a note (the same keys as PIANO: `Z S X D C V G B H N J M ,` and `Q 2 W 3 E R 5 T 6 Y 7 U I 9 O 0 P`). You hear it, and the cursor moves on a step, so you can type a line in. On a drum track, any note key puts the drum on |
| space | a drum on/off; a note out |
| `.` | hold the note before on through this step (shown as `-`) |
| Backspace | out, and back a step |
| Enter | play / stop |
| `;` | play all the patterns, or just the one on screen |
| `-` `=` | tempo, 40-250 |
| `[` `]` | the octave of the note keys |
| `K` `L` | the pattern on screen: A B C D |
| Tab | on the BASS or LEAD row: its next sound |
| `F` | files: `S` save, `L` load (`BEAT1.SEQ` to `BEAT9.SEQ` in the monitor's current folder), `N` new, `C` copy the pattern before into this one |
| Esc | quit (it asks first) |

- **The channels:** BASS plays on channel A, LEAD on B, and the drums share C. When a step has more than one drum, one plays: kick, then snare, crash, open hat, hi-hat.
- **Notes last a step,** or longer when the steps after hold them on with `.`. BASS starts as BUZZ, LEAD as CHIP.
- **Timing:** the steps come from the tempo with a running count, so they don't drift: at 120, a step is exactly 1/8 s on average. A step can be up to 1/100 s early or late.
- **The file:** 200 bytes: `SEQ1`, the tempo, the BASS and LEAD sounds, a spare byte, then for the 4 patterns: the drums (a bit for each), the BASS notes and the LEAD notes (a note number, $FF for none, $FE held on).
- **The gamepad:** it types W A S D and space, which are note keys here, so use the keyboard.

## The .AYS format

All numbers are little endian.

| Offset | Contents |
|---|---|
| 0 | `AYS1` |
| 4 | frames a second (usually 50) |
| 5 | 0 |
| 6 | number of frames (4 bytes) |
| 10 | loop frame (4 bytes) |
| 14 | 0, 0 |
| 16 | title (32 bytes, padded with zeros) |
| 48 | author (32 bytes, padded with zeros) |
| 80 | zeros up to 128 |
| 128 | the frames: 14 bytes each, the values for registers 0-13 |

In a frame, register 13 is $FF when it is not to be written, because writing it restarts the envelope.

## The driver for your own programs

`ay.s` can be included in any program (`.include "ay.s"`, after `sbc_api.inc`). It brings its note table, `ay_notes.inc`, with it.

| Routine | Does |
|---|---|
| `ay_write` | register X = A (keeps A, X, Y) |
| `ay_silence` | everything quiet |
| `ay_regs` | registers 0-13 from the 14 bytes at (`ay_ptr`); register 13 only if it isn't $FF |
| `ay_tone` | channel X (0-2): tone period A (low) / Y (high); frequency = 2 MHz / (16 x period) |
| `ay_note` | channel X: note A (0 = C1 ... 45 = A4 440 Hz ... 95 = B8) |
| `ay_volume` | channel X: volume A (0-15; 16 = follow the envelope) |
| `ay_mixer` | register 7 = A (0 bits turn on: bits 0-2 tone A-C, 3-5 noise A-C) |

Envelope shapes are named `ENV_DECAY`, `ENV_TRIANGLE` and so on. One envelope ramp lasts 256 x period / 2 MHz.

The driver writes to the card only with plain `STA`/`STX`. An indexed store (`STA $7F23,X`) makes an extra read of the address first, and because the card decodes the address without looking at R/W, that read would act as a write.

The note table is made for a 2 MHz chip clock: `python tools/gen_notes.py [clock] > ay_notes.inc`.

## Sound in games: `sfx.s`

`sfx.s` is a small engine for music and sound effects, and every game includes it. Their make files pass `-I ..`, so the line is `.include "ay/sfx.s"`. It costs about 830 bytes of code plus 123 of variables, and its note table is a single octave of 24 bytes.

- **No interrupt needed:** the game calls `sfx_poll` often: in its main loop and its delay loops, in most games for every character it sends, and in DOOM for every column it draws. `sfx_poll` keeps A, X, Y and the flags, so it can go anywhere. `sfx_poll` checks the VIA's **timer 2** (polled, with its interrupt left off) and runs the sound 50 times a second. If a call comes late, the next tick is shortened by the same amount, so music keeps its tempo even when a frame takes long to draw.
- **Six voices on three channels:** voices 0-2 are the *background* (music, the saucer's hum) and voices 3-5 the *foreground* (effects, jingles) on channels A, B and C. While a foreground voice plays, its channel plays it instead of the background voice. The background voice keeps running unheard and comes back when the effect ends, so the music never loses its place.
- **Priorities:** `sfx_play` (A = script, X = voice) doesn't interrupt a script of higher priority on that voice.
- **Routines:**

| Routine | Does |
|---|---|
| `sfx_init` | once at the start |
| `sfx_poll` | call it often (keeps A, X, Y and the flags) |
| `sfx_play` | start a script (A = script, X = voice) |
| `sfx_stop` | stop a voice |
| `sfx_off` | stop all voices |
| `sfx_hush` | silence before a pause |
| `sfx_mute` | 0 = sound on, 1 = muted |
| `sfx_snd` | start script A on its own voice, kept in the high 4 bits of its priority byte; keeps A, X, Y (with `SFX_SND = 1` before the include) |
| `sfx_toggle` | sound on / off, for the M key (with `SFX_SND`) |

- **Scripts:** a script is a few bytes that run 50 times a second. Notes take a byte each (`SX_NOTE(n)`), and so do waits (`SX_WAIT(t)`). There are also commands for volume, decay, a tone period, a pitch sweep, noise, the mixer, loops, jumps, rests and a note length (`SX_LEN`, so that a tune is one byte per note). The full list is at the top of `sfx.s`.
- **Writing sounds:** INVADERS and SNAKE write their scripts by hand at the end of their .s files. SMB writes them in a note language (`c5/2 e5 g5 [a4 c5]2 ...`) in `../smb/sound.py`. The other seven games use the same language in `tools/game_sounds.py`, one function each. `python game_sounds.py` (or `python game_sounds.py rocks`) writes each game's `<game>_sound.inc`. `tools/sndgen.py` holds the note language and the writer.
- **Music:** the tunes are written for the games, except two that are public domain. STACKER plays "Korobeiniki" (a Russian folk song, 1861) and MINER MOS plays "In the Hall of the Mountain King" (Grieg, 1875).
- **Memory:** a game can put the variables at a fixed address with `SFX_VARS = $0100` before the include. SMB does this because it has no room left anywhere else.

## Files

| File | |
|---|---|
| `aytest.s` | AYTEST |
| `ymplay.s` | YMPLAY |
| `piano.s` | PIANO |
| `seq.s`, `BEAT1.SEQ` | SEQ, and a demo song for it |
| `synth.s` | the sounds of PIANO and SEQ |
| `ay.s`, `ay_notes.inc` | the driver and its note table |
| `ch376r.s` | reading (and for SEQ, writing) files on the USB drive (CH376) |
| `sfx.s` | the sound engine for the games |
| `tools/game_sounds.py`, `tools/sndgen.py` | the games' music and effects (all but INVADERS, SNAKE and SMB): writes `<game>/<game>_sound.inc` |
| `common.s` | printing, keys, delays |
| `tools/ym2ays.py` | the .YM to .AYS converter |
| `tools/gen_notes.py` | makes `ay_notes.inc` |
| `test/sim.py`, `test/test_ay.py` | emulator tests (see below) |
| `test/aysnd.py` | the card and timer 2 for the games' emulators (`SOUND=1`); it can also write what was played to a .WAV |
| `test/gamesound.py` | runs a game's own bot test with the card modelled. It checks the sound's timing and counts the sounds played. Run it from the game's folder: `python3 ../ay/test/gamesound.py rocks OUTDIR` |

## Building

```
make.bat          all four programs, for CLOCK_MHZ in ..\sbc_api.inc
make.bat 1        for a 1 MHz CPU clock
```

The CPU clock only changes the delays and the frame timer. The card's own 2 MHz clock is separate.

## Tests

`test/test_ay.py` runs the programs in an emulator (py65) that models the card, the VIA's timer 2 and the CH376 with a folder of files. It checks:

- **AYTEST:** every test's register writes.
- **YMPLAY's register writes:** every frame of made-up songs written in order with the right values; register 13 written only when it should be.
- **YMPLAY's timing:** frames 1/50 s apart (1/60 s for 60 Hz songs).
- **YMPLAY's controls:** looping, pause, next, previous, back to the list and quit.
- **Hard cases:** a song longer than one read (64 KB), a slow drive, and no drive.
- **PIANO:** a chord on three channels with the right notes, notes fading by themselves, a fourth note taking the oldest channel, ORGAN held by key repeats (and stopping without them), PIANO not struck again by every repeat, the kick's falling pitch, the hi-hat's noise, BUZZ's envelope, CHORD's notes, the octave keys, and Esc.
- **SEQ:** a beat played at the right tempo (and again after the tempo changes), the kick winning over the hi-hat on the same step, saving to the monitor's folder and loading back, patterns taking turns (and `;` keeping to one), and Esc asking before it quits. The emulated drive writes files too.

Given a folder of .YM files, it also converts and plays a real song. Build with `sh b.sh` first.

```
PY65=path/to/py65 python3 test/test_ay.py [folder of .YM files]
```
