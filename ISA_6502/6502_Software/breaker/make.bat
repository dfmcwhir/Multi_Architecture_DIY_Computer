@echo off
rem Build BREAKER.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
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
