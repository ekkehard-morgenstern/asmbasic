# CLAUDE.md

AsmBASIC — a BASIC "compile and go" system written in **x86-64 NASM assembly** (Linux, System V ABI), linked with the C
library and SDL2. Early development (v0.0.8): tokenizer, EBNF-driven parser, raw and cooked syntax trees and an SDL
text console work; code generation and execution do **not** exist yet. GPLv3; programs written *in* AsmBASIC are
explicitly exempt (see `LICENSE`, file headers).

## Standing rules

- **Model: always Sonnet** (`claude-sonnet-5-5`). Project setting in `.claude/settings.json`; do not switch models or
  delegate to other models/subagent models.
- **Git: never run git write commands** (commit, add, push, merge, rebase, reset, checkout of files, stash, tag, branch
  changes). The user does all git writes manually. Read-only git (`status`, `log`, `diff`, `show`) is fine.
- **Disjoint from Engine1999.** `../engine1999` is a separate, unrelated project (C/SDL). Do not read from it for code,
  do not copy code from it, do not link against it, do not reference it from the makefile, and do not edit it. Only the
  *working style* (CLAUDE.md / SESSION.md / `docs/` conventions) was borrowed from it.
- **Keep `SESSION.md` current.** Update it whenever work changes the state (what was done, what is open, test/build
  status). Read it first when resuming. Keep `docs/` current too; open work lives in `docs/roadmap.md`.
