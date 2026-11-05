;
;  DS1302
;
;

.include "ds1302def.inc"
;
;--------------------------------------------------------
;
ds1302_init:

		sbi		DDR_RTCE, PIN_RTCE		; set enable pin as output
		sbi		PORT_RTCE, PIN_RTCE		; set enable pin High enable

		sbi		DDR_RTCC, PIN_RTCC		; set clock pin as output
		cbi		PORT_RTCC, PIN_RTCC		; set clock pin low (disabled)

		sbi		DDR_RTCD, PIN_RTCD		; set data pin as output
		cbi		PORT_RTCD, PIN_RTCD		; set data pin low 

		cbi		PORT_RTCE, PIN_RTCE		; set enable pin low (disabled)

		ldi		i, 0xff
		sts		sysClk, i				; mark clock not found

		; Set default date to 4/11/09 14:04:00 (random date, no significance)
		ldi		i, 0x00
		sts		rtcSec, i				; sec
		ldi		i, 0x04
		sts		rtcMin, i				; min
		ldi		i, 0x14
		sts		rtcHR, i				; hr
		ldi		i, 0x11
		sts		rtcDay, i				; day
		ldi		i, 0x04
		sts		rtcMon, i				; month
		ldi		i, 0x06
		sts		rtcDOW, i				; dow (not used)
		ldi		i, 0x09
		sts		rtcYR, i				; yr

		ldi		i, 0x8E					; write WP byte
		ldi		j, 0x00					; turn WP off
        call    WrCmd

		ldi		i, 0xC0					; write RAM loc 0
		ldi		j, 0xA5					; test pattern
        call    WrCmd					; 
		ldi		i, 0xC2					; write RAM loc 1
		ldi		j, 0x5A					; test pattern
        call    WrCmd					; 
		ldi		i, 0xC1					; read RAM 0
		call	RDCmd
		cpi		i, 0xA5					; bad RAM readback means no clock found
		brne	ds1302_init1
		ldi		i, 0xC3					; read RAM 1
		call	RDCmd
		cpi		i, 0x5A					; bad RAM readback means no clock found
		brne	ds1302_init1			; 
		ldi		i, 0x00
		sts		sysClk, i				; mark clock found

		ldi		i, 0x90					; write charger control reg
		ldi		j, 0x00					; turn trickle charger off
        call    WrCmd					; 


		ldi		i, 0x81					; read seconds
		call	RDCmd
		andi	i, 0x7F					; turn off clk halt bit
		mov		j, i
		ldi		i, 0x80					; seconds
		call	WrCmd					; enable clock

		ldi		i, 0x8E					; write WP byte
		ldi		j, 0x80					; turn WP on
        call    WrCmd
ds1302_init1:
		ret
;
;--------------------------------------------------------
; Write a cmd/data combo from i,j to the RTC.
;
WrCmd:
		push	j
		push	i
		sbi		PORT_RTCE, PIN_RTCE
		pop		i
        call    WrByte					; write cmd to RTC 
		pop		i
		sbi		DDR_RTCD, PIN_RTCD		; set data as output
        call   	WrByte					; write data to RTC
		cbi		PORT_RTCE, PIN_RTCE
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		ret

;--------------------------------------------------------
; Read a byte following write of command byte.
; command in i, data returned in i
;
RdCmd:
		sbi		PORT_RTCE, PIN_RTCE
        call    WrByte
        call    RdByte
		cbi		PORT_RTCE, PIN_RTCE
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		ret

;
;--------------------------------------------------------
; Clock out the byte in i to the RTC.
; Data is clocked out starting with bit 0. 
; Data is clocked into the RTC on the rising edge.

WrByte:
		ldi 	k, 8 					; 8 bits to clock out.
WrByte1:
		lsr 	i						; rotate.............bit 0 into C
		brcc 	WrByte2					; skip if bit = 0
		sbi		PORT_RTCD, PIN_RTCD
		jmp 	WrByte3
WrByte2:
		cbi		PORT_RTCD, PIN_RTCD
WrByte3:
		sbi		PORT_RTCC, PIN_RTCC
		dec 	k
		breq	WrByte4					; do 8 bits 			
		cbi		PORT_RTCC, PIN_RTCC
		jmp		WrByte1
WrByte4:
		cbi		DDR_RTCD, PIN_RTCD		; change data to input
		cbi		PORT_RTCD, PIN_RTCD		; DROP PULL-UP
		cbi		PORT_RTCC, PIN_RTCC
		ret

;
;--------------------------------------------------------
; read in a byte from the RTC to i
;
RdByte:
        ldi     i, 0					; Empty register for data
        ldi     k, 8					; 8 bits to clock in.
RdByte1:
        clc								; Clear carry.
        sbic    IN_RTCD, PIN_RTCD		; Jump if I/O = 0.
        sec								; Set Carry Flag
        ror     i						; Rotate data into bit.
		sbi		PORT_RTCC, PIN_RTCC
		nop
		cbi		PORT_RTCC, PIN_RTCC
        dec     k						; 8 bits
        brne    RdByte1
		ret

