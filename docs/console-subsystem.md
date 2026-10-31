# Console subsystem

## Patch bay (`patchbay.nasm`)

Four function pointers in `.bss`, set by `pb_initstdio` or `pb_initsdl`. All other code calls them indirectly
(`call qword [pb_putfmt]`).

| Pointer | Stdio implementation | SDL implementation | Signature |
|---|---|---|---|
| `pb_putfmt` | `std_printf` (`jmp printf`) | `sdl_printf` | `rdi` fmt, varargs, `al` = vector arg count |
| `pb_readln` | `std_readln` (`fgets`) | `sdl_readln` | `rdi` buffer, `rsi` size → `rax` ≠ 0 on success |
| `pb_color` | `std_color` (emits `ESC[3Xm`/`ESC[4Xm`) | `sdl_color` | `rdi` bits 0..7 fg, 8..15 bg |
| `pb_cls` | `std_cls` | `sdl_cls` | — |

`pb_initsdl` additionally calls `sdl_launch`.

## Stdio console (`stdconsole.nasm`)

Thin wrappers over libc. `std_readln` zeroes the buffer first and calls `fgets(stdin)`. Colour output uses ANSI
SGR sequences.

## SDL console

Client/server structure, on two threads.

```
main thread (client)                         worker thread (server)
────────────────────                         ──────────────────────
sdl_launch: SDL_Init, create epoll,          sdl_worker: window (desktop fullscreen),
  keyboard buffer, create worker  ─────────▶   accelerated vsync renderer, linear scaling,
sdl_printf: format → UTF-8 decode →            logical size 640×300, ARGB8888 streaming texture
  ANSI CSI parse → write cells to              main loop: SDL_PollEvent → keys → sdl_kbdputbuf →
  sdl_screenbuf, update cursor                   sdl_raiseepoll;  render sdl_screenbuf via font →
sdl_readln: set sdl_want_input,                  texture → present
  sdl_waitepoll for key events,
  sdl_kbdgetbuf, line-edit, echo
```

### Modules

| File | Content |
|---|---|
| `sdlconshr.nasm/.inc` | shared state: worker handle/result/flags, screen buffers (`sdl_screenbuf`, `sdl_workbuf`), cursor position/visibility, current attribute, text screen size, **palettes** `sdl_textbgpalette` / `sdl_textfgpalette` (16 ARGB entries each, bg and fg differ: e.g. index 0 bg transparent, fg black), `screencell` = `sc_col` (bits 4–7 bg pen, 0–3 fg pen) + `sc_chr` |
| `sdlconcli.nasm` | client API: `sdl_launch`, `sdl_printf`, `sdl_readln`, `sdl_color`, `sdl_cls`, `sdl_ink`; escape sequence handling (`sdl_execescseq`, buffer 64 bytes), `sdl_outputbs/lf/cp`, scrolling (`sdl_scrollup/down`) |
| `sdlconsrv.nasm` | worker thread: window/renderer/texture setup, event loop, `sdl_specialkey` (ESC → quit, Backspace, Return), `sdl_enterinput` (text input → keyboard buffer), `sdl_rendertextscreen` |
| `sdlconkbd.nasm` | 128-byte keyboard ring buffer with pthread mutex (`SDL_KBD_BUFSIZ`, mask 127); `sdl_kbdputbuf` writes the UTF-8 of a keypress, `sdl_kbdgetbuf` drains all pending bytes in one go (returns 0 if the destination is too small, so a multi-byte sequence is never split) |
| `sdlconcev.nasm/.inc` | event signalling with `epoll` + `eventfd`: `sdl_initepoll`, `sdl_raiseepoll(mask)`, `sdl_waitepoll` → result bits `SDL_WEP_ERROR 1`, `TIMEDOUT 2`, `SIGNALLED 4` (EINTR), `WORKERINITDONE 8`, `WORKERDOWN 16`, `SPECIALKEY 32`, `REGULARKEY 64` |
| `8x12font1.nasm` | exports `font8x12_1`, the 256×12-byte font (source `8x12font1.txt`, converted by `extract_font.pl`) |

### Text screen model

- 80×25 cells (`SDL_TEXTSCREENWIDTH/HEIGHT`), 640×300 pixel canvas.
- Cell attribute: 4-bit foreground and background pens into the 16-colour palettes (Black, White, Blue, Cyan, Yellow,
  Orange, Red, Green, Magenta, Gray, Dark Gray, Transparent/Black, Light Gray, Pink, Purple, Sea Green).
- `sdl_screenbuf` is written by the client; the server copies it to `sdl_workbuf` before rendering (to avoid tearing),
  then blits glyph rows into the texture pixels. Cursor blink uses `sdl_ticks`.
- ANSI/CSI support: `ESC [ … m` colour sequences (background 40–47, foreground 30–37, reset `ESC[m`), as used by the
  tokenizer test banner. Other sequences are not documented here; read `sdl_execescseq` before relying on them.
- Input: UTF-8 text from SDL text input is stored in the ring buffer; `sdl_readln` decodes it with the `unicode` module
  and performs line editing up to 1023 code points.

### Synchronisation

- `sdl_want_input` (client → server): shows the blinking cursor and enables key forwarding. Server only writes keys
  while it is set, so overflow of the 128-byte ring is unlikely (and handled).
- `sdl_worker_doquit` (client → server) and `sdl_worker_terminated` (server → client) coordinate shutdown;
  `sdl_cleanupworker`, `SDL_Quit` and the epoll/keyboard cleanup functions are registered with `atexit` (`sdlconcli`, `sdlconcev`, `sdlconkbd`).
- Start-up handshake: the worker raises `SDL_WEP_WORKERINITDONE` after setting `sdl_init_ok` (1 ok, -1 failed).

### Requirements

- Linux ≥ 2.6.37 (`osversion.nasm`), SDL2, a display. With no display `--stdio` must be used.
- The program links `-pthread`; `pthread_mutex_t` is 40 bytes on x86-64 glibc (`PTHREAD_MUTEX__SIZEOF`, taken from a C
  `sizeof` test — see `sizes.c`).
