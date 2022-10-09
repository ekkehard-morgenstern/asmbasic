;   AsmBASIC - a BASIC interpreter written in assembly language
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

                        cpu         x64
                        bits        64

                        section     .text

                        global      tok_rdamp,tok_rdnum,detok_wrnum
                        extern      tok_getch,tok_putb,sourceputback
                        extern      printf,ucputcp

; ---------------------------------------------------------------------------

                        ; read a number with specified-out number base
                        ; &H... &D... &O... &B...
                        ; assumes that '&' has already been read
                        ; if the character after & is invalid, it is put
                        ; back, and the '&' is stored as a verbatim token.
                        ; If the base is valid, but followed by invalid chars,
                        ; number 0 is stored.
tok_rdamp               enter       0x10,0
                        call        tok_getch
                        cmp         rax,-1
                        je          .no_followup
                        cmp         rax,'H'
                        je          .beg_hex
                        cmp         rax,'D'
                        je          .beg_dec
                        cmp         rax,'O'
                        je          .beg_oct
                        cmp         rax,'B'
                        je          .beg_bin
                        mov         [sourceputback],rax
.no_followup            mov         rdi,'&'
                        call        tok_putb
.end                    leave
                        ret
.beg_hex                mov         rdi,16
                        jmp         .beg_read
.beg_dec                mov         rdi,10
                        jmp         .beg_read
.beg_oct                mov         rdi,8
                        jmp         .beg_read
.beg_bin                mov         rdi,2
.beg_read               call        tok_rdnum
                        ; TEST: call printf to debug number
                        mov         [rbp-0x08],rax
                        lea         rdi,[rdnum_fmt]
                        mov         rsi,rax
                        movq        xmm0,rax
                        mov         al,1
                        call        printf
                        ; TEST: call detok_wrnum on the number to see if it
                        ; can be detokenized
                        mov         rdi,[rbp-0x08]
                        mov         rsi,10  ; need to test base 10 code
                        call        detok_wrnum
                        jmp         .end

; ---------------------------------------------------------------------------

                        ; read a number with a specified number base
                        ; input:
                        ;   rdi - base
                        ; output:
                        ;   rax - IEEE double-precision binary floating-point
                        ;
                        ; local variables:
                        ;   [rbp-0x08] - rbx backup
                        ;   [rbp-0x10] - r12 backup
                        ;   [rbp-0x18] - r13 backup
                        ;   [rbp-0x20] - r14 backup
                        ;   [rbp-0x38] - exp part of result (temporary)
                        ;   [rbp-0x40] - calculation (temporary)
                        ;   [rbp-0x47] - exponent 'P' mode (byte, temporary)
                        ;   [rbp-0x48] - exponent sign (byte, temporary)
                        ;   [rbp-0x50] - max. unshifted value (temporary)
                        ;   [rbp-0x52] - fpu control word (temporary)
                        ;   [rbp-0x54] - exp of integ part (word, temporary)
                        ;   [rbp-0x56] - num of digits aft pt (word, temporary)
                        ;   [rbp-0x57] - flag digits after point (temporary)
                        ;   [rbp-0x58] - overflow flag (byte, temporary)
tok_rdnum               enter       0x60,0
                        mov         [rbp-0x08],rbx
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],r13
                        mov         [rbp-0x20],r14
                        xor         rax,rax
                        mov         [rbp-0x38],rax  ; exp part of result
                        mov         [rbp-0x48],rax  ; flags (see above)
                        mov         [rbp-0x58],rax  ; flags (see above)
                        mov         rbx,rdi
                        xor         r12,r12     ; shift
                        xor         r13,r13     ; integral part of result
                        xor         r14,r14     ; maximum unshifted value
; base 10 vs base 2,8,16:
; in base 10 mode, digits are added using multiplication and adding,
; and the final result is calculated using the FPU.
; in base 2,8,16 mode, digits are added using shifting and adding,
; and the final result is calculated using the integer ALU of the CPU.
                        cmp         bl,10
                        je          .intloop
                        ; compute log2(base) as shift value (non-dec only)
                        bsf         r12,rbx
                        mov         rcx,r12
                        ; compute ((2^63)>>baseshift)-1 (max unshifted val)
                        inc         r14
                        ror         r14,1
                        shr         r14,cl
                        dec         r14
