;*****************************************************************************
; 
; AVR FAT16 driver for directly connected Compact Flash or ATA hard disk 
;
; Designed for the ATMega324P
; This version: the ATmega32 (or ATmega32A) at 16 MHz - see "ATmega32 port"
; below.  The other files are the same as v2.1, except defs.inc (F_CPU) and
; ata.asm (the 2 second time-out worked out from F_CPU).
;
; By Daryl Rictor, (c)2008-2009
;
; v2.1  Feb 16, 2013
;
; Inspired and adapted from Angelo Bannack and Giordano Bruno Wolaniuk's
; FAT 16/32 File System Driver for Atmel AVR 
; From Circuit Cellar Magazine's AVR 2004 Design Contest
;
; Use SPI port for SBC-3 host interface 
;
; /////////////////////////////////////////////////////////////////////////////////
;//                                                                               //
;//  This program and its associated documentation are provided for your personal //
;//  use only and appear here exclusively by permission of the copyright holder.  //
;//  Please contact the copyright holder before re-distributing, re-publishing    //
;//  or disseminating this copyrighted work. This code is not GPL or in the       //
;//  public domain. Please respect the author"s copyright.                        //
;//                                                                               //
;//  No waranty, either expressed or implied, are given.  I assume no liability   //
;//  for its use in any project or device.                                        //
;//                                                                               //
;//  Your use of this program indicates your acceptance of all license terms.     //
;//  This particular version is freeware as long as the copyright messages are    //
;//  left intact.                                                                 //
;//                                                                               //
; /////////////////////////////////////////////////////////////////////////////////


; *** Fuse Bits (ATmega32) ***
; JTAGEN unprogrammed (port C pins 2-5 are needed, not JTAG; the code also
; turns JTAG off at start with the JTD bit, in case).  CKOPT programmed and
; CKSEL3..0 = 1111, SUT1..0 = 11: an external 16 MHz crystal, full swing.
; (The ATmega32 has no CLKDIV8 fuse.)  avrdude:  -U lfuse:w:0xFF:m
; -U hfuse:w:0xC9:m   (hfuse C9: JTAGEN, OCDEN off, SPIEN on, CKOPT on,
; EESAVE off, BOOTSZ 00, BOOTRST off).  Read your chip's fuses first.
;

;*****************************************************************************

.include "macros.inc"		; IO address mode macros
.include "m32def.inc"
.include "defs.inc"		; Definitions

;*****************************************************************************
; ATmega32 port
;
; The ATmega32 is the chip this program was first written for (v1.0-1.2); v1.3
; moved it to the ATmega324P.  The differences that matter here:
;  - The interrupt table: 21 vectors, in a different order (below).
;  - The 324P's SPI and timer registers have a 0 or 1 on their names (SPCR0,
;    TIMSK1); the ATmega32's don't.  They are the same registers, with the
;    same bits.  HostIO.asm uses the ATmega32's names (SPDR0 can't be kept:
;    on the ATmega32 it is the name of a bit, = 0); TIMSK1 is defined below.
;  - 16 MHz at most (the 324P runs at 20): F_CPU in defs.inc.  The delays are
;    worked out from it.  The host's SPI clock must stay under F_CPU / 4.
;  - JTAG is on port C, as on the 324P: turned off at start (cpuInit).
; Pins: the same 40-pin DIP layout, the same ports, so the board is the same
; (with a 16 MHz crystal).
;*****************************************************************************
.equ	TIMSK1	= TIMSK			; (TOIE1 is bit 2 of TIMSK)

;*****************************************************************************
; Reset/Interrupt jump table (ATmega32)
;*****************************************************************************
.org 0
		jmp RESET 		; Reset Handler
.org INT0addr
		jmp EXT_INT0 	; IRQ0
.org INT1addr
		jmp EXT_INT1 	; IRQ1
.org INT2addr
		jmp EXT_INT2 	; IRQ2
.org OC2addr
		jmp TIM2_COMPA 	; Timer2 Compare
.org OVF2addr
		jmp TIM2_OVF 	; Timer2 Overflow
.org ICP1addr
		jmp TIM1_CAPT 	; Timer1 Capture
.org OC1Aaddr
		jmp TIM1_COMPA 	; Timer1 Compare A
.org OC1Baddr
		jmp TIM1_COMPB 	; Timer1 Compare B
.org OVF1addr
		jmp TIM1_OVF 	; Timer1 Overflow (the ATA time-out: ata.asm)
.org OC0addr
		jmp TIM0_COMPA 	; Timer0 Compare
.org OVF0addr
		jmp TIM0_OVF 	; Timer0 Overflow
.org SPIaddr
		jmp SPI_STC 	; SPI Transfer Complete (the host: HostIO.asm)
.org URXCaddr
		jmp USART0_RX 	; USART RX Complete
