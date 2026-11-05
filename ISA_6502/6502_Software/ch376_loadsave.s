; ============================================================================
; ch376_loadsave.s - EhBASIC "LOAD" and "SAVE" using the CH376 driver in
; ch376_abs.s (ch_init, ch_mount, ch_file_open, ch_file_create, ch_file_close,
; ch_read, ch_write ...).
;
;   LOAD "NAME"      -> reads /NAME.BAS into the BASIC program area
;   SAVE "NAME"      -> writes the current program to /NAME.BAS
;   LOAD "$"         -> lists the files in the root directory (the program in
;                       memory is NOT touched)
;   LOAD "$T*"       -> lists only matching files (the CH376's own wildcard
;                       matching, e.g. "$*.BAS" or "$GAME*")
;
;   - The name is any string expression, converted to UPPERCASE.
;   - ".BAS" is appended if the name contains no ".".
;   - A leading "/" is added for you (root directory). "DIR/NAME" works too.
;   - File format = BASIC's in-memory tokenised program (Smeml..Svarl-1).
;     Line links are rebuilt after loading, so files don't depend on where
;     the program was saved from.
;
; HOW EhBASIC CALLS US
;   basic.s dispatches the LOAD/SAVE tokens through V_LOAD/V_SAVE, which do
;   JMP (VEC_LD) / JMP (VEC_SV).  bios.s copies the addresses of CH_LOAD and
;   CH_SAVE into those RAM vectors at reset.  On entry the BASIC execute pointer
;   (Bpntrl/h) is just past the keyword, so we evaluate the argument with
;   LAB_EVEX/LAB_EVST.  SAVE finishes with RTS (back to the interpreter);
;   LOAD re-links the program and exits through LAB_1319 to the prompt.
;
; Variables (ch_name, ch_ready, ...) are declared in ch376_abs.s (CHVARS).
; ============================================================================

.segment "BIOS"

CH_NAME_MAX = 26                    ; longest name typed by the user

; EhBASIC error codes (offsets into LAB_BAER) used for argument errors
EH_ERR_FC    = $08                  ; ?Function call error
EH_ERR_TM    = $18                  ; ?Type mismatch   (raised by LAB_EVST)
EH_ERR_LS    = $1A                  ; ?String too long

CMD_FILE_ENUM_GO = $33              ; next directory entry

; --- private failure codes (CH376 codes are all < $F0)
CH_E_TOOBIG  = $F0
CH_E_BADFILE = $F1
CH_E_NODISK  = $F2

; continue if A = USB_INT_SUCCESS, otherwise jump to "target" with A intact
.macro CH_OK target
        .local ok
        cmp #USB_INT_SUCCESS
        beq ok
        jmp target
ok:
.endmacro

; ----------------------------------------------------------------------------
; CH_BOOT - call once at power-up/reset
; ----------------------------------------------------------------------------
CH_BOOT:
        lda #0
        sta ch_ready
        sta ch_mon
        rts

; ----------------------------------------------------------------------------
; CH_LOAD  - BASIC LOAD "name"
; ----------------------------------------------------------------------------
CH_LOAD:
        lda #0
        sta ch_raw
        jsr ch_get_filename
        lda ch_dir                  ; LOAD "$..." -> directory listing
        beq @file
        jmp ch_dirlist
@file:  jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_open            ; $42 = file not found
        CH_OK ch_fail

        sec                         ; ch_len = Ememl - Smeml (room available)
        lda Ememl
        sbc Smeml
        sta ch_len
        lda Ememh
        sbc Smemh
        sta ch_len+1
        lda Smeml                   ; destination = start of program
        sta ch_ptr
        lda Smemh
        sta ch_ptr+1
        jsr ch_read
        CH_OK ch_fail_close

        lda ch_got+1                ; got >= room?  -> file did not fit
        cmp ch_len+1
        bcc @fits
        bne @toobig
        lda ch_got
        cmp ch_len
        bcc @fits
