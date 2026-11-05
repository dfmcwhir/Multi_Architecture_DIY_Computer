;
;  ATA Support Routines
;  Current support is for LBA addressing on Hard drives and CF media

.include "atadefs.inc"
.include "ataconfig.inc"

;*****************************************************************************
; Uses: i, j, k, Z
; Gives a software reset into the ata drive
;*****************************************************************************
ataInit:
		ldi		i, 0x00					;							;
		out		DDR_DATAL, i			; Use DATAL as the input from the hardrive
		out		DDR_DATAH, i			; Use DATAH as the input from the hardrive
		ldi		i, 0xFF					;
		out		PORT_DATAL, i			; Enable pullup on DATAL
		out		PORT_DATAH, i			; Enable pullup on DATAH
						
		ldi		i, 0xFF
		out		DDR_ADDR, i				; IDE Address bus to outputs

		ldi		i, IDE_RES+IDE_WR+IDE_RD+IDE_CS2+IDE_CS1 ; 
    	out		PORT_ADDR, i        	; Initialize PORT_ADDR

		ldi     ZL, 0x00
		ldi		ZH, 0x14
		call	delay					; wait for ADDR port to stabilize (512uS min)
	
		cbi		PORT_IDE_RES,PIN_IDE_RES ; Assert /RESET
		ldi     ZL, 0x00
		ldi		ZH, 0x02
		call	delay					; wait in reset (512 uSec)

  		sbi		PORT_IDE_RES,PIN_IDE_RES ; Negate /RESET

		ldi		j, ATA_REG_ACTSTATUS
		ldi		i, 0x06
    	call	ataWriteByte			; Assert Software reboot.

		ldi     ZL, 0x64
		ldi		ZH, 0x00
		call	delay					; wait 100 uSec

		ldi		j, ATA_REG_ACTSTATUS
		ldi		i, 0x02
		call	ataWriteByte			; leave IRQ disabled

		ldi     ZL, 0x64
		ldi		ZH, 0x00
		call	delay					; wait 100 us

; Create a timeout interrupt to prevent lockup during media detection

    	ldi	 	i, high(65536 - 2 * F_CPU / 1024)	; counter init (counts up to FFFF)
		STORE	TCNT1H, i				; 2 second delay
		ldi	 	i, 0x00
		STORE 	TCNT1L, i
  		ldi	 	i, 1 << TOIE1			; 
		STORE 	TIMSK1, i				;  set INT for T1 overflow
		SEI								; enable interrupt
		ldi	 	i, 0x05
		STORE 	TCCR1B, i				; set clock to internal,prescaler = 1024

; Wait until drive clears BUSY Bit in Alternate Status Register
ataInit_1:
		ldi		k, ATA_SR_BSY
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte	
		and		i, k
		brne	ataInit_1		
		call	ataDriveSelect			; select drive (0 or 1)

; wait for Drive to be ready
ataInit_2:
		ldi		k, ATA_SR_DRDY
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte	
		and		i, k
		breq	ataInit_2		

; issue identify command
		ldi		i, ATA_CMD_IDENTIFY
		ldi		j, ATA_REG_CMDSTATUS1
		call	ataWriteByte

; wait for drive to request data transfer
ataInit_3:
		ldi		k, ATA_SR_DRQ
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte	
		and		i, k
		breq	ataInit_3		

; stop timeout timer here, communication with media successful

		CLI								; disable INT's
  		ldi		i, 0x00
		STORE	TIMSK1, i				; turn off T1 INTS
		STORE	TCCR1B, i				; stop T1
		SEI								; enable SPI

		ldi		ZL, 0xC8
		ldi		ZH, 0x00
		call	delay					; wait 200 us
		
		ldi		XL,	LOW(ata_buffer1)
		ldi		XH,	HIGH(ata_buffer1)
		ldi		YL, 0x00
		ldi		YH,	0x02				; 512 bytes
		call	ataReadDataBuffer

