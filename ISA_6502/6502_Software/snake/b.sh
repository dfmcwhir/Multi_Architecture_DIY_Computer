# test build: also writes snake.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS snake.s -o snake.o -l snake.lst && ld65 -C snake.cfg snake.o -o SNAKE.BIN -m snake.map -Ln snake.lbl
