;
;  FAT commands
;

; FAT Error codes
; 
; 0 = no errors
; 1 = 
; 4 = File Not found
; 5 = File already Exists
; 6 = invalid file type
; 7 = unable to erase all files (directory not empty)?
; b = file too large (> 2^32)
; A = file locked
; B = Disk full
; C = Root Dir Full
; D = invalid parameter (Seek)
; E = Unable to INIT FAT
; F = Read past EOF
; e = unexpected value - cluster size too large

.include "fatdefs.inc"
.include "fattime.asm"
		
;*****************************************************************************
; Uses: i,j,k,m,R0-R7,R15,X,Y,Z
; Get FAT info from ATA Device and initialize variables
;*****************************************************************************
fatInit: 
		; read boot sector
		call	fatClrR0
		ldi		i, 0x00                     ; buffer1
		call	ataReadSectors

		; test sector for validity
		lds		i, fat_buffer+prIsActive
		cpi		i, 0x80
		breq	fatInit2

fatInit1:
		;unrecognized boot sector
		jmp		fatInit20

fatInit2:
		lds		i, fat_buffer+510
		cpi		i, 0x55
		brne	fatInit1
		lds		i, fat_buffer+511
		cpi		i, 0xAA
		brne	fatInit1
		lds		i, fat_buffer+prPartType
		cpi		i, PART_TYPE_FAT16
		breq	fatInit3
		cpi		i, PART_TYPE_DOSFAT16
		breq	fatInit3
		; unsupported FAT type
		jmp		fatInit20

fatInit3:
		; load first partition's Volume Boot Record
		lds		lba,  fat_buffer+prStartLBA
		lds		lba1, fat_buffer+prStartLBA+1
		lds		lba2, fat_buffer+prStartLBA+2
		lds		lba3, fat_buffer+prStartLBA+3
		;FirstDataSector	= PartInfo.prStartLBA;
		sts		startLBA, 	lba
		sts		startLBA+1, lba1
		sts		startLBA+2, lba2
		sts		startLBA+3, lba3
		ldi		i, 0x00                       ; buffer1
		call	ataReadSectors

; verify proper VBR FAT structure
		lds		i, fat_buffer+510
		cpi		i, 0x55
		brne	fatInit4
		lds		i, fat_buffer+511
		cpi		i, 0xAA
		brne	fatInit4
		lds		i, fat_buffer
		cpi		i, 0xE9
		breq	fatInit33
		cpi		i, 0xEB
		brne	fatInit4
fatInit33:
		lds		i, fat_buffer+bpbBootSig
		cpi		i, 0x29
		breq	fatInit5
fatInit4:
		; VBR structure errors
		jmp		fatInit20

fatInit5:
; see if #sectors < 65535

		lds		i, fat_buffer+bpbFATsecs
		lds		j, fat_buffer+bpbFATsecs+1
		sts		FatSectors, i
		sts		FatSectors+1, j

		cpi		i, 0x00
		brne	fatInit6
		cpi		j, 0x00
		breq	fatInit4					; error with FAT size
fatInit6:
		lds		m, fat_buffer+bpbFATs        ; calc # FAT sectors used
		sts		NumFats, m
		ldi		k, 0x00
fatInit7:
		cpi		m, 0x01
		breq	fatInit8
		add		i, i
		adc		j, j
		adc		k, k
		lsr		m
		jmp		fatInit7

fatInit8:
		movw	R0, i
		mov		R2, k
		ldi		i, 0x00
		mov		R3, i
		lds		i, startLBA
		add		R0, i
		lds		i, startLBA+1
		adc		R1, i
		lds		i, startLBA+2
		adc		R2, i
		lds		i, startLBA+3
		adc		R3, i
		lds		i, fat_buffer+bpbResSectors
		add		R0, i
		lds		i, fat_buffer+bpbResSectors+1
		adc		R1, i
		ldi		i, 0x00
		adc		R2, i
		adc		R3, i

		sts		RootDirSector, R0
		sts		RootDirSector+1, R1
		sts		RootDirSector+2, R2
		sts		RootDirSector+3, R3
; 
		lds		i,	fat_buffer+bpbRootDirEnts
		lds		j,	fat_buffer+bpbRootDirEnts+1
		cpi		i,	0x00
		breq	fatInit81
		cpi		j,	0x02
		breq	fatInit81
		jmp		fatinit4	; VBR error - RootDirEntries must be 512!

fatInit81:
		ldi		k,	FAT_DIRENTRIES_PER_SECTOR
fatInit82:
		cpi		k, 0x01
		breq	fatInit84
		lsr		j
		ror		i
		lsr		k
		jmp		fatInit82
fatInit84:
		ldi		k,	0x00
		add		R0, i
		adc		R1,	j
		adc		R2,	k
		adc		R3,	k
		sts		FirstDataSector, R0
		sts		FirstDataSector+1, R1
		sts		FirstDataSector+2, R2
		sts		FirstDataSector+3, R3

		;	
		lds		i, fat_buffer+bpbSecPerClust
		sts		SectorsPerCluster, i

		lds		i, fat_buffer+bpbResSectors
		lds		j, startLBA
		add		i, j
		sts		FirstFATSector, i
		lds		i, fat_buffer+bpbResSectors+1
		lds		j, startLBA+1
		adc		i, j
		sts		FirstFATSector+1, i
		ldi		i, 0x00
		lds		j, startLBA+2
		adc		j, i
		sts		FirstFATSector+2, j
		lds		j, startLBA+3
		adc		j, i
		sts		FirstFATSector+3, j

		lds		R0, ata_sectors
		lds		R1, ata_sectors+1
		lds		R2, ata_sectors+2
		lds		R3, ata_sectors+3
		lds		i, SectorsPerCluster ;*** SEC PER CLUST LIMITED AT 255!!!
fatInit9:
		cpi		i, 0x01
		breq	fatInit10
		lsr		R3
		ror		R2
		ror		R1
		ror		R0
		lsr		i
		jmp		fatInit9
fatInit10:
		sts		NumClusters, R0
		sts		NumClusters+1, R1
		tst		R2
		brne	fatInit102
		tst		R3
		breq	fatInit105
fatInit102:
		jmp		fatInit20 ; sectors/sec-per-clust has remainder

fatInit105:

; initialize Volume Label
		ldi		XL, low(fat_buffer+bpbVolLab)
		ldi		XH, high(fat_buffer+bpbVolLab)
		ldi		YL, low(volname)
		ldi		YH, high(volname)
		ldi		j, 0x0B                             ; 11 characters
fatInit11:
		ld		i, X+
		st		Y+, i
		dec		j
		brne	fatInit11
		ldi		i, 0x00
		st		Y, i

		; currentDirCluster= root directory
		ldi		i, 0x00		;	root directory
		sts		CurrentDirCluster, i
		sts		CurrentDirCluster+1, i

		; 
		lds		i, FirstFATSector
		lds		j, fat_buffer+bpbFATsecs
		add		i, j
		sts		FirstFAT2Sector, i
		lds		i, FirstFATSector+1
		lds		j, fat_buffer+bpbFATsecs+1
		adc		i, j
		sts		FirstFAT2Sector+1, i
		ldi		j, 0x00
		lds		i, FirstFATSector+2
		adc		i, j
		sts		FirstFAT2Sector+2, i
		lds		i, FirstFATSector+3
		adc		i, j
		sts		FirstFAT2Sector+3, i

		;SEARCH ROOT DIR FOR VOLUME ENTRY - OVERWRITE VBR NAME IF FOUND
		ldi		i,	0x00
		mov		r4,	i
		mov		r5,	i
		movw	r6,	r4
fatInit12:
		ldi		i,	0x00
		mov		R0,	i
		mov		R1,	i
		movw	R2,	R0
		call	fatDir
		call	fatTestR0
		breq	fatInit19
fatInit13:
		ldi		i, 0x00							; counter for dir entries
		mov		R15, i
		ldi		ZL, low(fat_buffer)
		ldi		ZH, high(fat_buffer)

fatInit14:
		ldd		i,	Z+deAttrib
		cpi		i,	SLOT_EMPTY
		breq	fatInit19

fatInit15:
		cpi		i,	ATTR_VOLUME
		brne	fatInit16
		ldi		YL, low(volname)
		ldi		YH, high(volname)
		ldi		k,	0x0B
fatInit155:
		ld		i,	Z+
		st		Y+,	i
		dec		k
		brne	fatInit155
		ldi		i, 0x00
		st		Y, i
		rjmp	fatInit19
fatInit16:
		inc		R15
		mov		i, R15
		cpi		i,	FAT_DIRENTRIES_PER_SECTOR
		breq	fatInit18
fatInit17:
		adiw	ZL,	0x20
		rjmp	fatInit14
fatInit18:
		ldi		i, 0x01
		call	fatIncR0
		rjmp	fatInit12

fatInit19:
		ldi		XL, low(Handles)		; clear handle table
		ldi		XH, high(Handles)
		ldi		i,	0x00
		ldi		j, 0x00
fatInit191:
		st		X+,	i
		st		X+,	i
		dec		j
		brne	fatInit191
		ldi		i, 0x00
		sts		dessectorHasChanged, i	; init state
		ret

fatInit20:
		ldi		i,	0x0E				; Error - unable to Init FAT
		ret

;*****************************************************************************
; cluster in R0 - R1, sector out in R0-R3 
; $00000000 is returned sector of Root Dir
; Uses i, R0-R3
;*****************************************************************************
fatClustToSect:
		tst		R0
		brne	fatClust2sec1
		tst		R1
		brne	fatClust2sec1
; this is root directory
		lds		R0, RootDirSector
		lds		R1, RootDirSector+1
		lds		R2, RootDirSector+2
		lds		R3, RootDirSector+3
		ret

fatClust2sec1:
		ldi		i, 0x02
		sub		R0, i
		ldi		i, 	0x00
		sbc		R1, i
		mov		R2,	i
		mov		R3,	i
		; add test for cluster1?
		lds		i, SectorsPerCluster
fatClust2sec2:
		cpi		i, 0x01
		breq	fatClust2sec3
		lsl		R0
		rol		R1
		rol		R2
		rol		R3
		lsr		i
		jmp		fatClust2sec2
fatClust2sec3:
		lds		i, FirstDataSector
		add		R0, i
		lds		i, FirstDataSector+1
		adc		R1, i
		lds		i, FirstDataSector+2
		adc		R2, i
		lds		i, FirstDataSector+3
		adc		R3, i
		ret