;
;--------------------------------------------------------
; Read calendar in burst mode
; 
RdCal:
		sbi		PORT_RTCE, PIN_RTCE
		ldi		i, 0xBF					; burts mode read calendar
        call    WrByte
        call    RdByte
		sts		rtcSec, i				; sec
        call    RdByte
		sts		rtcMin, i				; min
        call    RdByte
		sts		rtcHR, i				; hr
        call    RdByte
		sts		rtcDay, i				; day
        call    RdByte
		sts		rtcMon, i				; month
        call    RdByte					 
		sts		rtcDOW, i				; dow (not used)
        call    RdByte
		sts		rtcYR, i				; yr
        call    RdByte					 
		sts		rtcPR, i				; WP (not used)
		cbi		PORT_RTCE, PIN_RTCE
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		ret

;
;--------------------------------------------------------
; Write calendar in burst mode
; 
WrCal:
		ldi		i, 0x8E					; write WP byte
		ldi		J, 0x00					; turn WP off
        call    WrCmd
		sbi		PORT_RTCE, PIN_RTCE		; enable clock
		ldi		i, 0xBE					; burts mode write calendar
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcSec				; secs
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcMin				; mins
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcHR				; hrs
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcDay				; day
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcMon				; month
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcDow				; dow
        call    WrByte
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		lds		i, rtcYR				; yr
        call    WrByte	
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		ldi		i, 0x80					; write protect on
		call    WrByte
		cbi		PORT_RTCE, PIN_RTCE
		sbi		DDR_RTCD, PIN_RTCD		; set data as output on exit
		ret

;
;--------------------------------------------------------
;
; Get Date and Time
; return in FAT format in R0-R3
;
ds1302_getDT:

		lds		i, sysClk			; DS1302 found?	
		tst		i
		brne	ds1302_0			; yes, get its date & time
		call	RdCal					; burst mode read	
ds1302_0:
		lds		i, rtcYR				; yr
		mov		j, i
		andi	j, 0x0F					; lower digit
		swap	i						; 
		andi	i, 0x0F					; upper digit
		lsl		i
		mov		k, i
		lsl		i
		lsl		i
		add		i, k					; k = i * 10
		add		i, j					; 
		ldi		j, 0x14					; OFFSET FOR 1980 - 20xx century
		add		i, j					; 
		mov		R3, i					; store upper byte (yr)
		lds		i, rtcMon				; month
		cpi		i, 0x10					; 
		brcs	ds1302_1
		ldi		j, 0x06					;
		sub		i, j					;
ds1302_1:
		andi	i, 0x0F					; 
		swap	i
		lsl		i
		rol		R3						; adjust R3
		mov		R2, i					; set R2
		lds		i, rtcDay				; day 1-31
		mov		j, i
		andi	j, 0x0F					; lower digit
		swap	i						; 
		andi	i, 0x0F					; upper digit
		lsl		i
		mov		k,i
		lsl		i
		lsl		i
		add		i, k					; k = i * 10
		add		i, j					; 
		andi	i, 0x1F					; 
		add		R2, i					; set day to month in R2
		lds		i, rtcHR				; hour
		tst		i						; 
		brmi	ds1302_3				; 12hr
		mov		j, i					; save i
		andi	i, 0x30					; mask 10's
		swap	i						; 
		lsl		i
		mov		k,i
		lsl		i
		lsl		i
		add		i, k					; k = i * 10
		andi	j, 0x0F					; mask 1's digit
		add		i, j					; hr digit ready
		jmp		ds1302_6
ds1302_3:
		mov		j,	i					; save
		andi	i, 0x1F					;
		cpi		i, 0x10					;
		brcs	ds1302_4
		andi	i, 0x0F
		ldi		k, 0x0a
		add		i, k					; bcd hrs to bin hrs
ds1302_4:
		andi	j, 0x20					; am/pm
		brne	ds1302_5
		cpi		i, 0x0c					; is am hrs = 12?
		brne	ds1302_6				; no done
		ldi		i, 0x00					; set hrs to 0
		jmp		ds1302_6
ds1302_5:								; pm
		cpi		i, 0x0c					; is it 12
		breq	ds1302_6				; yes done
		ldi		j, 0x0c					;
		add		i, j
ds1302_6:
		lsl		i
		lsl		i
		lsl		i
		mov		R1, i					; save hr to R1
		lds		i, rtcMin				; minutes
		mov		j,	i					; save
		andi	i, 0x70					;
		swap	i
		lsl		i
		mov		k,i
		lsl		i
		lsl		i
		add		i, k					; k = i * 10
		andi	j, 0x0F					; mask 1's
		add		i, j					; i= mins		
		mov		j, i					; save in j
		lsl		i		
		swap	i
		andi	i, 0x07
		add		R1, i					; save Mins to R1
		andi	j, 0x07					;
		swap	j
		lsl		j
		mov		R0, j					; save mins to R0
		lds		i, rtcSec				; secs
		mov		j,	i					; save
		andi	i, 0x70					;
		swap	i
		lsl		i
		mov		k,i
		lsl		i
		lsl		i
		add		i, k					; k = i * 10
		andi	j, 0x0F					; mask 1's
		add		i, j					; i= mins		
		andi	i, 0x3F					; mask secs
		lsr		i						; sec / 2
		add		R0, i					; save secs to R0
		ret