@toobig:
        lda #CH_E_TOOBIG
        jmp ch_fail_close
@fits:  lda ch_got+1                ; a program is at least 2 bytes ($00 $00)
        bne @sizeok
        lda ch_got
        cmp #2
        bcs @sizeok
        lda #CH_E_BADFILE
        jmp ch_fail_close
@sizeok:
        lda #0
        jsr ch_file_close
        lda ch_ptr                  ; ch_read advanced ch_ptr to end of data
        sta Svarl                   ; = new end of program / start of variables
        lda ch_ptr+1
        sta Svarh
        lda #0                      ; same as the warm start entry: clear any
        sta IrqBase                 ; ON IRQ / ON NMI set-up
        sta NmiBase
        lda #<LAB_RMSG              ; print CR,LF,"Ready",CR,LF
        ldy #>LAB_RMSG
        jsr ch_puts
        jmp LAB_1319                ; flush stack, CLEAR, rebuild line links, then
                                    ; wait for a command (we are not returning)

; ----------------------------------------------------------------------------
; CH_SAVE  - BASIC SAVE "name"
; ----------------------------------------------------------------------------
CH_SAVE:
        lda #0
        sta ch_raw
        jsr ch_get_filename
        lda ch_dir                  ; SAVE "$..." makes no sense
        beq @ok1
        ldx #EH_ERR_FC
        jmp LAB_XERR
@ok1:   jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_create          ; creates / replaces the file
        CH_OK ch_fail

        sec                         ; ch_len = Svarl - Smeml
        lda Svarl
        sbc Smeml
        sta ch_len
        lda Svarh
        sbc Smemh
        sta ch_len+1
        lda Smeml                   ; source = start of program
        sta ch_ptr
        lda Smemh
        sta ch_ptr+1
        jsr ch_write
        CH_OK ch_fail_close

        lda #1                      ; close AND update the file length
        jsr ch_file_close
        CH_OK ch_fail
        rts                         ; back to BASIC

; ----------------------------------------------------------------------------
; ch_get_filename - evaluate the string argument, build "/NAME.BAS",0 in
;                   ch_name. Raises normal BASIC errors for bad arguments.
; ----------------------------------------------------------------------------
ch_get_filename:
        jsr LAB_EVEX                ; evaluate the expression at the BASIC pointer
        jsr LAB_EVST                ; must be a string (else ?Type mismatch);
                                    ; A = length, (ut1_pl) -> characters
        sta ch_cnt
        beq @bad
        cmp #CH_NAME_MAX+1
        bcc @ok
        ldx #EH_ERR_LS              ; ?String too long
        jmp LAB_XERR
@bad:   ldx #EH_ERR_FC              ; empty name -> ?Function call error
        jmp LAB_XERR
@ok:    lda #0
        sta ch_dot
        sta ch_dir
        lda #'/'
        sta ch_name
        ldx #1                      ; X = index into ch_name
        ldy #0                      ; Y = index into the BASIC string
        lda (ut1_pl),y
        cmp #'$'
        bne @copy
        lda #1                      ; "$..." = directory request
        sta ch_dir
        sta ch_dot                  ; (so no ".BAS" is appended)
        iny                         ; skip the "$"
        cpy ch_cnt
        bne @copy                   ; "$pattern": copy the pattern
        lda #'*'                    ; plain "$": match everything
        sta ch_name,x
        inx
        bne @term                   ; always taken
@copy:  lda (ut1_pl),y
        cmp #'.'
        bne @upper
        lda #1
        sta ch_dot
        lda #'.'
        bne @store                  ; always taken
@upper: cmp #'a'
        bcc @store
        cmp #'z'+1
        bcs @store
        and #$DF                    ; to uppercase
