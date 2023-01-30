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

                        section     .text

                        extern      parsetree,xfree,xalloc,xrealloc

                        ; rdi - in-memory parse tree node
stn_from_impt           enter       0x18,0
                        mov         [rbp-0x10],rbx
                        mov         [rbp-0x18],r12
                        mov         [rbp-0x20],r13
                        mov         rbx,rdi

                        ; save current token position
                        mov         rax,[stn_tokenptr]
                        mov         [rbp-0x08],rax

                        ; test if node is zero
                        test        rbx,rbx
                        jz          .noresult

                        ; check node class
                        mov         al,[rbx+impn_nodeClass]
                        cmp         al,NC_PRODUCTION
                        je          .mandatory
                        cmp         al,NC_MANDATORY
                        je          .mandatory
                        cmp         al,NC_OPTIONAL
                        je          .optional
                        cmp         al,NC_OPTIONAL_REPETITIVE
                        je          .optional_repetitive
                        cmp         al,NC_TERMINAL
                        je          .terminal

                        ; unknown node class
                        jmp         .noresult

                        ; mandatory match requires ALL branches must
                        ; be satisfied.
.mandatory              xor         r12,r12     ; branch index

                        ; preallocate and populate syntax node (except branches)
                        mov         rdi,syntreenode_size
                        call        xalloc
                        mov         r13,rax
                        mov         [r13+stn_match],rbx
                        mov         qword [r13+stn_token],0
                        movzx       rax,word [rbx+impn_numBranches]
                        mov         [r13+stn_nargs],rax
                        mov         rdi,rax
                        shl         rdi,3   ; *8
                        call        xalloc
                        mov         [r13+stn_args],rax

                        ; match all of the branches, storing the results
.mannextbr              cmp         r12w,word [rbx+impn_numBranches]
                        jae         .manmatch
                        mov         rax,[rbx+impn_branches]
                        mov         rax,[rax+r12*8]
                        mov         rdi,rax
                        call        stn_from_impt
                        test        rax,rax
                        jz          .manfailed
                        mov         rdx,[r13+stn_args]
                        mov         [rdx+r12*8],rax
                        inc         r12
                        jmp         .mannextbr

                        ; check the node class again: if it's a production
                        ; with just one subbranch, take the subbranches from it
                        ; if it's just a generic node.
.manmatch               cmp         byte [rbx+impn_nodeClass],NC_PRODUCTION
                        jne         .manmatch2

                        cmp         r12,1   ; single branch?
                        jne         .manmatch2

                        ; child node with _NT_GENERIC?
                        mov         rdi,[r13+stn_args]
                        mov         rdi,[rdi]
                        mov         rsi,[rdi+stn_match]
                        cmp         word [rsi+impn_nodeType],_NT_GENERIC
                        jne         .manmatch2

                        ; take its branch info
                        mov         rsi,[rdi+stn_nargs]
                        mov         [r13+stn_nargs],rsi
                        mov         rsi,[rdi+stn_args]
                        mov         [r13+stn_args],rsi

                        ; zero out branch info in child node
                        xor         rsi,rsi
                        mov         [rdi+stn_nargs],rsi
                        mov         [rdi+stn_args],rsi

                        ; free child node
                        call        free_stn

                        ; done
.manmatch2              mov         rax,r13
                        jmp         .withresult

                        ; pretend the current branch index is the number of
                        ; branches in this node
.manfailed              mov         [r13+stn_nargs],r12w

                        ; free the node
                        mov         rdi,r13
                        call        free_stn

                        ; finish without result
                        jmp         .noresult

                        ; optional match requires ONE branch must be
                        ; satisfied. since optional matches are ALWAYS of type
                        ; _NT_GENERIC, the resulting branch can simply be passed
                        ; to the parent without further ado.
.optional               xor         r12,r12     ; branch index
.optnextbr              cmp         r12w,[rbx+impn_numBranches]
                        jae         .noresult  ; no match found
                        mov         rax,[rbx+impn_branches]
                        mov         rax,[rax+r12*8]
                        mov         rdi,rax
                        call        stn_from_impt
                        test        rax,rax
                        jnz         .withresult     ; result returned directly
                        inc         r12
                        jmp         .optnextbr

                        ; optional repetitive match requires ONE branch must be
                        ; satisfied; then the operation is retried as long as
                        ; results exist. Normally, I would implement this by
                        ; preallocating a certain number of branches,
                        ; but here, since the speed penalty is negligible
                        ; (since we're always processing one program line at a
                        ; time), I'll do a simple realloc every time a new match
                        ; is detected.
                        ;
                        ; preallocate and populate syntax node (except branches)