.org UDREaddr
		jmp USART0_UDRE	; UDR Empty
.org UTXCaddr
		jmp USART0_TX 	; USART TX Complete
.org ADCCaddr
		jmp ADC_INT		; ADC Conversion Complete
.org ERDYaddr
		jmp EE_READY	; EEPROM Ready
.org ACIaddr
		jmp Analog_Comp ; Analog Comparator
.org TWIaddr
		jmp TWI 		; Two-wire Serial Interface
.org SPMRaddr
		jmp SPM_READY 	; Store Program Memory Ready
.org INT_VECTORS_SIZE

;*****************************************************************************
; unused interrupts point to Reset vector
;*****************************************************************************

EXT_INT0: 				; IRQ0 Handler
EXT_INT1: 				; IRQ1 Handler
EXT_INT2: 				; IRQ2 Handler
PC_INT0: 				; Pin Change int Handler
PC_INT1: 				; Pin Change int Handler
PC_INT2: 				; Pin Change int Handler
PC_INT3: 				; Pin Change int Handler
WDT:					; watch dog timer interrupt
TIM2_COMPA: 			; Timer2 CompareA Handler
TIM2_COMPB: 			; Timer2 CompareB Handler
TIM2_OVF: 				; Timer2 Overflow Handler
TIM1_CAPT: 				; Timer1 Capture Handler
TIM1_COMPA: 			; Timer1 CompareA Handler
TIM1_COMPB: 			; Timer1 CompareB Handler
;TIM1_OVF: 				; Timer1 Overflow Handler
; see ATA_Init code for TIM1_OVF handler
TIM0_COMPA: 			; Timer0 CompareA Handler
TIM0_COMPB: 			; Timer0 CompareB Handler
TIM0_OVF: 				; Timer0 Overflow Handler
;SPI_STC: 				; SPI Transfer Complete Handler
;See HostIO for SPI_STC handler
USART0_RX: 				; USART0 RX Complete Handler
USART0_UDRE:			; UDR0 Empty Handler
USART0_TX: 				; USART0 TX Complete Handler
Analog_Comp:			; Analog comparitor Handler
ADC_INT:				; ADC Conversion Complete Handler
EE_READY:				; EEPROM Ready Handler
TWI: 					; Two-wire Serial Interface Handler
SPM_READY: 				; Store Program Memory Ready Handler
USART1_RX: 				; USART1 RX Complete Handler
USART1_UDRE:			; UDR1 Empty Handler
USART1_TX: 				; USART1 TX Complete Handler

;*****************************************************************************
; Reset code 
;*****************************************************************************

RESET:									; Reset Handler
		cli								; disable interrupts	
		ldi		i, low(RAMEND)			; Init stack
	    ldi		j, high(RAMEND)			; top of RAM
    	out		SPH, j					; 
	    out		SPL, i					; 
		call	cpuInit					; set CPU parms
		call	SPIInit
		call	DS1302_init				; init RTC
		ldi		i, 0x00
		sts		ata_Drive, i			; set drive 0 
		call	ataInit					; init the ATA interface
		tst		i
		breq	main2					; ATA init successful
		ldi		i, 0x01
		sts		ata_drive, i			; select new drive #
Reset1:
		call	ataInit					; init the ATA interface
		tst		i
		breq	main2					; ATA init successful
Reset2:
		ldi		i, 0xff					; no ata drive flag
		sts		ata_Drive, i	
		ldi		i, 0x01
		SEI								; enable SPI
		jmp		Host					; go to menu

main2:
		call	fatInit					; init the FAT16 driver - returns '0' or 'E'
		SEI								; enable SPI
		jmp 	Host					; System initialized - start Host App


;*****************************************************************************
; initialize the CPU's internal resources
;*****************************************************************************
cpuInit:
		ldi		i,	0x80				; Analog Comparator initialization
		out		ACSR,	i				; Analog Comparator: Off
		in		i, MCUCSR			; JTAG off (port C pins 2-5 free): JTD,
		ori		i, 1<<JTD			;  written twice within 4 cycles
		out		MCUCSR, i
		out		MCUCSR, i
		ret
								
;*****************************************************************************
;
;  Input/Output support routines
;
;*****************************************************************************

;*****************************************************************************
; Uses: i (R16), j (R17) 
; print Carrriage return and line feed 
;*****************************************************************************
crlfout:
		ldi		i,	0x0d		; CR
		call	cout
		ldi		i,	0x0a		; LF
		call	cout
		ret

;*****************************************************************************
; Uses: i,j,k
; convert hex to packed decimal, print using hexout
;*****************************************************************************
hextodec:
		cpi		i,	0x63
		brmi	hextodec1
		ret							; do nothing if over 99
hextodec1:
		cpi		i,	0x0a
		brmi	hextodec3
		mov		j,	i
		ldi		k,	0x06