;*****************************************************************************
; Uses i, R0-R3
; Converts sectors to Clusters - any sector < FirstDataSector return Cluster 0
;*****************************************************************************
fatSectToClust:

		lds		i, FirstDataSector
		sub		R0, i
		lds		i, FirstDataSector+1
		sbc		R1, i
		lds		i, FirstDataSector+2
		sbc		R2, i
		lds		i, FirstDataSector+3
		sbc		R3, i
		lds		i, SectorsPerCluster
		brcc	fatSectToClust1
		; < FirstDataSector is Root Dir, return cluster 0
		clr		R0
		clr		R1
		ret

fatSectToClust1:
		cpi		i, 0x01
		breq	fatSectToClust2
		lsr		R3
		ror		R2
		ror		R1
		ror		R0
		lsr		i
		jmp		fatSectToClust1
fatSectToClust2:
		ldi		i, 0x02
		add		R0,	i
		ldi		i,  0x00
		adc		R1,	i
		ret

;*****************************************************************************
; Uses i,R0-R3,R8-R9,X
; Find next cluster in the FAT chain
;*****************************************************************************
fatNextCluster: 

		call	fatTableClustToSect	  ; R0-R3, R8-R9, i
		ldi		i, 0x01
		call	ataReadSectors      ; read FAT in buffeR2
		ldi		XL,	LOW(fat_cache)
		ldi		XH,	HIGH(fat_cache)
		add		XL, R8				; offset
		adc		XH, R9				; offset
		ld		R0, X+
		ld		R1, X
		mov		i, R0
		cpi		i, CLUST_EOFE & 0xFF ; assumes all EOC's are CLUST_EOFE!
		brne	fatNextCluster1
		mov		i, R1
		cpi		i, (CLUST_EOFE>>8) & 0xFF
		brne	fatNextCluster1
		clr		R0
		clr		R1
fatNextCluster1:
		ret


;*****************************************************************************
; return the sector with direntries info starting in the cluster and with 
; offset sectors from the begining cluster sector
;*****************************************************************************
fatDir:

	; test for root dir
		tst		R0
		brne	fatDir0
		tst		R1
		brne	fatDir0
	; root directory
		lds		R0, RootDirSector
		lds		R1, RootDirSector+1
		lds		R2, RootDirSector+2
		lds		R3, RootDirSector+3
		tst		R7
		brne	fatDir00
		tst		R6
		brne	fatDir00
		tst		R5
		brne	fatDir00
		mov		i,	R4
		cpi		i, 0x20
		brcs	fatDir05
fatDir00:
		call	fatClrR0
		ret
fatDir05:
		add		R0,	R4
		adc		R1,	R5
		adc		R2,	R6
		adc		R3,	R7
		ldi		i, 0x00
		call	atareadsectors
		ret

	; non-root directory
fatDir0:
		movw	R12, R4
		movw	R14, R6
		lds		i, SectorsPerCluster
fatDir1:
		cpi		i, 0x01
		breq	fatDir2
		lsr		R15
		ror		R14
		ror		R13
		ror		R12
		lsr		i
		rjmp	fatDir1
fatDir2:
		tst		R12
		brne	fatDir3
		tst		R13
		brne	fatDir3
		tst		R14
		brne	fatDir3
		tst		R15
		breq	fatDir5
fatdir3:
		call	fatNextCluster 		; i,R0-R3,R8-R9,X
		tst		R0	
		brne	fatDir4
		tst		R1
		brne	fatDir4
		ret
fatDir4:
		ldi		i, 0x01
		sub		R12, i
		ldi		i, 0x00
		sbc		R13, i
		sbc		R14, i
		sbc		R15, i
		brne	fatdir3
fatDir5:
		call	fatClustToSect		; i,R0-R3
		lds		i, SectorsPerCluster
		dec		i
		and		i,	R4
		add		R0,	i
		ldi		i,  0x00
		adc		R1,	i
;		ldi		i, 0x00
		call	atareadsectors
		ret

;*****************************************************************************
; return the direntry struct filled out with the file info from the File Handle table
; Uses R0-R3, i,l, X, Y
;*****************************************************************************
fatLoadFileInfo:

		lds		R0, desDirEntSector
		lds		R1, desDirEntSector+1
		lds		R2, desDirEntSector+2
		lds		R3, desDirEntSector+3
		ldi		i,	0x00
		call	ataReadSectors
		lds		XL,	desDirEntpos
		lds		XH,	desDirEntpos+1
		ldi		YL,	low(desName)
		ldi		YH,	high(desName)
		ldi		l,	DIRENTRY_SIZE
fatLoadFileInfo1:
		ld		i,	X+
		st		Y+,	i
		dec		l
		brne	fatLoadFileInfo1
		ret

;*****************************************************************************
; search directory for matching filename
; return the direntry struct filled out with the file info or 0 if not found
; Uses R0-R9,i,j,k,l, X, Y
;*****************************************************************************
fatGetFileInfo:	

		call	fatNormalize
		lds		R0, currentDirCluster
		lds		R1, currentDirCluster+1

fatGetFileInfo1:

		clr		R4							; sector counter inside each cluster
		lds		R5, SectorsPerCluster
	; if cluster=0 (root dir), load 32 sectors (512 dir entries hard coded)
		tst		R0
		brne	fatGetFileInfo2
		tst		R1
		brne	fatGetFileInfo2
		ldi		i,	0x20
		mov		R5,	i
fatGetFileInfo2:
		movw	R8,	 R0						; save DirCluster
		call	fatClustToSect
		mov		i,	R4
		call	fatIncR0
;		ldi		i,	0x00
		call	ataReadSectors
		ldi		YL, low(fat_buffer)
		ldi		YH, high(fat_buffer)
		ldi		k, FAT_DIRENTRIES_PER_SECTOR ; loop counter

fatGetFileInfo3:
		ld		i,	Y
		cpi		i, 	SLOT_EMPTY
		brne	fatGetFileInfo4
		jmp		fatGetFileInfo99 			;->done

fatGetFileInfo4:
		cpi		i, SLOT_DELETED
		breq	fatGetFileInfo8				; no match, get next entry
		ldd		i, Y+ deAttrib
		cpi		i,	ATTR_LONG_FILENAME
		breq	fatGetFileInfo8				; no match, get next entry
		ldi		XL,	low(FileName)
		ldi		XH,	high(FileName)
		ldi		l,	0x0B
		push	YL
		push	YH							; save pointer in buffer

fatGetFileInfo5:
		ld		i,	Y+
		ld		j,	X+
		cp		i,	j
		brne	fatGetFileInfo7
		dec		l
		brne	fatGetFileInfo5

		pop		YH							; match found!
		pop		YL
		ldi		XL,	low(desName)
		ldi		XH,	high(desName)
		ldi		l,	DIRENTRY_SIZE
		sts		desDirEntpos, YL			; save pointer to dir struct in buffer1
		sts		desDirEntpos+1, YH
		sts		desDirEntSector, R0			; save dir entry sector
		sts		desDirEntSector+1, R1
		sts		desDirEntSector+2, R2
		sts		desDirEntSector+3, R3
fatGetFileInfo6:
		ld		i,	Y+						; move dir entry into des structure
		st		X+,	i						; and return
		dec		l
		brne	fatGetFileInfo6
		ser		i
		ret
fatGetFileInfo7:
		pop		YH
		pop		YL							; restore pointer

fatGetFileInfo8:							; get next entry
		adiw	Y, DIRENTRY_SIZE
		dec		k							; test if # dir entries per sector done
		brne	fatGetFileInfo3				; if not, get next entry from sector

		movw	R0,	R8						; restore DirCluster
		inc		R4							; next sector
		cp		R5, R4						; past last sector in cluster?
		breq	fatGetFileInfo9				; yes
		jmp		fatGetFileInfo2				; no

fatGetFileInfo9:
	; if root directory, we're done
		tst		R0
		brne	fatGetFileInfo92
		tst		R1
		brne	fatGetFileInfo92
fatGetFileInfo99:
		ldi		i, 0x00
		sts		desName, i					;	return NULL
		ret

fatGetFileInfo92:
		call	fatNextCluster		; Uses i,R0-R3,R6-R7,X
		tst		R0
		brne	fatGetFileInfo94
		tst		R1
		breq	fatGetFileInfo99
fatGetFileInfo94:
		jmp		fatGetFileInfo1


;*****************************************************************************
; Uses: R0-R9,i,j,k,l, X, Y
; Change the current directory. Only one level at a time, or use / for root dir.
;*****************************************************************************
fatCddir:
		call	fatGetFileInfo		; R0-R9,i,j,k,l, X, Y
		lds		i, desName
		tst		i					; match found?
		breq	fatCddir2			; nos
		lds		i,	desAttrib
		andi	i,	ATTR_DIRECTORY
		breq	fatCddir3			; not a DIR entry
		lds		i,	desStartCluster
		lds		j,	desStartCluster+1
		sts		currentDirCluster  ,	i
		sts		currentDirCluster+1,	j
		ldi		i, 0x00				; successful
		ret

fatCddir2:
        lds     i, filename         ; check for root request
        cpi     i, '/'
		breq    fatCddir4
		ldi		i, 0x04				; file not found
		ret

fatCddir3:
		ldi		i, 0x06				; invalid file name
		ret

fatCddir4:
		ldi		i, 0x00		     	; root directory
		sts		CurrentDirCluster, i
		sts		CurrentDirCluster+1, i
		ldi		i, 0x00				; successful
		ret


;*****************************************************************************
; Returns: TRUE if the path was created, otherwise FALSE in i
; Uses: R0-R9,R12-R13,i,j,k,l, X, Y, Z
; Description: Create a new directory on the current directory
;*****************************************************************************
fatMkdir:	; tested good
		call	fatGetFileInfo
		lds		i,	desName
		cpi		i,	0x00			; if the file already exists, return error
		breq	fatMkdir1			; not found
fatMkdir0:							; found
		ldi		i, 0x05				; return FALSE;
		ret
fatMkdir1:
	; Find a free direntry, returns a pointer to the direntry struct inside SectorBuffer,
		lds		R0,	currentDirCluster
		lds		R1,	currentDirCluster+1
		call	fatNextFreeDirEntry			; 
		cpi		XL,	0x00
		brne	fatMkdir4
		cpi		XH,	0x00
		brne	fatMkdir4
		ret						; return with error in i

	; at this point we have a direntry in SectorBuffer, and des points to the address of the informations about the new directory
fatMkdir4:
;		clr		R0
;		clr		R1
		call	fatNextFreeCluster
		tst		R0
		brne	fatMkdir5
		tst		R1
		brne	fatMkdir5			; no free clusters disk full!
		ret

fatMkdir5:
		movw		R14, R0			; save cluster #

		ldi		XL, low(Filename)
		ldi		XH, high(Filename)
		ldi		YL, low(desName)
		ldi		YH, high(desName)
		ldi		j,	0x0B
