;   AsmBASIC - a BASIC compile and go system written in assembly language
;   Copyright (C) 2022  Ekkehard Morgenstern
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
;   NOTE: Programs created with AsmBASIC do not fall under this license.
;
;   CONTACT INFO:
;       E-Mail: ekkehard@ekkehardmorgenstern.de
;       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
;             Germany, Europe

; see implementation notes file provided in "implnotes.txt"

LBUF_SIZE               equ         8192

                        cpu         x64
                        bits        64

                        section     .text

                        global      main
                        extern      init_locale,chkcputype
                        extern      init_tokenizer,initparsetree,dumpparsetree
                        extern      dump_tokenmap
                        extern      pb_initstdio,pb_initsdl,pb_readln,strlen
                        extern      tokenize,detokenize,tok_dumplinebuf
                        extern      tokenpad,tokenpadptr,strcmp,fprintf,stderr
                        extern      exit,pb_putfmt,crtsyntree,delsyntree
                        extern      tokenpad,tokenpadptr,stn_debug,prtsyntree
                        extern      cooksyntree,delcookedsyntree
                        extern      printcookedsyntree

main                    enter       0,0
                        mov         [argc],rdi
                        mov         [argv],rsi

                        call        init_locale
                        call        getargs
                        call        chkcputype
                        call        initparsetree

                        cmp         qword [dumppt],0
                        je          .notdumppt
                        call        dumpparsetree
                        jmp         .end

.notdumppt              cmp         qword [consolemode],0
                        je          .defaultconsole

                        ; stdio or curses: use standard I/O
                        call        pb_initstdio
                        jmp         .afterinitconsole

                        ; default or SDL: use SDL
.defaultconsole         call        pb_initsdl

.afterinitconsole       call        init_tokenizer

                        cmp         qword [testtok],0
                        je          .nottesttok

                        call        tokenizer_test
                        jmp         .end

.nottesttok             call        main_loop

.end                    xor         rax,rax
                        leave
                        ret

getargs                 enter       0x20,0
                        mov         [rbp-0x08],r12
                        mov         [rbp-0x10],r13
                        mov         [rbp-0x18],r14
                        mov         r12,[argc]
                        mov         r13,[argv]
                        dec         r12
                        add         r13,8
                        xor         rax,rax
                        mov         [helpmode],rax
                        mov         [consolemode],rax
                        mov         [filename],rax
                        mov         [testtok],rax
                        mov         [stnprint],rax

.argloop                test        r12,r12
                        jz          .endargs

                        mov         rax,[r13]
                        dec         r12
                        add         r13,8

                        cmp         byte [rax],'-'
                        je          .option

                        cmp         qword [filename],0
                        je          .notmultiple

                        mov         rdi,[stderr]
                        lea         rsi,[morethanonefile]
                        mov         rdx,rax
                        xor         al,al
                        call        fprintf
                        jmp         .argloop

.notmultiple            mov         [filename],rax
                        jmp         .argloop

