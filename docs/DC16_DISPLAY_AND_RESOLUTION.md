# Dark Colony `dc16.exe` — Display Pipeline and the 1024×768 Upgrade

Reverse-engineering notes on how Classic `dc16.exe` (`DC - Classic/dc16.exe`, MD5
`aa0a646b1234d1d9815a2b7480fd080b`) puts pixels on the screen — DirectDraw setup, the internal
"screen" and graphics-context objects, the sprite blitters, the in-game HUD geometry, the mouse and
the movie player (§1–§7) — followed by the complete inventory of resolution-dependent code sites
(§8) and a staged plan to raise the game from 640×480 to 1024×768 (§9–§12).

All addresses are virtual addresses in Classic `dc16.exe` (`VA = file_offset + 0x400C00` for the
`AUTO` code section, `VA = file_offset + 0x402800` for `DGROUP`). Council Wars `ENGEXP16.EXE`
(MD5 `50419d438427d31341057e9723724f66`) is the same code base; §8 lists its file offsets too, all
byte-verified. Council Wars `dc16.exe` (MD5 `4180f6e9d01925b23eac0eb335e0b95e`) is a different
build and is *not* covered except for the two globals in §3.

Calling convention is Watcom register-based: the first four arguments in `eax, edx, ebx, ecx`.
Facts marked **(verified)** were read directly from the disassembly; facts marked *(inferred)* are
consistent with the code but were not traced to the end.

---

## 1. Overview **(verified)**

```
                       ┌─ 8-bit sprite cells (.SPR / .FIN, juicel.c)
                       │  8-bit background pages (.GIF, gifload.c, W*H bytes)
                       ▼
        shade LUT ──► software blitters ──► "screen" 16-bit framebuffer
     (0x48C188,            (juicel.c,           (DirectDraw offscreen
      level*512)            engmain.c,           SYSTEMMEMORY surface,
                            lighting.c,          640×480×16, 0x489720)
                            sprite.c)                   │
                                                        │ ddex4.c
                                                        ▼
                                        primary + 1 back buffer (flip chain)
                                        640×480×16 EXCLUSIVE FULLSCREEN
```

* The game is **16 bits per pixel**, RGB565 or RGB555 (whichever the card reports), *not* 8-bit
  paletted. All art on disk is 8-bit; it is expanded to 16-bit through a shading lookup table at
  draw time.
* All drawing is done by **CPU software blitters writing into one linear 16-bit buffer**. That
  buffer is a DirectDraw `DDSCAPS_OFFSCREENPLAIN | DDSCAPS_SYSTEMMEMORY` surface, locked once per
  frame; the code uses `lpSurface` only and **ignores `lPitch`**, assuming `pitch == width * 2`.
* DirectDraw is used only to get the buffer, to blit/flip it, to hold the mouse cursors, and to
  set the display mode. There is no hardware 2-D acceleration path and no scaling anywhere.
* **Every screen, the in-game HUD included, is a plain-text script** in `INTRFACE/` (§6). Only two
  things about the in-game screen are compiled in: where the map view is rendered and where the
  minimap is plotted (§5). Everything else — the panel frame art, all 82 HUD widgets and their
  coordinates — is data.

Modules involved (link order, boundaries from assert strings): `main.c`, `avi.c`, `proto.c`,
`widget.c`, `gadget.c`, `animate.c`, `button.c`, `driver.c`, `ddex4.c`, `interface.c`, `marker.c`,
`engmain.c`, `sprites.c`, `text.c`, `gifload.c`, `juicel.c`, `image.c`, `mouse.c`, `tile.c`,
`mapit.c`, `lighting.c`, `sprite.c`.

---

## 2. DirectDraw layer (`ddex4.c`) **(verified)**

Imports used: `DDRAW.dll!DirectDrawCreate` only (thunk `0x0047F11C`); everything else goes through
the COM vtables. `GDI32` `BitBlt`/`CreateCompatibleDC` and `USER32` `LoadImageA` are used for the
two loading-screen bitmaps and nothing else.

| Function | Address | What it does |
|---|---|---|
| `win_init` | `0x0042E7B4` | `GetVersionExA`; sets mouse to screen centre (320,240); `DirectDrawCreate`; `SetCooperativeLevel(hwnd, DDSCL_ALLOWMODEX \| DDSCL_EXCLUSIVE \| DDSCL_FULLSCREEN)`; `set_mode_16`; `create_surfaces`; sound init |
| `create_window` | `0x0042E688` | `LoadIconA`, `RegisterClassA`, `CreateWindowExA(0, cls, title, WS_POPUP, 0, 0, W, H, …)` — **reads the globals of §3**, so no patch needed |
| `set_mode_8` | `0x0042E890` | `IDirectDraw::SetDisplayMode(640, 480, 8)` — live: called by `avi_end` |
| `set_mode_16` | `0x0042E914` | `IDirectDraw::SetDisplayMode(640, 480, 16)`; on failure prints "Setting to 16 bit mode Failure" and aborts |
| `create_surfaces` | `0x0042E998` | primary + 1 back buffer (`COMPLEX\|FLIP\|PRIMARYSURFACE`, video memory, falling back to any memory, 10 retries 500 ms apart, then error exit); `GetAttachedSurface(BACKBUFFER)`; a **640×480 `OFFSCREENPLAIN\|SYSTEMMEMORY`** surface; `GetSurfaceDesc` to detect RGB565 / RGB555; `CreatePalette`; 32 mouse cursors from `cursor/cursor%d.bmp` |
| `lock_screen` | `0x0042F828` | `Lock(offscreen)` → `screen->pixels = desc.lpSurface`. `lPitch` is discarded |
| `unlock_screen` | `0x0042F8D8` | `Unlock`; `screen->pixels = NULL` |
| `clear_screen` | `0x0042F774` | zeroes `0x4B000` (= 640·480) 16-bit words linearly, then `Flip` |
| `make_colour` | `0x0042F2D0` | `(r,g,b) → 16-bit` via three interleaved LUTs at `0x004DEC90/92/94` |
| `set_palette` | `0x0042F320` | rebuilds those LUTs and the shade table from a 768-byte palette |
| loading screen | `0x0042EEF6`…`0x0042F031` | `LoadImageA(0, "intrface/load.bmp"/"load2.bmp", IMAGE_BITMAP, 640, 480, LR_LOADFROMFILE\|LR_CREATEDIBSECTION)` → `GetDC(backbuffer)`, `BitBlt(0,0,640,480,SRCCOPY)`, `Flip` (function start not determined) |

Surface handles: `0x00489714` `IDirectDraw`, `0x00489718` primary, `0x0048971C` back buffer,
`0x00489720` the 640×480×16 offscreen work surface, `0x00489724` palette, `0x00489730` `HWND`,
`0x004DFE90[32]` cursor surfaces, `0x00489734` "screen is locked" flag.

Pixel-format detection stores the masks at `0x004DFF18` (R), `0x004DFF28` (G), `0x004DFF24` (B),
the format id at `screen+0x14` (`0x235` = RGB565, `0x22B` = RGB555) and a 50 %-brightness mask at
`screen+0x10` (`0x7BEF` / `0x3DEF`).

---

## 3. The two master dimension globals **(verified)**

```
DGROUP  0x00488DB4  dword = 640     screen width
DGROUP  0x00488DB8  dword = 480     screen height
```

These are **initialised data, never written at runtime**, and each is read at exactly four places:

| Reader | Meaning |
|---|---|
| `0x0042E6F4` / `0x0042E6ED` | `CreateWindowExA` width / height |
| `0x0042E82E` / `0x0042E83A` | `screen->width = W; screen->height = H` in `win_init` |
| `0x0044FFC7` / `0x0044FFCC` | `image.c` full-screen page: `malloc(W * H)` (8-bit) |
| `0x0044FFE0` / `0x0044FFE7` | same function: `image->width = W; image->height = H` |

They are preceded in `DGROUP` by the dword pair `0x14F, 0x16E` (335, 366 — purpose not
identified), which makes the 12-byte sequence

```
4F 01 6E 01 80 02 00 00 E0 01 00 00
```

a **unique anchor in all three binaries** — the reliable way to find these globals in any build:

| Binary | W offset | H offset |
|---|---|---|
| Classic `dc16.exe` | `0x865B4` | `0x865B8` |
| `ENGEXP16.EXE` | `0x867DC` | `0x867E0` |
| Council Wars `dc16.exe` | `0x868E0` | `0x868E4` |

