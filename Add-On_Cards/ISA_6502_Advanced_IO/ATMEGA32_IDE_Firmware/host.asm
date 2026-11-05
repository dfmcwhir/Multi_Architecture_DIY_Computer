;
; Host Interface
;
.include  "hostdefs.inc"

;*********************
; return/error codes
;*********************
;
;00 = no error
;01 = ATA init error
;02 = missing file name
;03 = Format error
;04 = File not found
;05 = Read Only File
;06 = invalid file type/open error
;07 = unable to erase all files?
;08 = file not open
;09 = file already open in another handle
;0A = write protected
;0B = disk full
;0C = root directory full
;0D = invalid command
;0E = Handle in use
;0F = read past EOF
;10 = File too large > 2^32
;11 = Cluster size too big?


;*****************************************************************************
; Host Processor reads and processes user requests
;*****************************************************************************
Host:
	sbi		LEDddr, LEDpin	; set up LED driver pin as output
	rjmp	Host1			; set FAT init response
;
; ready to start doing file/disk operations
;
Host0:
	ldi		i, 0x00
Host1:
    andi	i, 0x1F
	andi	status, 0xE0
	or		status, i
Host3:
	sbi		LEDpt, LEDpin		; raise LED pin (inactive)
	sbr		status, 0x80
	call	cin				; wait for command chr
	cbr		status, 0x80

Host_Proc:
	ldi		ZL, low(CmdList*2)
	ldi		ZH, high(CmdList*2)

Host_Proc1:
	lpm		j,	Z+	
	cpi		j,	0x00
	brne	Host_Proc2
	ldi		i, 0x0D			; invalid command
	rjmp	Host1

Host_Proc2:
	cp		i,	j
	breq	Host_Proc3
	lpm		j,	Z+
	lpm		j,	Z+
	lpm		j,	Z+
	rjmp	Host_Proc1

Host_Proc3:
	lpm		i,	Z+
	lpm		j,	Z+	
	lpm		k,	Z+	
	cpi		k, 0x00			; unlimited command?
	breq	Host_Proc4
	lds		k, ata_Drive
	cpi		k, 0xff			; no ata flag
	brne	Host_Proc4
	ldi		i, 0x0D			; invalid command
	rjmp	Host1

Host_Proc4:
	cbi		LEDpt, LEDpin		; drop LED pin	
	movw	ZL,	i
	ijmp				; jump indirect to user routine

CmdList:
			.db		0xC0, low(HostFatFCA), high(HostFatFCA),1		; Close all
			.db		0xC1, low(HostFatLD), high(HostFatLD),1			; Return Directory listing	
			.db		0xC2, low(HostFatMD), high(HostFatMD),1			; Make Directory
			.db		0xC3, low(HostFatCD), high(HostFatCD),1			; Change Directory
			.db		0xC4, low(HostFatER), high(HostFatER),1			; Erase File or Dir
			.db		0xC5, low(HostFatEA), high(HostFatEA),1			; Erase all
			.db		0xC6, low(HostFatPR), high(HostFatPR),1			; protect file/dir
			.db		0xC7, low(HostFatUP), high(HostFatUP),1			; unprotect file/dir
			.db		0xC8, low(HostFatCN), high(HostFatCN),1			; Rename File or Dir
			.db		0xC9, low(HostFatFO), high(HostFatFO),1			; Open File
			.db		0xCA, low(HostFatRF), high(HostFatRF),1			; Read File
			.db		0xCB, low(HostFatWF), high(HostFatWF),1			; Write File
			.db		0xCC, low(HostFatSP), high(HostFatSP),1			; Set pointer
			.db		0xCD, low(HostFatGP), high(HostFatGP),1			; Get pointer
			.db		0xCE, low(HostFatFC), high(HostFatFC),1			; Close File
			.db		0xCF, low(HostFatFT), high(HostFatFT),1			; Test File
			.db		0xD0, low(HostFatFS), high(HostFatFS),1			; File Size
			.db		0xD1, low(HostDirRS), high(HostDirRS),1			; Read sector
			.db		0xD2, low(HostDirWS), high(HostDirWS),1			; Write sector
			.db		0xE0, low(HostGetCal), high(HostGetCal),0		; Get Calendar
			.db		0xE1, low(HostSetCal), high(HostSetCal),0		; Set calendar
			.db		0xE2, low(HostGetCalX), high(HostGetCalX),0		; Get RTC register direct
			.db		0xF0, low(HostFatVL), high(HostFatVL),1			; Return Volume Name	
			.db		0xF1, low(HostFatFree), high(HostFatFree),1		; return free clusters
			.db		0xF2, low(HostFatDF), high(HostFatDF),1			; Format CF
			.db		0xF3, low(HostDriveInfo), high(HostDriveInfo),1	; return drive info
			.db		0xF4, low(HostInitFS),  high(HostInitFS), 0		; Device reset (soft)  
			.db		0x00, 0x00 

