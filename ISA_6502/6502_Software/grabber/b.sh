# test build: also writes grabber.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS grabber.s -o grabber.o -l grabber.lst && ld65 -C grabber.cfg grabber.o -o GRABBER.BIN -m grabber.map -Ln grabber.lbl
