@echo off
rem Build STACKER.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The pictures are in stacker_gfx.inc, made by  python gen.py
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. stacker.s -o stacker.o -l stacker.lst || goto fail
ld65 -C stacker.cfg stacker.o -o STACKER.BIN -m stacker.map || goto fail
del stacker.o
echo STACKER.BIN built.
exit /b 0
:fail
echo STACKER.BIN: build failed.
exit /b 1
