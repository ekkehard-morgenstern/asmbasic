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

LBUF_SIZE               equ         8192

                        cpu         x64
                        bits        64

                        section     .text

                        global      main
                        extern      init_locale
                        extern      init_tokenizer
                        extern      dump_tokenmap
                        extern      pb_initstdio,pb_readln,strlen
                        extern      tokenize,detokenize,tok_dumplinebuf
                        extern      tokenpad,tokenpadptr

main                    enter       0,0
                        call        pb_initstdio
                        call        init_locale
                        call        init_tokenizer
                        call        tokenizer_test
                        xor         rax,rax
                        leave
                        ret

getline                 enter       0,0
                        lea         rdi,[lbuf]
                        mov         rsi,lbuf_size
                        call        qword [pb_readln]
                        leave
                        ret

tokenizer_test          enter       0,0
.lineloop               call        getline
                        test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        call        strlen
                        cmp         byte [rdi+rax-1],0x0a
                        jne         .nolf
                        dec         rax
.nolf                   test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        mov         rsi,rax
                        call        tokenize
                        ; TEST: detokenize and output
                        lea         rdi,[tokenpad]
                        mov         rsi,[tokenpadptr]
                        sub         rsi,rdi
                        xor         rdx,rdx
                        call        detokenize
                        call        tok_dumplinebuf
                        jmp         .lineloop
.end                    leave
                        ret

                        section     .bss

lbuf                    resq        LBUF_SIZE/8
lbuf_size               equ         $-lbuf