fatMkdir6:
		ld		i, X+
		st		Y+, i
		dec		j
		brne	fatMkdir6

		call	fatGetCurTime

		ldi		i,	ATTR_DIRECTORY
		sts		desAttrib, i
		ldi		i,	0x00
		sts		desLowerCase, i
		ldi		i,	0x00
		sts		desCHundredth, i

		lds		i,	sysTime
		lds		j,	sysTime+1
		sts		desCTime, i
		sts		desCTime+1, j

		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desCDate, i
		sts		desCDate+1, j

		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desADate, i
		sts		desADate+1, j

		lds		i,	sysTime
		lds		j,	sysTime+1
		sts		desMTime, i
		sts		desMTime+1, j

		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desMDate, i
		sts		desMDate+1, j

		sts		desStartCluster, R14
		sts		desStartCluster+1, R15

		ldi		i,	0x00
		sts		desHighClust, i
		sts		desHighClust+1, i

		ldi		i, 0x00
		sts		desFileSize, i
		sts		desFileSize+1, i
		sts		desFileSize+2, i
		sts		desFileSize+3, i

		lds		XL, desDirEntpos
		lds		XH, desDirEntpos+1
		ldi		YL, low(desName)
		ldi		YH, high(desName)
		ldi		j,	DIRENTRY_SIZE
fatMkdir7:
		ld		i,	Y+
		st		X+, i
		dec		j
		brne	fatMkdir7

		lds		R0,	desDirEntSector
		lds		R1,	desDirEntSector+1
		lds		R2,	desDirEntSector+2
		lds		R3,	desDirEntSector+3
		ldi		i,	0x00			; use buffer1
		call	ataWriteSectors

; create the files "." and ".."
		ldi		XL,	low(fat_buffer)
		ldi		XH,	high(fat_buffer)

		ldi		i,	'.'
		sts		desName, i
		ldi		i,	' '
		sts		desName+1, i
		sts		desName+2, i
		sts		desName+3, i
		sts		desName+4, i
		sts		desName+5, i
		sts		desName+6, i
		sts		desName+7, i
		sts		desName+8, i
		sts		desName+9, i
		sts		desName+10, i

		ldi		YL,	low(desName)
		ldi		YH,	high(desName)
		ldi		j,	DIRENTRY_SIZE
fatMkdir8:
		ld		i,	Y+
		st		X+,	i
		dec		j
		brne	fatMkdir8

		lds		R0,	desStartCluster
		lds		R1,	desStartCluster+1
		movw	R4,	R0					; save cluster
		ldi		i,	'.'
		sts		desName+1,	i

		lds		i,	currentDirCluster
		lds		j,	currentDirCluster+1
		sts		desStartCluster, i
		sts		desStartCluster+1, j

		ldi		YL,	low(desName)
		ldi		YH,	high(desName)
		ldi		j,	DIRENTRY_SIZE
fatMkdir9:
		ld		i,	Y+
		st		X+,	i
		dec		j
		brne	fatMkdir9

		ldi		YL, low(BYTES_PER_SECTOR-(2*DIRENTRY_SIZE))
		ldi		YH, high(BYTES_PER_SECTOR-(2*DIRENTRY_SIZE))
		ldi		i,	0x00
fatMkdir10:
		st		X+,	i
		sbiw	YL,	0x01
		brne	fatMkdir10

		call	fatClustToSect		; i, R0-R3
		ldi		i,	0x00		;	use fat_buffer1
		call	ataWriteSectors

		lds		l,	SectorsPerCluster
		dec		l
		breq	fatMkdir13

		ldi		XL, low(fat_buffer)
		ldi		XH, high(fat_buffer)
		ldi		YL, low(BYTES_PER_SECTOR)
		ldi		YH, high(BYTES_PER_SECTOR)
		ldi		i,	0x00
fatMkdir11:
		st		X+,	i
		sbiw	YL,	0x01
		brne	fatMkdir11

fatMkdir12:
		ldi		i,	0x01
		call	fatIncR0
;		ldi		i,	0x00	; use fat_buffer1
		call	ataWriteSectors
		dec		l
		brne	fatMkdir12

fatMkdir13:
		sts		fat_inbuf1,   R0
		sts		fat_inbuf1+1, R1
		sts		fat_inbuf1+2, R2
		sts		fat_inbuf1+3, R3
		movw	R0,	R4			; restore cluster
		call	fatWriteEOC
		ldi		i,	0x00		;	return TRUE;
		ret


;*****************************************************************************
; Create a file and open it in the current directory
;*****************************************************************************
fatFcreate:   

		call	fatGetFileInfo
		lds		i,	desName
		tst		i
		breq	fatFcreate1
fatFcreate0:
		ldi		i, 0x00
		ret
fatFcreate1: 	;(called from HostPrOF)
		lds		R0,	currentDirCluster
		lds		R1,	currentDirCluster+1
		call	fatNextFreeDirEntry
		cpi		XL,	0x00
		brne	fatFcreate15
		cpi		XH,	0x00
		breq	fatFcreate0

fatFcreate15:
		call	fatNextFreeCluster
		tst		R0
		brne	fatFcreate2
		tst		R1
		breq	fatFcreate0
fatFcreate2:
		movw	R14, R0				; save new cluster
		ldi		XL, low(Filename)
		ldi		XH, high(Filename)
		ldi		YL, low(desName)
		ldi		YH, high(desName)
		ldi		j,	0x0B
fatFcreate5:
		ld		i, X+
		st		Y+, i
		dec		j
		brne	fatFcreate5
		call	fatGetCurTime
		ldi		i,	ATTR_ARCHIVE
		sts		desAttrib, i
		ldi		i,	0x00
		sts		desLowerCase, i
		ldi		i,	0x00
		sts		desCHundredth, i
		lds		i,	sysTime
		lds		j,	sysTime+1
		sts		desCTime, i
		sts		desCTime+1, j
		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desCDate, i
		sts		desCDate+1, j
		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desADate, i
		sts		desADate+1, j
		lds		i,	sysTime
		lds		j,	sysTime+1
		sts		desMTime, i
		sts		desMTime+1, j
		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desMDate, i
		sts		desMDate+1, j

		sts		desStartCluster, R14
		sts		desStartCluster+1, R15

		ldi		i,	0x00
		sts		desHighClust, i
		sts		desHighClust+1, i

		ldi		i, 0x00
		sts		desFileSize, i
		sts		desFileSize+1, i
		sts		desFileSize+2, i
		sts		desFileSize+3, i

		lds		XL, desDirEntpos
		lds		XH, desDirEntpos+1
		ldi		YL, low(desName)
		ldi		YH, high(desName)
		ldi		j,	DIRENTRY_SIZE
fatFcreate6:
		ld		i,	Y+
		st		X+, i
		dec		j
		brne	fatFcreate6

		lds		R0,	desDirEntSector
		lds		R1,	desDirEntSector+1
		lds		R2,	desDirEntSector+2
		lds		R3,	desDirEntSector+3
		ldi		i,	0x00			; use buffer1
		call	ataWriteSectors
		movw	R0,	R14
		call	fatWriteEOC
		call	fatFopen1
		ret


;*****************************************************************************
; Change the name of a directory or file
;*****************************************************************************
fatRename:
		ldi		XL,	low(FileName)
		ldi		XH,	high(FileName)
		ldi		YL,	low(OldFileName)
		ldi		YH,	high(OldFileName)		; get newfilename
		ldi		ZL,	low(NewFileName)
		ldi		ZH,	high(NewFileName)
		ldi		j, 0x0b
fatRename1:
		ld		i,	X
		st		Y+, i
		ld		i,	Z+
		st		X+, i
		dec		j
		brne	fatRename1
		call	fatGetFileInfo
		lds		i,	desName
		tst		i
		breq	fatRename2					; if new file exists, error
		ldi		i,	0x05
		ret

fatRename2:
		ldi		XL,	low(OldFileName)
		ldi		XH,	high(OldFileName)
		ldi		YL,	low(FileName)
		ldi		YH,	high(FileName)
		ldi		ZL,	low(NewFileName)
		ldi		ZH,	high(NewFileName)
		ldi		j, 0x0b
fatRename3:
		ld		i,	Y			; save normalized newFileName
		st		Z+, i
		ld		i,	X+			; get oldfilename
		st		Y+, i
		dec		j
		brne	fatRename3
		call	fatGetFileInfo
		lds		i,	desName
		tst		i
		breq	fatRename35		; old file not found
		cpi		i,	'.'
		breq	fatRename36
    	lds     i, desAttrib
		andi	i,  ATTR_READONLY
    	breq    fatRename4

fatRename34:					; return error file locked
		ldi		i,	0x0A
		ret

fatRename35:					; return error file not found
		ldi		i,	0x04
		ret

fatRename36:					; return error invalid file name
		ldi		i,	0x06
		ret

fatRename4:						; update file name in sector
    	lds     i, desAttrib
		andi	i,  ATTR_VOLUME
		breq	fatRename45

		ldi		XL,	low(Volname)
		ldi		XH,	high(Volname)
		ldi		YL,	low(NewFileName)
		ldi		YH,	high(NewFileName)
		ldi		j, 0x0b
fatRename44:
		ld		i,	Y+			; save normalized newFileName
		st		X+, i			; in vol label
		dec		j
		brne	fatRename44

fatRename45:	
		lds		XL,	desDirEntpos
		lds		XH,	desDirEntpos+1
		ldi		YL,	low(NewFileName)
		ldi		YH,	high(NewFileName)
		ldi		j, 0x0b

fatRename5:
		ld		i,	Y+			; save normalized newFileName
		st		X+, i			; in Dir Structure
		dec		j
		brne	fatRename5

		call	fatGetCurTime	; update file modified date and time
		adiw	X,	0x0b		; move pointer forward to modify date & time
		lds		i,	sysTime
		lds		j,	sysTime+1
		st		X+, i
		st		X+, j
		lds		i,	sysDate
		lds		j,	sysDate+1
		st		X+, i
		st		X, j

		lds		R0, desDirEntSector
		lds		R1, desDirEntSector+1
		lds		R2, desDirEntSector+2
		lds		R3, desDirEntSector+3
		ldi		i,	0x00
		call	ataWriteSectors		; save back to drive
		ldi		i,	0x00
		ret


;*****************************************************************************
; Uses: i, R0-R5, R12-R15, Y
; remove a file or directory
;*****************************************************************************
fatRemove:

		call	fatGetFileInfo
		lds		i, desName
		tst		i
		brne	fatRemove1
		ldi		i, 0x04		ret
