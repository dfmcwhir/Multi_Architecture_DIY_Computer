; ============================================================================
; gui.s - the file manager (shell) for the 6502 SBC, CPU Rev2, PICO9918
;
;   build:  make.bat           (GUI.BIN = install.s + this)
;   start:  L GUI 0800  then  R      (once; after that G on the boot menu)
;
; It lives in the top RAM bank at $1000 (install.s copies it there and
; registers it with SBC_SHELL), so programs still load at $0800 in bank 0
; and have all of their RAM.  When a program ends with JMP SBC_MENU (all
; the games do), or BASIC's EXIT, the ROM comes back here.
;
; Needs ROM stage 6 (SBC_DIR, SBC_RUN, SBC_SHELL).
;
; Header (at $1000 in its bank):
;   $1000  JMP start
;   $1003  "SH65"            (the ROM checks it)
;   $1007  1 = first start   (install.s's copy; then 0)
;   $1008  .word the end of the program (for install.s)
;
; Screen: Graphics I with the F18A's ECM2 tiles (3 colours + background a
; tile) and an ECM2 sprite for the mouse pointer.
;   row 0      the drive and folder; the U: and C: buttons
;   row 1      column titles
;   rows 2-21  the files (20 a screen); column 31 the scroll bar
;   row 22     messages
;   row 23     buttons: COPY, PASTE, DEL, UP, BASIC, MON, MENU
;
; Mouse:    click selects, double click opens; right click = up a folder;
;           the scroll bar's arrows and track; the buttons
; Keyboard: Up / Down select, Enter or Right open, Backspace / Left / Esc
;           up a folder, U / C drive, B BASIC, M monitor, Q boot menu,
;           R read the folder again, < > a screen up / down,
;           F5 or K copy, F6 or P paste, F8 or X delete
;
; COPY remembers the selected file; PASTE copies it into the folder shown
; (any folder, either drive: SBC_COPY); DEL deletes the selected file
; (SBC_DELETE).  Replacing and deleting ask first: YES / NO on the message
; line (click, Y / N, or the pad's A / B).
; Gamepad:  Up / Down select, A / Start / Right open, B / Left up a folder,
;           Select changes the drive
;
; Opening: a folder goes into it; .BIN runs (SBC_RUN, bank 0 at $0800);
; .BAS starts BASIC and runs it; anything else is shown as text.
;
; No zero page is used (the ROM's pointers are left alone).
; ============================================================================

        .include "sbc_api.inc"

; the stage 6 entries (an older sbc_api.inc doesn't have them)
.ifndef SBC_SHELL
SBC_DIR         = $FE57
SBC_RUN         = $FE5A
SBC_SHELL       = $FE5D
.endif
.ifndef SBC_COPY
SBC_COPY        = $FE60
SBC_DELETE      = $FE63
.endif

VDP_NAME        = $2000
V_TP0           = $0000         ; tile patterns, plane 0
V_TP1           = $0800         ;   plane 1
V_SP0           = $1000         ; sprite patterns, plane 0
V_SP1           = $1800         ;   plane 1
V_ATT           = $2400         ; tile attributes (one a pattern)
V_SAT           = $2600         ; sprite attributes

LIST_Y          = 2             ; the list's first row
LIST_H          = 20            ; rows in the list
MAXENT          = 200           ; folder entries read
PAGE_LINES      = 21            ; text lines a page in the viewer
TRAMP           = $0F80         ; (common RAM: the way out to bank 0)

K_BS            = $08
K_CR            = $0D
K_ESC           = $1B
K_DEL           = $7F

        .segment "CODE"
gui_base:
        jmp     start
        .byte   "SH65"
gui_new:
        .byte   1
        .word   gui_end

; ----------------------------------------------------------------------------
start:
        cld
        jsr     SBC_SYSINFO
        cmp     #DISP_PICO
        beq     @ok
        lda     #0              ; not the PICO9918: no shell
        jsr     SBC_SHELL
        jmp     SBC_MENU
@ok:    lda     gui_new
        beq     @old
        lda     #0              ; the first start
        sta     gui_new
        sta     cwd
        sta     sel
        sta     top
        sta     clip_name
        lda     #'U'
        sta     dev
        lda     #128
        sta     m_x
        lda     #96
        sta     m_y
@old:   lda     #0
        sta     mouse_ok
        sta     esc_st
        sta     up_name
        sta     m_click
        sta     m_rclick
        jsr     SBC_PADSTATE    ; (a button still held from the program)
        sta     pad_old
@fl:    jsr     SBC_CHRIN       ; keys typed before
        bcs     @fl
        jsr     gfx_init
        jsr     mouse_init
        jsr     load_dir
main:   jsr     vdp_frame
        inc     frames
        jsr     mouse_poll
        jsr     do_mouse
        jsr     do_pad
        jsr     do_keys
        jmp     main

frame_idle:
        rts

; ============================================================================
; the folder
; ============================================================================

; read the folder (dev, cwd), sort it, show it
load_dir:
        lda     #<s_reading
        ldy     #>s_reading
        jsr     st_text
        jsr     put_cwd
        jsr     read_dir
        bcc     @ok
        sta     errc
        lda     cwd             ; a folder that has gone: try the top
        beq     @fail
        lda     #0
        sta     cwd
        sta     sel
        sta     top
        jsr     put_cwd
        jsr     read_dir
        bcc     @ok
        sta     errc
@fail:  lda     #0
        sta     n_ent
        sta     n_list
        sta     sel
        sta     top
        jsr     draw_all
        lda     errc
        jmp     st_error
@ok:    sta     n_ent
        ldx     #0
        lda     cwd
        beq     @nu
        lda     #$FF            ; ".." first, below the top
        sta     order
        inx
@nu:    stx     k0
        ldy     #0
@o:     cpy     n_ent
        beq     @od
        tya
        sta     order,x
        inx
        iny
        bne     @o
@od:    stx     n_list
        jsr     sort
        lda     up_name         ; (back up a folder: select the one left)
        beq     @cl
        jsr     find_up
        lda     #0
        sta     up_name
@cl:    jsr     clamp_sel
        jsr     draw_all
        jmp     st_count

read_dir:
        lda     dev
        sta     dirblk+3
        lda     #<dirblk
        ldy     #>dirblk
        jmp     SBC_DIR

; the ROM's current folder = cwd
put_cwd:
        jsr     SBC_CWD
        sta     @wr+1
        sty     @wr+2
        ldx     #31
@c:     lda     cwd,x
@wr:    sta     $FFFF,x
        dex
        bpl     @c
        rts

; table entry A -> ebuf (16 bytes)
get_ent:
        jsr     ent_addr
        sta     @rd+1
        sty     @rd+2
        ldx     #15
@rd:    lda     $FFFF,x
        sta     ebuf,x
        dex
        bpl     @rd
        rts

; A = table index -> A/Y = its address (table + 16 A)
ent_addr:
        sta     ea
        lda     #0
        sta     ea+1
        asl     ea
        rol     ea+1
        asl     ea
        rol     ea+1
        asl     ea
        rol     ea+1
        asl     ea
        rol     ea+1
        lda     ea
        clc
        adc     #<table
        pha
        lda     ea+1
        adc     #>table
        tay
        pla
        rts

; sort order[k0 .. n_list): folders first, then by name (insertion sort)
sort:   ldx     k0
        inx
        stx     si
@out:   lda     si
        cmp     n_list
        bcs     @done
        tax
        lda     order,x
        sta     sv
        jsr     get_ent         ; (the one being placed: in ebuf)
        lda     si
        sta     sj
@in:    lda     sj
        cmp     k0
        beq     @put
        tax
        lda     order-1,x
        jsr     v_less
        bcc     @put
        ldx     sj
        lda     order-1,x
        sta     order,x
        dec     sj
        jmp     @in
@put:   ldx     sj
        lda     sv
        sta     order,x
        inc     si
        jmp     @out
@done:  rts

; C=1 if the entry in ebuf comes before table entry A
v_less: jsr     ent_addr
        sta     @at+1
        sty     @at+2
        sta     @nm+1
        sty     @nm+2
        lda     ebuf+11
        and     #$10
        sta     t1
        ldx     #11
@at:    lda     $FFFF,x
        and     #$10
        cmp     t1
        beq     @name
        lda     t1              ; one folder, one file: the folder first
        beq     @no
@yes:   sec
        rts
@name:  ldx     #0
@l:     lda     ebuf,x
@nm:    cmp     $FFFF,x
        bne     @d
        inx
        cpx     #11
        bne     @l
@no:    clc
        rts
@d:     bcc     @yes
        clc
        rts

; select the entry named up_name
find_up:
        jsr     find_name
        bcc     @r
        stx     sel
@r:     rts

; the list row of the entry named up_name: C=1, X = the row (and ebuf,
; nbuf hold it); C=0 none
find_name:
        lda     k0
        sta     si
@l:     lda     si
        cmp     n_list
        bcs     @no
        tax
        lda     order,x
        jsr     get_ent
        jsr     fmt_name
        ldx     #0
@c:     lda     nbuf,x
        cmp     up_name,x
        bne     @n
        inx
        cmp     #0
        bne     @c
        ldx     si
        sec
        rts
@n:     inc     si
        bne     @l
@no:    clc
        rts

; nbuf = the name in ebuf, "NAME.EXT", 0-ended; nlen = its length
fmt_name:
        ldx     #0
        ldy     #0
@b:     lda     ebuf,y
        cmp     #' '
        beq     @be
        sta     nbuf,x
        inx
        iny
        cpy     #8
        bne     @b
@be:    lda     ebuf+8
        cmp     #' '
        beq     @e
        lda     #'.'
        sta     nbuf,x
        inx
        ldy     #8
@x:     lda     ebuf,y
        cmp     #' '
        beq     @e
        sta     nbuf,x
        inx
        iny
        cpy     #11
        bne     @x
@e:     lda     #0
        sta     nbuf,x
        stx     nlen
        rts

; A = the kind of the entry in ebuf: 0 folder, 2 program, 3 BASIC,
; 4 text, 5 other  (1 is "..")
ent_kind:
        lda     ebuf+11
        and     #$10
        beq     @f
        lda     #0
        rts
@f:     ldx     #0
@l:     lda     ext_tab,x       ; 3 letters, then the kind
        beq     @other
        cmp     ebuf+8
        bne     @n
        lda     ext_tab+1,x
        cmp     ebuf+9
        bne     @n
        lda     ext_tab+2,x
        cmp     ebuf+10
        bne     @n
        lda     ext_tab+3,x
        rts
@n:     inx
        inx
        inx
        inx
        bne     @l
@other: lda     #5
        rts

; sel inside the list, and on the screen
clamp_sel:
        lda     n_list
        bne     @a
        lda     #0
        sta     sel
        sta     top
        rts
@a:     lda     sel
        cmp     n_list
        bcc     show_sel
        ldx     n_list
        dex
        stx     sel
show_sel:
        lda     sel
        cmp     top
        bcs     @1
        sta     top
        jmp     fix_top
@1:     sec
        sbc     top
        cmp     #LIST_H
        bcc     fix_top
        lda     sel
        sec
        sbc     #LIST_H-1
        sta     top
fix_top:                        ; top <= the last screen's
        lda     n_list
        sec
        sbc     #LIST_H
        bcs     @m
        lda     #0
@m:     cmp     top
        bcs     @r
        sta     top
@r:     rts

; ============================================================================
; actions
; ============================================================================
sel_up: lda     sel
        beq     @r
        sta     osel
        dec     sel
        jmp     sel_moved
@r:     rts

sel_dn: ldx     sel
        stx     osel
        inx
        cpx     n_list
        bcs     @r
        stx     sel
        jmp     sel_moved
@r:     rts

; the selection moved from osel: redraw its two rows (or the whole list if
; it had to scroll)
sel_moved:
        lda     top
        sta     otop
        jsr     show_sel
        lda     top
        cmp     otop
        beq     @two
        jmp     draw_list
@two:   lda     osel
        sec
        sbc     top
        cmp     #LIST_H
        bcs     @new            ; (the old one wasn't on the screen)
        sta     cr
        jsr     draw_row
@new:   lda     sel
        sec
        sbc     top
        sta     cr
        jmp     draw_row

scroll_up1:
        lda     top
        beq     @r
        dec     top
        jmp     draw_list
@r:     rts

scroll_dn1:
        inc     top
        jsr     fix_top
        jmp     draw_list

page_up:
        lda     top
        sec
        sbc     #LIST_H
        bcs     :+
        lda     #0
:       sta     top
        lda     sel             ; (the selection moves with it)
        sec
        sbc     #LIST_H
        bcs     :+
        lda     #0
:       sta     sel
        jmp     draw_list

page_down:
        lda     top
        clc
        adc     #LIST_H
        sta     top
        jsr     fix_top
        lda     sel
        clc
        adc     #LIST_H
        bcs     @last
        cmp     n_list
        bcc     @s
@last:  ldx     n_list
        beq     @d
        dex
        txa
@s:     sta     sel
@d:     jmp     draw_list

refresh:
        jmp     load_dir

drive_u:
        lda     #'U'
        bne     set_drive
drive_c:
        lda     #'C'
set_drive:
        sta     dev
        lda     #0
        sta     cwd
        sta     sel
        sta     top
        jmp     draw_dev        ; (the title first, then the folder)

draw_dev:
        jsr     draw_title
        jmp     load_dir

; up a folder (the one left is selected afterwards)
go_up:  lda     cwd
        bne     @g
        rts
@g:     ldx     #0
@f:     lda     cwd,x           ; the last '/'
        beq     @e
        cmp     #'/'
        bne     @n
        stx     t1
@n:     inx
        bne     @f
@e:     ldx     t1
        inx
        ldy     #0
@c:     lda     cwd,x
        sta     up_name,y
        beq     @z
        inx
        iny
        bne     @c
@z:     ldx     t1
        lda     #0
        sta     cwd,x
        sta     sel
        sta     top
        jmp     load_dir

; open the selected entry
open_sel:
        lda     n_list
        bne     @go
        rts
@go:    ldx     sel
        lda     order,x
        cmp     #$FF
        bne     @e
        jmp     go_up
@e:     jsr     get_ent
        jsr     fmt_name
        jsr     ent_kind
        cmp     #0
        beq     enter_dir
        cmp     #2
        bne     @nb
        lda     #0
        jmp     run_it
@nb:    cmp     #3
        bne     @nv
        lda     #1
        jmp     run_it
@nv:    jmp     view_text

; into the folder in nbuf (cwd + "/" + name: 31 characters at most)
enter_dir:
        ldx     #0
@l:     lda     cwd,x
        beq     @e
        inx
        bne     @l
@e:     txa
        sec                     ; + "/"
        adc     nlen
        cmp     #32
        bcc     @ok
        lda     #<s_long
        ldy     #>s_long
        jmp     st_text
@ok:    lda     #'/'
        sta     cwd,x
        inx
        ldy     #0
@c:     lda     nbuf,y
        sta     cwd,x
        beq     @d
        inx
        iny
        bne     @c
@d:     lda     #0
        sta     sel
        sta     top
        jmp     load_dir

; A = 0: run the program in nbuf; 1: the BASIC program.  Back here only
; when it failed to load.
run_it: sta     runblk
        lda     dev
        sta     runblk+1
        ldx     #0
@c:     lda     nbuf,x
        sta     runblk+2,x
        beq     @d
        inx
        bne     @c
@d:     lda     #<s_start
        ldy     #>s_start
        jsr     st_text
        jsr     st_name
        jsr     st_show
        jsr     put_cwd
        jsr     mouse_off
        jsr     leave_gfx
        lda     #<runblk
        ldy     #>runblk
        jsr     SBC_RUN
        sta     errc            ; (it failed)
        jsr     gfx_init
        jsr     mouse_init
        jsr     draw_all
        lda     errc
        jmp     st_error

; ============================================================================
; copy, paste, delete
; ============================================================================

; COPY: remember the selected file (its drive and full path)
act_copy:
        jsr     sel_file
        bcs     @r
        lda     #<nbuf
        ldy     #>nbuf
        jsr     mk_path
        bcs     @long
        ldx     #45
@c:     lda     pbuf,x
        sta     clip_path,x
        dex
        bpl     @c
        ldx     #12
@n:     lda     nbuf,x
        sta     clip_name,x
        dex
        bpl     @n
        lda     dev
        sta     clip_dev
        lda     #<s_ready
        ldy     #>s_ready
        jsr     st_text
        jsr     st_name
        jmp     st_show
@long:  lda     #<s_long
        ldy     #>s_long
        jmp     st_text
@r:     rts

; PASTE: copy the remembered file into the folder shown
act_paste:
        lda     clip_name
        bne     @have
        lda     #<s_noclip
        ldy     #>s_noclip
        jmp     st_text
@have:  lda     #<clip_name
        ldy     #>clip_name
        jsr     mk_path
        bcc     :+
        lda     #<s_long
        ldy     #>s_long
        jmp     st_text
:       lda     dev             ; the same file?
        cmp     clip_dev
        bne     @diff
        ldx     #0
@sm:    lda     pbuf,x
        cmp     clip_path,x
        bne     @diff
        inx
        cmp     #0
        bne     @sm
        lda     #<s_same
        ldy     #>s_same
        jmp     st_text
@diff:  ldx     #12             ; one by that name here already?
@un:    lda     clip_name,x
        sta     up_name,x
        dex
        bpl     @un
        jsr     find_name
        bcc     @go
        lda     ebuf+11
        and     #$10
        beq     @file
        lda     #0
        sta     up_name
        lda     #<s_isdir
        ldy     #>s_isdir
        jmp     st_text
@file:  lda     #<s_replace
        ldy     #>s_replace
        jsr     confirm
        bcs     @go
        lda     #0
        sta     up_name
        jmp     st_count
@go:    ldx     #12
@cn:    lda     clip_name,x
        sta     nbuf,x
        dex
        bpl     @cn
        lda     #<s_copying
        ldy     #>s_copying
        jsr     st_text
        jsr     st_name
        jsr     st_show
        lda     clip_dev
        sta     cpblk
        lda     #<clip_path
        sta     cpblk+1
        lda     #>clip_path
        sta     cpblk+2
        lda     dev
        sta     cpblk+3
        lda     #<pbuf
        sta     cpblk+4
        lda     #>pbuf
        sta     cpblk+5
        lda     #<cpblk
        ldy     #>cpblk
        jsr     SBC_COPY
        bcs     @err
        jsr     load_dir        ; (up_name: the copy is selected)
        lda     #<s_copied
        ldy     #>s_copied
        jsr     st_text
        lda     #<clip_name
        ldy     #>clip_name
        jsr     st_str
        jmp     st_show
@err:   sta     errc2
        lda     #0
        sta     up_name
        jsr     load_dir
        lda     errc2
        jmp     st_error

; DEL: delete the selected file (after YES)
act_delete:
        jsr     sel_file
        bcs     @r
        lda     #<s_delete
        ldy     #>s_delete
        jsr     confirm
        bcs     @yes
        jmp     st_count
@yes:   lda     #<nbuf
        ldy     #>nbuf
        jsr     mk_path
        bcs     @r
        lda     dev
        sta     delblk
        lda     #<pbuf
        sta     delblk+1
        lda     #>pbuf
        sta     delblk+2
        lda     #<delblk
        ldy     #>delblk
        jsr     SBC_DELETE
        bcs     @err
        lda     dev             ; (it was the one remembered: forget it)
        cmp     clip_dev
        bne     @nc
        ldx     #0
@sm:    lda     pbuf,x
        cmp     clip_path,x
        bne     @nc
        inx
        cmp     #0
        bne     @sm
        lda     #0
        sta     clip_name
@nc:    jsr     load_dir
        lda     #<s_deleted
        ldy     #>s_deleted
        jmp     st_text
@err:   sta     errc2
        jsr     load_dir
        lda     errc2
        jmp     st_error
@r:     rts

; the selected entry, if it is a file: C=0, ebuf / nbuf hold it
sel_file:
        lda     n_list
        beq     @no
        ldx     sel
        lda     order,x
        cmp     #$FF
        beq     @fold
        jsr     get_ent
        jsr     fmt_name
        lda     ebuf+11
        and     #$10
        bne     @fold
        clc
        rts
@fold:  lda     #<s_onlyf
        ldy     #>s_onlyf
        jsr     st_text
@no:    sec
        rts

; pbuf = cwd + "/" + the name at A/Y (C=1: longer than 45)
mk_path:
        sta     @rd+1
        sty     @rd+2
        ldx     #0
@c:     lda     cwd,x
        beq     @s
        sta     pbuf,x
        inx
        bne     @c
@s:     lda     #'/'
        sta     pbuf,x
        inx
        ldy     #0
@rd:    lda     $FFFF,y
        sta     pbuf,x
        beq     @ok
        inx
        iny
        cpx     #45
        bcc     @rd
        sec
        rts
@ok:    clc
        rts

; ask: the message at A/Y + nbuf + "?", and YES / NO on the message line.
; C=1 yes.  (a click on YES / NO, Y / N / Enter / Esc, the pad's A / B)
confirm:
        pha
        jsr     st_clear
        pla
        jsr     st_str
        jsr     st_name
        lda     #'?'
        jsr     st_chr
        jsr     st_show
        ldx     #6
@yn:    lda     s_yesno,x
        sta     line+24,x
        dex
        bpl     @yn
        lda     #$80
        sta     off
        ldx     #24
        lda     #27
        sta     lend
        jsr     put_cells
        ldx     #29
        lda     #31
        sta     lend
        jsr     put_cells
        jsr     mouse_flush
        jsr     SBC_PADSTATE
        sta     pad_old
@w:     jsr     vdp_frame
        inc     frames
        jsr     mouse_poll
        lda     m_rclick
        bne     @no
        lda     m_click
        beq     @pad
        lda     #0
        sta     m_click
        lda     m_y
        lsr
        lsr
        lsr
        cmp     #22
        bne     @pad
        lda     m_x
        lsr
        lsr
        lsr
        cmp     #24
        bcc     @pad
        cmp     #27
        bcc     @yes
        cmp     #29
        bcc     @pad
        cmp     #31
        bcc     @no
@pad:   jsr     SBC_PADSTATE
        tax
        eor     pad_old
        stx     pad_old
        and     pad_old
        lsr
        bcs     @yes            ; A
        lsr
        bcs     @no             ; B
        jsr     SBC_CHRIN
        bcc     @w
        cmp     #'a'
        bcc     :+
        and     #$DF
:       cmp     #'Y'
        beq     @yes
        cmp     #K_CR
        beq     @yes
        cmp     #'N'
        beq     @no
        cmp     #K_ESC
        beq     @no
        cmp     #KEY_ESC
        beq     @no
        cmp     #K_BS
        beq     @no
        jmp     @w
@yes:   jsr     mouse_flush
        sec
        rts
@no:    jsr     mouse_flush
        clc
        rts

; the buttons: out to BASIC, the monitor, the boot menu
act_basic:
        lda     #<SBC_COLD
        ldx     #>SBC_COLD
        jmp     leave_to
act_monitor:
        lda     #<SBC_MONITOR
        ldx     #>SBC_MONITOR
        jmp     leave_to
act_menu:
        lda     #0              ; no shell: the boot menu (G comes back)
        jsr     SBC_SHELL
        lda     #<SBC_MENU
        ldx     #>SBC_MENU
leave_to:
        sta     tr_code+6
        stx     tr_code+7
        jsr     put_cwd
        jsr     mouse_off
        jsr     leave_gfx
        jsr     SBC_CONRESET
        ldx     #7              ; bank 0 can't be chosen from in here:
@c:     lda     tr_code,x       ; a few bytes in common RAM do it
        sta     TRAMP,x
        dex
        bpl     @c
        jmp     TRAMP
tr_code:
        lda     #0
        jsr     SBC_BANKSET
        jmp     $FFFF

; ============================================================================
; input
; ============================================================================
do_mouse:
        lda     m_rclick
        beq     @l
        lda     #0
        sta     m_rclick
        jmp     go_up
@l:     lda     m_click
        bne     @c
@r:     rts
@c:     lda     #0
        sta     m_click
        lda     m_x
        lsr
        lsr
        lsr
        sta     cx
        lda     m_y
        lsr
        lsr
        lsr
        sta     cy
        bne     @n0
        lda     cx              ; the title row: the drive buttons
        cmp     #28
        bcs     @dc
        cmp     #24
        bcc     @r
        jmp     drive_u
@dc:    jmp     drive_c
@n0:    cmp     #23
        bne     @n23
        jmp     click_button
@n23:   cmp     #LIST_Y
        bcc     @r
        cmp     #LIST_Y+LIST_H
        bcs     @r
        sec
        sbc     #LIST_Y
        sta     cr
        lda     cx
        cmp     #31
        bne     @row
        lda     cr              ; the scroll bar
        bne     @nu
        jmp     scroll_up1
@nu:    cmp     #LIST_H-1
        bne     @tr
        jmp     scroll_dn1
@tr:    sec
        sbc     #1
        cmp     tpos
        bcc     @pu
        jmp     page_down
@pu:    jmp     page_up
@row:   lda     top
        clc
        adc     cr
        cmp     n_list
        bcs     @r
        cmp     sel
        bne     @new
        lda     frames          ; the same one again: a double click?
        sec
        sbc     click_t
        cmp     #30
        bcs     @slow
        lda     frames
        eor     #$80
        sta     click_t
        jmp     open_sel
@slow:  lda     frames
        sta     click_t
        rts
@new:   tax
        lda     sel
        sta     osel
        stx     sel
        lda     frames
        sta     click_t
        jmp     sel_moved

click_button:
        ldx     #0
@l:     lda     btn_x0,x
        cmp     #$FF
        beq     @r
        lda     cx
        cmp     btn_x0,x
        bcc     @n
        cmp     btn_x1,x
        bcs     @n
        txa
        asl
        tax
        lda     btn_go+1,x
        pha
        lda     btn_go,x
        pha
@r:     rts
@n:     inx
        bne     @l

do_pad: jsr     SBC_PADSTATE
        sta     pad_now
        eor     pad_old
        and     pad_now
        sta     pad_new
        lda     pad_now
        sta     pad_old
        and     #$30            ; up / down, repeating
        beq     @nr
        lda     pad_new
        and     #$30
        beq     @held
        lda     #20
        sta     pad_rep
        bne     @mv
@held:  dec     pad_rep
        bne     @nr
        lda     #5
        sta     pad_rep
@mv:    lda     pad_now
        and     #$10
        beq     @dn
        jsr     sel_up
        jmp     @nr
@dn:    jsr     sel_dn
@nr:    lda     pad_new
        and     #$89            ; A, Start, Right
        beq     @b
        jmp     open_sel
@b:     lda     pad_new
        and     #$42            ; B, Left
        beq     @s
        jmp     go_up
@s:     lda     pad_new
        and     #$04            ; Select: the other drive
        beq     @r
        lda     dev
        cmp     #'U'
        beq     @c
        jmp     drive_u
@c:     jmp     drive_c
@r:     rts

do_keys:
        jsr     SBC_CHRIN
        bcs     @k
        rts
@k:     jsr     key1
        jmp     do_keys

; one key (Esc [ A-D from a serial terminal = the arrows)
key1:   ldx     esc_st
        beq     @n
        cpx     #1
        bne     @s2
        cmp     #'['
        bne     @x
        lda     #2
        sta     esc_st
        rts
@s2:    ldx     #0
        stx     esc_st
        cmp     #'A'
        bne     :+
        jmp     sel_up
:       cmp     #'B'
        bne     :+
        jmp     sel_dn
:       cmp     #'C'
        bne     :+
        jmp     open_sel
:       cmp     #'D'
        bne     @r
        jmp     go_up
@x:     ldx     #0
        stx     esc_st
        jsr     go_up           ; (a lone Esc)
        rts
@n:     cmp     #K_ESC
        bne     @nk
        lda     #1
        sta     esc_st
@r:     rts
@nk:    cmp     #'a'
        bcc     @u
        cmp     #'z'+1
        bcs     @u
        and     #$DF
@u:     ldx     #0
@l:     ldy     key_tab,x
        beq     @r
        cmp     key_tab,x
        beq     @go
        inx
        bne     @l
@go:    txa
        asl
        tax
        lda     key_go+1,x
        pha
        lda     key_go,x
        pha
        rts

; ============================================================================
; the text viewer (the ROM's text console)
; ============================================================================
view_text:
        lda     #<s_read
        ldy     #>s_read
        jsr     st_text
        jsr     st_name
        jsr     st_show
        jsr     put_cwd
        ldx     #0
@c:     lda     nbuf,x
        sta     ldblk+4,x
        beq     @d
        inx
        bne     @c
@d:     lda     #<ldblk
        ldy     #>ldblk
        jsr     SBC_LOAD
        bcc     @ok
        jmp     st_error
@ok:    txa                     ; the end = viewbuf + the length
        clc
        adc     #<viewbuf
        sta     vend
        tya
        adc     #>viewbuf
        sta     vend+1
        jsr     leave_gfx
        jsr     pager
        jsr     gfx_init
        jsr     mouse_flush
        jsr     draw_all
        jmp     st_count

pager:  lda     #<viewbuf
        sta     vpos
        lda     #>viewbuf
        sta     vpos+1
        lda     #0
        sta     vpn
@page:  jsr     SBC_CONRESET
        lda     vpos
        sta     vstart
        lda     vpos+1
        sta     vstart+1
        jsr     v_head
        jsr     show_page
        jsr     v_prompt
@wait:  jsr     vdp_frame
        inc     frames
        jsr     mouse_poll
        jsr     v_input
        beq     @wait
        cmp     #3
        beq     @close
        cmp     #2
        beq     @back
        lda     veof            ; next page
        bne     @wait
        ldx     vpn
        cpx     #VSTK
        bcs     @page
        lda     vstart
        sta     vstk_lo,x
        lda     vstart+1
        sta     vstk_hi,x
        inc     vpn
        jmp     @page
@back:  ldx     vpn
        beq     @wait
        dex
        stx     vpn
        lda     vstk_lo,x
        sta     vpos
        lda     vstk_hi,x
        sta     vpos+1
        jmp     @page
@close: rts

; the top line: the name and the page
v_head: ldx     #0
@n:     lda     nbuf,x
        beq     @p
        jsr     SBC_CHROUT
        inx
        bne     @n
@p:     lda     #<s_page
        ldy     #>s_page
        jsr     v_puts
        lda     vpn
        clc
        adc     #1
        jsr     v_dec
        lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jmp     SBC_CHROUT

v_prompt:
        lda     vcol
        beq     :+
        lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jsr     SBC_CHROUT
:       lda     veof
        beq     @m
        lda     #<s_vend
        ldy     #>s_vend
        jmp     v_puts
@m:     lda     #<s_vmore
        ldy     #>s_vmore
        jmp     v_puts

; print up to PAGE_LINES lines from vpos (veof = 1 at the end of the text)
show_page:
        lda     #0
        sta     vlines
        sta     vcol
        sta     veof
@ch:    jsr     v_atend
        bcc     @get
        rts
@get:   jsr     v_next
        cmp     #K_CR
        bne     @n13
        jsr     v_atend         ; CR LF: one line end
        bcs     @nl
        lda     vpos
        sta     @pk+1
        lda     vpos+1
        sta     @pk+2
@pk:    lda     $FFFF
        cmp     #10
        bne     @nl
        jsr     v_next
        jmp     @nl
@n13:   cmp     #10
        beq     @nl
        cmp     #9
        bne     @n9
@tab:   lda     #' '
        jsr     v_out
        bcs     @full
        lda     vcol
        beq     @ch
        and     #7
        bne     @tab
        beq     @ch
@n9:    cmp     #' '
        bcc     @dot
        cmp     #$7F
        bcc     @pr
@dot:   lda     #'.'
@pr:    jsr     v_out
        bcs     @full
        jmp     @ch
@nl:    jsr     v_nl
        bcc     @ch
@full:  jsr     v_atend         ; (the page ended at the end of the text)
        rts

; C=1 (and veof = 1) when vpos has reached vend
v_atend:
        lda     vpos
        cmp     vend
        lda     vpos+1
        sbc     vend+1
        bcc     @r
        lda     #1
        sta     veof
@r:     rts

; A = the byte at vpos, vpos + 1
v_next: lda     vpos
        sta     @rd+1
        lda     vpos+1
        sta     @rd+2
@rd:    lda     $FFFF
        inc     vpos
        bne     :+
        inc     vpos+1
:       rts

; print A; a new line after 79 (C=1: the page is full)
v_out:  jsr     SBC_CHROUT
        inc     vcol
        lda     vcol
        cmp     #79
        bcs     v_nl
        clc
        rts
v_nl:   lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jsr     SBC_CHROUT
        lda     #0
        sta     vcol
        inc     vlines
        lda     vlines
        cmp     #PAGE_LINES
        rts

; A = 0 nothing, 1 next page, 2 the page before, 3 close
v_input:
        lda     m_click
        beq     @mr
        lda     #0
        sta     m_click
        lda     #1
        rts
@mr:    lda     m_rclick
        beq     @pad
        lda     #0
        sta     m_rclick
        lda     #3
        rts
@pad:   jsr     SBC_PADSTATE    ; B, Select, Start close (the pad's
        tax                     ; directions and A come as W A S D space)
        eor     pad_old
        stx     pad_old
        and     pad_old
        and     #$0E
        beq     @key
        lda     #3
        rts
@key:   jsr     SBC_CHRIN
        bcs     @k
        lda     #0
        rts
@k:     cmp     #'a'
        bcc     @u
        cmp     #'z'+1
        bcs     @u
        and     #$DF
@u:     ldx     #0
@l:     ldy     vkey_tab,x
        beq     @none
        cmp     vkey_tab,x
        beq     @f
        inx
        inx
        bne     @l
@f:     lda     vkey_tab+1,x
        rts
@none:  lda     #0
        rts

; print the 0-ended string at A/Y
v_puts: sta     @rd+1
        sty     @rd+2
        ldx     #0
@rd:    lda     $FFFF,x
        beq     @r
        jsr     SBC_CHROUT
        inx
        bne     @rd
@r:     rts

; print A in decimal
v_dec:  jsr     dec3
        ldx     #0
@l:     lda     dbuf,x
        cmp     #' '
        beq     @n
        jsr     SBC_CHROUT
@n:     inx
        cpx     #3
        bne     @l
        rts

; ============================================================================
; drawing
; ============================================================================
draw_all:
        jsr     draw_title
        jsr     draw_head
        jsr     draw_list
        jsr     st_show
        jmp     draw_buttons

; row 0: "U:\GAMES\SUB" and the drive buttons
draw_title:
        jsr     clear_line
        lda     dev
        sta     line+1
        lda     #':'
        sta     line+2
        ldx     #3
        lda     cwd
        bne     @p
        lda     #$5C            ; (backslash)
        sta     line,x
        bne     @d
@p:     ldy     #0
@pl:    lda     cwd,y
        beq     @d
        cmp     #'/'
        bne     :+
        lda     #$5C            ; (backslash)
:       jsr     map_ch
        sta     line,x
        inx
        iny
        cpx     #23
        bcc     @pl
@d:     lda     #'U'
        sta     line+25
        lda     #'C'
        sta     line+29
        lda     #':'
        sta     line+26
        sta     line+30
        lda     #0
        sta     row
        lda     #$40
        sta     off
        ldx     #0
        lda     #24
        sta     lend
        jsr     put_cells
        lda     #'U'
        jsr     @btn
        sta     off
        ldx     #24
        lda     #28
        sta     lend
        jsr     put_cells
        lda     #'C'
        jsr     @btn
        sta     off
        ldx     #28
        lda     #32
        sta     lend
        jmp     put_cells
@btn:   cmp     dev             ; the drive in use: lit
        beq     :+
        lda     #$40
        rts
:       lda     #$80
        rts

; row 1: the column titles
draw_head:
        ldx     #31
@c:     lda     s_head,x
        sta     line,x
        dex
        bpl     @c
        lda     #1
        sta     row
        lda     #0
        sta     off
        tax
        lda     #32
        sta     lend
        jmp     put_cells

; row 23: the buttons (their columns lit)
draw_buttons:
        ldx     #0
        ldy     #23
        jsr     vdp_at
@c:     lda     #$40
        sta     off
        ldy     #0
@b:     lda     btn_x0,y
        cmp     #$FF
        beq     @w
        txa
        cmp     btn_x0,y
        bcc     @nx
        cmp     btn_x1,y
        bcs     @nx
        lda     #$80
        sta     off
        bne     @w
@nx:    iny
        bne     @b
@w:     lda     s_btns,x
        clc
        adc     off
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @c
        rts

; the list rows and the scroll bar
draw_list:
        jsr     calc_tpos
        lda     #0
        sta     cr
@r:     jsr     draw_row
        inc     cr
        lda     cr
        cmp     #LIST_H
        bne     @r
        rts

; the scroll bar's thumb: tpos = top * 17 / (n_list - 20), $FF = none
calc_tpos:
        lda     #$FF
        sta     tpos
        lda     n_list
        sec
        sbc     #LIST_H+1
        bcc     @r
        clc
        adc     #1
        sta     den
        lda     top             ; num = top * 17
        sta     num
        lda     #0
        sta     num+1
        ldx     #4
@m:     asl     num
        rol     num+1
        dex
        bne     @m
        lda     num
        clc
        adc     top
        sta     num
        bcc     :+
        inc     num+1
:       ldx     #0              ; (the quotient is 17 at most)
@d:     lda     num
        sec
        sbc     den
        tay
        lda     num+1
        sbc     #0
        bcc     @q
        sta     num+1
        sty     num
        inx
        bne     @d
@q:     stx     tpos
@r:     rts

; list row cr
draw_row:
        jsr     clear_line
        lda     #0
        sta     off
        lda     top
        clc
        adc     cr
        sta     ri
        cmp     n_list
        bcs     @sb
        cmp     sel
        bne     @f
        lda     #$80
        sta     off
@f:     jsr     fill_entry
@sb:    lda     cr              ; the scroll bar
        bne     :+
        lda     #$E0
        bne     @s
:       cmp     #LIST_H-1
        bne     :+
        lda     #$E1
        bne     @s
:       sec
        sbc     #1
        cmp     tpos
        bne     :+
        lda     #$E3
        bne     @s
:       lda     #$E2
@s:     sta     line+31
        lda     cr
        clc
        adc     #LIST_Y
        sta     row
        ldx     #0
        lda     #32
        sta     lend
        jmp     put_cells

; line = list entry ri: icon, name, size, kind
fill_entry:
        ldx     ri
        lda     order,x
        cmp     #$FF
        bne     @real
        lda     #2              ; "..": the up icon
        sta     line+1
        lda     #3
        sta     line+2
        lda     #'.'
        sta     line+4
        sta     line+5
        rts
@real:  jsr     get_ent
        jsr     ent_kind
        sta     kind
        asl
        sta     line+1
        ora     #1
        sta     line+2
        jsr     fmt_name
        ldx     #0
@n:     lda     nbuf,x
        beq     @sz
        jsr     map_ch
        sta     line+4,x
        inx
        bne     @n
@sz:    lda     kind
        bne     @file
        ldx     #4              ; a folder: "<DIR>"
@dl:    lda     s_dir,x
        sta     line+20,x
        dex
        bpl     @dl
        rts
@file:  jsr     dec32           ; the size, 8 columns
        ldx     #7
@sl:    lda     dbuf,x
        sta     line+17,x
        dex
        bpl     @sl
        lda     kind            ; the kind
        sec
        sbc     #2
        cmp     #3
        bcs     @r
        sta     t1
        asl
        asl
        adc     t1              ; * 5
        tax
        ldy     #0
@kl:    lda     s_kinds,x
        sta     line+26,y
        inx
        iny
        cpy     #5
        bne     @kl
@r:     rts

; a character of a name, for the font ($20-$5F)
map_ch: cmp     #'a'
        bcc     @l
        cmp     #'z'+1
        bcs     @h
        and     #$DF
        rts
@h:     lda     #'-'
        rts
@l:     cmp     #' '
        bcs     @r
        lda     #'?'
@r:     rts

clear_line:
        lda     #' '
        ldx     #31
@c:     sta     line,x
        dex
        bpl     @c
        rts

; line[X .. lend) to the screen at (X, row), the font + off ($00 list,
; $40 bars, $80 selected); icons ($00-$17) get +$0C on a selected row;
; $E0 and up as they are
put_cells:
        ldy     row
        jsr     vdp_at
@l:     lda     line,x
        cmp     #$18
        bcs     @t
        ldy     off
        cpy     #$80
        bne     @w
        clc
        adc     #$0C
        bne     @w
@t:     cmp     #$E0
        bcs     @w
        clc
        adc     off
@w:     sta     VDP_DATA
        inx
        cpx     lend
        bcc     @l
        rts

; ============================================================================
; numbers
; ============================================================================

; the size in ebuf+12 (32 bit) -> dbuf, 8 characters, right-aligned
dec32:  ldx     #3
@c:     lda     ebuf+12,x
        sta     num4,x
        dex
        bpl     @c
        lda     num4+3          ; 100,000,000 and up: "BIG"
        cmp     #>(100000000 >> 16)
        bcc     @ok
        bne     @big
        lda     num4+2
        cmp     #<(100000000 >> 16)
        bcc     @ok
        bne     @big
        lda     num4+1
        cmp     #>100000000
        bcc     @ok
        bne     @big
        lda     num4
        cmp     #<100000000
        bcc     @ok
@big:   ldx     #7
@bl:    lda     s_big,x
        sta     dbuf,x
        dex
        bpl     @bl
        rts
@ok:    lda     #0
        sta     dlead
        sta     dpos
@dig:   lda     dpos            ; the power of ten: p10 + 4 dpos
        asl
        asl
        tay
        ldx     #0
@sub:   lda     num4            ; subtract while it fits
        sec
        sbc     p10,y
        sta     t4
        lda     num4+1
        sbc     p10+1,y
        sta     t5
        lda     num4+2
        sbc     p10+2,y
        sta     t6
        lda     num4+3
        sbc     p10+3,y
        bcc     @put
        sta     num4+3
        lda     t6
        sta     num4+2
        lda     t5
        sta     num4+1
        lda     t4
        sta     num4
        inx
        bne     @sub
@put:   ldy     dpos
        cpy     #7
        beq     @dg             ; the last digit always shows
        cpx     #0
        bne     @dg
        lda     dlead
        bne     @dg
        lda     #' '
        bne     @st
@dg:    lda     #1
        sta     dlead
        txa
        ora     #'0'
@st:    sta     dbuf,y
        inc     dpos
        lda     dpos
        cmp     #8
        bne     @dig
        rts

; A -> dbuf[0..2], right-aligned (no leading zeros)
dec3:   ldx     #'0'-1
        sec
@h:     inx
        sbc     #100
        bcs     @h
        adc     #100
        stx     dbuf
        ldx     #'0'-1
        sec
@t:     inx
        sbc     #10
        bcs     @t
        adc     #10+'0'
        sta     dbuf+2
        stx     dbuf+1
        lda     dbuf
        cmp     #'0'
        bne     @r
        lda     #' '
        sta     dbuf
        lda     dbuf+1
        cmp     #'0'
        bne     @r
        lda     #' '
        sta     dbuf+1
@r:     rts

; ============================================================================
; the message line (row 22)
; ============================================================================
st_clear:
        lda     #' '
        ldx     #31
@c:     sta     stat,x
        dex
        bpl     @c
        lda     #1
        sta     spos
        rts

; message = the string at A/Y (shown)
st_text:
        pha
        jsr     st_clear
        pla
        jsr     st_str
        jmp     st_show

; add the string at A/Y
st_str: sta     @rd+1
        sty     @rd+2
        ldy     #0
@rd:    lda     $FFFF,y
        beq     @r
        jsr     st_chr
        iny
        bne     @rd
@r:     rts

st_chr: ldx     spos
        cpx     #32
        bcs     @r
        jsr     map_ch
        sta     stat,x
        inc     spos
@r:     rts

; add nbuf
st_name:
        lda     #<nbuf
        ldy     #>nbuf
        jmp     st_str

st_show:
        ldx     #31
@c:     lda     stat,x
        sta     line,x
        dex
        bpl     @c
        lda     #22
        sta     row
        lda     #0
        sta     off
        tax
        lda     #32
        sta     lend
        jmp     put_cells

; " 12 ITEMS"
st_count:
        jsr     st_clear
        lda     n_ent
        bne     @n
        lda     #<s_empty
        ldy     #>s_empty
        jsr     st_str
        jmp     st_show
@n:     jsr     dec3
        ldx     #0
@d:     lda     dbuf,x
        cmp     #' '
        beq     :+
        stx     t3
        jsr     st_chr
        ldx     t3
:       inx
        cpx     #3
        bne     @d
        lda     #<s_items
        ldy     #>s_items
        jsr     st_str
        jmp     st_show

; an error code A, in words
st_error:
        sta     errc
        jsr     st_clear
        ldx     #0
@l:     lda     err_tab,x
        beq     @gen
        cmp     errc
        beq     @f
        inx
        inx
        inx
        bne     @l
@f:     lda     err_tab+1,x
        ldy     err_tab+2,x
        jsr     st_str
        jmp     st_show
@gen:   lda     #<s_err
        ldy     #>s_err
        jsr     st_str
        lda     errc
        lsr
        lsr
        lsr
        lsr
        jsr     @hex
        lda     errc
        and     #15
        jsr     @hex
        jmp     st_show
@hex:   cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     st_chr

; ============================================================================
; the display
; ============================================================================
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared)
        lda     #<V_TP0
        ldy     #>V_TP0
        jsr     vdp_waddr
        lda     #<tile_p0
        ldx     #>tile_p0
        ldy     #8
        jsr     copy_pages
        lda     #<V_TP1
        ldy     #>V_TP1
        jsr     vdp_waddr
        lda     #<tile_p1
        ldx     #>tile_p1
        ldy     #8
        jsr     copy_pages
        lda     #<V_ATT
        ldy     #>V_ATT
        jsr     vdp_waddr
        lda     #<tile_attr
        ldx     #>tile_attr
        ldy     #1
        jsr     copy_pages
        lda     #<V_SP0
        ldy     #>V_SP0
        jsr     vdp_waddr
        lda     #<spr_p0
        ldx     #>spr_p0
        jsr     copy8
        lda     #<V_SP1
        ldy     #>V_SP1
        jsr     vdp_waddr
        lda     #<spr_p1
        ldx     #>spr_p1
        jsr     copy8
        lda     #$C0 | 16       ; palette entries 16-63 (R47: the data port
        ldx     #47             ; writes the palette, counting up)
        jsr     vdp_reg
        ldx     #0
@pl:    lda     pal_gui,x
        sta     VDP_DATA
        inx
        cpx     #96
        bne     @pl
        lda     #0
        ldx     #47
        jsr     vdp_reg
        ldx     #0              ; the F18A's registers
@fr:    stx     t1
        lda     f18a_regs+1,x
        pha
        lda     f18a_regs,x
        tax
        pla
        jsr     vdp_reg
        ldx     t1
        inx
        inx
        cpx     #F18A_N * 2
        bne     @fr
        lda     #<V_SAT         ; the pointer (hidden until placed), the end
        ldy     #>V_SAT
        jsr     vdp_waddr
        lda     #$C0
        sta     VDP_DATA
        lda     #0
        sta     VDP_DATA
        sta     VDP_DATA
        lda     #15
        sta     VDP_DATA
        lda     #$D0
        sta     VDP_DATA
        lda     #1
        sta     gfx_on
        lda     mouse_ok
        beq     :+
        jsr     put_pointer
:       lda     #$C0            ; R1: display on, 16K, 8 x 8 sprites, no
        ldx     #1              ; VDP interrupt
        jmp     vdp_reg

; the display back to the console's (the PICO9918 reset: registers, palette)
leave_gfx:
        lda     #0
        sta     gfx_on
        lda     #$C0
        ldx     #50
        jmp     vdp_reg

; copy Y pages from A (lo) / X (hi) to VRAM (the address set)
copy_pages:
        sta     vdp_src
        stx     vdp_src+1
        lda     #0
        sta     vdp_n
        sty     vdp_n+1
        jmp     vdp_copy
copy8:  sta     vdp_src
        stx     vdp_src+1
        lda     #8
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        jmp     vdp_copy

; ============================================================================
; the mouse (SBC_MOUSEON / SBC_MOUSE)
; ============================================================================
mouse_init:
        lda     #0
        sta     mouse_ok
        sta     m_old
        lda     SBC_MOUSEON
        cmp     #$4C
        bne     @r
        lda     #1
        jsr     SBC_MOUSEON
        bcs     @r
        lda     #1
        sta     mouse_ok
        jsr     SBC_MOUSE       ; (the buttons as they are now)
        sta     m_old
        jsr     put_pointer
@r:     rts

mouse_off:
        lda     mouse_ok
        beq     @r
        lda     #0
        jsr     SBC_MOUSEON
@r:     rts

mouse_flush:
        jsr     mouse_poll
        lda     #0
        sta     m_click
        sta     m_rclick
        rts

; move the pointer; m_click / m_rclick = a button pressed
mouse_poll:
        lda     mouse_ok
        bne     @go
        rts
@go:    jsr     SBC_MOUSE
        bcs     @rep
        rts
@rep:   sta     m_btn
        sty     m_dy
        txa                     ; x: 0 .. 252
        beq     @y
        bmi     @xn
        clc
        adc     m_x
        bcs     @xmax
        cmp     #253
        bcc     @xs
@xmax:  lda     #252
        bne     @xs
@xn:    clc
        adc     m_x
        bcs     @xs
        lda     #0
@xs:    sta     m_x
@y:     lda     m_dy            ; y: 0 .. 190
        beq     @b
        bmi     @yn
        clc
        adc     m_y
        bcs     @ymax
        cmp     #191
        bcc     @ys
@ymax:  lda     #190
        bne     @ys
@yn:    clc
        adc     m_y
        bcs     @ys
        lda     #0
@ys:    sta     m_y
@b:     lda     m_old           ; pressed now and not before
        eor     #$FF
        and     m_btn
        lsr
        bcc     @nl
        ldx     #1
        stx     m_click
@nl:    lsr
        bcc     @nr
        ldx     #1
        stx     m_rclick
@nr:    lda     m_btn
        sta     m_old
put_pointer:
        lda     gfx_on
        beq     @r
        lda     #<V_SAT
        ldy     #>V_SAT
        jsr     vdp_waddr
        ldx     m_y
        dex
        stx     VDP_DATA
        lda     m_x
        sta     VDP_DATA
@r:     rts

        .include "lib/vdp.s"

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"

; R0-R7: Graphics I, display off, names $2000, attributes $2400, tile
; patterns $0000, sprite attributes $2600, sprite patterns $1000
vdp_regs:
        .byte   $00, $80, VDP_NAME / $400, V_ATT / $40, V_TP0 / $800, V_SAT / $80, V_SP0 / $800, $01
f18a_regs:
        .byte   24, 0                   ; palette selects (ECM: unused)
        .byte   29, 0                   ; 2K plane offsets, one page
        .byte   30, 31                  ; sprites a line
        .byte   50, $00
        .byte   49, $22                 ; ECM2 tiles, ECM2 sprites, one layer
F18A_N          = (* - f18a_regs) / 2

; the extensions: 3 letters and the kind (2 program, 3 BASIC, 4 text)
ext_tab:
        .byte   "BIN", 2, "BAS", 3
        .byte   "TXT", 4, "DOC", 4, "ME ", 4, "MD ", 4, "INC", 4, "S  ", 4
        .byte   "ASM", 4, "LST", 4, "CFG", 4, "BAT", 4, "LOG", 4, "INI", 4
        .byte   "C  ", 4, "H  ", 4, "PY ", 4, "CSV", 4, "LBL", 4, "MAP", 4
        .byte   0

; keys and what they do
key_tab:
        .byte   KEY_UP, KEY_DOWN, KEY_LEFT, K_BS, K_DEL, KEY_ESC
        .byte   KEY_RIGHT, K_CR, 'U', 'C', 'B', 'M', 'Q', 'R', '<', '>', $2C, '.'   ; ($2C = comma)
        .byte   KEY_F1+4, KEY_F1+5, KEY_F1+7, 'K', 'P', 'X'
        .byte   0
key_go: .word   sel_up-1, sel_dn-1, go_up-1, go_up-1, go_up-1, go_up-1
        .word   open_sel-1, open_sel-1, drive_u-1, drive_c-1, act_basic-1
        .word   act_monitor-1, act_menu-1, refresh-1, page_up-1, page_down-1
        .word   page_up-1, page_down-1
        .word   act_copy-1, act_paste-1, act_delete-1, act_copy-1, act_paste-1, act_delete-1

; the viewer's keys: key, 1 next / 2 back / 3 close
vkey_tab:
        .byte   ' ', 1, K_CR, 1, KEY_DOWN, 1, 'S', 1, 'D', 1, KEY_RIGHT, 1
        .byte   KEY_UP, 2, 'W', 2, 'A', 2
        .byte   'Q', 3, KEY_ESC, 3, K_ESC, 3, K_BS, 3, K_DEL, 3, KEY_LEFT, 3
        .byte   0

; the buttons on row 23: first column, after the last, what they do
btn_x0: .byte   0, 5, 11, 15, 18, 24, 28, $FF
btn_x1: .byte   4, 10, 14, 17, 23, 27, 32
btn_go: .word   act_copy-1, act_paste-1, act_delete-1, go_up-1
        .word   act_basic-1, act_monitor-1, act_menu-1

s_btns: .byte   "COPY PASTE DEL UP BASIC MON MENU"
s_head: .byte   "    NAME             SIZE TYPE  "
s_dir:  .byte   "<DIR>"
s_kinds:
        .byte   "PROG BASICTEXT "
s_big:  .byte   "     BIG"
s_reading:
        .byte   "READING THE FOLDER...", 0
s_start:
        .byte   "STARTING ", 0
s_read: .byte   "READING ", 0
s_long: .byte   "?FOLDER PATH TOO LONG", 0
s_empty:
        .byte   " EMPTY FOLDER", 0
s_items:
        .byte   " ITEMS", 0
s_err:  .byte   "?DISK ERROR $", 0
s_nodisk:
        .byte   "?NO DISK", 0
s_nf:   .byte   "?NOT FOUND", 0
s_nodrv:
        .byte   "?NO SUCH DRIVE", 0
s_ready:
        .byte   "TO PASTE: ", 0
s_noclip:
        .byte   "?NOTHING TO PASTE (COPY FIRST)", 0
s_same: .byte   "?IT IS ALREADY IN THIS FOLDER", 0
s_isdir:
        .byte   "?A FOLDER HAS THAT NAME", 0
s_replace:
        .byte   "REPLACE ", 0
s_delete:
        .byte   "DELETE ", 0
s_copying:
        .byte   "COPYING ", 0
s_copied:
        .byte   "COPIED ", 0
s_deleted:
        .byte   "DELETED", 0
s_onlyf:
        .byte   "?SELECT A FILE (NOT A FOLDER)", 0
s_yesno:
        .byte   "YES  NO"
s_toobig:
        .byte   "?TOO BIG TO COPY", 0
s_nodel:
        .byte   "?THIS DRIVE CANNOT DELETE YET", 0
err_tab:
        .byte   $F2
        .word   s_nodisk
        .byte   $42
        .word   s_nf
        .byte   $FE
        .word   s_nodrv
        .byte   $F0
        .word   s_toobig
        .byte   $FD
        .word   s_nodel
        .byte   0
s_page: .byte   "     page ", 0
s_vmore:
        .byte   "-- Space: next page   Up: back   Q / Esc: close --", 0
s_vend: .byte   "-- end --   Up: back   Q / Esc: close", 0

; powers of ten for dec32 (10,000,000 .. 1)
p10:
        .byte   $80, $96, $98, $00   ; 10000000
        .byte   $40, $42, $0F, $00   ; 1000000
        .byte   $A0, $86, $01, $00   ; 100000
        .byte   $10, $27, $00, $00   ; 10000
        .byte   $E8, $03, $00, $00   ; 1000
        .byte   $64, $00, $00, $00   ; 100
        .byte   $0A, $00, $00, $00   ; 10
        .byte   $01, $00, $00, $00   ; 1

dirblk: .word   table
        .byte   MAXENT, 'U'
ldblk:  .word   viewbuf
        .word   VIEW_END - viewbuf
        .res    13

        .include "gui_gfx.inc"
gui_end:

; ============================================================================
; variables (in the shell's own bank; kept while programs run)
; ============================================================================
        .segment "BSS"
dev:    .res    1               ; 'U' or 'C'
cwd:    .res    32              ; the folder: "" or "/A/B"
up_name:
        .res    13
n_ent:  .res    1               ; entries read
n_list: .res    1               ; rows in the list (+ "..")
k0:     .res    1               ; the first real entry's row (0 or 1)
sel:    .res    1
top:    .res    1
osel:   .res    1
otop:   .res    1
tpos:   .res    1
order:  .res    MAXENT + 1      ; list row -> table entry ($FF = "..")
ebuf:   .res    16
nbuf:   .res    13
nlen:   .res    1
kind:   .res    1
ea:     .res    2
si:     .res    1
sj:     .res    1
sv:     .res    1
t1:     .res    1
t2:     .res    1
t3:     .res    1
t4:     .res    1
t5:     .res    1
t6:     .res    1
num:    .res    2
den:    .res    1
num4:   .res    4
dbuf:   .res    8
dlead:  .res    1
dpos:   .res    1
cx:     .res    1
cy:     .res    1
cr:     .res    1
ri:     .res    1
row:    .res    1
off:    .res    1
lend:   .res    1
line:   .res    32
stat:   .res    32
spos:   .res    1
errc:   .res    1
frames: .res    1
click_t:
        .res    1
esc_st: .res    1
pad_now:
        .res    1
pad_old:
        .res    1
pad_new:
        .res    1
pad_rep:
        .res    1
gfx_on: .res    1
mouse_ok:
        .res    1
m_x:    .res    1
m_y:    .res    1
m_dy:   .res    1
m_btn:  .res    1
m_old:  .res    1
m_click:
        .res    1
m_rclick:
        .res    1
runblk: .res    16
clip_dev:
        .res    1
clip_path:
        .res    46
clip_name:
        .res    13
pbuf:   .res    46
cpblk:  .res    6
delblk: .res    3
errc2:  .res    1
vpos:   .res    2
vend:   .res    2
vstart: .res    2
vpn:    .res    1
VSTK    = 64
vstk_lo:
        .res    VSTK
vstk_hi:
        .res    VSTK
vlines: .res    1
vcol:   .res    1
veof:   .res    1
table:  .res    MAXENT * 16     ; the folder (SBC_DIR)
viewbuf:                        ; the text viewer's file, to $7EFF
VIEW_END        = $7F00
