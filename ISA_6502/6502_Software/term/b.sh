# test build: also writes the label file for the tests
ca65 -g -I .. $DEFS term.s -o term.o -l term.lst && ld65 -C term.cfg term.o -o TERM.BIN -m term.map -Ln term.lbl
