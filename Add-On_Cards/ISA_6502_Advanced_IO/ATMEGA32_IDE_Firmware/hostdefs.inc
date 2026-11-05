;
; Host Definitions
;
;

.def	din		=	R21			; SPI Slave Controller registers
.def	dout	=	R22			;  "
.def	cmdr	=	R23			;  "
.def	status	=	R24			;  "
.def	state	=	R25			;  "

.set	LEDpt	=	PORTB			; LED Driver Port
.set	LEDddr	=	DDRB			;
.set	LEDPin	=	PB3			;

.DSEG

; set file handle database
//.org $0500
Handles:			.byte 512
;
; Handles is 16 handles of 32 bytes each
; data originates from FAT mem variables
; desDirEntSector:	.byte 4		; hold LBA sector of dir entry
; desDirEntpos:		.byte 2		; pointer to Dir Entry in Sector
; descurrentSector:	.byte 4		; Actual sector address in memory
; desbytePointer:	.byte 4		; byte pointer to the actual byte (divide by 512 to find the current buffer position)
; desFileLength:	.byte 4		; length of open file
; dessectorHasChanged:	.byte 1		; TRUE if the sector in memory has changed and needs to be write before a close file or change in sector
; desFileMode:		.byte 1		; R = read only, W = write, A = append
;

//.ORG $0700		; first byte avail after "atadef.inc" declarations
cmd_buffer:			.byte 80	; Host command buffer
.CSEG

