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
                        extern      xalloc,printf
                        extern      nc_texts,tt_texts,tb_texts,nt_texts
                        global      initparsetree,dumpparsetree

                        ; initializes the parsing tree, which is used to parse
                        ; input written in BASIC (this is NOT the same as the
                        ; syntax tree which is generated from user input)
                        ;
                        ; it converts the "ROM-style" packed version of the
                        ; parsing tree to an "in-memory" version, which has
                        ; branch pointers instead of indices. this greatly
                        ; speeds up traversal of the tree later.

initparsetree           enter       0,0
                        lea         rax,[impn_lut]
                        mov         [impn_lutptr],rax
                        mov         qword [impn_calldepth],0
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
                        inc         qword [impn_calldepth]

                        call        impn_findlutpair
                        test        rax,rax
                        jz          .newentry

                        mov         rbx,rax
                        jmp         .end

.newentry               mov         rdi,inmemparsingnode_size
                        call        xalloc
                        mov         rbx,rax

                        mov         rdi,r12
                        mov         rsi,rbx
                        call        impn_storelutpair

                        ; copy first three WORD fields
                        mov         rsi,r12
                        mov         rdi,rbx
                        mov         rcx,3
                        cld
                        rep         movsw

                        ; init branch table pointer to 0
                        mov         qword [rbx+impn_branches],0

                        ; copy text pointer
                        mov         rax,[r12+pn_text]
                        mov         [rbx+impn_text],rax

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

.nobranches:
.end                    mov         rax,rbx
                        dec         qword [impn_calldepth]
                        mov         rbx,[rbp-0x10]
                        mov         r12,[rbp-0x08]
                        leave
                        ret

                        ; store new LUT pair
                        ; rdi - pn pointer
                        ; rsi - impn pointer
impn_storelutpair       enter       0,0
                        mov         rax,[impn_lutptr]
                        mov         [rax],rdi
                        mov         [rax+8],rsi
                        add         rax,16
                        mov         [impn_lutptr],rax
                        leave
                        ret

                        ; find LUT pair
                        ; rdi - pn pointer
                        ; result: rax - impn pointer
impn_findlutpair        enter       0,0

                        lea         rax,[impn_lut]
                        mov         rdx,[impn_lutptr]

.nextentry              cmp         rax,rdx
                        jae         .notfound
                        cmp         [rax],rdi
                        je          .found
                        add         rax,16
                        jmp         .nextentry

.end                    leave
                        ret

.found                  mov         rax,[rax+8]
                        jmp         .end

.notfound               xor         rax,rax
                        jmp         .end

                        ; dumps the parsing tree
dumpparsetree           enter       0,0
                        lea         rax,[impn_lut]
                        mov         [impn_lutptr],rax
                        mov         qword [impn_calldepth],0
                        mov         rdi,[parsetree]
                        mov         rsi,0   ; indent
                        call        dump_impn
                        leave
                        ret

                        ; dumps in-memory parse tree node
                        ; (recursively)
                        ; rdi - node
                        ; rsi - indent
dump_impn               enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        inc         qword [impn_calldepth]

                        mov         rbx,rdi
                        mov         r12,rsi

                        ; print node information
                        lea         rdi,[impn_fmt]
                        mov         rsi,r12
                        mov         rdx,rsi
                        lea         rcx,[impn_shift]
                        movzx       rax,byte [rbx+impn_nodeClass]
                        mov         r8,[nc_texts+rax*8]
                        movzx       rax,byte [rbx+impn_termType]
                        mov         r9,[tt_texts+rax*8]
                        movzx       rax,word [rbx+impn_nodeType]
                        mov         rax,[nt_texts+rax*8]
                        push        rax
                        xor         al,al
                        call        printf
                        add         rsp,8

                        ; write text
                        cmp         qword [rbx+impn_text],0
                        je          .notext

                        cmp         byte [rbx+impn_termType],TT_BINARY
                        je          .binarytext

                        lea         rdi,[impn_fmt_text]
                        mov         rsi,r12
                        mov         rdx,r12
                        lea         rcx,[impn_shift]
                        mov         r8,[rbx+impn_text]
                        xor         al,al
                        call        printf
                        jmp         .dobranches

.binarytext             mov         rax,[rbx+impn_text]
                        mov         dl,[rax]
                        cmp         dl,TB_DATA
                        je          .data

                        lea         rdi,[impn_fmt_byte]
                        mov         rsi,r12
                        mov         rdx,r12
                        lea         rcx,[impn_shift]
                        movzx       r8,byte [rax]
                        xor         al,al
                        call        printf
                        jmp         .dobranches

.data                   mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14
                        movzx       r13,byte [rax+1]
                        lea         r14,[rax+2]

                        lea         rdi,[impn_fmt_data]
                        mov         rsi,r12
                        mov         rdx,r12
                        lea         rcx,[impn_shift]
                        xor         al,al
                        call        printf

.nextbyte               lea         rdi,[impn_fmt_data2]
                        movzx       rsi,byte [r14]
                        xor         al,al
                        call        printf
                        inc         r14
                        dec         r13
                        jnz         .nextbyte

                        lea         rdi,[impn_fmt_data3]
                        xor         al,al
                        call        printf

                        mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]

.notext:
.dobranches             cmp         word [rbx+impn_numBranches],0
                        je          .end

                        ; to prevent infinite recursion (b/c we have
                        ; self-recursive subtrees like in expressions)
                        ; use a lookup table to see what we have already
                        ; printed
                        mov         rdi,rbx
                        call        impn_findlutpair
                        test        rax,rax
                        jz          .notprinted

                        ; if node has already been printed
                        lea         rdi,[impn_fmt_nest]
                        lea         rsi,[r12+2]
                        mov         rdx,rsi
                        lea         rcx,[impn_shift]
                        xor         al,al
                        call        printf

                        jmp         .end

                        ; write LUT entry
.notprinted             mov         rdi,rbx
                        mov         rsi,1
                        call        impn_storelutpair

                        ; print subtree
                        mov         [rbp-0x18],r13
                        xor         r13,r13

.nextbranch             mov         rdi,[rbx+impn_branches]
                        mov         rdi,[rdi+r13*8]
                        cmp         rdi,0
                        je          .skipbranch

                        lea         rsi,[r12+2]
                        call        dump_impn

.skipbranch             inc         r13
                        cmp         r13w,[rbx+impn_numBranches]
                        jb          .nextbranch

                        mov         r13,[rbp-0x18]

.end                    dec         qword [impn_calldepth]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret


                        section     .rodata

impn_shift              db          0
impn_fmt                db          '%-*.*s%s,%s,%s',10,0
impn_fmt_text           db          "%-*.*s'%s'",10,0
impn_fmt_byte           db          '%-*.*s%02x',10,0
impn_fmt_data           db          '%-*.*s',0
impn_fmt_data2          db          '%02x ',0
impn_fmt_data3          db          10,0
impn_fmt_nest           db          '%-*.*s...',10,0

                        section     .bss

                        global      parsetree

parsetree               resq        1
impn_calldepth          resq        1
impn_lutptr             resq        1
impn_lut                resq        2000
