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

                        section     .text

; memory allocation
;   using standard C library here to avoid handling Linux memory management
;   directly

                        extern      malloc,realloc,free
                        global      xalloc,xfree,xrealloc

                        ; rdi - requested size, in bytes

xalloc                  enter       0,0
                        or          rdi,rdi
                        jnz         .nonzero
                        inc         rdi
.nonzero                call        malloc
                        or          rax,rax
                        jnz         .ok
                        call        oom
.ok                     leave
                        ret

                        ; rdi - block to be freed

xfree                   enter       0,0
                        or          rdi,rdi
                        jz          .end
                        call        free
.end                    leave
                        ret

                        ; rdi - block to be reallocated
                        ; rsi - new size, in bytes

xrealloc                enter       0,0
                        or          rsi,rsi
                        jnz         .nonzero
                        inc         rsi
.nonzero                call        realloc
                        or          rax,rax
                        jnz         .ok
                        call        oom
.ok                     leave
                        ret

; error handling
;   using C library for stderr output and exit, since we have it anyway

                        extern      fprintf,stderr,exit

oom                     enter       0,0
                        mov         rdi,[stderr]
                        lea         rsi,[oommsg]
                        xor         al,al
                        call        fprintf
                        xor         rdi,rdi
                        inc         rdi
                        call        exit
                        leave
                        ret

; read-only data section

                        section     .rodata

oommsg                  db          "? out of memory",10,0
