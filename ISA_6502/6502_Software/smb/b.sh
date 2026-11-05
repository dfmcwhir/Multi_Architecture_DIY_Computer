# test build: SMB.BIN (the terminal draws the sprites) and SMBSW.BIN (the 6502 does),
# each with a label file for the test scripts (smb.lbl, smbsw.lbl)
ca65 -g -I .. $DEFS smb.s -o smb.o -l smb.lst && ld65 -C smb.cfg smb.o -o SMB.BIN -m smb.map -Ln smb.lbl && \
ca65 -g -I .. $DEFS -D SOFT_SPRITES=1 smb.s -o smbsw.o && ld65 -C smb.cfg smbsw.o -o SMBSW.BIN -m smbsw.map -Ln smbsw.lbl && rm -f smbsw.o
