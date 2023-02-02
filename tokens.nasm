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

LINEBUF_BYTES           equ         16384
TOKENPAD_BYTES          equ         32768
IDENTBUF_BYTES          equ         1024
STRLITBUF_BYTES         equ         1024

; token descriptors
                        struc       tokendesc
                            ; next entry with same hash value, in regular hash
                            td_nexthash:    resq    1
                            ; next entry with same hash value, in reverse hash
                            td_nextrev:     resq    1
                            ; name length, in bytes
                            td_namelen:     resb    1
                            ; encoding length, in bytes
                            td_enclen:      resb    1
                            ; directly followed by <td_namelen> bytes of name
                            ; directly followed by <td_enclen> bytes of encoding
                        endstruc

; token init descriptors
                        struc       tokeninit
                            ; name length, in bytes (0=end of data)
                            ti_namelen:     resb    1
                            ; encoding length, in bytes
                            ti_enclen:      resb    1
                            ; directly followed by <ti_namelen> bytes of name
                            ; directly followed by <ti_enclen> bytes of encoding
                        endstruc

; token init map entry
                        struc       tokenmapentry
                            ; next tokeninit block
                            tme_next:       resq    1
                            ; name of tokeninit block
                            tme_name:       resq    1
                            ; location of tokeninit block
                            tme_block:      resq    1
                            ; size of tokeninit block
                            tme_blksize:    resq    1
                        endstruc

; token map
TKM_HASHSIZE            equ         1000

                        struc       tokenmap
                            ; first tokeninit block
                            tkm_first:      resq    1
                            ; hash table
                            tkm_hash:       resq    TKM_HASHSIZE
                            ; reverse hash table
                            tkm_revhash:    resq    TKM_HASHSIZE
                        endstruc

                        section     .text

                        global      init_tokenizer,dump_tokenmap,tokenize
                        global      tok_getch,tok_putb,tok_putq,detok_putch
                        global      tok_dumplinebuf,detokenize
                        extern      xalloc,pb_putfmt,testtok
                        extern      uclineininit,ucgetcp,uclineoutinit,ucputcp
                        extern      tok_rdamp,tok_rdnum, detok_wrnum
                        extern      wcchar,iswspace,iswlower,towupper

; ---------------------------------------------------------------------------

                        ;     [rbp-0x08] - RBX backup
                        ;     [rbp-0x10] - R12 backup
                        ;     [rbp-0x18] - R13 backup
                        ;     [rbp-0x20] - R14 backup
                        ;     [rbp-0x28] - R15 backup
                        ;     [rbp-0x30] - next R13 value
init_tokenizer          enter       0x30,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14
                        mov         [rbp-0x28],r15
                        lea         rbx,[g_tokenmap]
                        lea         r12,[firstmapentry]
                        mov         [rbx+tkm_first],r12
                        ; clear hash table
                        cld                                 ; forward dir
                        lea         rdi,[rbx+tkm_hash]      ; target
                        mov         rcx,TKM_HASHSIZE        ; count
                        xor         rax,rax                 ; value
                        rep         stosq                   ; fill memory
                        lea         rdi,[rbx+tkm_revhash]   ; target
                        mov         rcx,TKM_HASHSIZE        ; count
                        rep         stosq                   ; fill memory
                        ; --- process next map entry --------------------------
                        ; r12 - map entry
.mapentry_loop          mov         r13,[r12+tme_block]
                        mov         r14,[r12+tme_blksize]
                        add         r14,r13
                        ; --- process next tokeninit entry --------------------
                        ; r13 - block pointer, r14 - end pointer
                        ; first, compute size of new entry to be allocated
