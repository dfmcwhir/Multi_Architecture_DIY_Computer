# test build: also writes rocks.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS rocks.s -o rocks.o -l rocks.lst && ld65 -C rocks.cfg rocks.o -o ROCKS.BIN -m rocks.map -Ln rocks.lbl