fatRemove1:  ;called from FatRemoveAll

		cpi		i,	'.'
		breq	fatremove15
		lds		R12,  fat_inbuf1
		lds		R13,  fat_inbuf1+1
		lds		R14,  fat_inbuf1+2
		lds		R15,  fat_inbuf1+3

		lds		R0,	desStartCluster
		lds		R1,	desStartCluster+1
		lds		i,	desAttrib
		cpi		i,	ATTR_VOLUME
		breq	fatremove4
		cpi		i,	ATTR_DIRECTORY
		brne	fatRemove2
		call	fatDirectoryIsEmpty
		tst		i
		brne	fatRemove2
		movw	R0, R12
		movw	R2, R14
		ldi		i,	0x00
		call	ataReadSectors
		ldi		i,	0x07
		ret
fatremove15:
		ldi		i,	0x07
		ret

fatremove2:
		movw	R0, R12
		movw	R2, R14
		ldi		i,	0x00
		call	ataReadSectors
		lds		YL, desDirEntpos
		lds		YH, desDirEntpos+1
		ldi		i,	SLOT_DELETED
		st		Y,	i
		ldi		i,	0x00
		call	ataWriteSectors
		lds		R0,	desStartCluster
		lds		R1,	desStartCluster+1
		
fatremove3:
		movw	R12, R0
		call	fatNextCluster
		movw	R14, R0
		movw	R0,	R12
		clr		R4
		clr		R5			; CLUST_FREE=0
		call	fatWrite
		movw	R0, R14
		tst		R0
		brne	fatremove3
		tst		R1
		brne	fatremove3
fatremove4:
		ldi		i, 0x00
		ret


;*****************************************************************************
; Open a file to read and/or write.
;*****************************************************************************
fatFopen:
		call	fatGetFileInfo
		lds		i, desName
		tst		i
		breq	fatFopen0
		lds		i, desAttrib
		cpi		i,	ATTR_VOLUME
		breq	fatFopen0
		cpi		i,	ATTR_DIRECTORY
		brne	fatFopen1

fatFopen0: ; ERROR
		ldi		i,	0x00
		ret
fatFopen1: ; called from fatFCreate
		lds		R0, desStartCluster
		lds		R1, desStartCluster+1
		call	fatClustToSect
		sts		descurrentSector, R0
		sts		descurrentSector+1, R1
		sts		descurrentSector+2, R2
		sts		descurrentSector+3, R3
		lds		i,	desFileSize
		sts		desFileLength, i
		lds		i,	desFileSize+1
		sts		desFileLength+1, i
		lds		i,	desFileSize+2
		sts		desFileLength+2, i
		lds		i,	desFileSize+3
		sts		desFileLength+3, i

		ldi		i, 0x00
		sts		desbytePointer, i
		sts		desbytePointer+1, i
		sts		desbytePointer+2, i
		sts		desbytePointer+3, i
		sts		dessectorHasChanged, i
		ser		i
		ret


;*****************************************************************************
; close file from further read/write - update file size and date stamp
;*****************************************************************************
fatFclose:

		lds		i,	desFileLength
		sts		desFilesize, i
		lds		i,	desFileLength+1
		sts		desFilesize+1, i
		lds		i,	desFileLength+2
		sts		desFilesize+2, i
		lds		i,	desFileLength+3
		sts		desFilesize+3, i
fatFcloseP:							; Called from HostProtect/HostUnprotect
		call	fatGetCurTime
		lds		i,	sysTime
		lds		j,	sysTime+1
		sts		desMTime, i
		sts		desMTime+1, j
		lds		i,	sysDate
		lds		j,	sysDate+1
		sts		desMDate, i
		sts		desMDate+1, j
		sts		desADate, i
		sts		desADate+1, j

		lds		R0, desDirEntSector
		lds		R1, desDirEntSector+1
		lds		R2, desDirEntSector+2
		lds		R3, desDirEntSector+3
		ldi		i, 0x00
		call	ataReadSectors

		lds		XL, desDirEntpos
		lds		XH, desDirEntpos+1
		ldi		YL, low(desName)
		ldi		YH, high(desName)
		ldi		j,	DIRENTRY_SIZE
fatFclose1:
		ld		i,	Y+
		st		X+, i
		dec		j
		brne	fatFclose1
		ldi		i, 0x00
		call	ataWriteSectors
		ret


;*****************************************************************************
; write current sector file to hard disk if necessary
;*****************************************************************************
fatFflush:
			lds		i,	dessectorHasChanged
			tst		i
			breq	fatFflush1
			lds		R0,	descurrentSector
			lds		R1,	descurrentSector+1
			lds		R2,	descurrentSector+2
			lds		R3,	descurrentSector+3
			ldi		i, 0x00				; select Fat_buffer
			call	ataWriteSectors
			ldi		i, 0x00
			sts		dessectorHasChanged, i
fatFflush1:
			ret


;*****************************************************************************
; Assumes Current Sector has been saved before relocating to new sector!!!
; Find a byte position in the file and load the corresponded sector in buffer
;    Modes: SEEK_CUR: from the current position of the file pointer;
;           SEEK_END: from the end of the file (write mode only) 
;           SEEK_SET: from the beginning of the file
;*****************************************************************************
fatFseek:
		cpi		i, SEEK_SET
		breq	fatFseek34

		cpi		i, SEEK_CUR
		breq	fatFseek25

		cpi		i, SEEK_END
		breq	fatFseek2

		ldi		i, 0x0D					; INVALID COMMAND
		ret

fatFseek2:								; SEEK_END (end of file)
		lds		R4, desFileLength	
		lds		R5, desFileLength+1
		lds		R6, desFileLength+2	
		lds		R7, desFileLength+3	
		rjmp	fatFseek28

fatFseek25:								; SEEK_CUR (current pos)
		lds		R4, desBytePointer
		lds		R5, desBytePointer+1
		lds		R6, desBytePointer+2
		lds		R7, desBytePointer+3
fatFseek28:
		add		R4, R0
		adc		R5, R1
		adc		R6, R2
		adc		R7, R3
		brcc	fatFseek4				; no carry, all is good, else fall thru to error
fatFseek3:
		ldi		i, 0x10					; File too large > 2^32
		ret


fatFseek34:								; SEEK_SET (from beginning)
		movw	R4, R0
		movw	R6, R2

fatFseek4:								; common entry with new file pos calculated
		lds		R0, desFileLength	
		lds		R1, desFileLength+1
		lds		R2, desFileLength+2	
		lds		R3, desFileLength+3	
		cp		R0, R4
		cpc		R1,	R5
		cpc		R2,	R6
		cpc		R3,	R7
		brcc	fatFseek42				; Pointer lower than file length
		lds		i, desFileMode
		cpi		i,	'R'
		brne	fatFseek41
		ldi		i, 0x0F					; read past EOF
		ret

fatFseek41:								; pointer is greater than length
		sts		desBytePointer, R0    
		sts		desBytePointer+1, R1
		sts		desBytePointer+2, R2
		sts		desBytePointer+3, R3
		call	fatFflush
		push	R4
		push	R5
		push	R6
		push	R7
		call	fatFseek44			; move to end of file
		pop		R7
		pop		R6
		pop		R5
		pop		R4

fatFseek412:
		push	R4
		push	R5
		push	R6
		push	R7

		ldi		i, 0x00					; null chr
		call	fatFputc				; add chr to end of file, adjusts pointer and length

		lds		R0, desBytePointer
		lds		R1, desBytePointer+1
		lds		R2, desBytePointer+2
		lds		R3, desBytePointer+3
		pop		R7						; target
		pop		R6
		pop		R5
		pop		R4
		cp		R4, R0
		cpc		R5,	R1
		cpc		R6,	R2
		cpc		R7,	R3
		brcc	fatFseek412				; not there yet, add another
		ldi		i, 0x00
		ret

fatFseek42:								; set pointer and move to proper sector
		sts		desBytePointer, R4
		sts		desBytePointer+1, R5
		sts		desBytePointer+2, R6
		sts		desBytePointer+3, R7

fatFseek44:

		call	fatFflush
										; calculate the current file cluster
		lds		R0, desStartCluster
		lds		R1, desStartCluster+1
		mov		R4, R5
		mov		R5, R6
		mov		R6, R7
		clr		R7
		lsr		R6
		ror		R5
		ror		R4						; pointer/512
		lds		i, SectorsPerCluster
		mov		j,	i
		dec		j
		and		j,	R4
		push	j						; pointer/512 mod SectorsPerCluster
fatFseek5:
		cpi		i, 0x01
		breq	fatFseek6
		lsr		R6
		ror		R5
		ror		R4
		lsr		i						; pointer/512/SectorsPerCluster
		rjmp	fatFseek5

fatFseek55:
        pop     i						; fix stack
		ldi		i,	0x11                 ; cluster size too big?
		ret

fatFseek6:
		tst		R7
		brne	fatFseek55
		tst		R6
		brne	fatFseek55
		tst		R5
		brne	fatFseek65
		tst		R4
		breq	fatFseek68

fatFseek65:
		call	fatNextCluster		;i, R0-R3,R8-R9, X
		ldi		i, 0x01
		sub		R4, i
		ldi		i, 0x00
		sbc		R5, i
		sbc		R6, i
		sbc		R7, i
		brne	fatFseek65

fatFseek68:
		call	fatClustToSect
		pop		i
		add		R0, i
		ldi		i, 0x00
		adc		R1, i
		adc		R2, i
		adc		R3, i
		sts		desCurrentSector, R0
		sts		desCurrentSector+1, R1
		sts		desCurrentSector+2, R2
		sts		desCurrentSector+3, R3
;		ldi		i, 0x00
		call	ataReadSectors
		ldi		i, 0x00
		ret


;*****************************************************************************
; Uses i,j, R12-R15, X
; Description: Get the next character from file and update file pointer
;*****************************************************************************
fatFgetc:
		lds		R0, desCurrentSector
		lds		R1, desCurrentSector+1
		lds		R2, desCurrentSector+2
		lds		R3, desCurrentSector+3
		ldi		i,	0x00
		call	ataReadSectors

fatFgetc05:
		call	fatFeof
		tst		i
		breq	fatFgetc1
fatFgetc0:
		ldi		i, 0x00		; chr value
		ldi		j, 0xff		; eof flag
		ret

fatFgetc1:
		lds		XL, desBytePointer
		lds		XH, desBytePointer+1
		andi	XH, 0x01
		lds		R12, desBytePointer
		lds		R13, desBytePointer+1
		lds		R14, desBytePointer+2
		lds		R15, desBytePointer+3
		ldi		i, 0x01
		ldi		j ,0x00
		add		R12, i
		adc		R13, j
		adc		R14, j
		adc		R15, j
		sts		desBytePointer, R12
		sts		desBytePointer+1, R13
		sts		desBytePointer+2, R14
		sts		desBytePointer+3, R15

		tst		XL
		brne	fatFgetc2
		tst		XH
		brne	fatFgetc2
		cp		R12, i
		brne	fatFgetc3
		cp		R13, j
		brne	fatFgetc3
		cp		R14, j
		brne	fatFgetc3
		cp		R15, j
		brne	fatFgetc3

