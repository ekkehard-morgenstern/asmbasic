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
SDL_SCREENWIDTH         equ         640
SDL_SCREENHEIGHT        equ         300

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
                        extern      SDL_CreateRenderer,SDL_DestroyRenderer
                        extern      SDL_RenderClear,SDL_RenderPresent
                        extern      SDL_PollEvent,strlen
                        extern      SDL_StartTextInput,SDL_StopTextInput
                        extern      SDL_SetRenderDrawColor,SDL_SetHint
                        extern      SDL_RenderSetLogicalSize,SDL_CreateTexture
                        extern      SDL_DestroyTexture,SDL_RenderCopy
                        extern      SDL_UpdateTexture

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

                        mov         rax,0x888888ff
                        mov         [sdl_background_rgba],rax

                        lea         rdi,[sdl_windowtitle]
                        mov         rsi,0x1FFF0000 ; SDL_WINDOWPOS_UNDEFINED
                        mov         rdx,rsi
                        xor         rcx,rcx
                        mov         r8,rcx
                        ; SDL_WINDOW_FULLSCREEN_DESKTOP
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

                        mov         rdi,rax
                        mov         rsi,-1
                        ; SDL_RENDERER_ACCELERATED + SDL_RENDERER_PRESENTVSYNC
                        mov         rdx,6
                        call        SDL_CreateRenderer
                        test        rax,rax
                        jnz         .renderer_ok

                        call        SDL_GetError
                        mov         rdi,[stderr]
                        lea         rsi,[sdl_crtrnderr]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf

                        mov         rdi,[sdl_window]
                        call        SDL_DestroyWindow
                        jmp         .init_failed

.renderer_ok            mov         [sdl_renderer],rax

                        ; user linear upscaling
                        lea         rdi,[sdl_rndscalqual]
                        lea         rsi,[sdl_linear]
                        call        SDL_SetHint

                        ; set logical canvas size
                        mov         rdi,[sdl_renderer]
                        mov         rsi,SDL_SCREENWIDTH
                        mov         rdx,SDL_SCREENHEIGHT
                        call        SDL_RenderSetLogicalSize

                        ; create texture
                        mov         rdi,[sdl_renderer]
                        ; 6, 3, 6, 32, 4
                        ;  0001 0110  0011 0110  0010 0000  0000 0100
                        ;   1    6      3   6     2    0     0    4
                        mov         rsi,0x16362004 ; SDL_PIXELFORMAT_ARGB8888
                        mov         rdx,1   ; SDL_TEXTUREACCESS_STREAMING
                        mov         rcx,SDL_SCREENWIDTH
                        mov         r8,SDL_SCREENHEIGHT
                        call        SDL_CreateTexture
                        test        rax,rax
                        jnz         .texture_ok

                        call        SDL_GetError
                        mov         rdi,[stderr]
                        lea         rsi,[sdl_crttexerr]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf

                        mov         rdi,[sdl_renderer]
                        call        SDL_DestroyRenderer
                        mov         rdi,[sdl_window]
                        call        SDL_DestroyWindow
                        jmp         .init_failed

.texture_ok             mov         [sdl_texture],rax

                        ; init complete
                        mov         qword [sdl_init_ok],1

                        ; MAIN LOOP
.mainloop               mov         rax,[sdl_worker_doquit]
                        test        rax,rax
                        jnz         .endmain

                        mov         rax,[sdl_want_input]
                        cmp         rax,[sdl_have_input]
                        je          .eventloop

                        mov         [sdl_have_input],rax
                        cmp         rax,1
                        je          .inputon

.inputoff               call        SDL_StopTextInput
                        jmp         .eventloop

.inputon                call        SDL_StartTextInput

                        ; HANDLE INPUT EVENTS
.eventloop              lea         rdi,[sdl_eventbuf]
                        call        SDL_PollEvent
                        cmp         eax,0
                        je          .render

                        lea         rax,[sdl_eventbuf]
                        cmp         dword [rax],0x0100  ; SDL_QUIT
                        jne         .notquit

                        mov         qword [sdl_worker_doquit],1
                        jmp         .eventloop

.notquit                cmp         dword [rax],0x0300  ; SDL_KEYDOWN
                        jne         .notkeydown

                        xor         rdi,rdi
                        mov         edi,dword [rax+20]  ; kev.keysym.sym
                        call        sdl_specialkey
                        jmp         .eventloop

