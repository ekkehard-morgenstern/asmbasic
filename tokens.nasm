

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

TOKENPAD_BYTES          equ         49152
DIGITBUF_BYTES          equ         512
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

                        global      init_tokenizer,dump_tokenmap
                        extern      xalloc,printf

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
                        call        printf
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
                        call        printf
                        ; next entry with same hash value
                        mov         r13,[r13+td_nexthash]
                        or          r13,r13
                        jnz         .printentry
                        ; print line feed
.noentry                lea         rdi,[dtm_lf]
                        xor         al,al
                        call        printf
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
                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - size of text, in bytes
                        ;     [rbp-0x18] - RBX backup
                        ;
                        ; output: rax - length of cleaned up input
tokenize                enter       0x20,0
                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi
                        ; call preparation code
                        call        tok_prepare
                        ; store new length
                        mov         [rbp-0x10],rax

                        ; return length of idealized input
                        mov         rax,[rbp-0x10]
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; initializes the tokenization process
                        ; rdi - source text pointer
                        ; rsi - source text length
tok_init                enter       0,0
                        mov         [sourceptr],rdi
                        add         rsi,rdi
                        mov         [sourceend],rsi
                        lea         rdi,[g_tokenpad]
                        mov         [tokenptr],rdi
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; read a character from the input stream
                        ; result:
                        ;   rax - character or -1 for end
tok_rdch                enter       0,0
                        mov         rsi,[sourceptr]
                        cmp         rsi,[sourceend]
                        jae         .atend
                        movzx       rax,byte [rsi]
                        inc         rsi
                        mov         [sourceptr],rsi
.term                   mov         [sourcechr],rax
                        leave
                        ret
.atend                  xor         rax,rax
                        dec         rax
                        jmp         .term

; ---------------------------------------------------------------------------

                        ; read a unicode code point (utf-8 encoded)
                        ; from the input stream
                        ; result:
                        ;   rax - code point or -1 for end
tok_rucp                enter 0,0

.nextch                 call        tok_rdch
                        cmp         rax,-1
                        je          .term

                        ; check for 1-byte encoding
                        test        al,0x80     ; msb set?
                        jz          .term       ; nope, regular char

                        ; check for 2-byte encoding
                        mov         dl,al
                        and         dl,0xe0     ; %110xxxxx ?
                        cmp         dl,0xc0
                        je          .twobyte

                        ; check for 3-byte encoding
                        mov         dl,al
                        and         dl,0xf0     ; %1110xxxx ?
                        cmp         dl,0xe0
                        je          .threebyte

                        ; check for 4-byte encoding
                        mov         dl,al
                        and         dl,0xf8     ; %11110xxx ?
                        cmp         dl,0xf0
                        je          .fourbyte

                        ; not recognized
                        jmp         .nextch

.term                   mov         [sourceucp],rax

.end                    leave
                        ret

                        ; %110xxxxx %10xxxxxx
.twobyte                mov         dl,al
                        and         dl,0x1f
                        movzx       rax,dl
                        mov         [sourceucp],rax
                        jmp         .lastbyte

                        ; %1110xxxx %10xxxxxx %10xxxxxx
.threebyte              mov         dl,al
                        and         dl,0x0f
                        movzx       rax,dl
                        mov         [sourceucp],rax
                        jmp         .secondtolast

                        ; %11110xxx %10xxxxxx %10xxxxxx %10xxxxxx
.fourbyte               mov         dl,al
                        and         dl,0x07
                        movzx       rax,dl
                        mov         [sourceucp],rax

.thirdtolast            call        tok_rdch
                        cmp         rax,-1
                        je          .term
                        mov         dl,al
                        and         dl,0xc0     ; %10xxxxxx ?
                        cmp         dl,0x80
                        jne         .term
                        and         al,0x3f
                        shl         qword [sourceucp],6
                        or          [sourceucp],al

.secondtolast           call        tok_rdch
                        cmp         rax,-1
                        je          .term
                        mov         dl,al
                        and         dl,0xc0     ; %10xxxxxx ?
                        cmp         dl,0x80
                        jne         .term
                        and         al,0x3f
                        shl         qword [sourceucp],6
                        or          [sourceucp],al

