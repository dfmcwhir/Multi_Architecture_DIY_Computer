@echo off
rem Build VGADEMO.BIN (load and run at $0500). Needs ca65/ld65 from cc65 on the PATH.
rem Change the adapter address in vga.inc (VGA_BASE) first.
ca65 --cpu 65C02 vga.s -o vga.o || goto :error
ca65 --cpu 65C02 vgademo.s -o vgademo.o || goto :error
ld65 -C vgademo.cfg vgademo.o vga.o -o VGADEMO.BIN -m vgademo.map || goto :error
echo Built VGADEMO.BIN
goto :eof
:error
echo Build failed.
exit /b 1