@store: sta ch_name,x
        inx
        iny
        cpy ch_cnt
        bne @copy
        lda ch_dot
        bne @term
        lda ch_raw                  ; no "." typed: append ".BAS" (LOAD/SAVE),
        asl                         ; ".DAT" (LOADRAW/SAVERAW) or ".ARR"
        asl                         ; (LOADARR/SAVEARR), 4 characters each
        tay
        clc
        adc #4
        sta ch_dot                  ; (flag no longer needed) = end index
@ext:   lda ch_ext,y
        sta ch_name,x
        inx
        iny
        cpy ch_dot
        bne @ext
@term:  lda #0
        sta ch_name,x
        rts

ch_ext: .byte ".BAS"
        .byte ".DAT"
        .byte ".ARR"

; ----------------------------------------------------------------------------
; ch_prepare - make sure the CH376 is initialised and the disk is mounted
;   out: carry clear = ready, set = no disk
; ----------------------------------------------------------------------------
ch_prepare:
        lda ch_ready
        bne @ok
        jsr ch_init
        bcs @fail
        jsr ch_mount
        bcs @fail
        lda #1
        sta ch_ready
@ok:    clc
        rts
@fail:  sec
        rts

; ----------------------------------------------------------------------------
; ch_dirlist - LOAD "$" : list the directory named by ch_name ("/*" etc.)
;
; CH376 enumeration: SET_FILE_NAME "/*", FILE_OPEN. For every match the chip
; interrupts with USB_INT_DISK_READ and the 32-byte FAT directory entry can
; be read with RD_USB_DATA0.  FILE_ENUM_GO fetches the next one; ERR_MISS_FILE
; ($42) means there are no more.
;
; Entry layout: 0-7 name, 8-10 extension (space padded), 11 attributes,
;               28-31 file size (little endian)
; ----------------------------------------------------------------------------
ch_dirlist:
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #0
        sta ch_nfiles
        sta ch_nfiles+1
        lda #<ch_name
        ldx #>ch_name
        jsr ch_set_name
        lda #CMD_FILE_OPEN
        jsr ch_cmd
@next:  jsr ch_wait_status
        cmp #USB_INT_DISK_READ      ; $1D = an entry is available
        bne @end
        lda #CMD_RD_USB_DATA0
        jsr ch_cmd
        jsr ch_rd                   ; length (normally 32)
        sta ch_cnt
        ldy #0
@rd:    cpy ch_cnt
        bcs @got
        jsr ch_rd
        cpy #32
        bcs @skip                   ; never overflow ch_ent
        sta ch_ent,y
@skip:  iny
        bne @rd
@got:   lda ch_cnt
        cmp #32
        bcc @more                   ; short entry: ignore it
        jsr ch_print_entry
@more:  lda #CMD_FILE_ENUM_GO
        jsr ch_cmd
        jmp @next
@end:   cmp #ERR_MISS_FILE          ; $42 = end of directory
        beq @done
        jmp ch_fail                 ; anything else is a real error
@done:  lda ch_nfiles
        ora ch_nfiles+1
        bne @ret
        lda #<msg_nofiles
        ldy #>msg_nofiles
        jsr ch_puts                ; print null terminated string (A=lo, Y=hi)
@ret:   rts                         ; back to BASIC ("OK")

; ch_print_entry - print one line for the entry in ch_ent, or nothing if it is
; a volume label / hidden / system entry
ch_print_entry:
        lda ch_ent+11
        and #$0E                    ; volume label, hidden, system
        beq @show
        rts
@show:  inc ch_nfiles
        bne @c1
        inc ch_nfiles+1
@c1:    ldy #0
@name:  lda ch_ent,y
        cmp #' '
        beq @namedone
        jsr ch_putc
        iny
        cpy #8
        bcc @name
@namedone:
        sty ch_col                  ; characters printed so far
        lda ch_ent+8
        cmp #' '
        beq @pad                    ; no extension
        lda #'.'
        jsr ch_putc
        inc ch_col
        ldy #8
@ext:   lda ch_ent,y
        cmp #' '
        beq @pad
        jsr ch_putc
        inc ch_col
        iny
        cpy #11
        bcc @ext
