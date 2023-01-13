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

SDL_EVTCNT              equ         3

                        ; cf. epoll_ctl(2)
                        struc       epollevt
                            ee_flags:   resd    1
                            ee_data:    resq    1
                        endstruc

; cf. /usr/include/sys/epoll.h
EPOLL_CTL_ADD           equ         1
EPOLL_CTL_DEL           equ         2
EPOLLIN                 equ         1

; cf. /usr/include/asm-generic/errno-base.h
EINTR                   equ         4

                        section     .text

                        extern      epoll_create1,perror,sdl_epollhnd,close
                        extern      exit,atexit,eventfd,epoll_ctl,epoll_wait
                        extern      __errno_location,read

                        global      sdl_initepoll


sdl_initepoll           enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13

                        ; create EPOLL instance

                        xor         rdi,rdi
                        call        epoll_create1

                        cmp         eax,-1
                        jne         .epollok

                        lea         rdi,[sdl_epollcrtpfx]
.errorexit              call        perror

                        mov         rdi,1
                        call        exit

                        jmp         .end

.epollok                mov         [sdl_epollhnd],eax
                        lea         rbx,[sdl_first_event]
                        mov         r12,SDL_EVTCNT
                        lea         r13,[sdl_epoll_evbuf]

.nextevt                xor         rdi,rdi
                        xor         rsi,rsi
                        call        eventfd

                        cmp         eax,-1
                        jne         .evtok

                        lea         rdi,[sdl_evtcrtpfx]
                        jmp         .errorexit

.evtok                  mov         [rbx],eax

                        movsx       rdi,dword [sdl_epollhnd]
                        mov         rsi,EPOLL_CTL_ADD
                        movsx       rdx,eax
                        mov         rcx,r13
                        mov         dword [rcx+ee_flags],EPOLLIN
                        mov         [rcx+ee_data],rdx
                        call        epoll_ctl

                        cmp         eax,-1
                        jne         .addok

                        lea         rdi,[sdl_epollctlpfx]
                        jmp         .errorexit

.addok                  add         r13,epollevt_size
                        add         rbx,4
                        dec         r12
                        jnz         .nextevt

                        lea         rdi,[sdl_cleanupepoll]
                        call        atexit

.end                    mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

sdl_cleanupepoll        enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12

                        lea         rbx,[sdl_last_event]
                        mov         r12,SDL_EVTCNT+1

.closeloop              sub         rbx,4

                        cmp         rbx,sdl_epollhnd
                        je          .skipdel

                        movsx       rdi,dword [sdl_epollhnd]
                        mov         rsi,EPOLL_CTL_DEL
                        movsx       rdx,dword [rbx]
                        xor         rcx,rcx
                        call        epoll_ctl

                        cmp         eax,-1
                        jne         .delok

                        lea         rdi,[sdl_epollctlpfx]
                        call        perror

.delok:
.skipdel                movsx       rdi,dword [rbx]
                        call        close

                        cmp         eax,-1
                        jne         .closeok

                        lea         rdi,[sdl_closeerrpfx]
                        call        perror

.closeok                dec         r12
                        jnz         .closeloop

                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

sdl_waitepoll           enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13

                        lea         rbx,[sdl_first_event]
                        xor         r13,r13

                        movsx       rdi,dword [sdl_epollhnd]
                        lea         rsi,[sdl_epoll_result]
                        mov         rdx,SDL_EVTCNT
                        mov         rcx,20  ; wait for 20 ms = 1/50 sec max
                        call        epoll_wait

                        cmp         eax,-1
                        jne         .noterr

                        call        __errno_location
                        mov         rax,[rax]
                        cmp         rax,EINTR
                        je          .eintr

                        lea         rdi,[sdl_epollwaitpfx]
                        call        perror

                        or          r13,SDL_WEP_ERROR
                        jmp         .end

.eintr                  or          r13,SDL_WEP_SIGNALLED
                        jmp         .end

.noterr                 cmp         eax,0
                        jnz         .notzero

                        or          r13,SDL_WEP_TIMEDOUT
                        jmp         .end

.notzero                movsx       r12,eax

.evtloop                mov         eax,[rbx+ee_flags]
                        and         eax,EPOLLIN
                        jz          .nextevt

                        mov         rax,[rbx+ee_data]

                        cmp         eax,[sdl_regular_keypress]
                        jne         .notregkey

                        or          r13,SDL_WEP_REGULARKEY
                        jmp         .readevt

.notregkey              cmp         eax,[sdl_special_keypress]
                        jne         .notspecial

                        or          r13,SDL_WEP_SPECIALKEY
                        jmp         .readevt

.notspecial             cmp         eax,[sdl_worker_exiting]
                        jne         .notexiting

                        or          r13,SDL_WEP_WORKERDOWN

                        ; dummy read from event object
.readevt                movsx       rdi,eax
                        lea         rsi,[rbp-0x20]
                        mov         rdx,8
                        call        read

.notexiting:
.nextevt                add         rbx,epollevt_size
                        dec         r12
                        jnz         .evtloop

.end                    mov         rax,r13
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

                        section     .bss

sdl_epollhnd            resd        1
sdl_first_event:
sdl_special_keypress    resd        1
sdl_regular_keypress    resd        1
sdl_worker_exiting      resd        1
sdl_last_event          resq        1
sdl_epoll_evbuf         resd        ( epollevt_size * SDL_EVTCNT ) / 4
sdl_epoll_result        resd        ( epollevt_size * SDL_EVTCNT ) / 4
                        align       8,resb 1

                        section     .rodata

sdl_epollcrtpfx         db          '? epoll_create1(2)',0
sdl_evtcrtpfx           db          '? eventfd(2)',0
sdl_closeerrpfx         db          '? close(2)',0
sdl_epollctlpfx         db          '? epoll_ctl(2)',0
sdl_epollwaitpfx        db          '? epoll_wait(2)',0