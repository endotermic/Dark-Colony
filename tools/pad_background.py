#!/usr/bin/env python3
"""Letterbox Dark Colony's full-screen interface screens into a larger framebuffer.

Two facts from docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.1 make this necessary, and both
were confirmed by running the patched game:

1. The GIF blit in gifload.c writes W*H pixels *linearly* into the locked framebuffer with no
   row-stride advance (decoder 0x0044EB7C, output loop 0x0044ECC5), and takes no destination
   origin (esi = screen->pixels at 0x0044EB89). So a background is drawn correctly only when its
   width equals the framebuffer stride, and it always lands at (0,0). After patching to 1024x768
   a 640x480 background fills just the first 307200 pixels -- 300 rows of a 1024-wide screen --
   skewed.
2. `size X Y W H` declares the window's bounds rect, but widget x/y are **absolute screen
   coordinates** and are not offset by it. Verified: NEWGAMEE's `checkb 0` at (193,23) renders at
   (193,23) whatever the size line says, and the shipped four-argument scripts (LOPTE and friends)
   simply place their widgets at coordinates that already agree with their rect.

So letterboxing a screen is three coupled edits, which is why they live in one tool:

    a. repack the background GIF onto a W x H canvas with the original content centred;
    b. set the script's `size` to `X Y w h` so the bounds rect covers where the content now is;
    c. add the same (X, Y) to every positioned widget's x and y.

The result is a pixel-correct 640x480 screen letterboxed inside 1024x768, with no artwork and no
code patching. Repainting properly at the target size (vector-first) can follow later and just
replaces the padded file -- at which point the offsets in (b) and (c) go back to zero.

This is a stop-gap for *menus*. It is deliberately NOT applied to MAINE, the in-game HUD: padding
that would keep the map viewport at its old 512x448, which is the opposite of the point. MAINE
needs INTRFACE.GIF genuinely redrawn with a 896x736 hole.

Council Wars: run it on INTRFACE first and then on `exp/intrface`, the expansion's override
scripts (their GIFs are found in the base INTRFACE, already padded by the first run) and
`exp/gamestat`'s two scene files.

CLI
    python pad_background.py plan   INTRFACE_DIR [--width 1024 --height 768] [--only NAME]
    python pad_background.py apply  INTRFACE_DIR [--width 1024 --height 768] [--only NAME]
    python pad_background.py revert INTRFACE_DIR

`apply` writes a .bak beside every file it touches and never overwrites an existing one, so
`revert` always restores the pristine originals.
"""

import argparse
import os
import re
import shutil
import struct
import sys

SIZE2 = re.compile(rb'^([ \t]*)size([ \t]+)(\d+)([ \t]+)(\d+)([ \t]*\r?)$', re.M)
SIZE4 = re.compile(rb'^[ \t]*size[ \t]+\d+[ \t]+\d+[ \t]+\d+[ \t]+\d+', re.M)
BACKGROUND = re.compile(rb'^[ \t]*background[ \t]+(?:intrface/)?(\S+)', re.M | re.I)

# Widget kinds whose 4th and 5th fields are x and y: <kind> <number> <desc> <x> <y> <w> <h> ...
# `label` (static text: "Choose race", "Type in a name for your leader", "Rank", "ENTER SESSION
# NAME:") was missing from the first version, which left those four captions at their 640x480
# places; `count`/`scount` only occur in MAINE, listed for completeness.
POSITIONED = {b'pushb', b'checkb', b'in_text', b'picture', b'list', b'scroll', b'gadget',
              b'label', b'count', b'scount'}
# `group` lists member numbers, `textmsg` carries text, `banim` frame indices, `animation` and
# `text` file names; none has coordinates.

