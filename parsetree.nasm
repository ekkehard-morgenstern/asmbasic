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

                        %include    "parsetree.inc"

                        section     .text

                        ; from mainsyntax.nasm:
                        ; NOTE that this file is generated at build time
                        extern      mainsyntax_branches
                        extern      mainsyntax_parsingTable
                        extern      xalloc
                        global      initparsetree

                        ; initializes the parsing tree, which is used to parse
                        ; input written in BASIC (this is NOT the same as the
                        ; syntax tree which is generated from user input)
                        ;
                        ; it converts the "ROM-style" packed version of the
                        ; parsing tree to an "in-memory" version, which has
                        ; branch pointers instead of indices. this greatly
                        ; speeds up traversal of the tree later.

initparsetree           enter       0,0
                        ; find NT_DIRECT_LINE entry in parsing table
                        ; (NOTE: WILL CRASH if not present)
                        lea         rax,[mainsyntax_parsingTable]
.search                 cmp         word [rax+pn_nodeType],NT_DIRECT_LINE
                        je          .found
                        add         rax,parsingnode_size
                        jmp         .search
                        ; initialize it and all others recursively
.found                  mov         rdi,rax
                        call        impn_from_pn
                        mov         [parsetree],rax
                        leave
                        ret

                        ; convert parse table entry to parse tree node
                        ; (recursively)
                        ; rdi - address of topmost parsing table entry
                        ; output:
                        ; rax - topmost impn
impn_from_pn            enter       0x20,0
                        mov         [rbp-0x08],r12
                        mov         [rbp-0x10],rbx
                        mov         r12,rdi
                        mov         rdi,inmemparsingnode_size
                        call        xalloc
                        mov         rbx,rax
                        ; copy first three WORD fields
                        mov         rsi,r12
                        mov         rdi,rbx
                        mov         rcx,3
                        cld
                        movsw
                        ; init branch table pointer to 0
                        mov         qword [rbx+impn_branches],0
                        ; copy text pointer
                        mov         rax,[r12+pn_text]
                        mov         [rbx+pn_text],rax
                        ; check if we have any branches
                        cmp         word [rbx+impn_numBranches],0
                        je          .nobranches
                        ; yes; allocate memory for pointer table
                        movzx       rdi,word [rbx+impn_numBranches]
                        shl         rdi,3 ; * 8
                        call        xalloc
                        mov         [rbx+impn_branches],rax

                        ; fill table with pointers
                        mov         [rbp-0x18],r13
                        xor         r13,r13     ; r13 - branch index
                        ; read production index from branch entry
.nextbranch             movzx       rax,word [r12+pn_branches]
                        add         rax,r13
                        movsx       rax,word [mainsyntax_branches+rax*2]
                        cmp         rax,0
                        jge         .proceed
                        ; negative production index: clear branch pointer
                        xor         rax,rax
                        jmp         .storebranch
                        ; calculate production table entry offset
.proceed                mov         rcx,parsingnode_size
                        mul         rcx
                        ; calculate address and process node
                        lea         rdi,[mainsyntax_parsingTable+rax]
                        call        impn_from_pn
                        ; store result in pointer table
.storebranch            mov         rdx,[rbx+impn_branches]
                        mov         [rdx+r13*8],rax
                        ; next entry
                        inc         r13
                        cmp         r13w,[rbx+impn_numBranches]
                        jb          .nextbranch
                        mov         r13,[rbp-0x18]

.nobranches             mov         rax,rbx
                        mov         rbx,[rbp-0x10]
                        mov         r12,[rbp-0x08]
                        leave
                        ret

                        section     .bss

                        global      parsetree

parsetree               resq        1
