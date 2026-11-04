; =====================================================================
;  Monitor for the 8085 board.  Works on whichever console is selected
;  (CONSEL).  Reuses the console and number routines from basic.asm.
;
;   D [s [e]]       dump memory (hex + ASCII); D alone continues
;   E a             examine/modify: type hex + Enter to change, Enter to
;                   skip to the next byte, "." to quit
;   F s e v         fill s..e with v
;   M s e d         move s..e to d (overlap safe)
;   G a             call the program at a (end it with RET to come back)
;   L               load Intel HEX arriving on the SERIAL port
;   S s e           send s..e as Intel HEX out of the SERIAL port
;   DIR             list the USB disk        (also "$")
;   LD name a       load file name (default .BIN) into memory at a
;   SV name s e     save s..e to file name (default .BIN)
;   I p / O p v     read / write I/O port p
;   C n             switch console: 0 = serial, 1 = keyboard/display
;   K               hex-dump keys typed on the display keyboard (Ctrl-C ends)
;   Z               send a test line to the display card
;   R               show registers saved by the last RST 1 breakpoint
;   B               cold start BASIC         W  warm start BASIC
;   ?               help
;  All numbers are hex.  RST 1 (opcode CFH) in a program is a breakpoint.
; =====================================================================

; monitor variables live at the bottom of the stack area (FC00-FC5F);
; the command line borrows BASIC's INPUT buffer
MVARS       EQU 0FC00H
MN_LAST     EQU MVARS+0             ; word: where "D" continues
MN_A1       EQU MVARS+2             ; parsed arguments
MN_A2       EQU MVARS+4
MN_A3       EQU MVARS+6
MN_CNT      EQU MVARS+8
MN_DEND     EQU MVARS+9             ; word
MN_DPTR     EQU MVARS+11            ; word
MN_DN       EQU MVARS+13
MN_EPTR     EQU MVARS+14            ; word
MN_LHCNT    EQU MVARS+16
MN_LHADR    EQU MVARS+17            ; word
MN_LHTYP    EQU MVARS+19
MN_LHSUM    EQU MVARS+20
MN_LHTMP    EQU MVARS+21
MN_LHTOT    EQU MVARS+22            ; word
MN_SPTR     EQU MVARS+24            ; word
MN_SN       EQU MVARS+26
MN_SSUM     EQU MVARS+27
MN_LDA      EQU MVARS+28            ; word
MN_LDCNT    EQU MVARS+30            ; word
MN_CON      EQU MVARS+44
BR_AF       EQU MVARS+32
BR_BC       EQU MVARS+34
BR_DE       EQU MVARS+36
BR_HL       EQU MVARS+38
BR_PC       EQU MVARS+40
BR_SP       EQU MVARS+42
MN_BUF      EQU INBUF

; ---------------- entry points ----------------
MONCOLD:LXI  SP,0
        XRA  A
        STA  OUTFLG
        STA  COLUMN
        MVI  A,0DBH             ; IN/OUT thunks used by the I and O commands
        STA  IOIN
        MVI  A,0D3H
        STA  IOOUT
        MVI  A,0C9H
        STA  IOIN+2
        STA  IOOUT+2
        MVI  A,0C3H             ; USR thunk (JMP nnnn)
        STA  USRTHK
        LXI  H,8000H
        SHLD MN_LAST
        CALL CRLF
        LXI  H,MN_BANNER
        CALL PRMSG
        CALL CRLF
        CALL CH_INIT            ; look for the USB disk; never hangs
        STA  CHRES
        LXI  H,MN_USB0
        ORA  A
        JZ   MC1
        LXI  H,MN_USB1
        CPI  0F0H
        JZ   MC1
        LXI  H,MN_USB2
        CPI  0F2H
        JZ   MC1
        LXI  H,MN_USB3
MC1:    CALL PRMSG
        CALL CRLF

MONITOR:LXI  SP,0               ; BASIC's MON command and G-programs return here
        XRA  A
        STA  OUTFLG
        EI
