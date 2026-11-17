@echo off
rem Build INVADERS.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The pictures are in invaders_gfx.inc, made by  python gen.py
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
