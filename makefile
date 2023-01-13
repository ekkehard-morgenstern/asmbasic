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
LNKOPT=-g -no-pie
else
ASMOPT=
LNKOPT=-s -no-pie
endif

.SUFFIXES:	.nasm

.nasm.o:
	nasm -f elf64 $(ASMOPT) -l $*.lst -o $@ $<

all:	asmbasic
	echo ok >all

clean:
	rm asmbasic *.o *.lst

MODULES=main.o osversion.o cpuinfo.o locale.o unicode.o xalloc.o patchbay.o \
		stdconsole.o sdlconsrv.o sdlconcli.o sdlconcev.o sdlconshr.o tokens.o \
		toknum.o 8x12font1.o

# NOTE: pkg-config --cflags --libs sdl2

asmbasic: $(MODULES)
	gcc $(LNKOPT) -pthread -Wall -o asmbasic $(MODULES) -lrt -lSDL2

main.o: 	main.nasm

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

sdlconshr.o: sdlconshr.nasm sdlconshr.inc

tokens.o: 	tokens.nasm

toknum.o: 	toknum.nasm

8x12font.o: 8x12font.nasm
