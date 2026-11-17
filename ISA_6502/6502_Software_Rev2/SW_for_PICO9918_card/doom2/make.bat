@echo off
rem Build DOOM2.BIN with the cc65 tools (ca65 and ld65 on the PATH).
rem   make.bat        the clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for 4 MHz (the sound engine's timer is counted in cycles)
rem The tables and art: python gen_tables.py; the maps: python mklevels.py.
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. doom2.s -o doom2.o -l doom2.lst || goto fail
ld65 -C doom2.cfg doom2.o -o DOOM2.BIN -m doom2.map || goto fail
del doom2.o
echo DOOM2.BIN built.
exit /b 0
:fail
echo DOOM2.BIN: build failed.
exit /b 1
