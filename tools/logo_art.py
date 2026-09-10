#!/usr/bin/env python3
"""Re-set the main-menu title (DARK COLONY, SPRITES/DCUT.SPR) with a bevelled, brushed surface.

The stock title is 1997 pixel art in an extended stencil face, 398x33, with a dithered fill and
staircase edges; at 1024x768 the maintainer found it rough. This tool renders it from a
typeface - Impact (Windows), stretched to the cell like the stock's extended face; no stencil
font exists on the machine and traced 33 px glyphs came out lumpy - with a lit bevel, gradient,
brushed streaks and grain, quantised into the game's master palette, and rebuilds the five
animation cells. The maintainer approved this look on 10 Sep 2026.

The DC mark (DCUK.SPR) is deliberately *not* touched here. Two re-renders of it were tried the
same day - a parametric vector redesign, then the stock silhouettes smoothed and re-lit - and the
maintainer rejected both: the mark stays the original 1997 pixel art, re-baked onto black by
paint_intro.py (SCREENS mode 'black').

Rendering: supersample 8x, box-filter to the cell for anti-aliased coverage, an erosion distance
field for a 2 px bevel lit from the top left with a specular highlight, a top-to-bottom tan
gradient, horizontal brushed streaks and fine grain, a dark 1 px rim so the letters read on
black, then nearest-colour quantisation with a little dither into the palette indices with
r >= g >= b (tans, browns, greys - no blue/green speckle). Black is index 0 (the sprite
convention; DCUT is drawn `unmask` on the black disc).

Cells (all 398x33): the stock's solid flash, a dark-red fade-in, a red-white glow, the final
letters with a hot highlight, the final letters. ANIMATE/DCUT.FIN is unchanged.

Both `SPRITES/` (what the game draws through ANIMATE/*.FIN, see paint_intro.py) and `INTRFACE/`
copies are written, with a .bak of the stock file beside each. paint_intro.py leaves the bank
alone (SCREENS mode 'art'). Run order: paint_intro.py apply, then logo_art.py apply.

CLI
    python logo_art.py apply   GAME_DIR [--seed 3]
    python logo_art.py preview GAME_DIR OUT.png      # final frame over the menu background
"""

import argparse
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from spr import read_spr, write_spr                                     # noqa: E402
from paint_intro import find_ci, intrface_dir, parse_widgets, need_np    # noqa: E402

S = 8                                   # supersampling factor
TITLE_W, TITLE_H = 398, 33
FONT = ('impact.ttf', 'arialbd.ttf', 'bahnschrift.ttf')
FONT_DIRS = ('C:/Windows/Fonts', '/usr/share/fonts/truetype/msttcorefonts')
SPRITE_DIRS = ('SPRITES', 'INTRFACE')

TAN_TOP, TAN_BOTTOM = (232, 170, 112), (172, 112, 60)
SPEC = (255, 236, 208)
LIGHT = (-0.45, -0.75, 0.55)
FLASH_TITLE = 193                       # the stock's solid first frame


def need_pil():
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    return Image, ImageDraw, ImageFont, ImageFilter


# ------------------------------------------------------------------ the title
def find_font():
    for d in FONT_DIRS:
        for fn in FONT:
            p = os.path.join(d, fn)
            if os.path.exists(p):
                return p
    raise SystemExit('no usable font found (looked for %s in %s)' % (FONT, FONT_DIRS))


def title_mask8(np, text='DARK COLONY', margin=1):
    Image, ImageDraw, ImageFont, _ = need_pil()
    f = ImageFont.truetype(find_font(), 46 * S)
    tmp = Image.new('L', (12000, 600), 0)
    d = ImageDraw.Draw(tmp)
    bb = d.textbbox((0, 0), text, font=f)
    d.text((-bb[0], -bb[1]), text, font=f, fill=255)
    glyphs = tmp.crop((0, 0, bb[2] - bb[0], bb[3] - bb[1]))
    w, h = (TITLE_W - 2 * margin) * S, (TITLE_H - 2 * margin) * S
    glyphs = glyphs.resize((w, h), Image.LANCZOS)
    im = Image.new('L', (TITLE_W * S, TITLE_H * S), 0)
    im.paste(glyphs, (margin * S, margin * S))
    return np.array(im) > 127


