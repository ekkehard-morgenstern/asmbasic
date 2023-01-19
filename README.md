# AsmBASIC

An assembly language BASIC compile and go system, initially for x86-64.

The project is in its earliest stages of development, and I have little spare time, so don't expect much.
Code in this repository can change and be restructured without prior warning.

## Compiling

To compile this package, you need to install a C development environment first, and then NASM (the Netwide Assembler), and then the SDL2 development package.
On Debian, Ubuntu and other similar Linux distros, simply write "sudo apt install build-essential nasm libsdl2-dev" to accomplish that.

After making sure you have those tools and libraries, type "make -B" to build the program.

## Using

To use AsmBASIC, either run it on the command line with "./asmbasic" or create a desktop launcher for it to run it from the desktop.

When run from the command line, you can specify the "--help" option to see its command line parameters, as in "./asmbasic --help".

In Standard I/O terminal emulation (switched on with the "--stdio" option), the compile and go system currently enters a loop asking for BASIC input lines and outputting the tokenized form as well as the detokenized form of the input lines.

In default or SDL mode (default, or switched on with the "--sdl" option), the compile and go system currently enters a loop asking for BASIC input lines and outputting the tokenized form as well as the detokenized form of the input lines.

## Limitations

Some of the currently defined limits are as follows:

The current maximum line length is 8191 bytes of UTF-8 text. However, the current maximum line editing length in the SDL driver is 1023 Unicode code points.

The current maximum length of string constants is 1004 bytes of UTF-8 text.

The current maximum length of identifiers is 1004 bytes of UTF-8 text.

Unicode support is currently limited to 8 bit code points (lowest Unicode bank).

The user-modifiable character set in the SDL driver is currently 256 characters of fixed 8 x 12 pixels.

The SDL driver's text screen is currently fixed to 80 x 25 8-bit character cells with 8-bit attribute information, which consists of 4 bit foreground color and 4 bit background color. The user-modifiable palette is currently fixed to 16 colors. Text color consists of 8 foreground and background inks each, which can be selected from the 16 color palette (mainly for ANSI CSI sequence compatibility).

## Playing Around

Since the code is currently in its initial development stages, it might be in a state that cannot be used (like, at all), at any given time.
If this happens, you might notify me of the circumstance, and I will upload a working version as soon as possible.
If I remember, I will make tags at various points during development, so you can go back to a specific version that was usable before.
As soon as the project is far along enough, I will stop making breaking changes to the master, and instead develop on feature branches.