.initblock_loop:        mov         al,tokendesc_size
                        add         al,[r13+ti_namelen]
                        add         al,[r13+ti_enclen]
                        movzx       rdi,al
                        ; allocate memory
                        call        xalloc
                        mov         r15,rax
                        ; r15 - token descriptor
                        xor         rax,rax
                        mov         [r15+td_nexthash],rax
                        mov         [r15+td_nextrev],rax
                        ; --- copy tokeninit to tokendesc ---------------------
                        ; prepare copying by setting direction to forward
                        cld
                        ; compute size of data to be copied
                        xor         rcx,rcx
                        mov         cl,tokeninit_size
                        add         cl,[r13+ti_namelen]
                        add         cl,[r13+ti_enclen]
                        ; compute next tokeninit pointer and remember it
                        lea         rax,[r13+rcx]
                        mov         [rbp-0x30],rax
                        ; source is the original init block
                        mov         rsi,r13
                        ; target is the new descriptor block
                        lea         rdi,[r15+td_namelen]
                        ; copy
                        rep         movsb
                        ; --- enter tokendesc into name hash table ------------
                        ; now, compute the hash value for the name
                        lea         rdi,[r15+tokendesc_size]
                        movzx       rsi,byte [r15+td_namelen]
                        call        computehash
                        ; get previous address in hash table that has the same
                        ; hash value
                        mov         rdx,[rbx+tkm_hash+rax*8]
                        ; store that in the next hash field
                        mov         [r15+td_nexthash],rdx
                        ; now set the new entry in the hash table
                        mov         [rbx+tkm_hash+rax*8],r15
                        ; --- enter tokendesc into encoding hash table --------
                        ; now, compute the "reverse" hash value for the encoding
                        lea         rdi,[r15+tokendesc_size]
                        ; the encoding bytes come right after the name
                        movzx       rax,byte [r15+td_namelen]
                        add         rdi,rax
                        ; get the length
                        movzx       rsi,byte [r15+td_enclen]
                        ; compute the "reverse" hash for the encoding
                        call        computehash
                        ; get previous address in "reverse" hash table that has
                        ; the same hash value
                        mov         rdx,[rbx+tkm_revhash+rax*8]
                        ; store that in the next rev field
                        mov         [r15+td_nextrev],rdx
                        ; now set the new entry in the hash table
                        mov         [rbx+tkm_revhash+rax*8],r15
                        ; --- proceed to next item ----------------------------
                        ; go to next init item (remembered earlier)
                        mov         r13,[rbp-0x30]
                        cmp         r13,r14
                        jb          .initblock_loop
                        ; done: get next map entry, if any
                        mov         r12,[r12+tme_next]
                        or          r12,r12
                        jnz         .mapentry_loop
                        ; complete
                        mov         r15,[rbp-0x28]
                        mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; rdi - name
                        ; rsi - name length
                        ;       [ebp-0x08] - RBX backup
computehash             enter       0x10,0
                        mov         [rbp-0x08],rbx
                        ; set forward direction
                        cld
                        ; swap rsi and rdi:
                        ; rsi -> name
                        ; rdi -> name length
                        xchg        rdi,rsi
                        ; load name length into counter
                        mov         rcx,rdi
                        ; preset some arbitrary values
                        mov         bx,0xf3a7
                        mov         dx,0x8492
                        ; clear some register parts
                        xor         ah,ah
                        xor         rbx,rbx
                        ; loop
                        ; load next byte
.nextbyte               lodsb
                        ; add to values
                        add         bx,ax
                        xor         dx,ax
                        sub         bx,dx
                        rol         bx,3
                        ror         dx,5
                        ; continue loop
                        loop        .nextbyte
                        ; finish
                        xor         ax,ax
                        xor         dx,bx
                        xchg        dx,ax
                        ; compute modulo of result with hash size
                        mov         bx,TKM_HASHSIZE
                        div         bx
                        movzx       rax,dx
                        ; done
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; [ebp-0x08] rbx backup

dump_tokenmap           enter       0x20,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        lea         rbx,[g_tokenmap]
                        ; rbx - tokenmap hash table
                        lea         rbx,[rbx+tkm_hash]
                        xor         r12,r12
                        ; r12 - index
                        ; print index "[nnnn]"
.nextindex              lea         rdi,[dtm_ixfmt]
                        mov         rsi,r12
                        xor         al,al
                        call        qword [pb_putfmt]
                        ; r13 - token descriptor list pointer
                        mov         r13,[rbx+r12*8]
                        or          r13,r13
                        jz          .noentry
                        ; print entry name
.printentry             lea         rdi,[dtm_namfmt]
                        movzx       rsi,byte [r13+td_namelen]
                        mov         rdx,rsi
                        lea         rcx,[r13+tokendesc_size]
                        xor         al,al
                        call        qword [pb_putfmt]
                        ; next entry with same hash value
                        mov         r13,[r13+td_nexthash]
                        or          r13,r13
                        jnz         .printentry
                        ; print line feed
.noentry                lea         rdi,[dtm_lf]
                        xor         al,al
                        call        qword [pb_putfmt]
                        ; go to next index
                        inc         r12
                        cmp         r12,TKM_HASHSIZE
                        jb          .nextindex
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; The main tokenizer routine.
                        ; NOTE that the input line gets replaced with the
                        ; idealized form to be used during tokenization.
                        ; The tokenizer returns the length of this line.
                        ;
                        ;
                        ; rdi - address
                        ; rsi - size of text, in bytes
                        ;
tokenize                enter       0x10,0
                        mov         [rbp-0x08],rbx

                        ; call preparation code
                        call        tok_prepare

                        cmp         qword [testtok],0
                        je          .skipdump

                        call        tok_dumplinebuf

.skipdump               lea         rdi,[linebuf]
                        mov         rsi,[linebuflen]
                        call        tok_main
                        mov         rbx,rax ; success? -1=true, 0=false

                        cmp         qword [testtok],0
                        je          .skipdump2

                        call        tok_dumptokbuf

.skipdump2              mov         rax,rbx
                        test        rax,rax
                        jz          .end

                        ; buffer maxed out?
                        mov         rax,[tokenpadptr]
                        cmp         rax,tokenpadend
                        jb          .ok

                        xor         rax,rax
                        jmp         .end

.ok                     mov         rax,rbx

