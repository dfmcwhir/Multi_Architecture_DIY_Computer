This a port of tinybasic from https://github.com/skiselev/minimax8085/tree/master/software/tinybasic with monitor program and the ch376 usb card support.

Assemble with ASW using commands:
asl -cpu 8085 -L -o boot_bios.p boot_bios.asm
p2bin boot_bios.p boot_bios.bin -r 0x0000-0x7FFF -l 0xFF

