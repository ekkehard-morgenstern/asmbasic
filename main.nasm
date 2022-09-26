; see implementation notes file provided in "implnotes.txt"

LBUF_SIZE               equ         8192

                        cpu         x64
                        bits        64

                        section     .text

                        global      main
                        extern      init_locale
                        extern      init_tokenizer
                        extern      dump_tokenmap
                        extern      stdin,fgets,strlen
                        extern      tokenize

main                    enter       0,0
                        call        init_locale
                        call        init_tokenizer
                        call        tokenizer_test
                        xor         rax,rax
                        leave
                        ret

getline                 enter       0,0
                        lea         rdi,[lbuf]
                        mov         rsi,lbuf_size
                        mov         rdx,[stdin]
                        call        fgets
                        leave
                        ret

tokenizer_test          enter       0,0
.lineloop               call        getline
                        test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        call        strlen
                        cmp         byte [rdi+rax-1],0x0a
                        jne         .nolf
                        dec         rax
.nolf                   test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        mov         rsi,rax
                        call        tokenize
                        jmp         .lineloop
.end                    leave
                        ret

                        section     .bss

lbuf                    resq        LBUF_SIZE/8
lbuf_size               equ         $-lbuf
