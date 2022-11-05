;   AsmBASIC - a BASIC interpreter written in assembly language
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

SDL_PRINTBUFSIZE        equ         16384
SDL_SCREENBUFSIZE       equ         16384

                        struc       screencell
                            sc_col: resb    1   ; bits 4..7: bgpen, 0..3: fgpen
                            sc_chr: resb    1
                        endstruc

                        section     .text
                        global      sdl_launch
                        global      sdl_printf,sdl_readln,sdl_color,sdl_cls
                        extern      snprintf,atexit,exit,fprintf,stderr
                        extern      SDL_SetMainReady,SDL_Init,SDL_GetError
                        extern      SDL_Quit,SDL_CreateThread,SDL_WaitThread
                        extern      SDL_Delay,SDL_CreateWindow,SDL_DestroyWindow

sdl_launch              enter       0,0

                        ; clear out screen and work buffers
                        lea         rdi,[sdl_screenbuf]
                        mov         rcx,sdl_screenbuf_size/8
                        xor         rax,rax
                        cld
                        rep         stosq
                        lea         rdi,[sdl_workbuf]
                        mov         rcx,sdl_screenbuf_size/8
                        rep         stosq

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

                        ; WORKER THREAD
                        ; - must terminate upon sdl_worker_doquit
sdl_worker              enter       0,0

                        lea         rdi,[sdl_windowtitle]
                        mov         rsi,0x1FFF0000
                        mov         rdx,rsi
                        xor         rcx,rcx
                        mov         r8,rcx
                        mov         r9,0x00001001
                        call        SDL_CreateWindow
                        test        rax,rax
                        jnz         .window_ok

                        call        SDL_GetError
                        mov         rdi,[stderr]
                        lea         rsi,[sdl_crtwnderr]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf

.init_failed            mov         qword [sdl_init_ok],-1
                        jmp         .sleeploop

.window_ok              mov         [sdl_window],rax

                        ; init complete
                        mov         qword [sdl_init_ok],1

                        ; MAIN LOOP
.mainloop               mov         rax,[sdl_worker_doquit]
                        test        rax,rax
                        jnz         .endmain

                        mov         rdi,50
                        call        SDL_Delay
                        jmp         .mainloop

.endmain                mov         rdi,[sdl_window]
                        call        SDL_DestroyWindow
                        jmp         .end

.sleeploop              mov         rax,[sdl_worker_doquit]
                        test        rax,rax
                        jnz         .end

                        mov         rdi,50
                        call        SDL_Delay
                        jmp         .sleeploop

.end                    leave
                        ret

                        ; CLIENT API
                        ; rdi - fmt
                        ; ... args
                        ; al - number of (floating-point) arguments in
                        ;      vector registers
sdl_printf              enter       0,0

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

                        leave
                        ret

                        ; CLIENT API
                        ; rdi - buffer
                        ; rsi - bufsiz
sdl_readln              enter       0,0
                        mov         byte [rdi],0
                        leave
                        ret

                        ; CLIENT API
                        ; rdi - bits 8..15: bg col, bits 0..7: fg col
sdl_color               enter       0,0
                        leave
                        ret

                        ; CLIENT API
sdl_cls                 enter       0,0
                        leave
                        ret

                        section     .bss

sdl_printbuf            resq        SDL_PRINTBUFSIZE/8
sdl_printbuf_size       equ         $-sdl_printbuf

sdl_worker_handle       resq        1
sdl_worker_result       resq        1
sdl_worker_doquit       resq        1

sdl_init_ok             resq        1
sdl_window              resq        1

sdl_textscreen_width    resq        1
sdl_textscreen_height   resq        1
sdl_textscreen_size     resq        1

sdl_screenbuf           resq        SDL_SCREENBUFSIZE/8
sdl_screenbuf_size      equ         $-sdl_screenbuf

sdl_workbuf             resq        SDL_SCREENBUFSIZE/8
sdl_workbuf_size        equ         $-sdl_workbuf

                        section     .rodata

sdl_initerr             db          '? SDL_Init failed: %s',10,0
sdl_worker_moniker      db          'SDL worker thread',0
sdl_thrcrterr           db          '? SDL_CreateThread failed: %s',10,0
sdl_windowtitle         db          'AsmBASIC',0
sdl_thrreperr           db          '? SDL worker failed',10,0
sdl_crtwnderr           db          '? SDL_CreateWindow failed: %s',10,0

                        align       8,db 0