;*************************************
; Change Directory
;*************************************
HostFatCD:
	call	HostGetFN
	brcc	HostFatCD0
	call	fatCDdir
HostFatCD0:
	rjmp	Host1				

;*************************************
; Make Directory
;*************************************
HostFatMD:
	call	HostGetFN
	brcc	HostFatMD1
	call	fatMkdir
HostFatMD1:
	rjmp	Host1

;*************************************
; Open File
;*************************************
HostFatFO:
	call	HostGetFH
	sts		Handle,  i
	push	j					; save mode for later
	call	HostLoadFH
	lds		i,  desDirEntSector
	tst		i
	brne	HostFatFO1	
	lds		i,  desDirEntSector+1
	tst		i
	brne	HostFatFO1	
	lds		i,  desDirEntSector+2
	tst		i
	brne	HostFatFO1	
	lds		i,  desDirEntSector+3
	tst		i
	breq	HostFatFO15

HostFatFO1:
	call	HostgetFN			; expected data, not used
	pop		i					; clean stack
	ldi		i,  0x0E
	jmp		Host1				; handle in use

HostFatFO15:
	pop		j					; get mode
	sts		desFileMode, j		; file mode  - from HostGetFH above
	call	HostGetFN
	brcc	HostFatFO9
	call	FatGetFileInfo
	tst		i					; if not found, don't try to find in handle table
	breq	HostFatFO16
    lds     i, desAttrib
	andi	i, ATTR_DIRECTORY+ATTR_VOLUME			; mask VOL/DIR bits
    cpi		i, ATTR_VOLUME				; is it volume label?
	breq	HostFatFO26
	cpi		i, ATTR_DIRECTORY				; is it a directory?
	breq	HostFatFO26
	call	HostSrchFH			; see if already open in another handle
	cpi		i,  0xFF
	breq	HostFatFO16
	ldi		i,  0x09			; file opened in another handle

HostFatFO9:
	jmp		Host1	

HostFatFO16:
	lds		i,  desName
	lds		j,  desFileMode
	cpi		j,  0x01
	breq	HostFatFO2			; read need to have existing file
	cpi		i, 0x00
	breq	HostFatFO17			; if not existing file, don't test for read only
    lds     k, desAttrib
	andi	k,  ATTR_READONLY
    breq    HostFatFO17
    ldi		i, 0x0A				; write protected
	jmp		Host1

HostFatFO17:
	cpi		j,  0x02
	breq	HostFatFO3			; if file exists, erase first, then write new
	cpi		j,  0x03
	breq	HostFatFO4			; add to file or create new
	ldi		i,  0x0D
	jmp		Host1				; invalid command

HostFatFO2:						; Read Mode
	tst		i
	brne	HostFatFO25
	ldi		i,  0x04			; file not found		
	jmp		Host1	

HostFatFO25:						; read - file found
	call	fatFOpen
	tst		i
	brne	HostFatFO27

HostFatFO26:
	ldi		i,  0x06			; invalid file type
	jmp		Host1

HostFatFO27:
	lds		i,  Handle
	call	HostSaveFH
	jmp		Host0				; completed successfully

HostFatFO3:						; Write Mode
	tst		i
	breq	HostFatFO33			
	call	fatRemove			; erase file before writing
	
HostFatFO33:						; new file
	call	fatFCreate	
	tst		i
	brne	HostFatFO37
	ldi		i,  0x06			; invalid file type
	jmp		Host1

HostFatFO37:
	lds		i,  Handle
	call	HostSaveFH
	jmp		Host0				; completed successfully

HostFatFO4:						; append
	tst		i	
	brne	HostFatFO41
	call	fatFCreate			; file not found - create a new one
	tst		i
	brne	HostFatFO45
	ldi		i,  0x06			; invalid file type/ open error
	jmp		Host1

HostFatFO41:						; file exists
	call	fatFOpen
	tst		i
	brne	HostFatFO42
	ldi		i,  0x06			; invalid file type/ open error
	jmp		Host1
	
