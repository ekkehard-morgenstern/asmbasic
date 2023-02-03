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

                        %include    "syntree.inc"
                        %include    "cookedsyntree.inc"

                        section     .text

                        extern      syntree,xalloc,xfree,xrealloc
                        global      cooksyntree,delcookedsyntree
                        global      printcookedsyntree

                        ; create cooked syntax tree from raw syntax tree
                        ; rdi - raw syntax tree node (stn)
                        ; output:
                        ; rax - cooked syntax tree node
crt_csn                 enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14

                        test        rdi,rdi
                        jz          .isnull
                        mov         rbx,rdi

                        ; allocate cooked node
                        mov         rdi,cookedsyntaxnode_size
                        call        xalloc
                        mov         r12,rax

                        ; zero out cooked node fields
                        cld
                        mov         rdi,rax
                        xor         rax,rax
                        mov         rcx,cookedsyntaxnode_size/8
                        rep         stosq

                        ; check stn type
                        mov         rdi,[rbx+stn_match]
                        mov         al,[rdi+impn_nodeClass]
                        cmp         al,NC_TERMINAL
                        je          .terminal

                        ; all non-terminal nodes are simply there
                        ; to hold their sub branches, except those who have
                        ; only NC_TERMINAL types as children; those must be
                        ; analyzed to determine the type of element they
                        ; represent

                        mov         rax,[rbx+stn_nargs]
                        test        rax,rax
                        jz          .discard ; useless node ->

                        mov         rcx,rax
                        mov         rsi,[rbx+stn_args]
                        cld
.testbr                 lodsq
                        mov         rdx,[rax+stn_match]
                        mov         r8b,[rdx+impn_nodeClass]
                        cmp         r8b,NC_TERMINAL
                        jne         .subbranches  ; only need branches ->
                        loop        .testbr

                        ; they are all NC_TERMINALs
                        ; look at the first one to see what it is
                        mov         rsi,[rbx+stn_args]
                        mov         rsi,[rsi]
                        mov         rsi,[rsi+stn_token]
                        mov         al,[rsi]
                        cmp         al,S_NUMBER
                        je          .number
                        cmp         al,S_STRLIT
                        je          .strlit
                        cmp         al,S_IDENT
                        je          .ident
                        ; neither
                        jmp         .discard

                        ; number starts with 01 BASE
.number                 mov         [r12+csn_type],al
                        mov         al,[rsi+1]
                        mov         [r12+csn_numbase],al
                        ; second branch has data
                        mov         rsi,[rbx+stn_args]
                        mov         rsi,[rsi+8]
                        mov         rsi,[rsi+stn_token]
                        ; number is stored in network byte order
                        xor         rax,rax
                        mov         rcx,8
                        cld
.rdnum                  shl         rax,8
                        lodsb
                        loop        .rdnum
                        mov         [r12+csn_data],rax
                        ; done
                        jmp         .finish

                        ; strlit starts with FF
.strlit                 mov         [r12+csn_type],al
.lengthdata             mov         rdx,[rbx+stn_args]
                        ; second branch has length in network byte order
                        mov         rax,[rdx+8]
                        mov         rax,[rax+stn_token]
                        mov         ch,[rax]
                        mov         cl,[rax+1]
                        mov         [r12+csn_length],cx
                        ; third branch has data (text, not NUL terminated)
                        mov         rax,[rdx+16]
                        mov         rax,[rax+stn_token]
                        mov         [r12+csn_data],rax
                        ; done
                        jmp         .finish

                        ; ident starts with FE TYPE
.ident                  mov         [r12+csn_type],al
                        mov         al,[rsi+1]
                        mov         [r12+csn_subtype],al
                        ; length and data are the same as with strlit
                        jmp         .lengthdata

                        ; immediately translatable NC_TERMINAL branches
                        ; are those with TB_DATA matches