; reading of integral part:
; reads digits and adds them to the right of the integral value.
; if the number would overflow, invisible 0 digits are added by
; incrementing the projected exponent.
.intloop                call        tok_getch
                        cmp         rax,-1
                        je          .numdone
                        cmp         rax,' '
                        je          .numdonepb
                        cmp         rax,'.'
                        je          .fractloop
                        cmp         rax,'0'
                        jb          .chkexp
                        cmp         rax,'9'
                        ja          .chkexp
                        sub         al,'0'
                        jmp         .dodig
.chkexp                 cmp         bl,16
                        je          .chkexphex
                        cmp         al,'E'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        jmp         .numdonepb
.chkexphex              cmp         al,'G'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        cmp         al,'A'
                        jb          .numdonepb
                        cmp         al,'F'
                        ja          .numdonepb
                        sub         al,'A'
                        add         al,10
                        jmp         .dodig
.intexpinc              inc         word [rbp-0x54] ; inc int exp
                        jmp         .intloop
.dodig                  cmp         al,bl
                        jae         .numdonepb
                        cmp         byte [rbp-0x58],0   ; overflow?
                        jne         .intexpinc          ; skip digit
                        test        r12,r12
                        jz          .dodigmul
                        ; base 2,8,16: shift and add
                        ; first check if overflow would occur
                        cmp         r13,r14
                        seta        byte [rbp-0x58]
                        ja          .intexpinc
                        mov         rcx,r12
                        sal         r13,cl
                        add         r13,rax
                        jmp         .intloop
                        ; base 10: multiply and add
.dodigmul               mov         rdx,r13
                        imul        rdx,rbx
                        seto        byte [rbp-0x58]
                        jo          .intexpinc
                        add         rdx,rax
                        seto        byte [rbp-0x58]
                        jo          .intexpinc
                        mov         r13,rdx
                        jmp         .intloop
; reading of fraction:
;       the dot has already been read, continue to read digits.
;       digits are added to the integral part, if possible, and ignored if not.
;       if a digit was added, the fractional digit counter is incremented,
;       which is later on used to compute the final exponent.
.fractloop              call        tok_getch
                        cmp         rax,-1
                        je          .numdone
                        cmp         rax,' '
                        je          .numdonepb
                        cmp         rax,'0'
                        jb          .chkexp2
                        cmp         rax,'9'
                        ja          .chkexp2
                        sub         al,'0'
                        jmp         .dodig2
.chkexp2                cmp         bl,16
                        je          .chkexphex2
                        cmp         al,'E'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        jmp         .numdonepb
.chkexphex2             cmp         al,'G'
                        je          .doexp
                        cmp         al,'P'
                        je          .dopexp
                        cmp         al,'A'
                        jb          .numdonepb
                        cmp         al,'F'
                        ja          .numdonepb
                        sub         al,'A'
                        add         al,10
.dodig2                 cmp         al,bl
                        jae         .numdonepb
                        cmp         byte [rbp-0x58],0       ; overflow?
                        jne         .fractloop              ; skip digits
                        test        r12,r12
                        jz          .dodigmul2
                        ; base 2,8,16: shift and add
                        ; first check if overflow would occur
                        cmp         r13,r14
                        seta        byte [rbp-0x58]
                        ja          .fractloop
                        mov         rcx,r12
                        sal         r13,cl
                        add         r13,rax
                        jmp         .fractadd
                        ; base 10: multiply and add
.dodigmul2              mov         rdx,r13
                        imul        rdx,rbx
                        seto        byte [rbp-0x58]
                        jo          .fractloop
                        add         rdx,rax
                        seto        byte [rbp-0x58]
                        jo          .fractloop
                        mov         r13,rdx
                        ; remember we added a fraction digit
