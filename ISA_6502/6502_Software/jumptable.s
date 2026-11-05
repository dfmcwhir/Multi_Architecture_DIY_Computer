; ============================================================================
; jumptable.s - FIXED entry points for programs you load with the monitor
;
; The addresses of the BIOS routines move every time the ROM is rebuilt, so a
; program that you assemble separately (and load with  L NAME ADDR  or
; LOADRAW) must not call them directly.  This table is always at $FE00 and
; every entry is a 3 byte JMP, so  JSR $FE03  always means "print a character".
; sbc_api.inc has the same addresses as ca65 equates for your own programs.
;
;   $FE00  JT_CHRIN      get a character: carry set + A = character, or carry
;                        clear if nothing is waiting (keyboard, serial, gamepad)
;   $FE03  JT_CHROUT     print the character in A (A, X and Y are preserved)
;   $FE06  JT_MENU       back to the boot menu ([C]old [W]arm [M]onitor)
;   $FE09  JT_COLD       EhBASIC cold start
;   $FE0C  JT_WARM       EhBASIC warm start
;   $FE0F  JT_MONITOR    the monitor prompt (same as JMP $FF00)
;   $FE12  JT_PADSTATE   A = gamepad buttons held right now, bit n = button n
;                        (0=A 1=B 2=Select 3=Start 4=Up 5=Down 6=Left 7=Right)
;                        Only registers A and flags are changed.
;   $FE15  JT_LOAD       load a whole file from the USB drive into RAM, silently
;                        (A/Y = parameter block, see SBC_LOAD in monitor_cmds.s)
; Add new entries at the END so the old addresses never change.
; ============================================================================
.segment "JUMPTAB"
JT_CHRIN:       jmp     CHRIN
JT_CHROUT:      jmp     CHROUT
JT_MENU:        jmp     MENU
JT_COLD:        jmp     LAB_COLD
JT_WARM:        jmp     LAB_WARM
JT_MONITOR:     jmp     WOZ_ENTRY
JT_PADSTATE:    jmp     PAD_STATE
JT_LOAD:        jmp     SBC_LOAD
JT_CWD:         jmp     sbc_cwd         ; $FE18  (new, always last)

sbc_cwd:        lda     #<mon_cwd       ; A/Y = the current folder
                ldy     #>mon_cwd
                rts

; RESET_CWD - the reset vector comes here: start in the top folder ("" in
; mon_cwd, which is RAM and random at power-up), then the normal RESET.  (Kept
; here rather than in RESET so the BIOS code doesn't move: see README)
RESET_CWD:      lda     #0
                sta     mon_cwd
                jmp     RESET