.end                    mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; dump the token buffer (DEBUG utility)
tok_dumptokbuf          enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        lea         rbx,[tokenpad]
                        mov         r12,[tokenpadptr]
.dumploop               cmp         rbx,r12
                        jae         .end
                        lea         rdi,[tokdump_fmt]
                        movzx       rsi,byte [rbx]
                        xor         al,al
                        call        qword [pb_putfmt]
                        inc         rbx
                        jmp         .dumploop
.end                    lea         rdi,[tokdump_lf]
                        xor         al,al
                        call        qword [pb_putfmt]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; initializes the tokenization process
                        ; rdi - source text pointer
                        ; rsi - source text length
tok_init                enter       0,0
                        call        uclineininit
                        mov         qword [sourceputback],-1
                        lea         rax,[tokenpad]
                        mov         [tokenpadptr],rax
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; retrieve a character (code point) from the input
                        ; (first call tok_init() to initialize input stream)
                        ; if there was a put back character, retrieve it,
                        ; otherwise get a new one
tok_getch               enter       0,0
                        mov         rax,[sourceputback]
                        cmp         rax,-1
                        je          .skip
                        mov         qword [sourceputback],-1
                        jmp         .end
.skip                   call        ucgetcp
.end                    leave
                        ret

; ---------------------------------------------------------------------------

                        ; put token byte in rdi to token buffer
tok_putb                enter       0,0
                        mov         rax,[tokenpadptr]
                        cmp         rax,tokenpadend
                        jae         .end
                        xchg        rdi,rax
                        mov         [rdi],al
                        inc         rdi
                        mov         [tokenpadptr],rdi
.end                    leave
                        ret

; ---------------------------------------------------------------------------

                        ; put string in rdi to token buffer
                        ; rdi - string pointer
                        ; rsi - length, in bytes
tok_puts                enter       0,0
                        mov         rcx,rsi
                        mov         rsi,rdi
                        ; check if there's enough room to store it
                        mov         rdi,[tokenpadptr]
                        add         rdi,rcx
                        cmp         rdi,tokenpadend
                        jb          .copy
                        ; no: compute number of available bytes
                        mov         rcx,tokenpadend
                        sub         rcx,[tokenpadptr]
                        ; check if size is zero
.copy                   test        rcx,rcx
                        jz          .end
                        ; copy the string
                        cld
                        mov         rdi,[tokenpadptr]
                        rep         movsb
                        mov         [tokenpadptr],rdi
.end                    leave
                        ret

; ---------------------------------------------------------------------------

                        ; put token quadword in rdi to token buffer

tok_putq                enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         rbx,rdi
                        mov         r12,8

.putloop                rol         rbx,8
                        mov         rdi,rbx
                        and         rdi,0xff
                        call        tok_putb

                        dec         r12
                        jnz         .putloop

                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; put code point in rdi to detokenization buffer
detok_putch             enter       0,0
                        call        ucputcp
                        mov         [linebuflen],rax
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ;   tok_main() takes a text line that has been
                        ;   prepared by tok_prepare(). It does the following:
                        ;   - numbers are converted to 64-bit IEEE
                        ;     floating-point values and stored with a 01 prefix.
                        ;     &H introduces hexadecimal mode.
                        ;     &D (optional) introduces decimal mode.
                        ;     &O introduces octal mode.
                        ;     &B introduces binary mode.
                        ;     decimal digits are supported in all number bases.
                        ;     exponent is written either in E/G or P form
                        ;     (E/G uses b^n exponent written in selected number
                        ;     base, while P uses 2^n exponent
                        ;     written in decimal)
                        ;   - identifiers are stored with 02 <len> prefix.
                        ;   - keywords are stored with a 03/... prefix.
                        ;   - spaces are ignored.
                        ;
                        ; rdi - pointer to text
                        ; rsi - size of text, in bytes
                        ;
                        ; result:
                        ; rax - boolean result (-1 = ok, 0 = error)
                        ;
tok_main                enter       0x10,0
                        call        tok_init

                        ; tokenization loop
                        ; examine next character
.tokloop                call        tok_getch
                        cmp         rax,-1
                        je          .succeed

                        cmp         rax,' '     ; skip spaces
                        je          .tokloop

                        ; check character for the token class it belongs to
                        cmp         rax,'0'
                        jb          .notdigit
                        cmp         rax,'9'
                        ja          .notdigit

                        ; a digit: tokenize as base 10 number
                        mov         [sourceputback],rax
                        mov         rdi,10
                        call        tok_rdnum

                        ; numbers are stored with a 01 prefix, followed by the
                        ; number base (2/8/10/16), then followed by 8 bytes of
                        ; IEEE 64 bit floating-point. NOTE that tokenized form
                        ; uses network byte order (big endian).
                        mov         [rbp-0x08],rax
                        mov         rdi,0x01
                        call        tok_putb
                        mov         rdi,10
                        call        tok_putb
                        mov         rdi,[rbp-0x08]
                        call        tok_putq
                        ; done
                        jmp         .tokloop

                        ; & ampersand
