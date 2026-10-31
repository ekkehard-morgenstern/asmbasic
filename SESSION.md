# Session state

Maintained by Claude; updated whenever work in a session changes something. Last update: 2026-10-31 (project onboarding).
Read this first when resuming; details are in `docs/` (start with `docs/README.md`) and `CLAUDE.md`.

## Standing rules
- **Model: Sonnet at all times** (`.claude/settings.json` sets `"model": "sonnet"`).
- **Never run git write commands.** The user does all of them manually. Read-only git is fine.
- **Disjoint from Engine1999** (`../engine1999`): no code, build or file sharing; only its working style was borrowed.
- Keep this file, `docs/`, `docs/roadmap.md` and `HistoryLog-Claude.md` current when work changes the state (log: Pending
  section, moved to Log with commit id once the user commits; see `CLAUDE.md`).
- Never hand-edit generated files (see `docs/build-system.md`).

## Repo state
- Branch `master` (main branch for PRs is `main`); latest commit `6e3b29d` ("introducing Claude Code to AsmBASIC", 2026-10-31, includes Claude's docs).
- Uncommitted at session start: `implnotes.txt` (new "Planned Features" chapter: variable storage, code generation,
  three-address code opcode list) and a number of untracked generated/scratch files (`*.inc`, `mainsyntax.nasm`,
  `parsenodename.nasm`, `stnflgtbl.nasm`, `main.ebnf`, `test2/3/4`, `foo.txt`, `.gitignore`, `.vscode/`, …).
- Session docs were committed in `6e3b29d`. `.claude/` is git-ignored (settings stay local). The `ebnfcomp` submodule shows
  as dirty only because of its built binary.
- Open question: vendoring `ebnfcomp` into this repo and dropping the submodule (commands given to the user, not yet applied).
- Version string: `v0.0.8` (`verstr.inc`, derived from a git tag by `tagtoverstr.pl`).

## Build / test status
- **`make -B` succeeds** (exit 0, 2026-10-31). Warnings only: `ebnfcomp/main.c:653` unused-but-set variable, `grep` warning in
  `extract_stnflgtbl.pl`, linker note that `cookedsyntree.o` lacks `.note.GNU-stack`. It regenerated all generated files,
  objects/listings and the `asmbasic` binary (no source edits).
- Verified in `--stdio` mode: help, option handling, tokenizer round trips, raw/cooked tree printing, syntax errors,
  limits. **SDL mode was not exercised** (the process just waits; no display confirmed).
- No automated tests exist. See `docs/usage.md` for manual verification.

## What exists
- Tokenizer, EBNF-generated parse table, raw syntax tree, cooked syntax tree, SDL text console + stdio console.
  Full description: `docs/architecture.md`.
- Nothing after the cooked tree: no program store, no variables, no code generation, no execution.

## This session
- Explored the whole project and `../engine1999` (read-only, for conventions only).
- Created `CLAUDE.md`, `SESSION.md`, `.claude/settings.json` and `docs/` (README, architecture, build-system, usage,
  language, tokenizer, grammar-and-parser, syntax-trees, console-subsystem, support-modules, conventions, roadmap).
- Docs written from the source, then checked against real `--stdio` output and corrected (see `HistoryLog-Claude.md`).
  Statements about SDL mode still come from reading the source only.
- Created `HistoryLog-Claude.md` (Pending section holds this session).

## Next steps
- See `docs/roadmap.md`. The user's own next step (per `implnotes.txt`) is variable storage + three-address code.
