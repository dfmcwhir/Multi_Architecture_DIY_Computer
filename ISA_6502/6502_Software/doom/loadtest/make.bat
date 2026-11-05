@echo off
rem Build LOADTEST.BIN with the cc65 tools (ca65 and ld65 must be on the PATH).
setlocal
ca65 -I ..\.. loadtest.s -o loadtest.o || goto fail
ld65 -C loadtest.cfg loadtest.o -o LOADTEST.BIN || goto fail
del loadtest.o
echo LOADTEST.BIN built.
exit /b 0
:fail
echo LOADTEST.BIN: build failed.
exit /b 1
