; =====================================================================
;  Tiny BASIC for the 8085 board  (original implementation)
;  - 16 bit signed integers, variables A-Z, array @(0..127)
;  - Statements: LET IF GOTO GOSUB RETURN FOR/TO/STEP NEXT PRINT (?) INPUT
;                REM END STOP RUN LIST NEW POKE OUT CLS MON
;                SAVE LOAD DIR ERASE   (CH376 USB storage; LOAD "$" = DIR)
;                SETISR irq,line   CLRISR irq     (BASIC interrupt handlers)
;  - Functions:  ABS(x) RND(x) SIZE PEEK(x) IN(x)     $hhhh = hex literal
;                USR(addr[,arg])  call machine code   IFR  VIA flags latched
;  - PRINT $(x) prints x in hex
;  - Operators (lowest first):  OR XOR | AND | = < > <= >= <> # | << >> | + - | * /
;                NOT x     relations give -1 (true) or 0, so AND/OR/NOT work on them
;  - PRINT: "text"  expr  CHR$(n) (any raw byte, e.g. VT100 ESC = CHR$(27))
;           $(expr) (hex)   ; and , separators
;  - SEND d,byte,...   INKEY(d)    raw access to the serial card (d=0) or the
;                keyboard/display card (d=1), for whichever is not the console
;  - SETISR (statement, irq)   run a statement when IRQ n happens, any time
;  Uses only 8080 instructions.  Text pointer lives in DE, values in HL.
; =====================================================================

CR          EQU 0DH
LF          EQU 0AH
QT          EQU 22H
BS          EQU 08H
DEL         EQU 7FH
LBMAX       EQU 79

; ---------------- RAM map ----------------
LINBUF      EQU 8300H               ; command line (80)
INBUF       EQU 8350H               ; INPUT line (80)
FBUF        EQU 83A0H               ; SAVE/LOAD line buffer (96)
ARRAY       EQU 8400H               ; @(0..127), 256 bytes
VARTAB      EQU 8500H               ; A-Z, 52 bytes
BVARS       EQU 8540H               ; scalars, cleared at cold start
PRGEND      EQU 8540H
CURLIN      EQU 8542H               ; address of running line record, 0 = direct mode
FORVAR      EQU 8544H
FORLIM      EQU 8546H
NXVAR       EQU 8548H
NXLIM       EQU 854AH
NXSTP       EQU 854CH
NXLN        EQU 854EH
NXTX        EQU 8550H
NXTXT       EQU 8552H
LNNUM       EQU 8554H
LNSRC       EQU 8556H
LNLEN       EQU 8558H
LNSZ        EQU 855AH
LNREC       EQU 855CH
TMPA        EQU 855EH
TMPB        EQU 8560H
LISTLO      EQU 8562H
LISTHI      EQU 8564H
RNDSEED     EQU 8566H
RNDN        EQU 8568H
RNDR        EQU 856AH
COLUMN      EQU 856CH
OUTFLG      EQU 856DH
OUTPTR      EQU 856EH
PRMFLG      EQU 8570H
RELM        EQU 8571H
LDPTR       EQU 8572H
LDCNT       EQU 8574H
IOOUT       EQU 8576H               ; 3 byte RAM thunk: OUT p / RET
IOIN        EQU 8579H               ; 3 byte RAM thunk: IN p / RET
PROG        EQU 8800H               ; program text starts here (8600-877F: interrupt handler text)
RAMTOP      EQU 0F800H              ; program may not grow past here; F800-FBFF is
                                        ; free for machine code (USR, monitor LD/G)
USRTHK      EQU 857CH               ; 3 byte RAM thunk: JMP addr (patched by USR)
; ISRPEND, ISRBUSY, ISRCTX, ISRSP and ISRTXT are defined in boot_bios.asm

; =====================================================================
;  Cold start / main loop
; =====================================================================
BASIC:  LXI  SP,0
        LXI  H,BVARS
        XRA  A
BCL1:   MOV  M,A
        INR  L
        JNZ  BCL1
        CALL DONEW
        LXI  H,0ACE1H
        SHLD RNDSEED
        MVI  A,0D3H             ; OUT thunk
        STA  IOOUT
        MVI  A,0DBH             ; IN thunk
        STA  IOIN
        MVI  A,0C9H
        STA  IOOUT+2
        STA  IOIN+2
        MVI  A,0C3H
        STA  USRTHK
        LXI  H,MBANNER
        CALL PRMSG
        CALL CRLF
        LXI  H,RAMTOP-PROG-2
        CALL PRTUNS
        LXI  H,MFREE
        CALL PRMSG
        CALL CRLF

WARM:   LXI  SP,0
        XRA  A
        STA  OUTFLG
        STA  ISRBUSY
        STA  ISRCTX
        LXI  H,0
        SHLD CURLIN
        MVI  A,'>'
        CALL OUTC
        LXI  H,LINBUF
        MVI  B,LBMAX
        CALL GETLN
        JC   WARM
        LXI  D,LINBUF
        CALL SKIPSP
        CPI  CR
        JZ   WARM
        CALL ISDIG
        JNC  STMT
        CALL GETNUM
        MOV  A,H
        ORA  L
        JZ   WHAT
        CALL ENTLN
        JMP  WARM

; =====================================================================
;  Errors
; =====================================================================
WHAT:   LXI  H,MWHAT
        JMP  ERR
HOW:    LXI  H,MHOW
        JMP  ERR
SORRY:  LXI  H,MSORRY
        JMP  ERR
BREAK:  LXI  H,MSTOP
ERR:    PUSH H
        XRA  A
        STA  OUTFLG
        LDA  COLUMN
        ORA  A
        CNZ  CRLF
        POP  H
        CALL PRMSG
        LHLD CURLIN
        MOV  A,H
        ORA  L
        JZ   ERR2
        PUSH H
        LXI  H,MIN
        CALL PRMSG
        POP  H
        MOV  E,M
        INX  H
        MOV  D,M
        XCHG
        CALL PRTUNS
ERR2:   CALL CRLF
        JMP  WARM

DISKERR:CPI  42H
        LXI  H,MNOFILE
        JZ   ERR
        PUSH PSW
        XRA  A
        STA  CHFLAG             ; remount on the next disk command
        LDA  COLUMN
        ORA  A
        CNZ  CRLF
        LXI  H,MDISK
        CALL PRMSG
        POP  PSW
        CALL PRHEX
        CALL CRLF
        JMP  WARM

; =====================================================================
;  Statement execution
; =====================================================================
STMT:   CALL BRKCHK
        JC   BREAK
        LDA  ISRPEND
        ORA  A
        CNZ  ISRPOLL
STM1:   CALL SKIPSP
        LXI  H,STMTAB
        CALL FINDKW
        JNC  S_LET
        MOV  H,B
        MOV  L,C
        PCHL

; ---- interrupt handlers --------------------------------------------------
; A SETISR handler is a BASIC statement (or several, separated by :) kept as
; text.  It runs at a safe point: before the next statement of a running
; program, or while BASIC waits for a key at the prompt or in INPUT.
; ISRPOLL runs the handler of the lowest pending IRQ, then returns.
ISRPOLL:LDA  ISRBUSY
        ORA  A
        RNZ                     ; a handler is already running
        MVI  C,0
        MVI  B,1
IP1:    LDA  ISRPEND
        ANA  B
        JNZ  IP2
        MOV  A,B
        ADD  A
        MOV  B,A
        INR  C
        MOV  A,C
        CPI  8
        JNZ  IP1
        XRA  A
        STA  ISRPEND
        RET
IP2:    MOV  A,B
        CMA
        MOV  B,A
        DI
        LDA  ISRPEND
        ANA  B
        STA  ISRPEND
        EI
        MOV  A,C
        CALL ISRADDR            ; HL = handler text
        MOV  A,M
        ORA  A
        RZ                      ; no handler any more
        PUSH D                  ; interrupted statement pointer
        XCHG                    ; DE = handler text
        LHLD CURLIN
        PUSH H
        LXI  H,0
        SHLD CURLIN             ; the handler runs like a typed-in line
        MVI  A,1
        STA  ISRBUSY
        STA  ISRCTX
        LXI  H,0
        DAD  SP
        SHLD ISRSP              ; where to unwind to when the handler is done
        JMP  STMT

