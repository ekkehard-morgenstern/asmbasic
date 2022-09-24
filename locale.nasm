
; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        section     .text

                        global      init_locale
                        extern      getenv,setlocale

LC_ALL                  equ         6

init_locale             enter       0,0

                        lea         rdi,[langname]
                        call        getenv
                        or          rax,rax
                        jz          .nolang

                        ; LANG is set to something: use as locale
                        mov         [locid],rax
                        mov         rsi,rax
                        mov         rdi,LC_ALL
                        call        setlocale
                        or          rax,rax
                        jz          .nolang

.end                    leave
                        ret

                        ; attempt   "" locale
.nolang                 lea         rsi,[langnull]
                        mov         [locid],rsi
                        mov         rdi,LC_ALL
                        call        setlocale
                        or          rax,rax
                        jnz         .end

                        ; attempt "C" locale, ignore result
                        lea         rsi,[langc]
                        mov         [locid],rsi
                        mov         rdi,LC_ALL
                        call        setlocale
                        jmp         .end

                        section     .rodata

langname                db          'LANG',0
langc                   db          'C'
langnull                db          0

                        align       8,db 0

                        section     .bss

locid                   resq        1
