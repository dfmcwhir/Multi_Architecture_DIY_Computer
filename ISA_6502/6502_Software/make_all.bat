@echo off
rem Build every game, the sound card programs, TERM and EDIT (ca65 and ld65 must be on the PATH).
rem   make_all.bat      CPU clock from CLOCK_MHZ in sbc_api.inc
rem   make_all.bat 1    build them all for a 1 MHz clock instead
for %%g in (invaders snake critters muncher doom stacker rocks smb grabber breaker miner ay term edit) do (
    pushd %%g
    call make.bat %1
    popd
)
pushd doom\loadtest
call make.bat
popd
