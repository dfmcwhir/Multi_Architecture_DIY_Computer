; =====================================================================
;  CH376 driver - parallel interface, ports 20H (data) / 21H (command)
;  Polled: INT# is read from status bit 7 (0 = interrupt pending),
;  busy is status bit 4.  All routines preserve nothing unless noted.
;  Status codes returned in A: 14H = success, 1DH = more data,
;  1EH = write more, 42H = file not found, F0H/F1H/F2H = init errors,
;  FFH = timeout.
; =====================================================================

CH_DATA     EQU 20H
CH_CMD      EQU 21H

; CPU clock in kHz (4.9152 MHz crystal / 2 = 2.4576 MHz) - used only for
; the post-reset delay.
CPUKHZ      EQU 2458
CHDLYCNT    EQU (35*CPUKHZ)/24      ; about 35 ms per CH_DELAY

; RAM (inside the cleared 8030-80FF block)
CHBTMO      EQU 803DH               ; word: busy-wait loop count, 0 = 65536 (normal)
CHRES       EQU 803FH               ; result of the boot-time CH_INIT
CHFLAG      EQU 8037H               ; 1 = mounted
CHCNT       EQU 8038H               ; bytes left in CHBUF
CHEOF       EQU 8039H
CHPTR       EQU 803AH               ; word
CHBUF       EQU 8040H               ; 64 bytes
NAMEBUF     EQU 8080H               ; 32 bytes
DIRBUF      EQU 80A0H               ; 64 bytes (32 used)

; ---------------- low level ----------------
; wait until not busy; CY=1 on timeout
CH_BUSY:PUSH B
        PUSH H
        LHLD CHBTMO             ; 0 = full length wait; CH_INIT shortens it while probing
        MOV  B,H
        MOV  C,L
        POP  H
CBY1:   IN   CH_CMD
        ANI  10H
        JZ   CBY2
        DCX  B
        MOV  A,B
        ORA  C
        JNZ  CBY1
        POP  B
        STC
        RET
CBY2:   POP  B
        ORA  A
        RET

CH_CMDW:PUSH PSW                ; A = command code
        CALL CH_BUSY
        POP  PSW
        OUT  CH_CMD
        RET

CH_WRB: PUSH PSW                ; A = data byte
        CALL CH_BUSY
        POP  PSW
        OUT  CH_DATA
        RET

CH_RDB: CALL CH_BUSY            ; returns byte in A
        IN   CH_DATA
        RET

CH_DELAY:PUSH D
        LXI  D,CHDLYCNT
CDL1:   DCX  D
        MOV  A,D
        ORA  E
        JNZ  CDL1
        POP  D
        RET

; wait for interrupt, then GET_STATUS. A = status, CY=1 on timeout (A=FFH)
CH_WAITINT:
        PUSH B
        PUSH D
        MVI  E,6
CWI0:   LXI  B,0
CWI1:   IN   CH_CMD
        ANI  80H
        JZ   CWI2
        DCX  B
        MOV  A,B
        ORA  C
        JNZ  CWI1
        DCR  E
        JNZ  CWI0
        POP  D
        POP  B
        MVI  A,0FFH
        STC
        RET
CWI2:   MVI  A,22H              ; GET_STATUS
        CALL CH_CMDW
        CALL CH_RDB
        POP  D
        POP  B
        ORA  A
        RET

; same, but always returns the status in A (FFH on timeout), CY clear
CH_INTST:
        CALL CH_WAITINT
        RNC
        MVI  A,0FFH
        ORA  A
        RET

; discard any pending interrupt status
CH_FLUSH:
        MVI  B,8
CFL1:   IN   CH_CMD
        ANI  80H
        RNZ
        MVI  A,22H
        CALL CH_CMDW
        CALL CH_RDB
        DCR  B
        JNZ  CFL1
        RET

; Z set if a CH376 answers CHECK_EXIST
CH_CHECK:
        MVI  A,06H
        CALL CH_CMDW
        MVI  A,0A5H
        CALL CH_WRB
        CALL CH_RDB
        CPI  5AH
        RET

; ---------------- init / mount ----------------
; returns A = 0 ok, F0H no CH376, F1H USB mode failed, F2H no disk.
; Probing for the chip uses short timeouts, so a missing CH376 costs well
; under a second instead of minutes.
CHQUICK     EQU 0100H

CH_INIT:LXI  H,CHQUICK
        SHLD CHBTMO
        CALL CH_INIT0
        PUSH PSW
        LXI  H,0
        SHLD CHBTMO
        POP  PSW
        RET

CH_INIT0:
        XRA  A
        STA  CHFLAG
        MVI  A,05H              ; RESET_ALL
        CALL CH_CMDW
        CALL CH_DELAY
        CALL CH_DELAY
        MVI  B,4
CIN1:   CALL CH_CHECK
        JZ   CIN2
        CALL CH_DELAY
        DCR  B
        JNZ  CIN1
        MVI  A,0F0H
        RET
CIN2:   LXI  H,0                ; the chip answered: normal timeouts from here on
        SHLD CHBTMO
        MVI  A,15H              ; SET_USB_MODE
        CALL CH_CMDW
        MVI  A,06H              ; host, auto SOF
        CALL CH_WRB
        CALL CH_RDB
        CPI  51H
        JZ   CIN3
        MVI  A,0F1H
        RET
