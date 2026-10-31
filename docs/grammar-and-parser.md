# Grammar and parser

## Flow

```
defaultsyntax.ebnf          human-readable, keywords quoted ('PRINT'), text-level tokens (regexps)
        │ build_main_ebnf.pl
        ▼
main.ebnf                   token-level: keywords/operators replaced by TOKEN productions with binary encodings
        │ ebnfcomp --asm mainsyntax
        ▼
mainsyntax.nasm + .inc      packed "ROM" parsing table: mainsyntax_parsingTable, mainsyntax_branches
        │ initparsetree (at start-up)
        ▼
in-memory parse tree        inmemparsingnode structs with pointer tables
        │ crtsyntree (per line)
        ▼
raw syntax tree
```

## Grammar source (`defaultsyntax.ebnf`)

Variant of Wirth EBNF: `name := a | b { c } [ d ] ( e f ) .` Comments start with `--`. A production may span several
lines and ends with a `.`. Quoted strings are keywords/operators; `/…/` are regular expressions (text level only;
replaced for the token-level grammar). Top-level production: **`direct-line`**.

Major groups (see `language.md` for the surface syntax):

- Token level: numbers (`hex-number`, `dec-number`, …), identifiers (`num-ident`, `str-ident`, function/array
  identifiers ending in `(`), `string-literal`, keyword classes, operator classes, `chan` (`#n`).
- Expressions: `num-expr` (unary, mul, add, shift, log), `str-expr`, comparisons, `imp-expr`, `and-expr`, `or-expr`,
  `cond-expr` (only in IF/loops), `expr`, `expr-list`.
- Statements: `any-mode-stmt` (both modes), `program-only-stmt`, `direct-only-stmt`; lists with `:`.
- Lines: `program-line := dec-number [ program-stmt-list ]`; `direct-line := direct-stmt { ':' direct-stmt } |
  program-line`.

Rules enforced by `build_main_ebnf.pl`: every referenced production must exist, none may be defined twice, none may be
unreferenced (besides `direct-line`), and unreachable productions are dropped.

## Token-level rewriting

`build_main_ebnf.pl` replaces:

| Source production | Replacement in `main.ebnf` |
|---|---|
| `hex/dec/oct/bin-number` | `$0110 / $010a / $0108 / $0102 QWORD` (matches `01 BASE` + 8 bytes) |
| `num-ident`, `str-ident`, `num-func-ident`, `str-func-ident` | `$fe00 / $fe01 / $fe02 / $fe03 WORD:len BYTE*len` |
| `string-literal` | `$ff WORD:len BYTE*len` |
| each keyword `'FOR'` | `for-kw` where `TOKEN for-kw := $03xx .` (name from `tokenlist.txt`: lowercase, `(`→`-fn`… e.g. `left-str-fn`) |
| each operator | e.g. `plus := $020b`, `power := $020f` |

## `ebnfcomp` output (`mainsyntax.inc`)

Constants for node numbering (`NT_*`: one per production/generated node, e.g. `NT_DIRECT_LINE`, `NT_PRINT_STMT`),
node classes (`NC_TERMINAL 0`, `NC_PRODUCTION 1`, `NC_MANDATORY 2` (sequence), `NC_ALTERNATIVE 3`, `NC_OPTIONAL 4`,
`NC_OPTIONAL_REPETITIVE 5`), terminal types (`TT_UNDEF`, `TT_STRING`, `TT_REGEX`, `TT_BINARY`) and terminal branch types
(`TB_DATA`, `TB_BYTE`, `TB_WORD`, `TB_DWORD`, `TB_QWORD`). Names for printing come from `parsenodename.nasm` (`nc_texts`, `tt_texts`, `tb_texts`, `nt_texts`).

## In-memory parse tree (`parsetree.nasm`)

```
inmemparsingnode:
  impn_nodeClass  resb 1     NC_*
  impn_termType   resb 1     TT_*
  impn_nodeType   resw 1     NT_* (index into production table)
  impn_numBranches resw 1
  impn__reserved  resw 1
  impn_branches   resq 1     pointer to table of child pointers (0 = none)
  impn_text       resq 1     pointer to text / byte data of terminals
```

`initparsetree` locates the `NT_DIRECT_LINE` entry in the packed table (it will crash if absent) and converts
recursively (`impn_from_pn`). Because the grammar is recursive (e.g. `expr` → `( expr )`), already-converted nodes are
remembered in a linear lookup table (`impn_lut`, `impn_storelutpair` / `impn_findlutpair`: parse-table entry → impn) so the result is a graph, not a tree.
`dumpparsetree` (`--dumppt`) prints it; branches already printed are shown as `...`.

## Matching (`syntree.nasm`)

`stn_from_impt` recursively matches a parse-tree node against the token string at `stn_tokenptr`, saving and restoring
the position when a branch fails (backtracking). Node classes: terminals (token byte patterns incl. length-prefixed
data), productions, mandatory sequences (`NC_MANDATORY`: all branches must match), alternatives (first match wins —
inferred from the class name; confirm in `syntree.nasm` before relying on it), optional groups and optional
repetitions. See `syntax-trees.md` for the produced structure.

Because alternatives are tried in order and the first success wins, **grammar order matters** (e.g. `num-cmp-expr`
before `str-cmp-expr`, `then-line` before `if-jump`). Keep this in mind when editing `defaultsyntax.ebnf`.

## Editing the grammar — checklist

1. Edit `defaultsyntax.ebnf` only.
2. `make -B`; read the Perl warnings (`undefined production`, `unused production`, `redefined`).
3. Statement/expression productions must contain `STMT` / `EXPR` in their names to be flagged for the cooked tree
   (see `stnflgtbl`).
4. Test with `./asmbasic --stdio --stnprint` and inspect the tree.