MN_LOOP:LXI  SP,0
        MVI  A,'*'
        CALL OUTC
        LXI  H,MN_BUF
        MVI  B,LBMAX
        CALL GETLN
        JC   MN_LOOP
        LXI  D,MN_BUF
        CALL MN_SKIP
        LDAX D
        CPI  CR
        JZ   MN_LOOP
        LXI  H,MN_CMDS
        CALL FINDKW
        JNC  MN_ERR
        MOV  H,B
        MOV  L,C
        PCHL

MN_ERR: MVI  A,'?'
        CALL OUTC
        CALL CRLF
        JMP  MN_LOOP

MN_RET: CALL CRLF               ; a G-program did RET
        JMP  MONITOR

; ---------------- parsing ----------------
; skip spaces and commas at DE
MN_SKIP:LDAX D
        CPI  ' '
        JZ   MS1
        CPI  ','
        RNZ
MS1:    INX  D
        JMP  MN_SKIP

; A = ASCII char -> CY=0, A = value 0..15 ; CY=1 if not a hex digit
MN_HEXDIG:
        CPI  '0'
        JC   MH_NO
        CPI  '9'+1
        JC   MH_1
        CPI  'A'
        JC   MH_NO
        CPI  'F'+1
        JNC  MH_NO
        SUI  'A'-10
        ORA  A
        RET
MH_1:   SUI  '0'
        ORA  A
        RET
MH_NO:  STC
        RET

; hex number at DE -> HL.  CY=1 (HL=0) if there is no number.
MN_HEXNUM:
        CALL MN_SKIP
        LXI  H,0
        MVI  B,0
HN1:    LDAX D
        CALL MN_HEXDIG
        JC   HN9
        INX  D
        DAD  H
        DAD  H
        DAD  H
        DAD  H
        ORA  L
        MOV  L,A
        INR  B
        JMP  HN1
HN9:    MOV  A,B
        ORA  A
        JNZ  HN10
        STC
        RET
HN10:   ORA  A
        RET

; parse up to three hex numbers into MN_A1..A3, A = how many
MN_ARGS:LXI  H,0
        SHLD MN_A1
        SHLD MN_A2
        SHLD MN_A3
        XRA  A
        STA  MN_CNT
        CALL MN_HEXNUM
        JC   AR9
        SHLD MN_A1
        MVI  A,1
        STA  MN_CNT
        CALL MN_HEXNUM
        JC   AR9
        SHLD MN_A2
        MVI  A,2
        STA  MN_CNT
        CALL MN_HEXNUM
        JC   AR9
        SHLD MN_A3
        MVI  A,3
        STA  MN_CNT
AR9:    LDA  MN_CNT
        RET

; file name at DE -> NAMEBUF as /NAME (".BIN" added if no extension)
MN_GETNAME:
        CALL MN_SKIP
        LXI  H,NAMEBUF
        LDAX D
        CPI  '/'
        JZ   GM1
        MVI  M,'/'
        INX  H
GM1:    MVI  B,0
        MVI  C,20
GM2:    LDAX D
        CPI  CR
        JZ   GM4
        CPI  ' '
        JZ   GM4
        CPI  ','
        JZ   GM4
        INX  D
        CPI  '.'
        JNZ  GM3
        MVI  B,1
GM3:    MOV  M,A
        INX  H
        DCR  C
        JNZ  GM2
GM4:    MOV  A,B
        ORA  A
        JNZ  GM5
        MVI  M,'.'
        INX  H
        MVI  M,'B'
        INX  H
        MVI  M,'I'
        INX  H
        MVI  M,'N'
        INX  H
GM5:    MVI  M,0
        RET

; print HL as 4 hex digits
MN_PRH16:
        MOV  A,H
        CALL PRHEX
        MOV  A,L
        JMP  PRHEX

; ---------------- D : dump ----------------
MN_D:   CALL MN_ARGS
        ORA  A
        JNZ  MD0
        LHLD MN_LAST
        SHLD MN_A1
        MVI  A,1
MD0:    CPI  1
        JNZ  MD2
        LHLD MN_A1
        LXI  D,127
        DAD  D
        JNC  MD1
        LXI  H,0FFFFH
