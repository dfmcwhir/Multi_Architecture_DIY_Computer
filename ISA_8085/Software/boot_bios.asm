; =====================================================================
;  8085 custom computer - boot, interrupts, 6551 drivers, BIOS table
;  ROM 0000-7FFF, RAM 8000-FFFF
;  Target assembler: Macroassembler AS (asl)
;    asl -L boot_bios.asm
;    p2bin boot_bios.p boot_bios.bin -r 0x0000-0x7FFF   (32K EPROM image)
; =====================================================================
        CPU  8085

; ---------------- I/O ports ----------------
ACIA_DATA   EQU 14H             ; serial card 6551
ACIA_STATUS EQU 15H
ACIA_CMD    EQU 16H
ACIA_CTRL   EQU 17H

KB_DATA     EQU 18H             ; keyboard/display card 6551
KB_STATUS   EQU 19H
KB_CMD      EQU 1AH
KB_CTRL     EQU 1BH

VIA_IFR     EQU 0DH             ; 65C22 interrupt flag register
VIA_IER     EQU 0EH             ; 65C22 interrupt enable register
INTREG      EQU 0FFH            ; interrupt register: (7 - IRQ number) * 2

; 6551 control register: bit 4 = 1 -> internal baud generator, 8 data
; bits, 1 stop bit.  With a 1.8432 MHz crystal: 1EH = 9600, 1FH = 19200.
; The KB/display card uses 10H = 115200 N-8-1 (value from the 6502 system).
; The serial card is set to 9600 here; change SERBAUD to taste.
SERBAUD     EQU 1EH
KBBAUD      EQU 10H

; 6551 command register: 09H = no parity, RTS/DTR on, TX int off, RX int ON
ACMD_RXINT  EQU 09H

; Console selected at power-up: 0 = serial card, 1 = keyboard/display card
DEFCON      EQU 1

; 1 = interrupt driven receive (RST 6.5 unmasked)
; 0 = polled only: RST 6.5 stays masked.  Use 0 to find out whether the
;     interrupt hardware is what is blocking the keyboard.  Keys are still
;     read whenever a program waits for one; characters typed while BASIC is
;     busy printing or running are lost.
USEIRQ      EQU 1
SIMVAL      EQU 1FH-(2*USEIRQ)  ; 1DH = unmask 6.5 only, 1FH = mask everything

; ---------------- RAM map ----------------
IRQTAB      EQU 8000H           ; 8 x 16-bit handler pointers
RST2VEC     EQU 8010H           ; 3-byte JMP slots for RST/TRAP hooks
RST3VEC     EQU 8013H
RST4VEC     EQU 8016H
TRAPVEC     EQU 8019H
RST5VEC     EQU 801CH
RST55VEC    EQU 801FH
RST6VEC     EQU 8022H
; 8025H slot is unused (RST 6.5 is the device interrupt)
RST75VEC    EQU 8028H

VARS        EQU 8030H           ; 8030-80FF cleared at boot
SRX_HEAD    EQU 8030H           ; head/tail MUST be adjacent (head first)
SRX_TAIL    EQU 8031H
KRX_HEAD    EQU 8032H
KRX_TAIL    EQU 8033H
CONSEL      EQU 8034H           ; 0 = serial console, 1 = keyboard/display
SSTAT       EQU 8035H           ; last serial status read
KSTAT       EQU 8036H           ; last KB/display status read
VIAFLG      EQU 80E0H           ; VIA flags (IFR bits) seen by the IRQ 2 handler, OR-ed together
ISRPEND     EQU 80E1H           ; bit n = IRQ n happened and a BASIC handler is waiting
ISRBUSY     EQU 80E2H           ; non-zero while a BASIC interrupt handler runs
ISRCTX      EQU 80E3H           ; non-zero while BASIC runs a handler's own text
ISRSP       EQU 80E4H           ; word: stack position to unwind to after a handler
ISRTXT      EQU 8600H           ; 8 x 48 bytes: BASIC handler text for each IRQ (0 = none)
BRKFLG      EQU 803CH           ; set by the receive ISRs when Ctrl-C arrives (not buffered)

SRXBUF      EQU 8100H           ; page-aligned 256-byte ring buffers
KRXBUF      EQU 8200H
; 8300H and up is free for BASIC / monitor workspace

; ---------------- Vectors ----------------
        ORG  0000H
RESET:  DI
        JMP  START

        ORG  0008H              ; RST 1 - monitor breakpoint
        JMP  BRKENT
        ORG  0010H              ; RST 2
        JMP  RST2VEC
        ORG  0018H              ; RST 3
        JMP  RST3VEC
        ORG  0020H              ; RST 4
        JMP  RST4VEC
        ORG  0024H              ; TRAP
        JMP  TRAPVEC
        ORG  0028H              ; RST 5
        JMP  RST5VEC
        ORG  002CH              ; RST 5.5
        JMP  RST55VEC
        ORG  0030H              ; RST 6
        JMP  RST6VEC
        ORG  0034H              ; RST 6.5 = all device interrupts (INTR line wired here)
        JMP  IRQENT
        ORG  0038H              ; RST 7 = INTR pin, only if the bus reads FFh on INTA
        JMP  IRQENT
        ORG  003CH              ; RST 7.5
        JMP  RST75VEC

