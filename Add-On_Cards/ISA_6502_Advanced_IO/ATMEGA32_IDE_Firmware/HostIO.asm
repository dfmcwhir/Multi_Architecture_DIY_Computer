;
; File contains routines to interface the SBC-3 computer 
;
;*****************************************************************************
;* 					   SPI I/O Support routines		   				 	     *
;*****************************************************************************
;
; send char to SPI Host
;
cout:
		sbrc	status, 6			; data ready 
		rjmp	cout				; wait until host ready to rcv data
		mov		dout, i				; move data to SPI controller
		sbr		status, 0x40		; data ready
		ret

;
; Get char from SPI Host
;
cin:
		sbrs	status, 5			; slave data rx
		rjmp	cin					; wait for slave to be ready
		mov		i, din				; slave ready
		cbr		status, 0x20		; 
		ret

;******************************************************************************
; SPI Routines (ATmega32: SPCR, SPSR, SPDR - the 324P calls them SPCR0 ...)
; 
;******************************************************************************

; see hostdefs.inc for register assignments

SPIInit:						; Initialize SPI interface
	sbi		ddrb, 6				; Set MISO as output
	ldi		i, 0x40				;
	out		SPCR, i				; enable spi, slave mode
	in		i, SPSR				;
	in		i, SPDR				; clr status reg
	ldi		i, 0xC0				;
	out		SPCR, i				; enable spi interrupt
	ldi		i, 0x00
	mov		status, i			; init status, state, and response
	mov		state, i
	mov		dout,  i
	ret

;
; SPI Slave Controller code v1.0
; Written by Daryl Rictor  (c) 2009
;
SPI_STC:						; IRQ handler
SPI_RX:
	cli	
	push  	i					; save reg
	in		i, sreg
	push	i

	tst		state
	brne	SPI_RX3	
	in		i, SPDR				; get byte
	cpi		i, 0x02				; STATUS
	brne	SPI_RX1
	out		SPDR, status		; send status reg
	rjmp	SPI_RX_DONE
SPI_RX1:
	cpi		i, 0x03				; get Data
	brne	SPI_RX2
	out		SPDR, dout			; send data out
	cbr		status, 0x40		; clr flag in status

SPI_RX5:
	clr		i
SPI_RX2:
	mov		state, i			; save state
SPI_RX_DONE:
	pop		i
	out		sreg, i
	pop		i
	reti	

SPI_RX3:
	in		din, SPDR			; data received
	sbr		status, 0x20
	rjmp	SPI_RX5
