;
;
; Global Definitions
;
;
.set FALSE	= 0x00
.set TRUE 	= 0xFF	

;define CPU clock speed
;.set 	F_CPU	=	20000000		        ; 20MHz processor (ATmega324P)
.set 	F_CPU	=	16000000		        ; 16MHz processor (ATmega32: its maximum)
;.set 	F_CPU	=	8000000            		;  8MHz processor
;.set 	F_CPU	=	4000000            		;  4MHz processor
;.set 	F_CPU	=	1000000            		;  1MHz processor
.set CYCLES_PER_US = ((F_CPU+500000)/1000000) ; cpu cycles per microsecond

; Register Definitions

;					R0-R15		; used in ATA & FAT routines
.def	i		=	R16			; temp integer regsisters, not preserved by subroutines
.def	j		=	R17			;	"
.def	k		=	R18			;	"
.def	l		=	R19			;	"
.def	m		=	R20			;	"



