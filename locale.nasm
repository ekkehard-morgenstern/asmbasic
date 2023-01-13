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

                        global      init_locale
                        extern      getenv,setlocale

LC_ALL                  equ         6

init_locale             enter       0,0

                        lea         rdi,[langname]
                        call        getenv
                        or          rax,rax
                        jz          .nolang

                        ; LANG is set to something: use as locale
                        mov         [locid],rax
                        mov         rsi,rax
                        mov         rdi,LC_ALL
                        call        setlocale
                        or          rax,rax
                        jz          .nolang

.end                    leave
                        ret

                        ; attempt   "" locale
.nolang                 lea         rsi,[langnull]
                        mov         [locid],rsi
                        mov         rdi,LC_ALL
                        call        setlocale
                        or          rax,rax
                        jnz         .end

                        ; attempt "C" locale, ignore result
                        lea         rsi,[langc]
                        mov         [locid],rsi
                        mov         rdi,LC_ALL
                        call        setlocale
                        jmp         .end

                        section     .rodata

langname                db          'LANG',0
langc                   db          'C'
langnull                db          0

                        align       8,db 0

                        section     .bss

locid                   resq        1
