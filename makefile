
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

MODULES=main.o xalloc.o tokens.o

asmbasic: $(MODULES)
	gcc $(LNKOPT) -Wall -o asmbasic $(MODULES) -lc

main.o: 	main.nasm

xalloc.o: 	xalloc.nasm

tokens.o: 	tokens.nasm
