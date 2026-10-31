# Build system

## Prerequisites

- `nasm` (Netwide Assembler), `gcc` (used as linker and to build `ebnfcomp`), `perl`, `make`
- SDL2 development files (`libsdl2-dev`)
- Debian/Ubuntu: `sudo apt install build-essential nasm libsdl2-dev perl git`
- Linux kernel ≥ 2.6.37 (epoll API; checked by `osversion.nasm`)
- `ebnfcomp` is part of the repository (directory `ebnfcomp/`, vendored on 2026-10-31; it used to be a git submodule), so a
  plain `git clone <url>` is enough.
- On WSL use a native Linux file system, because file attributes (executable Perl scripts) matter.

## Targets (`makefile`)

| Command | Effect |
|---|---|
| `make` / `make all` | builds `ebnfcomp/ebnfcomp` and `asmbasic`, then writes `echo ok >all` |
| `make -B` | forced full rebuild (a plain incremental `make` is reliable for the generated files since 2026-10-31, `-B` is still the safe choice after big changes) |
| `make DEBUG=1` | assembles with `-g -F dwarf`, links with `-g -no-pie -z noexecstack` (no `-s`) |
| `make clean` | `rm asmbasic *.o *.lst ebnfcomp/ebnfcomp` (does not remove generated `.inc`/`.nasm`) |

Suffix rule: `nasm -f elf64 $(ASMOPT) -l $*.lst -o $@ $<` — each object also yields a listing `.lst`.
`-z noexecstack` (also in the normal `-s -no-pie -z noexecstack`) marks the stack non-executable: the objects have no
`.note.GNU-stack` section, which made the linker assume an executable stack (verified: `readelf -l asmbasic` showed
`GNU_STACK RWE` before and `RW` now).
Link: `gcc $(LNKOPT) -pthread -Wall -o asmbasic $(MODULES) -lrt -lSDL2`.

`MODULES` = `main osversion cpuinfo locale unicode xalloc patchbay stdconsole sdlconsrv sdlconcli sdlconcev sdlconkbd
sdlconshr tokens toknum 8x12font1 mainsyntax parsetree parsenodename syntree stnflgtbl cookedsyntree`.
`collect.nasm` is not linked. `csnrefinery` was removed from the project (stale `csnrefinery.o/.lst` remain).

## Generated files

```
tokenlist.txt ──extract_tl.pl──────────────► tokendef.inc  (token init records: len,enclen,"NAME",0x03,id)
                               └───────────► keywords.inc  (KW_xxx equ 0xNN)
tokenlist.txt ┐
defaultsyntax.ebnf ┴─build_main_ebnf.pl──► main.ebnf      (token-level EBNF)
main.ebnf ──ebnfcomp --asm mainsyntax──────► mainsyntax.nasm + mainsyntax.inc
mainsyntax.inc ─extract_nodetext.pl────────► parsenodename.nasm  (nc_/tt_/tb_/nt_ name tables)
mainsyntax.inc ─extract_stnflgtbl.pl───────► stnflgtbl.nasm + stmtsexprs.txt (per node type STNF_STMT/EXPR flag)
cookedsyntree.inc + keywords.inc + tokendef.inc ─extract_csntext.pl─► csntext.inc (S_/ID_/OP_/KW_ name tables)
git tag ──tagtoverstr.pl───────────────────► verstr.inc    (e.g. db 'v0.0.8')
8x12font1.txt ──extract_font.pl────────────► 8x12font1.inc (3072 bytes of font bitmaps)
```

All generated files carry a "DO NOT MODIFY" banner; change the *source* and rebuild. Many of them are currently
untracked in git (see `git status`) — whether they should be committed is the author's decision.

### Script details

| Script | Notes |
|---|---|
| `extract_tl.pl` | reads keyword lines matching `^[A-Z][A-Z0-9]*[$]?[(]?`; emits at most 256 entries. Name mangling: `(`→`_FN`, `$`→`_STR`, e.g. `LEFT$(` → `KW_LEFT_STR_FN`. |
| `build_main_ebnf.pl` | 1) builds `TOKEN` productions for operators (`$0200`…`$0211`) and keywords (`$03xx`). 2) reads `defaultsyntax.ebnf`, skipping `--` comments, joining lines until a trailing `.`. 3) replaces numbers, identifiers and string literals with binary token definitions (`$0110 QWORD`, `$fe00 WORD:len BYTE*len`, `$ff WORD:len BYTE*len`). 4) replaces quoted keywords/operators in productions by their token production names. 5) fails (exit 1) on undefined productions, redefinitions or unreferenced productions; prunes productions unreachable from `direct-line`. |
| `extract_nodetext.pl` | string tables for node classes, terminal types, terminal branch types and node types used by tree printers. |
| `extract_stnflgtbl.pl` | runs `egrep` on `mainsyntax.inc` for names containing `STMT`/`EXPR`; table `stnflgtbl` indexed by node-type number gives `STNF_STMT`/`STNF_EXPR`/0. |
| `extract_csntext.pl` | reads `equ 0x..` constants from the `.inc` files, groups by alphabetic prefix, emits `<prefix>_table` of string pointers. |
| `tagtoverstr.pl` | version string: a `v<digits.dots>` found in the current branch name, else the highest tag in version order (`git tag --list --sort=version:refname`, so `v0.0.10` beats `v0.0.9`). The grep pattern for the current branch is `'^\\*'` inside Perl backticks — the backslash must be doubled, or `grep` warns about a leading `*`. |
| `extract_font.pl` | `8x12font1.txt` format: `!!8x12` header, `#XX` hex character code, then 12 rows of 8 chars (`.` = off, `o` = on), blank line between characters. |

