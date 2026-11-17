@echo off
rem Build SMB.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65 on the PATH).
rem   make.bat        the clock from CLOCK_MHZ in ..\sbc_api.inc (it only
rem   make.bat 4      matters to the sound engine's timer: the game is timed
rem                   by the VDP's frames)
rem The pictures: python gen_pico.py (smb_pico.inc, from gen.py's pictures);
rem the levels: python gen.py (WORLD1.SMB ... WORLD5.SMB, from levels.py).
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. smb.s -o smb.o -l smb.lst || goto fail
ld65 -C smb.cfg smb.o -o SMB.BIN -m smb.map || goto fail
del smb.o
echo SMB.BIN built.
exit /b 0
:fail
echo SMB.BIN: build failed.
exit /b 1
