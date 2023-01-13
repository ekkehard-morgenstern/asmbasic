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

; page descriptors
                        struc       pagedesc
                            pd_location:    resq    1
                            pd_numwords:    resq    1
                            pd_usedwords:   resq    1
                        endstruc

                        section     .text

                        extern      xalloc

;                             global  main

; main                    enter       0,0
;                         call        oom
;                         xor         rax,rax
;                         leave
;                         ret

; page descriptors

                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - requested size, in words
                        ;     [rbp-0x18] - RBX backup
init_page               enter       0x20,0
                        mov         [rbp-0x08],rdi
                        shl         rsi,3   ; *8
                        mov         [rbp-0x10],rsi
                        mov         [rbp-0x18],rbx
                        mov         rdi,rsi
                        call        xalloc
                        mov         rbx,[rbp-0x08]
                        mov         rdx,[rbp-0x10]
                        mov         [rbx+pd_location],rax
                        mov         [rbx+pd_numwords],rdx
                        xor         rax,rax
                        mov         [rbx+pd_usedwords],rax
                        mov         rbx,[rbp-0x18]
                        leave
                        ret

; regular data section

                        section     .data

; block-structured storage section

                        section     .bss

space1                  resq        pagedesc_size/8
space2                  resq        pagedesc_size/8
hndspc                  resq        pagedesc_size/8