@pad:   lda #' '                    ; pad the name field to 13 columns
        jsr ch_putc
        inc ch_col
        lda ch_col
        cmp #13
        bcc @pad
        lda ch_ent+11
        and #$10                    ; directory?
        beq @size
        lda #<msg_dir
        ldy #>msg_dir
        jsr ch_puts
        jmp @eol
@size:  ldx #3                      ; size -> ch_num
@cp:    lda ch_ent+28,x
        sta ch_num,x
        dex
        bpl @cp
        jsr ch_print_num
@eol:   jmp ch_crlf                 ; end of line (tail call)

; ch_print_num - print the 32-bit number in ch_num right-aligned in 10 columns
ch_print_num:
        lda #0
        sta ch_started
        ldy #0                      ; Y = 4 * index into ch_pow10
@digit: ldx #0                      ; X = this digit
@sub:   sec
        lda ch_num
        sbc ch_pow10,y
        sta ch_num
        lda ch_num+1
        sbc ch_pow10+1,y
        sta ch_num+1
        lda ch_num+2
        sbc ch_pow10+2,y
        sta ch_num+2
        lda ch_num+3
        sbc ch_pow10+3,y
        sta ch_num+3
        bcc @undo                   ; went negative: digit is complete
        inx
        jmp @sub
@undo:  clc                         ; add the power back
        lda ch_num
        adc ch_pow10,y
        sta ch_num
        lda ch_num+1
        adc ch_pow10+1,y
        sta ch_num+1
        lda ch_num+2
        adc ch_pow10+2,y
        sta ch_num+2
        lda ch_num+3
        adc ch_pow10+3,y
        sta ch_num+3
        lda ch_started
        bne @pr
        txa
        bne @pr
        cpy #36                     ; last digit is always printed
        beq @pr
        lda #' '                    ; leading zero -> space
        jmp @out
@pr:    lda #1
        sta ch_started
        txa
        clc
        adc #'0'
@out:   jsr ch_putc
        tya
        clc
        adc #4
        tay
        cpy #40
        beq @fin
        jmp @digit
@fin:   rts

ch_pow10:
        .dword 1000000000, 100000000, 10000000, 1000000, 100000
        .dword 10000, 1000, 100, 10, 1

; ch_putc - ch_prna (print char in A) that preserves X and Y
ch_putc:
        stx ch_sx
        sty ch_sy
        jsr ch_prna
        ldx ch_sx
        ldy ch_sy
        rts

msg_dir:     .byte "     <DIR>",0
msg_nofiles: .byte "NO FILES",13,10,0

; ----------------------------------------------------------------------------
; Error exits.  A = CH376 status or one of the CH_E_ codes.
; Prints a message, resets the stack and returns to the BASIC prompt.
; ----------------------------------------------------------------------------
ch_fail_close:                      ; same, but close the open file first
        pha
        lda #0
        jsr ch_file_close
        pla
ch_fail:
        cmp #ERR_MISS_FILE
        beq @nofile
        cmp #ERR_DISK_FULL
        beq @full
        cmp #CH_E_TOOBIG
        beq @toobig
        cmp #CH_E_BADFILE
        beq @badfile
        cmp #CH_E_NODISK
        beq @nodisk
        sta ch_stat                 ; anything else: remember the code,
        lda #0                      ; re-initialise next time
        sta ch_ready
        lda #<msg_io
        ldy #>msg_io
        jsr ch_puts                ; "?DISK ERROR"
        lda #' '                    ; then the CH376 status code in hex, e.g.
        jsr ch_prna                ; ?DISK ERROR $FF  ($FF = chip never answered)
        lda #'$'
        jsr ch_prna
        lda ch_stat
        lsr
        lsr
        lsr
        lsr
        jsr ch_hexdig
        lda ch_stat
        and #$0F
        jsr ch_hexdig
        lda ch_stat
        cmp #$FF
        bne @nodiag
        lda #<msg_diag1
        ldy #>msg_diag1
        jsr ch_puts
        lda ch_lastcmd
        jsr ch_hex2
        lda #<msg_diag2
        ldy #>msg_diag2
        jsr ch_puts
        lda ch_laststs
        jsr ch_hex2
        lda #')'
        jsr ch_prna