fatFgetc2:
		ldi		i, low(fat_buffer)
		ldi		j, high(fat_buffer)
		add		XL, i
		adc		XH, j
		ld		i, X
		clr		j
		ret

fatFgetc3:
		push	XL			; X always zero here?
		push	XH			; save bufferpointer
		lds		R0, desCurrentSector
		lds		R1, desCurrentSector+1
		lds		R2, desCurrentSector+2
		lds		R3, desCurrentSector+3
		movw	R8, R0
		movw	R10, R2
		call	fatSectToClust
		movw	R4, R0
		ldi		i, 0x01
		ldi		j, 0x00
		add		R8, i
		adc		R9, j
		adc		R10, j
		adc		R11, j
		movw	R0, R8
		movw	R2, R10
		call	fatSectToClust
		cp		R0, R4
		brne	fatFgetc5
		cp		R1, R5
		brne	fatFgetc5
		sts		descurrentSector, R8
		sts		descurrentSector+1, R9
		sts		descurrentSector+2, R10
		sts		descurrentSector+3, R11
		movw	R0, R8
		movw	R2, R10
		rjmp	fatFgetc7

fatFgetc5:
		movw	R0, R4
		call	fatNextCluster
		tst		R0
		brne	fatFgetc6
		tst		R1
		brne	fatFgetc6
		pop		i
		pop		i					; pull pushed X data
		rjmp	fatFgetc0			; no next cluster - return error		

fatFgetc6:
		call	fatClustToSect
		sts		descurrentSector, R0
		sts		descurrentSector+1, R1
		sts		descurrentSector+2, R2
		sts		descurrentSector+3, R3

fatFgetc7:
		ldi		i, 0x00
		call	ataReadSectors
		pop		XH
		pop		XL
		rjmp	fatFgetc2


;*****************************************************************************
; Write a character to the file
;*****************************************************************************
fatFputc:
		push	i							; save chr to write
		lds		R0, desCurrentSector
		lds		R1, desCurrentSector+1
		lds		R2, desCurrentSector+2
		lds		R3, desCurrentSector+3
		ldi		i,	0x00
		call	ataReadSectors
fatFputc05:
		lds		XL, desBytePointer
		lds		XH, desBytePointer+1
		andi	XH, 0x01
		lds		R12, desBytePointer
		lds		R13, desBytePointer+1
		lds		R14, desBytePointer+2
		lds		R15, desBytePointer+3
		ldi		i, 0x01
		ldi		j ,0x00
		add		R12, i
		adc		R13, j
		adc		R14, j
		adc		R15, j
		sts		desBytePointer, R12
		sts		desBytePointer+1, R13
		sts		desBytePointer+2, R14
		sts		desBytePointer+3, R15

		lds		k, desFileLength
		cp		k, R12
		lds		k, desFileLength+1
		cpc		k, R13
		lds		k, desFileLength+2
		cpc		k, R14
		lds		k, desFileLength+3
		cpc		k, R15
		brcc	fatFputc0					; 
		sts		desFileLength, R12			; update file size
		sts		desFileLength+1, R13
		sts		desFileLength+2, R14
		sts		desFileLength+3, R15

fatFputc0:
		push	XL
		push	XH							; save bufferpointer

		tst		XL
		brne	fatFputc1
		tst		XH
		brne	fatFputc1
		cp		R12, i
		brne	fatFputc2
		cp		R13, j
		brne	fatFputc2
		cp		R14, j
		brne	fatFputc2
		cp		R15, j
		brne	fatFputc2
fatFputc1:									; byte is in the current buffer
		jmp		fatFputc9   
fatFputc2:									; byte is in a different sector
		call	fatFflush		
		lds		R0, desCurrentSector
		lds		R1, desCurrentSector+1
		lds		R2, desCurrentSector+2
		lds		R3, desCurrentSector+3

		movw	R8, R0
		movw	R10, R2
		call	fatSectToClust				; current cluster
		movw	R4, R0
		ldi		i, 0x01
		ldi		j, 0x00
		add		R8, i
		adc		R9, j
		adc		R10, j
		adc		R11, j
		movw	R0, R8
		movw	R2, R10
		call	fatSectToClust				; next cluster
		cp		R0, R4
		brne	fatFputc3
		cp		R1, R5
		brne	fatFputc3
		sts		descurrentSector, R8		; save next sector in current cluster
		sts		descurrentSector+1, R9
		sts		descurrentSector+2, R10
		sts		descurrentSector+3, R11
		movw	R0, R8
		movw	R2, R10
		rjmp	fatFputc4

fatFputc3:  								; go to next cluster
		movw	R0, R4						; current cluster
		call	fatNextCluster
		tst		R0
		brne	fatFputc35
		tst		R1
		breq	fatFputc5		; if last cluster, add one

fatFputc35:
		call	fatClustToSect
		sts		descurrentSector, R0
		sts		descurrentSector+1, R1
		sts		descurrentSector+2, R2
		sts		descurrentSector+3, R3

fatFputc4:									; read the sector
		ldi		i, 0x00
		call	ataReadSectors
		rjmp	fatFputc9					

fatFputc5:									; append new cluster
		movw	R0,	R4						; restore current cluster		
		call	fatAppendCluster
		tst		R0
		brne	fatFputc35
		tst		R1
		brne	fatFputc35
		pop		i							; XH
		pop		i							; XL
		pop		i							; char
		ldi		i,	0x0B
		ret									; error - disk full

fatFputc9:
		ldi		i, low(fat_buffer)
		ldi		j, high(fat_buffer)
		pop		XH
		pop		XL							; save bufferpointer
		add		XL, i
		adc		XH, j
		pop		i							; chr to save
		st		X,  i
		ldi		i, 0xFF					
		sts		dessectorHasChanged, i		; SET TRUE
		ldi		i, 0x00
		ret


;*****************************************************************************
; Uses: i, j
; return TRUE if the byte pointer points to the end of the file
;*****************************************************************************
fatFeof:
			lds		i,	desbytePointer
			lds		j,	desFileLength
			sub		i, j
			lds		i,	desbytePointer+1
			lds		j,	desFileLength+1
			sbc		i, j
			lds		i,	desbytePointer+2
			lds		j,	desFileLength+2
			sbc		i, j
			lds		i,	desbytePointer+3
			lds		j,	desFileLength+3
			sbc		i, j
			clr		i
			brcs	fatFeof1
			ser		i
fatFeof1:
			ret

;*****************************************************************************
; Uses i,j, Y
; normalize the file name. Insert spaces betwen the name and the extension.
; The file name will be 11 caracters
;*****************************************************************************
fatNormalize:   ; Does not validate DOS characters!!!
			ldi		YL, low(fileName)
			ldi		YH, high(fileName)
			ldi		j, 0x00
			lds		i, FileName
			cpi		i, '/'				; ROOT DIR -ignore rest, fill with space and return
			breq    fatNormalize75
			cpi		i, '.'
			brne	fatNormalize6
			adiw	YL, 0x01
			inc		j
			lds		i, FileName+1
			cpi		i, '.'
			brne	fatNormalize8
			adiw	YL, 0x01
			inc		j
			rjmp	fatNormalize8

fatNormalize1:		; get next chr and test
			ld		i, Y
			cpi		i, '.'
			brne	fatNormalize6
			cpi		j, 0x08
			brne	fatNormalize2
			lds		i,	FileName+9		; move ext left one
			sts		FileName+8, i
			lds		i,	FileName+10
			sts		FileName+9,	i
			lds		i,	FileName+11
			sts		FileName+10, i
			rjmp	fatNormalize5
fatNormalize2:
			cpi		j, 0x07				;
			breq	fatNormalize3		; don't move ext, just replace . with space
			ldd		i, Y+3				; move ext right to end
			sts		FileName+10, i
			ldd		i, Y+2
			sts		FileName+9,	i
			ldd		i, Y+1
			sts		FileName+8,	i
fatNormalize3:
			ldi		i, ' '
fatNormalize4:							; fill file name with ' '
			st		Y+, i
			inc		j
			cpi		j, 0x08
			brne	fatNormalize4
fatNormalize5:
			ld		i, Y				; get first chr of extension
fatNormalize6:							; land here to check for 0x00 and check case
			cpi		i, 0x00
			breq	fatNormalize8
			cpi		i, 0x61
			brcs	fatNormalize7
			cpi		i, 0x7b
			brcc	fatNormalize7
			andi	i, 0xDF
fatNormalize7:
			st		Y+, i
			inc		j
			cpi		j, 0x0b
			brne	fatNormalize1
			rjmp	fatNormalize9
fatNormalize75:
			st		Y+, i
fatNormalize8:							; fill rest with ' ' and set end to pos 11
			ldi		i, ' '
			st		Y+, i
			inc		j
			cpi		j, 0x0b
			brne	fatNormalize8
fatNormalize9:
			ldi		i, 0x00
			sts		fileName+11, i
			ret


;*****************************************************************************
; Uses: i,j,k,l,R0-R7, X
; Find a free dir entry in the directory started in cluster address
;*****************************************************************************
fatNextFreeDirEntry: 
			tst		R0
			brne	fatNextFreeDirEntry0
			tst		R1
			brne	fatNextFreeDirEntry0
			;root directory
			ldi		l,	0x20				; root dir has 32 sectors fixed
			rjmp	fatNextFreeDirEntry05

fatNextFreeDirEntry0:
			lds		l,	SectorsPerCluster			; loop counter
fatNextFreeDirEntry05:
			movw	R4,	R0					; save cluster in R4-R5
			call	fatClustToSect			; R0-R3, i
			rjmp	fatNextFreeDirEntry15
fatNextFreeDirEntry1:
			ldi		i, 0x01
			call	fatIncR0		; i,R0-R3
fatNextFreeDirEntry15:
			ldi		i, 0x00
			call	ataReadSectors	; i,j,k,R0-R3,X,Y
			ldi		XL, low(Fat_Buffer)
			ldi		XH, high(Fat_Buffer)
			ldi		k,	FAT_DIRENTRIES_PER_SECTOR   ; 16	loop counter
fatNextFreeDirEntry2:
			ld		i, X
			cpi		i, SLOT_DELETED			; deleted entry ok to use
			breq	fatNextFreeDirEntry4
			cpi		i, 0x00					; last entry, free to use
			breq	fatNextFreeDirEntry4
			adiw	XL,	0x20
			dec		k
			brne	fatNextFreeDirEntry2	; get next entry in sector
			dec		l
			brne	fatNextFreeDirEntry1	; get next sector in cluster

			movw	R0, R4					; Restore cluster
			tst		R0
			brne	fatNextFreeDirEntry3
			tst		R1
			brne	fatNextFreeDirEntry3
			; root dir full!!
			clr		XL
			clr		XH
			ldi		i,	0x0C
			ret