; ---------------- INTR entry ----------------
        ORG  0040H
IRQENT: PUSH PSW
        PUSH B
        PUSH D
        PUSH H
        CALL KBSVC              ; always service both 6551s first, whatever the
        CALL SERSVC             ; interrupt register says (reading status clears IRQ)
        IN   INTREG             ; A = (7 - IRQ) * 2, FFH when nothing is pending
        ANI  0EH
        MOV  E,A
        MVI  A,14
        SUB  E                  ; A = IRQ * 2 = byte offset into IRQTAB
        MOV  E,A
        MVI  D,0
        LXI  H,IRQTAB
        DAD  D
        MOV  E,M
        INX  H
        MOV  D,M
        LXI  H,IRQDONE          ; handler RETs to IRQDONE
        PUSH H
        XCHG
        PCHL

IRQDONE:POP  H
        POP  D
        POP  B
        POP  PSW
        EI
        RET

DEFIRQ: RET

; IRQ 2 = the 65C22 on the I/O card.  Always acknowledges: it clears the
; IFR flags that are both set and enabled (writing 1s to IFR clears them)
; and remembers them in VIAFLG, so the line drops even if nobody wants the
; event.  BASIC reads the remembered flags with the IFR function.
VIAISR: IN   VIA_IFR
        MOV  B,A
        IN   VIA_IER
        ANA  B
        ANI  7FH
        RZ
        OUT  VIA_IFR
        LXI  H,VIAFLG
        ORA  M
        MOV  M,A
        RET


; ---------------- BIOS jump table (fixed address) ----------------
        ORG  0100H
CONIN:  JMP  CON_IN             ; wait for char, return in A
CONOUT: JMP  CON_OUT            ; send char in A
CONST:  JMP  CON_ST             ; A=FFH if char waiting, else 0
SERINP: JMP  SERIN
SEROUTP:JMP  SEROUT
SERSTP: JMP  SERST
KBINP:  JMP  KBIN
KBOUTP: JMP  KBOUT
KBSTP:  JMP  KBST
        ORG  0120H              ; CH376 entries (see ch376.asm for conventions)
CHINIT: JMP  CH_ENSURE          ; A=0 ok, else error code
CHOPEN: JMP  CH_FOPEN           ; HL=name -> A status (14H ok)
CHCREAT:JMP  CH_FCREATE
CHCLOSE:JMP  CH_CLOSE
CHWRITE:JMP  CH_WRITE
CHRDINI:JMP  CH_RDINIT
CHGETC: JMP  CH_GETC            ; A=byte, CY=1 at EOF

; ---------------- Boot ----------------
        ORG  0140H
START:  LXI  SP,0000H           ; first push lands at FFFFH/FFFEH

        ; default handler for every IRQ slot
        LXI  H,IRQTAB
        LXI  D,DEFIRQ
        MVI  B,8
FI1:    MOV  M,E
        INX  H
        MOV  M,D
        INX  H
        DCR  B
        JNZ  FI1

        ; default JMP DEFIRQ in each RST/TRAP hook slot (HL continues)
        LXI  H,RST2VEC
        MVI  B,9
FJ1:    MVI  M,0C3H
        INX  H
        MOV  M,E
        INX  H
        MOV  M,D
        INX  H
        DCR  B
        JNZ  FJ1

        ; clear variables 8030-80FF
        LXI  H,VARS
        XRA  A
CL1:    MOV  M,A
        INR  L
        JNZ  CL1

        MVI  A,DEFCON
        STA  CONSEL

        ; install real IRQ handlers
        LXI  H,VIAISR
        SHLD IRQTAB+4           ; IRQ 2 - 65C22 (acknowledge only)
        LXI  H,SERSVC
        SHLD IRQTAB+6           ; IRQ 3 - serial ACIA
        LXI  H,KBSVC
        SHLD IRQTAB+10          ; IRQ 5 - KB/display ACIA
        CALL ISRINIT            ; no BASIC interrupt handlers yet

        CALL SERINIT
        CALL KBINIT

        MVI  A,SIMVAL           ; SIM: see USEIRQ above
        SIM
        EI
        JMP  MONCOLD            ; boots into the monitor; B starts BASIC

; ---------------- Console routing ----------------
CON_IN: LDA  CONSEL
        ORA  A
        JZ   SERIN
CI_K:   CALL KBIN               ; KB card sends CR+LF on Enter:
        CPI  0AH                ; drop the LF so only CR reaches programs
        JZ   CI_K
        RET

CON_OUT:PUSH PSW
        LDA  CONSEL
        ORA  A
        JZ   CO_S
        POP  PSW
        JMP  KBOUT
CO_S:   POP  PSW
        JMP  SEROUT

CON_ST: LDA  CONSEL
        ORA  A
        JZ   SERST
        JMP  KBST

