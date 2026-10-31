# Roadmap and known issues

Open work. Keep this file current (see `CLAUDE.md`). Status date: 2026-10-31.

## Planned next steps (author's design, `implnotes.txt` "Planned Features")

1. **Variable storage** — decide between direct heap allocation (`xalloc`/`malloc`) and a memory pool
   (`collect.nasm` is an unfinished pool draft).
2. **Intermediate code** — three-address code (`threeaddrcode.inc` has the first structs):
   - `tacword`: `opcode, target, source1, source2` (4 × qword).
   - `tacobj` (class, refcount, cleanup, print function pointers), `tacval` (value descriptor: number/string),
     `tacvar` (variable: type, flags `HASINFO/TEMPORARY/LOCAL/GLOBAL`, name, info, data).
   - Operands are pointers to descriptors; descriptors must distinguish temporaries, user variables and arguments, and
     be context-sensitive (parent descriptors).
   - Planned opcodes: call frames (`BEGINCALL, ARGUMENT, RESULT, CALL, ENDCALL`), arithmetic/logic/comparison
     (`ADD SUB MUL DIV AND OR XOR NOT CONCAT NUMEQ… STREQ…`), branches (`BRIT BRIF BRANCH`), `MOVE`, declarations
     (`GLOBAL DIMENSION ERASE`), frames (`BEGINFRAME LOCAL REFLOCAL REFGLOBAL ENDFRAME`), loops (`BEGINLOOP ITERATE AGAIN
     LEAVE ENDLOOP`), conditions (`BEGINCOND CONDEXPR CONDTRUE CONDFALSE ENDCOND`), `LABEL`.
   - Variable rules: numbers preset to 0, strings to `""`; undimensioned arrays are 1-D with 0..10; arrays are always
     one-dimensional internally.
3. **Code generation** from the cooked syntax tree (replace the `; tbd` in `main_loop`), then execution (compile and go).
4. **Program store** for numbered lines, `LIST/RUN/…` direct commands.

## Known issues and observations

(Found by reading; not all reproduced.)

- The detokenized text differs from the input (upper-casing, odd spacing like ` PRINT"a"; B$`, hex numbers shown as `&H1.FEP7`); fine for debugging but not a faithful `LIST`.
- None of the NASM sources has a `.note.GNU-stack` section; the makefile links with `-z noexecstack` instead. A new module that really needs an executable stack would have to change that.
- Cooked tree is not fully flattened: `(generic)` and single-operand `S_EXPRESSION` wrapper nodes remain.
- Buffer sizes are fixed (`linebuf` 16 KiB, `tokenpad` 32 KiB, ident/string 1 KiB). Over-long identifiers/strings (> 1004 bytes) and token-heavy lines now fail with an error message, but the limits remain.
- `--curses` and a file name argument only print a notice (the features do not exist yet).
- Keywords exist in `tokenlist.txt` that the grammar does not use (see `language.md`).
- Stale scratch files remain in the working tree but are git-ignored and not part of the build (`main.lst.1/.2`,
  `csnrefinery.*`, `x*`, `test*`, `sizes`, `make-*.log`, `foo.txt`). Delete them if you don't need them (not done without
  the author's say-so).
- `ebnfcomp`'s regular-expression support is partly broken (its README); grammar regexes should stay simple. It is now
  vendored, so it can be fixed in this repository.
- Only code points 0–255 are fully supported; the font is 256 glyphs.
- No automated tests.

## Candidate improvements (not started, not requested)

- Add a `tests/` directory with input files and expected `--stdio --csnprint` output plus a `make check` target.
- Track generated include files explicitly in the makefile.
- Remove or archive stale scratch files after confirming with the author.

## Fixed (2026-10-31)

- Makefile dependencies completed (`keywords.inc`, `mainsyntax.inc`, `ebnfcomp` sources, `sdlconcev.inc`, version string); an incremental `make` now rebuilds what changed.
- Identifiers and strings over 1004 bytes were silently cut; now `? Identifier or string too long`.
- An empty input line used to end the program; now it is ignored (EOF/ESC still end it).
- `--curses` and a file name argument were silently ignored; now a notice is printed.
- README corrected.
- Added `bump_version.sh` (bump build/minor/major or set a version, tag creation).

## Decisions pending with the user

- Variable storage strategy and intermediate code format (above).
- Whether generated files should be committed.
