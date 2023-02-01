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
                        extern      pb_putfmt,nc_texts,tt_texts,nt_texts

                        global      crtsyntree,delsyntree,prtsyntree

                        ; rdi - in-memory parse tree node
stn_from_impt           enter       0x20,0
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

                        ; print node information
                        cmp         qword [stn_debug],0
                        je          .nodebug

                        lea         rdi,[pt_dbg_fmt]
                        movzx       rax,byte [rbx+impn_nodeClass]
                        mov         rsi,[nc_texts+rax*8]
                        movzx       rax,byte [rbx+impn_termType]
                        mov         rdx,[tt_texts+rax*8]
                        movzx       rax,word [rbx+impn_nodeType]
                        mov         rcx,[nt_texts+rax*8]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; check node class
.nodebug                mov         al,[rbx+impn_nodeClass]
                        cmp         al,NC_PRODUCTION
                        je          .mandatory
                        cmp         al,NC_MANDATORY
                        je          .mandatory
                        cmp         al,NC_ALTERNATIVE
                        je          .alternative
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
                        mov         rdi,[rax+r12*8]
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
                        jne         .notgeneric

                        ; a NC_TERMINAL? if so, take its match and token
                        ; pointers too
                        cmp         byte [rsi+impn_nodeClass],NC_TERMINAL
                        jne         .nonterminal

                        mov         [r13+stn_match],rsi
                        mov         rsi,[rdi+stn_token]
                        mov         [r13+stn_token],rsi

                        ; take its branch info
.nonterminal            mov         rsi,[rdi+stn_nargs]
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

                        ; is it another production node?
.notgeneric             cmp         byte [rsi+impn_nodeClass],NC_PRODUCTION
                        jne         .manmatch2

                        ; yes? then we don't need the current one
                        xchg        r13,rdi
                        mov         qword [rdi+stn_nargs],0
                        mov         qword [rdi+stn_args],0
                        call        free_stn
                        jmp         .manmatch2

                        ; pretend the current branch index is the number of
                        ; branches in this node
.manfailed              mov         [r13+stn_nargs],r12

                        ; free the node
                        mov         rdi,r13
                        call        free_stn

                        ; finish without result
                        jmp         .noresult

                        ; alternative match requires ONE branch must be
                        ; satisfied. since alternative matches are ALWAYS of
                        ; type _NT_GENERIC, the resulting branch can simply be
                        ; passed to the parent without further ado.
.alternative            xor         r12,r12     ; branch index
.altnextbr              cmp         r12w,[rbx+impn_numBranches]
                        jae         .noresult  ; no match found
                        mov         rax,[rbx+impn_branches]
                        mov         rdi,[rax+r12*8]
                        call        stn_from_impt
                        test        rax,rax
                        jnz         .withresult     ; result returned directly
                        inc         r12
                        jmp         .altnextbr

                        ; optional match does always match, whether it was
                        ; successful or not. thus, it comes out with NULL
                        ; value child branches if those were unsuccessful.

                        ; preallocate and populate syntax node (except branches)
.optional               mov         rdi,syntreenode_size
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
                        xor         r12,r12

                        ; match all of the branches, storing the results
.optnextbr              cmp         r12w,word [rbx+impn_numBranches]
                        jae         .optdone
                        mov         rax,[rbx+impn_branches]
                        mov         rdi,[rax+r12*8]
                        call        stn_from_impt
                        mov         rdx,[r13+stn_args]
                        mov         [rdx+r12*8],rax
                        inc         r12
                        jmp         .optnextbr

.optdone                mov         rax,r13
                        jmp         .withresult

                        ; optional repetitive never fails. one branch can be
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
                        mov         rdi,[rax+r12*8]
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
                        ; no result: return empty node
                        ; more than one match; syntax node is good as it is
.optrepempty            mov         rax,r13
                        jmp         .withresult

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
.terminal               cmp         byte [rbx+impn_termType],TT_BINARY
                        jne         .noresult

                        ; text pointer contains more info
                        mov         rax,[rbx+impn_text]
                        mov         dl,[rax]
                        cmp         dl,TB_DATA  ; literal data match
                        je          .termdata

                        ; control byte: check
                        mov         al,dl
                        and         al,TBF_PARAM-1
                        cmp         al,TB_BYTE
                        jb          .noresult
                        cmp         al,TB_QWORD
                        ja          .noresult

                        ; 1 << (al-TB_BYTE) is the number of bytes
                        ; to be read literally; to rcx
                        mov         cl,al
                        sub         cl,TB_BYTE
                        mov         rax,1
                        shl         rax,cl
                        mov         rcx,rax

                        ; check if the TBF_PARAM flag is set
                        test        dl,TBF_PARAM
                        jnz         .termparam

                        ; nope: match of N bytes: check if that number of bytes
                        ; would exhaust the token pointer
