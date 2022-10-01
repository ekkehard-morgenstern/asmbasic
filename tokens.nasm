

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

LINEBUF_BYTES           equ         16384
TOKENPAD_BYTES          equ         32768
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

                        global      init_tokenizer,dump_tokenmap,tokenize
                        extern      xalloc,printf
                        extern      uclineininit,ucgetcp,uclineoutinit,ucputcp
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
                        ; rdi - address
                        ; rsi - size of text, in bytes
                        ;
tokenize                enter       0,0
                        ; call preparation code
                        call        tok_prepare
                        call        tok_dumplinebuf
                        lea         rdi,[linebuf]
                        mov         rsi,[linebuflen]
                        call        tok_main
                        leave
                        ret

; ---------------------------------------------------------------------------

                        ; initializes the tokenization process
                        ; rdi - source text pointer
                        ; rsi - source text length
tok_init                enter       0,0
                        call        uclineininit
                        mov         qword [sourceputback],-1
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

                        ; read a number with specified-out number base
                        ; &H... &D... &O... &B...
                        ; assumes that '&' has already been read
                        ; if the character after & is invalid, it is put
                        ; back, and the '&' is stored as a verbatim token.
                        ; If the base is valid, but followed by invalid chars,
                        ; number 0 is stored.
tok_rdamp               enter       0,0
                        call        tok_getch
                        cmp         rax,-1
                        je          .no_followup
                        cmp         rax,'H'
                        je          .beg_hex
                        cmp         rax,'D'
                        je          .beg_dec
                        cmp         rax,'O'
                        je          .beg_oct
                        cmp         rax,'B'
                        je          .beg_bin
                        mov         [sourceputback],rax
.no_followup            mov         rdi,'&'
                        call        tok_putb
.end                    leave
                        ret
.beg_hex                mov         rdi,16
                        jmp         .beg_read
.beg_dec                mov         rdi,10
                        jmp         .beg_read
.beg_oct                mov         rdi,8
                        jmp         .beg_read
.beg_bin                mov         rdi,2
.beg_read               call        tok_rdnum
                        jmp         .end

; ---------------------------------------------------------------------------

                        ; read a number with a specified number base
                        ; input:
                        ;   rdi - base
                        ; output:
                        ;   rax - IEEE double-precision binary floating-point
                        ;
                        ; local variables:
                        ;   [rbp-0x08] - rbx backup
                        ;   [rbp-0x10] - r12 backup
                        ;   [rbp-0x18] - r13 backup
                        ;   [rbp-0x20] - r14 backup
                        ;   [rbp-0x38] - exp part of result (temporary)
                        ;   [rbp-0x40] - calculation (temporary)
                        ;   [rbp-0x48] - unused
                        ;   [rbp-0x50] - max. unshifted value (temporary)
                        ;   [rbp-0x52] - fpu control word (temporary)
                        ;   [rbp-0x54] - exp of integ part (word, temporary)
                        ;   [rbp-0x56] - num of digits aft pt (word, temporary)
                        ;   [rbp-0x57] - flag digits after point (temporary)
                        ;   [rbp-0x58] - overflow flag (byte, temporary)
tok_rdnum               enter       0x60,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14
                        xor         rax,rax
                        mov         [rbp-0x38],rax  ; exp part of result
                        mov         [rbp-0x58],rax  ; flags (see above)
                        mov         rbx,rdi
                        xor         r12,r12     ; shift
                        xor         r13,r13     ; integral part of result
                        xor         r14,r14     ; maximum unshifted value
; base 10 vs base 2,8,16:
; in base 10 mode, digits are added using multiplication and adding,
; and the final result is calculated using the FPU.
; in base 2,8,16 mode, digits are added using shifting and adding,
; and the final result is calculated using the integer ALU of the CPU.
                        cmp         bl,10
                        je          .intloop
                        ; compute log2(base) as shift value (non-dec only)
                        bsf         r12,rbx
                        mov         rcx,r12
                        ; compute ((2^63)>>baseshift)-1 (max unshifted val)
                        inc         r14
                        ror         r14,1
                        shr         r14,cl
                        dec         r14
; reading of integral part:
; reads digits and adds them to the right of the integral value.
; if the number would overflow, invisible 0 digits are added by
; incrementing the projected exponent.
.intloop                call        tok_getch
                        cmp         rax,-1
                        je          .numdone
                        cmp         rax,' '
                        je          .numdonepb
                        cmp         rax,'.'
                        je          .fractloop
                        cmp         rax,'0'
                        jb          .chkexp
                        cmp         rax,'9'
                        ja          .chkexp
                        sub         al,'0'
                        jmp         .dodig
.chkexp                 cmp         bl,16
                        je          .chkexphex
                        cmp         al,'E'
                        je          .doexp
                        jmp         .numdonepb
.chkexphex              cmp         al,'G'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        cmp         al,'A'
                        jmp         .numdonepb
                        cmp         al,'F'
                        jmp         .numdonepb
                        sub         al,'A'
                        add         al,10
                        jmp         .dodig
