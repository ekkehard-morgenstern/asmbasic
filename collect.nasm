

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

;                             global  main

; main                    enter       0,0
;                         call        oom
;                         xor         rax,rax
;                         leave
;                         ret

; page descriptors

                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - requested size
init_page               enter       0x10,0
                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi
                        mov         rdi,rsi
                        call        xalloc
                        mov         rbx,[rbp-0x08]
                        mov         rdx,[rbp-0x10]
                        mov         [rbx+pd_location],rax
                        mov         [rbx+pd_numwords],rdx
                        xor         rax,rax
                        mov         [rbx+pd_usedwords],rax
                        leave
                        ret

; memory allocation

                        extern      malloc,realloc,free

                        ; rdi - requested size, in bytes

xalloc                  enter       0,0
                        call        malloc
                        or          rax,rax
                        jnz         .ok
                        call        oom
.ok                     leave
                        ret

                        ; rdi - block to be freed

xfree                   enter       0,0
                        or          rdi,rdi
                        jz          .end
                        call        free
.end                    leave
                        ret

                        ; rdi - block to be reallocated
                        ; rsi - new size, in bytes

xrealloc                enter       0,0
                        call        realloc
                        or          rax,rax
                        jnz         .ok
                        call        oom
.ok                     leave
                        ret

; error handling
                        extern      fprintf,stderr,exit

oom                     enter       0,0
                        mov         rdi,[stderr]
                        lea         rsi,[oommsg]
                        call        fprintf
                        xor         rdi,rdi
                        inc         rdi
                        call        exit
                        leave
                        ret

                        section     .rodata

oommsg                  db          "? out of memory",10,0

                        section     .data

                        section     .bss

                        align       8,resb 1

space1                  resb        pagedesc_size
space2                  resb        pagedesc_size
hndspc                  resb        pagedesc_size
