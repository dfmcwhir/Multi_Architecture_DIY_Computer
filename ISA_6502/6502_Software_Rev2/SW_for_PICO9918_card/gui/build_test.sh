#!/bin/sh
# (here: asm6502.py in place of ca65/ld65; same layout as gui.cfg)
set -e
cd "$(dirname "$0")"
python3 gen_gui.py >/dev/null
python3 /home/claude/tools/asm6502.py gui.s img.bin -s 0x1000 -I .. -l gui.lbl
python3 /home/claude/tools/asm6502.py install.s inst.bin -s 0x0800 -I ..
python3 -c "
i=open('inst.bin','rb').read(); g=open('img.bin','rb').read()
assert len(i)<=0x300; open('GUI.BIN','wb').write(i+bytes(0x300-len(i))+g)"
rm -f img.bin inst.bin