.intexpinc              inc         word [rbp-0x54] ; inc int exp
                        jmp         .intloop
.dodig                  cmp         al,bl
                        jae         .numdone
                        cmp         byte [rbp-0x58],0   ; overflow?
                        jne         .intexpinc          ; skip digit
                        test        r12,r12
                        jz          .dodigmul
                        ; base 2,8,16: shift and add
                        ; first check if overflow would occur
                        cmp         r13,r14
                        seta        byte [rbp-0x58]
                        ja          .intexpinc
                        mov         rcx,r12
                        sal         r13,cl
                        add         r13,rax
                        jmp         .intloop
                        ; base 10: multiply and add
.dodigmul               mov         rdx,r13
                        imul        rdx,rbx
                        seto        byte [rbp-0x58]
                        jo          .intexpinc
                        add         rdx,rax
                        seto        byte [rbp-0x58]
                        jo          .intexpinc
                        mov         r13,rdx
                        jmp         .intloop
; reading of fraction:
;       the dot has already been read, continue to read digits.
;       digits are added to the integral part, if possible, and ignored if not.
;       if a digit was added, the fractional digit counter is incremented,
;       which is later on used to compute the final exponent.
.fractloop              call        tok_getch
                        cmp         rax,-1
                        je          .numdone
                        cmp         rax,' '
                        je          .numdonepb
                        cmp         rax,'0'
                        jb          .chkexp2
                        cmp         rax,'9'
                        ja          .chkexp2
                        sub         al,'0'
                        jmp         .dodig2
.chkexp2                cmp         bl,16
                        je          .chkexphex2
                        cmp         al,'E'
                        je          .doexp
                        jmp         .numdonepb
.chkexphex2             cmp         al,'G'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        cmp         al,'A'
                        jmp         .numdonepb
                        cmp         al,'F'
                        jmp         .numdonepb
                        sub         al,'A'
                        add         al,10
.dodig2                 cmp         al,bl
                        jae         .numdone
                        cmp         byte [rbp-0x58],0       ; overflow?
                        jne         .fractloop              ; skip digits
                        test        r12,r12
                        jz          .dodigmul2
                        ; base 2,8,16: shift and add
                        ; first check if overflow would occur
                        cmp         r13,r14
                        seta        byte [rbp-0x58]
                        ja          .fractloop
                        mov         rcx,r12
                        sal         r13,cl
                        add         r13,rax
                        jmp         .fractadd
                        ; base 10: multiply and add
.dodigmul2              mov         rdx,r13
                        imul        rdx,rbx
                        seto        byte [rbp-0x58]
                        jo          .fractloop
                        add         rdx,rax
                        seto        byte [rbp-0x58]
                        jo          .fractloop
                        mov         r13,rdx
                        ; remember we added a fraction digit
.fractadd               inc         word [rbp-0x56]     ; # of digits
                        mov         byte [rbp-0x57],1   ; fract flag
                        jmp         .fractloop
; reading of exponent
;
;
;
;


                        ; exponent E/G[+-]exp (based)
.doexp:

                        ; exponent P[+-]powerof2
.dopexp:

                        ; finished; check if we have something non-zero
.numdone                test        r13,r13
                        setz        al
                        or          al,[rbp-0x57]
                        jz          .zeroresult
; exponent fixup and final number computations:
; the exponent is calculated using overflow, fraction and user-supplied value,
; and then the final number is computed from the integral part and the fixed-up
; exponent.
;
; examples:
; - regular value with integral part (and fractional part)
;       1234.56         int:123456, frac:2, 1.23456 * 10^3
; - overshot value with integral part plus invisible exponent
;       1234[00]        int:1234, extra:2, 1.234 * 10^5
                        ; fixup exponent before normalization
                        cmp         bl,10
                        je          .decfixexp
; in non-decimal mode, we don't need the FPU to construct a floating-point
; value.
                        ; first, get int(logbase(integerpart))
                        ; get highest bit that is set
                        ; this is also the 2^n exponent
                        bsr         rax,r13
; 16^n = 2^(4*n)
;  8^n = 2^(3*n)
;  2^n = 2^(1*n)
; thus, the exponent needs only be shifted by the base shift
                        mov         rcx,r12
                        ; check for overflow
                        cmp         byte [rbp-0x58],0       ; overflow?
                        jne         .no_ovf2
                        ; yes: add additional powers of (base)
                        movzx       rdx,word [rbp-0x54]
                        shl         rdx,cl
                        add         rax,rdx
                        jmp         .nondecexpdone  ; cannot have fraction
                        ; check for fraction
.no_ovf2                cmp         byte [rbp-0x57],0
                        je          .nondecexpdone  ; no fraction
                        ; subtract powers of (base)
                        movzx       rdx,word [rbp-0x56]
                        shl         rdx,cl
                        sub         rax,rdx
                        ; now add the user-supplied exponent
                        ; NOTE that in nondecimal mode, the user-supplied
                        ; exponent must already have been premultiplied
                        ; with the base in E/G mode, but not in P mode
