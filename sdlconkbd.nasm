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

                        cpu         x64
                        bits        64

                        ; output of C program printing sizeof(pthread_mutex_t)
PTHREAD_MUTEX__SIZEOF   equ         40
SDL_KBD_BUFSIZ          equ         128
SDL_KBD_POSMSK          equ         127

                        section     .text

                        extern      pthread_mutex_init,pthread_mutex_destroy
                        extern      pthread_mutex_lock,pthread_mutex_unlock
                        extern      atexit

                        global      sdl_kbdinit,sdl_kbdcleanup
                        global      sdl_kbdputbuf,sdl_kbdgetbuf

sdl_kbdinit             enter       0,0

                        lea         rdi,[sdl_kbdmtx]
                        xor         rsi,rsi
                        call        pthread_mutex_init

                        mov         byte [sdl_kbdrdpos],0
                        mov         byte [sdl_kbdwrpos],0

                        lea         rdi,[sdl_kbdcleanup]
                        call        atexit

                        leave
                        ret

sdl_kbdcleanup          enter       0,0
                        lea         rdi,[sdl_kbdmtx]
                        call        pthread_mutex_destroy
                        leave
                        ret

sdl_kbdlockmutex        enter       0,0
                        lea         rdi,[sdl_kbdmtx]
                        call        pthread_mutex_lock
                        leave
                        ret

sdl_kbdunlockmutex      enter       0,0
                        lea         rdi,[sdl_kbdmtx]
                        call        pthread_mutex_unlock
                        leave
                        ret

                        ; write UTF-8 text of a single keypress to the keyboard
                        ; ring buffer. if unsuccessful, no byte will register as
                        ; input data. NOTE: It is useful to know here that the
                        ; SDL console server will only ever call this function
                        ; if the SDL console client has signalled interest in
                        ; input (i.e. when the server is displaying a blinking
                        ; text cursor). Thus, a ring buffer overflow is highly
                        ; unlikely (but is taken care of anyway).
                        ;
                        ; rdi - keyboard buffer to write from
                        ; rsi - length of data to write
                        ;
sdl_kbdputbuf           enter       0x10,0

                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi

                        call        sdl_kbdlockmutex

                        mov         rsi,[rbp-0x08]
                        mov         rcx,[rbp-0x10]

                        test        rcx,rcx
                        jz          .end

                        cld
                        lea         rdi,[sdl_kbdbuf]
                        xor         rdx,rdx
                        mov         dl,[sdl_kbdwrpos]
                        mov         r8b,[sdl_kbdrdpos]

.loopchr                lodsb
                        mov         [rdi+rdx],al

                        inc         dl
                        and         dl,SDL_KBD_POSMSK
                        cmp         dl,r8b
                        je          .end

                        loop        .loopchr
                        mov         [sdl_kbdwrpos],dl

.end                    call        sdl_kbdunlockmutex
                        leave
                        ret

                        ; This function reads the pending byte sequences from
                        ; the keyboard ring buffer in one go; It'll return
                        ; nonzero only if that is possible, and zero otherwise.
                        ;
                        ; rdi - keyboard buffer to read into
                        ; rsi - max. length of data to read (should be larger
                        ;       than or equal to SDL_KBD_BUFSIZ)
                        ;
                        ; returns:
                        ; rax - number of characters that have been read (will
                        ;       always be lower than the maximum specified);
                        ;       zero in case of no data or error

sdl_kbdgetbuf           enter       0x10,0

                        mov         [rbp-0x08],rdi
                        mov         [rbp-0x10],rsi

                        call        sdl_kbdlockmutex

                        mov         rdi,[rbp-0x08]
                        mov         rcx,[rbp-0x10]
                        xor         r9,r9
                        mov         [rbp-0x10],r9

                        cmp         rcx,SDL_KBD_BUFSIZ
                        jl          .end

                        cld
                        lea         rsi,[sdl_kbdbuf]
                        xor         rdx,rdx
                        mov         dl,[sdl_kbdrdpos]
                        mov         r8b,[sdl_kbdwrpos]

.loopchr                cmp         dl,r8b
                        je          .endok

                        mov         al,[rsi+rdx]
                        stosb
                        inc         r9

                        inc         dl
                        and         dl,SDL_KBD_POSMSK

                        loop        .loopchr

                        ; if there are still characters to be read, this means
                        ; that the caller-supplied buffer is too small; act as
                        ; if nothing had been read.

.end                    call        sdl_kbdunlockmutex
                        mov         rax,[rbp-0x10]
                        leave
                        ret

                        ; only when all pending characters have been read in
                        ; one go, then the read position will be updated and the
                        ; number of bytes read will be nonzero. the reason for
                        ; this is that there could be a pending Unicode shift
                        ; or combination sequence embedded in the text that are
                        ; meant to be processed as a single keystroke.

.endok                  mov         [rbp-0x10],r9
                        mov         [sdl_kbdrdpos],dl
                        jmp         .end

                        section     .bss

sdl_kbdmtx              resq        PTHREAD_MUTEX__SIZEOF/8
sdl_kbdbuf              resq        SDL_KBD_BUFSIZ/8
sdl_kbdrdpos            resb        1
sdl_kbdwrpos            resb        1
                        align       8,resb 1