; test for LBA compatibility
		ldi		i, 0x00
		LDS		j, ata_buffer1+ATA_IDENT_LBASUPPORT*2+1
		andi	j, 0x02
		breq	ataError
		LDS		j, ata_buffer1+ATA_IDENT_FIELDVALID*2
		andi	j, 0x01
		breq	ataError
ataInit_5:
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)
		sts		ata_sectors, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+1
		sts		ata_sectors+1, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+2
		sts		ata_sectors+2, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+3
		sts		ata_sectors+3, i

; add code to limit sectors to 3D2780 for max FAT16 partition  v2.1 fix
		tst		i
		brne		ataInit_58
		lds		i, ata_sectors+2
		ldi		j, 0x3D		 
		cp		j, i
		brcs	ataInit_58
		brne	ataInit_6
		lds		i, ata_sectors+1
		ldi		j, 0x27
		cp		j, i
		brcs	ataInit_58
		brne	ataInit_6
		lds		i, ata_sectors
		ldi		j, 0x80
		cp		j, i
		brcc		ataInit_6
ataInit_58:
		ldi		i, 0x00
		sts		ata_sectors+3, i
		ldi		i, 0x3D
		sts		ata_sectors+2, i
		ldi		i, 0x27
		sts		ata_sectors+1, i
		ldi		i, 0x80
		sts		ata_sectors, i
ataInit_6:
		ldi		i, 0xFF
		STS		ata_cache1, i       	; set sector in cache to non-zero
		STS		ata_cache2, i       	; set sector in cache to non-zero
		ldi		i, 0x00
		ret						

ATAError:
		ldi		i, 0x01					; error - drive not LBA compatible
		ret

; Execute this code if media communication fails

TIM1_OVF:
		CLI								; stop INT's
  		ldi		i, 0x00
		STORE	TIMSK1, i				; disable T1 INT's
		STORE	TCCR1B, i				; turn off T1
		ldi		i, low(RAMEND-2)		; 
	    ldi		j, high(RAMEND-2)		; Set stack to return from the AtaInit call
    	out		SPH, j					; 
	    out		SPL, i					; 

;*****************************************************************************
; Uses i,X,Y
; the Buffer will be filled with the read data
;*****************************************************************************
ataReadDataBuffer:

		ldi 	i, 0x00
		out		DDR_DATAL, i	      	; Use the PORT DATAH as an input
		out		DDR_DATAH, i	      	; Use the PORT DATAL as an input
		ldi		i, 0xFF
		out		PORT_DATAL, i			; enable pull-ups
		out		PORT_DATAH, i			; enable pull-ups
		in		i, Port_ADDR
		andi	i, 0xE0					; Clear the lower 5 bits of the address line
		ori		i, ATA_REG_DATA			; enable address bus
		out		Port_ADDR, i
		push	XL
		push	XH
		push	YL
		push	YH
ataReadDataBuffer_1:
		nop
		nop
		cbi		PORT_IDE_RD, PIN_IDE_RD
		nop
		nop
		in		i, PIN_DATAL
		st		X+, i
		in		i, PIN_DATAH
		st		X+, i
		sbi		PORT_IDE_RD, PIN_IDE_RD
		sbiw	YL, 0x02	
		brne	ataReadDataBuffer_1		
		pop		YH
		pop		YL
		pop		XH
		pop		XL
		RET


;*****************************************************************************
; Uses i, X, Y 
; The entire Buffer will be pulled out to the ata dispositive
;*****************************************************************************
ataWriteDataBuffer:

		ldi 	i, 0xFF
		out		DDR_DATAL, i	      	; Use the PORT DATAH as an input
		out		DDR_DATAH, i	      	; Use the PORT DATAL as an input
		ldi		i, ATA_REG_DATA	 		; Assert the address Line
		out		Port_ADDR, i
		push	XL
		push	XH
		push	YL
		push	YH

ataWriteDataBuffer_1:

		ld		i, X+
		out		PORT_DATAL, i
		ld		i, X+
		out		PORT_DATAH, i
		nop 
		cbi		PORT_IDE_WR, PIN_IDE_WR
		nop
		nop
		sbi		PORT_IDE_WR, PIN_IDE_WR
		sbiw	YL, 0x02	
		brne	ataWriteDataBuffer_1		
		pop		YH
		pop		YL
		pop		XH
		pop		XL
		RET

