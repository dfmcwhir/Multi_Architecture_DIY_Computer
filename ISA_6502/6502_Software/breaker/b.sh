# test build: also writes breaker.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS breaker.s -o breaker.o -l breaker.lst && ld65 -C breaker.cfg breaker.o -o BREAKER.BIN -m breaker.map -Ln breaker.lbl
