#!/usr/bin/env python3
"""Keep the Windows mouse pointer hidden over Dark Colony's window (dc16.exe / DCEXP16.EXE).

The game draws its own cursor (a DirectDraw BltFast from one of the 32 `CURSOR/cursor%d.bmp`
surfaces) and hides the Windows pointer with SetCursor(NULL), but the stock code leaves two
holes through which the system pointer comes back, so on a modern Windows it flickers between
the game cursor and a system pointer (an arrow on the first loading screen, an icon-sized
block later):

1. `create_window` (0x0042E688) fills a WNDCLASSA on the stack and never writes `hCursor`
   ([ebp-0x10]) - the field is whatever the previous callee left in that stack slot, so the
   class gets a random handle as its cursor.  The Windows contract for a self-drawn cursor is a
   NULL class cursor ("if the class cursor is not NULL, the system restores the class cursor each
   time the mouse is moved").
2. The window procedure (0x0042E340) answers WM_SETCURSOR with SetCursor(NULL) and then falls
   through into DefWindowProcA, which immediately restores the class cursor.  The handler has
   to return TRUE instead.

A third edit calls SetCursor(NULL) right after ShowWindow, so the pointer is already gone
while the loading screen is drawn (the stock code first hides it at 0x00408CD0, after the
initial load, and again once per frame at 0x0042F2B8).

Both fixes are done without moving any other code: the 7-byte `call cs:[import]` forms are
rewritten as 5-byte relative calls to the import thunks the linker already emitted at the end of
AUTO (`jmp dword ptr [import]`), which frees the bytes for `mov eax,1` / `mov [ebp-10h],ebx`.
The `.reloc` entries of the operands that move are updated and the ones that disappear are
turned into IMAGE_REL_BASED_ABSOLUTE padding, so the table still describes the image exactly.
The 12-byte SetCursor+UpdateWindow stub lives in the zero tail of AUTO (0x47F1D0 / 0x47F230),
which the section's raw size already covers.

The same code sits at +0x60 in Council Wars' DCEXP16.EXE (doc DC16_DISPLAY_AND_RESOLUTION.md
10.10); only the class-name pointer differs.  Nothing is written unless every site still holds
its expected bytes; `verify` reports stock / patched.  See doc section 10.12.

CLI
    python patch_cursor.py verify EXE
    python patch_cursor.py plan   EXE
    python patch_cursor.py apply  EXE          (writes EXE.cursor.bak first)
"""

import argparse
import shutil
import struct
import sys

AUTO_VA_TO_FILE = 0x400C00     # both builds: AUTO at VA 0x401000 = file 0x400
RELOC_PAGE = 0x2E000           # RVA of the page holding both functions (VA 0x42E000)


def rel32(src_end, target):
    return struct.pack('<i', target - src_end)


def code(*parts):
    return b''.join(bytes.fromhex(p) if isinstance(p, str) else p for p in parts)


# ------------------------------------------------------------------- builds
#
# Every address is a VA. `thunks` are the linker's `jmp dword ptr [IAT]` stubs at the end of
# AUTO; a relative call to one behaves exactly like the indirect call it replaces (stdcall,
# argument popped by the callee) and carries no absolute pointer, hence needs no relocation.
BUILDS = {
    'Classic dc16.exe': dict(
        wndproc=0x42E340, create_window=0x42E688, update_window_call=0x42E794,
        class_name=0x485914, stub=0x47F1D0,
        thunks=dict(SetCursor=0x47EFF0, UpdateWindow=0x47EF8A, RegisterClassA=0x47EF9C,
                    GetStockObject=0x47EFA2, LoadIconA=0x47EFA8)),
    'Council Wars DCEXP16.EXE': dict(
        wndproc=0x42E3A0, create_window=0x42E6E8, update_window_call=0x42E7F4,
        class_name=0x48591C, stub=0x47F230,
        thunks=dict(SetCursor=0x47F050, UpdateWindow=0x47EFEA, RegisterClassA=0x47EFFC,
                    GetStockObject=0x47F002, LoadIconA=0x47F008)),
}


