;   AsmBASIC - a BASIC compile and go system written in assembly language
;   Copyright (C) 2022  Ekkehard Morgenstern
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
;   NOTE: Programs created with AsmBASIC do not fall under this license.
;
;   CONTACT INFO:
;       E-Mail: ekkehard@ekkehardmorgenstern.de
;       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
;             Germany, Europe

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        %include    "sdlconshr.inc"
                        %include    "sdlconcev.inc"

SDL_PRINTBUFSIZE        equ         16384
SDL_KBDINPBUFSIZE       equ         128
SDL_ESCSEQBUFSIZE       equ         64

                        section     .text

                        global      sdl_launch
                        global      sdl_printf,sdl_readln,sdl_color,sdl_cls
                        extern      chkkernver,sdl_worker
                        extern      snprintf,atexit,exit,fprintf,stderr,strlen
                        extern      SDL_SetMainReady,SDL_Init,SDL_GetError
                        extern      SDL_Quit,SDL_CreateThread,SDL_WaitThread
                        extern      SDL_Delay, ucinsavectx,ucinloadctx
                        extern      sdl_screenbuf,sdl_screenbuf_size
                        extern      sdl_text_attribute
                        extern      sdl_have_input,sdl_want_input
                        extern      sdl_worker_terminated
                        extern      sdl_workbuf,sdl_workbuf_size
                        extern      sdl_textscreen_width,sdl_textscreen_height
                        extern      sdl_textscreen_size,sdl_textcursor_pos
                        extern      sdl_worker,sdl_worker_doquit,sdl_init_ok
                        extern      sdl_worker_handle,sdl_worker_result
                        extern      ucinsavectx,ucinloadctx,sdl_waitepoll
                        extern      uclineininit,ucgetcp,sdl_initepoll
                        extern      sdl_kbdinit,sdl_kbdgetbuf

sdl_launch              enter       0,0

                        ; check kernel version >= 2.6.37 b/c of epoll API
                        call        chkkernver

                        ; initialize epoll stuff
                        call        sdl_initepoll

                        ; initialize keyboard stuff
                        call        sdl_kbdinit

                        ; clear out screen and work buffers
                        lea         rdi,[sdl_screenbuf]
                        mov         rcx,[sdl_screenbuf_size]
                        shr         rcx,3   ; /8
                        xor         rax,rax
                        cld
                        rep         stosq
                        lea         rdi,[sdl_workbuf]
                        mov         rcx,[sdl_screenbuf_size]
                        shr         rcx,3   ; /8
                        rep         stosq

                        ; initialize text screen settings
                        mov         rax,SDL_TEXTSCREENWIDTH
                        mov         [sdl_textscreen_width],rax
                        mov         rax,SDL_TEXTSCREENHEIGHT
                        mov         [sdl_textscreen_height],rax
                        mov         rax,SDL_TEXTSCREENCELLS
                        mov         [sdl_textscreen_size],rax
                        xor         rax,rax
                        mov         [sdl_textcursor_pos],rax

                        ; call SDL_SetMainReady
                        call        SDL_SetMainReady

                        ; call SDL_Init
                        ;   TIMER, AUDIO, VIDEO, GAMECONTROLLER, EVENTS
                        mov         rdi,0x00006031
                        call        SDL_Init
                        test        rax,rax
                        jz          .init_ok

                        call        SDL_GetError
                        mov         rdi,[stderr]
                        lea         rsi,[sdl_initerr]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf

                        mov         rdi,1
                        call        exit

                        ; enqueue SDL_Quit for automated cleanup
.init_ok                lea         rdi,[SDL_Quit]
                        call        atexit

                        ; create the SDL worker thread
                        lea         rdi,[sdl_worker]
                        lea         rsi,[sdl_worker_moniker]
                        xor         rdx,rdx
                        mov         [sdl_worker_doquit],rdx
                        mov         [sdl_init_ok],rdx
                        call        SDL_CreateThread
                        test        rax,rax
                        jnz         .thread_ok

                        call        SDL_GetError
                        mov         rdi,[stderr]
                        lea         rsi,[sdl_thrcrterr]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf

                        mov         rdi,1
                        call        exit

