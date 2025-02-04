        .feature string_escapes
        .setcpu "6502"

        .include "apple2.inc"
        .include "../inc/macros.inc"
        .include "../inc/apple2.inc"
        .include "../inc/prodos.inc"
        .include "../mgtk/mgtk.inc"
        .include "../desktop.inc"

;;; ============================================================

        .org $800

        jmp     entry

;;; ============================================================

pathbuf:        .res    65, 0

font_buffer     := $D00
io_buf          := WINDOW_ICON_TABLES
read_length      = WINDOW_ICON_TABLES-font_buffer

        DEFINE_OPEN_PARAMS open_params, pathbuf, io_buf
        DEFINE_READ_PARAMS read_params, font_buffer, read_length
        DEFINE_CLOSE_PARAMS close_params

;;; ============================================================
;;; Get filename by checking DeskTop selected window/icon

entry:

.proc get_filename
        ;; Check that an icon is selected
        lda     #0
        sta     pathbuf
        lda     selected_file_count
        beq     abort           ; some file properties?
        lda     path_index      ; prefix index in table
        bne     :+
abort:  rts

        ;; Copy path (prefix) into pathbuf.
:       src := $06
        dst := $08

        asl     a               ; (since address table is 2 bytes wide)
        tax
        copy16  path_table,x, src
        ldy     #0
        lda     (src),y
        tax
        inc     src
        bne     :+
        inc     src+1
:       copy16  #pathbuf+1, dst
        jsr     copy_pathbuf   ; copy x bytes (src) to (dst)

        ;; Append separator.
        lda     #'/'
        ldy     #0
        sta     (dst),y
        inc     pathbuf
        inc     dst
        bne     :+
        inc     dst+1

        ;; Get file entry.
:       lda     selected_file_list      ; file index in table
        asl     a               ; (since table is 2 bytes wide)
        tax
        copy16  file_table,x, src

        ;; Exit if a directory.
        ldy     #2              ; 2nd byte of entry
        lda     (src),y
        and     #icon_entry_type_mask
        bne     :+
        rts                     ; 000 = directory

        ;; Set window title to point at filename (9th byte of entry)
        ;; (title includes the spaces before/after from the icon)
:       clc
        lda     src
        adc     #IconEntry::len
        sta     winfo_title
        lda     src+1
        adc     #0
        sta     winfo_title+1

        ;; Append filename to path.
        ldy     #IconEntry::len
        lda     (src),y         ; grab length
        tax                     ; name has spaces before/after
        dex                     ; so subtract 2 to get actual length
        dex
        clc
        lda     src
        adc     #11             ; 9 = length, 10 = space, 11 = name
        sta     src
        bcc     :+
        inc     src+1
:       jsr     copy_pathbuf    ; copy x bytes (src) to (dst)

        jmp     load_file_and_run_da

.proc copy_pathbuf              ; copy x bytes from src to dst
        ldy     #0              ; incrementing path length and dst
loop:   lda     (src),y
        sta     (dst),y
        iny
        inc     pathbuf
        dex
        bne     loop
        tya
        clc
        adc     dst
        sta     dst
        bcc     end
        inc     dst+1
end:    rts
.endproc

.endproc

;;; ============================================================
;;; Load the file

.proc load_file_and_run_da
        ;; TODO: Ensure there's enough room, fail if not

        ;; NOTE: This only leaves $1000-$1AFF (2816 bytes)
        ;; which is not enough for all the wide fonts.

        ;; --------------------------------------------------
        ;; Load the file

        sta     ALTZPOFF
        MLI_CALL OPEN, open_params ; TODO: Check for error
        lda     open_params::ref_num
        sta     read_params::ref_num
        sta     close_params::ref_num
        MLI_CALL READ, read_params ; TODO: Check for error
        MLI_CALL CLOSE, close_params
        sta     ALTZPON


        ;; --------------------------------------------------
        ;; Copy the DA code and loaded data to AUX

        lda     ROMIN2
        copy16  #DA_LOAD_ADDRESS, STARTLO
        copy16  #WINDOW_ICON_TABLES-1, ENDLO
        copy16  #DA_LOAD_ADDRESS, DESTINATIONLO
        sec                     ; main>aux
        jsr     AUXMOVE
        lda     LCBANK1
        lda     LCBANK1

        ;; --------------------------------------------------
        ;; Run the DA from Aux, back to Main when done

        sta     RAMRDON
        sta     RAMWRTON
        jsr     init
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts
.endproc

