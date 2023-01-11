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

                        %include    "sdlconshr.inc"

                        section     .bss

                        global      sdl_worker_handle,sdl_worker_result
                        global      sdl_worker_doquit,sdl_worker_terminated
                        global      sdl_init_ok,sdl_want_input,sdl_have_input
                        global      sdl_background_rgba,sdl_return_pressed
                        global      sdl_screenbuf,sdl_workbuf,sdl_screenmem
                        global      sdl_textcursor_pos,sdl_textscreen_width
                        global      sdl_textscreen_height,sdl_textscreen_size
                        global      sdl_worker_doquit,sdl_init_ok
                        global      sdl_worker_handle,sdl_worker_result
                        global      sdl_ticks,sdl_return_pressed
                        global      sdl_textcursor_visible,sdl_text_attribute
                        global      sdl_want_input,sdl_have_input,sdl_epollhnd

sdl_worker_handle       resq        1
sdl_worker_result       resq        1
sdl_worker_doquit       resq        1
sdl_worker_terminated   resq        1

sdl_init_ok             resq        1
sdl_want_input          resq        1
sdl_have_input          resq        1
sdl_background_rgba     resq        1
sdl_return_pressed      resq        1
sdl_textcursor_pos      resq        1
sdl_ticks               resq        1
sdl_textcursor_visible  resq        1
sdl_text_attribute      resq        1
sdl_epollhnd            resd        1
                        resd        1

sdl_textscreen_width    resq        1
sdl_textscreen_height   resq        1
sdl_textscreen_size     resq        1

sdl_screenbuf           resq        SDL_SCREENBUFSIZE/8
sdl_screenbuf_size_val  equ         $-sdl_screenbuf

sdl_workbuf             resq        SDL_SCREENBUFSIZE/8
sdl_workbuf_size_val    equ         $-sdl_workbuf

                        section     .data

                        global      sdl_screenbuf_size,sdl_workbuf_size
                        global      sdl_textbgpalette,sdl_textfgpalette

sdl_screenbuf_size      dq          sdl_screenbuf_size_val
sdl_workbuf_size        dq          sdl_workbuf_size_val

sdl_textbgpalette       dd          0x00000000  ; transparent
                        dd          0xFFCCCCCC  ; white
                        dd          0xFF0000AA  ; blue
                        dd          0xFF00AAAA  ; cyan
                        dd          0xFFCCCC00  ; yellow
                        dd          0xFFCC8800  ; orange
                        dd          0xFFAA0000  ; red
                        dd          0xFF00AA00  ; green
                        dd          0xFFAA00AA  ; magenta
                        dd          0xFF888888  ; gray
                        dd          0xFF444444  ; dark gray
                        dd          0xFF000000  ; black
                        dd          0xFFAAAAAA  ; light gray
                        dd          0xFFCC0088  ; pink
                        dd          0xFF8800CC  ; purple
                        dd          0xFF00CC88  ; sea green

sdl_textfgpalette       dd          0xFF000000  ; black
                        dd          0xFFFFFFFF  ; white
                        dd          0xFF0000FF  ; blue
                        dd          0xFF00FFFF  ; cyan
                        dd          0xFFFFFF00  ; yellow
                        dd          0xFFFF8800  ; orange
                        dd          0xFFFF0000  ; red
                        dd          0xFF00FF00  ; green
                        dd          0xFFFF00FF  ; magenta
                        dd          0xFFAAAAAA  ; gray
                        dd          0xFF666666  ; dark gray
                        dd          0x00000000  ; transparent
                        dd          0xFFCCCCCC  ; light gray
                        dd          0xFFFF0088  ; pink
                        dd          0xFF8800FF  ; purple
                        dd          0xFF00FF88  ; sea green
