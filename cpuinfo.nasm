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

                        section     .text
                        global      chkcputype
                        extern      stderr,fprintf,exit

chkcputype              enter       0x10,0
                        mov         [rbp-0x08],rbx

                        xor         eax,eax
                        cpuid

                        ; eax contains max value for eax
                        cmp         eax,1
                        jae         .canquery

                        mov         rdi,[stderr]
                        lea         rsi,[eaxnull]
                        xor         al,al
                        call        fprintf

.fail                   mov         rdi,1
                        call        exit

.canquery               mov         eax,1
                        cpuid

                        and         edx,1
                        jnz         .fpuok

                        mov         rdi,[stderr]
                        lea         rsi,[noonchipfpu]
                        xor         al,al
                        call        fprintf

                        jmp         .fail

.fpuok                  mov         rbx,[rbp-0x08]
                        leave
                        ret

                        section     .rodata

eaxnull                 db          '? maximum query index for CPUID is 0',10,0
noonchipfpu             db          '? on-chip FPU not found',10,0

                        align       8,db 0