fatNextFreeDirEntry4:		; Free slot found
			rjmp	fatNextFreeDirEntry9
			
fatNextFreeDirEntry3:
			call	fatNextCluster			; Uses i,R0-R3,R8-R9,X
			tst		R0
			brne	fatNextFreeDirEntry0
			tst		R1
			brne	fatNextFreeDirEntry0

		; End of clusters - need to add new cluster
			movw	R0, R4						; Restore last cluster
			call	fatAppendCluster			; i,j,R0-R09,R12-R15,X
			tst		R0
			brne	fatNextFreeDirEntry6
			tst		R1
			brne	fatNextFreeDirEntry6
			clr		XL						; no more clusters, return NULL
			clr		XH
			ldi		i,	0x0B
			ret

fatNextFreeDirEntry6:		; FILL NEW CLUSTER WITH ZEROS
			ldi		XL,	low(fat_buffer)
			ldi		XH,	high(fat_buffer)
			ldi		YL, low(BYTES_PER_SECTOR)
			ldi		YH, high(BYTES_PER_SECTOR)
			ldi		i,	0x00
fatNextFreeDirEntry7:
			st		X+,	i
			sbiw	YL,	0x01
			brne	fatNextFreeDirEntry7
			call	fatClustToSect
			sts		fat_inbuf1, R0
			sts		fat_inbuf1+1, R1
			sts		fat_inbuf1+2, R2
			sts		fat_inbuf1+3, R3
			lds		R4, SectorsPerCluster
			movw	R8, R0
			movw	R10, R2						; save sector
fatNextFreeDirEntry8:
			ldi		i,	0x00					; use atabuffeR1
			call	ataWriteSectors
			ldi		i,	0x01
			call	fatIncR0
			dec		R4
			brne	fatNextFreeDirEntry8
			movw	R0,	R8
			movw	R2,	R10						; restore sector
			ldi		XL,	low(fat_buffer)
			ldi		XH,	high(fat_buffer)
fatNextFreeDirEntry9:
			sts		desDirEntSector, R0			; save new entry pointers
			sts		desDirEntSector+1, R1
			sts		desDirEntSector+2, R2
			sts		desDirEntSector+3, R3
			sts		desDirEntpos, XL
			sts		desDirEntpos+1, XH
			ret


;*****************************************************************************
; Uses: i,j, R0-R3,R8-R9, X
; Returns the first free cluster found in Fat table.
;*****************************************************************************
fatNextFreeCluster:  
		lds		R0,	FirstFATSector
		lds		R1,	FirstFATSector+1
		lds		R2,	FirstFATSector+2
		lds		R3,	FirstFATSector+3
fatNextFreeCluster1:
		ldi		i, 0x01
		call	ataReadSectors
		clr		R8
		clr		R9

fatNextFreeCluster2:
		ldi		XL, low(fat_cache)
		ldi		XH, high(fat_cache)
fatNextFreeCluster25:
		ld		i, X+
		ld		j, X+
		tst		i
		brne	fatNextFreeCluster3   ; cluster used
		tst		j
		breq	fatNextFreeCluster4   ; free cluster found
fatNextFreeCluster3:
		ldi		i, 0x01
		add		R8, i
		ldi		i, 0x00
		adc		R9, i

		ldi		i, FAT16_STRUCTS_PER_SECTOR & 0xFF
		ldi		j, (FAT16_STRUCTS_PER_SECTOR >> 8 ) & 0xFF
		cp		r8, i
		brne	fatNextFreeCluster25
		cp		r9, j
		brne	fatNextFreeCluster25	; next cluster in sector
		
		ldi		i, 0x01					; get next sector
		call	fatIncR0

		lds		i, FirstFAT2Sector
		cp		i, R0
		brne	fatNextFreeCluster1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+1
		cp		i, R1
		brne	fatNextFreeCluster1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+2
		cp		i, R2
		brne	fatNextFreeCluster1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+3
		cp		i, R3
		brne	fatNextFreeCluster1		; if not end of first FAT, do again

		clr		R0
		clr		R1
		ldi		i,	0x0B
		ret			; VOL FULL no more free clusters!!!

fatNextFreeCluster4:
		lds		i, FirstFATSector
		sub		R0, i
		mov		R1, R0		; hard coded mult by 256
		clr		R0
		add		R0, R8
		adc		R1, R9
		ret


;*****************************************************************************
; append new cluster to current cluster chain (dir or file)
;*****************************************************************************
fatAppendCluster: 

		movw	R12, R0								; save start cluster
		call	fatNextFreeCluster					; i,j, R0-R9, X
		tst		R0
		brne	fatAppendCluster2					; 
		tst		R1
		brne	fatAppendCluster2
		clr		R0
		clr		R1
		ret

fatAppendCluster2:
		movw	R14, R0								; save freecluster
		movw	R0,	R12								; find the last cluster of the current chain
		call	fatLastCluster			; i, R0-R9, X
		movw	R4,	R14								; creates a connection between the last cluster of
		call	fatWrite							; the current directory and the new cluster created
		movw	R0,	R14								; mark the new cluster with an END OF CLUSTER mark
		call	fatWriteEOC
		movw	R0,	R14								; return w/new cluster
		ret


;*****************************************************************************
; Write the END OF CLUSTER mark in FAT table
;*****************************************************************************
fatWriteEOC: 

		ldi		i, CLUST_EOFE & 0xFF
		ldi		j, (CLUST_EOFE >>8) & 0xFF
		movw	R4, i
;		call	fatWrite
;		ret
	; FALL THRU TO FATWRITE

;*****************************************************************************
; uses  R0-R5,R8-R9, i, X
; Write the data in FAT in cluster position
;*****************************************************************************
fatWrite: 
		tst		R1				; if cluster = 0 or 1, don't write
		brne	fatWrite0
		mov		i,	R0
		cpi		i, 	0x02
		brcc	fatWrite0
		ret
fatWrite0:
		call	fatTableClustToSect     ;R0-R3, R6-R7, i
		ldi		i, 0x01
		call	ataReadSectors
		ldi		XL, low(fat_cache)
		ldi		XH, high(fat_cache)
		add		XL, R8			; offset
		adc		XH, R9			; offset
		st		X+, R4
		st		X,	R5
		ldi		i, 0x01
		call	ataWriteSectors
		lds		i, NumFats				; if # FATs is 1 were done, else write FAT2
		cpi		i,	0x01
		brne	fatWrite1
		ret
fatWrite1:
		lds		i,	FatSectors
		add		R0, i
		lds		i,	FatSectors + 1
		adc		R1, i
		ldi		i,	0x00
		adc		R2,	i
		adc		R3,	i
		ldi		i, 0x01
		call	ataWriteSectors
		ret


;*****************************************************************************
; Used R0-R3, R8-R9, i
; Calculate the FAT table sector address from the cluster #
;*****************************************************************************
fatTableClustToSect:  

		mov		R8, R0			; put offset in R6-R7
		clr		R9				;
		lsl		R8
		rol		R9	
		mov		R0, R1			; cluster / 256
		clr		R1
		clr		R2
		clr		R3
		lds		i, FirstFatSector	;	cluster += FirstFatSector
		add		R0, i
		lds		i, FirstFatSector+1
		adc		R1, i
		lds		i, FirstFatSector+2
		adc		R2, i
		lds		i, FirstFatSector+3
		adc		R3, i
		ret


;*****************************************************************************
; Uses: i, R0-R9, X
; Find the last cluster of a file in fat table
;*****************************************************************************
fatLastCluster: 
		movw	R4, R0
		call	fatNextCluster			; i,R0-R3,R6-R9,X
		tst		R0
		brne	fatLastCluster
		tst		R1
		brne	fatLastCluster
		movw	R0, R4
		ret


;*****************************************************************************
; Uses: R0-R11, X, i,j
; check to the existance of files in the directory from Cluster in R0, R1
;*****************************************************************************
fatDirectoryIsEmpty:  
		movw	R4,	R0
		call	fatClustToSect
		clr		R6
		lds		R7, SectorsPerCluster
		rjmp	fatDirectoryIsEmpty15
fatDirectoryIsEmpty1:
		call	fatIncR0
fatDirectoryIsEmpty15:
		ldi		i, 	0x00
		call	ataReadSectors
		ldi		XL, low(fat_buffer)
		ldi		XH, high(fat_buffer)
		ldi		j, FAT_DIRENTRIES_PER_SECTOR
fatDirectoryIsEmpty2:
		ld		i, X
		cpi		i, '.'
		breq	fatDirectoryIsEmpty3
		cpi		i, SLOT_EMPTY
		breq	fatDirectoryIsEmpty4
		cpi		i, SLOT_DELETED
		brne	fatDirectoryIsEmpty5
fatDirectoryIsEmpty3:
		adiw	X, DIRENTRY_SIZE		; 32
		dec		j
		brne	fatDirectoryIsEmpty2

		inc		R6
		cp		R6, R7
		brne	fatDirectoryIsEmpty1
		movw	R0,	R4
		call	fatNextCluster
		tst		R0
		brne	fatDirectoryIsEmpty
		tst		R1
		brne	fatDirectoryIsEmpty
fatDirectoryIsEmpty4:
		ldi		i,  0x01		;true
		ret

fatDirectoryIsEmpty5:
		ldi		i,  0x00		; false
		ret


;*****************************************************************************
; Remove all files in currentDirCluster
;*****************************************************************************
fatRemoveAll: 
		clr		R4
		clr		R5
		clr		R6
		clr		R7
		ldi		m, 0x00

fatRemoveAll1:
; get next dir sector
		lds		R0,	currentDirCluster
		lds		R1,	currentDirCluster+1
		call	fatDir
		tst		R0
		brne	fatRemoveAll3
		tst		R1
		brne	fatRemoveAll3

;fatRemoveAll2:
		rjmp	fatRemoveAll8

fatRemoveAll3:
		push	R4
		push	R5
		push	R6
		push	R7			 ;save offset
		ldi		j,	FAT_DIRENTRIES_PER_SECTOR		; 16
		ldi		YL,	low(fat_buffer)
		ldi		YH,	high(fat_buffer)
		
fatRemoveAll4:
; loop thru each dir entry
		push	j
		push	YL
		push	YH
		ld		i,	Y
		tst		i
		breq	fatRemoveAll7
		cpi		i,	SLOT_DELETED
		breq	fatRemoveAll6			

		ldi		XL,	low(desName)
		ldi		XH,	high(desName)
		ldi		l,	DIRENTRY_SIZE
		sts		desDirEntpos, YL			; save pointer to dir struct in buffer1
		sts		desDirEntpos+1, YH
		sts		desDirEntSector, R0			; save dir entry sector
		sts		desDirEntSector+1, R1
		sts		desDirEntSector+2, R2
		sts		desDirEntSector+3, R3