.notdigit               cmp         rax,'&'
                        jne         .notamp

                        ; number with specified number base
                        call        tok_rdamp
                        jmp         .tokloop

                        ; "..." string literals
.notamp                 cmp         rax,'"'
                        jne         .notquote

                        ; quoted string literal
                        call        tok_strlit
                        jmp         .tokloop

                        ; check for operators: <, <=, <>, >, >=, =
                        ; operators are encoded as 02, followed by code
.notquote               cmp         rax,'<'
                        jne         .notless

                        call        tok_getch
                        cmp         rax,-1
                        je          .lessend
                        cmp         rax,'='
                        je          .lesseq
                        cmp         rax,'>'
                        je          .noteq
                        mov         [sourceputback],rax

.lessend                mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x00    ; '<'
                        call        tok_putb
                        jmp         .tokloop

.lesseq                 mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x01    ; '<='
                        call        tok_putb
                        jmp         .tokloop

.noteq                  mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x02    ; '<>'
                        call        tok_putb
                        jmp         .tokloop

.notless                cmp         rax,'>'
                        jne         .notgreater

                        call        tok_getch
                        cmp         rax,-1
                        je          .greaterend
                        cmp         rax,'='
                        je          .greatereq
                        cmp         rax,'<'
                        je          .noteq      ; '><', same as '<>'
                        mov         [sourceputback],rax

.greaterend             mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x03    ; '>'
                        call        tok_putb
                        jmp         .tokloop

.greatereq              mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x04    ; '>='
                        call        tok_putb
                        jmp         .tokloop

.notgreater             cmp         rax,'='
                        jne         .notequal

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x05    ; '='
                        call        tok_putb
                        jmp         .tokloop

                        ; more operators: (, ), ,, ;, :

.notequal               cmp         rax,'('
                        jne         .notlparen

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x06    ; '('
                        call        tok_putb
                        jmp         .tokloop

.notlparen              cmp         rax,')'
                        jne         .notrparen

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x07    ; ')'
                        call        tok_putb
                        jmp         .tokloop

.notrparen              cmp         rax,','
                        jne         .notcomma

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x08    ; ','
                        call        tok_putb
                        jmp         .tokloop

.notcomma               cmp         rax,';'
                        jne         .notsemicolon

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x09    ; ';'
                        call        tok_putb
                        jmp         .tokloop

.notsemicolon           cmp         rax,':'
                        jne         .notcolon

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0a    ; ':'
                        call        tok_putb
                        jmp         .tokloop

                        ; arithmetic operators: +, -, *, **, /, ^
.notcolon               cmp         rax,'+'
                        jne         .notplus

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0b    ; '+'
                        call        tok_putb
                        jmp         .tokloop

.notplus                cmp         rax,'-'
                        jne         .notminus

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0c    ; '-'
                        call        tok_putb
                        jmp         .tokloop

.notminus               cmp         rax,'*'
                        jne         .notasterisk

                        call        tok_getch
                        cmp         rax,-1
                        je          .asteriskend
                        cmp         rax,'*'
                        je          .power      ; '**', same as '^'
                        mov         [sourceputback],rax

.asteriskend            mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0d    ; '*'
                        call        tok_putb
                        jmp         .tokloop

.notasterisk            cmp         rax,'/'
                        jne         .notslash

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0e    ; '/'
                        call        tok_putb
                        jmp         .tokloop

.notslash               cmp         rax,'^'
                        jne         .notpower

.power                  mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x0f    ; '^'
                        call        tok_putb
                        jmp         .tokloop

.notpower               cmp         rax,'#'
                        jne         .notlattice

                        mov         rdi,0x02
                        call        tok_putb
                        mov         rdi,0x11    ; '#'
                        call        tok_putb
                        jmp         .tokloop

                        ; everything else is regarded as an identifier
.notlattice             mov         rdi,rax
                        call        tok_ident
                        jmp         .tokloop

.succeed                mov         rax,-1
                        ; store a terminating NUL token to signify end of line.
.end                    mov         rdi,[tokenpadptr]
                        mov         byte [rdi],0
                        leave
                        ret

.fail                   xor         rax,rax
                        jmp         .end

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ; tok_strlit() simply tokenizes a text string literal.
                        ; It may contain any Unicode code point, but its maximum
                        ; size is limited by the STRLITBUFSIZE constant. Also,
                        ; STRLITBUFSIZE cannot be longer than 65535 bytes, since
                        ; string literals are encoded as FF, followed by two
                        ; bytes of length, in network byte order, followed by
                        ; the text string in UTF-8 format.

tok_strlit              enter       0x10,0

                        lea         rdi,[strlitbuf]
                        mov         rsi,strlitbufsize
                        call        uclineoutinit

.fetchloop              call        tok_getch
                        cmp         rax,-1
                        je          .end
                        cmp         rax,'"'
                        je          .end

                        mov         rdi,rax
                        call        ucputcp
                        mov         [rbp-0x08],rax

                        jmp         .fetchloop

                        ; string literals are encoded as 0xFF followed by
                        ; a two-byte length and then the actual string data
                        ; (NOT NUL terminated)

