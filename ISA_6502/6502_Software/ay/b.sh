# test build: also writes the label files for the test scripts
for p in aytest ymplay piano seq; do
  [ -f $p.s ] || continue
  ca65 -g -I .. $DEFS $p.s -o $p.o -l $p.lst && ld65 -C ay.cfg $p.o -o $(echo $p | tr a-z A-Z).BIN -m $p.map -Ln $p.lbl || exit 1
done