.thread_ok              mov         [sdl_worker_handle],rax
                        lea         rdi,[sdl_cleanupworker]
                        call        atexit

.wait_feedback          call        sdl_waitepoll

                        mov         rdx,rax
                        and         rdx,SDL_WEP_WORKERINITDONE
                        jz          .wait_feedback

                        cmp         qword [sdl_init_ok],-1
                        je          .init_failed

                        ; init ok

.end                    leave
                        ret

.init_failed            mov         rdi,[stderr]
                        lea         rsi,[sdl_thrreperr]
                        xor         al,al
                        call        fprintf

                        mov         rdi,1
                        call        exit

                        jmp         .end

sdl_cleanupworker       enter       0,0
                        ; set 'quit' flag for worker thread
                        mov         qword [sdl_worker_doquit],1
                        ; wait for it to terminate
                        mov         rdi,[sdl_worker_handle]
                        lea         rsi,[sdl_worker_result]
                        call        SDL_WaitThread
                        ; done
                        leave
                        ret

                        ; CLIENT API
                        ; rdi - fmt
                        ; ... args
                        ; al - number of (floating-point) arguments in
                        ;      vector registers
sdl_printf              enter       0x30,0

                        ; use snprintf(3) to fill print buffer
                        push        r9
                        push        r8
                        mov         r9,rcx
                        mov         r8,rdx
                        mov         rcx,rsi
                        mov         rdx,rdi
                        mov         rsi,sdl_printbuf_size
                        lea         rdi,[sdl_printbuf]
                        call        snprintf
                        add         rsp,16

                        ; get length of string
                        lea         rdi,[sdl_printbuf]
                        call        strlen
                        mov         [rbp-0x08],rax

                        ; save UTF-8 decoder state
                        lea         rdi,[rbp-0x30]
                        call        ucinsavectx

                        ; initialize UTF-8 decoder with print buffer
                        lea         rdi,[sdl_printbuf]
                        mov         rsi,[rbp-0x08]
                        call        uclineininit

                        ; get next code point
.nextchar               call        ucgetcp
                        cmp         rax,-1
                        je          .end

                        ; check for pending escape sequence
                        cmp         byte [sdl_escseqflag],0
                        je          .notescseq

                        cmp         byte [sdl_escseqflag],1
                        jne         .csiseq

                        cmp         rax,'['
                        jne         .stopescseq

                        mov         byte [sdl_escseqflag],2     ; csi seq
                        jmp         .nextchar

                        ; CSI sequence
                        ; if character is '0'..'9' or ';', add to sequence
.csiseq                 cmp         rax,'0'
                        jb          .lower0
                        cmp         rax,'9'
                        ja          .greater9

.stoescchr              mov         dl,[sdl_escseqbufpos]
                        cmp         dl,SDL_ESCSEQBUFSIZE-1
                        jae         .nextchar

                        movzx       rdx,dl
                        mov         [sdl_escseqbuf+rdx],al
                        inc         dl
                        mov         [sdl_escseqbufpos],dl
                        jmp         .nextchar

.greater9               cmp         rax,';'
                        je          .stoescchr

.lower0                 mov         [sdl_escseqtype],al
                        mov         byte [sdl_escseqflag],0
                        movzx       rdx,byte [sdl_escseqbufpos]
                        mov         byte [sdl_escseqbuf+rdx],0

                        call        sdl_execescseq
                        jmp         .nextchar

                        ; check for escape character
.notescseq              cmp         rax,27
                        jne         .notescape

                        mov         byte [sdl_escseqbufpos],0
                        mov         byte [sdl_escseqtype],0
                        mov         byte [sdl_escseqflag],1
                        jmp         .nextchar

.stopescseq             mov         byte [sdl_escseqflag],0
                        jmp         .nextchar

                        ; check for line feed character
.notescape              cmp         rax,10
                        jne         .notlinefeed

                        call        sdl_outputlf
                        jmp         .nextchar

