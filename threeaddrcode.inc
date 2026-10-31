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


                        struc      tacword
                            tw_opcode:      resq    1
                            tw_target:      resq    1
                            tw_sourc1:      resq    1
                            tw_sourc2:      resq    1
                        endstruc



                        struc       tacobj
                            to_class:       resb    1
                            to__reserved1:  resb    7
                            to_refcnt:      resq    1
                            to_cleanup:     resq    1
                            to_print:       resq    1
                        endstruc

TOC_UNDEF               equ         0
TOC_VALUE               equ         1
TOC_VARIABLE            equ         2

                        struc       tacval
                            tvl_base:       resq    tacobj_size/8
                            tvl_type:       resb    1
                            tvl_flags:      resb    1
                            tvl_reserved1:  resb    6
                            tvl_data:       resq    1
                        endstruc

TVLT_UNDEF              equ         0
TVLT_NUMBER             equ         1
TVLT_STRING             equ         2
TVLF_HASVALUE           equ         1

                        struc       tacvar
                            tvr_base:       resq    tacobj_size/8
                            tvr_type:       resb    1
                            tvr_flags:      resb    1
                            tvr__reserved1: resb    6
                            tvr_name:       resq    1
                            tvr_info:       resq    1
                            tvr_data:       resq    1
                        endstruc

TVRT_UNDEF              equ         0
TVRT_NUMBER             equ         1
TVRT_STRING             equ         2
TVRT_NUMARRAY           equ         3
TVRT_STRARRAY           equ         4
TVRF_HASINFO            equ         1
TVRF_TEMPORARY          equ         2
TVRF_LOCAL              equ         4
TVRF_GLOBAL             equ         8
