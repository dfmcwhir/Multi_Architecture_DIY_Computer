@echo off
rem Build BREAKER.BIN (PICO9918 version) with the cc65 tools (ca65 and ld65
rem must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 4      build for a 4 MHz clock instead (or 1, 2 ...)
rem The graphics: python gen_pico.py (breaker_gfx.inc); the levels: python gen.py > breaker_data.inc
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. breaker.s -o breaker.o -l breaker.lst || goto fail
ld65 -C breaker.cfg breaker.o -o BREAKER.BIN -m breaker.map || goto fail
del breaker.o
echo BREAKER.BIN built.
exit /b 0
:fail
echo BREAKER.BIN: build failed.
exit /b 1