MD1:    SHLD MN_A2
MD2:    LHLD MN_A2
        XCHG
        LHLD MN_A1
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        JC   MN_ERR
        SHLD MN_DPTR
        XCHG
        SHLD MN_DEND
MD3:    LHLD MN_DEND            ; bytes left = end - addr + 1
        XCHG
        LHLD MN_DPTR
        MOV  A,E
        SUB  L
        MOV  C,A
        MOV  A,D
        SBB  H
        MOV  B,A
        INX  B
        MOV  A,B
        ORA  A
        JNZ  MD4
        MOV  A,C
        CPI  16
        JC   MD5
MD4:    MVI  A,16
MD5:    STA  MN_DN
        MOV  A,H
        CALL PRHEX
        MOV  A,L
        CALL PRHEX
        MVI  A,':'
        CALL OUTC
        MVI  A,' '
        CALL OUTC
        PUSH H
        LDA  MN_DN
        MOV  B,A
MD6:    MOV  A,M
        CALL PRHEX
        MVI  A,' '
        CALL OUTC
        INX  H
        DCR  B
        JNZ  MD6
        LDA  MN_DN
        MOV  B,A
        MVI  A,16
        SUB  B
        MOV  B,A
        JZ   MD8
MD7:    MVI  A,' '
        CALL OUTC
        CALL OUTC
        CALL OUTC
        DCR  B
        JNZ  MD7
MD8:    MVI  A,' '
        CALL OUTC
        POP  H
        LDA  MN_DN
        MOV  B,A
MD9:    MOV  A,M
        CPI  20H
        JC   MD10
        CPI  7FH
        JC   MD11
MD10:   MVI  A,'.'
MD11:   CALL OUTC
        INX  H
        DCR  B
        JNZ  MD9
        CALL CRLF
        SHLD MN_DPTR
        SHLD MN_LAST
        MOV  A,H
        ORA  L
        JZ   MN_LOOP            ; wrapped past FFFF
        XCHG
        LHLD MN_DEND
        MOV  A,L
        SUB  E
        MOV  A,H
        SBB  D
        JC   MN_LOOP            ; passed the end
        CALL BRKCHK
        JC   MN_LOOP
        JMP  MD3

; ---------------- E : examine / modify ----------------
MN_E:   CALL MN_ARGS
        ORA  A
        JZ   MN_ERR
        LHLD MN_A1
        SHLD MN_EPTR
ME1:    LHLD MN_EPTR
        MOV  A,H
        CALL PRHEX
        MOV  A,L
        CALL PRHEX
        MVI  A,' '
        CALL OUTC
        MOV  A,M
        CALL PRHEX
        MVI  A,'-'
        CALL OUTC
        LXI  H,MN_BUF
        MVI  B,LBMAX
        CALL GETLN
        JC   MN_LOOP
        LXI  D,MN_BUF
        CALL MN_SKIP
        LDAX D
        CPI  CR
        JZ   ME2
        CPI  '.'
        JZ   MN_LOOP
        CALL MN_HEXNUM
        JC   MN_ERR
        MOV  A,L
        LHLD MN_EPTR
        MOV  M,A
ME2:    LHLD MN_EPTR
        INX  H
        SHLD MN_EPTR
        JMP  ME1

; ---------------- F : fill ----------------
MN_F:   CALL MN_ARGS
        CPI  3
        JNZ  MN_ERR
        LHLD MN_A2
        XCHG
        LHLD MN_A1
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        JC   MN_ERR
        LDA  MN_A3
        MOV  C,A
MF1:    MOV  M,C
        INX  H
        MOV  A,H
        ORA  L
        JZ   MN_LOOP
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        JNC  MF1
        JMP  MN_LOOP

; ---------------- M : move ----------------
MN_M:   CALL MN_ARGS
        CPI  3
        JNZ  MN_ERR
        LHLD MN_A2
        XCHG
        LHLD MN_A1
        MOV  A,E
        SUB  L
        MOV  C,A
        MOV  A,D
        SBB  H
        MOV  B,A
        JC   MN_ERR
        INX  B                  ; BC = count
        LHLD MN_A3
        XCHG                    ; DE = destination
        LHLD MN_A1              ; HL = source
        MOV  A,L
        SUB  E
        MOV  A,H
        SBB  D
        JC   MM1                ; source < destination: copy backwards
        CALL MOVEDN
        JMP  MN_LOOP
