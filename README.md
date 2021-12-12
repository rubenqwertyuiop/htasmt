
# htasmt
hyper text assembly transfer
[A screenshot of htasmt in lynx](/lynx.png?raw=true "htasmt in lynx")

# Compilation
htasmt is a http fileserver written in x86\_64 assembly.
Because of this you will need `nasm` and a linker named `ld` (such as the
one provided in the `binutils` package). The build system used is a plain
makefile, although you can compile htasmt without it with relative ease.
You can install all of those on ubuntu with `apt install binutils nasm make`.
To actually compile you just write `make` in the source directory, or if you
don't have `make` but do have `nasm` and `ld`:
`nasm -f elf64 htasmt.S -o htasmt.o; ld htasmt.o -o htasmt`.
You can optionally install htasmt with `make install` (or `cp htasmt /usr/local/bin`).

# Usage
To run htasmt just run the `htasmt` command. It will spawn a server on `0.0.0.0:8000`.
To get your IP-address you can check the output of `ifconfig`. If you just want to test
on the same computer as you're hosting the server typing `http://0.0.0.0:8000` in your
browsers address bar will work as well. To close the server press CTRL+C or send a SIGINT
signal to the htasmt process: `killall -SIGINT htasmt`.