CIN3:   CALL CH_FLUSH
        MVI  B,5
CIN4:   MVI  A,31H              ; DISK_MOUNT
        CALL CH_CMDW
        CALL CH_INTST
        CPI  14H
        JZ   CIN6
        CALL CH_DELAY
        CALL CH_DELAY
        CALL CH_DELAY
        DCR  B
        JNZ  CIN4
        MVI  A,0F2H
        RET
CIN6:   MVI  A,1
        STA  CHFLAG
        XRA  A
        RET

; mount if not already; A = 0 ok else error code
CH_ENSURE:
        LDA  CHFLAG
        ORA  A
        JZ   CH_INIT
        XRA  A
        RET

; ---------------- files ----------------
; HL -> zero terminated name (e.g. "/PROG.BAS")
CH_SETNAME:
        MVI  A,2FH
        CALL CH_CMDW
CSN1:   MOV  A,M
        CALL CH_WRB
        MOV  A,M
        INX  H
        ORA  A
        JNZ  CSN1
        RET

; open existing file, A = status (14H ok, 42H not found)
CH_FOPEN:
        CALL CH_SETNAME
        MVI  A,32H
        CALL CH_CMDW
        JMP  CH_INTST

; create (replace) file, A = status
CH_FCREATE:
        PUSH H
        CALL CH_SETNAME
        MVI  A,35H              ; FILE_ERASE, result ignored
        CALL CH_CMDW
        CALL CH_INTST
        POP  H
        CALL CH_SETNAME
        MVI  A,34H              ; FILE_CREATE
        CALL CH_CMDW
        JMP  CH_INTST

; erase file named at HL, A = status
CH_FERASE:
        CALL CH_SETNAME
        MVI  A,35H
        CALL CH_CMDW
        JMP  CH_INTST

; close, A = 0 keep size, 1 update size. returns status in A
CH_CLOSE:
        PUSH PSW
        MVI  A,36H
        CALL CH_CMDW
        POP  PSW
        CALL CH_WRB
        JMP  CH_INTST

; write BC bytes from HL (BC > 0). returns status in A (14H ok)
CH_WRITE:
        MVI  A,3CH              ; BYTE_WRITE
        CALL CH_CMDW
        MOV  A,C
        CALL CH_WRB
        MOV  A,B
        CALL CH_WRB
CHW1:   CALL CH_INTST
        CPI  1EH
        RNZ
        MVI  A,2DH              ; WR_REQ_DATA
        CALL CH_CMDW
        CALL CH_RDB
        MOV  B,A
        ORA  A
        JZ   CHW3
CHW2:   MOV  A,M
        INX  H
        CALL CH_WRB
        DCR  B
        JNZ  CHW2
CHW3:   MVI  A,3DH              ; BYTE_WR_GO
        CALL CH_CMDW
        JMP  CHW1

; start reading the open file
CH_RDINIT:
        XRA  A
        STA  CHEOF
        STA  CHCNT
        MVI  A,3AH              ; BYTE_READ
        CALL CH_CMDW
        MVI  A,0FFH
        CALL CH_WRB
        CALL CH_WRB
        JMP  CH_RDSTAT

CH_RDSTAT:
        CALL CH_INTST
        CPI  1DH
        JZ   CRC0
        MVI  A,1
        STA  CHEOF
        RET
CRC0:   MVI  A,27H              ; RD_USB_DATA0
        CALL CH_CMDW
        CALL CH_RDB
        ANI  7FH
        JNZ  CRC1
        MVI  A,1
        STA  CHEOF
        RET
CRC1:   STA  CHCNT
        MOV  B,A
        LXI  H,CHBUF
CRC2:   CALL CH_RDB
        MOV  M,A
        INX  H
        DCR  B
        JNZ  CRC2
        LXI  H,CHBUF
        SHLD CHPTR
        RET

; next byte of the open file: A = byte, CY=0; CY=1 at end of file
CH_GETC:LDA  CHCNT
        ORA  A
        JNZ  CG2
        LDA  CHEOF
        ORA  A
        JNZ  CGE
        MVI  A,3BH              ; BYTE_RD_GO
        CALL CH_CMDW
        CALL CH_RDSTAT
        LDA  CHCNT
        ORA  A
        JZ   CGE
CG2:    DCR  A
        STA  CHCNT
        LHLD CHPTR
        MOV  A,M
        INX  H
        SHLD CHPTR
        ORA  A
        RET
CGE:    STC
        RET

; ---------------- directory ----------------
; A = 1DH: entry in DIRBUF.  42H: no more entries.  other: error
CH_DIRFIRST:
        LXI  H,CHDIRMASK
        CALL CH_SETNAME
        MVI  A,32H
        CALL CH_CMDW
        JMP  CHDG
CH_DIRNEXT:
        MVI  A,33H              ; FILE_ENUM_GO
        CALL CH_CMDW
CHDG:   CALL CH_INTST
        CPI  1DH
        RNZ
        MVI  A,27H
        CALL CH_CMDW
        CALL CH_RDB
        ANI  3FH
        MOV  B,A
        LXI  H,DIRBUF
        ORA  A
        JZ   CHDG2
CHDG1:  CALL CH_RDB
        MOV  M,A
        INX  H
        DCR  B
        JNZ  CHDG1
CHDG2:  MVI  A,1DH
        RET

CHDIRMASK:
        DB   "/*",0
