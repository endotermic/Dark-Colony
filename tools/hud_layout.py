#!/usr/bin/env python3
"""Scaffolding for redrawing Dark Colony's in-game HUD at a larger resolution.

The HUD is three files (docs/DC16_DISPLAY_AND_RESOLUTION.md section 6.1): the layout script
INTRFACE/MAINE, the frame artwork INTRFACE/INTRFACE.GIF, and the widget cells INTRFACE/MAINBUT.SPR.
Only the frame has to be redrawn -- the cells are reused unchanged -- and the script transform is
mechanical. This tool does everything except the drawing:

    spec       what the frame's regions are, where they move to, and which can be tiled
    extract    cut the frame into per-region layers, plus tracing masks (section 10 stage 5 step 1)
    template   a target-resolution guide PNG to paint into
    maine      shift the MAINE widgets to match (plan / apply / revert)

Why the frame and not just padding: padding INTRFACE.GIF would keep the map viewport at its old
512x448. The whole point of the exercise is a bigger battlefield, so the frame's transparent hole
has to grow to 896x736, which means real artwork.

The frame is 8.9% opaque; palette index 254 (black) is the erase colour that shows the map view
through. Keep it exactly 254 in anything you draw, with no anti-aliasing at the hole boundary, or
a halo appears along the edge of the map (section 10 stage 5 step 1).
"""

import argparse
import collections
import os
import re
import shutil
import sys

# ---------------------------------------------------------------- geometry
# Measured from INTRFACE.GIF and cross-checked against the code constants (section 5).
SRC_W, SRC_H = 640, 480
INSET_X, INSET_Y = 4, 6            # map view origin
VIEW_W, VIEW_H = 512, 448          # map view size at 640x480
PANEL_X = 516                      # right panel starts here (= INSET_X + VIEW_W)
BOTTOM_Y = 454                     # bottom bar starts here (= INSET_Y + VIEW_H)
ERASE = 254                        # palette index that reads as transparent
MSG_Y = 420                        # widgets at or below this are bottom-bar furniture

# Each region records where it is, what it is anchored to (so we know whether it slides when the
# screen grows), which way it has to stretch, and what the tileability measurement showed.
#   anchor 'tl' stays at the top left, 'r' slides right by dx, 'b' slides down by dy
# `insert` is where `build` splices the extra rows/columns in. Each was picked so that the art on
# both sides of the splice stays aligned with the widgets that sit on it:
#   right_panel  399 -- the panel's bottom cluster (status box 399..415, BUILD 416..432, DAYS,
#                       money dial 445..472) starts with a full-width bar at row 399; above it,
#                       rows 94..398 are only the side rail. Splicing here keeps the minimap, the
#                       tabs and the button grid at the top and the cluster on the bottom edge,
#                       as in the original. (The first build spliced at 450, below BUILD, which
#                       left the Build button mid-screen -- rejected in the second visual test.)
#   left_border  450 -- so the corner detail still meets the bottom bar
#   map_edge     400 -- inside the constant stretch y=94..399
#   top_border   515 -- at the map's right edge, so the panel's top decoration stays on the right
#   bottom_bar   520 -- right of in_text #200 at x=480, the rightmost bottom-bar widget
REGIONS = [
    dict(name='left_border', box=(0, 0, INSET_X, SRC_H), anchor='tl', grows='height',
         insert=450, note='detail, only ~78 px periodic: pick a repeat segment or draw'),
    dict(name='top_border', box=(0, 0, SRC_W, INSET_Y), anchor='tl', grows='width',
         insert=515, note='detail, only ~77 px periodic: pick a repeat segment or draw'),
    dict(name='map_edge', box=(INSET_X + VIEW_W - 1, 0, 3, SRC_H), anchor='r', grows='height',
         insert=400, note='constant over y=94..399: tile a single column, free'),
    dict(name='right_panel', box=(PANEL_X, 0, SRC_W - PANEL_X, SRC_H), anchor='r',
         grows='height', insert=399,
         note='287 rows carry only 6 px of side rail: tile that row, free'),
    dict(name='bottom_bar', box=(0, BOTTOM_Y, SRC_W, SRC_H - BOTTOM_Y), anchor='b',
         grows='width', insert=520,
         note='no period beyond ~49 px: this one needs new artwork'),
]