.end                    mov         rdi,0xff
                        call        tok_putb
                        movzx       rdi,byte [rbp-0x07]
                        call        tok_putb
                        movzx       rdi,byte [rbp-0x08]
                        call        tok_putb
                        lea         rdi,[strlitbuf]
                        mov         rsi,[rbp-0x08]
                        call        tok_puts

.storeend               leave
                        ret

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ;
                        ; tok_ident() tokenizes identifiers, keywords, etc.
                        ; It may contain any Unicode code point, but its maximum
                        ; size is limited by the IDENTBUFSIZE constant. Also,
                        ; IDENTBUFSIZE cannot be longer than 65535 bytes, since
                        ; identifiers are encoded as FE, followed by two
                        ; bytes of length, in network byte order, followed by
                        ; the name of the identifier in UTF-8 format.
                        ;
                        ; If an identifier turns out to be a builtin keyword,
                        ; the keyword's byte sequence is emitted instead.
                        ;
                        ; parameters:
                        ;   rdi - initial character
                        ;
                        ; local variables:
                        ;   [rbp-0x08]  name length
                        ;   [rbp-0x10]  RDI backup (initial code point)
                        ;   [rbp-0x18]  RBX backup

tok_ident               enter       0x30,0
                        mov         [rbp-0x10],rdi
                        mov         [rbp-0x18],rbx
                        mov         [rbp-0x20],r12
                        mov         byte [rbp-0x30],0 ; type field

                        lea         rdi,[identbuf]
                        mov         rsi,identbufsize
                        call        uclineoutinit

                        mov         rdi,[rbp-0x10]
.storechar              call        ucputcp
                        mov         [rbp-0x08],rax

                        call        tok_getch
                        cmp         rax,-1
                        je          .endread

                        ; a space or operator character
                        ; terminates the identifier (exclusively)
                        cmp         rax,' '
                        je          .terminate
                        cmp         rax,'"'
                        je          .terminate
                        cmp         rax,'<'
                        je          .terminate
                        cmp         rax,'='
                        je          .terminate
                        cmp         rax,'>'
                        je          .terminate
                        cmp         rax,'*'
                        je          .terminate
                        cmp         rax,'/'
                        je          .terminate
                        cmp         rax,'+'
                        je          .terminate
                        cmp         rax,'-'
                        je          .terminate
                        cmp         rax,'^'
                        je          .terminate
                        cmp         rax,','
                        je          .terminate
                        cmp         rax,';'
                        je          .terminate
                        cmp         rax,':'
                        je          .terminate
                        cmp         rax,')'
                        je          .terminate

                        jmp         .continue

.terminate              mov         [sourceputback],rax
                        jmp         .endread

                        ; a sigil character terminates the identifier
                        ; (inclusively)
.continue               cmp         rax,'$'
                        je          .strsigil
                        cmp         rax,'%'
                        je          .sigil
                        cmp         rax,'&'
                        je          .sigil
                        cmp         rax,'!'
                        je          .sigil
                        cmp         rax,'#'
                        je          .sigil
                        cmp         rax,'('
                        je          .lparen

                        mov         rdi,rax
                        jmp         .storechar

                        ; we have a string sigil '$': set flag in type field
.strsigil               or          byte [rbp-0x30],1

                        ; we have a sigil: store the character
.sigil                  mov         rdi,rax
                        call        ucputcp
                        mov         [rbp-0x08],rax

                        ; now, check for left parenthesis (function/array
                        ; application)
                        call        tok_getch
                        cmp         rax,-1
                        je          .endread

                        cmp         rax,'('
                        jne         .notlparen

                        ; we have a left parenthesis: store it & finish
.lparen                 mov         rdi,rax
                        call        ucputcp
                        mov         [rbp-0x08],rax
                        or          byte [rbp-0x30],2 ; func flag in type field
                        jmp         .endread

                        ; not a left parenthesis: put codepoint back
.notlparen              mov         [sourceputback],rax

                        ; after reading an identifier, look it up in the keyword
                        ; hash table to see if it's a keyword
                        ; now, compute the hash value for the name
.endread                lea         rdi,[identbuf]
                        mov         rsi,[rbp-0x08]
                        call        computehash
                        ; get first address in hash table that has the same
                        ; hash value
                        lea         rbx,[g_tokenmap]
                        mov         rdx,[rbx+tkm_hash+rax*8]    ; tokendesc ptr
.nextentry              test        rdx,rdx
                        jz          .notfound
                        ; check name length; skip if not equal
                        movzx       rcx,byte [rdx+td_namelen]
                        cmp         rcx,[rbp-0x08]
                        je          .samelength
                        mov         rdx,[rdx+td_nexthash]
                        jmp         .nextentry
                        ; if same length, compare names
