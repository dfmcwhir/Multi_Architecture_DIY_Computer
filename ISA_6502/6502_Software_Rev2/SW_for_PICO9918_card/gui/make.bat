@echo off
rem Build GUI.BIN (the file manager) with the cc65 tools (ca65 and ld65 on
rem the PATH).  The graphics: python gen_gui.py (makes gui_gfx.inc)
setlocal
ca65 -I .. install.s -o install.o -l install.lst || goto fail
ca65 -I .. gui.s -o gui.o -l gui.lst || goto fail
ld65 -C gui.cfg install.o gui.o -o GUI.BIN -m gui.map || goto fail
del install.o gui.o
echo GUI.BIN built.
exit /b 0
:fail
echo GUI.BIN: build failed.
exit /b 1
