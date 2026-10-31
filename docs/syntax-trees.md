# Syntax trees

## Raw syntax tree (`syntree.nasm`, `syntree.inc`)

```
syntreenode:
  stn_match   resq 1   pointer to the matched in-memory parse tree node (impn)
  stn_token   resq 1   pointer to the matched token bytes in tokenpad (terminals)
  stn_nargs   resq 1   number of sub-nodes
  stn_args    resq 1   pointer to table of sub-node pointers
  stn_flags   resq 1   STNF_* flags
```

Flags: `STNF_MASK = 0x03`, `STNF_STMT = 0x01`, `STNF_EXPR = 0x02`. `setflgs_stn` sets them from `stnflgtbl`, a byte table
indexed by node-type number (generated; only productions whose names contain `STMT` / `EXPR` get a flag).

### API

| Function | Notes |
|---|---|
| `crtsyntree(rdi=tokens, rsi=len)` | returns `rax`≠0 if a prefix of the line matched. Sets `stn_tokenptr` to the first unmatched token and `stn_tokenend`. A remaining token (`*stn_tokenptr != 0`) is a "syntax error near". |
| `delsyntree` | frees the whole tree (`free_stn`) |
| `prtsyntree` | prints the tree (`--stnprint`) |
| `stn_debug` | when non-zero (`--stndebug`) logs node creation and deletion |

### Minimisation during construction

- `stn_remove_null`: trailing null branches (unmatched optionals) are dropped.
- A production with exactly one sub-branch takes over that child's branch info; generic children are freed.
  Terminal children pass their `match` and `token` up.
- A production whose only child is itself a production is replaced by the child.

Goal (from `implnotes.txt`): minimal complexity for later code generation.

## Cooked syntax tree (`cookedsyntree.nasm`, `cookedsyntree.inc`)

```
cookedsyntaxnode:
  csn_type     resb 1    S_*
  csn_subtype  resb 1    keyword/operator id, identifier type
  csn_numbase  resb 1    2/8/10/16 for numbers
  csn__rsvd_1  resb 1
  csn_length   resw 1    length of identifier / string data
  csn_nargs    resw 1
  csn_data     resq 1    pointer to token data (number value, text)
  csn_args     resq 1    table of argument pointers
```

Types: `S_UNDEF 00`, `S_NUMBER 01`, `S_OPER 02`, `S_KEYWORD 03`, `S_LINENUMBER E0`, `S_STATEMENT E1`,
`S_EXPRESSION E2`, `S_LINE E3`, `S_IDENT FE`, `S_STRLIT FF`. Identifier subtypes: `ID_NUM 0`, `ID_STR 1`, `ID_NUMFN 2`,
`ID_STRFN 3`. `OP_*` operator ids and `KW_*` keyword ids (from `keywords.inc`) are the subtypes of operators and
keywords.

`crt_csn` (rdi = raw node → rax = cooked node) applies these rules:

- Non-terminal nodes are containers and vanish, except those flagged `STNF_EXPR` (→ `S_EXPRESSION`) or `STNF_STMT`
  (→ `S_STATEMENT`).
- A node whose children are all terminals is analysed to find what it represents (first terminal decides).
- Numbers: `01 BASE` + 8 bytes → `S_NUMBER` with `csn_numbase`, big-endian data.
- String literals / identifiers: length (big endian) and data pointer taken from the tokens; identifier subtype from the
  type byte.
- Operators and keywords (`TB_DATA` matches whose first byte is `02`/`03`) are instantiated directly; anything else is
  handled by the parent.
- Sub-branches are cooked recursively into `csn_args`.

`cooksyntree` cooks the global `syntree`; `delcookedsyntree` frees it (`del_csn`); `printcookedsyntree` prints each node
as `type,subtype,"data"` using the text tables in `csntext.inc` (format string `csn_id_fmt = '%s,%s,"%-*.*s"'`), indented two spaces per level.

## Printed forms (verified by running `make -B` output, 2026-10-31)

Raw tree (`--stnprint`), one node per line, indented by depth: `class,termtype,nodetype,flags`, `(null)` for an unmatched
optional branch, and terminals followed by their token bytes in hex. Input `X=1+2`:

```
NC_PRODUCTION,TT_UNDEF,NT_ASSIGN_STMT,STNF_STMT
  (null)
  NC_PRODUCTION,TT_UNDEF,NT_NUM_ASSIGN,0
    NC_PRODUCTION,TT_UNDEF,NT_NUM_IDENT,0
      NC_TERMINAL,TT_BINARY,_NT_GENERIC,0
        fe 00
      NC_TERMINAL,TT_BINARY,_NT_GENERIC,0
        00 01
      NC_TERMINAL,TT_BINARY,_NT_GENERIC,0
        58
    NC_TERMINAL,TT_BINARY,_NT_GENERIC,0
      02 05
    ...
```

Cooked tree (printed by default). `10 PRINT "HI"`:

```
(generic)
  S_NUMBER,base 10,"10"
  S_STATEMENT
    S_KEYWORD,KW_PRINT
    S_STRLIT,"HI"
```

`X=1+2` gives `S_STATEMENT` with children `S_IDENT,ID_NUM,"X"`, `S_OPER,OP_EQ` and a nested `S_EXPRESSION`/`(generic)`
structure containing `S_NUMBER,base 10,"1"`, `S_OPER,OP_ADD`, `S_NUMBER,base 10,"2"`. `FOO(1)=2` shows the function
identifier as `S_IDENT,ID_NUMFN,"FOO("` with the closing parenthesis as a separate `S_OPER,OP_RPAREN`.

Observations from real output:

- **Nodes labelled `(generic)`** are cooked nodes with no type (`S_UNDEF`/container) that were kept because they have
  several children (the line itself, repetition groups such as `: stmt`, `THEN stmt`). The cooked tree is therefore
  *not yet fully flattened*; nested `S_EXPRESSION` wrappers also remain around single operands.
- **Line numbers are plain `S_NUMBER` children** of a `(generic)` root. `S_LINENUMBER` and `S_LINE` are defined and
  recognised only in the printing code (`cookedsyntree.nasm` ~line 375–381); nothing creates them yet.
- Numbers are stored as doubles (`3f f0 00…` = 1.0) but the cooked print shows decimal text.
- Identifier names are **upper-cased** (`b$` → `B$`) and keep their sigil and, for functions, the `(`.
- `--stndebug` prints `crt <class>,<termtype>,<nodetype>` lines for every node creation.

## Open topics

- The cooked tree is the intended input of the code generator. Its refinement ("csnrefinery") was attempted and removed in
  commit `fbd2b8a`; the git history (`477d14c` "formulated goals for csnrefinery") has the goals.
- There is no program store yet and the cooked tree has no line node (see above).
