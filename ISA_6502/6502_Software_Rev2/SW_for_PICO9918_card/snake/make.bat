@echo off
rem Build SNAKE.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The font: python gen_pico.py (makes snake_gfx.inc)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. snake.s -o snake.o -l snake.lst || goto fail
ld65 -C snake.cfg snake.o -o SNAKE.BIN -m snake.map || goto fail
del snake.o
echo SNAKE.BIN built.
exit /b 0
:fail
echo SNAKE.BIN: build failed.
exit /b 1