# The mission-selection screen marks the current mission on its globe with `intrface/epic`,
# whose position is data: the `frame x y` line of every mission block in these files
# (scenario.c 0x00429B67ff, sscanf "%d %d %d" -> gs+0x14D4/0x14E0/0x14DC; main.c 0x00403732
# then pic_create(x=gs+0x14E0, y=gs+0x14DC)). Doc 10.7. The x/y assignment is inferred.
SCENE_FILES = ('HSCENE.TXT', 'GSCENE.TXT', 'HTSCENE.TXT', 'GTSCENE.TXT',
               # Council Wars: the Aerogen and Council campaigns, in exp/gamestat
               'HXSCENE.TXT', 'GXSCENE.TXT')

# Council Wars (ENGEXP16.EXE) resolves every data path through a wrapper that tries `exp/<path>`
# before `<path>` (doc 10.10), so `exp/intrface` holds override *scripts* (bintroe, introe,
# shumane with the expansion's button layout) whose `background` GIFs still live in the base
# INTRFACE. When a script's GIF is not beside it, look in the game root's INTRFACE.
OVERRIDE_PARENT = 'exp'
FRAME_XY = re.compile(rb'^([ \t]*)(\d+)([ \t]+)(\d+)([ \t]+)(\d+)([ \t]*\r?)$')

HUD_SCRIPT = 'maine'

# The two loading screens are not interface scripts: driver.c loads INTRFACE/load.bmp (first
# start) or load2.bmp (later starts) with LoadImageA(..., W, H, LR_LOADFROMFILE |
# LR_CREATEDIBSECTION) at 0x0042EF07/0x0042EF38 and BitBlts W x H to (0,0) at 0x0042EFED..
# patch_resolution.py stage 2 sets W x H to the new screen size, so LoadImage would *stretch* the
# 640x480 art (which is not the original image) -- unless the file itself is padded to W x H
# with the picture centred, the same treatment as the GIF backgrounds. The BitBlt destination
# cannot be moved instead: it is two `push 0` imm8 bytes and 192 does not fit in a signed byte.
LOADING_BITMAPS = ('LOAD.BMP', 'LOAD2.BMP')


def need_pil():
    try:
        from PIL import Image
        return Image
    except ImportError:
        sys.exit('this tool needs Pillow: pip install Pillow')


def scan(intrface_dir, only=None, include_hud=False, width=1024, height=768):
    """Full-screen scripts that have a background. Returns (jobs, skipped)."""
    Image = need_pil()
    jobs, skipped = [], []
    for fn in sorted(os.listdir(intrface_dir), key=str.lower):
        path = os.path.join(intrface_dir, fn)
        if not os.path.isfile(path) or fn.lower().endswith('.bak'):
            continue
        # a screen repainted at the target size (paint_intro.py) already says `size W H` for
        # the framebuffer; leave it and its GIF alone even though a .bak exists
        cur = SIZE2.search(open(path, 'rb').read())
        if cur and (int(cur.group(3)), int(cur.group(5))) == (width, height):
            skipped.append((fn, 'already full-screen at %dx%d (repainted)' % (width, height)))
            continue
        # a script we padded earlier is judged by its pristine copy, so a re-run picks it up
        # again (apply always transforms from the .bak)
        src = path + '.bak' if os.path.exists(path + '.bak') else path
        data = open(src, 'rb').read()
        if SIZE4.search(data):
            continue                              # already positioned (sub-window dialog)
        if not SIZE2.search(data):
            continue
        bg = BACKGROUND.search(data)
        if not bg:
            skipped.append((fn, 'no background line'))
            continue
        if fn.lower() == HUD_SCRIPT and not include_hud:
            skipped.append((fn, 'in-game HUD, needs a real repaint (--include-hud to override)'))
            continue
        if only and fn.lower() != only.lower():
            continue
        gif = find_gif(intrface_dir, bg.group(1).decode())
        if not gif:
            skipped.append((fn, 'background %s has no .GIF' % bg.group(1).decode()))
            continue
        with Image.open(gif + '.bak' if os.path.exists(gif + '.bak') else gif) as im:
            gw, gh = im.size
        jobs.append((fn, gif, gw, gh))
    return jobs, skipped


