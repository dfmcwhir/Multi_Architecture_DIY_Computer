# test build: also writes the label file for the tests
ca65 -g -I .. $DEFS edit.s -o edit.o -l edit.lst && ld65 -C edit.cfg edit.o -o EDIT.BIN -m edit.map -Ln edit.lbl