;*****************************************************************************
; Uses i,j,k,R0-R3,X,Y
; Read one Sector (512 Bytes) from the ata dispositive using LBA
;*****************************************************************************
ataReadSectors:
		tst		i					; 0 = ata_buffer1, 1=ata_buffer2
		breq	ataReadSectors_1
; working from buffer2
		lds		j, ata_cache2
		cp		j, lba
		brne	ataReadSectors_0
		lds		j, ata_cache2+1
		cp		j, lba1
		brne	ataReadSectors_0
		lds		j, ata_cache2+2
		cp		j, lba2
		brne	ataReadSectors_0
		lds		j, ata_cache2+3
		cp		j, lba3
		brne	ataReadSectors_0
		ldi		i, 0x00		; no errors
		ret					; sector already loaded	

ataReadSectors_0:
; save new cached cache buffer number
		STS		ata_cache2, lba					
		STS		ata_cache2+1, lba1					
		STS		ata_cache2+2, lba2					
		STS		ata_cache2+3, lba3					
		ldi		XL,	LOW(ata_buffer2)
		ldi		XH,	HIGH(ata_buffer2)
		jmp		ataReadSectors_3

ataReadSectors_1:
; working from buffer1
		lds		j, ata_cache1
		cp		j, lba
		brne	ataReadSectors_2
		lds		j, ata_cache1+1
		cp		j, lba1
		brne	ataReadSectors_2
		lds		j, ata_cache1+2
		cp		j, lba2
		brne	ataReadSectors_2
		lds		j, ata_cache1+3
		cp		j, lba3
		brne	ataReadSectors_2
		ldi		i, 0x00		; no errors
		ret					; sector already loaded	

ataReadSectors_2: 
; save new cached sector number
		STS		ata_cache1, lba					
		STS		ata_cache1+1, lba1					
		STS		ata_cache1+2, lba2					
		STS		ata_cache1+3, lba3	
		ldi		XL,	LOW(ata_buffer1)
		ldi		XH,	HIGH(ata_buffer1)

ataReadSectors_3: ; called from DumpDriveInfo below
; Prepare parameters...
		mov		i, lba3
		andi	i, 0x0F
		ori		i, ATA_HEAD_USE_LBA		; LBA mode enabled
		lds		j, ata_drive
		tst		j
		breq	ataReadSectors_4
		ori		i, DRIVE1
ataReadSectors_4:
		ldi		j, ATA_REG_HDDEVSEL		; set drive, LBA mode, and 
		call	ataWriteByte			; upper LBA address bits 

		ldi		j, ATA_REG_CYLHI
		mov		i, lba2
		call	ataWriteByte
		ldi		j, ATA_REG_CYLLO
		mov		i, lba1
		call	ataWriteByte
		ldi		j, ATA_REG_STARTSEC
		mov		i, lba
		call	ataWriteByte
		ldi		j, ATA_REG_SECCOUNT
		ldi		i, 0x01                 ; 1 sector
		call	ataWriteByte

; Issue read sector command
		ldi		j, ATA_REG_CMDSTATUS1
		ldi		i, ATA_CMD_READ
		call	ataWriteByte

; Wait for drive to be ready
ataReadSectors_45:
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte			;
		mov		j,	i				; save data for error check below
		andi	j, ATA_SR_BSY
		brne 	ataReadSectors_45

; Check for errors
		andi	i, ATA_SR_ERR
		breq	ataReadSectors_5
		ret							; return with error in i

; Wait for drive to request data transfer
ataReadSectors_5:  	
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte			;
		andi	i, ATA_SR_DRQ
		breq 	ataReadSectors_5

; read data from drive
		ldi		YL, 0x00
		ldi		YH,	0x02						; 512 bytes
		call	ataReadDataBuffer

; Return the error bit from the status register...
		ldi		i, 	ATA_REG_CMDSTATUS1
		call	ataReadByte						; read status register
		andi	i, ATA_SR_ERR
		breq	ataReadSectors_6
		ldi		i, 0x01                         ; error 1
