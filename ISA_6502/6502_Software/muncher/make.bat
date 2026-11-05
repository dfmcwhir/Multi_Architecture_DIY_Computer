@echo off
rem Build MUNCHER.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