def sites_for(b):
    """Return [(name, va, expected_bytes, new_bytes)] and the .reloc edits for a build."""
    t = b['thunks']
    wp, cw = b['wndproc'], b['create_window']
    cls = struct.pack('<I', b['class_name'])
    sites = []

    # --- window procedure: WM_SETCURSOR -> SetCursor(NULL); return TRUE -----------------
    #
    #   stock (wp+0x11 .. wp+0x39)                 patched
    #   76 1B        jbe  wp+0x2E (WM_SETCURSOR)   76 17        jbe  wp+0x2A
    #   81 FE 12 01 00 00  cmp esi,112h            (same)
    #   74 1E        je   wp+0x39 (WM_SYSCOMMAND)  (same)
    #   E9 8D000000  jmp  wp+0xAD (DefWindowProc)  (same)
    #   83 FE 02     cmp  esi,2                    (same)
    #   0F 84 76000000 je wp+0x9F (WM_DESTROY)     74 7A        je   wp+0x9F
    #   E9 7F000000  jmp  wp+0xAD                  E9 83000000  jmp  wp+0xAD
    #   6A 00        push 0                        6A 00        push 0
    #   2E FF 15 E0034800 call cs:[SetCursor]      E8 rel32     call thunk SetCursor
    #   EB 74        jmp  wp+0xAD (DefWindowProc)  6A 01 58     push 1 / pop eax  (return TRUE)
    #                                              E9 85000000  jmp  wp+0xBE (epilogue: pop x4, ret 10h)
    va = wp + 0x11
    stock = code('76 1B', '81 FE 12 01 00 00', '74 1E', 'E9 8D 00 00 00', '83 FE 02',
                 '0F 84 76 00 00 00', 'E9 7F 00 00 00', '6A 00', '2E FF 15 E0 03 48 00', 'EB 74')
    new = code('76 17', '81 FE 12 01 00 00', '74 1E', 'E9 8D 00 00 00', '83 FE 02',
               '74 7A', 'E9 83 00 00 00', '6A 00',
               'E8', rel32(wp + 0x2A + 2 + 5, t['SetCursor']),
               '6A 01', '58',
               'E9', rel32(wp + 0x34 + 5, wp + 0xBE))
    assert len(stock) == len(new) == 0x28
    sites.append(('wndproc WM_SETCURSOR returns TRUE', va, stock, new))

    # --- create_window: WNDCLASSA.hCursor = NULL ----------------------------------------
    #
    #   stock (cw+0x27 .. cw+0x5B)                 patched
    #   2E FF 15 C8034800 call cs:[LoadIconA]      E8 rel32     call thunk LoadIconA
    #   89 45 EC     mov [ebp-14h],eax  (hIcon)    (same)
    #   A1 20FF4D00  mov eax,[hInstance]           (same, 2 bytes earlier)
    #   6A 04        push BLACK_BRUSH              (same)
    #   89 45 E8     mov [ebp-18h],eax             (same)
    #   2E FF 15 A0034800 call cs:[GetStockObject] E8 rel32     call thunk GetStockObject
    #   89 45 F4     mov [ebp-0Ch],eax (hbrBackground)  (same)
    #   8D 45 D8     lea eax,[ebp-28h]  (&wc)      (same)
    #   BA <class>   mov edx,offset class name     (same, 4 bytes earlier)
    #   50           push eax                      (same)
    #   89 5D F8     mov [ebp-8],ebx  (lpszMenuName=0)   (same)
    #   89 55 FC     mov [ebp-4],edx  (lpszClassName)    (same)
    #                                              89 5D F0     mov [ebp-10h],ebx  (hCursor = 0)  NEW
    #   2E FF 15 DC034800 call cs:[RegisterClassA] E8 rel32     call thunk RegisterClassA
    #                                              90 90 90
    va = cw + 0x27
    stock = code('2E FF 15 C8 03 48 00', '89 45 EC', 'A1 20 FF 4D 00', '6A 04', '89 45 E8',
                 '2E FF 15 A0 03 48 00', '89 45 F4', '8D 45 D8', 'BA', cls, '50',
                 '89 5D F8', '89 55 FC', '2E FF 15 DC 03 48 00')
    new = code('E8', rel32(cw + 0x27 + 5, t['LoadIconA']),
               '89 45 EC', 'A1 20 FF 4D 00', '6A 04', '89 45 E8',
               'E8', rel32(cw + 0x39 + 5, t['GetStockObject']),
               '89 45 F4', '8D 45 D8', 'BA', cls, '50', '89 5D F8', '89 55 FC',
               '89 5D F0',
               'E8', rel32(cw + 0x53 + 5, t['RegisterClassA']),
               '90 90 90')
    assert len(stock) == len(new) == 0x34
    sites.append(('create_window hCursor = NULL', va, stock, new))

    # --- create_window: UpdateWindow(hwnd) -> stub: SetCursor(NULL); UpdateWindow(hwnd) ----
    va = b['update_window_call']
    stock = code('2E FF 15 E8 03 48 00')
    new = code('E8', rel32(va + 5, b['stub']), '90 90')
    sites.append(('create_window UpdateWindow -> stub', va, stock, new))

    # --- the stub, in the zero tail of AUTO ---------------------------------------------
    #   6A 00      push 0
    #   E8 rel32   call thunk SetCursor          (stdcall: pops the 0)
    #   E9 rel32   jmp  thunk UpdateWindow       (tail call: hwnd and return address untouched)
    va = b['stub']
    new = code('6A 00', 'E8', rel32(va + 2 + 5, t['SetCursor']),
               'E9', rel32(va + 7 + 5, t['UpdateWindow']))
    sites.append(('stub SetCursor(NULL)+UpdateWindow', va, bytes(len(new)), new))

    # --- .reloc: page offsets of the absolute operands that move or vanish ------------------
    # (offset_in_page: new_offset or None for "turn into ABSOLUTE padding")
    relocs = {
        wp - 0x42E000 + 0x33: None,            # SetCursor IAT operand in the wndproc
        cw - 0x42E000 + 0x2A: None,            # LoadIconA IAT operand
        cw - 0x42E000 + 0x32: cw - 0x42E000 + 0x30,   # hInstance global (mov eax,[..])
        cw - 0x42E000 + 0x3E: None,            # GetStockObject IAT operand
        cw - 0x42E000 + 0x49: cw - 0x42E000 + 0x45,   # class name (mov edx,imm32)
        cw - 0x42E000 + 0x57: None,            # RegisterClassA IAT operand
        b['update_window_call'] - 0x42E000 + 3: None,  # UpdateWindow IAT operand
    }
    return sites, relocs