ataReadSectors_6:
		ret


;*****************************************************************************
; Uses: R0-R3, i,j,k,X,Y
; Write one Sector (512 Bytes) to the ata dispositive using LBA
;*****************************************************************************
ataWriteSectors:

		tst		i                       ; 0=buffer1, else buffer2
		breq	ataWriteSectors02	

		ldi		XL,	LOW(ata_buffer2)
		ldi		XH,	HIGH(ata_buffer2)
		rjmp 	ataWriteSectors05

ataWriteSectors02:
		ldi		XL,	LOW(ata_buffer1)
		ldi		XH,	HIGH(ata_buffer1)

; Wait for drive to be ready
ataWriteSectors05:
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte			;
		andi	i, ATA_SR_BSY
		brne 	ataWriteSectors05		; wait for ready status

; Prepare parameters...
		mov		i, lba3
		andi	i, 0x0F
		ori		i, ATA_HEAD_USE_LBA		; LBA mode enabled
		lds		j, ata_drive
		tst		j                       ; if drive=0
		breq	ataWriteSectors_1       
		ori		i, DRIVE1               ; else drive =1
ataWriteSectors_1:
		ldi		j, ATA_REG_HDDEVSEL		; set drive, LBA mode, and 
		call	ataWriteByte			; upper LBA address bits 
		ldi		j, ATA_REG_CYLHI
		mov		i, lba2
		call	ataWriteByte
		ldi		j, ATA_REG_CYLLO
		mov		i, lba1
		call	ataWriteByte
		ldi		j, ATA_REG_STARTSEC
		mov		i, lba
		call	ataWriteByte

		ldi		j, ATA_REG_SECCOUNT
		ldi		i, 0x01                 ; get 1 sector
		call	ataWriteByte

; Issue write sector command
		ldi		j, ATA_REG_CMDSTATUS1
		ldi		i, ATA_CMD_WRITE
		call	ataWriteByte
  	
; Wait for drive to request data transfer
ataWriteSectors_15:
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte			;
		andi	i, ATA_SR_DRQ
		breq 	ataWriteSectors_15		; wait for ready status

; write data to drive
		ldi		YL, 0x00
		ldi		YH,	0x02						; 512 bytes
		call	ataWriteDataBuffer

; Wait for drive to finish write
ataWriteSectors_17:
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte			;
		mov		j,	i					; save data for error bit test below
		andi	j, ATA_SR_BSY
		brne 	ataWriteSectors_17		; wait for ready status

; Return the error bit from the status register...
		andi	i, ATA_SR_ERR
		breq	ataWriteSectors_2
		ldi		i, 0x01                         ; error 1
ataWriteSectors_2:
		ret


;*****************************************************************************
; Uses i, j 
; Read one Byte from the ata dispositive
;*****************************************************************************
ataReadByte:

		ldi		j, 0xff
		out		PORT_DATAL, j			    ; enable pull-ups
		ldi		j, 0x00
		out		DDR_DATAL, j  	      	    ; Use the DATAH as an input
		out		PORT_ADDR, i				; assert Address
  		cbi		PORT_IDE_RD, PIN_IDE_RD    	; Assert DIOR
		nop                                 ; pause to 
		nop                                 ; allow data to stablize
		in		i, PIN_DATAL				; read low byte
  		sbi		PORT_IDE_RD, PIN_IDE_RD    	; Negate DIOR
		ret

;*****************************************************************************
; Uses i, j, k 
; write one Byte to the ata dispositive
;*****************************************************************************
ataWriteByte:

		ldi		k, 0xFF
		out		DDR_DATAL, k			   	; Use DATAL an an output
		out		PORT_ADDR, j				; assert Address
  		out		PORT_DATAL , i				; Output the data
		nop                                 ; wait
  		cbi		PORT_IDE_WR,PIN_IDE_WR		; Assert DIOW
		nop                                 ;
		nop                                 ; pause for wr pule width
  		sbi		PORT_IDE_WR,PIN_IDE_WR		; Negate DIOW
		ret