# ------------------------------------------------------------------ shading
def box_down(np, a):
    h, w = a.shape[0] // S, a.shape[1] // S
    return a.reshape(h, S, w, S).mean((1, 3))


def erosion_distance(np, mask, steps):
    """How many erosions a pixel survives (capped), an octagonal distance to the edge."""
    d = np.zeros(mask.shape, np.int32)
    cur = mask.copy()
    for i in range(steps):
        n = cur.copy()
        n[1:] &= cur[:-1]
        n[:-1] &= cur[1:]
        n[:, 1:] &= cur[:, :-1]
        n[:, :-1] &= cur[:, 1:]
        if i % 2:                                                       # diagonals every other step
            n[1:, 1:] &= cur[:-1, :-1]
            n[1:, :-1] &= cur[:-1, 1:]
            n[:-1, 1:] &= cur[1:, :-1]
            n[:-1, :-1] &= cur[1:, 1:]
        cur = n
        d += cur
    return d


def shade(np, mask8, bevel_px, rng, top=TAN_TOP, bottom=TAN_BOTTOM, hot=0.0):
    """Lit, bevelled, brushed letters. Returns (rgb float 0..255 premultiplied by coverage,
    coverage 0..1)."""
    alpha = box_down(np, mask8.astype(float))
    steps = bevel_px * S
    d8 = erosion_distance(np, mask8, steps)
    height = box_down(np, np.minimum(d8, steps) / float(steps))
    rim = box_down(np, np.minimum(d8, S) / float(S))                    # 0 at the edge, 1 inside
    gy, gx = np.gradient(height)
    k = bevel_px * 1.6
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(height)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / norm, ny / norm, nz / norm
    lx, ly, lz = LIGHT
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    ndl = np.clip((nx * lx + ny * ly + nz * lz) / ln, 0, 1)
    h, w = alpha.shape
    rows = np.nonzero(alpha.any(1))[0]
    y0, y1 = (rows.min(), rows.max()) if len(rows) else (0, h - 1)
    t = np.clip((np.arange(h) - y0) / max(1, y1 - y0), 0, 1)[:, None]
    base = (1 - t) * np.array(top)[None, :] + t * np.array(bottom)[None, :]
    base = np.repeat(base[:, None, :], w, 1)
    streak = rng.normal(0, 1, (h, w))
    kern = 9
    streak = np.cumsum(np.pad(streak, ((0, 0), (kern, 0))), 1)
    streak = (streak[:, kern:] - streak[:, :-kern]) / kern
    grain = rng.normal(0, 1, (h, w))
    tex = 1.0 + 0.07 * streak + 0.03 * grain
    diffuse = 0.42 + 0.72 * ndl
    spec = (ndl ** 14) * (0.42 + hot)
    rgb = base * (diffuse * tex)[:, :, None] + spec[:, :, None] * np.array(SPEC)[None, None, :]
    rgb *= (0.30 + 0.70 * rim)[:, :, None]                              # dark rim
    if hot:
        rgb += hot * 110 * (ndl ** 3)[:, :, None]
    return np.clip(rgb, 0, 255) * alpha[:, :, None], alpha


def metal_indices(np, palette):
    """Tans, browns and greys: r >= g >= b, never index 0."""
    pal = np.array(palette).reshape(256, 3).astype(int)
    r, g, b = pal[:, 0], pal[:, 1], pal[:, 2]
    ok = (r >= g) & (g >= b) & (r > 0)
    ok[0] = False
    return np.nonzero(ok)[0]


def quantise(np, rgb, alpha, palette, rng, indices, dither=3.0):
    pal = np.array(palette).reshape(256, 3).astype(float)
    cand = pal[indices]
    src = rgb + rng.uniform(-dither, dither, rgb.shape)
    flat = src.reshape(-1, 1, 3)
    d = ((flat - cand[None, :, :]) ** 2).sum(-1)
    out = indices[d.argmin(1)].reshape(alpha.shape).astype(np.uint8)
    out[alpha < 0.5] = 0
    return out


def tint(np, rgb, colour, strength=1.0):
    lum = rgb.mean(-1, keepdims=True) / 255.0
    return lum * np.array(colour)[None, None, :] * strength