HostFatFO42:						; opened existing file
	lds		i, desFileSize		; move pointer to end of file
	sts		desBytePointer, i
	lds		i, desFileSize+1
	sts		desBytePointer+1, i
	lds		i, desFileSize+2
	sts		desBytePointer+2, i
	lds		i, desFileSize+3
	sts		desBytePointer+3, i

	lds		R0,	desBytePointer		; move file pointer
	lds		R1,	desBytePointer+1
	lds		R2,	desBytePointer+2
	lds		R3,	desBytePointer+3
	ldi		i, 0x02				; seek set
	call	fatFseek

HostFatFO45:
	lds		i,  Handle
	call	HostSaveFH
	jmp		Host0				; completed successfully

;*************************************
; Close All Files
;*************************************
HostFatFCA:
	ldi		i, 0x0F
HostFatFCA1:
	push	i
	call	HostFatFCA0
	pop		i
	dec		i
	cpi		i, 0xFF
	brne	HostFatFCA1	
	jmp		Host0				; done

;*************************************
; Close File
;*************************************
HostFatFC:
	call	HostFatFC0
	jmp		Host1				; 

HostFatFC0:
	call	HostGetFH
HostFatFCA0: 						; called from Close All
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatFC1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatFC1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatFC1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatFC1
	ldi		i,	0x08			; file not opened
	ret	

HostFatFC1:
	lds		i, desFileMode
	cpi		i,	0x01
	breq	HostFatFC5			; if read mode, just reset handle
	call	fatLoadFileInfo
	call	fatFClose			; update file date

HostFatFC5:
	ldi		i,	0x00
	sts		desDirEntSector, i
	sts		desDirEntSector+1, i
	sts		desDirEntSector+2, i
	sts		desDirEntSector+3, i
	lds		i,	Handle
	call	HostSaveFH
	ldi		i,	0x00			; no errors
	ret

;*************************************
; Test File
;*************************************
HostFatFT:
	call		HostGetFN
	brcc		HostFatFT5
	call		FatGetFileInfo
	tst		i					
	breq		HostFatFT1			; file not found
	lds		i, desAttrib
	andi		i,ATTR_VOLUME+ATTR_DIRECTORY
	cpi		i, ATTR_VOLUME				; is it volume label?
	breq		HostFatFT3
	cpi		i, ATTR_DIRECTORY				; is it a directory?
	breq		HostFatFT3
	lds		i, desAttrib
	andi		i,ATTR_READONLY
	brne		HostFatFT4			
	jmp		Host0				; good file found
HostFatFT1:
	ldi		i,  0x04			; file not found		
	jmp		Host1	
HostFatFt3:
	ldi		i,  0x06			; invalid file type	
	jmp		Host1
HostFatFt4:
	ldi		i,  0x0A			; write protected	
HostFatFT5:
	jmp		Host1

;*************************************
; Read File
;*************************************
HostFatRF:
	call	HostGetFH
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatRF1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatRF1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatRF1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatRF1
	call	HostGetBCnt				; for host sync only
	lds		i,	byteCount
	tst		i
	brne	HostFatRF0
	lds		i,	byteCount+1
	tst		i
	brne	HostFatRF0
	lds		i,	byteCount+2
	tst		i
	brne	HostFatRF0
	lds		i,	byteCount+3
	tst		i
	brne	HostFatRF0
	ldi		i,	0x08
	jmp		Host1				; file not open
HostFatRF0:
	call	HostFatRFFlush		; flush reads
	ldi		i,	0x08
	jmp		Host1				; file not open

HostFatRF1:
	call	fatLoadFileInfo
	call	HostGetBCnt

HostFatRF15:
	lds		i,	byteCount
	tst		i
	brne	HostFatRF2
	lds		i,	byteCount+1
	tst		i
	brne	HostFatRF2
	lds		i,	byteCount+2
	tst		i
	brne	HostFatRF2
	lds		i,	byteCount+3
	tst		i
	brne	HostFatRF2
	lds		i,	Handle
	call	HostSaveFH
	jmp		Host0			;done without errors
	
HostFatRF2:
	call	fatFgetc
	cpi		j,	0xff		; eof marker
	breq	HostFatRF3		; eof reached
	call	cout			; send byte to host	
	lds		i,	byteCount
	ldi		j,	0x01
	sub		i,	j
	sts		ByteCount, i
	lds		i,	byteCount+1
	ldi		j,	0x00
	sbc		i,	j
	sts		ByteCount+1, i
	lds		i,	byteCount+2
	sbc		i,	j
	sts		ByteCount+2, i
	lds		i,	byteCount+3
	sbc		i,	j
	sts		ByteCount+3, i
	rjmp	HostFatRF15

HostFatRF3:
	call	HostFatRFFlush
	lds		i,	Handle
	call	HostSaveFH
	ldi		i,	0x0F
	jmp		Host1			; read past eof

