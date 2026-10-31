# HistoryLog-Claude

Log of the changes Claude (Claude Code) made to this repository, one entry per commit.
The user makes all commits, so an entry is first written under **Pending** and gets its
commit ID and timestamp once the commit exists (see "Maintenance" in `CLAUDE.md`).

- A commit belongs here if its message contains "Claude" or "Claude Code" (`git log -i --grep=claude`).
- Timestamps are the commit's author date (`git log --date=iso`). Stats are `git show --shortstat`.
- Entries are in chronological order (oldest first).

Related files: `SESSION.md` (current state), `docs/roadmap.md` (open work).

## Pending (not committed yet)

(nothing pending)

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
