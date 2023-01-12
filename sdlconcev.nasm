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

                        section     .text

                        extern      epoll_create1,perror,sdl_epollhnd,close
                        extern      exit,atexit

                        global      sdl_initepoll


sdl_initepoll           enter       0,0

                        ; create EPOLL instance

                        xor         rdi,rdi
                        call        epoll_create1

                        cmp         eax,-1
                        jne         .epollok

                        lea         rdi,[sdl_epollcrtpfx]
                        call        perror

                        mov         rdi,1
                        call        exit

                        jmp         .end

.epollok                mov         [sdl_epollhnd],eax

                        lea         rdi,[sdl_cleanupepoll]
                        call        atexit

.end                    leave
                        ret

sdl_cleanupepoll        enter       0,0

                        movsx       rdi,dword [sdl_epollhnd]
                        call        close

                        cmp         eax,-1
                        jne         .closeok

                        lea         rdi,[sdl_closeerrpfx]
                        call        perror

.closeok:
                        leave
                        ret

                        section     .bss

sdl_epollhnd            resd        1
                        resd        1

                        section     .rodata

sdl_epollcrtpfx         db          '? epoll_create1(2)',0
sdl_closeerrpfx         db          '? close(2)',0