.lastbyte               call        tok_rdch
                        cmp         rax,-1
                        je          .term
                        mov         dl,al
                        and         dl,0xc0     ; %10xxxxxx ?
                        cmp         dl,0x80
                        jne         .term
                        and         al,0x3f
                        shl         qword [sourceucp],6
                        or          [sourceucp],al

                        mov         rax,[sourceucp]
                        jmp         .end

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
                        ;     The digits are stored into a either a bit pattern
                        ;     (hex/oct/bin) or a BCD pattern (dec). The location
                        ;     or absence of the decimal point is noted, as is
                        ;     the value of the exponent, and the number of
                        ;     digits. Then the floating-point value is
                        ;     constructed.
                        ;   - identifiers are stored with 02 <len> prefix.
                        ;   - keywords are stored with a 03/... prefix.
                        ;   - spaces are ignored.
                        ;
                        ; rdi - pointer to text
                        ; rsi - size of text, in bytes
                        ;
tok_main                enter       0,0
                        call        tok_init



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
                        ; set r9 to the beginning of input (save for later)
                        mov         r9,rdi
                        ; compute r8 - end of input pointer
                        mov         r8,rsi
                        add         r8,rdi
                        ; make rsi (source) point to the same location as
                        ; rdi (target)
                        mov         rsi,rdi
                        ; clear direction flag (forward)
                        cld
                        ; loop body: check against end pointer first
.scanner                cmp         rsi,r8
                        jae         .scanend
                        ; load a byte
                        lodsb
                        ; if it's a space or tab, jump to space eliminator
                        cmp         al,0x20
                        je          .scanspc
                        cmp         al,0x09
                        je          .scanspc
                        ; if it's a double quote character, ", jump to
                        ; double quote handler
                        cmp         al,0x22
                        je          .dblquot
                        ; check if it's a lower case letter
                        cmp         al,0x61     ; 'a'
                        jb          .noletter
                        cmp         al,0x7a     ; 'z'
                        ja          .noletter
                        ; it is a lowercase letter: turn to upper case
                        xor         al,0x20
                        ; store character
.noletter               stosb
                        ; continue loop
                        jmp         .scanner
                        ; at the end, compute the new size and return it
.scanend                mov         rax,rdi
                        sub         rax,r9
                        leave
                        ret
                        ; space scanner
.scanspc                cmp         rsi,r8      ; beyond input?
                        jae         .spcend
                        ; load next byte
                        lodsb
                        cmp         al,0x20
                        je          .scanspc
                        cmp         al,0x09
                        je          .scanspc
                        ; not a space: backpedal
                        dec         rsi
                        ; end of whitespace: store a space
.spcend                 mov         al,0x20
                        stosb
                        ; resume with normal operation
                        jmp         .scanner
                        ; double quote handler
                        ; store it
.dblquot                stosb
                        ; check for end
                        cmp         rsi,r8
                        jae         .quotend
                        ; load next byte
                        lodsb
                        ; if it's not a double quote, keep copying
                        cmp         al,0x22
                        jne         .dblquot
                        ; store closing double quote
                        stosb
                        ; done, jump back to scanner
.quotend                jmp         .scanner

; ---------------------------------------------------------------------------

                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - size of encoded text, in bytes
                        ;     [rbp-0x18] - RBX backup
detokenize              enter       0,0
                        leave
                        ret

; ---------------------------------------------------------------------------

; read-only data section

                        section     .rodata

