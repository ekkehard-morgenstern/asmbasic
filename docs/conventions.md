# Assembly conventions

## File layout

```
; AsmBASIC - a BASIC compile and go system written in assembly language
; Copyright (C) 2022  Ekkehard Morgenstern
; … GPLv3 banner … "NOTE: Programs created with AsmBASIC do not fall under this license."

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64
                        %include    "….inc"
                        section     .text
                        global      …
                        extern      …
```

Perl files use `#`, `.ebnf` files use `--` for the same banner. New files should get the same banner.

## Columns

Labels start in column 0 (functions) or are `.local`; the mnemonic starts at column 24 (labels longer than 23
characters push to the next column group), operands at column 36. Comments sit on their own line at column 24 or after
the operands. Lowercase mnemonics and register names. Section/constant tables follow the same alignment
(`NAME   equ   value`).

## Function frames

```nasm
func                    enter       0x30,0          ; locals / saved registers
                        mov         [rbp-0x08],rbx  ; save callee-saved registers first
                        mov         [rbp-0x10],r12
                        …
                        mov         rbx,[rbp-0x08]  ; restore
                        mov         r12,[rbp-0x10]
                        leave
                        ret
```

- `enter N,0` is used deliberately (clarity over a few bytes/cycles; `implnotes.txt`). `N` is the local frame size,
  keep it a multiple of 16 where it matters for alignment (`enter` after the call pushes 8 bytes of return address and
  8 of `rbp`, so the stack is 16-byte aligned inside the function).
- A block comment above each function documents the frame (`[rbp-0x08] - RBX backup`…), inputs (`rdi - …`) and
  outputs (`rax - …`).

## ABI rules (System V AMD64; see `abinotes.txt`)

- Arguments: `rdi, rsi, rdx, rcx, r8, r9`, then stack; floating point in `xmm0–7`.
- Return: `rax` (`rdx:rax` for 128-bit).
- Callee-saved: `rbx, rbp, r12–r15`. Everything else may be clobbered by any call — don't keep values in `rax`,
  `rcx`, `rdx`, `rsi`, `rdi`, `r8–r11` across calls.
- `rsp` 16-byte aligned immediately **before** a `call`.
- Variadic callee (`printf`, `fprintf`, `snprintf`, `pb_putfmt`): `al` = number of vector registers used (`xor al,al`).
- Direction flag clear on entry/exit; use `cld` before string instructions.
- Linux syscalls: number in `rax`, args `rdi, rsi, rdx, r10, r8, r9`; `rcx` and `r11` are destroyed; result `-errno`.

## Data

- Static data in `.bss` (`resq`/`resb`), constants in `.rodata`, initialised data in `.data`.
- `align 8,db 0` after string tables.
- Non-`static` symbols are exported with `global`; there is no namespace, so prefix by module (`stn_`, `csn_`, `sdl_`,
  `tok_`, `uc`, `pb_`, `impn_`).
- Structures: `struc name` with prefixed field names and `name_size` auto-defined by NASM.

## Tokens and trees

- Big-endian for every multi-byte value inside token strings.
- Never edit generated files; extend the generator or the grammar.
- Append-only keyword list.

## Naming

- Production names in the grammar: lowercase with dashes; node-type constants `NT_UPPER_SNAKE`.
- Cooked-tree constants: `S_` (node type), `ID_` (identifier kind), `OP_` (operator), `KW_` (keyword).

## Comments and documentation

- Update `docs/` and `SESSION.md` with each change (see `CLAUDE.md`).
- `implnotes.txt` remains the author's own notebook; don't restructure it without being asked.
