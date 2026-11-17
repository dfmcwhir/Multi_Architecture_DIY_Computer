@echo off
rem Build DOOM.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65 on the PATH).
rem   make.bat        the clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for 4 MHz (the sound engine's timer is counted in cycles)
rem The tables: python gen_tables.py > tables.inc; the font: python gen_font.py;
rem the colours: python gen_colours.py;
rem the maps: python mklevels.py.
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. doom.s -o doom.o -l doom.lst || goto fail
ld65 -C doom.cfg doom.o -o DOOM.BIN -m doom.map || goto fail
del doom.o
echo DOOM.BIN built.
exit /b 0
:fail
echo DOOM.BIN: build failed.
exit /b 1
