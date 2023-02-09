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
                        extern      cookedsyntree,xalloc,del_csn,xfree
                        global      refinecookedsyntree

; GOALS:
;   - Rearrange cooked syntax tree such that:
;     o The line number is the first subnode of the root node
;       (and its parent generic node is marked as S_LINENUMBER).
;     o Statements separated by semicolon are regrouped to be
;       children of the root node, each of their generic parent
;       nodes are marked with S_STATEMENT.
;     o Colon operators can be removed.
;     o Expressions will be marked with a S_EXPRESSION parent.
;     o They become direct children of the statement or function
;       call / array access nodes they belong to.
;     o Comma operators can be removed.
;     o Nodes that became superfluous as a part of previous
;       operations are discarded (i.e. generic nodes that
;       became empty), and branch tables are cleaned up.
;     o The root node is marked with S_LINE.
;   - Future steps:
;     o ...
;

                        ; rdi - cooked syntax (sub-)tree
refine_csn              enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         rbx,rdi
                        test        rbx,rbx
                        jz          .null

                        ; root node?
                        cmp         rbx,[cookedsyntree]
                        jne         .notroot

                        cmp         byte [rbx+csn_type],S_UNDEF
                        jnz         .notgenroot

                        mov         byte [rbx+csn_type],S_LINE

.notgenroot             cmp         word [rbx+csn_nargs],1
                        jb          .null

                        mov         rax,[rbx+csn_args]
                        test        rax,rax
                        jz          .null

                        ; if the first branch is of S_NUMBER, pack it into a
                        ; S_LINENUMBER node and make that the first branch.
                        ;           10 a=1
                        ;           (generic)
                        ;               S_NUMBER,base 10,"10"
                        ;           ...
                        mov         rax,[rax]
                        cmp         byte [rax+csn_type],S_NUMBER
                        jne         .notlinenumber

                        mov         r12,rax ; r12 - line number value node
                        mov         rdi,cookedsyntaxnode_size
                        call        xalloc
                        mov         r13,rax
                        mov         rdi,rax
                        xor         rax,rax
                        mov         rcx,cookedsyntaxnode_size/8
                        cld
                        rep         stosq
                        mov         byte [r13+csn_type],S_LINENUMBER
                        mov         rdi,8
                        call        xalloc
                        mov         [r13+csn_args],rax
                        mov         [rax],r12
                        mov         word [r13+csn_nargs],1

                        mov         rax,[rbx+csn_args]
                        mov         [rax],r13
                        mov         r12,1 ; branch index of next branch
                        jmp         .continue1

                        ; Check the first (non-number) or second branch
                        ; If it's a generic node and its first child is not
                        ; another generic node, it's the first statement.
                        ; In that case, mark it with a S_STATEMENT tag.
                        ; If it's an S_IDENT or S_KEYWORD node, there's
                        ; only one statement. In that case, pack it into a
                        ; S_STATEMENT node.
                        ;           10 a=1
                        ;           (generic)
                        ;               S_NUMBER,base 10,"10"
                        ;               (generic)
                        ;                   S_IDENT,ID_NUM,"A"
                        ;                   S_OPER,OP_EQ
                        ;                   S_NUMBER,base 10,"1"
                        ;           a=1
                        ;           (generic)
                        ;               S_IDENT,ID_NUM,"A"
                        ;               S_OPER,OP_EQ
                        ;               S_NUMBER,base 10,"1"
                        ;           a=1:b=2
                        ;           (generic)
                        ;               (generic)
                        ;                   S_IDENT,ID_NUM,"A"
                        ;                   S_OPER,OP_EQ
                        ;                   S_NUMBER,base 10,"1"
                        ;               ...

.notlinenumber          mov         r12,0 ; branch index of next branch
                        cmp         r12w,[rbx+csn_nargs]
                        jae         .recurse
                        mov         rax,[rbx+csn_args]
                        ; check node type of first or second branch
.continue1              mov         rax,[rax+r12*8]
                        mov         dl,[rax+csn_type]
                        cmp         dl,S_IDENT
                        je          .onestatement
                        cmp         dl,S_KEYWORD
                        je          .onestatement
                        cmp         dl,S_UNDEF
                        jne         .recurse
                        ; it's a generic node: check if first child of that
                        ; is also a generic node.
                        mov         dx,word [rax+csn_nargs]
                        cmp         dx,1
                        jb          .firststatement
                        mov         rdx,[rax+csn_args]
                        mov         rdx,[rdx]
                        cmp         byte [rdx+csn_type],S_UNDEF
                        jne         .firststatement
                        ; first statement lies deeper
                        mov         rax,rdx
.firststatement         mov         byte [rax+csn_type],S_STATEMENT
                        jmp         .recurse
                        ; there's only one statement: its elements are direct
                        ; branches from the root node. move them into a child.
                        ;           a=1
                        ;           (generic)
                        ;               S_IDENT,ID_NUM,"A"
                        ;               S_OPER,OP_EQ
                        ;               S_NUMBER,base 10,"1"
