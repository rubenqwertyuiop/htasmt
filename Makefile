
all: htasmt test

test: test.c
	cc test.c -o test

htasmt: htasmt.S
	nasm -f elf64 htasmt.S -o htasmt.o
	ld htasmt.o -o htasmt

install: htasmt
	cp htasmt /usr/local/bin

clean:
	rm -f test htasmt htasmt.o

