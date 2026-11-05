@echo off
rem Build INVADERS.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. invaders.s -o invaders.o -l invaders.lst || goto fail
ld65 -C invaders.cfg invaders.o -o INVADERS.BIN -m invaders.map || goto fail
del invaders.o
echo INVADERS.BIN built.
exit /b 0
:fail
echo INVADERS.BIN: build failed.
exit /b 1
