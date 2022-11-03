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
                        global      pb_initstdio
                        extern      printf,fgets,stdin

pb_initstdio            enter       0,0
                        lea         rax,[printf]
                        mov         [pb_putfmt],rax
                        lea         rax,[readln]
                        mov         [pb_readln],rax
                        leave
                        ret

                        ; rdi - buffer
                        ; rsi - bufsiz
readln                  enter       0,0
                        mov         byte [rdi],0
                        mov         rdx,[stdin]
                        call        fgets
                        leave
                        ret

                        section     .bss

                        global      pb_putfmt,pb_readln

pb_putfmt               resq        1
pb_readln               resq        1