tokentbl                db          4,2,"ABS(",0x03,0x00
                        db          5,2,"AFTER",0x03,0x01
                        db          5,2,"AGAIN",0x03,0x02
                        db          3,2,"AND",0x03,0x03
                        db          2,2,"AS",0x03,0x04
                        db          4,2,"ASC(",0x03,0x05
                        db          3,2,"ASL",0x03,0x06
                        db          3,2,"ASR",0x03,0x07
                        db          5,2,"ATAN(",0x03,0x08
                        db          4,2,"ATN(",0x03,0x09
                        db          4,2,"AUTO",0x03,0x0a
                        db          5,2,"BIN$(",0x03,0x0b
                        db          3,2,"BRK",0x03,0x0c
                        db          4,2,"CALL",0x03,0x0d
                        db          7,2,"CATALOG",0x03,0x0e
                        db          5,2,"CEIL(",0x03,0x0f
                        db          5,2,"CHAIN",0x03,0x10
                        db          5,2,"CLEAR",0x03,0x11
                        db          5,2,"CLOSE",0x03,0x12
                        db          3,2,"CLS",0x03,0x13
                        db          4,2,"CONT",0x03,0x14
                        db          4,2,"COS(",0x03,0x15
                        db          5,2,"DATE$",0x03,0x16
                        db          9,2,"DATETIME$",0x03,0x17
                        db          5,2,"DEC$(",0x03,0x18
                        db          3,2,"DEF",0x03,0x19
                        db          6,2,"DELETE",0x03,0x1a
                        db          3,2,"DIM",0x03,0x1b
                        db          2,2,"DO",0x03,0x1c
                        db          4,2,"DOWN",0x03,0x1d
                        db          6,2,"DOWNTO",0x03,0x1e
                        db          7,2,"DYNAMIC",0x03,0x1f
                        db          4,2,"EACH",0x03,0x20
                        db          4,2,"EDIT",0x03,0x21
                        db          4,2,"ELSE",0x03,0x22
                        db          3,2,"END",0x03,0x23
                        db          3,2,"EQV",0x03,0x24
                        db          5,2,"ERASE",0x03,0x25
                        db          3,2,"ERL",0x03,0x26
                        db          4,2,"ERR$",0x03,0x27
                        db          5,2,"ERROR",0x03,0x28
                        db          4,2,"EVER",0x03,0x29
                        db          5,2,"EVERY",0x03,0x2a
                        db          4,2,"EXIT",0x03,0x2b
                        db          4,2,"EXP(",0x03,0x2c
                        db          5,2,"FILES",0x03,0x2d
                        db          6,2,"FLOOR(",0x03,0x2e
                        db          2,2,"FN",0x03,0x2f
                        db          3,2,"FOR",0x03,0x30
                        db          7,2,"FOREACH",0x03,0x31
                        db          7,2,"FOREVER",0x03,0x32
                        db          4,2,"FUNC",0x03,0x33
                        db          8,2,"FUNCTION",0x03,0x34
                        db          3,2,"GET",0x03,0x35
                        db          2,2,"GO",0x03,0x36
                        db          5,2,"GOSUB",0x03,0x37
                        db          4,2,"GOTO",0x03,0x38
                        db          5,2,"HEX$(",0x03,0x39
                        db          6,2,"HTAB$(",0x03,0x3a
                        db          2,2,"IF",0x03,0x3b
                        db          3,2,"IMP",0x03,0x3c
                        db          5,2,"INPUT",0x03,0x3d
                        db          4,2,"INT(",0x03,0x3e
                        db          7,2,"ITERATE",0x03,0x3f
                        db          5,2,"LEAVE",0x03,0x40
                        db          6,2,"LEFT$(",0x03,0x41
                        db          3,2,"LET",0x03,0x42
                        db          3,2,"LG(",0x03,0x43
                        db          4,2,"LINE",0x03,0x44
                        db          4,2,"LIST",0x03,0x45
                        db          3,2,"LN(",0x03,0x46
                        db          4,2,"LOAD",0x03,0x47
                        db          6,2,"LOCATE",0x03,0x48
                        db          6,2,"LOG10(",0x03,0x49
                        db          5,2,"LOG2(",0x03,0x4a
                        db          5,2,"LOGN(",0x03,0x4b
                        db          4,2,"LOOP",0x03,0x4c
                        db          5,2,"MERGE",0x03,0x4d
                        db          5,2,"MID$(",0x03,0x4e
                        db          4,2,"NAND",0x03,0x4f
                        db          4,2,"NEQV",0x03,0x50
                        db          3,2,"NEW",0x03,0x51
                        db          4,2,"NEXT",0x03,0x52
                        db          4,2,"NIMP",0x03,0x53
                        db          3,2,"NOR",0x03,0x54
                        db          3,2,"NOT",0x03,0x55
                        db          5,2,"OCT$(",0x03,0x56
                        db          3,2,"OFF",0x03,0x57
                        db          3,2,"OLD",0x03,0x58
                        db          2,2,"ON",0x03,0x59
                        db          4,2,"OPEN",0x03,0x5a
                        db          6,2,"OPTION",0x03,0x5b
                        db          2,2,"OR",0x03,0x5c
                        db          6,2,"OUTPUT",0x03,0x5d
                        db          5,2,"PEEK(",0x03,0x5e
                        db          6,2,"PEEKB(",0x03,0x5f
                        db          6,2,"PEEKD(",0x03,0x60
                        db          6,2,"PEEKF(",0x03,0x61
                        db          6,2,"PEEKL(",0x03,0x62
                        db          6,2,"PEEKQ(",0x03,0x63
                        db          6,2,"PEEKW(",0x03,0x64
                        db          4,2,"POKE",0x03,0x65
                        db          5,2,"POKEB",0x03,0x66
                        db          5,2,"POKED",0x03,0x67
                        db          5,2,"POKEF",0x03,0x68
                        db          5,2,"POKEL",0x03,0x69
                        db          5,2,"POKEQ",0x03,0x6a
                        db          5,2,"POKEW",0x03,0x6b
                        db          3,2,"POP",0x03,0x6c
                        db          5,2,"PRINT",0x03,0x6d
                        db          4,2,"PROC",0x03,0x6e
                        db          9,2,"PROCEDURE",0x03,0x6f
                        db          4,2,"PUSH",0x03,0x70
                        db          3,2,"PUT",0x03,0x71
                        db          9,2,"RANDOMIZE",0x03,0x72
                        db          3,2,"REL",0x03,0x73
                        db          6,2,"RENAME",0x03,0x74
                        db          5,2,"RENUM",0x03,0x75
                        db          8,2,"RENUMBER",0x03,0x76
                        db          6,2,"REPEAT",0x03,0x77
                        db          7,2,"RIGHT$(",0x03,0x78
                        db          3,2,"RND",0x03,0x79
                        db          3,2,"ROL",0x03,0x7a
                        db          3,2,"ROR",0x03,0x7b
                        db          3,2,"RUN",0x03,0x7c
                        db          4,2,"SAVE",0x03,0x7d
                        db          4,2,"SEEK",0x03,0x7e
                        db          3,2,"SHL",0x03,0x7f
                        db          3,2,"SHR",0x03,0x80
                        db          4,2,"SIN(",0x03,0x81
                        db          4,2,"SQR(",0x03,0x82
                        db          5,2,"SQRT(",0x03,0x83
                        db          4,2,"STOP",0x03,0x84
                        db          5,2,"STR$(",0x03,0x85
                        db          3,2,"SUB",0x03,0x86
                        db          3,2,"SYS",0x03,0x87
                        db          2,2,"TI",0x03,0x88
                        db          3,2,"TI$",0x03,0x89
                        db          5,2,"TIME$",0x03,0x8a
                        db          5,2,"TIMER",0x03,0x8b
                        db          2,2,"TO",0x03,0x8c
                        db          5,2,"TRACE",0x03,0x8d
                        db          4,2,"UNI(",0x03,0x8e
                        db          5,2,"UNI$(",0x03,0x8f
                        db          6,2,"UNLESS",0x03,0x90
                        db          5,2,"UNTIL",0x03,0x91
                        db          5,2,"USING",0x03,0x92
                        db          4,2,"VAL(",0x03,0x93
                        db          6,2,"VTAB$(",0x03,0x94
                        db          4,2,"WEND",0x03,0x95
                        db          5,2,"WHILE",0x03,0x96
                        db          4,2,"XNOR",0x03,0x97
                        db          3,2,"XOR",0x03,0x98
tokentbl_size           equ         $-tokentbl
tokentbl_name           db          7,"default"

; ---------------------------------------------------------------------------

dtm_ixfmt               db          "[%04u]",0
dtm_namfmt              db          " %-*.*s",0
dtm_lf                  db          10,0

                        align       8,db 0

; ---------------------------------------------------------------------------

; regular data section
                        section     .data

firstmapentry           dq          0
                        dq          tokentbl_name
                        dq          tokentbl
                        dq          tokentbl_size

; ---------------------------------------------------------------------------

; block-structured storage section

                        section     .bss

sourceptr               resq        1
sourceend               resq        1
sourcechr               resq        1
sourceucp               resq        1
tokenptr                resq        1

g_tokenmap              resq        tokenmap_size/8
g_tokenpad              resq        TOKENPAD_BYTES/8
tokenend                equ         $-g_tokenpad
digitbuf                resq        DIGITBUF_BYTES/8
digitbufend             equ         $-digitbuf
identbuf                resq        IDENTBUF_BYTES/8
identbufend             equ         $-identbuf
strlitbuf               resq        STRLITBUF_BYTES/8
strlitbufend            equ         $-strlitbuf

; ---------------------------------------------------------------------------
