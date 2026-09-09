#!/usr/bin/env python3
"""Reader / writer for the Dark Colony .SPR sprite container.

Format reverse-engineered from Classic dc16.exe; see
docs/DC16_DISPLAY_AND_RESOLUTION.md section 6.3 for the derivation and the code addresses.

Verified against all 561 .SPR files in DC - Classic, DC - Council wars and the map editor:
every file parses byte-exact, and all 15088 compressed cells decode to exactly w*h pixels
while consuming exactly their declared stream length.

ANIMATE/*.FIN is a *different* container (loaded via "animate/%s") and is not handled here.

CLI
    python spr.py info    FILE.SPR
    python spr.py extract FILE.SPR OUTDIR          # one PNG per cell + cells.json
    python spr.py build   INDIR   OUT.SPR          # rebuild from cells.json + PNGs
    python spr.py check   FILE.SPR [FILE.SPR ...]  # parse + round-trip self-test
"""

import json
import os
import struct
import sys

# ---------------------------------------------------------------- file layout
#
#   0x000  u16  flags        bit 7 or 8 set (mask 0x180) => cells are RLE compressed
#                            observed values: 0x0001 (raw, 84 files), 0x0081 (RLE, 477 files)
#   0x002  u16  ncells
#   0x004  u32  datasize     size hint used only to size one allocation; see note below
#   0x008  768  palette      256 * (r,g,b), 6-bit VGA components (0..63)
#   0x308  8*n  directory    per cell: u16 width, u16 height, u16 xoffset, u16 yoffset
#   0x308+8n   cell bodies, in order:
#                raw  (flags & 0x180 == 0): width*height bytes, no length prefix
#                RLE  (flags & 0x180 != 0): u32 length, then that many bytes
#
# All integers are little-endian: the loader reads them with plain fread
# (0x00406A44 = fread(dst,2,1,f), 0x00406A5C = fread(dst,4,1,f)), no byte swapping.
#
# `datasize` is not the body size. For RLE files it is the sum of the per-cell stream
# lengths; for raw files the header value counts an extra 12 bytes per cell (the 8-byte
# directory entry plus a notional 4-byte length prefix that raw files do not store), which
# is why the loader does `datasize -= ncells*4` at 0x0044F88B and then over-allocates by
# ncells*24. Nothing depends on the value beyond that allocation, so writers can compute it
# as this module does.
#
# Palette index 0 is transparent in both blitters (0x0044FBEF and 0x0044FDA0).

HEADER = 8
PALETTE = 768
DIRECTORY = HEADER + PALETTE          # 776
ENTRY = 8


def _pal_from_file(raw):
    return [tuple(v << 2 | v >> 4 for v in raw[i * 3:i * 3 + 3]) for i in range(256)]


def _pal_to_file(palette):
    return bytes(b for r, g, bl in palette for b in (r >> 2, g >> 2, bl >> 2))


def decode_rle(raw, w, h):
    """Decode one RLE cell body to a w*h index buffer.

    Control byte c, read as signed:
        c >= 0  ->  the next c+1 bytes are literal palette indices
        c <  0  ->  skip -c pixels (leave them transparent)
    The cursor advances in row-major order and wraps at `w`, so a skip may cross rows.
    Mirrors the blitter's inner loop at 0x0044FD4F.

    Returns (pixels, bytes_consumed, error_or_None).
    """
    out = bytearray(w * h)
    p = 0
    i = 0
    n = w * h
    while i < n:
        if p >= len(raw):
            return out, p, 'stream exhausted at pixel %d of %d' % (i, n)
        c = raw[p]
        p += 1
        if c & 0x80:                       # negative -> transparent run
            i += 256 - c
        else:                              # literal run of c+1 pixels
            run = c + 1
            if p + run > len(raw):
                return out, p, 'literal run overruns stream'
            end = min(i + run, n)
            out[i:end] = raw[p:p + (end - i)]
            p += run
            i += run
    return out, p, None


