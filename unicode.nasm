; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

WCOUT_OVERSHOOT         equ         20  ; room for 4 * 5 bytes of overshoot

                        ; cf. /usr/include/x86-64-linux-gnu/bits/types/
                        ; __mbstate_t.h
                        struc       mbstate
                            mb_count:       resd    1
                            mb_value:       resd    1
                        endstruc

                        section     .text
                        global      uclineininit,ucgetcp,uclineoutinit,ucputcp
                        extern      mbrtowc,wcrtomb

                        ; SYNOPSIS: uclineininit() initializes a text line
                        ; for processing.
                        ;   rdi - beginning of line in utf-8 format
                        ;   rsi - length of line, in bytes
uclineininit            enter       0,0
                        ; reset wide character state
                        xor         edx,edx
                        mov         [wcinstate+mb_count],edx
                        mov         [wcinstate+mb_value],edx
                        ; init text pointers
                        mov         [wclinein],rdi
                        add         rsi,rdi
                        mov         [wclineinend],rsi
                        ; done
                        leave
                        ret

                        ; SYNOPSIS ucgetcp() reads one code point from
                        ; the text line initialized using uclineininit().
                        ; Output will be in RAX. RAX will be -1 on end of input.
ucgetcp                 enter       0,0
                        ; rdi - pwc, rsi - s, rdx - n, rcx - ps; cf. mbrtowc(3)
.resume                 mov         rsi,[wclinein]
                        mov         rdx,[wclineinend]
                        cmp         rsi,rdx
                        jae         .inputend
                        lea         rdi,[wcchar]
                        sub         rdx,rsi
                        lea         rcx,[wcinstate]
                        call        mbrtowc
                        or          rax,rax
                        jz          .zero       ; a NUL character
                        cmp         rax,-2
                        je          .garbage
                        cmp         rax,-1
                        je          .garbage
                        ; otherwise, rax contains the number of input bytes
                        ; that have been consumed
                        add         [wclinein],rax
                        ; wcchar contains the translated character
                        mov         eax,dword [wcchar]
                        ; restore registers
.end                    leave
                        ret
                        ; a NUL or L'\0' character: can't read further
                        ; set pointer to end of line and finish
.zero                   mov         rdx,[wclineinend]
                        mov         [wclinein],rdx
                        ; end of input
.inputend               xor         rax,rax     ; return -1
                        dec         rax
                        jmp         .end
                        ; garbage: skip all chars with
                        ; high bit set
.garbage                mov         rsi,[wclinein]
                        mov         rdx,[wclineinend]
                        cld
.garbskip               mov         [wclinein],rsi
                        cmp         rsi,rdx
                        jae         .inputend
                        lodsb
                        test        al,0x80
                        jnz         .garbskip
                        ; reset conversion state
                        xor         edx,edx
                        mov         [wcinstate+mb_count],edx
                        mov         [wcinstate+mb_value],edx
                        ; go back to conversion
                        jmp         .resume

                        ; SYNOPSIS: uclineoutinit() initializes a text line
                        ; for processing.
                        ;   rdi - beginning of buffer in utf-8 format
                        ;   rsi - length of buffer, in bytes
                        ;         (will be reduced by WCOUT_OVERSHOOT bytes)
uclineoutinit           enter       0,0
                        ; reset wide character state
                        xor         edx,edx
                        mov         [wcoutstate+mb_count],edx
                        mov         [wcoutstate+mb_value],edx
                        ; init text pointers
                        mov         [wclineout],rdi
                        mov         [wclineoutbeg],rdi
                        sub         rsi,WCOUT_OVERSHOOT
                        add         rsi,rdi
                        mov         [wclineoutend],rsi
                        ; done
                        leave
                        ret

                        ; SYNOPSIS ucputcp() writes one code point from
                        ; the text line initialized using uclineoutinit().
                        ; Parameters:
                        ;   rdi - character
                        ; Output:
                        ;   rax - returns number of bytes in output buffer
ucputcp                 enter       0,0
                        mov         rsi,rdi
                        mov         rdi,[wclineout]
                        mov         rdx,[wclineoutend]
                        cmp         rdi,rdx
                        jae         .end
                        lea         rdx,[wcoutstate]
                        call        wcrtomb
                        cmp         rax,-1          ; invalid wchar
                        je          .end
                        add         [wclineout],rax
.end                    mov         rax,[wclineout]
                        sub         rax,[wclineoutbeg]
                        leave
                        ret

; variables in block-structured storage

                        section     .bss
                        global      wcchar

wcchar                  resd        1
                        resd        1
wcinstate               resd        mbstate_size/4
wclinein                resq        1
wclineinend             resq        1
wcoutstate              resd        mbstate_size/4
wclineout               resq        1
wclineoutend            resq        1
wclineoutbeg            resq        1