Because `screen->width` doubles as the framebuffer **stride** for the main sprite blitter (§4),
changing these two dwords alone already moves a large part of the renderer to a new resolution.
It is *not* sufficient — §8 lists the ~60 places that hardcode the numbers independently.

---

## 4. The `screen` and graphics-context objects **(verified)**

`driver.c` `0x0042C29C` builds both:

```c
ctx    = malloc(0xEC);              /* "Screen" */
screen = new_screen();              /* 0x1A4 bytes, driver.c 0x0042BD78 */
ctx[0x20] = screen;
ctx[0x24] = gfx_descriptor;
screen[0xFC] = 0; install_ddraw_driver(screen);   /* ddex4.c 0x0042FBF0 */
assert(screen[0xFC] != 0);
ctx->clip   = make_rect(0, 0, 640, 480);    /* 0x0042C347 / 0x0042C363 */
ctx->bounds = make_rect(0, 0, 640, 480);
```

**`screen`** (0x1A4 bytes) is an *image* with the graphics driver's method table appended:

| Offset | Field |
|---|---|
| `+0x00` | width **= stride in pixels** |
| `+0x04` | height |
| `+0x08` | pixel pointer (16-bit for the screen, 8-bit for `image.c` pages) |
| `+0x10` | u16 50 %-brightness mask |
| `+0x14` | pixel format id |
| `+0x18` | → shade / palette LUT block (`0x1802` bytes) |
| `+0xFC` | `win_init` |
| `+0x100`…`+0x1A0` | driver methods (graphics **and** sound — `driver.c` is the whole platform layer) |

**`ctx`** (0xEC bytes) is the drawing context every blitter receives in `eax`:

| Offset | Field |
|---|---|
| `+0x00`…`+0x0C` | clip rect `x0, y0, x1, y1` |
| `+0x10`…`+0x1C` | screen bounds rect |
| `+0x20` | → `screen` |
| `+0x24` | → gfx descriptor |
| `+0x29` | u8 "use shadow table" flag |
| `+0x30`…`+0x98` | method slots copied from `screen+0x100`… by `0x0042C405`ff; notably `+0x8C` `lock_screen`, `+0x90` `unlock_screen`, `+0x94` `set_origin` |

`make_rect(x, y, w, h)` is `0x004365BC` (`engmain.c`); it returns `{x, y, x+w, y+h}` by value
through `esi`. It is the single place rectangles are built, which makes it a useful breakpoint.

### The sprite-cell blitter `0x0044FAC0` (`juicel.c`) **(verified)**

The hot path, and the reason a resolution change is tractable at all:

```
screen = ctx[0x20]
stride = screen[0]                  <-- NOT a constant
base   = screen[8]
clip against ctx[0x00..0x0C]
dst    = base + (y*stride + x) * 2
src    = 8-bit cell data; each byte -> u16 through  [0x48C188] + level*512 + idx*2
```

It is fully resolution-independent. The same is true of the text (`text.c`), gadget and widget
drawing paths, which all go through it. There are exactly eleven `ctx+0x8C`/`ctx+0x90`
(`lock_screen`/`unlock_screen`) call sites, i.e. eleven **entry points** into framebuffer access —
everything else draws inside one of these brackets: `0x0042BCCE`, `0x0042BEFE`, `0x0042BFC1`,
`0x0042C146`, `0x0042C203` (`driver.c` generic rect/pixel ops), `0x00436399` (main map render, which
calls `draw_terrain` and `draw_objects` while holding the lock), `0x0043A095` and `0x0043A44F`
(minimap), `0x0044EA8C` (`gifload.c`), `0x0044FAED` and `0x0044FCCB` (`juicel.c`). That list is the
audit surface: any function that touches the framebuffer is reachable from one of them.

---

## 5. In-game screen layout **(verified)**

The whole HUD geometry is four numbers plus one byte offset:

```
screen                    640 x 480          (§3)
map viewport              512 x 448  at (4, 6)
   size   engmain.c  0x00435F46 (512) / 0x00435F61 (448)
   rect   proto.c    0x0041ED63 (x=4) / 0x0041ED6E (y=6) / 0x0041ED23 (512) / 0x0041ED1E (448)
   tiles  engmain.c  0x00435E4F (16 across) / 0x00435E47 (14 down)      <- 512/32, 448/32
minimap                    96 x  84  at (519, 6)
   size   engmain.c  0x0043A083 (96 cols) / 0x0043A07E (84 rows)
   steps  engmain.c  0x0043A463 (96<<8) / 0x0043A478 (84<<8)
   origin engmain.c  0x0043A0AF / 0x0043A484:  +0x220E bytes = (6*640 + 519) * 2
```

So the panel chrome is the right-hand strip `x = 516…639` (124 px) plus the bottom strip
`y = 454…479` (26 px). Tiles are **32×32 pixels**; world coordinates are `tile << 8` (8 fractional
bits), and the terrain renderer converts with `>> 5` (`0x004539B3`ff), i.e. the view origin
`0x005044AC`/`0x005044B0` is in **pixels**.

Every one of these numbers is independently confirmed by the HUD artwork and its layout script:
`INTRFACE.GIF` is opaque exactly on columns 0–3, rows 0–5 and columns 515–517, and all 75 panel
widgets in `MAINE` start at x ≥ 516 — see §6.1.

### The render view struct at `0x005044AC` **(verified)**

Set up by `engmain.c` `0x00435E7C`:

| Offset | Address | Value |
|---|---|---|
| `+0x00` | `0x005044AC` | i32 view x (pixels) |
| `+0x04` | `0x005044B0` | i32 view y (pixels) |
| `+0x08` | `0x005044B4` | destination pixel pointer |
| `+0x0C` | `0x005044B8` | u16 viewport width  = 512 |
| `+0x0E` | `0x005044BA` | u16 viewport height = 448 |
| `+0x10` | `0x005044BC` | u16 **destination stride in pixels = 640** (`0x00435F9F`) |
| `+0x14` | `0x005044C0` | → map (`0x9AA38` bytes, "kev: mapinfo") |
| `+0x18` | `0x005044C4` | → occlusion mask, `0x7000` bytes = 512·448/8 ("kev: maskbuffer", `0x00435F88`) |
| `+0x34` | `0x005044E0` | → tile-type table, `0x4260` bytes = 1416 × 12 ("kev: tilememory") — indexed by **tile type** (`0x00435FEF`), so resolution-independent |

Per-frame path (`engmain.c` `0x00436080` → `0x00435E7C`, and `0x00436380`ff):

```
lock_screen(ctx)
draw_ptr = screen[8] + (clip.y0 * 640 + clip.x0) * 2   <- 0x004363B6 (*5<<7), 0x004360B6 (*5<<8)
draw_terrain(view)          lighting.c 0x00453910
draw_objects(view)          sprite.c   0x004543FC
unlock_screen(ctx)
draw_minimap(ctx, ...)      engmain.c  0x0043A064 / 0x0043A43C
```

### Buffers that size themselves from the view struct **(verified)**

`lighting.c` `lighting_init` `0x00453770` is the model to imitate: it takes the view struct, reads
the viewport width and height back out of it (`[view+0x0A]>>16`, `[view+0x0C]>>16`), stores the
width in `0x0049931C` and the pixel count in `0x005360B0`, and allocates a 1-byte-per-pixel
"lightplane" of exactly that size into `view+0x1C`. `0x0049931C` is then used as the light-plane
row stride by the object renderer (`0x004542E8`, `0x00465051`, `0x00465401`, `0x004657B1`,
`0x00465B61`, `0x00465E6A`). **This whole path follows the viewport size automatically** — changing
the two immediates at `0x00435F46`/`0x00435F61` is enough for it. The occlusion mask
(`0x00435F88`) is the one that was written as a literal `0x7000` instead, and therefore has to be
patched by hand.

### Buffers that are **not** resolution-dependent **(verified)**

Worth stating because it removes the hardest class of problem: **no static `.bss` buffer scales
with the screen size.** `0x00533C90` (`0x2420` bytes) is the fade/shading table read verbatim from
`FADE.DAT` (9248 bytes, `lighting.c` `0x004537AD`); the 289×32-byte loop at `0x00453970` only
rewrites its low 3 bits with the current light level. Everything that does scale — the map, the
flat maps, the occlusion mask, the `image.c` full-screen pages, the DirectDraw surfaces — is heap
or DirectDraw allocated. `.bss` runs `0x0049A000…0x00536E00` with `.reloc` immediately after at
`0x00537000`, so growing it in place would mean moving `.reloc` and `.rsrc`; that is not needed.

---