; end of the handler's text: unwind and return to whoever called ISRPOLL
ISRBACK:LHLD ISRSP
        SPHL
        XRA  A
        STA  ISRCTX
        STA  ISRBUSY
        POP  H
        SHLD CURLIN
        POP  D
        RET

; A = IRQ 0..7 -> HL = address of its 48 byte handler text buffer
ISRADDR:MOV  L,A
        MVI  H,0
        MOV  B,H
        MOV  C,L
        DAD  H
        DAD  B
        DAD  H
        DAD  H
        DAD  H
        DAD  H
        LXI  B,ISRTXT
        DAD  B
        RET

ENDST:  CALL SKIPSP
        CPI  ':'
        JNZ  ES1
        INX  D
        JMP  STMT
ES1:    CPI  CR
        JNZ  WHAT
NEXTLN: LHLD CURLIN
        MOV  A,H
        ORA  L
        JNZ  NL2
        LDA  ISRCTX
        ORA  A
        JNZ  ISRBACK            ; the end of an interrupt handler's text
        JMP  WARM
NL2:    CALL SKIPREC
RUNLN:  MOV  A,M                ; HL = line record
        INX  H
        ORA  M
        DCX  H
        JZ   WARM               ; end marker
        SHLD CURLIN
        INX  H
        INX  H
        XCHG
        JMP  STMT

S_LET:  CALL SKIPSP
        CPI  '@'
        JNZ  LET1
        CALL ARRADDR
        JMP  LET2
LET1:   CALL VARADDR
        JC   WHAT
LET2:   PUSH H
        MVI  A,'='
        CALL EXPECT
        CALL EXPR
        POP  B
        MOV  A,L
        STAX B
        INX  B
        MOV  A,H
        STAX B
        JMP  ENDST

S_REM:  LDAX D
        CPI  CR
        JZ   ENDST
        INX  D
        JMP  S_REM

S_END:  JMP  WARM

S_IF:   CALL EXPR
        MOV  A,H
        ORA  L
        PUSH PSW
        LXI  H,THENTAB
        CALL FINDKW
        POP  PSW
        JZ   NEXTLN
        CALL SKIPSP
        CALL ISDIG
        JC   S_GOTO
        JMP  STMT

S_GOTO: CALL EXPR
        XCHG
        CALL FINDLN
        JNZ  HOW
        JMP  RUNLN

S_GOSUB:CALL EXPR
        PUSH D                  ; return text pointer
        XCHG
        LHLD CURLIN
        PUSH H
        LXI  H,1
        PUSH H                  ; frame type 1 = GOSUB
        CALL STKCHK
        CALL FINDLN
        JNZ  HOW
        JMP  RUNLN

S_RETURN:
SRT1:   LXI  H,0
        DAD  SP
        MOV  A,H
        ORA  L
        JZ   HOW                ; nothing to return to
        POP  H
        MOV  A,L
        CPI  1
        JZ   SRT2
        LXI  H,10               ; FOR frame: drop the other 5 words
        DAD  SP
        SPHL
        JMP  SRT1
SRT2:   POP  H
        SHLD CURLIN
        POP  D
        JMP  ENDST
S_FOR:  CALL VARADDR
        JC   WHAT
        SHLD FORVAR
        CALL FNDFOR
        JNC  SF0
        LXI  B,12
        DAD  B
        SPHL                    ; drop earlier loop on the same variable
SF0:    MVI  A,'='
        CALL EXPECT
        CALL EXPR
        PUSH H
        LHLD FORVAR
        MOV  B,H
        MOV  C,L
        POP  H
        MOV  A,L
        STAX B
        INX  B
        MOV  A,H
        STAX B
        LXI  H,TOTAB
        CALL FINDKW
        JNC  WHAT
        CALL EXPR
        SHLD FORLIM
        LXI  H,STEPTAB
        CALL FINDKW
        LXI  H,1
        JNC  SF1
        CALL EXPR
SF1:    PUSH D                  ; text pointer
        XCHG
        LHLD CURLIN
        PUSH H
        PUSH D                  ; step
        LHLD FORLIM
        PUSH H
        LHLD FORVAR
        PUSH H
        LXI  H,2
        PUSH H                  ; frame type 2 = FOR
        CALL STKCHK
        LXI  H,10
        DAD  SP
        MOV  E,M
        INX  H
        MOV  D,M
        JMP  ENDST

S_NEXT: CALL VARADDR
        JC   WHAT
        SHLD FORVAR
        XCHG
        SHLD NXTXT
        XCHG
        CALL FNDFOR
        JNC  HOW
        SPHL                    ; SP at the frame
        POP  H                  ; type
        POP  H
        SHLD NXVAR
        POP  H
        SHLD NXLIM
        POP  H
        SHLD NXSTP
        POP  H
        SHLD NXLN
        POP  H
        SHLD NXTX
        LHLD NXVAR
        MOV  B,H
        MOV  C,L
        MOV  E,M
        INX  H
        MOV  D,M
        LHLD NXSTP
        DAD  D
        MOV  A,L
        STAX B
        INX  B
        MOV  A,H
        STAX B
        MOV  B,H
        MOV  C,L                ; BC = new value
        LHLD NXLIM
        CALL SCMP
        MOV  B,A
        LDA  NXSTP+1
        ORA  A
        MOV  A,B
        JM   SN1
        CPI  1                  ; step >= 0: finished when value > limit
        JZ   SN3
        JMP  SN2
SN1:    CPI  0FFH               ; step < 0: finished when value < limit
        JZ   SN3
SN2:    LHLD NXTX
        PUSH H
        LHLD NXLN
        PUSH H
        SHLD CURLIN
        LHLD NXSTP
        PUSH H
        LHLD NXLIM
        PUSH H
        LHLD NXVAR
        PUSH H
        LXI  H,2
        PUSH H
        LHLD NXTX
        XCHG
        JMP  ENDST
SN3:    LHLD NXTXT
        XCHG
        JMP  ENDST

S_PRINT:CALL SKIPSP
        CPI  CR
        JZ   PRNL
        CPI  ':'
        JZ   PRNL
PR1:    LXI  H,CHRTAB
        CALL FINDKW
        JNC  PR1H
        CALL PAREXP             ; CHR$(n): send the raw byte n
        MOV  A,L
        CALL OUTC
        JMP  PR3
PR1H:   LDAX D
        CPI  '$'
        JNZ  PR1S
        INX  D
        LDAX D
        DCX  D
        CPI  '('
        MVI  A,'$'
        JNZ  PR1S               ; $hhhh is an ordinary hex number
        INX  D                  ; $(expr) prints expr in hex
        CALL PAREXP
        CALL PRTHEX
        JMP  PR3
PR1S:   CPI  QT
        JNZ  PR2
        INX  D
PR1L:   LDAX D
        CPI  CR
        JZ   PR3
        INX  D
        CPI  QT
        JZ   PR3
        CALL OUTC
        JMP  PR1L
PR2:    CALL EXPR
        CALL PRTNUM
PR3:    CALL SKIPSP
        CPI  ';'
        JZ   PRSEMI
        CPI  ','
        JZ   PRCOMMA
PRNL:   CALL CRLF
        JMP  ENDST
PRSEMI: INX  D
        JMP  PRMORE
PRCOMMA:INX  D
        CALL PRTAB
PRMORE: CALL SKIPSP
        CPI  CR
        JZ   ENDST
        CPI  ':'
        JZ   ENDST
        JMP  PR1

S_INPUT:XRA  A
        STA  PRMFLG
        CALL SKIPSP
        CPI  QT
        JNZ  IN1
        INX  D
IN0:    LDAX D
        CPI  CR
        JZ   WHAT
        INX  D
        CPI  QT
        JZ   IN0E
        CALL OUTC
        JMP  IN0
