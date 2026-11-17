@echo off
rem make.bat - build the CPU Rev2 ROM (rom.bin)
rem   make                  the settings in config.inc
rem   make 4000             CPU_KHZ = 4000 (4 MHz)
rem   make 4000 esp32       ... and the display card: none, term, pico or esp32
set OPT=
if not "%1"=="" set OPT=-D CPU_KHZ=%1
if /i "%2"=="none"  set OPT=%OPT% -D CON_DISPLAY=0
if /i "%2"=="term"  set OPT=%OPT% -D CON_DISPLAY=1
if /i "%2"=="pico"  set OPT=%OPT% -D CON_DISPLAY=2
if /i "%2"=="esp32" set OPT=%OPT% -D CON_DISPLAY=3
ca65 %OPT% main.s -o main.o -l main.lst
if errorlevel 1 goto failed
ld65 -C sbc.cfg main.o -o rom.bin -m rom.map -Ln rom.lbl
if errorlevel 1 goto failed
echo rom.bin built
goto :eof
:failed
echo *** build FAILED ***