fatRemoveAll5:
		ld		i,	Y+						; move dir entry into des structure
		st		X+,	i						; 
		dec		l
		brne	fatRemoveAll5
		lds		i, desName
		call	fatRemove1
		cpi		i, 0x00
		breq	fatRemoveAll6
		ldi		m, 0x07

fatRemoveAll6:
		pop		YH
		pop		YL
		adiw	YL, DIRENTRY_SIZE
		pop		j
		dec		j
		brne	fatRemoveAll4

		pop		R7
		pop		R6
		pop		R5
		pop		R4
		ldi		i,	0x01
		ldi		j,	0x00
		add		R4, i
		adc		R5, j
		adc		R6, j
		adc		R7, j
		rjmp	fatRemoveAll1

fatRemoveAll7:
		pop		YH
		pop		YL
		pop		j
		pop		R7
		pop		R6
		pop		R5
		pop		R4
fatRemoveAll8:
		mov		i, m
		ret

;*****************************************************************************
; Uses: i,j, R0-R3,R8-R9,R10-R13 X
; Count free clusters on current drive
;*****************************************************************************
fatFreeClusters:	
		ldi		i, 0x00
		mov		R10, i
		mov		R11, i; cluster counter

fatFreeClusters0:	
		lds		R0,	FirstFATSector
		lds		R1,	FirstFATSector+1
		lds		R2,	FirstFATSector+2
		lds		R3,	FirstFATSector+3

fatFreeClusters1:
		ldi		i, 0x01
		call	ataReadSectors
		clr		R8
		clr		R9

;fatFreeClusters2:
		ldi		XL, low(fat_cache)
		ldi		XH, high(fat_cache)

fatFreeClusters25:
		ld		i, X+
		ld		j, X+
		tst		i
		brne	fatFreeClusters3   ; cluster used
		tst		j
		brne	fatFreeClusters3   ; 
		ldi		i, 0x01				; free cluster, inc counter
		add		R10, i
		ldi		i, 0x00
		adc		R11, i

fatFreeClusters3:
		ldi		i, 0x01
		add		R8, i
		ldi		i, 0x00
		adc		R9, i

		ldi		i, FAT16_STRUCTS_PER_SECTOR & 0xFF
		cp		r8, i
		brne	fatFreeClusters25
		ldi		j, (FAT16_STRUCTS_PER_SECTOR >> 8 ) & 0xFF
		cp		r9, j
		brne	fatFreeClusters25	; next cluster in sector
		
		ldi		i, 0x01					; get next sector
		call	fatIncR0

		lds		i, FirstFAT2Sector
		cp		i, R0
		brne	fatFreeClusters1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+1
		cp		i, R1
		brne	fatFreeClusters1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+2
		cp		i, R2
		brne	fatFreeClusters1		; if not end of first FAT, do again
		lds		i, FirstFAT2Sector+3
		cp		i, R3
		brne	fatFreeClusters1		; if not end of first FAT, do again
		movw	R0, R10			; move cluster count to R0-R1
		ret

;*****************************************************************************
; Formats Drive as FAT16 with 1 Active partition.
;*****************************************************************************
fatDriveFormat:	
		call	AtaInit			; init drive and get drive info
		tst		i
		breq	fatDriveFormat0
		rjmp	fatDriveFormatErr

fatDriveFormat0:				; build sector 0 Volume Boot Sector

		ldi		XL, low(fat_buffer)
		ldi		XH, high(fat_buffer)		
		ldi		YL, 0x00
		ldi		YH, 0x02			; 512 bytes
		ldi		ZL, low(SECT0Data*2)
		ldi		ZH, high(SECT0Data*2)		
		
fatDriveFormat1:
		lpm		i,	Z+
		st		X+,	i
		sbiw	Y, 0x01
		brne	fatDriveFormat1			; fill fatbuffer with data image

		lds		R4, ata_Sectors
		lds		R5, ata_Sectors+1
		lds		R6, ata_Sectors+2
		lds		R7, ata_Sectors+3
		ldi		i, 0x0F
		and		i, R7		
		sts		fat_buffer+prEndHead, i
		mov		j, R6
		lsr		j
		ror		i
		lsr		j
		ror		i
		andi	i,	0xC0
		mov		j, R4
		andi	j, 0x3F
		or		i, j
		sts		fat_buffer+prEndCylSect, i
		sts		fat_buffer+prEndCylSect+1, R5

		lds		R8, ata_Sectors
		lds		R9, ata_Sectors+1
		lds		R10, ata_Sectors+2
		lds		R11, ata_Sectors+3
		ldi		i, 0x00
		ldi		j, 0x02
		sub		R8, j
		sbc		R9, i
		sbc		R10, i
		sbc		R11, i
		sts		fat_buffer+prSize, R8
		sts		fat_buffer+prSize+1, R9
		sts		fat_buffer+prSize+2, R10
		sts		fat_buffer+prSize+3, R11

		ldi		i, 0x00
		mov		R0, i
		mov		R1, i
		movw	R2, R0
		call	ataWriteSectors				; write MBR
		inc		R0
		call	ataWriteSectors				; write MBR into sector 1 as a backup

		ldi		XL, low(fat_buffer)
		ldi		XH, high(fat_buffer)		
		ldi		YL, 0x00
		ldi		YH, 0x02			; 512 bytes
		ldi		ZL, low(SECT2Data*2)
		ldi		ZH, high(SECT2Data*2)		
		
fatDriveFormat2:
		lpm		i,	Z+
		st		X+,	i
		sbiw	Y, 0x01
		brne	fatDriveFormat2			; fill fatbuffer with data image

		lds		R4, ata_Sectors
		lds		R5, ata_Sectors+1
		lds		R6, ata_Sectors+2
		lds		R7, ata_Sectors+3
		ldi		m,	0x01				; sectors per cluster
fatDriveFormat3:
		ldi		i, 0xF6
		cp		R4, i
		ldi		i, 0xFF
		cpc		R5, i
		ldi		i, 0x00
		cpc		R6, i
		cpc		R7, i
		brcs	fatDriveFormat4
		lsr		R7
		ror		R6
		ror		R5
		ror		R4
		lsl		m
		rjmp	fatDriveFormat3

fatDriveFormatErr:
		ldi		i, 0x03
		ret

fatDriveFormat4:						; R4-R5 hold # clusters total, m holds # sectors per cluster
		tst		m
		breq	fatDriveFormatErr		
		cpi		m, 0x80					; m = 1,2,4,8,16,32,64 only
		breq	fatDriveFormatErr		

		sts		fat_buffer+bpbSecPerClust, m

		tst		R10
		brne	fatDriveFormat5
		tst		R11
		brne	fatDriveFormat5

		sts		fat_buffer+bpbSectors, R8
		sts		fat_buffer+bpbSectors+1, R9
		rjmp	fatDriveFormat55

fatDriveFormat5:
		sts		fat_buffer+bpbHugeSectors, R8
		sts		fat_buffer+bpbHugeSectors+1, R9
		sts		fat_buffer+bpbHugeSectors+2, R10
		sts		fat_buffer+bpbHugeSectors+3, R11

fatDriveFormat55:
		mov		R6, R5
		tst		R4
		breq	fatDriveFormat6
		inc		R6						
fatDriveFormat6:						; R6 holds FAT # sectors
		sts		fat_buffer+bpbFATsecs, R6

		ldi		i, 0x02
		mov		R0, i
		ldi		i, 0x00
		mov		R1, i
		mov		R2, i
		mov		R3, i
		call	ataWriteSectors				; write VBR

		ldi		XL, low(fat_buffer)			; fill FAT sectors with 00
		ldi		XH, high(fat_buffer)		
		ldi		YL, 0x00
		ldi		YH, 0x02					; 512 bytes
		ldi		i, 0x00

fatDriveFormat8:	
		st		X+,	i
		sbiw	Y, 0x01
		brne	fatDriveFormat8				; clear buffer
			
		mov		R7, i						; clr sector counter high byte
		movw	R10, R6						; save FAT size for root dir below
		ldi		j, 0x1F
		add		R6, j
		adc		R7, i						; sector counter = FAT size + Root Dir Sectors (32) - 1
		ldi		i, 0x04
		mov		R0, i						; R0-R3 = sector 4, R6-R7 is sector counter

fatDriveFormat9:	
		ldi		i, 0x00
		call	ataWriteSectors
		ldi		i, 0x01
		call	fatIncR0
		ldi		i, 0x01
		sub		R6, i
		ldi		i, 0x00
		sbc		R7, i
		brne	fatDriveFormat9

		ldi		i, 0xF8
		sts		Fat_buffer, i
		ldi		i, 0xFF
		sts		Fat_buffer+1, i
		sts		Fat_buffer+2, i
		sts		Fat_buffer+3, i			; fix cluster 0 & 1 in FAT table

		ldi		i, 0x03
		mov		R0, i
		ldi		i, 0x00
		mov		R1, i
		mov		R2, i
		mov		R3, i
		call	ataWriteSectors			; write FAT

		ldi		XL, low(fat_buffer)		; CREATE VOLUME LABEL ENTRY IN ROOT DIR
		ldi		XH, high(fat_buffer)		
		ldi		ZL, low(VOLREC*2)
		ldi		ZH, high(VOLREC*2)		
		ldi		j,	0x20
fatDriveFormat95:	
		lpm		i,	Z+
		st		X+, i
		dec		j
		brne	fatDriveFormat95
	
		movw	R0, R10
		ldi		i,	0x03
		add		R0,	i
		ldi		i,	0x00
		adc		R1,	i
		mov		R2, i
		mov		R3, i
		call	ataWriteSectors
		call	fatInit						; init the FAT16 driver
		ret


;*****************************************************************************
; Test R0-R3 equal to zero - set Z flag accordingly
;*****************************************************************************
fatTestR0:
		tst		R0
		brne	fatTestR9
		tst		R1
		brne	fatTestR9
		tst		R2
		brne	fatTestR9
		tst		R3
fatTestR9:
		ret

;*****************************************************************************
; Increment R0-R3 by the value in i
;*****************************************************************************
fatIncR0:
		add		R0,	i
		ldi		i,  0x00
		adc		R1,	i
		adc		R2,	i
		adc		R3,	i
		ret

;*****************************************************************************
; set R0-R3 to 0
;*****************************************************************************
fatClrR0:
		clr		R0
		clr		R1
		clr		R2
		clr		R3
		ret