# ------------------------------------------------------------------ PE helpers
def sections(data):
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    nsec = struct.unpack_from('<H', data, pe + 6)[0]
    opt = struct.unpack_from('<H', data, pe + 20)[0]
    st = pe + 24 + opt
    out = {}
    for i in range(nsec):
        s = data[st + i * 40: st + i * 40 + 40]
        name = s[:8].rstrip(b'\0').decode()
        vsize, va, rsize, rptr = struct.unpack_from('<IIII', s, 8)
        out[name] = (va, rsize, rptr)
    return out


def reloc_block(data, page_rva):
    """File offset of the entries and their count for the .reloc block of one page."""
    va, rsize, rptr = sections(data)['.reloc']
    pos, end = rptr, rptr + rsize
    while pos + 8 <= end:
        rva, size = struct.unpack_from('<II', data, pos)
        if size == 0:
            break
        if rva == page_rva:
            return pos + 8, (size - 8) // 2
        pos += size
    raise SystemExit('no .reloc block for page RVA %#x' % page_rva)


def reloc_edits(data, relocs):
    """Return [(file_offset, expected_u16, new_u16)] for the .reloc entries of one page."""
    start, count = reloc_block(data, RELOC_PAGE)
    entries = {}
    for i in range(count):
        v = struct.unpack_from('<H', data, start + 2 * i)[0]
        if v >> 12 == 3:                          # HIGHLOW
            entries.setdefault(v & 0xFFF, []).append(start + 2 * i)
    edits = []
    for old, new in relocs.items():
        want_new = 0 if new is None else 0x3000 | new
        want_old = 0x3000 | old
        if old in entries:
            edits.append((entries[old][0], want_old, want_new))
        elif new is not None and new in entries:
            edits.append((entries[new][0], want_new, want_new))     # already moved
        else:
            edits.append((None, want_new, want_new))                # already neutralised
    return edits