.termcheck              mov         rax,[stn_tokenptr]
                        add         rax,rcx
                        cmp         rax,[stn_tokenend]
                        ja          .noresult

                        ; nope: just update the token pointer; use the old
                        ; value in creating a new node
.termcreate             mov         r12,[stn_tokenptr]
                        mov         [stn_tokenptr],rax
                        mov         rdi,syntreenode_size
                        call        xalloc
                        mov         r13,rax
                        mov         [r13+stn_match],rbx
                        mov         [r13+stn_token],r12
                        mov         qword [r13+stn_nargs],0
                        mov         qword [r13+stn_args],0

                        ; done
                        mov         rax,r13
                        jmp         .withresult

                        ; check if the TBF_WRITE flag is also set
.termparam              test        dl,TBF_WRITE
                        jnz         .termwrite

                        ; nope, it's a read: get the previously saved parameter
                        ; and use it to skip a number of bytes(*rcx)
                        mov         rax,rcx
                        mul         qword [stn_tokenparam]
                        mov         rcx,rax
                        jmp         .termcheck

                        ; it's a write: first check if possible, then read a
                        ; number of bytes and store them in stn_tokenparam for
                        ; subsequent use (usually the sibling node following
                        ; right after the current one)
.termwrite              mov         rax,[stn_tokenptr]
                        add         rax,rcx
                        cmp         rax,[stn_tokenend]
                        ja          .noresult

                        mov         rdx,[stn_tokenptr]
                        xor         rax,rax
.termwritegetcnt        shl         rax,8
                        mov         al,[rdx]
                        inc         rdx
                        loop        .termwritegetcnt
                        mov         [stn_tokenparam],rax
                        mov         rax,rdx
                        jmp         .termcreate

                        ; get number of bytes
.termdata               inc         rax
                        movzx       rcx,byte [rax]
                        inc         rax
                        mov         rsi,rax

                        ; check if token data is available
                        mov         rax,[stn_tokenptr]
                        add         rax,rcx
                        cmp         rax,[stn_tokenend]
                        ja          .noresult
                        mov         rdi,[stn_tokenptr]

                        ; yes: compare with expected data
                        cld
                        repe        cmpsb
                        jne         .noresult  ; no match ->

                        ; match: create new node
                        mov         rax,rdi
                        jmp         .termcreate

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
crtsyntree              enter       0x10,0
                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi

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

                        leave
                        ret

                        ; rdi - syntreenode
free_stn                enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         rbx,rdi     ; rbx - syntreenode pointer
                        inc         qword [stn_calldepth]

                        test        rbx,rbx
                        jz          .nullptr

                        ; print node information
                        cmp         qword [stn_debug],0
                        je          .nodebug
                        lea         rdi,[pt_dbg_fmt2]
                        mov         r12,[rbx+stn_match]
                        movzx       rax,byte [r12+impn_nodeClass]
                        mov         rsi,[nc_texts+rax*8]
                        movzx       rax,byte [r12+impn_termType]
                        mov         rdx,[tt_texts+rax*8]
                        movzx       rax,word [r12+impn_nodeType]
                        mov         rcx,[nt_texts+rax*8]
                        xor         al,al
                        call        qword [pb_putfmt]

.nodebug                mov         rax,[rbx+stn_args]
                        test        rax,rax
                        jz          .noargs

                        mov         r12,[rbx+stn_nargs]
.prevbranch             dec         r12
                        jl          .endargs

                        mov         rax,[rbx+stn_args]
                        mov         rdi,[rax+r12*8]
                        test        rdi,rdi
                        jz          .prevbranch
                        ; mov         qword [rax+r12*8],0

                        ; free branch
                        call        free_stn
                        jmp         .prevbranch

                        ; free args vector
.endargs                mov         rdi,[rbx+stn_args]
                        ; mov         qword [rbx+stn_args],0
                        call        xfree

                        ; free node object
.noargs                 mov         rdi,rbx
                        call        xfree

.nullptr                dec         qword [stn_calldepth]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

delsyntree              enter       0,0

                        mov         rax,[syntree]
                        test        rax,rax
                        jz          .end

                        mov         rdi,rax
                        mov         qword [stn_calldepth],0
                        call        free_stn

                        xor         rax,rax
                        mov         [syntree],rax

.end                    leave
                        ret

                        ; rdi - tree node