def encode_rle(px, w, h):
    """Inverse of decode_rle.

    One linear stream with wrapping, so transparent runs may cross rows. Round-trips all
    15088 compressed cells in the shipped data, reproduces the original byte stream for
    55.2% of them, and is never larger (0.4% smaller in total).
    """
    out = bytearray()
    i = 0
    n = w * h
    while i < n:
        if px[i] == 0:
            run = 0
            while i + run < n and px[i + run] == 0 and run < 128:
                run += 1
            out.append((256 - run) & 0xFF)
        else:
            run = 0
            while i + run < n and px[i + run] != 0 and run < 128:
                run += 1
            out.append(run - 1)
            out += bytes(px[i:i + run])
        i += run
    return bytes(out)


def read_spr(path):
    """Parse a .SPR. Each cell gets w, h, ox, oy and px (a w*h index bytearray)."""
    d = open(path, 'rb').read()
    if len(d) < DIRECTORY:
        raise ValueError('%s: too short to be a .SPR' % path)
    flags, ncells = struct.unpack_from('<HH', d, 0)
    datasize, = struct.unpack_from('<I', d, 4)
    compressed = bool(flags & 0x180)
    palette = _pal_from_file(d[HEADER:HEADER + PALETTE])

    cells = []
    off = DIRECTORY + ncells * ENTRY
    for i in range(ncells):
        w, h, ox, oy = struct.unpack_from('<HHHH', d, DIRECTORY + i * ENTRY)
        if compressed:
            length, = struct.unpack_from('<I', d, off)
            off += 4
        else:
            length = w * h
        body = d[off:off + length]
        off += length
        if w and h:
            if compressed:
                px, used, err = decode_rle(body, w, h)
                if err:
                    raise ValueError('%s cell %d: %s' % (path, i, err))
                if used != length:
                    raise ValueError('%s cell %d: consumed %d of %d bytes'
                                     % (path, i, used, length))
            else:
                px = bytearray(body)
        else:
            px = bytearray()
        cells.append(dict(w=w, h=h, ox=ox, oy=oy, px=px))
    if off != len(d):
        raise ValueError('%s: %d trailing bytes' % (path, len(d) - off))
    return dict(flags=flags, datasize=datasize, compressed=compressed,
                palette=palette, cells=cells)


def write_spr(path, flags, cells, palette):
    """Write a .SPR. cells: dicts with w, h, ox, oy, px (len == w*h, index 0 transparent)."""
    compressed = bool(flags & 0x180)
    bodies = []
    for i, c in enumerate(cells):
        if not (c['w'] and c['h']):
            bodies.append(b'')
            continue
        if len(c['px']) != c['w'] * c['h']:
            raise ValueError('cell %d: px is %d bytes, expected %d'
                             % (i, len(c['px']), c['w'] * c['h']))
        bodies.append(encode_rle(c['px'], c['w'], c['h']) if compressed else bytes(c['px']))

    if compressed:
        datasize = sum(len(b) for b in bodies)
    else:
        datasize = sum(len(b) for b in bodies) + len(cells) * 12

    out = bytearray(struct.pack('<HHI', flags, len(cells), datasize))
    out += _pal_to_file(palette)
    for c in cells:
        out += struct.pack('<HHHH', c['w'], c['h'], c['ox'], c['oy'])
    for b in bodies:
        if compressed:
            out += struct.pack('<I', len(b))
        out += b
    open(path, 'wb').write(bytes(out))
    return len(out)


# ------------------------------------------------------------------------ CLI

def _need_pil():
    try:
        from PIL import Image
        return Image
    except ImportError:
        sys.exit('this command needs Pillow: pip install Pillow')