HostFatRFFlush:
HostFatRF4:
	ldi		i, 0x00
	call	cout
	lds		i,	byteCount
	ldi		j,	0x01
	sub		i,	j
	sts		ByteCount, i
	lds		i,	byteCount+1
	ldi		j,	0x00
	sbc		i,	j
	sts		ByteCount+1, i
	lds		i,	byteCount+2
	sbc		i,	j
	sts		ByteCount+2, i
	lds		i,	byteCount+3
	sbc		i,	j
	sts		ByteCount+3, i
	lds		i,	byteCount
	tst		i
	brne	HostFatRF4
	lds		i,	byteCount+1
	tst		i
	brne	HostFatRF4
	lds		i,	byteCount+2
	tst		i
	brne	HostFatRF4
	lds		i,	byteCount+3
	tst		i
	brne	HostFatRF4
	ret

;*************************************
; File Size
;*************************************
HostFatFS:
	call	HostGetFH
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatFS1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatFS1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatFS1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatFS1
	ldi		i,	0x00
	call	cout						; null data
	call	cout
	call	cout
	call	cout
	ldi		i,	0x08
	jmp		Host1						; file not opened

HostFatFS1:
	lds		i,	desFileLength
	call	cout
	lds		i,	desFileLength+1
	call	cout
	lds		i,	desFileLength+2
	call	cout
	lds		i,	desFileLength+3
	call	cout
	jmp		host0

;*************************************
; Set File Pointer
;*************************************
HostFatSP:
	call	HostGetFH
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatSP1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatSP1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatSP1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatSP1
	call	cin					; flush
	call	HostGetBCnt			; flush
	ldi		i,	0x08
	jmp		Host1				; file not open

HostFatSP1:
	call	fatLoadFileInfo
	call	cin					; get seek type
	andi	i,	0x03			; use bit 0 and 1
	push	i
	call	HostGetBCnt			; this gets 4 bytes, stored in bytecount
	lds		R0,	ByteCount
	lds		R1,	ByteCount+1
	lds		R2,	ByteCount+2
	lds		R3,	ByteCount+3
	pop		i
	call	fatFseek
	PUSH	i
	lds		i,	Handle
	call	HostSaveFH
	POP		i
	jmp		Host1

;*************************************
; Get File Pointer
;*************************************
HostFatGP:
	call	HostGetFH
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatGP1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatGP1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatGP1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatGP1
	ldi		i, 0x00
	call	cout
	call	cout
	call	cout
	call	cout
	ldi		i,	0x08
	jmp		Host1				; file not open

HostFatGP1:
	lds		i, 	desbytePointer
	call	cout
	lds		i, 	desbytePointer+1
	call	cout
	lds		i, 	desbytePointer+2
	call	cout
	lds		i, 	desbytePointer+3
	call	cout
	jmp		Host0

;*************************************
; Rename File
;*************************************
HostFatCN:
	call	HostGetFN
	brcc	HostFatCN2
	call	HostGetNFN
	brcc	HostFatCN2
	call	fatRename
HostFatCN2:
	rjmp	Host1

;*************************************
; Erase File or Dir
;*************************************
HostFatER:
	call	HostGetFN
	brcc	HostFatER1
	call	FatGetFileInfo
	tst		i					
	breq	HostFatER02			; file not found
	call	HostSrchFH			; see if already open in another handle
	cpi		i,  0xFF
	breq	HostFatER03
	ldi		i,  0x09
	jmp		Host1				; file opened in another handle

HostFatER02:
	ldi		i, 0x04				; file not found
	rjmp    Host1

HostFatER03:
    lds     i, desAttrib
	andi	i,  ATTR_READONLY
    breq    HostFatER0
    ldi		i, 0x0A			; write protected
	jmp		Host1
HostFatER0:
	call	fatRemove
HostFatER1:
	rjmp	Host1				; send error

;*************************************
; Erase all Files and Directories in current directory
;*************************************
HostFatEA:
	call	fatremoveAll
	rjmp	Host1

;*************************************
; Write data to File
;*************************************
HostFatWF:
	call	HostGetFH
	sts		Handle, i
	call	HostLoadFH
	lds		i, desDirEntSector
	tst		i
	brne	HostFatWF1	
	lds		i, desDirEntSector+1
	tst		i
	brne	HostFatWF1	
	lds		i, desDirEntSector+2
	tst		i
	brne	HostFatWF1	
	lds		i, desDirEntSector+3
	tst		i
	brne	HostFatWF1
	call	HostGetBCnt
