

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

; page descriptors
                        struc       pagedesc
                            pd_location:    resq    1
                            pd_numwords:    resq    1
                            pd_usedwords:   resq    1
                        endstruc

                        section     .text

                        extern      xalloc

;                             global  main

; main                    enter       0,0
;                         call        oom
;                         xor         rax,rax
;                         leave
;                         ret

; page descriptors

                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - requested size, in words
                        ;     [rbp-0x18] - RBX backup
init_page               enter       0x20,0
                        mov         [rbp-0x08],rdi
                        shl         rsi,3   ; *8
                        mov         [rbp-0x10],rsi
                        mov         [rbp-0x18],rbx
                        mov         rdi,rsi
                        call        xalloc
                        mov         rbx,[rbp-0x08]
                        mov         rdx,[rbp-0x10]
                        mov         [rbx+pd_location],rax
                        mov         [rbx+pd_numwords],rdx
                        xor         rax,rax
                        mov         [rbx+pd_usedwords],rax
                        mov         rbx,[rbp-0x18]
                        leave
                        ret

; regular data section

                        section     .data

; block-structured storage section

                        section     .bss

space1                  resq        pagedesc_size/8
space2                  resq        pagedesc_size/8
hndspc                  resq        pagedesc_size/8