## 6. What is data, not code **(verified)**

**Every screen in the game — including the in-game HUD — is a plain-text script in `INTRFACE/`.**
There are **30** of them in Classic, parsed by `widget.c` `0x004232E2`ff and loaded by
`load_interface(app, name, flags)` `0x004231E8` (freed by `0x004231B0`):

| Script | `size` line | Script | `size` line |
|---|---|---|---|
| `MAINE` — **in-game HUD** | `size 640 480` | `LOGOE` | `size 640 480` |
| `NEWGAMEE` — main menu | `size 640 480` | `LOSTE` | `size 640 480` |
| `MULTIE` — lobby | `size 640 480` | `METAE` | `size 640 480` |
| `MULTIWNE` | `size 640 480` | `NETOPTE` | `size 640 480` |
| `GENERALE` | `size 640 480` | `STORYE` | `size 640 480` |
| `BUTTONSE` | `size 640 480` | `ENCYCLOE` | `size 640 480` |
| `DEMOWINE` | `size 640 480` | `WINE` | `size 640 480` |
| `DINTROE` | `size 640 480` | `WINGAMEE` | `size 640 480` |
| `DPBLANKE` | `size 640 480` | `WINUKE` | `size 640 480` |
| `DPLAYSE` | `size 640 480` | `bintroe` | `size 640 480` |
| `GETSVRE` | `size 640 480` | `introe` | `size 640 480` |
| `IPXNAMEE` | `size 640 480` | `shumane` | `size 640 480` |
| `LOADGE` | `size 640 480` | `LOBJE` | `size 112 96 304 272` |
| `LOPTE` | `size 112 128 308 240` | `LQCE` | `size 112 160 304 176` |
| `LSGE` | `size 112 48 304 386` | `MULTIE~1.TXT` (readable copy of a lobby script) | `size 640 480` |

Note the lowercase `bintroe`, `introe`, `shumane` — easy to miss on a case-insensitive listing.
Council Wars has the same set (uppercase `BINTROE`, `INTROE`, `SHUMANE`) plus three more under
`exp/intrface/`.

Keywords: `size`, `pictures`, `background`, `palette`, `text`, `font`, `font_offset`, `colour`,
`bright_pushed`, `bright_highlight`, `end`, plus per-object `pushb`, `checkb`, `in_text`,
`picture`, `list`, `scroll`, `group`, `textmsg`, each with explicit `x y w h`.

The `size` handler is `widget.c` `0x004223A8` and it accepts **two or four** numbers:

* `size W H` → rect `(0, 0, W, H)` — what the 26 full-screen scripts use
* `size X Y W H` → rect `(X, Y, W, H)` — used by the four sub-window scripts above

**Consequence: every screen can be repositioned or resized by editing one line of text, with no
binary patching at all.** Centring an existing 640×480 screen inside 1024×768 is
`size 192 144 640 480`.

### 6.1 The in-game HUD is three data files **(verified)**

This was the one part of the display assumed to be compiled in. It is not. `proto.c` loads it in
the same function that sets the map view rect (§5): `mov edx, "intrface/main"` at `0x0041EB34`,
`call load_interface` at `0x0041EB63`, handle stored in `0x004AB1C4`. `MAINE`'s own header names
the other two files:

```
size 640 480
pictures   intrface/mainbut     -> INTRFACE/MAINBUT.SPR   242 231 B, the HUD widget cell bank
font 0     intrface/mfonto7
background intrface/intrface    -> INTRFACE/INTRFACE.GIF   640x480, the HUD frame / panel art
palette    palette
colour erase 0 0 0
bright_pushed 4
bright_highlight 4
```

`INTRFACE.GIF` is a **frame with a hole**, and the hole is exactly the map viewport derived from
the code in §5. Decoded, it is only **8.9 % opaque** (27 230 of 307 200 px); index 254 (RGB 0,0,0,
the `erase` colour) fills the rest. Over the rect `(4,6)-(515,453)` — the 512×448 viewport — it is
**99.8 % index 254** with 4 distinct colours, against 81 distinct colours outside it. The fully
opaque runs pin the frame down to the pixel:

| Opaque run | Meaning |
|---|---|
| columns `0…3` (100 %) | left border — map view starts at x = 4 |
| rows `0…5` (100 %) | top border — map view starts at y = 6 |
| columns `515…517` (100 %) | map view right edge (4 + 512 − 1 = 515) |
| columns `636…639` (100 %) | right screen border |
| rows `457…462`, `473…479` (100 %) | bottom bar detail |
| `x 516…639` overall | 24.6 % opaque — the right panel, rest filled by `MAINBUT.SPR` widgets and the engine-drawn minimap |
| `x 0…639, y 454…479` | 55.1 % opaque — the bottom bar |

`MAINE` places **82 positioned widgets** (47 `pushb`, 13 `picture`, 13 `in_text`, 9 `checkb`) plus
9 `group`s:

* **75 widgets at x ≥ 516**, spanning x `516…638`, y `92…449` — the right panel. Tabs at y = 92,
  unit-order buttons from y = 153, Build button at (516, 422).
* **4 widgets in the bottom bar**: `pushb #147` (4,460) 20×19, `pushb #149` (24,460) 20×19,
  `in_text #148` (50,462) 61×1, `in_text #200` (480,463) 3×1.
* **3 widgets over the map**: `picture #199` (200,160) 5×5, `in_text #203` (10,440) 72×1,
  `in_text #204` (10,425) 72×1 — the message lines.
* **y 6…90 at x 519…615 is deliberately left empty** — that is the minimap, painted by
  `engmain.c` `0x0043A064`/`0x0043A43C`, not by a widget.

So the division of labour is: the **code** fixes where the map view and minimap are rendered; the
**data** positions everything else around them.

### 6.2 The art

Fixed-size and never scaled by the engine: 19 × 640×480 `.GIF` backgrounds in `INTRFACE/`
(including the HUD frame above), the terrain `.GIF` palettes at the game root, `LOAD.BMP` and
`LOAD2.BMP` (640×480), 32 `CURSOR/cursor%d.bmp`, and the `.SPR` cell banks (§6.3).

### 6.3 The `.SPR` container format **(verified)**

Decoded from `juicel.c`. Entry points, all reached through the graphics context:

| Address | Role |
|---|---|
| `0x0042532C` | `load_sprite_bank(name, ctx)` in `animate.c` — builds `"sprites/%s"`, allocates a 20-byte bank record ("animation cell header") and calls the two below through `ctx+0x44` then `ctx+0x40` |
| `0x0044F790` | `ctx+0x44` — reads the header only, to compute the allocation size |
| `0x0044F818` | `ctx+0x40` — the parser |
| `0x0044FAC0` | raw-cell blitter |
| `0x0044FC44` | RLE-cell blitter (decode loop at `0x0044FD4F`) |
| `0x0044FE81`ff | per-cell draw dispatcher: applies the cell offsets, clips, then picks the blitter from `bank+0x0C` |

**File layout.** All integers little-endian — the loader uses plain `fread`
(`0x00406A44` = `fread(dst,2,1,f)`, `0x00406A5C` = `fread(dst,4,1,f)`), with no byte swapping.

| Offset | Size | Field |
|---|---|---|
| `0x000` | `u16` | `flags` — `flags & 0x180` means the cell bodies are RLE compressed. Only two values occur in the shipped data: `0x0001` (raw, 84 files) and `0x0081` (RLE, 468 files) |
| `0x002` | `u16` | `ncells` |
| `0x004` | `u32` | `datasize` — an allocation hint, **not** the body size (see below) |
| `0x008` | 768 | palette, 256 × (r,g,b), 6-bit VGA components (0…63) |
| `0x308` | `8·n` | directory, per cell: `u16 width`, `u16 height`, `u16 xoffset`, `u16 yoffset` |
| `0x308+8n` | — | cell bodies in order: raw = `width·height` bytes with no prefix; RLE = `u32 length` then that many bytes |

The directory therefore starts at **776**, not 779 — see the dead end recorded in §13.

**RLE scheme** (`0x0044FD4F`). A signed control byte, with the write cursor running in row-major
order and wrapping at `width`, so a transparent run may cross rows:

* `c >= 0` → the next `c + 1` bytes are literal palette indices (max run 128)
* `c < 0` → skip `-c` pixels, leaving them transparent (max skip 128)

**Palette index 0 is transparent** in both blitters (`0x0044FBEF`, `0x0044FDA0`) — including inside
a literal run, so a literal may legally carry zeros and they still read through.