MM1:    DAD  B
        DCX  H
        XCHG
        DAD  B
        DCX  H
        XCHG
        CALL MOVEUP
        JMP  MN_LOOP

; ---------------- G : go ----------------
MN_G:   CALL MN_ARGS
        ORA  A
        JZ   MN_ERR
        LHLD MN_A1
        LXI  B,MN_RET
        PUSH B
        PCHL

; ---------------- L : load Intel HEX from the serial port ----------------
; next serial byte in A. CY=1 on Ctrl-C.
MN_LGETC:
        CALL SERST
        ORA  A
        JNZ  LG1
        LDA  BRKFLG
        ORA  A
        JZ   MN_LGETC
        XRA  A
        STA  BRKFLG
        STC
        RET
LG1:    CALL SERIN
        ORA  A
        RET

; two ASCII hex digits from serial -> A, added to MN_LHSUM. CY=1 on error.
MN_LGBYTE:
        CALL MN_LGETC
        RC
        CALL MN_HEXDIG
        RC
        ADD  A
        ADD  A
        ADD  A
        ADD  A
        STA  MN_LHTMP
        CALL MN_LGETC
        RC
        CALL MN_HEXDIG
        RC
        LXI  H,MN_LHTMP
        ORA  M
        PUSH PSW
        LXI  H,MN_LHSUM
        ADD  M
        MOV  M,A
        POP  PSW
        ORA  A
        RET

MN_L:   LXI  H,MN_MSGL
        CALL PRMSG
        LXI  H,0
        SHLD MN_LHTOT
LH1:    CALL MN_LGETC
        JC   LHABT
        CPI  ':'
        JNZ  LH1
        XRA  A
        STA  MN_LHSUM
        CALL MN_LGBYTE
        JC   LHERR
        STA  MN_LHCNT
        CALL MN_LGBYTE
        JC   LHERR
        STA  MN_LHADR+1
        CALL MN_LGBYTE
        JC   LHERR
        STA  MN_LHADR
        CALL MN_LGBYTE
        JC   LHERR
        STA  MN_LHTYP
LH2:    LDA  MN_LHCNT
        ORA  A
        JZ   LH4
        CALL MN_LGBYTE
        JC   LHERR
        MOV  C,A
        LDA  MN_LHTYP
        ORA  A
        JNZ  LH3
        LHLD MN_LHADR
        MOV  M,C
        MOV  A,M
        CMP  C
        JNZ  LHMEM
        INX  H
        SHLD MN_LHADR
        LHLD MN_LHTOT
        INX  H
        SHLD MN_LHTOT
LH3:    LDA  MN_LHCNT
        DCR  A
        STA  MN_LHCNT
        JMP  LH2
LH4:    CALL MN_LGBYTE
        JC   LHERR
        LDA  MN_LHSUM
        ORA  A
        JNZ  LHSUMER
        MVI  A,'.'
        CALL OUTC
        LDA  MN_LHTYP
        CPI  1
        JNZ  LH1
        CALL CRLF
        LXI  H,MN_MSGOK
        CALL PRMSG
        LHLD MN_LHTOT
        CALL PRTUNS
        LXI  H,MN_MSGB
        CALL PRMSG
        CALL CRLF
        JMP  MN_LOOP
LHABT:  LXI  H,MN_MSGABT
        JMP  LHEND
LHERR:  LXI  H,MN_MSGBAD
        JMP  LHEND
LHSUMER:LXI  H,MN_MSGSUM
        JMP  LHEND
LHMEM:  CALL CRLF
        LXI  H,MN_MSGMEM
        CALL PRMSG
        LHLD MN_LHADR
        CALL MN_PRH16
        CALL CRLF
        JMP  MN_LOOP
