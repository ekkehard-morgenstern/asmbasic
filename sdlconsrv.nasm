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

                        section     .text

                        global      sdl_worker

                        extern      sdl_background_rgba,sdl_windowtitle
                        extern      sdl_init_ok,sdl_worker_doquit
                        extern      sdl_worker_terminated
                        extern      sdl_ticks
                        extern      sdl_textcursor_visible,sdl_text_attribute
                        extern      sdl_want_input,sdl_have_input,sdl_screenbuf
                        extern      sdl_workbuf,sdl_textcursor_pos
                        extern      sdl_textscreen_width,sdl_textscreen_height
                        extern      sdl_textbgpalette,sdl_textfgpalette
                        extern      fprintf,stderr,printf
                        extern      SDL_Init,SDL_GetError
                        extern      SDL_Quit,SDL_CreateThread,SDL_WaitThread
                        extern      SDL_Delay,SDL_CreateWindow,SDL_DestroyWindow
                        extern      SDL_CreateRenderer,SDL_DestroyRenderer
                        extern      SDL_RenderClear,SDL_RenderPresent
                        extern      SDL_PollEvent,strlen,font8x12_1
                        extern      SDL_StartTextInput,SDL_StopTextInput
                        extern      SDL_SetRenderDrawColor,SDL_SetHint
                        extern      SDL_RenderSetLogicalSize,SDL_CreateTexture
                        extern      SDL_DestroyTexture,SDL_RenderCopy
                        extern      SDL_UpdateTexture,SDL_SetTextureBlendMode
                        extern      SDL_GetTicks
                        extern      uclineininit,ucgetcp,sdl_raiseepoll
                        extern      sdl_kbdputbuf

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
                        mov         rdi,SDL_WEP_WORKERINITDONE
                        call        sdl_raiseepoll
                        jmp         .end

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
                        mov         rdi,rax
                        mov         rsi,1       ; SDL_BLENDMODE_BLEND
                        call        SDL_SetTextureBlendMode

                        ; init complete
                        mov         qword [sdl_worker_terminated],0
                        mov         qword [sdl_want_input],0
                        mov         qword [sdl_have_input],0
                        mov         qword [sdl_init_ok],1

                        mov         rdi,SDL_WEP_WORKERINITDONE
                        call        sdl_raiseepoll

                        ; MAIN LOOP
.mainloop               mov         rax,[sdl_worker_doquit]
                        test        rax,rax
                        jnz         .endmain

                        call        SDL_GetTicks
                        mov         rdx,0xffffffff
                        and         rax,rdx
                        mov         [sdl_ticks],rax

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
                        ; render text screen
.render                 call        sdl_rendertextscreen

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

.end                    mov         qword [sdl_worker_terminated],1
                        mov         rdi,SDL_WEP_WORKERDOWN
                        call        sdl_raiseepoll
                        leave
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

.backspace              lea         rdi,[sdl_backspacekey]
                        call        sdl_enterinput
                        jmp         .end

.return                 lea         rdi,[sdl_returnkey]
                        call        sdl_enterinput
                        jmp         .end

                        ; enter a Unicode character
                        ; rdi - NUL-terminated string in UTF-8 format
sdl_enterinput          enter       0x10,0
                        mov         [rbp-0x08],r12

                        mov         r12,rdi
                        call        strlen

                        mov         rdi,r12
                        mov         rsi,rax
                        call        sdl_kbdputbuf

                        mov         rdi,SDL_WEP_REGULARKEY
                        call        sdl_raiseepoll

                        mov         r12,[rbp-0x08]
                        leave
                        ret

                        ; SERVER side text screen renderer
                        ; write text screen to screen memory