.onestatement           mov         rdi,cookedsyntaxnode_size
                        call        xalloc
                        mov         r12,rax
                        mov         rdi,rax
                        mov         rcx,cookedsyntaxnode_size/8
                        xor         rax,rax
                        cld
                        rep         stosq   ; zero out structure
                        ; init node
                        mov         byte [r12+csn_type],S_STATEMENT
                        ; take over branches from root node
                        mov         ax,[rbx+csn_nargs]
                        mov         [r12+csn_nargs],ax
                        mov         rax,[rbx+csn_args]
                        mov         [r12+csn_args],rax
                        ; set branch count in root node to 1
                        mov         word [rbx+csn_nargs],1
                        ; alloc a one branch subtree
                        mov         rdi,8
                        call        xalloc
                        mov         [rbx+csn_args],rax
                        ; set the branch to the new node
                        mov         [rax],r12
                        ; continue with recursion
                        jmp         .recurse

                        ; a node with a COLON operator has a direct sibling
                        ; containing the statement, like this:
                        ;           (generic)
                        ;               S_OPER,OP_COLON
                        ;               (generic)
                        ;                   S_IDENT,ID_NUM,"B"
                        ;                   S_OPER,OP_EQ
                        ;                   S_NUMBER,base 10,"2"
.notroot:               cmp         byte [rbx+csn_type],S_UNDEF
                        jne         .doexpr
                        cmp         word [rbx+csn_nargs],2
                        jb          .doexpr
                        mov         rax,[rbx+csn_args]
                        test        rax,rax
                        jz          .doexpr
                        mov         rsi,[rax]
                        cmp         byte [rsi+csn_type],S_OPER
                        jne         .doexpr
                        cmp         byte [rsi+csn_subtype],OP_COLON
                        jne         .doexpr
                        mov         rsi,[rax+8]
                        cmp         byte [rsi+csn_type],S_UNDEF
                        jne         .doexpr
                        mov         byte [rsi+csn_type],S_STATEMENT
                        mov         r12,rsi
                        ; copy statement node over current node, unlink
                        ; statement node from its subbranches then free it.
                        mov         rdi,rbx
                        mov         rcx,cookedsyntaxnode_size/8
                        cld
                        rep         movsq
                        mov         rdi,r12
                        mov         word [rdi+csn_nargs],0
                        mov         qword [rdi+csn_args],0
                        call        del_csn

.doexpr:                nop     ; TBD

                        ; recurse into sub branches
.recurse                xor         r12,r12
.nextbr                 cmp         r12w,[rbx+csn_nargs]
                        jae         .afterbr
                        mov         rdi,[rbx+csn_args]
                        test        rdi,rdi
                        jz          .afterbr
                        mov         rdi,[rdi+r12*8]
                        test        rdi,rdi
                        jz          .iterbr
                        call        refine_csn
.iterbr                 inc         r12
                        jmp         .nextbr

                        ; after recursion into branches:
                        ; if this is the root node and its final branch is a
                        ; generic with S_STATEMENTs under it, then move its
                        ; branches up to the root node, discarding the generic
                        ; branch.
                        ;           (generic)
                        ;               S_STATEMENT
                        ;               ...

.afterbr                cmp         rbx,[cookedsyntree]
                        jne         .end

                        ; test if final branch of root node is a generic node
                        mov         dx,[rbx+csn_nargs]
                        cmp         dx,2
                        jb          .end
                        movzx       rdx,dx
                        dec         rdx
                        mov         rsi,[rbx+csn_args]
                        test        rsi,rsi
                        jz          .end
                        mov         rsi,[rsi+rdx*8]
                        test        rsi,rsi
                        jz          .end
                        cmp         byte [rsi+csn_type],S_UNDEF
                        jne         .end

                        ; see if that contains a STATEMENT as the first child
                        cmp         word [rsi+csn_nargs],0
                        je          .end
                        mov         rdi,[rsi+csn_args]
                        test        rdi,rdi
                        jz          .end
                        mov         rdi,[rdi]
                        cmp         byte [rdi+csn_type],S_STATEMENT
                        jne         .end

                        ; yes: remember that generic node, then zero out its
                        ; pointer in the original branch table, and decrement
                        ; the branch count on the root node.
                        mov         r12,rsi
                        mov         rsi,[rbx+csn_args]
                        mov         qword [rsi+rdx*8],0
                        dec         word [rbx+csn_nargs]

                        ; compute the new branch count as the sum of the old
                        ; branch count + the branch count in the generic node.
                        movzx       rdx,word [rbx+csn_nargs]
                        movzx       rax,word [r12+csn_nargs]
                        add         rdx,rax
                        mov         [rbx+csn_nargs],dx

                        ; remember old branch table
                        mov         r13,[rbx+csn_args]

                        ; allocate new branch table
                        shl         rax,8
                        mov         rdi,rax
                        call        xalloc
                        mov         [rbx+csn_args],rax

                        ; copy old entries over to new table
                        mov         rdi,rax
                        mov         rsi,r13
                        mov         cx,[rbx+csn_nargs]
                        sub         cx,[r12+csn_nargs]
                        movzx       rcx,cx
                        cld
                        rep         movsq

                        ; append new entries in new table
                        mov         rsi,[r12+csn_args]
                        movzx       rcx,word [r12+csn_nargs]
                        rep         movsq

                        ; free old branch table of root node
                        mov         rdi,r13
                        call        xfree

                        ; free old branch table of child node
                        mov         rdi,[r12+csn_args]
                        call        xfree

                        ; zero out branch info in child node
                        ; then free child node
                        mov         word [r12+csn_nargs],0
                        mov         qword [r12+csn_args],0
                        mov         rdi,r12
                        call        del_csn

                        ; voila: root node contains merged table

.null:
.end                    mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

refinecookedsyntree     enter       0,0

                        mov         rdi,[cookedsyntree]
                        test        rdi,rdi
                        jz          .end

                        cmp         qword [disable_csnref],0
                        jne         .end

                        call        refine_csn

.end                    leave
                        ret

                        section     .data

                        global      disable_csnref

disable_csnref          dq          0