LHEND:  PUSH H
        CALL CRLF
        POP  H
        CALL PRMSG
        CALL CRLF
        JMP  MN_LOOP

; ---------------- S : send Intel HEX to the serial port ----------------
; A -> two hex digits out of the serial port, adds A to MN_SSUM. Preserves all.
MN_SHEX:PUSH H
        PUSH PSW
        LXI  H,MN_SSUM
        ADD  M
        MOV  M,A
        POP  PSW
        POP  H
        PUSH PSW
        RRC
        RRC
        RRC
        RRC
        CALL SX1
        POP  PSW
SX1:    ANI  0FH
        ADI  '0'
        CPI  '9'+1
        JC   SX2
        ADI  7
SX2:    JMP  SEROUT

MN_S:   CALL MN_ARGS
        CPI  2
        JC   MN_ERR
        LHLD MN_A2
        XCHG
        LHLD MN_A1
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        JC   MN_ERR
        SHLD MN_SPTR
SH1:    LHLD MN_A2
        XCHG
        LHLD MN_SPTR
        MOV  A,E
        SUB  L
        MOV  C,A
        MOV  A,D
        SBB  H
        MOV  B,A
        INX  B
        MOV  A,B
        ORA  A
        JNZ  SH2
        MOV  A,C
        CPI  16
        JC   SH3
SH2:    MVI  A,16
SH3:    STA  MN_SN
        MVI  A,':'
        CALL SEROUT
        XRA  A
        STA  MN_SSUM
        LDA  MN_SN
        CALL MN_SHEX
        LHLD MN_SPTR
        MOV  A,H
        CALL MN_SHEX
        MOV  A,L
        CALL MN_SHEX
        XRA  A
        CALL MN_SHEX
        LDA  MN_SN
        MOV  B,A
        LHLD MN_SPTR
SH4:    MOV  A,M
        CALL MN_SHEX
        INX  H
        DCR  B
        JNZ  SH4
        SHLD MN_SPTR
        LDA  MN_SSUM
        CMA
        INR  A
        CALL MN_SHEX
        MVI  A,CR
        CALL SEROUT
        MVI  A,LF
        CALL SEROUT
        MOV  A,H
        ORA  L
        JZ   SH9
        XCHG
        LHLD MN_A2
        MOV  A,L
        SUB  E
        MOV  A,H
        SBB  D
        JC   SH9
        CALL BRKCHK
        JC   SH9
        JMP  SH1
SH9:    LXI  H,MN_EOF
SH10:   MOV  A,M
        INX  H
        ORA  A
        JZ   MN_LOOP
        CALL SEROUT
        JMP  SH10

; ---------------- disk ----------------
MN_DIR: CALL DODIR
        ORA  A
        JNZ  MN_DERR
        JMP  MN_LOOP

MN_DERR:CPI  42H
        LXI  H,MNOFILE
        JZ   DE1
        PUSH PSW
        XRA  A
        STA  CHFLAG             ; remount on the next disk command
        LXI  H,MDISK
        CALL PRMSG
        POP  PSW
        CALL PRHEX
        CALL CRLF
        JMP  MN_LOOP
DE1:    CALL PRMSG
        CALL CRLF
        JMP  MN_LOOP

; LD name addr
MN_LD:  CALL MN_GETNAME
        CALL MN_HEXNUM
        JC   MN_ERR
        SHLD MN_LDA
        SHLD MN_A1
        CALL CH_ENSURE
        ORA  A
        JNZ  MN_DERR
        LXI  H,NAMEBUF
        CALL CH_FOPEN
        CPI  14H
        JNZ  MN_DERR
        CALL CH_RDINIT
        LXI  H,0
        SHLD MN_LDCNT
LD1X:   CALL CH_GETC
        JC   LD9X
        LHLD MN_LDA
        MOV  M,A
        INX  H
        SHLD MN_LDA
        MOV  A,H
        ORA  L
        JZ   LD9X
        LHLD MN_LDCNT
        INX  H
        SHLD MN_LDCNT
        JMP  LD1X
