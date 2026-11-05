# test build: also writes invaders.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS invaders.s -o invaders.o -l invaders.lst && ld65 -C invaders.cfg invaders.o -o INVADERS.BIN -m invaders.map -Ln invaders.lbl
