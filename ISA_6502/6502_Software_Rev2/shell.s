; ============================================================================
; shell.s - a file manager (or any "shell" program) kept in a RAM bank, and
;           the monitor's prompt.  Stage 6.
;
; A shell is a program that runs in the banked window of one RAM bank (1-15).
; Its bank starts with:   $1000  JMP entry     (entered with that bank selected)
;                         $1003  "SH65"        (the signature)
; Programs it starts run in bank 0 from $0800, as from the monitor; when they
; finish (JMP SBC_MENU) the ROM goes back to the shell instead of the boot
; menu.  After a reset the boot menu looks for a shell in the banks and
; offers [G] to go back to it.
;
;   SBC_DIR    $FE57  read the current folder into a table
;   SBC_RUN    $FE5A  load and start a program (.BIN) or a BASIC program
;   SBC_SHELL  $FE5D  A = the shell's bank (0 = none)
;   SBC_COPY   $FE60  copy a file (any folder, either drive), through the
;                     RAM banks other than the caller's
;   SBC_DELETE $FE63  delete a file
; ============================================================================

SH_ENTRY        = $1000
SH_SIG          = $1003
DIRLINE         = 40                    ; the longest listing line looked at

.segment "DRVVARS"
sh_bank:        .res 1                  ; the shell's bank, 0 = none
sh_cur:         .res 1                  ; (the caller's bank)
dir_cap:        .res 1                  ; bit 7: listings go to dir_char
dir_sp:         .res 1                  ; the stack to go back to on an error
dir_max:        .res 1
dir_n:          .res 1
dir_len:        .res 1
dir_sx:         .res 1
dir_sy:         .res 1
dir_ent:        .res 16                 ; the entry being made
dir_line:       .res DIRLINE
dir_t:          .res 4
run_kind:       .res 1
run_blk:        .res 4 + 13             ; SBC_LOAD's block: $0800, $7700, name
run_t:          .res 1
cp_dst:         .res 46                 ; SBC_COPY: the destination's path
cp_sdev:        .res 1                  ;   the devices ('U' / 'C')
cp_ddev:        .res 1
cp_b:           .res 1                  ;   the next bank to look at
cp_n:           .res 1                  ;   banks filled
cp_k:           .res 1
cp_last:        .res 2                  ;   bytes in the last bank
cp_probe:       .res 1

.segment "BIOS"

; ----------------------------------------------------------------------------
; sh_ok - C=0 if bank A holds a shell (its signature).  Keeps the selected
; bank (and X).
; ----------------------------------------------------------------------------
sh_ok:  sta     run_t
        lda     bank_cur
        sta     sh_cur
        lda     run_t
        beq     @no
        cmp     bank_count
        bcs     @no
        jsr     BANK_SET
        ldy     #3
@c:     lda     SH_SIG,y
        cmp     sh_sigtxt,y
        bne     @nb
        dey
        bpl     @c
        lda     sh_cur
        jsr     BANK_SET
        clc
        rts
@nb:    lda     sh_cur
        jsr     BANK_SET
@no:    sec
        rts
sh_sigtxt:
        .byte   "SH65"

; sh_find - A = the highest bank holding a shell, C=0; C=1 none
sh_find:
        ldx     bank_count
@b:     dex
        beq     @none
        txa
        jsr     sh_ok
        bcs     @b
        txa
        clc
        rts
@none:  sec
        rts

; ----------------------------------------------------------------------------
; SBC_SHELL - A = the shell's bank (1-15), C=1 if there is no shell there;
; A = 0: no shell (SBC_MENU goes to the boot menu again)
; ----------------------------------------------------------------------------
sbc_shell:
        cmp     #0
        beq     @set
        pha
        jsr     sh_ok
        pla
        bcs     @r
@set:   sta     sh_bank
        clc
@r:     rts

; ----------------------------------------------------------------------------
; shell_menu - SBC_MENU: back to the shell if there is one, else the boot menu
; ----------------------------------------------------------------------------
shell_menu:
        lda     sh_bank
        beq     @menu
        jsr     sh_ok
        bcc     sh_enter
        lda     #0
        sta     sh_bank
@menu:  jmp     MENU

; sh_enter - start the shell in bank sh_bank (a clean stack, sound off)
sh_enter:
        cld
        ldx     #$FF
        txs
        jsr     BI_QUIET
        lda     #0
        sta     ld_on
        sta     dir_cap
        sta     ch_mon
        lda     sh_bank
        jsr     BANK_SET
        cli
        jmp     SH_ENTRY

; ----------------------------------------------------------------------------
; SBC_DIR - the current folder (SBC_CWD) of a device, as a table
;   In : A/Y = a block:  +0 .word table, +2 .byte the most entries,
;                        +3 .byte the device: 'U', 'C' or 0 (as it is)
;   Out: C=0, A = entries put in the table, 16 bytes each:
;          0-7 name, 8-10 extension (both space padded), 11 attributes
;          ($10 = a folder), 12-15 size (little endian).  "." and ".." are
;          left out.
;        C=1, A = error code (as SBC_LOAD's; $FE = bad device)
;   The table may be in any bank's window: the caller's bank stays selected.
; ----------------------------------------------------------------------------
sbc_dir:
        sta     strptr
        sty     strptr+1
        tsx
        stx     dir_sp
        ldy     #0
        lda     (strptr),y
        sta     dir_ptr
        iny
        lda     (strptr),y
        sta     dir_ptr+1
        iny
        lda     (strptr),y
        sta     dir_max
        iny
        lda     (strptr),y
        beq     @dev
        jsr     fs_letter
        bcc     @dev
        lda     #$FE
        rts
@dev:   lda     #0
        sta     dir_n
        sta     dir_len
        lda     #1
        sta     ch_mon
        lda     #$80
        sta     dir_cap
        jsr     fs_prepare
        bcc     :+
        lda     #CH_E_NODISK
        jmp     dir_fail
:       jsr     mon_copy_cwd        ; the folder, as the monitor's L does it
        stx     mon_end
        cpx     #0
        beq     @root
        jsr     mon_enter
        cmp     #ERR_OPEN_DIR
        beq     @rel
        jmp     dir_fail
@rel:   ldx     #0
        beq     @set
@root:  ldx     #1
        lda     #'/'
        sta     ch_name
@set:   lda     #'*'
        sta     ch_name,x
        lda     #0
        sta     ch_name+1,x
        jsr     fs_dirlist
        lda     #13                 ; (a last line without its end)
        jsr     dir_char
        lda     #0
        sta     dir_cap
        sta     ch_mon
        lda     dir_n
        clc
        rts

; dir_fail - an error while listing (also from ch_fail): back to SBC_DIR's
; caller, C=1, A = the code
dir_fail:
        ldx     dir_sp
        txs
        pha
        lda     #0
        sta     dir_cap
        sta     ch_mon
        jsr     fs_unready
        pla
        sec
        rts

; ch_out - the monitor-style output of the CH376 / IDE code: to the console,
; or a listing line being read (keeps X, Y)
ch_out: bit     dir_cap
        bmi     dir_char
        jmp     CHROUT

; dir_char - a character of the listing: collect a line; at its end, make
; an entry of it if it is "NAME.EXT  <DIR>" or "NAME.EXT  12345"
dir_char:
        stx     dir_sx
        sty     dir_sy
        cmp     #13
        beq     @eol
        cmp     #10
        beq     @eol
        ldx     dir_len
        cpx     #DIRLINE
        bcs     @r
        sta     dir_line,x
        inc     dir_len
@r:     ldx     dir_sx
        ldy     dir_sy
        rts
@eol:   lda     dir_len
        beq     @r
        jsr     dir_parse
        lda     #0
        sta     dir_len
        beq     @r

dp_no:  rts

; dir_parse - dir_line (dir_len) -> an entry at (dir_ptr), if it is one
dir_parse:
        ldx     #15                 ; blank entry: spaces, then zeros
@clr:   lda     #0
        cpx     #11
        bcs     :+
        lda     #' '
:       sta     dir_ent,x
        dex
        bpl     @clr
        ldx     #0
        jsr     dp_blanks
        ldy     #0                  ; the name: 1-8 characters
@nm:    jsr     dp_char
        bcs     @nme
        cmp     #'.'
        beq     @nme
        cpy     #8
        bcs     dp_no
        sta     dir_ent,y
        iny
        inx
        bne     @nm
@nme:   cpy     #0
        beq     dp_no                 ; ("." and ".." too)
        cmp     #'.'
        bne     @sp
        inx                         ; the extension: up to 3
        ldy     #8
@ex:    jsr     dp_char
        bcs     @sp
        cpy     #11
        bcs     dp_no
        sta     dir_ent,y
        iny
        inx
        bne     @ex
@sp:    jsr     dp_blanks           ; then <DIR> or the size
        cpx     dir_len
        bcs     @no
        lda     dir_line,x
        cmp     #'<'
        bne     @num
        lda     #$10
        sta     dir_ent+11
        bne     @put
@num:   jsr     dp_digit
        bcs     @no
@dg:    pha                         ; size = size * 10 + digit
        jsr     dp_x10
        pla
        clc
        adc     dir_ent+12
        sta     dir_ent+12
        bcc     :+
        inc     dir_ent+13
        bne     :+
        inc     dir_ent+14
        bne     :+
        inc     dir_ent+15
:       inx
        cpx     dir_len
        bcs     @put
        jsr     dp_digit
        bcc     @dg
@put:   lda     dir_n               ; room for it?
        cmp     dir_max
        bcs     @no
        inc     dir_n
        ldy     #15
@cp:    lda     dir_ent,y
        sta     (dir_ptr),y
        dey
        bpl     @cp
        lda     dir_ptr
        clc
        adc     #16
        sta     dir_ptr
        bcc     @no
        inc     dir_ptr+1
@no:    rts

; X past the blanks in dir_line
dp_blanks:
        cpx     dir_len
        bcs     @r
        lda     dir_line,x
        cmp     #' '
        bne     @r
        inx
        bne     dp_blanks
@r:     rts
; the name character at X: C=1 at a blank or the end (A = '.' if a dot)
dp_char:
        cpx     dir_len
        bcs     @end
        lda     dir_line,x
        cmp     #' '+1
        bcc     @end
        cmp     #'a'                ; (upper case)
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       clc
        rts
@end:   sec
        rts
; the digit at X -> A (0-9), C=0; C=1 not a digit
dp_digit:
        lda     dir_line,x
        sec
        sbc     #'0'
        cmp     #10
        rts
; dir_ent+12..15 * 10 (= * 2 + * 8)
dp_x10: asl     dir_ent+12
        rol     dir_ent+13
        rol     dir_ent+14
        rol     dir_ent+15
        ldy     #3
@k:     lda     dir_ent+12,y
        sta     dir_t,y
        dey
        bpl     @k
        ldy     #2
@s:     asl     dir_ent+12
        rol     dir_ent+13
        rol     dir_ent+14
        rol     dir_ent+15
        dey
        bne     @s
        clc
        ldy     #0
@a:     lda     dir_ent+12,y
        adc     dir_t,y
        sta     dir_ent+12,y
        iny
        tya
        eor     #4
        bne     @a
        rts

; ----------------------------------------------------------------------------
; SBC_RUN - load a program from the current folder (SBC_CWD) and start it
;   In : A/Y = a block:  +0 .byte 0 = a program (.BIN, loaded and run at
;                              $0800 in bank 0), 1 = a BASIC program (BASIC
;                              is started, the program loaded and RUN)
;                        +1 .byte the device: 'U', 'C' or 0 (as it is)
;                        +2 the file name, 8.3, ending with a 0 byte
;   Out: only on an error: C=1, A = the code (as SBC_LOAD's), the caller's
;        bank selected again
;   The display is put back to the text console and the mouse turned off
;   before the program starts.  When it ends with JMP SBC_MENU, the shell
;   (SBC_SHELL) runs again.
; ----------------------------------------------------------------------------
sbc_run:
        sta     strptr
        sty     strptr+1
        lda     bank_cur
        sta     sh_cur
        ldy     #1
        lda     (strptr),y
        beq     @dev
        jsr     fs_letter
        bcs     @bad
@dev:   ldy     #0
        lda     (strptr),y
        sta     run_kind
        ldx     #0                  ; the name (before leaving the caller's bank)
        ldy     #2
@c:     lda     (strptr),y
        sta     run_blk+4,x
        beq     @cd
        inx
        iny
        cpx     #13
        bcc     @c
@bad:   lda     #$FE
        sec
        rts
@cd:    cpx     #0
        beq     @bad
        lda     #<USER_RAM
        sta     run_blk
        lda     #>USER_RAM
        sta     run_blk+1
        lda     #<($7F00 - USER_RAM)
        sta     run_blk+2
        lda     #>($7F00 - USER_RAM)
        sta     run_blk+3
        lda     run_kind
        bne     run_bas
        lda     #0                  ; the program, into bank 0
        jsr     BANK_SET
        lda     #<run_blk
        ldy     #>run_blk
        jsr     SBC_LOAD
        bcc     :+
        pha                         ; failed: back to the caller
        lda     sh_cur
        jsr     BANK_SET
        pla
        sec
        rts
:       jsr     run_prep
        ldx     #$FF
        txs
        cli
        jmp     USER_RAM

; run_prep - bank 0, quiet, the text console, no mouse, a clean input buffer
run_prep:
        lda     #0
        jsr     BANK_SET
        jsr     BI_QUIET
        lda     #0
        jsr     jt_mouseon
        jsr     jt_conreset
        jmp     INIT_BUFFER

; a BASIC program: BASIC's cold start, with the keys typed for it:
;   Enter (the memory size), LOAD "path/NAME.BAS" Enter, RUN Enter
run_bas:
        jsr     run_prep
        sei
        lda     #13
        jsr     CON_PUTKEY
        ldy     #0
@l:     lda     run_load,y
        beq     @path
        jsr     CON_PUTKEY
        iny
        bne     @l
@path:  lda     fs_dev              ; "U:" or "C:"
        tay
        lda     run_dev,y
        jsr     CON_PUTKEY
        lda     #':'
        jsr     CON_PUTKEY
        ldy     #1                  ; the folder without its first "/"
@p:     lda     mon_cwd,y
        beq     @pe
        jsr     CON_PUTKEY
        iny
        bne     @p
@pe:    cpy     #1
        beq     @nm                 ; (the top folder)
        lda     #'/'
        jsr     CON_PUTKEY
@nm:    ldy     #0
@n:     lda     run_blk+4,y
        beq     @ne
        jsr     CON_PUTKEY
        iny
        bne     @n
@ne:    ldy     #0
@r:     lda     run_run,y
        beq     @go
        jsr     CON_PUTKEY
        iny
        bne     @r
@go:    cli
        ldx     #$FF
        txs
        jmp     LAB_COLD
run_load:
        .byte   "LOAD ", '"', 0
run_run:
        .byte   '"', 13, "RUN", 13, 0
run_dev:
        .byte   "UC"

; ----------------------------------------------------------------------------
; SBC_COPY - copy a file
;   In : A/Y = a block:  +0 .byte the source's device ('U' / 'C')
;                        +1 .word -> its full path, "/A/B/NAME.EXT",0
;                        +3 .byte the destination's device
;                        +4 .word -> its full path (replaced if it exists)
;   Out: C=0 copied; C=1, A = the error (CH_E_TOOBIG $F0: it doesn't fit)
;   The whole file is read first, into $1000-$7EFF of every RAM bank but the
;   caller's (3 x 28,416 = 85,248 bytes with 4 banks), then written, so
;   one file is open at a time (the CH376's limit) and a copy within one
;   drive needs no seeking.  What was in those banks (a program in bank 0)
;   is lost.  The caller's bank is selected again at the end.
; ----------------------------------------------------------------------------
CP_SIZE         = $7F00 - $1000

sbc_copy:
        sta     strptr
        sty     strptr+1
        lda     bank_cur
        sta     sh_cur
        ldy     #0
        lda     (strptr),y
        sta     cp_sdev
        ldy     #3
        lda     (strptr),y
        sta     cp_ddev
        ldy     #1                  ; the source's path -> ch_name
        jsr     cp_ptr
        ldx     #0
@s:     lda     (dir_ptr),y
        sta     ch_name,x
        beq     @d
        iny
        inx
        cpx     #45
        bcc     @s
        bcs     cp_badp
@d:     ldy     #4                  ; the destination's -> cp_dst
        jsr     cp_ptr
        ldx     #0
@t:     lda     (dir_ptr),y
        sta     cp_dst,x
        beq     cp_src
        iny
        inx
        cpx     #45
        bcc     @t
cp_badp:
        lda     #$FE
        sec
        rts
cp_src: lda     cp_sdev             ; read it
        jsr     fs_letter
        bcs     cp_badp
        jsr     fs_prepare
        bcc     :+
        jmp     cp_nodisk
:       ; (far)
        jsr     mon_open
        cmp     #USB_INT_SUCCESS
        beq     :+
        jmp     cp_err
:       ; (far)
        lda     #0
        sta     cp_b
        sta     cp_n
@rb:    jsr     cp_bank
        bcs     @full
        jsr     BANK_SET
        jsr     cp_buf
        jsr     fs_read
        cmp     #USB_INT_SUCCESS
        beq     :+
        jmp     cp_rderr
:       ; (far)
        inc     cp_n
        lda     ch_got
        sta     cp_last
        lda     ch_got+1
        sta     cp_last+1
        cmp     #>CP_SIZE           ; a whole bank: there may be more
        bne     @eof
        lda     ch_got
        cmp     #<CP_SIZE
        beq     @rb
        bne     @eof
@full:  lda     #<cp_probe          ; every bank full: is there more?
        sta     ch_ptr
        lda     #>cp_probe
        sta     ch_ptr+1
        lda     #1
        sta     ch_len
        lda     #0
        sta     ch_len+1
        jsr     fs_read
        cmp     #USB_INT_SUCCESS
        beq     :+
        jmp     cp_rderr
:       ; (far)
        lda     ch_got
        beq     @eof
        lda     #0
        jsr     fs_close
        lda     #CH_E_TOOBIG
        bne     cp_err
@eof:   lda     #0
        jsr     fs_close
        lda     cp_ddev             ; write it
        jsr     fs_letter
        bcc     :+
        jmp     cp_badp
:       ; (far)
        jsr     fs_prepare
        bcs     cp_nodisk
        ldx     #0
@n:     lda     cp_dst,x
        sta     ch_name,x
        beq     @cr
        inx
        bne     @n
@cr:    jsr     mon_create
        cmp     #USB_INT_SUCCESS
        bne     cp_err
        lda     #0
        sta     cp_b
        lda     cp_n
        sta     cp_k
@wb:    lda     cp_k
        beq     @done
        jsr     cp_bank
        jsr     BANK_SET
        jsr     cp_buf
        lda     cp_k
        cmp     #1
        bne     :+
        lda     cp_last             ; (the last one: what it holds)
        sta     ch_len
        lda     cp_last+1
        sta     ch_len+1
:       jsr     fs_write
        cmp     #USB_INT_SUCCESS
        bne     cp_wrerr
        dec     cp_k
        jmp     @wb
@done:  lda     #1                  ; close, with the length
        jsr     fs_close
        cmp     #USB_INT_SUCCESS
        bne     cp_err
        jsr     cp_back
        clc
        rts
cp_nodisk:
        lda     #CH_E_NODISK
cp_err: pha
        jsr     cp_back
        pla
        sec
        rts
cp_rderr:
        pha
        lda     #0
        jsr     fs_close
        jmp     cp_reset
cp_wrerr:
        pha
        lda     #1
        jsr     fs_close
cp_reset:
        lda     #0                  ; (set the drive up afresh next time)
        jsr     fs_unready
        pla
        jmp     cp_err

; dir_ptr = the word at (strptr),y; Y = 0
cp_ptr: lda     (strptr),y
        sta     dir_ptr
        iny
        lda     (strptr),y
        sta     dir_ptr+1
        ldy     #0
        rts

; A = the next bank to use (not the caller's), C=1: none left
cp_bank:
        lda     cp_b
        cmp     bank_count
        bcs     @r
        inc     cp_b
        cmp     sh_cur
        beq     cp_bank
        clc
@r:     rts

; ch_ptr = $1000, ch_len = a bank's worth
cp_buf: lda     #<$1000
        sta     ch_ptr
        lda     #>$1000
        sta     ch_ptr+1
        lda     #<CP_SIZE
        sta     ch_len
        lda     #>CP_SIZE
        sta     ch_len+1
        rts

cp_back:
        lda     sh_cur
        jmp     BANK_SET

; ----------------------------------------------------------------------------
; SBC_DELETE - delete a file
;   In : A/Y = a block:  +0 .byte the device ('U' / 'C')
;                        +1 .word -> the full path, "/A/B/NAME.EXT",0
;   Out: C=0 deleted; C=1, A = the error ($42 not found)
; ----------------------------------------------------------------------------
sbc_delete:
        sta     strptr
        sty     strptr+1
        ldy     #0
        lda     (strptr),y
        jsr     fs_letter
        bcs     cp_badp2
        ldy     #1
        jsr     cp_ptr
        ldx     #0
@s:     lda     (dir_ptr),y
        sta     ch_name,x
        beq     del_go
        iny
        inx
        cpx     #45
        bcc     @s
cp_badp2:
        lda     #$FE
        sec
        rts
del_go: jsr     fs_prepare
        bcc     :+
        lda     #CH_E_NODISK
        sec
        rts
:       jsr     mon_erase
        cmp     #USB_INT_SUCCESS
        beq     @ok
        sec
        rts
@ok:    clc
        rts

; ----------------------------------------------------------------------------
; mon_dirs - enter the folders of the path in ch_name (as mon_open does);
;   C=0: A/X = the name part, relative to the folder now open
;   C=1: A = the error
; mon_create / mon_erase - create (replace) / delete the file at that path
; ----------------------------------------------------------------------------
mon_dirs:
        ldx     #0
        stx     mon_end
@f:     lda     ch_name,x
        beq     @e
        cmp     #'/'
        bne     @n
        stx     mon_end
@n:     inx
        bne     @f
@e:     lda     mon_end
        beq     @root
        jsr     mon_enter
        cmp     #ERR_OPEN_DIR
        bne     @bad
        ldx     mon_end
        inx
        ldy     #0
@m:     lda     ch_name,x
        sta     mon_comp,y
        beq     @rel
        inx
        iny
        bne     @m
@rel:   lda     #<mon_comp
        ldx     #>mon_comp
        clc
        rts
@root:  lda     #<ch_name
        ldx     #>ch_name
        clc
        rts
@bad:   sec
        rts

mon_create:
        jsr     mon_dirs
        bcs     @r
        jmp     fs_create
@r:     rts

mon_erase:
        jsr     mon_dirs
        bcs     @r
        jmp     fs_erase
@r:     rts

; ----------------------------------------------------------------------------
; mon_prompt - the monitor's new line: CR LF and "U:\GAMES\DEEP>" (the
; device and the current folder)
; ----------------------------------------------------------------------------
mon_prompt:
        lda     #$0D
        jsr     CHROUT
        lda     #$0A
        jsr     CHROUT
        ldy     fs_dev
        lda     run_dev,y
        jsr     CHROUT
        lda     #':'
        jsr     CHROUT
        ldy     #0
        lda     mon_cwd
        bne     @p
        lda     #'\'
        jsr     CHROUT
        jmp     @e
@p:     lda     mon_cwd,y
        beq     @e
        cmp     #'/'
        bne     :+
        lda     #'\'
:       jsr     CHROUT
        iny
        cpy     #31
        bcc     @p
@e:     lda     #'>'
        jmp     CHROUT
