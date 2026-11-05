@echo off
rem Build MINER.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. miner.s -o miner.o -l miner.lst || goto fail
ld65 -C miner.cfg miner.o -o MINER.BIN -m miner.map || goto fail
del miner.o
echo MINER.BIN built.
exit /b 0
:fail
echo MINER.BIN: build failed.
exit /b 1