@nodiag:
        jmp @after
@nofile:  lda #<msg_nofile
          ldy #>msg_nofile
          jmp @print
@full:    lda #<msg_full
          ldy #>msg_full
          jmp @print
@toobig:  lda #<msg_toobig
          ldy #>msg_toobig
          jmp @print
@badfile: lda #<msg_badfile
          ldy #>msg_badfile
          jmp @print
@nodisk:  lda #<msg_nodisk
          ldy #>msg_nodisk
@print: jsr ch_puts                ; print string at (Y,A)
@after: lda ch_mon                  ; called from the monitor?
        beq @basic
        jsr ch_crlf                 ; (still in monitor mode: plain CR/LF)
        lda #0
        sta ch_mon
        jmp WOZ_ENTRY               ; yes: back to the monitor prompt
@basic: jsr LAB_1491                ; flush stack, clear continue flag
        jmp LAB_1274                ; BASIC warm start: "Ready" prompt

; ---- output wrappers: BASIC's print routines when called from BASIC, plain
;      CHROUT when called from the monitor (BASIC may never have been started)
ch_puts:                            ; print zero terminated string, A=lo Y=hi
        ldx ch_mon
        bne @mon
        jmp LAB_18C3
@mon:   sta strptr
        sty strptr+1
        ldy #0
@l:     lda (strptr),y
        beq @d
        jsr CHROUT
        iny
        bne @l
@d:     rts

ch_prna:                            ; print character in A
        pha
        lda ch_mon
        bne @mon
        pla
        jmp LAB_PRNA
@mon:   pla
        jmp CHROUT

ch_crlf:
        lda ch_mon
        bne @mon
        jmp LAB_CRLF
@mon:   lda #13
        jsr CHROUT
        lda #10
        jmp CHROUT

; print the low nibble of A as a hex digit
ch_hex2:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr ch_hexdig
        pla
        and #$0F
ch_hexdig:
        cmp #10
        bcc @dig
        adc #'A'-11                 ; carry is set here, so this adds 'A'-10
        jmp ch_prna
@dig:   adc #'0'
        jmp ch_prna

msg_nofile:  .byte 13,10,"?FILE NOT FOUND",0
msg_full:    .byte 13,10,"?DISK FULL",0
msg_toobig:  .byte 13,10,"?FILE TOO LARGE",0
msg_badfile: .byte 13,10,"?BAD FILE",0
msg_nodisk:  .byte 13,10,"?NO DISK",0
msg_diag1:   .byte " (CMD $",0
msg_diag2:   .byte ", PORT $",0
msg_io:      .byte 13,10,"?DISK ERROR",0

; ============================================================================
; LOADRAW "name" [, start]     SAVERAW "name", start, end
;
;   Raw memory block files (".DAT" is added when the name has no extension).
;   SAVERAW writes the bytes start .. end-1.   (end is NOT included)
;   LOADRAW reads the whole file to "start".  Without a start address the file
;   goes to the first byte above BASIC's memory (Ememl), i.e. into the area you
;   reserved with the "Memory size?" question at cold start.
;   LOADRAW only accepts targets from Ememl up to Ram_top-1, so it can never
;   overwrite the program, variables, strings or system RAM.  Anything else
;   (or a file that does not fit) is a ?FUNCTION CALL ERROR / ?FILE TOO BIG.
; ============================================================================

; ch_getaddr - evaluate a numeric expression as an address 0..65535
;   out: Itempl/Itemph = value.  ?Function call error if negative or > 65535
ch_getaddr:
        jsr LAB_EVNM                ; evaluate, must be numeric
        lda FAC1_s
        bmi ch_fc
        lda FAC1_e
        cmp #$91                    ; >= 65536 ?
        bcs ch_fc
        jmp LAB_F2FX                ; to Itempl/Itemph