HostFatWF000:
	lds		i,	byteCount
	tst		i
	brne	HostFatWF00
	lds		i,	byteCount+1
	tst		i
	brne	HostFatWF00
	lds		i,	byteCount+2
	tst		i
	brne	HostFatWF00
	lds		i,	byteCount+3
	tst		i
	brne	HostFatWF00
	call	cin					; flush
	lds		i,	byteCount
	ldi		j,	0x01
	sub		i,	j
	sts		ByteCount, i
	lds		i,	byteCount+1
	ldi		j,	0x00
	sbc		i,	j
	sts		ByteCount+1, i
	lds		i,	byteCount+2
	sbc		i,	j
	sts		ByteCount+2, i
	lds		i,	byteCount+3
	sbc		i,	j
	sts		ByteCount+3, i
	rjmp	HostFatWF000

HostFatWF00:
	ldi		i,	0x08			; file not open
HostFatWF0:
	jmp		Host1	

HostFatWF1:
	lds		i, desFileMode
	cpi		i, 0x01
	brne	HostFatWF12
	ldi		i,	0x05			; read only file
	rjmp	HostFatWF0

HostFatWF12:
	call	fatLoadFileInfo
	call	HostGetBCnt
HostFatWF15:
	lds		i,	byteCount
	tst		i
	brne	HostFatWF2
	lds		i,	byteCount+1
	tst		i
	brne	HostFatWF2
	lds		i,	byteCount+2
	tst		i
	brne	HostFatWF2
	lds		i,	byteCount+3
	tst		i
	brne	HostFatWF2
	call	fatFflush
	lds		i,	Handle
	call	HostSaveFH
	jmp		Host0			;done without errors
	
HostFatWF2:
	call	cin
	call	fatFPutc
	tst		i
	brne	HostFatWF0			; write error
	lds		i,	byteCount
	ldi		j,	0x01
	sub		i,	j
	sts		ByteCount, i
	lds		i,	byteCount+1
	ldi		j,	0x00
	sbc		i,	j
	sts		ByteCount+1, i
	lds		i,	byteCount+2
	sbc		i,	j
	sts		ByteCount+2, i
	lds		i,	byteCount+3
	sbc		i,	j
	sts		ByteCount+3, i
	rjmp	HostFatWF15

;*************************************
; Protect file/dir
;*************************************

HostFatPR:
	call	HostGetFN
	brcc	HostFatPR0
	call	FatGetFileInfo
	tst		i					; if not found, don't try to find in handle table
	breq	HostFatPR2
    lds     i, desAttrib
	andi	i, ATTR_VOLUME+ATTR_DIRECTORY
    cpi		i, ATTR_VOLUME		; is it volume label?
	breq	HostFatPR3
	cpi		i, ATTR_DIRECTORY	; is it a directory?
	breq	HostFatPR4
	call	HostSrchFH			; see if already open in another handle
	cpi		i,  0xFF
	breq	HostFatPR4
	ldi		i,  0x09			; file opened in another handle
HostFatPR1:
	jmp		Host1				

HostFatPR0:
	ldi		i,  0x02			; missing file name
	jmp		Host1				; 

HostFatPR2:
	ldi		i,  0x08			; file/dir not found
	jmp		Host1				; 
HostFatPR3:
	ldi		i,  0x06			; invalid file name
	jmp		Host1				; 
HostFatPR4:						; good fiel/dir
    lds     i, desAttrib
	ori		i, ATTR_READONLY    ; mark read only (PROTECTED)
    sts     desAttrib, i
    call	fatFcloseP			; update dir entry
	jmp		Host0

;*************************************
; Unprotect File/Dir
;*************************************

HostFatUP:
	call	HostGetFN
	brcc	HostFatUP0
	call	FatGetFileInfo
	tst		i					; if not found, don't try to find in handle table
	breq	HostFatUP2
    lds     i, desAttrib
	andi	i, ATTR_VOLUME+ATTR_DIRECTORY
    cpi		i, ATTR_VOLUME		; is it volume label?
	breq	HostFatUP3
	cpi		i, ATTR_DIRECTORY	; is it a directory?
	breq	HostFatUP4
	call	HostSrchFH			; see if already open in another handle
	cpi		i,  0xFF
	breq	HostFatUP4
	ldi		i,  0x09			; file opened in another handle

HostFatUP1:
	jmp		Host1				

HostFatUP0:
	ldi		i,  0x02			; missing file name
	jmp		Host1				; 

HostFatUP2:
	ldi		i,  0x08			; file/dir not found
	jmp		Host1				; 

HostFatUP3:
	ldi		i,  0x06			; invalid file name
	jmp		Host1				; 

