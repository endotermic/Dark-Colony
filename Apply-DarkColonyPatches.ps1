<#
.SYNOPSIS
    Rebuilds the patched Dark Colony executables from the untouched originals, one documented
    patch at a time, so that anyone can see exactly which bytes change and why.

.DESCRIPTION
    The executables shipped in https://github.com/endotermic/Dark-Colony are the original 1997/98
    binaries with a handful of byte patches (no CD check, 1024x768, cursor fix, ...).  Because a
    hand-modified exe cannot be signed and looks suspicious to antivirus heuristics, this script
    makes the modification fully transparent and reproducible:

      * run without arguments it opens a window: pick the original, tick the fixes you want (the first
        box selects all of them), press Apply - or drive it from the command line, see the examples
      * it never touches the input file; it writes a new file
      * every patch is a list of (file offset, old bytes, new bytes, reason) in plain text below
      * a byte is only written if the file still holds the documented old bytes at that offset
      * the SHA-256 of the input must match the known original (override with -Force, the
        per-byte checks stay on)
      * after writing it prints the SHA-256 of the result; with every patch selected the result
        is byte-identical to the executable published in the repository and the script says so

    The originals: "DC - Classic\dc16original1998.exe" (the dc16.exe of the January 1998 update,
    6 sections, entry point 0x4528DE) and "DC - Council wars\engexp16original.exe" (ENGEXP16.EXE
    from the Council Wars CD).  Both are committed untouched in the repository (commit 9b1b286).

    The script is complete in itself: it uses nothing but the .NET classes that ship with Windows
    PowerShell 5.1 / PowerShell 7 (System.IO.File, System.Security.Cryptography.SHA256, Windows Forms).
    No Python, no downloads, no external tools, no network access - a plain Windows installation is
    enough.  (Python is only used by the maintainer to regenerate this file from the repository.)  Read it top to bottom: the logic is ~200 lines at the end, the rest is data.

    How the patches were found is documented in the sister repository
    https://github.com/endotermic/Dark-Colony-Server, folder docs/ (DC16_DISPLAY_AND_RESOLUTION.md
    in particular) and tools/ (the Python patchers whose output this file reproduces).  This
    file was generated from those tools by replaying them on the originals and diffing after every
    step; the "old bytes" of every edit are therefore the bytes of the original (or of the previous
    patch in the fixed order below), and the sum of all patches is exactly the shipped exe.

.PARAMETER Original
    Path of the untouched original executable (dc16original1998.exe or engexp16original.exe).

.PARAMETER Output
    Where to write the patched copy.  Default: dc16.exe / DCEXP16.EXE next to the original.
    An existing file is not overwritten unless -Overwrite is given.

.PARAMETER Patches
    Patch ids to apply (see -List).  Order does not matter: they are always applied in the fixed
    canonical order.  Use -All for every patch of the build.  With neither, the window opens
    (with the original preloaded when -Original was given).

.PARAMETER Verify
    Instead of patching, inspect an existing exe: which build it is and which patches it carries.

.EXAMPLE
    .\Apply-DarkColonyPatches.ps1                               # the window
    .\Apply-DarkColonyPatches.ps1 -List
    .\Apply-DarkColonyPatches.ps1 -List -Detail                 # every single byte edit
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Classic\dc16original1998.exe" -All
        (run from the root of the Dark-Colony repository, where this file lives)
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Classic\dc16original1998.exe" -Patches cdcheck,resolution,hdpaths,pool
    .\Apply-DarkColonyPatches.ps1 -Verify "DC - Classic\dc16.exe"

