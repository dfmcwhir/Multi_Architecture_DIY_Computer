;
; FAT definitions
;

; RESISTER ASSIGNMENTS

; Some useful cluster numbers
.set MSDOSFSROOT    =	0               ; cluster 0 means the root dir
.set CLUST_FREE     =	0               ; cluster 0 also means a free cluster
.set MSDOSFSFREE    =	CLUST_FREE
.set CLUST_FIRST    =	2               ; first legal cluster number
.set CLUST_RSRVD    =	0xfff6      ; reserved cluster range
.set CLUST_BAD      =	0xfff7      ; a cluster with a defect
.set CLUST_EOFS     =	0xfff8      ; start of eof cluster range
.set CLUST_EOFE     =	0xffff      ; end of eof cluster range

; Partition Type used in the partition record
.set PART_TYPE_UNKNOWN		=	0x00
.set PART_TYPE_FAT12		=	0x01
.set PART_TYPE_XENIX		=	0x02
.set PART_TYPE_DOSFAT16		=	0x04
.set PART_TYPE_EXTDOS		=	0x05
.set PART_TYPE_FAT16		=	0x06
.set PART_TYPE_NTFS			=	0x07
.set PART_TYPE_FAT32		=	0x0B
.set PART_TYPE_FAT32LBA		=	0x0C
.set PART_TYPE_FAT16LBA		=	0x0E
.set PART_TYPE_EXTDOSLBA	=	0x0F
.set PART_TYPE_ONTRACK		=	0x33
.set PART_TYPE_NOVELL		=	0x40
.set PART_TYPE_PCIX			=	0x4B
.set PART_TYPE_PHOENIXSAVE	=	0xA0
.set PART_TYPE_CPM			=	0xDB
.set PART_TYPE_DBFS			=	0xE0
.set PART_TYPE_BBT			=	0xFF

.set BYTES_PER_SECTOR			=	512	; bytes
.set DIRENTRY_SIZE				=	32	; bytes
.set FAT_DIRENTRIES_PER_SECTOR	=	16  ; =BYTES_PER_SECTOR/DIRENTRY_SIZE
.set FAT16_STRUCTS_PER_SECTOR	=	256 ; 

.set SEEK_CUR			=	0x00
.set SEEK_END			=	0x01
.set SEEK_SET			=	0x02

;struct partrecord ; length 16 bytes
.set prIsActive			=	0x1BE			; 0x80 indicates active partition
.set prStartHead		=	0x1BF			; starting head for partition
.set prStartCylSect     =   0x1C0			; starting cylinder and sector
.set prPartType         =   0x1C2			; partition type (see above)
.set prEndHead          =   0x1C3			; ending head for this partition
.set prEndCylSect       =   0x1C4			; ending cylinder and sector
.set prStartLBA			=   0x1C6			; first LBA sector for this partition
.set prSize				=	0x1CA			; size of this partition (bytes or sectors ?)

; Format of a boot sector.  This is the first sector on a DOS floppy disk
; or the first sector of a partition on a hard disk.  But, it is not the
; first sector of a partitioned hard disk.

.set bsJump				=	0x00			; jump inst E9xxxx or EBxx90
.set bsOEMName			=	0x03			; OEM name and version
.set bsBPB				=	0x0b			; BIOS parameter block
.set bpExt				= 	0x40			; Bootsector Extension
.set bpBootCode			=	0x5A			; pad so structure is 512b
.set bpBootSectSig2     =   0x1FC			; 2 & 3 are only defined for FAT32?
.set bpBootSectSig3     =   0x1FD
.set bpBootSectSig0     =   0x1FE			; boot sector signature byte 0x55
.set bpBootSectSig1     =   0x1FF			; boot sector signature byte 0xAA

/***************************************************************/
; BPB for DOS 5.0 (FAT16)
.set bpbBytesPerSec		= 	0x0B			;2 bytes per sector
.set bpbSecPerClust		=	0x0D			;1 sectors per cluster
.set bpbResSectors		=	0x0E			;2 number of reserved sectors
.set bpbFATs			=	0x10			;1 number of FATs
.set bpbRootDirEnts		=	0x11			;2 number of root directory entries
.set bpbSectors			=	0x13			;2 total number of sectors
.set bpbMedia			=	0x15			;1 media descriptor
.set bpbFATsecs			=	0x16			;2 number of sectors per FAT
.set bpbSecPerTrack		=	0x18			;2 sectors per track
.set bpbHeads			=	0x1A			;2 number of heads
.set bpbHiddenSecs		=	0x1C			;4 no. of hidden sectors
; 3.3 compat ends here
.set bpbHugeSectors		=	0x20			;4 no. of sectors if bpbSectors == 0
.set bpbDrvNum			=	0x24			;1 Drive number 0x00 for floppy disks, 0x80 for hard disks
.set bpbReserved1		=	0x25			;1 used by NT, set to 0x00 for FAT
.set bpbBootSig			=	0x26			;1 Extended boot signature (0x29). This is a signature byte 
											;  that indicates that the following three fields in the 
											;  boot sector are present.
