@ECHO OFF
REM Build IDE32.hex for the ATmega32 (run it in this folder).
REM AVR Studio 4 path below; for Microchip Studio, avrasm2.exe is in
REM   "C:\Program Files (x86)\Atmel\Studio\7.0\toolchain\avr8\avrassembler"
REM with the device files (m32def.inc) in its "include" folder: add  -I <that folder>
"C:\Program Files\Atmel\AVR Tools\AvrAssembler2\avrasm2.exe" -fI -W+ie -o IDE32.hex -l IDE32.lst -m IDE32.map ide32.asm