.optional_repetitive    mov         rdi,syntreenode_size
                        call        xalloc
                        mov         r13,rax
                        mov         [r13+stn_match],rbx
                        mov         qword [r13+stn_token],0
                        mov         qword [r13+stn_nargs],0
                        mov         qword [r13+stn_args],0

                        ; iterate over branches to find a match
.optrep                 xor         r12,r12     ; branch index
.optrepnextbr           cmp         r12w,[rbx+impn_numBranches]
                        jae         .optrepdone
                        mov         rax,[rbx+impn_branches]
                        mov         rax,[rax+r12*8]
                        mov         rdi,rax
                        call        stn_from_impt
                        test        rax,rax
                        jnz         .optrepgotmatch
                        inc         r12
                        jmp         .optnextbr

                        ; got a match: resize branch array and add branch
.optrepgotmatch         mov         r12,rax ; r12 - branch to be added
                        mov         rdi,[r13+stn_args]
                        inc         qword [r13+stn_nargs]
                        mov         rsi,[r13+stn_nargs]
                        shl         rsi,3 ; *8
                        call        xrealloc
                        mov         [r13+stn_args],rax
                        mov         rdx,[r13+stn_nargs]
                        dec         rdx
                        mov         [rax+rdx*8],r12
                        jmp         .optrep

                        ; done matching, check if there's more than one match
                        ; if it's just one match, return that.
                        ; if it's zero matches, return 0.
.optrepdone             cmp         qword [r13+stn_nargs],0
                        je          .optrepempty
                        cmp         qword [r13+stn_nargs],1
                        je          .optrepone
                        ; more than one match; syntax node is good as it is
                        mov         rax,r13
                        jmp         .withresult

                        ; no result: free syntax node and return 0
.optrepempty            mov         rdi,r13
                        call        free_stn
                        jmp         .noresult

                        ; exactly one result: return that node instead
.optrepone              mov         r12,[r13+stn_args]
                        mov         r12,[r12]

                        ; clear out branch fields and free current node
                        xor         rax,rax
                        mov         [r13+stn_nargs],rax
                        mov         [r13+stn_args],rax
                        mov         rdi,r13
                        call        free_stn

                        ; return child node
                        mov         rax,r12
                        jmp         .withresult

                        ; terminal match depends on terminal type
                        ; (since we're operating on a token buffer, all the
                        ; terminals we encounter must be of type TT_BINARY)
.terminal:


                        ; restore token position, return 0
.noresult               mov         rax,[rbp-0x08]
                        mov         [stn_tokenptr],rax
                        xor         rax,rax

.withresult             mov         r13,[rbp-0x20]
                        mov         r12,[rbp-0x18]
                        mov         rbx,[rbp-0x10]
                        leave
                        ret

                        ; rdi - tokenbuf
                        ; rsi - tokenbuf size
crtsyntree              enter       0x20,0
                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi
                        mov         [rbp-0x18],rbx
                        mov         [rbp-0x20],r12

                        mov         rax,[syntree]
                        test        rax,rax
                        jz          .iszero

                        call        delsyntree

.iszero                 mov         rax,[rbp-0x08] ; tokenbuf
                        mov         rdx,[rbp-0x10] ; tokenbuf_size
                        add         rdx,rax
                        mov         [stn_tokenptr],rax
                        mov         [stn_tokenend],rdx

                        mov         rdi,[parsetree]
                        call        stn_from_impt
                        mov         [syntree],rax

                        mov         r12,[rbp-0x20]
                        mov         rbx,[rbp-0x18]
                        leave
                        ret

                        ; rdi - syntreenode
free_stn                enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         rbx,rdi     ; rbx - syntreenode pointer
                        xor         r12,r12     ; r12 - argument index

                        mov         rax,[rbx+stn_args]
                        test        rax,rax
                        jz          .noargs

                        mov         r12,[rbx+stn_nargs]
.prevbranch             dec         r12
                        cmp         r12,0
                        jl          .endargs

                        mov         rax,[rbx+stn_args]
                        mov         rax,[rax+r12*8]
                        test        rax,rax
                        jz          .prevbranch

                        ; free branch
                        mov         rdi,rax
                        call        free_stn
                        jmp         .prevbranch

                        ; free args vector
.endargs                mov         rdi,[rbx+stn_args]
                        call        xfree

                        ; free node object
.noargs                 mov         rdi,rbx
                        call        xfree

                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

delsyntree              enter       0,0

                        mov         rax,[syntree]
                        test        rax,rax
                        jz          .end

                        mov         rdi,rax
                        call        free_stn

                        xor         rax,rax
                        mov         [syntree],rax

.end                    leave
                        ret

                        section     .data

syntree                 dq          0

                        section     .bss

stn_tokenptr            resq        1
stn_tokenend            resq        1
