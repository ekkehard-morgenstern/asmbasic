; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        ; cf. /usr/include/x86-64-linux-gnu/bits/types/
                        ; __mbstate_t.h
                        struc       mbstate
                            mb_count:       resd    1
                            mb_value:       resd    1
                        endstruc

                        section     .text
                        global      uclinelinit,ucgetcp
                        extern      mbrtowc

                        ; SYNOPSIS: uclineinit() initializes a text line
                        ; for processing.
                        ;   rdi - beginning of line in utf-8 format
                        ;   rsi - length of line, in bytes
uclineinit              enter       0,0
                        ; reset wide character state
                        xor         edx,edx
                        mov         [wcstate+mb_count],edx
                        mov         [wcstate+mb_value],edx
                        ; init text pointers
                        mov         [wclinein],rdi
                        add         rsi,rdi
                        mov         [wclineinend],rsi
                        ; done
                        leave
                        ret

                        ; SYNOPSIS ucgetcp() reads one code point from
                        ; the text line initialized using uclineinit().
                        ; Output will be in RAX. RAX will be -1 on end of input.
ucgetcp                 enter       0,0
                        ; rdi - pwc, rsi - s, rdx - n, rcx - ps; cf. mbrtowc(3)
.resume                 mov         rsi,[wclinein]
                        mov         rdx,[wclineinend]
                        cmp         rsi,rdx
                        jae         .inputend
                        lea         rdi,[wcchar]
                        sub         rdx,rsi
                        lea         rcx,[wcstate]
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
.end                    mov         r15,[rbp-0x20]
                        mov         r14,[rbp-0x18]
                        mov         r13,[rbp-0x10]
                        mov         r12,[rbp-0x08]
                        leave
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
                        mov         [wcstate+mb_count],edx
                        mov         [wcstate+mb_value],edx
                        ; go back to conversion
                        jmp         .resume

; variables in thread-local storage

                        section     .bss
                        global      wcchar

wcchar                  resd        1
                        resd        1
wcstate                 resd        mbstate_size/4
wclinein                resq        1
wclineinend             resq        1