HostFatUP4:						; good fiel/dir
    lds     i, desAttrib
	andi	i, 0xFE             ; mark read/write (UNPROTECTED)
    sts     desAttrib, i
    call	fatFcloseP			; update dir entry
	jmp		Host0

;*************************************
; Print Free Cluster Count <space> free bytes
;*************************************
HostFatFree:
	call	fatFreeClusters
;	mov		i, R1
;	call	hexout		; print # clusters free in hex
;	mov		i, R0
;	call	hexout
;	ldi		i, 0x20
;	call	cout		; space
	ldi		i, 0x00
	mov		R2, i
	mov		R3, i
	lds		i, SectorsPerCluster	;(1,2,4,8,16,32,64)
HostFatFree1:
	cpi		i, 0x01
	breq	HostFatFree2
	lsl		R0
	rol		R1
	rol		R2
	rol		R3
	lsr		i
	jmp		HostFatFree1

HostFatFree2:
	lsl		R0
	rol		R1
	rol		R2
	rol		R3
	mov		R3, R2
	mov		R2, R1
	mov		R1, R0
	clr		R0
	call	decout
	ldi		i, 0x00
	call	cout			; null term
	jmp		Host0

;*************************************
; Print Vol Label
;*************************************
HostFatVL:
	ldi		ZL, low(Voltxt*2)				; 
	ldi		ZH, high(Voltxt*2)	
	call	cstrout							; print Drive:
	lds		i, ata_drive
	ori		i, 0x30
	call	cout							; send drive number
	call	cstrout							; print Volume:
	call	fatVolLbl
	ldi		i,	0x00
	call	cout							; null terminated
	jmp		Host0

.CSEG
Voltxt:
		.db "Drive:", 0x00," Volume:", 0x00 

;*************************************
; Format Drive as Fat16
;*************************************
HostFatDF:
	call	fatDriveFormat
	jmp		Host1

;*************************************
; List Directory
;*************************************
HostFatLD:
DirSer:
		ldi		i,	0x00
		mov		R4, i
		mov		R5, i
		movw	R6, R4

DirSer1:	
		lds		lba,	CurrentDirCluster
		lds		lba1,	CurrentDirCluster+1
		lds		lba2,	CurrentDirCluster+2
		lds		lba3,	CurrentDirCluster+3
		call	fatdir
		call	fatTestR0
		brne	DirSer2
		ldi		i,	0x00
		call	cout							; null terminated
		rjmp	Host0		

DirSer2:
		ldi		i, 0x00							; counter for dir entries
		mov		R15, i
		ldi		ZL, low(fat_buffer)
		ldi		ZH, high(fat_buffer)

DirSer3:
		ldi		k,	0x0B
		ld		i,	Z+
		cpi		i,	SLOT_EMPTY
		brne	DirSer4
		ldi		i,	0x00
		call	cout							; null terminated
		rjmp	Host0		

DirSer4:
		cpi		i,	SLOT_DELETED
		brne	DirSer45

DirSer44:
		jmp		DirSer6

DirSer45:
		ldd		j,	Z+deAttrib-1
		cpi		j,	ATTR_VOLUME
		breq	DirSer44
		cpi		j,	ATTR_LONG_FILENAME
		breq	DirSer44

DirSer5:
		call	cout
		ld		i,	Z+
		dec		k
		brne	DirSer5
		push    i  									; save attrib byte
		ldi		i,	' '								; space 
		call	cout
		pop		i
		push	i
		andi	i, ATTR_READONLY	
		breq	DirSer54
		ldi		i, '*'								; show read only
		jmp		DirSer55

DirSer54:
		ldi		i,	' '								; show read/write

DirSer55:
		call	cout
		ldi		i,	' '								; show read/write
		call	cout
		pop		i									; restore attrib byte
		andi	i, 	ATTR_DIRECTORY
		breq	DirSer52
		push	ZL
		push	ZH
		ldi		ZL, low(DIR*2)              		; print <DIR> after directories
		ldi		ZH, high(DIR*2)

DirSer53:
	    call	cstrout	
		pop		ZH
		pop		ZL
		rjmp	DirSer57

DirSer52:
		ldd		i,	Z+19							; file size byte 4
		call	hexout
		ldd		i,	Z+18							; file size byte 3
		call	hexout
		ldd		i,	Z+17							; file size byte 2
		call	hexout
		ldd		i,	Z+16							; file size byte 1
		call	hexout

