; ============================================================================
; monitor_cmds.s - extra wozmon commands
;
; wozmon.s calls MON_HOOK when Enter is pressed, before it parses the line.
; MON_HOOK looks at the start of the line in the input buffer IN ($0200):
;
;   ?                   list the commands
;   L                   list the files in the current directory of the USB drive
;   L DIR               change into directory DIR     L ..  up one level
;   L \  or  L /        back to the root directory     L A/B  several levels
;   L NAME [XXXX]       load NAME.BIN (from the current directory) into RAM at XXXX.
;                       Without XXXX the file goes to the last address used in
;                       the monitor (type the address, Enter, then L NAME).
;                       ".BIN" is added if NAME has no extension.
;                       Allowed targets: $0500-$7EFF.  Afterwards the monitor's
;                       current address is the load address, so  R  runs it.
;
; Returns carry set = line was a command and is finished, clear = not ours.
; "L" and "?" are not hex digits so they never clash with wozmon's own syntax.
; ============================================================================
.segment "BIOS"

MON_LOAD_MIN = $0500
MON_LOAD_TOP = $7F00                ; first address that is NOT loadable (I/O)

MON_HOOK:
        lda     IN
        cmp     #'?'
        bne     @notq
        lda     #<mon_help
        ldy     #>mon_help
        jsr     mon_puts
        sec
        rts
@notq:  cmp     #'L'
        bne     @not
        ldy     IN+1
        cpy     #$0D
        beq     @dir
        cpy     #' '
        beq     @load
@not:   clc
        rts

; ---- L : list the current directory -------------------------------------------
@dir:   lda     #1
        sta     ch_mon
        jsr     ch_prepare
        bcc     @lp
        lda     #CH_E_NODISK
        jmp     ch_fail
@lp:    jsr     mon_copy_cwd        ; X = length of the current directory
        stx     mon_end
        cpx     #0
        beq     @lroot
        jsr     mon_enter           ; open it, step by step (name "*" is then relative)
        cmp     #ERR_OPEN_DIR
        beq     @lrel
        jmp     ch_fail
@lrel:  ldx     #0                  ; ch_name = "*"
        beq     @lset
@lroot: ldx     #1                  ; ch_name = "/*"
        lda     #'/'
        sta     ch_name
@lset:  lda     #'*'
        sta     ch_name,x
        lda     #0
        sta     ch_name+1,x
        jsr     mon_showcwd         ; CR LF, "/GAMES"
        lda     #<mon_crlf
        ldy     #>mon_crlf
        jsr     mon_puts
        jsr     ch_dirlist
        lda     #0
        sta     ch_mon
        sec
        rts

; ---- L PATH [XXXX] : change directory, or load a file ---------------------------
; PATH is relative to the current directory; "..", ".", a leading "/" or "\"
; and several parts ("GAMES/DEEP") are understood.  A PATH that names a directory
; changes into it, anything else is a file (".BIN" is added when it has no ".").
@load:  ldy     #1
@sp1:   lda     IN,y                ; skip blanks
        cmp     #' '
        bne     @a1
        iny
        bne     @sp1
@a1:    cmp     #$0D
        beq     @dir                ; "L   " = list
        sty     mon_y
        jsr     mon_path            ; ch_name = new path
        bcc     @pok
        jmp     mon_badpath
@pok:   lda     mon_kind
        bne     @cd                 ; ends in "..", "." or "/": a directory
        lda     mon_x
        beq     @cd                 ; the root
        lda     mon_flag
        bne     @tail               ; has a ".": a file
        lda     #1                  ; no ".": ask the drive what it is
        sta     ch_mon
        jsr     ch_prepare
        bcc     @pr1
        lda     #CH_E_NODISK
        jmp     ch_fail
@pr1:   jsr     mon_open
        cmp     #ERR_OPEN_DIR
        beq     @isdir
        cmp     #USB_INT_SUCCESS
        beq     @isfile
        cmp     #ERR_MISS_FILE
        beq     @addext
        jmp     ch_fail
@isdir: lda     #0
        jsr     ch_file_close
        lda     #0
        sta     ch_mon
        jmp     @cd
@isfile:
        lda     #0
        jsr     ch_file_close
        jmp     @tail
