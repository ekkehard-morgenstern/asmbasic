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

SDL_TEXTSCREENWIDTH     equ         80
SDL_TEXTSCREENHEIGHT    equ         25
SDL_TEXTSCREENCELLS     equ         SDL_TEXTSCREENWIDTH*SDL_TEXTSCREENHEIGHT
SDL_SCREENWIDTH         equ         SDL_TEXTSCREENWIDTH*8
SDL_SCREENHEIGHT        equ         SDL_TEXTSCREENHEIGHT*12

                        struc       screencell
                            sc_col: resb    1   ; bits 4..7: bgpen, 0..3: fgpen
                            sc_chr: resb    1
                        endstruc

SDL_SCREENBUFSIZE       equ         screencell_size*SDL_TEXTSCREENCELLS