ch_fc:  ldx #EH_ERR_FC
        jmp LAB_XERR

; ch_rawname - filename for the RAW commands (no directory listing)
ch_rawname:                         ; A = 1 (.DAT) or 2 (.ARR)
        sta ch_raw
        jsr ch_get_filename
        lda ch_dir
        bne ch_fc
        rts

BI_SAVERAW:
        lda #1
        jsr ch_rawname
        jsr LAB_1C01                ; ","
        jsr ch_getaddr
        lda Itempl
        sta ch_a0
        lda Itemph
        sta ch_a0+1
        jsr LAB_1C01                ; ","
        jsr ch_getaddr
        sec                         ; ch_len = end - start
        lda Itempl
        sbc ch_a0
        sta ch_len
        lda Itemph
        sbc ch_a0+1
        sta ch_len+1
        bcc ch_fc                   ; end < start
        ora ch_len
        beq ch_fc                   ; empty block
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_create
        CH_OK ch_fail
        lda ch_a0
        sta ch_ptr
        lda ch_a0+1
        sta ch_ptr+1
        jsr ch_write
        CH_OK ch_fail_close
        lda #1                      ; close AND update the file length
        jsr ch_file_close
        CH_OK ch_fail
        rts

BI_LOADRAW:
        lda #1
        jsr ch_rawname
        jsr LAB_GBYT                ; optional ", start"
        bne @addr
        lda Ememl                   ; default: first byte above BASIC memory
        sta ch_a0
        lda Ememh
        sta ch_a0+1
        jmp @check
@addr:  jsr LAB_1C01
        jsr ch_getaddr
        lda Itempl
        sta ch_a0
        lda Itemph
        sta ch_a0+1
@check: lda ch_a0+1                 ; start >= Ememl ?
        cmp Ememh
        bcc lr_fc
        bne @hiok
        lda ch_a0
        cmp Ememl
        bcc lr_fc
@hiok:  lda ch_a0+1                 ; start < Ram_top ?
        cmp #>Ram_top
        bcs lr_fc
        sec                         ; room = Ram_top - start
        lda #<Ram_top
        sbc ch_a0
        sta ch_len
        lda #>Ram_top
        sbc ch_a0+1
        sta ch_len+1
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_open
        CH_OK ch_fail
        lda ch_a0
        sta ch_ptr
        lda ch_a0+1
        sta ch_ptr+1
        jsr ch_read
        CH_OK ch_fail_close
        lda ch_got+1                ; got >= room?  -> file did not fit
        cmp ch_len+1
        bcc @fits
        bne @toobig
        lda ch_got
        cmp ch_len
        bcc @fits
@toobig:
        lda #CH_E_TOOBIG
        jmp ch_fail_close
@fits:  lda #0
        jsr ch_file_close
        CH_OK ch_fail
        rts
lr_fc:    jmp ch_fc

; ============================================================================
; SAVEARR "name", A()      LOADARR "name", A()
;
;   Saves / restores a whole numeric array (".ARR" is added when the name has
;   no extension).  The file holds the array's dimension header followed by its
;   data.  LOADARR needs the array to exist already (DIM it first) with exactly
;   the same dimensions, so it can only ever overwrite that array's own data.
;   String arrays (A$()) are not supported (?Type mismatch).
; ============================================================================

; ch_findarr - parse  NAME()  at the BASIC pointer and locate the array
;   out: (Astrtl) = start of the array entry:
;        +0,+1 name, +2,+3 size of whole entry, +4 dimensions, +5.. sizes, data
ch_findarr:
        jsr LAB_GBYT
        sta Varnm1
        jsr LAB_CASC                ; must start with a letter
        bcs @l1
        jmp LAB_SNER
