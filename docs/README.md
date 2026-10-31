# AsmBASIC documentation

AsmBASIC is a BASIC "compile and go" system written in x86-64 NASM assembly for Linux. It is at version v0.0.8 and in
its earliest stage: it can tokenize a line of BASIC, parse it against a grammar into a syntax tree, simplify that into
a "cooked" syntax tree and print it. It cannot execute anything yet.

The project is independent of Engine1999 (a different project in `../engine1999`); nothing is shared.

## Index

| Document | Content |
|---|---|
| [architecture.md](architecture.md) | Overview of the pipeline, modules, data flow and memory ownership |
| [build-system.md](build-system.md) | makefile, generated files, Perl scripts, `ebnfcomp`, prerequisites |
| [usage.md](usage.md) | Command line options, console modes, manual testing and debugging |
| [language.md](language.md) | The BASIC dialect: grammar summary, statements, expressions, numbers, identifiers |
| [tokenizer.md](tokenizer.md) | Token encodings, token map, `tokenize`/`detokenize`, number reader |
| [grammar-and-parser.md](grammar-and-parser.md) | EBNF flow, `ebnfcomp` output, in-memory parse tree |
| [syntax-trees.md](syntax-trees.md) | Raw syntax tree (`stn`) and cooked syntax tree (`csn`), flags, printing |
| [console-subsystem.md](console-subsystem.md) | Patch bay, stdio console, SDL console client/server, keyboard, events, font |
| [support-modules.md](support-modules.md) | `xalloc`, `unicode`, `locale`, `cpuinfo`, `osversion`, `collect` |
| [conventions.md](conventions.md) | Assembly style, ABI rules, stack frame layout, naming |
| [roadmap.md](roadmap.md) | Planned features (three-address code etc.), known issues and cleanup candidates |

Related top-level files: `README.md` (user-facing intro), `implnotes.txt` (author's implementation notes, including the
planned code-generation design), `abinotes.txt` (System V ABI cheat sheet), `CLAUDE.md`, `SESSION.md` and `HistoryLog-Claude.md`
(working agreements, current state and change log for Claude Code).

## Reading order

1. `architecture.md` for the big picture.
2. `build-system.md` — the build is unusual (a grammar compiler feeds generated assembly).
3. `tokenizer.md`, `grammar-and-parser.md`, `syntax-trees.md` in pipeline order.
4. `console-subsystem.md` if working on I/O.
5. `roadmap.md` for what comes next.

## Provenance and accuracy

These documents were written from the sources and notes, then checked against the real output of `make -B` and the
`--stdio` mode (2026-10-31); those parts are marked "verified". SDL-mode statements come from reading the source only.
Where a statement is an inference, the text says so. Keep them updated when
the code changes (see `CLAUDE.md`).