.fractadd               inc         word [rbp-0x56]     ; # of digits
                        mov         byte [rbp-0x57],1   ; fract flag
                        jmp         .fractloop
; reading of exponent
;       in E/G mode, the exponent is expected in current number base.
;           in base 2,8,16 mode, the exponent is shifted to the left
;           at the end to turn it into a power of 2 exponent
;       in P mode, the exponent is expected in decimal form.
;           the exponent is a literal power of 2 exponent
;
                        ; exponent E/G[+-]exp (based)
.doexp                  call        tok_getch
                        cmp         rax,-1
                        je          .expdone
                        cmp         rax,' '
                        je          .expdonepb
                        cmp         rax,'+'
                        jne         .notplus3
                        mov         byte [rbp-0x48],0
                        jmp         .doexp
.notplus3               cmp         rax,'-'
                        jne         .notminus3
                        mov         byte [rbp-0x48],1
                        jmp         .doexp
.notminus3              cmp         rax,'0'
                        jb          .chkexp3
                        cmp         rax,'9'
                        ja          .chkexp3
                        sub         al,'0'
                        jmp         .dodig3
.chkexp3                cmp         al,'A'
                        jb          .expdonepb
                        cmp         al,'F'
                        ja          .expdonepb
                        sub         al,'A'
                        add         al,10
.dodig3                 cmp         al,bl
                        jae         .expdonepb
                        test        r12,r12
                        jz          .dodigmul3
                        ; base 2,8,16: shift and add
                        mov         rcx,r12
                        sal         qword [rbp-0x38],cl
                        add         qword [rbp-0x38],rax
                        jmp         .doexp
                        ; base 10: multiply and add
.dodigmul3              mov         rdx,[rbp-0x38]
                        imul        rdx,rbx
                        add         rdx,rax
                        mov         [rbp-0x38],rdx
                        jmp         .doexp
                        ; exponent done
.expdone                cmp         byte [rbp-0x48],0
                        je          .expplus
                        neg         qword [rbp-0x38]
                        ; in non-decimal mode, premultiply the exponent
                        ; by multiplying it with the base shift
.expplus                cmp         bl,10
                        je          .numdone
                        mov         rdx,[rbp-0x38]
                        imul        rdx,r12
                        mov         [rbp-0x38],rdx
                        jmp         .numdone
.expdonepb              mov         [sourceputback],rax
                        jmp         .expdone
                        ; exponent P[+-]powerof2
                        ;   exponent is always base 10
.dopexp                 call        tok_getch
                        cmp         rax,-1
                        je          .pexpdone
                        cmp         rax,' '
                        je          .pexpdonepb
                        cmp         rax,'+'
                        jne         .notplus4
                        mov         byte [rbp-0x48],0
                        jmp         .dopexp
.notplus4               cmp         rax,'-'
                        jne         .notminus4
                        mov         byte [rbp-0x48],1
                        jmp         .dopexp
.notminus4              cmp         rax,'0'
                        jb          .numdonepb
                        cmp         rax,'9'
                        ja          .numdonepb
                        sub         al,'0'
                        mov         rdx,[rbp-0x38]
                        imul        rdx,10
                        add         rdx,rax
                        mov         [rbp-0x38],rdx
                        jmp         .dopexp
.pexpdone               mov         byte [rbp-0x47],1   ; 'P' mode
                        cmp         byte [rbp-0x48],0   ; neg exp?
                        je          .numdone
                        neg         qword [rbp-0x38]
                        jmp         .numdone
.pexpdonepb             mov         [sourceputback],rax
                        jmp         .pexpdone
                        ; finished; check if we have something non-zero
.numdone                test        r13,r13
                        setnz       al
                        or          al,[rbp-0x57]
                        jz          .zeroresult
; exponent fixup and final number computations:
; the exponent is calculated using overflow, fraction and user-supplied value,
; and then the final number is computed from the integral part and the fixed-up
; exponent.
;
; examples:
; - regular value with integral part (and fractional part)
;       1234.56         int:123456, frac:2, 123456 * 10^-2
; - overshot value with integral part plus invisible exponent
;       1234[00]        int:1234, extra:2, 1234 * 10^2
                        ; fixup exponent before normalization
                        cmp         bl,10
                        je          .decfixexp