.notlinefeed            cmp         rax,13
                        jne         .notcarriagereturn

                        ; CR is synonymous with LF here b/c in actuality (i.e.
                        ; on Linux), LF is the line feed character, but on
                        ; classic BASIC computers, CR is used as the line feed
                        ; character. As a compromise, we'll support both here
                        call        sdl_outputlf
                        jmp         .nextchar

.notcarriagereturn      cmp         rax,8
                        jne         .notbackspace

                        call        sdl_outputbs
                        jmp         .nextchar

                        ; write character at the current text cursor position
.notbackspace           mov         rdi,rax
                        call        sdl_outputcp
                        jmp         .nextchar

                        ; restore UTF-8 decoder state
.end                    lea         rdi,[rbp-0x30]
                        call        ucinloadctx

                        leave
                        ret

                        ; execute an escape sequence
sdl_execescseq          enter       0,0
                        lea         rsi,[sdl_escseqbuf]
                        cld
                        xor         dh,dh   ; dh - param cnt
.nextparam              xor         ah,ah   ; ah - param val

.getchr                 lodsb
                        cmp         al,0
                        je          .eos
                        cmp         al,';'
                        je          .semic
                        cmp         al,'0'
                        jb          .getchr
                        cmp         al,'9'
                        ja          .getchr

                        ; ah = ah*10 + (al-'0')
                        mov         dl,ah   ; ah *= 10
                        shl         ah,3
                        add         ah,dl
                        add         ah,dl
                        sub         al,'0'  ; ah += al-'0'
                        add         ah,al
                        jmp         .getchr

.eos:
.semic                  test        ah,ah
                        jz          .zeroparam

                        cmp         dh,10
                        jae         .endparams

                        mov         cl,dh
                        movzx       rcx,cl
                        mov         [sdl_escapeparams+rcx],ah
                        inc         dh

.zeroparam              test        al,al
                        jnz         .nextparam

.endparams              mov         [sdl_numescparams],dh
                        mov         al,[sdl_escseqtype]

                        cmp         al,'m'
                        jne         .notmseq

                        xor         rcx,rcx
                        xor         rdx,rdx
.nextmparam             cmp         cl,[sdl_numescparams]
                        jae         .endmparam
                        mov         al,[sdl_escapeparams+rcx]
                        cmp         al,30
                        jb          .lower30
                        cmp         al,37
                        ja          .higher37
                        mov         dl,al   ; fg col
                        sub         dl,30
.lower30:
.lower40:
.higher47:
.nextmparam2            inc         cl
                        jmp         .nextmparam

.higher37               cmp         al,40
                        jb          .lower40
                        cmp         al,47
                        ja          .higher47
                        mov         dh,al
                        sub         dh,40

.endmparam              mov         rdi,rdx
                        call        sdl_color
                        jmp         .end

.notmseq                cmp         al,'H'
                        jne         .notHseq

                        nop

.notHseq                cmp         al,'J'
                        jne         .notJseq

                        nop

.notJseq:
.end                    leave
                        ret

                        ; output BACKSPACE character
sdl_outputbs            enter       0,0

                        mov         rax,[sdl_textcursor_pos]
                        test        rax,rax
                        jz          .scroll

.setpos                 dec         rax
                        mov         [sdl_textcursor_pos],rax

.end                    leave
                        ret

.scroll                 call        sdl_scrolldown

                        mov         rax,[sdl_textscreen_width]
                        jmp         .setpos

sdl_outputlf            enter       0,0

                        ; divide the cursor position by the screen width
                        ; and then multiply with that +1 to get the cursor
                        ; position at the beginning of the next line

                        mov         rax,[sdl_textcursor_pos]
                        xor         rdx,rdx
                        mov         rcx,[sdl_textscreen_width]
                        div         rcx ; divide by line width
                        inc         rax ; next line
                        mul         rcx ; multiply with line width

                        cmp         rax,[sdl_textscreen_size]
                        jb          .notbeyondscreen

                        sub         rax,rcx ; cursor up one line
                        mov         [sdl_textcursor_pos],rax
                        call        sdl_scrollup
                        jmp         .end