# ------------------------------------------------------------------ frames
def title_frames(np, mask8, palette, rng):
    idx = metal_indices(np, palette)
    pal = np.array(palette).reshape(256, 3).astype(int)
    r, g, b = pal[:, 0], pal[:, 1], pal[:, 2]
    reds = np.nonzero((r > 0) & (g <= r * 0.7) & (b <= r * 0.7))[0]      # for the red frames
    reds = reds[reds != 0]
    final_rgb, alpha = shade(np, mask8, 2, rng)
    hot_rgb, _ = shade(np, mask8, 2, np.random.default_rng(1), hot=0.5)
    cells = [np.full((TITLE_H, TITLE_W), FLASH_TITLE, np.uint8)]
    dark = tint(np, final_rgb, (140, 10, 20), 0.9)
    cells.append(quantise(np, dark, alpha, palette, rng, reds, dither=1.0))
    Image, _, _, ImageFilter = need_pil()
    halo = np.array(Image.fromarray((alpha * 255).astype(np.uint8))
                    .filter(ImageFilter.GaussianBlur(2.5))) / 255.0
    glow = np.clip(tint(np, final_rgb, (255, 230, 220), 1.15)
                   + halo[:, :, None] * np.array([200, 30, 30])[None, None, :]
                   * (1 - alpha)[:, :, None], 0, 255)
    galpha = np.maximum(alpha, (halo > 0.12).astype(float))
    cells.append(quantise(np, glow, galpha, palette, rng,
                          np.concatenate([reds, idx, np.array([1, 255])]), dither=1.0))
    cells.append(quantise(np, hot_rgb, alpha, palette, rng, idx))
    cells.append(quantise(np, final_rgb, alpha, palette, rng, idx))
    return cells


# ------------------------------------------------------------------ files
def master_palette(game_dir):
    Image = need_pil()[0]
    gif = find_ci(game_dir, 'PALETTE.GIF')
    if not gif:
        raise SystemExit('%s: no PALETTE.GIF' % game_dir)
    with Image.open(gif) as im:
        return im.getpalette()


def write_bank(game_dir, name, cells, palette):
    pal = [tuple(palette[i * 3:i * 3 + 3]) for i in range(256)]
    spr_cells = [dict(w=c.shape[1], h=c.shape[0], ox=0, oy=0, px=bytearray(c.tobytes()))
                 for c in cells]
    written = []
    for d in SPRITE_DIRS:
        folder = find_ci(game_dir, d)
        path = find_ci(folder, name + '.SPR') if folder else None
        if not path:
            continue
        if not os.path.exists(path + '.bak'):
            shutil.copy2(path, path + '.bak')
        write_spr(path, 0x81, spr_cells, pal)
        written.append(os.path.relpath(path, game_dir))
    return written


def cmd_apply(args):
    np = need_np()
    palette = master_palette(args.dir)
    title = title_frames(np, title_mask8(np), palette, np.random.default_rng(args.seed + 2))
    for p in write_bank(args.dir, 'DCUT', title, palette):
        print('wrote %-24s %d cells %dx%d (title, %s)' % (p, len(title), TITLE_W, TITLE_H,
                                                            os.path.basename(find_font())))


def cmd_preview(args):
    np = need_np()
    Image = need_pil()[0]
    idir = intrface_dir(args.dir)
    with Image.open(find_ci(idir, 'INTRG.GIF')) as im:
        pal = np.array(im.getpalette(), np.uint8).reshape(256, 3)
        canvas = im.convert('RGB')
    data = open(find_ci(idir, 'bintroe'), 'rb').read()
    sprites = find_ci(args.dir, 'SPRITES')
    for kind, n, x, y, w, h, rest in parse_widgets(data):
        if kind == b'gadget' and rest and rest[0] in (b'DCUK', b'DCUT'):
            s = read_spr(find_ci(sprites, rest[0].decode() + '.SPR'))
            c = s['cells'][-1]
            px = np.frombuffer(bytes(c['px']), np.uint8).reshape(c['h'], c['w'])
            canvas.paste(Image.fromarray(pal[px], 'RGB'), (x, y))
    canvas.save(args.out)
    print('wrote %s' % args.out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='command', required=True)
    a = sub.add_parser('apply')
    a.add_argument('dir')
    a.add_argument('--seed', type=int, default=3)
    p = sub.add_parser('preview')
    p.add_argument('dir')
    p.add_argument('out')
    args = ap.parse_args(argv)
    return {'apply': cmd_apply, 'preview': cmd_preview}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
