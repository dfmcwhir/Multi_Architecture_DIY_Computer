# test build: also writes muncher.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS muncher.s -o muncher.o -l muncher.lst && ld65 -C muncher.cfg muncher.o -o MUNCHER.BIN -m muncher.map -Ln muncher.lbl
