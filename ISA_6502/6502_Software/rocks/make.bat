@echo off
rem Build ROCKS.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