; in non-decimal mode, we don't need the FPU to construct a floating-point
; value.
                        ; first, get int(logbase(integerpart))
                        ; get highest bit that is set
                        ; this is also the 2^n exponent
                        bsr         rax,r13
; 16^n = 2^(4*n)
;  8^n = 2^(3*n)
;  2^n = 2^(1*n)
; thus, the exponent needs only be multiplied by the base shift
                        mov         rcx,r12
                        ; check for overflow
                        cmp         byte [rbp-0x58],0       ; overflow?
                        je          .no_ovf2
                        ; yes: add additional powers of (base)
                        movzx       rdx,word [rbp-0x54]
                        imul        rdx,rcx
                        add         rax,rdx
                        jmp         .nondecexpdone  ; cannot have fraction
                        ; check for fraction
.no_ovf2                cmp         byte [rbp-0x57],0
                        je          .nondecexpdone  ; no fraction
                        ; subtract powers of (base)
                        movzx       rdx,word [rbp-0x56]
                        imul        rdx,rcx
                        sub         rax,rdx
                        ; now add the user-supplied exponent
                        ; NOTE that in nondecimal mode, the user-supplied
                        ; exponent must already have been premultiplied
                        ; with the base in E/G mode, but not in P mode
.nondecexpdone          add         rax,[rbp-0x38]
                        ; now check for maxima / minima and limit the exponent
                        ; accordingly.
                        cmp         rax,-1022
                        jl          .zeroresult
                        cmp         rax,1023
                        jg          .infresult
                        ; get biased exponent
                        add         rax,1023
                        ; shift into position
                        shl         rax,52
                        ; get highest bit of integral part
                        bsr         rdx,r13
                        cmp         dl,52
                        jb          .mant2left
                        ja          .mant2right
                        jmp         .mantdone
                        ; mantissa needs to be shifted to the left into pos
.mant2left              mov         cl,52
                        sub         cl,dl
                        shl         r13,cl
                        jmp         .mantdone
                        ; mantissa needs to be shifted to the right into pos
.mant2right             mov         cl,dl
                        sub         cl,52
                        shr         r13,cl
                        ; get shifted mantissa and mask off unnecessary bits
.mantdone               mov         rdx,0x000fffffffffffff
                        and         rdx,r13
                        ; combine
                        or          rax,rdx
                        ; finished
                        jmp         .done
                        ; regular fixup for base 10
                        ; set rounding mode to round down
.decfixexp              fclex
                        fstcw       word [rbp-0x52]
                        mov         dx,[rbp-0x52]   ; dx ctrl backup
                        mov         ax,dx
                        and         ax,0xf0c0
                        or          ax,0x0f3f   ; xcpt off, hi prec, rnd2z
                        mov         [rbp-0x52],ax
                        fldcw       word [rbp-0x52]
                        mov         [rbp-0x52],dx   ; safekeep ctrl backup
                        xor         rax,rax
                        ; check for overflow of integral part
                        cmp         byte [rbp-0x58],0       ; overflow?
                        je          .no_ovf                 ; nope
                        ; yes: add additional powers of 10
                        movzx       rax,word [rbp-0x54]
                        jmp         .no_frac    ; cannot have fraction
                        ; no: check for fraction, subtract powers of 10
.no_ovf                 cmp         byte [rbp-0x57],0
                        je          .no_frac
                        movzx       rax,word [rbp-0x56]
                        neg         rax
                        ; finally, add user-supplied exponent
.no_frac                cmp         byte [rbp-0x47],0   ; 'P' mode
                        jne         .skipusr1           ; yes->
                        add         rax,[rbp-0x38]
                        ; compute final number
                        ; result = intpart * 10^exp
