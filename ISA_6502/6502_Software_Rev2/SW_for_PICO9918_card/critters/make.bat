@echo off
rem Build CRITTERS.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The graphics: python gen_pico.py (critters_gfx.inc)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. critters.s -o critters.o -l critters.lst || goto fail
ld65 -C critters.cfg critters.o -o CRITTERS.BIN -m critters.map || goto fail
del critters.o
echo CRITTERS.BIN built.
exit /b 0
:fail
echo CRITTERS.BIN: build failed.
exit /b 1
