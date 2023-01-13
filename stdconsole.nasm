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
                        global      std_printf,std_readln,std_color,std_cls
                        extern      printf,fgets,stdin

                        ; rdi - fmt
                        ; ... args
                        ; al - number of (floating-point) arguments in
                        ;      vector registers
std_printf              jmp         printf


                        ; rdi - buffer
                        ; rsi - bufsiz
std_readln              enter       0,0
                        mov         byte [rdi],0
                        mov         rdx,[stdin]
                        call        fgets
                        leave
                        ret

                        ; rdi - bits 8..15: bg col, bits 0..7: fg col
std_color               enter       0,0
                        mov         rsi,rdi
                        and         rsi,0x0007
                        add         rsi,30
                        mov         rdx,rdi
                        and         rdx,0x0700
                        shr         rdx,8
                        add         rdx,40
                        lea         rdi,[color_fmt]
                        xor         al,al
                        call        printf
                        leave
                        ret

std_cls                 enter       0,0
                        lea         rdi,[cls_fmt]
                        xor         al,al
                        call        printf
                        leave
                        ret

                        section     .data

color_fmt               db          0x1b,'[%u;%um',0
cls_fmt                 db          0x1b,'[2J',0x1b,'[H',0

                        align       8,db 0
