# The AsmBASIC language (as defined by the grammar)

Source of truth: `defaultsyntax.ebnf`. Only **syntax** exists so far; no statement has any semantics or executes.
Behaviours below come from the grammar and `implnotes.txt`, and describe the *intended* language.

## Lines and modes

- **Program line:** `<decimal number> [statement { : statement }]`.
- **Direct line:** statements separated by `:`; may use direct-only statements.
- Statement groups: *any-mode* (both), *program-only*, *direct-only*.

## Lexical elements

| Element | Rules |
|---|---|
| Numbers | decimal (default, optional `&D`), `&H` hex, `&O` octal, `&B` binary; fractional part allowed in every base (`&B1.1`); exponent `E±n` (`G±n` in hex), `P±n` universal; stored as double |
| Strings | `"…"` (no escapes; cannot contain `"`) |
| Identifiers | any run of characters excluding `" < = > * / + - ^ , ; : ) $ % & ! # (`; numeric sigils `% & ! #`, string sigil `$`; a trailing `(` makes it a function/array identifier |
| Keywords | listed in `tokenlist.txt`; a word equal to a keyword is that keyword; keyword functions include `(` (e.g. `LEFT$(`) |
| Channels | `#` followed by number or numeric identifier |
| Operators | `< <= <> >< > >= =  + - * ** ^ / ( ) , ; : & #` |

Verified: input is case-insensitive and both keywords and identifiers are upper-cased by the tokenizer (`print` → `PRINT`,
`b$` → `B$`), so `A` and `a` are the same variable.

## Expressions

Numeric precedence (lowest to highest): logical (`AND NAND OR NOR XOR XNOR`) → shifts (`ASL ASR SHL SHR`, at most one)
→ `+ -` → `* ** ^ /` → unary (`NOT + -`) → base (number, variable, function call, parenthesised). Note that `^` and `**`
share the multiplicative level with `*` and `/` in the grammar.

String expressions: literals, string variables/functions, concatenation with `+`.

Conditions (`cond-expr`, only in IF/DO/LOOP/WHILE/UNTIL): comparisons (`= <> >< >= <= < >`, numeric or string),
then `IMP NIMP EQV NEQV`, `AND NAND`, `OR NOR XOR XNOR`. A logical expression inside a condition must be parenthesised
(note in the grammar).

Predefined: numeric `ERL RND TI`; string `DATE$ DATETIME$ ERR$ TI$ TIME$`.
Numeric functions: `ABS ASC ATAN ATN CEIL COS EXP FLOOR INT LG LN LOG10 LOG2 LOGN PEEK PEEKB/D/F/L/Q/W SIN SQR SQRT UNI`.
String functions: `AT$ BIN$ DEC$ HEX$ HTAB$ LEFT$ MID$ OCT$ RIGHT$ STR$ UNI$ VTAB$`.

## Statements

Any mode: `BRK`, `CALL`, `CATALOG`/`FILES [path$]`, `DEF CHAR`, `CLEAR`, `CLOSE [#ch,…]`, `CLS`, `COLOR fg[,bg]`,
`DIM`/`ERASE`, `DO [WHILE|UNTIL cond]`, `FOR … TO|DOWNTO … [STEP]`, `FOR EACH|FOREACH k[,v] IN arr()`,
`FOR EVER|FOREVER`, `REPEAT`, `WHILE`/`UNTIL cond`, `LOOP [WHILE|UNTIL]`, `NEXT [vars]`, `EXIT|LEAVE|ITERATE|AGAIN
[loop|line]`, `WEND`, `GOTO|GOSUB line`, `IF|UNLESS cond [THEN stmts | GOTO/GOSUB n [ELSE …]]`, `ELSE …`,
`END IF|UNLESS`, `HTAB`, `VTAB`, `INK`, `[LINE] INPUT [#ch|prompt$,] vars`, `[LET] a = expr`, `OPEN`, `RANDOMIZE
[n|TIMER]`, `RESTORE [line]`, `SAFETY ON|OFF`, `YIELD`, `SEEK #ch,pos`, `SYS addr[,args]`, `POKE[B|D|F|L|Q|W] a,v`,
`RESUME [NEXT|line]`, `RETURN [expr]`, `PRINT [#ch,] items` with `AT(row[,col])`, `HTAB(n)`, `VTAB(n)`, `USING fmt$`
and `;`/`,` separators.

Program only: `AFTER|EVERY n GOTO/GOSUB`, `AGAIN|EXIT`, `CHAIN [MERGE] file$`, `DATA`, `DEF FN name(args)=expr`,
`FUNC|FUNCTION|SUB|PROC|PROCEDURE name(args)` … `END [FUNC…]`, `ON ERROR OFF|GOTO n`, `ON expr GOTO|GOSUB list`,
`LABEL name`, `STOP [n]`.

Direct only: `AUTO`, `CONT`, `EDIT n`, `LOAD|OLD file$`, `SAVE file$`, `LIST a[-b]`, `DELETE a[-b]`, `RENUM|RENUMBER
a[,b]`, `MERGE file$`, `NEW`, `RENAME a$ TO b$`, `RUN [line]`, `TRACE ON|OFF`.

Notes:

- Arrays dimensioned by `DIM a(n, DYNAMIC, ASSOC)`; the planned implementation treats all arrays as one-dimensional
  internally (`implnotes.txt`).
- `GOTO`/`GOSUB` targets are numbers or numeric identifiers (labels created by `LABEL`).
- Some keywords in `tokenlist.txt` have no grammar rule yet (e.g. `INT`-family aliases, `OPTION`, `RECORD`, `TYPE`,
  `PUSH`, `PUT`, `GET`, `LOCATE`, `PALETTE`, `HTAB`-variants) — they tokenize but do not parse.
  (Derived by comparing the lists; may be incomplete.)
- Variable defaults planned: numbers start as 0, strings as `""`; undimensioned arrays are 0..10.

## Limits (current)

| Limit | Value |
|---|---|
| Line length | 8191 bytes UTF-8 (SDL line editor: 1023 code points) |
| String constant | ≈1004 bytes UTF-8 (longer literals are silently truncated — verified with 1500) |
| Token string | 32768 bytes (`tokenpad`); overflow → `? Tokenizer failure` (≈5000–5600 chars of `1+1+…`) |
| Identifier | 1004 bytes UTF-8 per README; a 1500-character identifier was accepted untruncated in testing |
| Keywords | 256 |
| Character set | 256 user-redefinable 8×12 glyphs |
| Text screen | 80×25 cells; 4-bit foreground, 4-bit background, 16-colour palette |
| Unicode | only code points 0–255 fully supported |
