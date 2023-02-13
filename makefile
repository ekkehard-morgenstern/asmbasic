#   AsmBASIC - a BASIC compile and go system written in assembly language
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
LNKOPT=-g -no-pie
else
ASMOPT=
LNKOPT=-s -no-pie
endif

.SUFFIXES:	.nasm .ebnf .pl

.nasm.o:
	nasm -f elf64 $(ASMOPT) -l $*.lst -o $@ $<

all:	ebnfcomp/ebnfcomp asmbasic
	echo ok >all

clean:
	rm asmbasic *.o *.lst ebnfcomp/ebnfcomp

MODULES=main.o osversion.o cpuinfo.o locale.o unicode.o xalloc.o patchbay.o \
		stdconsole.o sdlconsrv.o sdlconcli.o sdlconcev.o sdlconkbd.o \
		sdlconshr.o tokens.o toknum.o 8x12font1.o mainsyntax.o parsetree.o \
		parsenodename.o syntree.o stnflgtbl.o cookedsyntree.o

# NOTE: pkg-config --cflags --libs sdl2

asmbasic: $(MODULES)
	gcc $(LNKOPT) -pthread -Wall -o asmbasic $(MODULES) -lrt -lSDL2

ebnfcomp/ebnfcomp:
	cd ebnfcomp && make && cd ..

mainsyntax.nasm: main.ebnf
	ebnfcomp/ebnfcomp --asm mainsyntax <main.ebnf

parsenodename.nasm: mainsyntax.inc extract_nodetext.pl
	./extract_nodetext.pl >parsenodename.nasm

stnflgtbl.nasm: mainsyntax.inc extract_stnflgtbl.pl
	./extract_stnflgtbl.pl

main.ebnf: defaultsyntax.ebnf tokenlist.txt build_main_ebnf.pl
	./build_main_ebnf.pl

8x12font1.inc: 8x12font1.txt extract_font.pl
	./extract_font.pl

tokendef.inc: tokenlist.txt extract_tl.pl
	./extract_tl.pl

verstr.inc:
	./tagtoverstr.pl

csntext.inc: cookedsyntree.inc keywords.inc tokendef.inc extract_csntext.pl
	./extract_csntext.pl >csntext.inc

main.o: 	main.nasm verstr.inc

osversion.o: 	osversion.nasm

cpuinfo.o: 	cpuinfo.nasm

locale.o: 	locale.nasm

unicode.o: 	unicode.nasm

xalloc.o: 	xalloc.nasm

patchbay.o:	patchbay.nasm

stdconsole.o: stdconsole.nasm

sdlconsrv.o: sdlconsrv.nasm sdlconshr.inc

sdlconcli.o: sdlconcli.nasm sdlconshr.inc

sdlconcev.o: sdlconcev.nasm sdlconshr.inc sdlconcev.inc

sdlconkbd.o: sdlconkbd.nasm

sdlconshr.o: sdlconshr.nasm sdlconshr.inc

tokens.o: 	tokens.nasm tokendef.inc

toknum.o: 	toknum.nasm

8x12font1.o: 8x12font1.nasm 8x12font1.inc

mainsyntax.o: mainsyntax.nasm mainsyntax.inc

parsetree.o: parsetree.nasm parsetree.inc mainsyntax.inc

parsenodename.o: parsenodename.nasm

syntree.o: syntree.nasm syntree.inc parsetree.inc mainsyntax.inc

stnflgtbl.o: stnflgtbl.nasm syntree.inc

cookedsyntree.o: cookedsyntree.nasm cookedsyntree.inc csntext.inc \
				 syntree.inc parsetree.inc mainsyntax.inc
