# test build: also writes critters.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS critters.s -o critters.o -l critters.lst && ld65 -C critters.cfg critters.o -o CRITTERS.BIN -m critters.map -Ln critters.lbl