DirSer57:
		ldi		i,	' '
		call	cout
		ldd		j,	Z+13							; date byte 2
		ldd		i,	Z+12							; date byte 1
		call	fatDtoStr
		ldi		i,	' '
		call	cout
		ldd		j,	Z+11							; time byte 2
		ldd		i,	Z+10							; time byte 1
		call	fatTtoStr
		call	crlfout								; not used w/40 col disp

DirSer6:
		inc		R15
		mov		i, R15
		ldi		j, 0x00
		cpi		i,	FAT_DIRENTRIES_PER_SECTOR
		breq	DirSer8

DirSer7:
		lsl		i
		rol		j
		lsl		i
		rol		j
		lsl		i
		rol		j
		lsl		i
		rol		j
		lsl		i
		rol		j
		ldi		ZL, low(fat_buffer)
		ldi		ZH, high(fat_buffer)
		add		ZL,	i
		adc		ZH,	j
		rjmp	DirSer3	

DirSer8:
		ldi		i, 0x01
		add		R4, i
		ldi		i, 0x00
		adc		R5, i
		adc		R6, i
		adc		R7, i	
		rjmp	DirSer1

DIR:		.db " <DIR>  ", 0x00, 0x00

;*************************************
; parse New File Name
;*************************************
HostGetNFN:
	ldi		ZL, low(NewFileName)
	ldi		ZH, high(NewFileName)
	ldi		k, 0x00
	rjmp	HostGetFN1	

;*************************************
; Get File Name
;*************************************
HostGetFN:
	ldi		ZL, low(FileName)
	ldi		ZH, high(FileName)
	ldi		k, 0x00

HostGetFN1:
	call	cin
	cpi		i, 0x00			; null terminated name
	breq	HostGetFN4	
	cpi		k, 12
	breq	HostGetFN1		; ignore characters after 12 (8+3+.)
	st		Z+,	i
	inc		k
	rjmp	HostGetFN1

HostGetFN4:
	cpi		k, 12
	breq	HostgetFN44
	ldi		i,	0x00		; if file name < 12 chrs, add null term to end
	st		Z,	i
HostGetFN44:
	ldi		i,	0x02		; missing file name error
	clc
	tst		k
	breq	HostGetFN5
	sec

HostGetFN5:
	ret

;*************************************
; Get File Handle
;*************************************
HostGetFH:
	call	cin
	mov		j, i		
	swap	j
	andi	j, 0x0F		; File Mode
	andi	i, 0x0F		; File handle
	ret

;*************************************
; Load File Handle
;*************************************
HostLoadFH:
	andi	i, 0x0F
	swap	i
	ldi		XL, low(Handles)
	ldi		XH, high(Handles)
	ldi		j, 0x00
	add		XL, i
	adc		XH, j
	add		XL, i
	adc		XH, j
	ldi		YL, low(desDirEntSector)
	ldi		YH, high(desDirEntSector)
	ldi		j, 0x14

HostLoadFH1:
	ld		i, X+
	st		Y+, i
	dec		j
	brne	HostLoadFH1
	ret

;*************************************
; Save File Handle
;*************************************
HostSaveFH:
	andi	i, 0x0F
	swap	i
	ldi		XL, low(Handles)
	ldi		XH, high(Handles)
	ldi		j, 0x00
	add		XL, i
	adc		XH, j
	add		XL, i
	adc		XH, j
	ldi		YL, low(desDirEntSector)
	ldi		YH, high(desDirEntSector)
	ldi		j,	0x14

HostSaveFH1:
	ld		i,	Y+
	st		X+, i
	dec		j
	brne	HostSaveFH1
	ret

;*************************************
; Search File Handle
;*************************************
HostSrchFH:
	ldi		XL,	low(Handles)
	ldi		XH, high(Handles)
	ldi		k,	0x00

HostSrchFH1:
	ldi		YL, low(desDirEntSector)	
	ldi		YH, high(desDirEntSector)	
	ldi		l,	0x06

HostSrchFH2:
	ld		i,	Y+
	ld		j,	X+
	cp		i,	j
	brne	HostSaveFH4
	dec		l
	brne	HostSrchFH2
	mov		i,	k
	ret	
		
HostSaveFH4: ; no match
	inc		k
	mov		i, k
	andi	i, 0x0F
	swap	i
	ldi		XL, low(Handles)
	ldi		XH, high(Handles)
	ldi		j, 0x00
	add		XL, i
	adc		XH, j
	add		XL, i
	adc		XH, j
	cpi		k, 0x10
	brne	HostSrchFH1
; not found		
	ldi		i, 0xFF
	ret


