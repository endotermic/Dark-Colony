#!/usr/bin/env python3
"""Raise the screen resolution of Dark Colony's dc16.exe / ENGEXP16.EXE.

Every site in the table below was read out of the disassembly and byte-verified in the shipped
binaries; see docs/DC16_DISPLAY_AND_RESOLUTION.md, which this table is the executable copy of
(section 8 for the inventory, section 9 for the target geometry, section 10 for the stages).

Nothing is written unless *every* site selected for the run still holds its expected bytes, so
running this against an already-patched or unknown build fails loudly instead of corrupting it.

CLI
    python patch_resolution.py verify EXE
    python patch_resolution.py plan   EXE --width 1024 --height 768 [--stage N]
    python patch_resolution.py apply  EXE --width 1024 --height 768 [--stage N]

Stages are cumulative and mirror the plan in the doc:
    1  display mode, framebuffer stride, clip rect          (game in the top-left corner)
    2  + full-screen chrome, mouse, cursor, loading screens (640x480 content, centred by data)
    3  + enlarged map viewport and relocated minimap, and the 31 hardcoded 512-byte row
         advances of draw_terrain's lightplane fill; when the view no longer fits
         draw_terrain's stack lightmap (17x16 tiles), its frame is grown and the PE
         header's stack reserve/commit raised
    4  + movie back-buffer clear                            (default)

Stages 5 and 6 of the plan are data and art only; nothing here touches them.
To revert, restore the .bak that `apply` writes.
"""

import argparse
import hashlib
import os
import shutil
import struct
import sys
import textwrap

# ------------------------------------------------------------------- builds
#
# The width and height globals are preceded in DGROUP by the dword pair (0x14F, 0x16E), whose
# four bytes are a unique signature in every binary tested -- stock and already patched alike,
# which is why the search must not include the dimension values themselves (doc section 3).
# The full stock sequence is ANCHOR_PREFIX + "80 02 00 00" + "E0 01 00 00".
ANCHOR_PREFIX = bytes.fromhex('4f016e01')

BUILDS = {
    'aa0a646b1234d1d9815a2b7480fd080b': ('Classic dc16.exe', 0),
    '50419d438427d31341057e9723724f66': ('Council Wars ENGEXP16.EXE', 0x60),
    # Council Wars dc16.exe (4180f6e9d01925b23eac0eb335e0b95e) is a different build: only the
    # DGROUP anchor transfers, so its AUTO offsets are deliberately absent. Patching it needs
    # the sites re-derived in Ghidra first.
}

# ENGEXP16 is Classic shifted by +0x60 in AUTO from about 0x6000 onward, and +0 below it.
# Verified for every site in the table; the mandatory expected-byte check is what makes
# relying on the rule safe rather than a guess.
SHIFT_THRESHOLD = 0x5000


def auto_offset(classic_off, shift):
    return classic_off + (shift if classic_off >= SHIFT_THRESHOLD else 0)


# ------------------------------------------------------------------ geometry
#
# The HUD chrome keeps its native pixel size, so all the new space goes to the map view.
# At 640x480 the layout is a 4 px left inset, a 6 px top inset, a 124 px right panel and a
# 26 px bottom bar, with the minimap 121 px in from the right edge.
INSET_X, INSET_Y = 4, 6
PANEL_W, BOTTOM_H = 124, 26
MINIMAP_W, MINIMAP_H = 96, 84
MINIMAP_RIGHT_GAP = 640 - 519
TILE = 32

# draw_terrain's stack lightmap (doc 10.4 / 10.5). A dword per half-tile, row stride a hardcoded
# 144 bytes = 36 half-tile columns. The array base is [ebp-0x1452], which is exactly esp after
# the prologue (mov ebp,esp; sub esp,0x14CC; sub ebp,0x7A), and it grows upward toward the
# function's own locals, the lowest of which is [ebp+0x2E].
#
# Loop 1 writes (even row, even col) for rows 0..2*ty+2 and cols 0..2*tx+2; loop 2 writes
# (odd row, odd col) from four loop-1 neighbours; loop 3 reads (odd row, odd col) only. Half the
# cells are never touched, and a row's columns beyond 36 alias exactly those unused cells of the
# next row (same byte, opposite parity) - so the 144-byte stride stays correct up to 34 tiles
# across and the only real limit is the room below the locals. The last write is
# (row 2*ty+2, col 2*tx+2), so the array needs 144*(2*ty+2) + 4*(2*tx+2) + 4 bytes; when that
# exceeds the stock room the frame is grown by LIGHTMAP delta and the ten disp32 bases move down.
LIGHTMAP_BASE = 0x1452
LIGHTMAP_ROOM = LIGHTMAP_BASE + 0x2E
LIGHTMAP_STRIDE = 144
LIGHTMAP_FRAME = 0x14CC
LIGHTMAP_MAX_TILES_X = 34          # 4 * (2*tx + 2) < 2 * 144: a double wrap would collide