@addext:
        ldx     mon_x               ; not found as typed: try  NAME.BIN
        ldy     #0
@e:     lda     mon_bin,y
        sta     ch_name,x
        inx
        iny
        cpy     #4
        bne     @e
        lda     #0
        sta     ch_name,x
@tail:  ldy     mon_y               ; continue with the optional address
        jmp     @addr

@cd:    lda     mon_x               ; the new directory is ch_name
        cmp     #32
        bcs     @cdbad              ; longer than 31 characters: cannot keep it
        ldx     #0
@cc:    lda     ch_name,x
        sta     mon_cwd,x
        beq     @cdd
        inx
        bne     @cc
@cdd:   jsr     mon_showcwd
        sec
        rts
@cdbad: jmp     mon_badpath

@addr:  lda     XAML                ; default address = monitor's current one
        sta     ch_a0
        lda     XAMH
        sta     ch_a0+1
@sp2:   lda     IN,y
        cmp     #' '
        bne     @a0
        iny
        bne     @sp2
@a0:    cmp     #$0D
        beq     @check              ; no address typed: use the default
        lda     #0
        sta     ch_a0
        sta     ch_a0+1
        ldx     #0                  ; digit count
@hex:   lda     IN,y
        cmp     #$0D
        beq     @hexend
        cmp     #' '
        beq     @hexend
        sec
        sbc     #'0'
        bcc     @hbad
        cmp     #10
        bcc     @dig
        sbc     #7                  ; "A".."F"
        cmp     #10
        bcc     @hbad
        cmp     #16
        bcs     @hbad
@dig:   asl     ch_a0
        rol     ch_a0+1
        asl     ch_a0
        rol     ch_a0+1
        asl     ch_a0
        rol     ch_a0+1
        asl     ch_a0
        rol     ch_a0+1
        ora     ch_a0
        sta     ch_a0
        inx
        iny
        cpx     #5
        bcc     @hex
@hbad:  jmp     mon_syntax          ; bad digit, or more than 4 digits
@hexend:
        cpx     #0
        beq     @hbad
@check: lda     ch_a0+1             ; MON_LOAD_MIN <= address < MON_LOAD_TOP
        cmp     #>MON_LOAD_MIN
        bcc     @hbad
        cmp     #>MON_LOAD_TOP
        bcs     @hbad
        sec                         ; room = top - address
        lda     #<MON_LOAD_TOP
        sbc     ch_a0
        sta     ch_len
        lda     #>MON_LOAD_TOP
        sbc     ch_a0+1
        sta     ch_len+1

        lda     #1
        sta     ch_mon
        lda     #<mon_crlf
        ldy     #>mon_crlf
        jsr     mon_puts
        jsr     ch_prepare
        bcc     @ready
        lda     #CH_E_NODISK
        jmp     ch_fail
@ready: jsr     mon_open
        CH_OK   ch_fail
        lda     ch_a0
        sta     ch_ptr
        lda     ch_a0+1
        sta     ch_ptr+1
        jsr     ch_read
        CH_OK   ch_fail_close
        lda     ch_got+1            ; got >= room -> did not fit
        cmp     ch_len+1
        bcc     @fits
        bne     @big
        lda     ch_got
        cmp     ch_len
        bcc     @fits
@big:   lda     #CH_E_TOOBIG
        jmp     ch_fail_close
@fits:  lda     #0
        jsr     ch_file_close
        CH_OK   ch_fail
        lda     #0
        sta     ch_mon
        lda     ch_a0               ; monitor's current address = load address
        sta     XAML
        lda     ch_a0+1
        sta     XAMH
        lda     #<mon_loaded        ; "LOADED xxxx-yyyy"
        ldy     #>mon_loaded
        jsr     mon_puts
        lda     ch_a0+1
        jsr     PRBYTE
        lda     ch_a0
        jsr     PRBYTE
        lda     ch_got              ; empty file: nothing loaded
        ora     ch_got+1
        beq     @empty
        lda     #'-'
        jsr     CHROUT
        lda     ch_ptr              ; ch_read left ch_ptr after the data
        sec
        sbc     #1
        tax
        lda     ch_ptr+1
        sbc     #0
        jsr     PRBYTE
        txa
        jsr     PRBYTE
        sec
        rts
