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

                        %include    "sdlconshr.inc"

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

                        section     .text

                        extern      epoll_create1,perror,sdl_epollhnd,close
                        extern      exit,atexit,eventfd,epoll_ctl

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
                        mov         qword [rcx+ee_data],0
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

                        section     .bss

sdl_epollhnd            resd        1
sdl_first_event:
sdl_special_keypress    resd        1
sdl_regular_keypress    resd        1
sdl_worker_exiting      resd        1
sdl_last_event          resq        1
sdl_epoll_evbuf         resb        epollevt_size * SDL_EVTCNT
                        align       8,resb 1

                        section     .rodata

sdl_epollcrtpfx         db          '? epoll_create1(2)',0
sdl_evtcrtpfx           db          '? eventfd(2)',0
sdl_closeerrpfx         db          '? close(2)',0
sdl_epollctlpfx         db          '? epoll_ctl(2)',0