.NOTES
    If Windows refuses to run the script ("running scripts is disabled"), start it once with
        powershell -ExecutionPolicy Bypass -File .\Apply-DarkColonyPatches.ps1
    Offsets are 0-based file offsets, written as PowerShell hex literals (0x431F).  Bytes are
    upper-case hex separated by spaces.  Code addresses quoted in the comments are virtual
    addresses (VA) inside the loaded image: VA = file offset + 0x400C00 for code, DGROUP data
    VA = file offset + 0x402800 (Classic) / 0x402600 (Council Wars).
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply', Position = 0)] [string] $Original,
    [Parameter(ParameterSetName = 'Apply')] [string] $Output,
    [Parameter(ParameterSetName = 'Apply')] [string[]] $Patches,
    [Parameter(ParameterSetName = 'Apply')] [switch] $All,
    [Parameter(ParameterSetName = 'Apply')] [switch] $Overwrite,
    [Parameter(ParameterSetName = 'Apply')] [switch] $Force,
    [Parameter(ParameterSetName = 'List')] [switch] $List,
    [Parameter(ParameterSetName = 'List')] [switch] $Detail,
    [Parameter(ParameterSetName = 'Verify')] [string] $Verify
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# =================================================================================================
#  DATA - the two builds and their patches
#
#  Each edit:  @{ Offset = <file offset>; Old = '<hex bytes>'; New = '<hex bytes>'; Note = '<why>' }
#  One special edit kind (OZI patch only): @{ Insert = <offset>; Bytes = '<16 bytes>'; Before = '<the
#  16 bytes found there before>'; SectionEnd = <offset>; Note = ... } - inserts Bytes at Insert and
#  drops the 16 zero bytes just before SectionEnd, so the file size does not change.
# =================================================================================================
$Builds = @(

    # ---------------------------------------------------------------------------------------------
    #  Dark Colony (Classic) dc16.exe, build linked 7 Jan 1998, 659456 bytes
    # ---------------------------------------------------------------------------------------------
    @{
        Id             = 'Classic'
        Title          = 'Dark Colony (Classic) dc16.exe, build linked 7 Jan 1998, 659456 bytes'
        OriginalName   = 'dc16original1998.exe'
        OutputName     = 'dc16.exe'
        Size           = 659456
        OriginalSha256 = '7c003f85d902dc025d05ab4c5b8f754cd7568bafdf60af6866e8dbcc9b2d57f1'   # untouched original
        PatchedSha256  = '0e9297c236996976a1796e4a73d242ea7056b3a8ae8e5b3f70558cb1d477b735'   # every patch applied = the exe in the repository (14 Sep 2026)
        Patches        = @(

            # ---- cdcheck: No CD required ---------------------------------------------------------
            #  Added      : 28-30 Sep 2025
            #  Made with  : hand-patched (commits f6246e1, 314ae66 in endotermic/Dark-Colony)
            #  Documented : CLAUDE.md "Patches applied so far"
            #  Changes    : 2 bytes in 2 edits
            #  The game refuses to start, and greys out most main-menu buttons, when it cannot find its
            #  CD in a drive.  One function (VA 0x405E8C) answers "is the CD here?" with a bool in al and every
            #  caller does "test al,al ; jne ok".  Turning that conditional jump (opcode 75) into an
            #  unconditional jump (opcode EB) makes the game behave as if the disc were always present.
            #  Council Wars has a third test that runs while a game is in progress and throws the player back
            #  to the menu; that one is inverted (75 -> 74, jne -> je).
            #
            #  Nothing else changes: no code is added, no file access is redirected, one byte per site.
            @{
                Id = 'cdcheck'; Name = 'No CD required'; Date = '28-30 Sep 2025'
                Tool = 'hand-patched (commits f6246e1, 314ae66 in endotermic/Dark-Colony)'; Doc = 'CLAUDE.md "Patches applied so far"'
                Description = @'
The game refuses to start, and greys out most main-menu buttons, when it cannot find its
CD in a drive.  One function (VA 0x405E8C) answers "is the CD here?" with a bool in al and every
caller does "test al,al ; jne ok".  Turning that conditional jump (opcode 75) into an
unconditional jump (opcode EB) makes the game behave as if the disc were always present.
Council Wars has a third test that runs while a game is in progress and throws the player back
to the menu; that one is inverted (75 -> 74, jne -> je).

Nothing else changes: no code is added, no file access is redirected, one byte per site.
'@
                Edits = @(
                    # jne -> jmp right after "call 0x405E8C ; test al,al" (the CD-presence check returning a bool in al): always take the "CD present" path
                    @{ Offset = 0x431F; Old = '75'; New = 'EB' }
                    # jne -> jmp after the same CD test in the main-menu builder: the menu buttons that are greyed out without the CD stay enabled
                    @{ Offset = 0x509F; Old = '75'; New = 'EB' }
                )
            }

            # ---- resolution: 1024x768 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10
            #  Changes    : 362 bytes in 165 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (20x15 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
            #    stage 1  display mode, framebuffer stride, clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at (903,6), the 31
            #             lightplane row advances, and a bigger stack frame for draw_terrain (so the PE
            #             header's SizeOfStackReserve / SizeOfStackCommit go up as well - the two edits at
            #             file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,96)-(1024,672) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the rebuilt 1024x768 interface data that ships in the repository next to the exe -
            #  since 14 Sep 2026 in the INTRF_HD/ folder, read through the "Interface data from INTRF_HD"
            #  patch below (select both); with stock 640x480 data the menus draw in the top-left corner.
            @{
                Id = 'resolution'; Name = '1024x768 display'; Date = '9 Sep 2026'
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (20x15 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
  stage 1  display mode, framebuffer stride, clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at (903,6), the 31
           lightplane row advances, and a bigger stack frame for draw_terrain (so the PE
           header's SizeOfStackReserve / SizeOfStackCommit go up as well - the two edits at
           file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,96)-(1024,672) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the rebuilt 1024x768 interface data that ships in the repository next to the exe -
since 14 Sep 2026 in the INTRF_HD/ folder, read through the "Interface data from INTRF_HD"
patch below (select both); with stock 640x480 data the menus draw in the top-left corner.
'@
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 03 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 FF 02 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA CA 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 64 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA F6 01 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 4E 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA DD 00 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA DD 02 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA DD 02 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB C8 00 00 00'; New = 'BB 89 01 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA 74 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5060; Old = 'BB 18 00 00 00'; New = 'BB A8 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5071; Old = 'BA 50 01 00 00'; New = 'BA 10 02 00 00' }
                    # release_surfaces: release the movie surface whenever it exists
                    @{ Offset = 0x6430; Old = '75 18'; New = '90 90' }
                    # avi_create_surfaces: after GetAttachedSurface, mov edx,eax; jmp 4071E0 (edx=0 -> create the 320x180 surface; else return 0)
                    @{ Offset = 0x652E; Old = '85 C0 0F 84 55 01 00 00 E9 71 02 00 00'; New = '89 C2 E9 AB 00 00 00 90 90 90 90 90 90' }
                    # avi_create_surfaces: keep the flip flag when creating the movie surface
                    @{ Offset = 0x663D; Old = '89 1D 0C 8E 48 00'; New = '90 90 90 90 90 90' }
                    # movie clear: cmp eax,[ebp-60h] (dwWidth from the Lock)
                    @{ Offset = 0x67F4; Old = '3D 80 02 00 00'; New = '3B 45 A0 90 90' }
                    # movie clear: add ecx,[ebp-5Ch] (lPitch from the Lock)
                    @{ Offset = 0x6805; Old = '81 C1 00 05 00 00'; New = '03 4D A4 90 90 90' }
                    # movie clear: cmp edx,[ebp-64h] (dwHeight from the Lock)
                    @{ Offset = 0x680B; Old = '81 FA E0 01 00 00'; New = '3B 55 9C 90 90 90' }
                    # clear_and_flip: also clear the movie surface in flip mode
                    @{ Offset = 0x6879; Old = 'E9 D4 00 00 00'; New = '90 90 90 90 90' }
                    # draw_offscreen: draw all H rows, not H-1 (jae -> ja)
                    @{ Offset = 0x6D1B; Old = '0F 83'; New = '0F 87' }
                    # draw_offscreen: BltFast -> stretching Blt(primary, dest rect, movie surface)
                    @{ Offset = 0x7214; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 18 97 48 00 89 55 5A 8D 55 52 8B 1D 00 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 60 00 00 00 C7 45 6A 00 04 00 00 C7 45 6E A0 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 00 8E 48 00 8D 55 62 52 A1 18 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F3E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x9484; Old = '2D 07 02 00 00'; New = '2D 87 03 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F0A; Old = '6A 0E'; New = '6A 17' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F0C; Old = 'B9 10 00 00 00'; New = 'B9 1C 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F1C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0B 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F2B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 0E 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA4BC; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0B 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA4E0; Old = '81 EA 00 08 00 00'; New = '81 EA 00 0E 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E11E; Old = 'B9 C0 01 00 00'; New = 'B9 E0 02 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E123; Old = 'BB 00 02 00 00'; New = 'BB 80 03 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E243; Old = 'B8 07 02 00 00'; New = 'B8 87 03 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E266; Old = 'B9 00 08 00 00'; New = 'B9 00 0E 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E26F; Old = 'BB 00 07 00 00'; New = 'BB 80 0B 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B594; Old = 'BB 80 02 00 00'; New = 'BB 00 04 00 00' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B613; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640 -> y*W: shl edx
                    @{ Offset = 0x2B618; Old = 'C1 E2 07'; New = 'C1 E2 08' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B661; Old = 'BA 80 02 00 00'; New = 'BA 00 04 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B747; Old = 'BB 80 02 00 00'; New = 'BB 00 04 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B763; Old = 'B9 E0 01 00 00'; New = 'B9 00 03 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D5D2; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D5FF; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D60E; Old = 'B8 E0 01 00 00'; New = 'B8 00 03 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D619; Old = 'B8 E0 01 00 00'; New = 'B8 00 03 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DBC4; Old = 'BA 40 01 00 00'; New = 'BA 00 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DBC9; Old = 'B9 F0 00 00 00'; New = 'B9 80 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DC98; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DCA2; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD1C; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD26; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DE89; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DE8E; Old = 'BA E0 01 00 00'; New = 'BA 00 03 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E307; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E30C; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E338; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E33D; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E3ED; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E3F2; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EBAD; Old = '3D 00 B0 04 00'; New = '3D 00 00 0C 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EBE2; Old = '3D 00 B0 04 00'; New = '3D 00 00 0C 00' }
                    # visible tiles down
                    @{ Offset = 0x35247; Old = 'B9 0E 00 00 00'; New = 'B9 17 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x3524C; Old = '8D 50 F2'; New = '8D 50 E9' }
                    # visible tiles across
                    @{ Offset = 0x3524F; Old = 'BB 10 00 00 00'; New = 'BB 1C 00 00 00' }
                    # viewport width
                    @{ Offset = 0x35346; Old = 'BA 00 02 00 00'; New = 'BA 80 03 00 00' }
                    # viewport height
                    @{ Offset = 0x35361; Old = 'BB C0 01 00 00'; New = 'BB E0 02 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x35388; Old = 'BA 00 70 00 00'; New = 'BA 00 42 01 00' }
                    # render destination stride
                    @{ Offset = 0x3539F; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # engmain.c y*1280: neutralise add eax,edi
                    @{ Offset = 0x354B9; Old = '01 F8'; New = '89 C0' }
                    # engmain.c y*1280 -> y*W*2: shl eax
                    @{ Offset = 0x354BE; Old = 'C1 E0 08'; New = 'C1 E0 09' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x357BD; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640 -> y*W: shl eax
                    @{ Offset = 0x357C5; Old = 'C1 E0 07'; New = 'C1 E0 08' }
                    # minimap stride (a)
                    @{ Offset = 0x3949B; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x394AF; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 37 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x395E4; Old = 'B8 07 02 00 00'; New = 'B8 87 03 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x3967A; Old = '05 07 02 00 00'; New = '05 87 03 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x3985B; Old = 'BA 80 02 00 00'; New = 'BA 00 04 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x39884; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 37 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x50247; Old = '81 FE 80 02 00 00'; New = '81 FE 00 04 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x5024F; Old = 'BE 7F 02 00 00'; New = 'BE FF 03 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x5025C; Old = '81 FF E0 01 00 00'; New = '81 FF 00 03 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x50264; Old = 'BF DF 01 00 00'; New = 'BF FF 02 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x50346; Old = '3D 7F 02 00 00'; New = '3D FF 03 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x5034D; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 03 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x5036B; Old = '81 FE DF 01 00 00'; New = '81 FE FF 02 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x50373; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 FF 02 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D15; Old = '81 EC CC 14 00 00'; New = '81 EC 3C 1C 00 00' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F20; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 46 E4 FF FF' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52F7A; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E 3E E4 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52F81; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F 3E E4 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52F88; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 46 E4 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52F91; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 46 E4 FF FF' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x52FB3; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 42 E4 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53005; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A 3A E4 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5302D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 3A E4 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5303C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 42 E4 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x5305D; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 42 E4 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x530CB; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x530F2; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53115; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x53162; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x5318E; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x531C9; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x531FC; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53226; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x53258; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x53293; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x532C6; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x532F9; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53324; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x53361; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x53394; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x533C7; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x533FA; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5342D; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x53457; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x53492; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x534B4; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x534F6; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53529; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x53545; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x5358F; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x535C2; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x535F5; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53628; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x5365B; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x53676; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x536BC; Old = '8D B8 00 02 00 00'; New = '8D B8 80 03 00 00' }
                    # screen width global
                    @{ Offset = 0x865B4; Old = '80 02 00 00'; New = '00 04 00 00' }
                    # screen height global
                    @{ Offset = 0x865B8; Old = 'E0 01 00 00'; New = '00 03 00 00' }
                )
            }

            # ---- hdpaths: Interface data from INTRF_HD (1024x768 files renamed) ---------------------------------------------------------
            #  Added      : 14 Sep 2026
            #  Made with  : tools/patch_hd_paths.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17
            #  Changes    : 120 bytes in 30 edits
            #  The 1024x768 menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
            #  used to replace the stock files under their stock names, so the untouched original exe could no
            #  longer run from the same folder.  They now live under their stock names in INTRF_HD/ (Council Wars
            #  also exp/intrf_hd/ and ozi_ns/intrf_hd/), the stock 640x480 files are back in INTRFACE/ and
            #  GAMESTAT/, and the re-baked logo animations are SPRITES/DCSS_HD.SPR, DCUK_HD.SPR, DCUT_HD.SPR with
            #  matching ANIMATE/*_HD.FIN.  The game opens each of those files through a literal path in the data
            #  section ("intrface/bintro" plus the language letter, "gamestat/hscene" plus ".txt", ...), so this
            #  patch rewrites the 8-byte directory part of exactly the 30 strings whose files were rebuilt:
            #  "intrface" / "gamestat" -> "intrf_hd", same length, in place.  Fonts, text files, per-screen
            #  sprite lists without logo banks and every other file keep their stock path and single copy; the two
            #  lists that do name logo banks (INTRG.DAT, INTRO.DAT) are redirected to INTRF_HD copies that say
            #  dcuk_hd.fin etc.  No code changes.  With this patch dc16original1998.exe / engexp16original.exe
            #  (stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
            #  meaningful together with the 1024x768 patch, and REQUIRES the INTRF_HD/ folder from the repository.
            @{
                Id = 'hdpaths'; Name = 'Interface data from INTRF_HD (1024x768 files renamed)'; Date = '14 Sep 2026'
                Tool = 'tools/patch_hd_paths.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17'
                Description = @'
The 1024x768 menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
used to replace the stock files under their stock names, so the untouched original exe could no
longer run from the same folder.  They now live under their stock names in INTRF_HD/ (Council Wars
also exp/intrf_hd/ and ozi_ns/intrf_hd/), the stock 640x480 files are back in INTRFACE/ and
GAMESTAT/, and the re-baked logo animations are SPRITES/DCSS_HD.SPR, DCUK_HD.SPR, DCUT_HD.SPR with
matching ANIMATE/*_HD.FIN.  The game opens each of those files through a literal path in the data
section ("intrface/bintro" plus the language letter, "gamestat/hscene" plus ".txt", ...), so this
patch rewrites the 8-byte directory part of exactly the 30 strings whose files were rebuilt:
"intrface" / "gamestat" -> "intrf_hd", same length, in place.  Fonts, text files, per-screen
sprite lists without logo banks and every other file keep their stock path and single copy; the two
lists that do name logo banks (INTRG.DAT, INTRO.DAT) are redirected to INTRF_HD copies that say
dcuk_hd.fin etc.  No code changes.  With this patch dc16original1998.exe / engexp16original.exe
(stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
meaningful together with the 1024x768 patch, and REQUIRES the INTRF_HD/ folder from the repository.
'@
                Edits = @(
                    # DGROUP string "intrface/newgame" -> "intrf_hd/newgame": new-game / mission-selection script NEWGAMEE
                    @{ Offset = 0x7F930; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/story" -> "intrf_hd/story": story screen script STORYE
                    @{ Offset = 0x7F94C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/encyclo" -> "intrf_hd/encyclo": encyclopedia screen script ENCYCLOE
                    @{ Offset = 0x7F9AC; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/hscene" -> "intrf_hd/hscene": human campaign briefing list HSCENE.TXT (letterboxed globe markers)
                    @{ Offset = 0x7FA10; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gscene" -> "intrf_hd/gscene": alien campaign briefing list GSCENE.TXT
                    @{ Offset = 0x7FA20; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/htscene" -> "intrf_hd/htscene": human training briefing list HTSCENE.TXT
                    @{ Offset = 0x7FA30; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gtscene" -> "intrf_hd/gtscene": alien training briefing list GTSCENE.TXT
                    @{ Offset = 0x7FA44; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/hxscene" -> "intrf_hd/hxscene": Council Wars human campaign briefing list HXSCENE.TXT (exp/ overlay)
                    @{ Offset = 0x7FA58; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gxscene" -> "intrf_hd/gxscene": Council Wars alien campaign briefing list GXSCENE.TXT (exp/ overlay)
                    @{ Offset = 0x7FA6C; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/shuman" -> "intrf_hd/shuman": campaign map script SHUMANE
                    @{ Offset = 0x7FB08; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/loadg" -> "intrf_hd/loadg": load-game screen script LOADGE
                    @{ Offset = 0x7FB4C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/wingame" -> "intrf_hd/wingame": end-of-game statistics script WINGAMEE
                    @{ Offset = 0x7FB84; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/multiwn" -> "intrf_hd/multiwn": multiplayer results script MULTIWNE
                    @{ Offset = 0x7FC1C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/intrg.dat" -> "intrf_hd/intrg.dat": main menu FIN list INTRG.DAT (INTRF_HD copy names dcuk_hd.fin, dcut_hd.fin)
                    @{ Offset = 0x7FC84; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/bintro" -> "intrf_hd/bintro": main menu script BINTROE (+ language letter e)
                    @{ Offset = 0x7FC98; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/dpblank" -> "intrf_hd/dpblank": direct-play blank screen script DPBLANKE
                    @{ Offset = 0x7FD38; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/ipxname" -> "intrf_hd/ipxname": player-name screen script IPXNAMEE
                    @{ Offset = 0x7FD4C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/dplays" -> "intrf_hd/dplays": direct-play session screen script DPLAYSE
                    @{ Offset = 0x7FD60; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/getsvr" -> "intrf_hd/getsvr": server-address screen script GETSVRE
                    @{ Offset = 0x7FD9C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/netopt" -> "intrf_hd/netopt": network options screen script NETOPTE
                    @{ Offset = 0x7FDD0; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/meta" -> "intrf_hd/meta": lobby meta screen script METAE
                    @{ Offset = 0x80830; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lost" -> "intrf_hd/lost": defeat screen script LOSTE
                    @{ Offset = 0x80940; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/multi" -> "intrf_hd/multi": multiplayer lobby script MULTIE
                    @{ Offset = 0x809E0; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/main" -> "intrf_hd/main": in-game HUD script MAINE (background intrf_hd/intrface = the rebuilt frame)
                    @{ Offset = 0x814FC; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/load.bmp" -> "intrf_hd/load.bmp": first loading screen LOAD.BMP (opened by driver.c directly)
                    @{ Offset = 0x831CC; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/load2.bmp" -> "intrf_hd/load2.bmp": second loading screen LOAD2.BMP
                    @{ Offset = 0x83274; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lsg" -> "intrf_hd/lsg": in-game save/load dialog script LSGE
                    @{ Offset = 0x83678; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lobj" -> "intrf_hd/lobj": in-game objectives dialog script LOBJE
                    @{ Offset = 0x836E8; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lqc" -> "intrf_hd/lqc": in-game quit dialog script LQCE
                    @{ Offset = 0x836F8; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lopt" -> "intrf_hd/lopt": in-game options dialog script LOPTE
                    @{ Offset = 0x83734; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                )
            }

            # ---- cursor: Windows pointer stays hidden ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_cursor.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.12
            #  Changes    : 101 bytes in 11 edits
            #  The game draws its own cursor and hides the Windows pointer with SetCursor(NULL), but two
            #  holes let the system pointer flicker back on a modern Windows: create_window never fills
            #  WNDCLASSA.hCursor (a random stack value becomes the class cursor), and the window procedure
            #  answers WM_SETCURSOR with SetCursor(NULL) and then falls through into DefWindowProcA, which
            #  restores the class cursor.  Fix: hCursor = NULL, WM_SETCURSOR returns TRUE, and a 12-byte stub
            #  in the zero tail of the code section (VA 0x47F1D0 / 0x47F230) calls SetCursor(NULL) right
            #  after ShowWindow so the pointer is gone during the loading screen too.
            #
            #  Watcom's 7-byte "call cs:[import]" instructions become 5-byte relative calls to the import
            #  thunks the linker already emitted, which frees the bytes for the new instructions without
            #  moving any code.  The .reloc entries that described the moved or removed absolute operands
            #  are updated (moved operand -> new page offset; vanished operand -> type 0 ABSOLUTE padding),
            #  so the relocation table still describes the image exactly.  The stub lives in bytes that were
            #  zero and inside the section's raw size, so the file layout is unchanged.
            @{
                Id = 'cursor'; Name = 'Windows pointer stays hidden'; Date = '10 Sep 2026'
                Tool = 'tools/patch_cursor.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.12'
                Description = @'
The game draws its own cursor and hides the Windows pointer with SetCursor(NULL), but two
holes let the system pointer flicker back on a modern Windows: create_window never fills
WNDCLASSA.hCursor (a random stack value becomes the class cursor), and the window procedure
answers WM_SETCURSOR with SetCursor(NULL) and then falls through into DefWindowProcA, which
restores the class cursor.  Fix: hCursor = NULL, WM_SETCURSOR returns TRUE, and a 12-byte stub
in the zero tail of the code section (VA 0x47F1D0 / 0x47F230) calls SetCursor(NULL) right
after ShowWindow so the pointer is gone during the loading screen too.

Watcom's 7-byte "call cs:[import]" instructions become 5-byte relative calls to the import
thunks the linker already emitted, which frees the bytes for the new instructions without
moving any code.  The .reloc entries that described the moved or removed absolute operands
are updated (moved operand -> new page offset; vanished operand -> type 0 ABSOLUTE padding),
so the relocation table still describes the image exactly.  The stub lives in bytes that were
zero and inside the section's raw size, so the file layout is unchanged.
'@
                Edits = @(
                    # wndproc WM_SETCURSOR returns TRUE
                    @{ Offset = 0x2D751; Old = '76 1B 81 FE 12 01 00 00 74 1E E9 8D 00 00 00 83 FE 02 0F 84 76 00 00 00 E9 7F 00 00 00 6A 00 2E FF 15 E0 03 48 00 EB 74'; New = '76 17 81 FE 12 01 00 00 74 1E E9 8D 00 00 00 83 FE 02 74 7A E9 83 00 00 00 6A 00 E8 7F 0C 05 00 6A 01 58 E9 85 00 00 00' }
                    # create_window hCursor = NULL
                    @{ Offset = 0x2DAAF; Old = '2E FF 15 C8 03 48 00 89 45 EC A1 20 FF 4D 00 6A 04 89 45 E8 2E FF 15 A0 03 48 00 89 45 F4 8D 45 D8 BA 14 59 48 00 50 89 5D F8 89 55 FC 2E FF 15 DC 03 48 00'; New = 'E8 F4 08 05 00 89 45 EC A1 20 FF 4D 00 6A 04 89 45 E8 E8 DC 08 05 00 89 45 F4 8D 45 D8 BA 14 59 48 00 50 89 5D F8 89 55 FC 89 5D F0 E8 BC 08 05 00 90 90 90' }
                    # create_window UpdateWindow -> stub
                    @{ Offset = 0x2DB94; Old = '2E FF 15 E8 03 48 00'; New = 'E8 37 0A 05 00 90 90' }
                    # stub SetCursor(NULL)+UpdateWindow
                    @{ Offset = 0x7E5D0; Old = '00 00 00 00 00 00 00 00 00 00 00 00'; New = '6A 00 E8 19 FE FF FF E9 AE FD FF FF' }
                    # .reloc table: entry 3373 (type 3 HIGHLOW, page offset 0x373) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99DEA; Old = '73 33'; New = '00 00' }
                    # .reloc table: entry 36B2 (type 3 HIGHLOW, page offset 0x6B2) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99E3A; Old = 'B2 36'; New = '00 00' }
                    # .reloc table: entry 36BA -> 36B8: the absolute operand moved from page offset 0x6BA to 0x6B8, entry follows it
                    @{ Offset = 0x99E3C; Old = 'BA 36'; New = 'B8 36' }
                    # .reloc table: entry 36C6 (type 3 HIGHLOW, page offset 0x6C6) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99E3E; Old = 'C6 36'; New = '00 00' }
                    # .reloc table: entry 36D1 -> 36CD: the absolute operand moved from page offset 0x6D1 to 0x6CD, entry follows it
                    @{ Offset = 0x99E40; Old = 'D1 36'; New = 'CD 36' }
                    # .reloc table: entry 36DF (type 3 HIGHLOW, page offset 0x6DF) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99E42; Old = 'DF 36'; New = '00 00' }
                    # .reloc table: entry 3797 (type 3 HIGHLOW, page offset 0x797) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99E6C; Old = '97 37'; New = '00 00' }
                )
            }

            # ---- pool: Local memory pool 11.5 MB -> 32 MiB ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_pool.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13
            #  Changes    : 4 bytes in 1 edits
            #  Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
            #  info, game state, AI, widgets) is carved from one arena created at start-up with
            #  "mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
            #  786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
            #  pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
            #  headers are 32-bit and the size check unsigned, so nothing else changes.
            @{
                Id = 'pool'; Name = 'Local memory pool 11.5 MB -> 32 MiB'; Date = '10 Sep 2026'
                Tool = 'tools/patch_pool.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13'
                Description = @'
Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
info, game state, AI, widgets) is carved from one arena created at start-up with
"mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
headers are 32-bit and the size check unsigned, so nothing else changes.
'@
                Edits = @(
                    # mov eax,imm32 before call SMalloc_Pool: pool size 11 500 000 (0x00AF79E0) -> 33 554 432 bytes (0x02000000, 32 MiB)
                    @{ Offset = 0x4734; Old = 'B8 E0 79 AF 00'; New = 'B8 00 00 00 02' }
                )
            }

            # ---- speed: Default game speed 150 % ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_speed.py --percent 150
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.14
            #  Changes    : 2 bytes in 2 edits
            #  One simulation tick runs every gs->tick_ms milliseconds.  Two stock values feed it and both
            #  must change or the game resets the speed within a second: the game-state initialiser
            #  ("mov dword ptr [esi+970h],66") and the persistent "desired tick" setting in DGROUP that the
            #  options screen and the speed negotiation read.  66 ms = 100 %, 44 ms = 150 % (the slider shows
            #  6600 / tick_ms).  Multiplayer speed comes from the server, saved games keep their own speed.
            #  Cosmetic; pick it if you like the faster default.
            @{
                Id = 'speed'; Name = 'Default game speed 150 %'; Date = '10 Sep 2026'
                Tool = 'tools/patch_speed.py --percent 150'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.14'
                Description = @'
One simulation tick runs every gs->tick_ms milliseconds.  Two stock values feed it and both
must change or the game resets the speed within a second: the game-state initialiser
("mov dword ptr [esi+970h],66") and the persistent "desired tick" setting in DGROUP that the
options screen and the speed negotiation read.  66 ms = 100 %, 44 ms = 150 % (the slider shows
6600 / tick_ms).  Multiplayer speed comes from the server, saved games keep their own speed.
Cosmetic; pick it if you like the faster default.
'@
                Edits = @(
                    # game-state initialiser: imm32 of mov dword ptr [esi+970h],imm32 (gs->tick_ms) 66 ms -> 44 ms
                    @{ Offset = 0x1B002; Old = '42 00 00 00'; New = '2C 00 00 00' }
                    # DGROUP: persistent "desired tick" settings global (4th of four settings dwords) 66 ms -> 44 ms
                    @{ Offset = 0x865EC; Old = '42 00 00 00'; New = '2C 00 00 00' }
                )
            }

            # ---- clock: Day/night clock hand re-anchored ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1024x768 patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored'; Date = '13 Sep 2026'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1024x768 patch.
'@
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 738 (0x2E2)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = 'E2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 992 (0x3E0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 03 00 00' }
                )
            }

            # ---- ddraw: Two-monitor start-up hang fixed ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_ddraw_lost.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.16
            #  Changes    : 16 bytes in 7 edits
            #  With two monitors, SetDisplayMode(1024,768,16) makes Windows re-lay out the desktop and
            #  DirectDraw marks every exclusive-mode surface lost about a second later.  The stock start-up
            #  code then asserts (palette remap: GetDC / Lock / Unlock; loading screen: Flip) into a
            #  MessageBox hidden behind the full-screen surface: black screen, apparent hang.  The four
            #  assert branches become "skip and continue": three "push format-string" instructions (5 bytes)
            #  turn into "jmp next-palette-index", and the Flip check's je becomes jmp.  The game's own
            #  per-frame restore path repairs the surfaces at the first frame.  The three push operands were
            #  absolute pointers, so their .reloc entries become type 0 ABSOLUTE padding.
            @{
                Id = 'ddraw'; Name = 'Two-monitor start-up hang fixed'; Date = '13 Sep 2026'
                Tool = 'tools/patch_ddraw_lost.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.16'
                Description = @'
With two monitors, SetDisplayMode(1024,768,16) makes Windows re-lay out the desktop and
DirectDraw marks every exclusive-mode surface lost about a second later.  The stock start-up
code then asserts (palette remap: GetDC / Lock / Unlock; loading screen: Flip) into a
MessageBox hidden behind the full-screen surface: black screen, apparent hang.  The four
assert branches become "skip and continue": three "push format-string" instructions (5 bytes)
turn into "jmp next-palette-index", and the Flip check's je becomes jmp.  The game's own
per-frame restore path repairs the surfaces at the first frame.  The three push operands were
absolute pointers, so their .reloc entries become type 0 ABSOLUTE padding.
'@
                Edits = @(
                    # loading screen: Flip failure -> continue
                    @{ Offset = 0x2E433; Old = '74 5B'; New = 'EB 5B' }
                    # remap: Unlock failure -> next index
                    @{ Offset = 0x2E794; Old = '68 F0 5A 48 00'; New = 'E9 ED 00 00 00' }
                    # remap: Lock failure -> next index
                    @{ Offset = 0x2E7F5; Old = '68 D8 56 48 00'; New = 'E9 8C 00 00 00' }
                    # remap: GetDC failure -> next index
                    @{ Offset = 0x2E83E; Old = '68 D8 56 48 00'; New = 'E9 43 00 00 00' }
                    # .reloc table: entry 3395 (type 3 HIGHLOW, page offset 0x395) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99FF4; Old = '95 33'; New = '95 03' }
                    # .reloc table: entry 33F6 (type 3 HIGHLOW, page offset 0x3F6) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A006; Old = 'F6 33'; New = 'F6 03' }
                    # .reloc table: entry 343F (type 3 HIGHLOW, page offset 0x43F) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A014; Old = '3F 34'; New = '3F 04' }
                )
            }
        )
    }
    # ---------------------------------------------------------------------------------------------
    #  Dark Colony - The Council Wars ENGEXP16.EXE (shipped as DCEXP16.EXE), 659968 bytes
    # ---------------------------------------------------------------------------------------------
    @{
        Id             = 'CouncilWars'
        Title          = 'Dark Colony - The Council Wars ENGEXP16.EXE (shipped as DCEXP16.EXE), 659968 bytes'
        OriginalName   = 'engexp16original.exe'
        OutputName     = 'DCEXP16.EXE'
        Size           = 659968
        OriginalSha256 = '3b930ba92cfd07ab4403c499d5251d604e660f4e8b092303691315e13a1737f4'   # untouched original
        PatchedSha256  = '5e4f12fd9812976f362116ab269107aa3354bfb4d927c316b7d1485e7963dbe2'   # every patch applied = the exe in the repository (14 Sep 2026)
        Patches        = @(

            # ---- cdcheck: No CD required ---------------------------------------------------------
            #  Added      : 28-30 Sep 2025
            #  Made with  : hand-patched (commits f6246e1, 314ae66 in endotermic/Dark-Colony)
            #  Documented : CLAUDE.md "Patches applied so far"
            #  Changes    : 3 bytes in 3 edits
            #  The game refuses to start, and greys out most main-menu buttons, when it cannot find its
            #  CD in a drive.  One function (VA 0x405E8C) answers "is the CD here?" with a bool in al and every
            #  caller does "test al,al ; jne ok".  Turning that conditional jump (opcode 75) into an
            #  unconditional jump (opcode EB) makes the game behave as if the disc were always present.
            #  Council Wars has a third test that runs while a game is in progress and throws the player back
            #  to the menu; that one is inverted (75 -> 74, jne -> je).
            #
            #  Nothing else changes: no code is added, no file access is redirected, one byte per site.
            @{
                Id = 'cdcheck'; Name = 'No CD required'; Date = '28-30 Sep 2025'
                Tool = 'hand-patched (commits f6246e1, 314ae66 in endotermic/Dark-Colony)'; Doc = 'CLAUDE.md "Patches applied so far"'
                Description = @'
The game refuses to start, and greys out most main-menu buttons, when it cannot find its
CD in a drive.  One function (VA 0x405E8C) answers "is the CD here?" with a bool in al and every
caller does "test al,al ; jne ok".  Turning that conditional jump (opcode 75) into an
unconditional jump (opcode EB) makes the game behave as if the disc were always present.
Council Wars has a third test that runs while a game is in progress and throws the player back
to the menu; that one is inverted (75 -> 74, jne -> je).

Nothing else changes: no code is added, no file access is redirected, one byte per site.
'@
                Edits = @(
                    # jne -> jmp right after "call 0x405E8C ; test al,al" (the CD-presence check returning a bool in al): always take the "CD present" path
                    @{ Offset = 0x431F; Old = '75'; New = 'EB' }
                    # jne -> jmp after the same CD test in the main-menu builder: the menu buttons that are greyed out without the CD stay enabled
                    @{ Offset = 0x507F; Old = '75'; New = 'EB' }
                    # jne -> je: the second CD check, run later, that threw the player out of a running game; inverted so it passes without the disc
                    @{ Offset = 0x781D9; Old = '75'; New = '74' }
                )
            }

            # ---- resolution: 1024x768 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10
            #  Changes    : 364 bytes in 165 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (20x15 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
            #    stage 1  display mode, framebuffer stride, clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at (903,6), the 31
            #             lightplane row advances, and a bigger stack frame for draw_terrain (so the PE
            #             header's SizeOfStackReserve / SizeOfStackCommit go up as well - the two edits at
            #             file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,96)-(1024,672) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the rebuilt 1024x768 interface data that ships in the repository next to the exe -
            #  since 14 Sep 2026 in the INTRF_HD/ folder, read through the "Interface data from INTRF_HD"
            #  patch below (select both); with stock 640x480 data the menus draw in the top-left corner.
            @{
                Id = 'resolution'; Name = '1024x768 display'; Date = '9 Sep 2026'
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (20x15 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
  stage 1  display mode, framebuffer stride, clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at (903,6), the 31
           lightplane row advances, and a bigger stack frame for draw_terrain (so the PE
           header's SizeOfStackReserve / SizeOfStackCommit go up as well - the two edits at
           file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,96)-(1024,672) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the rebuilt 1024x768 interface data that ships in the repository next to the exe -
since 14 Sep 2026 in the INTRF_HD/ folder, read through the "Interface data from INTRF_HD"
patch below (select both); with stock 640x480 data the menus draw in the top-left corner.
'@
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 03 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 FF 02 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA CA 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA D4 00 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB FA 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 9D 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA EF 01 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 64 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA F6 01 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB AA 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA E2 00 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 4E 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA DD 00 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA DD 02 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA DD 02 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB AF 01 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA 74 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5040; Old = 'BB 18 00 00 00'; New = 'BB A8 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5051; Old = 'BA 50 01 00 00'; New = 'BA 10 02 00 00' }
                    # release_surfaces: release the movie surface whenever it exists
                    @{ Offset = 0x6490; Old = '75 18'; New = '90 90' }
                    # avi_create_surfaces: after GetAttachedSurface, mov edx,eax; jmp 4071E0 (edx=0 -> create the 320x180 surface; else return 0)
                    @{ Offset = 0x658E; Old = '85 C0 0F 84 55 01 00 00 E9 71 02 00 00'; New = '89 C2 E9 AB 00 00 00 90 90 90 90 90 90' }
                    # avi_create_surfaces: keep the flip flag when creating the movie surface
                    @{ Offset = 0x669D; Old = '89 1D 34 8E 48 00'; New = '90 90 90 90 90 90' }
                    # movie clear: cmp eax,[ebp-60h] (dwWidth from the Lock)
                    @{ Offset = 0x6854; Old = '3D 80 02 00 00'; New = '3B 45 A0 90 90' }
                    # movie clear: add ecx,[ebp-5Ch] (lPitch from the Lock)
                    @{ Offset = 0x6865; Old = '81 C1 00 05 00 00'; New = '03 4D A4 90 90 90' }
                    # movie clear: cmp edx,[ebp-64h] (dwHeight from the Lock)
                    @{ Offset = 0x686B; Old = '81 FA E0 01 00 00'; New = '3B 55 9C 90 90 90' }
                    # clear_and_flip: also clear the movie surface in flip mode
                    @{ Offset = 0x68D9; Old = 'E9 D4 00 00 00'; New = '90 90 90 90 90' }
                    # draw_offscreen: draw all H rows, not H-1 (jae -> ja)
                    @{ Offset = 0x6D7B; Old = '0F 83'; New = '0F 87' }
                    # draw_offscreen: BltFast -> stretching Blt(primary, dest rect, movie surface)
                    @{ Offset = 0x7274; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 40 97 48 00 89 55 5A 8D 55 52 8B 1D 28 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 60 00 00 00 C7 45 6A 00 04 00 00 C7 45 6E A0 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 28 8E 48 00 8D 55 62 52 A1 40 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F9E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x94E4; Old = '2D 07 02 00 00'; New = '2D 87 03 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F6A; Old = '6A 0E'; New = '6A 17' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F6C; Old = 'B9 10 00 00 00'; New = 'B9 1C 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F7C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0B 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F8B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 0E 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA51C; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0B 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA540; Old = '81 EA 00 08 00 00'; New = '81 EA 00 0E 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E17E; Old = 'B9 C0 01 00 00'; New = 'B9 E0 02 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E183; Old = 'BB 00 02 00 00'; New = 'BB 80 03 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E2A3; Old = 'B8 07 02 00 00'; New = 'B8 87 03 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E2C6; Old = 'B9 00 08 00 00'; New = 'B9 00 0E 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E2CF; Old = 'BB 00 07 00 00'; New = 'BB 80 0B 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B5F4; Old = 'BB 80 02 00 00'; New = 'BB 00 04 00 00' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B673; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640 -> y*W: shl edx
                    @{ Offset = 0x2B678; Old = 'C1 E2 07'; New = 'C1 E2 08' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B6C1; Old = 'BA 80 02 00 00'; New = 'BA 00 04 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B7A7; Old = 'BB 80 02 00 00'; New = 'BB 00 04 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B7C3; Old = 'B9 E0 01 00 00'; New = 'B9 00 03 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D632; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D65F; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D66E; Old = 'B8 E0 01 00 00'; New = 'B8 00 03 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D679; Old = 'B8 E0 01 00 00'; New = 'B8 00 03 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DC24; Old = 'BA 40 01 00 00'; New = 'BA 00 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DC29; Old = 'B9 F0 00 00 00'; New = 'B9 80 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DCF8; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DD02; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD7C; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD86; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DEE9; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DEEE; Old = 'BA E0 01 00 00'; New = 'BA 00 03 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E367; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E36C; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E398; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E39D; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E44D; Old = '68 E0 01 00 00'; New = '68 00 03 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E452; Old = '68 80 02 00 00'; New = '68 00 04 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EC0D; Old = '3D 00 B0 04 00'; New = '3D 00 00 0C 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EC42; Old = '3D 00 B0 04 00'; New = '3D 00 00 0C 00' }
                    # visible tiles down
                    @{ Offset = 0x352A7; Old = 'B9 0E 00 00 00'; New = 'B9 17 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x352AC; Old = '8D 50 F2'; New = '8D 50 E9' }
                    # visible tiles across
                    @{ Offset = 0x352AF; Old = 'BB 10 00 00 00'; New = 'BB 1C 00 00 00' }
                    # viewport width
                    @{ Offset = 0x353A6; Old = 'BA 00 02 00 00'; New = 'BA 80 03 00 00' }
                    # viewport height
                    @{ Offset = 0x353C1; Old = 'BB C0 01 00 00'; New = 'BB E0 02 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x353E8; Old = 'BA 00 70 00 00'; New = 'BA 00 42 01 00' }
                    # render destination stride
                    @{ Offset = 0x353FF; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # engmain.c y*1280: neutralise add eax,edi
                    @{ Offset = 0x35519; Old = '01 F8'; New = '89 C0' }
                    # engmain.c y*1280 -> y*W*2: shl eax
                    @{ Offset = 0x3551E; Old = 'C1 E0 08'; New = 'C1 E0 09' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x3581D; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640 -> y*W: shl eax
                    @{ Offset = 0x35825; Old = 'C1 E0 07'; New = 'C1 E0 08' }
                    # minimap stride (a)
                    @{ Offset = 0x394FB; Old = 'B8 80 02 00 00'; New = 'B8 00 04 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x3950F; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 37 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x39644; Old = 'B8 07 02 00 00'; New = 'B8 87 03 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x396DA; Old = '05 07 02 00 00'; New = '05 87 03 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x398BB; Old = 'BA 80 02 00 00'; New = 'BA 00 04 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x398E4; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 37 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x502A7; Old = '81 FE 80 02 00 00'; New = '81 FE 00 04 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x502AF; Old = 'BE 7F 02 00 00'; New = 'BE FF 03 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x502BC; Old = '81 FF E0 01 00 00'; New = '81 FF 00 03 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x502C4; Old = 'BF DF 01 00 00'; New = 'BF FF 02 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x503A6; Old = '3D 7F 02 00 00'; New = '3D FF 03 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x503AD; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 03 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x503CB; Old = '81 FE DF 01 00 00'; New = '81 FE FF 02 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x503D3; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 FF 02 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D75; Old = '81 EC CC 14 00 00'; New = '81 EC 3C 1C 00 00' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F80; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 46 E4 FF FF' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52FDA; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E 3E E4 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52FE1; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F 3E E4 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52FE8; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 46 E4 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52FF1; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 46 E4 FF FF' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x53013; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 42 E4 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53065; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A 3A E4 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5308D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 3A E4 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5309C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 42 E4 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x530BD; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 42 E4 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x5312B; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x53152; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53175; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x531C2; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x531EE; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x53229; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x5325C; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53286; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x532B8; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x532F3; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x53326; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x53359; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53384; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x533C1; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x533F4; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x53427; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x5345A; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5348D; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x534B7; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x534F2; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x53514; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x53556; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53589; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x535A5; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x535EF; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x53622; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x53655; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53688; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x536BB; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x536D6; Old = '05 00 02 00 00'; New = '05 80 03 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x5371C; Old = '8D B8 00 02 00 00'; New = '8D B8 80 03 00 00' }
                    # screen width global
                    @{ Offset = 0x867DC; Old = '80 02 00 00'; New = '00 04 00 00' }
                    # screen height global
                    @{ Offset = 0x867E0; Old = 'E0 01 00 00'; New = '00 03 00 00' }
                )
            }

            # ---- hdpaths: Interface data from INTRF_HD (1024x768 files renamed) ---------------------------------------------------------
            #  Added      : 14 Sep 2026
            #  Made with  : tools/patch_hd_paths.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17
            #  Changes    : 120 bytes in 30 edits
            #  The 1024x768 menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
            #  used to replace the stock files under their stock names, so the untouched original exe could no
            #  longer run from the same folder.  They now live under their stock names in INTRF_HD/ (Council Wars
            #  also exp/intrf_hd/ and ozi_ns/intrf_hd/), the stock 640x480 files are back in INTRFACE/ and
            #  GAMESTAT/, and the re-baked logo animations are SPRITES/DCSS_HD.SPR, DCUK_HD.SPR, DCUT_HD.SPR with
            #  matching ANIMATE/*_HD.FIN.  The game opens each of those files through a literal path in the data
            #  section ("intrface/bintro" plus the language letter, "gamestat/hscene" plus ".txt", ...), so this
            #  patch rewrites the 8-byte directory part of exactly the 30 strings whose files were rebuilt:
            #  "intrface" / "gamestat" -> "intrf_hd", same length, in place.  Fonts, text files, per-screen
            #  sprite lists without logo banks and every other file keep their stock path and single copy; the two
            #  lists that do name logo banks (INTRG.DAT, INTRO.DAT) are redirected to INTRF_HD copies that say
            #  dcuk_hd.fin etc.  No code changes.  With this patch dc16original1998.exe / engexp16original.exe
            #  (stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
            #  meaningful together with the 1024x768 patch, and REQUIRES the INTRF_HD/ folder from the repository.
            @{
                Id = 'hdpaths'; Name = 'Interface data from INTRF_HD (1024x768 files renamed)'; Date = '14 Sep 2026'
                Tool = 'tools/patch_hd_paths.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17'
                Description = @'
The 1024x768 menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
used to replace the stock files under their stock names, so the untouched original exe could no
longer run from the same folder.  They now live under their stock names in INTRF_HD/ (Council Wars
also exp/intrf_hd/ and ozi_ns/intrf_hd/), the stock 640x480 files are back in INTRFACE/ and
GAMESTAT/, and the re-baked logo animations are SPRITES/DCSS_HD.SPR, DCUK_HD.SPR, DCUT_HD.SPR with
matching ANIMATE/*_HD.FIN.  The game opens each of those files through a literal path in the data
section ("intrface/bintro" plus the language letter, "gamestat/hscene" plus ".txt", ...), so this
patch rewrites the 8-byte directory part of exactly the 30 strings whose files were rebuilt:
"intrface" / "gamestat" -> "intrf_hd", same length, in place.  Fonts, text files, per-screen
sprite lists without logo banks and every other file keep their stock path and single copy; the two
lists that do name logo banks (INTRG.DAT, INTRO.DAT) are redirected to INTRF_HD copies that say
dcuk_hd.fin etc.  No code changes.  With this patch dc16original1998.exe / engexp16original.exe
(stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
meaningful together with the 1024x768 patch, and REQUIRES the INTRF_HD/ folder from the repository.
'@
                Edits = @(
                    # DGROUP string "intrface/newgame" -> "intrf_hd/newgame": new-game / mission-selection script NEWGAMEE
                    @{ Offset = 0x7FB30; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/story" -> "intrf_hd/story": story screen script STORYE
                    @{ Offset = 0x7FB4C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/encyclo" -> "intrf_hd/encyclo": encyclopedia screen script ENCYCLOE
                    @{ Offset = 0x7FBAC; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/hscene" -> "intrf_hd/hscene": human campaign briefing list HSCENE.TXT (letterboxed globe markers)
                    @{ Offset = 0x7FC10; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gscene" -> "intrf_hd/gscene": alien campaign briefing list GSCENE.TXT
                    @{ Offset = 0x7FC20; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/htscene" -> "intrf_hd/htscene": human training briefing list HTSCENE.TXT
                    @{ Offset = 0x7FC30; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gtscene" -> "intrf_hd/gtscene": alien training briefing list GTSCENE.TXT
                    @{ Offset = 0x7FC44; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/hxscene" -> "intrf_hd/hxscene": Council Wars human campaign briefing list HXSCENE.TXT (exp/ overlay)
                    @{ Offset = 0x7FC58; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "gamestat/gxscene" -> "intrf_hd/gxscene": Council Wars alien campaign briefing list GXSCENE.TXT (exp/ overlay)
                    @{ Offset = 0x7FC6C; Old = '67 61 6D 65 73 74 61 74'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/shuman" -> "intrf_hd/shuman": campaign map script SHUMANE
                    @{ Offset = 0x7FD08; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/loadg" -> "intrf_hd/loadg": load-game screen script LOADGE
                    @{ Offset = 0x7FD4C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/wingame" -> "intrf_hd/wingame": end-of-game statistics script WINGAMEE
                    @{ Offset = 0x7FD84; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/multiwn" -> "intrf_hd/multiwn": multiplayer results script MULTIWNE
                    @{ Offset = 0x7FE1C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/intrg.dat" -> "intrf_hd/intrg.dat": main menu FIN list INTRG.DAT (INTRF_HD copy names dcuk_hd.fin, dcut_hd.fin)
                    @{ Offset = 0x7FE84; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/bintro" -> "intrf_hd/bintro": main menu script BINTROE (+ language letter e)
                    @{ Offset = 0x7FE98; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/dpblank" -> "intrf_hd/dpblank": direct-play blank screen script DPBLANKE
                    @{ Offset = 0x7FF38; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/ipxname" -> "intrf_hd/ipxname": player-name screen script IPXNAMEE
                    @{ Offset = 0x7FF4C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/dplays" -> "intrf_hd/dplays": direct-play session screen script DPLAYSE
                    @{ Offset = 0x7FF60; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/getsvr" -> "intrf_hd/getsvr": server-address screen script GETSVRE
                    @{ Offset = 0x7FF9C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/netopt" -> "intrf_hd/netopt": network options screen script NETOPTE
                    @{ Offset = 0x7FFD0; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/meta" -> "intrf_hd/meta": lobby meta screen script METAE
                    @{ Offset = 0x80A38; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lost" -> "intrf_hd/lost": defeat screen script LOSTE
                    @{ Offset = 0x80B48; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/multi" -> "intrf_hd/multi": multiplayer lobby script MULTIE
                    @{ Offset = 0x80BE8; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/main" -> "intrf_hd/main": in-game HUD script MAINE (background intrf_hd/intrface = the rebuilt frame)
                    @{ Offset = 0x81704; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/load.bmp" -> "intrf_hd/load.bmp": first loading screen LOAD.BMP (opened by driver.c directly)
                    @{ Offset = 0x833D4; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/load2.bmp" -> "intrf_hd/load2.bmp": second loading screen LOAD2.BMP
                    @{ Offset = 0x8347C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lsg" -> "intrf_hd/lsg": in-game save/load dialog script LSGE
                    @{ Offset = 0x83880; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lobj" -> "intrf_hd/lobj": in-game objectives dialog script LOBJE
                    @{ Offset = 0x838F0; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lqc" -> "intrf_hd/lqc": in-game quit dialog script LQCE
                    @{ Offset = 0x83900; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                    # DGROUP string "intrface/lopt" -> "intrf_hd/lopt": in-game options dialog script LOPTE
                    @{ Offset = 0x8393C; Old = '69 6E 74 72 66 61 63 65'; New = '69 6E 74 72 66 5F 68 64' }
                )
            }

            # ---- cursor: Windows pointer stays hidden ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_cursor.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.12
            #  Changes    : 101 bytes in 11 edits
            #  The game draws its own cursor and hides the Windows pointer with SetCursor(NULL), but two
            #  holes let the system pointer flicker back on a modern Windows: create_window never fills
            #  WNDCLASSA.hCursor (a random stack value becomes the class cursor), and the window procedure
            #  answers WM_SETCURSOR with SetCursor(NULL) and then falls through into DefWindowProcA, which
            #  restores the class cursor.  Fix: hCursor = NULL, WM_SETCURSOR returns TRUE, and a 12-byte stub
            #  in the zero tail of the code section (VA 0x47F1D0 / 0x47F230) calls SetCursor(NULL) right
            #  after ShowWindow so the pointer is gone during the loading screen too.
            #
            #  Watcom's 7-byte "call cs:[import]" instructions become 5-byte relative calls to the import
            #  thunks the linker already emitted, which frees the bytes for the new instructions without
            #  moving any code.  The .reloc entries that described the moved or removed absolute operands
            #  are updated (moved operand -> new page offset; vanished operand -> type 0 ABSOLUTE padding),
            #  so the relocation table still describes the image exactly.  The stub lives in bytes that were
            #  zero and inside the section's raw size, so the file layout is unchanged.
            @{
                Id = 'cursor'; Name = 'Windows pointer stays hidden'; Date = '10 Sep 2026'
                Tool = 'tools/patch_cursor.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.12'
                Description = @'
The game draws its own cursor and hides the Windows pointer with SetCursor(NULL), but two
holes let the system pointer flicker back on a modern Windows: create_window never fills
WNDCLASSA.hCursor (a random stack value becomes the class cursor), and the window procedure
answers WM_SETCURSOR with SetCursor(NULL) and then falls through into DefWindowProcA, which
restores the class cursor.  Fix: hCursor = NULL, WM_SETCURSOR returns TRUE, and a 12-byte stub
in the zero tail of the code section (VA 0x47F1D0 / 0x47F230) calls SetCursor(NULL) right
after ShowWindow so the pointer is gone during the loading screen too.

Watcom's 7-byte "call cs:[import]" instructions become 5-byte relative calls to the import
thunks the linker already emitted, which frees the bytes for the new instructions without
moving any code.  The .reloc entries that described the moved or removed absolute operands
are updated (moved operand -> new page offset; vanished operand -> type 0 ABSOLUTE padding),
so the relocation table still describes the image exactly.  The stub lives in bytes that were
zero and inside the section's raw size, so the file layout is unchanged.
'@
                Edits = @(
                    # wndproc WM_SETCURSOR returns TRUE
                    @{ Offset = 0x2D7B1; Old = '76 1B 81 FE 12 01 00 00 74 1E E9 8D 00 00 00 83 FE 02 0F 84 76 00 00 00 E9 7F 00 00 00 6A 00 2E FF 15 E0 03 48 00 EB 74'; New = '76 17 81 FE 12 01 00 00 74 1E E9 8D 00 00 00 83 FE 02 74 7A E9 83 00 00 00 6A 00 E8 7F 0C 05 00 6A 01 58 E9 85 00 00 00' }
                    # create_window hCursor = NULL
                    @{ Offset = 0x2DB0F; Old = '2E FF 15 C8 03 48 00 89 45 EC A1 20 FF 4D 00 6A 04 89 45 E8 2E FF 15 A0 03 48 00 89 45 F4 8D 45 D8 BA 1C 59 48 00 50 89 5D F8 89 55 FC 2E FF 15 DC 03 48 00'; New = 'E8 F4 08 05 00 89 45 EC A1 20 FF 4D 00 6A 04 89 45 E8 E8 DC 08 05 00 89 45 F4 8D 45 D8 BA 1C 59 48 00 50 89 5D F8 89 55 FC 89 5D F0 E8 BC 08 05 00 90 90 90' }
                    # create_window UpdateWindow -> stub
                    @{ Offset = 0x2DBF4; Old = '2E FF 15 E8 03 48 00'; New = 'E8 37 0A 05 00 90 90' }
                    # stub SetCursor(NULL)+UpdateWindow
                    @{ Offset = 0x7E630; Old = '00 00 00 00 00 00 00 00 00 00 00 00'; New = '6A 00 E8 19 FE FF FF E9 AE FD FF FF' }
                    # .reloc table: entry 33D3 (type 3 HIGHLOW, page offset 0x3D3) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x99FE4; Old = 'D3 33'; New = '00 00' }
                    # .reloc table: entry 3712 (type 3 HIGHLOW, page offset 0x712) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A034; Old = '12 37'; New = '00 00' }
                    # .reloc table: entry 371A -> 3718: the absolute operand moved from page offset 0x71A to 0x718, entry follows it
                    @{ Offset = 0x9A036; Old = '1A 37'; New = '18 37' }
                    # .reloc table: entry 3726 (type 3 HIGHLOW, page offset 0x726) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A038; Old = '26 37'; New = '00 00' }
                    # .reloc table: entry 3731 -> 372D: the absolute operand moved from page offset 0x731 to 0x72D, entry follows it
                    @{ Offset = 0x9A03A; Old = '31 37'; New = '2D 37' }
                    # .reloc table: entry 373F (type 3 HIGHLOW, page offset 0x73F) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A03C; Old = '3F 37'; New = '00 00' }
                    # .reloc table: entry 37F7 (type 3 HIGHLOW, page offset 0x7F7) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A066; Old = 'F7 37'; New = '00 00' }
                )
            }

            # ---- pool: Local memory pool 11.5 MB -> 32 MiB ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_pool.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13
            #  Changes    : 4 bytes in 1 edits
            #  Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
            #  info, game state, AI, widgets) is carved from one arena created at start-up with
            #  "mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
            #  786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
            #  pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
            #  headers are 32-bit and the size check unsigned, so nothing else changes.
            @{
                Id = 'pool'; Name = 'Local memory pool 11.5 MB -> 32 MiB'; Date = '10 Sep 2026'
                Tool = 'tools/patch_pool.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13'
                Description = @'
Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
info, game state, AI, widgets) is carved from one arena created at start-up with
"mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
headers are 32-bit and the size check unsigned, so nothing else changes.
'@
                Edits = @(
                    # mov eax,imm32 before call SMalloc_Pool: pool size 11 500 000 (0x00AF79E0) -> 33 554 432 bytes (0x02000000, 32 MiB)
                    @{ Offset = 0x4719; Old = 'B8 E0 79 AF 00'; New = 'B8 00 00 00 02' }
                )
            }

            # ---- speed: Default game speed 150 % ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_speed.py --percent 150
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.14
            #  Changes    : 2 bytes in 2 edits
            #  One simulation tick runs every gs->tick_ms milliseconds.  Two stock values feed it and both
            #  must change or the game resets the speed within a second: the game-state initialiser
            #  ("mov dword ptr [esi+970h],66") and the persistent "desired tick" setting in DGROUP that the
            #  options screen and the speed negotiation read.  66 ms = 100 %, 44 ms = 150 % (the slider shows
            #  6600 / tick_ms).  Multiplayer speed comes from the server, saved games keep their own speed.
            #  Cosmetic; pick it if you like the faster default.
            @{
                Id = 'speed'; Name = 'Default game speed 150 %'; Date = '10 Sep 2026'
                Tool = 'tools/patch_speed.py --percent 150'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.14'
                Description = @'
One simulation tick runs every gs->tick_ms milliseconds.  Two stock values feed it and both
must change or the game resets the speed within a second: the game-state initialiser
("mov dword ptr [esi+970h],66") and the persistent "desired tick" setting in DGROUP that the
options screen and the speed negotiation read.  66 ms = 100 %, 44 ms = 150 % (the slider shows
6600 / tick_ms).  Multiplayer speed comes from the server, saved games keep their own speed.
Cosmetic; pick it if you like the faster default.
'@
                Edits = @(
                    # game-state initialiser: imm32 of mov dword ptr [esi+970h],imm32 (gs->tick_ms) 66 ms -> 44 ms
                    @{ Offset = 0x1B062; Old = '42 00 00 00'; New = '2C 00 00 00' }
                    # DGROUP: persistent "desired tick" settings global (4th of four settings dwords) 66 ms -> 44 ms
                    @{ Offset = 0x86814; Old = '42 00 00 00'; New = '2C 00 00 00' }
                )
            }

            # ---- clock: Day/night clock hand re-anchored ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1024x768 patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored'; Date = '13 Sep 2026'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1024x768 patch.
'@
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 738 (0x2E2)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = 'E2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 992 (0x3E0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 03 00 00' }
                )
            }

            # ---- ddraw: Two-monitor start-up hang fixed ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_ddraw_lost.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.16
            #  Changes    : 16 bytes in 7 edits
            #  With two monitors, SetDisplayMode(1024,768,16) makes Windows re-lay out the desktop and
            #  DirectDraw marks every exclusive-mode surface lost about a second later.  The stock start-up
            #  code then asserts (palette remap: GetDC / Lock / Unlock; loading screen: Flip) into a
            #  MessageBox hidden behind the full-screen surface: black screen, apparent hang.  The four
            #  assert branches become "skip and continue": three "push format-string" instructions (5 bytes)
            #  turn into "jmp next-palette-index", and the Flip check's je becomes jmp.  The game's own
            #  per-frame restore path repairs the surfaces at the first frame.  The three push operands were
            #  absolute pointers, so their .reloc entries become type 0 ABSOLUTE padding.
            @{
                Id = 'ddraw'; Name = 'Two-monitor start-up hang fixed'; Date = '13 Sep 2026'
                Tool = 'tools/patch_ddraw_lost.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.16'
                Description = @'
With two monitors, SetDisplayMode(1024,768,16) makes Windows re-lay out the desktop and
DirectDraw marks every exclusive-mode surface lost about a second later.  The stock start-up
code then asserts (palette remap: GetDC / Lock / Unlock; loading screen: Flip) into a
MessageBox hidden behind the full-screen surface: black screen, apparent hang.  The four
assert branches become "skip and continue": three "push format-string" instructions (5 bytes)
turn into "jmp next-palette-index", and the Flip check's je becomes jmp.  The game's own
per-frame restore path repairs the surfaces at the first frame.  The three push operands were
absolute pointers, so their .reloc entries become type 0 ABSOLUTE padding.
'@
                Edits = @(
                    # loading screen: Flip failure -> continue
                    @{ Offset = 0x2E493; Old = '74 5B'; New = 'EB 5B' }
                    # remap: Unlock failure -> next index
                    @{ Offset = 0x2E7F4; Old = '68 F8 5A 48 00'; New = 'E9 ED 00 00 00' }
                    # remap: Lock failure -> next index
                    @{ Offset = 0x2E855; Old = '68 E0 56 48 00'; New = 'E9 8C 00 00 00' }
                    # remap: GetDC failure -> next index
                    @{ Offset = 0x2E89E; Old = '68 E0 56 48 00'; New = 'E9 43 00 00 00' }
                    # .reloc table: entry 33F5 (type 3 HIGHLOW, page offset 0x3F5) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A1F0; Old = 'F5 33'; New = 'F5 03' }
                    # .reloc table: entry 3456 (type 3 HIGHLOW, page offset 0x456) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A202; Old = '56 34'; New = '56 04' }
                    # .reloc table: entry 349F (type 3 HIGHLOW, page offset 0x49F) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9A210; Old = '9F 34'; New = '9F 04' }
                )
            }

            # ---- ozi: OZI MISSIONS menu mode (Council Wars only) ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_ozi_menu.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13
            #  Changes    : 3292 bytes in 15 edits
            #  Council Wars opens every data file through one helper that prefixes the name with the
            #  8-byte string at DGROUP 0x4826D0 ("exp/"); the wave loader has its own copy and the save
            #  folder name "esave" sits in two more slots.  A campaign *mode* is therefore the content of
            #  those four writable slots.  This patch turns the unused PLAY INTRO button into OZI MISSIONS
            #  and SINGLE PLAYER WAR into OZI LOAD, so the 2010 ozi_ns mission pack (22 missions) plays from
            #  the main menu:
            #    * the PLAY INTRO handler body (96 bytes) becomes: set the two campaign flags, call
            #      stub_pack (writes "ozi_ns/" / "ozisave" into the four slots), enter the campaign runner;
            #      the rest is NOP padding
            #    * NEW CAMPAIGN / TRAINING / LOAD GAME go through trampolines that first write the Council
            #      Wars strings back ("exp/" / "esave"), OZI LOAD through one that writes the pack strings
            #    * the two 73-byte stubs and three 10-byte trampolines live in the zero tail of the code
            #      section (VA 0x47F240..0x47F30A) - bytes that were zero and already inside the section
            #    * the eight "mov edi,imm32" slot addresses in the stubs are absolute, so eight HIGHLOW
            #      entries are appended to the .reloc block of page 0x7F000: 16 bytes inserted, the block's
            #      size field and the PE base-relocation directory size grow by 16, and 16 zero bytes of
            #      slack at the end of the .reloc section are dropped so the file size stays the same.  The
            #      two absolute operands that vanished with the old PLAY INTRO body become type 0 padding.
            #    * the start-up animation list is opened as "animozi.dat" instead of "anim.dat" (one 12-byte
            #      string in the data section): exp/animozi.dat is the stock list plus the pack's three new
            #      units and its transport as "tranozi", so the stock exp/anim.dat, tran.fin and tran.spr that
            #      the original exe reads stay untouched.
            #  REQUIRES the "DC - Council wars/ozi_ns/" overlay folder, exp/animozi.dat, exp/animate/tranozi.fin,
            #  exp/sprites/tranozi.spr and the rewritten main-menu script (exp/intrf_hd/bintroe) from the
            #  repository.  Because the .reloc insert shifts every later relocation entry, this patch is always
            #  applied last.
            @{
                Id = 'ozi'; Name = 'OZI MISSIONS menu mode (Council Wars only)'; Date = '10 Sep 2026'
                Tool = 'tools/patch_ozi_menu.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13'
                Description = @'
Council Wars opens every data file through one helper that prefixes the name with the
8-byte string at DGROUP 0x4826D0 ("exp/"); the wave loader has its own copy and the save
folder name "esave" sits in two more slots.  A campaign *mode* is therefore the content of
those four writable slots.  This patch turns the unused PLAY INTRO button into OZI MISSIONS
and SINGLE PLAYER WAR into OZI LOAD, so the 2010 ozi_ns mission pack (22 missions) plays from
the main menu:
  * the PLAY INTRO handler body (96 bytes) becomes: set the two campaign flags, call
    stub_pack (writes "ozi_ns/" / "ozisave" into the four slots), enter the campaign runner;
    the rest is NOP padding
  * NEW CAMPAIGN / TRAINING / LOAD GAME go through trampolines that first write the Council
    Wars strings back ("exp/" / "esave"), OZI LOAD through one that writes the pack strings
  * the two 73-byte stubs and three 10-byte trampolines live in the zero tail of the code
    section (VA 0x47F240..0x47F30A) - bytes that were zero and already inside the section
  * the eight "mov edi,imm32" slot addresses in the stubs are absolute, so eight HIGHLOW
    entries are appended to the .reloc block of page 0x7F000: 16 bytes inserted, the block's
    size field and the PE base-relocation directory size grow by 16, and 16 zero bytes of
    slack at the end of the .reloc section are dropped so the file size stays the same.  The
    two absolute operands that vanished with the old PLAY INTRO body become type 0 padding.
  * the start-up animation list is opened as "animozi.dat" instead of "anim.dat" (one 12-byte
    string in the data section): exp/animozi.dat is the stock list plus the pack's three new
    units and its transport as "tranozi", so the stock exp/anim.dat, tran.fin and tran.spr that
    the original exe reads stay untouched.
REQUIRES the "DC - Council wars/ozi_ns/" overlay folder, exp/animozi.dat, exp/animate/tranozi.fin,
exp/sprites/tranozi.spr and the rewritten main-menu script (exp/intrf_hd/bintroe) from the
repository.  Because the .reloc insert shifts every later relocation entry, this patch is always
applied last.
'@
                Edits = @(
                    # PE optional header: base-relocation directory size 0x93CC -> 0x93DC (+16)
                    @{ Offset = 0x124; Old = 'CC 93 00 00'; New = 'DC 93 00 00' }
                    # NEW CAMPAIGN/TRAINING call -> tramp_cw_campaign
                    @{ Offset = 0x4465; Old = 'E8 9E CB FF FF'; New = 'E8 76 A2 07 00' }
                    # NEW CAMPAIGN/TRAINING call -> tramp_cw_campaign
                    @{ Offset = 0x4483; Old = 'E8 80 CB FF FF'; New = 'E8 58 A2 07 00' }
                    # OZI LOAD (was SINGLE PLAYER WAR) call -> tramp_pack_load
                    @{ Offset = 0x44AB; Old = 'E8 34 0A 00 00'; New = 'E8 50 A2 07 00' }
                    # LOAD GAME call -> tramp_cw_load
                    @{ Offset = 0x44BF; Old = 'E8 E0 E9 FF FF'; New = 'E8 2C A2 07 00' }
                    # OZI MISSIONS handler (was PLAY INTRO)
                    @{ Offset = 0x44DD; Old = 'BE F2 46 4A 00 8D BD F0 FE FF FF 57 8A 06 88 07 3C 00 74 10 8A 46 01 83 C6 02 88 47 01 83 C7 02 3C 00 75 E8 5F BE A8 24 48 00 8D BD F0 FE FF FF 8D 95 F0 FE FF FF 57 2B C9 49 B0 00 F2 AE 4F 8A 06 88 07 3C 00 74 10 8A 46 01 83 C6 02 88 47 01 83 C7 02 3C 00 75 E8 5F 8B 45 FC E8 EB BE FF FF'; New = 'C7 80 F4 14 00 00 01 00 00 00 C7 80 F0 14 00 00 00 00 00 00 89 C2 8B 45 FC E8 45 A1 07 00 E8 08 CB FF FF EB 3B 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90' }
                    # stub_pack (pack strings into the 4 slots)
                    @{ Offset = 0x7E640; Old = '00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'; New = '50 57 BF D0 26 48 00 B8 6F 7A 69 5F AB B8 6E 73 2F 00 AB BF C8 7D 48 00 B8 6F 7A 69 5F AB B8 6E 73 2F 00 AB BF 44 23 48 00 B8 6F 7A 69 73 AB B8 61 76 65 00 AB BF 5C 5E 48 00 B8 6F 7A 69 73 AB B8 61 76 65 00 AB 5F 58 C3' }
                    # stub_cw_set (Council Wars strings)
                    @{ Offset = 0x7E690; Old = '00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'; New = '50 57 BF D0 26 48 00 B8 65 78 70 2F AB B8 00 00 00 00 AB BF C8 7D 48 00 B8 65 78 70 2F AB B8 00 00 00 00 AB BF 44 23 48 00 B8 65 73 61 76 AB B8 65 00 00 00 AB BF 5C 5E 48 00 B8 65 73 61 76 AB B8 65 00 00 00 AB 5F 58 C3 00 00 00 00' }
                    # tramp_cw_campaign (stub_cw_set; jmp 401C08)
                    @{ Offset = 0x7E6E0; Old = '00 00 00 00 00 00 00 00 00 00'; New = 'E8 AB FF FF FF E9 1E 29 F8 FF' }
                    # tramp_cw_load (stub_cw_set; jmp 403AA4)
                    @{ Offset = 0x7E6F0; Old = '00 00 00 00 00 00 00 00 00 00'; New = 'E8 9B FF FF FF E9 AA 47 F8 FF' }
                    # tramp_pack_load (stub_pack; jmp 403AA4)
                    @{ Offset = 0x7E700; Old = '00 00 00 00 00 00 00 00 00 00'; New = 'E8 3B FF FF FF E9 9A 47 F8 FF' }
                    # start-up animation list "anim.dat" -> "animozi.dat" (exp/animozi.dat = stock list + pack units)
                    @{ Offset = 0x7FEB8; Old = '61 6E 69 6D 2E 64 61 74 00 00 00 00'; New = '61 6E 69 6D 6F 7A 69 2E 64 61 74 00' }
                    # .reloc table, page-0x5000 block: entries 30DE, 3103 -> 0000 (the absolute operands of the removed PLAY INTRO body at VA 0x4050DE / 0x405103 no longer exist; type 0 ABSOLUTE padding)
                    @{ Offset = 0x97BE0; Old = 'DE 30 03 31'; New = '00 00 00 00' }
                    # .reloc block for page 0x7F000 (header at 0xA002C): SizeOfBlock 0xC0 -> 0xD0
                    @{ Offset = 0xA0030; Old = 'C0 00 00 00'; New = 'D0 00 00 00' }
                    # .reloc table: insert 8 HIGHLOW entries (3243, 3254, 3265, 3276, 3293, 32A4, 32B5, 32C6) at the end of the page-0x7F000 block; bytes 0xA00EC..0xA0DF0 move up by 16, the 16 zero slack bytes 0xA0DF0..0xA0E00 at the end of the section are dropped
                    @{ Insert = 0xA00EC; Bytes = '43 32 54 32 65 32 76 32 93 32 A4 32 B5 32 C6 32'; Before = '00 80 08 00 48 00 00 00 E8 3D EC 3D F0 3D F4 3D'; SectionEnd = 0xA0E00 }
                )
            }
        )
    }
)

# =================================================================================================
#  LOGIC - byte level helpers
# =================================================================================================
function ConvertFrom-HexString([string] $Hex) {
    $parts = $Hex.Trim() -split '\s+'
    $bytes = New-Object byte[] $parts.Count
    for ($i = 0; $i -lt $parts.Count; $i++) { $bytes[$i] = [Convert]::ToByte($parts[$i], 16) }
    return ,$bytes   # the comma keeps a 1-byte array an array (PowerShell would unroll it)
}

function Get-Sha256Hex([byte[]] $Data) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Data)) -replace '-', '').ToLower() }
    finally { $sha.Dispose() }
}

function Test-BytesAt([byte[]] $Data, [int] $Offset, [byte[]] $Expected) {
    if ($Offset + $Expected.Length -gt $Data.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) { if ($Data[$Offset + $i] -ne $Expected[$i]) { return $false } }
    return $true
}

# 'old' = the file still holds the documented original bytes, 'new' = the patched bytes, 'other' = neither.
function Get-EditState([byte[]] $Data, $Edit) {
    if ($Edit.ContainsKey('Insert')) {
        if (Test-BytesAt $Data $Edit.Insert (ConvertFrom-HexString $Edit.Bytes))  { return 'new' }
        if (Test-BytesAt $Data $Edit.Insert (ConvertFrom-HexString $Edit.Before)) { return 'old' }
        return 'other'
    }
    if (Test-BytesAt $Data $Edit.Offset (ConvertFrom-HexString $Edit.New)) { return 'new' }
    if (Test-BytesAt $Data $Edit.Offset (ConvertFrom-HexString $Edit.Old)) { return 'old' }
    return 'other'
}

# Applies one patch to a byte array and returns the new array.  Every edit is checked first;
# nothing is written unless all of them still hold their documented old bytes.
function Invoke-Patch([byte[]] $Data, $Patch) {
    foreach ($e in $Patch.Edits) {
        $state = Get-EditState $Data $e
        if ($state -ne 'old') {
            $where = if ($e.ContainsKey('Insert')) { '0x{0:X}' -f $e.Insert } else { '0x{0:X}' -f $e.Offset }
            throw ("fix '{0}': the bytes at file offset {1} are {2} - expected the documented original bytes. " +
                   "Is this the untouched original exe?") -f $Patch.Id, $where, $(if ($state -eq 'new') { 'already patched' } else { 'unknown' })
        }
    }
    $out = [byte[]] $Data.Clone()
    foreach ($e in $Patch.Edits) {
        if ($e.ContainsKey('Insert')) {
            [byte[]] $ins = ConvertFrom-HexString $e.Bytes
            $end = $e.SectionEnd
            for ($i = $end - $ins.Length; $i -lt $end; $i++) {
                if ($out[$i] -ne 0) { throw "fix '$($Patch.Id)': the section slack before 0x$('{0:X}' -f $end) is not zero, cannot insert" }
            }
            # shift [Insert, SectionEnd-16) up by 16, then drop in the new bytes
            [Array]::Copy($out, $e.Insert, $out, $e.Insert + $ins.Length, $end - $ins.Length - $e.Insert)
            [Array]::Copy($ins, 0, $out, $e.Insert, $ins.Length)
        } else {
            [byte[]] $new = ConvertFrom-HexString $e.New
            [Array]::Copy($new, 0, $out, $e.Offset, $new.Length)
        }
    }
    return ,$out
}

function Get-EditCount($Patch) { $n = 0; foreach ($e in $Patch.Edits) { $n++ }; return $n }

function Find-BuildBySha([string] $Sha) { foreach ($b in $Builds) { if ($b.OriginalSha256 -eq $Sha) { return $b } }; return $null }

# Guess the build of an arbitrary exe from its size and the state of the cdcheck edits.
function Find-BuildByContent([byte[]] $Data) {
    foreach ($b in $Builds) {
        if ($Data.Length -ne $b.Size) { continue }
        $ok = $true
        foreach ($e in $b.Patches[0].Edits) { if ((Get-EditState $Data $e) -eq 'other') { $ok = $false } }
        if ($ok) { return $b }
    }
    return $null
}

# The byte edits of one patch as text lines (what -List -Detail and the window show).
function Get-EditLines($Patch) {
    $lines = @()
    foreach ($e in $Patch.Edits) {
        if ($e.ContainsKey('Insert')) {
            $lines += ('insert @0x{0:X6}  {1}   (16 zero bytes dropped before 0x{2:X})' -f $e.Insert, $e.Bytes, $e.SectionEnd)
        } else {
            $lines += ('@0x{0:X6}  {1}  ->  {2}' -f $e.Offset, $e.Old, $e.New)
        }
    }
    return $lines
}

# Inspects an exe: which build, which patches it carries.  Returns text lines.
function Get-VerifyReport([string] $Path) {
    $data = [System.IO.File]::ReadAllBytes((Resolve-Path $Path).Path)
    $sha = Get-Sha256Hex $data
    $lines = @(('{0}' -f $Path), ('{0} bytes, SHA-256 {1}' -f $data.Length, $sha), '')
    $b = Find-BuildBySha $sha
    if ($b) { $lines += ('= the untouched original of {0}: no fix applied.' -f $b.Id); return $lines }
    $b = Find-BuildByContent $data
    if (-not $b) { $lines += 'Not a build this script knows (neither size nor code layout match).'; return $lines }
    $lines += ('build: {0}' -f $b.Title)
    if ($sha -eq $b.PatchedSha256) { $lines += '= the fully patched executable published in the repository.' }
    $lines += ''
    foreach ($p in $b.Patches) {
        $old = 0; $new = 0; $other = 0
        foreach ($e in $p.Edits) { switch (Get-EditState $data $e) { 'old' { $old++ } 'new' { $new++ } default { $other++ } } }
        $total = $old + $new + $other
        $verdict = if ($new -eq $total) { 'APPLIED' } elseif ($old -eq $total) { 'not applied' } else { "MIXED ($new applied, $old original, $other unknown)" }
        $lines += ('  {0,-12} {1,-12} {2}' -f $p.Id, $verdict, $p.Name)
    }
    return $lines
}

# Applies the chosen patches (canonical order) to the bytes of $OriginalPath and writes $OutputPath.
# Returns a small result object; throws on any check failure.
function Invoke-PatchRun([string] $OriginalPath, $Build, [object[]] $Chosen, [string] $OutputPath) {
    $data = [System.IO.File]::ReadAllBytes($OriginalPath)
    $ordered = @($Build.Patches | Where-Object { $p = $_; ($Chosen | Where-Object { $_.Id -eq $p.Id }) })
    $result = $data
    foreach ($p in $ordered) { $result = Invoke-Patch $result $p }
    [System.IO.File]::WriteAllBytes($OutputPath, $result)
    $outSha = Get-Sha256Hex $result
    $allCount = 0; foreach ($p in $Build.Patches) { $allCount++ }
    return @{
        Applied  = $ordered
        Sha256   = $outSha
        Size     = $result.Length
        Complete = ($ordered.Count -eq $allCount)
        Matches  = ($outSha -eq $Build.PatchedSha256)
    }
}

function Write-PatchList([switch] $WithEdits) {
    foreach ($b in $Builds) {
        Write-Host ''
        Write-Host ("=== {0}: {1}" -f $b.Id, $b.Title) -ForegroundColor Cyan
        Write-Host ("    original {0} ({1} bytes)  SHA-256 {2}" -f $b.OriginalName, $b.Size, $b.OriginalSha256)
        Write-Host ("    all patches -> {0}         SHA-256 {1}" -f $b.OutputName, $b.PatchedSha256)
        $n = 0
        foreach ($p in $b.Patches) {
            $n++
            Write-Host ''
            Write-Host ("  {0}. [{1}] {2}  ({3}, {4} edits)" -f $n, $p.Id, $p.Name, $p.Date, (Get-EditCount $p)) -ForegroundColor Yellow
            foreach ($line in ($p.Description -split "`r?`n")) { Write-Host ("       " + $line) }
            if ($WithEdits) { foreach ($line in (Get-EditLines $p)) { Write-Host ("       " + $line) -ForegroundColor DarkGray } }
        }
    }
    Write-Host ''
}

# =================================================================================================
#  WINDOW - the checkbox front end (Windows Forms, part of every Windows PowerShell)
# =================================================================================================
function Show-PatcherWindow([string] $PreloadPath) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $script:gui = @{ Path = $null; Data = $null; Build = $null; IsOriginal = $false; Syncing = $false }
    $mono = New-Object System.Drawing.Font('Consolas', 9)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Dark Colony patcher - rebuild the patched exe from the original, fix by fix'
    $form.Size = New-Object System.Drawing.Size(1000, 680)
    $form.MinimumSize = New-Object System.Drawing.Size(820, 560)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    # --- row 1: original exe
    $lblIn = New-Object System.Windows.Forms.Label
    $lblIn.Text = 'Original exe:'; $lblIn.Location = '12,15'; $lblIn.AutoSize = $true
    $txtIn = New-Object System.Windows.Forms.TextBox
    $txtIn.Location = '110,12'; $txtIn.Size = '760,23'; $txtIn.Anchor = 'Top,Left,Right'; $txtIn.ReadOnly = $true
    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = 'Browse...'; $btnBrowse.Location = '880,10'; $btnBrowse.Size = '92,26'; $btnBrowse.Anchor = 'Top,Right'

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = '110,40'; $lblStatus.Size = '860,36'; $lblStatus.Anchor = 'Top,Left,Right'
    $lblStatus.Text = 'Pick dc16original1998.exe (Classic) or engexp16original.exe (Council Wars) - both are in the repository, untouched.'

    # --- left: the fixes
    $grpFix = New-Object System.Windows.Forms.GroupBox
    $grpFix.Text = 'Fixes to apply (always applied in this order)'; $grpFix.Location = '12,82'; $grpFix.Size = '450,470'
    $grpFix.Anchor = 'Top,Bottom,Left'
    $chkAll = New-Object System.Windows.Forms.CheckBox
    $chkAll.Text = 'Select all fixes  (result = the exe published in the repository)'
    $chkAll.Location = '12,24'; $chkAll.AutoSize = $true; $chkAll.Enabled = $false
    $chkAll.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lst = New-Object System.Windows.Forms.CheckedListBox
    $lst.Location = '12,52'; $lst.Size = '426,406'; $lst.Anchor = 'Top,Bottom,Left,Right'
    $lst.CheckOnClick = $true; $lst.IntegralHeight = $false; $lst.Enabled = $false
    $lst.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $grpFix.Controls.AddRange(@($chkAll, $lst))

    # --- right: description of the highlighted fix
    $grpInfo = New-Object System.Windows.Forms.GroupBox
    $grpInfo.Text = 'What the highlighted fix changes'; $grpInfo.Location = '474,82'; $grpInfo.Size = '498,470'
    $grpInfo.Anchor = 'Top,Bottom,Left,Right'
    $txtInfo = New-Object System.Windows.Forms.TextBox
    $txtInfo.Location = '12,24'; $txtInfo.Size = '474,434'; $txtInfo.Anchor = 'Top,Bottom,Left,Right'
    $txtInfo.Multiline = $true; $txtInfo.ReadOnly = $true; $txtInfo.ScrollBars = 'Vertical'; $txtInfo.WordWrap = $true
    $txtInfo.Font = $mono; $txtInfo.BackColor = [System.Drawing.SystemColors]::Window
    $txtInfo.Text = @(
        'This window rebuilds the patched game executable from the untouched original,',
        'one fix at a time.  Every fix is a list of byte edits written out in this .ps1 file:',
        '',
        '    @{ Offset = 0x431F; Old = ''75''; New = ''EB'' }   # jne -> jmp after the CD check',
        '',
        'A byte is written only if the file still holds the documented old bytes, the input',
        'file is never modified, and the result is a new file whose SHA-256 is shown here.',
        'With every fix selected the result is byte-identical to the exe in the repository.',
        '',
        'Open this file in a text editor to read all of it - it uses nothing but the .NET',
        'classes that ship with Windows (File, SHA256, Windows Forms).',
        '',
        'Click a fix on the left to read what it does and see its byte edits.'
    ) -join "`r`n"
    $grpInfo.Controls.Add($txtInfo)

    # --- bottom: output + buttons + log
    $lblOut = New-Object System.Windows.Forms.Label
    $lblOut.Text = 'Write to:'; $lblOut.Location = '12,565'; $lblOut.AutoSize = $true; $lblOut.Anchor = 'Bottom,Left'
    $txtOut = New-Object System.Windows.Forms.TextBox
    $txtOut.Location = '110,562'; $txtOut.Size = '760,23'; $txtOut.Anchor = 'Bottom,Left,Right'
    $btnOut = New-Object System.Windows.Forms.Button
    $btnOut.Text = '...'; $btnOut.Location = '880,560'; $btnOut.Size = '92,26'; $btnOut.Anchor = 'Bottom,Right'
    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Apply selected fixes'; $btnApply.Location = '110,596'; $btnApply.Size = '170,30'; $btnApply.Anchor = 'Bottom,Left'
    $btnApply.Enabled = $false
    $btnVerify = New-Object System.Windows.Forms.Button
    $btnVerify.Text = 'Inspect an exe...'; $btnVerify.Location = '290,596'; $btnVerify.Size = '140,30'; $btnVerify.Anchor = 'Bottom,Left'
    $lblLog = New-Object System.Windows.Forms.Label
    $lblLog.Location = '440,596'; $lblLog.Size = '532,40'; $lblLog.Anchor = 'Bottom,Left,Right'; $lblLog.Font = $mono

    $form.Controls.AddRange(@($lblIn, $txtIn, $btnBrowse, $lblStatus, $grpFix, $grpInfo, $lblOut, $txtOut, $btnOut, $btnApply, $btnVerify, $lblLog))
    $script:gui.Controls = @{ Form = $form; In = $txtIn; Status = $lblStatus; All = $chkAll; List = $lst; Info = $txtInfo; Out = $txtOut; Apply = $btnApply; Log = $lblLog; Browse = $btnBrowse; OutBtn = $btnOut; Verify = $btnVerify }
    $c = $script:gui.Controls   # event handlers run outside this function's scope, so they reach the controls through this table

    # --- behaviour
    $loadOriginal = {
        param([string] $path)
        $c = $script:gui.Controls
        $g = $script:gui
        $g.Path = $null; $g.Data = $null; $g.Build = $null; $g.IsOriginal = $false
        $c.List.Items.Clear(); $c.All.Checked = $false
        try {
            $data = [System.IO.File]::ReadAllBytes($path)
        } catch {
            $c.Status.ForeColor = 'Firebrick'; $c.Status.Text = "cannot read: $($_.Exception.Message)"; return
        }
        $sha = Get-Sha256Hex $data
        $build = Find-BuildBySha $sha
        $isOriginal = ($null -ne $build)
        if (-not $build) { $build = Find-BuildByContent $data }
        $c.In.Text = $path
        if (-not $build) {
            $c.Status.ForeColor = 'Firebrick'
            $c.Status.Text = "Not a build this script knows ($($data.Length) bytes). Use dc16original1998.exe or engexp16original.exe from the repository."
            $c.List.Enabled = $false; $c.All.Enabled = $false; $c.Apply.Enabled = $false
            return
        }
        $g.Path = $path; $g.Data = $data; $g.Build = $build; $g.IsOriginal = $isOriginal
        if ($isOriginal) {
            $c.Status.ForeColor = 'DarkGreen'
            $c.Status.Text = "$($build.Title)`r`nSHA-256 $sha = the untouched original."
        } else {
            $c.Status.ForeColor = 'DarkOrange'
            $c.Status.Text = "$($build.Title)`r`nSHA-256 does not match the untouched original (already patched, or another copy). Every byte is still checked before it is written."
        }
        foreach ($p in $build.Patches) { [void] $c.List.Items.Add(('{0}   ({1})' -f $p.Name, $p.Date), $false) }
        $c.List.Enabled = $true; $c.All.Enabled = $true; $c.Apply.Enabled = $true
        $c.Out.Text = Join-Path (Split-Path $path) $build.OutputName
        if ($c.List.Items.Count -gt 0) { $c.List.SelectedIndex = 0 }
        $c.Log.Text = ''
    }
    $script:gui.Load = $loadOriginal

    $c.Browse.Add_Click({
        $c = $script:gui.Controls
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Pick the untouched original executable'
        $dlg.Filter = 'Dark Colony executables (*.exe)|*.exe|All files (*.*)|*.*'
        if ($script:gui.Path) { $dlg.InitialDirectory = Split-Path $script:gui.Path }
        if ($dlg.ShowDialog($c.Form) -eq 'OK') { & $script:gui.Load $dlg.FileName }
    })

    $c.OutBtn.Add_Click({
        $c = $script:gui.Controls
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = 'Where to write the patched exe'; $dlg.Filter = 'Executable (*.exe)|*.exe'
        $dlg.OverwritePrompt = $false
        if ($c.Out.Text) { $dlg.FileName = Split-Path -Leaf $c.Out.Text; try { $dlg.InitialDirectory = Split-Path $c.Out.Text } catch {} }
        if ($dlg.ShowDialog($c.Form) -eq 'OK') { $c.Out.Text = $dlg.FileName }
    })

    # "Select all" <-> individual boxes, without the two events feeding each other
    $c.All.Add_CheckedChanged({
        $c = $script:gui.Controls
        if ($script:gui.Syncing) { return }
        $script:gui.Syncing = $true
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) { $c.List.SetItemChecked($i, $c.All.Checked) }
        $script:gui.Syncing = $false
    })
    $c.List.Add_ItemCheck({
        param($sender, $e)
        $c = $script:gui.Controls
        if ($script:gui.Syncing) { return }
        $all = $true
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) {
            $checked = if ($i -eq $e.Index) { $e.NewValue -eq 'Checked' } else { $c.List.GetItemChecked($i) }
            if (-not $checked) { $all = $false }
        }
        $script:gui.Syncing = $true; $c.All.Checked = $all; $script:gui.Syncing = $false
    })

    $c.List.Add_SelectedIndexChanged({
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build -or $c.List.SelectedIndex -lt 0) { return }
        $p = $g.Build.Patches[$c.List.SelectedIndex]
        $lines = @(
            $p.Name, ('=' * $p.Name.Length),
            ('id {0}   added {1}   {2} byte edits' -f $p.Id, $p.Date, (Get-EditCount $p)),
            ('made with {0}' -f $p.Tool), ('documented in {0}' -f $p.Doc), ''
        )
        # the descriptions are pre-wrapped for the source file; join each paragraph so the box wraps it itself
        $para = ''
        foreach ($l in ($p.Description -split "`r?`n")) {
            if ($l -eq '' -or $l -match '^\s') { if ($para) { $lines += $para; $para = '' }; $lines += $l }
            else { $para = if ($para) { "$para $l" } else { $l } }
        }
        if ($para) { $lines += $para }
        $lines += @('', 'Byte edits (file offset: old bytes -> new bytes):', '') + (Get-EditLines $p)
        $c.Info.Text = $lines -join "`r`n"
        $c.Info.SelectionStart = 0; $c.Info.SelectionLength = 0; $c.Info.ScrollToCaret()
    })

    $script:gui.Apply = {
        param([bool] $confirmOverwrite)
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build) { return $null }
        $chosen = @()
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) { if ($c.List.GetItemChecked($i)) { $chosen += $g.Build.Patches[$i] } }
        if ($chosen.Count -eq 0) { $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'No fix selected.'; return $null }
        $outPath = $c.Out.Text.Trim()
        if (-not $outPath) { $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'Choose where to write the result.'; return $null }
        if ([System.IO.Path]::GetFullPath($outPath) -eq [System.IO.Path]::GetFullPath($g.Path)) {
            $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'The output must not be the original file.'; return $null
        }
        if ((Test-Path $outPath) -and $confirmOverwrite) {
            $answer = [System.Windows.Forms.MessageBox]::Show($c.Form, "$outPath exists.`r`nReplace it?", 'Replace file?', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { return $null }
        }
        try {
            $r = Invoke-PatchRun $g.Path $g.Build $chosen $outPath
        } catch {
            $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'Nothing written.'
            [System.Windows.Forms.MessageBox]::Show($c.Form, $_.Exception.Message, 'Check failed - nothing written', 'OK', 'Error') | Out-Null
            return $null
        }
        $ids = ($r.Applied | ForEach-Object { $_.Id }) -join ', '
        if ($r.Complete -and $r.Matches) {
            $c.Log.ForeColor = 'DarkGreen'
            $c.Log.Text = "Written: $($r.Size) bytes, all $($r.Applied.Count) fixes.`r`nSHA-256 $($r.Sha256) = byte-identical to the exe published in the repository."
        } elseif ($r.Complete) {
            $c.Log.ForeColor = 'Firebrick'
            $c.Log.Text = "Written, but the SHA-256 differs from the published exe - please report this.`r`n$($r.Sha256)"
        } else {
            $c.Log.ForeColor = 'Black'
            $c.Log.Text = "Written: $($r.Size) bytes with $($r.Applied.Count) of $(Get-EditCount @{Edits=$g.Build.Patches}) fixes ($ids).`r`nSHA-256 $($r.Sha256)"
        }
        return $r
    }
    $c.Apply.Add_Click({ & $script:gui.Apply $true | Out-Null })

    $c.Verify.Add_Click({
        $c = $script:gui.Controls
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Inspect an executable: which fixes does it carry?'
        $dlg.Filter = 'Dark Colony executables (*.exe)|*.exe|All files (*.*)|*.*'
        if ($dlg.ShowDialog($c.Form) -eq 'OK') {
            $c.Info.Text = (Get-VerifyReport $dlg.FileName) -join "`r`n"
            $c.List.ClearSelected()
        }
    })

    if ($PreloadPath) { & $loadOriginal ((Resolve-Path $PreloadPath).Path) }
    return $form
}

# =================================================================================================
#  ENTRY POINT
# =================================================================================================
if ($PSCmdlet.ParameterSetName -eq 'List') { Write-PatchList -WithEdits:$Detail; return }

if ($PSCmdlet.ParameterSetName -eq 'Verify') { Get-VerifyReport $Verify | ForEach-Object { Write-Host $_ }; return }

# No -All / -Patches: open the window (double-click, "Run with PowerShell", or just `.\Apply-DarkColonyPatches.ps1`)
if (-not $All -and -not $Patches) {
    $form = Show-PatcherWindow $Original
    [void] $form.ShowDialog()
    return
}

# --- command-line apply
if (-not $Original) { throw 'give -Original <exe> together with -All or -Patches' }
$origPath = (Resolve-Path $Original).Path
$data = [System.IO.File]::ReadAllBytes($origPath)
$sha = Get-Sha256Hex $data
Write-Host ("input : {0}" -f $origPath)
Write-Host ("        {0} bytes, SHA-256 {1}" -f $data.Length, $sha)

$build = Find-BuildBySha $sha
if (-not $build) {
    $build = Find-BuildByContent $data
    if (-not $build) { throw "This is not one of the two known original executables (size / layout mismatch)." }
    if (-not $Force) {
        throw ("The SHA-256 is not that of the untouched {0} original. Start from {1} (in the repository), " +
               "or pass -Force to rely on the per-byte checks alone.") -f $build.Id, $build.OriginalName
    }
    Write-Warning "SHA-256 does not match the untouched original; continuing because -Force was given (every edit is still byte-checked)."
}
Write-Host ("build : {0}" -f $build.Title)

$available = @($build.Patches)
if ($All) {
    $chosen = $available
} else {
    # accept -Patches a,b,c from a PowerShell prompt (array) as well as "a,b,c" / "a b c" from cmd / -File (one string)
    $chosen = @()
    foreach ($id in @($Patches | ForEach-Object { $_ -split '[\s,]+' } | Where-Object { $_ })) {
        $p = $available | Where-Object { $_.Id -eq $id }
        if (-not $p) { throw "unknown patch id '$id' for $($build.Id); valid: $(($available | ForEach-Object { $_.Id }) -join ', ')" }
        $chosen += $p
    }
}
if (-not $Output) { $Output = Join-Path (Split-Path $origPath) $build.OutputName }
if ((Test-Path $Output) -and -not $Overwrite) { throw "output '$Output' exists; pass -Overwrite to replace it" }
if ((Test-Path $Output) -and ((Resolve-Path $Output).Path -eq $origPath)) { throw 'refusing to overwrite the original' }

Write-Host ''
foreach ($p in @($available | Where-Object { $p = $_; ($chosen | Where-Object { $_.Id -eq $p.Id }) })) {
    Write-Host ("applying [{0,-10}] {1,-45} {2,3} edits" -f $p.Id, $p.Name, (Get-EditCount $p))
}
$r = Invoke-PatchRun $origPath $build $chosen $Output
Write-Host ''
Write-Host ("output: {0}" -f $Output)
Write-Host ("        {0} bytes, SHA-256 {1}" -f $r.Size, $r.Sha256)
if ($r.Complete) {
    if ($r.Matches) { Write-Host '        byte-identical to the executable published in the repository.' -ForegroundColor Green }
    else { Write-Warning 'all patches applied but the SHA-256 differs from the published executable - report this.' }
} else {
    Write-Host ("        {0} of {1} patches applied ({2}); a partial build has no published reference hash." -f $r.Applied.Count, $available.Count, (($r.Applied | ForEach-Object { $_.Id }) -join ', '))
}