.notkeydown             cmp         dword [rax],0x0303  ; SDL_TEXTINPUT
                        jne         .nottextinput

                        lea         rdi,[rax+12]
                        call        sdl_enterinput
                        jmp         .eventloop

.nottextinput           cmp         dword [rax],0x0302  ; SDL_TEXTEDITING
                        jne         .nottextediting

                        jmp         .eventloop

.nottextediting         jmp         .eventloop

                        ; RENDER
.render:

                        ; update texture
                        mov         rdi,[sdl_texture]
                        xor         rsi,rsi
                        lea         rdx,[sdl_screenmem]
                        mov         rcx,SDL_SCREENWIDTH*4
                        call        SDL_UpdateTexture

                        ; clear screen
                        mov         rax,[sdl_background_rgba]
                        mov         rdi,[sdl_renderer]
                        rol         eax,8
                        movzx       rsi,al      ; r
                        rol         eax,8
                        movzx       rdx,al      ; g
                        rol         eax,8
                        movzx       rcx,al      ; b
                        rol         eax,8
                        movzx       r8,al       ; a
                        call        SDL_SetRenderDrawColor
                        mov         rdi,[sdl_renderer]
                        call        SDL_RenderClear

                        ; paint texture
                        mov         rdi,[sdl_renderer]
                        mov         rsi,[sdl_texture]
                        xor         rdx,rdx
                        xor         rcx,rcx
                        call        SDL_RenderCopy

                        ; present screen
                        mov         rdi,[sdl_renderer]
                        call        SDL_RenderPresent

                        jmp         .mainloop

.endmain                mov         rdi,[sdl_texture]
                        call        SDL_DestroyTexture
                        mov         rdi,[sdl_renderer]
                        call        SDL_DestroyRenderer
                        mov         rdi,[sdl_window]
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

                        ; special keys
                        ; rdi - keyboard symbol from SDL
sdl_specialkey          enter       0,0

                        cmp         rdi,0x1b    ; ESC
                        je          .escape
                        cmp         rdi,0x08    ; BACKSPACE
                        je          .backspace
                        cmp         rdi,0x0d    ; RETURN
                        je          .return

.end                    leave
                        ret

.escape                 mov         qword [sdl_worker_doquit],1
                        jmp         .end

.backspace              jmp         .end

.return                 jmp         .end

                        ; enter a Unicode character
                        ; rdi - NUL-terminated string in UTF-8 format
sdl_enterinput          enter       0x10,0
                        mov         [rbp-0x08],r12
                        mov         r12,rdi
                        call        strlen
                        mov         rcx,rax


                        mov         r12,[rbp-0x08]
                        leave
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
sdl_renderer            resq        1
sdl_want_input          resq        1
sdl_have_input          resq        1
sdl_background_rgba     resq        1
sdl_texture             resq        1

sdl_eventbuf            resq        256/8

sdl_textscreen_width    resq        1
sdl_textscreen_height   resq        1
sdl_textscreen_size     resq        1

sdl_screenbuf           resq        SDL_SCREENBUFSIZE/8
sdl_screenbuf_size      equ         $-sdl_screenbuf

sdl_workbuf             resq        SDL_SCREENBUFSIZE/8
sdl_workbuf_size        equ         $-sdl_workbuf

sdl_screenmem           resq        ((SDL_SCREENWIDTH*4)*SDL_SCREENHEIGHT)/8
sdl_screenmem_size      equ         $-sdl_screenmem

                        section     .rodata

sdl_initerr             db          '? SDL_Init failed: %s',10,0
sdl_worker_moniker      db          'SDL worker thread',0
sdl_thrcrterr           db          '? SDL_CreateThread failed: %s',10,0
sdl_windowtitle         db          'AsmBASIC',0
sdl_thrreperr           db          '? SDL worker failed',10,0
sdl_crtwnderr           db          '? SDL_CreateWindow failed: %s',10,0
sdl_crtrnderr           db          '? SDL_CreateRenderer failed: %s',10,0
sdl_rndscalqual         db          'SDL_RENDER_SCALE_QUALITY',0
sdl_linear              db          'linear',0
sdl_crttexerr           db          '? SDL_CreateTexture failed: %s',10,0

                        align       8,db 0