@empty: lda     #<mon_empty
        ldy     #>mon_empty
        jsr     mon_puts
        sec
        rts
mon_syntax:
        lda     #<mon_bad
        ldy     #>mon_bad
        jsr     mon_puts
        sec
        rts

; print zero terminated string, A = lo, Y = hi
mon_puts:
        sta     strptr
        sty     strptr+1
        ldy     #0
@l:     lda     (strptr),y
        beq     @d
        jsr     CHROUT
        iny
        bne     @l
        inc     strptr+1            ; strings may be longer than 256 bytes
        bne     @l
@d:     rts

mon_bin:     .byte ".BIN"
mon_crlf:    .byte 13,10,0
mon_loaded:  .byte 13,10,"LOADED ",0
mon_empty:   .byte " (EMPTY FILE)",0
mon_bad:     .byte 13,10,"?SYNTAX  (L NAME [XXXX], XXXX = $0500-$7EFF)",0
mon_badp:    .byte 13,10,"?BAD PATH",0
mon_help:
        .byte 13,10
        .byte "?             this list",13,10
        .byte "XXXX          show the byte at address XXXX",13,10
        .byte "XXXX.YYYY     show a range of memory",13,10
        .byte "XXXX: AA BB   store bytes starting at XXXX",13,10
        .byte "R             run the program at the last address (XXXXR)",13,10
        .byte "L             list the files in the current USB directory",13,10
        .byte "L DIR         change into directory DIR",13,10
        .byte "L ..          up one level      L \ or L /   back to the root",13,10
        .byte "L NAME [XXXX] load NAME.BIN from the current directory into RAM at",13,10
        .byte "              XXXX (default: the last address; range $0500-$7EFF)",13,10
        .byte "CTRL-C        back to the boot menu",0


; ---------------------------------------------------------------------------
; Current directory and path helpers
; ---------------------------------------------------------------------------
.segment "BIOSVARS"
mon_cwd:    .res 32                 ; current directory: "" (root) or "/A/B" (max 31)
.segment "CHVARS"
mon_x:      .res 1                  ; length of the path in ch_name
mon_y:      .res 1                  ; read position in the input line
mon_cl:     .res 1                  ; length of the path part being read
mon_kind:   .res 1                  ; 1 = path ends in a directory ("..", ".", "/")
mon_end:    .res 1                  ; end of the directory part of ch_name
mon_t:      .res 1
mon_flag:   .res 1                  ; 1 = last part contains a "."
mon_comp    = ch_ent                ; scratch: the path part being read (ch_ent is free here)
.segment "BIOS"

ERR_OPEN_DIR     = $41              ; CH376: FILE_OPEN found a directory

; mon_enter - open the directories of the path in ch_name[0..mon_end) one level
; at a time ("/A" first, then "B" relative to it).  The CH376 keeps the last
; directory it opened as the current one.
;   out: A = status of the last open (ERR_OPEN_DIR = all went well)
mon_enter:
        ldy     #0
@next:  cpy     mon_end
        bcs     @done
        ldx     #0
        lda     ch_name,y           ; the '/'
        cpy     #0
        bne     @skip               ; only the first name starts with '/'
        sta     mon_comp,x
        inx
@skip:  iny
@cp:    cpy     mon_end
        bcs     @end
        lda     ch_name,y
        cmp     #'/'
        beq     @end
        sta     mon_comp,x
        inx
        iny
        bne     @cp
@end:   lda     #0
        sta     mon_comp,x
        sty     mon_t
        lda     #<mon_comp
        ldx     #>mon_comp
        jsr     ch_file_open
        ldy     mon_t
        cmp     #ERR_OPEN_DIR
        beq     @next
        rts
@done:  lda     #ERR_OPEN_DIR
        rts

; mon_open - FILE_OPEN the full path in ch_name ("/NAME.EXT" or "/A/B/NAME.EXT")
;   out: A = status.  Directories are entered one level at a time first.
mon_open:
        ldx     #0
        stx     mon_end             ; position of the last '/'
@f:     lda     ch_name,x
        beq     @e
        cmp     #'/'
        bne     @n
        stx     mon_end