# Every positioned widget kind MAINE uses. `count` is the build/troop/upgrade button with a
# price counter (80 of them, the whole build panel) and `scount` the money counter; both were
# missing from the first version of this list, so the first 1024x768 test build had every
# build button left at x=518/577 -- under the map view, where the terrain paints over them.
KINDS = ('pushb', 'checkb', 'in_text', 'picture', 'list', 'scroll', 'gadget', 'count', 'scount')
PANEL_INSERT = 399                 # right-panel widgets from here down travel with the bottom bar
SIZE2 = re.compile(rb'^([ \t]*)size([ \t]+)(\d+)([ \t]+)(\d+)([ \t]*\r?)$', re.M)


def need_pil():
    try:
        from PIL import Image, ImageDraw
        return Image, ImageDraw
    except ImportError:
        sys.exit('this tool needs Pillow: pip install Pillow')


def target(width, height):
    """Where each region lands, and how much it has to grow."""
    dx, dy = width - SRC_W, height - SRC_H
    out = []
    for r in REGIONS:
        x, y, w, h = r['box']
        tx = x + dx if r['anchor'] == 'r' else x
        ty = y + dy if r['anchor'] == 'b' else y
        tw = w + dx if r['grows'] == 'width' else w
        th = h + dy if r['grows'] == 'height' else h
        out.append(dict(name=r['name'], src=r['box'], dst=(tx, ty, tw, th),
                        grows=r['grows'], add=dx if r['grows'] == 'width' else dy,
                        note=r['note']))
    return out, dx, dy