IN0E:   MVI  A,1
        STA  PRMFLG
        CALL SKIPSP
        CPI  ';'
        JZ   IN0F
        CPI  ','
        JNZ  IN1
IN0F:   INX  D
IN1:    CALL VARADDR
        JC   WHAT
        PUSH H
        PUSH D
        LDA  PRMFLG
        ORA  A
        JNZ  IN2
        MVI  A,'?'
        CALL OUTC
        MVI  A,' '
        CALL OUTC
IN2:    XRA  A
        STA  PRMFLG
        LXI  H,INBUF
        MVI  B,LBMAX
        CALL GETLN
        JC   BREAK
        LXI  D,INBUF
        CALL EXPR
        POP  D
        POP  B
        MOV  A,L
        STAX B
        INX  B
        MOV  A,H
        STAX B
        CALL SKIPSP
        CPI  ','
        JNZ  ENDST
        INX  D
        JMP  IN1

S_RUN:  LXI  SP,0
        XRA  A
        STA  ISRPEND
        STA  ISRBUSY
        STA  ISRCTX
        LXI  H,PROG
        JMP  RUNLN

S_NEW:  CALL DONEW
        JMP  WARM

S_POKE: CALL EXPR
        PUSH H
        MVI  A,','
        CALL EXPECT
        CALL EXPR
        POP  B
        MOV  A,L
        STAX B
        JMP  ENDST

S_OUT:  CALL EXPR
        MOV  A,L
        STA  IOOUT+1
        MVI  A,','
        CALL EXPECT
        CALL EXPR
        MOV  A,L
        CALL IOOUT
        JMP  ENDST

; SEND d, byte, byte ... : send raw bytes to device d (0 = serial card, 1 = display)
S_SEND: CALL EXPR
        MOV  A,H
        ORA  A
        JNZ  HOW
        MOV  A,L
        CPI  2
        JNC  HOW
        STA  TMPB
SS1:    MVI  A,','
        CALL EXPECT
        CALL EXPR
        LDA  TMPB
        ORA  A
        MOV  A,L
        JNZ  SS2
        CALL SEROUT
        JMP  SS3
SS2:    CALL KBOUT
SS3:    CALL SKIPSP
        CPI  ','
        JZ   SS1
        JMP  ENDST

S_CLS:  LXI  H,MCLS
        CALL PRMSG
        XRA  A
        STA  COLUMN
        JMP  ENDST

S_MON:  MVI  A,1                ; no BASIC handlers while in the monitor
        STA  ISRBUSY
        JMP  MONITOR

; ---------------- interrupts: SETISR / CLRISR ----------------
; SETISR irq,line          handler is  GOSUB line
; SETISR (statement, irq)  handler is any statement(s), e.g.
;                          SETISR (PRINT "IRQ RAISED", 2)
; The handler runs as soon as BASIC is at a safe point (even at the prompt)
; and ends with the end of its text, or RETURN if it GOSUBs.
; IRQ 3 (serial card) can be used only when the serial port is NOT the
; console, IRQ 5 (keyboard/display card) only when it is not; their handlers
; run when a character arrives (read it with INKEY).
S_SETISR:
        CALL SKIPSP
        CPI  '('
        JZ   SIS
        CALL EXPR               ; numeric form: irq, line
        PUSH H
        MVI  A,','
        CALL EXPECT
        CALL EXPR
        XCHG
        SHLD TMPB               ; where BASIC continues afterwards
        XCHG
        POP  B                  ; BC = irq
        CALL SICHK
        MOV  A,C
        STA  LNREC
        PUSH H                  ; line number
        CALL ISRADDR
        SHLD OUTPTR             ; "print" the handler text into its buffer
        MVI  A,1
        STA  OUTFLG
        LXI  H,MGOSUB
        CALL PRMSG
        POP  H
        CALL PRTUNS
        MVI  A,CR
        CALL OUTC
        XRA  A
        STA  OUTFLG
        JMP  SIREG

SIS:    INX  D                  ; statement form: ( statement , irq )
        CALL SKIPSP
        XCHG
        SHLD LNSRC              ; start of the statement text
        XCHG
        XRA  A
        STA  PRMFLG             ; inside-quotes flag
        STA  RELM               ; parenthesis depth
        LXI  H,0                ; HL = text after the last top-level comma
SI1:    LDAX D
        CPI  CR
        JZ   WHAT
        INX  D
        CPI  QT
        JNZ  SI2
        LDA  PRMFLG
        XRI  1
        STA  PRMFLG
        JMP  SI1
SI2:    MOV  B,A
        LDA  PRMFLG
        ORA  A
        JNZ  SI1
        MOV  A,B
        CPI  '('
        JNZ  SI3
        LDA  RELM
        INR  A
        STA  RELM
        JMP  SI1
SI3:    CPI  ')'
        JNZ  SI4
        LDA  RELM
        ORA  A
        JZ   SI5                ; the closing parenthesis of SETISR( ... )
        DCR  A
        STA  RELM
        JMP  SI1
SI4:    CPI  ','
        JNZ  SI1
        LDA  RELM
        ORA  A
        JNZ  SI1
        MOV  H,D
        MOV  L,E
        JMP  SI1
SI5:    MOV  A,H
        ORA  L
        JZ   WHAT
        SHLD TMPA               ; the irq expression starts here
        XCHG                    ; HL = text after the ')'
        SHLD TMPB               ; where BASIC continues afterwards
        LHLD TMPA
        XCHG                    ; DE = irq expression
        CALL EXPR
        MVI  A,')'
        CALL EXPECT
        MOV  B,H
        MOV  C,L
        CALL SICHK
        MOV  A,C
        STA  LNREC
        CALL ISRADDR
        XCHG                    ; DE = buffer
        LHLD LNSRC
        XCHG                    ; DE = source, HL = buffer
        MVI  B,0
SI6:    PUSH H
        LHLD TMPA
        DCX  H                  ; HL = the comma before the irq
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        POP  H
        JNC  SI7                ; source reached the comma
        LDAX D
        MOV  M,A
        INX  D
        INX  H
        INR  B
        MOV  A,B
        CPI  46
        JC   SI6
        JMP  HOW                ; handler text too long (46 characters)
SI7:    MOV  A,B
        ORA  A
        JZ   HOW
        MVI  M,CR
SIREG:  LDA  LNREC              ; IRQ 3 and 5 keep their receive handlers
        CPI  3
        JZ   SID
        CPI  5
        JZ   SID
        ADD  A
        MOV  C,A
        MVI  B,0
        LXI  H,BISRTAB
        DAD  B
        MOV  E,M
        INX  H
        MOV  D,M
        LXI  H,IRQTAB
        DAD  B
        DI
        MOV  M,E
        INX  H
        MOV  M,D
        EI
SID:    LHLD TMPB
        XCHG
        JMP  ENDST

; BC = IRQ number: HOW? unless 0..7 and available
SICHK:  MOV  A,B
        ORA  A
        JNZ  HOW
        MOV  A,C
        CPI  8
        JNC  HOW
        CPI  3
        JNZ  SIC1
        LDA  CONSEL
        ORA  A
        JZ   HOW                ; the serial port is the console
        RET
SIC1:    CPI  5
        RNZ
        LDA  CONSEL
        ORA  A
        JNZ  HOW                ; the keyboard/display card is the console
        RET

S_CLRISR:
        CALL EXPR               ; CLRISR 2   or   CLRISR (2)
        MOV  A,H
        ORA  A
        JNZ  HOW
        MOV  A,L
        CPI  8
        JNC  HOW
        PUSH D
        PUSH PSW
        CALL ISRADDR
        MVI  M,0                ; no handler text
        POP  PSW
        ADD  A
        MOV  C,A
        MVI  B,0
        LXI  H,ISRDEF
        DAD  B
        MOV  E,M
        INX  H
        MOV  D,M
        LXI  H,IRQTAB
        DAD  B
        DI
        MOV  M,E
        INX  H
        MOV  M,D
        EI
        POP  D
        JMP  ENDST