Not wired into the makefile: `x`, `x1`, `xx`, `sizes.c` and `test*.c` are scratch files (the `*.c` files are git-ignored).

## `ebnfcomp` (vendored)

Lives in `ebnfcomp/` (single source file `main.c`, own `makefile`, `README.md`, `LICENSE`, test grammars `test.ebnf`,
`bintest.ebnf`). Originally the separate repository `https://github.com/ekkehard-morgenstern/ebnfcomp.git` (GPLv3, © 2019,
pinned at v1.4.2 / `e5fb206`), copied in as plain files; the built binary `ebnfcomp/ebnfcomp` is git-ignored (`*.c` in
`.gitignore` has the exception `!ebnfcomp/*.c`). A Wirth-style EBNF
compiler with regular expression and rudimentary binary matching (`WORD:len BYTE*len`). With `--asm` it emits NASM
tables (`mainsyntax_branches`, `mainsyntax_parsingTable`) and an include file with constants (`NT_*` node-type numbers,
`NC_*` node classes, `TT_*`/`TB_*` terminal types). Known limitations are in its README (regular expression support is
partly broken; only one length-prefixed sequence per chain). Since it is vendored, fixes are made here directly; the upstream repository is no longer the source of truth (the unused
variable `token` in `read_production` was removed here and does not exist upstream).

## Versioning (`bump_version.sh`)

Version = `vMAJOR.MINOR.BUILD` as a git tag (existing tags are lightweight). `bump_version.sh` finds the highest such tag
(version order) and creates the next one on `HEAD` — commit first.

| Command | Effect (from v0.0.8) |
|---|---|
| `./bump_version.sh` or `--build` | v0.0.9 |
| `--minor` | v0.1.0 (build reset) |
| `--major` | v1.0.0 (minor and build reset) |
| `--set X.Y.Z` | exactly that version; must be higher than the current one unless `--force` |
| `--annotate ["text"]` | annotated tag instead of lightweight |
| `--dry-run` / `-n` | show the result only (dirty tree is just a warning then) |
| `--force` | allow a dirty tree and a non-increasing `--set` |
| `--show` | print the current version |

Refuses an existing tag, a malformed version and (without `--force`) a dirty tree. It never pushes (`git push origin vX.Y.Z`).
Afterwards `make` regenerates `verstr.inc` (`tagtoverstr.pl`; the makefile watches `.git/refs/tags` and `.git/packed-refs`)
and relinks `main.o`. Tested in a throwaway repository (build/minor/major/set/annotate/dry-run/error cases) and as `--dry-run`
here. Afterwards the user created the annotated tag `v0.1.0` on `ee106c6`; a plain `make` then regenerated `verstr.inc`
(`v0.0.8` → `v0.1.0`), rebuilt `main.o`, relinked, and the greeting reads `AsmBASIC v0.1.0` (verified).
`tagtoverstr.pl` prefers a `vN.N` found in the current *branch name* over the tag, so don't name branches like `v2`
if you want the tag to show.

## Dependencies

Fixed 2026-10-31: the makefile now tracks the generator chain. Verified by touching files:

- `touch tokenlist.txt` → `tokendef.inc`/`keywords.inc` → `main.ebnf` → `mainsyntax.*` → dependent objects → relink (8 `nasm` runs);
- `touch ebnfcomp/main.c` → `ebnfcomp` is rebuilt, the grammar tables regenerated and the dependent objects rebuilt;
- `touch tagtoverstr.pl` (or a new tag/branch switch: `.git/HEAD`, `.git/refs/tags`, `.git/packed-refs`) → `verstr.inc` → `main.o`.

`mainsyntax.inc` and `keywords.inc` are by-products of the same generator run as `mainsyntax.nasm` / `tokendef.inc`
(rules with empty recipes `mainsyntax.inc: mainsyntax.nasm ;`). Still not tracked: the Perl scripts' own inputs beyond those
listed in the makefile, and the `.nasm` → `.inc` includes of a module you add — list them explicitly. `make -B` remains the
safe choice after larger changes.
- The `all` file is a stamp (`echo ok >all`), git-ignored, and also the name of the default target.
