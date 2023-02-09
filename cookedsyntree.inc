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

                        struc      cookedsyntaxnode
                            csn_type:       resb    1
                            csn_subtype:    resb    1
                            csn_numbase:    resb    1   ; for numbers
                            csn__rsvd_1:    resb    1
                            csn_length:     resw    1   ; for str/ident
                            csn_nargs:      resw    1
                            csn_data:       resq    1   ; data ptr
                            csn_args:       resq    1   ; table of argptrs
                        endstruc

S_UNDEF                 equ         0x00
S_NUMBER                equ         0x01
S_OPER                  equ         0x02
S_KEYWORD               equ         0x03
S_LINENUMBER            equ         0xe0
S_STATEMENT             equ         0xe1
S_EXPRESSION            equ         0xe2
S_LINE                  equ         0xe3
S_IDENT                 equ         0xfe
S_STRLIT                equ         0xff

ID_NUM                  equ         0x00
ID_STR                  equ         0x01
ID_NUMFN                equ         0x02
ID_STRFN                equ         0x03

OP_LT                   equ         0x00
OP_LE                   equ         0x01
OP_NE                   equ         0x02
OP_GT                   equ         0x03
OP_GE                   equ         0x04
OP_EQ                   equ         0x05
OP_LPAREN               equ         0x06
OP_RPAREN               equ         0x07
OP_COMMA                equ         0x08
OP_SEMIC                equ         0x09
OP_COLON                equ         0x0a
OP_ADD                  equ         0x0b
OP_SUB                  equ         0x0c
OP_MUL                  equ         0x0d
OP_DIV                  equ         0x0e
OP_POW                  equ         0x0f
OP_AMP                  equ         0x10
OP_CHAN                 equ         0x11

                        %include    "keywords.inc"