# ------------------------------------------------------------------- checks
def identify(data, path):
    for name, b in BUILDS.items():
        sites, relocs = sites_for(b)
        name_, va, stock, new = sites[0]
        off = va - AUTO_VA_TO_FILE
        if data[off:off + len(stock)] == stock:
            return name, b, 'stock'
        if data[off:off + len(new)] == new:
            return name, b, 'patched'
    raise SystemExit('%s: neither build\'s window procedure found at 0x2D751 / 0x2D7B1; '
                     'not a dc16.exe / DCEXP16.EXE build this tool knows.' % path)


def resolve(data, b):
    """[(name, file_off, expected, new)] for code, plus reloc edits; raises on a mismatch."""
    sites, relocs = sites_for(b)
    out, problems = [], []
    for name, va, stock, new in sites:
        off = va - AUTO_VA_TO_FILE
        have = data[off:off + len(stock)]
        if have == stock:
            out.append((name, off, stock, new))
        elif have == new:
            out.append((name, off, new, new))
        else:
            problems.append('%s @ file %#x: expected %s, found %s'
                            % (name, off, stock.hex(), have.hex()))
    if problems:
        raise SystemExit('refusing to patch, unexpected bytes:\n  ' + '\n  '.join(problems))
    return out, reloc_edits(data, relocs)


def state(edits):
    done = sum(1 for _, _, exp, new in edits if exp == new)
    return 'patched' if done == len(edits) else 'stock' if done == 0 else 'PARTIAL'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('command', choices=('verify', 'plan', 'apply'))
    ap.add_argument('exe')
    a = ap.parse_args(argv)

    data = bytearray(open(a.exe, 'rb').read())
    name, b, _ = identify(data, a.exe)
    edits, redits = resolve(data, b)
    print('%s: %s, cursor fix %s' % (a.exe, name, state(edits)))
    if a.command == 'verify':
        return 0

    for site, off, exp, new in edits:
        print('  %-40s file %#7x  VA %#x  %s' % (site, off, off + AUTO_VA_TO_FILE,
                                                  'done' if exp == new else '%d bytes' % len(new)))
        if exp != new:
            print('      %s\n   -> %s' % (exp.hex(' '), new.hex(' ')))
    for off, old, new in redits:
        print('  .reloc @ file %s: %04X -> %04X%s' % (off is not None and '%#x' % off or '-', old,
                                                      new, '  (done)' if old == new else ''))
    if a.command == 'plan':
        return 0
    if state(edits) == 'patched':
        print('nothing to do')
        return 0

    bak = a.exe + '.cursor.bak'
    shutil.copyfile(a.exe, bak)
    for site, off, exp, new in edits:
        data[off:off + len(new)] = new
    for off, old, new in redits:
        if off is not None:
            struct.pack_into('<H', data, off, new)
    open(a.exe, 'wb').write(data)
    print('written %s (%d code sites, %d .reloc entries); backup %s'
          % (a.exe, len(edits), len(redits), bak))
    return 0


if __name__ == '__main__':
    sys.exit(main())
