;//*****************************************************************************
;//
;// FAT time driver
;//
;//*****************************************************************************

.include "fattimedef.inc"

#ifndef ATA_READ_ONLY
;//*****************************************************************************
;// Function: fatGetCurTime
;// Parameters: The current Date and Time Address Struct
;// Returns: Date & time in sysDate & sysTime RAM variables
;// Description: Returns the current Time and Date
;//
;//              You will have to change this routine to read your local time,
;//              and return it in this format.
;//
;//              Date and Time Format
;//              Day:     valid range 1-31
;//	            Month:   1= January, valid range 1-12
;//              Year:    valid range 0-65535
;//              Hour:    valid range 0-23
;//              Minutes: valid range 0-59
;//              Seconds: valid range 0-59
;//*****************************************************************************
fatGetCurTime:

;	day     = 26;
;	month   = 04;
;	year    = 2004;
;	hour    = 17;
;	minutes = 30;
;	seconds = 00;
	
;	time	8BC0	1000	1011	1100	0000			
;	date	329A	0011	0010	1001	1010


;		ldi		i,	0x9A		; else, use default
;		sts		sysDate, i
;		ldi		i,	0x32
;		sts		sysDate+1, i
;		ldi		i,	0xC0
;		sts		sysTime, i
;		ldi		i,	0x8B
;		sts		sysTime+1, i
;		ret

fatGetCurTime1:
		call	ds1302_getDT
		sts		sysDate, R2
		sts		sysDate+1, R3
		sts		sysTime, R0
		sts		sysTime+1, R1
		ret
		
#endif

;
; Date in j,i
; uses i,j
; format mm/dd/yy
;
FatDtoStr:
		push	j
		push	i
		lsl		i
		rol		j
		lsl		i
		rol		j
		lsl		i
		rol		j
		andi	j,	0x0f
		mov		i,	j
		call	hextodec
		ldi		i,	'/'
		call	cout
		pop		i
		andi	i,	0x1f
		call	hextodec
		ldi		i,	'/'
		call	cout
		pop		i
		lsr		i
		cpi		i,	0x78		;	
		brpl	FatDtoStr21
		cpi		i,	0x14
		brpl	FatDtoStr20	
FatDtoStr19:
		ldi		j,	0x50
		add		i,	j
		push	i
;		ldi		i,	'1'
;		call	cout
;		ldi		i,	'9'
;		call	cout
		rjmp	FatDtoStr30
FatDtoStr20:
		subi	i,	0x14
		push	i
;		ldi		i,	'2'
;		call	cout
;		ldi		i,	'0'
;		call	cout
		rjmp	FatDtoStr30
FatDtoStr21:
		subi	i,	0x78
		push	i
;		ldi		i,	'2'
;		call	cout
;		ldi		i,	'1'
;		call	cout
FatDtoStr30:
		pop		i
		call	hextodec
		ret
;
; Time in j,i
; uses i,j,k,l
; set for 24hr time to save space, uncomment cmds for 12hr format

FatTtoStr:
		push	j
		push	i
		lsr		j
		lsr		j
		lsr		j
		mov		i,	j
;		ldi		l,	0x00		;AM
;		cpi		i,	0x0c
;		brmi	FatTtoStr1
;		inc		l				;PM		
;		subi	i,	0x0c
;FatTtoStr1:
;		tst		i
;		brne	FatTtoStr2
;		ldi		i,	0x0c
FatTtoStr2:
		call	hextodec
		ldi		i,	':'
		call	cout
		pop		i
		pop		j
		push	i
		lsl		i
		rol		j
		lsl		i
		rol		j
		lsl		i
		rol		j
		andi	j,	0x3F
		mov		i,	j
		call	hextodec
		ldi		i,	':'
		call	cout
		pop		i
		andi	i,	0x1f
		lsl		i
		call	hextodec
;		ldi		i,	' '
;		call	cout
;		ldi		i,	'A'
;		tst		l
;		breq	FatTtoStr9
;		ldi		i,	'P'
;FatTtoStr9:
;		call	cout
;		ldi		i,	'M'
;		call	cout
		ret

