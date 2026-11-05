@echo off
rem Build SMB.BIN and SMBSW.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. smb.s -o smb.o -l smb.lst || goto fail
ld65 -C smb.cfg smb.o -o SMB.BIN -m smb.map || goto fail
ca65 %DEFS% -D SOFT_SPRITES=1 -I .. smb.s -o smbsw.o || goto fail
ld65 -C smb.cfg smbsw.o -o SMBSW.BIN -m smbsw.map || goto fail
del smb.o smbsw.o
echo SMB.BIN (terminal sprites) and SMBSW.BIN (for older terminals) built.
exit /b 0
:fail
echo SMB.BIN: build failed.
exit /b 1
