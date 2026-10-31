# Support modules

| Module | Exports | Purpose |
|---|---|---|
| `xalloc.nasm` | `xalloc(rdi=size)`, `xfree(rdi=ptr)`, `xrealloc(rdi=ptr, rsi=size)` | wrappers over `malloc`/`free`/`realloc`; on failure `oom` prints a message to `stderr` and exits. Use these everywhere instead of calling libc directly. |
| `unicode.nasm` | `uclineininit`, `ucgetcp`, `uclineoutinit`, `ucputcp`, `ucinsavectx`/`ucinloadctx`, `ucoutsavectx`/`ucoutloadctx`, `wcchar`, `wclineoutbeg`, `wclineout` | UTF-8 ⇄ wide character conversion using `mbrtowc`/`wcrtomb` with an explicit `mbstate_t` (24 bytes input context, 32 bytes output context). `ucgetcp` returns -1 at end of input; invalid bytes (high bit set) are skipped and the state reset. The save/load functions let nested decoders (e.g. printing while reading a line) preserve state. |
| `locale.nasm` | `init_locale` | `setlocale` from `LANG`; falls back to `""` then `"C"`. Required for correct `mbrtowc` behaviour. |
| `cpuinfo.nasm` | `chkcputype` | CPUID check at start-up: requires CPUID leaf 1 and the on-chip FPU bit (EDX bit 0); otherwise prints `? maximum query index for CPUID is 0` / `? on-chip FPU not found` to stderr and exits 1. |
| `osversion.nasm` | `chkkernver` | `uname(2)` via libc; parses the kernel release, requires ≥ 2.6.37 for the epoll API; no-op on non-Linux. `main` does not call it; only `sdl_launch` does, so `--stdio` skips the kernel check. |
| `collect.nasm` | — | draft of a block-structured memory pool (`init_page`, "page descriptors"); **not in `MODULES`**, not linked. Relevant to the open question "heap vs memory pool" in `implnotes.txt`. |

## `xalloc` contract

- Returns a non-NULL pointer or terminates the process.
- `xfree` of a pointer from `xalloc`/`xrealloc` only.
- Callers do not need to check for NULL.

## `unicode` usage pattern

```nasm
        mov     rdi,line           ; UTF-8 bytes
        mov     rsi,len
        call    uclineininit
.loop   call    ucgetcp            ; rax = bytes consumed (or -1), code point in [wcchar]
        cmp     rax,-1
        je      .done
        ...
```

Output: `uclineoutinit`, then `ucputcp` per code point writes UTF-8 into the output line (`wclineout`).
