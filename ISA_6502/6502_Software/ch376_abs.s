; ============================================================================
; CH376 USB/SD file driver for 6502 - 8-bit PARALLEL interface   (ca65 syntax)
; ============================================================================
; HARDWARE
;   CH376 D0-D7 -> 6502 D0-D7
;   CH376 A0    -> 6502 A0          (A0=0: data port, A0=1: command/status port)
;   CH376 CS#   -> your address decode (active low), e.g. $7F20-$7F21
;   CH376 RD#   -> NAND(PHI2, R/W)          (low during a read cycle)
;   CH376 WR#   -> NAND(PHI2, NOT R/W)      (low during a write cycle)
;   CH376 INT#  -> optional (this code polls bit 7 of the status port instead)
;   CH376 RST   -> reset circuit (or tie low->high at power-up)
;   Many cheap CH376 modules only break out UART/SPI. Make sure your module
;   exposes D0-D7/A0/CS/RD/WR and has the parallel interface selected.
;
; PORTS
;   CH_DATA ($7F20) read/write data bytes
;   CH_CMD  ($7F21) write = command code, read = status
;       bit 7 (INTB): 0 = interrupt active (operation finished)
;       bit 4 (BUSY): 1 = chip busy, don't access yet
;
; CONVENTIONS
;   Routines that return a CH376 status in A: $14 = success, anything else
;   is an error (or a "need data" code for read/write, handled internally).
;   ch_init / ch_mount return carry set on failure.
;   File names: 8.3, UPPERCASE, null terminated, root dir = "/NAME.EXT"
; ============================================================================

CH_BASE   = $7F20
CH_DATA   = CH_BASE
CH_CMD    = CH_BASE + 1

CPU_KHZ   = CPU_MHZ * 1000             ; CPU clock in kHz (CPU_MHZ is set in main.s)
; one delay "tick" = ~1285 cycles
DELAY_40MS = (CPU_KHZ * 40) / 1285 + 1
.assert DELAY_40MS < 256, error, "CPU_MHZ too high for the 8 bit delay counter"

.zeropage
zp_ptr:   .res 2    ; 2 bytes of zero page used for (pointer),Y while a transfer runs
strptr:   .res 2    ; string pointer (LCD routines, monitor and CH376 messages); declared here
                    ; so it is known before first use (zero page addressing)

; --- variables -------------------------------------------------------------
; All CH376 variables live in segment CHVARS (placed at $0280 by sbc.cfg).
; Layout is identical to the old VARS+n block (90 bytes total).
.segment "CHVARS"
ch_ptr:     .res 2   ; buffer pointer (caller sets, advanced by read/write)
ch_len:     .res 2   ; bytes requested
ch_got:     .res 2   ; bytes actually read (output of ch_read)
ch_cnt:     .res 1   ; chunk counter
ch_tmp:     .res 1   ; timeout counter
ch_retry:   .res 1   ; mount retry counter
ch_off:     .res 4   ; file offset for ch_seek (little endian)
; --- used by ch376_loadsave.s
ch_name:    .res 48  ; "/NAME.BAS",0 (a path such as "/GAMES/DEEP/X.BIN" for the monitor)
ch_ready:   .res 1   ; 0 = CH376 not initialised / mounted
ch_dot:     .res 1   ; non-zero if the name contained a "."
ch_dir:     .res 1   ; non-zero: LOAD "$..." (directory listing)
ch_ent:     .res 32  ; directory entry from the chip
ch_num:     .res 4   ; number being printed
ch_col:     .res 1   ; column counter while printing a name
ch_started: .res 1   ; leading-zero suppression flag
ch_nfiles:  .res 2   ; files listed
ch_sx:      .res 1   ; saved X / Y around the output routine
ch_sy:      .res 1
ch_lastcmd: .res 1   ; last command byte sent to the chip (diagnostics)
ch_laststs: .res 1   ; raw status port value when a wait timed out
ch_mon:     .res 1   ; non-zero while a monitor command is using the CH376 code
ch_raw:     .res 1   ; 0 = LOAD/SAVE (.BAS), 1 = LOADRAW/SAVERAW (.DAT)
ch_a0:      .res 2   ; LOADRAW/SAVERAW start address
ch_stat:    .res 1   ; last CH376 status code that caused a ?DISK ERROR

; The 6502 can only do (pointer),Y indirection through ZERO PAGE, so two
; zero-page bytes (zp_ptr, reserved above) are used while a transfer runs.
; ZP_ENTER/ZP_LEAVE still save/restore them, which is harmless.



.macro ZP_ENTER                      ; save zp pair, load it with ch_ptr
        lda zp_ptr
        pha
        lda zp_ptr+1
        pha
        lda ch_ptr
        sta zp_ptr
        lda ch_ptr+1
        sta zp_ptr+1
.endmacro

.macro ZP_LEAVE                      ; store advanced pointer back, restore zp
        lda zp_ptr
        sta ch_ptr
        lda zp_ptr+1
        sta ch_ptr+1
        pla
        sta zp_ptr+1
        pla
        sta zp_ptr
