# test build: also writes stacker.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS stacker.s -o stacker.o -l stacker.lst && ld65 -C stacker.cfg stacker.o -o STACKER.BIN -m stacker.map -Ln stacker.lbl