.set bpbVolID			=	0x27			;4 Volume serial number
.set bpbVolLab			=	0x2B			;11 Volume label
.set bpbFilSysType		=	0x36			;8 FAT12, FAT16, FAT32, etc
; 5.0 compat ends here

/***************************************************************/
; Structure of a dos directory entry.

.set SLOT_EMPTY     = 	0x00	; slot has never been used
.set SLOT_E5        = 	0x05	; the real value is 0xe5
.set SLOT_DELETED   = 	0xe5	; file in this slot deleted

.set ATTR_NORMAL    = 	0x00	; normal file
.set ATTR_READONLY  =	0x01	; file is readonly
.set ATTR_HIDDEN    = 	0x02	; file is hidden
.set ATTR_SYSTEM    = 	0x04	; file is a system file
.set ATTR_VOLUME    = 	0x08	; entry is a volume label
.set ATTR_LONG_FILENAME	= 0x0f	; this is a long filename entry
.set ATTR_DIRECTORY = 	0x10	; entry is a directory name
.set ATTR_ARCHIVE   = 	0x20	; file is new or modified

.set LCASE_BASE     = 	0x08	; filename base in lower case
.set LCASE_EXT      = 	0x10	; filename extension in lower case

.set deName			=	0x00	; filename, blank filled
.set deExt			=	0x08	; extension, blank filled
.set deAttrib		=	0x0B	; file attributes
.set deLowerCase	=	0x0C	; NT VFAT lower case flags
.set deCHundredth	=	0x0D	; hundredth of seconds in CTime
.set deCTime		=   0x0E	; create time
.set deCDate		=	0x10	; create date
.set deADate		=	0x12	; access date
.set deHighClust	=	0x14	; high bytes of cluster number
.set deMTime		=	0x16	; last update time
.set deMDate		=	0x18	; last update date
.set deStartCluster =	0x1A	; starting cluster of file
.set deFileSize		=	0x1C	; size of file in bytes
.set DIRENTRIES_PER_SECTOR	=	0x10

;*****************************************************************************
;
; SRAM variable defs
;
;*****************************************************************************

.set fat_buffer		=	ata_buffer1		; use the ata buffer assignments
.set fat_cache		=	ata_buffer2		; use the ata buffer assignments
.set fat_inbuf1		=	ata_cache1		;
.set fat_inbuf2		=	ata_cache2		;

.DSEG
//.ORG $0070		; first byte avail after "atadef.inc" declarations
;SysMode:            .byte 1     ; holds 0 for FAT16, non-zero for Direct mode (init)
volname:			.byte 12	; holds Vol name, from fatinit
startLBA:			.byte 4		; holds VBR sector, from fatinit
FirstDataSector: 	.byte 4  	; First Data Sector Address
SectorsPerCluster:	.byte 1		; Number of Sectors per Cluster
FirstFATSector:		.byte 4		; First FAT Sector Address
FirstFAT2Sector:	.byte 4		; First FAT2 Sector Address
RootDirSector:		.byte 4		; First Directory (Data) sector Address
FatSectors:			.byte 2		; Number of FAT Sectors
NumFats:			.byte 1		; number of fats 1 or 2
currentDirCluster:	.byte 2		; Actual Dir Cluster Number
NumClusters:		.byte 2		; ATA Dispositive Cluster Numbers
fileName:			.byte 12	; temp storage for File/Directory name
NewFileName:		.byte 12	; temp storage for new file\directory name
oldFileName:		.byte 12	; temp storage for old file\directory name
handle:				.byte 1		; holds current file handle
;Mode:				.byte 1		; holds File Open Mode
ByteCount:			.byte 4		; # bytes to read/write	
; directory entry for selected file 32 bytes)
desName:			.byte 8		; filename, blank filled
desExt:				.byte 3		; extension, blank filled
desAttrib:			.byte 1		; file attributes
desLowerCase:		.byte 1		; NT VFAT lower case flags
desCHundredth:		.byte 1		; hundredth of seconds in CTime
desCTime:			.byte 2		; create time
desCDate:			.byte 2		; create date
desADate:			.byte 2		; access date
desHighClust:		.byte 2		; high bytes of cluster number
desMTime:			.byte 2		; last update time
desMDate:			.byte 2		; last update date
desStartCluster: 	.byte 2		; starting cluster of file
desFileSize:		.byte 4		; size of file in bytes
; added variables for file manipulation (20 bytes in a 32 byte table)
desDirEntSector:	.byte 4		; hold LBA sector of dir entry
desDirEntpos:		.byte 2		; pointer to Dir Entry in Sector
descurrentSector:	.byte 4		; Actual sector address in memory
desbytePointer:		.byte 4		; byte pointer to the actual byte (divide by 512 to find the current buffer position)
desFileLength:		.byte 4		; length of open file
dessectorHasChanged:.byte 1		; TRUE if the sector in memory has changed and needs to be write before a close file or change in sector
desFileMode:		.byte 1		; R = read only, W = write, A = append

.CSEG