; forget all handlers and put the default IRQ handlers back
ISRINIT:XRA  A
        STA  ISRPEND
        STA  ISRBUSY
        STA  ISRCTX
        LXI  H,ISRTXT
        LXI  D,48
        MVI  B,8
II1:    MVI  M,0
        DAD  D
        DCR  B
        JNZ  II1
        LXI  H,IRQTAB
        LXI  D,ISRDEF
        MVI  B,16
II2:    LDAX D
        MOV  M,A
        INX  D
        INX  H
        DCR  B
        JNZ  II2
        RET

ISRCLR: DI
        CALL ISRINIT
        EI
        RET

; stubs placed in IRQTAB while a handler is registered: note the event
BISR0:  MVI  A,01H
        JMP  BISRCOM
BISR1:  MVI  A,02H
        JMP  BISRCOM
BISR2:  CALL VIAISR             ; acknowledge the 65C22, then note the event
        MVI  A,04H
        JMP  BISRCOM
BISR4:  MVI  A,10H
        JMP  BISRCOM
BISR6:  MVI  A,40H
        JMP  BISRCOM
BISR7:  MVI  A,80H
BISRCOM:LXI  H,ISRPEND
        ORA  M
        MOV  M,A
        RET

BISRTAB:DW   BISR0,BISR1,BISR2,SERSVC,BISR4,KBSVC,BISR6,BISR7
ISRDEF: DW   DEFIRQ,DEFIRQ,VIAISR,SERSVC,DEFIRQ,KBSVC,DEFIRQ,DEFIRQ

; ---------------- LIST ----------------
S_LIST: LXI  H,0
        SHLD LISTLO
        LXI  H,0FFFFH
        SHLD LISTHI
        CALL SKIPSP
        CALL ISDIG
        JNC  SLS0
        CALL GETNUM
        SHLD LISTLO
        SHLD LISTHI
        CALL SKIPSP
        CPI  ','
        JNZ  SLS0
        INX  D
        CALL SKIPSP
        LXI  H,0FFFFH
        CALL ISDIG
        JNC  SLS1
        CALL GETNUM
SLS1:   SHLD LISTHI
SLS0:   PUSH D
        LXI  H,PROG
SLS2:   CALL BRKCHK
        JC   BREAK
        MOV  E,M
        INX  H
        MOV  D,M
        DCX  H
        MOV  A,D
        ORA  E
        JZ   SLSEND
        PUSH H
        LHLD LISTHI
        MOV  A,L
        SUB  E
        MOV  A,H
        SBB  D
        POP  H
        JC   SLSEND
        PUSH H
        LHLD LISTLO
        MOV  A,E
        SUB  L
        MOV  A,D
        SBB  H
        POP  H
        JC   SLSKIP
        CALL LISTLINE
        CALL CRLF
        JMP  SLS2
SLSKIP: CALL SKIPREC
        JMP  SLS2
SLSEND: POP  D
        JMP  ENDST

; print one program line (no newline); HL = record -> HL = next record
LISTLINE:
        MOV  E,M
        INX  H
        MOV  D,M
        INX  H
        XCHG
        CALL PRTUNS
        MVI  A,' '
        CALL OUTC
        XCHG
LL1:    MOV  A,M
        INX  H
        CPI  CR
        RZ
        CALL OUTC
        JMP  LL1

; ---------------- disk statements ----------------
S_SAVE: CALL GETNAME
        PUSH D
        CALL CH_ENSURE
        ORA  A
        JNZ  DISKERR
        LXI  H,NAMEBUF
        CALL CH_FCREATE
        CPI  14H
        JNZ  DISKERR
        LXI  H,PROG
SV1:    MOV  E,M
        INX  H
        MOV  D,M
        DCX  H
        MOV  A,D
        ORA  E
        JZ   SV9
        PUSH H
        LXI  H,FBUF
        SHLD OUTPTR
        MVI  A,1
        STA  OUTFLG
        POP  H
        CALL LISTLINE
        PUSH H
        MVI  A,CR
        CALL OUTC
        MVI  A,LF
        CALL OUTC
        XRA  A
        STA  OUTFLG
        LHLD OUTPTR
        LXI  D,FBUF
        MOV  A,L
        SUB  E
        MOV  C,A
        MOV  A,H
        SBB  D
        MOV  B,A
        LXI  H,FBUF
        CALL CH_WRITE
        CPI  14H
        JNZ  DISKERR
        POP  H
        JMP  SV1
SV9:    MVI  A,1
        CALL CH_CLOSE
        CPI  14H
        JNZ  DISKERR
        POP  D
        JMP  ENDST

S_LOAD: CALL GETNAME
        LDA  NAMEBUF+1          ; LOAD "$" lists the directory (same as DIR)
        CPI  '$'
        JNZ  SLD0
        LDA  NAMEBUF+2
        CPI  '.'
        JZ   S_DIR
SLD0:   PUSH D
        CALL CH_ENSURE
        ORA  A
        JNZ  DISKERR
        LXI  H,NAMEBUF
        CALL CH_FOPEN
        CPI  14H
        JNZ  DISKERR
        CALL DONEW
        CALL CH_RDINIT
LD1:    LXI  H,FBUF
        SHLD LDPTR
        XRA  A
        STA  LDCNT
LD2:    CALL CH_GETC
        JC   LD5
        CPI  CR
        JZ   LD4
        CPI  LF
        JZ   LD4
        MOV  C,A
        LDA  LDCNT
        CPI  90
        JNC  LD2
        INR  A
        STA  LDCNT
        LHLD LDPTR
        MOV  M,C
        INX  H
        SHLD LDPTR
        JMP  LD2
LD4:    CALL LDPROC
        JMP  LD1
LD5:    CALL LDPROC
        XRA  A
        CALL CH_CLOSE
        POP  D
        JMP  ENDST

; process the line collected in FBUF (numbered lines only)
LDPROC: LDA  LDCNT
        ORA  A
        RZ
        LHLD LDPTR
        MVI  M,CR
        LXI  H,FBUF
        MVI  B,0
LP1:    MOV  A,M
        CPI  CR
        JZ   LP4
        CPI  QT
        JNZ  LP2
        MOV  A,B
        XRI  1
        MOV  B,A
        JMP  LP3
LP2:    MOV  C,A
        MOV  A,B
        ORA  A
        JNZ  LP3
        MOV  A,C
        CPI  'a'
        JC   LP3
        CPI  'z'+1
        JNC  LP3
        ANI  5FH
        MOV  M,A
LP3:    INX  H
        JMP  LP1
LP4:    LXI  D,FBUF
        CALL SKIPSP
        CALL ISDIG
        RNC
        CALL GETNUM
        MOV  A,H
        ORA  L
        RZ
        JMP  ENTLN

S_ERASE:CALL GETNAME
        PUSH D
        CALL CH_ENSURE
        ORA  A
        JNZ  DISKERR
        LXI  H,NAMEBUF
        CALL CH_FERASE
        CPI  14H
        JNZ  DISKERR
        POP  D
        JMP  ENDST

S_DIR:  PUSH D
        CALL DODIR
        ORA  A
        JNZ  DISKERR
        POP  D
        JMP  ENDST

; list the root directory. A = 0 ok, else disk error code
DODIR:  CALL CH_ENSURE
        ORA  A
        RNZ
        CALL CH_DIRFIRST
SD1:    CPI  1DH
        JNZ  SD9
        CALL PRDIRENT
        CALL BRKCHK
        JC   SD8
        CALL CH_DIRNEXT
        JMP  SD1
SD8:    XRA  A
        RET
SD9:    CPI  42H
        RNZ
        XRA  A
        RET

PRDIRENT:
        LDA  DIRBUF+11
        ANI  08H
        RNZ                     ; volume label
        LXI  H,DIRBUF
        MVI  B,8
        CALL PRFLD
        MOV  A,M
        CPI  ' '
        JZ   PDE1
        MVI  A,'.'
        CALL OUTC
        MVI  B,3
        CALL PRFLD
PDE1:   MVI  A,' '
        CALL OUTC
        LDA  COLUMN
        CPI  13
        JC   PDE1
        LDA  DIRBUF+11
        ANI  10H
        JZ   PDE2
        LXI  H,MDIRTAG
        CALL PRMSG
        JMP  CRLF
