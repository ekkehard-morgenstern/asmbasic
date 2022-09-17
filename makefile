
.SUFFIXES:	.nasm

.nasm.o:
	nasm -f elf64 -o $@ $<

all:	asmbasic
	echo ok >all

MODULES=main.o xalloc.o tokens.o

asmbasic: $(MODULES)
	gcc -Wall -o asmbasic $(MODULES) -lc

main.o: 	main.nasm

xalloc.o: 	xalloc.nasm

tokens.o: 	tokens.nasm
