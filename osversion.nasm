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
                        global      chkkernver
                        extern      uname,perror,exit,strcmp,stderr,fprintf
                        extern      sscanf

                        ; This is necessary in the SQL driver b/c we want to
                        ; use the epoll API which has various quirks in earlier
                        ; Linux versions, so we have to refuse to run on those
                        ; older kernel releases.
                        ;
                        ; This call does nothing if we're not running on Linux;
                        ; This assumes correct epoll API implementation in this
                        ; case (application won't link if not present).
                        ;
chkkernver              enter       0,0

                        ; clear out result buffer
                        lea         rdi,[unamebuf]
                        xor         rax,rax
                        mov         rcx,390/8
                        cld
                        rep         stosq

                        ; NOTE: The library version of uname(2) calls whichever
                        ; version of uname(2) is the most current. Thus, the
                        ; memory layout of the returned data can vary.
                        lea         rdi,[unamebuf]
                        call        uname
                        test        eax,eax
                        jz          .noerror

                        lea         rdi,[unamepfx]
                        call        perror

.fail                   mov         rdi,1
                        call        exit

                        ; the first field contains the OS name
.noerror                lea         rdi,[unamebuf]
                        lea         rsi,[linuxname]
                        call        strcmp
                        test        eax,eax
                        jnz         .verok  ; not Linux, skip ->

                        ; the third field designates the kernel release
                        ; it can be at offset 2*9 or 2*65
                        cmp         byte [unamebuf+2*65],0
                        jnz         .release265

                        cmp         byte [uname+2*9],0
                        jnz         .release29

                        mov         rdi,[stderr]
                        lea         rsi,[releaseinfonotfound]
                        xor         al,al
                        call        fprintf

                        jmp         .fail

.release265             lea         rdi,[unamebuf+2*65]
                        jmp         .releasechk

.release29              lea         rdi,[unamebuf+2*9]

.releasechk             mov         [releaseptr],rdi
                        lea         rsi,[releasescanfmt]
                        lea         rdx,[major]
                        lea         rcx,[minor]
                        lea         r8,[release]
                        xor         al,al
                        call        sscanf
                        cmp         eax,3
                        je          .scanok

                        mov         rdi,[stderr]
                        lea         rsi,[badreleasestr]
                        mov         rdx,[releaseptr]
                        xor         al,al
                        call        fprintf

                        jmp         .fail

.badver                 mov         rdi,[stderr]
                        lea         rsi,[badrelease]
                        mov         rdx,[releaseptr]
                        xor         al,al
                        call        fprintf

                        jmp         .fail

.scanok                 cmp         dword [major],3
                        jae         .verok
                        cmp         dword [major],2
                        jb          .badver
                        cmp         dword [minor],6
                        jb          .badver
                        cmp         dword [release],37
                        jb          .badver

.verok                  leave
                        ret

                        section     .rodata

unamepfx                db          '? uname(2)',0
linuxname               db          'Linux',0
releaseinfonotfound     db          '? kernel release info not found',10,0
releasescanfmt          db          '%u.%u.%u',0
badreleasestr           db          '? unsupported kernel release format "%s"'
                        db          10,0
badrelease              db          '? unsupported kernel release "%s"',10,0

                        align       8,db 0

                        section     .bss

releaseptr              resq        1
unamebuf                resq        390/8
major                   resd        1
minor                   resd        1
release                 resd        1
                        resd        1