- **Keep `HistoryLog-Claude.md` current.** After each piece of work add a short entry (what changed, why, what was
  run) under its **Pending** section, together with the `SESSION.md` update. At the start of a session, and whenever the
  user says they committed, run `git log -i --grep=claude --format='%h|%ad|%s' --date=iso` and `git show --shortstat`,
  move the pending entries into the **Log** as `### <id> — <timestamp> — "<subject>"` (oldest first, with file/line
  stats) and clear Pending. Commits whose message lacks "Claude" are not logged (mention it if the user bundled
  Claude's work into one). Never commit it myself — the user does.
- Don't claim something builds or works unless you ran it. Say what was and wasn't verified.

Full documentation is in `docs/` — start with `docs/README.md`.

@SESSION.md

## Build

```
sudo apt install build-essential nasm libsdl2-dev perl     # prerequisites (Debian/Ubuntu)
git clone --recursive <url>                                 # ebnfcomp is a submodule
make -B                                                     # full rebuild (dependencies in makefile are incomplete)
make DEBUG=1 -B                                             # -g -F dwarf, no -s
./asmbasic --help
```

Pipeline order (generated files are produced by Perl scripts and `ebnfcomp`, see `docs/build-system.md`):
`tokenlist.txt` → `extract_tl.pl` → `tokendef.inc`, `keywords.inc`; `tokenlist.txt` + `defaultsyntax.ebnf` →
`build_main_ebnf.pl` → `main.ebnf` → `ebnfcomp/ebnfcomp --asm mainsyntax` → `mainsyntax.nasm/.inc` →
`extract_nodetext.pl`, `extract_stnflgtbl.pl` → `parsenodename.nasm`, `stnflgtbl.nasm`; `extract_csntext.pl` →
`csntext.inc`; `tagtoverstr.pl` → `verstr.inc`; `extract_font.pl` → `8x12font1.inc`.
**Never hand-edit a generated file** (they carry a "DO NOT MODIFY" header); edit the source and rebuild.

There is **no automated test suite** (`make -B` was verified to build; `docs/usage.md` has verified sample output). Verification is manual: run `./asmbasic --stdio` (or `--sdl`), type lines, inspect
the printed syntax trees (`--stnprint`, `--csnprint`), and use `--testtok` for the tokenizer. Debug with `gdb` on a
`make DEBUG=1` build.

## Conventions (follow the surrounding code)

- NASM syntax, `cpu x64` / `bits 64`, labels in column 0, mnemonics at column 24, operands at column 36, comments at
  the mnemonic column. Lowercase mnemonics/registers. Each file starts with the GPL banner (`;` comments) and
  `; see implementation notes file provided in "implnotes.txt"`.
- Function prologue is `enter N,0` / epilogue `leave` + `ret` (deliberate, see `implnotes.txt`), not push rbp/mov.
- System V AMD64 ABI: args in `rdi, rsi, rdx, rcx, r8, r9`; result in `rax`; callee-saved `rbx, rbp, r12–r15` are saved
  in the frame at `[rbp-0x08]`… and restored before `leave`. `rsp` must be 16-byte aligned at every `call`. For variadic
  C calls (`fprintf`, `snprintf`, `pb_putfmt`) set `al` = number of vector args (usually `xor al,al`). `DF` clear.
  Details in `abinotes.txt`.
- Document each function with a comment block giving input registers (`rdi - …`) and output (`rax - …`).
- Structures are `struc … endstruc` in `.inc` files with a field prefix (`stn_`, `csn_`, `impn_`, `td_`, `tme_`…).
- Local labels (`.name`) inside functions; `global`/`extern` lists at the top of the section.
- Memory goes through `xalloc`/`xfree`/`xrealloc` (`xalloc.nasm`, aborts on OOM), not raw `malloc`.
- Text is UTF-8 on the outside; the tokenizer reads code points via `unicode.nasm`. Multi-byte values **inside the
  token stream are big endian** (network order).
- Keep `tokenlist.txt` order stable: the line index is the keyword ID. **Only append**, never insert (max 256).
- Console I/O goes through the patch bay function pointers `pb_putfmt/pb_readln/pb_color/pb_cls`, never directly to
  SDL or stdio from higher layers.

## Where things are

| Area | Files |
|---|---|
| Entry / driver | `main.nasm` (option parsing, `main_loop`, `tokenizer_test`) |
| Tokenizer | `tokens.nasm` (token map, `tokenize`, `detokenize`), `toknum.nasm` (numbers, `&H/&D/&O/&B`), `tokenlist.txt`, `tokendef.inc`, `keywords.inc` |
| Grammar / parser tables | `defaultsyntax.ebnf` → `main.ebnf` → `mainsyntax.nasm/.inc`, `build_main_ebnf.pl`, `ebnfcomp/` (submodule) |
| Trees | `parsetree.nasm/.inc` (in-memory grammar tree), `syntree.nasm/.inc` (raw syntax tree), `stnflgtbl.nasm`, `cookedsyntree.nasm/.inc` (cooked tree), `csntext.inc`, `parsenodename.nasm` |
| Planned back end | `threeaddrcode.inc` (draft three-address-code structs; unused), `implnotes.txt` ("Planned Features") |
| Console abstraction | `patchbay.nasm`, `stdconsole.nasm` (stdio), `sdlconcli.nasm` (client API), `sdlconsrv.nasm` (render thread), `sdlconkbd.nasm`, `sdlconcev.nasm` (epoll events), `sdlconshr.nasm/.inc`, `8x12font1.*` |
| Support | `xalloc.nasm`, `unicode.nasm`, `locale.nasm`, `cpuinfo.nasm`, `osversion.nasm`, `collect.nasm` (unused memory-pool sketch, not in `MODULES`) |
| Notes | `implnotes.txt`, `abinotes.txt`, `README.md`, `docs/` |
| Stale / scratch | `*.c` test programs (`test*.c`, `sizes.c`; `*.c` is git-ignored), `x`, `x1`, `xx`, `all`, `make-*.log`, `main.lst.1/.2`, `csnrefinery.o/.lst` (module was removed), `foo.txt` — not part of the build |

## Current state — read first

- Pipeline implemented: line → tokens → raw syntax tree (`crtsyntree`) → cooked syntax tree (`cooksyntree`) → printed.
  Nothing consumes the cooked tree yet (`main.nasm` has a `; tbd` where code generation goes).
- Next planned step (per `implnotes.txt`, uncommitted edits at the time of writing): choose variable storage and an
  intermediate code (three-address code), then generate and run code. See `docs/roadmap.md`.
- No program store (line numbers are parsed but lines are not stored), no variables, no evaluation.
