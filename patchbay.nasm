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
                        global      pb_initstdio, pb_initsdl
                        extern      std_printf,std_readln,std_color,std_cls
                        extern      sdl_printf,sdl_readln,sdl_color,sdl_cls
                        extern      sdl_launch

pb_initstdio            enter       0,0
                        lea         rax,[std_printf]
                        mov         [pb_putfmt],rax
                        lea         rax,[std_readln]
                        mov         [pb_readln],rax
                        lea         rax,[std_color]
                        mov         [pb_color],rax
                        lea         rax,[std_cls]
                        mov         [pb_cls],rax
                        leave
                        ret

pb_initsdl              enter       0,0
                        lea         rax,[sdl_printf]
                        mov         [pb_putfmt],rax
                        lea         rax,[sdl_readln]
                        mov         [pb_readln],rax
                        lea         rax,[sdl_color]
                        mov         [pb_color],rax
                        lea         rax,[sdl_cls]
                        mov         [pb_cls],rax
                        call        sdl_launch
                        leave
                        ret

                        section     .bss

                        global      pb_putfmt,pb_readln,pb_color,pb_cls

pb_putfmt               resq        1
pb_readln               resq        1
pb_color                resq        1
pb_cls                  resq        1