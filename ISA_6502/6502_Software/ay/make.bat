@echo off
rem Build AYTEST.BIN, YMPLAY.BIN, PIANO.BIN and SEQ.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. aytest.s -o aytest.o -l aytest.lst || goto fail
ld65 -C ay.cfg aytest.o -o AYTEST.BIN -m aytest.map || goto fail
ca65 %DEFS% -I .. ymplay.s -o ymplay.o -l ymplay.lst || goto fail
ld65 -C ay.cfg ymplay.o -o YMPLAY.BIN -m ymplay.map || goto fail
ca65 %DEFS% -I .. piano.s -o piano.o -l piano.lst || goto fail
ld65 -C ay.cfg piano.o -o PIANO.BIN -m piano.map || goto fail
ca65 %DEFS% -I .. seq.s -o seq.o -l seq.lst || goto fail
ld65 -C ay.cfg seq.o -o SEQ.BIN -m seq.map || goto fail
del aytest.o ymplay.o piano.o seq.o
echo AYTEST.BIN, YMPLAY.BIN, PIANO.BIN and SEQ.BIN built.
exit /b 0
:fail
echo build failed.
exit /b 1