def base_intrface_dir(intrface_dir):
    """For an `exp/intrface` override folder, the game root's INTRFACE; else None."""
    d = os.path.abspath(intrface_dir)
    parent = os.path.dirname(d)
    if os.path.basename(parent).lower() != OVERRIDE_PARENT:
        return None
    root = os.path.dirname(parent)
    names = {fn.lower(): fn for fn in os.listdir(root)}
    fn = names.get('intrface')
    return os.path.join(root, fn) if fn else None


def find_gif(intrface_dir, name):
    """The background GIF `name` (as written in the script) beside the scripts, or in the base
    INTRFACE when the scripts are `exp/` overrides. Case-insensitive; None if absent."""
    want = name.upper() + '.GIF'
    for d in (intrface_dir, base_intrface_dir(intrface_dir)):
        if not d:
            continue
        names = {fn.upper(): fn for fn in os.listdir(d)}
        if want in names:
            return os.path.join(d, names[want])
    return None


def gamestat_dir(intrface_dir):
    """The sibling GAMESTAT folder, if this INTRFACE sits inside a game directory."""
    parent = os.path.dirname(os.path.abspath(intrface_dir))
    names = {fn.lower(): fn for fn in os.listdir(parent)}
    fn = names.get('gamestat')
    return os.path.join(parent, fn) if fn else None


def scene_files(intrface_dir):
    gs = gamestat_dir(intrface_dir)
    if not gs:
        return []
    names = {fn.lower(): fn for fn in os.listdir(gs)}
    return [os.path.join(gs, names[w.lower()]) for w in SCENE_FILES if w.lower() in names]


def edit_scene(path, dx, dy, dry_run=False):
    """Add (dx, dy) to the `frame x y` line of every mission block: the line of three integers
    that follows the second .avi line. Returns the number of lines changed."""
    data = open(path, 'rb').read()
    out, changed, prev_avi = [], 0, False
    for ln in data.split(b'\n'):
        m = FRAME_XY.match(ln)
        if m and prev_avi:
            ln = b'%s%s%s%d%s%d%s' % (m.group(1), m.group(2), m.group(3),
                                      int(m.group(4)) + dx, m.group(5),
                                      int(m.group(6)) + dy, m.group(7))
            changed += 1
        prev_avi = ln.strip().lower().endswith(b'.avi')
        out.append(ln)
    if not dry_run:
        open(path, 'wb').write(b'\n'.join(out))
    return changed


def check_gif_layout(path):
    """The game's parser reads a 13-byte header, the global colour table, then expects an image
    descriptor immediately. An extension block in between would desynchronise it, so verify."""
    d = open(path, 'rb').read()
    if d[:6] not in (b'GIF87a', b'GIF89a'):
        return 'not a GIF'
    w, h, flags = struct.unpack_from('<HHB', d, 6)
    if not flags & 0x80:
        return 'no global colour table'
    if (2 << (flags & 7)) != 256:
        return 'colour table is %d entries, not 256' % (2 << (flags & 7))
    off = 13 + 768
    if d[off] != 0x2C:
        return ('byte after the colour table is 0x%02X, not an image descriptor (0x2C): an '
                'extension block is present and would desynchronise the game parser' % d[off])
    il, it, iw, ih, iflags = struct.unpack_from('<HHHHB', d, off + 1)
    if (il, it) != (0, 0):
        return 'image is at (%d,%d), not (0,0)' % (il, it)
    if (iw, ih) != (w, h):
        return 'image %dx%d does not fill the %dx%d logical screen' % (iw, ih, w, h)
    if iflags & 0x40:
        return 'image is interlaced'
    if iflags & 0x80:
        return 'image has a local colour table'
    return None