**Cell `xoffset`/`yoffset`** are draw offsets added to the requested position by the dispatcher at
`0x0044FE9A` and `0x0044FEA2`. Every cell in the shipped data is tightly cropped (no empty
margins), so these are the trim offsets that put a cropped cell back where it belongs in its
logical frame. `SPRITES/ACAR.SPR` shows it plainly: constant height 227, widths 15/32/33/66/82…
with offsets 54/36/36/36/20… so that `width + xoffset` is constant within a facing group.

**The `datasize` quirk.** For RLE files it is the sum of the per-cell stream lengths. For raw files
the stored value counts an extra 12 bytes per cell — the 8-byte directory entry plus a notional
4-byte length prefix that raw files do not actually store — which is why the loader does
`datasize -= ncells*4` at `0x0044F88B` and then over-allocates by `ncells*24` (24 = the in-memory
cell header size, from `0x0044F7FF`). Nothing else depends on the value, so a writer can simply
recompute it.

**Validation.** All **552** unique `.SPR` files in `DC - Classic`, `DC - Council wars` (including
`exp/`) and the map editor parse byte-exact, with no trailing bytes: 17 958 cells, of which 52 are
`0x0` placeholders and 15 088 are non-empty compressed cells. Every one of those 15 088 decodes to
exactly `width·height` pixels while consuming exactly its declared stream length. Re-encoding and
decoding again reproduces the pixels for **15 088 / 15 088** cells; the re-encoded stream is
byte-identical to the original for 55.2 % of cells and never larger (0.4 % smaller in total, so the
original packer was marginally suboptimal). **337 of the 552 files (61.1 %) rebuild
byte-identically** from the parsed representation — `INTRFACE/MAINBUT.SPR` among them, same MD5.

**Tooling.** `tools/spr.py` implements the codec: `info`, `extract` (one PNG per cell plus a
`cells.json` carrying flags, palette and the per-cell offsets), `build` (rebuild from that
directory) and `check` (parse plus round-trip self-test). This is what unblocks re-importing traced
artwork in §10 stage 5.

**Cell size limits.** `engmain.c` asserts `sprite->xsize > 0 && xsize < 512 && ysize > 0 &&
ysize < 512` (string at `DGROUP 0x00486274`), but the shipped data contains **60 cells with a
dimension ≥ 512** (largest 640×257), so that path clearly is not reached for every cell. Treat
512 as the safe ceiling for anything drawn through `engmain.c`.

`ANIMATE/*.FIN` is a **different container** — loaded via `"animate/%s"` (`animate.c`
`0x00425613`), and its header does not fit the layout above (its `flags` word reads `0x001D`).
It is not covered here.

---

## 7. Mouse and movies **(verified)**

**Mouse** (`mouse.c`). Two paths, both clamping to the screen:

* `0x00450E20`ff (absolute): clamps to `[0, 639] × [0, 479]`, stores to `0x0048C164/68`.
* `0x00450E80` (DirectInput `GetDeviceState`, relative): accumulates into
  `0x005327C0`/`0x005327C4`, clamps to `[0, 639] × [0, 479]`, mirrors into `0x004DFF14` /
  `0x004DFF1C`, which is the position the cursor blit and every hit test use.
* `win_init` seeds `0x004DFF14/1C` with (320, 240) — the screen centre.
* The cursor sprite is blitted with `IDirectDrawSurface::BltFast` from one of the 32 cursor
  surfaces and clipped by hand against 640×480 at `0x0042E1D2`…`0x0042E219`.

**Movies** (`avi.c`, `AVIFIL32` + `MSVFW32`). Source frames are **320×240** (`0x0040722B`,
`0x004074B1`, `0x0040762B`, `0x00407E14`) written into their own DirectDraw surface
(`0x00488E00`) with a hardcoded **320-pixel** stride (`add edx, 0x280` = 640 bytes,
`0x004074C2`) and a 180-row clear (`0x004074C8`) — i.e. some clips are letterboxed 320×180.
`avi_begin` `0x00406FD0` releases the game surfaces; `avi_end` `0x00406FF0` does
`SetDisplayMode(640,480,8)` → `SetDisplayMode(640,480,16)` → `create_surfaces`, a deliberate mode
cycle, so **both** mode setters are live. The back buffer is cleared directly at `0x004073C4`
with a hardcoded 640×480 extent and a **1280-byte row pitch** (`add ecx, 0x500`, `0x00407405`).

---

## 8. Complete inventory of resolution-dependent sites

Verified by disassembly and byte-checked in the file. `ENGEXP16.EXE` offsets were located by
relocation-tolerant byte matching and all resolve to a single uniform shift:
**`ENGEXP16 = Classic + 0x60` in `AUTO` from `0x6000` onward, `+0` below it, `+0x228` in
`DGROUP`** (98.3 % of `AUTO 0x7000…0x50000` is byte-identical at that shift).

Council Wars `dc16.exe` is a different build; only the §3 anchor is given for it.

### 8.1 Plain immediates

