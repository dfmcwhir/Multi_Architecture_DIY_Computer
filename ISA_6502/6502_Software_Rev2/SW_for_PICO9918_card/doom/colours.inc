; colours.inc - made by gen_colours.py

C_DEAD = $60
C_GUN = $E0
C_FLASH = $B0
wall_col:
        .byte   $F1, $F1, $81, $61, $54, $41, $FE, $E1, $BA, $A1, $32, $2C
thing_col:
        .byte   $F0, $30, $80, $F0, $B0
gseg:
        .byte   $48, $F1, $F1, $20, $FD, $FD, $24, $FD, $F1, $26, $F1, $F1, $28, $F1, $F9, $48
        .byte   $F9, $F9, $0F, $F4, $F1, $39, $F1, $F1, $48, $FE, $F1
gseg_start:
        .byte   $00, $03, $12
GROUND_N = 3
pal_dark:
        .byte   $04, $32, $02, $23
pal_def:
        .byte   $0F, $76, $0C, $5C
cellrep:
        .byte   $01, $03, $06, $09, $0B, $0E, $11, $13, $16, $19, $1B, $1E, $21, $23, $26, $29
        .byte   $2B, $2E, $31, $33, $36, $39, $3B, $3E, $41, $43, $46, $49, $4B, $4E
cellfirst:
        .byte   $00, $02, $05, $08, $0A, $0D, $10, $12, $15, $18, $1A, $1D, $20, $22, $25, $28
        .byte   $2A, $2D, $30, $32, $35, $38, $3A, $3D, $40, $42, $45, $48, $4A, $4D
celllast:
        .byte   $02, $05, $07, $0A, $0D, $0F, $12, $15, $17, $1A, $1D, $1F, $22, $25, $27, $2A
        .byte   $2D, $2F, $32, $35, $37, $3A, $3D, $3F, $42, $45, $47, $4A, $4D, $4F
gun_cell:
        .byte   $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $44, $3C, $3C
        .byte   $44, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
gun_cellf:
        .byte   $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $38, $38, $38
        .byte   $38, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