.samelength             lea         rsi,[rdx+tokendesc_size]
                        lea         rdi,[identbuf]
                        cld
                        repe        cmpsb
                        je          .found
                        mov         rdx,[rdx+td_nexthash]
                        jmp         .nextentry
                        ; after successful comparison, RSI should point to
                        ; the token bytes to be emitted
.found                  mov         rbx,rsi
                        movzx       r12,byte [rdx+td_enclen]
.storeloop              movzx       rdi,byte [rbx]
                        call        tok_putb
                        inc         rbx
                        dec         r12
                        jnz         .storeloop
                        jmp         .storeend

                        ; identifiers are encoded as 0xFE followed by
                        ; a type field, a two-byte length and then the
                        ; actual name (NOT NUL terminated)
.notfound               mov         rdi,0xfe
                        call        tok_putb
                        movzx       rdi,byte [rbp-0x30]
                        call        tok_putb
                        movzx       rdi,byte [rbp-0x07]
                        call        tok_putb
                        movzx       rdi,byte [rbp-0x08]
                        call        tok_putb
                        lea         rdi,[identbuf]
                        mov         rsi,[rbp-0x08]
                        call        tok_puts

.storeend               mov         r12,[rbp-0x20]
                        mov         rbx,[rbp-0x18]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ;   tok_dumplinebuf() outputs the linebuffer for
                        ;   debugging purposes

tok_dumplinebuf         enter       0,0
                        lea         rdi,[dlb_fmt]
                        mov         rsi,[linebuflen]
                        mov         rdx,rsi
                        lea         rcx,[linebuf]
                        xor         al,al
                        call        qword [pb_putfmt]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ;   tok_prepare() takes a text line. It goes over all
                        ;   characters in the line, and reduces whitespace to
                        ;   single spaces, except within quotes ("..."). It also
                        ;   converts all letters to upper case, again, except
                        ;   within quotes.
                        ;
                        ; rdi - address of text line
                        ; rsi - size of text, in bytes
tok_prepare             enter       0,0
                        call        uclineininit
                        lea         rdi,[linebuf]
                        mov         rsi,linebufsize
                        xor         rax,rax
                        mov         [linebuflen],rax
                        call        uclineoutinit
.getcp                  call        ucgetcp
.checkcp                cmp         rax,-1
                        je          .end
                        cmp         rax,'"'
                        je          .quotes
                        mov         rdi,rax
                        call        iswspace
                        test        eax,eax
                        jnz         .spaces
                        xor         rdi,rdi
                        mov         edi,dword [wcchar]
                        call        iswlower
                        jnz         .lcase
                        xor         rdi,rdi
                        mov         edi,dword [wcchar]
.storecp                call        ucputcp
                        mov         [linebuflen],rax
                        jmp         .getcp
.end                    leave
                        ret
.quotes                 mov         rdi,rax ; store initial '"'
                        call        ucputcp
                        mov         [linebuflen],rax
.qunext                 call        ucgetcp
                        cmp         rax,-1  ; end?
                        je          .end
                        cmp         rax,'"' ; terminating '"'
                        je          .quend
                        mov         rdi,rax
                        call        ucputcp ; transfer all others
                        mov         [linebuflen],rax
                        jmp         .qunext
.quend                  mov         rdi,rax
                        call        ucputcp ; store terminating '"'
                        mov         [linebuflen],rax
                        jmp         .getcp  ; continue normally
.spaces                 call        ucgetcp
                        cmp         rax,-1  ; end?
                        je          .end
                        mov         rdi,rax
                        call        iswspace
                        test        eax,eax
                        jnz         .spaces
                        ; not a space: store ' ' character
                        mov         rdi,' '
                        call        ucputcp
                        mov         [linebuflen],rax
                        ; get character last read
                        xor         rax,rax
                        mov         eax,dword [wcchar]
                        jmp         .checkcp
.lcase                  xor         rdi,rdi
                        mov         edi,dword [wcchar]
                        call        towupper
                        xor         rdi,rdi
                        mov         edi,eax
                        jmp         .storecp

; ---------------------------------------------------------------------------

                        ; SYNOPSIS:
                        ; Detokenization decodes a tokenized line back into
                        ; the line buffer.
                        ;
                        ; parameters:
                        ;   rdi - address
                        ;   rsi - size of encoded text, in bytes
                        ;   rdx - flags
                        ;
                        ; TODO: support syntax highlighting through flags
                        ;
                        ; local variables:
                        ;   [rbp-0x08]  RBX backup
                        ;   [rbp-0x10]  R12 backup
                        ;   [rbp-0x18]  RDI backup (token buffer address)
                        ;   [rbp-0x20]  RSI backup (token buffer size)
                        ;   [rbp-0x28]  RDX backup (flags)
                        ;
detokenize              enter       0x40,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],rdi
                        mov         [rbp-0x20],rsi
                        mov         [rbp-0x28],rdx
                        mov         [rbp-0x30],r13
                        mov         [rbp-0x38],r14

                        lea         rdi,[linebuf]
                        mov         rsi,linebufsize
                        xor         rax,rax
                        mov         [linebuflen],rax
                        call        uclineoutinit

                        mov         rbx,[rbp-0x18]
                        mov         r12,[rbp-0x20]

