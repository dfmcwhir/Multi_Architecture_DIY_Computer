@echo off
rem Build GRABBER.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The game's pictures: python gen.py > grabber_data.inc; the art: python gen_pico.py
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. grabber.s -o grabber.o -l grabber.lst || goto fail
ld65 -C grabber.cfg grabber.o -o GRABBER.BIN -m grabber.map || goto fail
del grabber.o
echo GRABBER.BIN built.
exit /b 0
:fail
echo GRABBER.BIN: build failed.
exit /b 1
