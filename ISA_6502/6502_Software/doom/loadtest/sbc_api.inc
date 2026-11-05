; sbc_api.inc - fixed ROM entry points of the SBC (see jumptable.s)
; Use in your own ca65 programs:  .include "sbc_api.inc"
SBC_CHRIN       = $FE00         ; carry set + A = char, carry clear = none waiting
SBC_CHROUT      = $FE03         ; print A (A, X, Y preserved)
SBC_MENU        = $FE06         ; boot menu
SBC_COLD        = $FE09         ; BASIC cold start
SBC_WARM        = $FE0C         ; BASIC warm start
SBC_MONITOR     = $FE0F         ; monitor prompt (or JMP $FF00)
SBC_PADSTATE    = $FE12         ; A = gamepad buttons held: bit0 A,1 B,2 Select,3 Start,4 Up,5 Down,6 Left,7 Right
SBC_LOAD        = $FE15         ; load a file: A/Y = parameter block (.word addr, .word max, "NAME.EXT",0)
                                ;   carry clear = loaded, X/Y = length; carry set = failed, A = error code