sdl_rendertextscreen    enter       0x30,0
                        mov         [rbp-0x08],r12
                        mov         [rbp-0x10],r13
                        mov         [rbp-0x18],r14
                        mov         [rbp-0x20],r15
                        mov         [rbp-0x28],rbx

                        ; copy screen buffer to work buffer
                        lea         rsi,[sdl_screenbuf]
                        lea         rdi,[sdl_workbuf]
                        mov         rcx,SDL_SCREENBUFSIZE/8
                        cld
                        rep         movsq

                        ; r10 - screen cell pointer
                        lea         r10,[sdl_workbuf]
                        ; r12 - character set
                        lea         r12,[font8x12_1]
                        ; rdi - screen memory
                        lea         rdi,[sdl_screenmem]
                        ; r13 - on-screen stride: next row
                        mov         r13,(SDL_SCREENWIDTH-8)*4
                        ; r14 - on-screen stride: next char
                        mov         r14,(SDL_SCREENWIDTH*12-8)*4
                        ; r15 - on-screen stride: next line
                        mov         r15,(SDL_SCREENWIDTH*11)*4

                        ; compute text cursor address (rbx)
                        mov         rax,[sdl_textcursor_pos]
                        mov         rdx,screencell_size
                        mul         rdx
                        add         rax,r10
                        mov         [rbp-0x30],rax

                        ; compute cursor visibility
                        mov         rcx,[sdl_want_input]
                        mov         rax,[sdl_ticks]
                        xor         rdx,rdx
                        mov         rbx,500
                        div         rbx
                        cmp         rdx,250
                        setae       al
                        movzx       rax,al
                        and         rcx,rax
                        mov         [sdl_textcursor_visible],rcx

                        ; r9 - remaining rows on text screen
                        ; r8 - remaining columns on text screen
                        mov         r9,[sdl_textscreen_height]
.nextrow                mov         r8,[sdl_textscreen_width]

                        ; get screen cell info
.nextcell               xor         rax,rax
                        mov         al,[r10+sc_col]
                        shr         al,4
                        mov         r11d,dword [sdl_textbgpalette + rax*4]
                        shl         r11,32
                        mov         al,[r10+sc_col]
                        and         al,15
                        xor         rcx,rcx
                        mov         ecx,dword [sdl_textfgpalette + rax*4]
                        or          r11,rcx
                        ; r11 - contains background color in upper 32 bits
                        ; r11 - contains foreground color in lower 32 bits
                        movzx       rax,byte [r10+sc_chr]
                        lea         rsi,[r12+rax*8]
                        lea         rsi,[rsi+rax*4]
                        ; rsi - character start address
                        ; bl  - text cursor xor mask
                        cmp         r10,[rbp-0x30]
                        sete        bl
                        and         bl,[sdl_textcursor_visible]
                        neg         bl
                        add         r10,screencell_size

                        ; transfer character lines
                        mov         ah,12
                        ; transfer character line
.charline               lodsb
                        mov         ch,8    ; bits per line
.charpixel              rol         al,1    ; get one bit
                        setnc       cl      ; select color
                        neg         cl
                        xor         cl,bl
                        and         cl,32
                        mov         rdx,r11
                        shr         rdx,cl
                        mov         dword [rdi],edx ; store
                        add         rdi,4   ; next pixel
                        dec         ch
                        jnz         .charpixel
                        add         rdi,r13 ; next row
                        dec         ah
                        jnz         .charline
                        sub         rdi,r14 ; next char

                        ; loop over cells
                        dec         r8
                        jnz         .nextcell
                        add         rdi,r15 ; next line

                        ; loop over lines
                        dec         r9
                        jnz         .nextrow

                        mov         rbx,[rbp-0x28]
                        mov         r15,[rbp-0x20]
                        mov         r14,[rbp-0x18]
                        mov         r13,[rbp-0x10]
                        mov         r12,[rbp-0x08]
                        leave
                        ret

                        section     .bss

sdl_window              resq        1
sdl_renderer            resq        1
sdl_texture             resq        1
sdl_eventbuf            resq        256/8

sdl_screenmem           resq        ((SDL_SCREENWIDTH*4)*SDL_SCREENHEIGHT)/8
sdl_screenmem_size_val  equ         $-sdl_screenmem

                        section     .data

sdl_screenmem_size      dq          sdl_screenmem_size_val

                        section     .rodata

sdl_windowtitle         db          'AsmBASIC',0
sdl_crtwnderr           db          '? SDL_CreateWindow failed: %s',10,0
sdl_crtrnderr           db          '? SDL_CreateRenderer failed: %s',10,0
sdl_rndscalqual         db          'SDL_RENDER_SCALE_QUALITY',0
sdl_linear              db          'linear',0
sdl_crttexerr           db          '? SDL_CreateTexture failed: %s',10,0
sdl_debugprtfmt         db          '<<%s>>',10,0
sdl_returnkey           db          10,0
sdl_backspacekey        db          8,0

                        align       8,db 0
