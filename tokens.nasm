

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

                        ;     [rbp-0x08] - RBX backup
                        ;     [rbp-0x10] - R12 backup
init_tokenizer          enter       0x10,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        cld
                        lea         rbx,[g_tokenmap]
                        lea         r12,[firstmapentry]
                        mov         [rbx+tkm_first],r12
                        ; r12 - map entry
.mapentry_loop          mov         rsi,[r12+tme_block]
                        mov         rcx,[r12+tme_blksize]
                        ; rsi - block pointer, rcx - block size
.initblock_loop:


                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret


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
                        db          7,2,"CATALOG",0x03,0x0c
                        db          5,2,"CEIL(",0x03,0x0d
                        db          5,2,"CLEAR",0x03,0x0e
                        db          5,2,"CLOSE",0x03,0x0f
                        db          3,2,"CLS",0x03,0x10
                        db          4,2,"CONT",0x03,0x11
                        db          4,2,"COS(",0x03,0x12
                        db          5,2,"DATE$",0x03,0x13
                        db          9,2,"DATETIME$",0x03,0x14
                        db          5,2,"DEC$(",0x03,0x15
                        db          3,2,"DEF",0x03,0x16
                        db          6,2,"DELETE",0x03,0x17
                        db          3,2,"DIM",0x03,0x18
                        db          7,2,"DYNAMIC",0x03,0x19
                        db          4,2,"EACH",0x03,0x1a
                        db          4,2,"ELSE",0x03,0x1b
                        db          3,2,"END",0x03,0x1c
                        db          3,2,"EQV",0x03,0x1d
                        db          5,2,"ERASE",0x03,0x1e
                        db          3,2,"ERL",0x03,0x1f
                        db          4,2,"ERR$",0x03,0x20
                        db          5,2,"ERROR",0x03,0x21
                        db          4,2,"EVER",0x03,0x22
                        db          5,2,"EVERY",0x03,0x23
                        db          4,2,"EXP(",0x03,0x24
                        db          5,2,"FILES",0x03,0x25
                        db          6,2,"FLOOR(",0x03,0x26
                        db          2,2,"FN",0x03,0x27
                        db          3,2,"FOR",0x03,0x28
                        db          7,2,"FOREACH",0x03,0x29
                        db          7,2,"FOREVER",0x03,0x2a
                        db          3,2,"GET",0x03,0x2b
                        db          2,2,"GO",0x03,0x2c
                        db          5,2,"GOSUB",0x03,0x2d
                        db          4,2,"GOTO",0x03,0x2e
                        db          5,2,"HEX$(",0x03,0x2f
                        db          6,2,"HTAB$(",0x03,0x30
                        db          2,2,"IF",0x03,0x31
                        db          3,2,"IMP",0x03,0x32
                        db          5,2,"INPUT",0x03,0x33
                        db          4,2,"INT(",0x03,0x34
                        db          7,2,"ITERATE",0x03,0x35
                        db          5,2,"LEAVE",0x03,0x36
                        db          6,2,"LEFT$(",0x03,0x37
                        db          3,2,"LET",0x03,0x38
                        db          3,2,"LG(",0x03,0x39
                        db          4,2,"LINE",0x03,0x3a
                        db          4,2,"LIST",0x03,0x3b
                        db          3,2,"LN(",0x03,0x3c
                        db          4,2,"LOAD",0x03,0x3d
                        db          6,2,"LOCATE",0x03,0x3e
                        db          6,2,"LOG10(",0x03,0x3f
                        db          5,2,"LOG2(",0x03,0x40
                        db          5,2,"LOGN(",0x03,0x41
                        db          5,2,"MID$(",0x03,0x42
                        db          4,2,"NAND",0x03,0x43
                        db          4,2,"NEQV",0x03,0x44
                        db          3,2,"NEW",0x03,0x45
                        db          4,2,"NEXT",0x03,0x46
                        db          4,2,"NIMP",0x03,0x47
                        db          3,2,"NOR",0x03,0x48
                        db          3,2,"NOT",0x03,0x49
                        db          5,2,"OCT$(",0x03,0x4a
                        db          3,2,"OFF",0x03,0x4b
                        db          3,2,"OLD",0x03,0x4c
                        db          2,2,"ON",0x03,0x4d
                        db          4,2,"OPEN",0x03,0x4e
                        db          6,2,"OPTION",0x03,0x4f
                        db          2,2,"OR",0x03,0x50
                        db          6,2,"OUTPUT",0x03,0x51
                        db          5,2,"PEEK(",0x03,0x52
                        db          6,2,"PEEKB(",0x03,0x53
                        db          6,2,"PEEKD(",0x03,0x54
                        db          6,2,"PEEKF(",0x03,0x55
                        db          6,2,"PEEKL(",0x03,0x56
                        db          6,2,"PEEKQ(",0x03,0x57
                        db          6,2,"PEEKW(",0x03,0x58
                        db          4,2,"POKE",0x03,0x59
                        db          5,2,"POKEB",0x03,0x5a
                        db          5,2,"POKED",0x03,0x5b
                        db          5,2,"POKEF",0x03,0x5c
                        db          5,2,"POKEL",0x03,0x5d
                        db          5,2,"POKEQ",0x03,0x5e
                        db          5,2,"POKEW",0x03,0x5f
                        db          3,2,"POP",0x03,0x60
                        db          5,2,"PRINT",0x03,0x61
                        db          4,2,"PUSH",0x03,0x62
                        db          3,2,"PUT",0x03,0x63
                        db          9,2,"RANDOMIZE",0x03,0x64
                        db          3,2,"REL",0x03,0x65
                        db          6,2,"RENAME",0x03,0x66
                        db          5,2,"RENUM",0x03,0x67
                        db          8,2,"RENUMBER",0x03,0x68
                        db          6,2,"REPEAT",0x03,0x69
                        db          7,2,"RIGHT$(",0x03,0x6a
                        db          3,2,"RND",0x03,0x6b
                        db          3,2,"ROL",0x03,0x6c
                        db          3,2,"ROR",0x03,0x6d
                        db          3,2,"RUN",0x03,0x6e
                        db          4,2,"SAVE",0x03,0x6f
                        db          4,2,"SEEK",0x03,0x70
                        db          3,2,"SHL",0x03,0x71
                        db          3,2,"SHR",0x03,0x72
                        db          4,2,"SIN(",0x03,0x73
                        db          4,2,"SQR(",0x03,0x74
                        db          5,2,"SQRT(",0x03,0x75
                        db          4,2,"STOP",0x03,0x76
                        db          5,2,"STR$(",0x03,0x77
                        db          3,2,"SUB",0x03,0x78
                        db          2,2,"TI",0x03,0x79
                        db          3,2,"TI$",0x03,0x7a
                        db          5,2,"TIME$",0x03,0x7b
                        db          5,2,"TIMER",0x03,0x7c
                        db          2,2,"TO",0x03,0x7d
                        db          5,2,"TRACE",0x03,0x7e
                        db          4,2,"UNI(",0x03,0x7f
                        db          5,2,"UNI$(",0x03,0x80
                        db          6,2,"UNLESS",0x03,0x81
                        db          5,2,"UNTIL",0x03,0x82
                        db          5,2,"USING",0x03,0x83
                        db          4,2,"VAL(",0x03,0x84
                        db          6,2,"VTAB$(",0x03,0x85
                        db          4,2,"WEND",0x03,0x86
                        db          5,2,"WHILE",0x03,0x87
                        db          4,2,"XNOR",0x03,0x88
                        db          3,2,"XOR",0x03,0x89
tokentbl_size           equ         $-tokentbl
tokentbl_name           db          7,"default"
                        align       8,db 0


; regular data section

                        section     .data

firstmapentry           dq          0
                        dq          tokentbl_name
                        dq          tokentbl
                        dq          tokentbl_size

; block-structured storage section

                        section     .bss

g_tokenmap              resq        tokenmap_size/8
