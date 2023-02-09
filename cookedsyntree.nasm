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

                        extern      syntree,xalloc,xfree,xrealloc,pb_putfmt
                        extern      refinecookedsyntree
                        global      cooksyntree,delcookedsyntree,del_csn
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
                        test        rax,rax
                        jz          .subbranches
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
                        jmp         .subbranches

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
                        jne         .discard
                        mov         rsi,[rdi+impn_text]
                        mov         al,[rsi]
                        cmp         al,TB_DATA
                        jne         .discard

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

.endbr                  mov         [r12+csn_nargs],r14w
                        cmp         r14,1
                        jne         .finish
                        cmp         byte [r12+csn_type],0
                        jne         .finish

                        ; if this is a generic node with one sub branch,
                        ; return the child node instead
                        mov         rsi,[r12+csn_args]
                        mov         rdi,[rsi]
                        mov         qword [rsi],0
                        xchg        rdi,r12
                        call        del_csn

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

                        call        crt_csn
                        mov         [cookedsyntree],rax

                        call        refinecookedsyntree

                        jmp         .end

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
.nextbr                 cmp         r12w,[rbx+csn_nargs]
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

                        ; rdi - csn
                        ; rsi - indent
print_csn               enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         rbx,rdi
                        mov         r13,rsi

                        ; print indent
                        lea         rdi,[csn_indent_fmt]
                        mov         rsi,r13
                        mov         rdx,r13
                        lea         rcx,[csn_indent_spc]
                        xor         al,al
                        call        qword [pb_putfmt]

                        ; test for NULL node
                        test        rbx,rbx
                        jz          .zero

                        ; check node type
                        mov         al,[rbx+csn_type]
                        test        al,al
                        jz          .generic

                        cmp         al,S_OPER
                        je          .operator
                        cmp         al,S_KEYWORD
                        je          .keyword
                        cmp         al,S_NUMBER
                        je          .number
                        cmp         al,S_STRLIT
                        je          .strlit
                        cmp         al,S_IDENT
                        je          .ident

                        cmp         al,S_LINENUMBER
                        je          .specific
                        cmp         al,S_STATEMENT
                        je          .specific
                        cmp         al,S_EXPRESSION
                        je          .specific
                        cmp         al,S_LINE
                        je          .specific

.generic                lea         rdi,[csn_generic_fmt]
.genprt                 xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .dobranches

.specific               lea         rdi,[csn_specific_fmt]
                        movzx       rax,al
                        mov         rsi,[s_table+rax*8]
                        test        rsi,rsi
                        jz          .generic
                        jmp         .genprt

                        ; operator/keyword; rdx must be set
.prtopkw                lea         rdi,[csn_opkw_fmt]
                        movzx       rax,byte [rbx+csn_type]
                        mov         rsi,[s_table+rax*8]
                        test        rsi,rsi
                        jnz         .opkwok
                        lea         rsi,[csn_bad]
.opkwok                 xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .dobranches

.operator               movzx       rax,byte [rbx+csn_subtype]
                        mov         rdx,[op_table+rax*8]
.kwent                  test        rdx,rdx
                        jnz         .opok
                        lea         rdx,[csn_bad]
.opok                   jmp         .prtopkw

.keyword                movzx       rax,byte [rbx+csn_subtype]
                        mov         rdx,[kw_table+rax*8]
                        jmp         .kwent

.number                 lea         rdi,[csn_num_fmt]
                        lea         rsi,[s_number_text]
                        movzx       rdx,byte [rbx+csn_numbase]
                        movq        xmm0,[rbx+csn_data]
                        mov         al,1
                        call        qword [pb_putfmt]
                        jmp         .dobranches

.strlit                 lea         rsi,[s_strlit_text]
                        lea         rdi,[csn_str_fmt]
                        movzx       rdx,word [rbx+csn_length]
                        mov         rcx,rdx
                        mov         r8,[rbx+csn_data]
                        xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .dobranches

.ident                  lea         rsi,[s_ident_text]
                        lea         rdi,[csn_id_fmt]
                        movzx       rdx,byte [rbx+csn_subtype]
                        mov         rdx,[id_table+rdx*8]
                        test        rdx,rdx
                        jnz         .notbadid
                        lea         rdx,[csn_bad]
.notbadid               movzx       rcx,word [rbx+csn_length]
                        mov         r8,rcx
                        mov         r9,[rbx+csn_data]
                        xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .dobranches

.dobranches             xor         r12,r12
.nextbr                 cmp         r12w,[rbx+csn_nargs]
                        jae         .end
                        mov         rdi,[rbx+csn_args]
                        mov         rdi,[rdi+r12*8]
                        lea         rsi,[r13+2]
                        call        print_csn
                        inc         r12
                        jmp         .nextbr

.end                    mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

.zero                   lea         rdi,[csn_null_fmt]
                        xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .end



printcookedsyntree      enter       0,0

                        mov         rdi,[cookedsyntree]
                        test        rdi,rdi
                        jz          .end

                        xor         rsi,rsi
                        call        print_csn

.end                    leave
                        ret

                        section     .data
                        global      cookedsyntree

cookedsyntree           dq          0

                        section     .rodata

csn_indent_fmt          db          '%-*.*s'
csn_indent_spc          db          0
csn_null_fmt            db          '(null)',10,0
csn_generic_fmt         db          '(generic)',10,0
csn_specific_fmt        db          '%s',10,0
csn_bad                 db          '???',0
csn_opkw_fmt            db          '%s,%s',10,0
csn_num_fmt             db          '%s,base %u,"%g"',10,0
csn_str_fmt             db          '%s,"%-*.*s"',10,0
csn_id_fmt              db          '%s,%s,"%-*.*s"',10,0

                        align       8,db 0

                        %include    "csntext.inc"
