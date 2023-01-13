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

                        section     .text

                        global      sdl_launch
                        global      sdl_printf,sdl_readln,sdl_color,sdl_cls
                        extern      chkkernver,sdl_worker
                        extern      snprintf,atexit,exit,fprintf,stderr,strlen
                        extern      SDL_SetMainReady,SDL_Init,SDL_GetError
                        extern      SDL_Quit,SDL_CreateThread,SDL_WaitThread
                        extern      SDL_Delay, ucinsavectx,ucinloadctx
                        extern      sdl_screenbuf,sdl_screenbuf_size
                        extern      sdl_text_attribute,sdl_return_pressed
                        extern      sdl_have_input,sdl_want_input
                        extern      sdl_worker_terminated,sdl_return_pressed
                        extern      sdl_workbuf,sdl_workbuf_size
                        extern      sdl_textscreen_width,sdl_textscreen_height
                        extern      sdl_textscreen_size,sdl_textcursor_pos
                        extern      sdl_worker,sdl_worker_doquit,sdl_init_ok
                        extern      sdl_worker_handle,sdl_worker_result
                        extern      ucinsavectx,ucinloadctx
                        extern      uclineininit,ucgetcp,sdl_initepoll

sdl_launch              enter       0,0

                        ; check kernel version >= 2.6.37 b/c of epoll API
                        call        chkkernver

                        ; initialize epoll stuff
                        call        sdl_initepoll

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

.wait_feedback          cmp         qword [sdl_init_ok],0
                        jne         .thread_feedback
                        mov         rdi,50
                        call        SDL_Delay
                        jmp         .wait_feedback

.thread_feedback        cmp         qword [sdl_init_ok],-1
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

                        ; check for line feed character
                        cmp         rax,10
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

                        ; write character at the current text cursor position
.notcarriagereturn      mov         rdi,rax
                        call        sdl_outputcp
                        jmp         .nextchar

                        ; restore UTF-8 decoder state
.end                    lea         rdi,[rbp-0x30]
                        call        ucinloadctx

                        leave
                        ret

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

                        ; CLIENT API
                        ; rdi - buffer
                        ; rsi - bufsiz
sdl_readln              enter       0,0
                        mov         byte [rdi],0

                        mov         qword [sdl_return_pressed],0
                        mov         qword [sdl_have_input],0
                        mov         qword [sdl_want_input],1

.waitinput              cmp         qword [sdl_worker_terminated],0
                        jne         .workerquit

                        cmp         qword [sdl_return_pressed],0
                        jne         .gotreturn

                        mov         rdi,50
                        call        SDL_Delay
                        jmp         .waitinput

.workerquit:
.gotreturn              mov         qword [sdl_want_input],0

                        leave
                        ret

                        ; CLIENT API
                        ; rdi - bits 8..15: bg col, bits 0..7: fg col
sdl_color               enter       0,0
                        mov         rax,rdi
                        and         rax,0x0f00
                        shr         rax,4
                        mov         rdx,rdi
                        and         rdx,0x000f
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

                        section     .bss

sdl_printbuf            resq        SDL_PRINTBUFSIZE/8
sdl_printbuf_size       equ         $-sdl_printbuf

                        section     .rodata

sdl_worker_moniker      db          'SDL worker thread',0
sdl_initerr             db          '? SDL_Init failed: %s',10,0
sdl_thrcrterr           db          '? SDL_CreateThread failed: %s',10,0
sdl_thrreperr           db          '? SDL worker failed',10,0

                        align       8,db 0