.terminal               mov         al,[rdi+impn_termType]
                        cmp         al,TT_BINARY
                        jne         .isnull
                        mov         rsi,[rdi+impn_text]
                        mov         al,[rsi]
                        cmp         al,TB_DATA
                        jne         .isnull

                        ; look at the matched bytes, first byte is token type
                        ; only S_OPER and S_KEYWORD fulfill the requirements for
                        ; direct instantiation
                        mov         rsi,[rbx+stn_token]
                        mov         al,[rsi]
                        cmp         al,S_OPER
                        je          .termok
                        cmp         al,S_KEYWORD
                        je          .termok

                        ; otherwise, it must be handled in the parent node
                        jmp         .discard

.termok                 mov         [r12+csn_type],al
                        mov         al,[rsi+1]
                        mov         [r12+csn_subtype],al
                        jmp         .finish

.subbranches            xor         r13,r13 ; r13 - src br counter
                        xor         r14,r14 ; r14 - dst br counter
                        mov         rdi,[rbx+stn_nargs]
                        test        rdi,rdi
                        jz          .finish
                        cmp         rdi,65535   ; b/c cnt is 16 bit in csn
                        jb          .nbrok
                        mov         rdi,65535
.nbrok                  shl         rdi,3       ; *8
                        call        xalloc
                        mov         [r12+csn_args],rax

.nextbr                 cmp         r13,[rbx+stn_nargs]
                        jae         .endbr
                        cmp         r13,65535   ; b/c cnt is 16 bit in csn
                        jae         .endbr
                        mov         rax,[rbx+stn_args]
                        mov         rdi,[rax+r13*8]
                        call        crt_csn
                        test        rax,rax
                        jz          .iterbr
                        mov         rdx,[r12+csn_args]
                        mov         [rdx+r14*8],rax
                        inc         r14
.iterbr                 inc         r13
                        jmp         .nextbr

.endbr                  mov         [r12+csn_nargs],r14

.finish                 mov         rax,r12

.end                    mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

.discard                mov         rdi,r12
                        call        xfree

.isnull                 xor         rax,rax
                        jmp         .end

                        ; can only be called after a syntax tree has been
                        ; created using crtsyntree
cooksyntree             enter       0,0

                        cmp         qword [cookedsyntree],0
                        je          .notcookedyet
                        call        delcookedsyntree

.notcookedyet           mov         rdi,[syntree]
                        test        rdi,rdi
                        jz          .nosyntree

.nosyntree              xor         rax,rax

.end                    leave
                        ret

                        ; rdi - csn
del_csn                 enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12

                        test        rdi,rdi
                        jz          .zero
                        mov         rbx,rdi

                        xor         r12,r12
.nextbr                 cmp         r12,[rbx+csn_nargs]
                        jae         .endbr
                        mov         rsi,[rbx+csn_args]
                        mov         rdi,[rsi+r12*8]
                        test        rdi,rdi
                        jz          .zerobr
                        mov         qword [rsi+r12*8],0
                        call        del_csn
.zerobr                 inc         r12
                        jmp         .nextbr

.endbr                  mov         rdi,[rbx+csn_args]
                        test        rdi,rdi
                        jz          .nobr
                        mov         qword [rbx+csn_args],0
                        call        xfree

.nobr                   mov         rdi,rbx
                        call        xfree

.zero                   mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

delcookedsyntree        enter       0,0

                        mov         rdi,[cookedsyntree]
                        test        rdi,rdi
                        jz          .notcookedyet

                        call        del_csn
                        mov         qword [cookedsyntree],0

.notcookedyet           leave
                        ret

print_csn               enter       0,0

                        leave
                        ret

printcookedsyntree      enter       0,0

                        mov         rdi,[cookedsyntree]
                        test        rdi,rdi
                        jz          .end

                        call        print_csn

.end                    leave
                        ret

                        section     .data

cookedsyntree           dq          0

                        section     .rodata

                        %include    "csntext.inc"
