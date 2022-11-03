#   AsmBASIC - a BASIC interpreter written in assembly language
#   Copyright (C) 2022  Ekkehard Morgenstern
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#   NOTE: Programs created with AsmBASIC do not fall under this license.
#
#   CONTACT INFO:
#       E-Mail: ekkehard@ekkehardmorgenstern.de
#       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
#             Germany, Europe

ifdef DEBUG
ASMOPT=-g -F dwarf
LNKOPT=-g
else
ASMOPT=
LNKOPT=-s
endif

.SUFFIXES:	.nasm

.nasm.o:
	nasm -f elf64 $(ASMOPT) -l $*.lst -o $@ $<

all:	asmbasic
	echo ok >all

clean:
	rm asmbasic *.o *.lst

MODULES=main.o patchbay.o locale.o unicode.o xalloc.o tokens.o toknum.o

asmbasic: $(MODULES)
	gcc $(LNKOPT) -Wall -o asmbasic $(MODULES) -lc

main.o: 	main.nasm

patchbay.o:	patchbay.nasm

locale.o: 	locale.nasm

unicode.o: 	unicode.nasm

xalloc.o: 	xalloc.nasm

tokens.o: 	tokens.nasm

toknum.o: 	toknum.nasm
