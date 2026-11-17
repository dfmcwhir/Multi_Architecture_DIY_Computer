@echo off
rem Build ROCKS.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The shapes: python gen.py > rocks_data.inc; the font and tables: python gen_pico.py
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. rocks.s -o rocks.o -l rocks.lst || goto fail
ld65 -C rocks.cfg rocks.o -o ROCKS.BIN -m rocks.map || goto fail
del rocks.o
echo ROCKS.BIN built.
exit /b 0
:fail
echo ROCKS.BIN: build failed.
exit /b 1
