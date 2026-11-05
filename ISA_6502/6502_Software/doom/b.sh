# test build: also writes doom.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS doom.s -o doom.o -l doom.lst && ld65 -C doom.cfg doom.o -o DOOM.BIN -m doom.map -Ln doom.lbl