.nondecexpdone          add         rax,[rbp-0x38]
                        ; now check for maxima / minima and limit the exponent
                        ; accordingly.
                        cmp         rax,-1022
                        jl          .zeroresult
                        cmp         rax,1023
                        jg          .infresult
                        ; get biased exponent
                        add         rax,1023
                        ; shift into position
                        shl         rax,52
                        ; get highest bit of integral part
                        bsr         rdx,r13
                        cmp         dl,52
                        jb          .mant2left
                        ja          .mant2right
                        jmp         .mantdone
                        ; mantissa needs to be shifted to the left into pos
.mant2left              mov         cl,52
                        sub         cl,dl
                        shl         r13,cl
                        jmp         .mantdone
                        ; mantissa needs to be shifted to the right into pos
.mant2right             mov         cl,dl
                        sub         cl,52
                        shr         r13,cl
                        ; get shifted mantissa and mask off unnecessary bits
.mantdone               mov         rdx,0x000fffffffffffff
                        and         rdx,r13
                        ; combine
                        or          rax,rdx
                        ; finished
                        jmp         .done
                        ; regular fixup for base 10
                        ; set rounding mode to round down
.decfixexp              fclex
                        fstcw       word [rbp-0x52]
                        mov         dx,[rbp-0x52]   ; dx ctrl backup
                        mov         ax,dx
                        and         ax,0xf0c0
                        or          ax,0x0f3f   ; xcpt off, hi prec, rnd2z
                        mov         [rbp-0x52],ax
                        fldcw       word [rbp-0x52]
                        mov         [rbp-0x52],dx   ; safekeep ctrl backup
                        ; compute int(log10(integralpart)) to get power of 10
                        mov         [rbp-0x40],r13
                        fld1
                        fild        qword [rbp-0x40]
                        fyl2x       ; 1*log2(integralpart)
                        fldl2t      ; /log2(10)
                        fdivp
                        fistp       qword [rbp-0x40]
                        mov         rax,[rbp-0x40]
                        ; check for overflow of integral part
                        cmp         byte [rbp-0x58],0       ; overflow?
                        jne         .no_ovf                 ; nope
                        ; yes: add additional powers of 10
                        movzx       rdx,word [rbp-0x54]
                        add         rax,rdx
                        jmp         .no_frac    ; cannot have fraction
                        ; no: check for fraction, subtract powers of 10
.no_ovf                 cmp         byte [rbp-0x57],0
                        je          .no_frac
                        movzx       rdx,word [rbp-0x56]
                        sub         rax,rdx
                        ; finally, add user-supplied exponent
.no_frac                add         rax,[rbp-0x38]
                        ; compute final number
                        ; result = intpart * 10^exp =
                        ;   intpart * ((2^(exp*log2(10))-1)+1)
                        mov         [rbp-0x40],rax
                        ; compute exp*log2(10)
                        fild        qword [rbp-0x40]
                        fldl2t
                        fmulp
                        ; compute 2^n-1
                        f2xm1
                        ; add 1
                        fld1
                        faddp
                        ; multiply with intpart
                        mov         [rbp-0x40],r13
                        fild        qword [rbp-0x40]
                        fmulp
                        ; done
                        fstp        qword [rbp-0x40]
                        ; restore FPU settings
                        fclex
                        fldcw       word [rbp-0x52]
                        ; get return value
                        mov         rax,[rbp-0x40]
.done                   mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret
.numdonepb              mov         [sourceputback],rax
                        jmp         .numdone
.zeroresult             xor         rax,rax
                        jmp         .done
.infresult              mov         rax,0x7ff0000000000000  ; +inf
                        jmp         .done

; ---------------------------------------------------------------------------

                        ; put token byte in rdi to token buffer
tok_putb                enter       0,0
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
                        ;   tok_dumplinebuf() outputs the linebuffer for
                        ;   debugging purposes

tok_dumplinebuf         enter       0,0
                        lea         rdi,[dlb_fmt]
                        mov         rsi,[linebuflen]
                        mov         rdx,rsi
                        lea         rcx,[linebuf]
                        xor         al,al
                        call        printf
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

dlb_fmt                 db          "line buf: <<%-*.*s>>",10,0


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


g_tokenmap              resq        tokenmap_size/8
linebuf                 resq        LINEBUF_BYTES/8
linebufsize             equ         $-linebuf
linebuflen              resq        1
sourceputback           resq        1
tokenpad                resq        TOKENPAD_BYTES/8
tokenpadsize            equ         $-tokenpad
digitbuf                resq        DIGITBUF_BYTES/8
digitbufsize            equ         $-digitbuf
identbuf                resq        IDENTBUF_BYTES/8
identbufsize            equ         $-identbuf
strlitbuf               resq        STRLITBUF_BYTES/8
strlitbufsize           equ         $-strlitbuf

; ---------------------------------------------------------------------------