.notbeyondscreen        mov         [sdl_textcursor_pos],rax

.end                    leave
                        ret

                        ; rdi - code point
sdl_outputcp            enter       0,0

                        ; ignore code points outside lowest bank (for now)
                        cmp         rdi,256
                        jae         .end

                        ; output attribute byte followed by character byte
                        ; to the screen buffer at the current text cursor pos.
                        mov         rcx,rdi
                        lea         rdi,[sdl_screenbuf]
                        mov         rax,[sdl_textcursor_pos]
                        mov         rdx,screencell_size
                        mul         rdx
                        add         rdi,rax
                        mov         rax,[sdl_text_attribute]
                        cld
                        stosb
                        mov         rax,rcx
                        stosb
                        inc         qword [sdl_textcursor_pos]

                        ; check if cursor advanced beyond screen
                        mov         rax,[sdl_textscreen_size]
                        cmp         [sdl_textcursor_pos],rax
                        jb          .end

                        mov         rax,[sdl_textscreen_width]
                        sub         [sdl_textcursor_pos],rax

                        call        sdl_scrollup

.end                    leave
                        ret

sdl_scrollup            enter       0,0

                        ; copy lines to previous line, top to bottom
                        lea         rdi,[sdl_screenbuf]
                        mov         rdx,[sdl_textscreen_width]
                        lea         rsi,[rdi+rdx*2]
                        mov         rcx,[sdl_textscreen_size]
                        sub         rcx,rdx
                        shr         rcx,2   ; /4, 1 qword = 4 cells
                        cld
                        rep         movsq
                        ; rdi will point to the line at the bottom of the screen

                        ; clear line at the bottom of the screen
                        mov         rax,[sdl_text_attribute]
                        ; rax - 00aa
                        mov         rdx,rax
                        shl         rdx,16
                        or          rax,rdx
                        ; rax - 00aa 00aa
                        mov         rdx,rax
                        shl         rdx,32
                        or          rax,rdx
                        ; rax - 00aa 00aa 00aa 00aa
                        mov         rcx,[sdl_textscreen_width]
                        shr         rcx,2   ; /4
                        cld
                        rep         stosq
                        ; in memory: aa 00 aa 00 ...

                        leave
                        ret

sdl_scrolldown          enter       0,0

                        ; copy lines from previous line, bottom to top
                        lea         rax,[sdl_screenbuf]
                        mov         rdx,[sdl_textscreen_width]
                        mov         rcx,[sdl_textscreen_size]
                        lea         rdi,[rax+rcx*2-8]
                        sub         rcx,rdx
                        lea         rsi,[rax+rcx*2-8]
                        shr         rcx,2   ; /4, 1 qword = 4 cells
                        std
                        rep         movsq
                        ; rdi will point to the end of line at the top of
                        ; the screen

                        ; clear line at the top of the screen
                        mov         rax,[sdl_text_attribute]
                        ; rax - 00aa
                        mov         rdx,rax
                        shl         rdx,16
                        or          rax,rdx
                        ; rax - 00aa 00aa
                        mov         rdx,rax
                        shl         rdx,32
                        or          rax,rdx
                        ; rax - 00aa 00aa 00aa 00aa
                        mov         rcx,[sdl_textscreen_width]
                        shr         rcx,2   ; /4
                        rep         stosq
                        ; in memory: aa 00 aa 00 ...

                        cld
                        leave
                        ret


                        ; CLIENT API
                        ; rdi - buffer
                        ; rsi - bufsiz
                        ; [rbp-0x18] - start cursor position
sdl_readln              enter       0x20,0
                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi
                        mov         rax,[sdl_textcursor_pos]
                        mov         [rbp-0x18],rax
                        mov         byte [rdi],0

                        mov         qword [sdl_want_input],1