LD9X:   XRA  A
        CALL CH_CLOSE
        LXI  H,MN_MSGLD
        CALL PRMSG
        LHLD MN_LDCNT
        CALL PRTUNS
        LXI  H,MN_MSGAT
        CALL PRMSG
        LHLD MN_A1
        CALL MN_PRH16
        CALL CRLF
        JMP  MN_LOOP

; SV name start end
MN_SV:  CALL MN_GETNAME
        CALL MN_ARGS
        CPI  2
        JC   MN_ERR
        LHLD MN_A2
        XCHG
        LHLD MN_A1
        MOV  A,E
        SUB  L
        MOV  C,A
        MOV  A,D
        SBB  H
        MOV  B,A
        JC   MN_ERR
        INX  B
        PUSH B
        PUSH H
        CALL CH_ENSURE
        ORA  A
        JNZ  MN_DERR
        LXI  H,NAMEBUF
        CALL CH_FCREATE
        CPI  14H
        JNZ  MN_DERR
        POP  H
        POP  B
        CALL CH_WRITE
        CPI  14H
        JNZ  MN_DERR
        MVI  A,1
        CALL CH_CLOSE
        CPI  14H
        JNZ  MN_DERR
        LXI  H,MN_MSGSV
        CALL PRMSG
        CALL CRLF
        JMP  MN_LOOP

; ---------------- breakpoints and registers ----------------
; RST 1 lands here.  The stack holds the return address.
BRKENT: SHLD BR_HL
        PUSH PSW
        POP  H
        SHLD BR_AF
        MOV  H,B
        MOV  L,C
        SHLD BR_BC
        XCHG
        SHLD BR_DE
        POP  H
        DCX  H                  ; address of the RST 1 itself
        SHLD BR_PC
        LXI  H,0
        DAD  SP
        SHLD BR_SP
        LXI  SP,0
        EI
        CALL CRLF
        LXI  H,MN_MSGBRK
        CALL PRMSG
        CALL MN_SHOWREGS
        JMP  MONITOR

MN_R:   CALL MN_SHOWREGS
        JMP  MN_LOOP

MN_SHOWREGS:
        LXI  H,MN_RPC
        CALL PRMSG
        LHLD BR_PC
        CALL MN_PRH16
        LXI  H,MN_RSP
        CALL PRMSG
        LHLD BR_SP
        CALL MN_PRH16
        LXI  H,MN_RAF
        CALL PRMSG
        LHLD BR_AF
        CALL MN_PRH16
        LXI  H,MN_RBC
        CALL PRMSG
        LHLD BR_BC
        CALL MN_PRH16
        LXI  H,MN_RDE
        CALL PRMSG
        LHLD BR_DE
        CALL MN_PRH16
        LXI  H,MN_RHL
        CALL PRMSG
        LHLD BR_HL
        CALL MN_PRH16
        JMP  CRLF

; ---------------- other commands ----------------
; C n : switch the console (0 = serial, 1 = keyboard/display)
MN_C:   CALL MN_ARGS
        ORA  A
        JZ   MN_ERR
        LDA  MN_A1
        ANI  1
        STA  CONSEL
        JMP  MN_LOOP

; I p : read I/O port p and print it
MN_I:   CALL MN_ARGS
        ORA  A
        JZ   MN_ERR
        LDA  MN_A1
        STA  IOIN+1
        CALL IOIN
        CALL PRHEX
        CALL CRLF
        JMP  MN_LOOP

; O p v : write v to I/O port p
MN_O:   CALL MN_ARGS
        CPI  2
        JC   MN_ERR
        LDA  MN_A1
        STA  IOOUT+1
        LDA  MN_A2
        CALL IOOUT
        JMP  MN_LOOP

; K : read keys through the display-console input path, show each as hex
;     (Ctrl-C ends).  Output goes to the current console, so run it from serial.
MN_K:   LDA  CONSEL
        STA  MN_CON
        LXI  H,MN_MSGK
        CALL PRMSG
MK1:    MVI  A,1
        STA  CONSEL
        CALL GETKEY
        PUSH PSW
        LDA  MN_CON
        STA  CONSEL
        POP  PSW
        CPI  3
        JZ   MK9
        CALL PRHEX
        MVI  A,' '
        CALL OUTC
        JMP  MK1
