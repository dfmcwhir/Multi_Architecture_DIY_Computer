;
; ATA Configuration definitions
;
; hardware interface specific assignments
;
;****************************************************************************
; If you change the hardware, you will have to change these definitions.

.set DDR_DATAL		=	DDRC		; Define the Direction PORT to DATA High
.set PORT_DATAL		=	PORTC		; Define the PORT to DATA High
.set PIN_DATAL		=	PINC		; Define the PIN to DATA High

.set DDR_DATAH		=	DDRA		; Define the Direction PORT to DATA Low
.set PORT_DATAH		=	PORTA		; Define the PORT to DATA Low
.set PIN_DATAH		=	PINA		; Define the PIN to DATA Low

.set DDR_ADDR		=	DDRD		; Define the PORT to Address
.set PORT_ADDR		=	PORTD		; Define the PORT to Address

.set PORT_IDE_RD	=	PORTD		; Define the PORT to IDE_RD
.set PIN_IDE_RD 	=	5			; Define the PIN number to IDE_RD
	
.set PORT_IDE_WR	=	PORTD		; Define the PORT to IDE_WR
.set PIN_IDE_WR 	=	6			; Define the PIN number to IDE_WR

.set PORT_IDE_RES	=	PORTD		; Define the PORT to IDE_RES
.set PIN_IDE_RES 	=	7			; Define the PIN number to IDE_RES

.set IDE_RES       	=  	0x80       	; Define the binary weight to the bit position
.set IDE_WR         =  	0x40       	; Define the binary weight to the bit position
.set IDE_RD         =  	0x20       	; Define the binary weight to the bit position
.set IDE_CS2       	=  	0x10       	; Define the binary weight to the bit position
.set IDE_CS1       	=  	0x08       	; Define the binary weight to the bit position

;****************************************************************************

; ATA ADDR (Port B) bit map
; A0 = PortAddr bit 0
; A1 = PortAddr bit 1
; A2 = PortAddr bit 2
; CS1 = PortAddr bit 3
; CS2 = PortAddr bit 4
; /RD = PortAddr bit 5
; /WR =PortAddr bit 6
; /RES =PortAddr bit 7
;
.set ATA_REG_DATA		=	0x10 + IDE_RD + IDE_WR + IDE_RES		
.set ATA_REG_ERROR		=	0x11 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_SECCOUNT	=	0x12 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_STARTSEC	=	0x13 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_CYLLO		=	0x14 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_CYLHI		=	0x15 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_HDDEVSEL	=	0x16 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_CMDSTATUS1	=	0x17 + IDE_RD + IDE_WR + IDE_RES
.set ATA_REG_ACTSTATUS	=	0x0E + IDE_RD + IDE_WR + IDE_RES