def cmd_info(path):
    s = read_spr(path)
    print('%s\n  flags 0x%04X (%s)  cells %d  datasize %d'
          % (path, s['flags'], 'RLE' if s['compressed'] else 'raw',
             len(s['cells']), s['datasize']))
    live = [c for c in s['cells'] if c['w'] and c['h']]
    if live:
        print('  w %d..%d  h %d..%d  ox %d..%d  oy %d..%d  (%d empty cells)'
              % (min(c['w'] for c in live), max(c['w'] for c in live),
                 min(c['h'] for c in live), max(c['h'] for c in live),
                 min(c['ox'] for c in live), max(c['ox'] for c in live),
                 min(c['oy'] for c in live), max(c['oy'] for c in live),
                 len(s['cells']) - len(live)))
    for i, c in enumerate(s['cells']):
        print('    %-4d %4dx%-4d ox=%-4d oy=%-4d' % (i, c['w'], c['h'], c['ox'], c['oy']))


def cmd_extract(path, outdir):
    Image = _need_pil()
    s = read_spr(path)
    os.makedirs(outdir, exist_ok=True)
    meta = dict(flags=s['flags'], palette=s['palette'], cells=[])
    for i, c in enumerate(s['cells']):
        entry = dict(w=c['w'], h=c['h'], ox=c['ox'], oy=c['oy'], png=None)
        if c['w'] and c['h']:
            im = Image.frombytes('P', (c['w'], c['h']), bytes(c['px']))
            im.putpalette([v for rgb in s['palette'] for v in rgb])
            im.info['transparency'] = 0
            entry['png'] = 'cell%04d.png' % i
            im.save(os.path.join(outdir, entry['png']))
        meta['cells'].append(entry)
    with open(os.path.join(outdir, 'cells.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('extracted %d cells to %s' % (len(s['cells']), outdir))


def cmd_build(indir, out):
    Image = _need_pil()
    meta = json.load(open(os.path.join(indir, 'cells.json')))
    cells = []
    for i, e in enumerate(meta['cells']):
        if e['png']:
            im = Image.open(os.path.join(indir, e['png'])).convert('P')
            if im.size != (e['w'], e['h']):
                sys.exit('cell %d: %s is %dx%d, cells.json says %dx%d — update both'
                         % (i, e['png'], im.size[0], im.size[1], e['w'], e['h']))
            px = bytearray(im.tobytes())
        else:
            px = bytearray()
        cells.append(dict(w=e['w'], h=e['h'], ox=e['ox'], oy=e['oy'], px=px))
    n = write_spr(out, meta['flags'], cells, [tuple(c) for c in meta['palette']])
    print('wrote %s (%d bytes, %d cells)' % (out, n, len(cells)))


def cmd_check(paths):
    bad = 0
    for p in paths:
        try:
            s = read_spr(p)
        except ValueError as e:
            print('FAIL parse  %s' % e)
            bad += 1
            continue
        errs = 0
        for i, c in enumerate(s['cells']):
            if not (c['w'] and c['h']):
                continue
            if s['compressed']:
                enc = encode_rle(c['px'], c['w'], c['h'])
                px2, _, err = decode_rle(enc, c['w'], c['h'])
                if err or bytes(px2) != bytes(c['px']):
                    print('FAIL rt     %s cell %d' % (p, i))
                    errs += 1
        if errs:
            bad += 1
        else:
            print('ok  %-52s %s %d cells' % (p, 'RLE' if s['compressed'] else 'raw',
                                             len(s['cells'])))
    print('\n%d ok, %d failed' % (len(paths) - bad, bad))
    return 1 if bad else 0


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd = argv[1]
    if cmd == 'info' and len(argv) == 3:
        cmd_info(argv[2])
    elif cmd == 'extract' and len(argv) == 4:
        cmd_extract(argv[2], argv[3])
    elif cmd == 'build' and len(argv) == 4:
        cmd_build(argv[2], argv[3])
    elif cmd == 'check' and len(argv) >= 3:
        return cmd_check(argv[2:])
    else:
        sys.exit(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