MK9:    CALL CRLF
        JMP  MN_LOOP

; Z : send a test line to the display card whatever the console is
MN_Z:   LXI  H,MN_MSGZ
MZ1:    MOV  A,M
        INX  H
        ORA  A
        JZ   MN_LOOP
        CALL KBOUT
        JMP  MZ1

MN_B:   JMP  BASIC
MN_W:   JMP  WARM

MN_HELP:LXI  H,MN_MSGHELP
        CALL PRMSG
        JMP  MN_LOOP

; ---------------- tables and messages ----------------
MN_CMDS:DB   "DI",'R'+80H
        DW   MN_DIR
        DB   '$'+80H
        DW   MN_DIR
        DB   'L','D'+80H
        DW   MN_LD
        DB   'S','V'+80H
        DW   MN_SV
        DB   'D'+80H
        DW   MN_D
        DB   'E'+80H
        DW   MN_E
        DB   'F'+80H
        DW   MN_F
        DB   'M'+80H
        DW   MN_M
        DB   'G'+80H
        DW   MN_G
        DB   'L'+80H
        DW   MN_L
        DB   'S'+80H
        DW   MN_S
        DB   'R'+80H
        DW   MN_R
        DB   'C'+80H
        DW   MN_C
        DB   'I'+80H
        DW   MN_I
        DB   'O'+80H
        DW   MN_O
        DB   'K'+80H
        DW   MN_K
        DB   'Z'+80H
        DW   MN_Z
        DB   'B'+80H
        DW   MN_B
        DB   'W'+80H
        DW   MN_W
        DB   '?'+80H
        DW   MN_HELP
        DB   0

MN_BANNER:  DB "8085 MONITOR  ? FOR HELP",0
MN_USB0:    DB "USB DISK READY",0
MN_USB1:    DB "NO CH376 FOUND",0
MN_USB2:    DB "NO USB DISK",0
MN_USB3:    DB "CH376 ERROR",0
MN_MSGL:    DB "SEND INTEL HEX ON THE SERIAL PORT (CTRL-C ABORTS)",0DH,0AH,0
MN_MSGOK:   DB "OK ",0
MN_MSGB:    DB " BYTES",0
MN_MSGABT:  DB "ABORTED",0
MN_MSGBAD:  DB "BAD HEX",0
MN_MSGSUM:  DB "CHECKSUM ERROR",0
MN_MSGMEM:  DB "NOT RAM AT ",0
MN_MSGLD:   DB "LOADED ",0
MN_MSGAT:   DB " BYTES AT ",0
MN_MSGSV:   DB "SAVED",0
MN_MSGK:    DB "KEYS FROM THE DISPLAY KEYBOARD, CTRL-C ENDS:",0DH,0AH,0
MN_MSGZ:    DB "DISPLAY OUTPUT TEST OK",0DH,0AH,0
MN_MSGBRK:  DB "BREAK  ",0
MN_RPC:     DB "PC=",0
MN_RSP:     DB " SP=",0
MN_RAF:     DB " AF=",0
MN_RBC:     DB " BC=",0
MN_RDE:     DB " DE=",0
MN_RHL:     DB " HL=",0
MN_EOF:     DB ":00000001FF",0DH,0AH,0
MN_MSGHELP: DB "D [s [e]]  dump        E a      examine/modify",0DH,0AH
            DB "F s e v    fill        M s e d  move",0DH,0AH
            DB "G a        go (RET returns)",0DH,0AH
            DB "L          load HEX from serial   S s e  send HEX to serial",0DH,0AH
            DB "DIR        list disk   LD name a  load file   SV name s e  save file",0DH,0AH
            DB "I p        read port   O p v  write port   C n  console (0 serial, 1 display)",0DH,0AH
            DB "K          show keys typed on the display keyboard   Z  test display output",0DH,0AH
            DB "R          registers   B BASIC   W warm BASIC   (numbers are hex)",0DH,0AH,0