.detokloop              test        r12,r12
                        jle         .detokend

                        mov         al,[rbx]
                        test        al,al
                        jz          .detokend

                        cmp         al,0x01
                        jne         .notnumber
                        mov         al,[rbx+1]
                        cmp         al,10
                        je          .knownbase
                        cmp         al,16
                        je          .knownbase
                        cmp         al,8
                        je          .knownbase
                        cmp         al,2
                        je          .knownbase
                        ; unknown base?
                        jmp         .detokend
                        ; read number
.knownbase              movzx       rsi,al
                        mov         al,[rbx+2]
                        shl         rax,8
                        mov         al,[rbx+3]
                        shl         rax,8
                        mov         al,[rbx+4]
                        shl         rax,8
                        mov         al,[rbx+5]
                        shl         rax,8
                        mov         al,[rbx+6]
                        shl         rax,8
                        mov         al,[rbx+7]
                        shl         rax,8
                        mov         al,[rbx+8]
                        shl         rax,8
                        mov         al,[rbx+9]
                        mov         rdi,rax
                        mov         r13,rdi
                        mov         r14,rsi
                        ; output single space as separator
                        mov         rdi,' '
                        call        detok_putch
                        ; output &H,&O or &B for hex/oct/bin
                        cmp         r14,16
                        jne         .nothex
                        mov         rdi,'&'
                        call        detok_putch
                        mov         rdi,'H'
                        call        detok_putch
                        jmp         .outputnumber
.nothex                 cmp         r14,8
                        jne         .notoct
                        mov         rdi,'&'
                        call        detok_putch
                        mov         rdi,'O'
                        call        detok_putch
                        jmp         .outputnumber
.notoct                 cmp         r14,2
                        jne         .outputnumber
                        mov         rdi,'&'
                        call        detok_putch
                        mov         rdi,'B'
                        call        detok_putch
                        ; detokenize number
.outputnumber           mov         rdi,r13
                        mov         rsi,r14
                        call        detok_wrnum
                        ; go to next token
                        add         rbx,10
                        sub         r12,10
                        jmp         .detokloop

.notnumber              cmp         al,0xff
                        jne         .notstrlit

                        ; string literal

                        mov         rdi,'"'
                        call        detok_putch

                        ; get length
                        mov         ah,[rbx+1]
                        mov         al,[rbx+2]
                        movzx       r13,ax
                        add         rbx,3
                        sub         r12,3

                        ; initialize unicode input
                        mov         rdi,rbx
                        mov         rsi,r13
                        call        uclineininit

.strlitloop             call        ucgetcp
                        cmp         rax,-1
                        je          .strlitend
                        mov         rdi,rax
                        call        detok_putch
                        jnz         .strlitloop

                        ; finish string literal
.strlitend              add         rbx,r13
                        sub         r12,r13
                        mov         rdi,'"'
                        call        detok_putch
                        jmp         .detokloop

.notstrlit              cmp         al,0xfe
                        jne         .notident

                        ; get length
                        mov         ah,[rbx+2]
                        mov         al,[rbx+3]
                        movzx       r13,ax
                        add         rbx,4
                        sub         r12,3

                        ; output single space as separator
                        mov         rdi,' '
                        call        detok_putch

                        ; initialize unicode input
                        mov         rdi,rbx
                        mov         rsi,r13
                        call        uclineininit

.identloop              call        ucgetcp
                        cmp         rax,-1
                        je          .identend
                        mov         rdi,rax
                        call        detok_putch
                        jnz         .identloop

                        ; finish identifier
.identend               add         rbx,r13
                        sub         r12,r13
                        jmp         .detokloop

.notident               cmp         al,0x02
                        jne         .notoperator

                        mov         al,[rbx+1]
                        add         rbx,2
                        sub         r12,2
                        mov         r13,rax

                        cmp         al,0x08
                        je          .comma
                        cmp         al,0x09
                        je          .semicolon

                        ; except before comma and semicolon, output blank
                        ; character first
                        mov         rdi,' '
                        call        detok_putch
                        mov         rax,r13

                        ; then, output operator character(s)
                        cmp         al,0x00
                        je          .lower
                        cmp         al,0x01
                        je          .lowerorequal
                        cmp         al,0x02
                        je          .notequal
                        cmp         al,0x03
                        je          .greater
                        cmp         al,0x04
                        je          .greaterorequal
                        cmp         al,0x05
                        je          .equal
                        cmp         al,0x06
                        je          .lparen
                        cmp         al,0x07
                        je          .rparen
                        cmp         al,0x0a
                        je          .colon
                        cmp         al,0x0b
                        je          .plus
                        cmp         al,0x0c
                        je          .minus
                        cmp         al,0x0d
                        je          .asterisk
                        cmp         al,0x0e
                        je          .slash
                        cmp         al,0x0f
                        je          .power
                        cmp         al,0x10
                        je          .ampersand
                        cmp         al,0x11
                        je          .lattice

                        ; unknown
                        jmp         .detokend

