;
; DS1302 Driver definitions
;
;

.set DDR_RTCC	    =	DDRB		; Define the PORT to DS1320 clock pin
.set PORT_RTCC	    =	PORTB		; Define the PORT to DS1320 clock pin
.set PIN_RTCC 	    =	2			; Define the PIN number to DS1320 clock pin
.set RTCC           =	0x04       	; Define the binary weight to the bit position

.set DDR_RTCD	    =	DDRB		; Define the PORT to DS1320 clock pin
.set PORT_RTCD	    =	PORTB		; Define the PORT to DS1320 data pin for OUTPUT
.set IN_RTCD	    =	PINB		; Define the PORT to DS1320 data pin for INPUT
.set PIN_RTCD 	    =	1			; Define the PIN number to DS1320 data pin
.set RTCD           =	0x02       	; Define the binary weight to the bit position

.set DDR_RTCE	    =	DDRB		; Define the PORT to DS1320 clock pin
.set PORT_RTCE	    =	PORTB		; Define the PORT to DS1320 enable pin
.set PIN_RTCE 	    =	0			; Define the PIN number to DS1320 enable pin
.set RTCE			=	0x01       	; Define the binary weight to the bit position

.DSEG
//.ORG $07F0		; 8 BYTES used to hold calendar data 

rtcSec:				.byte 1			; seconds
rtcMin:				.byte 1			; minutes
rtcHr:				.byte 1			; hour
rtcDay:				.byte 1			; day
rtcMon:				.byte 1			; month
rtcDOW:				.byte 1			; day of week
rtcYR:				.byte 1			; year
rtcPR:				.byte 1			; protect

.CSEG