.waitinput              cmp         qword [sdl_worker_terminated],0
                        jne         .workerquit

                        call        sdl_waitepoll

                        mov         rdx,rax
                        and         rdx,SDL_WEP_SIGNALLED
                        jnz         .signalled

                        mov         rdx,rax
                        and         rdx,SDL_WEP_ERROR
                        jnz         .error

                        mov         rdx,rax
                        and         rdx,SDL_WEP_WORKERDOWN
                        jnz         .workerquit

                        mov         rdx,rax
                        and         rdx,SDL_WEP_SPECIALKEY
                        ;jz          .notspecialkey

.notspecialkey          mov         rdx,rax
                        and         rdx,SDL_WEP_REGULARKEY
                        jz          .notregularkey

                        lea         rdi,[sdl_kbd_input]
                        mov         rsi,sdl_kbd_input_size
                        call        sdl_kbdgetbuf

                        test        rax,rax
                        jz          .skipregkey

                        lea         rdi,[sdl_kbdprinttest]
                        mov         rsi,rax
                        mov         rdx,rax
                        lea         rcx,[sdl_kbd_input]
                        xor         al,al
                        call        sdl_printf

.skipregkey:

.notregularkey          jmp         .waitinput

.signalled:
.error:
.workerquit:
.gotreturn              mov         qword [sdl_want_input],0

                        leave
                        ret

                        ; CLIENT API
                        ; rdi - bits 8..15: bg col, bits 0..7: fg col
sdl_color               enter       0,0
                        mov         rax,rdi
                        and         rax,0x0700
                        shr         ax,8
                        mov         al,[sdl_bg_inktable+rax]
                        shl         al,4
                        mov         rdx,rdi
                        and         rdx,0x0007
                        mov         dl,[sdl_fg_inktable+rdx]
                        or          rax,rdx
                        mov         [sdl_text_attribute],rax
                        leave
                        ret

                        ; CLIENT API
sdl_cls                 enter       0,0
                        mov         rax,[sdl_text_attribute]
                        ; rax - 00aa
                        mov         rdx,rax
                        shl         rdx,16
                        or          rax,rdx
                        ; rax - 00aa 00aa
                        mov         rdx,rax
                        shl         rdx,32
                        or          rax,rdx
                        ; rax - 00aa 00aa 00aa 00aa
                        lea         rdi,[sdl_screenbuf]
                        mov         rcx,[sdl_screenbuf_size]
                        shr         rcx,2
                        cld
                        rep         stosq
                        ; in memory: aa 00 aa 00 ...
                        leave
                        ret

                        ; rdi - ink number
                        ; rsi - foreground color index
                        ; rdx - background color index
sdl_ink                 enter       0,0
                        and         rdi,7
                        and         rsi,15
                        mov         rcx,rsi
                        and         rdx,15
                        mov         [sdl_fg_inktable+rdi],cl
                        mov         [sdl_bg_inktable+rdi],dl
                        leave
                        ret

                        section     .bss

sdl_printbuf            resq        SDL_PRINTBUFSIZE/8
sdl_printbuf_size       equ         $-sdl_printbuf

sdl_kbd_input           resq        SDL_KBDINPBUFSIZE/8
sdl_kbd_input_size      equ         $-sdl_kbd_input

sdl_escseqbuf           resq        SDL_ESCSEQBUFSIZE/8
sdl_escseqbuf_size      equ         $-sdl_escseqbuf

sdl_numescparams        resb        1
sdl_escapeparams        resb        10
                        align       8,resb 1

                        section     .data

sdl_fg_inktable         db          0,1,2,3,4,5,6,7
sdl_bg_inktable         db          0,1,2,3,4,5,6,7
sdl_escseqbufpos        db          0
sdl_escseqflag          db          0
sdl_escseqtype          db          0
                        align       8,db 0

                        section     .rodata

sdl_worker_moniker      db          'SDL worker thread',0
sdl_initerr             db          '? SDL_Init failed: %s',10,0
sdl_thrcrterr           db          '? SDL_CreateThread failed: %s',10,0
sdl_thrreperr           db          '? SDL worker failed',10,0
sdl_kbdprinttest        db          '%-*.*s',0


                        align       8,db 0
