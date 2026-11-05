# make      builds SMB.BIN (needs ca65/ld65 and ../sbc_api.inc); the WORLDn.SMB
#           files come from gen.py (python3 gen.py), and are in the zip
CA65 ?= ca65
LD65 ?= ld65

all: SMB.BIN SMBSW.BIN

SMB.BIN: smb.s smb.cfg ../sbc_api.inc smb_data.inc smb_sound.inc ../ay/sfx.s
	$(CA65) -I .. $(DEFS) smb.s -o smb.o -l smb.lst
	$(LD65) -C smb.cfg smb.o -o SMB.BIN -m smb.map

SMBSW.BIN: smb.s smb.cfg ../sbc_api.inc smb_data.inc
	$(CA65) -I .. $(DEFS) -D SOFT_SPRITES=1 smb.s -o smbsw.o
	$(LD65) -C smb.cfg smbsw.o -o SMBSW.BIN -m smbsw.map

smb_data.inc WORLD1.SMB SMBSPR.SMB: gen.py levels.py
	python3 gen.py

smb_sound.inc: sound.py
	python3 sound.py > smb_sound.inc

clean:
	rm -f smb.o smbsw.o smb.lst smb.map smbsw.map SMB.BIN SMBSW.BIN
