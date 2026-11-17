@echo off
rem Build MOUSETEST.BIN with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. mousetest.s -o mousetest.o -l mousetest.lst || goto fail
ld65 -C mousetest.cfg mousetest.o -o MOUSETEST.BIN -m mousetest.map || goto fail
del mousetest.o
echo MOUSETEST.BIN built.
exit /b 0
:fail
echo MOUSETEST.BIN: build failed.
exit /b 1
