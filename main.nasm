; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        section     .text

                        global      main
                        extern      init_tokenizer

main                    enter       0,0
                        call        init_tokenizer
                        xor         rax,rax
                        leave
                        ret