@n:     inx
        bne     @f
@e:     lda     mon_end
        beq     @root               ; file in the root directory
        jsr     mon_enter
        cmp     #ERR_OPEN_DIR
        bne     @r
        ldx     mon_end             ; the last part, now relative
        inx
        ldy     #0
@m:     lda     ch_name,x
        sta     mon_comp,y
        beq     @go
        inx
        iny
        bne     @m
@go:    lda     #<mon_comp
        ldx     #>mon_comp
        jmp     ch_file_open
@root:  lda     #<ch_name
        ldx     #>ch_name
        jmp     ch_file_open
@r:     rts

; mon_copy_cwd - ch_name = mon_cwd, mon_x = X = its length
mon_copy_cwd:
        ldx     #0
@l:     lda     mon_cwd,x
        sta     ch_name,x
        beq     @d
        inx
        bne     @l
@d:     stx     mon_x
        rts

; mon_showcwd - CR LF and the current directory ("/" for the root)
mon_showcwd:
        lda     #<mon_crlf
        ldy     #>mon_crlf
        jsr     mon_puts
        lda     mon_cwd
        bne     @p
        lda     #'/'
        jmp     CHROUT
@p:     lda     #<mon_cwd
        ldy     #>mon_cwd
        jmp     mon_puts

mon_badpath:
        lda     #<mon_badp
        ldy     #>mon_badp
        jsr     mon_puts
        sec
        rts

