# HistoryLog-Claude

Log of the changes Claude (Claude Code) made to this repository, one entry per commit.
The user makes all commits, so an entry is first written under **Pending** and gets its
commit ID and timestamp once the commit exists (see "Maintenance" in `CLAUDE.md`).

- A commit belongs here if its message contains "Claude" or "Claude Code" (`git log -i --grep=claude`).
- Timestamps are the commit's author date (`git log --date=iso`). Stats are `git show --shortstat`.
- Entries are in chronological order (oldest first).

Related files: `SESSION.md` (current state), `docs/roadmap.md` (open work).

## Pending (not committed yet)

### Session 2026-10-31 — fixing the known problems (docs/roadmap.md)
- `tokens.nasm`: identifiers and string literals over 1004 bytes were silently truncated (`ucputcp` drops what doesn't fit).
  New helper `tok_putcp` detects the dropped code point and sets `tok_toolong` (cleared in `tok_prepare`); `tokenize`
  then fails. `main.nasm` prints `? Identifier or string too long` (other failures still `? Tokenizer failure`).
  Correction: my earlier note that identifiers were *not* truncated was a measurement error — both were cut at 1004.
- `main.nasm`: empty input lines are ignored in `main_loop` and `tokenizer_test` (they used to end the program; EOF still does);
  `--curses` prints a notice and falls back to stdio; a file name argument prints a "not implemented" notice.
- `makefile`: dependency gaps closed — `ebnfcomp` binary on its sources, `mainsyntax.nasm` on the binary,
  `mainsyntax.inc`/`keywords.inc` as by-products, `verstr.inc` on `tagtoverstr.pl` + git HEAD/tags, `sdlconcev.inc` for
  `sdlconsrv/cli.o`, `keywords.inc` for `cookedsyntree.o`.
- `README.md`, `implnotes.txt`, `CLAUDE.md`, `docs/{build-system,language,tokenizer,usage,roadmap}.md`, `SESSION.md` updated.
- Verified: `make -B` clean (no warnings); idents/strings: 1004 ok, 1005/2000 rejected; empty lines (stdio and `--testtok`);
  notices for `-c`/file; incremental `make` after touching `tokenlist.txt`, `ebnfcomp/main.c`, `tagtoverstr.pl`; sample run
  unchanged. SDL mode not exercised.
- New `bump_version.sh` (build/minor/major bump, `--set`, `--annotate`, `--dry-run`, `--force`, `--show`; creates a local tag only).
  Tested in a throwaway repo under the scratchpad; in this repo only `--show`/`--dry-run` were run (no tag created).
  Documented in `README.md`, `docs/build-system.md`; `CLAUDE.md` forbids Claude from running it without `--dry-run`.
- Not fixed on purpose (design decisions): cooked tree flattening, fixed buffer sizes, unused keywords, detokenizer
  output format, scratch files (git-ignored), no tests.

## Log

### 6e3b29d — 2026-10-31 08:32:22 +0100 — "introducing Claude Code to AsmBASIC"
25 files, +3846/-0.
- Created `CLAUDE.md` (standing rules: Sonnet only, no git writes, disjoint from Engine1999; build, conventions, module map),
  `SESSION.md`, `.claude/settings.json` (`"model": "sonnet"`) and `docs/` (README, architecture, build-system, usage,
  language, tokenizer, grammar-and-parser, syntax-trees, console-subsystem, support-modules, conventions, roadmap).
- Created this file.
- Ran `make -B` (succeeds; regenerates the generated `.inc`/`.nasm` files, all `.o`/`.lst`, `ebnfcomp/ebnfcomp` and
  `asmbasic`; these are build outputs, not edits) and verified the docs against the real program output in `--stdio`
  mode (help text, option handling, tokens, detokenized text, raw and cooked tree printing, error messages, limits).
  Corrected the docs where they were wrong (cooked-tree format, `S_LINE` never created, case folding, string truncation,
  token-buffer limit, empty line ends the program). SDL mode was **not** exercised.
- No source files (`*.nasm`, `*.inc` sources, `*.pl`, `*.ebnf`, makefile) were edited.
- The user bundled other files into this commit: `.gitignore`, `implnotes.txt` (planned-features chapter), the generated
  `8x12font1.inc csntext.inc keywords.inc main.ebnf mainsyntax.inc tokendef.inc verstr.inc` and `threeaddrcode.inc`.
  `.claude/` is git-ignored, so `.claude/settings.json` is not in the repository.

### 6245add — 2026-10-31 09:01:21 +0100 — "Claude Code session update"
3 files, +15/-10.
- `HistoryLog-Claude.md` / `SESSION.md`: recorded commit `6e3b29d` (moved the pending entry into the log) and the open
  question about vendoring `ebnfcomp`. `.gitignore` was changed by the user in the same commit.

### d63337a — 2026-10-31 09:08:34 +0100 — "Various fixes by Claude Code"
10 files, +59/-27.
- `ebnfcomp/main.c`: removed the unused variable `token` in `read_production` (the `-Wunused-but-set-variable` warning
  at line 653); `make -B` now shows no ebnfcomp warning and regenerates byte-identical `mainsyntax.nasm/.inc`.
- Docs for the vendored `ebnfcomp` (the user had applied `vendor_ebnfcomp.sh`, commit `8fa7859`): `README.md` and
  `implnotes.txt` no longer ask for `git clone --recursive`; `CLAUDE.md`, `docs/build-system.md`, `docs/roadmap.md`
  updated; `SESSION.md` refreshed.
- `tagtoverstr.pl`: the `grep: * am Anfang des Ausdrucks` warning came from here (not from `extract_stnflgtbl.pl`):
  Perl turned `'^\*'` inside the backticks into `^*`. Doubled the backslash. `verstr.inc` still says `v0.0.8`.
- `tagtoverstr.pl`: the tag fallback now uses `git tag --list --sort=version:refname | tail -n 1`. Checked in a throwaway repo
  under the scratchpad (tags v0.0.2, v0.0.9, v0.0.10): old order gave `v0.0.9`, new gives `v0.0.10`; in this repo it still gives `v0.0.8`.
- `makefile`: added `-z noexecstack` to `LNKOPT` (normal and DEBUG) instead of adding `.note.GNU-stack` to all 23 modules.
  `readelf -lW asmbasic`: `GNU_STACK` was `RWE`, is now `RW`.
- Verified: `make -B` rc 0 with no warning or note output at all; `printf '10 PRINT "HI"\n' | ./asmbasic --stdio` prints the same cooked tree as before.
- Commit `8fa7859` ("ebnfcomp vendored into the repository; submodule removed", 10 files, +2485/-5) was the result of
  the `vendor_ebnfcomp.sh` script Claude wrote; its message has no "Claude", so by the rule above it is not a log entry.

### d4050fa — 2026-10-31 09:09:53 +0100 — "Claude session files updated"
2 files, +27/-28.
- `HistoryLog-Claude.md` / `SESSION.md`: moved the `d63337a` entry into the log, sorted the entries chronologically,
  refreshed the session state. Bookkeeping only.
