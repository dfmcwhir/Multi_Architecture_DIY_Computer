@echo off
rem Build DOOM.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
