# AsmBASIC

An assembly language BASIC interpreter, initially for x86-64.

The project is in its earliest stages of development, and I have little spare time, so don't expect much.
Code in this repository can change and be restructured without prior warning.

## Compiling

To compile this package, you need to install a C development environment first, and then NASM (the Netwide Assembler), and then the SDL2 development package.
On Debian, Ubuntu and other similar Linux distros, simply write "sudo apt install build-essential nasm libsdl2-dev" to accomplish that.

After making sure you have those tools and libraries, type "make -B" to build the program.

NOTE: There seems to be a problem with linking on Ubuntu 20.04+. I'm using Debian 10, and this problem doesn't occur for me, so it must be a Ubuntu-specific problem. I'm trying to solve the issue.

## Playing Around

Since the code is currently in its initial development stages, it might be in a state that cannot be used (like, at all), at any given time.
If this happens, you might notify me of the circumstance, and I will upload a working version as soon as possible.
If I remember, I will make tags at various points during development, so you can go back to a specific version that was usable before.
As soon as the project is far along enough, I will stop making breaking changes to the master, and instead develop on feature branches.