PDE2:   LHLD DIRBUF+30
        MOV  A,H
        ORA  L
        JZ   PDE3
        LXI  H,MBIG
        CALL PRMSG
        JMP  CRLF
PDE3:   LHLD DIRBUF+28
        CALL PRTUNS
        JMP  CRLF

PRFLD:  MOV  A,M
        INX  H
        CPI  ' '
        CNZ  OUTC
        DCR  B
        JNZ  PRFLD
        RET

; "name" -> NAMEBUF as /NAME.EXT (".BAS" added if no extension)
GETNAME:CALL SKIPSP
        CPI  QT
        JNZ  WHAT
        INX  D
        LXI  H,NAMEBUF
        LDAX D
        CPI  '/'
        JZ   GNM1
        MVI  M,'/'
        INX  H
GNM1:   MVI  B,0
        MVI  C,20
GNM2:   LDAX D
        CPI  CR
        JZ   GNM4
        INX  D
        CPI  QT
        JZ   GNM4
        CPI  '.'
        JNZ  GNM3
        MVI  B,1
GNM3:   MOV  M,A
        INX  H
        DCR  C
        JNZ  GNM2
        JMP  WHAT
GNM4:   MOV  A,B
        ORA  A
        JNZ  GNM5
        MVI  M,'.'
        INX  H
        MVI  M,'B'
        INX  H
        MVI  M,'A'
        INX  H
        MVI  M,'S'
        INX  H
GNM5:   MVI  M,0
        RET

; =====================================================================
;  Program storage
; =====================================================================
DONEW:  CALL ISRCLR
        LXI  H,PROG
        SHLD PRGEND
        XRA  A
        MOV  M,A
        INX  H
        MOV  M,A
        RET

; DE = line number -> HL = first record with number >= DE, Z if equal
FINDLN: LXI  H,PROG
FL1:    MOV  C,M
        INX  H
        MOV  B,M
        DCX  H
        MOV  A,B
        ORA  C
        JZ   FL9                ; end marker
        MOV  A,B
        CMP  D
        JC   FL2
        JNZ  FL9
        MOV  A,C
        CMP  E
        JC   FL2
        RET                     ; Z if equal, NZ if greater
FL2:    CALL SKIPREC
        JMP  FL1
FL9:    MVI  A,1
        ORA  A
        RET

; HL = record start -> HL = start of next record
SKIPREC:INX  H
        INX  H
SKR1:   MOV  A,M
        INX  H
        CPI  CR
        JNZ  SKR1
        RET

MOVEDN: MOV  A,B                ; HL src, DE dst, BC count, ascending
        ORA  C
        RZ
        MOV  A,M
        STAX D
        INX  H
        INX  D
        DCX  B
        JMP  MOVEDN

MOVEUP: MOV  A,B                ; HL src end, DE dst end, BC count, descending
        ORA  C
        RZ
        MOV  A,M
        STAX D
        DCX  H
        DCX  D
        DCX  B
        JMP  MOVEUP

; HL = line number, DE = text after the number. Insert / replace / delete.
ENTLN:  SHLD LNNUM
        CALL SKIPSP
        XCHG
        SHLD LNSRC
        XCHG
        LXI  B,0
EL1:    LDAX D
        INX  D
        INX  B
        CPI  CR
        JNZ  EL1
        MOV  H,B
        MOV  L,C
        SHLD LNLEN              ; text length including CR
        INX  H
        INX  H
        SHLD LNSZ               ; record size
        LHLD LNNUM
        XCHG
        CALL FINDLN
        SHLD LNREC
        JNZ  EL3
        MOV  D,H                ; delete the old record
        MOV  E,L
        INX  H
        INX  H
EL2:    MOV  A,M
        INX  H
        CPI  CR
        JNZ  EL2                ; HL = next record, DE = old record
        PUSH H
        MOV  A,L
        SUB  E
        MOV  C,A
        MOV  A,H
        SBB  D
        MOV  B,A                ; BC = old record size
        LHLD PRGEND
        MOV  A,L
        SUB  C
        MOV  L,A
        MOV  A,H
        SBB  B
        MOV  H,A
        SHLD PRGEND
        INX  H
        INX  H
        MOV  A,L
        SUB  E
        MOV  C,A
        MOV  A,H
        SBB  D
        MOV  B,A                ; BC = bytes to move
        POP  H
        CALL MOVEDN
EL3:    LHLD LNLEN
        DCX  H
        MOV  A,H
        ORA  L
        RZ                      ; empty text: deletion only
        LHLD PRGEND
        XCHG
        LHLD LNSZ
        DAD  D
        MOV  A,H
        CPI  RAMTOP/256-1
        JNC  SORRY
        LHLD PRGEND
        INX  H
        SHLD TMPA               ; source end
        XCHG
        LHLD LNSZ
        DAD  D
        SHLD TMPB               ; destination end
        LHLD LNREC
        XCHG
        LHLD TMPA
        MOV  A,L
        SUB  E
        MOV  C,A
        MOV  A,H
        SBB  D
        MOV  B,A
        INX  B                  ; BC = count
        LHLD TMPB
        XCHG
        LHLD TMPA
        CALL MOVEUP
        LHLD LNREC
        XCHG
        LHLD LNNUM
        XCHG                    ; HL = record, DE = number
        MOV  M,E
        INX  H
        MOV  M,D
        INX  H
        XCHG                    ; DE = text destination
        LHLD LNLEN
        MOV  B,H
        MOV  C,L
        LHLD LNSRC
        CALL MOVEDN
        LHLD PRGEND
        XCHG
        LHLD LNSZ
        DAD  D
        SHLD PRGEND
        RET

