@echo off
rem Build MINER.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The rooms and pictures: python gen.py > miner_data.inc; the colours, sprites and font: python gen_pico.py
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
