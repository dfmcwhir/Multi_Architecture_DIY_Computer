# make      builds AYTEST.BIN, YMPLAY.BIN, PIANO.BIN and SEQ.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

all: AYTEST.BIN YMPLAY.BIN PIANO.BIN SEQ.BIN

AYTEST.BIN: aytest.s ay.s ay_notes.inc common.s ay.cfg ../sbc_api.inc
	$(CA65) -I .. $(DEFS) aytest.s -o aytest.o -l aytest.lst
	$(LD65) -C ay.cfg aytest.o -o AYTEST.BIN -m aytest.map

YMPLAY.BIN: ymplay.s ay.s ay_notes.inc common.s ch376r.s ay.cfg ../sbc_api.inc
	$(CA65) -I .. $(DEFS) ymplay.s -o ymplay.o -l ymplay.lst
	$(LD65) -C ay.cfg ymplay.o -o YMPLAY.BIN -m ymplay.map

PIANO.BIN: piano.s synth.s ay.s ay_notes.inc common.s ay.cfg ../sbc_api.inc
	$(CA65) -I .. $(DEFS) piano.s -o piano.o -l piano.lst
	$(LD65) -C ay.cfg piano.o -o PIANO.BIN -m piano.map

SEQ.BIN: seq.s synth.s ay.s ay_notes.inc common.s ch376r.s ay.cfg ../sbc_api.inc
	$(CA65) -I .. $(DEFS) seq.s -o seq.o -l seq.lst
	$(LD65) -C ay.cfg seq.o -o SEQ.BIN -m seq.map

ay_notes.inc: tools/gen_notes.py
	python3 tools/gen_notes.py > ay_notes.inc

clean:
	rm -f *.o *.lst *.map *.lbl AYTEST.BIN YMPLAY.BIN PIANO.BIN SEQ.BIN