;*************************************
; Direct Mode Read ATA Sector
;*************************************
HostDirRS:
	call	cin				; read 1 byte
	andi	i, 0x01				; mask 0 or 1 for ATA Buffer
	push	i
	push    i
	call	cin
	mov		R0,	i
	call	cin
	mov		R1,	i
	call	cin
	mov		R2,	i
	call	cin
	mov		R3,	i
	pop 	i
	call	ataReadSectors
	pop		i
	tst		i
	brne	HostDirRS1
	ldi		XL,	LOW(ata_buffer1)
	ldi		XH,	HIGH(ata_buffer1)
	rjmp	HostDirRS2

HostDirRS1:
	ldi		XL,	LOW(ata_buffer2)
	ldi		XH,	HIGH(ata_buffer2)

HostDirRS2:
	ldi		YL, 0x00
	ldi		YH,	0x02						; 512 bytes	

HostDirRS3:
	ld		i,	X+
;	call	Hexout			; send as Hexdigit pair
	call	cout			; send as raw
	sbiw	YL, 0x01
	brne	HostDirRS3
	jmp		Host0			; return no errors


;*************************************
; Direct Mode Write ATA Sector
;*************************************
HostDirWS:
	call	HostGetFH			; read 1 byte
	andi	i, 0x01				; mask 0 or 1 for ATA Buffer#
	push	i
	push	i
	call	cin
	mov		R0,	i
	call	cin
	mov		R1,	i
	call	cin
	mov		R2,	i
	call	cin
	mov		R3,	i
	pop		i
	tst		i
	brne	HostDirWS1
	ldi		XL,	LOW(ata_buffer1)
	ldi		XH,	HIGH(ata_buffer1)
	rjmp	HostDirWS2

HostDirWS1:
	ldi		XL,	LOW(ata_buffer2)
	ldi		XH,	HIGH(ata_buffer2)

HostDirWS2:
	ldi		YL, 0x00
	ldi		YH,	0x02						; 512 bytes	

HostDirWS3:
	call	cin				; get Hex byte
	st		X+, i				; save in buffer
	sbiw	YL, 0x01
	brne	HostDirWS3
	pop		i					; buffer #
	call	ataWriteSectors
	jmp		Host0


;*************************************
; Get Byte Count to read/write
;*************************************
HostGetBCnt:
	call	cin
	sts		ByteCount, i
	call	cin
	sts		ByteCount+1, i
	call	cin
	sts		ByteCount+2, i
	call	cin
	sts		ByteCount+3, i
	ret

;*************************************
; Set Time and Date
;*************************************
HostSetCal:
	call	HostGetHB
	sts		rtcDow, i			; DOW
	call	HostGetHB
	sts		rtcYR, i			; YR
	call	HostGetHB
	sts		rtcMon, i			; MON
	call	HostGetHB
	sts		rtcDay, i			; DAY
	call	HostGetHB
	sts		rtcHR, i			; HR
	call	HostGetHB
	sts		rtcMin, i			; MIN
	call	HostGetHB
	sts		rtcSec, i			; SEC
	call	WrCal
	rjmp	Host0

;*************************************
; Get Time and Date
;*************************************
HostGetCal:
	call	ds1302_getDT	; get FAT formatted Calendar 
	mov		j, R3
	mov		i, R2
 	call	FatDtoStr
	LDI		i, ' '
	CALL	cout
	mov		j, R1
	mov		i, R0
	call	FatTtoStr
	ldi		i, 0x00
	call	cout			; null term
	jmp		Host0

;*************************************
; Get Hex byte
; input two ascii chars 
; output byte in i
;*************************************
HostGetHB:
	call	cin
	cpi		i, 0x3a
	brcs	HostGetHB1
	subi	i, 0x07

HostGetHB1:
	andi	i, 0x0F
	swap	i
	mov		k, i
	call	cin
	cpi		i, 0x3a
	brcs	HostGetHB3
	subi	i, 0x07

HostGetHB3:
	andi	i, 0x0F
    add		i, k
	ret

;*************************************
; Direct Read RTC register
;*************************************
HostGetCalX:
;	call	HostGetHB
	call	cin			; fixed in v1.9
	sec
	rol		i
	andi	i, 0x0F
	ori		i, 0x80
	call	RDCmd
	call	cout			; send raw binary
	jmp		Host0

;*************************************
; Dump Drive Info
;*************************************
HostDriveInfo:
	call	DumpDriveInfo
	ldi		i, 0x00
	call	cout
	jmp		Host0

;*************************************
; Init File System
;*************************************
HostInitFS:
	call	cin
	andi	i, 0x01
	sts		ata_Drive, i
	cbr		status, 0x80	; disable cmd mode
	jmp		Reset1

;*************************************
;END OF FILE
;*************************************
