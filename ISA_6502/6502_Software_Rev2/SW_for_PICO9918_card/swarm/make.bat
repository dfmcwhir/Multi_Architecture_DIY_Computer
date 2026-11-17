@echo off
rem Build SWARM.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The paths: python gen.py > swarm_data.inc; the graphics: python gen_pico.py
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. swarm.s -o swarm.o -l swarm.lst || goto fail
ld65 -C swarm.cfg swarm.o -o SWARM.BIN -m swarm.map || goto fail
del swarm.o
echo SWARM.BIN built.
exit /b 0
:fail
echo SWARM.BIN: build failed.
exit /b 1
