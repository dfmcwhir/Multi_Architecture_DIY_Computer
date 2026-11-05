;
; FAT TIME include file
;
;

;// This is the format of the contents of the deTime field in the direntry
;// structure.
.set DT_2SECONDS_MASK        = 0x1F    // seconds divided by 2
.set DT_2SECONDS_SHIFT       = 1		// SHIFT to right, ALL the others are to left
.set DT_MINUTES_MASK         = 0x7E0   // minutes
.set DT_MINUTES_SHIFT        = 5
.set DT_HOURS_MASK           = 0xF800  // hours
.set DT_HOURS_SHIFT          = 11

;// This is the format of the contents of the deDate field in the direntry
;// structure.
.set DD_DAY_MASK             = 0x1F    // day of month
.set DD_DAY_SHIFT            = 0
.set DD_MONTH_MASK           = 0x1E0   // month
.set DD_MONTH_SHIFT          = 5
.set DD_YEAR_MASK            = 0xFE00  // year - 1980
.set DD_YEAR_SHIFT           = 9


.DSEG
//.ORG $00F8		; last 8 bytes before the buffers
sysDate:			.byte 2	; holds system date
sysTime:			.byte 2	; holds system time
sysClk:				.byte 1 ; clock detected flag
.CSEG