.lower                  mov         rdi,'<'
                        call        detok_putch
                        jmp         .detokloop

.lowerorequal           mov         rdi,'<'
                        call        detok_putch

.equal                  mov         rdi,'='
                        call        detok_putch
                        jmp         .detokloop

.notequal               mov         rdi,'<'
                        call        detok_putch

.greater                mov         rdi,'>'
                        call        detok_putch
                        jmp         .detokloop

.greaterorequal         mov         rdi,'>'
                        call        detok_putch
                        mov         rdi,'='
                        call        detok_putch
                        jmp         .detokloop

.lparen                 mov         rdi,'('
                        call        detok_putch
                        jmp         .detokloop

.rparen                 mov         rdi,')'
                        call        detok_putch
                        jmp         .detokloop

.comma                  mov         rdi,','
                        call        detok_putch
                        jmp         .detokloop

.semicolon              mov         rdi,';'
                        call        detok_putch
                        jmp         .detokloop

.colon                  mov         rdi,':'
                        call        detok_putch
                        jmp         .detokloop

.plus                   mov         rdi,'+'
                        call        detok_putch
                        jmp         .detokloop

.minus                  mov         rdi,'-'
                        call        detok_putch
                        jmp         .detokloop

.asterisk               mov         rdi,'*'
                        call        detok_putch
                        jmp         .detokloop

.slash                  mov         rdi,'/'
                        call        detok_putch
                        jmp         .detokloop

.power                  mov         rdi,'^'
                        call        detok_putch
                        jmp         .detokloop

.ampersand              mov         rdi,'&'
                        call        detok_putch
                        jmp         .detokloop

.lattice                mov         rdi,'#'
                        call        detok_putch
                        jmp         .detokloop

                        ; everything else could be a keyword
                        ; look the following two bytes up in the reverse hash
.notoperator            mov         rdi,rbx
                        mov         rsi,2
                        call        computehash
                        ; get first address in hash table that has the same
                        ; hash value
                        lea         r13,[g_tokenmap]
                        mov         rdx,[r13+tkm_revhash+rax*8] ; tokendesc ptr
.nextentry              test        rdx,rdx
                        jz          .notfound
                        ; check encoding length; skip if not equal
                        movzx       rcx,byte [rdx+td_enclen]
                        cmp         rcx,2
                        je          .samelength
                        mov         rdx,[rdx+td_nextrev]
                        jmp         .nextentry
                        ; if same length, compare encodings
.samelength             lea         rsi,[rdx+tokendesc_size]
                        movzx       rax,byte [rdx+td_namelen]
                        add         rsi,rax
                        mov         rdi,rbx
                        cld
                        repe        cmpsb
                        je          .found
                        mov         rdx,[rdx+td_nextrev]
                        jmp         .nextentry
                        ; after successful comparison, RSI should point to
                        ; the token name to be emitted
.found                  lea         r13,[rdx+tokendesc_size]
                        movzx       r14,byte [rdx+td_namelen]
                        mov         rdi,' '
                        call        detok_putch
.storeloop              movzx       rdi,byte [r13]
                        call        detok_putch
                        inc         r13
                        dec         r14
                        jnz         .storeloop
                        add         rbx,2
                        sub         r12,2
                        jmp         .detokloop
.notfound:
.detokend               mov         r14,[rbp-0x38]
                        mov         r13,[rbp-0x30]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret

; ---------------------------------------------------------------------------

; read-only data section

                        section     .rodata

tokentbl:
                        %include    "tokendef.inc"

tokentbl_size           equ         $-tokentbl
tokentbl_name           db          7,"default"

; ---------------------------------------------------------------------------

dtm_ixfmt               db          "[%04u]",0
dtm_namfmt              db          " %-*.*s",0
dtm_lf                  db          10,0

dlb_fmt                 db          "line buf: <<%-*.*s>>",10,0

tokdump_fmt             db          " %02X",0
tokdump_lf              db          10,0

                        align       8,db 0

; ---------------------------------------------------------------------------

; TLS data section
                        section     .data

firstmapentry           dq          0
                        dq          tokentbl_name
                        dq          tokentbl
                        dq          tokentbl_size

; ---------------------------------------------------------------------------

; TLS block-structured storage section

                        section     .bss
                        global      sourceputback,tokenpad,tokenpadptr


g_tokenmap              resq        tokenmap_size/8
linebuf                 resq        LINEBUF_BYTES/8
linebufsize             equ         $-linebuf
linebuflen              resq        1
sourceputback           resq        1
tokenpad                resq        TOKENPAD_BYTES/8
tokenpadsize            equ         $-tokenpad
tokenpadend             equ         $-1
tokenpadptr             resq        1
identbuf                resq        IDENTBUF_BYTES/8
identbufsize            equ         $-identbuf
strlitbuf               resq        STRLITBUF_BYTES/8
strlitbufsize           equ         $-strlitbuf

; ---------------------------------------------------------------------------