@l1:    ldx #0
        stx Dtypef
        jsr LAB_IGBY                ; 2nd character
        bcc @two                    ; digit
        jsr LAB_CASC
        bcc @suffix                 ; not a letter
@two:   tax
@skip:  jsr LAB_IGBY                ; ignore further name characters
        bcc @skip
        jsr LAB_CASC
        bcs @skip
@suffix:
        cmp #'$'
        bne @nostr
        ldx #EH_ERR_TM              ; string arrays are not supported
        jmp LAB_XERR
@nostr: stx Varnm2
        cmp #'('
        beq @paren
        jmp LAB_SNER
@paren: jsr LAB_IGBY
        jsr LAB_1BFB                ; ")"

        ldx Sarryl                  ; search the array area (as LAB_1E17 does)
        lda Sarryh
@next:  stx Astrtl
        sta Astrth
        cmp Earryh
        bne @chk
        cpx Earryl
        beq @none
@chk:   ldy #0
        lda (Astrtl),y
        cmp Varnm1
        bne @skp
        iny
        lda (Astrtl),y
        cmp Varnm2
        beq @found
@skp:   ldy #2
        lda (Astrtl),y
        clc
        adc Astrtl
        tax
        iny
        lda (Astrtl),y
        adc Astrth
        bcc @next
@none:  jmp ch_fc                   ; no such array: ?Function call error
@found: ldy #4
        lda (Astrtl),y              ; dimensions
        cmp #16
        bcs @none                   ; header must fit in ch_ent
        rts

BI_SAVEARR:
        lda #2
        jsr ch_rawname
        jsr LAB_1C01                ; ","
        jsr ch_findarr
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_create
        CH_OK ch_fail
        ldy #2                      ; ch_len = size - 4
        sec
        lda (Astrtl),y
        sbc #4
        sta ch_len
        iny
        lda (Astrtl),y
        sbc #0
        sta ch_len+1
        clc                         ; ch_ptr = entry + 4
        lda Astrtl
        adc #4
        sta ch_ptr
        lda Astrth
        adc #0
        sta ch_ptr+1
        jsr ch_write
        CH_OK ch_fail_close
        lda #1
        jsr ch_file_close
        CH_OK ch_fail
        rts

BI_LOADARR:
        lda #2
        jsr ch_rawname
        jsr LAB_1C01                ; ","
        jsr ch_findarr
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_open
        CH_OK ch_fail
        ldy #4                      ; header = 1 + 2*dimensions bytes
        lda (Astrtl),y
        asl
        clc
        adc #1
        sta ch_len
        lda #0
        sta ch_len+1
        lda #<ch_ent
        sta ch_ptr
        lda #>ch_ent
        sta ch_ptr+1
        jsr ch_read
        CH_OK ch_fail_close
        lda ch_got+1
        bne la_bad
        lda ch_got
        cmp ch_len
        bne la_bad                    ; file shorter than a header
        ldx #0                      ; header must match the array exactly
        ldy #4
@cmp:   lda ch_ent,x
        cmp (Astrtl),y
        bne la_bad
        inx
        iny
        cpx ch_len
        bne @cmp
        lda ch_len                  ; data offset = 4 + header
        clc
        adc #4
        sta ch_cnt
        ldy #2                      ; ch_len = size - offset
        sec
        lda (Astrtl),y
        sbc ch_cnt
        sta ch_len
        iny
        lda (Astrtl),y
        sbc #0
        sta ch_len+1
        clc                         ; ch_ptr = entry + offset
        lda Astrtl
        adc ch_cnt
        sta ch_ptr
        lda Astrth
        adc #0
        sta ch_ptr+1
        jsr ch_read
        CH_OK ch_fail_close
        lda ch_got                  ; must have got everything
        cmp ch_len
        bne la_bad
        lda ch_got+1
        cmp ch_len+1
        bne la_bad
        lda #0
        jsr ch_file_close
        CH_OK ch_fail
        rts
la_bad:   lda #CH_E_BADFILE
        jmp ch_fail_close