print_stn               enter       0x30,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14
                        mov         [rbp-0x28],r15
                        mov         rbx,rdi
                        inc         qword [stn_calldepth]

                        test        rbx,rbx
                        jz          .iszero

                        ; indent
                        lea         rdi,[stn_prt_fmt]
                        mov         rsi,[stn_calldepth]
                        dec         rsi
                        shl         rsi,1   ; *2
                        mov         rdx,rsi
                        lea         rcx,[stn_shf_fmt]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; match node info
                        mov         r12,[rbx+stn_match]
                        lea         rdi,[stn_prt_fmt2]
                        movzx       rax,byte [r12+impn_nodeClass]
                        mov         rsi,[nc_texts+rax*8]
                        movzx       rax,byte [r12+impn_termType]
                        mov         rdx,[tt_texts+rax*8]
                        movzx       rax,word [r12+impn_nodeType]
                        mov         rcx,[nt_texts+rax*8]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; terminal info
                        cmp         byte [r12+impn_nodeClass],NC_TERMINAL
                        jne         .notterminal
                        cmp         byte [r12+impn_termType],TT_BINARY
                        jne         .notterminal

                        ; print terminal info
                        ;   r13 - impn_text (requirement info)
                        ;   r14 - stn_token (matching bytes)
                        ;   r15 - length of output bytes
                        mov         r13,[r12+impn_text]
                        mov         r14,[rbx+stn_token]
                        xor         r15,r15

                        ; check for TB_DATA
                        mov         dl,[r13]
                        cmp         dl,TB_DATA
                        jne         .notdata

                        ; literal match
                        movzx       r15,byte [r13+1]
                        jmp         .outputhex

                        ; get field type, convert to length
.notdata                mov         cl,dl
                        and         cl,TBF_PARAM-1
                        sub         cl,TB_BYTE
                        mov         rax,1
                        shl         rax,cl
                        mov         rcx,rax

                        ; test for TBF_PARAM
                        test        dl,TBF_PARAM
                        jnz         .param

                        ; nope: single item match
                        mov         r15,rcx
                        jmp         .outputhex

                        ; test for TBF_WRITE
.param                  test        dl,TBF_WRITE
                        jnz         .paramwrite

                        ; get previously saved value:
                        mov         rax,[stn_tokenparam]
                        mul         rcx

                        ; result is the length
                        mov         r15,rax
                        jmp         .outputhex

                        ; read length
.paramwrite             xor         rax,rax
                        mov         r15,rcx ; also for output
.getnextbyte            shl         rax,8
                        mov         al,[r14]
                        inc         r14
                        loop        .getnextbyte

                        ; save it
                        mov         [stn_tokenparam],rax

                        ; reset pointer for output
                        mov         r14,[rbx+stn_token]

                        ; output
                        ; jmp       .outputhex

.outputhex              test        r15,r15
                        jz          .notterminal

                        ; first output indent
                        lea         rdi,[stn_prt_fmt]
                        mov         rsi,[stn_calldepth]
                        shl         rsi,1   ; *2
                        mov         rdx,rsi
                        lea         rcx,[stn_shf_fmt]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; output individual bytes
.prtbyte                lea         rdi,[stn_prt_fmt3]
                        movzx       rsi,byte [r14]
                        inc         r14
                        xor         al,al
                        call        qword [pb_putfmt]
                        dec         r15
                        jnz         .prtbyte

                        ; done output lf
                        lea         rdi,[stn_prt_lf]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; output branches
.notterminal            xor         r12,r12
.nextbr                 cmp         r12,[rbx+stn_nargs]
                        jae         .endbr

                        mov         rdi,[rbx+stn_args]
                        mov         rdi,[rdi+r12*8]
                        call        print_stn

                        inc         r12
                        jmp         .nextbr

                        ; NULL node, print

                        ; indent
.iszero                 lea         rdi,[stn_prt_fmt]
                        mov         rsi,[stn_calldepth]
                        dec         rsi
                        shl         rsi,1   ; *2
                        mov         rdx,rsi
                        lea         rcx,[stn_shf_fmt]
                        xor         al,al
                        call        qword [pb_putfmt]

                        lea         rdi,[stn_prt_null]
                        xor         al,al
                        call        qword [pb_putfmt]

.endbr:
.end                    dec         qword [stn_calldepth]
                        mov         r15,[rbp-0x28]
                        mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret


prtsyntree              enter       0,0

                        mov         rax,[syntree]
                        test        rax,rax
                        jz          .end

                        mov         rdi,rax
                        mov         qword [stn_calldepth],0
                        call        print_stn

.end                    leave
                        ret

                        section     .data

                        global      syntree,stn_debug

syntree                 dq          0
stn_debug               dq          0

                        section     .bss

stn_tokenptr            resq        1
stn_tokenend            resq        1
stn_tokenparam          resq        1
stn_calldepth           resq        1

                        section     .rodata

pt_dbg_fmt              db          'crt %s,%s,%s',10,0
pt_dbg_fmt2             db          'del %s,%s,%s',10,0
stn_prt_fmt             db          '%-*.*s',0
stn_prt_fmt2            db          '%s,%s,%s',10,0
stn_prt_fmt3            db          '%02x ',0
stn_prt_lf              db          10,0
stn_prt_null            db          '(null)',10,0
stn_shf_fmt             db          0

                        align       8,db 0
