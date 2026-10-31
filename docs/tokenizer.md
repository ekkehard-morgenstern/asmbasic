# Tokenizer

Files: `tokens.nasm` (core), `toknum.nasm` (numbers), `tokenlist.txt` (keywords), `tokendef.inc` / `keywords.inc`
(generated from the list), `unicode.nasm` (input decoding).

## Buffers (`tokens.nasm`)

| Name | Size | Purpose |
|---|---|---|
| `linebuf` / `linebuflen` | 16384 bytes | copy of the current input line (UTF-8) |
| `tokenpad` / `tokenpadptr` | 32768 bytes | output token string; `tokenpadptr` = end of data |
| `identbuf` | 1024 bytes | scratch for identifier text |
| `strlitbuf` | 1024 bytes | scratch for string literal text |
| `lbuf` (`main.nasm`) | 8192 bytes | line read buffer of the driver (`LBUF_SIZE`) |

The README's limits (line 8191 bytes, identifiers/strings 1004 bytes) follow from these buffers. Observed behaviour:

- A line of `PRINT 1+1+1+…` fails with `? Tokenizer failure` somewhere between 5000 and 5600 characters (each `1+` costs
  12 token bytes, so the 32 KiB `tokenpad` fills before the 8 KiB line limit matters). Token-heavy lines are thus limited
  by `tokenpad`, not by the line length.
- A string literal of 1500 characters is cut to about 1004 characters (silently). An identifier of 1500 characters
  survived the round trip untruncated, so the 1004 limit for identifiers in the README/`language.md` is not enforced by
  `tokenize` (the limit may apply elsewhere, e.g. in the token map).

## Token encodings

All multi-byte values are big endian.

| Token | Encoding | Notes |
|---|---|---|
| Number | `01 BASE VALUE.q` | `BASE` = 2, 8, 10 or 16; `VALUE` is 8 bytes, a big-endian IEEE 754 double (verified: `1` → `01 0A 3F F0 00 00 00 00 00 00`) |
| Operator | `02 ID` | hard-coded in the tokenizer; IDs `OP_*` in `cookedsyntree.inc` |
| Keyword | `03 ID` | `ID` = zero-based line index of the keyword in `tokenlist.txt` (max 256; the list currently has 177 entries; `PRINT` = `03 7A`) |
| Identifier | `FE TYPE LEN.w NAME…` (LEN and NAME include the sigil: `B$` → `FE 01 00 02 42 24`) | `TYPE`: 0 numeric, 1 string (`$`), 2 numeric function/array (`name(`), 3 string function/array |
| String literal | `FF LEN.w TEXT…` | no terminating NUL |

Operator IDs: `< 00`, `<= 01`, `<> / >< 02`, `> 03`, `>= 04`, `= 05`, `( 06`, `) 07`, `, 08`, `; 09`, `: 0A`, `+ 0B`,
`- 0C`, `* 0D`, `/ 0E`, `^ and ** 0F`, `& 10`, `# 11`. In `main.ebnf` these appear as 16-bit values `$0200 + id`.

Number base prefixes: `&H` hex, `&D` decimal (optional), `&O` octal, `&B` binary. `&` not followed by a valid base letter
is stored verbatim as the `&` operator token. Exponent markers: `E±n` (decimal/octal/binary), `G±n` (hex), `P±n`
(all bases).

## Keywords and the token map

`init_tokenizer` builds a **token map** (`tokenmap`: first init block, a 1000-entry hash table by name, and a
1000-entry reverse hash by encoding). It consumes *token init blocks* — sequences of `tokeninit` records
(`ti_namelen`, `ti_enclen`, name bytes, encoding bytes; a zero name length ends the block) — registered through
`tokenmapentry` records. `tokendef.inc` supplies the keyword block (`db len,2,"NAME",0x03,id`). Descriptors in the
tables (`tokendesc`: two chain pointers, `td_namelen`, `td_enclen`, name, encoding) are allocated with `xalloc`.
`computehash` (name pointer, length → `rax` mod `TKM_HASHSIZE`) is the hash function.

- Name → encoding: used by `tokenize` when a word is read (`tok_ident`).
- Encoding → name: used by `detokenize` to print keywords back.
- Keywords that end in `(` (e.g. `LEFT$(`, `ABS(`) include the parenthesis in the name; user functions/arrays
  lex as `FE 02/03` identifiers including the `(`.
- A word that matches a keyword exactly is emitted as the keyword; everything else becomes an identifier. There
  is therefore no "invalid token".

## Public functions

| Function | In | Out | Notes |
|---|---|---|---|
| `init_tokenizer` | — | — | builds token map; call once after `init_locale` |
| `tokenize` | `rdi` line, `rsi` length | `rax` ≠ 0 success | fills `tokenpad`, sets `tokenpadptr`; failure only if `tokenpad` overflows |
| `detokenize` | `rdi` tokens, `rsi` length, `rdx` flags | text into `linebuf` | `rdx`=0 in current callers; output is read back with `tok_dumplinebuf` |
| `tok_dumplinebuf` | — | — | prints `linebuf` via `pb_putfmt` |
| `dump_tokenmap` | — | — | debugging |
| `tok_getch`, `tok_putb`, `tok_putq`, `detok_putch` | | | helper primitives shared with `toknum.nasm` |
| `tok_rdamp`, `tok_rdnum`, `detok_wrnum` (`toknum.nasm`) | | | read `&`-prefixed number, read decimal number, write number token as text |

Input is consumed as Unicode code points: `uclineininit(line, len)` then repeated `ucgetcp` (code point in `wcchar`).
`sourceputback` provides one-character push-back. Only code points < 256 are fully supported (README).

## Detokenized form (verified)

`detokenize` does not reproduce the input text. Keywords and identifiers are upper-cased, spacing is normalised and
numbers are rewritten in normalised mantissa/exponent form in their own base:

| Input | `line buf` after detokenize |
|---|---|
| `print "a";b$` | ` PRINT"a"; B$` |
| `&HFF+&B101` | ` &H1.FEP7 + &B1.01P2` |
| `1.5E+3` | `1.5E+3` |
| `left$(a$,2)` | `LEFT$( A$, 2 )` |

(The `line buf: <<…>>` wrapper is printed by `tok_dumplinebuf`; in `--testtok` mode the first round trip of a line also
prints the token bytes in hex.)

## Tokenizer test mode

`--testtok`: prints a colour test, then for each input line prints the detokenized line (round trip through
`tokenpad`). Useful to check keyword/number changes without the parser.

## Adding a keyword

1. **Append** the keyword to `tokenlist.txt` (never insert; IDs are positional). Names ending in `(` or `$(` denote
   function keywords.
2. Add it to `defaultsyntax.ebnf` where it is used. Keywords not referenced are fine as tokens, but
   `build_main_ebnf.pl` fails on productions that are defined and unreferenced.
3. `make -B`.
4. If the keyword also needs a name in the cooked tree dump, `extract_csntext.pl` handles it automatically via
   `keywords.inc`.