def cmd_spec(args):
    regions, dx, dy = target(args.width, args.height)
    print('frame  %dx%d  ->  %dx%d      (+%d px wide, +%d px tall)\n'
          % (SRC_W, SRC_H, args.width, args.height, dx, dy))
    print('map viewport  %dx%d at (%d,%d)  ->  %dx%d at (%d,%d)   = %dx%d tiles\n'
          % (VIEW_W, VIEW_H, INSET_X, INSET_Y, VIEW_W + dx, VIEW_H + dy, INSET_X, INSET_Y,
             (VIEW_W + dx) // 32, (VIEW_H + dy) // 32))
    print('  %-13s %-22s %-22s %s' % ('region', 'source', 'target', 'extension'))
    print('  ' + '-' * 96)
    for r in regions:
        x, y, w, h = r['src']
        tx, ty, tw, th = r['dst']
        print('  %-13s (%4d,%4d) %4dx%-4d (%4d,%4d) %4dx%-4d +%d px %s: %s'
              % (r['name'], x, y, w, h, tx, ty, tw, th, r['add'], r['grows'], r['note']))
    print('\n  erase colour: palette index %d, no anti-aliasing at the hole boundary' % ERASE)


def used_indices(im):
    px = im.load()
    w, h = im.size
    hist = {}
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            if v != ERASE:
                hist[v] = hist.get(v, 0) + 1
    return hist


def cmd_extract(args):
    Image, _ = need_pil()
    src = os.path.join(args.dir, 'INTRFACE.GIF')
    if not os.path.exists(src):
        sys.exit('%s not found' % src)
    os.makedirs(args.out, exist_ok=True)
    im = Image.open(src)
    if im.size != (SRC_W, SRC_H):
        sys.exit('%s is %dx%d, expected %dx%d -- already modified?'
                 % (src, im.size[0], im.size[1], SRC_W, SRC_H))
    pal = im.getpalette()
    px = im.load()

    # a reference render with the transparent area made obvious
    ref = Image.new('RGB', im.size)
    rp = ref.load()
    for y in range(SRC_H):
        for x in range(SRC_W):
            v = px[x, y]
            rp[x, y] = ((40, 0, 40) if (x // 8 + y // 8) % 2 else (25, 0, 25)) \
                if v == ERASE else tuple(pal[v * 3:v * 3 + 3])
    ref.save(os.path.join(args.out, 'reference.png'))

    # one layer per region, at native size, transparency preserved as index 254
    for r in REGIONS:
        x, y, w, h = r['box']
        im.crop((x, y, x + w, y + h)).save(
            os.path.join(args.out, 'region_%s.gif' % r['name']))

    # structural vs texture split: runs of >= 4 px are the traceable half (section 10 stage 5)
    struct = Image.new('1', im.size, 0)
    tex = Image.new('1', im.size, 0)
    sp, tp = struct.load(), tex.load()
    for y in range(SRC_H):
        x = 0
        while x < SRC_W:
            if px[x, y] == ERASE:
                x += 1
                continue
            v = px[x, y]
            n = 0
            while x + n < SRC_W and px[x + n, y] == v:
                n += 1
            dst = sp if n >= 4 else tp
            for i in range(n):
                dst[x + i, y] = 1
            x += n
    struct.save(os.path.join(args.out, 'structural.png'))
    tex.save(os.path.join(args.out, 'texture.png'))

    # per-index bilevel masks for plane-by-plane tracing
    masks = os.path.join(args.out, 'masks')
    os.makedirs(masks, exist_ok=True)
    hist = used_indices(im)
    for v, n in sorted(hist.items(), key=lambda kv: -kv[1]):
        m = Image.new('1', im.size, 0)
        mp = m.load()
        for y in range(SRC_H):
            for x in range(SRC_W):
                if px[x, y] == v:
                    mp[x, y] = 1
        m.save(os.path.join(masks, 'idx%03d_%06dpx.png' % (v, n)))

    with open(os.path.join(args.out, 'palette.txt'), 'w') as f:
        f.write('# index  r   g   b   opaque pixel count\n')
        for i in range(256):
            r, g, b = pal[i * 3:i * 3 + 3]
            f.write('%5d %4d %4d %4d %8d%s\n'
                    % (i, r, g, b, hist.get(i, 0), '   <- erase' if i == ERASE else ''))

    total = sum(hist.values())
    print('wrote %s' % args.out)
    print('  reference.png        the frame on a checkerboard, so the hole is visible')
    print('  region_*.gif         %d layers at native size, index %d kept as the hole'
          % (len(REGIONS), ERASE))
    print('  structural.png       runs >= 4 px: the part worth tracing')
    print('  texture.png          single-pixel detail and dither: treat as texture')
    print('  masks/idx*.png       %d bilevel planes for potrace, largest first' % len(hist))
    print('  palette.txt          the 256 entries with opaque pixel counts')
    print('  %d opaque pixels of %d (%.1f%%), %d distinct indices'
          % (total, SRC_W * SRC_H, 100.0 * total / (SRC_W * SRC_H), len(hist)))


def cmd_template(args):
    Image, ImageDraw = need_pil()
    regions, dx, dy = target(args.width, args.height)
    im = Image.new('RGB', (args.width, args.height), (18, 18, 22))
    d = ImageDraw.Draw(im)

    hx, hy = INSET_X, INSET_Y
    hw, hh = VIEW_W + dx, VIEW_H + dy
    d.rectangle([hx, hy, hx + hw - 1, hy + hh - 1], fill=(0, 0, 0), outline=(0, 200, 0))
    d.text((hx + 6, hy + 6), 'MAP VIEWPORT  %dx%d  = %d x %d tiles of 32 px'
           % (hw, hh, hw // 32, hh // 32), fill=(0, 220, 0))
    d.text((hx + 6, hy + 18), 'must be palette index %d (erase), hard edge, no AA' % ERASE,
           fill=(0, 160, 0))

    # Shade the part of each region that has no source pixels behind it: that is the new art.
    for r in regions:
        tx, ty, tw, th = r['dst']
        sx, sy, sw, sh = r['src']
        if r['grows'] == 'height':
            new = (tx, ty + sh, tw, th - sh)
        else:
            new = (tx + sw, ty, tw - sw, th)
        if new[2] > 0 and new[3] > 0:
            # hatch inside its own tile so the strokes cannot bleed outside the region
            patch = Image.new('RGB', (new[2], new[3]), (26, 22, 14))
            pd = ImageDraw.Draw(patch)
            for i in range(0, new[2] + new[3], 8):
                pd.line([(i, 0), (i - new[3], new[3])], fill=(90, 70, 30))
            im.paste(patch, (new[0], new[1]))
            d.rectangle([new[0], new[1], new[0] + new[2] - 1, new[1] + new[3] - 1],
                        outline=(210, 160, 40))
        d.rectangle([tx, ty, tx + tw - 1, ty + th - 1], outline=(200, 60, 60))
        d.text((min(tx + 3, args.width - 90), min(ty + th + 2, args.height - 12)),
               r['name'], fill=(240, 120, 120))

    # MAINE widgets at their new positions
    maine = os.path.join(args.dir, 'MAINE')
    n = 0
    if os.path.exists(maine):
        for kind, num, x, y, w, h in parse_widgets(open(maine, 'rb').read()):
            nx, ny = shift(x, y, dx, dy)
            d.rectangle([nx, ny, nx + max(w, 1) - 1, ny + max(h, 1) - 1], outline=(70, 110, 210))
            n += 1

    # legend, parked in the middle of the map area where there is room
    lx, ly = INSET_X + 24, INSET_Y + 60
    d.rectangle([lx - 8, ly - 8, lx + 640, ly + 20 + 14 * len(regions)], fill=(10, 10, 14),
                outline=(60, 60, 70))
    d.text((lx, ly), 'target %dx%d      red = frame region      hatched = new art needed'
           '      blue = %d MAINE widgets' % (args.width, args.height, n), fill=(170, 170, 180))
    for i, r in enumerate(regions):
        tx, ty, tw, th = r['dst']
        d.text((lx, ly + 20 + 14 * i),
               '%-12s (%4d,%4d) %4dx%-4d  +%3d px %-6s  %s'
               % (r['name'], tx, ty, tw, th, r['add'], r['grows'], r['note']),
               fill=(210, 160, 40) if 'needs new artwork' in r['note'] else (140, 140, 150))
    im.save(args.out)
    print('wrote %s  (%dx%d, %d widget boxes)' % (args.out, args.width, args.height, n))


def parse_widgets(data):
    """<kind> <number> <desc> <x> <y> <w> <h> ... -- see section 6.1."""
    out = []
    for line in data.split(b'\n'):
        toks = line.split(b'%')[0].strip().split()
        if len(toks) >= 7 and toks[0].decode(errors='replace') in KINDS:
            try:
                out.append((toks[0].decode(), int(toks[1]),
                            int(toks[3]), int(toks[4]), int(toks[5]), int(toks[6])))
            except ValueError:
                pass
    return out


def shift(x, y, dx, dy):
    """Right-panel widgets move sideways; bottom furniture moves down.

    The panel's bottom cluster does both: the status text (`in_text 79` at y 404), the Build
    button (`pushb 19`, 422), the days counter (`in_text 234`, 433) and the money counter
    (`scount 75`, 456) sit on art that `build` splices above (right_panel insert=399), so they
    follow it down as well as right and stay on the bottom edge of the screen.
    """
    if x >= PANEL_X:
        return x + dx, y + dy if y >= PANEL_INSERT else y
    if y >= MSG_Y:
        return x, y + dy
    return x, y


def _lines(px, w, h, vertical):
    """Rows (or columns) of an index buffer, as a list of bytes."""
    if vertical:
        return [bytes(px[y * w:(y + 1) * w]) for y in range(h)]
    return [bytes(px[y * w + x] for y in range(h)) for x in range(w)]


def _extend(px, w, h, grows, add, insert):
    """Splice `add` copies of the most common row/column in at `insert`."""
    vertical = grows == 'height'
    seq = _lines(px, w, h, vertical)
    filler = collections.Counter(seq).most_common(1)[0][0]
    insert = max(0, min(insert, len(seq)))
    seq = seq[:insert] + [filler] * add + seq[insert:]
    if vertical:
        return b''.join(seq), w, h + add
    nw, nh = w + add, h
    out = bytearray(nw * nh)
    for x, coldata in enumerate(seq):
        for y in range(nh):
            out[y * nw + x] = coldata[y]
    return bytes(out), nw, nh


def cmd_build(args):
    """Composite a target-size frame from the source regions, tiling where it can.

    This is a mechanical test build, not finished artwork. It gets a playable HUD on screen so the
    bigger battlefield can actually be used; the bottom bar in particular will show a visible
    repeat, because that region has no real period (see the `spec` output).
    """
    Image, _ = need_pil()
    src_path = os.path.join(args.dir, 'INTRFACE.GIF')
    im = Image.open(src_path)
    if im.size != (SRC_W, SRC_H):
        sys.exit('%s is %dx%d, expected %dx%d' % (src_path, im.size[0], im.size[1], SRC_W, SRC_H))
    pal = im.getpalette()
    src = im.tobytes()
    regions, dx, dy = target(args.width, args.height)
    by_name = {r['name']: r for r in regions}

    canvas = bytearray([ERASE]) * (args.width * args.height)
    for r in REGIONS:
        x, y, w, h = r['box']
        sub = bytearray()
        for row in range(h):
            sub += src[(y + row) * SRC_W + x:(y + row) * SRC_W + x + w]
        t = by_name[r['name']]
        data, nw, nh = _extend(sub, w, h, r['grows'], t['add'], r['insert'])
        tx, ty, _, _ = t['dst']
        for row in range(nh):
            off = (ty + row) * args.width + tx
            canvas[off:off + nw] = data[row * nw:(row + 1) * nw]
        print('  %-12s %4dx%-4d -> %4dx%-4d  spliced %d at %s=%d'
              % (r['name'], w, h, nw, nh, t['add'],
                 'y' if r['grows'] == 'height' else 'x', r['insert']))

    out = Image.frombytes('P', (args.width, args.height), bytes(canvas))
    out.putpalette(pal)
    dst = args.out or src_path
    if dst == src_path and not os.path.exists(dst + '.bak'):
        shutil.copy2(dst, dst + '.bak')
    out.save(dst, format='GIF', version='GIF87a', interlace=False, optimize=False)

    opaque = sum(1 for v in canvas if v != ERASE)
    print('\nwrote %s  %dx%d, %d opaque px (%.1f%%)'
          % (dst, args.width, args.height, opaque,
             100.0 * opaque / (args.width * args.height)))
    print('the map hole is everything left at index %d: (%d,%d) %dx%d'
          % (ERASE, INSET_X, INSET_Y, VIEW_W + dx, VIEW_H + dy))
    print('NOTE: mechanical splice, not finished art. The bottom bar will show a visible repeat.')
    return 0


def cmd_maine(args):
    path = os.path.join(args.dir, 'MAINE')
    if args.action == 'revert':
        bak = path + '.bak'
        if not os.path.exists(bak):
            sys.exit('%s: nothing to revert' % bak)
        shutil.copy2(bak, path)
        os.remove(bak)
        print('restored MAINE')
        return 0

    dx, dy = args.width - SRC_W, args.height - SRC_H
    data = open(path, 'rb').read()
    if args.action == 'apply':
        if not os.path.exists(path + '.bak'):
            shutil.copy2(path, path + '.bak')
        data = open(path + '.bak', 'rb').read()      # always transform the pristine copy

    panel = bottom = left = 0
    out = []
    for line in data.split(b'\n'):
        body, sep, comment = line.partition(b'%')
        toks = re.findall(rb'\S+|[ \t]+', body)
        words = [t for t in toks if not t.isspace()]
        if words and words[0].decode(errors='replace') in KINDS \
                and len(words) >= 5 and re.fullmatch(rb'\d+', words[3]) \
                and re.fullmatch(rb'\d+', words[4]):
            x, y = int(words[3]), int(words[4])
            nx, ny = shift(x, y, dx, dy)
            if (nx, ny) != (x, y):
                if nx != x:
                    panel += 1
                if ny != y:
                    bottom += 1
                n = 0
                for i, t in enumerate(toks):
                    if t.isspace():
                        continue
                    n += 1
                    if n == 4:
                        toks[i] = b'%d' % nx
                    elif n == 5:
                        toks[i] = b'%d' % ny
                        break
                body = b''.join(toks)
            else:
                left += 1
                if args.action == 'plan':
                    print('  left alone: %-8s #%-4s at (%d,%d)'
                          % (words[0].decode(), words[1].decode(), x, y))
        out.append(body + sep + comment)
    data = b'\n'.join(out)

    m = SIZE2.search(data)
    if m:
        data = (data[:m.start()]
                + b'%ssize%s%d %d%s' % (m.group(1), m.group(2), args.width, args.height,
                                        m.group(6))
                + data[m.end():])

    print('  size %d %d -> size %d %d' % (SRC_W, SRC_H, args.width, args.height))
    print('  %d right-panel widget(s) x += %d' % (panel, dx))
    print('  %d bottom-row widget(s)  y += %d  (the panel\'s bottom cluster is in both)'
          % (bottom, dy))
    print('  %d widget(s) left where they are (inside the map view)' % left)
    if args.action == 'plan':
        print('\nplan only, nothing written.')
        return 0
    open(path, 'wb').write(data)
    print('\nwrote MAINE (original kept as MAINE.bak)')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('spec', 'extract', 'template', 'build', 'maine'):
        p = sub.add_parser(name)
        p.add_argument('dir', help='an INTRFACE directory')
        p.add_argument('--width', type=int, default=1024)
        p.add_argument('--height', type=int, default=768)
        if name == 'extract':
            p.add_argument('--out', default='hud_layers')
        if name == 'template':
            p.add_argument('--out', default='hud_template.png')
        if name == 'build':
            p.add_argument('--out', default=None,
                           help='output GIF (default: overwrite INTRFACE.GIF, keeping a .bak)')
        if name == 'maine':
            p.add_argument('action', choices=('plan', 'apply', 'revert'))
    args = ap.parse_args(argv)
    if not os.path.isdir(args.dir):
        raise SystemExit('%s: not a directory' % args.dir)
    return {'spec': cmd_spec, 'extract': cmd_extract, 'template': cmd_template,
            'build': cmd_build, 'maine': cmd_maine}[args.cmd](args) or 0


if __name__ == '__main__':
    sys.exit(main())