;*****************************************************************************
; Print Volume Name
;*****************************************************************************
fatVolLbl:

		ldi		ZL, low(volname)					; print vol name value
		ldi		ZH, high(volname)
	    call	strout
;		ldi		i, 0x00
;		call	cout
		ret

;*****************************************************************************
; data table for Master Boot Sector (mirror data to sector 1 (it's reserved)
SECT0Data:
		.db 0xFA, 0x33, 0xC0, 0x8E, 0xD0, 0xBC, 0x00, 0x7C, 0x8B, 0xF4, 0x50, 0x07, 0x50, 0x1F, 0xFB, 0xFC
 		.db 0xBF, 0x00, 0x06, 0xB9, 0x00, 0x01, 0xF2, 0xA5, 0xEA, 0x1D, 0x06, 0x00, 0x00, 0xBE, 0xBE, 0x07
		.db 0xB3, 0x04, 0x80, 0x3C, 0x80, 0x74, 0x0E, 0x80, 0x3C, 0x00, 0x75, 0x1C, 0x83, 0xC6, 0x10, 0xFE
		.db 0xCB, 0x75, 0xEF, 0xCD, 0x18, 0x8B, 0x14, 0x8B, 0x4C, 0x02, 0x8B, 0xEE, 0x83, 0xC6, 0x10, 0xFE
		.db 0xCB, 0x74, 0x1A, 0x80, 0x3C, 0x00, 0x74, 0xF4, 0xBE, 0x8B, 0x06, 0xAC, 0x3C, 0x00, 0x74, 0x0B
		.db 0x56, 0xBB, 0x07, 0x00, 0xB4, 0x0E, 0xCD, 0x10, 0x5E, 0xEB, 0xF0, 0xEB, 0xFE, 0xBF, 0x05, 0x00
 		.db 0xBB, 0x00, 0x7C, 0xB8, 0x01, 0x02, 0x57, 0xCD, 0x13, 0x5F, 0x73, 0x0C, 0x33, 0xC0, 0xCD, 0x13
 		.db 0x4F, 0x75, 0xED, 0xBE, 0xA3, 0x06, 0xEB, 0xD3, 0xBE, 0xC2, 0x06, 0xBF, 0xFE, 0x7D, 0x81, 0x3D
 		.db 0x55, 0xAA, 0x75, 0xC7, 0x8B, 0xF5, 0xEA, 0x00, 0x7C, 0x00, 0x00, 0x49, 0x6E, 0x76, 0x61, 0x6C
 		.db 0x69, 0x64, 0x20, 0x70, 0x61, 0x72, 0x74, 0x69, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x74, 0x61, 0x62
 		.db 0x6C, 0x65, 0x00, 0x45, 0x72, 0x72, 0x6F, 0x72, 0x20, 0x6C, 0x6F, 0x61, 0x64, 0x69, 0x6E, 0x67
 		.db 0x20, 0x6F, 0x70, 0x65, 0x72, 0x61, 0x74, 0x69, 0x6E, 0x67, 0x20, 0x73, 0x79, 0x73, 0x74, 0x65
 		.db 0x6D, 0x00, 0x4D, 0x69, 0x73, 0x73, 0x69, 0x6E, 0x67, 0x20, 0x6F, 0x70, 0x65, 0x72, 0x61, 0x74
 		.db 0x69, 0x6E, 0x67, 0x20, 0x73, 0x79, 0x73, 0x74, 0x65, 0x6D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00 ; 1B0
 		.db 0x02, 0x00, 0x06, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 1C0
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 1D0
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 1E0
 		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x55, 0xAA ; 1F0


; data table for Volume boot Record
SECT2Data:
 		.db 0xEB, 0x3C, 0x90, 0x4D, 0x53, 0x57, 0x49, 0x4E, 0x34, 0x2E, 0x31, 0x00, 0x02, 0x00, 0x01, 0x00 ; mod +13
 		.db 0x01, 0x00, 0x02, 0x00, 0x00, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 ; mod +3,4,6,7,
 		.db 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x29, 0x9A, 0x32, 0xC0, 0x8B, 0x4E, 0x4F, 0x20, 0x4E, 0x41  
 		.db 0x4D, 0x45, 0x20, 0x20, 0x20, 0x20, 0x46, 0x41, 0x54, 0x31, 0x36, 0x20, 0x20, 0x20, 0xFA, 0x33
 		.db 0xC0, 0x8E, 0xD0, 0xBC, 0x00, 0x7C, 0x16, 0x07, 0xBB, 0x78, 0x00, 0x36, 0xC5, 0x37, 0x1E, 0x56
 		.db 0x16, 0x53, 0xBF, 0x3E, 0x7C, 0xB9, 0x0B, 0x00, 0xFC, 0xF3, 0xA4, 0x06, 0x1F, 0xC6, 0x45, 0xFE
 		.db 0x0F, 0x8B, 0x0E, 0x18, 0x7C, 0x88, 0x4D, 0xF9, 0x89, 0x47, 0x02, 0xC7, 0x07, 0x3E, 0x7C, 0xFB
 		.db 0xCD, 0x13, 0x72, 0x79, 0x33, 0xC0, 0x39, 0x06, 0x13, 0x7C, 0x74, 0x08, 0x8B, 0x0E, 0x13, 0x7C
 		.db 0x89, 0x0E, 0x20, 0x7C, 0xA0, 0x10, 0x7C, 0xF7, 0x26, 0x16, 0x7C, 0x03, 0x06, 0x1C, 0x7C, 0x13
 		.db 0x16, 0x1E, 0x7C, 0x03, 0x06, 0x0E, 0x7C, 0x83, 0xD2, 0x00, 0xA3, 0x50, 0x7C, 0x89, 0x16, 0x52
 		.db 0x7C, 0xA3, 0x49, 0x7C, 0x89, 0x16, 0x4B, 0x7C, 0xB8, 0x20, 0x00, 0xF7, 0x26, 0x11, 0x7C, 0x8B
 		.db 0x1E, 0x0B, 0x7C, 0x03, 0xC3, 0x48, 0xF7, 0xF3, 0x01, 0x06, 0x49, 0x7C, 0x83, 0x16, 0x4B, 0x7C
 		.db 0x00, 0xBB, 0x00, 0x05, 0x8B, 0x16, 0x52, 0x7C, 0xA1, 0x50, 0x7C, 0xE8, 0x92, 0x00, 0x72, 0x1D
 		.db 0xB0, 0x01, 0xE8, 0xAC, 0x00, 0x72, 0x16, 0x8B, 0xFB, 0xB9, 0x0B, 0x00, 0xBE, 0xE6, 0x7D, 0xF3
 		.db 0xA6, 0x75, 0x0A, 0x8D, 0x7F, 0x20, 0xB9, 0x0B, 0x00, 0xF3, 0xA6, 0x74, 0x18, 0xBE, 0x9E, 0x7D
 		.db 0xE8, 0x5F, 0x00, 0x33, 0xC0, 0xCD, 0x16, 0x5E, 0x1F, 0x8F, 0x04, 0x8F, 0x44, 0x02, 0xCD, 0x19
 		.db 0x58, 0x58, 0x58, 0xEB, 0xE8, 0x8B, 0x47, 0x1A, 0x48, 0x48, 0x8A, 0x1E, 0x0D, 0x7C, 0x32, 0xFF
 		.db 0xF7, 0xE3, 0x03, 0x06, 0x49, 0x7C, 0x13, 0x16, 0x4B, 0x7C, 0xBB, 0x00, 0x07, 0xB9, 0x03, 0x00
 		.db 0x50, 0x52, 0x51, 0xE8, 0x3A, 0x00, 0x72, 0xD8, 0xB0, 0x01, 0xE8, 0x54, 0x00, 0x59, 0x5A, 0x58
 		.db 0x72, 0xBB, 0x05, 0x01, 0x00, 0x83, 0xD2, 0x00, 0x03, 0x1E, 0x0B, 0x7C, 0xE2, 0xE2, 0x8A, 0x2E
 		.db 0x15, 0x7C, 0x8A, 0x16, 0x24, 0x7C, 0x8B, 0x1E, 0x49, 0x7C, 0xA1, 0x4B, 0x7C, 0xEA, 0x00, 0x00
 		.db 0x70, 0x00, 0xAC, 0x0A, 0xC0, 0x74, 0x29, 0xB4, 0x0E, 0xBB, 0x07, 0x00, 0xCD, 0x10, 0xEB, 0xF2
 		.db 0x3B, 0x16, 0x18, 0x7C, 0x73, 0x19, 0xF7, 0x36, 0x18, 0x7C, 0xFE, 0xC2, 0x88, 0x16, 0x4F, 0x7C
 		.db 0x33, 0xD2, 0xF7, 0x36, 0x1A, 0x7C, 0x88, 0x16, 0x25, 0x7C, 0xA3, 0x4D, 0x7C, 0xF8, 0xC3, 0xF9
 		.db 0xC3, 0xB4, 0x02, 0x8B, 0x16, 0x4D, 0x7C, 0xB1, 0x06, 0xD2, 0xE6, 0x0A, 0x36, 0x4F, 0x7C, 0x8B
 		.db 0xCA, 0x86, 0xE9, 0x8A, 0x16, 0x24, 0x7C, 0x8A, 0x36, 0x25, 0x7C, 0xCD, 0x13, 0xC3, 0x0D, 0x0A
 		.db 0x4E, 0x6F, 0x6E, 0x2D, 0x53, 0x79, 0x73, 0x74, 0x65, 0x6D, 0x20, 0x64, 0x69, 0x73, 0x6B, 0x20
 		.db 0x6F, 0x72, 0x20, 0x64, 0x69, 0x73, 0x6B, 0x20, 0x65, 0x72, 0x72, 0x6F, 0x72, 0x0D, 0x0A, 0x52
 		.db 0x65, 0x70, 0x6C, 0x61, 0x63, 0x65, 0x20, 0x61, 0x6E, 0x64, 0x20, 0x70, 0x72, 0x65, 0x73, 0x73
 		.db 0x20, 0x61, 0x6E, 0x79, 0x20, 0x6B, 0x65, 0x79, 0x20, 0x77, 0x68, 0x65, 0x6E, 0x20, 0x72, 0x65
 		.db 0x61, 0x64, 0x79, 0x0D, 0x0A, 0x00, 0x49, 0x4F, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x53, 0x59
 		.db 0x53, 0x4D, 0x53, 0x44, 0x4F, 0x53, 0x20, 0x20, 0x20, 0x53, 0x59, 0x53, 0x00, 0x00, 0x55, 0xAA

VOLREC:
        .db  "AVR_CF01   ", 0x08, 0x00, 0x00, 0x00, 0x00
		.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFC, 0x59, 0x77, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 