# Watcom emits no stack probe, so a frame that jumps by several pages must land on stack that is
# already committed: the stock header commits only 64 KB and reserves 80000 bytes. Raise both.
STACK_RESERVE = (0x13880, 0x100000)
STACK_COMMIT = (0x10000, 0x40000)


class Geometry:
    def __init__(self, width, height, viewport=None):
        self.w, self.h = width, height
        self.shift = width.bit_length() - 1
        if 1 << self.shift != width:
            raise ValueError(
                'width must be a power of two. The three framebuffer strides are compiled as\n'
                '    (y*4 + y) << 7      [= y*640]\n'
                'and can only be rewritten without relocating code as\n'
                '    (y*4) << (log2(width) - 2).\n'
                'Use 1024, the documented target. 800 would need a real imul and code motion.')
        self.view_w = width - INSET_X - PANEL_W
        self.view_h = height - INSET_Y - BOTTOM_H
        if viewport:
            # Diagnostic override: shrink the map view below the maximum the screen allows, to
            # test whether a failure scales with the viewport (a fixed-size buffer) rather than
            # with the screen. The HUD frame will not match; that is fine for a crash test.
            vw, vh = viewport
            if vw > self.view_w or vh > self.view_h:
                raise ValueError('viewport %dx%d exceeds the %dx%d the screen allows'
                                 % (vw, vh, self.view_w, self.view_h))
            self.view_w, self.view_h = vw, vh
        for what, v in (('viewport width', self.view_w), ('viewport height', self.view_h)):
            if v <= 0:
                raise ValueError('%s comes out %d: the screen is too small for the HUD'
                                 % (what, v))
            if v % TILE:
                raise ValueError('%s comes out %d, not a multiple of the %d px tile size'
                                 % (what, v, TILE))
        self.tiles_x = self.view_w // TILE
        self.tiles_y = self.view_h // TILE
        if not 1 <= self.tiles_y <= 127:
            raise ValueError(
                'visible tile rows comes out %d; clip_view_to_map encodes that count a second '
                'time as a signed 8-bit lea displacement, so it has to fit in 1..127'
                % self.tiles_y)
        # draw_terrain 0x00453910 keeps a half-tile lightmap in its own stack frame (doc 10.4).
        # If the view does not fit the stock room, grow the frame (doc 10.5).
        if self.tiles_x > LIGHTMAP_MAX_TILES_X:
            raise ValueError(
                '%d tiles across: the draw_terrain lightmap rows (144 bytes) would wrap twice '
                'and collide; at most %d fit' % (self.tiles_x, LIGHTMAP_MAX_TILES_X))
        self.lm_cols = 2 * self.tiles_x + 3
        self.lm_rows = 2 * self.tiles_y + 3
        self.lightmap_bytes = (LIGHTMAP_STRIDE * (self.lm_rows - 1)
                               + 4 * (self.lm_cols - 1) + 4)
        over = self.lightmap_bytes - LIGHTMAP_ROOM
        self.lm_delta = -(-over // 16) * 16 if over > 0 else 0
        self.lightmap_patch = self.lm_delta > 0
        self.lm_frame = LIGHTMAP_FRAME + self.lm_delta
        self.warnings = []
        self.mask_bytes = self.view_w * self.view_h // 8
        # Half the viewport in world units: the camera is the centre of the view, and world
        # coordinates run 256 per tile, so half a viewport is tiles * 128.
        self.half_x = self.tiles_x * 128
        self.half_y = self.tiles_y * 128
        self.minimap_x = width - MINIMAP_RIGHT_GAP
        self.minimap_off = (INSET_Y * width + self.minimap_x) * 2

    def describe(self):
        return [
            'screen           %d x %d' % (self.w, self.h),
            'map viewport     %d x %d = %d x %d tiles, at (%d, %d)'
            % (self.view_w, self.view_h, self.tiles_x, self.tiles_y, INSET_X, INSET_Y),
            'occlusion mask   %d bytes (0x%X)' % (self.mask_bytes, self.mask_bytes),
            'minimap          %d x %d at (%d, %d), framebuffer byte offset 0x%X'
            % (MINIMAP_W, MINIMAP_H, self.minimap_x, INSET_Y, self.minimap_off),
            'framebuffer      stride %d px, %d px total, %d bytes per row'
            % (self.w, self.w * self.h, self.w * 2),
            'terrain lightmap %d x %d half-tiles, %d bytes of %d: %s'
            % (self.lm_cols, self.lm_rows, self.lightmap_bytes, LIGHTMAP_ROOM,
               'frame grown 0x%X -> 0x%X (+0x%X)' % (LIGHTMAP_FRAME, self.lm_frame,
                                                       self.lm_delta)
               if self.lightmap_patch else 'fits the stock frame, untouched'),
        ]


# --------------------------------------------------------------------- sites
#
# imm32 site: (stage, classic_off, expected_hex, imm_index, value_fn, description)
#             the little-endian dword at expected[imm_index:imm_index+4] is replaced
# raw site:   (stage, classic_off, expected_hex, None, bytes_fn, description)
#             bytes_fn must return a replacement of identical length

SITES = [
    # -- stage 1: display mode, surfaces, framebuffer stride, clip rect ----------------------
    (1, 0x2DC98, '68e0010000', 1, lambda g: g.h, 'SetDisplayMode 8-bit height'),
    (1, 0x2DCA2, '6880020000', 1, lambda g: g.w, 'SetDisplayMode 8-bit width'),
    (1, 0x2DD1C, '68e0010000', 1, lambda g: g.h, 'SetDisplayMode 16-bit height'),
    (1, 0x2DD26, '6880020000', 1, lambda g: g.w, 'SetDisplayMode 16-bit width'),
    (1, 0x2DE89, 'b880020000', 1, lambda g: g.w, 'offscreen surface width'),
    (1, 0x2DE8E, 'bae0010000', 1, lambda g: g.h, 'offscreen surface height'),
    (1, 0x2EBAD, '3d00b00400', 1, lambda g: g.w * g.h, 'clear_screen pixel count (a)'),
    (1, 0x2EBE2, '3d00b00400', 1, lambda g: g.w * g.h, 'clear_screen pixel count (b)'),
    (1, 0x2B747, 'bb80020000', 1, lambda g: g.w, 'driver.c clip rect width'),
    (1, 0x2B763, 'b9e0010000', 1, lambda g: g.h, 'driver.c clip rect height'),
    (1, 0x2B594, 'bb80020000', 1, lambda g: g.w, 'driver.c row advance (a)'),
    (1, 0x2B661, 'ba80020000', 1, lambda g: g.w, 'driver.c row advance (b)'),
    # the three strength-reduced strides: drop the "+ y", then shift one place further
    (1, 0x2B613, '01ca', None, lambda g: b'\x89\xd2',
     'driver.c y*640: neutralise add edx,ecx'),
    (1, 0x2B618, 'c1e207', None, lambda g: bytes((0xC1, 0xE2, g.shift - 2)),
     'driver.c y*640 -> y*W: shl edx'),
    (1, 0x357BD, '01c8', None, lambda g: b'\x89\xc0',
     'engmain.c y*640: neutralise add eax,ecx'),
    (1, 0x357C5, 'c1e007', None, lambda g: bytes((0xC1, 0xE0, g.shift - 2)),
     'engmain.c y*640 -> y*W: shl eax'),
    (1, 0x354B9, '01f8', None, lambda g: b'\x89\xc0',
     'engmain.c y*1280: neutralise add eax,edi'),
    (1, 0x354BE, 'c1e008', None, lambda g: bytes((0xC1, 0xE0, g.shift - 1)),
     'engmain.c y*1280 -> y*W*2: shl eax'),

    # -- stage 2: chrome, mouse, cursor, loading screens -------------------------------------
    (2, 0x004E5, 'bf7f020000', 1, lambda g: g.w - 1, 'main.c full-screen rect right'),
    (2, 0x004EA, 'b8df010000', 1, lambda g: g.h - 1, 'main.c full-screen rect bottom'),
    (2, 0x2DBC4, 'ba40010000', 1, lambda g: g.w // 2, 'initial mouse X (screen centre)'),
    (2, 0x2DBC9, 'b9f0000000', 1, lambda g: g.h // 2, 'initial mouse Y (screen centre)'),
    (2, 0x2D5D2, 'b880020000', 1, lambda g: g.w, 'cursor clip width (a)'),
    (2, 0x2D5FF, 'b880020000', 1, lambda g: g.w, 'cursor clip width (b)'),
    (2, 0x2D60E, 'b8e0010000', 1, lambda g: g.h, 'cursor clip height (a)'),
    (2, 0x2D619, 'b8e0010000', 1, lambda g: g.h, 'cursor clip height (b)'),
    (2, 0x50247, '81fe80020000', 2, lambda g: g.w, 'mouse clamp: compare X against width'),
    (2, 0x5024F, 'be7f020000', 1, lambda g: g.w - 1, 'mouse clamp: X maximum'),
    (2, 0x5025C, '81ffe0010000', 2, lambda g: g.h, 'mouse clamp: compare Y against height'),
    (2, 0x50264, 'bfdf010000', 1, lambda g: g.h - 1, 'mouse clamp: Y maximum'),
    (2, 0x50346, '3d7f020000', 1, lambda g: g.w - 1, 'DirectInput clamp: compare X'),
    (2, 0x5034D, 'c705c02753007f020000', 6, lambda g: g.w - 1,
     'DirectInput clamp: X maximum'),
    (2, 0x5036B, '81fedf010000', 2, lambda g: g.h - 1, 'DirectInput clamp: compare Y'),
    (2, 0x50373, 'c705c4275300df010000', 6, lambda g: g.h - 1,
     'DirectInput clamp: Y maximum'),
    (2, 0x2E307, '68e0010000', 1, lambda g: g.h, 'load.bmp LoadImageA height'),
    (2, 0x2E30C, '6880020000', 1, lambda g: g.w, 'load.bmp LoadImageA width'),
    (2, 0x2E338, '68e0010000', 1, lambda g: g.h, 'load2.bmp LoadImageA height'),
    (2, 0x2E33D, '6880020000', 1, lambda g: g.w, 'load2.bmp LoadImageA width'),
    (2, 0x2E3ED, '68e0010000', 1, lambda g: g.h, 'loading screen BitBlt height'),
    (2, 0x2E3F2, '6880020000', 1, lambda g: g.w, 'loading screen BitBlt width'),

    # -- stage 3: map viewport and minimap ---------------------------------------------------
    (3, 0x35346, 'ba00020000', 1, lambda g: g.view_w, 'viewport width'),
    (3, 0x35361, 'bbc0010000', 1, lambda g: g.view_h, 'viewport height'),
    (3, 0x3524F, 'bb10000000', 1, lambda g: g.tiles_x, 'visible tiles across'),
    (3, 0x35247, 'b90e000000', 1, lambda g: g.tiles_y, 'visible tiles down'),
    # clip_view_to_map builds the rect from the map's bottom edge as
    #   make_rect(view_tile_x, map_h - view_tile_y - tiles_down, tiles_across, tiles_down)
    # and that second use of tiles_down is an 8-bit lea displacement, invisible to any search
    # for the imm32 form. Leaving it at 14 while the height says 23 makes the rect overrun the
    # map by 9 rows, and the vision scan at 0x00439D5E then dereferences a row pointer from past
    # the end of the 256-entry table: access violation the moment a battle starts.
    (3, 0x3524C, '8d50f2', None,
     lambda g: bytes((0x8D, 0x50, (256 - g.tiles_y) & 0xFF)),
     'clip_view_to_map: lea edx,[eax-tiles_down]'),

    # The camera is expressed as the *centre* of the view, so half the viewport shows up in
    # world units (256 per tile) as 0x800 = 8 tiles across and 0x700 = 7 tiles down. Three
    # separate places use it, and the scroll clamp is one of them:
    #   0x0041EE66/6F  proto.c  camera bounds = [half, map_size - half]  <- THE clamp
    #   0x0040AB1C/2B  view origin = camera - half, for the fog/interface update
    #   0x0040B0BC/E0  view origin = camera - half, for the frame render
    # Leaving these at 8/7 while the viewport is 28x23 lets the camera travel 6 tiles too far
    # right and 4.5 too far down, so draw_terrain reads past the map: access violation at
    # 0x00453AD4/0x00453ADE the moment a battle starts.
    (3, 0x09F0A, '6a0e', None, lambda g: bytes((0x6A, g.tiles_y)),
     'interface update: push tiles_down (imm8)'),
    (3, 0x09F0C, 'b910000000', 1, lambda g: g.tiles_x,
     'interface update: tiles_across'),
    (3, 0x09F1C, '81eb00070000', 2, lambda g: g.half_y,
     'interface update: sub ebx,half_viewport_y'),
    (3, 0x09F2B, '81ea00080000', 2, lambda g: g.half_x,
     'interface update: sub edx,half_viewport_x'),
    (3, 0x0A4BC, '81ea00070000', 2, lambda g: g.half_y,
     'frame render: sub edx,half_viewport_y'),
    (3, 0x0A4E0, '81ea00080000', 2, lambda g: g.half_x,
     'frame render: sub edx,half_viewport_x'),
    (3, 0x1E266, 'b900080000', 1, lambda g: g.half_x,
     'scroll clamp: half_viewport_x'),
    (3, 0x1E26F, 'bb00070000', 1, lambda g: g.half_y,
     'scroll clamp: half_viewport_y'),
    (3, 0x35388, 'ba00700000', 1, lambda g: g.mask_bytes, 'occlusion mask size'),
    (3, 0x3539F, 'b880020000', 1, lambda g: g.w, 'render destination stride'),
    (3, 0x1E123, 'bb00020000', 1, lambda g: g.view_w, 'proto.c map view rect width'),
    (3, 0x1E11E, 'b9c0010000', 1, lambda g: g.view_h, 'proto.c map view rect height'),
    (3, 0x3949B, 'b880020000', 1, lambda g: g.w, 'minimap stride (a)'),
    (3, 0x3985B, 'ba80020000', 1, lambda g: g.w, 'minimap stride (b)'),
    (3, 0x394AF, '81c20e220000', 2, lambda g: g.minimap_off, 'minimap origin (a)'),
    (3, 0x39884, '8145f00e220000', 3, lambda g: g.minimap_off, 'minimap origin (b)'),

    # -- stage 4: movies ---------------------------------------------------------------------
    (4, 0x067F4, '3d80020000', 1, lambda g: g.w, 'movie back-buffer clear width'),
    (4, 0x0680B, '81fae0010000', 2, lambda g: g.h, 'movie back-buffer clear height'),
    (4, 0x06805, '81c100050000', 2, lambda g: g.w * 2,
     'movie back-buffer row pitch (bytes)'),
]


def _rebase(disp):
    """A lightmap disp32 moved down by the frame growth, as the unsigned dword to store."""
    return lambda g: (disp - g.lm_delta) & 0xFFFFFFFF


# Only applied when Geometry.lightmap_patch is set (the view does not fit the stock room).
# draw_terrain 0x00453910: the frame and the ten disp32 accesses to the array, at four column
# offsets from the base (-0x1456 = col-1, -0x1452 = col, -0x144E = col+1, -0x144A = col+2).
# All of them lie between 0x00453915 and 0x00453C5D; nothing after that touches the array, and
# no pointer to it ever leaves the frame. The epilogue is `lea esp,[ebp+7Ah]`, so it needs no
# edit. The x144 row-stride idioms are left alone on purpose (see LIGHTMAP_MAX_TILES_X). Doc 10.5.
LIGHTMAP_SITES = [
    (3, 0x52D15, '81eccc140000', 2, lambda g: g.lm_frame, 'draw_terrain: sub esp,frame'),
    (3, 0x52F20, '89b428b6ebffff', 3, _rebase(-0x144A), 'lightmap store, loop 1 (2r, 2c)'),
    (3, 0x52F7A, '8b842eaeebffff', 3, _rebase(-0x1452), 'lightmap read, loop 2 (r, c)'),
    (3, 0x52F81, '03842faeebffff', 3, _rebase(-0x1452), 'lightmap read, loop 2 (r+2, c)'),
    (3, 0x52F88, '03842eb6ebffff', 3, _rebase(-0x144A), 'lightmap read, loop 2 (r, c+2)'),
    (3, 0x52F91, '8b842fb6ebffff', 3, _rebase(-0x144A), 'lightmap read, loop 2 (r+2, c+2)'),
    (3, 0x52FB3, '89bc2bb2ebffff', 3, _rebase(-0x144E), 'lightmap store, loop 2 (r+1, c+1)'),
    (3, 0x53005, '8b8c2aaaebffff', 3, _rebase(-0x1456), 'lightmap read, loop 3 (2i+1, 2j+1)'),
    (3, 0x5302D, '8b8428aaebffff', 3, _rebase(-0x1456), 'lightmap read, loop 3 (2i+3, 2j+1)'),
    (3, 0x5303C, '8b942ab2ebffff', 3, _rebase(-0x144E), 'lightmap read, loop 3 (2i+1, 2j+3)'),
    (3, 0x5305D, '8b8428b2ebffff', 3, _rebase(-0x144E), 'lightmap read, loop 3 (2i+3, 2j+3)'),
]


# The second half of draw_terrain fills the per-pixel lightplane (view+0x1C, one byte per
# pixel, row stride = viewport width, kept in 0x0049931C) one 32x32 tile at a time: 32 rows of
# 8 dwords each, and between one row and the next the destination advances by a hardcoded
# 0x200 = 512 = the stock viewport width. Only the advance from one tile row to the next
# (0x004542E8) multiplies by 0x0049931C. With a wider view, rows 1..31 of every tile land on
# the wrong rows of the plane, so the battlefield is covered in a repeating pattern of unlit
# (black) lines. 30 x `add eax,200h` plus the final `lea edi,[eax+200h]` (doc 10.6).
AUTO_VA_TO_FILE = 0x400C00
LIGHTPLANE_ROW_ADVANCE_VAS = [
    0x453CCB, 0x453CF2, 0x453D15, 0x453D62, 0x453D8E, 0x453DC9, 0x453DFC, 0x453E26,
    0x453E58, 0x453E93, 0x453EC6, 0x453EF9, 0x453F24, 0x453F61, 0x453F94, 0x453FC7,
    0x453FFA, 0x45402D, 0x454057, 0x454092, 0x4540B4, 0x4540F6, 0x454129, 0x454145,
    0x45418F, 0x4541C2, 0x4541F5, 0x454228, 0x45425B, 0x454276,
]
SITES += [
    (3, va - AUTO_VA_TO_FILE, '0500020000', 1, lambda g: g.view_w,
     'lightplane row advance %d/32 (add eax)' % (i + 1))
    for i, va in enumerate(LIGHTPLANE_ROW_ADVANCE_VAS)
]
SITES.append((3, 0x4542BC - AUTO_VA_TO_FILE, '8db800020000', 2, lambda g: g.view_w,
              'lightplane row advance 31/32 (lea edi)'))


def sites_for(geom):
    return SITES + (LIGHTMAP_SITES if geom.lightmap_patch else [])


def stack_sites(data):
    """(offset, expected, new, description) for the PE optional header's stack fields."""
    pe, = struct.unpack_from('<I', data, 0x3C)
    opt = pe + 4 + 20
    out = []
    for field, (old, new), what in ((0x48, STACK_RESERVE, 'PE header: SizeOfStackReserve'),
                                    (0x4C, STACK_COMMIT, 'PE header: SizeOfStackCommit')):
        out.append((opt + field, struct.pack('<I', old), struct.pack('<I', new), what))
    return out


def find_anchor(data, path):
    hits = [i for i in range(len(data) - len(ANCHOR_PREFIX) + 1)
            if data[i:i + len(ANCHOR_PREFIX)] == ANCHOR_PREFIX]
    if len(hits) != 1:
        raise SystemExit('%s: expected exactly one dimension anchor, found %d. Not a Dark '
                         'Colony executable, or too heavily modified to touch safely.'
                         % (path, len(hits)))
    return hits[0]


def read_dimensions(data, path):
    anchor = find_anchor(data, path)
    w, = struct.unpack_from('<I', data, anchor + 4)
    h, = struct.unpack_from('<I', data, anchor + 8)
    return anchor, w, h


def identify(data, path):
    md5 = hashlib.md5(data).hexdigest()
    if md5 in BUILDS:
        name, shift = BUILDS[md5]
        return name, shift, md5
    _, w, h = read_dimensions(data, path)
    if (w, h) != (640, 480):
        raise SystemExit('%s: already patched to %d x %d. Restore the .bak to get back to '
                         'stock before patching to a different size.' % (path, w, h))
    raise SystemExit('%s: md5 %s is not a build I know, though it is stock 640 x 480. It is '
                     'probably a build I have no AUTO offsets for (Council Wars dc16.exe is '
                     'one such). Re-derive the sites in Ghidra before patching it.'
                     % (path, md5))


def expected_and_target(site, geom):
    _, _, exp_hex, imm, fn, _ = site
    exp = bytes.fromhex(exp_hex)
    if imm is None:
        return exp, fn(geom)
    new = bytearray(exp)
    new[imm:imm + 4] = struct.pack('<I', fn(geom))
    return exp, bytes(new)


def resolve(data, path, shift, geom, stage, exclude=()):
    """Return (edits, problems); edits are (offset, old, new, description)."""
    anchor = find_anchor(data, path)
    edits, problems = [], []

    for off, val, what in ((anchor + 4, geom.w, 'screen width global'),
                           (anchor + 8, geom.h, 'screen height global')):
        edits.append((off, data[off:off + 4], struct.pack('<I', val), what))

    for site in sites_for(geom):
        site_stage, classic_off, _, _, _, what = site
        if site_stage > stage:
            continue
        if any(x.lower() in what.lower() for x in exclude):
            continue
        exp, new = expected_and_target(site, geom)
        off = auto_offset(classic_off, shift)
        got = data[off:off + len(exp)]
        if got != exp:
            problems.append('0x%-7X %-42s expected %s, found %s'
                            % (off, what, exp.hex(' '), got.hex(' ') or '<past end of file>'))
        elif len(new) != len(exp):
            problems.append('0x%-7X %-42s replacement changes instruction length'
                            % (off, what))
        else:
            edits.append((off, exp, new, what))

    if geom.lightmap_patch and stage >= 3:
        for off, exp, new, what in stack_sites(data):
            got = data[off:off + 4]
            if got != exp:
                problems.append('0x%-7X %-42s expected %s, found %s'
                                % (off, what, exp.hex(' '), got.hex(' ')))
            else:
                edits.append((off, exp, new, what))
    return edits, problems


def cmd_verify(path):
    data = open(path, 'rb').read()
    md5 = hashlib.md5(data).hexdigest()
    print('%s\n  %d bytes, md5 %s' % (path, len(data), md5))
    known_shift = None
    if md5 in BUILDS:
        name, known_shift = BUILDS[md5]
        print('  build: %s (stock)' % name)
    else:
        print('  build: not a known stock binary (patched, or one with no site table)')

    anchor, w, h = read_dimensions(data, path)
    print('  dimension globals at 0x%X / 0x%X: %d x %d' % (anchor + 4, anchor + 8, w, h))
    if (w, h) == (640, 480):
        print('  -> stock resolution')
        return 0

    try:
        geom = Geometry(w, h)
    except ValueError as e:
        print('  -> patched to a geometry this tool cannot reproduce:')
        print('     ' + str(e).replace('\n', '\n     '))
        return 1

    # A patched binary has an unknown md5, so try each known shift and keep the best fit.
    candidates = [known_shift] if known_shift is not None else sorted(
        {s for _, s in BUILDS.values()})
    best = None
    for cand in candidates:
        tally = {}
        for site in sites_for(geom):
            site_stage, classic_off = site[0], site[1]
            exp, want = expected_and_target(site, geom)
            got = data[auto_offset(classic_off, cand):][:len(exp)]
            state = 'patched' if got == want else 'stock' if got == exp else 'other'
            tally.setdefault(site_stage, []).append(state)
        score = sum(v.count('patched') for v in tally.values())
        if best is None or score > best[0]:
            best = (score, cand, tally)

    _, cand, tally = best
    for off, exp, new, what in stack_sites(data):
        got = data[off:off + 4]
        print('  %s: 0x%X (%s)' % (what, struct.unpack('<I', got)[0],
                                   'patched' if got == new else 'stock' if got == exp
                                   else 'unrecognised'))
    print('  site table matched with AUTO shift +0x%X:' % cand)
    for st in sorted(tally):
        v = tally[st]
        print('    stage %d: %2d/%-2d patched, %d stock, %d unrecognised'
              % (st, v.count('patched'), len(v), v.count('stock'), v.count('other')))
    print('  -> restore the .bak to go back to stock')
    return 0


def report(path, geom, stage, edits, problems):
    print('%s\n' % path)
    for line in geom.describe():
        print('  %s' % line)
    for w in geom.warnings:
        print('\n  !! %s' % '\n     '.join(textwrap.wrap(w, 92)))
    print('\n  stages 1..%d, %d edits\n' % (stage, len(edits)))
    for off, old, new, what in edits:
        print('  0x%-7X %-42s %-22s -> %s' % (off, what, old.hex(' '), new.hex(' ')))
    if problems:
        print('\n  %d site(s) did NOT match the expected bytes:\n' % len(problems))
        for p in problems:
            print('  ' + p)
    return len(problems)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=('verify', 'plan', 'apply'))
    ap.add_argument('exe')
    ap.add_argument('--width', type=int, default=1024)
    ap.add_argument('--height', type=int, default=768)
    ap.add_argument('--stage', type=int, default=4, choices=(1, 2, 3, 4),
                    help='highest cumulative stage to apply (default 4, everything)')
    ap.add_argument('--viewport', metavar='WxH',
                    help='diagnostic: force a smaller map viewport than the screen allows')
    ap.add_argument('--exclude', action='append', default=[], metavar='SUBSTR',
                    help='skip sites whose description contains SUBSTR (repeatable). For '
                         'bisecting a misbehaving stage; not for normal use.')
    args = ap.parse_args(argv)

    if not os.path.isfile(args.exe):
        raise SystemExit('%s: no such file' % args.exe)
    data = open(args.exe, 'rb').read()

    if args.command == 'verify':
        return cmd_verify(args.exe)

    name, shift, _ = identify(data, args.exe)
    try:
        vp = None
        if args.viewport:
            vp = tuple(int(x) for x in args.viewport.lower().split('x'))
        geom = Geometry(args.width, args.height, vp)
    except ValueError as e:
        raise SystemExit('bad target geometry: %s' % e)
    print('build: %s  (AUTO shift +0x%X)\n' % (name, shift))

    edits, problems = resolve(data, args.exe, shift, geom, args.stage, args.exclude)
    if args.exclude:
        print('excluding sites matching: %s'
              % ', '.join(repr(x) for x in args.exclude))
    if report(args.exe, geom, args.stage, edits, problems):
        print('\nrefusing to write: fix the mismatches above first.')
        return 1

    if args.command == 'plan':
        print('\nplan only, nothing written. Re-run with "apply" to patch.')
        return 0

    bak = args.exe + '.bak'
    if os.path.exists(bak):
        print('\nkeeping the existing %s, assumed to be the pristine original' % bak)
    else:
        shutil.copy2(args.exe, bak)
        print('\nsaved the original to %s' % bak)

    out = bytearray(data)
    for off, old, new, _ in edits:
        assert bytes(out[off:off + len(old)]) == old
        out[off:off + len(new)] = new
    open(args.exe, 'wb').write(bytes(out))
    print('patched %s: %d edits, %d x %d' % (args.exe, len(edits), geom.w, geom.h))

    print('\nStill to do by hand, data and art only (doc section 10):')
    if args.stage >= 2:
        print('  stage 2: set "size %d %d 640 480" in the INTRFACE/*E scripts to centre the'
              % ((geom.w - 640) // 2, (geom.h - 480) // 2))
        print('           30 existing 640x480 screens, or repaint them at %d x %d'
              % (geom.w, geom.h))
    if args.stage >= 3:
        print('  stage 5: repaint INTRFACE/INTRFACE.GIF with the transparent hole at')
        print('           (%d,%d) %dx%d, and shift the MAINE widgets: x += %d for the 75'
              % (INSET_X, INSET_Y, geom.view_w, geom.view_h, geom.w - 640))
        print('           right-panel ones, y += %d for the bottom bar and message lines'
              % (geom.h - 480))
        print('           (tools/spr.py handles MAINBUT.SPR and the fonts)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
