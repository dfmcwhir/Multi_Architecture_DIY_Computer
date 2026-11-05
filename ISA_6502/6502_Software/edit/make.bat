@echo off
rem Build EDIT.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
rem   make.bat        CPU clock from CLOCK_MHZ in ..\sbc_api.inc
rem   make.bat 1      build for a 1 MHz clock instead (or 2, 4 ...)
setlocal
set DEFS=
if not "%~1"=="" set DEFS=-D CLOCK_MHZ=%~1
ca65 %DEFS% -I .. edit.s -o edit.o -l edit.lst || goto fail
ld65 -C edit.cfg edit.o -o EDIT.BIN -m edit.map || goto fail
del edit.o
echo EDIT.BIN built.
exit /b 0
:fail
echo EDIT.BIN: build failed.
exit /b 1