.option                 inc         rax
                        cmp         byte [rax],'-'
                        je          .longoption

                        mov         r14,rax

                        mov         rdi,r14
                        lea         rsi,[hoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .noth
                        mov         qword [helpmode],1
                        jmp         .argloop

.noth                   mov         rdi,r14
                        lea         rsi,[doption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notd
                        mov         qword [consolemode],0
                        jmp         .argloop

.notd                   mov         rdi,r14
                        lea         rsi,[soption]
                        call        strcmp
                        test        rax,rax
                        jnz         .nots
                        mov         qword [consolemode],1
                        jmp         .argloop

.nots                   mov         rdi,r14
                        lea         rsi,[coption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notc
                        mov         qword [consolemode],2
                        jmp         .argloop

.notc                   mov         rdi,[stderr]
                        lea         rsi,[badoption]
                        mov         rdx,r14
                        xor         al,al
                        call        fprintf
                        jmp         .argloop

.longoption             inc         rax

                        mov         r14,rax

                        mov         rdi,r14
                        lea         rsi,[helpoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .nothelp
                        mov         qword [helpmode],1
                        jmp         .argloop

.nothelp                mov         rdi,r14
                        lea         rsi,[sdloption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notsdl
                        mov         qword [consolemode],0
                        jmp         .argloop

.notsdl                 mov         rdi,r14
                        lea         rsi,[stdiooption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notstdio
                        mov         qword [consolemode],1
                        jmp         .argloop

.notstdio               mov         rdi,r14
                        lea         rsi,[cursesoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notcurses
                        mov         qword [consolemode],2
                        jmp         .argloop

.notcurses              mov         rdi,r14
                        lea         rsi,[testtokoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .nottesttok
                        mov         qword [testtok],1
                        jmp         .argloop

.nottesttok             mov         rdi,r14
                        lea         rsi,[dumpptoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notdumppt
                        mov         qword [dumppt],1
                        jmp         .argloop

.notdumppt              mov         rdi,r14
                        lea         rsi,[stndebugoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notstndebug
                        mov         qword [stn_debug],1
                        jmp         .argloop

.notstndebug            mov         rdi,r14
                        lea         rsi,[stnprintoption]
                        call        strcmp
                        test        rax,rax
                        jnz         .notstnprint
                        mov         qword [stnprint],1
                        jmp         .argloop

.notstnprint            mov         rdi,[stderr]
                        lea         rsi,[badoption]
                        mov         rdx,r14
                        xor         al,al
                        call        fprintf
                        jmp         .argloop

.endargs                cmp         qword [helpmode],1
                        jne         .end

                        mov         rdi,[stderr]
                        lea         rsi,[helptext]
                        mov         rdx,[argv]
                        mov         rdx,[rdx]
                        xor         al,al
                        call        fprintf

                        mov         rdi,1
                        call        exit

.end                    mov         r14,[rbp-0x18]
                        mov         r13,[rbp-0x10]
                        mov         r12,[rbp-0x08]
                        leave
                        ret

getline                 enter       0,0
                        lea         rdi,[lbuf]
                        mov         rsi,lbuf_size
                        call        qword [pb_readln]
                        leave
                        ret

tokenizer_test          enter       0,0
                        lea         rdi,[tokenizertest]
                        xor         al,al
                        call        qword [pb_putfmt]
.lineloop               call        getline
                        test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        call        strlen
                        lea         rdi,[lbuf]
                        cmp         byte [rdi+rax-1],0x0a
                        jne         .nolf
                        dec         rax
                        mov         byte [rdi+rax],0
.nolf                   test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        mov         rsi,rax
                        call        tokenize
                        ; TEST: detokenize and output
                        lea         rdi,[tokenpad]
                        mov         rsi,[tokenpadptr]
                        sub         rsi,rdi
                        xor         rdx,rdx
                        call        detokenize
                        call        tok_dumplinebuf
                        jmp         .lineloop
.end                    leave
                        ret

main_loop               enter       0,0
                        lea         rdi,[greeting]
                        xor         al,al
                        call        qword [pb_putfmt]

.readyloop              lea         rdi,[readyprompt]
                        xor         al,al
                        call        qword [pb_putfmt]

.lineloop               call        getline
                        test        rax,rax
                        jz          .end
                        lea         rdi,[lbuf]
                        call        strlen
                        lea         rdi,[lbuf]
                        cmp         byte [rdi+rax-1],0x0a
                        jne         .nolf
                        dec         rax
                        mov         byte [rdi+rax],0
.nolf                   test        rax,rax
                        jz          .end

                        ; tokenize line buffer
                        lea         rdi,[lbuf]
                        mov         rsi,rax
                        call        tokenize

                        ; tokenizer failure: this cannot realistically occur,
                        ; since there are no invalid tokens (anything not one
                        ; of the standard tokens gets converted into
                        ; identifiers). Only if the token buffer gets exhausted
                        ; (i.e. with too long lines), this might be an issue,
                        ; but I didn't want to output '? Line too long' when I
                        ; don't know if that was actually the case.
                        test        rax,rax
                        jz          .tokfail

                        ; create syntax tree from tokens
                        lea         rdi,[tokenpad]
                        mov         rsi,[tokenpadptr]
                        sub         rsi,rdi
                        call        crtsyntree
                        test        rax,rax
                        jz          .synerr

                        cmp         qword [stnprint],0
                        je          .nostnprint
                        call        prtsyntree

.nostnprint             call        cooksyntree


                        call        delcookedsyntree
                        call        delsyntree

                        jmp         .lineloop
.end                    leave
                        ret

.synerr                 lea         rdi,[syntaxerror]
.printerr               xor         al,al
                        call        qword [pb_putfmt]
                        jmp         .readyloop

.tokfail                lea         rdi,[tokenfail]
                        jmp         .printerr

                        section     .bss
                        global      testtok

lbuf                    resq        LBUF_SIZE/8
lbuf_size               equ         $-lbuf

argc                    resq        1
argv                    resq        1
helpmode                resq        1
consolemode             resq        1
filename                resq        1
testtok                 resq        1
dumppt                  resq        1
stnprint                resq        1

                        section     .rodata

helpoption              db          'help',0
hoption                 db          'h',0
sdloption               db          'sdl',0
doption                 db          'd',0
stdiooption             db          'stdio',0
soption                 db          's',0
cursesoption            db          'curses',0
coption                 db          'c',0
testtokoption           db          'testtok',0
dumpptoption            db          'dumppt',0
stndebugoption          db          'stndebug',0
stnprintoption          db          'stnprint',0

badoption               db          '? Bad option "%s" ignored',10,0
morethanonefile         db          '? Extra filename ignored: %s',10,0

greeting                db          'AsmBASIC '
                        %include    "verstr.inc"
                        db          10,10,0
readyprompt             db          'Ready.',10,0
tokenfail               db          '? Tokenizer failure',10,0
syntaxerror             db          '? Syntax error',10,0

tokenizertest           db          'AsmBASIC color test',10
                        db          'background colors 0-7: '
                        db          27,'[40m',' '
                        db          27,'[41m',' '
                        db          27,'[42m',' '
                        db          27,'[43m',' '
                        db          27,'[44m',' '
                        db          27,'[45m',' '
                        db          27,'[46m',' '
                        db          27,'[47m',' '
                        db          27,'[m',10
                        db          'foreground colors 0-7: '
                        db          27,'[30m','*'
                        db          27,'[31m','*'
                        db          27,'[32m','*'
                        db          27,'[33m','*'
                        db          27,'[34m','*'
                        db          27,'[35m','*'
                        db          27,'[36m','*'
                        db          27,'[37m','*'
                        db          27,'[m',10,10
                        db          'AsmBASIC tokenizer test',10,0

helptext                db          'Usage: %s [options] [file]',10
                        db          'Options:',10
                        db          '  --help -h            (this)',10
                        db          '  --sdl -d             SDL mode (default)'
                        db          10
                        db          '  --stdio -s           standard I/O',10
                        db          '  --curses -c          ncurses (not impl)'
                        db          10
                        db          'Debugging Options:',10
                        db          '  --testtok            test tokenizer',10
                        db          '  --dumppt             dump parsing tree'
                        db          10
                        db          '  --stndebug           syntax tree node '
                        db          'debugging (crt/del)',10
                        db          '  --stnprint           syntax tree node '
                        db          'printing',10
                        db          0

                        align       8,db 0