| Site | Classic VA | Classic file | Bytes | ENGEXP16 file |
|---|---|---|---|---|
| W global (640) | `0x00488DB4` | `0x865B4` | `80 02 00 00` | `0x867DC` |
| H global (480) | `0x00488DB8` | `0x865B8` | `E0 01 00 00` | `0x867E0` |
| `main.c` full-screen rect 639 | `0x004010E5` | `0x4E5` | `BF 7F 02 00 00` | `0x4E5` |
| `main.c` full-screen rect 479 | `0x004010EA` | `0x4EA` | `B8 DF 01 00 00` | `0x4EA` |
| avi back-buffer clear width 640 | `0x004073F4` | `0x67F4` | `3D 80 02 00 00` | `0x6854` |
| avi back-buffer row pitch 1280 | `0x00407405` | `0x6805` | `81 C1 00 05 00 00` | `0x6865` |
| avi back-buffer clear height 480 | `0x0040740B` | `0x680B` | `81 FA E0 01 00 00` | `0x686B` |
| avi movie-surface width 320 | `0x004074B1` | `0x68B1` | `3D 40 01 00 00` | `0x6911` |
| avi movie-surface pitch 640 B | `0x004074C2` | `0x68C2` | `81 C2 80 02 00 00` | `0x6922` |
| avi movie-surface rows 180 | `0x004074C8` | `0x68C8` | `81 F9 B4 00 00 00` | `0x6928` |
| map view rect h 448 | `0x0041ED1E` | `0x1E11E` | `B9 C0 01 00 00` | `0x1E17E` |
| map view rect w 512 | `0x0041ED23` | `0x1E123` | `BB 00 02 00 00` | `0x1E183` |
| map view rect x 4 | `0x0041ED63` | `0x1E163` | `B8 04 00 00 00` | `0x1E1C3` |
| map view rect y 6 | `0x0041ED6E` | `0x1E16E` | `BA 06 00 00 00` | `0x1E1CE` |
| `driver.c` row advance 640 (a) | `0x0042C194` | `0x2B594` | `BB 80 02 00 00` | `0x2B5F4` |
| `driver.c` row advance 640 (b) | `0x0042C261` | `0x2B661` | `BA 80 02 00 00` | `0x2B6C1` |
| `driver.c` clip rect w 640 | `0x0042C347` | `0x2B747` | `BB 80 02 00 00` | `0x2B7A7` |
| `driver.c` clip rect h 480 | `0x0042C363` | `0x2B763` | `B9 E0 01 00 00` | `0x2B7C3` |
| cursor clip w 640 (a) | `0x0042E1D2` | `0x2D5D2` | `B8 80 02 00 00` | `0x2D632` |
| cursor clip w 640 (b) | `0x0042E1FF` | `0x2D5FF` | `B8 80 02 00 00` | `0x2D65F` |
| cursor clip h 480 (a) | `0x0042E20E` | `0x2D60E` | `B8 E0 01 00 00` | `0x2D66E` |
| cursor clip h 480 (b) | `0x0042E219` | `0x2D619` | `B8 E0 01 00 00` | `0x2D679` |
| mouse init X 320 | `0x0042E7C4` | `0x2DBC4` | `BA 40 01 00 00` | `0x2DC24` |
| mouse init Y 240 | `0x0042E7C9` | `0x2DBC9` | `B9 F0 00 00 00` | `0x2DC29` |
| `SetDisplayMode` 8-bit h 480 | `0x0042E898` | `0x2DC98` | `68 E0 01 00 00` | `0x2DCF8` |
| `SetDisplayMode` 8-bit w 640 | `0x0042E8A2` | `0x2DCA2` | `68 80 02 00 00` | `0x2DD02` |
| `SetDisplayMode` 16-bit h 480 | `0x0042E91C` | `0x2DD1C` | `68 E0 01 00 00` | `0x2DD7C` |
| `SetDisplayMode` 16-bit w 640 | `0x0042E926` | `0x2DD26` | `68 80 02 00 00` | `0x2DD86` |
| offscreen surface w 640 | `0x0042EA89` | `0x2DE89` | `B8 80 02 00 00` | `0x2DEE9` |
| offscreen surface h 480 | `0x0042EA8E` | `0x2DE8E` | `BA E0 01 00 00` | `0x2DEEE` |
| `load.bmp` `LoadImageA` h | `0x0042EF07` | `0x2E307` | `68 E0 01 00 00` | `0x2E367` |
| `load.bmp` `LoadImageA` w | `0x0042EF0C` | `0x2E30C` | `68 80 02 00 00` | `0x2E36C` |
| `load2.bmp` `LoadImageA` h | `0x0042EF38` | `0x2E338` | `68 E0 01 00 00` | `0x2E398` |
| `load2.bmp` `LoadImageA` w | `0x0042EF3D` | `0x2E33D` | `68 80 02 00 00` | `0x2E39D` |
| splash `BitBlt` h 480 | `0x0042EFED` | `0x2E3ED` | `68 E0 01 00 00` | `0x2E44D` |
| splash `BitBlt` w 640 | `0x0042EFF2` | `0x2E3F2` | `68 80 02 00 00` | `0x2E452` |
| clear loop `W*H` (a) | `0x0042F7AD` | `0x2EBAD` | `3D 00 B0 04 00` | `0x2EC0D` |
| clear loop `W*H` (b) | `0x0042F7E2` | `0x2EBE2` | `3D 00 B0 04 00` | `0x2EC42` |
| viewport tiles down 14 | `0x00435E47` | `0x35247` | `B9 0E 00 00 00` | `0x352A7` |
| viewport tiles across 16 | `0x00435E4F` | `0x3524F` | `BB 10 00 00 00` | `0x352AF` |
| viewport width 512 | `0x00435F46` | `0x35346` | `BA 00 02 00 00` | `0x353A6` |
| viewport height 448 | `0x00435F61` | `0x35361` | `BB C0 01 00 00` | `0x353C1` |
| occlusion mask size `0x7000` | `0x00435F88` | `0x35388` | `BA 00 70 00 00` | `0x353E8` |
| render dest stride 640 | `0x00435F9F` | `0x3539F` | `B8 80 02 00 00` | `0x353FF` |
| minimap rows 84 | `0x0043A07E` | `0x3947E` | `BB 54 00 00 00` | `0x394DE` |
| minimap cols 96 | `0x0043A083` | `0x39483` | `BF 60 00 00 00` | `0x394E3` |
| minimap stride 640 (a) | `0x0043A09B` | `0x3949B` | `B8 80 02 00 00` | `0x394FB` |
| minimap origin `0x220E` (a) | `0x0043A0AF` | `0x394AF` | `81 C2 0E 22 00 00` | `0x3950F` |
| minimap stride 640 (b) | `0x0043A45B` | `0x3985B` | `BA 80 02 00 00` | `0x398BB` |
| minimap x step `96<<8` | `0x0043A463` | `0x39863` | `B8 00 60 00 00` | `0x398C3` |
| minimap y step `84<<8` | `0x0043A478` | `0x39878` | `B8 00 54 00 00` | `0x398D8` |
| minimap origin `0x220E` (b) | `0x0043A484` | `0x39884` | `81 45 F0 0E 22 00 00` | `0x398E4` |
| mouse clamp `cmp 640` | `0x00450E47` | `0x50247` | `81 FE 80 02 00 00` | `0x502A7` |
| mouse clamp `set 639` | `0x00450E4F` | `0x5024F` | `BE 7F 02 00 00` | `0x502AF` |
| mouse clamp `cmp 480` | `0x00450E5C` | `0x5025C` | `81 FF E0 01 00 00` | `0x502BC` |
| mouse clamp `set 479` | `0x00450E64` | `0x50264` | `BF DF 01 00 00` | `0x502C4` |
| DI clamp `cmp 639` | `0x00450F46` | `0x50346` | `3D 7F 02 00 00` | `0x503A6` |
| DI clamp `set 639` | `0x00450F4D` | `0x5034D` | `C7 05 C0 27 53 00 7F 02 00 00` | `0x503AD` |
| DI clamp `cmp 479` | `0x00450F6B` | `0x5036B` | `81 FE DF 01 00 00` | `0x503CB` |
| DI clamp `set 479` | `0x00450F73` | `0x50373` | `C7 05 C4 27 53 00 DF 01 00 00` | `0x503D3` |

### 8.2 Hidden multiplies — the trap

Watcom strength-reduced `× 640` and `× 1280` into `(y*4 + y) << n`, so **searching the
disassembly for `280h` finds only 17 sites and misses these three entirely**:

| Site | Classic VA | Classic file | Bytes | ENGEXP16 file | Effect |
|---|---|---|---|---|---|
| `driver.c` `y*640` | `0x0042C213` + `0x0042C218` | `0x2B613`, `0x2B618` | `01 CA` … `C1 E2 07` | `0x2B673`, `0x2B678` | `edx = (y*4 + y) << 7` |
| `engmain.c` `y*1280` (bytes) | `0x004360B9` + `0x004360BE` | `0x354B9`, `0x354BE` | `01 F8` … `C1 E0 08` | `0x35519`, `0x3551E` | `eax = (y*4 + y) << 8` |
| `engmain.c` `y*640` | `0x004363BD` + `0x004363C5` | `0x357BD`, `0x357C5` | `01 C8` … `C1 E0 07` | `0x3581D`, `0x35825` | `eax = (y*4 + y) << 7` |

A full sweep for `shl reg, 4…12` preceded by a `×3`/`×5` idiom found no other framebuffer strides;
the remaining hits are struct strides (`×96`, `×160`, `×192`, `×384`, `×1600`), the minimap grid
row stride (`×384` = 96 × 4), signed-divide idioms and percentage scaling.

### 8.3 Not verified / still open

* `0x0044EF15` (`gifload.c`): an 8-bit writer with a hardcoded **320**-pixel stride over a
  16-iteration loop, using the shade LUT at `0x0048C188`. Purpose not identified. Must be read
  before trusting a non-640 mode.
* `driver.c` `0x0042BCCE`, `0x0042BEFE`, `0x0042BFC1`, `0x0042C146` were not decoded individually;
  `0x0042BCEE` loads `0x4B000` (= 640·480) into `esi`, so at least one of them is a full-screen
  pass that needs the same treatment as `clear_screen`.
* The two dwords `0x14F`, `0x16E` at `DGROUP 0x00488DAC/B0` were not identified.
* Nothing here was re-verified in Council Wars `dc16.exe`.

---

## 9. Target geometry for 1024×768

**Why 1024 and not 800.** `1024 = 2^10`, so every `y * width` becomes a single shift. The three
hidden multiplies of §8.2 then need only a *length-preserving* two-instruction edit — neutralise
the `+ y` and bump the shift by one:

| Site | From | To | Result |
|---|---|---|---|
| `0x0042C213` / `0x0042C218` | `01 CA` / `C1 E2 07` | `89 D2` / `C1 E2 08` | `(y*4) << 8 = y*1024` |
| `0x004363BD` / `0x004363C5` | `01 C8` / `C1 E0 07` | `89 C0` / `C1 E0 08` | `(y*4) << 8 = y*1024` |
| `0x004360B9` / `0x004360BE` | `01 F8` / `C1 E0 08` | `89 C0` / `C1 E0 09` | `(y*4) << 9 = y*2048` B |

(`89 D2` = `mov edx,edx`, `89 C0` = `mov eax,eax` — two-byte no-ops, so no NOP sleds, no shifted
code, and no risk of landing inside a jump target.) With 800 pixels each of these would need a
real `imul` or a longer sequence and therefore code relocation. Recommend **1024×768** and treat
800×600 as out of scope.

**Layout.** Keep the HUD chrome at its native pixel size and spend all the new space on the map
view. Current chrome is 124 px on the right and 26 px at the bottom, with a 4/6 px inset:

| | 640×480 (now) | 1024×768 (target) |
|---|---|---|
| screen | 640 × 480 | 1024 × 768 |
| map viewport | 512 × 448 = 16 × 14 tiles | **896 × 736 = 28 × 23 tiles** |
| map view rect | (4, 6, 512, 448) | (4, 6, 896, 736) |
| occlusion mask | `0x7000` (512·448/8) | **`0x14200`** (896·736/8 = 82 432) |
| minimap | 96 × 84 at (519, 6) | 96 × 84 at (903, 6), origin byte `0x370E` |
| clear loop count | `0x4B000` | **`0xC0000`** (1024·768) |
| avi row pitch | `0x500` | **`0x800`** |
| mouse clamp | 639 / 479 | **1023 / 767** (`0x3FF` / `0x2FF`) |
| mouse centre | 320 / 240 | **512 / 384** (`0x200` / `0x180`) |

896 and 736 are both exact multiples of 32, so no partial tile row or column is introduced. The
minimap origin is `(6 * 1024 + 903) * 2 = 0x370E`.

**What this does *not* do.** Nothing is scaled. Sprites, fonts, buttons, the HUD and every menu
background stay at their 640×480 pixel size, so at 1024×768 they occupy proportionally less of the
screen and the panel art has 288 px of empty space below it. Fixing that is art work (§10 stage
5), not patching.

---

## 10. Staged plan

Each stage ends in a runnable binary, so a regression can be bisected to one stage. Mirror every
stage in `ENGEXP16.EXE` using the `+0x60` / `+0x228` rule of §8 and re-verify the bytes before
writing.

### Stage 0 — reproducible patching (done)

The two CD patches so far were single-byte edits recorded only in the commit history. Sixty-odd
multi-byte edits across two binaries need a script, so `tools/patch_resolution.py` is that script
and **it, not §8, is now the authoritative copy of the site table**. It

* takes `--width`/`--height` and a `--stage` (1…4, cumulative, matching the stages below);
* locates the globals by the **4-byte** prefix `4F 01 6E 01` of the §3 anchor — deliberately not
  the full 12-byte sequence, because that contains the dimensions and so stops matching the moment
  the file is patched, which would break `verify`. The 4-byte prefix is unique in all three stock
  builds *and* in a patched one;
* identifies the build by MD5, and derives `ENGEXP16` offsets with the `+0x60` rule;
* applies each site as `(file_offset, expected_bytes, new_bytes)` and **refuses to write unless
  every selected site still holds its expected bytes** — that check is what makes relying on the
  shift rule safe rather than a guess, and it makes a double-apply or a wrong build fail loudly;
* keeps instruction lengths identical at every site, so no code moves and no jump target shifts;
* writes a `.bak` (and never overwrites an existing one, which is assumed to be pristine).

Three commands: `verify` reports a binary's state — for a patched file it reads the geometry back
out of the globals and tallies, per stage, how many sites are patched / stock / unrecognised, which
is what makes the staged bisection below usable. `plan` prints every edit and writes nothing.
`apply` patches, then prints the data and art work that is left.

Verified end to end: 57 edits on Classic and 57 on `ENGEXP16` (55 code sites plus the two
globals); `--stage 1` applies 20 and `verify` then correctly reports stages 2–4 as untouched;
re-applying is refused; the `.bak` is byte-identical to the original; and the three rewritten
multiply sequences were re-disassembled out of the patched binary to confirm they read

```
0042C213: 89 D2   mov edx,edx        0042C218: C1 E2 08   shl edx,8     ; y*1024
004363BD: 89 C0   mov eax,eax        004363C5: C1 E0 08   shl eax,8     ; y*1024
004360B9: 89 C0   mov eax,eax        004360BE: C1 E0 09   shl eax,9     ; y*1024*2 bytes
```

with every following instruction still at its original address. The optional-header `CheckSum` of
these binaries is `0`, so there is nothing to recompute after patching.

### Stage 1 — prove the display mode (letterbox)

Patch only: the two globals (§3), both `SetDisplayMode` calls, the offscreen surface size, the
clear-loop count, the `driver.c` clip rect, and the three hidden multiplies of §9.

Leave the map viewport, the minimap, the HUD rect, the mouse clamps and all art alone. Expected
result: a 1024×768 framebuffer with the game drawn in its top-left 640×480 corner and the rest
black or garbage. What this proves: that DirectDraw gives us a 1024×768×16 exclusive-fullscreen
flip chain on the target machines, that `pitch == width * 2` still holds for the system-memory
offscreen surface, and that the blitters follow `screen->width` as advertised.

**Watch for:** neither `set_mode_16` nor `create_surfaces` has a fallback if 16-bit at the new size
is refused — they print an error and abort. If a machine refuses RGB565 at 1024×768 there is no
second chance in the code.

**Result, run 9 Sep 2026 on Windows 11 (1280×800 desktop).** Stage 1 applied to a copy of
Classic `dc16.exe` (20 edits), launched from `DC - Classic/`:

* the mode was granted — `PrimaryScreen.Bounds` read **1024×768** while the game ran, and the
  desktop was restored on exit;
* the process ran stably for the whole 20 s observation, no assert, `error.log` stayed empty;
* `pitch == width * 2` holds and the blitters do follow `screen->width`: the loading screen, the
  intro movie, the `DC` logo, the title, the credits and the whole button grid rendered sharp and
  at their correct coordinates in the top-left 640×480. A wrong stride would have sheared every
  one of them diagonally;
* the 640×480 loading screen and the letterboxed intro AVI sat in the top-left corner on black,
  exactly as intended for this stage.

One real defect surfaced, which is what the stage exists for — §10.1 below.

#### 10.1 Full-screen `.GIF` backgrounds skew — repaint them, do not centre them **(verified)**

The main menu came up with its logo, title and buttons correct but its **background** wrecked: the
Mars limb gone, replaced by diagonal red streaks, and the starfield smeared across the full
1024 px width. Captured side by side with the stock binary at 640×480, which is clean, so this is
new and not the menu's own animated interference.

Cause, read out of `gifload.c`: the GIF LZW decoder `0x0044EB7C` writes **straight into the locked
16-bit framebuffer** (`esi = screen->pixels`, colours through `screen->LUT + 0x602`), and its
output loop has **no row-stride advance at all** — `add esi,2` per pixel at
`0x0044ECC5`/`0x0044ECCE`, and `add esi,length*2` for a multi-pixel LZW string at `0x0044ECF4`. It
streams the whole image as one linear run, which is correct only while
`image width == framebuffer stride`. Give a 640-wide GIF a 1024-stride framebuffer and every row
lands 384 px early, so the picture shears left and compresses vertically by 640/1024.

**There is no constant to patch here.** The stride is not wrong, it is absent. Two options:

1. **Repaint every full-screen background at the target resolution** (stage 5). Then width equals
   stride again and the linear write is correct. This is the cheap route and the art work was
   going to do it anyway — but it is now **required**, not optional, for any screen with a
   `background` line.
2. Inject a row advance into the decoder. There is no room in place, so that means a code cave and
   a jump: a much bigger change than anything else in this plan.

**Correction to the plan this forces:** re-centring a 640×480 script with `size 192 144 640 480`
(stage 2) fixes where its *widgets* land but **not its background**, which never goes through the
widget rect. Scripts naming a `background` need their art repainted; scripts without one are fully
fixed by the `size` edit alone. The ones naming a background are `MAINE` (`intrface/intrface`),
`NEWGAMEE` and `LOGOE` (`intrface/choo`), `METAE` and `LOADGE` (`intrface/loader`), `BUTTONSE`
(`intrface/intro`), plus the `.DAT`-driven intro screens.

### Stage 2 — full-screen chrome, menus centred

* Mouse clamps and centre → 1023/767, 512/384.
* Cursor clip → 1024/768.
* `main.c` full-screen rect → 1023/767.
* Loading screens: either repaint `LOAD.BMP`/`LOAD2.BMP` at 1024×768 (the `LoadImageA` and
  `BitBlt` calls just take the new numbers), or keep them 640×480 and centre them by changing the
  `BitBlt` destination — the simpler edit is to repaint the art.
* Menus: edit one line per `INTRFACE/*E` script (§6) from `size 640 480` to
  `size 192 144 640 480`. This centres every menu, lobby and dialog with **no patching**. The
  in-game map view is positioned separately (`proto.c`, stage 3) and is unaffected.
  **But this only moves the widgets** — the seven scripts with a `background` line also need
  their art repainted at the target size, because the GIF decoder ignores the widget rect and
  writes linearly to the framebuffer (§10.1). Until that art exists those screens show a correct
  button layout over a skewed background.