;;; ============================================================

da_window_id    = 60
da_width        = 380
da_height       = 140
da_left         = (screen_width - da_width)/2
da_top          = (screen_height - da_height)/2

.proc winfo
window_id:      .byte   da_window_id
options:        .byte   MGTK::Option::go_away_box
title:          .addr   0       ; overwritten to point at filename
hscroll:        .byte   MGTK::Scroll::option_none
vscroll:        .byte   MGTK::Scroll::option_none
hthumbmax:      .byte   32
hthumbpos:      .byte   0
vthumbmax:      .byte   32
vthumbpos:      .byte   0
status:         .byte   0
reserved:       .byte   0
mincontwidth:   .word   da_width
mincontlength:  .word   da_height
maxcontwidth:   .word   da_width
maxcontlength:  .word   da_height
port:
viewloc:        DEFINE_POINT da_left, da_top
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .word   MGTK::screen_mapwidth
maprect:        DEFINE_RECT 0, 0, da_width, da_height
pattern:        .res    8, $FF
colormasks:     .byte   MGTK::colormask_and, MGTK::colormask_or
penloc:          DEFINE_POINT 0, 0
penwidth:       .byte   2
penheight:      .byte   1
penmode:        .byte   0
textback:       .byte   $7F
textfont:       .addr   font_buffer
nextwinfo:      .addr   0
.endproc
        winfo_title := winfo::title

;;; ============================================================

.proc event_params
kind:  .byte   0
;;; EventKind::key_down
key             := *
modifiers       := * + 1
;;; EventKind::update
window_id       := *
;;; otherwise
xcoord          := *
ycoord          := * + 2
        .res    4
.endproc

.proc findwindow_params
mousex:         .word   0
mousey:         .word   0
which_area:     .byte   0
window_id:      .byte   0
.endproc

.proc trackgoaway_params
clicked:        .byte   0
.endproc

.proc dragwindow_params
window_id:      .byte   0
dragx:          .word   0
dragy:          .word   0
moved:          .byte   0
.endproc

.proc winport_params
window_id:      .byte   da_window_id
port:           .addr   grafport
.endproc

.proc grafport
viewloc:        DEFINE_POINT 0, 0
mapbits:        .word   0
mapwidth:       .word   0
cliprect:       DEFINE_RECT 0, 0, 0, 0
pattern:        .res    8, 0
colormasks:     .byte   0, 0
penloc:         DEFINE_POINT 0, 0
penwidth:       .byte   0
penheight:      .byte   0
penmode:        .byte   0
textback:       .byte   0
textfont:       .addr   0
.endproc

.proc drawtext_params_char
        .addr   char_label
        .byte   1
.endproc
char_label:  .byte   0

;;; ============================================================


;;; ============================================================

.proc init
        MGTK_CALL MGTK::OpenWindow, winfo
        jsr     draw_window
        MGTK_CALL MGTK::FlushEvents
        ;; fall through
.endproc

.proc input_loop
        MGTK_CALL MGTK::GetEvent, event_params
        bne     exit
        lda     event_params::kind
        cmp     #MGTK::EventKind::button_down ; was clicked?
        bne     :+
        jmp     handle_down


:       cmp     #MGTK::EventKind::key_down  ; any key?
        bne     :+
        jmp     handle_key


:       jmp     input_loop
.endproc

.proc exit
        MGTK_CALL MGTK::CloseWindow, winfo
        ITK_CALL IconTK::REDRAW_ICONS
        rts                     ; exits input loop
.endproc

;;; ============================================================

.proc handle_key
        lda     event_params::key
        cmp     #CHAR_ESCAPE
        bne     :+
        jmp     exit
:       jmp     input_loop
.endproc

;;; ============================================================

