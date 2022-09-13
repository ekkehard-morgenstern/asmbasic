

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64


; token descriptors
                        struc       tokendesc
                            ; next entry with same hash value
                            td_nexthash:    resq    1
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
                        endstruc

                        section     .text

;                             global  main

; main                    enter       0,0
;                         call        oom
;                         xor         rax,rax
;                         leave
;                         ret


                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - requested size, in words
                        ;     [rbp-0x18] - RBX backup
tokenize                enter       0,0
                        leave
                        ret

                        ; rdi [rbp-0x08] - address
                        ; rsi [rbp-0x10] - requested size, in words
                        ;     [rbp-0x18] - RBX backup
detokenize              enter       0,0
                        leave
                        ret

; read-only data section

                        section     .rodata


; regular data section

                        section     .data

; block-structured storage section

                        section     .bss

g_tokenmap              resq        tokenmap_size/8