.endmacro

.segment "BIOS"
; --- commands --------------------------------------------------------------
CMD_GET_IC_VER    = $01
CMD_RESET_ALL     = $05
CMD_CHECK_EXIST   = $06
CMD_SET_USB_MODE  = $15
CMD_GET_STATUS    = $22
CMD_RD_USB_DATA0  = $27
CMD_WR_REQ_DATA   = $2D
CMD_SET_FILE_NAME = $2F
CMD_DISK_CONNECT  = $30
CMD_DISK_MOUNT    = $31
CMD_FILE_OPEN     = $32
CMD_FILE_CREATE   = $34
CMD_FILE_ERASE    = $35
CMD_FILE_CLOSE    = $36
CMD_BYTE_LOCATE   = $39
CMD_BYTE_READ     = $3A
CMD_BYTE_RD_GO    = $3B
CMD_BYTE_WRITE    = $3C
CMD_BYTE_WR_GO    = $3D

; --- status / result codes -------------------------------------------------
CMD_RET_SUCCESS   = $51
USB_INT_SUCCESS   = $14
USB_INT_CONNECT   = $15
USB_INT_DISCONNECT= $16
USB_INT_DISK_READ = $1D
USB_INT_DISK_WRITE= $1E
USB_INT_DISK_ERR  = $1F
ERR_MISS_FILE     = $42      ; file not found
ERR_DISK_DISCON   = $82
ERR_DISK_FULL     = $B1

USB_MODE_HOST     = $06      ; host mode, auto SOF



; ----------------------------------------------------------------------------
; Low level
; ----------------------------------------------------------------------------
ch_wait_busy:                        ; spin until BUSY (bit 4) clears
        lda CH_CMD
        and #$10
        bne ch_wait_busy
        rts

ch_cmd:                              ; A = command code
        pha
        jsr ch_wait_busy
        pla
        sta ch_lastcmd
        sta CH_CMD
        nop                          ; chip needs ~1.5us before next access;
        nop                          ; add more NOPs if your CPU is fast
        nop
        nop
        rts

ch_wr:                               ; A = data byte to send
        pha
        jsr ch_wait_busy
        pla
        sta CH_DATA
        rts

ch_rd:                               ; returns data byte in A
        jsr ch_wait_busy
        lda CH_DATA
        rts

ch_delay:                            ; X = ticks (~1285 cycles each)
@outer: ldy #0
@inner: dey
        bne @inner
        dex
        bne @outer
        rts

ch_wait_int:                         ; wait for INT (status bit 7 = 0)
        lda #4                       ; ~3 s at 1 MHz
        sta ch_tmp
        ldy #0
        ldx #0
@loop:  lda CH_CMD
        bpl @got
        inx
        bne @loop
        iny
        bne @loop
        dec ch_tmp
        bne @loop
        sec                          ; timeout
        rts
@got:   clc
        rts

ch_get_status:                       ; returns result code in A, releases INT
        lda #CMD_GET_STATUS
        jsr ch_cmd
        jmp ch_rd

ch_wait_status:                      ; wait for INT then read status
        jsr ch_wait_int              ; carry set = timeout (A = $FF)
        bcs @timeout
        jmp ch_get_status
@timeout:
        lda CH_CMD
        sta ch_laststs
        lda #$FF
        sec
        rts

; ----------------------------------------------------------------------------
; ch_init - reset chip, check it exists, switch to USB host mode
;   out: carry clear = ok, set = failed
; ----------------------------------------------------------------------------
ch_init:
        lda #CMD_RESET_ALL
        sta CH_CMD                   ; raw write: no busy check during reset
        ldx #DELAY_40MS
        jsr ch_delay

        lda #CMD_CHECK_EXIST
        jsr ch_cmd
        lda #$57
        jsr ch_wr
        jsr ch_rd
        cmp #$A8                     ; chip returns bitwise NOT of $57
        bne @fail

        lda #CMD_SET_USB_MODE
        jsr ch_cmd
        lda #USB_MODE_HOST
        jsr ch_wr
        ldx #1                       ; >= 20us
        jsr ch_delay
        jsr ch_rd
        cmp #CMD_RET_SUCCESS
        bne @fail
        clc
        rts
@fail:  sec
        rts

; ----------------------------------------------------------------------------
; ch_mount - wait for USB drive, connect + mount the filesystem
;   out: carry clear = ok, set = no drive / unreadable filesystem
; ----------------------------------------------------------------------------
ch_mount:
        jsr ch_wait_status           ; expect "device connected"
        cmp #USB_INT_CONNECT
        bne @fail

        lda #CMD_DISK_CONNECT
        jsr ch_cmd
        jsr ch_wait_status
        cmp #USB_INT_SUCCESS
        bne @fail

        lda #5
        sta ch_retry
