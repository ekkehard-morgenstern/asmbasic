; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        section     .text

                        global      main
                        extern      init_tokenizer
                        extern      dump_tokenmap

main                    enter       0,0
                        call        init_tokenizer
                        call        dump_tokenmap
                        xor         rax,rax
                        leave
                        ret