def pad_gif(src, dst, width, height):
    """Centre src on a width x height canvas, preserving the palette exactly."""
    Image = need_pil()
    with Image.open(src) as im:
        if im.mode != 'P':
            raise ValueError('%s is mode %s, expected P' % (src, im.mode))
        sw, sh = im.size
        palette = im.getpalette()
        version = im.info.get('version', b'GIF87a')
        if isinstance(version, bytes):
            version = version.decode()
        pad = next((i for i in range(256)
                    if tuple(palette[i * 3:i * 3 + 3]) == (0, 0, 0)), None)
        if pad is None:
            raise ValueError('%s has no black palette entry to pad with' % src)
        canvas = Image.new('P', (width, height), pad)
        canvas.putpalette(palette)
        canvas.paste(im, ((width - sw) // 2, (height - sh) // 2))
        canvas.save(dst, format='GIF', version=version, interlace=False, optimize=False)
    return sw, sh, pad


def find_bitmaps(intrface_dir):
    """(path, w, h) for each loading bitmap present, matched case-insensitively."""
    Image = need_pil()
    out = []
    names = {fn.lower(): fn for fn in os.listdir(intrface_dir)}
    for want in LOADING_BITMAPS:
        fn = names.get(want.lower())
        if fn and not fn.lower().endswith('.bak'):
            path = os.path.join(intrface_dir, fn)
            with Image.open(path) as im:
                out.append((path, im.size[0], im.size[1]))
    return out


def pad_bmp(src, dst, width, height):
    """Centre an 8-bit BMP on a width x height canvas, palette preserved, black border."""
    Image = need_pil()
    with Image.open(src) as im:
        if im.mode != 'P':
            raise ValueError('%s is mode %s, expected P (8-bit)' % (src, im.mode))
        sw, sh = im.size
        palette = im.getpalette()
        pad = next((i for i in range(256)
                    if tuple(palette[i * 3:i * 3 + 3]) == (0, 0, 0)), None)
        if pad is None:
            raise ValueError('%s has no black palette entry to pad with' % src)
        canvas = Image.new('P', (width, height), pad)
        canvas.putpalette(palette)
        canvas.paste(im, ((width - sw) // 2, (height - sh) // 2))
        canvas.save(dst, format='BMP')
    return sw, sh, pad


def edit_script(path, x, y, w, h, dry_run=False):
    """Set `size x y w h` and add (x, y) to every positioned widget's coordinates.

    Returns (size_before, size_after, widgets_moved, warnings).
    """
    data = open(path, 'rb').read()
    warnings = []
    out, moved = [], 0
    lines = data.split(b'\n')
    for ln in lines:
        body, sep, comment = ln.partition(b'%')
        toks = re.findall(rb'\S+|[ \t]+', body)
        words = [t for t in toks if not t.isspace()]
        if words and words[0].lower() in POSITIONED:
            if len(words) < 5:
                warnings.append('%r: positioned keyword with only %d fields, left alone'
                                % (body.strip().decode(errors='replace'), len(words)))
            else:
                n = 0
                for i, t in enumerate(toks):
                    if t.isspace():
                        continue
                    n += 1
                    if n in (4, 5) and re.fullmatch(rb'\d+', t):
                        toks[i] = b'%d' % (int(t) + (x if n == 4 else y))
                    elif n in (4, 5):
                        warnings.append('%r: field %d is %r, not a plain number'
                                        % (body.strip().decode(errors='replace'), n,
                                           t.decode(errors='replace')))
                    if n >= 5:
                        break
                moved += 1
                body = b''.join(toks)
        out.append(body + sep + comment)
    data = b'\n'.join(out)

    m = SIZE2.search(data)
    before = m.group(0).rstrip(b'\r\n').decode() if m else None
    after = None
    if m:
        new = b'%ssize%s%d %d %d %d%s' % (m.group(1), m.group(2), x, y, w, h, m.group(6))
        data = data[:m.start()] + new + data[m.end():]
        after = new.rstrip(b'\r\n').decode()
    if not dry_run:
        open(path, 'wb').write(data)
    return before, after, moved, warnings


def backup(path):
    bak = path + '.bak'
    if not os.path.exists(bak):
        shutil.copy2(path, bak)


def q(p):
    return '"%s"' % p if ' ' in p else p


def cmd_plan(args, jobs, skipped):
    from PIL import Image
    print('target framebuffer %d x %d\n' % (args.width, args.height))
    gifs = {}
    for script, gif, gw, gh in jobs:
        gifs.setdefault(gif, []).append((script, gw, gh))
    print('  %d script(s), %d distinct background GIF(s):\n' % (len(jobs), len(gifs)))
    for gif, entries in sorted(gifs.items()):
        with Image.open(gif + '.bak' if os.path.exists(gif + '.bak') else gif) as im:
            gw, gh = im.size
        dx, dy = (args.width - gw) // 2, (args.height - gh) // 2
        fits = gw <= args.width and gh <= args.height
        elsewhere = os.path.dirname(os.path.abspath(gif)) != os.path.abspath(args.dir)
        print('  %-26s %4dx%-4d -> %dx%d, content at (%d,%d)%s%s'
              % (os.path.basename(gif), gw, gh, args.width, args.height, dx, dy,
                 '' if fits else '   TOO LARGE, would be skipped',
                 '   (in the base INTRFACE)' if elsewhere else ''))
        for script, _, _ in entries:
            _, _, moved, warns = edit_script(os.path.join(args.dir, script), dx, dy, gw, gh,
                                             dry_run=True)
            print('        %-14s size -> %d %d %d %d, %d widget(s) shifted by (+%d,+%d)%s'
                  % (script, dx, dy, gw, gh, moved, dx, dy,
                     '   %d WARNING(S)' % len(warns) if warns else ''))
            for wtext in warns:
                print('            ! ' + wtext)
    bitmaps = find_bitmaps(args.dir)
    if bitmaps:
        print('\n  loading screens (LoadImageA/BitBlt, not scripts):')
        for path, bw, bh in bitmaps:
            print('  %-26s %4dx%-4d -> %dx%d, content at (%d,%d)'
                  % (os.path.basename(path), bw, bh, args.width, args.height,
                     (args.width - bw) // 2, (args.height - bh) // 2))
    scenes = scene_files(args.dir)
    if scenes:
        dx, dy = (args.width - 640) // 2, (args.height - 480) // 2
        print('\n  mission globe markers (%s/*SCENE.TXT `frame x y` lines):'
              % os.path.basename(os.path.dirname(scenes[0])))
        for path in scenes:
            src = path + '.bak' if os.path.exists(path + '.bak') else path
            print('  %-26s %d marker(s) +(%d,%d)'
                  % (os.path.basename(path), edit_scene(src, dx, dy, dry_run=True), dx, dy))
    if skipped:
        print('\n  not touched:')
        for fn, why in skipped:
            print('    %-14s %s' % (fn, why))
    print('\nplan only, nothing written.')
    return 0


def cmd_apply(args, jobs, skipped):
    done, problems = {}, []
    for script, gif, gw, gh in jobs:
        if gw > args.width or gh > args.height:
            problems.append('%s: %dx%d does not fit %dx%d'
                            % (os.path.basename(gif), gw, gh, args.width, args.height))
            continue
        if gif not in done:
            backup(gif)
            try:
                sw, sh, pad = pad_gif(gif + '.bak', gif, args.width, args.height)
            except ValueError as e:
                shutil.copy2(gif + '.bak', gif)
                problems.append(str(e))
                done[gif] = None
                continue
            bad = check_gif_layout(gif)
            if bad:
                shutil.copy2(gif + '.bak', gif)
                problems.append('%s: rewritten file rejected (%s); original restored'
                                % (os.path.basename(gif), bad))
                done[gif] = None
                continue
            done[gif] = (sw, sh)
            print('padded  %-24s %dx%d -> %dx%d, border index %d'
                  % (os.path.basename(gif), sw, sh, args.width, args.height, pad))
        if done[gif] is None:
            continue
        sw, sh = done[gif]
        dx, dy = (args.width - sw) // 2, (args.height - sh) // 2
        spath = os.path.join(args.dir, script)
        backup(spath)
        # always edit from the pristine copy, so re-running apply is idempotent rather than
        # shifting every widget a second time
        shutil.copy2(spath + '.bak', spath)
        before, after, moved, warns = edit_script(spath, dx, dy, sw, sh)
        print('script  %-24s %r -> %r, %d widget(s) +(%d,%d)'
              % (script, before, after, moved, dx, dy))
        for wtext in warns:
            print('        ! ' + wtext)
    for path, bw, bh in find_bitmaps(args.dir):
        if bw > args.width or bh > args.height:
            problems.append('%s: %dx%d does not fit %dx%d'
                            % (os.path.basename(path), bw, bh, args.width, args.height))
            continue
        if (bw, bh) == (args.width, args.height) and os.path.exists(path + '.bak'):
            continue                                  # already padded on an earlier run
        backup(path)
        try:
            sw, sh, pad = pad_bmp(path + '.bak', path, args.width, args.height)
        except ValueError as e:
            shutil.copy2(path + '.bak', path)
            problems.append(str(e))
            continue
        print('padded  %-24s %dx%d -> %dx%d, border index %d'
              % (os.path.basename(path), sw, sh, args.width, args.height, pad))
    dx, dy = (args.width - 640) // 2, (args.height - 480) // 2
    for path in scene_files(args.dir):
        backup(path)
        shutil.copy2(path + '.bak', path)             # transform the pristine copy
        n = edit_scene(path, dx, dy)
        print('markers %-24s %d `frame x y` line(s) +(%d,%d)'
              % (os.path.basename(path), n, dx, dy))
    if problems:
        print('\nproblems:')
        for p in problems:
            print('  ' + p)
        return 1
    print('\nrevert with:  python pad_background.py revert %s' % q(args.dir))
    return 0


def cmd_revert(args):
    n = 0
    dirs = [args.dir] + ([gamestat_dir(args.dir)] if gamestat_dir(args.dir) else [])
    for d in dirs:
        for fn in sorted(os.listdir(d)):
            if not fn.endswith('.bak'):
                continue
            if d != args.dir and fn.upper()[:-4] not in SCENE_FILES:
                continue                          # only our own files in GAMESTAT
            bak = os.path.join(d, fn)
            shutil.copy2(bak, bak[:-4])
            os.remove(bak)
            print('restored %s' % os.path.basename(bak[:-4]))
            n += 1
    print('%d file(s) restored' % n)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=('plan', 'apply', 'revert'))
    ap.add_argument('dir', help='an INTRFACE directory')
    ap.add_argument('--width', type=int, default=1024)
    ap.add_argument('--height', type=int, default=768)
    ap.add_argument('--only', help='act on one script only, e.g. NEWGAMEE')
    ap.add_argument('--include-hud', action='store_true',
                    help='also pad MAINE (almost certainly wrong: see the docstring)')
    args = ap.parse_args(argv)

    if not os.path.isdir(args.dir):
        raise SystemExit('%s: not a directory' % args.dir)
    if args.command == 'revert':
        return cmd_revert(args)

    jobs, skipped = scan(args.dir, args.only, args.include_hud, args.width, args.height)
    if not jobs and not (find_bitmaps(args.dir) and not args.only):
        raise SystemExit('nothing to do in %s%s'
                         % (args.dir, ' for --only %s' % args.only if args.only else ''))
    return (cmd_plan if args.command == 'plan' else cmd_apply)(args, jobs, skipped)


if __name__ == '__main__':
    sys.exit(main())
