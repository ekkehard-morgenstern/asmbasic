# Usage, testing and debugging

## Running

```
./asmbasic [options] [file]
```

| Option | Short | Meaning |
|---|---|---|
| `--help` | `-h` | print usage to stderr and exit(1) |
| `--sdl` | `-d` | SDL window console (default) |
| `--stdio` | `-s` | standard I/O console |
| `--curses` | `-c` | ncurses — **not implemented**: prints `? Curses mode is not implemented, using standard I/O` and behaves like `--stdio` |
| `--testtok` | | tokenizer test mode (detokenize round trip), no parsing |
| `--dumppt` | | print the parse tree and exit |
| `--stndebug` | | log syntax tree node creation/deletion |
| `--stnprint` | | print the raw syntax tree after each line |
| `--csnprint` | | print the cooked syntax tree (already the default: `csnprint` starts at 1) |

Bad options print `? Bad option "…" ignored`; a second filename prints `? Extra filename ignored`. The filename is
stored but unused; a non-empty filename prints `? Loading files is not implemented, ignored: <name>` (stderr).

## Interactive behaviour

Greeting `AsmBASIC v0.0.8` plus a blank line, then `Ready.`. There is no other prompt string; input is read at the cursor. Each non-empty line is tokenized, parsed and its trees are
printed. Empty lines are ignored (verified; they used to end the program). The program ends at end of input (Ctrl-D / EOF) or, in SDL mode, ESC. Errors:

- `? Tokenizer failure` — token buffer exhausted
- `? Identifier or string too long` — an identifier or string literal over 1004 bytes
- `? Syntax error` — nothing matched
- `? Syntax error near <<…>>` — a prefix matched, the shown text is the rest of the line (verified: `10 PRINT 1 2` → `? Syntax error near << 2>>`; the detokenized remainder starts with a space). After an error `Ready.` is printed again.

In SDL mode: the window is full-screen desktop; **ESC quits** the worker thread (and thereby the program); Backspace
and Return are handled as special keys; other text arrives via SDL text input events. The text screen is 80×25 cells
of 8×12 pixels.

## Manual test recipe

There is no test suite. For changes:

1. `make -B` (or `make DEBUG=1 -B` for gdb).
2. `./asmbasic --stdio --testtok` and feed keyword/number lines; compare input with the detokenized output.
   Examples: `PRINT "A";B$`, `&HFF + &B101`, `1.5E+3`, `left$(a$,2)`.
3. `./asmbasic --stdio --stnprint` with representative statements from each group (assignment, `IF … THEN`, `FOR`,
   `DIM`, `PRINT USING`, `DEF FN`, `ON … GOTO`, line numbers).
4. Compare cooked-tree output before/after a grammar change.
5. Pipe input for repeatable checks: `printf '10 PRINT "HI"\n' | ./asmbasic --stdio` (EOF ends the program).

Capture baseline outputs *before* editing the grammar, since the output is the only oracle.

## Debugging tips

- `make DEBUG=1 -B` and `gdb ./asmbasic`; listings (`*.lst`) give addresses and machine code for each source line.
- `--stndebug` shows syntax-node allocation; use it with `valgrind` to look for leaks and double frees
  (`valgrind` works with the stdio mode; the SDL mode adds noise).
- Stack misalignment before `call` into libc/SDL shows up as crashes in `movaps` — check `rsp` alignment and `al` for
  variadic calls (`abinotes.txt`).
- `--dumppt` verifies that the generated grammar table was built and expanded correctly.

## Verified sessions (2026-10-31, after `make -B`)

```
$ ./asmbasic --help          # usage text as listed above, printed to stderr, exit status 1
$ printf '10 PRINT "HI"\n' | ./asmbasic --stdio
AsmBASIC v0.0.8

Ready.
(generic)
  S_NUMBER,base 10,"10"
  S_STATEMENT
    S_KEYWORD,KW_PRINT
    S_STRLIT,"HI"
$ ./asmbasic -x --stdio </dev/null     →  ? Bad option "x" ignored
$ ./asmbasic --stdio a b </dev/null    →  ? Extra filename ignored: b
```

The `--testtok` mode prints a colour test banner (ANSI escape codes) before the first line. SDL mode could not be tried
in this environment (the process just waits); its behaviour in `console-subsystem.md` is from reading the source.
