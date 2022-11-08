# AsmBASIC

An assembly language BASIC interpreter, initially for x86-64.

The project is in its earliest stages of development, and I have little spare time, so don't expect much.
Code in this repository can change and be restructured without prior warning.

## Compiling

To compile this package, you need to install a C development environment first, and then NASM (the Netwide Assembler), and then the SDL2 development package.
On Debian, Ubuntu and other similar Linux distros, simply write "sudo apt install build-essential nasm libsdl2-dev" to accomplish that.

After making sure you have those tools and libraries, type "make -B" to build the program.

## Using

To use AsmBASIC, either run it on the command line with "./asmbasic" or create a desktop launcher for it to run it from the desktop.

When run from the command line, you can specify the "--help" option to see its command line parameters, as in "./asmbasic --help".

In Standard I/O terminal emulation (switched on with the "--stdio" option), the interpreter currently enters a loop asking for BASIC input lines and outputting the tokenized form as well as the detokenized form of the input lines.

In default or SDL mode (default, or switched on with the "--sdl" option), the interpreter currently just shows a blank screen with a blinking cursor. I'm still working on text input/output in the SDL terminal emulation.

## Playing Around

Since the code is currently in its initial development stages, it might be in a state that cannot be used (like, at all), at any given time.
If this happens, you might notify me of the circumstance, and I will upload a working version as soon as possible.
If I remember, I will make tags at various points during development, so you can go back to a specific version that was usable before.
As soon as the project is far along enough, I will stop making breaking changes to the master, and instead develop on feature branches.
