;
; ATA definitions
;
.def	lba					=	R0			; used when calling
.def	lba1				=	R1			; ata_read_sectors  &
.def	lba2				= 	R2			; ata_write_sectors
.def	lba3				=	R3

; constants

.set DRIVE0					=	0x00
.set DRIVE1             	=   0x10

; ATA status register bits
.set ATA_SR_BSY				=	0x80
.set ATA_SR_DRDY			=	0x40
.set ATA_SR_DF				=	0x20
.set ATA_SR_DSC				=	0x10
.set ATA_SR_DRQ				=	0x08
.set ATA_SR_CORR			=	0x04
.set ATA_SR_IDX				=	0x02
.set ATA_SR_ERR				=	0x01

; ATA error register bits
.set ATA_ER_UNC				=	0x40
.set ATA_ER_MC				=	0x20
.set ATA_ER_IDNF			=	0x10
.set ATA_ER_MCR				=	0x08
.set ATA_ER_ABRT			=	0x04
.set ATA_ER_TK0NF			=	0x02
.set ATA_ER_AMNF			=	0x01

; ATA 
.set ATA_HEAD_USE_LBA 		=	0xE0

; ATA commands
.set ATA_CMD_READ			=	0x20
.set ATA_CMD_READNR			=	0x21
.set ATA_CMD_WRITE			=	0x30
.set ATA_CMD_WRITENR		=	0x31
.set ATA_CMD_IDENTIFY		=	0xEC
.set ATA_CMD_RECALIBRATE	=	0x10
.set ATA_CMD_SPINDOWN		=	0xE0		; spin down disk immediately
.set ATA_CMD_SPINUP			=	0xE1		; spin up disk immediately
.set ATA_CMD_STANDBY_5SU	=	0xE2		; spin down disk and set auto-power-down timer (sectorcount*5sec)
.set ATA_CMD_IDLE_5SU		=	0xE3		; keep disk spinning and set auto-power-down timer (sectorcount*5sec)
.set ATA_CMD_SLEEP			=	0xE6		; sleep disk (wakeup only on HW or SW reset)
.set ATA_CMD_STANDBY_01SU	=	0xF2		; spin down disk and set auto-power-down timer (sectorcount*0.1sec)
.set ATA_CMD_IDLE_01SU 		=	0xF3		; keep disk spinning and set auto-power-down timer (sectorcount*0.1sec)


; ATA Identity fields
; all offsets refer to word offset (2 unsigned char increments)
.set ATA_IDENT_DEVICETYPE	=	0		; specifies ATA/ATAPI, removable/non-removable
.set ATA_IDENT_CYLINDERS	=	1		; number of logical cylinders
.set ATA_IDENT_HEADS		=	3		; number of logical heads
.set ATA_IDENT_SECTORS		=	6		; number of sectors per track
.set ATA_IDENT_SERIAL		=	10		; drive serial number (20 characters)
.set ATA_IDENT_MODEL		=	27		; drive model name (40 characters)
.set ATA_IDENT_LBASUPPORT	=	49		; bit 9 = 1 if LBA mode supported
.set ATA_IDENT_FIELDVALID	=	53		; indicates field validity of higher words (bit0: words54-58, bit1: words 64-70)
.set ATA_IDENT_LBASECTORS	=	60		; number of sectors in LBA translation mode

.DSEG
//.org $0060		; ata allowed $0060-006F for storage 
ata_cache1:			.byte 4
ata_cache2:			.byte 4
ata_sectors:		.byte 4
ata_drive:			.byte 1

//.ORG $0100
ata_buffer1:		.byte 512

//.org $0300
ata_buffer2:		.byte 512

.CSEG