.skipusr1               mov         [rbp-0x40],rax  ; exp
                        ; compute 2^(exp*log2(10))
                        fild        qword [rbp-0x40]
                        fldl2t                  ; log2(10) constant
                        fmulp                   ; * exp
                        cmp         byte [rbp-0x47],0   ; 'P' mode
                        je          .skipusr2           ; no->
                        fild        qword [rbp-0x38]    ; + pexp
                        faddp
.skipusr2               fld1
                        fld         st1     ; save int part for scale
; at this point, the FPU stack should look like this:
;   st2     log2(10)*exp -OR- exp (only int part will be used for scale)
;   st1     1
;   st0     log2(10)*exp -OR- exp
.loop_prem              fprem               ; n=fmod(log2(10)*exp,1)
                        fstsw       ax
                        test        ax,0x0400
                        jnz         .loop_prem
; at this point, the FPU stack should look like this:
;   st2     log2(10)*exp -OR- exp (only int part will be used for scale)
;   st1     1
;   st0     n=fmod(log2(10)*exp -OR- exp,1) (fraction of log2(10)*exp -OR- exp)
; (the reason for doing fmod() was that f2xm1 only takes -1..+1 args)
                        f2xm1               ; (2^n-1)+1
                        faddp
; at this point, the FPU stack should look like this:
;   st1     log2(10)*exp -OR- exp (only int part will be used for scale)
;   st0     (2^fmod(log2(10)*exp -OR- exp,1)-1)+1
; fscale takes the int part of st1 and adds it to the exponent of st0,
; effectively resulting in 2^(exp*log2(10))
                        fscale
                        ; swap result up, and remove temporary values
                        fxch        st1
                        ffree       st0
                        fincstp
                        ; multiply with intpart
                        mov         [rbp-0x40],r13
                        fild        qword [rbp-0x40]
                        fmulp
                        ; done
                        fstp        qword [rbp-0x40]
                        ; restore FPU settings
                        fclex
                        fldcw       word [rbp-0x52]
                        ; get return value
                        mov         rax,[rbp-0x40]
.done                   mov         r14,[rbp-0x20]
                        mov         r13,[rbp-0x18]
                        mov         r12,[rbp-0x10]
                        mov         rbx,[rbp-0x08]
                        leave
                        ret
.numdonepb              mov         [sourceputback],rax
                        jmp         .numdone
.zeroresult             xor         rax,rax
                        jmp         .done
.infresult              mov         rax,0x7ff0000000000000  ; +inf
                        jmp         .done

; ---------------------------------------------------------------------------

                        ; Write number to Unicode output buffer
                        ;
                        ; rdi - IEEE double precision floating-point
                        ; rsi - base (2,8,10,16)
                        ;
                        ; local variables:
                        ;   [rbp-0x02] small int temporary (word); val10
                        ;   [rbp-0x04] small int temporary (word): dig10
                        ;   [rbp-0x06] small int temporary (word): exp10
                        ;   [rbp-0x08] FPU config backup (word)
                        ;   [rbp-0x10] R12 backup
                        ;   [rbp-0x18] RDI (parameter) backup
                        ;   [rbp-0x20] test: result significand
                        ;   [rbp-0x30] test: result bcd
                        ;   [rbp-0x38] R13 backup
                        ;
detok_wrnum             enter       0x40,0
                        mov         [rbp-0x10],r12
                        mov         [rbp-0x18],rdi
                        mov         [rbp-0x38],r13

                        ; clear sign (must be processed by caller)
                        mov         rdx,0x7fffffffffffffff
                        and         rdi,rdx
                        ; check for common special values
                        cmp         rdi,0x0000000000000000
                        je          .zero
                        mov         rdx,0x7ff0000000000000
                        cmp         rdi,rdx
                        je          .inf
                        mov         rax,rdi
                        and         rax,rdx
                        cmp         rdi,rdx
                        je          .nan


                        cmp         rsi,10
                        je          .base10


                        jmp         .done

                        ; for base 10, first initialize the FPU to use
                        ; round-towards-zero