; ---------------- Ring buffer primitives ----------------
; RXSTORE: C = byte, DE -> head var (tail follows), H = buffer page
;          drops the byte if the buffer is full
RXSTORE:LDAX D                  ; head
        MOV  L,A
        INR  A
        MOV  B,A                ; new head
        INX  D
        LDAX D                  ; tail
        DCX  D
        CMP  B
        RZ                      ; full
        MOV  M,C
        MOV  A,B
        STAX D
        RET

; RXGET: DE -> head var, H = buffer page
;        returns CY=1 and A=byte, or CY=0 if empty
RXGET:  INX  D
        LDAX D                  ; tail
        DCX  D
        MOV  L,A
        MOV  B,A
        LDAX D                  ; head
        CMP  B
        JNZ  RG1
        XRA  A                  ; empty: CY=0
        RET
RG1:    MOV  C,M
        INR  B
        INX  D
        MOV  A,B
        STAX D                  ; tail = tail + 1
        DCX  D
        MOV  A,C
        STC
        RET

; ---------------- Serial card (6551) ----------------
SERINIT:OUT  ACIA_STATUS        ; any write = programmed reset
        MVI  A,SERBAUD
        OUT  ACIA_CTRL
        MVI  A,ACMD_RXINT
        OUT  ACIA_CMD
        RET

; Drain the receiver into the ring buffer. Reading status clears the
; chip's IRQ flag, so EVERY status read must be followed by draining RDRF
; or a byte can be stranded with no interrupt pending.
SERSVC: IN   ACIA_STATUS
        STA  SSTAT
        ANI  08H                ; RDRF
        RZ
        IN   ACIA_DATA
        MOV  C,A
        CPI  03H                ; Ctrl-C: flag it, don't buffer it
        JNZ  SRX1
        MVI  A,1
        STA  BRKFLG
        JMP  SERSVC
SRX1:   LXI  D,SRX_HEAD
        MVI  H,SRXBUF/256
        CALL RXSTORE
        CALL NOTE3
        JMP  SERSVC

SERIN:  LXI  D,SRX_HEAD
        MVI  H,SRXBUF/256
        CALL RXGET
        JNC  SERIN
        RET

SERST:  LDA  SRX_TAIL
        MOV  B,A
        LDA  SRX_HEAD
        CMP  B
        MVI  A,0
        RZ
        DCR  A                  ; FFH
        RET

; Polled transmit, preserves all registers. Disables interrupts around the
; status read, drains any received byte it finds, and re-enables interrupts
; on exit (don't call with interrupts intentionally off).
SEROUT: PUSH PSW
        PUSH B
        PUSH D
        PUSH H
SO1:    DI
        CALL SERSVC
        LDA  SSTAT
        ANI  10H                ; TDRE
        JNZ  SO2
        EI
        JMP  SO1
SO2:    POP  H
        POP  D
        POP  B
        POP  PSW
        OUT  ACIA_DATA
        EI
        RET

; A byte arrived on the serial card / keyboard card.  If BASIC has a SETISR
; handler for that IRQ (and the port is not the console) flag it.
NOTE3:  LDA  CONSEL
        ORA  A
        RZ
        LDA  ISRTXT+3*48
        ORA  A
        RZ
        LDA  ISRPEND
        ORI  08H
        STA  ISRPEND
        RET

NOTE5:  LDA  CONSEL
        ORA  A
        RNZ
        LDA  ISRTXT+5*48
        ORA  A
        RZ
        LDA  ISRPEND
        ORI  20H
        STA  ISRPEND
        RET

; ---------------- Keyboard/display card (6551) ----------------
KBINIT: OUT  KB_STATUS
        MVI  A,KBBAUD
        OUT  KB_CTRL
        MVI  A,ACMD_RXINT
        OUT  KB_CMD
        RET

KBSVC:  IN   KB_STATUS
        STA  KSTAT
        ANI  08H
        RZ
        IN   KB_DATA
        MOV  C,A
        CPI  03H
        JNZ  KRX1
        MVI  A,1
        STA  BRKFLG
        JMP  KBSVC
KRX1:   LXI  D,KRX_HEAD
        MVI  H,KRXBUF/256
        CALL RXSTORE
        CALL NOTE5
        JMP  KBSVC

KBIN:   LXI  D,KRX_HEAD
        MVI  H,KRXBUF/256
        CALL RXGET
        JNC  KBIN
        RET

KBST:   LDA  KRX_TAIL
        MOV  B,A
        LDA  KRX_HEAD
        CMP  B
        MVI  A,0
        RZ
        DCR  A
        RET

KBOUT:  PUSH PSW
        PUSH B
        PUSH D
        PUSH H
KO1:    DI
        CALL KBSVC
        LDA  KSTAT
        ANI  10H
        JNZ  KO2
        EI
        JMP  KO1
KO2:    POP  H
        POP  D
        POP  B
        POP  PSW
        OUT  KB_DATA
        EI
        RET

        INCLUDE "ch376.asm"
        INCLUDE "basic.asm"
        INCLUDE "monitor.asm"

        END
