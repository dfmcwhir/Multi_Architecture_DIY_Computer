@echo off
rem Build SNAKE.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