At the end of stage 2 the game is a genuine 1024×768 application with 640×480 content boxed in the
middle — clean on the background-less screens, and needing the seven repaints of §10.1 for the
rest. This is already a usable state and a sensible place to stop if the art work stalls.

### Stage 3 — enlarge the map viewport

* `engmain.c` viewport 512 → 896, 448 → 736; tiles 16 → 28, 14 → 23.
* Occlusion mask `0x7000` → `0x14200`.
* Render dest stride 640 → 1024.
* `proto.c` map view rect 512 → 896, 448 → 736 (keep x=4, y=6).
* Minimap origin `0x220E` → `0x370E`, both strides 640 → 1024.

The lightplane and its stride follow automatically (§5), so no edit is needed there.

Then re-derive, from the disassembly, everything the terrain and object renderers clamp against.
`0x00435E24` (clip view to map) builds `make_rect(view_x>>5, map_h - (view_y>>5) - 14, 16, 14)`
from the same two tile counts, so those two immediates look like they cover the scroll clamp as
well — but that must be confirmed, together with `lighting.c` `0x00453910` and `sprite.c`
`0x004543FC`, before declaring the stage done.

**Consequence to accept:** a 28×23-tile view on a 256×256-tile map shows 2.9× the area. This is
render-side only — the lockstep checksum (`sync.c`, `DC16_BATTLE_ENGINE.md` §16) covers simulation
state and not the camera, and the relay server (`Dark-Colony-Server`) never sees viewport data — so
it does not desync. It *is* a competitive change if a patched and an unpatched client meet in the
same game.

### Stage 4 — cursors and movies

* Cursors are `IDirectDrawSurface` blits at 1:1, so they simply look small. Redrawing
  `CURSOR/cursor%d.bmp` at 1.6× is optional and independent.
* Movies: the 320×240 source and its 320-pixel stride are independent of the screen size, but the
  back-buffer clear at `0x004073C4` hardcodes 640×480 and a 1280-byte pitch and **must** be
  updated or it will clear only the top-left corner of a 1024×768 back buffer (cosmetic, not a
  crash). The clip is on the back buffer, not the offscreen surface, so `screen->width` does not
  help here.
* Where the movie is placed on screen was not traced; expect to find its destination rect near
  `0x00407E14`. This ties into README goal 3 ("increase quality of movies") — a higher-resolution
  re-encode would need this whole path reworked, which is a separate project.

### Stage 5 — HUD reflow (data only)

No patching and no reverse engineering here: the HUD is `MAINE` + `INTRFACE.GIF` +
`MAINBUT.SPR` (§6.1). `MAINBUT.SPR` needs no change at all — the buttons are the same buttons.

1. **Vectorise before repainting.** Do not resample the 640×480 art up to 1024×768. Trace each
   element to vector (SVG) first, keep the vector as the master, and render the raster from it at
   the target size. Rendering from geometry is what keeps edges sharp — a 1.6× resample can only
   blur or blockify what is already there, whereas a traced bevel or border re-rendered at 1024×768
   is exactly as crisp as the original was at 640×480, and gradients and highlights come out
   smoother than the 8-bit source. It also turns this from a one-off repaint into an asset
   pipeline: commit the SVGs and any future resolution (1440p, 4K, or the 800×600 that §9 rejects
   for code reasons) is a re-render, not another manual repaint.

   **Which elements this pays off on.** `INTRFACE.GIF` is not uniform material — measured over its
   27 230 opaque pixels (80 distinct palette indices):

   | Measure | Value | Reading |
   |---|---|---|
   | mean horizontal run | 1.93 px (median 1, max 634) | mixed: long structural runs plus fine noise |
   | opaque px in runs ≥ 4 px | 43.4 % | the structural half — borders, bevels, panel outlines |
   | opaque px in runs of 1 px | 44.7 % | per-pixel shading detail |
   | pixels matching the one below | 32.5 % | little vertical coherence |
   | dither-pattern pixels | 6.1 % | deliberate 2-colour dithering |

   So split the work: **trace the structural 43 %** — the frame borders, the bevels, the rectangular
   panel outlines, and above all the map-view hole boundary, which is mostly long axis-aligned runs
   and vectorises essentially losslessly. Do **not** blindly trace the noisy interior fill; a
   general-purpose tracer turns 44.7 % single-pixel detail and 6.1 % dither into thousands of
   micro-paths that render worse than the original. Handle those regions as tiled/procedural
   texture, or with a pixel-art-aware upscaler, or by hand.

   **Tools.** Inkscape's *Trace Bitmap* with multi-colour scans, or its *Pixel art* mode
   (Kopf–Lischinski depixelization, `libdepixelize`) which is designed for exactly this kind of
   source; `potrace`/`autotrace` per colour plane for scripted runs. Snap traced geometry to the
   pixel grid so borders stay axis-aligned.

   **Two hard constraints on the render-back step.** (a) The output must be **8-bit indexed in the
   game's existing palette** (`MAINE` says `palette palette`, i.e. `PALETTE.GIF`/`.RGB`/`.RMP`) —
   `gifload.c` consumes indices directly and does no re-quantisation. (b) The erase colour must
   stay **exactly index 254** across the whole map-view hole: render the hole as a hard mask, with
   anti-aliasing and dithering **off** at its boundary. Any interpolated near-black pixel that is
   not index 254 stops being transparent and shows as a halo along the edge of the map view.

   **Sequencing.** Nothing is blocked. `INTRFACE.GIF` is a plain GIF, and `.SPR` is decoded with a
   working codec in `tools/spr.py` (§6.3), so traced cells can be re-imported into `MAINBUT.SPR` and
   the fonts as soon as the SVGs exist. Use `spr.py extract` → trace → render → `spr.py build`, and
   `spr.py check` to verify. Fonts are the strongest vectorisation candidate of all — glyphs are
   shapes, and a vector font makes every future resolution free.

2. **`INTRFACE/INTRFACE.GIF`** — render at 1024×768 from the vector master. The 8.9 % of it that is
   opaque has to move:
   the transparent hole becomes `(4,6)-(899,741)` (896×736), the left border stays at columns 0–3,
   the top border at rows 0–5, the map-view right edge moves from columns 515–517 to 899–901, the
   right screen border from 636–639 to 1020–1023, and the bottom bar from rows 454–479 to 742–767.
   The 124 px-wide panel column and the 26 px-tall bottom bar keep their pixel dimensions, so most
   of the existing artwork can be translated rather than redrawn — except that the panel column is
   now 768 px tall instead of 480 and needs 288 px of new filler between the widget groups.
3. **`INTRFACE/MAINE`** — shift the widget coordinates:
   * the 75 right-panel widgets (x `516…638`) → `x += 384`, giving x `900…1022`;
   * the 4 bottom-bar widgets (y `460…463`) → `y += 288`, giving y `748…751`;
   * the 3 message-line widgets over the map (`in_text #203`/`#204` at y 425/440, `picture #199`)
     → `y += 288` to stay the same distance above the bottom bar;
   * leave `size 640 480` → `size 1024 768`.
   That is a scripted edit over one text file, easy to verify by re-parsing and re-checking the
   zone counts.
4. The minimap is **not** in `MAINE` — it is the code patch in stage 3.
5. Optionally re-render the other 18 × 640×480 `INTRFACE/*.GIF` backgrounds at 1024×768 — same
   vector-first route as step 1, and easier there because they are full images with no transparency
   hole to preserve — then drop the `size 192 144 640 480` centring from stage 2.
6. Optionally redraw the fonts (`INTRFACE/FONT.SPR`, `MFONT*`) larger, from vector outlines per
   step 1 and via `tools/spr.py` (§6.3). `FONT.SPR` is 122 raw cells, 1…38 px wide by 28…29 tall —
   variable-width glyphs starting at `!`, with an alien head in place of `*`. The widget scripts
   carry per-font metrics, so a larger font is a data change plus a per-script `x y w h`
   adjustment.

Because stages 2 and 5 are pure data, they can be developed and tested against the **unpatched**
exe first (a 640×480 `MAINE` with shifted coordinates will simply look wrong, but it proves the
parse), which de-risks them completely.

### Stage 6 — parity and release

* Apply every stage to `ENGEXP16.EXE` and diff-verify.
* Council Wars `dc16.exe`: re-derive all offsets in Ghidra (only the §3 anchor transfers).
* The map editor (`maped_by_ozy_ns_v1.2PL.exe`) is a separate binary with its own 640×480
  assumptions and is **not** covered here.
* Commit each stage separately with a message describing the behaviour change, per the repo
  convention.

---

## 11. Risks