hextodec2:
		add		i,	k
		subi	j,	0x0a
		cpi		j,	0x0a
		brpl	hextodec2
hextodec3:

		; fall thru to hexout and print it
;*****************************************************************************
; Uses: i,j 
; print byte as two ASCII HEX characters
;*****************************************************************************
hexout:	push	i
		swap	i
		call	hex1	
		pop		i
hex1:	andi	i, 0x0f
		ori		i, 0x30
		cpi		i, 0x3A	
		brmi	hex2
		ldi		j, 0x07
		add		i, j
hex2:	jmp		cout

;*****************************************************************************
; Uses: i,j,Z 
; print null terminated string from RAM 
;*****************************************************************************
strout:	ld		i, Z+
		tst		i
		breq	str9
		call	cout
		rjmp	strout
str9:	ret

;*****************************************************************************
; Uses: i,j,Z 
; print null terminated string from program memory 
;*****************************************************************************
cstrout:
		lpm		i, Z+
		tst		i
		breq	cstr9
		call	cout
		jmp		cstrout
cstr9:	ret
;*****************************************************************************
; Uses: i,j,k, R0-R3 , R4-R7
; print decimal ASCII characters of hex value
;*****************************************************************************
decout:
		ldi		i, 0x00		
		tst		r0
		brne	decout0
		tst		r1
		brne	decout0
		tst		r2
		brne	decout0
		tst		r3
		breq	decout4
decout0:
		ldi		l, 0x0b	; 
decoutalt:
		ldi		i, 0x00
		ldi		k, 0xff
        ldi		ZL, low(decmode*2)
		ldi		ZH, high(decmode*2)
decout1:		
		lpm		R4, Z+
		lpm		R5, Z+
		lpm		R6, Z+
		lpm		R7, Z+
		dec		l
		brne	decout2
		ret
decout2:
		cp		r0, r4
		cpc		r1, r5
		cpc 	r2, r6
		cpc 	r3, r7
		brcc	decout3
		cpi		k, 0xff
		breq	decout1			; don't want leading zeros
		ori		i, 0x30			; convert count to ASCII
		call	cout
		ldi		i, 0x00			; reset counter
		jmp		decout1		
decout3:
		ldi		k, 0x00
		inc		i				; count digit
		sub		r0, r4
		sbc		r1, r5
		sbc 	r2, r6
		sbc 	r3, r7
		jmp		decout2
decout4:
		ori		i, 0x30			; convert count to ASCII
		call	cout
		ret

.CSEG
decmode:
		.db 0x00, 0xca, 0x9a, 0x3b		;  1,000,000,000
		.db 0x00, 0xe1, 0xf5, 0x05		;    100,000,000
		.db	0x80, 0x96, 0x98, 0x00		;     10,000,000
		.db 0x40, 0x42, 0x0f, 0x00		;      1,000,000
		.db	0xa0, 0x86, 0x01, 0x00		;        100,000
		.db 0x10, 0x27, 0x00, 0x00		;         10,000
		.db 0xe8, 0x03, 0x00, 0x00		;          1,000
		.db 0x64, 0x00, 0x00, 0x00		;            100
		.db 0x0a, 0x00, 0x00, 0x00		;             10
		.db	0x01, 0x00, 0x00, 0x00		;              1
		.db 0x00, 0x00, 0x00, 0x00   ; fixes input of  0.

;*****************************************************************************
; include support files
;*****************************************************************************
.include "HostIO.asm"
.include "ata.asm"
.include "fat.asm"
.include "host.asm"
.include "ds1302.asm"

;*****************************************************************************
; Version History
;*****************************************************************************
; 0.1 - Draft 
; 1.0 - First release
; 1.1 - Re written with SPI Slave Controller code
; 1.2 - a few bug fixes and optimizations
; 1.3 - Converted from Mega32 to Mega324P - increased clock to 20MHz
; 1.4 - fixed bug in the Host Get File Pointer command
; 1.5 - fixed bug in the FatFSeek routine - added SEEK_END mode
; 1.6 - another fix to the FatFSeek routine
; 1.7 - fixed "file open append" to properly point to the end of file
; 1.8 - Added init for "dessectorHasChanged" in FatInit - fixed lockup on DumpDriveInfo
;       also fixed delay timing for 20MHz clock vs. 16MHz
; 1.9 - Fixed Get RTC Register command to match the datasheet {e2}{dd} now works.
; 2.0 - Added status LED function to PB3 (Pin 4) - active low during IDE command
; 2.1 - Added 2GB limit on Partition 1's size to allow larger media to be mounted.
; 2.1-32 - Back on the ATmega32 (16 MHz): its interrupt table and register
;       names, JTAG off at start, the ATA time-out from F_CPU.
;       Requires a FV and MV to be performed before media can be used.