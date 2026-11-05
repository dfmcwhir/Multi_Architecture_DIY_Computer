# test build: also writes miner.lbl (labels) for the test scripts
ca65 -g -I .. $DEFS miner.s -o miner.o -l miner.lst && ld65 -C miner.cfg miner.o -o MINER.BIN -m miner.map -Ln miner.lbl