.base10                 fclex
                        fstcw       word [rbp-0x08]
                        mov         dx,[rbp-0x08]   ; dx ctrl backup
                        mov         ax,dx
                        and         ax,0xf0c0
                        or          ax,0x0f3f   ; xcpt off, hi prec, rnd2z
                        mov         [rbp-0x08],ax
                        fldcw       word [rbp-0x08]
                        mov         [rbp-0x08],dx   ; safekeep ctrl backup

                        ; first, convert the exponent into base 10
                        ; exp10 = exp2 * log10(2)
                        ;   extract exponent and significand
                        fld         qword [rbp-0x18]
                        fxtract
                        ; st1 - exponent
                        ; st0 - significand
                        fxch
                        ; st1 - significand
                        ; st0 - exponent
                        ;   multiply exp2 with log10(2)
                        fldlg2      ; log10(2)
                        fmulp
                        ; st1 - significand
                        ; st0 - exp10 (exp2 * log10(2))
                        fld         st0
                        ; st2 - significand
                        ; st1 - exp10 (exp2 * log10(2))
                        ; st0 - exp10 (exp2 * log10(2))
                        frndint
                        fist        word [rbp-0x06] ; store int of exp10
                        fsubp       st1,st0
                        ; st1 - significand
                        ; st0 - fraction of exp10
                        ;   convert exp10 fraction back to exp2
                        fldlg2      ; log10(2)
                        fdivp
                        ; st1 - significand
                        ; st0 - fraction of exp10, in exp2 form
                        fld1
                        fld         st1     ; save int part for scale
                        ; st3 - significand
                        ; st2 - fraction of exp10, in exp2 form
                        ; st1 - 1
                        ; st0 - fraction of exp10, in exp2 form
.loop_prem              fprem               ; n=fmod(exp2,1)
                        fstsw       ax
                        test        ax,0x0400
                        jnz         .loop_prem
                        ; st3 - significand
                        ; st2 - fraction of exp10, in exp2 form
                        ; st1 - 1
                        ; st0 - n=fmod(exp2,1)
                        ; (the reason for doing fmod() was that f2xm1 only
                        ;  takes -1..+1 args)
                        f2xm1               ; (2^n-1)+1
                        faddp
                        ; st2 - significand
                        ; st1 - fraction of exp10, in exp2 form
                        ; st0 - n=2^fmod(exp2,1)
                        ; (the reason for doing fmod() was that f2xm1 only
                        ;  takes -1..+1 args)
                        ; fscale takes the int part of st1 and adds it to the
                        ; exponent of st0, effectively resulting in 2^n
                        ; (i.e. 2^(fmod(exp2,1)+int(exp2)))
                        fscale
                        ; st2 - significand
                        ; st1 - fraction of exp10, in exp2 form
                        ; st0 - n=2^exp2
                        ; swap result up, and remove temporary values
                        fxch        st1
                        ffree       st0
                        fincstp
                        ; st1 - significand
                        ; st0 - n=2^exp2
                        ; finally, multiply to get the base10 significand
                        fmulp
; NOW, we have a significand that has one or two digits before the decimal
; point and zero or more digits after the decimal point, and an exponent that
; designates the power of ten to multiply with to get the correct number.
; However, since we want to output the number, we need to bring it as close
; to an integral value as possible to get all the digits we can. The FPU has
; a BCD write function that takes an up to 18 digit long integer and stores it
; as a packed BCD number in memory. So, we begin multiplying with 10, until
; either there's no more digits after the decimal point (fmod(n,1)=0), or the
; maximum number of digits (18) has been reached. We need to keep track how
; often we multiplied. First, we have to determine the number of digits before
; the decimal point, so we don't overshoot the maximum digit range.
                        fld         st0     ; copy the result
                        ; st1 - result
                        ; st0 - result
                        fld1
                        fxch
                        ; st2 - result
                        ; st1 - 1
                        ; st0 - result
                        fyl2x   ; 1 * log2(result)
                        ; st1 - result
                        ; st0 - log2(result)
                        fldl2t  ; / log2(10)
                        fdivp
                        ; st1 - result
                        ; st0 - log10(result)
                        fistp   word [rbp-0x04]
                        ; preset val10
                        mov     ax,10
                        mov     word [rbp-0x02],ax
                        ; clear shift counter
                        xor     cx,cx
                        ; multiplication loop