; =====================================================================
;  Expressions
; =====================================================================
; expression levels, lowest precedence first:
;   OR XOR  <  AND  <  relations (= < > <= >= <> #)  <  << >>  <  + -  <  * /
EXPR:   CALL EXPAN
EO1:    CALL SKIPSP
        PUSH H                  ; left value
        LXI  H,ORTAB
        CALL FINDKW             ; BC = 0 for OR, 1 for XOR
        JC   EO2
        POP  H
        RET
EO2:    MOV  A,C
        PUSH PSW                ; operation
        CALL EXPAN              ; HL = right value
        POP  PSW
        POP  B                  ; BC = left value
        ORA  A
        JNZ  EOX
        MOV  A,H
        ORA  B
        MOV  H,A
        MOV  A,L
        ORA  C
        MOV  L,A
        JMP  EO1
EOX:    MOV  A,H
        XRA  B
        MOV  H,A
        MOV  A,L
        XRA  C
        MOV  L,A
        JMP  EO1

EXPAN:  CALL EXPREL
EA1:    CALL SKIPSP
        PUSH H                  ; left value
        LXI  H,ANDTAB
        CALL FINDKW
        JC   EA2
        POP  H
        RET
EA2:    CALL EXPREL             ; HL = right value
        POP  B
        MOV  A,H
        ANA  B
        MOV  H,A
        MOV  A,L
        ANA  C
        MOV  L,A
        JMP  EA1

; shifts: value << count, value >> count (logical, 16 bit; count above 15 gives 0)
EXPSH:  CALL EXPR1
EXS1:   CALL SKIPSP
        CPI  '<'
        JZ   ESL
        CPI  '>'
        JZ   ESR
        RET
ESL:    INX  D
        LDAX D
        DCX  D
        CPI  '<'
        RNZ                     ; just a "<" relation
        INX  D
        INX  D
        PUSH H
        CALL EXPR1
        POP  B
        CALL SHLBC
        JMP  EXS1
ESR:    INX  D
        LDAX D
        DCX  D
        CPI  '>'
        RNZ
        INX  D
        INX  D
        PUSH H
        CALL EXPR1
        POP  B
        CALL SHRBC
        JMP  EXS1

; HL = BC << HL
SHLBC:  MOV  A,H
        ORA  A
        JNZ  SHZ
        MOV  A,L
        CPI  16
        JNC  SHZ
        ORA  A
        JZ   SHN
SHL1:   MOV  A,C
        ADD  A
        MOV  C,A
        MOV  A,B
        RAL
        MOV  B,A
        DCR  L
        JNZ  SHL1
SHN:    MOV  H,B
        MOV  L,C
        RET
SHZ:    LXI  H,0
        RET

; HL = BC >> HL (zero fill)
SHRBC:  MOV  A,H
        ORA  A
        JNZ  SHZ
        MOV  A,L
        CPI  16
        JNC  SHZ
        ORA  A
        JZ   SHN
SHR1:   ORA  A
        MOV  A,B
        RAR
        MOV  B,A
        MOV  A,C
        RAR
        MOV  C,A
        DCR  L
        JNZ  SHR1
        JMP  SHN

EXPREL: CALL EXPSH
        CALL SKIPSP
        CPI  '='
        JZ   XR_EQ
        CPI  '#'
        JZ   XR_EQ2
        CPI  '<'
        JZ   XR_LT
        CPI  '>'
        JZ   XR_GT
        RET
XR_EQ:  MVI  A,2
        JMP  XR_D1
XR_EQ2: MVI  A,5
        JMP  XR_D1
XR_LT:  INX  D
        LDAX D
        CPI  '='
        JZ   XR_LE
        CPI  '>'
        JZ   XR_NE
        MVI  A,1
        JMP  XR_DO
XR_LE:  INX  D
        MVI  A,3
        JMP  XR_DO
XR_NE:  INX  D
        MVI  A,5
        JMP  XR_DO
XR_GT:  INX  D
        LDAX D
        CPI  '='
        JZ   XR_GE
        CPI  '<'
        JZ   XR_NE
        MVI  A,4
        JMP  XR_DO
XR_GE:  INX  D
        MVI  A,6
        JMP  XR_DO
XR_D1:  INX  D
XR_DO:  PUSH H                  ; left value
        PUSH PSW                ; relation mask: 1 <, 2 =, 4 >
        CALL EXPSH
        POP  PSW
        STA  RELM
        POP  B
        CALL SCMP
        ORA  A
        JZ   XR_E
        JM   XR_L
        MVI  A,4
        JMP  XR_T
XR_L:   MVI  A,1
        JMP  XR_T
XR_E:   MVI  A,2
XR_T:   LXI  H,RELM
        ANA  M
        LXI  H,0
        RZ
        DCX  H                  ; true is -1 (all bits set) so AND/OR/NOT work on it
        RET

EXPR1:  CALL TERM
EX1L:   CALL SKIPSP
        CPI  '+'
        JZ   EX1A
        CPI  '-'
        JZ   EX1S
        RET
EX1A:   INX  D
        PUSH H
        CALL TERM
        POP  B
        DAD  B
        JMP  EX1L
EX1S:   INX  D
        PUSH H
        CALL TERM
        POP  B
        MOV  A,C
        SUB  L
        MOV  L,A
        MOV  A,B
        SBB  H
        MOV  H,A
        JMP  EX1L

TERM:   CALL FACTOR
TM1:    CALL SKIPSP
        CPI  '*'
        JZ   TMM
        CPI  '/'
        JZ   TMD
        RET
TMM:    INX  D
        PUSH H
        CALL FACTOR
        POP  B
        CALL MULT
        JMP  TM1
TMD:    INX  D
        PUSH H
        CALL FACTOR
        POP  B
        CALL DIVS
        JMP  TM1

FACTOR: CALL SKIPSP
        CPI  '('
        JZ   FPAR
        CPI  '-'
        JZ   FNEG
        CPI  '+'
        JZ   FPOS
        CPI  '@'
        JZ   FARR
        CPI  '$'
        JZ   FHEX
        CALL ISDIG
        JC   GETNUM
        CPI  'A'
        JC   WHAT
        CPI  'Z'+1
        JNC  WHAT
        LXI  H,FUNTAB
        CALL FINDKW
        JNC  FVAR
        MOV  H,B
        MOV  L,C
        PCHL                    ; function returns to FACTOR's caller
FVAR:   CALL VARADDR
        MOV  A,M
        INX  H
        MOV  H,M
        MOV  L,A
        RET
FPAR:   INX  D
        CALL EXPR
        MVI  A,')'
        JMP  EXPECT
FNEG:   INX  D
        CALL FACTOR
        JMP  NEGHL
FPOS:   INX  D
        JMP  FACTOR
FARR:   CALL ARRADDR
        MOV  A,M
        INX  H
        MOV  H,M
        MOV  L,A
        RET
FHEX:   INX  D
        LXI  H,0
FH1:    LDAX D
        CPI  '0'
        RC
        CPI  '9'+1
        JC   FH2
        CPI  'A'
        RC
        CPI  'F'+1
        RNC
        SUI  'A'-10
        JMP  FH3
FH2:    SUI  '0'
FH3:    INX  D
        DAD  H
        DAD  H
        DAD  H
        DAD  H
        MOV  C,A
        MVI  B,0
        DAD  B
        JMP  FH1

PAREXP: MVI  A,'('
        CALL EXPECT
        CALL EXPR
        MVI  A,')'
        JMP  EXPECT

ARRADDR:INX  D                  ; DE was at '@'
        CALL PAREXP
        MOV  A,H
        ORA  A
        JNZ  HOW
        MOV  A,L
        CPI  128
        JNC  HOW
        DAD  H
        LXI  B,ARRAY
        DAD  B
        RET

; ---------------- functions (return value in HL) ----------------
F_ABS:  CALL PAREXP
        MOV  A,H
        ORA  A
        RP
        JMP  NEGHL

F_SIZE: LHLD PRGEND
        MOV  B,H
        MOV  C,L
        LXI  H,RAMTOP
        MOV  A,L
        SUB  C
        MOV  L,A
        MOV  A,H
        SBB  B
        MOV  H,A
        RET

; NOT x: all bits inverted
F_NOT:  CALL FACTOR
        MOV  A,H
        CMA
        MOV  H,A
        MOV  A,L
        CMA
        MOV  L,A
        RET

; INKEY(d): next byte received on device d (0 = serial card, 1 = keyboard/display
; card), or -1 if none is waiting.  d must not be the console.
F_INKEY:CALL PAREXP
        MOV  A,H
        ORA  A
        JNZ  HOW
        MOV  A,L
        CPI  2
        JNC  HOW
        MOV  C,A
        LDA  CONSEL
        CMP  C
        JZ   HOW
        PUSH D
        MOV  A,C
        ORA  A
        JNZ  FIK1
        LXI  D,SRX_HEAD
        MVI  H,SRXBUF/256
        JMP  FIK2
FIK1:   LXI  D,KRX_HEAD
        MVI  H,KRXBUF/256
FIK2:   CALL RXGET
        POP  D
        JC   FIK3
        LXI  H,0FFFFH
        RET
FIK3:   MOV  L,A
        MVI  H,0
        RET

; USR(addr) or USR(addr,arg): call machine code at addr with HL = arg
; (0 if omitted); the routine returns the value in HL with RET.  It may
; use every register but must leave the stack as it found it.
F_USR:  MVI  A,'('
        CALL EXPECT
        CALL EXPR
        PUSH H
        CALL SKIPSP
        CPI  ','
        LXI  H,0
        JNZ  FU1
        INX  D
        CALL EXPR
FU1:    MVI  A,')'
        CALL EXPECT
        XTHL                    ; HL = address, stack = argument
        SHLD USRTHK+1
        POP  H                  ; HL = argument
        PUSH D
        CALL USRTHK
        POP  D
        RET

; IFR: the 65C22 interrupt flags the IRQ 2 handler has seen and cleared
; since the last time this was read (bits as in the VIA's IFR); reading clears
F_IFR:  DI
        LDA  VIAFLG
        MOV  L,A
        XRA  A
        STA  VIAFLG
        EI
        MVI  H,0
        RET

F_PEEK: CALL PAREXP
        MOV  L,M
        MVI  H,0
        RET

F_IN:   CALL PAREXP
        MOV  A,L
        STA  IOIN+1
        CALL IOIN
        MOV  L,A
        MVI  H,0
        RET

F_RND:  CALL PAREXP
        MOV  A,H
        ORA  A
        JM   HOW
        ORA  L
        JZ   HOW
        SHLD RNDN
        LHLD RNDSEED
        LXI  B,25173
        CALL MULT
        LXI  B,13849
        DAD  B
        SHLD RNDSEED
        MOV  A,H
        ANI  7FH
        MOV  H,A
        SHLD RNDR
        MOV  B,H
        MOV  C,L
        LHLD RNDN
        CALL DIVS               ; HL = r / n
        MOV  B,H
        MOV  C,L
        LHLD RNDN
        CALL MULT               ; HL = q * n
        MOV  B,H
        MOV  C,L
        LHLD RNDR
        MOV  A,L
        SUB  C
        MOV  L,A
        MOV  A,H
        SBB  B
        MOV  H,A
        INX  H
        RET

; ---------------- arithmetic ----------------
NEGHL:  MOV  A,L
        CMA
        MOV  L,A
        MOV  A,H
        CMA
        MOV  H,A
        INX  H
        RET

NEGBC:  MOV  A,C
        CMA
        MOV  C,A
        MOV  A,B
        CMA
        MOV  B,A
        INX  B
        RET

; HL = BC * HL (low 16 bits), preserves DE
MULT:   PUSH D
        XCHG
        LXI  H,0
ML1:    MOV  A,D
        ORA  E
        JZ   ML3
        MOV  A,D
        ORA  A
        RAR
        MOV  D,A
        MOV  A,E
        RAR
        MOV  E,A
        JNC  ML2
        DAD  B
ML2:    MOV  A,C
        ADD  A
        MOV  C,A
        MOV  A,B
        RAL
        MOV  B,A
        JMP  ML1
ML3:    POP  D
        RET

; HL = BC / HL (signed), preserves DE; HOW? on divide by zero
DIVS:   MOV  A,H
        ORA  L
        JZ   HOW
        PUSH D
        MOV  A,B
        XRA  H
        PUSH PSW                ; bit 7 = sign of result
        MOV  A,B
        ORA  A
        JP   DV1
        CALL NEGBC
DV1:    MOV  A,H
        ORA  A
        JP   DV2
        CALL NEGHL
DV2:    XCHG
        MOV  A,E
        CMA
        MOV  E,A
        MOV  A,D
        CMA
        MOV  D,A
        INX  D                  ; DE = -divisor
        LXI  H,0                ; remainder
        MVI  A,16
DV3:    PUSH PSW
        MOV  A,C
        ADD  A
        MOV  C,A
        MOV  A,B
        RAL
        MOV  B,A
        MOV  A,L
        RAL
        MOV  L,A
        MOV  A,H
        RAL
        MOV  H,A
        PUSH H
        DAD  D
        JNC  DV4
        INX  SP
        INX  SP
        INR  C
        JMP  DV5
DV4:    POP  H
DV5:    POP  PSW
        DCR  A
        JNZ  DV3
        MOV  H,B
        MOV  L,C
        POP  PSW
        ORA  A
        JP   DV6
        CALL NEGHL
DV6:    POP  D
        RET

; A = sign of (BC - HL) as -1, 0, 1 (signed compare)
SCMP:   MOV  A,B
        XRA  H
        JP   SC1
        MOV  A,B
        ORA  A
        JM   SCLT
        JMP  SCGT
SC1:    MOV  A,B
        CMP  H
        JC   SCLT
        JNZ  SCGT
        MOV  A,C
        CMP  L
        JC   SCLT
        JNZ  SCGT
        XRA  A
        RET
SCLT:   MVI  A,0FFH
        RET
SCGT:   MVI  A,1
        RET

; ---------------- parsing helpers ----------------
SKIPSP: LDAX D
        CPI  ' '
        RNZ
        INX  D
        JMP  SKIPSP

; CY=1 if A is a digit
ISDIG:  CPI  '0'
        JC   ISD0
        CPI  '9'+1
        JNC  ISD0
        STC
        RET
ISD0:   ORA  A
        RET

; decimal number at DE -> HL
GETNUM: LXI  H,0
GNL:    LDAX D
        CALL ISDIG
        RNC
        INX  D
        SUI  '0'
        PUSH PSW
        DAD  H
        MOV  B,H
        MOV  C,L
        DAD  H
        DAD  H
        DAD  B
        POP  PSW
        MOV  C,A
        MVI  B,0
        DAD  B
        JMP  GNL

; variable letter at DE -> HL = address, CY=1 if not a variable
VARADDR:CALL SKIPSP
        CPI  'A'
        JC   VNO
        CPI  'Z'+1
        JNC  VNO
        INX  D
        SUI  'A'
        ADD  A
        MOV  L,A
        MVI  H,0
        LXI  B,VARTAB
        DAD  B
        ORA  A
        RET
VNO:    STC
        RET

; next non-blank must be A, else WHAT?
EXPECT: MOV  B,A
        CALL SKIPSP
        CMP  B
        JNZ  WHAT
        INX  D
        RET

; keyword table lookup: DE = text, HL = table.
; CY=1: BC = handler, DE advanced.  CY=0: DE unchanged.
FINDKW: PUSH D
FK0:    MOV  A,M
        ORA  A
        JZ   FKFAIL
        POP  D
        PUSH D
FK1:    LDAX D
        MOV  B,A
        MOV  A,M
        ANI  7FH
        CMP  B
        JNZ  FKSKIP
        MOV  A,M
        INX  H
        INX  D
        ORA  A
        JP   FK1
        MOV  C,M
        INX  H
        MOV  B,M
        INX  SP
        INX  SP
        STC
        RET
FKSKIP: MOV  A,M
        INX  H
        ORA  A
        JP   FKSKIP
        INX  H
        INX  H
        JMP  FK0
FKFAIL: POP  D
        ORA  A
        RET

; find the FOR frame whose variable is FORVAR. CY=1: HL = frame address
FNDFOR: PUSH D
        LXI  H,4
        DAD  SP                 ; caller's SP
FF1:    MOV  A,H
        ORA  L
        JZ   FFNO
        MOV  C,M
        INX  H
        INX  H
        MOV  A,C
        CPI  2
        JNZ  FF2
        MOV  E,M
        INX  H
        MOV  D,M
        PUSH H
        LHLD FORVAR
        MOV  A,L
        CMP  E
        JNZ  FF3
        MOV  A,H
        CMP  D
        JNZ  FF3
        POP  H
        LXI  B,-3
        DAD  B
        POP  D
        STC
        RET
FF3:    POP  H
        LXI  B,9
        DAD  B
        JMP  FF1
FF2:    LXI  B,4
        DAD  B
        JMP  FF1
FFNO:   POP  D
        ORA  A
        RET

STKCHK: LXI  H,0
        DAD  SP
        MOV  A,H
        CPI  0FCH
        RNC
        JMP  SORRY

; =====================================================================
;  Console helpers
; =====================================================================
OUTC:   PUSH H
        PUSH PSW
        LDA  OUTFLG
        ORA  A
        JNZ  OC_BUF
        LXI  H,COLUMN
        POP  PSW
        PUSH PSW
        CPI  CR
        JNZ  OC1
        MVI  M,0
        JMP  OC3
OC1:    CPI  20H
        JC   OC3
        INR  M
OC3:    POP  PSW
        POP  H
        JMP  CONOUT
OC_BUF: POP  PSW
        LHLD OUTPTR
        MOV  M,A
        INX  H
        SHLD OUTPTR
        POP  H
        RET

CRLF:   MVI  A,CR
        CALL OUTC
        MVI  A,LF
        JMP  OUTC

PRMSG:  MOV  A,M
        INX  H
        ORA  A
        RZ
        CALL OUTC
        JMP  PRMSG

PRTAB:  MVI  A,' '
        CALL OUTC
        LDA  COLUMN
        ANI  7
        JNZ  PRTAB
        RET

PRHEX:  PUSH PSW
        RRC
        RRC
        RRC
        RRC
        CALL PRHEX1
        POP  PSW
PRHEX1: ANI  0FH
        ADI  '0'
        CPI  '9'+1
        JC   PRH2
        ADI  7
PRH2:   JMP  OUTC

; HL in hex: 2 digits if it fits in a byte, else 4
PRTHEX: MOV  A,H
        ORA  A
        JZ   PRTHL
        CALL PRHEX
PRTHL:  MOV  A,L
        JMP  PRHEX

; signed HL
PRTNUM: MOV  A,H
        ORA  A
        JP   PRTUNS
        MVI  A,'-'
        CALL OUTC
        CALL NEGHL
; unsigned HL, preserves DE
PRTUNS: PUSH D
        MVI  B,0
        LXI  D,-10000
        CALL PD1
        LXI  D,-1000
        CALL PD1
        LXI  D,-100
        CALL PD1
        LXI  D,-10
        CALL PD1
        MOV  A,L
        ADI  '0'
        CALL OUTC
        POP  D
        RET
PD1:    MVI  C,'0'
PD2:    PUSH H
        DAD  D
        JNC  PD3
        INX  SP
        INX  SP
        INR  C
        JMP  PD2
PD3:    POP  H
        MOV  A,C
        CPI  '0'
        JNZ  PD4
        MOV  A,B
        ORA  A
        RZ
PD4:    MVI  B,1
        MOV  A,C
        JMP  OUTC

; wait for a key; keeps the random seed churning. Preserves BC DE HL.
GETKEY: PUSH H
        PUSH D
        PUSH B
GK1:    DI                      ; poll the 6551 of the active console here, so typing
        LDA  CONSEL             ; works even if the interrupt path is not (yet)
        ORA  A                  ; working.  The other port is left alone, so an
        JNZ  GKK                ; unplugged serial cable cannot get in the way.
        CALL SERSVC
        JMP  GKE
GKK:    CALL KBSVC
GKE:    EI
        LDA  ISRPEND
        ORA  A
        CNZ  ISRPOLL            ; a SETISR handler may run while we wait for a key
        LDA  BRKFLG
        ORA  A
        JNZ  GK3
        CALL CONST
        ORA  A
        JNZ  GK2
        LHLD RNDSEED
        INX  H
        SHLD RNDSEED
        JMP  GK1
GK3:    XRA  A
        STA  BRKFLG
        MVI  A,3
        JMP  GK4
GK2:    CALL CONIN
GK4:    POP  B
        POP  D
        POP  H
        RET

; CY=1 if Ctrl-C was pressed (flag set by the receive ISR). Preserves all but A.
BRKCHK: LDA  BRKFLG
        ORA  A
        RZ
        XRA  A
        STA  BRKFLG
        STC
        RET

; line editor: HL = buffer, B = max length. CY=1 if Ctrl-C.
; Uppercases outside quotes. Clobbers BC DE HL.
GETLN:  MVI  C,0
        MVI  D,0
GL1:    CALL GETKEY
        CPI  CR
        JZ   GLEND
        CPI  3
        JZ   GLBRK
        CPI  BS
        JZ   GLBS
        CPI  DEL
        JZ   GLBS
        CPI  20H
        JC   GL1
        MOV  E,A
        MOV  A,C
        CMP  B
        JNC  GL1
        MOV  A,E
        CPI  QT
        JNZ  GL2
        MOV  A,D
        XRI  1
        MOV  D,A
        JMP  GL4
GL2:    MOV  A,D
        ORA  A
        JNZ  GL4
        MOV  A,E
        CPI  'a'
        JC   GL4
        CPI  'z'+1
        JNC  GL4
        ANI  5FH
        MOV  E,A
GL4:    MOV  A,E
        MOV  M,A
        INX  H
        INR  C
        CALL OUTC
        JMP  GL1
GLBS:   MOV  A,C
        ORA  A
        JZ   GL1
        DCX  H
        DCR  C
        MOV  A,M
        CPI  QT
        JNZ  GLBS2
        MOV  A,D
        XRI  1
        MOV  D,A
GLBS2:  MVI  A,BS
        CALL OUTC
        MVI  A,' '
        CALL OUTC
        MVI  A,BS
        CALL OUTC
        JMP  GL1
GLEND:  MVI  M,CR
        CALL CRLF
        ORA  A
        RET
GLBRK:  MVI  A,'^'
        CALL OUTC
        MVI  A,'C'
        CALL OUTC
        CALL CRLF
        STC
        RET

; =====================================================================
;  Tables and messages
; =====================================================================
STMTAB: DB   "LE",'T'+80H
        DW   S_LET
        DB   'I','F'+80H
        DW   S_IF
        DB   "GOT",'O'+80H
        DW   S_GOTO
        DB   "GOSU",'B'+80H
        DW   S_GOSUB
        DB   "RETUR",'N'+80H
        DW   S_RETURN
        DB   "FO",'R'+80H
        DW   S_FOR
        DB   "NEX",'T'+80H
        DW   S_NEXT
        DB   "PRIN",'T'+80H
        DW   S_PRINT
        DB   '?'+80H
        DW   S_PRINT
        DB   "INPU",'T'+80H
        DW   S_INPUT
        DB   "RE",'M'+80H
        DW   S_REM
        DB   "EN",'D'+80H
        DW   S_END
        DB   "STO",'P'+80H
        DW   S_END
        DB   "RU",'N'+80H
        DW   S_RUN
        DB   "LIS",'T'+80H
        DW   S_LIST
        DB   "NE",'W'+80H
        DW   S_NEW
        DB   "POK",'E'+80H
        DW   S_POKE
        DB   "OU",'T'+80H
        DW   S_OUT
        DB   "SAV",'E'+80H
        DW   S_SAVE
        DB   "LOA",'D'+80H
        DW   S_LOAD
        DB   "DI",'R'+80H
        DW   S_DIR
        DB   "ERAS",'E'+80H
        DW   S_ERASE
        DB   "CL",'S'+80H
        DW   S_CLS
        DB   "MO",'N'+80H
        DW   S_MON
        DB   "SETIS",'R'+80H
        DW   S_SETISR
        DB   "CLRIS",'R'+80H
        DW   S_CLRISR
        DB   "SEN",'D'+80H
        DW   S_SEND
        DB   0

FUNTAB: DB   "INKE",'Y'+80H           ; before IN, which is a prefix of it
        DW   F_INKEY
        DB   "NO",'T'+80H
        DW   F_NOT
        DB   "AB",'S'+80H
        DW   F_ABS
        DB   "RN",'D'+80H
        DW   F_RND
        DB   "SIZ",'E'+80H
        DW   F_SIZE
        DB   "PEE",'K'+80H
        DW   F_PEEK
        DB   'I','N'+80H
        DW   F_IN
        DB   "US",'R'+80H
        DW   F_USR
        DB   "IF",'R'+80H
        DW   F_IFR
        DB   0

THENTAB:DB   "THE",'N'+80H
        DW   0
        DB   0
CHRTAB: DB   "CHR",'$'+80H
        DW   0
        DB   0
ORTAB:  DB   'O','R'+80H
        DW   0
        DB   "XO",'R'+80H
        DW   1
        DB   0
ANDTAB: DB   "AN",'D'+80H
        DW   0
        DB   0
TOTAB:  DB   'T','O'+80H
        DW   0
        DB   0
STEPTAB:DB   "STE",'P'+80H
        DW   0
        DB   0

MGOSUB: DB   "GOSUB ",0
MBANNER:DB   "TINY BASIC 8085",0
MFREE:  DB   " BYTES FREE",0
MWHAT:  DB   "WHAT?",0
MHOW:   DB   "HOW?",0
MSORRY: DB   "SORRY",0
MSTOP:  DB   "STOPPED",0
MIN:    DB   " IN ",0
MNOFILE:DB   "NO FILE",0
MDISK:  DB   "DISK ERR ",0
MDIRTAG:DB   "<DIR>",0
MBIG:   DB   ">64K",0
MCLS:   DB   1BH,"[2J",1BH,"[H",0