| Risk | Assessment |
|---|---|
| No fallback if 1024×768×16 is refused | Real. `set_mode_16` / `create_surfaces` abort. Mitigate by keeping the unpatched exe alongside, and consider adding a mode-list walk later. |
| `pitch != width * 2` on the offscreen surface | The code ignores `lPitch` everywhere. For a `SYSTEMMEMORY` surface DirectDraw has always returned a tight pitch; 1024 px = 2048 B is a friendlier alignment than 1280 B, so this is lower risk after the change than before. Verify once in stage 1. |
| A missed hardcoded 640 | The §8.2 sweep was systematic but §8.3 lists three unresolved items. Symptom would be a skewed or torn band rather than a crash. |
| Menu scripts drifting from the exe | Low: the `size` line is data and the parser accepts both forms (§6, verified). |
| Multiplayer fairness | Stage 3 changes what a player can see. Not a desync (§10 stage 3), but a balance issue between patched and unpatched clients. Decide whether to gate it. |
| Growing `.bss` | Not needed — nothing resolution-dependent lives there (§5). |

---

## 12. Address index

| Address | Meaning |
|---|---|
| `0x00488DB4` / `0x00488DB8` | **screen width / height globals (`DGROUP`)** |
| `0x0040117F`ff | `main.c`; full-screen rect at `0x004010E5` |
| `0x00406FD0` / `0x00406FF0` | `avi_begin` / `avi_end` (mode cycle) |
| `0x004073C4` | clear back buffer for movie (640×480, pitch `0x500`) |
| `0x0041EB34` / `0x0041EB63` | `proto.c`: `"intrface/main"` → `load_interface`, HUD handle to `0x004AB1C4` — same function as the map view rect below |
| `0x0041ED1E`ff | `proto.c` initial camera + map view screen rect |
| `0x004231E8` / `0x004231B0` | `load_interface(app, name, flags)` / free — 21 call sites, one per screen |
| `0x0040B430` | `timeGetTime` thunk (**not** a loader — easy to misread next to the HUD load) |
| `0x0042BD78` | `new_screen` (0x1A4 bytes) |
| `0x0042C29C` | `driver_create` — builds `ctx` (0xEC) + `screen`, sets clip/bounds |
| `0x0042C405`ff | copies `screen+0x100…` method slots into `ctx+0x30…` |
| `0x0042E688` | `create_window` (reads the globals) |
| `0x0042E7B4` | `win_init` |
| `0x0042E890` / `0x0042E914` | `SetDisplayMode` 8-bit / 16-bit |
| `0x0042E998` | `create_surfaces` |
| `0x0042F2D0` / `0x0042F320` | `make_colour` / `set_palette` |
| `0x0042F774` | `clear_screen` (`0x4B000` words + `Flip`) |
| `0x0042F828` / `0x0042F8D8` | `lock_screen` / `unlock_screen` |
| `0x0042FBF0` | `install_ddraw_driver` |
| `0x004223A8` | `widget.c` `size` keyword parser (2 or 4 numbers) |
| `0x004232E2`ff | `widget.c` interface-script keyword dispatch |
| `0x00435E24` | clip view rect to map (uses the 16/14 tile counts) |
| `0x00435E7C` | build the render view struct at `0x005044AC` |
| `0x00436080` | per-frame `set_view_target` (`y*1280` at `0x004360BE`) |
| `0x00436380`ff | main map render: lock, terrain, objects, unlock, minimap |
| `0x004365BC` | `make_rect(x, y, w, h)` → `{x, y, x+w, y+h}` |
| `0x0043A064` / `0x0043A43C` | minimap terrain plot / minimap object plot |
| `0x0044EE30` | allocate the shade LUT at `0x0048C188` |
| `0x0042532C` | `load_sprite_bank` (`animate.c`) — `"sprites/%s"` (§6.3) |
| `0x0044F790` / `0x0044F818` | `.SPR` size helper / parser (`ctx+0x44` / `ctx+0x40`) (§6.3) |
| `0x0044FAC0` | **sprite-cell blitter**, raw cells (`juicel.c`) — resolution-independent |
| `0x0044FC44` | sprite-cell blitter, RLE cells; decode loop `0x0044FD4F` (§6.3) |
| `0x0044FE81`ff | per-cell draw dispatcher; applies cell offsets at `0x0044FE9A`/`0x0044FEA2` |
| `0x0044FFC0` | `image.c` full-screen 8-bit page (`malloc(W*H)`) |
| `0x00450E20` / `0x00450E80` | mouse absolute / DirectInput poll + clamp |
| `0x00453770` | `lighting_init` — allocates the "lightplane" at the viewport size, sets `0x0049931C` (viewport width) and `0x005360B0` (viewport pixel count) |
| `0x00453910` | `draw_terrain` (`lighting.c`); `>> 5` ⇒ 32-px tiles |
| `0x004537AD` | load `FADE.DAT` into `0x00533C90` (`0x2420` B) |
| `0x004543FC` | `draw_objects` (`sprite.c`) |
| `0x004DFF14` / `0x004DFF1C` | current mouse X / Y |
| `0x004DEC90/92/94` | R/G/B → 16-bit component LUTs |
| `0x005044AC` | render view struct (§5) |
| `0x0048C188` | shade LUT base (`level * 512 + idx * 2`) |
| `0x0048978C` / `0x00489790` | global `ctx` / `screen` |
| `0x00533C84` | current destination pixel pointer |

---

## 13. How this was produced

`dumpbin -NOLOGO -ALL -DISASM` output of Classic `dc16.exe` (`dc16.asm` in the development
folder), plus:

* the `DGROUP` raw hex dump reassembled into a binary to extract strings with their VAs
  (`VA = file offset + 0x402800`), which gave the assert `*.c` file names and hence a **module map
  in link order** — that is what localised the renderer to `engmain.c` / `lighting.c` /
  `sprite.c` / `juicel.c`;
* following the DirectDraw COM vtable offsets (`IDirectDraw::CreateSurface` `+0x18`,
  `SetCooperativeLevel` `+0x50`, `SetDisplayMode` `+0x54`; `IDirectDrawSurface::Blt` `+0x14`,
  `Flip` `+0x2C`, `GetAttachedSurface` `+0x30`, `GetDC` `+0x44`, `GetSurfaceDesc` `+0x58`,
  `Lock` `+0x64`, `SetPalette` `+0x7C`, `Unlock` `+0x80`) and the `DDSURFACEDESC` layout;
* enumerating the call sites of the `ctx+0x8C` / `ctx+0x90` lock/unlock pair to get the complete
  set of direct framebuffer writers;
* a scripted sweep of `shl reg, 4…12` preceded by a `×3`/`×5` idiom to find the strength-reduced
  strides of §8.2, which a search for `280h` alone does not find;
* relocation-tolerant byte matching of a window around each Classic site against `ENGEXP16.EXE`
  and Council Wars `dc16.exe` (masking any dword in `0x401000…0x542000`) to produce the
  cross-binary offsets, then a byte-for-byte re-check of every match;
* reading `INTRFACE/MULTIE~1.TXT`, `LOPTE` and `MAINE` directly, which is how the interface
  scripts turned out to be editable text;
* to identify the HUD: resolving every `intrface/*`, `sprites/*`, `animate/*`, `gamestat/*` string
  in `DGROUP` to the code addresses that reference it, then mapping those addresses to modules via
  the assert-string module map — which showed `"intrface/main"` being loaded by `proto.c` right
  beside the map-view rect, rather than by `interface.c` as the module name suggests;
* decoding `INTRFACE.GIF` with PIL and histogramming the presumed map rect against the rest, then
  reducing per-column and per-row opacity to runs, to confirm the frame geometry independently of
  the disassembly.

* to decode `.SPR` (§6.3): reading `juicel.c`'s parser and both blitters rather than pattern-matching
  the files, then validating by re-encoding all 15 088 compressed cells and by rendering cells to PNG
  (the buttons and font glyphs are immediately recognisable, which is the cheapest possible check
  that a palette-and-RLE guess is right).

Three dead ends worth recording, so they are not repeated: the in-game panel is **not** in a `.SPR`
bank of its own (it is the `INTRFACE.GIF` background of `MAINE`); `interface.c` is the
save/load/options **dialog** module (`intrface/lsg`, `lobj`, `lqc`, `lopt`), not the HUD; and the
`.SPR` palette starts at offset **8**, not at the first `3F 3F 3F` triple — assuming the latter puts
the cell directory at 779 instead of 776, which by coincidence makes width/height look big-endian
and fits some files but not others.
