@echo off
rem Build GRABBER.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