.upscaleloop            mov     ax,word [rbp-0x04]
                        cmp     ax,17
                        jge     .upscaleend
                        ; check if fmod(n,1)=0
                        fld     st0
                        fld1
                        fxch
                        ; st2 - scaled result
                        ; st1 - 1
                        ; st0 - scaled result
.loop_prem2             fprem
                        fstsw       ax
                        test        ax,0x0400   ; C2 = 1?
                        jnz         .loop_prem2
                        ; st2 - scaled result
                        ; st1 - 1
                        ; st0 - fmod(n,1)
                        ; analyze result, store status in AX
                        fxam
                        fstsw       ax
                        ; free intermediate results
.check                  ffree       st0
                        ffree       st1
                        fincstp
                        fincstp
                        ; now test status (fmod(n,1)=0?)
                        test        ax,0x4000   ; C3 = 1?
                        jnz         .upscaleend
                        ; multiply with 10
                        ; st0 - scaled result
                        fild    word [rbp-0x02]
                        fmulp
                        inc     word [rbp-0x04]
                        inc     cx
                        jmp     .upscaleloop
.upscaleend             mov     word [rbp-0x04],cx ; save shift counter
                        ; before rounding, rounding mode has to be reset
                        ; to round to nearest
                        mov         dx,[rbp-0x08]   ; dx ctrl backup
                        mov         ax,dx
                        and         ax,0xf0c0
                        or          ax,0x033f   ; xcpt off, hi prec, rnd2n
                        mov         [rbp-0x08],ax
                        fldcw       word [rbp-0x08]
                        mov         [rbp-0x08],dx   ; safekeep ctrl backup
                        ; round number to nearest integer
                        ; frndint
                        ; store result as BCD
                        fld         st0
                        fbstp       [rbp-0x30]
                        ;
                        ; store result for printing
                        fstp        qword [rbp-0x20]
                        ; restore FPU settings
                        fclex
                        fldcw       word [rbp-0x08]
                        ; print result
                        lea         rdi,[wrnum_fmt]
                        movq        xmm0,[rbp-0x20]
                        movsx       rsi,word [rbp-0x04]
                        movsx       rdx,word [rbp-0x06]
                        mov         al,1
                        call        printf
                        ; print hexdump of BCD number
                        lea         r12,[rbp-0x30]
                        lea         r13,[r12+10]
.hexloop                cmp         r12,r13
                        jae         .hexend
                        lea         rdi,[wrnum_dumpbyte]
                        movzx       rsi,byte [r12]
                        inc         r12
                        xor         al,al
                        call        printf
                        jmp         .hexloop
.hexend                 lea         rdi,[wrnum_lf]
                        xor         al,al
                        call        printf

                        ;
.done                   mov         r13,[rbp-0x38]
                        mov         r12,[rbp-0x10]
                        leave
                        ret

.outfixed               xor         rax,rax
                        mov         al,[r12]
                        test        rax,rax
                        jz          .done
                        mov         rdi,rax
                        call        ucputcp
                        inc         r12
                        jmp         .outfixed

.zero                   lea         r12,[fixed_zero]
                        jmp         .outfixed

.inf                    lea         r12,[fixed_inf]
                        jmp         .outfixed

.nan                    lea         r12,[fixed_nan]
                        jmp         .outfixed

; ---------------------------------------------------------------------------

                        section     .rodata

rdnum_fmt               db          "number: 0x%016Lx %g",10,0
fixed_zero              db          "0",0
fixed_inf               db          "INF",0
fixed_nan               db          "NAN",0
wrnum_fmt               db          "man10 = %g, dig10 = %d, exp10 = %d",10,0
wrnum_dumpbyte          db          " %02x",0
wrnum_lf                db          10,0

                        align       8,db 0
