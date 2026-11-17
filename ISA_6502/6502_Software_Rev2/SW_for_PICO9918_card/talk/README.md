# TALK - text to speech on the SPO256-AL2

Type a sentence and the SPO256 on the AY sound card says it. It works with any display and loads at $0800 like the games, so you can start it from the file manager. Quitting goes back there.

```
> Hello, this is the 6502 talking.
> /F STORY.TXT
```

| Command | |
|---|---|
| any text | speak it |
| `/F NAME` | speak a text file from the current drive and folder; the text is shown as it goes (Esc or Q stops it between chunks) |
| `/P` | show the allophones as they are spoken (on / off) |
| `/A ...` | speak allophones directly, by name or number: `/A HH1 EH LL OW` or `/A 27 7 45 53` |
| `/?` | help |
| `/Q` | quit |

If no SPO256 answers at $7F26 at start-up, TALK says so and only shows the allophones.

## How it works

1. **Clean-up.**
   - Letters become upper case.
   - Numbers up to 65535 become words ("1984" → ONE THOUSAND NINE HUNDRED EIGHTY FOUR); longer ones are read digit by digit.
   - `, ; :` become a short pause, `. !` a long one; `?` and `-` are kept.
2. **Letters to sounds.** These are the US Naval Research Laboratory's letter-to-sound rules: 329 rules like "A before a consonant and E sounds like EY" (Elovitz, Johnson, McHugh and Shore, *NRL Report 7948*, 1976; public domain).
   - The paper reports about 90% of words right. English spelling being what it is, some words will come out oddly.
   - The rule text is Greg Kennedy's typed-up copy (public domain, `NRL_RULES_LICENSE.txt`).
   - Before the rules, a short word list (`words.txt`) is checked. It holds the number words, which the rules get wrong (HUNDRED came out "hun-drd").
3. **Sounds to SPO256 allophones.** The SPO256 has several versions of many sounds, and TALK picks one by what is around it:
   - K: KK1 before E/I-type vowels, KK3 before other vowels, KK2 elsewhere. G works the same way with GG1/GG2/GG3.
   - T and D: TT2 and DD2 before a vowel, TT1 and DD1 elsewhere.
   - At the start of a word: BB2, NN2, RR1, DH1 and YY2.
   - UW1 after Y ("you"), UW2 elsewhere. HH1 before front vowels, HH2 elsewhere.
   - R-coloured vowels: AR, OR, XR (air), YR (ear). "-le" at a word's end becomes EL.
   - A short pause (PA1 or PA2) goes in before B D G J or P T K CH inside a word.
   - Pauses: PA3 between words, PA4 at commas, PA5 at full stops.
4. **Speaking.** The allophones are handed to `SBC_SAY` up to 200 at a time. The ROM feeds the chip from its 64-byte queue on the VIA interrupt, so a 100-character line takes about 0.15 s to work out at 4 MHz (0.3 s at 2 MHz) before the speech starts. Long text is done in chunks of about 190 characters.

The choice of allophones (step 3) follows the SPO256 data sheet's notes as best I know them. It hasn't been heard yet, so if something sounds wrong, tell me the word and what it says (`/P` shows the allophones).

## Making it say a word better

Add the word to `words.txt` with its phonemes, using the NRL set: IY IH EY EH AE AA AO OW UH UW ER AX AH AY AW OY Y P B T D K G F V TH DH S Z SH ZH HH CH JH M N NX L W WH R. For example:

```
COMPUTER = K AX M P Y UW T ER
```

Then run `python gen_rules.py` (it rebuilds `rules.inc`) and `make.bat`. To try sounds directly, use `/A`.

## Files

| File | |
|---|---|
| `talk.s` | the program |
| `rules.inc` | made by `gen_rules.py` from `nrl_rules.json` and `words.txt`: the rules, the word list, the allophone tables |
| `tts_ref.py` | the same conversion in Python (`python tts_ref.py "some text"` prints the phonemes and allophones). The test checks TALK against it. |
| `test_talk.py` | emulator test: 17 sentences (numbers, punctuation, random words) must give exactly the reference's allophones; /P, /A, /F (a 6-chunk file), /Q, no chip |
| `talk.cfg`, `make.bat` | build (ca65 / ld65) |

TALK.BIN runs from $0800 to $258B, with variables up to about $2940. The file buffer runs from there to $7EFF, about 21 KB.

The converter was checked against Kennedy's Perl version of the NRL rules on 6,000 words, and every one gave the same phonemes. It uses a greedy matcher, as the original C did. Two rule patterns that need back-tracking (`^:` and `##`) were rewritten as the classes "one or more consonants" and "two or more vowels", which give the same results.