.proc handle_down
        copy16  event_params::xcoord, findwindow_params::mousex
        copy16  event_params::ycoord, findwindow_params::mousey
        MGTK_CALL MGTK::FindWindow, findwindow_params
        bpl     :+
        jmp     exit
:       lda     findwindow_params::window_id
        cmp     winfo::window_id
        bpl     :+
        jmp     input_loop
:       lda     findwindow_params::which_area
        cmp     #MGTK::Area::close_box
        beq     handle_close
        cmp     #MGTK::Area::dragbar
        beq     handle_drag
        jmp     input_loop
.endproc

;;; ============================================================

.proc handle_close
        MGTK_CALL MGTK::TrackGoAway, trackgoaway_params
        lda     trackgoaway_params::clicked
        bne     :+
        jmp     input_loop
:       jmp     exit
.endproc

;;; ============================================================

.proc handle_drag
        copy    winfo::window_id, dragwindow_params::window_id
        copy16  event_params::xcoord, dragwindow_params::dragx
        copy16  event_params::ycoord, dragwindow_params::dragy
        MGTK_CALL MGTK::DragWindow, dragwindow_params
        lda     dragwindow_params::moved
        bpl     :+

        ;; Draw DeskTop's windows (from Main)
        sta     RAMRDOFF
        sta     RAMWRTOFF
        jsr     JUMP_TABLE_REDRAW_ALL
        sta     RAMRDON
        sta     RAMWRTON

        ;; Draw DA's window
        jsr     draw_window

        ;; Draw DeskTop icons
        ITK_CALL IconTK::REDRAW_ICONS

:       jmp     input_loop

.endproc

;;; ============================================================

line1:  PASCAL_STRING "\x00 \x01 \x02 \x03 \x04 \x05 \x06 \x07 \x08 \x09 \x0A \x0B \x0C \x0D \x0E \x0F"
line2:  PASCAL_STRING "\x10 \x11 \x12 \x13 \x14 \x15 \x16 \x17 \x18 \x19 \x1A \x1B \x1C \x1D \x1E \x1F"
line3:  PASCAL_STRING "  ! \x22 # $ % & ' ( ) * + , - . /"
line4:  PASCAL_STRING "0 1 2 3 4 5 6 7 8 9 : ; < = > ?"
line5:  PASCAL_STRING "@ A B C D E F G H I J K L M N O"
line6:  PASCAL_STRING "P Q R S T U V W X Y Z [ \x5C ] ^ _"
line7:  PASCAL_STRING "` a b c d e f g h i j k l m n o"
line8:  PASCAL_STRING "p q r s t u v w x y z { | } ~ \x7F"

        line_count = 8
line_addrs:
        .addr line1, line2, line3, line4, line5, line6, line7, line8

pos:    DEFINE_POINT 0,0, pos

        initial_y = 5
        line_height = 15


.proc draw_window
        ptr := $06

PARAM_BLOCK params, $06
data:   .addr   0
len:    .byte   0
width:  .word   0
END_PARAM_BLOCK

        MGTK_CALL MGTK::GetWinPort, winport_params
        cmp     #MGTK::Error::window_obscured
        bne     :+
        rts

:       MGTK_CALL MGTK::SetPort, grafport
        MGTK_CALL MGTK::HideCursor

        copy16  #initial_y, pos::ycoord


        copy    #0, index
loop:   lda     index
        asl
        tax
        copy16  line_addrs,x, ptr

        ldy     #0
        lda     (ptr),y         ; length
        sta     params::len
        add16   ptr, #1, params::data ; offset past length

        ;; Position the string
        MGTK_CALL MGTK::TextWidth, params
        sub16   #da_width, params::width, pos::xcoord ; center it
        lsr16   pos::xcoord
        add16   pos::ycoord, #line_height, pos::ycoord ; next row

        MGTK_CALL MGTK::MoveTo, pos
        MGTK_CALL MGTK::DrawText, params

        inc     index
        lda     index
        cmp     #line_count
        bne     loop

        MGTK_CALL MGTK::ShowCursor
        rts

index:  .byte   0

.endproc


;;; ============================================================

.assert * < font_buffer, error, "DA too big"