; mon_path - turn the text at IN+mon_y into a full path in ch_name (starting at
; the current directory unless the text begins with "/" or "\").
;   out: carry clear: ch_name = path ("" = root), mon_x = its length,
;        mon_kind = 1 if it ends in ".." "." or "/", mon_flag = last part has a ".",
;        mon_y = index of the character after the path (blank or CR)
;        carry set: path too long / part too long
mon_path:
        jsr     mon_copy_cwd
        lda     #0
        sta     mon_kind
        sta     mon_flag
        ldy     mon_y
        lda     IN,y
        cmp     #'/'
        beq     @abs
        cmp     #'\'
        bne     @comp
@abs:   iny                         ; absolute: start again at the root
        lda     #0
        sta     mon_x
        sta     ch_name
        lda     #1
        sta     mon_kind
@comp:  lda     IN,y
        cmp     #$0D
        beq     @fin
        cmp     #' '
        beq     @fin
        bne     @nfin
@fin:   jmp     @end
@nfin:  cmp     #'/'
        beq     @sep
        cmp     #'\'
        bne     @word
@sep:   iny
        lda     #1                  ; a trailing separator means "directory"
        sta     mon_kind
        bne     @comp
@word:  ldx     #0                  ; read one part into mon_comp
@rd:    lda     IN,y
        cmp     #$0D
        beq     @wend
        cmp     #' '
        beq     @wend
        cmp     #'/'
        beq     @wend
        cmp     #'\'
        beq     @wend
        cpx     #13
        bcs     @err
        sta     mon_comp,x
        inx
        iny
        bne     @rd
@err:   sec
        rts
@wend:  lda     #0
        sta     mon_comp,x
        sty     mon_y
        stx     mon_cl
        cpx     #1
        bne     @n2
        lda     mon_comp
        cmp     #'.'
        bne     @norm
        lda     #1                  ; "."  stay where we are
        sta     mon_kind
        bne     @next
@n2:    cpx     #2
        bne     @norm
        lda     mon_comp
        cmp     #'.'
        bne     @norm
        lda     mon_comp+1
        cmp     #'.'
        bne     @norm
        ldx     mon_x               ; ".."  drop the last part
        beq     @popd
@pl:    dex
        lda     ch_name,x
        cmp     #'/'
        beq     @popd
        cpx     #0
        bne     @pl
@popd:  stx     mon_x
        lda     #0
        sta     ch_name,x
        lda     #1
        sta     mon_kind
        bne     @next
@norm:  lda     mon_x               ; room for "/" + part?  (max 40 characters)
        clc
        adc     mon_cl
        adc     #1
        cmp     #41
        bcs     @err
        ldx     mon_x
        lda     #'/'
        sta     ch_name,x
        inx
        ldy     #0
        sty     mon_flag
@cp:    lda     mon_comp,y
        beq     @cpd
        cmp     #'.'
        bne     @nd
        pha
        lda     #1
        sta     mon_flag
        pla
@nd:    sta     ch_name,x
        inx
        iny
        bne     @cp
@cpd:   lda     #0
        sta     ch_name,x
        stx     mon_x
        sta     mon_kind            ; (A = 0)
@next:  ldy     mon_y
        jmp     @comp
@end:   sty     mon_y
        clc
        rts

; ============================================================================
; SBC_LOAD - load a whole file into RAM, for programs (jump table entry $FE15)
;
;   In : A = low, Y = high byte of a parameter block anywhere in RAM:
;           +0 .word  address to load to
;           +2 .word  most bytes to write (a longer file is cut off, still OK)
;           +4 .byte  file name, 8.3, root directory, ends with a 0 byte
;   Out: carry clear = loaded, X = length low, Y = length high
;        carry set   = failed, A = error code: the CH376 status ($42 = file not
;                      found), $FF = timeout / no drive, $FE = bad parameter block
;   Prints nothing, never jumps to the monitor, closes the file before it
;   returns.  Changes A, X, Y and flags (and strptr, the firmware's own zero
;   page bytes).  Never writes beyond address + max - 1.
; ============================================================================
SBC_LOAD_USES_CWD = 1               ; 1 = names are relative to the monitor's current
                                    ; directory (L DIR), 0 = always the root directory
SBC_LOAD:
        sta     strptr
        sty     strptr+1
        jsr     mon_copy_cwd        ; build "<current dir>/NAME.EXT",0 in ch_name
        lda     #SBC_LOAD_USES_CWD
        bne     @cw
        ldx     #0                  ; root only
@cw:    lda     #'/'
        sta     ch_name,x
        inx
        stx     mon_x               ; start of the file name part
        txa
        clc
        adc     #12                 ; at most 12 characters
        sta     mon_cl
        ldy     #4
@cp:    lda     (strptr),y
        beq     @term
        cpx     mon_cl
        bcs     @bad
        cmp     #'a'                ; lower case -> upper case
        bcc     @st
        cmp     #'z'+1
        bcs     @st
        and     #$DF
@st:    sta     ch_name,x
        inx
        iny
        bne     @cp
@bad:   lda     #$FE                ; bad parameter block
        sec
        rts
@term:  lda     #0
        sta     ch_name,x
        cpx     mon_x
        beq     @bad                ; empty name
        ldy     #0                  ; address and limit from the block
        lda     (strptr),y
        sta     ch_a0
        iny
        lda     (strptr),y
        sta     ch_a0+1
        iny
        lda     (strptr),y
        sta     ch_len
        iny
        lda     (strptr),y
        sta     ch_len+1
        jsr     ch_prepare          ; initialise the CH376 / mount if needed
        bcs     sl_nodisk
                jsr     mon_open
        cmp     #USB_INT_SUCCESS
        bne     sl_err              ; (nothing is open: no close needed)
        lda     ch_len
        ora     ch_len+1
        beq     sl_zero             ; room for 0 bytes: just report the file exists
        lda     ch_a0
        sta     ch_ptr
        lda     ch_a0+1
        sta     ch_ptr+1
        jsr     ch_read             ; reads at most ch_len bytes
        cmp     #USB_INT_SUCCESS
        bne     sl_rderr
        lda     #0
        jsr     ch_file_close
        ldx     ch_got
        ldy     ch_got+1
        clc
        rts
sl_zero:
        lda     #0
        jsr     ch_file_close
        ldx     #0
        ldy     #0
        clc
        rts
sl_rderr:
        pha                         ; read failed: close, start afresh next time
        lda     #0
        sta     ch_ready
        lda     #0
        jsr     ch_file_close
        pla
        sec
        rts
sl_err: cmp     #ERR_MISS_FILE      ; "file not found" is a normal answer
        beq     @ret
        pha
        lda     #0
        sta     ch_ready            ; anything else: re-initialise next time
        pla
@ret:   sec
        rts
sl_nodisk:
        lda     #0
        sta     ch_ready
        lda     #$FF
        sec
        rts