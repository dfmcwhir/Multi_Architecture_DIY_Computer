@echo off
rem Build MUNCHER.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The maze: python gen.py > muncher_data.inc; the PICO9918 graphics: python gen_pico.py
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. muncher.s -o muncher.o -l muncher.lst || goto fail
ld65 -C muncher.cfg muncher.o -o MUNCHER.BIN -m muncher.map || goto fail
del muncher.o
echo MUNCHER.BIN built.
exit /b 0
:fail
echo MUNCHER.BIN: build failed.
exit /b 1