@try:   lda #CMD_DISK_MOUNT          ; some drives need a few tries
        jsr ch_cmd
        jsr ch_wait_status
        cmp #USB_INT_SUCCESS
        beq @ok
        ldx #DELAY_40MS
        jsr ch_delay
        dec ch_retry
        bne @try
@fail:  sec
        rts
@ok:    clc
        rts

; ----------------------------------------------------------------------------
; File name / open / create / close
; ----------------------------------------------------------------------------
ch_set_name:                         ; A = name lo, X = name hi
        sta ch_ptr
        stx ch_ptr+1
        ZP_ENTER
        lda #CMD_SET_FILE_NAME
        jsr ch_cmd
        ldy #0
@l:     lda (zp_ptr),y
        jsr ch_wr
        lda (zp_ptr),y
        beq @done                    ; terminator was sent too
        iny
        bne @l
@done:  ZP_LEAVE
        rts

ch_file_open:                        ; A/X = name. returns status in A
        jsr ch_set_name
        lda #CMD_FILE_OPEN
        jsr ch_cmd
        jmp ch_wait_status

ch_file_create:                      ; A/X = name. creates/truncates file
        jsr ch_set_name
        lda #CMD_FILE_CREATE
        jsr ch_cmd
        jmp ch_wait_status

ch_file_erase:                       ; A/X = name. deletes file
        jsr ch_set_name
        lda #CMD_FILE_ERASE
        jsr ch_cmd
        jmp ch_wait_status

ch_file_close:                       ; A = 1 update file length (after writing)
        pha                          ;     0 = no update (after reading)
        lda #CMD_FILE_CLOSE
        jsr ch_cmd
        pla
        jsr ch_wr
        jmp ch_wait_status

; ch_seek - move file pointer to 32-bit offset in ch_off (little endian)
;   Set ch_off = $FFFFFFFF to seek to end (for appending).
ch_seek:
        lda #CMD_BYTE_LOCATE
        jsr ch_cmd
        ldx #0
@l:     lda ch_off,x
        jsr ch_wr
        inx
        cpx #4
        bne @l
        jmp ch_wait_status

; ----------------------------------------------------------------------------
; ch_read - read ch_len bytes from the open file into (ch_ptr)
;   in : ch_ptr = destination, ch_len = max bytes
;   out: A = $14 on success, ch_got = bytes actually read (less at EOF),
;        ch_ptr advanced past the data
; ----------------------------------------------------------------------------
ch_read:
        ZP_ENTER
        lda #0
        sta ch_got
        sta ch_got+1
        lda #CMD_BYTE_READ
        jsr ch_cmd
        lda ch_len
        jsr ch_wr
        lda ch_len+1
        jsr ch_wr
@next:  jsr ch_wait_status
        cmp #USB_INT_DISK_READ       ; $1D = a chunk (<=64 bytes) is ready
        bne @done                    ; $14 = finished, else error
        lda #CMD_RD_USB_DATA0
        jsr ch_cmd
        jsr ch_rd                    ; first byte = chunk length
        sta ch_cnt
        beq @go
        ldy #0
@copy:  jsr ch_rd
        sta (zp_ptr),y
        iny
        cpy ch_cnt
        bne @copy
        clc                          ; zp_ptr += ch_cnt
        lda zp_ptr
        adc ch_cnt
        sta zp_ptr
        bcc :+
        inc zp_ptr+1
:       clc                          ; ch_got += ch_cnt
        lda ch_got
        adc ch_cnt
        sta ch_got
        bcc @go
        inc ch_got+1
@go:    lda #CMD_BYTE_RD_GO          ; ask for next chunk
        jsr ch_cmd
        jmp @next
@done:  tax                          ; keep status while restoring zp
        ZP_LEAVE
        txa
        rts

; ----------------------------------------------------------------------------
; ch_write - write ch_len bytes from (ch_ptr) to the open file
;   in : ch_ptr = source, ch_len = byte count
;   out: A = $14 on success, ch_ptr advanced
;   Call ch_file_close with A=1 afterwards so the file length is saved.
; ----------------------------------------------------------------------------
ch_write:
        ZP_ENTER
        lda #CMD_BYTE_WRITE
        jsr ch_cmd
        lda ch_len
        jsr ch_wr
        lda ch_len+1
        jsr ch_wr
@next:  jsr ch_wait_status
        cmp #USB_INT_DISK_WRITE      ; $1E = chip wants more data
        bne @done                    ; $14 = finished, else error
        lda #CMD_WR_REQ_DATA
        jsr ch_cmd
        jsr ch_rd                    ; how many bytes it wants (<=64)
        sta ch_cnt
        beq @go
        ldy #0
@copy:  lda (zp_ptr),y
        jsr ch_wr
        iny
        cpy ch_cnt
        bne @copy
        clc
        lda zp_ptr
        adc ch_cnt
        sta zp_ptr
        bcc @go
        inc zp_ptr+1
@go:    lda #CMD_BYTE_WR_GO
        jsr ch_cmd
        jmp @next
@done:  tax
        ZP_LEAVE
        txa
        rts

