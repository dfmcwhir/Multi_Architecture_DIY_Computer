Assemble with ASW using commands:
asl -cpu 8085 -L -o boot_bios.p boot_bios.asm
p2bin boot_bios.p boot_bios.bin -r 0x0000-0x7FFF -l 0xFF