;*****************************************************************************
; Uses i, j, k
; Change the drive, Master or Slave
;*****************************************************************************
ataDriveSelect:
		lds		i, ata_drive
		tst		i
		breq	ataDriveSelect_1
		ldi		i, DRIVE1
ataDriveSelect_1:
		ori		i, 0xE0                 ; form set drive data byte 111d0000
		ldi		j, ATA_REG_HDDEVSEL
		call	ataWriteByte			; Drive selection
		ret

;*****************************************************************************
; Uses Z reg to count usecs and i for loop cntr
; delay for a minimum of <us> microseconds
;*****************************************************************************
delay:

		ldi		i, CYCLES_PER_US>>2			; 1
delay_1:
		nop									; 1
		subi	i, 0x01						; 1
		brne	delay_1						; 1/2
		sbiw	ZL, 0x01						;
		brne	delay
		ret	

;*****************************************************************************
; print Drive info
;*****************************************************************************
dumpDriveInfo:

		call	fatFFlush						; save buffer contents

; Wait for drive to be ready
dumpDriveInfo05:
		ldi		k, ATA_SR_DRDY
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte	
		and		i, k
		breq 	dumpDriveInfo05			; wait for ready status

		ldi		i, ATA_CMD_IDENTIFY
		ldi		j, ATA_REG_CMDSTATUS1
		call	ataWriteByte

; wait for drive to request data transfer
dumpDriveInfo1:
		ldi		k, ATA_SR_DRQ
		ldi		i, ATA_REG_ACTSTATUS
		call	ataReadByte	
		and		i, k
		breq	dumpDriveInfo1
		ldi		ZH, 0x00
		ldi		ZL, 0xC8
		call	delay		; wait 200 us
		
		ldi		XL,	LOW(ata_buffer1)
		ldi		XH,	HIGH(ata_buffer1)
		ldi		YL, 0x00
		ldi		YH,	0x02						; 512 bytes
		call	ataReadDataBuffer

		ldi		ZL, low(drivetxt*2)				; print Drive:_
		ldi		ZH, high(drivetxt*2)	
		call	cstrout
		lds		i, ata_Drive
		ori		i, 0x30
		call	cout							; print 0 or 1
		ldi		i, 0x20
		call	cout							; print _
	; get sector count * 512 then print millions
		ldi		i, 0x00
		mov		r0, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)
		mov		r1, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+1		
		mov		r2, i
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+2			
		mov		r3, i
		lsl		r1
		rol		r2
		rol		r3
		push	ZL
		push	ZH
		ldi		l, 0x05						; stop at million value
		call	decoutalt					; print decimal value of drive capacity
		pop		ZH
		pop		ZL
		call	cstrout							; print MB Model:_
		ldi		XL, low(ata_buffer1+(ATA_IDENT_MODEL*2))
		ldi		XH, high(ata_buffer1+(ATA_IDENT_MODEL*2))
		ldi		k, 0x14
	dumpDrive_1:
		ld		l,	X+
		ld		i,	X+
		call	cout
		mov		i, l
		call	cout
		dec		k
		brne	dumpDrive_1						; print "Model name of Drive"
		call	cstrout							; print CR/LF Total Sectors:
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+3
		call	hexout
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+2
		call	hexout
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)+1		
		call	hexout
		lds		i, ata_buffer1+(ATA_IDENT_LBASECTORS*2)			
		call	hexout
;		call	crlfout							; print CR/LF 

		lds		lba, ata_cache1
		lds		lba1, ata_cache1+1
		lds		lba2, ata_cache1+2
		lds		lba3, ata_cache1+3
		ldi		XL,	LOW(ata_buffer1)
		ldi		XH,	HIGH(ata_buffer1)
		ldi		i, 0x00
		call	ataReadSectors_3                ; reload buffer contents
		ret
.CSEG
drivetxt:
		.db "FW2.1 Drive:", 0x00,"MB Model:", 0x00, 0x0d, 0x0a, "Total Sectors:", 0x00

