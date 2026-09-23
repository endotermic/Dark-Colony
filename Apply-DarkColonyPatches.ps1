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
      * the screen resolution is chosen in a drop-down (or -Resolution): 640x480, 1024x768, 1280x1024,
        1280x720, 1280x800, 3840x1080; the sizes with your monitor's aspect ratio are marked "recommended for your
        screen" and the largest of them is preselected in the window (the command line defaults to
        1024x768, the published exes)
      * for an HD resolution the script also WRITES the interface data the patched exe reads
        (INTRF_HD\, exp\intrf_hd\, ozi_ns\intrf_hd\: menu scripts, HUD script, briefing lists,
        letterboxed backgrounds, loading screens) from the stock 640x480 files of the game folder and
        the three pictures per size that ship with the game (INTRF_HD\<WxH>\INTRG.GIF, INTRO.GIF,
        INTRFACE.GIF).  Re-encoding the GIF backgrounds needs a small GIF reader/writer: its C# SOURCE
        TEXT is in this file and is compiled in memory by Add-Type when the set is built, with the
        .NET compiler that is part of Windows (no download, no install, ~2 s).  Doing the same in
        plain PowerShell would take 15-30 s per set under Windows PowerShell 5.1 and minutes under
        PowerShell 7; if Add-Type is blocked on your PC, copy a pre-built set instead - see the
        "INTERFACE SET" section below for the details
      * a fix whose resources (data files it needs next to the exe: the INTRF_HD interface files,
        the DC*.AVI movies, the ozi_ns overlay) are not in the target folder is marked
        "RESOURCES NOT FOUND", its checkbox cannot be ticked and -All skips it; a fix that depends
        on such a fix is marked the same way

    The originals, both in the "DC - Council wars" folder (since 15 Sep 2026 the one folder both games
    run from): "dc16.exe" (the untouched Dark Colony exe of the January 1998 update, 6 sections, entry
    point 0x4528DE; its patched build is written as "dc16new.exe") and "ENGEXP16.EXE"
    (ENGEXP16.EXE from the Council Wars CD; patched build "engexp16new.exe").  Both are committed untouched
    in the repository.  The third build is the map editor "Dark Colony - Map editor\maped.exe" (the
    original from the Dark Colony CD): its fixes clear the "disabled" flag on dialog controls the
    original greyed out - the functional part of the ozi_ns editor, without the Polish translation -
    and write "maped_ozi_ns_v1.2.exe".

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
    Path of the untouched original executable (dc16.exe, ENGEXP16.EXE or the map editor's maped.exe).

.PARAMETER Output
    Where to write the patched copy.  Default: dc16new.exe / engexp16new.exe / maped_ozi_ns_v1.2.exe
    next to the original.
    An existing file is not overwritten unless -Overwrite is given.

.PARAMETER Resolution
    Screen resolution to patch for: 640x480 (the stock size: no display fixes), 1024x768 (default,
    the published exes), 1280x1024, 1280x720, 1280x800 or 3840x1080 (32:9).  The 'resolution' and 'clock' fixes exist
    once per size; all sizes share the one INTRF_HD data folder, which must hold the interface set
    built for the chosen size.  The window offers the same choice in a drop-down, marks the sizes
    with your monitor's aspect ratio as "recommended for your screen" and preselects the largest of
    them; without -Resolution the command line uses 1024x768, the size of the published exes.

.PARAMETER Patches
    Patch ids to apply (see -List).  Order does not matter: they are always applied in the fixed
    canonical order.  Use -All for every patch of the build.  With neither, the window opens
    (with the original preloaded when -Original was given).

.PARAMETER IgnoreMissingData
    Apply fixes whose resources (the INTRF_HD interface files, the DC*.AVI movies, the ozi_ns
    overlay, ...) are missing next to the output, or whose prerequisite fixes are not selected.
    Without it -All skips such fixes (reported as "resources not found") and an explicit -Patches
    list naming one is refused, because such an exe fails at start-up or draws garbage and the
    failure would look like a bug of the patch.  Each fix's Requires / Data lists say what it
    needs; -List prints them.

.PARAMETER Verify
    Instead of patching, inspect an existing exe: which build it is and which patches it carries.

.EXAMPLE
    .\Apply-DarkColonyPatches.ps1                               # the window
    .\Apply-DarkColonyPatches.ps1 -List
    .\Apply-DarkColonyPatches.ps1 -List -Detail                 # every single byte edit
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Council wars\dc16.exe" -All
        (run from the root of the Dark-Colony repository, where this file lives; writes dc16new.exe)
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Council wars\dc16.exe" -Patches nocd,resolution,hdpaths,pool
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Council wars\ENGEXP16.EXE" -All
    .\Apply-DarkColonyPatches.ps1 -Original "DC - Council wars\dc16.exe" -All -Resolution 1280x800
    .\Apply-DarkColonyPatches.ps1 -Original "Dark Colony - Map editor\maped.exe" -All     (-> maped_ozi_ns_v1.2.exe)
    .\Apply-DarkColonyPatches.ps1 -Verify "DC - Council wars\dc16new.exe"

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
    [Parameter(ParameterSetName = 'Apply')] [string] $Resolution,
    [Parameter(ParameterSetName = 'Apply')] [switch] $All,
    [Parameter(ParameterSetName = 'Apply')] [switch] $Overwrite,
    [Parameter(ParameterSetName = 'Apply')] [switch] $Force,
    [Parameter(ParameterSetName = 'Apply')] [switch] $IgnoreMissingData,
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
    #  Dark Colony (Classic) dc16.exe, build linked 7 Jan 1998, 659456 bytes (patched build: dc16new.exe)
    # ---------------------------------------------------------------------------------------------
    @{
        Id             = 'Classic'
        Title          = 'Dark Colony (Classic) dc16.exe, build linked 7 Jan 1998, 659456 bytes (patched build: dc16new.exe)'
        OriginalName   = 'dc16.exe'
        OutputName     = 'dc16new.exe'
        Size           = 659456
        OriginalSha256 = '7c003f85d902dc025d05ab4c5b8f754cd7568bafdf60af6866e8dbcc9b2d57f1'   # untouched original
        PatchedSha256  = 'a71d038b0c8cab089b267748e0c6e1b2e3467678dbed680b55002226834f8f3c'   # every patch applied in the default resolution = the exe in the repository
        # screen resolutions this build can be patched for: '640x480' = the stock size (no display fixes),
        # the others select the per-resolution variants of the 'resolution' and 'clock' fixes below
        Modes          = @('640x480', '1024x768', '1280x1024', '1280x720', '1280x800', '3840x1080')
        DefaultMode    = '1024x768'
        # SHA-256 with every fix of that resolution applied (the default one is the published exe)
        ReferenceSha256 = @{ '640x480' = 'ef82c30a197f556817e48c3177a4efae9ee9a5cb96754ce44128b97c2328df48'; '1024x768' = 'a71d038b0c8cab089b267748e0c6e1b2e3467678dbed680b55002226834f8f3c'; '1280x1024' = '37420219be4bd6905ce07963ead474280aaaac98e8ed5416bb1f02832b2cca4b'; '1280x720' = 'f228661d7228a934acdeca67990fde7f6998662342f11148a3c717db3b7c67c0'; '1280x800' = 'e72b1ec135d633f39da61fb11f81897827e36f0cb400c32d7f003d4bb38e9c6c'; '3840x1080' = '5c4934b23ed49a8ff3e6e3cac7f2ac88d21bffdfb7f48fe5cd12f59746cb58dd' }
        Patches        = @(

            # ---- nocd: No CD: the game neither needs the disc nor touches the CD path ---------------------------------------------------------
            #  Added      : 28-30 Sep 2025 / 18 Sep 2026 / 21 Sep 2026
            #  Made with  : tools/patch_nocd.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.19; CLAUDE.md "Patches applied so far" (the 2025 bytes)
            #  Changes    : 166 bytes in 18 edits
            #  The game refuses to start, and greys out most main-menu buttons, when it cannot find its
            #  CD in a drive.  This one fix removes the whole CD business from the exe:
            #
            #    1. The two menu tests of the "CD present" flag ("call cd_flag ; test al,al ; jne ok") become
            #       unconditional jumps (opcode 75 -> EB): the game starts and keeps every menu button without
            #       the disc.  Council Wars has a third test that threw the player out of a running game; that
            #       one is inverted (75 -> 74).  These are the three bytes hand-patched in 2025.
            #    2. Those bypasses alone only ignore the ANSWER of the test.  Until 18 Sep 2026 the machinery
            #       itself still ran: at start-up the game opened HBNFUFL.A01 / HBNFUFL.A02 (the drive letter
            #       its installer recorded, "D:" in the repository; a missing file was a silent exit), built the
            #       path "D:\dc\" and probed it - it opened D:\dc\anim.dat and, if that existed, tried to
            #       create a file there to see whether the medium refuses writes.  The same probe ran again at
            #       every menu screen and periodically during a battle, two loaders fell back to "D:\dc\<name>"
            #       when a file was missing locally, the sound loader then asked to "insert The Dark Colony CD
            #       and Restart", and the movie opener fell back to the CD when the flag said the disc was in.
            #       The game never tells Windows to fail such accesses quietly (no SetErrorMode call), so when
            #       the letter D: belonged to a drive that was not ready - a card reader or a USB/optical drive
            #       without a medium, an unplugged removable disk, a second hard disk that had spun down -
            #       Windows showed its "No Disk / Please insert a disk into drive ..." box behind the full-screen
            #       game (a black screen that looks like a hang and reads like a CD request) or the game stalled
            #       for the seconds the disk needed to wake up.  Reported by players with more than one drive.
            #       Now: the start-up instructions that load the HBNFUFL name become a jump over the whole block
            #       (HBNFUFL is never opened, no letter, no path, no probe; the two absolute operands that vanish
            #       had .reloc entries, which become type-0 padding), the "call cd_probe" becomes five NOPs and
            #       cd_probe itself starts with "ret" for its two remaining callers, the file-open helper and the
            #       sound loader jump to their ordinary "file missing" exits instead of trying "<CD path><name>",
            #       the movie opener never takes its CD branch, the dead "%c:\dc\" string is zeroed, and the
            #       sound loader's box says "FILE NOT FOUND / A sound file is missing - see error.log".
            #    3. The "Please insert Dark Colony CD" box (21 Sep 2026, player report).  That text is a picture,
            #       not a string: when a file the game insists on is missing, the file-open helper draws the
            #       sprite intrface/insee over the screen and waits for the file to appear - once for the disc to
            #       be inserted, now forever.  Those 68 bytes of the display object's CD-prompt method become the
            #       sound loader's error exit with the file name as the message: a line "unable to open file
            #       <name>" in error.log, the desktop mode restored, a box "FILE NOT FOUND / <name>", exit.  The
            #       four absolute operands of the new code take over the relocation entries of the old ones.
            #       (Seen with a copy of the game that lacked ozi_ns\intrf_hd\: OZI MISSIONS -> NEXT showed the
            #       prompt for intrf_hd/hxscene.txt.)
            #
            #  Every edit sits inside an existing instruction or string; nothing moves.  The patched exe no
            #  longer needs HBNFUFL.A01 / .A02 (the untouched originals still read the drive letter from them).
            @{
                Id = 'nocd'; Name = 'No CD: the game neither needs the disc nor touches the CD path'; Date = '28-30 Sep 2025 / 18 Sep 2026 / 21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_nocd.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.19; CLAUDE.md "Patches applied so far" (the 2025 bytes)'
                Description = @'
The game refuses to start, and greys out most main-menu buttons, when it cannot find its
CD in a drive.  This one fix removes the whole CD business from the exe:

  1. The two menu tests of the "CD present" flag ("call cd_flag ; test al,al ; jne ok") become
     unconditional jumps (opcode 75 -> EB): the game starts and keeps every menu button without
     the disc.  Council Wars has a third test that threw the player out of a running game; that
     one is inverted (75 -> 74).  These are the three bytes hand-patched in 2025.
  2. Those bypasses alone only ignore the ANSWER of the test.  Until 18 Sep 2026 the machinery
     itself still ran: at start-up the game opened HBNFUFL.A01 / HBNFUFL.A02 (the drive letter
     its installer recorded, "D:" in the repository; a missing file was a silent exit), built the
     path "D:\dc\" and probed it - it opened D:\dc\anim.dat and, if that existed, tried to
     create a file there to see whether the medium refuses writes.  The same probe ran again at
     every menu screen and periodically during a battle, two loaders fell back to "D:\dc\<name>"
     when a file was missing locally, the sound loader then asked to "insert The Dark Colony CD
     and Restart", and the movie opener fell back to the CD when the flag said the disc was in.
     The game never tells Windows to fail such accesses quietly (no SetErrorMode call), so when
     the letter D: belonged to a drive that was not ready - a card reader or a USB/optical drive
     without a medium, an unplugged removable disk, a second hard disk that had spun down -
     Windows showed its "No Disk / Please insert a disk into drive ..." box behind the full-screen
     game (a black screen that looks like a hang and reads like a CD request) or the game stalled
     for the seconds the disk needed to wake up.  Reported by players with more than one drive.
     Now: the start-up instructions that load the HBNFUFL name become a jump over the whole block
     (HBNFUFL is never opened, no letter, no path, no probe; the two absolute operands that vanish
     had .reloc entries, which become type-0 padding), the "call cd_probe" becomes five NOPs and
     cd_probe itself starts with "ret" for its two remaining callers, the file-open helper and the
     sound loader jump to their ordinary "file missing" exits instead of trying "<CD path><name>",
     the movie opener never takes its CD branch, the dead "%c:\dc\" string is zeroed, and the
     sound loader's box says "FILE NOT FOUND / A sound file is missing - see error.log".
  3. The "Please insert Dark Colony CD" box (21 Sep 2026, player report).  That text is a picture,
     not a string: when a file the game insists on is missing, the file-open helper draws the
     sprite intrface/insee over the screen and waits for the file to appear - once for the disc to
     be inserted, now forever.  Those 68 bytes of the display object's CD-prompt method become the
     sound loader's error exit with the file name as the message: a line "unable to open file
     <name>" in error.log, the desktop mode restored, a box "FILE NOT FOUND / <name>", exit.  The
     four absolute operands of the new code take over the relocation entries of the old ones.
     (Seen with a copy of the game that lacked ozi_ns\intrf_hd\: OZI MISSIONS -> NEXT showed the
     prompt for intrf_hd/hxscene.txt.)

Every edit sits inside an existing instruction or string; nothing moves.  The patched exe no
longer needs HBNFUFL.A01 / .A02 (the untouched originals still read the drive letter from them).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # movie opener: je <no CD> -> jmp (never the CD path, whatever the flag says)
                    @{ Offset = 0x478; Old = '74 63'; New = 'EB 63' }
                    # start-up CD test: jne -> jmp after "call cd_flag ; test al,al" (the game starts without the disc)
                    @{ Offset = 0x431F; Old = '75'; New = 'EB' }
                    # main-menu CD test: jne -> jmp after the same test (the CD-gated menu buttons stay enabled)
                    @{ Offset = 0x509F; Old = '75'; New = 'EB' }
                    # cd_probe entry: push ebx -> ret (the two remaining callers, load_interface and the in-game check, get nothing)
                    @{ Offset = 0x52AC; Old = '53'; New = 'C3' }
                    # start-up: mov edx,"r" / mov eax,"hbnfufl.a0x" -> jmp to the "full" marker check (HBNFUFL is not opened, no drive letter, no CD path, no probe)
                    @{ Offset = 0x53B3; Old = 'BA 30 26 48 00 B8 44 26 48 00'; New = 'E9 9C 00 00 00 90 90 90 90 90' }
                    # start-up: call cd_probe -> 5 NOPs
                    @{ Offset = 0x5474; Old = 'E8 33 FE FF FF'; New = '90 90 90 90 90' }
                    # open helper: je <try "<CD path><name>"> -> jmp <fail as for any missing file>
                    @{ Offset = 0x57DF; Old = '0F 84 6E FE FF FF'; New = 'E9 F9 FE FF FF 90' }
                    # CD-prompt method (display slot +4Ch, called for a missing required file): "draw intrface/insee and wait for the file" -> the wave loader's error exit: fprintf(error.log, "unable to open file %s", name); display shutdown; Sleep(2000); MessageBoxA(hwnd, name, "FILE NOT FOUND"); exit (68 bytes; the rest of the old body is dead)
                    @{ Offset = 0x2B4BC; Old = '53 51 56 57 55 89 E5 83 EC 38 89 45 FC 89 55 E8 8B 40 20 8B 55 FC 89 45 F8 89 D1 B8 0C 54 48 00 BB 1C 54 48 00 FF 51 44 8B 49 24 89 C2 89 C8 E8 AC FF FD FF 8B 5D FC 8D 55 D8 89 D9 89 45 E0 B8 0C 54 48 00'; New = '52 52 68 C8 7D 48 00 FF 35 B4 49 4A 00 E8 78 FD 04 00 83 C4 0C E8 A1 FD 04 00 E8 D5 21 00 00 B8 D0 07 00 00 E8 E3 47 00 00 5A 6A 00 68 E0 7D 48 00 52 FF 35 30 97 48 00 E8 BB 2E 05 00 31 C0 E8 F7 FF 04 00' }
                    # wave loader: jne <found> -> jmp: after the two local names the loader takes its error exit instead of the two CD-path attempts
                    @{ Offset = 0x51EE9; Old = '0F 85 D7 00 00 00'; New = 'E9 D8 00 00 00 90' }
                    # DGROUP "%c:\dc\" (the CD-path format, now dead) -> 8 zero bytes
                    @{ Offset = 0x7FE54; Old = '25 63 3A 5C 64 63 5C 00'; New = '00 00 00 00 00 00 00 00' }
                    # DGROUP "CDROM NOT FOUND" -> "FILE NOT FOUND" (title of the wave loader's box for a missing WAV)
                    @{ Offset = 0x855E0; Old = '43 44 52 4F 4D 20 4E 4F 54 20 46 4F 55 4E 44 00'; New = '46 49 4C 45 20 4E 4F 54 20 46 4F 55 4E 44 00 00' }
                    # DGROUP "Please insert The Dark Colony ... CD and Restart" -> "A sound file is missing - see error.log" (NUL-padded to the old length)
                    @{ Offset = 0x855F0; Old = '50 6C 65 61 73 65 20 69 6E 73 65 72 74 20 54 68 65 20 44 61 72 6B 20 43 6F 6C 6F 6E 79 20 43 44 20 61 6E 64 20 52 65 73 74 61 72 74 00'; New = '41 20 73 6F 75 6E 64 20 66 69 6C 65 20 69 73 20 6D 69 73 73 69 6E 67 20 2D 20 73 65 65 20 65 72 72 6F 72 2E 6C 6F 67 00 00 00 00 00 00' }
                    # .reloc table: entry 3FB4 (type 3 HIGHLOW, page offset 0xFB4) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97A8A; Old = 'B4 3F'; New = 'B4 0F' }
                    # .reloc table: entry 3FB9 (type 3 HIGHLOW, page offset 0xFB9) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97A8C; Old = 'B9 3F'; New = 'B9 0F' }
                    # .reloc table: entry 30D8 -> 30BF: the absolute operand moved from page offset 0x0D8 to 0x0BF, entry follows it
                    @{ Offset = 0x99B78; Old = 'D8 30'; New = 'BF 30' }
                    # .reloc table: entry 30DD -> 30C5: the absolute operand moved from page offset 0x0DD to 0x0C5, entry follows it
                    @{ Offset = 0x99B7A; Old = 'DD 30'; New = 'C5 30' }
                    # .reloc table: entry 30FC -> 30E9: the absolute operand moved from page offset 0x0FC to 0x0E9, entry follows it
                    @{ Offset = 0x99B7C; Old = 'FC 30'; New = 'E9 30' }
                    # .reloc table: entry 3132 -> 30F0: the absolute operand moved from page offset 0x132 to 0x0F0, entry follows it
                    @{ Offset = 0x99B7E; Old = '32 31'; New = 'F0 30' }
                )
            }

            # ---- resolution @ 1024x768: 1024x768 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 362 bytes in 165 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
            #    stage 1  display mode, framebuffer stride (a shift, 1024 is a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at
            #             (903,6), the 31 lightplane row advances,  and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,96)-(1024,672) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1024x768 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1024x768 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1024x768 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1024x768'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1024x768\INTRG.GIF', 'INTRF_HD\1024x768\INTRO.GIF', 'INTRF_HD\1024x768\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
  stage 1  display mode, framebuffer stride (a shift, 1024 is a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at
           (903,6), the 31 lightplane row advances,  and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,96)-(1024,672) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1024x768 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1024x768 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (60; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'INTRF_HD\1024x768\INTRG.GIF'
                    'INTRF_HD\1024x768\INTRO.GIF'
                    'INTRF_HD\1024x768\INTRFACE.GIF'
                )
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

            # ---- resolution @ 1280x1024: 1280x1024 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 439 bytes in 178 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x1024 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+272) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x992 (36x31 tiles) at (4,6), minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,152)-(1280,872) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x1024 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x1024 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x1024 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x1024'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x1024\INTRG.GIF', 'INTRF_HD\1280x1024\INTRO.GIF', 'INTRF_HD\1280x1024\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x1024 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+272) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x992 (36x31 tiles) at (4,6), minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,152)-(1280,872) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x1024 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x1024 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (60; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'INTRF_HD\1280x1024\INTRG.GIF'
                    'INTRF_HD\1280x1024\INTRO.GIF'
                    'INTRF_HD\1280x1024\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 FF 03 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB E4 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB CE 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB B9 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB B9 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB C8 00 00 00'; New = 'BB 22 02 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5060; Old = 'BB 18 00 00 00'; New = 'BB 28 01 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5071; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7214; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 18 97 48 00 89 55 5A 8D 55 52 8B 1D 00 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 98 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E 68 03 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 00 8E 48 00 8D 55 62 52 A1 18 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F3E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x9484; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F0A; Old = '6A 0E'; New = '6A 1F' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F0C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F1C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0F 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F2B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA4BC; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0F 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA4E0; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E11E; Old = 'B9 C0 01 00 00'; New = 'B9 E0 03 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E123; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E243; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E266; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E26F; Old = 'BB 00 07 00 00'; New = 'BB 80 0F 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B594; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B609; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B613; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B618; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B661; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B747; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B763; Old = 'B9 E0 01 00 00'; New = 'B9 00 04 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D5D2; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D5FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D60E; Old = 'B8 E0 01 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D619; Old = 'B8 E0 01 00 00'; New = 'B8 00 04 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DBC4; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DBC9; Old = 'B9 F0 00 00 00'; New = 'B9 00 02 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DC98; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DCA2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD1C; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD26; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DE89; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DE8E; Old = 'BA E0 01 00 00'; New = 'BA 00 04 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E307; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E30C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E338; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E33D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E3ED; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E3F2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EBAD; Old = '3D 00 B0 04 00'; New = '3D 00 00 14 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EBE2; Old = '3D 00 B0 04 00'; New = '3D 00 00 14 00' }
                    # visible tiles down
                    @{ Offset = 0x35247; Old = 'B9 0E 00 00 00'; New = 'B9 1F 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x3524C; Old = '8D 50 F2'; New = '8D 50 E1' }
                    # visible tiles across
                    @{ Offset = 0x3524F; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x35346; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x35361; Old = 'BB C0 01 00 00'; New = 'BB E0 03 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x35388; Old = 'BA 00 70 00 00'; New = 'BA 00 2E 02 00' }
                    # render destination stride
                    @{ Offset = 0x3539F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x354B6; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x357B6; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x357BD; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x357C5; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x3949B; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x394AF; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x395E4; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x3967A; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x3985B; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x39884; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x50247; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x5024F; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x5025C; Old = '81 FF E0 01 00 00'; New = '81 FF 00 04 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x50264; Old = 'BF DF 01 00 00'; New = 'BF FF 03 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x50346; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x5034D; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x5036B; Old = '81 FE DF 01 00 00'; New = '81 FE FF 03 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x50373; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 FF 03 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D15; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 41 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F0E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F10; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F20; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 BF FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52F5C; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F5E; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52F72; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F74; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52F7A; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE BE FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52F81; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE BE FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52F88; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 BF FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52F91; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 BF FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x52FA6; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FA8; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x52FB3; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 BF FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x52FFB; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53000; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53005; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA BE FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53023; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53025; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5302D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA BE FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5303C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 BF FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x5305D; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 BF FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x530CB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x530F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53115; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x53162; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x5318E; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x531C9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x531FC; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53226; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x53258; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x53293; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x532C6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x532F9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53324; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x53361; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x53394; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x533C7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x533FA; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5342D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x53457; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x53492; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x534B4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x534F6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53529; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x53545; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x5358F; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x535C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x535F5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53628; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x5365B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x53676; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x536BC; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x865B4; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x865B8; Old = 'E0 01 00 00'; New = '00 04 00 00' }
                )
            }

            # ---- resolution @ 1280x720: 1280x720 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 421 bytes in 178 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x720 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+120) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x672 (36x21 tiles) at (4,6) plus 16 spare rows given to the taller HUD bottom bar, minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,0)-(1280,720) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x720 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x720 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x720 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x720'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x720\INTRG.GIF', 'INTRF_HD\1280x720\INTRO.GIF', 'INTRF_HD\1280x720\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x720 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+120) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x672 (36x21 tiles) at (4,6) plus 16 spare rows given to the taller HUD bottom bar, minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,0)-(1280,720) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x720 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x720 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (60; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'INTRF_HD\1280x720\INTRG.GIF'
                    'INTRF_HD\1280x720\INTRO.GIF'
                    'INTRF_HD\1280x720\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 CF 02 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 4C 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 36 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 21 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 21 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB C8 00 00 00'; New = 'BB 6C 01 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5060; Old = 'BB 18 00 00 00'; New = 'BB 90 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5071; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7214; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 18 97 48 00 89 55 5A 8D 55 52 8B 1D 00 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 00 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E D0 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 00 8E 48 00 8D 55 62 52 A1 18 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F3E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x9484; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F0A; Old = '6A 0E'; New = '6A 15' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F0C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F1C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0A 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F2B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA4BC; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0A 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA4E0; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E11E; Old = 'B9 C0 01 00 00'; New = 'B9 A0 02 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E123; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E243; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E266; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E26F; Old = 'BB 00 07 00 00'; New = 'BB 80 0A 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B594; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B609; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B613; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B618; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B661; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B747; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B763; Old = 'B9 E0 01 00 00'; New = 'B9 D0 02 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D5D2; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D5FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D60E; Old = 'B8 E0 01 00 00'; New = 'B8 D0 02 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D619; Old = 'B8 E0 01 00 00'; New = 'B8 D0 02 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DBC4; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DBC9; Old = 'B9 F0 00 00 00'; New = 'B9 68 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DC98; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DCA2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD1C; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD26; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DE89; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DE8E; Old = 'BA E0 01 00 00'; New = 'BA D0 02 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E307; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E30C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E338; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E33D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E3ED; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E3F2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EBAD; Old = '3D 00 B0 04 00'; New = '3D 00 10 0E 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EBE2; Old = '3D 00 B0 04 00'; New = '3D 00 10 0E 00' }
                    # visible tiles down
                    @{ Offset = 0x35247; Old = 'B9 0E 00 00 00'; New = 'B9 15 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x3524C; Old = '8D 50 F2'; New = '8D 50 EB' }
                    # visible tiles across
                    @{ Offset = 0x3524F; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x35346; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x35361; Old = 'BB C0 01 00 00'; New = 'BB A0 02 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x35388; Old = 'BA 00 70 00 00'; New = 'BA 00 7A 01 00' }
                    # render destination stride
                    @{ Offset = 0x3539F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x354B6; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x357B6; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x357BD; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x357C5; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x3949B; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x394AF; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x395E4; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x3967A; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x3985B; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x39884; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x50247; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x5024F; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x5025C; Old = '81 FF E0 01 00 00'; New = '81 FF D0 02 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x50264; Old = 'BF DF 01 00 00'; New = 'BF CF 02 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x50346; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x5034D; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x5036B; Old = '81 FE DF 01 00 00'; New = '81 FE CF 02 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x50373; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 CF 02 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D15; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 2D 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F0E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F10; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F20; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 D3 FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52F5C; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F5E; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52F72; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F74; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52F7A; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE D2 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52F81; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE D2 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52F88; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 D3 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52F91; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 D3 FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x52FA6; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FA8; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x52FB3; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 D3 FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x52FFB; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53000; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53005; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA D2 FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53023; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53025; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5302D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA D2 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5303C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 D3 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x5305D; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 D3 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x530CB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x530F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53115; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x53162; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x5318E; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x531C9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x531FC; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53226; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x53258; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x53293; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x532C6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x532F9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53324; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x53361; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x53394; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x533C7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x533FA; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5342D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x53457; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x53492; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x534B4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x534F6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53529; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x53545; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x5358F; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x535C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x535F5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53628; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x5365B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x53676; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x536BC; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x865B4; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x865B8; Old = 'E0 01 00 00'; New = 'D0 02 00 00' }
                )
            }

            # ---- resolution @ 1280x800: 1280x800 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 425 bytes in 178 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x800 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+160) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x768 (36x24 tiles) at (4,6), minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,40)-(1280,760) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x800 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x800 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x800 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x800'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x800\INTRG.GIF', 'INTRF_HD\1280x800\INTRO.GIF', 'INTRF_HD\1280x800\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x800 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+160) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x768 (36x24 tiles) at (4,6), minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,40)-(1280,760) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x800 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x800 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (60; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'INTRF_HD\1280x800\INTRG.GIF'
                    'INTRF_HD\1280x800\INTRO.GIF'
                    'INTRF_HD\1280x800\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 1F 03 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 74 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 5E 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 49 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 49 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB C8 00 00 00'; New = 'BB 9C 01 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5060; Old = 'BB 18 00 00 00'; New = 'BB B8 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5071; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7214; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 18 97 48 00 89 55 5A 8D 55 52 8B 1D 00 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 28 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E F8 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 00 8E 48 00 8D 55 62 52 A1 18 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F3E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x9484; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F0A; Old = '6A 0E'; New = '6A 18' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F0C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F1C; Old = '81 EB 00 07 00 00'; New = '81 EB 00 0C 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F2B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA4BC; Old = '81 EA 00 07 00 00'; New = '81 EA 00 0C 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA4E0; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E11E; Old = 'B9 C0 01 00 00'; New = 'B9 00 03 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E123; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E243; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E266; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E26F; Old = 'BB 00 07 00 00'; New = 'BB 00 0C 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B594; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B609; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B613; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B618; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B661; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B747; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B763; Old = 'B9 E0 01 00 00'; New = 'B9 20 03 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D5D2; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D5FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D60E; Old = 'B8 E0 01 00 00'; New = 'B8 20 03 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D619; Old = 'B8 E0 01 00 00'; New = 'B8 20 03 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DBC4; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DBC9; Old = 'B9 F0 00 00 00'; New = 'B9 90 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DC98; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DCA2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD1C; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD26; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DE89; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DE8E; Old = 'BA E0 01 00 00'; New = 'BA 20 03 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E307; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E30C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E338; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E33D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E3ED; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E3F2; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EBAD; Old = '3D 00 B0 04 00'; New = '3D 00 A0 0F 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EBE2; Old = '3D 00 B0 04 00'; New = '3D 00 A0 0F 00' }
                    # visible tiles down
                    @{ Offset = 0x35247; Old = 'B9 0E 00 00 00'; New = 'B9 18 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x3524C; Old = '8D 50 F2'; New = '8D 50 E8' }
                    # visible tiles across
                    @{ Offset = 0x3524F; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x35346; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x35361; Old = 'BB C0 01 00 00'; New = 'BB 00 03 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x35388; Old = 'BA 00 70 00 00'; New = 'BA 00 B0 01 00' }
                    # render destination stride
                    @{ Offset = 0x3539F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x354B6; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x357B6; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x357BD; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x357C5; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x3949B; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x394AF; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x395E4; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x3967A; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x3985B; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x39884; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x50247; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x5024F; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x5025C; Old = '81 FF E0 01 00 00'; New = '81 FF 20 03 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x50264; Old = 'BF DF 01 00 00'; New = 'BF 1F 03 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x50346; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x5034D; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x5036B; Old = '81 FE DF 01 00 00'; New = '81 FE 1F 03 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x50373; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 1F 03 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D15; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 33 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F0E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F10; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F20; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 CD FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52F5C; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F5E; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52F72; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F74; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52F7A; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE CC FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52F81; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE CC FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52F88; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 CD FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52F91; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 CD FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x52FA6; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FA8; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x52FB3; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 CD FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x52FFB; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53000; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53005; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA CC FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53023; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53025; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5302D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA CC FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5303C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 CD FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x5305D; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 CD FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x530CB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x530F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53115; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x53162; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x5318E; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x531C9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x531FC; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53226; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x53258; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x53293; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x532C6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x532F9; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53324; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x53361; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x53394; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x533C7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x533FA; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5342D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x53457; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x53492; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x534B4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x534F6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53529; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x53545; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x5358F; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x535C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x535F5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53628; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x5365B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x53676; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x536BC; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x865B4; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x865B8; Old = 'E0 01 00 00'; New = '20 03 00 00' }
                )
            }

            # ---- resolution @ 3840x1080: 3840x1080 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 436 bytes in 178 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 3840x1080 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 3840 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+1600,+300) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 3712x1024 (116x32 tiles) at (4,6) plus 24 spare rows given to the taller HUD bottom bar, minimap 96x84 at
            #             (3719,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x512 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (960,0)-(2880,1080) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 3840x1080 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 3840x1080 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '3840x1080 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '3840x1080'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\3840x1080\INTRG.GIF', 'INTRF_HD\3840x1080\INTRO.GIF', 'INTRF_HD\3840x1080\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 3840x1080 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 3840 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+1600,+300) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 3712x1024 (116x32 tiles) at (4,6) plus 24 spare rows given to the taller HUD bottom bar, minimap 96x84 at
           (3719,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x512 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (960,0)-(2880,1080) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 3840x1080 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 3840x1080 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (60; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'INTRF_HD\3840x1080\INTRG.GIF'
                    'INTRF_HD\3840x1080\INTRO.GIF'
                    'INTRF_HD\3840x1080\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 0E 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 37 04 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 00 02 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 07 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB EA 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 06 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB D5 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 08 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB D5 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 08 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB C8 00 00 00'; New = 'BB 44 02 00 00' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 06 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5060; Old = 'BB 18 00 00 00'; New = 'BB 44 01 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5071; Old = 'BA 50 01 00 00'; New = 'BA 90 07 00 00' }
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
                    @{ Offset = 0x7214; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 18 97 48 00 89 55 5A 8D 55 52 8B 1D 00 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF C7 45 62 C0 03 00 00 C7 45 66 00 00 00 00 C7 45 6A 40 0B 00 00 C7 45 6E 38 04 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 00 8E 48 00 8D 55 62 52 A1 18 97 48 00 50 8B 08 FF 51 14 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F3E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x9484; Old = '2D 07 02 00 00'; New = '2D 87 0E 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F0A; Old = '6A 0E'; New = '6A 20' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F0C; Old = 'B9 10 00 00 00'; New = 'B9 74 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F1C; Old = '81 EB 00 07 00 00'; New = '81 EB 00 10 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F2B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 3A 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA4BC; Old = '81 EA 00 07 00 00'; New = '81 EA 00 10 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA4E0; Old = '81 EA 00 08 00 00'; New = '81 EA 00 3A 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E11E; Old = 'B9 C0 01 00 00'; New = 'B9 00 04 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E123; Old = 'BB 00 02 00 00'; New = 'BB 80 0E 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E243; Old = 'B8 07 02 00 00'; New = 'B8 87 0E 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E266; Old = 'B9 00 08 00 00'; New = 'B9 00 3A 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E26F; Old = 'BB 00 07 00 00'; New = 'BB 00 10 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B594; Old = 'BB 80 02 00 00'; New = 'BB 00 0F 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B609; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 0F 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B613; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B618; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B661; Old = 'BA 80 02 00 00'; New = 'BA 00 0F 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B747; Old = 'BB 80 02 00 00'; New = 'BB 00 0F 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B763; Old = 'B9 E0 01 00 00'; New = 'B9 38 04 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D5D2; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D5FF; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D60E; Old = 'B8 E0 01 00 00'; New = 'B8 38 04 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D619; Old = 'B8 E0 01 00 00'; New = 'B8 38 04 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DBC4; Old = 'BA 40 01 00 00'; New = 'BA 80 07 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DBC9; Old = 'B9 F0 00 00 00'; New = 'B9 1C 02 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DC98; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DCA2; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD1C; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD26; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DE89; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DE8E; Old = 'BA E0 01 00 00'; New = 'BA 38 04 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E307; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E30C; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E338; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E33D; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E3ED; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E3F2; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EBAD; Old = '3D 00 B0 04 00'; New = '3D 00 48 3F 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EBE2; Old = '3D 00 B0 04 00'; New = '3D 00 48 3F 00' }
                    # visible tiles down
                    @{ Offset = 0x35247; Old = 'B9 0E 00 00 00'; New = 'B9 20 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x3524C; Old = '8D 50 F2'; New = '8D 50 E0' }
                    # visible tiles across
                    @{ Offset = 0x3524F; Old = 'BB 10 00 00 00'; New = 'BB 74 00 00 00' }
                    # viewport width
                    @{ Offset = 0x35346; Old = 'BA 00 02 00 00'; New = 'BA 80 0E 00 00' }
                    # viewport height
                    @{ Offset = 0x35361; Old = 'BB C0 01 00 00'; New = 'BB 00 04 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x35388; Old = 'BA 00 70 00 00'; New = 'BA 00 40 07 00' }
                    # render destination stride
                    @{ Offset = 0x3539F; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x354B6; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 1E 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x357B6; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 0F 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x357BD; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x357C5; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x3949B; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x394AF; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E D1 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x395E4; Old = 'B8 07 02 00 00'; New = 'B8 87 0E 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x3967A; Old = '05 07 02 00 00'; New = '05 87 0E 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x3985B; Old = 'BA 80 02 00 00'; New = 'BA 00 0F 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x39884; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E D1 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x50247; Old = '81 FE 80 02 00 00'; New = '81 FE 00 0F 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x5024F; Old = 'BE 7F 02 00 00'; New = 'BE FF 0E 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x5025C; Old = '81 FF E0 01 00 00'; New = '81 FF 38 04 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x50264; Old = 'BF DF 01 00 00'; New = 'BF 37 04 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x50346; Old = '3D 7F 02 00 00'; New = '3D FF 0E 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x5034D; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 0E 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x5036B; Old = '81 FE DF 01 00 00'; New = '81 FE 37 04 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x50373; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 37 04 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D15; Old = '81 EC CC 14 00 00'; New = '81 EC FC 87 00 00' }
                    # lightmap x144 -> x512, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F0E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F10; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F20; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 86 78 FF FF' }
                    # lightmap x144 -> x512, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52F5C; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F5E; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap x144 -> x512, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52F72; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F74; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52F7A; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E 7E 78 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52F81; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F 7E 78 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52F88; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 86 78 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52F91; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 86 78 FF FF' }
                    # lightmap x144 -> x512, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x52FA6; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FA8; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x52FB3; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 82 78 FF FF' }
                    # lightmap x144 -> x512, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x52FFB; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x512, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53000; Old = 'C1 E2 04'; New = 'C1 E2 06' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53005; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A 7A 78 FF FF' }
                    # lightmap x144 -> x512, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53023; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53025; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5302D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 7A 78 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5303C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 82 78 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x5305D; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 82 78 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x530CB; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x530F2; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53115; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x53162; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x5318E; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x531C9; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x531FC; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53226; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x53258; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x53293; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x532C6; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x532F9; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53324; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x53361; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x53394; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x533C7; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x533FA; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5342D; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x53457; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x53492; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x534B4; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x534F6; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53529; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x53545; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x5358F; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x535C2; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x535F5; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53628; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x5365B; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x53676; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x536BC; Old = '8D B8 00 02 00 00'; New = '8D B8 80 0E 00 00' }
                    # screen width global
                    @{ Offset = 0x865B4; Old = '80 02 00 00'; New = '00 0F 00 00' }
                    # screen height global
                    @{ Offset = 0x865B8; Old = 'E0 01 00 00'; New = '38 04 00 00' }
                )
            }

            # ---- hdpaths: Interface data from INTRF_HD (rebuilt files renamed) ---------------------------------------------------------
            #  Added      : 14 Sep 2026
            #  Made with  : tools/patch_hd_paths.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17
            #  Changes    : 120 bytes in 30 edits
            #  The rebuilt (1024x768 or another HD size) menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
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
            #  dcuk_hd.fin etc.  No code changes.  With this patch the untouched dc16.exe / ENGEXP16.EXE
            #  (stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
            #  meaningful together with the display patch, and REQUIRES the INTRF_HD/ folder holding the set built for the chosen
            #  resolution (one folder for every size, maintainer decision 21 Sep 2026).
            @{
                Id = 'hdpaths'; Name = 'Interface data from INTRF_HD (rebuilt files renamed)'; Date = '14 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = 'hd'
                Tool = 'tools/patch_hd_paths.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17'
                Description = @'
The rebuilt (1024x768 or another HD size) menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
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
dcuk_hd.fin etc.  No code changes.  With this patch the untouched dc16.exe / ENGEXP16.EXE
(stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
meaningful together with the display patch, and REQUIRES the INTRF_HD/ folder holding the set built for the chosen
resolution (one folder for every size, maintainer decision 21 Sep 2026).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (57; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                )
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_pool.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13'
                Description = @'
Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
info, game state, AI, widgets) is carved from one arena created at start-up with
"mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
headers are 32-bit and the size check unsigned, so nothing else changes.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # mov eax,imm32 before call SMalloc_Pool: pool size 11 500 000 (0x00AF79E0) -> 33 554 432 bytes (0x02000000, 32 MiB)
                    @{ Offset = 0x4734; Old = 'B8 E0 79 AF 00'; New = 'B8 00 00 00 02' }
                )
            }

            # ---- clock @ 1024x768: Day/night clock hand re-anchored (1024x768) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1024x768 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1024x768)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1024x768'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1024x768 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 738 (0x2E2)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = 'E2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 992 (0x3E0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 03 00 00' }
                )
            }

            # ---- clock @ 1280x1024: Day/night clock hand re-anchored (1280x1024) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x1024 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,994), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x1024 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x1024)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x1024'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x1024 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,994), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x1024 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 994 (0x3E2)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = 'E2 03 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 1280x720: Day/night clock hand re-anchored (1280x720) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x720 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,690), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x720 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x720)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x720'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x720 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,690), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x720 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 690 (0x2B2)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = 'B2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 1280x800: Day/night clock hand re-anchored (1280x800) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x800 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,770), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x800 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x800)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x800'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x800 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,770), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x800 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 770 (0x302)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = '02 03 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 3840x1080: Day/night clock hand re-anchored (3840x1080) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 3840x1080 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (3808,1050), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 3840x1080 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (3840x1080)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '3840x1080'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 3840x1080 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (3808,1050), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 3840x1080 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 1050 (0x41A)
                    @{ Offset = 0x3A0A3; Old = 'C2 01 00 00'; New = '1A 04 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 3808 (0xEE0)
                    @{ Offset = 0x3A0B6; Old = '60 02 00 00'; New = 'E0 0E 00 00' }
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
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

            # ---- camera: Camera clamped at battle start: no crash when the start position is near the map edge ---------------------------------------------------------
            #  Added      : 21 Sep 2026
            #  Made with  : tools/patch_camera.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.22
            #  Changes    : 34 bytes in 2 edits
            #  When a battle starts the game puts the camera on the player's start position and only
            #  afterwards computes the camera limits ("half a screen from every map edge") - but it never applies
            #  them to that first position.  The per-frame scrolling code clamps the camera, yet the very first
            #  frame already uses the unclamped position: it hands "camera minus half a screen" as the visible
            #  tile rectangle to the routine that picks the ambient sounds from the terrain on screen, and that
            #  routine walks the rectangle row by row through the map's row-pointer table without checking the far
            #  edge.  With the original 16x14-tile view no shipped start position was close enough to an edge for
            #  the rectangle to leave the map; with the 1024x768 view (28x23 tiles, "1024x768" fix) every start
            #  row within 11 tiles of the far map edge does - the row pointers past the map are NULL and the game
            #  dies with an access violation the moment the battlefield appears (Windows' crash dialog stays
            #  hidden behind the full-screen surface, so it looks like a hang; a relay server then drops the
            #  player after 5 s and the other players continue).  Hit on Fly on 19 Sep 2026 by the player whose
            #  game slot got start position 0 of "Plink - O" (row 131 of 140); Plink - O positions 0 and 1,
            #  Armageddon 3, Circle of Friends 1 and 2, Olympus Mons 0 and 1 and others are affected the same way.
            #  The fix redirects the call that follows the limit computation into a 33-byte routine placed in the
            #  unused zero bytes at the end of the code section: it calls the game's own 2-D clamp function with
            #  those limits on the camera and then continues into the routine the call originally targeted.
            #  Only register-relative addressing, no relocation entries, nothing moves.  Harmless without the
            #  1024x768 fix and in single-player missions (a clamp can only move the camera inside the map).
            @{
                Id = 'camera'; Name = 'Camera clamped at battle start: no crash when the start position is near the map edge'; Date = '21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_camera.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.22'
                Description = @'
When a battle starts the game puts the camera on the player's start position and only
afterwards computes the camera limits ("half a screen from every map edge") - but it never applies
them to that first position.  The per-frame scrolling code clamps the camera, yet the very first
frame already uses the unclamped position: it hands "camera minus half a screen" as the visible
tile rectangle to the routine that picks the ambient sounds from the terrain on screen, and that
routine walks the rectangle row by row through the map's row-pointer table without checking the far
edge.  With the original 16x14-tile view no shipped start position was close enough to an edge for
the rectangle to leave the map; with the 1024x768 view (28x23 tiles, "1024x768" fix) every start
row within 11 tiles of the far map edge does - the row pointers past the map are NULL and the game
dies with an access violation the moment the battlefield appears (Windows' crash dialog stays
hidden behind the full-screen surface, so it looks like a hang; a relay server then drops the
player after 5 s and the other players continue).  Hit on Fly on 19 Sep 2026 by the player whose
game slot got start position 0 of "Plink - O" (row 131 of 140); Plink - O positions 0 and 1,
Armageddon 3, Circle of Friends 1 and 2, Olympus Mons 0 and 1 and others are affected the same way.
The fix redirects the call that follows the limit computation into a 33-byte routine placed in the
unused zero bytes at the end of the code section: it calls the game's own 2-D clamp function with
those limits on the camera and then continues into the routine the call originally targeted.
Only register-relative addressing, no relocation entries, nothing moves.  Harmless without the
1024x768 fix and in single-player missions (a clamp can only move the camera inside the map).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # proto.c init: call load_ambience -> call stub: rel32 operand of the E8 that follows the camera-bounds stores; the stub clamps the camera first and then continues into load_ambience 0x00432F80
                    @{ Offset = 0x1E2B9; Old = 'C3 40 01 00'; New = '1F 03 06 00' }
                    # stub clamp_camera in the AUTO zero tail: lea esi,[eax+108h]; push &cam_z, &cam_x, max_z, max_x, min_z, min_x (ui+0x120..0x114); call clamp2d 0x00436668; jmp load_ambience 0x00432F80 - register-relative only, no .reloc entries
                    @{ Offset = 0x7E5DC; Old = '00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'; New = '8D B0 08 01 00 00 8D 4E 08 51 56 FF 76 18 FF 76 14 FF 76 10 FF 76 0C E8 70 74 FB FF E9 83 3D FB FF' }
                )
            }

            # ---- widemap: Maps narrower than the screen: the view is centred on the map and every map read stays inside it ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_widemap.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.32
            #  Changes    : 370 bytes in 26 edits
            #  The battlefield view is the screen minus the panel, in whole 32-pixel tiles: 28 tiles across at
            #  1024x768, 36 at 1280x800, 76 at 2560x1440, 116 at 3840x1080.  The maps are 64 to 160 tiles wide
            #  (the training maps and two two-player maps 64, the first two campaign missions and 22 two-player
            #  maps 96).  Once the view is wider than the map the game's camera limits ("half a screen from every
            #  map edge") contradict each other and the camera settles at the far one, so the view begins left of
            #  the map; nothing that then reads the map checks for that: the terrain drawer continues into the
            #  neighbouring rows (the far side of the map drawn shifted by a row) and, at the top and bottom map
            #  row, past the tile block into memory whose contents it takes for tile numbers - a crash in the tile
            #  blitter as soon as the camera reaches those rows; the lighting pass reads before and after each row;
            #  the visibility scan tests tiles of the wrong row; the ambient sounds fall silent (their picker gives
            #  up when the visible rectangle starts left of the map); a click on the black margin sends units to
            #  the far side of the map (the position wraps in a 16-bit field).  The fix, in six parts written into
            #  the dead body of the CD-probe routine (unused since the "No CD" fix, which is therefore required,
            #  as is the "Camera clamped" fix whose stub the first part chains into): (1) when the limits
            #  contradict each other, both become the map centre, so the map sits centred in the view and cannot
            #  scroll sideways; (2) the terrain drawer clamps every column to the map, so the margin repeats the
            #  edge tiles instead of reading beyond them; (3) the lighting pass clamps rows and columns the same
            #  way (in place of its four edge cases); (4) the visibility rectangle is cut to the map; (5) the
            #  ambient-sound picker clamps its rectangle instead of giving up; (6) a spot order's x is clamped to
            #  the map.  The 14 relocation entries of the dead routine are re-pointed to the new absolute operands
            #  or neutralised.  Rows are never affected with the shipped maps (the tallest view, 44 rows at
            #  5120x1440, is shorter than the smallest map, 56 rows), so only the column direction is handled.
            #  Without a wide screen the fix changes nothing visible: every map is wider than 28 or 36 tiles.
            @{
                Id = 'widemap'; Name = 'Maps narrower than the screen: the view is centred on the map and every map read stays inside it'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_widemap.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.32'
                Description = @'
The battlefield view is the screen minus the panel, in whole 32-pixel tiles: 28 tiles across at
1024x768, 36 at 1280x800, 76 at 2560x1440, 116 at 3840x1080.  The maps are 64 to 160 tiles wide
(the training maps and two two-player maps 64, the first two campaign missions and 22 two-player
maps 96).  Once the view is wider than the map the game's camera limits ("half a screen from every
map edge") contradict each other and the camera settles at the far one, so the view begins left of
the map; nothing that then reads the map checks for that: the terrain drawer continues into the
neighbouring rows (the far side of the map drawn shifted by a row) and, at the top and bottom map
row, past the tile block into memory whose contents it takes for tile numbers - a crash in the tile
blitter as soon as the camera reaches those rows; the lighting pass reads before and after each row;
the visibility scan tests tiles of the wrong row; the ambient sounds fall silent (their picker gives
up when the visible rectangle starts left of the map); a click on the black margin sends units to
the far side of the map (the position wraps in a 16-bit field).  The fix, in six parts written into
the dead body of the CD-probe routine (unused since the "No CD" fix, which is therefore required,
as is the "Camera clamped" fix whose stub the first part chains into): (1) when the limits
contradict each other, both become the map centre, so the map sits centred in the view and cannot
scroll sideways; (2) the terrain drawer clamps every column to the map, so the margin repeats the
edge tiles instead of reading beyond them; (3) the lighting pass clamps rows and columns the same
way (in place of its four edge cases); (4) the visibility rectangle is cut to the map; (5) the
ambient-sound picker clamps its rectangle instead of giving up; (6) a spot order's x is clamped to
the map.  The 14 relocation entries of the dead routine are re-pointed to the new absolute operands
or neutralised.  Rows are never affected with the shipped maps (the tallest view, 44 rows at
5120x1440, is shorter than the smallest map, 56 rows), so only the column direction is handled.
Without a wide screen the fix changes nothing visible: every map is wider than 28 or 36 tiles.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('nocd', 'camera')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # cd_probe dead body: bounds rule + column stub + vision stub + order stub: bounds rule at +0 (per axis `if max < min: min = max = (min+max)/2`, 10 absolute operands, jmp camera stub 0x0047F1DC), column stub at +73, vision stub at +124 (call make_rect 0x004365BC, 1 absolute operand), order stub at +158
                    @{ Offset = 0x52AD; Old = '51 52 56 55 89 E5 81 EC 00 01 00 00 68 B0 48 4A 00 30 E4 68 24 26 48 00 88 25 B8 49 4A 00 8D 85 00 FF FF FF 50 E8 8D 61 07 00 83 C4 0C BA 30 26 48 00 8D 85 00 FF FF FF E8 9A 5C 07 00 85 C0 75 0F A0 F4 8D 48 00 A2 B8 49 4A 00 E9 83 00 00 00 E8 7D 5D 07 00 BE A0 86 01 00 31 D2 E8 22 55 00 00 F7 F6 52 68 B0 48 4A 00 68 34 26 48 00 8D 85 00 FF FF FF 50 E8 3D 61 07 00 83 C4 10 BA 3C 26 48 00 8D 85 00 FF FF FF E8 4A 5C 07 00 89 C6 85 C0 75 0F C6 05 B8 49 4A 00 01 89 EC 5D 5E 5A 59 5B C3 BB 01 00 00 00 89 C1 B8 40 26 48 00 89 DA E8 E6 61 07 00 85 C0 75 09 C6 05 B8 49 4A 00 01 EB 0A A0 F4 8D 48 00 A2 B8 49 4A 00 89 F0 E8'; New = '8B 0D EC AA 4A 00 3B 0D E4 AA 4A 00 7D 14 03 0D E4 AA 4A 00 D1 F9 89 0D E4 AA 4A 00 89 0D EC AA 4A 00 8B 0D F0 AA 4A 00 3B 0D E8 AA 4A 00 7D 14 03 0D E8 AA 4A 00 D1 F9 89 0D E8 AA 4A 00 89 0D F0 AA 4A 00 E9 E6 92 07 00 8B 06 C1 F8 05 8D 14 38 85 D2 7D 02 31 D2 8B 4E 14 0F BF 09 49 39 CA 7E 02 89 CA 29 C2 C1 E2 02 89 55 BC 8B 45 C8 8D 04 B8 89 45 B8 8A 4D F4 8B 45 F8 C3 E8 8E 06 03 00 8B 15 C0 44 50 00 83 38 00 7D 03 83 20 00 8B 8A B0 A4 09 00 39 48 08 7E 03 89 48 08 C3 51 8B 48 0C 8B 89 4C 6F 04 00 85 D2 7D 02 31 D2 3B 91 B8 A4 09 00 7C 07 8B 91 B8 A4 09 00 4A 89 D6 59 66 89 98 92 07 00 00 66 89 90 90 07 00 00 C3' }
                    # spot order: the two 16-bit stores of the world point -> call order stub (clamps x to [0, map_w*256-1], updates esi, then stores)
                    @{ Offset = 0x8A9F; Old = '66 89 98 92 07 00 00 66 89 90 90 07 00 00'; New = 'E8 A7 C8 FF FF 90 90 90 90 90 90 90 90 90' }
                    # proto.c init: call camera stub -> call bounds rule (which chains into the camera stub)
                    @{ Offset = 0x1E2B8; Old = 'E8 1F 03 06 00'; New = 'E8 F0 6F FE FF' }
                    # clip_view_to_map: call make_rect -> call vision stub (make_rect, then x0 = max(x0,0), x1 = min(x1,w))
                    @{ Offset = 0x35262; Old = 'E8 55 07 00 00'; New = 'E8 C2 00 FD FF' }
                    # ambience pick: origin guards -> x0 = max(x0,0), w = min(w, W-x0); the z guard keeps its stock meaning (return 0 via 0x00445BEA)
                    @{ Offset = 0x44EBD; Old = '85 FF 7C 0E 8B 96 4C 6F 04 00 3B BA B0 A4 09 00 7E 07 31 C0 E9 14 01 00 00 85 DB 7C 08 3B 9A B4 A4 09 00 7E 0B 31 C0 8D 65 7E 5D 5F 5E C2 04 00'; New = '85 FF 7D 02 31 FF 8B 96 4C 6F 04 00 8B 8A B0 A4 09 00 29 F9 39 C8 7E 02 89 C8 85 DB 7C 08 3B 9A B4 A4 09 00 7E 0A 31 C0 E9 00 01 00 00 90 90 90' }
                    # tile drawer: sub esp,38h -> 48h; two new locals [ebp-44h] = clamped column offset, [ebp-48h] = mask column pointer
                    @{ Offset = 0x4F523; Old = '83 EC 38'; New = '83 EC 48' }
                    # tile drawer: column-loop head `mov cl,[ebp-0Ch]; mov eax,[ebp-8]` -> call column stub (which runs both); NOP
                    @{ Offset = 0x4F5D2; Old = '8A 4D F4 8B 45 F8'; New = 'E8 1F 5D FB FF 90' }
                    # tile drawer: `lea ecx,[edi*4]` (tile word column) -> `mov ecx,[ebp-44h]` clamped offset
                    @{ Offset = 0x4F60C; Old = '8D 0C BD 00 00 00 00'; New = '8B 4D BC 90 90 90 90' }
                    # tile drawer: mask pointer `mov eax,[ebp-38h]; add eax,ecx` -> `mov eax,[ebp-48h]` (real column, computed by the stub)
                    @{ Offset = 0x4F674; Old = '8B 45 C8 8A 5C 11 03 01 C8 F6 C3 08'; New = '8B 45 B8 8A 5C 11 03 90 90 F6 C3 08' }
                    # tile drawer: `lea edx,[edi*4]` (fg flag word) -> `mov edx,[ebp-44h]`
                    @{ Offset = 0x4F693; Old = '8D 14 BD 00 00 00 00'; New = '8B 55 BC 90 90 90 90' }
                    # tile drawer: `lea edx,[edi*4]` (fg tile word) -> `mov edx,[ebp-44h]`
                    @{ Offset = 0x4F6B3; Old = '8D 14 BD 00 00 00 00'; New = '8B 55 BC 90 90 90 90' }
                    # draw_terrain lightmap pass: the four edge-flag corrections -> clamp the map row to [0,h-1] and the column to [0,w-1] (esi/edi scratch, eax = row, [ebp+72h] = column)
                    @{ Offset = 0x52E80; Old = '85 F6 74 06 83 F9 FF 75 01 40 83 7D 42 00 74 06 3B 4D 6A 75 01 48 83 7D 3E 00 74 08 83 FA FF 75 03 FF 45 72 83 7D 46 00 74 08 3B 55 6E 75 03 FF 4D 72'; New = '8B 73 14 85 C0 7D 02 31 C0 8B BE B4 A4 09 00 4F 39 F8 7E 02 89 F8 8B 7D 72 85 FF 7D 02 31 FF 8B B6 B0 A4 09 00 4E 39 F7 7E 02 89 F7 89 7D 72 90 90 90' }
                    # .reloc table: entry 3EBA -> 3EAF: the absolute operand moved from page offset 0xEBA to 0xEAF, entry follows it
                    @{ Offset = 0x97A6A; Old = 'BA 3E'; New = 'AF 3E' }
                    # .reloc table: entry 3EC1 -> 3EB5: the absolute operand moved from page offset 0xEC1 to 0xEB5, entry follows it
                    @{ Offset = 0x97A6C; Old = 'C1 3E'; New = 'B5 3E' }
                    # .reloc table: entry 3EC7 -> 3EBD: the absolute operand moved from page offset 0xEC7 to 0xEBD, entry follows it
                    @{ Offset = 0x97A6E; Old = 'C7 3E'; New = 'BD 3E' }
                    # .reloc table: entry 3EDB -> 3EC5: the absolute operand moved from page offset 0xEDB to 0xEC5, entry follows it
                    @{ Offset = 0x97A70; Old = 'DB 3E'; New = 'C5 3E' }
                    # .reloc table: entry 3EEF -> 3ECB: the absolute operand moved from page offset 0xEEF to 0xECB, entry follows it
                    @{ Offset = 0x97A72; Old = 'EF 3E'; New = 'CB 3E' }
                    # .reloc table: entry 3EF4 -> 3ED1: the absolute operand moved from page offset 0xEF4 to 0xED1, entry follows it
                    @{ Offset = 0x97A74; Old = 'F4 3E'; New = 'D1 3E' }
                    # .reloc table: entry 3F12 -> 3ED7: the absolute operand moved from page offset 0xF12 to 0xED7, entry follows it
                    @{ Offset = 0x97A76; Old = '12 3F'; New = 'D7 3E' }
                    # .reloc table: entry 3F17 -> 3EDF: the absolute operand moved from page offset 0xF17 to 0xEDF, entry follows it
                    @{ Offset = 0x97A78; Old = '17 3F'; New = 'DF 3E' }
                    # .reloc table: entry 3F2B -> 3EE7: the absolute operand moved from page offset 0xF2B to 0xEE7, entry follows it
                    @{ Offset = 0x97A7A; Old = '2B 3F'; New = 'E7 3E' }
                    # .reloc table: entry 3F42 -> 3EED: the absolute operand moved from page offset 0xF42 to 0xEED, entry follows it
                    @{ Offset = 0x97A7C; Old = '42 3F'; New = 'ED 3E' }
                    # .reloc table: entry 3F57 -> 3F30: the absolute operand moved from page offset 0xF57 to 0xF30, entry follows it
                    @{ Offset = 0x97A7E; Old = '57 3F'; New = '30 3F' }
                    # .reloc table: entry 3F68 (type 3 HIGHLOW, page offset 0xF68) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97A80; Old = '68 3F'; New = '00 00' }
                    # .reloc table: entry 3F70 (type 3 HIGHLOW, page offset 0xF70) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97A82; Old = '70 3F'; New = '00 00' }
                    # .reloc table: entry 3F75 (type 3 HIGHLOW, page offset 0xF75) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97A84; Old = '75 3F'; New = '00 00' }
                )
            }

            # ---- restore: Window restore after minimising: Alt+Tab and the taskbar bring the game back ---------------------------------------------------------
            #  Added      : 21 Sep 2026
            #  Made with  : tools/patch_restore.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.28
            #  Changes    : 86 bytes in 2 edits
            #  Leave the running game with Alt+Tab, the Win key or a click on another window and DirectDraw
            #  minimises it and restores the desktop resolution.  Coming back with Alt+Tab or the taskbar button
            #  the game stays minimised although it is the active window, or shows a black window at desktop
            #  resolution; it is alive and busy, error.log stays empty.  The game has no message loop: once per
            #  frame it pulls posted messages with range-filtered PeekMessage calls (mouse, keyboard, system
            #  commands - the last only to swallow the screen-saver command) and dispatches none of them.
            #  Windows restores a minimised window by posting the system command SC_RESTORE to it, so the request
            #  is removed from the queue and dropped; being activated while still minimised also defeats
            #  DirectDraw's own window hook, which re-sets the exclusive display mode only during a proper
            #  activation - afterwards every attempt to restore the drawing surfaces fails with DDERR_WRONGMODE.
            #  The fix rewrites that per-frame block in place (107 bytes, 86 of them new code, the rest NOP):
            #  the system-command peek hands every command except the screen saver to DefWindowProcA, so
            #  SC_RESTORE, SC_MINIMIZE and the others take effect, and after an SC_RESTORE it calls
            #  ShowWindow(SW_MINIMIZE) followed by ShowWindow(SW_RESTORE) - a deactivate/activate cycle on a window
            #  that is not minimised at the moment of activation, which is the path DirectDraw's hook handles: it
            #  re-sets the mode, the game's own per-frame surface restore repairs the surfaces and the next frame
            #  is drawn.  The two peeks it replaces looked for WM_SETCURSOR and WM_DESTROY, messages Windows never
            #  posts (dead code).  Second part: while minimised the game's main loop used to spin at 100 % of a
            #  processor core - the per-frame present routine fails its blit, fails the surface restore and
            #  returns early, so the Flip that normally paces the loop is never reached (about 4 400 passes per
            #  second).  The branch taken after that failed restore now goes to a 12-byte stub in the spare tail
            #  of the same block: Sleep(1) - one system timer period, at most 16 ms, well inside the 44 ms game
            #  tick - then back to the routine's exit.  Game ticks are clock-driven and keep running while
            #  minimised (a multiplayer client stays in the game), only the idle spin is gone.  The four calls go
            #  through the linker's import thunks; nothing moves, no relocation entry changes.  Verified in game
            #  21 Sep 2026 on both exes (Alt+Tab, taskbar button, Start menu, minimise from the taskbar).
            @{
                Id = 'restore'; Name = 'Window restore after minimising: Alt+Tab and the taskbar bring the game back'; Date = '21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_restore.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.28'
                Description = @'
Leave the running game with Alt+Tab, the Win key or a click on another window and DirectDraw
minimises it and restores the desktop resolution.  Coming back with Alt+Tab or the taskbar button
the game stays minimised although it is the active window, or shows a black window at desktop
resolution; it is alive and busy, error.log stays empty.  The game has no message loop: once per
frame it pulls posted messages with range-filtered PeekMessage calls (mouse, keyboard, system
commands - the last only to swallow the screen-saver command) and dispatches none of them.
Windows restores a minimised window by posting the system command SC_RESTORE to it, so the request
is removed from the queue and dropped; being activated while still minimised also defeats
DirectDraw's own window hook, which re-sets the exclusive display mode only during a proper
activation - afterwards every attempt to restore the drawing surfaces fails with DDERR_WRONGMODE.
The fix rewrites that per-frame block in place (107 bytes, 86 of them new code, the rest NOP):
the system-command peek hands every command except the screen saver to DefWindowProcA, so
SC_RESTORE, SC_MINIMIZE and the others take effect, and after an SC_RESTORE it calls
ShowWindow(SW_MINIMIZE) followed by ShowWindow(SW_RESTORE) - a deactivate/activate cycle on a window
that is not minimised at the moment of activation, which is the path DirectDraw's hook handles: it
re-sets the mode, the game's own per-frame surface restore repairs the surfaces and the next frame
is drawn.  The two peeks it replaces looked for WM_SETCURSOR and WM_DESTROY, messages Windows never
posts (dead code).  Second part: while minimised the game's main loop used to spin at 100 % of a
processor core - the per-frame present routine fails its blit, fails the surface restore and
returns early, so the Flip that normally paces the loop is never reached (about 4 400 passes per
second).  The branch taken after that failed restore now goes to a 12-byte stub in the spare tail
of the same block: Sleep(1) - one system timer period, at most 16 ms, well inside the 44 ms game
tick - then back to the routine's exit.  Game ticks are clock-driven and keep running while
minimised (a multiplayer client stays in the game), only the idle spin is gone.  The four calls go
through the linker's import thunks; nothing moves, no relocation entry changes.  Verified in game
21 Sep 2026 on both exes (Alt+Tab, taskbar button, Start menu, minimise from the taskbar).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # present(): failed surface restore -> idle stub instead of exit: the jne after restore_surfaces (taken while the window is minimised: BltFast DDERR_SURFACELOST, Restore DDERR_WRONGMODE) goes to the stub at 0x0042F293, which sleeps one timer period and continues to the original exit 0x0042E2A1 - the main loop no longer spins at 100% CPU while minimised, game ticks are clock-driven and unaffected
                    @{ Offset = 0x2D54F; Old = '0F 85 4C 01 00 00'; New = '0F 85 3E 11 00 00' }
                    # frame_end: posted WM_SYSCOMMAND dispatched, SC_RESTORE re-activates: the WM_SYSCOMMAND PeekMessageA(PM_REMOVE) keeps swallowing SC_SCREENSAVE but hands every other system command to DefWindowProcA(msg.hwnd, WM_SYSCOMMAND, wParam, lParam) - so the SC_RESTORE that Alt+Tab, the taskbar and Win+D post to a minimised window restores it; for SC_RESTORE it then calls ShowWindow(hwnd, SW_MINIMIZE) and ShowWindow(hwnd, SW_RESTORE), the deactivate/activate cycle on a non-iconic window that makes DirectDraw re-set the exclusive display mode; the two dead peeks for WM_SETCURSOR and WM_DESTROY (never posted) are replaced; bytes 86..97 are the idle stub for present(): Sleep(1) through the thunk 0x0047F008, then jmp to the present() exit 0x0042E2A1; the rest is NOP; calls through the import thunks 0x0047EFD8 / 0x0047EFBA / 0x0047EF90, no .reloc changes
                    @{ Offset = 0x2E63D; Old = '6A 01 68 12 01 00 00 68 12 01 00 00 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 09 81 7D EC 40 F1 00 00 74 45 6A 01 6A 20 6A 20 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 09 6A 00 2E FF 15 E0 03 48 00 6A 01 6A 02 6A 02 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 0E E8 11 F0 FF FF 6A 00 2E FF 15 D8 03 48 00'; New = '6A 01 68 12 01 00 00 68 12 01 00 00 6A 00 8D 45 E4 50 E8 84 FD 04 00 85 C0 74 50 81 7D EC 40 F1 00 00 74 47 FF 75 F0 FF 75 EC 68 12 01 00 00 FF 75 E4 E8 46 FD 04 00 81 7D EC 20 F1 00 00 75 2B 6A 06 FF 75 E4 E8 09 FD 04 00 6A 09 FF 75 E4 E8 FF FC 04 00 EB 15 6A 01 E8 6E FD 04 00 E9 02 F0 FF FF 90 90 90 90 90 90 90 90 90' }
                )
            }

            # ---- longpath: Sound files load from any folder depth: the wave loader no longer uses the 128-character OpenFile ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_longpath.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.29
            #  Changes    : 57 bytes in 4 edits
            #  Installed in a deep folder (about 128 characters of path and more, e.g. a repository ZIP
            #  extracted under Downloads and then moved into a sub-folder), the game shows "FILE NOT FOUND /
            #  A sound file is missing - see error.log" about five seconds after start and exits; error.log
            #  holds the line "unable to open file" with no name after it.  The same files run fine from a
            #  short path.  Cause: the routine that loads every WAV (sound banks, briefings, ambience) is the
            #  only code in the game that opens files through the Windows 3.1-era OpenFile function, which
            #  writes the full path into a 128-character field and fails outright when it does not fit.  All
            #  other loaders use the C runtime (CreateFileA underneath) and have no such limit, so the rest
            #  of the game runs and only the first sound kills it.  The empty name is a leftover of the
            #  "No CD" fix: the error message printed the buffer of the skipped CD attempt.  The fix replaces
            #  the two live OpenFile calls with calls to a 22-byte routine written over the first CD attempt
            #  (dead code since the "No CD" fix, which is therefore required): CreateFileA(name, GENERIC_READ,
            #  FILE_SHARE_READ, OPEN_EXISTING) - it returns -1 on failure exactly like OpenFile, and its
            #  handle is what the loader's seek, read and close calls take.  The error message now names the
            #  file that was tried.  Register-relative operands and a call through the import thunk only;
            #  nothing moves, no relocation entry changes; the same four edits at +0x60 in Council Wars.
            #  Verified 22 Sep 2026: from a 161-character game folder path the unfixed Council Wars exe fails
            #  at 5 s, the fixed one plays on with an empty error.log.
            @{
                Id = 'longpath'; Name = 'Sound files load from any folder depth: the wave loader no longer uses the 128-character OpenFile'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_longpath.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.29'
                Description = @'
Installed in a deep folder (about 128 characters of path and more, e.g. a repository ZIP
extracted under Downloads and then moved into a sub-folder), the game shows "FILE NOT FOUND /
A sound file is missing - see error.log" about five seconds after start and exits; error.log
holds the line "unable to open file" with no name after it.  The same files run fine from a
short path.  Cause: the routine that loads every WAV (sound banks, briefings, ambience) is the
only code in the game that opens files through the Windows 3.1-era OpenFile function, which
writes the full path into a 128-character field and fails outright when it does not fit.  All
other loaders use the C runtime (CreateFileA underneath) and have no such limit, so the rest
of the game runs and only the first sound kills it.  The empty name is a leftover of the
"No CD" fix: the error message printed the buffer of the skipped CD attempt.  The fix replaces
the two live OpenFile calls with calls to a 22-byte routine written over the first CD attempt
(dead code since the "No CD" fix, which is therefore required): CreateFileA(name, GENERIC_READ,
FILE_SHARE_READ, OPEN_EXISTING) - it returns -1 on failure exactly like OpenFile, and its
handle is what the loader's seek, read and close calls take.  The error message now names the
file that was tried.  Register-relative operands and a call through the import thunk only;
nothing moves, no relocation entry changes; the same four edits at +0x60 in Council Wars.
Verified 22 Sep 2026: from a 161-character game folder path the unfixed Council Wars exe fails
at 5 s, the fixed one plays on with an empty error.log.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('nocd')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # wave loader, first open (prefix+name): OpenFile(name,&ofs,OF_READ) -> lea eax,[ebp-80Eh]; call open_read 0x00452aef; 9 x nop
                    @{ Offset = 0x51EB7; Old = '6A 00 8D 45 F2 50 8D 85 F2 F7 FF FF 50 2E FF 15 C8 04 48 00'; New = '8D 85 F2 F7 FF FF E8 2D 00 00 00 90 90 90 90 90 90 90 90 90' }
                    # wave loader, second open (bare name): OpenFile(ebx,&ofs,OF_READ) -> mov eax,ebx; call open_read 0x00452aef; 7 x nop
                    @{ Offset = 0x51ED6; Old = '6A 00 8D 45 F2 50 53 2E FF 15 C8 04 48 00'; New = '89 D8 E8 12 00 00 00 90 90 90 90 90 90 90' }
                    # stub open_read over the dead first CD attempt: push 0,0,OPEN_EXISTING,0,FILE_SHARE_READ,GENERIC_READ,eax; call CreateFileA thunk 0x0047ef3c (IAT slot 0x004803f8); ret - returns the handle or -1 like OpenFile did
                    @{ Offset = 0x51EEF; Old = 'E8 AC 33 FB FF 8D BD F2 FB FF FF 89 C6 57 8A 06 88 07 3C 00 74 10'; New = '6A 00 6A 00 6A 03 6A 00 6A 01 68 00 00 00 80 50 E8 38 C4 02 00 C3' }
                    # error exit fprintf/MessageBox name: lea eax,[ebp-40Eh] (CD buffer, empty since nocd) -> lea eax,[ebp-80Eh] (prefix+name)
                    @{ Offset = 0x51FCD; Old = 'F2 FB FF FF'; New = 'F2 F7 FF FF' }
                )
            }

            # ---- music: Original CD soundtrack from MP3 files (MUSIC\TRACK02-05.MP3 / exp\music\track02-05.mp3) ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_music.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.31
            #  Changes    : 1790 bytes in 46 edits
            #  The soundtrack of both games was never a file: the CDs are mixed-mode discs with the music as
            #  audio tracks 2-5 after the data track, and the game plays them through Windows' CD-audio
            #  interface (MCI "cdaudio") - at the start of every battle it seeks to track 2 and plays the disc to
            #  its end, checks every five seconds whether the disc has stopped and then starts over at track 2,
            #  and stops the disc when the battle ends.  Without a CD-ROM drive that interface fails at start-up
            #  and the game is silent for good; the music slider of the options screen sets a "CD line" volume
            #  that modern sound drivers no longer have.
            #
            #  This fix rewrites the CD-audio routines in place (the seven entry points the music code calls
            #  keep their addresses) as an MP3 player on Windows' own MCI "mpegvideo" device (mciqtz32.dll,
            #  part of every Windows since 98; the exe imports nothing new): at battle start it opens and plays
            #  MUSIC\TRACK02.MP3, the five-second check plays the next file when one has ended and TRACK02
            #  again after the last one - the original "whole disc, repeat" - and the music slider now sets the
            #  volume of the playing file (the saved level is applied to every track).  Dark Colony reads
            #  MUSIC\TRACK0N.MP3, Council Wars exp\music\track0N.mp3, because both exes share one folder and
            #  the two discs have different music.  Everything inside the two rewritten routines; the
            #  relocation entries of the old code's absolute operands are re-pointed at the new ones and the
            #  rest become padding; nothing moves.
            #
            #  REQUIRES the eight tracks from the repository (encoded from the CD images at 192 kbit/s, 32 MB):
            #  MUSIC\TRACK02.MP3 .. TRACK05.MP3 for Dark Colony, exp\music\track02.mp3 .. track05.mp3 for
            #  Council Wars.  Without a TRACK02 file the game simply stays silent, as it does today.
            @{
                Id = 'music'; Name = 'Original CD soundtrack from MP3 files (MUSIC\TRACK02-05.MP3 / exp\music\track02-05.mp3)'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_music.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.31'
                Description = @'
The soundtrack of both games was never a file: the CDs are mixed-mode discs with the music as
audio tracks 2-5 after the data track, and the game plays them through Windows' CD-audio
interface (MCI "cdaudio") - at the start of every battle it seeks to track 2 and plays the disc to
its end, checks every five seconds whether the disc has stopped and then starts over at track 2,
and stops the disc when the battle ends.  Without a CD-ROM drive that interface fails at start-up
and the game is silent for good; the music slider of the options screen sets a "CD line" volume
that modern sound drivers no longer have.

This fix rewrites the CD-audio routines in place (the seven entry points the music code calls
keep their addresses) as an MP3 player on Windows' own MCI "mpegvideo" device (mciqtz32.dll,
part of every Windows since 98; the exe imports nothing new): at battle start it opens and plays
MUSIC\TRACK02.MP3, the five-second check plays the next file when one has ended and TRACK02
again after the last one - the original "whole disc, repeat" - and the music slider now sets the
volume of the playing file (the saved level is applied to every track).  Dark Colony reads
MUSIC\TRACK0N.MP3, Council Wars exp\music\track0N.mp3, because both exes share one folder and
the two discs have different music.  Everything inside the two rewritten routines; the
relocation entries of the old code's absolute operands are re-pointed at the new ones and the
rest become padding; nothing moves.

REQUIRES the eight tracks from the repository (encoded from the CD images at 192 kbit/s, 32 MB):
MUSIC\TRACK02.MP3 .. TRACK05.MP3 for Dark Colony, exp\music\track02.mp3 .. track05.mp3 for
Council Wars.  Without a TRACK02 file the game simply stays silent, as it does today.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (4; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'MUSIC\TRACK02.MP3'
                    'MUSIC\TRACK03.MP3'
                    'MUSIC\TRACK04.MP3'
                    'MUSIC\TRACK05.MP3'
                )
                Edits = @(
                    # cdaudio module -> MP3 player on MCI mpegvideo (seven entry points kept: cd_open +0, play_from_here +0x3C, close +0x88, stop +0xB8, tracks +0x338, seek_track +0x4E8, mode +0x6E0; helpers, "mpegvideo" and the path template "music\\track0?.mp3" inside; the rest zero)
                    @{ Offset = 0x504D0; Old = '51 52 55 89 E5 83 EC 14 8D 45 EC 50 68 00 21 00 00 68 03 08 00 00 31 D2 B9 1C 7C 48 00 52 89 55 F0 89 4D F4 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F0 89 EC 5D 5A 59 C3 53 51 52 55 89 E5 83 EC 18 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 0A 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 75 15 8D 45 E8 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 5B C3 51 52 55 89 E5 6A 00 6A 00 68 04 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 06 31 C0 5D 5A 59 C3 B8 01 00 00 00 5D 5A 59 C3 8B C0 51 52 55 89 E5 83 EC 04 8D 55 FC 52 6A 00 68 08 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 C3 53 51 52 55 89 E5 83 EC 20 8D 5D E0 53 68 00 01 00 00 31 DB 68 14 08 00 00 66 89 C3 BA 04 00 00 00 53 89 55 E8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 4E 81 7D E4 0D 02 00 00 75 20 8D 45 F0 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 29 31 C0 89 EC 5D 5A 59 5B C3 8D 45 FC 50 6A 00 68 09 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5A 59 5B C3 B8 01 00 00 00 89 EC 5D 5A 59 5B C3 8D 40 00 53 51 52 56 57 55 89 E5 83 EC 28 89 C3 8D 45 D8 50 68 00 01 00 00 31 F6 68 14 08 00 00 66 89 DE BA 08 00 00 00 56 89 55 E0 2E FF 15 70 05 48 00 85 C0 74 07 31 C0 E9 A7 00 00 00 8B 45 DC 89 45 FC 8D 45 D8 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 56 89 4D E0 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8B 75 FC 8B 7D DC 46 BA 08 00 00 00 39 FE 76 0C B8 02 00 00 00 BE 01 00 00 00 EB 0A 8A 45 FC FE C0 25 FF 00 00 00 89 45 F8 8D 45 F4 50 52 68 07 08 00 00 81 E3 FF FF 00 00 53 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8D 45 E8 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 89 F0 89 EC 5D 5F 5E 5A 59 5B C3 90 53 51 52 56 57 55 89 E5 83 EC 24 89 C6 8D 45 DC 50 68 00 01 00 00 31 FF 68 14 08 00 00 66 89 F7 BA 08 00 00 00 57 89 55 E4 2E FF 15 70 05 48 00 85 C0 74 07 31 C0 E9 9A 00 00 00 8D 45 DC 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 57 8B 5D E0 89 4D E4 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 BF 08 00 00 00 83 FB 01 75 08 8A 45 E0 8B 5D E0 EB 0A 88 D8 FE C8 25 FF 00 00 00 4B 89 45 FC 8D 45 F8 50 57 68 07 08 00 00 81 E6 FF FF 00 00 56 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8D 45 EC 50 6A 00 68 06 08 00 00 56 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 89 D8 89 EC 5D 5F 5E 5A 59 5B C3 8B C0 51 52 55 89 E5 83 EC 10 C7 45 F8 03 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F4 89 EC 5D 5A 59 C3 90 51 52 55 89 E5 83 EC 10 C7 45 F8 08 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F4 89 EC 5D 5A 59 C3 90 53 51 52 55 89 E5 83 EC 1C 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 0A 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 2E 8D 45 E4 50 68 00 01 00 00 68 14 08 00 00 B9 02 00 00 00 53 89 4D EC 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5A 59 5B C3 8B 45 E8 89 EC 5D 5A 59 5B C3 8D 40 00 53 51 52 56 55 89 E5 83 EC 1C 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 02 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 5B 8D 45 E4 50 68 00 01 00 00 68 14 08 00 00 B9 02 00 00 00 53 89 4D EC 2E FF 15 70 05 48 00 85 C0 74 0A 31 C0 89 EC 5D 5E 5A 59 5B C3 8D 45 F4 50 68 00 04 00 00 68 0D 08 00 00 BE 0A 00 00 00 53 89 75 F8 2E FF 15 70 05 48 00 85 C0 74 0A 31 C0 89 EC 5D 5E 5A 59 5B C3 8B 45 E8 89 EC 5D 5E 5A 59 5B C3 51 52 55 89 E5 83 EC 0C 8D 55 F4 52 68 00 01 00 00 68 0D 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 C3 90 55 89 E5 5D C3 8D 40 00 53 51 56 55 89 E5 83 EC 20 88 D3 8D 75 EC 56 68 00 04 00 00 31 F6 68 0D 08 00 00 66 89 C6 BA 0A 00 00 00 56 89 55 F0 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 4E 88 D8 89 45 FC 8D 45 F8 50 6A 08 68 07 08 00 00 81 E3 FF 00 00 00 56 43 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5E 59 5B C3 8D 45 E0 50 6A 00 68 06 08 00 00 56 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5E 59 5B C3 89 D8 89 EC 5D 5E 59 5B C3 90 55 89 E5 31 C0 5D C3 90 53 51 52 56 57 55 89 E5 83 EC 20 89 C6 8D 45 F0 50 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 F3 BA 02 00 00 00 53 89 55 F4 2E FF 15 70 05 48 00 89 C7 85 C0 74 18 6A 00 6A 00 68 04 08 00 00 53 2E FF 15 70 05 48 00 89 F8 E9 EF 00 00 00 8D 45 E0 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 53 89 4D E8 2E FF 15 70 05 48 00 89 C7 85 C0 74 1C 6A 00 6A 00 68 04 08 00 00 53 2E FF 15 70 05 48 00 89 F8 89 EC 5D 5F 5E 5A 59 5B C3 8B 45 E4 A3 0C 28 53 00 83 F8 14 7C 05 B8 14 00 00 00 BB 01 00 00 00 A3 0C 28 53 00 3B 1D 0C 28 53 00 0F 8F 85 00 00 00 C7 45 E8 02 00 00 00 8D 45 E0 50 68 10 01 00 00 31 C0 68 14 08 00 00 66 89 F0 50 89 5D EC 89 45 FC 2E FF 15 70 05 48 00 89 C7 85 C0 74 1F 6A 00 6A 00 68 04 08 00 00 8B 4D FC 51 2E FF 15 70 05 48 00 89 F8 89 EC 5D 5F 5E 5A 59 5B C3 8D 7B FF 8D 04 BD 00 00 00 00 29 F8 89 C7 8A 45 E4 88 87 D0 27 53 00 31 C0 66 8B 45 E4 C1 F8 08 88 87 D1 27 53 00 8B 45 E4 C1 E8 10 43 88 87 D2 27 53 00 E9 6F FF FF FF 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8B C0 55 89 E5 25 FF FF 00 00 E8 A3 FC FF FF 39 D0 76 07 B8 01 00 00 00 5D C3 31 C0 5D C3 51 52 55 89 E5 83 EC 10 C7 45 F8 04 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 07 B8 04 00 00 00 EB 36 8B 4D F4 81 F9 12 02 00 00 75 0B B8 01 00 00 00 89 EC 5D 5A 59 C3 81 F9 0C 02 00 00 75 0B B8 02 00 00 00 89 EC 5D 5A 59 C3 81 F9 0D 02 00 00 75 05 B8 03 00 00 00 89 EC 5D 5A 59 C3'; New = 'E8 DB 00 00 00 A1 E8 8D 48 00 6B C0 64 A3 D8 27 53 00 B8 02 00 00 00 E8 F4 00 00 00 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 31 C0 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 EB 56 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 A1 D0 27 53 00 85 C0 74 10 6A 00 6A 00 68 08 08 00 00 50 FF 15 70 05 48 00 31 C0 5A 59 C3 00 00 00 00 00 00 00 00 51 52 A1 D0 27 53 00 85 C0 74 17 6A 00 6A 00 68 04 08 00 00 50 FF 15 70 05 48 00 31 C0 A3 D0 27 53 00 5A 59 C3 00 00 00 00 00 00 00 00 00 00 00 51 52 56 57 55 89 E5 83 EC 14 89 C2 BE AC 12 45 00 BF DC 27 53 00 B9 06 00 00 00 F3 A5 04 30 A2 E8 27 53 00 89 15 D4 27 53 00 31 C0 89 45 EC 89 45 F0 C7 45 F4 A0 12 45 00 C7 45 F8 DC 27 53 00 89 45 FC 8D 45 EC 50 68 02 22 00 00 68 03 08 00 00 6A 00 FF 15 70 05 48 00 85 C0 75 1A 8B 45 F0 A3 D0 27 53 00 8B 0D D8 27 53 00 E8 80 00 00 00 A1 D0 27 53 00 EB 02 31 C0 89 EC 5D 5F 5E 5A 59 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 55 89 E5 83 EC 0C 31 D2 89 55 F4 89 55 F8 89 55 FC 8D 55 F4 52 6A 00 68 06 08 00 00 50 FF 15 70 05 48 00 89 EC 5D 5A 59 C3 00 00 00 00 00 6D 70 65 67 76 69 64 65 6F 00 00 00 6D 75 73 69 63 5C 74 72 61 63 6B 30 3F 2E 6D 70 33 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 55 89 E5 83 EC 18 31 D2 89 55 E8 C7 45 EC 02 40 00 00 89 4D F0 89 55 F4 89 55 F8 89 55 FC 8D 55 E8 52 68 00 00 80 01 68 73 08 00 00 50 FF 15 70 05 48 00 89 EC 5D 5A 59 C3 00 00 00 00 00 51 52 55 89 E5 83 EC 10 A1 D0 27 53 00 85 C0 74 66 31 D2 89 55 F0 89 55 F4 C7 45 F8 04 00 00 00 89 55 FC 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 50 FF 15 70 05 48 00 85 C0 75 3B 81 7D F4 0D 02 00 00 75 2A 8B 15 D4 27 53 00 42 E8 4F FE FF FF 89 D0 E8 78 FE FF FF 85 C0 75 0E B8 02 00 00 00 E8 6A FE FF FF 85 C0 74 0D E8 F1 FE FF FF 31 C0 89 EC 5D 5A 59 C3 B8 04 00 00 00 EB F3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 31 C0 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 52 E8 F2 FB FF FF 0F B6 C2 E8 1A FC FF FF 85 C0 74 0B E8 A1 FC FF FF 0F B6 C2 40 5A C3 31 C0 5A C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 E9 5B FB FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' }
                    # set_volume method 0: aux CD-audio device walk -> store level*100, MCI_SETAUDIO volume on the open element (the rest zero)
                    @{ Offset = 0x51C70; Old = '53 51 52 56 57 55 89 E5 83 EC 34 89 C7 2E FF 15 68 05 48 00 89 45 FC 31 F6 3B 75 FC 73 47 BB 30 00 00 00 8D 45 CC 31 D2 E8 AF 97 02 00 6A 30 8D 45 CC 50 56 2E FF 15 64 05 48 00 85 C0 75 23 66 83 7D F4 01 75 1C 8D 04 BD 00 00 00 00 29 F8 C1 E0 0B 89 C2 C1 E2 10 09 D0 50 56 2E FF 15 6C 05 48 00 46 EB B4 89 EC 5D 5F 5E 5A 59 5B C3'; New = '51 6B C8 64 89 0D D8 27 53 00 A1 D0 27 53 00 85 C0 74 05 E8 48 EA FF FF 59 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' }
                    # .reloc table: entry 30E9 -> 30D6: the absolute operand moved from page offset 0x0E9 to 0x0D6, entry follows it
                    @{ Offset = 0x9BE72; Old = 'E9 30'; New = 'D6 30' }
                    # .reloc table: entry 30F7 -> 30DE: the absolute operand moved from page offset 0x0F7 to 0x0DE, entry follows it
                    @{ Offset = 0x9BE74; Old = 'F7 30'; New = 'DE 30' }
                    # .reloc table: entry 3134 -> 318B: the absolute operand moved from page offset 0x134 to 0x18B, entry follows it
                    @{ Offset = 0x9BE76; Old = '34 31'; New = '8B 31' }
                    # .reloc table: entry 314B -> 319F: the absolute operand moved from page offset 0x14B to 0x19F, entry follows it
                    @{ Offset = 0x9BE78; Old = '4B 31'; New = '9F 31' }
                    # .reloc table: entry 316F -> 31B3: the absolute operand moved from page offset 0x16F to 0x1B3, entry follows it
                    @{ Offset = 0x9BE7A; Old = '6F 31'; New = 'B3 31' }
                    # .reloc table: entry 31A4 -> 31C7: the absolute operand moved from page offset 0x1A4 to 0x1C7, entry follows it
                    @{ Offset = 0x9BE7C; Old = 'A4 31'; New = 'C7 31' }
                    # .reloc table: entry 31D8 -> 31CE: the absolute operand moved from page offset 0x1D8 to 0x1CE, entry follows it
                    @{ Offset = 0x9BE7E; Old = 'D8 31'; New = 'CE 31' }
                    # .reloc table: entry 31FC -> 31ED: the absolute operand moved from page offset 0x1FC to 0x1ED, entry follows it
                    @{ Offset = 0x9BE80; Old = 'FC 31'; New = 'ED 31' }
                    # .reloc table: entry 321C -> 31F2: the absolute operand moved from page offset 0x21C to 0x1F2, entry follows it
                    @{ Offset = 0x9BE82; Old = '1C 32'; New = 'F2 31' }
                    # .reloc table: entry 3268 -> 3200: the absolute operand moved from page offset 0x268 to 0x200, entry follows it
                    @{ Offset = 0x9BE84; Old = '68 32'; New = '00 32' }
                    # .reloc table: entry 3297 -> 3206: the absolute operand moved from page offset 0x297 to 0x206, entry follows it
                    @{ Offset = 0x9BE86; Old = '97 32'; New = '06 32' }
                    # .reloc table: entry 32E7 -> 3215: the absolute operand moved from page offset 0x2E7 to 0x215, entry follows it
                    @{ Offset = 0x9BE88; Old = 'E7 32'; New = '15 32' }
                    # .reloc table: entry 3309 -> 321C: the absolute operand moved from page offset 0x309 to 0x21C, entry follows it
                    @{ Offset = 0x9BE8A; Old = '09 33'; New = '1C 32' }
                    # .reloc table: entry 3354 -> 3235: the absolute operand moved from page offset 0x354 to 0x235, entry follows it
                    @{ Offset = 0x9BE8C; Old = '54 33'; New = '35 32' }
                    # .reloc table: entry 3380 -> 3241: the absolute operand moved from page offset 0x380 to 0x241, entry follows it
                    @{ Offset = 0x9BE8E; Old = '80 33'; New = '41 32' }
                    # .reloc table: entry 33C6 -> 3247: the absolute operand moved from page offset 0x3C6 to 0x247, entry follows it
                    @{ Offset = 0x9BE90; Old = 'C6 33'; New = '47 32' }
                    # .reloc table: entry 33E8 -> 3251: the absolute operand moved from page offset 0x3E8 to 0x251, entry follows it
                    @{ Offset = 0x9BE92; Old = 'E8 33'; New = '51 32' }
                    # .reloc table: entry 342E -> 3291: the absolute operand moved from page offset 0x42E to 0x291, entry follows it
                    @{ Offset = 0x9BE94; Old = '2E 34'; New = '91 32' }
                    # .reloc table: entry 346A -> 3301: the absolute operand moved from page offset 0x46A to 0x301, entry follows it
                    @{ Offset = 0x9BE96; Old = '6A 34'; New = '01 33' }
                    # .reloc table: entry 34A8 -> 3319: the absolute operand moved from page offset 0x4A8 to 0x319, entry follows it
                    @{ Offset = 0x9BE98; Old = 'A8 34'; New = '19 33' }
                    # .reloc table: entry 34CE -> 3344: the absolute operand moved from page offset 0x4CE to 0x344, entry follows it
                    @{ Offset = 0x9BE9A; Old = 'CE 34'; New = '44 33' }
                    # .reloc table: entry 3515 -> 3357: the absolute operand moved from page offset 0x515 to 0x357, entry follows it
                    @{ Offset = 0x9BE9C; Old = '15 35'; New = '57 33' }
                    # .reloc table: entry 353B (type 3 HIGHLOW, page offset 0x53B) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BE9E; Old = '3B 35'; New = '00 00' }
                    # .reloc table: entry 3567 (type 3 HIGHLOW, page offset 0x567) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEA0; Old = '67 35'; New = '00 00' }
                    # .reloc table: entry 35A3 (type 3 HIGHLOW, page offset 0x5A3) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEA2; Old = 'A3 35'; New = '00 00' }
                    # .reloc table: entry 35E2 (type 3 HIGHLOW, page offset 0x5E2) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEA4; Old = 'E2 35'; New = '00 00' }
                    # .reloc table: entry 3609 (type 3 HIGHLOW, page offset 0x609) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEA6; Old = '09 36'; New = '00 00' }
                    # .reloc table: entry 3629 (type 3 HIGHLOW, page offset 0x629) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEA8; Old = '29 36'; New = '00 00' }
                    # .reloc table: entry 3678 (type 3 HIGHLOW, page offset 0x678) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEAA; Old = '78 36'; New = '00 00' }
                    # .reloc table: entry 368F (type 3 HIGHLOW, page offset 0x68F) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEAC; Old = '8F 36'; New = '00 00' }
                    # .reloc table: entry 36B4 (type 3 HIGHLOW, page offset 0x6B4) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEAE; Old = 'B4 36'; New = '00 00' }
                    # .reloc table: entry 36CB (type 3 HIGHLOW, page offset 0x6CB) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEB0; Old = 'CB 36'; New = '00 00' }
                    # .reloc table: entry 36DE (type 3 HIGHLOW, page offset 0x6DE) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEB2; Old = 'DE 36'; New = '00 00' }
                    # .reloc table: entry 36F2 (type 3 HIGHLOW, page offset 0x6F2) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEB4; Old = 'F2 36'; New = '00 00' }
                    # .reloc table: entry 36F8 (type 3 HIGHLOW, page offset 0x6F8) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEB6; Old = 'F8 36'; New = '00 00' }
                    # .reloc table: entry 3726 (type 3 HIGHLOW, page offset 0x726) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEB8; Old = '26 37'; New = '00 00' }
                    # .reloc table: entry 3740 (type 3 HIGHLOW, page offset 0x740) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEBA; Old = '40 37'; New = '00 00' }
                    # .reloc table: entry 3762 (type 3 HIGHLOW, page offset 0x762) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEBC; Old = '62 37'; New = '00 00' }
                    # .reloc table: entry 3771 (type 3 HIGHLOW, page offset 0x771) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEBE; Old = '71 37'; New = '00 00' }
                    # .reloc table: entry 377E (type 3 HIGHLOW, page offset 0x77E) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEC0; Old = '7E 37'; New = '00 00' }
                    # .reloc table: entry 37D6 (type 3 HIGHLOW, page offset 0x7D6) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9BEC2; Old = 'D6 37'; New = '00 00' }
                    # .reloc table: entry 3880 -> 3876: the absolute operand moved from page offset 0x880 to 0x876, entry follows it
                    @{ Offset = 0x9C0F0; Old = '80 38'; New = '76 38' }
                    # .reloc table: entry 38A7 -> 387B: the absolute operand moved from page offset 0x8A7 to 0x87B, entry follows it
                    @{ Offset = 0x9C0F2; Old = 'A7 38'; New = '7B 38' }
                    # .reloc table: entry 38CE (type 3 HIGHLOW, page offset 0x8CE) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0F4; Old = 'CE 38'; New = '00 00' }
                )
            }

            # ---- movies @ 640x480: Classic movies under their own names: DCINTRO / DCAENDING / DCHENDING (Dark Colony only) ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_movies.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.18
            #  Changes    : 17 bytes in 3 edits
            #  Since 15 Sep 2026 both games run from the "DC - Council wars" folder.  Council Wars has its own
            #  INTRO.AVI, AENDING.AVI and HENDING.AVI, so the Classic movies live beside them as AVI/DCINTRO.AVI,
            #  DCAENDING.AVI and DCHENDING.AVI.  Without this fix the Classic exe in that folder plays the Council
            #  Wars intro and endings.  The intro name is one data-section string, "intro.avi", appended to "avi/"
            #  at start-up and by the PLAY INTRO button; the linker aligned the next string to 4 bytes, so
            #  "intro.avi" plus its two padding zeros is exactly the 12 bytes of "dcintro.avi" - rewritten in
            #  place, same address, no code and no relocation entry changes.  The two campaign endings are not in
            #  the exe at all: line 154 of the campaign lists HSCENE.TXT / GSCENE.TXT names them, and the patched exe
            #  reads those lists from INTRF_HD/ (fix "Interface data from INTRF_HD"), where they say
            #  "avi/dchending.avi" / "avi/dcaending.avi" in the repository.  The stock GAMESTAT/ lists that the
            #  untouched exe reads keep the stock names.  REQUIRES the three AVI files DCINTRO.AVI, DCAENDING.AVI,
            #  DCHENDING.AVI in the AVI folder next to the exe (the two INTRF_HD lists come with the "Interface
            #  data from INTRF_HD" fix).  Dark Colony only: the Council Wars exe's intro.avi is its own intro.
            @{
                Id = 'movies'; Name = 'Classic movies under their own names: DCINTRO / DCAENDING / DCHENDING (Dark Colony only)'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '640x480'
                Tool = 'tools/patch_movies.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.18'
                Description = @'
Since 15 Sep 2026 both games run from the "DC - Council wars" folder.  Council Wars has its own
INTRO.AVI, AENDING.AVI and HENDING.AVI, so the Classic movies live beside them as AVI/DCINTRO.AVI,
DCAENDING.AVI and DCHENDING.AVI.  Without this fix the Classic exe in that folder plays the Council
Wars intro and endings.  The intro name is one data-section string, "intro.avi", appended to "avi/"
at start-up and by the PLAY INTRO button; the linker aligned the next string to 4 bytes, so
"intro.avi" plus its two padding zeros is exactly the 12 bytes of "dcintro.avi" - rewritten in
place, same address, no code and no relocation entry changes.  The two campaign endings are not in
the exe at all: line 154 of the campaign lists HSCENE.TXT / GSCENE.TXT names them, and the patched exe
reads those lists from INTRF_HD/ (fix "Interface data from INTRF_HD"), where they say
"avi/dchending.avi" / "avi/dcaending.avi" in the repository.  The stock GAMESTAT/ lists that the
untouched exe reads keep the stock names.  REQUIRES the three AVI files DCINTRO.AVI, DCAENDING.AVI,
DCHENDING.AVI in the AVI folder next to the exe (the two INTRF_HD lists come with the "Interface
data from INTRF_HD" fix).  Dark Colony only: the Council Wars exe's intro.avi is its own intro.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (5; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'AVI\DCINTRO.AVI'
                    'AVI\DCAENDING.AVI'
                    'AVI\DCHENDING.AVI'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                )
                Edits = @(
                    # DGROUP string "gamestat/hscene" -> "gamestat/hscndc": 68 73 63 65 6e 65 -> 68 73 63 6e 64 63; the exe appends ".txt", so it reads GAMESTAT/HSCNDC.TXT - a copy of the stock HSCENE.TXT naming the Classic ending, written by the patcher; the stock list stays untouched for the original exe
                    @{ Offset = 0x7FA19; Old = '68 73 63 65 6E 65'; New = '68 73 63 6E 64 63' }
                    # DGROUP string "gamestat/gscene" -> "gamestat/gscndc": 67 73 63 65 6e 65 -> 67 73 63 6e 64 63; the exe appends ".txt", so it reads GAMESTAT/GSCNDC.TXT - a copy of the stock GSCENE.TXT naming the Classic ending, written by the patcher; the stock list stays untouched for the original exe
                    @{ Offset = 0x7FA29; Old = '67 73 63 65 6E 65'; New = '67 73 63 6E 64 63' }
                    # DGROUP string "intro.avi" -> "dcintro.avi": 69 6e 74 72 6f 2e 61 76 69 00 00 00 -> 64 63 69 6e 74 72 6f 2e 61 76 69 00; the movie name appended to "avi/" at start-up (0x004053A7) and by PLAY INTRO (0x004050FE); "intro.avi\0" plus its two alignment padding zeros is exactly 12 bytes, so the string grows in place, its address and the .reloc table are unchanged
                    @{ Offset = 0x7FCA8; Old = '69 6E 74 72 6F 2E 61 76 69 00 00 00'; New = '64 63 69 6E 74 72 6F 2E 61 76 69 00' }
                )
            }

            # ---- movies: Classic movies under their own names: DCINTRO / DCAENDING / DCHENDING (Dark Colony only) ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_movies.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.18
            #  Changes    : 11 bytes in 1 edits
            #  Since 15 Sep 2026 both games run from the "DC - Council wars" folder.  Council Wars has its own
            #  INTRO.AVI, AENDING.AVI and HENDING.AVI, so the Classic movies live beside them as AVI/DCINTRO.AVI,
            #  DCAENDING.AVI and DCHENDING.AVI.  Without this fix the Classic exe in that folder plays the Council
            #  Wars intro and endings.  The intro name is one data-section string, "intro.avi", appended to "avi/"
            #  at start-up and by the PLAY INTRO button; the linker aligned the next string to 4 bytes, so
            #  "intro.avi" plus its two padding zeros is exactly the 12 bytes of "dcintro.avi" - rewritten in
            #  place, same address, no code and no relocation entry changes.  The two campaign endings are not in
            #  the exe at all: line 154 of the campaign lists HSCENE.TXT / GSCENE.TXT names them, and the patched exe
            #  reads those lists from INTRF_HD/ (fix "Interface data from INTRF_HD"), where they say
            #  "avi/dchending.avi" / "avi/dcaending.avi" in the repository.  The stock GAMESTAT/ lists that the
            #  untouched exe reads keep the stock names.  REQUIRES the three AVI files DCINTRO.AVI, DCAENDING.AVI,
            #  DCHENDING.AVI in the AVI folder next to the exe (the two INTRF_HD lists come with the "Interface
            #  data from INTRF_HD" fix).  Dark Colony only: the Council Wars exe's intro.avi is its own intro.
            @{
                Id = 'movies'; Name = 'Classic movies under their own names: DCINTRO / DCAENDING / DCHENDING (Dark Colony only)'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = 'hd'
                Tool = 'tools/patch_movies.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.18'
                Description = @'
Since 15 Sep 2026 both games run from the "DC - Council wars" folder.  Council Wars has its own
INTRO.AVI, AENDING.AVI and HENDING.AVI, so the Classic movies live beside them as AVI/DCINTRO.AVI,
DCAENDING.AVI and DCHENDING.AVI.  Without this fix the Classic exe in that folder plays the Council
Wars intro and endings.  The intro name is one data-section string, "intro.avi", appended to "avi/"
at start-up and by the PLAY INTRO button; the linker aligned the next string to 4 bytes, so
"intro.avi" plus its two padding zeros is exactly the 12 bytes of "dcintro.avi" - rewritten in
place, same address, no code and no relocation entry changes.  The two campaign endings are not in
the exe at all: line 154 of the campaign lists HSCENE.TXT / GSCENE.TXT names them, and the patched exe
reads those lists from INTRF_HD/ (fix "Interface data from INTRF_HD"), where they say
"avi/dchending.avi" / "avi/dcaending.avi" in the repository.  The stock GAMESTAT/ lists that the
untouched exe reads keep the stock names.  REQUIRES the three AVI files DCINTRO.AVI, DCAENDING.AVI,
DCHENDING.AVI in the AVI folder next to the exe (the two INTRF_HD lists come with the "Interface
data from INTRF_HD" fix).  Dark Colony only: the Council Wars exe's intro.avi is its own intro.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (3; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'AVI\DCINTRO.AVI'
                    'AVI\DCAENDING.AVI'
                    'AVI\DCHENDING.AVI'
                )
                Edits = @(
                    # DGROUP string "intro.avi" -> "dcintro.avi": 69 6e 74 72 6f 2e 61 76 69 00 00 00 -> 64 63 69 6e 74 72 6f 2e 61 76 69 00; the movie name appended to "avi/" at start-up (0x004053A7) and by PLAY INTRO (0x004050FE); "intro.avi\0" plus its two alignment padding zeros is exactly 12 bytes, so the string grows in place, its address and the .reloc table are unchanged
                    @{ Offset = 0x7FCA8; Old = '69 6E 74 72 6F 2E 61 76 69 00 00 00'; New = '64 63 69 6E 74 72 6F 2E 61 76 69 00' }
                )
            }

            # ---- sounds: WAV files read from the game root, not exp/: the Classic briefings and water ambience (Dark Colony only) ---------------------------------------------------------
            #  Added      : 19 Sep 2026
            #  Made with  : tools/patch_wavprefix.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.21
            #  Changes    : 4 bytes in 1 edits
            #  Classic and Council Wars are one code base.  Council Wars opens its files through a helper that
            #  puts "exp/" in front of every name and falls back to the bare name; the Classic build has no such
            #  prefix - except in the wave loader, the function that opens the mission briefings (mission/h1.wav,
            #  g1.wav ...) and every other WAV.  Its own 8-byte prefix slot still says "exp/" in the Classic exe.
            #  In the old "DC - Classic" folder no exp/ tree existed, so that first attempt always failed and
            #  nothing was noticed.  Since both games share the "DC - Council wars" folder, exp/mission/h1-h8.wav
            #  and g1-g8.wav are the Council Wars briefings and exp/sound/water.wav the Council Wars water sound:
            #  the Classic exe found them first and played the wrong briefings for missions 1-8.  The fix empties
            #  the prefix (the four letters become NUL) so the loader opens MISSION/ and SOUND/ directly.  Data
            #  only, in place, no code and no relocation entry changes.
            @{
                Id = 'sounds'; Name = 'WAV files read from the game root, not exp/: the Classic briefings and water ambience (Dark Colony only)'; Date = '19 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_wavprefix.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.21'
                Description = @'
Classic and Council Wars are one code base.  Council Wars opens its files through a helper that
puts "exp/" in front of every name and falls back to the bare name; the Classic build has no such
prefix - except in the wave loader, the function that opens the mission briefings (mission/h1.wav,
g1.wav ...) and every other WAV.  Its own 8-byte prefix slot still says "exp/" in the Classic exe.
In the old "DC - Classic" folder no exp/ tree existed, so that first attempt always failed and
nothing was noticed.  Since both games share the "DC - Council wars" folder, exp/mission/h1-h8.wav
and g1-g8.wav are the Council Wars briefings and exp/sound/water.wav the Council Wars water sound:
the Classic exe found them first and played the wrong briefings for missions 1-8.  The fix empties
the prefix (the four letters become NUL) so the loader opens MISSION/ and SOUND/ directly.  Data
only, in place, no code and no relocation entry changes.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # DGROUP string "exp/" -> "" (wave-loader prefix): 65 78 70 2f -> 00 00 00 00; the wave loader (0x00452A50) builds prefix+name first and falls back to the bare name, so in the shared Council Wars folder the Classic exe played exp/mission/h1-h8.wav, g1-g8.wav (the Council Wars briefings) and exp/sound/water.wav instead of the Classic files in MISSION/ and SOUND/; the slot is data only, same address, no code and no .reloc entry changes
                    @{ Offset = 0x855C0; Old = '65 78 70 2F'; New = '00 00 00 00' }
                )
            }
        )
    }
    # ---------------------------------------------------------------------------------------------
    #  Dark Colony - The Council Wars ENGEXP16.EXE, 659968 bytes (patched build: engexp16new.exe; called DCEXP16.EXE 10-15 Sep 2026)
    # ---------------------------------------------------------------------------------------------
    @{
        Id             = 'CouncilWars'
        Title          = 'Dark Colony - The Council Wars ENGEXP16.EXE, 659968 bytes (patched build: engexp16new.exe; called DCEXP16.EXE 10-15 Sep 2026)'
        OriginalName   = 'ENGEXP16.EXE'
        OutputName     = 'engexp16new.exe'
        Size           = 659968
        OriginalSha256 = '3b930ba92cfd07ab4403c499d5251d604e660f4e8b092303691315e13a1737f4'   # untouched original
        PatchedSha256  = 'bfba1bd5d11fa229068ebd53f673f6b02d7a3a7d3cb8237db7bd0336c0458ffe'   # every patch applied in the default resolution = the exe in the repository
        # screen resolutions this build can be patched for: '640x480' = the stock size (no display fixes),
        # the others select the per-resolution variants of the 'resolution' and 'clock' fixes below
        Modes          = @('640x480', '1024x768', '1280x1024', '1280x720', '1280x800', '3840x1080')
        DefaultMode    = '1024x768'
        # SHA-256 with every fix of that resolution applied (the default one is the published exe)
        ReferenceSha256 = @{ '640x480' = '99071b792cdf04ee5a9e586654196d37d03540edfe1a24a88129c569f7a23531'; '1024x768' = 'bfba1bd5d11fa229068ebd53f673f6b02d7a3a7d3cb8237db7bd0336c0458ffe'; '1280x1024' = '892fba96276bd8661f37433f31d9c9d145d7573dbde3711ab8098c1fe455fd72'; '1280x720' = '155be4958e4a6a2be70b807005df6001c58b63be1d4fc13e152d7e917c54b39a'; '1280x800' = '47eafe9e9621ab27caf0fe5bdd2ca2cc11610ee57abca677ce8cfc64ef5f10a9'; '3840x1080' = '33d276019c661736272aca3bf64477f87ae0277dbcc5c1b359fa2c3795cbc779' }
        Patches        = @(

            # ---- nocd: No CD: the game neither needs the disc nor touches the CD path ---------------------------------------------------------
            #  Added      : 28-30 Sep 2025 / 18 Sep 2026 / 21 Sep 2026
            #  Made with  : tools/patch_nocd.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.19; CLAUDE.md "Patches applied so far" (the 2025 bytes)
            #  Changes    : 198 bytes in 19 edits
            #  The game refuses to start, and greys out most main-menu buttons, when it cannot find its
            #  CD in a drive.  This one fix removes the whole CD business from the exe:
            #
            #    1. The two menu tests of the "CD present" flag ("call cd_flag ; test al,al ; jne ok") become
            #       unconditional jumps (opcode 75 -> EB): the game starts and keeps every menu button without
            #       the disc.  Council Wars has a third test that threw the player out of a running game; that
            #       one is inverted (75 -> 74).  These are the three bytes hand-patched in 2025.
            #    2. Those bypasses alone only ignore the ANSWER of the test.  Until 18 Sep 2026 the machinery
            #       itself still ran: at start-up the game opened HBNFUFL.A01 / HBNFUFL.A02 (the drive letter
            #       its installer recorded, "D:" in the repository; a missing file was a silent exit), built the
            #       path "D:\dc\" and probed it - it opened D:\dc\anim.dat and, if that existed, tried to
            #       create a file there to see whether the medium refuses writes.  The same probe ran again at
            #       every menu screen and periodically during a battle, two loaders fell back to "D:\dc\<name>"
            #       when a file was missing locally, the sound loader then asked to "insert The Dark Colony CD
            #       and Restart", and the movie opener fell back to the CD when the flag said the disc was in.
            #       The game never tells Windows to fail such accesses quietly (no SetErrorMode call), so when
            #       the letter D: belonged to a drive that was not ready - a card reader or a USB/optical drive
            #       without a medium, an unplugged removable disk, a second hard disk that had spun down -
            #       Windows showed its "No Disk / Please insert a disk into drive ..." box behind the full-screen
            #       game (a black screen that looks like a hang and reads like a CD request) or the game stalled
            #       for the seconds the disk needed to wake up.  Reported by players with more than one drive.
            #       Now: the start-up instructions that load the HBNFUFL name become a jump over the whole block
            #       (HBNFUFL is never opened, no letter, no path, no probe; the two absolute operands that vanish
            #       had .reloc entries, which become type-0 padding), the "call cd_probe" becomes five NOPs and
            #       cd_probe itself starts with "ret" for its two remaining callers, the file-open helper and the
            #       sound loader jump to their ordinary "file missing" exits instead of trying "<CD path><name>",
            #       the movie opener never takes its CD branch, the dead "%c:\dc\" string is zeroed, and the
            #       sound loader's box says "FILE NOT FOUND / A sound file is missing - see error.log".
            #    3. The "Please insert Dark Colony CD" box (21 Sep 2026, player report).  That text is a picture,
            #       not a string: when a file the game insists on is missing, the file-open helper draws the
            #       sprite intrface/insee over the screen and waits for the file to appear - once for the disc to
            #       be inserted, now forever.  Those 68 bytes of the display object's CD-prompt method become the
            #       sound loader's error exit with the file name as the message: a line "unable to open file
            #       <name>" in error.log, the desktop mode restored, a box "FILE NOT FOUND / <name>", exit.  The
            #       four absolute operands of the new code take over the relocation entries of the old ones.
            #       (Seen with a copy of the game that lacked ozi_ns\intrf_hd\: OZI MISSIONS -> NEXT showed the
            #       prompt for intrf_hd/hxscene.txt.)
            #
            #  Every edit sits inside an existing instruction or string; nothing moves.  The patched exe no
            #  longer needs HBNFUFL.A01 / .A02 (the untouched originals still read the drive letter from them).
            @{
                Id = 'nocd'; Name = 'No CD: the game neither needs the disc nor touches the CD path'; Date = '28-30 Sep 2025 / 18 Sep 2026 / 21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_nocd.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.19; CLAUDE.md "Patches applied so far" (the 2025 bytes)'
                Description = @'
The game refuses to start, and greys out most main-menu buttons, when it cannot find its
CD in a drive.  This one fix removes the whole CD business from the exe:

  1. The two menu tests of the "CD present" flag ("call cd_flag ; test al,al ; jne ok") become
     unconditional jumps (opcode 75 -> EB): the game starts and keeps every menu button without
     the disc.  Council Wars has a third test that threw the player out of a running game; that
     one is inverted (75 -> 74).  These are the three bytes hand-patched in 2025.
  2. Those bypasses alone only ignore the ANSWER of the test.  Until 18 Sep 2026 the machinery
     itself still ran: at start-up the game opened HBNFUFL.A01 / HBNFUFL.A02 (the drive letter
     its installer recorded, "D:" in the repository; a missing file was a silent exit), built the
     path "D:\dc\" and probed it - it opened D:\dc\anim.dat and, if that existed, tried to
     create a file there to see whether the medium refuses writes.  The same probe ran again at
     every menu screen and periodically during a battle, two loaders fell back to "D:\dc\<name>"
     when a file was missing locally, the sound loader then asked to "insert The Dark Colony CD
     and Restart", and the movie opener fell back to the CD when the flag said the disc was in.
     The game never tells Windows to fail such accesses quietly (no SetErrorMode call), so when
     the letter D: belonged to a drive that was not ready - a card reader or a USB/optical drive
     without a medium, an unplugged removable disk, a second hard disk that had spun down -
     Windows showed its "No Disk / Please insert a disk into drive ..." box behind the full-screen
     game (a black screen that looks like a hang and reads like a CD request) or the game stalled
     for the seconds the disk needed to wake up.  Reported by players with more than one drive.
     Now: the start-up instructions that load the HBNFUFL name become a jump over the whole block
     (HBNFUFL is never opened, no letter, no path, no probe; the two absolute operands that vanish
     had .reloc entries, which become type-0 padding), the "call cd_probe" becomes five NOPs and
     cd_probe itself starts with "ret" for its two remaining callers, the file-open helper and the
     sound loader jump to their ordinary "file missing" exits instead of trying "<CD path><name>",
     the movie opener never takes its CD branch, the dead "%c:\dc\" string is zeroed, and the
     sound loader's box says "FILE NOT FOUND / A sound file is missing - see error.log".
  3. The "Please insert Dark Colony CD" box (21 Sep 2026, player report).  That text is a picture,
     not a string: when a file the game insists on is missing, the file-open helper draws the
     sprite intrface/insee over the screen and waits for the file to appear - once for the disc to
     be inserted, now forever.  Those 68 bytes of the display object's CD-prompt method become the
     sound loader's error exit with the file name as the message: a line "unable to open file
     <name>" in error.log, the desktop mode restored, a box "FILE NOT FOUND / <name>", exit.  The
     four absolute operands of the new code take over the relocation entries of the old ones.
     (Seen with a copy of the game that lacked ozi_ns\intrf_hd\: OZI MISSIONS -> NEXT showed the
     prompt for intrf_hd/hxscene.txt.)

Every edit sits inside an existing instruction or string; nothing moves.  The patched exe no
longer needs HBNFUFL.A01 / .A02 (the untouched originals still read the drive letter from them).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # movie opener: je <no CD> -> jmp (never the CD path, whatever the flag says)
                    @{ Offset = 0x478; Old = '74 63'; New = 'EB 63' }
                    # start-up CD test: jne -> jmp after "call cd_flag ; test al,al" (the game starts without the disc)
                    @{ Offset = 0x431F; Old = '75'; New = 'EB' }
                    # main-menu CD test: jne -> jmp after the same test (the CD-gated menu buttons stay enabled)
                    @{ Offset = 0x507F; Old = '75'; New = 'EB' }
                    # cd_probe entry: push ebx -> ret (the two remaining callers, load_interface and the in-game check, get nothing)
                    @{ Offset = 0x528C; Old = '53'; New = 'C3' }
                    # start-up: mov edx,"r" / mov eax,"hbnfufl.a0x" -> jmp to the "full" marker check (HBNFUFL is not opened, no drive letter, no CD path, no probe)
                    @{ Offset = 0x5393; Old = 'BA 30 26 48 00 B8 44 26 48 00'; New = 'E9 9C 00 00 00 90 90 90 90 90' }
                    # start-up: call cd_probe -> 5 NOPs
                    @{ Offset = 0x5454; Old = 'E8 33 FE FF FF'; New = '90 90 90 90 90' }
                    # open helper: je <try "<CD path><name>"> -> jmp <fail as for any missing file>
                    @{ Offset = 0x57BF; Old = '0F 84 6E FE FF FF'; New = 'E9 F9 FE FF FF 90' }
                    # CD-prompt method (display slot +4Ch, called for a missing required file): "draw intrface/insee and wait for the file" -> the wave loader's error exit: fprintf(error.log, "unable to open file %s", name); display shutdown; Sleep(2000); MessageBoxA(hwnd, name, "FILE NOT FOUND"); exit (68 bytes; the rest of the old body is dead)
                    @{ Offset = 0x2B51C; Old = '53 51 56 57 55 89 E5 83 EC 38 89 45 FC 89 55 E8 8B 40 20 8B 55 FC 89 45 F8 89 D1 B8 14 54 48 00 BB 24 54 48 00 FF 51 44 8B 49 24 89 C2 89 C8 E8 AC FF FD FF 8B 5D FC 8D 55 D8 89 D9 89 45 E0 B8 14 54 48 00'; New = '52 52 68 D0 7D 48 00 FF 35 B4 49 4A 00 E8 78 FD 04 00 83 C4 0C E8 A1 FD 04 00 E8 D5 21 00 00 B8 D0 07 00 00 E8 E3 47 00 00 5A 6A 00 68 E8 7D 48 00 52 FF 35 58 97 48 00 E8 BB 2E 05 00 31 C0 E8 F7 FF 04 00' }
                    # wave loader: jne <found> -> jmp: after the two local names the loader takes its error exit instead of the two CD-path attempts
                    @{ Offset = 0x51F49; Old = '0F 85 D7 00 00 00'; New = 'E9 D8 00 00 00 90' }
                    # in-game CD test (Council Wars only): jne -> je in the C-runtime write path, the 2025 hand patch that stopped the expansion from throwing the player out of a running game
                    @{ Offset = 0x781D9; Old = '75'; New = '74' }
                    # DGROUP "%c:\dc\" (the CD-path format, now dead) -> 8 zero bytes
                    @{ Offset = 0x80054; Old = '25 63 3A 5C 64 63 5C 00'; New = '00 00 00 00 00 00 00 00' }
                    # DGROUP "CDROM NOT FOUND" -> "FILE NOT FOUND" (title of the wave loader's box for a missing WAV)
                    @{ Offset = 0x857E8; Old = '43 44 52 4F 4D 20 4E 4F 54 20 46 4F 55 4E 44 00'; New = '46 49 4C 45 20 4E 4F 54 20 46 4F 55 4E 44 00 00' }
                    # DGROUP "Please insert The Dark Colony ... CD and Restart" -> "A sound file is missing - see error.log" (NUL-padded to the old length)
                    @{ Offset = 0x857F8; Old = '50 6C 65 61 73 65 20 69 6E 73 65 72 74 20 54 68 65 20 44 61 72 6B 20 43 6F 6C 6F 6E 79 20 45 78 70 61 6E 73 69 6F 6E 20 50 61 6B 20 43 44 20 2D 20 54 68 65 20 43 6F 75 6E 63 69 6C 20 57 61 72 73 20 61 6E 64 20 52 65 73 74 61 72 74 00'; New = '41 20 73 6F 75 6E 64 20 66 69 6C 65 20 69 73 20 6D 69 73 73 69 6E 67 20 2D 20 73 65 65 20 65 72 72 6F 72 2E 6C 6F 67 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' }
                    # .reloc table: entry 3F94 (type 3 HIGHLOW, page offset 0xF94) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97C88; Old = '94 3F'; New = '94 0F' }
                    # .reloc table: entry 3F99 (type 3 HIGHLOW, page offset 0xF99) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97C8A; Old = '99 3F'; New = '99 0F' }
                    # .reloc table: entry 3138 -> 311F: the absolute operand moved from page offset 0x138 to 0x11F, entry follows it
                    @{ Offset = 0x99D74; Old = '38 31'; New = '1F 31' }
                    # .reloc table: entry 313D -> 3125: the absolute operand moved from page offset 0x13D to 0x125, entry follows it
                    @{ Offset = 0x99D76; Old = '3D 31'; New = '25 31' }
                    # .reloc table: entry 315C -> 3149: the absolute operand moved from page offset 0x15C to 0x149, entry follows it
                    @{ Offset = 0x99D78; Old = '5C 31'; New = '49 31' }
                    # .reloc table: entry 3192 -> 3150: the absolute operand moved from page offset 0x192 to 0x150, entry follows it
                    @{ Offset = 0x99D7A; Old = '92 31'; New = '50 31' }
                )
            }

            # ---- resolution @ 1024x768: 1024x768 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 365 bytes in 166 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
            #    stage 1  display mode, framebuffer stride (a shift, 1024 is a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at
            #             (903,6), the 31 lightplane row advances,  and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,96)-(1024,672) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1024x768 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1024x768 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1024x768 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1024x768'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1024x768\INTRG.GIF', 'INTRF_HD\1024x768\INTRO.GIF', 'INTRF_HD\1024x768\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1024x768 equivalent here:
  stage 1  display mode, framebuffer stride (a shift, 1024 is a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+192,+144) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 896x736 (28x23 tiles) at (4,6), minimap 96x84 at
           (903,6), the 31 lightplane row advances,  and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,96)-(1024,672) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1024x768 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1024x768 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (67; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'INTRF_HD\1024x768\INTRG.GIF'
                    'INTRF_HD\1024x768\INTRO.GIF'
                    'INTRF_HD\1024x768\INTRFACE.GIF'
                )
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
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB 92 01 00 00' }
                    # menu: intro credits text height 100 -> 80 (room for the OZI menu row)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
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

            # ---- resolution @ 1280x1024: 1280x1024 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 442 bytes in 179 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x1024 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+272) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x992 (36x31 tiles) at (4,6), minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,152)-(1280,872) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x1024 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x1024 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x1024 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x1024'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x1024\INTRG.GIF', 'INTRF_HD\1280x1024\INTRO.GIF', 'INTRF_HD\1280x1024\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x1024 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+272) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x992 (36x31 tiles) at (4,6), minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,152)-(1280,872) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x1024 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x1024 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (67; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'INTRF_HD\1280x1024\INTRG.GIF'
                    'INTRF_HD\1280x1024\INTRO.GIF'
                    'INTRF_HD\1280x1024\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 FF 03 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 7A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 1D 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB E4 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 2A 01 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB CE 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB B9 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB B9 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB 2F 02 00 00' }
                    # menu: intro credits text height 100 -> 80 (room for the OZI menu row)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5040; Old = 'BB 18 00 00 00'; New = 'BB 28 01 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5051; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7274; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 40 97 48 00 89 55 5A 8D 55 52 8B 1D 28 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 98 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E 68 03 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 28 8E 48 00 8D 55 62 52 A1 40 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F9E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x94E4; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F6A; Old = '6A 0E'; New = '6A 1F' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F6C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F7C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0F 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F8B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA51C; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0F 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA540; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E17E; Old = 'B9 C0 01 00 00'; New = 'B9 E0 03 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E183; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E2A3; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E2C6; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E2CF; Old = 'BB 00 07 00 00'; New = 'BB 80 0F 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B5F4; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B669; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B673; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B678; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B6C1; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B7A7; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B7C3; Old = 'B9 E0 01 00 00'; New = 'B9 00 04 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D632; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D65F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D66E; Old = 'B8 E0 01 00 00'; New = 'B8 00 04 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D679; Old = 'B8 E0 01 00 00'; New = 'B8 00 04 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DC24; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DC29; Old = 'B9 F0 00 00 00'; New = 'B9 00 02 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DCF8; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DD02; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD7C; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD86; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DEE9; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DEEE; Old = 'BA E0 01 00 00'; New = 'BA 00 04 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E367; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E36C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E398; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E39D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E44D; Old = '68 E0 01 00 00'; New = '68 00 04 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E452; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EC0D; Old = '3D 00 B0 04 00'; New = '3D 00 00 14 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EC42; Old = '3D 00 B0 04 00'; New = '3D 00 00 14 00' }
                    # visible tiles down
                    @{ Offset = 0x352A7; Old = 'B9 0E 00 00 00'; New = 'B9 1F 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x352AC; Old = '8D 50 F2'; New = '8D 50 E1' }
                    # visible tiles across
                    @{ Offset = 0x352AF; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x353A6; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x353C1; Old = 'BB C0 01 00 00'; New = 'BB E0 03 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x353E8; Old = 'BA 00 70 00 00'; New = 'BA 00 2E 02 00' }
                    # render destination stride
                    @{ Offset = 0x353FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x35516; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x35816; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x3581D; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x35825; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x394FB; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x3950F; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x39644; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x396DA; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x398BB; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x398E4; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x502A7; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x502AF; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x502BC; Old = '81 FF E0 01 00 00'; New = '81 FF 00 04 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x502C4; Old = 'BF DF 01 00 00'; New = 'BF FF 03 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x503A6; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x503AD; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x503CB; Old = '81 FE DF 01 00 00'; New = '81 FE FF 03 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x503D3; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 FF 03 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D75; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 41 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F6E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F70; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F80; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 BF FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52FBC; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FBE; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52FD2; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FD4; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52FDA; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE BE FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52FE1; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE BE FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52FE8; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 BF FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52FF1; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 BF FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x53006; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53008; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x53013; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 BF FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x5305B; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53060; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53065; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA BE FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53083; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53085; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5308D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA BE FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5309C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 BF FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x530BD; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 BF FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x5312B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x53152; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53175; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x531C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x531EE; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x53229; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x5325C; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53286; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x532B8; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x532F3; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x53326; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x53359; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53384; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x533C1; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x533F4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x53427; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x5345A; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5348D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x534B7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x534F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x53514; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x53556; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53589; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x535A5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x535EF; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x53622; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x53655; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53688; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x536BB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x536D6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x5371C; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x867DC; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x867E0; Old = 'E0 01 00 00'; New = '00 04 00 00' }
                )
            }

            # ---- resolution @ 1280x720: 1280x720 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 424 bytes in 179 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x720 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+120) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x672 (36x21 tiles) at (4,6) plus 16 spare rows given to the taller HUD bottom bar, minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,0)-(1280,720) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x720 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x720 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x720 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x720'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x720\INTRG.GIF', 'INTRF_HD\1280x720\INTRO.GIF', 'INTRF_HD\1280x720\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x720 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+120) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x672 (36x21 tiles) at (4,6) plus 16 spare rows given to the taller HUD bottom bar, minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,0)-(1280,720) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x720 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x720 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (67; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'INTRF_HD\1280x720\INTRG.GIF'
                    'INTRF_HD\1280x720\INTRO.GIF'
                    'INTRF_HD\1280x720\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 CF 02 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB E2 00 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 85 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 4C 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 92 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 36 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 21 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 21 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB 74 01 00 00' }
                    # menu: intro credits text height 100 -> 80 (room for the OZI menu row)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5040; Old = 'BB 18 00 00 00'; New = 'BB 90 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5051; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7274; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 40 97 48 00 89 55 5A 8D 55 52 8B 1D 28 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 00 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E D0 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 28 8E 48 00 8D 55 62 52 A1 40 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F9E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x94E4; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F6A; Old = '6A 0E'; New = '6A 15' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F6C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F7C; Old = '81 EB 00 07 00 00'; New = '81 EB 80 0A 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F8B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA51C; Old = '81 EA 00 07 00 00'; New = '81 EA 80 0A 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA540; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E17E; Old = 'B9 C0 01 00 00'; New = 'B9 A0 02 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E183; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E2A3; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E2C6; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E2CF; Old = 'BB 00 07 00 00'; New = 'BB 80 0A 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B5F4; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B669; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B673; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B678; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B6C1; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B7A7; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B7C3; Old = 'B9 E0 01 00 00'; New = 'B9 D0 02 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D632; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D65F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D66E; Old = 'B8 E0 01 00 00'; New = 'B8 D0 02 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D679; Old = 'B8 E0 01 00 00'; New = 'B8 D0 02 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DC24; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DC29; Old = 'B9 F0 00 00 00'; New = 'B9 68 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DCF8; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DD02; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD7C; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD86; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DEE9; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DEEE; Old = 'BA E0 01 00 00'; New = 'BA D0 02 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E367; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E36C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E398; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E39D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E44D; Old = '68 E0 01 00 00'; New = '68 D0 02 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E452; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EC0D; Old = '3D 00 B0 04 00'; New = '3D 00 10 0E 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EC42; Old = '3D 00 B0 04 00'; New = '3D 00 10 0E 00' }
                    # visible tiles down
                    @{ Offset = 0x352A7; Old = 'B9 0E 00 00 00'; New = 'B9 15 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x352AC; Old = '8D 50 F2'; New = '8D 50 EB' }
                    # visible tiles across
                    @{ Offset = 0x352AF; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x353A6; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x353C1; Old = 'BB C0 01 00 00'; New = 'BB A0 02 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x353E8; Old = 'BA 00 70 00 00'; New = 'BA 00 7A 01 00' }
                    # render destination stride
                    @{ Offset = 0x353FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x35516; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x35816; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x3581D; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x35825; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x394FB; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x3950F; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x39644; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x396DA; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x398BB; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x398E4; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x502A7; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x502AF; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x502BC; Old = '81 FF E0 01 00 00'; New = '81 FF D0 02 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x502C4; Old = 'BF DF 01 00 00'; New = 'BF CF 02 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x503A6; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x503AD; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x503CB; Old = '81 FE DF 01 00 00'; New = '81 FE CF 02 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x503D3; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 CF 02 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D75; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 2D 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F6E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F70; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F80; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 D3 FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52FBC; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FBE; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52FD2; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FD4; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52FDA; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE D2 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52FE1; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE D2 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52FE8; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 D3 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52FF1; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 D3 FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x53006; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53008; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x53013; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 D3 FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x5305B; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53060; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53065; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA D2 FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53083; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53085; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5308D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA D2 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5309C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 D3 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x530BD; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 D3 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x5312B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x53152; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53175; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x531C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x531EE; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x53229; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x5325C; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53286; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x532B8; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x532F3; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x53326; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x53359; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53384; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x533C1; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x533F4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x53427; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x5345A; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5348D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x534B7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x534F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x53514; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x53556; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53589; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x535A5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x535EF; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x53622; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x53655; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53688; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x536BB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x536D6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x5371C; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x867DC; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x867E0; Old = 'E0 01 00 00'; New = 'D0 02 00 00' }
                )
            }

            # ---- resolution @ 1280x800: 1280x800 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 428 bytes in 179 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 1280x800 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+320,+160) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 1152x768 (36x24 tiles) at (4,6), minimap 96x84 at
            #             (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (0,40)-(1280,760) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 1280x800 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x800 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '1280x800 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x800'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\1280x800\INTRG.GIF', 'INTRF_HD\1280x800\INTRO.GIF', 'INTRF_HD\1280x800\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 1280x800 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 1280 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+320,+160) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 1152x768 (36x24 tiles) at (4,6), minimap 96x84 at
           (1159,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x256 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (0,40)-(1280,760) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 1280x800 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 1280x800 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (67; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'INTRF_HD\1280x800\INTRG.GIF'
                    'INTRF_HD\1280x800\INTRO.GIF'
                    'INTRF_HD\1280x800\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 04 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 1F 03 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 01 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 0A 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB AD 00 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 02 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 74 01 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 02 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB BA 00 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 01 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB 5E 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 01 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB 49 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB 49 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 03 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB A5 01 00 00' }
                    # menu: intro credits text height 100 -> 80 (room for the OZI menu row)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 01 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5040; Old = 'BB 18 00 00 00'; New = 'BB B8 00 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5051; Old = 'BA 50 01 00 00'; New = 'BA 90 02 00 00' }
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
                    @{ Offset = 0x7274; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 40 97 48 00 89 55 5A 8D 55 52 8B 1D 28 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF 89 7D 62 C7 45 66 28 00 00 00 C7 45 6A 00 05 00 00 C7 45 6E F8 02 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 28 8E 48 00 8D 55 62 52 A1 40 97 48 00 50 8B 08 FF 51 14 90 90 90 90 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F9E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x94E4; Old = '2D 07 02 00 00'; New = '2D 87 04 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F6A; Old = '6A 0E'; New = '6A 18' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F6C; Old = 'B9 10 00 00 00'; New = 'B9 24 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F7C; Old = '81 EB 00 07 00 00'; New = '81 EB 00 0C 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F8B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA51C; Old = '81 EA 00 07 00 00'; New = '81 EA 00 0C 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA540; Old = '81 EA 00 08 00 00'; New = '81 EA 00 12 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E17E; Old = 'B9 C0 01 00 00'; New = 'B9 00 03 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E183; Old = 'BB 00 02 00 00'; New = 'BB 80 04 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E2A3; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E2C6; Old = 'B9 00 08 00 00'; New = 'B9 00 12 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E2CF; Old = 'BB 00 07 00 00'; New = 'BB 00 0C 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B5F4; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B669; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 05 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B673; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B678; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B6C1; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B7A7; Old = 'BB 80 02 00 00'; New = 'BB 00 05 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B7C3; Old = 'B9 E0 01 00 00'; New = 'B9 20 03 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D632; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D65F; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D66E; Old = 'B8 E0 01 00 00'; New = 'B8 20 03 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D679; Old = 'B8 E0 01 00 00'; New = 'B8 20 03 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DC24; Old = 'BA 40 01 00 00'; New = 'BA 80 02 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DC29; Old = 'B9 F0 00 00 00'; New = 'B9 90 01 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DCF8; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DD02; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD7C; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD86; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DEE9; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DEEE; Old = 'BA E0 01 00 00'; New = 'BA 20 03 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E367; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E36C; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E398; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E39D; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E44D; Old = '68 E0 01 00 00'; New = '68 20 03 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E452; Old = '68 80 02 00 00'; New = '68 00 05 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EC0D; Old = '3D 00 B0 04 00'; New = '3D 00 A0 0F 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EC42; Old = '3D 00 B0 04 00'; New = '3D 00 A0 0F 00' }
                    # visible tiles down
                    @{ Offset = 0x352A7; Old = 'B9 0E 00 00 00'; New = 'B9 18 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x352AC; Old = '8D 50 F2'; New = '8D 50 E8' }
                    # visible tiles across
                    @{ Offset = 0x352AF; Old = 'BB 10 00 00 00'; New = 'BB 24 00 00 00' }
                    # viewport width
                    @{ Offset = 0x353A6; Old = 'BA 00 02 00 00'; New = 'BA 80 04 00 00' }
                    # viewport height
                    @{ Offset = 0x353C1; Old = 'BB C0 01 00 00'; New = 'BB 00 03 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x353E8; Old = 'BA 00 70 00 00'; New = 'BA 00 B0 01 00' }
                    # render destination stride
                    @{ Offset = 0x353FF; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x35516; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 0A 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x35816; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 05 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x3581D; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x35825; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x394FB; Old = 'B8 80 02 00 00'; New = 'B8 00 05 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x3950F; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E 45 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x39644; Old = 'B8 07 02 00 00'; New = 'B8 87 04 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x396DA; Old = '05 07 02 00 00'; New = '05 87 04 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x398BB; Old = 'BA 80 02 00 00'; New = 'BA 00 05 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x398E4; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E 45 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x502A7; Old = '81 FE 80 02 00 00'; New = '81 FE 00 05 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x502AF; Old = 'BE 7F 02 00 00'; New = 'BE FF 04 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x502BC; Old = '81 FF E0 01 00 00'; New = '81 FF 20 03 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x502C4; Old = 'BF DF 01 00 00'; New = 'BF 1F 03 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x503A6; Old = '3D 7F 02 00 00'; New = '3D FF 04 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x503AD; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 04 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x503CB; Old = '81 FE DF 01 00 00'; New = '81 FE 1F 03 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x503D3; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 1F 03 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D75; Old = '81 EC CC 14 00 00'; New = '81 EC 7C 33 00 00' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F6E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F70; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F80; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 06 CD FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52FBC; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FBE; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52FD2; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FD4; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52FDA; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E FE CC FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52FE1; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F FE CC FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52FE8; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 06 CD FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52FF1; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 06 CD FF FF' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x53006; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53008; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x53013; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 02 CD FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x5305B; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x256, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53060; Old = 'C1 E2 04'; New = 'C1 E2 05' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53065; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A FA CC FF FF' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53083; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x256, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53085; Old = 'C1 E0 04'; New = 'C1 E0 05' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5308D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 FA CC FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5309C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 02 CD FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x530BD; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 02 CD FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x5312B; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x53152; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53175; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x531C2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x531EE; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x53229; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x5325C; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53286; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x532B8; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x532F3; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x53326; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x53359; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53384; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x533C1; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x533F4; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x53427; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x5345A; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5348D; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x534B7; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x534F2; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x53514; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x53556; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53589; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x535A5; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x535EF; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x53622; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x53655; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53688; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x536BB; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x536D6; Old = '05 00 02 00 00'; New = '05 80 04 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x5371C; Old = '8D B8 00 02 00 00'; New = '8D B8 80 04 00 00' }
                    # screen width global
                    @{ Offset = 0x867DC; Old = '80 02 00 00'; New = '00 05 00 00' }
                    # screen height global
                    @{ Offset = 0x867E0; Old = 'E0 01 00 00'; New = '20 03 00 00' }
                )
            }

            # ---- resolution @ 3840x1080: 3840x1080 display ---------------------------------------------------------
            #  Added      : 9 Sep 2026 (any size since 21 Sep 2026)
            #  Made with  : tools/patch_resolution.py (Dark-Colony-Server)
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25
            #  Changes    : 437 bytes in 179 edits
            #  The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
            #  (y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
            #  position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
            #  512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
            #  constants was read out of the disassembly and is replaced by the 3840x1080 equivalent here:
            #    stage 1  display mode, framebuffer stride (imul: 3840 is not a power of two), clip rect
            #    stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
            #             moved by (+1600,+300) - the same offset the letterboxed 640x480 menu screens use
            #    stage 3  map viewport 3712x1024 (116x32 tiles) at (4,6) plus 24 spare rows given to the taller HUD bottom bar, minimap 96x84 at
            #             (3719,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x512 (more than 34 tiles across), and a bigger stack frame for
            #             draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
            #             well - the two edits at file offsets 0xE0 / 0xE4)
            #    stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
            #             (960,0)-(2880,1080) through IDirectDrawSurface::Blt
            #  Every edit swaps one immediate constant or one arithmetic opcode inside an existing
            #  instruction; no code is added and no instruction moves.  Council Wars is the same code at
            #  +0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.
            #
            #  REQUIRES the interface data rebuilt for 3840x1080 next to the exe - in the INTRF_HD/ folder,
            #  read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
            #  serves every resolution, so it must hold the set built for THIS size: the patcher reads the
            #  size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
            #  the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
            #  LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
            #  INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 3840x1080 canvas) whenever
            #  the ones in place have another size.
            @{
                Id = 'resolution'; Name = '3840x1080 display'; Date = '9 Sep 2026 (any size since 21 Sep 2026)'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '3840x1080'
                # applying this fix also GENERATES the INTRF_HD interface set for this size from the stock files
                # (Write-InterfaceSet); these three pictures cannot be derived and ship with the game
                SetSources = @('INTRF_HD\3840x1080\INTRG.GIF', 'INTRF_HD\3840x1080\INTRO.GIF', 'INTRF_HD\3840x1080\INTRFACE.GIF')
                Tool = 'tools/patch_resolution.py (Dark-Colony-Server)'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md sections 8-10, 10.24, 10.25'
                Description = @'
The engine is hard-wired for 640x480: the DirectDraw display mode, the framebuffer stride
(y*640 done as shl 7 + add), clip rectangles, the map viewport (16x14 tiles), the minimap
position, the movie blit, the 44 code-positioned main-menu elements, the terrain light plane's
512-byte row advances and the size of draw_terrain's stack lightmap.  Every one of those
constants was read out of the disassembly and is replaced by the 3840x1080 equivalent here:
  stage 1  display mode, framebuffer stride (imul: 3840 is not a power of two), clip rect
  stage 2  full-screen chrome, mouse, cursor clip, loading screens, and the 44 menu elements
           moved by (+1600,+300) - the same offset the letterboxed 640x480 menu screens use
  stage 3  map viewport 3712x1024 (116x32 tiles) at (4,6) plus 24 spare rows given to the taller HUD bottom bar, minimap 96x84 at
           (3719,6), the 31 lightplane row advances, the six lightmap row idioms x144 -> x512 (more than 34 tiles across), and a bigger stack frame for
           draw_terrain (so the PE header's SizeOfStackReserve / SizeOfStackCommit go up as
           well - the two edits at file offsets 0xE0 / 0xE4)
  stage 4  movies: pitch-aware back-buffer clear and the 320x180 movie frames stretched to
           (960,0)-(2880,1080) through IDirectDrawSurface::Blt
Every edit swaps one immediate constant or one arithmetic opcode inside an existing
instruction; no code is added and no instruction moves.  Council Wars is the same code at
+0x60 (AUTO) / +0x28 (DGROUP) with three site fixups, hence the slightly different offsets.

REQUIRES the interface data rebuilt for 3840x1080 next to the exe - in the INTRF_HD/ folder,
read through the "Interface data from INTRF_HD" patch below (select both).  One INTRF_HD folder
serves every resolution, so it must hold the set built for THIS size: the patcher reads the
size of INTRF_HD\INTRFACE.GIF and refuses a mismatch (with a 1024x768 set the game would draw
the menus and the HUD frame at the wrong size).  The two loading screens INTRF_HD\LOAD.BMP /
LOAD2.BMP are not part of a set: this patcher writes them for the chosen size from the stock
INTRFACE\LOAD.BMP / LOAD2.BMP (the 640x480 picture centred on a black 3840x1080 canvas) whenever
the ones in place have another size.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (67; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'INTRF_HD\3840x1080\INTRG.GIF'
                    'INTRF_HD\3840x1080\INTRO.GIF'
                    'INTRF_HD\3840x1080\INTRFACE.GIF'
                )
                Edits = @(
                    # PE header: SizeOfStackReserve
                    @{ Offset = 0xE0; Old = '80 38 01 00'; New = '00 00 10 00' }
                    # PE header: SizeOfStackCommit
                    @{ Offset = 0xE4; Old = '00 00 01 00'; New = '00 00 04 00' }
                    # main.c full-screen rect right
                    @{ Offset = 0x4E5; Old = 'BF 7F 02 00 00'; New = 'BF FF 0E 00 00' }
                    # main.c full-screen rect bottom
                    @{ Offset = 0x4EA; Old = 'B8 DF 01 00 00'; New = 'B8 37 04 00 00' }
                    # menu: campaign overview text y 13
                    @{ Offset = 0x1871; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: campaign overview text x 10
                    @{ Offset = 0x187B; Old = 'BA 0A 00 00 00'; New = 'BA 4A 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1B02; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1B07; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1B28; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1B2F; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1D76; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1D7C; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1DC7; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1DCE; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1EC2; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1EC8; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x1F13; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x1F1A; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x1FE0; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x1FE5; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2029; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x2030; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x210D; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x2117; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2156; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x215D; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: encyclopedia text x 20
                    @{ Offset = 0x2240; Old = 'BA 14 00 00 00'; New = 'BA 54 06 00 00' }
                    # menu: encyclopedia text y 106
                    @{ Offset = 0x224A; Old = 'BB 6A 00 00 00'; New = 'BB 96 01 00 00' }
                    # menu: encyclopedia model y 13
                    @{ Offset = 0x2284; Old = 'BB 0D 00 00 00'; New = 'BB 39 01 00 00' }
                    # menu: encyclopedia model x 303
                    @{ Offset = 0x228B; Old = 'BA 2F 01 00 00'; New = 'BA 6F 07 00 00' }
                    # menu: mission description text y 212
                    @{ Offset = 0x2600; Old = 'BB D4 00 00 00'; New = 'BB 00 02 00 00' }
                    # menu: mission description text x 310
                    @{ Offset = 0x260A; Old = 'BA 36 01 00 00'; New = 'BA 76 07 00 00' }
                    # menu: mission globe (human) x 34
                    @{ Offset = 0x263F; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: mission globe (human) y 26
                    @{ Offset = 0x2649; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe (alien) y 26
                    @{ Offset = 0x2675; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe (alien) x 34
                    @{ Offset = 0x267C; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: mission globe overlay y 26
                    @{ Offset = 0x269A; Old = 'BB 1A 00 00 00'; New = 'BB 46 01 00 00' }
                    # menu: mission globe overlay x 34
                    @{ Offset = 0x269F; Old = 'BA 22 00 00 00'; New = 'BA 62 06 00 00' }
                    # menu: victory debrief text y 190
                    @{ Offset = 0x367A; Old = 'BB BE 00 00 00'; New = 'BB EA 01 00 00' }
                    # menu: victory debrief text x 29
                    @{ Offset = 0x3681; Old = 'BA 1D 00 00 00'; New = 'BA 5D 06 00 00' }
                    # menu: victory medal y 169
                    @{ Offset = 0x386D; Old = 'BB A9 00 00 00'; New = 'BB D5 01 00 00' }
                    # menu: victory medal x 541
                    @{ Offset = 0x3874; Old = 'BA 1D 02 00 00'; New = 'BA 5D 08 00 00' }
                    # menu: victory medal (re-create) y 169
                    @{ Offset = 0x3BEC; Old = 'BB A9 00 00 00'; New = 'BB D5 01 00 00' }
                    # menu: victory medal (re-create) x 541
                    @{ Offset = 0x3BF3; Old = 'BA 1D 02 00 00'; New = 'BA 5D 08 00 00' }
                    # menu: intro credits text y 200
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB 52 02 00 00' }
                    # menu: intro credits text height 100 -> 80 (room for the OZI menu row)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
                    # menu: intro credits text x 178
                    @{ Offset = 0x42A0; Old = 'BA B2 00 00 00'; New = 'BA F4 06 00 00' }
                    # menu: network screen globe y 24
                    @{ Offset = 0x5040; Old = 'BB 18 00 00 00'; New = 'BB 44 01 00 00' }
                    # menu: network screen globe x 336
                    @{ Offset = 0x5051; Old = 'BA 50 01 00 00'; New = 'BA 90 07 00 00' }
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
                    @{ Offset = 0x7274; Old = 'BA 40 01 00 00 B9 B4 00 00 00 6A 10 A1 40 97 48 00 89 55 5A 8D 55 52 8B 1D 28 8E 48 00 52 31 FF 8B 15 80 56 4A 00 53 01 D2 89 7D 52 52 89 7D 56 89 4D 5E 68 A0 00 00 00 8B 08 50 FF 51 1C'; New = '31 FF C7 45 62 C0 03 00 00 C7 45 66 00 00 00 00 C7 45 6A 40 0B 00 00 C7 45 6E 38 04 00 00 6A 00 68 00 00 00 01 6A 00 FF 35 28 8E 48 00 8D 55 62 52 A1 40 97 48 00 50 8B 08 FF 51 14 90 90' }
                    # display thread: always draw through the 320x180 movie surface
                    @{ Offset = 0x7F9E; Old = '75 07'; New = 'EB 07' }
                    # minimap click: mouse x - minimap x
                    @{ Offset = 0x94E4; Old = '2D 07 02 00 00'; New = '2D 87 0E 00 00' }
                    # interface update: push tiles_down (imm8)
                    @{ Offset = 0x9F6A; Old = '6A 0E'; New = '6A 20' }
                    # interface update: tiles_across
                    @{ Offset = 0x9F6C; Old = 'B9 10 00 00 00'; New = 'B9 74 00 00 00' }
                    # interface update: sub ebx,half_viewport_y
                    @{ Offset = 0x9F7C; Old = '81 EB 00 07 00 00'; New = '81 EB 00 10 00 00' }
                    # interface update: sub edx,half_viewport_x
                    @{ Offset = 0x9F8B; Old = '81 EA 00 08 00 00'; New = '81 EA 00 3A 00 00' }
                    # frame render: sub edx,half_viewport_y
                    @{ Offset = 0xA51C; Old = '81 EA 00 07 00 00'; New = '81 EA 00 10 00 00' }
                    # frame render: sub edx,half_viewport_x
                    @{ Offset = 0xA540; Old = '81 EA 00 08 00 00'; New = '81 EA 00 3A 00 00' }
                    # proto.c map view rect height
                    @{ Offset = 0x1E17E; Old = 'B9 C0 01 00 00'; New = 'B9 00 04 00 00' }
                    # proto.c map view rect width
                    @{ Offset = 0x1E183; Old = 'BB 00 02 00 00'; New = 'BB 80 0E 00 00' }
                    # minimap hit rect x (proto.c make_rect -> ui+0x7B4)
                    @{ Offset = 0x1E2A3; Old = 'B8 07 02 00 00'; New = 'B8 87 0E 00 00' }
                    # scroll clamp: half_viewport_x
                    @{ Offset = 0x1E2C6; Old = 'B9 00 08 00 00'; New = 'B9 00 3A 00 00' }
                    # scroll clamp: half_viewport_y
                    @{ Offset = 0x1E2CF; Old = 'BB 00 07 00 00'; New = 'BB 00 10 00 00' }
                    # driver.c row advance (a)
                    @{ Offset = 0x2B5F4; Old = 'BB 80 02 00 00'; New = 'BB 00 0F 00 00' }
                    # driver.c y*640 -> y*W: lea edx,[ecx*4] -> imul edx,ecx,W
                    @{ Offset = 0x2B669; Old = '8D 14 8D 00 00 00 00'; New = '69 D1 00 0F 00 00 90' }
                    # driver.c y*640: neutralise add edx,ecx
                    @{ Offset = 0x2B673; Old = '01 CA'; New = '89 D2' }
                    # driver.c y*640: neutralise shl edx,7 (lea edx,[edx+0])
                    @{ Offset = 0x2B678; Old = 'C1 E2 07'; New = '8D 52 00' }
                    # driver.c row advance (b)
                    @{ Offset = 0x2B6C1; Old = 'BA 80 02 00 00'; New = 'BA 00 0F 00 00' }
                    # driver.c clip rect width
                    @{ Offset = 0x2B7A7; Old = 'BB 80 02 00 00'; New = 'BB 00 0F 00 00' }
                    # driver.c clip rect height
                    @{ Offset = 0x2B7C3; Old = 'B9 E0 01 00 00'; New = 'B9 38 04 00 00' }
                    # cursor clip width (a)
                    @{ Offset = 0x2D632; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # cursor clip width (b)
                    @{ Offset = 0x2D65F; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # cursor clip height (a)
                    @{ Offset = 0x2D66E; Old = 'B8 E0 01 00 00'; New = 'B8 38 04 00 00' }
                    # cursor clip height (b)
                    @{ Offset = 0x2D679; Old = 'B8 E0 01 00 00'; New = 'B8 38 04 00 00' }
                    # initial mouse X (screen centre)
                    @{ Offset = 0x2DC24; Old = 'BA 40 01 00 00'; New = 'BA 80 07 00 00' }
                    # initial mouse Y (screen centre)
                    @{ Offset = 0x2DC29; Old = 'B9 F0 00 00 00'; New = 'B9 1C 02 00 00' }
                    # SetDisplayMode 8-bit height
                    @{ Offset = 0x2DCF8; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # SetDisplayMode 8-bit width
                    @{ Offset = 0x2DD02; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # SetDisplayMode 16-bit height
                    @{ Offset = 0x2DD7C; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # SetDisplayMode 16-bit width
                    @{ Offset = 0x2DD86; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # offscreen surface width
                    @{ Offset = 0x2DEE9; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # offscreen surface height
                    @{ Offset = 0x2DEEE; Old = 'BA E0 01 00 00'; New = 'BA 38 04 00 00' }
                    # load.bmp LoadImageA height
                    @{ Offset = 0x2E367; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # load.bmp LoadImageA width
                    @{ Offset = 0x2E36C; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # load2.bmp LoadImageA height
                    @{ Offset = 0x2E398; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # load2.bmp LoadImageA width
                    @{ Offset = 0x2E39D; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # loading screen BitBlt height
                    @{ Offset = 0x2E44D; Old = '68 E0 01 00 00'; New = '68 38 04 00 00' }
                    # loading screen BitBlt width
                    @{ Offset = 0x2E452; Old = '68 80 02 00 00'; New = '68 00 0F 00 00' }
                    # clear_screen pixel count (a)
                    @{ Offset = 0x2EC0D; Old = '3D 00 B0 04 00'; New = '3D 00 48 3F 00' }
                    # clear_screen pixel count (b)
                    @{ Offset = 0x2EC42; Old = '3D 00 B0 04 00'; New = '3D 00 48 3F 00' }
                    # visible tiles down
                    @{ Offset = 0x352A7; Old = 'B9 0E 00 00 00'; New = 'B9 20 00 00 00' }
                    # clip_view_to_map: lea edx,[eax-tiles_down]
                    @{ Offset = 0x352AC; Old = '8D 50 F2'; New = '8D 50 E0' }
                    # visible tiles across
                    @{ Offset = 0x352AF; Old = 'BB 10 00 00 00'; New = 'BB 74 00 00 00' }
                    # viewport width
                    @{ Offset = 0x353A6; Old = 'BA 00 02 00 00'; New = 'BA 80 0E 00 00' }
                    # viewport height
                    @{ Offset = 0x353C1; Old = 'BB C0 01 00 00'; New = 'BB 00 04 00 00' }
                    # occlusion mask size
                    @{ Offset = 0x353E8; Old = 'BA 00 70 00 00'; New = 'BA 00 40 07 00' }
                    # render destination stride
                    @{ Offset = 0x353FF; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # engmain.c y*1280 -> y*W*2: shl/add/shl window -> imul eax,eax,W*2; mov ebx,[ebx+8]
                    @{ Offset = 0x35516; Old = 'C1 E0 02 01 F8 8B 5B 08 C1 E0 08'; New = '69 C0 00 1E 00 00 8B 5B 08 90 90' }
                    # engmain.c y*640 -> y*W: lea eax,[ecx*4] -> imul eax,ecx,W
                    @{ Offset = 0x35816; Old = '8D 04 8D 00 00 00 00'; New = '69 C1 00 0F 00 00 90' }
                    # engmain.c y*640: neutralise add eax,ecx
                    @{ Offset = 0x3581D; Old = '01 C8'; New = '89 C0' }
                    # engmain.c y*640: neutralise shl eax,7 (lea eax,[eax+0])
                    @{ Offset = 0x35825; Old = 'C1 E0 07'; New = '8D 40 00' }
                    # minimap stride (a)
                    @{ Offset = 0x394FB; Old = 'B8 80 02 00 00'; New = 'B8 00 0F 00 00' }
                    # minimap origin (a)
                    @{ Offset = 0x3950F; Old = '81 C2 0E 22 00 00'; New = '81 C2 0E D1 00 00' }
                    # minimap draw: clip rect x
                    @{ Offset = 0x39644; Old = 'B8 07 02 00 00'; New = 'B8 87 0E 00 00' }
                    # minimap draw: view-box indicator x
                    @{ Offset = 0x396DA; Old = '05 07 02 00 00'; New = '05 87 0E 00 00' }
                    # minimap stride (b)
                    @{ Offset = 0x398BB; Old = 'BA 80 02 00 00'; New = 'BA 00 0F 00 00' }
                    # minimap origin (b)
                    @{ Offset = 0x398E4; Old = '81 45 F0 0E 22 00 00'; New = '81 45 F0 0E D1 00 00' }
                    # mouse clamp: compare X against width
                    @{ Offset = 0x502A7; Old = '81 FE 80 02 00 00'; New = '81 FE 00 0F 00 00' }
                    # mouse clamp: X maximum
                    @{ Offset = 0x502AF; Old = 'BE 7F 02 00 00'; New = 'BE FF 0E 00 00' }
                    # mouse clamp: compare Y against height
                    @{ Offset = 0x502BC; Old = '81 FF E0 01 00 00'; New = '81 FF 38 04 00 00' }
                    # mouse clamp: Y maximum
                    @{ Offset = 0x502C4; Old = 'BF DF 01 00 00'; New = 'BF 37 04 00 00' }
                    # DirectInput clamp: compare X
                    @{ Offset = 0x503A6; Old = '3D 7F 02 00 00'; New = '3D FF 0E 00 00' }
                    # DirectInput clamp: X maximum
                    @{ Offset = 0x503AD; Old = 'C7 05 C0 27 53 00 7F 02 00 00'; New = 'C7 05 C0 27 53 00 FF 0E 00 00' }
                    # DirectInput clamp: compare Y
                    @{ Offset = 0x503CB; Old = '81 FE DF 01 00 00'; New = '81 FE 37 04 00 00' }
                    # DirectInput clamp: Y maximum
                    @{ Offset = 0x503D3; Old = 'C7 05 C4 27 53 00 DF 01 00 00'; New = 'C7 05 C4 27 53 00 37 04 00 00' }
                    # draw_terrain: sub esp,frame
                    @{ Offset = 0x52D75; Old = '81 EC CC 14 00 00'; New = '81 EC FC 87 00 00' }
                    # lightmap x144 -> x512, loop 1 row 2r+2 (eax,esi): neutralise add
                    @{ Offset = 0x52F6E; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 1 row 2r+2 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52F70; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap store, loop 1 (2r, 2c)
                    @{ Offset = 0x52F80; Old = '89 B4 28 B6 EB FF FF'; New = '89 B4 28 86 78 FF FF' }
                    # lightmap x144 -> x512, loop 2 row r+2 (eax,ebx): neutralise add
                    @{ Offset = 0x52FBC; Old = '01 D8'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r+2 (eax,ebx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FBE; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap x144 -> x512, loop 2 row r (eax,edx): neutralise add
                    @{ Offset = 0x52FD2; Old = '01 D0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r (eax,edx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x52FD4; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap read, loop 2 (r, c)
                    @{ Offset = 0x52FDA; Old = '8B 84 2E AE EB FF FF'; New = '8B 84 2E 7E 78 FF FF' }
                    # lightmap read, loop 2 (r+2, c)
                    @{ Offset = 0x52FE1; Old = '03 84 2F AE EB FF FF'; New = '03 84 2F 7E 78 FF FF' }
                    # lightmap read, loop 2 (r, c+2)
                    @{ Offset = 0x52FE8; Old = '03 84 2E B6 EB FF FF'; New = '03 84 2E 86 78 FF FF' }
                    # lightmap read, loop 2 (r+2, c+2)
                    @{ Offset = 0x52FF1; Old = '8B 84 2F B6 EB FF FF'; New = '8B 84 2F 86 78 FF FF' }
                    # lightmap x144 -> x512, loop 2 row r+1 (eax,esi): neutralise add
                    @{ Offset = 0x53006; Old = '01 F0'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 2 row r+1 (eax,esi): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53008; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap store, loop 2 (r+1, c+1)
                    @{ Offset = 0x53013; Old = '89 BC 2B B2 EB FF FF'; New = '89 BC 2B 82 78 FF FF' }
                    # lightmap x144 -> x512, loop 3 row 2i+1 (edx,eax): neutralise add
                    @{ Offset = 0x5305B; Old = '01 C2'; New = '89 D2' }
                    # lightmap x144 -> x512, loop 3 row 2i+1 (edx,eax): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53060; Old = 'C1 E2 04'; New = 'C1 E2 06' }
                    # lightmap read, loop 3 (2i+1, 2j+1)
                    @{ Offset = 0x53065; Old = '8B 8C 2A AA EB FF FF'; New = '8B 8C 2A 7A 78 FF FF' }
                    # lightmap x144 -> x512, loop 3 row 2i+3 (eax,ecx): neutralise add
                    @{ Offset = 0x53083; Old = '01 C8'; New = '89 C0' }
                    # lightmap x144 -> x512, loop 3 row 2i+3 (eax,ecx): shl 4 -> shl log2(stride/8)
                    @{ Offset = 0x53085; Old = 'C1 E0 04'; New = 'C1 E0 06' }
                    # lightmap read, loop 3 (2i+3, 2j+1)
                    @{ Offset = 0x5308D; Old = '8B 84 28 AA EB FF FF'; New = '8B 84 28 7A 78 FF FF' }
                    # lightmap read, loop 3 (2i+1, 2j+3)
                    @{ Offset = 0x5309C; Old = '8B 94 2A B2 EB FF FF'; New = '8B 94 2A 82 78 FF FF' }
                    # lightmap read, loop 3 (2i+3, 2j+3)
                    @{ Offset = 0x530BD; Old = '8B 84 28 B2 EB FF FF'; New = '8B 84 28 82 78 FF FF' }
                    # lightplane row advance 1/32 (add eax)
                    @{ Offset = 0x5312B; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 2/32 (add eax)
                    @{ Offset = 0x53152; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 3/32 (add eax)
                    @{ Offset = 0x53175; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 4/32 (add eax)
                    @{ Offset = 0x531C2; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 5/32 (add eax)
                    @{ Offset = 0x531EE; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 6/32 (add eax)
                    @{ Offset = 0x53229; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 7/32 (add eax)
                    @{ Offset = 0x5325C; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 8/32 (add eax)
                    @{ Offset = 0x53286; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 9/32 (add eax)
                    @{ Offset = 0x532B8; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 10/32 (add eax)
                    @{ Offset = 0x532F3; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 11/32 (add eax)
                    @{ Offset = 0x53326; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 12/32 (add eax)
                    @{ Offset = 0x53359; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 13/32 (add eax)
                    @{ Offset = 0x53384; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 14/32 (add eax)
                    @{ Offset = 0x533C1; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 15/32 (add eax)
                    @{ Offset = 0x533F4; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 16/32 (add eax)
                    @{ Offset = 0x53427; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 17/32 (add eax)
                    @{ Offset = 0x5345A; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 18/32 (add eax)
                    @{ Offset = 0x5348D; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 19/32 (add eax)
                    @{ Offset = 0x534B7; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 20/32 (add eax)
                    @{ Offset = 0x534F2; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 21/32 (add eax)
                    @{ Offset = 0x53514; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 22/32 (add eax)
                    @{ Offset = 0x53556; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 23/32 (add eax)
                    @{ Offset = 0x53589; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 24/32 (add eax)
                    @{ Offset = 0x535A5; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 25/32 (add eax)
                    @{ Offset = 0x535EF; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 26/32 (add eax)
                    @{ Offset = 0x53622; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 27/32 (add eax)
                    @{ Offset = 0x53655; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 28/32 (add eax)
                    @{ Offset = 0x53688; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 29/32 (add eax)
                    @{ Offset = 0x536BB; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 30/32 (add eax)
                    @{ Offset = 0x536D6; Old = '05 00 02 00 00'; New = '05 80 0E 00 00' }
                    # lightplane row advance 31/32 (lea edi)
                    @{ Offset = 0x5371C; Old = '8D B8 00 02 00 00'; New = '8D B8 80 0E 00 00' }
                    # screen width global
                    @{ Offset = 0x867DC; Old = '80 02 00 00'; New = '00 0F 00 00' }
                    # screen height global
                    @{ Offset = 0x867E0; Old = 'E0 01 00 00'; New = '38 04 00 00' }
                )
            }

            # ---- hdpaths: Interface data from INTRF_HD (rebuilt files renamed) ---------------------------------------------------------
            #  Added      : 14 Sep 2026
            #  Made with  : tools/patch_hd_paths.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17
            #  Changes    : 120 bytes in 30 edits
            #  The rebuilt (1024x768 or another HD size) menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
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
            #  dcuk_hd.fin etc.  No code changes.  With this patch the untouched dc16.exe / ENGEXP16.EXE
            #  (stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
            #  meaningful together with the display patch, and REQUIRES the INTRF_HD/ folder holding the set built for the chosen
            #  resolution (one folder for every size, maintainer decision 21 Sep 2026).
            @{
                Id = 'hdpaths'; Name = 'Interface data from INTRF_HD (rebuilt files renamed)'; Date = '14 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = 'hd'
                Tool = 'tools/patch_hd_paths.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.17'
                Description = @'
The rebuilt (1024x768 or another HD size) menus, HUD frame, loading screens, briefing-marker lists and re-baked logo sprites
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
dcuk_hd.fin etc.  No code changes.  With this patch the untouched dc16.exe / ENGEXP16.EXE
(stock data) and the patched exe (INTRF_HD data) run side by side from one folder.  Only
meaningful together with the display patch, and REQUIRES the INTRF_HD/ folder holding the set built for the chosen
resolution (one folder for every size, maintainer decision 21 Sep 2026).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (64; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'INTRFACE\BINTROE'
                    'INTRFACE\BUTTONSE'
                    'INTRFACE\CHOO.GIF'
                    'INTRFACE\DEMOWINE'
                    'INTRFACE\DINTROE'
                    'INTRFACE\DPBLANKE'
                    'INTRFACE\DPLAYSE'
                    'INTRFACE\ENCY.GIF'
                    'INTRFACE\ENCYCLOE'
                    'INTRFACE\GETSVRE'
                    'INTRFACE\GTSUX.GIF'
                    'INTRFACE\INTRG.DAT'
                    'INTRFACE\INTRO.DAT'
                    'INTRFACE\INTROE'
                    'INTRFACE\IPXNAMEE'
                    'INTRFACE\LOAD.BMP'
                    'INTRFACE\LOAD2.BMP'
                    'INTRFACE\LOADER.GIF'
                    'INTRFACE\LOADGE'
                    'INTRFACE\LOBJE'
                    'INTRFACE\LOGOE'
                    'INTRFACE\LOPTE'
                    'INTRFACE\LOST.GIF'
                    'INTRFACE\LOSTE'
                    'INTRFACE\LQCE'
                    'INTRFACE\LSGE'
                    'INTRFACE\MAINE'
                    'INTRFACE\METAE'
                    'INTRFACE\MULTIE'
                    'INTRFACE\MULTIWIN.GIF'
                    'INTRFACE\MULTIWNE'
                    'INTRFACE\NAME.GIF'
                    'INTRFACE\NET.GIF'
                    'INTRFACE\NETOPTE'
                    'INTRFACE\NEWGAMEE'
                    'INTRFACE\SERVER.GIF'
                    'INTRFACE\SHUMAN.GIF'
                    'INTRFACE\SHUMANE'
                    'INTRFACE\STORY.GIF'
                    'INTRFACE\STORYE'
                    'INTRFACE\TCPWAIT.GIF'
                    'INTRFACE\VICTORG.GIF'
                    'INTRFACE\VICTORY.GIF'
                    'INTRFACE\WINE'
                    'INTRFACE\WINGAME.GIF'
                    'INTRFACE\WINGAMEE'
                    'INTRFACE\WINUKE'
                    'GAMESTAT\HSCENE.TXT'
                    'GAMESTAT\GSCENE.TXT'
                    'GAMESTAT\HTSCENE.TXT'
                    'GAMESTAT\GTSCENE.TXT'
                    'SPRITES\DCSS_HD.SPR'
                    'SPRITES\DCUK_HD.SPR'
                    'SPRITES\DCUT_HD.SPR'
                    'ANIMATE\DCSS_HD.FIN'
                    'ANIMATE\DCUK_HD.FIN'
                    'ANIMATE\DCUT_HD.FIN'
                    'exp\intrface\bintroe'
                    'exp\intrface\introe'
                    'exp\intrface\shumane'
                    'exp\gamestat\hxscene.txt'
                    'exp\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                )
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_pool.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13'
                Description = @'
Everything the game keeps for a session (sprite banks, screen backgrounds, light plane, map
info, game state, AI, widgets) is carved from one arena created at start-up with
"mov eax,11500000 ; call SMalloc_Pool".  At 1024x768 the backgrounds alone grow from 307 KB to
786 KB each, and extra sprite banks exhausted the arena ("SMalloc: Out of memory in local
pool" in error.log).  The fix is the constant: 0x00AF79E0 -> 0x02000000 (32 MiB).  Block
headers are 32-bit and the size check unsigned, so nothing else changes.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # mov eax,imm32 before call SMalloc_Pool: pool size 11 500 000 (0x00AF79E0) -> 33 554 432 bytes (0x02000000, 32 MiB)
                    @{ Offset = 0x4719; Old = 'B8 E0 79 AF 00'; New = 'B8 00 00 00 02' }
                )
            }

            # ---- clock @ 1024x768: Day/night clock hand re-anchored (1024x768) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1024x768 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1024x768)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1024x768'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1024x768 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (992,738), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1024x768 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 738 (0x2E2)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = 'E2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 992 (0x3E0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 03 00 00' }
                )
            }

            # ---- clock @ 1280x1024: Day/night clock hand re-anchored (1280x1024) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x1024 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,994), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x1024 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x1024)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x1024'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x1024 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,994), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x1024 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 994 (0x3E2)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = 'E2 03 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 1280x720: Day/night clock hand re-anchored (1280x720) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x720 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,690), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x720 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x720)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x720'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x720 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,690), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x720 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 690 (0x2B2)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = 'B2 02 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 1280x800: Day/night clock hand re-anchored (1280x800) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 1280x800 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (1248,770), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 1280x800 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (1280x800)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '1280x800'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 1280x800 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (1248,770), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 1280x800 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 770 (0x302)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = '02 03 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 1248 (0x4E0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 04 00 00' }
                )
            }

            # ---- clock @ 3840x1080: Day/night clock hand re-anchored (3840x1080) ---------------------------------------------------------
            #  Added      : 13 Sep 2026
            #  Made with  : tools/patch_clock.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15
            #  Changes    : 4 bytes in 2 edits
            #  The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
            #  corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
            #  sweep did not touch them.  At 3840x1080 that point lies inside the enlarged map view and the
            #  terrain paints over the hand every frame.  The anchor moves to (3808,1050), where the rebuilt
            #  HUD frame has the clock face.  Only meaningful together with the 3840x1080 display patch.
            @{
                Id = 'clock'; Name = 'Day/night clock hand re-anchored (3840x1080)'; Date = '13 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '3840x1080'
                Tool = 'tools/patch_clock.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.15'
                Description = @'
The HUD's day/night hand is a sprite cell that clock.c blits by code with its bottom-right
corner at (608,450) - two plain immediates that are neither 640 nor 480, so the resolution
sweep did not touch them.  At 3840x1080 that point lies inside the enlarged map view and the
terrain paints over the hand every frame.  The anchor moves to (3808,1050), where the rebuilt
HUD frame has the clock face.  Only meaningful together with the 3840x1080 display patch.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('resolution')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # clock_draw: imm32 of mov edx,ANCHOR_Y - bottom-right anchor y 450 (0x1C2) -> 1050 (0x41A)
                    @{ Offset = 0x3A103; Old = 'C2 01 00 00'; New = '1A 04 00 00' }
                    # clock_draw: imm32 of mov eax,ANCHOR_X - bottom-right anchor x 608 (0x260) -> 3808 (0xEE0)
                    @{ Offset = 0x3A116; Old = '60 02 00 00'; New = 'E0 0E 00 00' }
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
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

            # ---- camera: Camera clamped at battle start: no crash when the start position is near the map edge ---------------------------------------------------------
            #  Added      : 21 Sep 2026
            #  Made with  : tools/patch_camera.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.22
            #  Changes    : 34 bytes in 2 edits
            #  When a battle starts the game puts the camera on the player's start position and only
            #  afterwards computes the camera limits ("half a screen from every map edge") - but it never applies
            #  them to that first position.  The per-frame scrolling code clamps the camera, yet the very first
            #  frame already uses the unclamped position: it hands "camera minus half a screen" as the visible
            #  tile rectangle to the routine that picks the ambient sounds from the terrain on screen, and that
            #  routine walks the rectangle row by row through the map's row-pointer table without checking the far
            #  edge.  With the original 16x14-tile view no shipped start position was close enough to an edge for
            #  the rectangle to leave the map; with the 1024x768 view (28x23 tiles, "1024x768" fix) every start
            #  row within 11 tiles of the far map edge does - the row pointers past the map are NULL and the game
            #  dies with an access violation the moment the battlefield appears (Windows' crash dialog stays
            #  hidden behind the full-screen surface, so it looks like a hang; a relay server then drops the
            #  player after 5 s and the other players continue).  Hit on Fly on 19 Sep 2026 by the player whose
            #  game slot got start position 0 of "Plink - O" (row 131 of 140); Plink - O positions 0 and 1,
            #  Armageddon 3, Circle of Friends 1 and 2, Olympus Mons 0 and 1 and others are affected the same way.
            #  The fix redirects the call that follows the limit computation into a 33-byte routine placed in the
            #  unused zero bytes at the end of the code section: it calls the game's own 2-D clamp function with
            #  those limits on the camera and then continues into the routine the call originally targeted.
            #  Only register-relative addressing, no relocation entries, nothing moves.  Harmless without the
            #  1024x768 fix and in single-player missions (a clamp can only move the camera inside the map).
            @{
                Id = 'camera'; Name = 'Camera clamped at battle start: no crash when the start position is near the map edge'; Date = '21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_camera.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.22'
                Description = @'
When a battle starts the game puts the camera on the player's start position and only
afterwards computes the camera limits ("half a screen from every map edge") - but it never applies
them to that first position.  The per-frame scrolling code clamps the camera, yet the very first
frame already uses the unclamped position: it hands "camera minus half a screen" as the visible
tile rectangle to the routine that picks the ambient sounds from the terrain on screen, and that
routine walks the rectangle row by row through the map's row-pointer table without checking the far
edge.  With the original 16x14-tile view no shipped start position was close enough to an edge for
the rectangle to leave the map; with the 1024x768 view (28x23 tiles, "1024x768" fix) every start
row within 11 tiles of the far map edge does - the row pointers past the map are NULL and the game
dies with an access violation the moment the battlefield appears (Windows' crash dialog stays
hidden behind the full-screen surface, so it looks like a hang; a relay server then drops the
player after 5 s and the other players continue).  Hit on Fly on 19 Sep 2026 by the player whose
game slot got start position 0 of "Plink - O" (row 131 of 140); Plink - O positions 0 and 1,
Armageddon 3, Circle of Friends 1 and 2, Olympus Mons 0 and 1 and others are affected the same way.
The fix redirects the call that follows the limit computation into a 33-byte routine placed in the
unused zero bytes at the end of the code section: it calls the game's own 2-D clamp function with
those limits on the camera and then continues into the routine the call originally targeted.
Only register-relative addressing, no relocation entries, nothing moves.  Harmless without the
1024x768 fix and in single-player missions (a clamp can only move the camera inside the map).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # proto.c init: call load_ambience -> call stub: rel32 operand of the E8 that follows the camera-bounds stores; the stub clamps the camera first and then continues into load_ambience 0x00432FE0
                    @{ Offset = 0x1E319; Old = 'C3 40 01 00'; New = 'F3 03 06 00' }
                    # stub clamp_camera in the AUTO zero tail: lea esi,[eax+108h]; push &cam_z, &cam_x, max_z, max_x, min_z, min_x (ui+0x120..0x114); call clamp2d 0x004366C8; jmp load_ambience 0x00432FE0 - register-relative only, no .reloc entries
                    @{ Offset = 0x7E710; Old = '00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'; New = '8D B0 08 01 00 00 8D 4E 08 51 56 FF 76 18 FF 76 14 FF 76 10 FF 76 0C E8 9C 73 FB FF E9 AF 3C FB FF' }
                )
            }

            # ---- widemap: Maps narrower than the screen: the view is centred on the map and every map read stays inside it ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_widemap.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.32
            #  Changes    : 368 bytes in 26 edits
            #  The battlefield view is the screen minus the panel, in whole 32-pixel tiles: 28 tiles across at
            #  1024x768, 36 at 1280x800, 76 at 2560x1440, 116 at 3840x1080.  The maps are 64 to 160 tiles wide
            #  (the training maps and two two-player maps 64, the first two campaign missions and 22 two-player
            #  maps 96).  Once the view is wider than the map the game's camera limits ("half a screen from every
            #  map edge") contradict each other and the camera settles at the far one, so the view begins left of
            #  the map; nothing that then reads the map checks for that: the terrain drawer continues into the
            #  neighbouring rows (the far side of the map drawn shifted by a row) and, at the top and bottom map
            #  row, past the tile block into memory whose contents it takes for tile numbers - a crash in the tile
            #  blitter as soon as the camera reaches those rows; the lighting pass reads before and after each row;
            #  the visibility scan tests tiles of the wrong row; the ambient sounds fall silent (their picker gives
            #  up when the visible rectangle starts left of the map); a click on the black margin sends units to
            #  the far side of the map (the position wraps in a 16-bit field).  The fix, in six parts written into
            #  the dead body of the CD-probe routine (unused since the "No CD" fix, which is therefore required,
            #  as is the "Camera clamped" fix whose stub the first part chains into): (1) when the limits
            #  contradict each other, both become the map centre, so the map sits centred in the view and cannot
            #  scroll sideways; (2) the terrain drawer clamps every column to the map, so the margin repeats the
            #  edge tiles instead of reading beyond them; (3) the lighting pass clamps rows and columns the same
            #  way (in place of its four edge cases); (4) the visibility rectangle is cut to the map; (5) the
            #  ambient-sound picker clamps its rectangle instead of giving up; (6) a spot order's x is clamped to
            #  the map.  The 14 relocation entries of the dead routine are re-pointed to the new absolute operands
            #  or neutralised.  Rows are never affected with the shipped maps (the tallest view, 44 rows at
            #  5120x1440, is shorter than the smallest map, 56 rows), so only the column direction is handled.
            #  Without a wide screen the fix changes nothing visible: every map is wider than 28 or 36 tiles.
            @{
                Id = 'widemap'; Name = 'Maps narrower than the screen: the view is centred on the map and every map read stays inside it'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_widemap.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.32'
                Description = @'
The battlefield view is the screen minus the panel, in whole 32-pixel tiles: 28 tiles across at
1024x768, 36 at 1280x800, 76 at 2560x1440, 116 at 3840x1080.  The maps are 64 to 160 tiles wide
(the training maps and two two-player maps 64, the first two campaign missions and 22 two-player
maps 96).  Once the view is wider than the map the game's camera limits ("half a screen from every
map edge") contradict each other and the camera settles at the far one, so the view begins left of
the map; nothing that then reads the map checks for that: the terrain drawer continues into the
neighbouring rows (the far side of the map drawn shifted by a row) and, at the top and bottom map
row, past the tile block into memory whose contents it takes for tile numbers - a crash in the tile
blitter as soon as the camera reaches those rows; the lighting pass reads before and after each row;
the visibility scan tests tiles of the wrong row; the ambient sounds fall silent (their picker gives
up when the visible rectangle starts left of the map); a click on the black margin sends units to
the far side of the map (the position wraps in a 16-bit field).  The fix, in six parts written into
the dead body of the CD-probe routine (unused since the "No CD" fix, which is therefore required,
as is the "Camera clamped" fix whose stub the first part chains into): (1) when the limits
contradict each other, both become the map centre, so the map sits centred in the view and cannot
scroll sideways; (2) the terrain drawer clamps every column to the map, so the margin repeats the
edge tiles instead of reading beyond them; (3) the lighting pass clamps rows and columns the same
way (in place of its four edge cases); (4) the visibility rectangle is cut to the map; (5) the
ambient-sound picker clamps its rectangle instead of giving up; (6) a spot order's x is clamped to
the map.  The 14 relocation entries of the dead routine are re-pointed to the new absolute operands
or neutralised.  Rows are never affected with the shipped maps (the tallest view, 44 rows at
5120x1440, is shorter than the smallest map, 56 rows), so only the column direction is handled.
Without a wide screen the fix changes nothing visible: every map is wider than 28 or 36 tiles.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('nocd', 'camera')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # cd_probe dead body: bounds rule + column stub + vision stub + order stub: bounds rule at +0 (per axis `if max < min: min = max = (min+max)/2`, 10 absolute operands, jmp camera stub 0x0047F310), column stub at +73, vision stub at +124 (call make_rect 0x0043661C, 1 absolute operand), order stub at +158
                    @{ Offset = 0x528D; Old = '51 52 56 55 89 E5 81 EC 00 01 00 00 68 B0 48 4A 00 30 E4 68 24 26 48 00 88 25 B8 49 4A 00 8D 85 00 FF FF FF 50 E8 0D 62 07 00 83 C4 0C BA 30 26 48 00 8D 85 00 FF FF FF E8 1A 5D 07 00 85 C0 75 0F A0 1C 8E 48 00 A2 B8 49 4A 00 E9 83 00 00 00 E8 FD 5D 07 00 BE A0 86 01 00 31 D2 E8 A2 55 00 00 F7 F6 52 68 B0 48 4A 00 68 34 26 48 00 8D 85 00 FF FF FF 50 E8 BD 61 07 00 83 C4 10 BA 3C 26 48 00 8D 85 00 FF FF FF E8 CA 5C 07 00 89 C6 85 C0 75 0F C6 05 B8 49 4A 00 01 89 EC 5D 5E 5A 59 5B C3 BB 01 00 00 00 89 C1 B8 40 26 48 00 89 DA E8 66 62 07 00 85 C0 75 09 C6 05 B8 49 4A 00 01 EB 0A A0 1C 8E 48 00 A2 B8 49 4A 00 89 F0 E8'; New = '8B 0D EC AA 4A 00 3B 0D E4 AA 4A 00 7D 14 03 0D E4 AA 4A 00 D1 F9 89 0D E4 AA 4A 00 89 0D EC AA 4A 00 8B 0D F0 AA 4A 00 3B 0D E8 AA 4A 00 7D 14 03 0D E8 AA 4A 00 D1 F9 89 0D E8 AA 4A 00 89 0D F0 AA 4A 00 E9 3A 94 07 00 8B 06 C1 F8 05 8D 14 38 85 D2 7D 02 31 D2 8B 4E 14 0F BF 09 49 39 CA 7E 02 89 CA 29 C2 C1 E2 02 89 55 BC 8B 45 C8 8D 04 B8 89 45 B8 8A 4D F4 8B 45 F8 C3 E8 0E 07 03 00 8B 15 C0 44 50 00 83 38 00 7D 03 83 20 00 8B 8A B0 A4 09 00 39 48 08 7E 03 89 48 08 C3 51 8B 48 0C 8B 89 4C 6F 04 00 85 D2 7D 02 31 D2 3B 91 B8 A4 09 00 7C 07 8B 91 B8 A4 09 00 4A 89 D6 59 66 89 98 92 07 00 00 66 89 90 90 07 00 00 C3' }
                    # spot order: the two 16-bit stores of the world point -> call order stub (clamps x to [0, map_w*256-1], updates esi, then stores)
                    @{ Offset = 0x8AFF; Old = '66 89 98 92 07 00 00 66 89 90 90 07 00 00'; New = 'E8 27 C8 FF FF 90 90 90 90 90 90 90 90 90' }
                    # proto.c init: call camera stub -> call bounds rule (which chains into the camera stub)
                    @{ Offset = 0x1E318; Old = 'E8 F3 03 06 00'; New = 'E8 70 6F FE FF' }
                    # clip_view_to_map: call make_rect -> call vision stub (make_rect, then x0 = max(x0,0), x1 = min(x1,w))
                    @{ Offset = 0x352C2; Old = 'E8 55 07 00 00'; New = 'E8 42 00 FD FF' }
                    # ambience pick: origin guards -> x0 = max(x0,0), w = min(w, W-x0); the z guard keeps its stock meaning (return 0 via 0x00445C4A)
                    @{ Offset = 0x44F1D; Old = '85 FF 7C 0E 8B 96 4C 6F 04 00 3B BA B0 A4 09 00 7E 07 31 C0 E9 14 01 00 00 85 DB 7C 08 3B 9A B4 A4 09 00 7E 0B 31 C0 8D 65 7E 5D 5F 5E C2 04 00'; New = '85 FF 7D 02 31 FF 8B 96 4C 6F 04 00 8B 8A B0 A4 09 00 29 F9 39 C8 7E 02 89 C8 85 DB 7C 08 3B 9A B4 A4 09 00 7E 0A 31 C0 E9 00 01 00 00 90 90 90' }
                    # tile drawer: sub esp,38h -> 48h; two new locals [ebp-44h] = clamped column offset, [ebp-48h] = mask column pointer
                    @{ Offset = 0x4F583; Old = '83 EC 38'; New = '83 EC 48' }
                    # tile drawer: column-loop head `mov cl,[ebp-0Ch]; mov eax,[ebp-8]` -> call column stub (which runs both); NOP
                    @{ Offset = 0x4F632; Old = '8A 4D F4 8B 45 F8'; New = 'E8 9F 5C FB FF 90' }
                    # tile drawer: `lea ecx,[edi*4]` (tile word column) -> `mov ecx,[ebp-44h]` clamped offset
                    @{ Offset = 0x4F66C; Old = '8D 0C BD 00 00 00 00'; New = '8B 4D BC 90 90 90 90' }
                    # tile drawer: mask pointer `mov eax,[ebp-38h]; add eax,ecx` -> `mov eax,[ebp-48h]` (real column, computed by the stub)
                    @{ Offset = 0x4F6D4; Old = '8B 45 C8 8A 5C 11 03 01 C8 F6 C3 08'; New = '8B 45 B8 8A 5C 11 03 90 90 F6 C3 08' }
                    # tile drawer: `lea edx,[edi*4]` (fg flag word) -> `mov edx,[ebp-44h]`
                    @{ Offset = 0x4F6F3; Old = '8D 14 BD 00 00 00 00'; New = '8B 55 BC 90 90 90 90' }
                    # tile drawer: `lea edx,[edi*4]` (fg tile word) -> `mov edx,[ebp-44h]`
                    @{ Offset = 0x4F713; Old = '8D 14 BD 00 00 00 00'; New = '8B 55 BC 90 90 90 90' }
                    # draw_terrain lightmap pass: the four edge-flag corrections -> clamp the map row to [0,h-1] and the column to [0,w-1] (esi/edi scratch, eax = row, [ebp+72h] = column)
                    @{ Offset = 0x52EE0; Old = '85 F6 74 06 83 F9 FF 75 01 40 83 7D 42 00 74 06 3B 4D 6A 75 01 48 83 7D 3E 00 74 08 83 FA FF 75 03 FF 45 72 83 7D 46 00 74 08 3B 55 6E 75 03 FF 4D 72'; New = '8B 73 14 85 C0 7D 02 31 C0 8B BE B4 A4 09 00 4F 39 F8 7E 02 89 F8 8B 7D 72 85 FF 7D 02 31 FF 8B B6 B0 A4 09 00 4E 39 F7 7E 02 89 F7 89 7D 72 90 90 90' }
                    # .reloc table: entry 3E9A -> 3E8F: the absolute operand moved from page offset 0xE9A to 0xE8F, entry follows it
                    @{ Offset = 0x97C68; Old = '9A 3E'; New = '8F 3E' }
                    # .reloc table: entry 3EA1 -> 3E95: the absolute operand moved from page offset 0xEA1 to 0xE95, entry follows it
                    @{ Offset = 0x97C6A; Old = 'A1 3E'; New = '95 3E' }
                    # .reloc table: entry 3EA7 -> 3E9D: the absolute operand moved from page offset 0xEA7 to 0xE9D, entry follows it
                    @{ Offset = 0x97C6C; Old = 'A7 3E'; New = '9D 3E' }
                    # .reloc table: entry 3EBB -> 3EA5: the absolute operand moved from page offset 0xEBB to 0xEA5, entry follows it
                    @{ Offset = 0x97C6E; Old = 'BB 3E'; New = 'A5 3E' }
                    # .reloc table: entry 3ECF -> 3EAB: the absolute operand moved from page offset 0xECF to 0xEAB, entry follows it
                    @{ Offset = 0x97C70; Old = 'CF 3E'; New = 'AB 3E' }
                    # .reloc table: entry 3ED4 -> 3EB1: the absolute operand moved from page offset 0xED4 to 0xEB1, entry follows it
                    @{ Offset = 0x97C72; Old = 'D4 3E'; New = 'B1 3E' }
                    # .reloc table: entry 3EF2 -> 3EB7: the absolute operand moved from page offset 0xEF2 to 0xEB7, entry follows it
                    @{ Offset = 0x97C74; Old = 'F2 3E'; New = 'B7 3E' }
                    # .reloc table: entry 3EF7 -> 3EBF: the absolute operand moved from page offset 0xEF7 to 0xEBF, entry follows it
                    @{ Offset = 0x97C76; Old = 'F7 3E'; New = 'BF 3E' }
                    # .reloc table: entry 3F0B -> 3EC7: the absolute operand moved from page offset 0xF0B to 0xEC7, entry follows it
                    @{ Offset = 0x97C78; Old = '0B 3F'; New = 'C7 3E' }
                    # .reloc table: entry 3F22 -> 3ECD: the absolute operand moved from page offset 0xF22 to 0xECD, entry follows it
                    @{ Offset = 0x97C7A; Old = '22 3F'; New = 'CD 3E' }
                    # .reloc table: entry 3F37 -> 3F10: the absolute operand moved from page offset 0xF37 to 0xF10, entry follows it
                    @{ Offset = 0x97C7C; Old = '37 3F'; New = '10 3F' }
                    # .reloc table: entry 3F48 (type 3 HIGHLOW, page offset 0xF48) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97C7E; Old = '48 3F'; New = '00 00' }
                    # .reloc table: entry 3F50 (type 3 HIGHLOW, page offset 0xF50) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97C80; Old = '50 3F'; New = '00 00' }
                    # .reloc table: entry 3F55 (type 3 HIGHLOW, page offset 0xF55) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x97C82; Old = '55 3F'; New = '00 00' }
                )
            }

            # ---- restore: Window restore after minimising: Alt+Tab and the taskbar bring the game back ---------------------------------------------------------
            #  Added      : 21 Sep 2026
            #  Made with  : tools/patch_restore.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.28
            #  Changes    : 86 bytes in 2 edits
            #  Leave the running game with Alt+Tab, the Win key or a click on another window and DirectDraw
            #  minimises it and restores the desktop resolution.  Coming back with Alt+Tab or the taskbar button
            #  the game stays minimised although it is the active window, or shows a black window at desktop
            #  resolution; it is alive and busy, error.log stays empty.  The game has no message loop: once per
            #  frame it pulls posted messages with range-filtered PeekMessage calls (mouse, keyboard, system
            #  commands - the last only to swallow the screen-saver command) and dispatches none of them.
            #  Windows restores a minimised window by posting the system command SC_RESTORE to it, so the request
            #  is removed from the queue and dropped; being activated while still minimised also defeats
            #  DirectDraw's own window hook, which re-sets the exclusive display mode only during a proper
            #  activation - afterwards every attempt to restore the drawing surfaces fails with DDERR_WRONGMODE.
            #  The fix rewrites that per-frame block in place (107 bytes, 86 of them new code, the rest NOP):
            #  the system-command peek hands every command except the screen saver to DefWindowProcA, so
            #  SC_RESTORE, SC_MINIMIZE and the others take effect, and after an SC_RESTORE it calls
            #  ShowWindow(SW_MINIMIZE) followed by ShowWindow(SW_RESTORE) - a deactivate/activate cycle on a window
            #  that is not minimised at the moment of activation, which is the path DirectDraw's hook handles: it
            #  re-sets the mode, the game's own per-frame surface restore repairs the surfaces and the next frame
            #  is drawn.  The two peeks it replaces looked for WM_SETCURSOR and WM_DESTROY, messages Windows never
            #  posts (dead code).  Second part: while minimised the game's main loop used to spin at 100 % of a
            #  processor core - the per-frame present routine fails its blit, fails the surface restore and
            #  returns early, so the Flip that normally paces the loop is never reached (about 4 400 passes per
            #  second).  The branch taken after that failed restore now goes to a 12-byte stub in the spare tail
            #  of the same block: Sleep(1) - one system timer period, at most 16 ms, well inside the 44 ms game
            #  tick - then back to the routine's exit.  Game ticks are clock-driven and keep running while
            #  minimised (a multiplayer client stays in the game), only the idle spin is gone.  The four calls go
            #  through the linker's import thunks; nothing moves, no relocation entry changes.  Verified in game
            #  21 Sep 2026 on both exes (Alt+Tab, taskbar button, Start menu, minimise from the taskbar).
            @{
                Id = 'restore'; Name = 'Window restore after minimising: Alt+Tab and the taskbar bring the game back'; Date = '21 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_restore.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.28'
                Description = @'
Leave the running game with Alt+Tab, the Win key or a click on another window and DirectDraw
minimises it and restores the desktop resolution.  Coming back with Alt+Tab or the taskbar button
the game stays minimised although it is the active window, or shows a black window at desktop
resolution; it is alive and busy, error.log stays empty.  The game has no message loop: once per
frame it pulls posted messages with range-filtered PeekMessage calls (mouse, keyboard, system
commands - the last only to swallow the screen-saver command) and dispatches none of them.
Windows restores a minimised window by posting the system command SC_RESTORE to it, so the request
is removed from the queue and dropped; being activated while still minimised also defeats
DirectDraw's own window hook, which re-sets the exclusive display mode only during a proper
activation - afterwards every attempt to restore the drawing surfaces fails with DDERR_WRONGMODE.
The fix rewrites that per-frame block in place (107 bytes, 86 of them new code, the rest NOP):
the system-command peek hands every command except the screen saver to DefWindowProcA, so
SC_RESTORE, SC_MINIMIZE and the others take effect, and after an SC_RESTORE it calls
ShowWindow(SW_MINIMIZE) followed by ShowWindow(SW_RESTORE) - a deactivate/activate cycle on a window
that is not minimised at the moment of activation, which is the path DirectDraw's hook handles: it
re-sets the mode, the game's own per-frame surface restore repairs the surfaces and the next frame
is drawn.  The two peeks it replaces looked for WM_SETCURSOR and WM_DESTROY, messages Windows never
posts (dead code).  Second part: while minimised the game's main loop used to spin at 100 % of a
processor core - the per-frame present routine fails its blit, fails the surface restore and
returns early, so the Flip that normally paces the loop is never reached (about 4 400 passes per
second).  The branch taken after that failed restore now goes to a 12-byte stub in the spare tail
of the same block: Sleep(1) - one system timer period, at most 16 ms, well inside the 44 ms game
tick - then back to the routine's exit.  Game ticks are clock-driven and keep running while
minimised (a multiplayer client stays in the game), only the idle spin is gone.  The four calls go
through the linker's import thunks; nothing moves, no relocation entry changes.  Verified in game
21 Sep 2026 on both exes (Alt+Tab, taskbar button, Start menu, minimise from the taskbar).
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # present(): failed surface restore -> idle stub instead of exit: the jne after restore_surfaces (taken while the window is minimised: BltFast DDERR_SURFACELOST, Restore DDERR_WRONGMODE) goes to the stub at 0x0042F2F3, which sleeps one timer period and continues to the original exit 0x0042E301 - the main loop no longer spins at 100% CPU while minimised, game ticks are clock-driven and unaffected
                    @{ Offset = 0x2D5AF; Old = '0F 85 4C 01 00 00'; New = '0F 85 3E 11 00 00' }
                    # frame_end: posted WM_SYSCOMMAND dispatched, SC_RESTORE re-activates: the WM_SYSCOMMAND PeekMessageA(PM_REMOVE) keeps swallowing SC_SCREENSAVE but hands every other system command to DefWindowProcA(msg.hwnd, WM_SYSCOMMAND, wParam, lParam) - so the SC_RESTORE that Alt+Tab, the taskbar and Win+D post to a minimised window restores it; for SC_RESTORE it then calls ShowWindow(hwnd, SW_MINIMIZE) and ShowWindow(hwnd, SW_RESTORE), the deactivate/activate cycle on a non-iconic window that makes DirectDraw re-set the exclusive display mode; the two dead peeks for WM_SETCURSOR and WM_DESTROY (never posted) are replaced; bytes 86..97 are the idle stub for present(): Sleep(1) through the thunk 0x0047F068, then jmp to the present() exit 0x0042E301; the rest is NOP; calls through the import thunks 0x0047F038 / 0x0047F01A / 0x0047EFF0, no .reloc changes
                    @{ Offset = 0x2E69D; Old = '6A 01 68 12 01 00 00 68 12 01 00 00 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 09 81 7D EC 40 F1 00 00 74 45 6A 01 6A 20 6A 20 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 09 6A 00 2E FF 15 E0 03 48 00 6A 01 6A 02 6A 02 6A 00 8D 45 E4 50 2E FF 15 D4 03 48 00 85 C0 74 0E E8 11 F0 FF FF 6A 00 2E FF 15 D8 03 48 00'; New = '6A 01 68 12 01 00 00 68 12 01 00 00 6A 00 8D 45 E4 50 E8 84 FD 04 00 85 C0 74 50 81 7D EC 40 F1 00 00 74 47 FF 75 F0 FF 75 EC 68 12 01 00 00 FF 75 E4 E8 46 FD 04 00 81 7D EC 20 F1 00 00 75 2B 6A 06 FF 75 E4 E8 09 FD 04 00 6A 09 FF 75 E4 E8 FF FC 04 00 EB 15 6A 01 E8 6E FD 04 00 E9 02 F0 FF FF 90 90 90 90 90 90 90 90 90' }
                )
            }

            # ---- longpath: Sound files load from any folder depth: the wave loader no longer uses the 128-character OpenFile ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_longpath.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.29
            #  Changes    : 57 bytes in 4 edits
            #  Installed in a deep folder (about 128 characters of path and more, e.g. a repository ZIP
            #  extracted under Downloads and then moved into a sub-folder), the game shows "FILE NOT FOUND /
            #  A sound file is missing - see error.log" about five seconds after start and exits; error.log
            #  holds the line "unable to open file" with no name after it.  The same files run fine from a
            #  short path.  Cause: the routine that loads every WAV (sound banks, briefings, ambience) is the
            #  only code in the game that opens files through the Windows 3.1-era OpenFile function, which
            #  writes the full path into a 128-character field and fails outright when it does not fit.  All
            #  other loaders use the C runtime (CreateFileA underneath) and have no such limit, so the rest
            #  of the game runs and only the first sound kills it.  The empty name is a leftover of the
            #  "No CD" fix: the error message printed the buffer of the skipped CD attempt.  The fix replaces
            #  the two live OpenFile calls with calls to a 22-byte routine written over the first CD attempt
            #  (dead code since the "No CD" fix, which is therefore required): CreateFileA(name, GENERIC_READ,
            #  FILE_SHARE_READ, OPEN_EXISTING) - it returns -1 on failure exactly like OpenFile, and its
            #  handle is what the loader's seek, read and close calls take.  The error message now names the
            #  file that was tried.  Register-relative operands and a call through the import thunk only;
            #  nothing moves, no relocation entry changes; the same four edits at +0x60 in Council Wars.
            #  Verified 22 Sep 2026: from a 161-character game folder path the unfixed Council Wars exe fails
            #  at 5 s, the fixed one plays on with an empty error.log.
            @{
                Id = 'longpath'; Name = 'Sound files load from any folder depth: the wave loader no longer uses the 128-character OpenFile'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_longpath.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.29'
                Description = @'
Installed in a deep folder (about 128 characters of path and more, e.g. a repository ZIP
extracted under Downloads and then moved into a sub-folder), the game shows "FILE NOT FOUND /
A sound file is missing - see error.log" about five seconds after start and exits; error.log
holds the line "unable to open file" with no name after it.  The same files run fine from a
short path.  Cause: the routine that loads every WAV (sound banks, briefings, ambience) is the
only code in the game that opens files through the Windows 3.1-era OpenFile function, which
writes the full path into a 128-character field and fails outright when it does not fit.  All
other loaders use the C runtime (CreateFileA underneath) and have no such limit, so the rest
of the game runs and only the first sound kills it.  The empty name is a leftover of the
"No CD" fix: the error message printed the buffer of the skipped CD attempt.  The fix replaces
the two live OpenFile calls with calls to a 22-byte routine written over the first CD attempt
(dead code since the "No CD" fix, which is therefore required): CreateFileA(name, GENERIC_READ,
FILE_SHARE_READ, OPEN_EXISTING) - it returns -1 on failure exactly like OpenFile, and its
handle is what the loader's seek, read and close calls take.  The error message now names the
file that was tried.  Register-relative operands and a call through the import thunk only;
nothing moves, no relocation entry changes; the same four edits at +0x60 in Council Wars.
Verified 22 Sep 2026: from a 161-character game folder path the unfixed Council Wars exe fails
at 5 s, the fixed one plays on with an empty error.log.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('nocd')
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # wave loader, first open (prefix+name): OpenFile(name,&ofs,OF_READ) -> lea eax,[ebp-80Eh]; call open_read 0x00452b4f; 9 x nop
                    @{ Offset = 0x51F17; Old = '6A 00 8D 45 F2 50 8D 85 F2 F7 FF FF 50 2E FF 15 C8 04 48 00'; New = '8D 85 F2 F7 FF FF E8 2D 00 00 00 90 90 90 90 90 90 90 90 90' }
                    # wave loader, second open (bare name): OpenFile(ebx,&ofs,OF_READ) -> mov eax,ebx; call open_read 0x00452b4f; 7 x nop
                    @{ Offset = 0x51F36; Old = '6A 00 8D 45 F2 50 53 2E FF 15 C8 04 48 00'; New = '89 D8 E8 12 00 00 00 90 90 90 90 90 90 90' }
                    # stub open_read over the dead first CD attempt: push 0,0,OPEN_EXISTING,0,FILE_SHARE_READ,GENERIC_READ,eax; call CreateFileA thunk 0x0047ef9c (IAT slot 0x004803f8); ret - returns the handle or -1 like OpenFile did
                    @{ Offset = 0x51F4F; Old = 'E8 2C 33 FB FF 8D BD F2 FB FF FF 89 C6 57 8A 06 88 07 3C 00 74 10'; New = '6A 00 6A 00 6A 03 6A 00 6A 01 68 00 00 00 80 50 E8 38 C4 02 00 C3' }
                    # error exit fprintf/MessageBox name: lea eax,[ebp-40Eh] (CD buffer, empty since nocd) -> lea eax,[ebp-80Eh] (prefix+name)
                    @{ Offset = 0x5202D; Old = 'F2 FB FF FF'; New = 'F2 F7 FF FF' }
                )
            }

            # ---- music: Original CD soundtrack from MP3 files (MUSIC\TRACK02-05.MP3 / exp\music\track02-05.mp3) ---------------------------------------------------------
            #  Added      : 22 Sep 2026
            #  Made with  : tools/patch_music.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.31
            #  Changes    : 1794 bytes in 46 edits
            #  The soundtrack of both games was never a file: the CDs are mixed-mode discs with the music as
            #  audio tracks 2-5 after the data track, and the game plays them through Windows' CD-audio
            #  interface (MCI "cdaudio") - at the start of every battle it seeks to track 2 and plays the disc to
            #  its end, checks every five seconds whether the disc has stopped and then starts over at track 2,
            #  and stops the disc when the battle ends.  Without a CD-ROM drive that interface fails at start-up
            #  and the game is silent for good; the music slider of the options screen sets a "CD line" volume
            #  that modern sound drivers no longer have.
            #
            #  This fix rewrites the CD-audio routines in place (the seven entry points the music code calls
            #  keep their addresses) as an MP3 player on Windows' own MCI "mpegvideo" device (mciqtz32.dll,
            #  part of every Windows since 98; the exe imports nothing new): at battle start it opens and plays
            #  MUSIC\TRACK02.MP3, the five-second check plays the next file when one has ended and TRACK02
            #  again after the last one - the original "whole disc, repeat" - and the music slider now sets the
            #  volume of the playing file (the saved level is applied to every track).  Dark Colony reads
            #  MUSIC\TRACK0N.MP3, Council Wars exp\music\track0N.mp3, because both exes share one folder and
            #  the two discs have different music.  Everything inside the two rewritten routines; the
            #  relocation entries of the old code's absolute operands are re-pointed at the new ones and the
            #  rest become padding; nothing moves.
            #
            #  REQUIRES the eight tracks from the repository (encoded from the CD images at 192 kbit/s, 32 MB):
            #  MUSIC\TRACK02.MP3 .. TRACK05.MP3 for Dark Colony, exp\music\track02.mp3 .. track05.mp3 for
            #  Council Wars.  Without a TRACK02 file the game simply stays silent, as it does today.
            @{
                Id = 'music'; Name = 'Original CD soundtrack from MP3 files (MUSIC\TRACK02-05.MP3 / exp\music\track02-05.mp3)'; Date = '22 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_music.py'; Doc = 'docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.31'
                Description = @'
The soundtrack of both games was never a file: the CDs are mixed-mode discs with the music as
audio tracks 2-5 after the data track, and the game plays them through Windows' CD-audio
interface (MCI "cdaudio") - at the start of every battle it seeks to track 2 and plays the disc to
its end, checks every five seconds whether the disc has stopped and then starts over at track 2,
and stops the disc when the battle ends.  Without a CD-ROM drive that interface fails at start-up
and the game is silent for good; the music slider of the options screen sets a "CD line" volume
that modern sound drivers no longer have.

This fix rewrites the CD-audio routines in place (the seven entry points the music code calls
keep their addresses) as an MP3 player on Windows' own MCI "mpegvideo" device (mciqtz32.dll,
part of every Windows since 98; the exe imports nothing new): at battle start it opens and plays
MUSIC\TRACK02.MP3, the five-second check plays the next file when one has ended and TRACK02
again after the last one - the original "whole disc, repeat" - and the music slider now sets the
volume of the playing file (the saved level is applied to every track).  Dark Colony reads
MUSIC\TRACK0N.MP3, Council Wars exp\music\track0N.mp3, because both exes share one folder and
the two discs have different music.  Everything inside the two rewritten routines; the
relocation entries of the old code's absolute operands are re-pointed at the new ones and the
rest become padding; nothing moves.

REQUIRES the eight tracks from the repository (encoded from the CD images at 192 kbit/s, 32 MB):
MUSIC\TRACK02.MP3 .. TRACK05.MP3 for Dark Colony, exp\music\track02.mp3 .. track05.mp3 for
Council Wars.  Without a TRACK02 file the game simply stays silent, as it does today.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (4; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'exp\music\track02.mp3'
                    'exp\music\track03.mp3'
                    'exp\music\track04.mp3'
                    'exp\music\track05.mp3'
                )
                Edits = @(
                    # cdaudio module -> MP3 player on MCI mpegvideo (seven entry points kept: cd_open +0, play_from_here +0x3C, close +0x88, stop +0xB8, tracks +0x338, seek_track +0x4E8, mode +0x6E0; helpers, "mpegvideo" and the path template "exp\\music\\track0?.mp3" inside; the rest zero)
                    @{ Offset = 0x50530; Old = '51 52 55 89 E5 83 EC 14 8D 45 EC 50 68 00 21 00 00 68 03 08 00 00 31 D2 B9 24 7C 48 00 52 89 55 F0 89 4D F4 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F0 89 EC 5D 5A 59 C3 53 51 52 55 89 E5 83 EC 18 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 0A 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 75 15 8D 45 E8 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 5B C3 51 52 55 89 E5 6A 00 6A 00 68 04 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 06 31 C0 5D 5A 59 C3 B8 01 00 00 00 5D 5A 59 C3 8B C0 51 52 55 89 E5 83 EC 04 8D 55 FC 52 6A 00 68 08 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 C3 53 51 52 55 89 E5 83 EC 20 8D 5D E0 53 68 00 01 00 00 31 DB 68 14 08 00 00 66 89 C3 BA 04 00 00 00 53 89 55 E8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 4E 81 7D E4 0D 02 00 00 75 20 8D 45 F0 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 29 31 C0 89 EC 5D 5A 59 5B C3 8D 45 FC 50 6A 00 68 09 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5A 59 5B C3 B8 01 00 00 00 89 EC 5D 5A 59 5B C3 8D 40 00 53 51 52 56 57 55 89 E5 83 EC 28 89 C3 8D 45 D8 50 68 00 01 00 00 31 F6 68 14 08 00 00 66 89 DE BA 08 00 00 00 56 89 55 E0 2E FF 15 70 05 48 00 85 C0 74 07 31 C0 E9 A7 00 00 00 8B 45 DC 89 45 FC 8D 45 D8 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 56 89 4D E0 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8B 75 FC 8B 7D DC 46 BA 08 00 00 00 39 FE 76 0C B8 02 00 00 00 BE 01 00 00 00 EB 0A 8A 45 FC FE C0 25 FF 00 00 00 89 45 F8 8D 45 F4 50 52 68 07 08 00 00 81 E3 FF FF 00 00 53 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8D 45 E8 50 6A 00 68 06 08 00 00 53 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 89 F0 89 EC 5D 5F 5E 5A 59 5B C3 90 53 51 52 56 57 55 89 E5 83 EC 24 89 C6 8D 45 DC 50 68 00 01 00 00 31 FF 68 14 08 00 00 66 89 F7 BA 08 00 00 00 57 89 55 E4 2E FF 15 70 05 48 00 85 C0 74 07 31 C0 E9 9A 00 00 00 8D 45 DC 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 57 8B 5D E0 89 4D E4 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 BF 08 00 00 00 83 FB 01 75 08 8A 45 E0 8B 5D E0 EB 0A 88 D8 FE C8 25 FF 00 00 00 4B 89 45 FC 8D 45 F8 50 57 68 07 08 00 00 81 E6 FF FF 00 00 56 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8D 45 EC 50 6A 00 68 06 08 00 00 56 2E FF 15 70 05 48 00 85 C0 74 0B 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 89 D8 89 EC 5D 5F 5E 5A 59 5B C3 8B C0 51 52 55 89 E5 83 EC 10 C7 45 F8 03 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F4 89 EC 5D 5A 59 C3 90 51 52 55 89 E5 83 EC 10 C7 45 F8 08 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 03 8B 45 F4 89 EC 5D 5A 59 C3 90 53 51 52 55 89 E5 83 EC 1C 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 0A 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 2E 8D 45 E4 50 68 00 01 00 00 68 14 08 00 00 B9 02 00 00 00 53 89 4D EC 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5A 59 5B C3 8B 45 E8 89 EC 5D 5A 59 5B C3 8D 40 00 53 51 52 56 55 89 E5 83 EC 1C 8D 5D F4 53 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 C3 BA 02 00 00 00 53 89 55 F8 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 5B 8D 45 E4 50 68 00 01 00 00 68 14 08 00 00 B9 02 00 00 00 53 89 4D EC 2E FF 15 70 05 48 00 85 C0 74 0A 31 C0 89 EC 5D 5E 5A 59 5B C3 8D 45 F4 50 68 00 04 00 00 68 0D 08 00 00 BE 0A 00 00 00 53 89 75 F8 2E FF 15 70 05 48 00 85 C0 74 0A 31 C0 89 EC 5D 5E 5A 59 5B C3 8B 45 E8 89 EC 5D 5E 5A 59 5B C3 51 52 55 89 E5 83 EC 0C 8D 55 F4 52 68 00 01 00 00 68 0D 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 89 EC 5D 5A 59 C3 90 55 89 E5 5D C3 8D 40 00 53 51 56 55 89 E5 83 EC 20 88 D3 8D 75 EC 56 68 00 04 00 00 31 F6 68 0D 08 00 00 66 89 C6 BA 0A 00 00 00 56 89 55 F0 2E FF 15 70 05 48 00 85 C0 74 04 31 C0 EB 4E 88 D8 89 45 FC 8D 45 F8 50 6A 08 68 07 08 00 00 81 E3 FF 00 00 00 56 43 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5E 59 5B C3 8D 45 E0 50 6A 00 68 06 08 00 00 56 2E FF 15 70 05 48 00 85 C0 74 09 31 C0 89 EC 5D 5E 59 5B C3 89 D8 89 EC 5D 5E 59 5B C3 90 55 89 E5 31 C0 5D C3 90 53 51 52 56 57 55 89 E5 83 EC 20 89 C6 8D 45 F0 50 68 00 04 00 00 31 DB 68 0D 08 00 00 66 89 F3 BA 02 00 00 00 53 89 55 F4 2E FF 15 70 05 48 00 89 C7 85 C0 74 18 6A 00 6A 00 68 04 08 00 00 53 2E FF 15 70 05 48 00 89 F8 E9 EF 00 00 00 8D 45 E0 50 68 00 01 00 00 68 14 08 00 00 B9 03 00 00 00 53 89 4D E8 2E FF 15 70 05 48 00 89 C7 85 C0 74 1C 6A 00 6A 00 68 04 08 00 00 53 2E FF 15 70 05 48 00 89 F8 89 EC 5D 5F 5E 5A 59 5B C3 8B 45 E4 A3 0C 28 53 00 83 F8 14 7C 05 B8 14 00 00 00 BB 01 00 00 00 A3 0C 28 53 00 3B 1D 0C 28 53 00 0F 8F 85 00 00 00 C7 45 E8 02 00 00 00 8D 45 E0 50 68 10 01 00 00 31 C0 68 14 08 00 00 66 89 F0 50 89 5D EC 89 45 FC 2E FF 15 70 05 48 00 89 C7 85 C0 74 1F 6A 00 6A 00 68 04 08 00 00 8B 4D FC 51 2E FF 15 70 05 48 00 89 F8 89 EC 5D 5F 5E 5A 59 5B C3 8D 7B FF 8D 04 BD 00 00 00 00 29 F8 89 C7 8A 45 E4 88 87 D0 27 53 00 31 C0 66 8B 45 E4 C1 F8 08 88 87 D1 27 53 00 8B 45 E4 C1 E8 10 43 88 87 D2 27 53 00 E9 6F FF FF FF 31 C0 89 EC 5D 5F 5E 5A 59 5B C3 8B C0 55 89 E5 25 FF FF 00 00 E8 A3 FC FF FF 39 D0 76 07 B8 01 00 00 00 5D C3 31 C0 5D C3 51 52 55 89 E5 83 EC 10 C7 45 F8 04 00 00 00 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 25 FF FF 00 00 50 2E FF 15 70 05 48 00 85 C0 74 07 B8 04 00 00 00 EB 36 8B 4D F4 81 F9 12 02 00 00 75 0B B8 01 00 00 00 89 EC 5D 5A 59 C3 81 F9 0C 02 00 00 75 0B B8 02 00 00 00 89 EC 5D 5A 59 C3 81 F9 0D 02 00 00 75 05 B8 03 00 00 00 89 EC 5D 5A 59 C3'; New = 'E8 DB 00 00 00 A1 10 8E 48 00 6B C0 64 A3 D8 27 53 00 B8 02 00 00 00 E8 F4 00 00 00 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 31 C0 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 EB 56 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 A1 D0 27 53 00 85 C0 74 10 6A 00 6A 00 68 08 08 00 00 50 FF 15 70 05 48 00 31 C0 5A 59 C3 00 00 00 00 00 00 00 00 51 52 A1 D0 27 53 00 85 C0 74 17 6A 00 6A 00 68 04 08 00 00 50 FF 15 70 05 48 00 31 C0 A3 D0 27 53 00 5A 59 C3 00 00 00 00 00 00 00 00 00 00 00 51 52 56 57 55 89 E5 83 EC 14 89 C2 BE 0C 13 45 00 BF DC 27 53 00 B9 06 00 00 00 F3 A5 04 30 A2 EC 27 53 00 89 15 D4 27 53 00 31 C0 89 45 EC 89 45 F0 C7 45 F4 00 13 45 00 C7 45 F8 DC 27 53 00 89 45 FC 8D 45 EC 50 68 02 22 00 00 68 03 08 00 00 6A 00 FF 15 70 05 48 00 85 C0 75 1A 8B 45 F0 A3 D0 27 53 00 8B 0D D8 27 53 00 E8 80 00 00 00 A1 D0 27 53 00 EB 02 31 C0 89 EC 5D 5F 5E 5A 59 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 55 89 E5 83 EC 0C 31 D2 89 55 F4 89 55 F8 89 55 FC 8D 55 F4 52 6A 00 68 06 08 00 00 50 FF 15 70 05 48 00 89 EC 5D 5A 59 C3 00 00 00 00 00 6D 70 65 67 76 69 64 65 6F 00 00 00 65 78 70 5C 6D 75 73 69 63 5C 74 72 61 63 6B 30 3F 2E 6D 70 33 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 51 52 55 89 E5 83 EC 18 31 D2 89 55 E8 C7 45 EC 02 40 00 00 89 4D F0 89 55 F4 89 55 F8 89 55 FC 8D 55 E8 52 68 00 00 80 01 68 73 08 00 00 50 FF 15 70 05 48 00 89 EC 5D 5A 59 C3 00 00 00 00 00 51 52 55 89 E5 83 EC 10 A1 D0 27 53 00 85 C0 74 66 31 D2 89 55 F0 89 55 F4 C7 45 F8 04 00 00 00 89 55 FC 8D 55 F0 52 68 00 01 00 00 68 14 08 00 00 50 FF 15 70 05 48 00 85 C0 75 3B 81 7D F4 0D 02 00 00 75 2A 8B 15 D4 27 53 00 42 E8 4F FE FF FF 89 D0 E8 78 FE FF FF 85 C0 75 0E B8 02 00 00 00 E8 6A FE FF FF 85 C0 74 0D E8 F1 FE FF FF 31 C0 89 EC 5D 5A 59 C3 B8 04 00 00 00 EB F3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 31 C0 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 52 E8 F2 FB FF FF 0F B6 C2 E8 1A FC FF FF 85 C0 74 0B E8 A1 FC FF FF 0F B6 C2 40 5A C3 31 C0 5A C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 E9 5B FB FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' }
                    # set_volume method 0: aux CD-audio device walk -> store level*100, MCI_SETAUDIO volume on the open element (the rest zero)
                    @{ Offset = 0x51CD0; Old = '53 51 52 56 57 55 89 E5 83 EC 34 89 C7 2E FF 15 68 05 48 00 89 45 FC 31 F6 3B 75 FC 73 47 BB 30 00 00 00 8D 45 CC 31 D2 E8 AF 97 02 00 6A 30 8D 45 CC 50 56 2E FF 15 64 05 48 00 85 C0 75 23 66 83 7D F4 01 75 1C 8D 04 BD 00 00 00 00 29 F8 C1 E0 0B 89 C2 C1 E2 10 09 D0 50 56 2E FF 15 6C 05 48 00 46 EB B4 89 EC 5D 5F 5E 5A 59 5B C3'; New = '51 6B C8 64 89 0D D8 27 53 00 A1 D0 27 53 00 85 C0 74 05 E8 48 EA FF FF 59 C3 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00' }
                    # .reloc table: entry 3149 -> 3136: the absolute operand moved from page offset 0x149 to 0x136, entry follows it
                    @{ Offset = 0x9C072; Old = '49 31'; New = '36 31' }
                    # .reloc table: entry 3157 -> 313E: the absolute operand moved from page offset 0x157 to 0x13E, entry follows it
                    @{ Offset = 0x9C074; Old = '57 31'; New = '3E 31' }
                    # .reloc table: entry 3194 -> 31EB: the absolute operand moved from page offset 0x194 to 0x1EB, entry follows it
                    @{ Offset = 0x9C076; Old = '94 31'; New = 'EB 31' }
                    # .reloc table: entry 31AB -> 31FF: the absolute operand moved from page offset 0x1AB to 0x1FF, entry follows it
                    @{ Offset = 0x9C078; Old = 'AB 31'; New = 'FF 31' }
                    # .reloc table: entry 31CF -> 3213: the absolute operand moved from page offset 0x1CF to 0x213, entry follows it
                    @{ Offset = 0x9C07A; Old = 'CF 31'; New = '13 32' }
                    # .reloc table: entry 3204 -> 3227: the absolute operand moved from page offset 0x204 to 0x227, entry follows it
                    @{ Offset = 0x9C07C; Old = '04 32'; New = '27 32' }
                    # .reloc table: entry 3238 -> 322E: the absolute operand moved from page offset 0x238 to 0x22E, entry follows it
                    @{ Offset = 0x9C07E; Old = '38 32'; New = '2E 32' }
                    # .reloc table: entry 325C -> 324D: the absolute operand moved from page offset 0x25C to 0x24D, entry follows it
                    @{ Offset = 0x9C080; Old = '5C 32'; New = '4D 32' }
                    # .reloc table: entry 327C -> 3252: the absolute operand moved from page offset 0x27C to 0x252, entry follows it
                    @{ Offset = 0x9C082; Old = '7C 32'; New = '52 32' }
                    # .reloc table: entry 32C8 -> 3260: the absolute operand moved from page offset 0x2C8 to 0x260, entry follows it
                    @{ Offset = 0x9C084; Old = 'C8 32'; New = '60 32' }
                    # .reloc table: entry 32F7 -> 3266: the absolute operand moved from page offset 0x2F7 to 0x266, entry follows it
                    @{ Offset = 0x9C086; Old = 'F7 32'; New = '66 32' }
                    # .reloc table: entry 3347 -> 3275: the absolute operand moved from page offset 0x347 to 0x275, entry follows it
                    @{ Offset = 0x9C088; Old = '47 33'; New = '75 32' }
                    # .reloc table: entry 3369 -> 327C: the absolute operand moved from page offset 0x369 to 0x27C, entry follows it
                    @{ Offset = 0x9C08A; Old = '69 33'; New = '7C 32' }
                    # .reloc table: entry 33B4 -> 3295: the absolute operand moved from page offset 0x3B4 to 0x295, entry follows it
                    @{ Offset = 0x9C08C; Old = 'B4 33'; New = '95 32' }
                    # .reloc table: entry 33E0 -> 32A1: the absolute operand moved from page offset 0x3E0 to 0x2A1, entry follows it
                    @{ Offset = 0x9C08E; Old = 'E0 33'; New = 'A1 32' }
                    # .reloc table: entry 3426 -> 32A7: the absolute operand moved from page offset 0x426 to 0x2A7, entry follows it
                    @{ Offset = 0x9C090; Old = '26 34'; New = 'A7 32' }
                    # .reloc table: entry 3448 -> 32B1: the absolute operand moved from page offset 0x448 to 0x2B1, entry follows it
                    @{ Offset = 0x9C092; Old = '48 34'; New = 'B1 32' }
                    # .reloc table: entry 348E -> 32F1: the absolute operand moved from page offset 0x48E to 0x2F1, entry follows it
                    @{ Offset = 0x9C094; Old = '8E 34'; New = 'F1 32' }
                    # .reloc table: entry 34CA -> 3361: the absolute operand moved from page offset 0x4CA to 0x361, entry follows it
                    @{ Offset = 0x9C096; Old = 'CA 34'; New = '61 33' }
                    # .reloc table: entry 3508 -> 3379: the absolute operand moved from page offset 0x508 to 0x379, entry follows it
                    @{ Offset = 0x9C098; Old = '08 35'; New = '79 33' }
                    # .reloc table: entry 352E -> 33A4: the absolute operand moved from page offset 0x52E to 0x3A4, entry follows it
                    @{ Offset = 0x9C09A; Old = '2E 35'; New = 'A4 33' }
                    # .reloc table: entry 3575 -> 33B7: the absolute operand moved from page offset 0x575 to 0x3B7, entry follows it
                    @{ Offset = 0x9C09C; Old = '75 35'; New = 'B7 33' }
                    # .reloc table: entry 359B (type 3 HIGHLOW, page offset 0x59B) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C09E; Old = '9B 35'; New = '00 00' }
                    # .reloc table: entry 35C7 (type 3 HIGHLOW, page offset 0x5C7) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0A0; Old = 'C7 35'; New = '00 00' }
                    # .reloc table: entry 3603 (type 3 HIGHLOW, page offset 0x603) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0A2; Old = '03 36'; New = '00 00' }
                    # .reloc table: entry 3642 (type 3 HIGHLOW, page offset 0x642) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0A4; Old = '42 36'; New = '00 00' }
                    # .reloc table: entry 3669 (type 3 HIGHLOW, page offset 0x669) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0A6; Old = '69 36'; New = '00 00' }
                    # .reloc table: entry 3689 (type 3 HIGHLOW, page offset 0x689) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0A8; Old = '89 36'; New = '00 00' }
                    # .reloc table: entry 36D8 (type 3 HIGHLOW, page offset 0x6D8) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0AA; Old = 'D8 36'; New = '00 00' }
                    # .reloc table: entry 36EF (type 3 HIGHLOW, page offset 0x6EF) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0AC; Old = 'EF 36'; New = '00 00' }
                    # .reloc table: entry 3714 (type 3 HIGHLOW, page offset 0x714) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0AE; Old = '14 37'; New = '00 00' }
                    # .reloc table: entry 372B (type 3 HIGHLOW, page offset 0x72B) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0B0; Old = '2B 37'; New = '00 00' }
                    # .reloc table: entry 373E (type 3 HIGHLOW, page offset 0x73E) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0B2; Old = '3E 37'; New = '00 00' }
                    # .reloc table: entry 3752 (type 3 HIGHLOW, page offset 0x752) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0B4; Old = '52 37'; New = '00 00' }
                    # .reloc table: entry 3758 (type 3 HIGHLOW, page offset 0x758) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0B6; Old = '58 37'; New = '00 00' }
                    # .reloc table: entry 3786 (type 3 HIGHLOW, page offset 0x786) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0B8; Old = '86 37'; New = '00 00' }
                    # .reloc table: entry 37A0 (type 3 HIGHLOW, page offset 0x7A0) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0BA; Old = 'A0 37'; New = '00 00' }
                    # .reloc table: entry 37C2 (type 3 HIGHLOW, page offset 0x7C2) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0BC; Old = 'C2 37'; New = '00 00' }
                    # .reloc table: entry 37D1 (type 3 HIGHLOW, page offset 0x7D1) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0BE; Old = 'D1 37'; New = '00 00' }
                    # .reloc table: entry 37DE (type 3 HIGHLOW, page offset 0x7DE) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0C0; Old = 'DE 37'; New = '00 00' }
                    # .reloc table: entry 3836 (type 3 HIGHLOW, page offset 0x836) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C0C2; Old = '36 38'; New = '00 00' }
                    # .reloc table: entry 38E0 -> 38D6: the absolute operand moved from page offset 0x8E0 to 0x8D6, entry follows it
                    @{ Offset = 0x9C2F0; Old = 'E0 38'; New = 'D6 38' }
                    # .reloc table: entry 3907 -> 38DB: the absolute operand moved from page offset 0x907 to 0x8DB, entry follows it
                    @{ Offset = 0x9C2F2; Old = '07 39'; New = 'DB 38' }
                    # .reloc table: entry 392E (type 3 HIGHLOW, page offset 0x92E) -> 0000: the absolute operand it described no longer exists, entry becomes type 0 ABSOLUTE padding
                    @{ Offset = 0x9C2F4; Old = '2E 39'; New = '00 00' }
                )
            }

            # ---- ozi @ 640x480: OZI MISSIONS menu mode (Council Wars only) ---------------------------------------------------------
            #  Added      : 10 Sep 2026
            #  Made with  : tools/patch_ozi_menu.py
            #  Documented : docs/DC16_DISPLAY_AND_RESOLUTION.md section 10.13
            #  Changes    : 3296 bytes in 18 edits
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = '640x480'
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (385; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'ozi_ns\alta.gif'
                    'ozi_ns\alta.rgb'
                    'ozi_ns\alta.rmp'
                    'ozi_ns\area52.gif'
                    'ozi_ns\area52.rgb'
                    'ozi_ns\area52.rmp'
                    'ozi_ns\earth.gif'
                    'ozi_ns\gamestat\BOOMSTAT.TXT'
                    'ozi_ns\gamestat\gamestat.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\MBULLET.TXT'
                    'ozi_ns\gamestat\UNITID.TXT'
                    'ozi_ns\gamestat\WEAPSTAT.TXT'
                    'ozi_ns\gatlan.GIF'
                    'ozi_ns\gatlan.NCY'
                    'ozi_ns\gatlan.RGB'
                    'ozi_ns\gatlan.RMP'
                    'ozi_ns\gjungle.gif'
                    'ozi_ns\gjungle.rgb'
                    'ozi_ns\gJUNGLE.RMP'
                    'ozi_ns\intrf_hd\bintroe'
                    'ozi_ns\intrf_hd\gxscene.txt'
                    'ozi_ns\intrf_hd\hxscene.txt'
                    'ozi_ns\intrf_hd\introe'
                    'ozi_ns\intrf_hd\shumane'
                    'ozi_ns\intrface\astory.txt'
                    'ozi_ns\intrface\credits.txt'
                    'ozi_ns\intrface\hstory.txt'
                    'ozi_ns\jubjub.gif'
                    'ozi_ns\jubjub.rgb'
                    'ozi_ns\jubjub.rmp'
                    'ozi_ns\mission\g1.wav'
                    'ozi_ns\mission\g10.wav'
                    'ozi_ns\mission\g11.wav'
                    'ozi_ns\mission\g2.wav'
                    'ozi_ns\mission\g3.wav'
                    'ozi_ns\mission\g4.wav'
                    'ozi_ns\mission\g5.wav'
                    'ozi_ns\mission\g6.wav'
                    'ozi_ns\mission\g7.wav'
                    'ozi_ns\mission\g8.wav'
                    'ozi_ns\mission\g9.wav'
                    'ozi_ns\mission\h1.wav'
                    'ozi_ns\mission\h10.wav'
                    'ozi_ns\mission\h11.wav'
                    'ozi_ns\mission\h2.wav'
                    'ozi_ns\mission\h3.wav'
                    'ozi_ns\mission\h4.wav'
                    'ozi_ns\mission\h5.wav'
                    'ozi_ns\mission\h6.wav'
                    'ozi_ns\mission\h7.wav'
                    'ozi_ns\mission\h8.wav'
                    'ozi_ns\mission\h80.wav'
                    'ozi_ns\mission\h9.wav'
                    'ozi_ns\scenario\all.jus'
                    'ozi_ns\scenario\alta.bts'
                    'ozi_ns\scenario\area52.bts'
                    'ozi_ns\scenario\atlantis.bts'
                    'ozi_ns\scenario\council\scene.txt'
                    'ozi_ns\scenario\council\tarr01.001'
                    'ozi_ns\scenario\council\tarr01.002'
                    'ozi_ns\scenario\council\tarr01.003'
                    'ozi_ns\scenario\council\tarr01.004'
                    'ozi_ns\scenario\council\tarr01.map'
                    'ozi_ns\scenario\council\tarr01.msg'
                    'ozi_ns\scenario\council\tarr01.mtg'
                    'ozi_ns\scenario\council\tarr01.ovh'
                    'ozi_ns\scenario\council\tarr01.pop'
                    'ozi_ns\scenario\council\tarr01.pth'
                    'ozi_ns\scenario\council\tarr01.scn'
                    'ozi_ns\scenario\council\tarr01.tro'
                    'ozi_ns\scenario\council\tarr01.txt'
                    'ozi_ns\scenario\council\tarr02.001'
                    'ozi_ns\scenario\council\tarr02.002'
                    'ozi_ns\scenario\council\tarr02.map'
                    'ozi_ns\scenario\council\tarr02.msg'
                    'ozi_ns\scenario\council\tarr02.mtg'
                    'ozi_ns\scenario\council\tarr02.ovh'
                    'ozi_ns\scenario\council\tarr02.pop'
                    'ozi_ns\scenario\council\tarr02.pth'
                    'ozi_ns\scenario\council\tarr02.scn'
                    'ozi_ns\scenario\council\tarr02.tro'
                    'ozi_ns\scenario\council\tarr02.txt'
                    'ozi_ns\scenario\council\tarr03.001'
                    'ozi_ns\scenario\council\tarr03.002'
                    'ozi_ns\scenario\council\tarr03.map'
                    'ozi_ns\scenario\council\tarr03.msg'
                    'ozi_ns\scenario\council\tarr03.mtg'
                    'ozi_ns\scenario\council\tarr03.ovh'
                    'ozi_ns\scenario\council\tarr03.pop'
                    'ozi_ns\scenario\council\tarr03.pth'
                    'ozi_ns\scenario\council\tarr03.scn'
                    'ozi_ns\scenario\council\tarr03.tro'
                    'ozi_ns\scenario\council\tarr03.txt'
                    'ozi_ns\scenario\council\tarr04.001'
                    'ozi_ns\scenario\council\tarr04.002'
                    'ozi_ns\scenario\council\tarr04.map'
                    'ozi_ns\scenario\council\tarr04.msg'
                    'ozi_ns\scenario\council\tarr04.mtg'
                    'ozi_ns\scenario\council\tarr04.ovh'
                    'ozi_ns\scenario\council\tarr04.pop'
                    'ozi_ns\scenario\council\tarr04.pth'
                    'ozi_ns\scenario\council\tarr04.scn'
                    'ozi_ns\scenario\council\tarr04.tro'
                    'ozi_ns\scenario\council\tarr04.txt'
                    'ozi_ns\scenario\council\tarr05.001'
                    'ozi_ns\scenario\council\tarr05.002'
                    'ozi_ns\scenario\council\tarr05.map'
                    'ozi_ns\scenario\council\tarr05.msg'
                    'ozi_ns\scenario\council\tarr05.mtg'
                    'ozi_ns\scenario\council\tarr05.ovh'
                    'ozi_ns\scenario\council\tarr05.pop'
                    'ozi_ns\scenario\council\tarr05.pth'
                    'ozi_ns\scenario\council\tarr05.scn'
                    'ozi_ns\scenario\council\tarr05.tro'
                    'ozi_ns\scenario\council\tarr05.txt'
                    'ozi_ns\scenario\council\tarr06.001'
                    'ozi_ns\scenario\council\tarr06.002'
                    'ozi_ns\scenario\council\tarr06.003'
                    'ozi_ns\scenario\council\tarr06.map'
                    'ozi_ns\scenario\council\tarr06.msg'
                    'ozi_ns\scenario\council\tarr06.mtg'
                    'ozi_ns\scenario\council\tarr06.ovh'
                    'ozi_ns\scenario\council\tarr06.pop'
                    'ozi_ns\scenario\council\tarr06.pth'
                    'ozi_ns\scenario\council\tarr06.scn'
                    'ozi_ns\scenario\council\tarr06.tro'
                    'ozi_ns\scenario\council\tarr06.txt'
                    'ozi_ns\scenario\council\tarr07.001'
                    'ozi_ns\scenario\council\tarr07.002'
                    'ozi_ns\scenario\council\tarr07.003'
                    'ozi_ns\scenario\council\tarr07.004'
                    'ozi_ns\scenario\council\tarr07.map'
                    'ozi_ns\scenario\council\tarr07.msg'
                    'ozi_ns\scenario\council\tarr07.mtg'
                    'ozi_ns\scenario\council\tarr07.ovh'
                    'ozi_ns\scenario\council\tarr07.pop'
                    'ozi_ns\scenario\council\tarr07.pth'
                    'ozi_ns\scenario\council\tarr07.scn'
                    'ozi_ns\scenario\council\tarr07.tro'
                    'ozi_ns\scenario\council\tarr07.txt'
                    'ozi_ns\scenario\council\tarr08.001'
                    'ozi_ns\scenario\council\tarr08.002'
                    'ozi_ns\scenario\council\tarr08.003'
                    'ozi_ns\scenario\council\tarr08.004'
                    'ozi_ns\scenario\council\tarr08.map'
                    'ozi_ns\scenario\council\tarr08.msg'
                    'ozi_ns\scenario\council\tarr08.mtg'
                    'ozi_ns\scenario\council\tarr08.ovh'
                    'ozi_ns\scenario\council\tarr08.pop'
                    'ozi_ns\scenario\council\tarr08.pth'
                    'ozi_ns\scenario\council\tarr08.scn'
                    'ozi_ns\scenario\council\tarr08.tro'
                    'ozi_ns\scenario\council\tarr08.txt'
                    'ozi_ns\scenario\council\tarr09.001'
                    'ozi_ns\scenario\council\tarr09.002'
                    'ozi_ns\scenario\council\tarr09.003'
                    'ozi_ns\scenario\council\tarr09.map'
                    'ozi_ns\scenario\council\tarr09.msg'
                    'ozi_ns\scenario\council\tarr09.mtg'
                    'ozi_ns\scenario\council\tarr09.ovh'
                    'ozi_ns\scenario\council\tarr09.pop'
                    'ozi_ns\scenario\council\tarr09.pth'
                    'ozi_ns\scenario\council\tarr09.scn'
                    'ozi_ns\scenario\council\tarr09.tro'
                    'ozi_ns\scenario\council\tarr09.txt'
                    'ozi_ns\scenario\council\tarr10.001'
                    'ozi_ns\scenario\council\tarr10.002'
                    'ozi_ns\scenario\council\tarr10.003'
                    'ozi_ns\scenario\council\tarr10.004'
                    'ozi_ns\scenario\council\tarr10.map'
                    'ozi_ns\scenario\council\tarr10.MSG'
                    'ozi_ns\scenario\council\tarr10.mtg'
                    'ozi_ns\scenario\council\tarr10.ovh'
                    'ozi_ns\scenario\council\tarr10.pop'
                    'ozi_ns\scenario\council\tarr10.pth'
                    'ozi_ns\scenario\council\tarr10.scn'
                    'ozi_ns\scenario\council\tarr10.tro'
                    'ozi_ns\scenario\council\tarr10.TXT'
                    'ozi_ns\scenario\council\tarr11.001'
                    'ozi_ns\scenario\council\tarr11.002'
                    'ozi_ns\scenario\council\tarr11.map'
                    'ozi_ns\scenario\council\tarr11.msg'
                    'ozi_ns\scenario\council\tarr11.mtg'
                    'ozi_ns\scenario\council\tarr11.ovh'
                    'ozi_ns\scenario\council\tarr11.pop'
                    'ozi_ns\scenario\council\tarr11.pth'
                    'ozi_ns\scenario\council\tarr11.scn'
                    'ozi_ns\scenario\council\tarr11.tro'
                    'ozi_ns\scenario\council\tarr11.txt'
                    'ozi_ns\scenario\DESERT.BTS'
                    'ozi_ns\scenario\earth.bts'
                    'ozi_ns\scenario\gatlan.bts'
                    'ozi_ns\scenario\GJUNGLE.BTS'
                    'ozi_ns\scenario\globo\globo01.001'
                    'ozi_ns\scenario\globo\globo01.002'
                    'ozi_ns\scenario\globo\globo01.003'
                    'ozi_ns\scenario\globo\globo01.map'
                    'ozi_ns\scenario\globo\globo01.msg'
                    'ozi_ns\scenario\globo\globo01.mtg'
                    'ozi_ns\scenario\globo\globo01.ovh'
                    'ozi_ns\scenario\globo\globo01.pop'
                    'ozi_ns\scenario\globo\globo01.pth'
                    'ozi_ns\scenario\globo\globo01.scn'
                    'ozi_ns\scenario\globo\globo01.tro'
                    'ozi_ns\scenario\globo\globo01.txt'
                    'ozi_ns\scenario\globo\globo02.001'
                    'ozi_ns\scenario\globo\globo02.002'
                    'ozi_ns\scenario\globo\globo02.003'
                    'ozi_ns\scenario\globo\globo02.map'
                    'ozi_ns\scenario\globo\globo02.msg'
                    'ozi_ns\scenario\globo\globo02.mtg'
                    'ozi_ns\scenario\globo\globo02.ovh'
                    'ozi_ns\scenario\globo\globo02.pop'
                    'ozi_ns\scenario\globo\globo02.pth'
                    'ozi_ns\scenario\globo\globo02.scn'
                    'ozi_ns\scenario\globo\globo02.tro'
                    'ozi_ns\scenario\globo\globo02.txt'
                    'ozi_ns\scenario\globo\globo03.001'
                    'ozi_ns\scenario\globo\globo03.002'
                    'ozi_ns\scenario\globo\globo03.003'
                    'ozi_ns\scenario\globo\globo03.map'
                    'ozi_ns\scenario\globo\globo03.msg'
                    'ozi_ns\scenario\globo\globo03.mtg'
                    'ozi_ns\scenario\globo\globo03.ovh'
                    'ozi_ns\scenario\globo\globo03.pop'
                    'ozi_ns\scenario\globo\globo03.pth'
                    'ozi_ns\scenario\globo\globo03.scn'
                    'ozi_ns\scenario\globo\globo03.tro'
                    'ozi_ns\scenario\globo\globo03.txt'
                    'ozi_ns\scenario\globo\globo04.001'
                    'ozi_ns\scenario\globo\globo04.002'
                    'ozi_ns\scenario\globo\globo04.003'
                    'ozi_ns\scenario\globo\globo04.map'
                    'ozi_ns\scenario\globo\globo04.msg'
                    'ozi_ns\scenario\globo\globo04.mtg'
                    'ozi_ns\scenario\globo\globo04.ovh'
                    'ozi_ns\scenario\globo\globo04.pop'
                    'ozi_ns\scenario\globo\globo04.pth'
                    'ozi_ns\scenario\globo\globo04.scn'
                    'ozi_ns\scenario\globo\globo04.tro'
                    'ozi_ns\scenario\globo\globo04.txt'
                    'ozi_ns\scenario\globo\globo05.001'
                    'ozi_ns\scenario\globo\globo05.002'
                    'ozi_ns\scenario\globo\globo05.map'
                    'ozi_ns\scenario\globo\globo05.msg'
                    'ozi_ns\scenario\globo\globo05.mtg'
                    'ozi_ns\scenario\globo\globo05.ovh'
                    'ozi_ns\scenario\globo\globo05.pop'
                    'ozi_ns\scenario\globo\globo05.pth'
                    'ozi_ns\scenario\globo\globo05.scn'
                    'ozi_ns\scenario\globo\globo05.tro'
                    'ozi_ns\scenario\globo\globo05.txt'
                    'ozi_ns\scenario\globo\globo06.001'
                    'ozi_ns\scenario\globo\globo06.002'
                    'ozi_ns\scenario\globo\globo06.003'
                    'ozi_ns\scenario\globo\globo06.map'
                    'ozi_ns\scenario\globo\globo06.msg'
                    'ozi_ns\scenario\globo\globo06.mtg'
                    'ozi_ns\scenario\globo\globo06.ovh'
                    'ozi_ns\scenario\globo\globo06.pop'
                    'ozi_ns\scenario\globo\globo06.pth'
                    'ozi_ns\scenario\globo\globo06.scn'
                    'ozi_ns\scenario\globo\globo06.tro'
                    'ozi_ns\scenario\globo\globo06.txt'
                    'ozi_ns\scenario\globo\globo07.001'
                    'ozi_ns\scenario\globo\globo07.002'
                    'ozi_ns\scenario\globo\globo07.003'
                    'ozi_ns\scenario\globo\globo07.004'
                    'ozi_ns\scenario\globo\globo07.map'
                    'ozi_ns\scenario\globo\globo07.msg'
                    'ozi_ns\scenario\globo\globo07.mtg'
                    'ozi_ns\scenario\globo\globo07.ovh'
                    'ozi_ns\scenario\globo\globo07.pop'
                    'ozi_ns\scenario\globo\globo07.pth'
                    'ozi_ns\scenario\globo\globo07.scn'
                    'ozi_ns\scenario\globo\globo07.tro'
                    'ozi_ns\scenario\globo\globo07.txt'
                    'ozi_ns\scenario\globo\globo08.001'
                    'ozi_ns\scenario\globo\globo08.002'
                    'ozi_ns\scenario\globo\globo08.003'
                    'ozi_ns\scenario\globo\globo08.map'
                    'ozi_ns\scenario\globo\globo08.msg'
                    'ozi_ns\scenario\globo\globo08.mtg'
                    'ozi_ns\scenario\globo\globo08.ovh'
                    'ozi_ns\scenario\globo\globo08.pop'
                    'ozi_ns\scenario\globo\globo08.pth'
                    'ozi_ns\scenario\globo\globo08.scn'
                    'ozi_ns\scenario\globo\globo08.tro'
                    'ozi_ns\scenario\globo\globo08.txt'
                    'ozi_ns\scenario\globo\globo09.001'
                    'ozi_ns\scenario\globo\globo09.002'
                    'ozi_ns\scenario\globo\globo09.003'
                    'ozi_ns\scenario\globo\globo09.map'
                    'ozi_ns\scenario\globo\globo09.msg'
                    'ozi_ns\scenario\globo\globo09.mtg'
                    'ozi_ns\scenario\globo\globo09.ovh'
                    'ozi_ns\scenario\globo\globo09.pop'
                    'ozi_ns\scenario\globo\globo09.pth'
                    'ozi_ns\scenario\globo\globo09.scn'
                    'ozi_ns\scenario\globo\globo09.tro'
                    'ozi_ns\scenario\globo\globo09.txt'
                    'ozi_ns\scenario\globo\globo10.001'
                    'ozi_ns\scenario\globo\globo10.002'
                    'ozi_ns\scenario\globo\globo10.003'
                    'ozi_ns\scenario\globo\globo10.004'
                    'ozi_ns\scenario\globo\globo10.map'
                    'ozi_ns\scenario\globo\globo10.msg'
                    'ozi_ns\scenario\globo\globo10.mtg'
                    'ozi_ns\scenario\globo\globo10.ovh'
                    'ozi_ns\scenario\globo\globo10.pop'
                    'ozi_ns\scenario\globo\globo10.pth'
                    'ozi_ns\scenario\globo\globo10.scn'
                    'ozi_ns\scenario\globo\globo10.tro'
                    'ozi_ns\scenario\globo\globo10.txt'
                    'ozi_ns\scenario\globo\globo11.001'
                    'ozi_ns\scenario\globo\globo11.002'
                    'ozi_ns\scenario\globo\globo11.003'
                    'ozi_ns\scenario\globo\globo11.map'
                    'ozi_ns\scenario\globo\globo11.msg'
                    'ozi_ns\scenario\globo\globo11.mtg'
                    'ozi_ns\scenario\globo\globo11.ovh'
                    'ozi_ns\scenario\globo\globo11.pop'
                    'ozi_ns\scenario\globo\globo11.pth'
                    'ozi_ns\scenario\globo\globo11.scn'
                    'ozi_ns\scenario\globo\globo11.tro'
                    'ozi_ns\scenario\globo\globo11.txt'
                    'ozi_ns\scenario\globo\scene.txt'
                    'ozi_ns\scenario\HTRAIN.BTS'
                    'ozi_ns\scenario\jubjub.bts'
                    'ozi_ns\scenario\JUNGLE.BTS'
                    'ozi_ns\scenario\special.bts'
                    'ozi_ns\scenario\trainh.bts'
                    'ozi_ns\scenario\vent.jus'
                    'ozi_ns\sound\ALIST.DAT'
                    'ozi_ns\sound\alta.amb'
                    'ozi_ns\sound\area52.amb'
                    'ozi_ns\sound\ATLANTIS.AMB'
                    'ozi_ns\sound\ATLANTIS.DAT'
                    'ozi_ns\sound\ATRAIN.DAT'
                    'ozi_ns\sound\birds.wav'
                    'ozi_ns\sound\cobra.wav'
                    'ozi_ns\sound\cow.wav'
                    'ozi_ns\sound\cricket.wav'
                    'ozi_ns\sound\DALG1DEA.wav'
                    'ozi_ns\sound\DALG1SEL.wav'
                    'ozi_ns\sound\DALG2ACK.wav'
                    'ozi_ns\sound\DALG2SEL.wav'
                    'ozi_ns\sound\dog.wav'
                    'ozi_ns\sound\dog2.wav'
                    'ozi_ns\sound\earth.amb'
                    'ozi_ns\sound\frog.wav'
                    'ozi_ns\sound\frogs.wav'
                    'ozi_ns\sound\gatlan.AMB'
                    'ozi_ns\sound\gease.wav'
                    'ozi_ns\sound\GJUNGLE.AMB'
                    'ozi_ns\sound\GJUNGLE.DAT'
                    'ozi_ns\sound\jubjub.amb'
                    'ozi_ns\sound\KOMANDWE.wav'
                    'ozi_ns\sound\KOMANWEA.wav'
                    'ozi_ns\sound\mosq.wav'
                    'ozi_ns\sound\r2bird.wav'
                    'ozi_ns\sound\SCENESND.DAT'
                    'ozi_ns\sound\seagull.wav'
                    'ozi_ns\sound\slist.dat'
                    'ozi_ns\sound\turkey.wav'
                    'ozi_ns\sound\water.wav'
                    'ozi_ns\sound\wolf.wav'
                    'ozi_ns\special.gif'
                    'ozi_ns\special.rgb'
                    'ozi_ns\special.rmp'
                    'ozisave\ozisave.txt'
                    'exp\animozi.dat'
                    'exp\animate\dalg.fin'
                    'exp\animate\reae.fin'
                    'exp\animate\spyo.fin'
                    'exp\animate\tranozi.fin'
                    'exp\sprites\dalg.spr'
                    'exp\sprites\reae.spr'
                    'exp\sprites\spyo.spr'
                    'exp\sprites\tranozi.spr'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'exp\intrface\bintroe'
                )
                Edits = @(
                    # PE optional header: base-relocation directory size 0x93CC -> 0x93DC (+16)
                    @{ Offset = 0x124; Old = 'CC 93 00 00'; New = 'DC 93 00 00' }
                    # credits box y 230 -> 204 (640x480: room for the five-row OZI menu)
                    @{ Offset = 0x4299; Old = 'BB E6 00 00 00'; New = 'BB CC 00 00 00' }
                    # credits box height 100 -> 80 (640x480: room for the five-row OZI menu)
                    @{ Offset = 0x429E; Old = '6A 64'; New = '6A 50' }
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
                    # main menu script "intrface/bintro" -> "intrface/bintoz" (640x480: exp/intrface/bintoze = stock menu + OZI rows, written by the patcher)
                    @{ Offset = 0x7FE98; Old = '69 6E 74 72 66 61 63 65 2F 62 69 6E 74 72 6F 00'; New = '69 6E 74 72 66 61 63 65 2F 62 69 6E 74 6F 7A 00' }
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
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = 'hd'
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
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @('hdpaths')
                # data files this fix needs next to the exe (384; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                    'ozi_ns\alta.gif'
                    'ozi_ns\alta.rgb'
                    'ozi_ns\alta.rmp'
                    'ozi_ns\area52.gif'
                    'ozi_ns\area52.rgb'
                    'ozi_ns\area52.rmp'
                    'ozi_ns\earth.gif'
                    'ozi_ns\gamestat\BOOMSTAT.TXT'
                    'ozi_ns\gamestat\gamestat.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\MBULLET.TXT'
                    'ozi_ns\gamestat\UNITID.TXT'
                    'ozi_ns\gamestat\WEAPSTAT.TXT'
                    'ozi_ns\gatlan.GIF'
                    'ozi_ns\gatlan.NCY'
                    'ozi_ns\gatlan.RGB'
                    'ozi_ns\gatlan.RMP'
                    'ozi_ns\gjungle.gif'
                    'ozi_ns\gjungle.rgb'
                    'ozi_ns\gJUNGLE.RMP'
                    'ozi_ns\intrf_hd\bintroe'
                    'ozi_ns\intrf_hd\gxscene.txt'
                    'ozi_ns\intrf_hd\hxscene.txt'
                    'ozi_ns\intrf_hd\introe'
                    'ozi_ns\intrf_hd\shumane'
                    'ozi_ns\intrface\astory.txt'
                    'ozi_ns\intrface\credits.txt'
                    'ozi_ns\intrface\hstory.txt'
                    'ozi_ns\jubjub.gif'
                    'ozi_ns\jubjub.rgb'
                    'ozi_ns\jubjub.rmp'
                    'ozi_ns\mission\g1.wav'
                    'ozi_ns\mission\g10.wav'
                    'ozi_ns\mission\g11.wav'
                    'ozi_ns\mission\g2.wav'
                    'ozi_ns\mission\g3.wav'
                    'ozi_ns\mission\g4.wav'
                    'ozi_ns\mission\g5.wav'
                    'ozi_ns\mission\g6.wav'
                    'ozi_ns\mission\g7.wav'
                    'ozi_ns\mission\g8.wav'
                    'ozi_ns\mission\g9.wav'
                    'ozi_ns\mission\h1.wav'
                    'ozi_ns\mission\h10.wav'
                    'ozi_ns\mission\h11.wav'
                    'ozi_ns\mission\h2.wav'
                    'ozi_ns\mission\h3.wav'
                    'ozi_ns\mission\h4.wav'
                    'ozi_ns\mission\h5.wav'
                    'ozi_ns\mission\h6.wav'
                    'ozi_ns\mission\h7.wav'
                    'ozi_ns\mission\h8.wav'
                    'ozi_ns\mission\h80.wav'
                    'ozi_ns\mission\h9.wav'
                    'ozi_ns\scenario\all.jus'
                    'ozi_ns\scenario\alta.bts'
                    'ozi_ns\scenario\area52.bts'
                    'ozi_ns\scenario\atlantis.bts'
                    'ozi_ns\scenario\council\scene.txt'
                    'ozi_ns\scenario\council\tarr01.001'
                    'ozi_ns\scenario\council\tarr01.002'
                    'ozi_ns\scenario\council\tarr01.003'
                    'ozi_ns\scenario\council\tarr01.004'
                    'ozi_ns\scenario\council\tarr01.map'
                    'ozi_ns\scenario\council\tarr01.msg'
                    'ozi_ns\scenario\council\tarr01.mtg'
                    'ozi_ns\scenario\council\tarr01.ovh'
                    'ozi_ns\scenario\council\tarr01.pop'
                    'ozi_ns\scenario\council\tarr01.pth'
                    'ozi_ns\scenario\council\tarr01.scn'
                    'ozi_ns\scenario\council\tarr01.tro'
                    'ozi_ns\scenario\council\tarr01.txt'
                    'ozi_ns\scenario\council\tarr02.001'
                    'ozi_ns\scenario\council\tarr02.002'
                    'ozi_ns\scenario\council\tarr02.map'
                    'ozi_ns\scenario\council\tarr02.msg'
                    'ozi_ns\scenario\council\tarr02.mtg'
                    'ozi_ns\scenario\council\tarr02.ovh'
                    'ozi_ns\scenario\council\tarr02.pop'
                    'ozi_ns\scenario\council\tarr02.pth'
                    'ozi_ns\scenario\council\tarr02.scn'
                    'ozi_ns\scenario\council\tarr02.tro'
                    'ozi_ns\scenario\council\tarr02.txt'
                    'ozi_ns\scenario\council\tarr03.001'
                    'ozi_ns\scenario\council\tarr03.002'
                    'ozi_ns\scenario\council\tarr03.map'
                    'ozi_ns\scenario\council\tarr03.msg'
                    'ozi_ns\scenario\council\tarr03.mtg'
                    'ozi_ns\scenario\council\tarr03.ovh'
                    'ozi_ns\scenario\council\tarr03.pop'
                    'ozi_ns\scenario\council\tarr03.pth'
                    'ozi_ns\scenario\council\tarr03.scn'
                    'ozi_ns\scenario\council\tarr03.tro'
                    'ozi_ns\scenario\council\tarr03.txt'
                    'ozi_ns\scenario\council\tarr04.001'
                    'ozi_ns\scenario\council\tarr04.002'
                    'ozi_ns\scenario\council\tarr04.map'
                    'ozi_ns\scenario\council\tarr04.msg'
                    'ozi_ns\scenario\council\tarr04.mtg'
                    'ozi_ns\scenario\council\tarr04.ovh'
                    'ozi_ns\scenario\council\tarr04.pop'
                    'ozi_ns\scenario\council\tarr04.pth'
                    'ozi_ns\scenario\council\tarr04.scn'
                    'ozi_ns\scenario\council\tarr04.tro'
                    'ozi_ns\scenario\council\tarr04.txt'
                    'ozi_ns\scenario\council\tarr05.001'
                    'ozi_ns\scenario\council\tarr05.002'
                    'ozi_ns\scenario\council\tarr05.map'
                    'ozi_ns\scenario\council\tarr05.msg'
                    'ozi_ns\scenario\council\tarr05.mtg'
                    'ozi_ns\scenario\council\tarr05.ovh'
                    'ozi_ns\scenario\council\tarr05.pop'
                    'ozi_ns\scenario\council\tarr05.pth'
                    'ozi_ns\scenario\council\tarr05.scn'
                    'ozi_ns\scenario\council\tarr05.tro'
                    'ozi_ns\scenario\council\tarr05.txt'
                    'ozi_ns\scenario\council\tarr06.001'
                    'ozi_ns\scenario\council\tarr06.002'
                    'ozi_ns\scenario\council\tarr06.003'
                    'ozi_ns\scenario\council\tarr06.map'
                    'ozi_ns\scenario\council\tarr06.msg'
                    'ozi_ns\scenario\council\tarr06.mtg'
                    'ozi_ns\scenario\council\tarr06.ovh'
                    'ozi_ns\scenario\council\tarr06.pop'
                    'ozi_ns\scenario\council\tarr06.pth'
                    'ozi_ns\scenario\council\tarr06.scn'
                    'ozi_ns\scenario\council\tarr06.tro'
                    'ozi_ns\scenario\council\tarr06.txt'
                    'ozi_ns\scenario\council\tarr07.001'
                    'ozi_ns\scenario\council\tarr07.002'
                    'ozi_ns\scenario\council\tarr07.003'
                    'ozi_ns\scenario\council\tarr07.004'
                    'ozi_ns\scenario\council\tarr07.map'
                    'ozi_ns\scenario\council\tarr07.msg'
                    'ozi_ns\scenario\council\tarr07.mtg'
                    'ozi_ns\scenario\council\tarr07.ovh'
                    'ozi_ns\scenario\council\tarr07.pop'
                    'ozi_ns\scenario\council\tarr07.pth'
                    'ozi_ns\scenario\council\tarr07.scn'
                    'ozi_ns\scenario\council\tarr07.tro'
                    'ozi_ns\scenario\council\tarr07.txt'
                    'ozi_ns\scenario\council\tarr08.001'
                    'ozi_ns\scenario\council\tarr08.002'
                    'ozi_ns\scenario\council\tarr08.003'
                    'ozi_ns\scenario\council\tarr08.004'
                    'ozi_ns\scenario\council\tarr08.map'
                    'ozi_ns\scenario\council\tarr08.msg'
                    'ozi_ns\scenario\council\tarr08.mtg'
                    'ozi_ns\scenario\council\tarr08.ovh'
                    'ozi_ns\scenario\council\tarr08.pop'
                    'ozi_ns\scenario\council\tarr08.pth'
                    'ozi_ns\scenario\council\tarr08.scn'
                    'ozi_ns\scenario\council\tarr08.tro'
                    'ozi_ns\scenario\council\tarr08.txt'
                    'ozi_ns\scenario\council\tarr09.001'
                    'ozi_ns\scenario\council\tarr09.002'
                    'ozi_ns\scenario\council\tarr09.003'
                    'ozi_ns\scenario\council\tarr09.map'
                    'ozi_ns\scenario\council\tarr09.msg'
                    'ozi_ns\scenario\council\tarr09.mtg'
                    'ozi_ns\scenario\council\tarr09.ovh'
                    'ozi_ns\scenario\council\tarr09.pop'
                    'ozi_ns\scenario\council\tarr09.pth'
                    'ozi_ns\scenario\council\tarr09.scn'
                    'ozi_ns\scenario\council\tarr09.tro'
                    'ozi_ns\scenario\council\tarr09.txt'
                    'ozi_ns\scenario\council\tarr10.001'
                    'ozi_ns\scenario\council\tarr10.002'
                    'ozi_ns\scenario\council\tarr10.003'
                    'ozi_ns\scenario\council\tarr10.004'
                    'ozi_ns\scenario\council\tarr10.map'
                    'ozi_ns\scenario\council\tarr10.MSG'
                    'ozi_ns\scenario\council\tarr10.mtg'
                    'ozi_ns\scenario\council\tarr10.ovh'
                    'ozi_ns\scenario\council\tarr10.pop'
                    'ozi_ns\scenario\council\tarr10.pth'
                    'ozi_ns\scenario\council\tarr10.scn'
                    'ozi_ns\scenario\council\tarr10.tro'
                    'ozi_ns\scenario\council\tarr10.TXT'
                    'ozi_ns\scenario\council\tarr11.001'
                    'ozi_ns\scenario\council\tarr11.002'
                    'ozi_ns\scenario\council\tarr11.map'
                    'ozi_ns\scenario\council\tarr11.msg'
                    'ozi_ns\scenario\council\tarr11.mtg'
                    'ozi_ns\scenario\council\tarr11.ovh'
                    'ozi_ns\scenario\council\tarr11.pop'
                    'ozi_ns\scenario\council\tarr11.pth'
                    'ozi_ns\scenario\council\tarr11.scn'
                    'ozi_ns\scenario\council\tarr11.tro'
                    'ozi_ns\scenario\council\tarr11.txt'
                    'ozi_ns\scenario\DESERT.BTS'
                    'ozi_ns\scenario\earth.bts'
                    'ozi_ns\scenario\gatlan.bts'
                    'ozi_ns\scenario\GJUNGLE.BTS'
                    'ozi_ns\scenario\globo\globo01.001'
                    'ozi_ns\scenario\globo\globo01.002'
                    'ozi_ns\scenario\globo\globo01.003'
                    'ozi_ns\scenario\globo\globo01.map'
                    'ozi_ns\scenario\globo\globo01.msg'
                    'ozi_ns\scenario\globo\globo01.mtg'
                    'ozi_ns\scenario\globo\globo01.ovh'
                    'ozi_ns\scenario\globo\globo01.pop'
                    'ozi_ns\scenario\globo\globo01.pth'
                    'ozi_ns\scenario\globo\globo01.scn'
                    'ozi_ns\scenario\globo\globo01.tro'
                    'ozi_ns\scenario\globo\globo01.txt'
                    'ozi_ns\scenario\globo\globo02.001'
                    'ozi_ns\scenario\globo\globo02.002'
                    'ozi_ns\scenario\globo\globo02.003'
                    'ozi_ns\scenario\globo\globo02.map'
                    'ozi_ns\scenario\globo\globo02.msg'
                    'ozi_ns\scenario\globo\globo02.mtg'
                    'ozi_ns\scenario\globo\globo02.ovh'
                    'ozi_ns\scenario\globo\globo02.pop'
                    'ozi_ns\scenario\globo\globo02.pth'
                    'ozi_ns\scenario\globo\globo02.scn'
                    'ozi_ns\scenario\globo\globo02.tro'
                    'ozi_ns\scenario\globo\globo02.txt'
                    'ozi_ns\scenario\globo\globo03.001'
                    'ozi_ns\scenario\globo\globo03.002'
                    'ozi_ns\scenario\globo\globo03.003'
                    'ozi_ns\scenario\globo\globo03.map'
                    'ozi_ns\scenario\globo\globo03.msg'
                    'ozi_ns\scenario\globo\globo03.mtg'
                    'ozi_ns\scenario\globo\globo03.ovh'
                    'ozi_ns\scenario\globo\globo03.pop'
                    'ozi_ns\scenario\globo\globo03.pth'
                    'ozi_ns\scenario\globo\globo03.scn'
                    'ozi_ns\scenario\globo\globo03.tro'
                    'ozi_ns\scenario\globo\globo03.txt'
                    'ozi_ns\scenario\globo\globo04.001'
                    'ozi_ns\scenario\globo\globo04.002'
                    'ozi_ns\scenario\globo\globo04.003'
                    'ozi_ns\scenario\globo\globo04.map'
                    'ozi_ns\scenario\globo\globo04.msg'
                    'ozi_ns\scenario\globo\globo04.mtg'
                    'ozi_ns\scenario\globo\globo04.ovh'
                    'ozi_ns\scenario\globo\globo04.pop'
                    'ozi_ns\scenario\globo\globo04.pth'
                    'ozi_ns\scenario\globo\globo04.scn'
                    'ozi_ns\scenario\globo\globo04.tro'
                    'ozi_ns\scenario\globo\globo04.txt'
                    'ozi_ns\scenario\globo\globo05.001'
                    'ozi_ns\scenario\globo\globo05.002'
                    'ozi_ns\scenario\globo\globo05.map'
                    'ozi_ns\scenario\globo\globo05.msg'
                    'ozi_ns\scenario\globo\globo05.mtg'
                    'ozi_ns\scenario\globo\globo05.ovh'
                    'ozi_ns\scenario\globo\globo05.pop'
                    'ozi_ns\scenario\globo\globo05.pth'
                    'ozi_ns\scenario\globo\globo05.scn'
                    'ozi_ns\scenario\globo\globo05.tro'
                    'ozi_ns\scenario\globo\globo05.txt'
                    'ozi_ns\scenario\globo\globo06.001'
                    'ozi_ns\scenario\globo\globo06.002'
                    'ozi_ns\scenario\globo\globo06.003'
                    'ozi_ns\scenario\globo\globo06.map'
                    'ozi_ns\scenario\globo\globo06.msg'
                    'ozi_ns\scenario\globo\globo06.mtg'
                    'ozi_ns\scenario\globo\globo06.ovh'
                    'ozi_ns\scenario\globo\globo06.pop'
                    'ozi_ns\scenario\globo\globo06.pth'
                    'ozi_ns\scenario\globo\globo06.scn'
                    'ozi_ns\scenario\globo\globo06.tro'
                    'ozi_ns\scenario\globo\globo06.txt'
                    'ozi_ns\scenario\globo\globo07.001'
                    'ozi_ns\scenario\globo\globo07.002'
                    'ozi_ns\scenario\globo\globo07.003'
                    'ozi_ns\scenario\globo\globo07.004'
                    'ozi_ns\scenario\globo\globo07.map'
                    'ozi_ns\scenario\globo\globo07.msg'
                    'ozi_ns\scenario\globo\globo07.mtg'
                    'ozi_ns\scenario\globo\globo07.ovh'
                    'ozi_ns\scenario\globo\globo07.pop'
                    'ozi_ns\scenario\globo\globo07.pth'
                    'ozi_ns\scenario\globo\globo07.scn'
                    'ozi_ns\scenario\globo\globo07.tro'
                    'ozi_ns\scenario\globo\globo07.txt'
                    'ozi_ns\scenario\globo\globo08.001'
                    'ozi_ns\scenario\globo\globo08.002'
                    'ozi_ns\scenario\globo\globo08.003'
                    'ozi_ns\scenario\globo\globo08.map'
                    'ozi_ns\scenario\globo\globo08.msg'
                    'ozi_ns\scenario\globo\globo08.mtg'
                    'ozi_ns\scenario\globo\globo08.ovh'
                    'ozi_ns\scenario\globo\globo08.pop'
                    'ozi_ns\scenario\globo\globo08.pth'
                    'ozi_ns\scenario\globo\globo08.scn'
                    'ozi_ns\scenario\globo\globo08.tro'
                    'ozi_ns\scenario\globo\globo08.txt'
                    'ozi_ns\scenario\globo\globo09.001'
                    'ozi_ns\scenario\globo\globo09.002'
                    'ozi_ns\scenario\globo\globo09.003'
                    'ozi_ns\scenario\globo\globo09.map'
                    'ozi_ns\scenario\globo\globo09.msg'
                    'ozi_ns\scenario\globo\globo09.mtg'
                    'ozi_ns\scenario\globo\globo09.ovh'
                    'ozi_ns\scenario\globo\globo09.pop'
                    'ozi_ns\scenario\globo\globo09.pth'
                    'ozi_ns\scenario\globo\globo09.scn'
                    'ozi_ns\scenario\globo\globo09.tro'
                    'ozi_ns\scenario\globo\globo09.txt'
                    'ozi_ns\scenario\globo\globo10.001'
                    'ozi_ns\scenario\globo\globo10.002'
                    'ozi_ns\scenario\globo\globo10.003'
                    'ozi_ns\scenario\globo\globo10.004'
                    'ozi_ns\scenario\globo\globo10.map'
                    'ozi_ns\scenario\globo\globo10.msg'
                    'ozi_ns\scenario\globo\globo10.mtg'
                    'ozi_ns\scenario\globo\globo10.ovh'
                    'ozi_ns\scenario\globo\globo10.pop'
                    'ozi_ns\scenario\globo\globo10.pth'
                    'ozi_ns\scenario\globo\globo10.scn'
                    'ozi_ns\scenario\globo\globo10.tro'
                    'ozi_ns\scenario\globo\globo10.txt'
                    'ozi_ns\scenario\globo\globo11.001'
                    'ozi_ns\scenario\globo\globo11.002'
                    'ozi_ns\scenario\globo\globo11.003'
                    'ozi_ns\scenario\globo\globo11.map'
                    'ozi_ns\scenario\globo\globo11.msg'
                    'ozi_ns\scenario\globo\globo11.mtg'
                    'ozi_ns\scenario\globo\globo11.ovh'
                    'ozi_ns\scenario\globo\globo11.pop'
                    'ozi_ns\scenario\globo\globo11.pth'
                    'ozi_ns\scenario\globo\globo11.scn'
                    'ozi_ns\scenario\globo\globo11.tro'
                    'ozi_ns\scenario\globo\globo11.txt'
                    'ozi_ns\scenario\globo\scene.txt'
                    'ozi_ns\scenario\HTRAIN.BTS'
                    'ozi_ns\scenario\jubjub.bts'
                    'ozi_ns\scenario\JUNGLE.BTS'
                    'ozi_ns\scenario\special.bts'
                    'ozi_ns\scenario\trainh.bts'
                    'ozi_ns\scenario\vent.jus'
                    'ozi_ns\sound\ALIST.DAT'
                    'ozi_ns\sound\alta.amb'
                    'ozi_ns\sound\area52.amb'
                    'ozi_ns\sound\ATLANTIS.AMB'
                    'ozi_ns\sound\ATLANTIS.DAT'
                    'ozi_ns\sound\ATRAIN.DAT'
                    'ozi_ns\sound\birds.wav'
                    'ozi_ns\sound\cobra.wav'
                    'ozi_ns\sound\cow.wav'
                    'ozi_ns\sound\cricket.wav'
                    'ozi_ns\sound\DALG1DEA.wav'
                    'ozi_ns\sound\DALG1SEL.wav'
                    'ozi_ns\sound\DALG2ACK.wav'
                    'ozi_ns\sound\DALG2SEL.wav'
                    'ozi_ns\sound\dog.wav'
                    'ozi_ns\sound\dog2.wav'
                    'ozi_ns\sound\earth.amb'
                    'ozi_ns\sound\frog.wav'
                    'ozi_ns\sound\frogs.wav'
                    'ozi_ns\sound\gatlan.AMB'
                    'ozi_ns\sound\gease.wav'
                    'ozi_ns\sound\GJUNGLE.AMB'
                    'ozi_ns\sound\GJUNGLE.DAT'
                    'ozi_ns\sound\jubjub.amb'
                    'ozi_ns\sound\KOMANDWE.wav'
                    'ozi_ns\sound\KOMANWEA.wav'
                    'ozi_ns\sound\mosq.wav'
                    'ozi_ns\sound\r2bird.wav'
                    'ozi_ns\sound\SCENESND.DAT'
                    'ozi_ns\sound\seagull.wav'
                    'ozi_ns\sound\slist.dat'
                    'ozi_ns\sound\turkey.wav'
                    'ozi_ns\sound\water.wav'
                    'ozi_ns\sound\wolf.wav'
                    'ozi_ns\special.gif'
                    'ozi_ns\special.rgb'
                    'ozi_ns\special.rmp'
                    'ozisave\ozisave.txt'
                    'exp\animozi.dat'
                    'exp\animate\dalg.fin'
                    'exp\animate\reae.fin'
                    'exp\animate\spyo.fin'
                    'exp\animate\tranozi.fin'
                    'exp\sprites\dalg.spr'
                    'exp\sprites\reae.spr'
                    'exp\sprites\spyo.spr'
                    'exp\sprites\tranozi.spr'
                    'ozi_ns\gamestat\hxscene.txt'
                    'ozi_ns\gamestat\gxscene.txt'
                )
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
    # ---------------------------------------------------------------------------------------------
    #  Dark Colony map editor maped.exe (Aug 1997, Borland C++), 336424 bytes (unlocked build: maped_ozi_ns_v1.2.exe)
    # ---------------------------------------------------------------------------------------------
    @{
        Id             = 'MapEditor'
        Title          = 'Dark Colony map editor maped.exe (Aug 1997, Borland C++), 336424 bytes (unlocked build: maped_ozi_ns_v1.2.exe)'
        OriginalName   = 'maped.exe'
        OutputName     = 'maped_ozi_ns_v1.2.exe'
        Size           = 336424
        OriginalSha256 = 'e8471a0adcade0d0562f0e38ddbc85ebbd0776f50cc7429628dee435fa6a8f7e'   # untouched original
        PatchedSha256  = '1edc261af23a88c78a0ef784b75d52e0e3f85831b7e36f336f1ee9949d5ac767'   # every patch applied in the default resolution = the exe in the repository
        # screen resolutions this build can be patched for: '640x480' = the stock size (no display fixes),
        # the others select the per-resolution variants of the 'resolution' and 'clock' fixes below
        Modes          = @()
        DefaultMode    = ''
        # SHA-256 with every fix of that resolution applied (the default one is the published exe)
        ReferenceSha256 = @{ '' = '1edc261af23a88c78a0ef784b75d52e0e3f85831b7e36f336f1ee9949d5ac767' }
        Patches        = @(

            # ---- blocksets: New Map: Atlantis, Training and Special block sets selectable ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_maped.py --fix blocksets
            #  Documented : CLAUDE.md "Map editor notes" (Dark-Colony-development)
            #  Changes    : 3 bytes in 3 edits
            #  The original editor greys out three of the five block-set buttons of the New Map dialog: Atlantis,
            #  Training Set and Special Set (the WS_DISABLED style bit, 0x08000000, is set in the dialog template).
            #  The code behind them is complete - the dialog's command table routes the three buttons to block sets
            #  2, 3 and 4 (atlantis.bts, htrain.bts, special.bts) exactly like Desert and Jungle - so this fix only
            #  clears that bit: one byte per button, in the DIALOG resource, no code changes.  This is what the
            #  "ozi_ns" editor did (together with a Polish translation and a renamed title, which stay out here).
            #
            #  The editor loads the block set's palette window from scenario\<set>.set and its tiles from
            #  <set>.bts.  The game itself ships only desert and jungle; atlantis.set, trainh.set, special.set and
            #  special.bts come with the ozi_ns mission pack.  Without them the editor answers "Can't open file" when
            #  one of the three buttons is pressed - nothing worse.
            @{
                Id = 'blocksets'; Name = 'New Map: Atlantis, Training and Special block sets selectable'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_maped.py --fix blocksets'; Doc = 'CLAUDE.md "Map editor notes" (Dark-Colony-development)'
                Description = @'
The original editor greys out three of the five block-set buttons of the New Map dialog: Atlantis,
Training Set and Special Set (the WS_DISABLED style bit, 0x08000000, is set in the dialog template).
The code behind them is complete - the dialog's command table routes the three buttons to block sets
2, 3 and 4 (atlantis.bts, htrain.bts, special.bts) exactly like Desert and Jungle - so this fix only
clears that bit: one byte per button, in the DIALOG resource, no code changes.  This is what the
"ozi_ns" editor did (together with a Polish translation and a renamed title, which stay out here).

The editor loads the block set's palette window from scenario\<set>.set and its tiles from
<set>.bts.  The game itself ships only desert and jungle; atlantis.set, trainh.set, special.set and
special.bts come with the ozi_ns mission pack.  Without them the editor answers "Can't open file" when
one of the three buttons is pressed - nothing worse.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # DIALOG MAPSIZE control id 16 "Atlantis": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3131F; Old = '58'; New = '50' }
                    # DIALOG MAPSIZE control id 21 "Training Set": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x313F7; Old = '58'; New = '50' }
                    # DIALOG MAPSIZE control id 22 "Special Set": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3142B; Old = '58'; New = '50' }
                )
            }

            # ---- teams: Team Attributes: Team Colour and Allies selectable ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_maped.py --fix teams
            #  Documented : CLAUDE.md "Map editor notes" (Dark-Colony-development)
            #  Changes    : 18 bytes in 18 edits
            #  The Team Attributes dialog ships with its Team Colour group (eight radio buttons) and its Allies group
            #  (eight radio buttons) greyed out.  The dialog procedure reads both groups and writes them to the
            #  scenario (%TeamColour, %TeamAllies) - the code was always there.  This fix clears WS_DISABLED on the
            #  sixteen radio buttons and the two group boxes: 18 single-byte edits in the DIALOG resource.  The
            #  AI Slots group of the same dialog stays disabled, as in every version of the editor.
            @{
                Id = 'teams'; Name = 'Team Attributes: Team Colour and Allies selectable'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_maped.py --fix teams'; Doc = 'CLAUDE.md "Map editor notes" (Dark-Colony-development)'
                Description = @'
The Team Attributes dialog ships with its Team Colour group (eight radio buttons) and its Allies group
(eight radio buttons) greyed out.  The dialog procedure reads both groups and writes them to the
scenario (%TeamColour, %TeamAllies) - the code was always there.  This fix clears WS_DISABLED on the
sixteen radio buttons and the two group boxes: 18 single-byte edits in the DIALOG resource.  The
AI Slots group of the same dialog stays disabled, as in every version of the editor.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # DIALOG RACE control id 108 "0 Red": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x315A3; Old = '58'; New = '50' }
                    # DIALOG RACE control id 109 "1 Blue": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x315C7; Old = '58'; New = '50' }
                    # DIALOG RACE control id 110 "2 Yellow": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x315EF; Old = '58'; New = '50' }
                    # DIALOG RACE control id 111 "3 Purple": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3161B; Old = '58'; New = '50' }
                    # DIALOG RACE control id 112 "4 Green": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x31647; Old = '58'; New = '50' }
                    # DIALOG RACE control id 113 "5 Orange": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3166F; Old = '58'; New = '50' }
                    # DIALOG RACE control id 114 "6 Flesh": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3169B; Old = '58'; New = '50' }
                    # DIALOG RACE control id 115 "7 Teal": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x316C3; Old = '58'; New = '50' }
                    # DIALOG RACE control id 116 "Team Colour": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x316EB; Old = '58'; New = '50' }
                    # DIALOG RACE control id 117 "0 Red": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3171B; Old = '58'; New = '50' }
                    # DIALOG RACE control id 118 "1 Blue": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3173F; Old = '58'; New = '50' }
                    # DIALOG RACE control id 119 "2 Yellow": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x31767; Old = '58'; New = '50' }
                    # DIALOG RACE control id 120 "3 Purple": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x31793; Old = '58'; New = '50' }
                    # DIALOG RACE control id 121 "4 Green": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x317BF; Old = '58'; New = '50' }
                    # DIALOG RACE control id 122 "5 Orange": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x317E7; Old = '58'; New = '50' }
                    # DIALOG RACE control id 123 "6 Flesh": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x31813; Old = '58'; New = '50' }
                    # DIALOG RACE control id 124 "7 Teal": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3183B; Old = '58'; New = '50' }
                    # DIALOG RACE control id 125 "Allies": style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x31863; Old = '58'; New = '50' }
                )
            }

            # ---- healer: Troop Attributes: Healer row usable ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_maped.py --fix healer
            #  Documented : CLAUDE.md "Map editor notes" (Dark-Colony-development)
            #  Changes    : 2 bytes in 2 edits
            #  In the Troop Attributes dialog the Healer row - its select radio button and its hit-points edit - is
            #  greyed out, although the dialog procedure reads the edit like those of the other units and the game
            #  knows the healing units (GAMESTAT.TXT rows 49 and 50).  Two single-byte edits clear WS_DISABLED.
            @{
                Id = 'healer'; Name = 'Troop Attributes: Healer row usable'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_maped.py --fix healer'; Doc = 'CLAUDE.md "Map editor notes" (Dark-Colony-development)'
                Description = @'
In the Troop Attributes dialog the Healer row - its select radio button and its hit-points edit - is
greyed out, although the dialog procedure reads the edit like those of the other units and the game
knows the healing units (GAMESTAT.TXT rows 49 and 50).  Two single-byte edits clear WS_DISABLED.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # DIALOG TROOPS control id 678 (no text): style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x3323B; Old = '58'; New = '50' }
                    # DIALOG TROOPS control id 508 (no text): style byte 3, WS_DISABLED (0x08000000) cleared - the control is usable
                    @{ Offset = 0x33257; Old = '58'; New = '50' }
                )
            }

            # ---- troopsframe: Troop Attributes: close box instead of sizing border ---------------------------------------------------------
            #  Added      : 15 Sep 2026
            #  Made with  : tools/patch_maped.py --fix troopsframe
            #  Documented : CLAUDE.md "Map editor notes" (Dark-Colony-development)
            #  Changes    : 1 bytes in 1 edits
            #  Cosmetic, taken over from the ozi_ns editor: the Troop Attributes dialog's frame style changes from
            #  WS_THICKFRAME (a sizing border, useless for a fixed layout) to WS_SYSMENU (a title-bar close box).
            #  One byte in the DIALOG template's style dword.
            @{
                Id = 'troopsframe'; Name = 'Troop Attributes: close box instead of sizing border'; Date = '15 Sep 2026'
                # $null = part of every resolution, 'hd' = every resolution but 640x480, 'WxH' = that one only
                Mode = $null
                Tool = 'tools/patch_maped.py --fix troopsframe'; Doc = 'CLAUDE.md "Map editor notes" (Dark-Colony-development)'
                Description = @'
Cosmetic, taken over from the ozi_ns editor: the Troop Attributes dialog's frame style changes from
WS_THICKFRAME (a sizing border, useless for a fixed layout) to WS_SYSMENU (a title-bar close box).
One byte in the DIALOG template's style dword.
'@
                # fixes that must be applied together with this one (the exe would not work otherwise)
                Requires = @()
                # data files this fix needs next to the exe (0; listed from the repository when this
                # script was generated) - the patcher refuses to write when any of them is missing
                Data = @(
                )
                Edits = @(
                    # DIALOG TROOPS template style byte 2: WS_THICKFRAME (0x00040000) -> WS_SYSMENU (0x00080000), sizing border -> close box
                    @{ Offset = 0x3290A; Old = 'C4'; New = 'C8' }
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
            $why = if ($state -eq 'new') { 'already patched - this file already carries the fix' } else { 'not the documented original bytes' }
            throw ("fix '{0}': the bytes at file offset {1} are {2}. The fixes apply to the untouched original exe of the repository " +
                   "(dc16.exe / ENGEXP16.EXE in 'DC - Council wars', maped.exe in the editor folder), not to an already patched build.") -f $Patch.Id, $where, $why
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

# --- screen resolutions (21 Sep 2026) -------------------------------------------------------------
function Get-ModeSize([string] $Mode) { $p = $Mode -split 'x'; return @([int]$p[0], [int]$p[1]) }
function Get-Gcd([int] $a, [int] $b) { while ($b) { $t = $a % $b; $a = $b; $b = $t }; return $a }

# "4:3", "5:4", "16:9", "16:10" - 8:5 is what everyone calls 16:10, and 1366x768 counts as 16:9
function Get-AspectLabel([int] $W, [int] $H) {
    if ($W -le 0 -or $H -le 0) { return '?' }
    $g = Get-Gcd $W $H; $a = [int]($W / $g); $b = [int]($H / $g)
    if ($a -eq 8 -and $b -eq 5) { return '16:10' }
    if ([math]::Abs($W / $H - 16 / 9) -lt 0.01) { return '16:9' }
    return ('{0}:{1}' -f $a, $b)
}

# The PRIMARY monitor's size.  First choice: the Windows Forms screen list, whose Primary flag is
# explicit; Windows PowerShell 5.1 sees the bounds DPI-scaled (1280x800 for a 1920x1200 panel at
# 150 %), but the aspect ratio survives the scaling, and the ratio is all the "recommended" mark
# needs.  Fallback: the video controller's mode (WMI), which is exact but names ONE mode per adapter -
# with two monitors on one adapter it can be the other monitor's (maintainer's laptop 21 Sep 2026:
# primary 1920x1080 external, controller reported the 1920x1200 panel).
function Get-MonitorSize {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        if ($b.Width -gt 0 -and $b.Height -gt 0) { return @([int]$b.Width, [int]$b.Height) }
    } catch {}
    try {
        $vc = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.CurrentHorizontalResolution -gt 0 })
        if ($vc.Count -gt 0) { return @([int]$vc[0].CurrentHorizontalResolution, [int]$vc[0].CurrentVerticalResolution) }
    } catch {}
    return $null
}

# "1280x800 (16:10) recommended for your screen" - recommended = the aspect ratio of the monitor this runs on
function Test-ModeRecommended([string] $Mode, $MonitorSize) {
    $wh = Get-ModeSize $Mode
    return [bool] ($MonitorSize -and (Get-AspectLabel $MonitorSize[0] $MonitorSize[1]) -eq (Get-AspectLabel $wh[0] $wh[1]))
}
function Format-ModeLabel([string] $Mode, $MonitorSize) {
    $wh = Get-ModeSize $Mode
    $label = '{0} ({1})' -f $Mode, (Get-AspectLabel $wh[0] $wh[1])
    if (Test-ModeRecommended $Mode $MonitorSize) { $label += ' recommended for your screen' }
    return $label
}
# The window's initial choice: the largest resolution with the monitor's aspect ratio, else the build's
# default (the published exe).  The command line keeps the build's default, so `-All` without
# -Resolution reproduces the published exe on every PC.
function Get-PreferredMode($Build, $MonitorSize) {
    $pick = $Build.DefaultMode
    foreach ($m in @($Build.Modes)) { if (Test-ModeRecommended $m $MonitorSize) { $pick = $m } }
    return $pick
}

# The fixes of a build for one resolution.  Mode $null = part of every resolution, 'hd' = every
# resolution but 640x480, 'WxH' = that resolution's variant of the fix (640x480 has its own variants of
# movies and ozi).
function Get-BuildPatches($Build, [string] $Mode) {
    $out = @()
    foreach ($p in $Build.Patches) {
        $m = $p.Mode
        if (-not $m) { $out += $p; continue }                                   # every resolution
        if ($Mode -and $m -eq $Mode) { $out += $p; continue }                  # this resolution's own variant (also 640x480)
        if ($m -eq 'hd' -and $Mode -and $Mode -ne '640x480') { $out += $p }    # the shared HD variant
    }
    return $out      # callers wrap it in @(); an empty list comes back as an empty array
}

# The resolution to use for a build: validated -Resolution, else the build's default; '' for a build
# without resolutions (the map editor).
function Resolve-Mode($Build, [string] $Mode) {
    $modes = @($Build.Modes)
    if ($modes.Count -eq 0) { return '' }
    if (-not $Mode) { return $Build.DefaultMode }
    if ($modes -notcontains $Mode) { throw ("unknown resolution '{0}' for {1}; valid: {2}" -f $Mode, $Build.Id, ($modes -join ', ')) }
    return $Mode
}

function Find-BuildBySha([string] $Sha) { foreach ($b in $Builds) { if ($b.OriginalSha256 -eq $Sha) { return $b } }; return $null }

# Guess the build of an arbitrary exe from its size and the state of the first patch's edits (nocd).
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
    else { foreach ($k in @($b.ReferenceSha256.Keys)) { if ($k -and $b.ReferenceSha256[$k] -eq $sha) { $lines += ('= every fix applied for {0} (the reference build of the generator, not the published exe).' -f $k) } } }
    $lines += ''
    # a fix with per-resolution variants (resolution, clock) is reported once, with the variant found
    $seen = @()
    foreach ($p in $b.Patches) {
        if ($seen -contains $p.Id) { continue }
        $seen += $p.Id
        $variants = @($b.Patches | Where-Object { $_.Id -eq $p.Id })
        $applied = @(); $untouched = 0; $mixed = 'MIXED'
        foreach ($v in $variants) {
            $old = 0; $new = 0; $other = 0
            foreach ($e in $v.Edits) { switch (Get-EditState $data $e) { 'old' { $old++ } 'new' { $new++ } default { $other++ } } }
            $total = $old + $new + $other
            if ($new -eq $total) { $applied += $v } elseif ($old -eq $total) { $untouched++ } else { $mixed = "MIXED ($new applied, $old original, $other unknown)" }
        }
        if ($applied.Count -gt 0) {
            $verdict = 'APPLIED'; if ($applied[0].Mode -and $applied[0].Mode -ne 'hd') { $verdict += ' (' + $applied[0].Mode + ')' }
            $name = $applied[0].Name
        } elseif ($untouched -eq $variants.Count) { $verdict = 'not applied'; $name = $p.Name }
        else { $verdict = $mixed; $name = $p.Name }
        $lines += ('  {0,-12} {1,-22} {2}' -f $p.Id, $verdict, $name)
    }
    return $lines
}

# Width and height of an 8-bit BMP from its BITMAPINFOHEADER, or $null.
function Get-BmpSize([string] $Path) {
    try {
        $fs = [System.IO.File]::OpenRead($Path); $h = New-Object byte[] 26; $n = $fs.Read($h, 0, 26); $fs.Dispose()
        if ($n -lt 26 -or $h[0] -ne 0x42 -or $h[1] -ne 0x4D) { return $null }
        return @([BitConverter]::ToInt32($h, 18), [Math]::Abs([BitConverter]::ToInt32($h, 22)))
    } catch { return $null }
}

# The loading screens driver.c shows through LoadImageA(..., W, H) + a full-screen BitBlt (doc 10.2):
# the 640x480 stock picture must sit centred on a black WxH canvas, or LoadImage stretches it.  They
# are not shipped per resolution (two uncompressed megabytes of mostly black); this writes
# INTRF_HD\LOAD.BMP and LOAD2.BMP from INTRFACE\LOAD.BMP / LOAD2.BMP for the chosen size, unless the
# ones in place already have that size.  Same bytes as tools/pad_background.py (Pillow's BMP writer:
# the source's palette size kept - 256 entries for LOAD.BMP, 255 for LOAD2.BMP - as BGRX, biClrUsed =
# biClrImportant = that count, 96 dpi, rows bottom-up), checked byte for byte against its output.
# Returns text lines about what was written.
function Write-LoadingScreens([string] $GameDir, [string] $Mode) {
    $lines = @()
    $wh = Get-ModeSize $Mode; $W = $wh[0]; $H = $wh[1]
    foreach ($name in 'LOAD.BMP', 'LOAD2.BMP') {
        $src = Join-Path $GameDir ('INTRFACE\' + $name)
        $dst = Join-Path $GameDir ('INTRF_HD\' + $name)
        $have = if (Test-Path -LiteralPath $dst) { Get-BmpSize $dst } else { $null }
        if ($have -and $have[0] -eq $W -and $have[1] -eq $H) { continue }
        if (-not (Test-Path -LiteralPath $src)) {
            # only reachable with -IgnoreMissingData (the stock pair is in the fix's Data list)
            $lines += ('INTRF_HD\{0} NOT written: the stock INTRFACE\{0} is not in this folder' -f $name)
            continue
        }
        $s = [System.IO.File]::ReadAllBytes($src)
        $off = [BitConverter]::ToInt32($s, 10); $sw = [BitConverter]::ToInt32($s, 18); $sh = [BitConverter]::ToInt32($s, 22)
        $bpp = [BitConverter]::ToUInt16($s, 28); $ncol = [BitConverter]::ToInt32($s, 46); if ($ncol -eq 0) { $ncol = 256 }
        if ($bpp -ne 8 -or $sh -le 0 -or $sw -gt $W -or $sh -gt $H) { throw "INTRFACE\$name is not an 8-bit ${sw}x${sh} bitmap that fits ${W}x${H}" }
        # palette: the source's entries as BGRX (the border is the first black entry)
        $palBytes = $ncol * 4; $hdr = 54 + $palBytes
        $pal = New-Object byte[] $palBytes
        [Array]::Copy($s, 54, $pal, 0, [Math]::Min($palBytes, $off - 54))
        for ($i = 0; $i -lt $palBytes; $i += 4) { $pal[$i + 3] = 0 }
        $pad = -1
        for ($i = 0; $i -lt $ncol; $i++) { if ($pal[4*$i] -eq 0 -and $pal[4*$i+1] -eq 0 -and $pal[4*$i+2] -eq 0) { $pad = $i; break } }
        if ($pad -lt 0) { throw "INTRFACE\$name has no black palette entry to pad with" }
        $srcStride = ($sw + 3) -band -bnot 3; $dstStride = ($W + 3) -band -bnot 3
        $out = New-Object byte[] ($hdr + $dstStride * $H)
        # BITMAPFILEHEADER + BITMAPINFOHEADER as Pillow writes them
        $out[0] = 0x42; $out[1] = 0x4D
        [Array]::Copy([BitConverter]::GetBytes([int]$out.Length), 0, $out, 2, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$hdr), 0, $out, 10, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]40), 0, $out, 14, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$W), 0, $out, 18, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$H), 0, $out, 22, 4)
        $out[26] = 1; $out[28] = 8
        [Array]::Copy([BitConverter]::GetBytes([int]($dstStride * $H)), 0, $out, 34, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]3780), 0, $out, 38, 4)     # 96 dpi
        [Array]::Copy([BitConverter]::GetBytes([int]3780), 0, $out, 42, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$ncol), 0, $out, 46, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$ncol), 0, $out, 50, 4)
        [Array]::Copy($pal, 0, $out, 54, $palBytes)
        if ($pad -ne 0) { for ($i = $hdr; $i -lt $out.Length; $i++) { $out[$i] = [byte]$pad } }
        # rows are stored bottom-up in both files: source row r lands on canvas row r + (H-sh)/2
        $x0 = [int](($W - $sw) / 2); $y0 = [int](($H - $sh) / 2)
        for ($r = 0; $r -lt $sh; $r++) {
            [Array]::Copy($s, $off + $r * $srcStride, $out, $hdr + ($r + $y0) * $dstStride + $x0, $sw)
        }
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        [System.IO.File]::WriteAllBytes($dst, $out)
        $lines += ('wrote INTRF_HD\{0} ({1}x{2}, from INTRFACE\{0}{3})' -f $name, $W, $H, $(if ($have) { ', replacing a ' + $have[0] + 'x' + $have[1] + ' one' } else { '' }))
    }
    return $lines
}

# =================================================================================================
#  INTERFACE SET - the INTRF_HD files for the chosen resolution, generated from the stock game files
#
#  Until 21 Sep 2026 the resolution-dependent interface files (INTRF_HD\, exp\intrf_hd\,
#  ozi_ns\intrf_hd\) were built by the maintainer's Python tools and shipped as one set per size.
#  Since then this script builds them itself when an HD display fix is applied, from files every
#  game folder has: the stock 640x480 scripts, pictures and briefing lists in INTRFACE\, GAMESTAT\,
#  exp\intrface, exp\gamestat and ozi_ns\gamestat.  The rules are the Python tools' rules
#  (pad_background.py, paint_intro.py, hud_layout.py, split_hd_data.py, build_ozi_overlay.py,
#  patch_movies.py), reproduced here line by line; the output is byte-identical for every text
#  file and pixel-identical for every picture, checked against the tools' output for all sizes.
#
#  Three pictures per size cannot be derived and ship with the game: INTRF_HD\<WxH>\INTRG.GIF and
#  INTRO.GIF (the procedurally painted main-menu planet) and INTRFACE.GIF (the HUD frame).
#
#  ---- A NOTE ON THE COMPILED CODE BELOW ------------------------------------------------------------
#  The 15 menu backgrounds are GIF files.  The game's loader (gifload.c) insists that the picture is
#  exactly the size of the screen, so each 640x480 picture has to be decoded, centred on a black
#  WIDTHxHEIGHT canvas and encoded again (LZW).  That inner loop runs over some 30 million pixels per
#  set.  This script therefore carries the small C# source text of a GIF reader/writer
#  ($GifCodecSource, about 250 lines, plain to read) and hands it to Add-Type, which compiles it in
#  memory when the set is built:
#    * Windows PowerShell 5.1 uses csc.exe from the .NET Framework that is part of Windows
#      (C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe); PowerShell 7 uses the Roslyn
#      compiler it ships with.  No Visual Studio, SDK or download is needed; the compile takes ~2 s,
#      the codec then needs about a second for a whole set.  Nothing is written to disk by the
#      compile and nothing is installed.
#    * Alternatives without compilation: (a) the same codec in plain PowerShell - measured at about
#      15-30 s per set under Windows PowerShell 5.1 and several minutes under PowerShell 7 (a loop
#      over 30 million pixels); (b) the pre-built sets from the maintainer, copied into INTRF_HD by
#      hand.  If Add-Type is not allowed on your PC (Constrained Language Mode, AppLocker), this
#      script says so and points to (b); the exe itself is still written.
# =================================================================================================
$GifCodecSource = @'
using System;
using System.Collections.Generic;
using System.IO;

// DcGif: read one GIF (87a/89a, global or local colour table, interlaced or not, extension blocks
// skipped), centre it on a black canvas of another size, write it back as a plain GIF the game's
// loader accepts: header, 256-entry global colour table, one image descriptor at (0,0) filling the
// screen, no extension blocks, no interlace, LZW with an 8-bit minimum code size.  The LZW output
// is byte-identical to Pillow's (same clear-code and code-width rules), checked on all 15 backgrounds.
public static class DcGif
{
    public class Image
    {
        public int Width, Height;
        public byte[] Palette;      // 768 bytes RGB
        public byte[] Pixels;       // Width*Height palette indices
        public string Version;      // "GIF87a" / "GIF89a"
    }

    public static Image Decode(byte[] d)
    {
        if (d.Length < 13 || d[0] != (byte)'G' || d[1] != (byte)'I' || d[2] != (byte)'F') throw new Exception("not a GIF");
        Image im = new Image();
        im.Version = System.Text.Encoding.ASCII.GetString(d, 0, 6);
        int flags = d[10];
        int pos = 13;
        byte[] palette = new byte[768];
        if ((flags & 0x80) != 0)
        {
            int n = 2 << (flags & 7);
            Array.Copy(d, pos, palette, 0, Math.Min(768, n * 3));
            pos += n * 3;
        }
        while (pos < d.Length)
        {
            byte b = d[pos++];
            if (b == 0x3B) break;
            if (b == 0x21)
            {   // extension: label, then data sub-blocks up to a zero-length one
                pos++;
                while (pos < d.Length) { int len = d[pos++]; if (len == 0) break; pos += len; }
                continue;
            }
            if (b != 0x2C) throw new Exception("unexpected block 0x" + b.ToString("X2"));
            int iw = d[pos + 4] | (d[pos + 5] << 8), ih = d[pos + 6] | (d[pos + 7] << 8);
            int iflags = d[pos + 8];
            pos += 9;
            if ((iflags & 0x80) != 0)
            {
                int n = 2 << (iflags & 7);
                palette = new byte[768];
                Array.Copy(d, pos, palette, 0, Math.Min(768, n * 3));
                pos += n * 3;
            }
            int minCode = d[pos++];
            // gather the sub-blocks
            MemoryStream ms = new MemoryStream();
            while (pos < d.Length) { int len = d[pos++]; if (len == 0) break; ms.Write(d, pos, len); pos += len; }
            byte[] pixels = LzwDecode(ms.ToArray(), minCode, iw * ih);
            if ((iflags & 0x40) != 0) pixels = Deinterlace(pixels, iw, ih);
            im.Width = iw; im.Height = ih; im.Palette = palette; im.Pixels = pixels;
            return im;
        }
        throw new Exception("no image in GIF");
    }

    static byte[] Deinterlace(byte[] src, int w, int h)
    {
        byte[] dst = new byte[src.Length];
        int row = 0;
        int[] starts = { 0, 4, 2, 1 }; int[] steps = { 8, 8, 4, 2 };
        for (int pass = 0; pass < 4; pass++)
            for (int y = starts[pass]; y < h; y += steps[pass])
            { Array.Copy(src, row * w, dst, y * w, w); row++; }
        return dst;
    }

    static byte[] LzwDecode(byte[] data, int minCode, int count)
    {
        byte[] outp = new byte[count];
        int outPos = 0;
        int clear = 1 << minCode, eoi = clear + 1;
        int[] prefix = new int[4096]; byte[] suffix = new byte[4096]; int[] length = new int[4096];
        for (int i = 0; i < clear; i++) { prefix[i] = -1; suffix[i] = (byte)i; length[i] = 1; }
        int codeSize = minCode + 1, next = clear + 2, prev = -1;
        int bitBuf = 0, bitCnt = 0, pos = 0;
        byte[] stack = new byte[4097];
        while (true)
        {
            while (bitCnt < codeSize && pos < data.Length) { bitBuf |= data[pos++] << bitCnt; bitCnt += 8; }
            if (bitCnt < codeSize) break;
            int code = bitBuf & ((1 << codeSize) - 1);
            bitBuf >>= codeSize; bitCnt -= codeSize;
            if (code == clear) { codeSize = minCode + 1; next = clear + 2; prev = -1; continue; }
            if (code == eoi) break;
            int emit = code, firstOfEmit;
            if (code >= next)
            {   // KwKwK case: the code being defined; its string is prev's string + prev's first byte
                if (prev < 0) throw new Exception("bad LZW code");
                int n = length[prev];
                int p = prev;
                for (int i = n - 1; i >= 0; i--) { stack[i] = suffix[p]; p = prefix[p]; }
                firstOfEmit = stack[0];
                stack[n] = (byte)firstOfEmit;
                int total = n + 1;
                if (outPos + total > count) total = count - outPos;
                Array.Copy(stack, 0, outp, outPos, total); outPos += total;
            }
            else
            {
                int n = length[emit];
                int p = emit;
                for (int i = n - 1; i >= 0; i--) { stack[i] = suffix[p]; p = prefix[p]; }
                firstOfEmit = stack[0];
                int total = n;
                if (outPos + total > count) total = count - outPos;
                Array.Copy(stack, 0, outp, outPos, total); outPos += total;
            }
            if (prev >= 0 && next < 4096)
            {
                prefix[next] = prev; suffix[next] = (byte)firstOfEmit; length[next] = length[prev] + 1; next++;
                if (next == (1 << codeSize) && codeSize < 12) codeSize++;
            }
            prev = code;
            if (outPos >= count) break;
        }
        return outp;
    }

    // Encode pixels as a plain GIF: 256-entry global colour table, one full-screen image, LZW-8.
    public static byte[] Encode(string version, int w, int h, byte[] palette, byte[] pixels)
    {
        MemoryStream ms = new MemoryStream();
        BinaryWriter bw = new BinaryWriter(ms);
        bw.Write(System.Text.Encoding.ASCII.GetBytes(version.Length == 6 ? version : "GIF87a"));
        bw.Write((ushort)w); bw.Write((ushort)h);
        bw.Write((byte)0x87);            // global colour table, 256 entries
        bw.Write((byte)0); bw.Write((byte)0);
        byte[] pal = new byte[768]; Array.Copy(palette, 0, pal, 0, Math.Min(768, palette.Length));
        bw.Write(pal);
        bw.Write((byte)0x2C); bw.Write((ushort)0); bw.Write((ushort)0); bw.Write((ushort)w); bw.Write((ushort)h); bw.Write((byte)0);
        bw.Write((byte)8);
        byte[] lzw = LzwEncode(pixels, 8);
        for (int p = 0; p < lzw.Length; p += 255)
        {
            int n = Math.Min(255, lzw.Length - p);
            bw.Write((byte)n); bw.Write(lzw, p, n);
        }
        bw.Write((byte)0); bw.Write((byte)0x3B);
        bw.Flush();
        return ms.ToArray();
    }

    static byte[] LzwEncode(byte[] pixels, int minCode)
    {
        int clear = 1 << minCode, eoi = clear + 1;
        MemoryStream ms = new MemoryStream();
        int bitBuf = 0, bitCnt = 0;
        int codeSize = minCode + 1, next = clear + 2;
        // dictionary: (prefix code, byte) -> code, as a flat table indexed prefix*256+byte
        int[] table = new int[4096 * 256];
        for (int i = 0; i < table.Length; i++) table[i] = -1;
        Action<int> put = delegate (int code)
        {
            bitBuf |= code << bitCnt; bitCnt += codeSize;
            while (bitCnt >= 8) { ms.WriteByte((byte)(bitBuf & 0xFF)); bitBuf >>= 8; bitCnt -= 8; }
        };
        put(clear);
        if (pixels.Length == 0) { put(eoi); }
        else
        {
            int cur = pixels[0];
            for (int i = 1; i < pixels.Length; i++)
            {
                int k = pixels[i];
                int idx = cur * 256 + k;
                if (table[idx] >= 0) { cur = table[idx]; continue; }
                put(cur);
                if (next < 4096)
                {
                    table[idx] = next++;
                    if (next > (1 << codeSize) && codeSize < 12) codeSize++;
                }
                else
                {
                    put(clear);
                    for (int t = 0; t < table.Length; t++) table[t] = -1;
                    codeSize = minCode + 1; next = clear + 2;
                }
                cur = k;
            }
            put(cur);
            put(eoi);
        }
        if (bitCnt > 0) ms.WriteByte((byte)(bitBuf & 0xFF));
        return ms.ToArray();
    }

    // pad_background.pad_gif: the picture centred on a canvas of the first black palette entry.
    public static byte[] Pad(byte[] src, int W, int H)
    {
        Image im = Decode(src);
        if (im.Width > W || im.Height > H) throw new Exception("picture " + im.Width + "x" + im.Height + " does not fit " + W + "x" + H);
        int pad = -1;
        for (int i = 0; i < 256; i++) if (im.Palette[i * 3] == 0 && im.Palette[i * 3 + 1] == 0 && im.Palette[i * 3 + 2] == 0) { pad = i; break; }
        if (pad < 0) throw new Exception("no black palette entry to pad with");
        byte[] canvas = new byte[W * H];
        if (pad != 0) for (int i = 0; i < canvas.Length; i++) canvas[i] = (byte)pad;
        int x0 = (W - im.Width) / 2, y0 = (H - im.Height) / 2;
        for (int y = 0; y < im.Height; y++) Array.Copy(im.Pixels, y * im.Width, canvas, (y + y0) * W + x0, im.Width);
        // always GIF87a: Pillow writes 87a whenever no 89a feature (extension block) is used, whatever
        // the source said, and the game accepts both - so the output stays byte-identical to the
        // tools' sets (VICTORY.GIF is the one GIF89a source; found 21 Sep 2026 as a 1-byte git diff)
        return Encode("GIF87a", W, H, im.Palette, canvas);
    }

    // width and height from the logical screen descriptor
    public static int[] Size(byte[] d) { return new int[] { d[6] | (d[7] << 8), d[8] | (d[9] << 8) }; }
}
'@

$script:gifCodecReady = $false
function Initialize-GifCodec {
    if ($script:gifCodecReady) { return }
    try {
        if (-not ('DcGif' -as [type])) { Add-Type -TypeDefinition $GifCodecSource -ErrorAction Stop }
        $script:gifCodecReady = $true
    } catch {
        throw ("the GIF reader/writer could not be compiled (Add-Type): {0}`r`n" +
               "The exe was written, but the INTRF_HD interface set for this resolution was not. Either allow Add-Type " +
               "(it compiles the C# text in this file with the .NET compiler that ships with Windows) or copy a pre-built " +
               "set from the maintainer into INTRF_HD.") -f $_.Exception.Message
    }
}

# --- the text rules of the Python tools, on Latin-1 strings (one char per byte, so nothing is lost) ---
$script:latin1 = [System.Text.Encoding]::GetEncoding(28591)
function Read-Latin1([string] $Path) { return $script:latin1.GetString([System.IO.File]::ReadAllBytes($Path)) }
function Write-Latin1([string] $Path, [string] $Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($Path, $script:latin1.GetBytes($Text))
}
function Find-CI([string] $Folder, [string] $Name) {     # case-insensitive file lookup, $null if absent
    if (-not (Test-Path -LiteralPath $Folder)) { return $null }
    foreach ($f in [System.IO.Directory]::GetFiles($Folder)) { if ([System.IO.Path]::GetFileName($f) -ieq $Name) { return $f } }
    return $null
}

$SIZE2 = [regex] '(?m)^([ \t]*)size([ \t]+)(\d+)([ \t]+)(\d+)([ \t]*\r?)$'
$SIZE4 = [regex] '(?m)^([ \t]*)size([ \t]+)(\d+)[ \t]+(\d+)[ \t]+(\d+)[ \t]+(\d+)([ \t]*\r?)$'
$BACKGROUND = [regex] '(?im)^[ \t]*background[ \t]+(?:intrface/|intrf_hd/)?(\S+)'
$BG_RETARGET = [regex] '(?im)^([ \t]*background[ \t]+)intrface/(\S+)'
$FRAME_XY = [regex] '^([ \t]*)(\d+)([ \t]+)(\d+)([ \t]+)(\d+)([ \t]*\r?)$'
$TOKENS = [regex] '\S+|[ \t]+'
$POSITIONED = @('pushb', 'checkb', 'in_text', 'picture', 'list', 'scroll', 'gadget', 'label', 'count', 'scount')   # pad_background / paint_intro
$HUD_KINDS = @('pushb', 'checkb', 'in_text', 'picture', 'list', 'scroll', 'gadget', 'count', 'scount')            # hud_layout (no label)

# Rewrites the 4th and 5th field (x, y) of every positioned widget line through $Move (a script block
# taking the words and returning @(x, y) or $null to leave the line) and returns the joined text.
# Lines are split at LF and keep their own CR, as the Python tools do.
function Edit-Widgets([string] $Text, [scriptblock] $Move, [string[]] $Kinds) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $Text.Split("`n")) {
        $i = $ln.IndexOf('%')
        $body = if ($i -ge 0) { $ln.Substring(0, $i) } else { $ln }
        $rest = if ($i -ge 0) { $ln.Substring($i) } else { '' }
        $toks = @($TOKENS.Matches($body) | ForEach-Object { $_.Value })
        $words = @($toks | Where-Object { $_.Trim().Length -gt 0 })
        if ($words.Count -gt 0 -and $Kinds -contains $words[0].ToLower()) {
            $xy = & $Move $words
            if ($xy) {
                $n = 0
                for ($t = 0; $t -lt $toks.Count; $t++) {
                    if ($toks[$t].Trim().Length -eq 0) { continue }
                    $n++
                    if ($n -eq 4 -and $xy[0] -ne $null) { $toks[$t] = [string][int]$xy[0] }
                    elseif ($n -eq 5) { if ($xy[1] -ne $null) { $toks[$t] = [string][int]$xy[1] }; break }
                }
                $body = -join $toks
            }
        }
        $out.Add($body + $rest)
    }
    return ($out -join "`n")
}

# pad_background.edit_script: widgets +(dx,dy) where the fields are plain numbers; size -> rect.
# (The $move blocks below are plain script blocks: PowerShell's dynamic scoping lets them read the
# caller's $dx/$dy/$W/$H and call this script's functions; a GetNewClosure() block could not.)
function Edit-PaddedScript([string] $Text, [int] $dx, [int] $dy, [int[]] $Rect) {
    $move = { param($fields) if ($fields.Count -lt 5) { return $null }
              $x = if ($fields[3] -match '^\d+$') { [int]$fields[3] + $dx } else { $null }
              $y = if ($fields[4] -match '^\d+$') { [int]$fields[4] + $dy } else { $null }
              return @($x, $y) }
    $t = Edit-Widgets $Text $move $POSITIONED
    $m = $SIZE2.Match($t); $tail = 6
    if (-not $m.Success) { $m = $SIZE4.Match($t); $tail = 7 }
    if ($m.Success) {
        $new = '{0}size{1}{2} {3} {4} {5}{6}' -f $m.Groups[1].Value, $m.Groups[2].Value, $Rect[0], $Rect[1], $Rect[2], $Rect[3], $m.Groups[$tail].Value
        $t = $t.Substring(0, $m.Index) + $new + $t.Substring($m.Index + $m.Length)
    }
    return $t
}

# paint_intro._positioned: kind n desc x y [w h] rest, with n/desc/x/y integers
function Get-Positioned([string[]] $w) {
    if ($w.Count -lt 5 -or $POSITIONED -notcontains $w[0].ToLower()) { return $null }
    for ($i = 1; $i -le 4; $i++) { if ($w[$i] -notmatch '^-?\d+$') { return $null } }
    $ww = 0; $hh = 0; $rest = @()
    if ($w.Count -ge 7 -and $w[5] -match '^\d+$' -and $w[6] -match '^\d+$') { $ww = [int]$w[5]; $hh = [int]$w[6]; if ($w.Count -gt 7) { $rest = $w[7..($w.Count-1)] } }
    elseif ($w.Count -gt 5) { $rest = $w[5..($w.Count-1)] }
    return @{ kind = $w[0].ToLower(); n = [int]$w[1]; x = [int]$w[3]; y = [int]$w[4]; w = $ww; h = $hh; rest = @($rest) }
}
$LOGOS = @('DCSS', 'DCUK'); $BUTTON_SPRITES = @('LARGEBUTTON', 'MEDBUTTON'); $LOGO_CLEARANCE = 20
function Test-Logo($p)  { return ($p.kind -eq 'gadget' -and $p.rest.Count -gt 0 -and $LOGOS -contains $p.rest[0]) }
function Test-Title($p) { return ($p.kind -eq 'gadget' -and $p.rest.Count -gt 0 -and ($BUTTON_SPRITES + $LOGOS) -notcontains $p.rest[0]) }

# paint_intro.layout_for + relayout: the title/credits/button cluster keeps its stock vertical centre
# as a fraction of the height, the button grid is centred horizontally, logo and title centred each.
function Edit-IntroScript([string] $Text, [int] $W, [int] $H) {
    $widgets = @()
    foreach ($ln in $Text.Split("`n")) {
        $i = $ln.IndexOf('%'); $body = if ($i -ge 0) { $ln.Substring(0, $i) } else { $ln }
        $p = Get-Positioned @($body -split '\s+' | Where-Object { $_ })
        if ($p) { $widgets += $p }
    }
    $cluster = @($widgets | Where-Object { -not (Test-Logo $_) })
    if ($cluster.Count -eq 0) { throw 'intro script: no widgets besides the logo' }
    $y0 = ($cluster | ForEach-Object { $_.y } | Measure-Object -Minimum).Minimum
    $y1 = ($cluster | ForEach-Object { $_.y + $_.h } | Measure-Object -Maximum).Maximum
    $dy = [int][Math]::Round(($y0 + $y1) / 2 * ($H / 480 - 1), [System.MidpointRounding]::ToEven)
    if (@($widgets | Where-Object { Test-Logo $_ }).Count -gt 0) { $dy += $LOGO_CLEARANCE }
    $grid = @($cluster | Where-Object { -not (Test-Title $_) })
    $x0 = ($grid | ForEach-Object { $_.x } | Measure-Object -Minimum).Minimum
    $x1 = ($grid | ForEach-Object { $_.x + $_.w } | Measure-Object -Maximum).Maximum
    $dx = [int][Math]::Round($W / 2 - ($x0 + $x1) / 2, [System.MidpointRounding]::ToEven)
    $move = { param($fields) $p = Get-Positioned $fields; if (-not $p) { return $null }   # not $w: it would shadow the width $W
              if ((Test-Logo $p) -or (Test-Title $p)) { return @([int](($W - $p.w) / 2), ($p.y + $dy)) }
              return @(($p.x + $dx), ($p.y + $dy)) }
    $t = Edit-Widgets $Text $move $POSITIONED
    $m = $SIZE2.Match($t); if (-not $m.Success) { $m = $SIZE4.Match($t) }
    if (-not $m.Success) { throw 'intro script: no size line' }
    $lead = ([regex] '^[ \t]*').Match($m.Value).Value
    return $t.Substring(0, $m.Index) + $lead + ('size {0} {1}' -f $W, $H) + $t.Substring($m.Index + $m.Length)
}

# hud_layout.cmd_maine: right-panel widgets slide right (and down with the panel's bottom cluster),
# bottom-bar furniture slides down (and right from the message box's end), the one in-view widget
# (PAUSED) by half the growth; size -> W H
function Edit-HudScript([string] $Text, [int] $W, [int] $H) {
    $dx = $W - 640; $dy = $H - 480
    $move = { param($fields) if ($fields.Count -lt 5 -or $fields[3] -notmatch '^\d+$' -or $fields[4] -notmatch '^\d+$') { return $null }
              $x = [int]$fields[3]; $y = [int]$fields[4]
              if ($x -ge 516) { $nx = $x + $dx; $ny = if ($y -ge 399) { $y + $dy } else { $y } }
              elseif ($y -ge 420) { $nx = if ($x -ge 300) { $x + $dx } else { $x }; $ny = $y + $dy }
              else { $nx = $x + [int][Math]::Floor($dx / 2); $ny = $y + [int][Math]::Floor($dy / 2) }
              if ($nx -eq $x -and $ny -eq $y) { return $null }
              return @($nx, $ny) }
    $t = Edit-Widgets $Text $move $HUD_KINDS
    $m = $SIZE2.Match($t)
    if ($m.Success) { $t = $t.Substring(0, $m.Index) + ('{0}size{1}{2} {3}{4}' -f $m.Groups[1].Value, $m.Groups[2].Value, $W, $H, $m.Groups[6].Value) + $t.Substring($m.Index + $m.Length) }
    return $t
}

# pad_background.edit_scene / build_ozi_overlay.shift_scene_markers: the `frame x y` line after an .avi line
function Edit-SceneList([string] $Text, [int] $dx, [int] $dy) {
    $out = New-Object System.Collections.Generic.List[string]
    $prevAvi = $false
    foreach ($ln in $Text.Split("`n")) {
        $m = $FRAME_XY.Match($ln)
        if ($m.Success -and $prevAvi) {
            $ln = '{0}{1}{2}{3}{4}{5}{6}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, ([int]$m.Groups[4].Value + $dx), $m.Groups[5].Value, ([int]$m.Groups[6].Value + $dy), $m.Groups[7].Value
        }
        $prevAvi = $ln.Trim().ToLower().EndsWith('.avi')
        $out.Add($ln)
    }
    return ($out -join "`n")
}

# split_hd_data: `background intrface/<gif>` -> `intrf_hd/<gif>` (every background of a generated script moved)
function Set-BackgroundHd([string] $Text) { return $BG_RETARGET.Replace($Text, '$1intrf_hd/$2') }

# split_hd_data.rename_dat_list: the per-screen FIN lists name the re-baked logo banks
function Edit-DatList([string] $Text) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $Text.Split("`n")) {
        $cr = if ($raw.EndsWith("`r")) { "`r" } else { '' }
        $line = if ($cr) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        if (@('dcss.fin', 'dcuk.fin', 'dcut.fin') -contains $line.Trim().ToLower()) { $line = $line.Trim().Substring(0, $line.Trim().Length - 4) + '_hd.fin' }
        $out.Add($line + $cr)
    }
    return ($out -join "`n")
}

# build_ozi_overlay.menu_layout (23 Sep 2026, maintainer's order): the patched Council Wars menu has
# five rows, the second column only on rows 1, 3 and 5.  The numbers are the exe's button ids, which
# pick the handler (patch_ozi_menu.py rewires 16 and 4 to the pack), so only positions and labels move:
#
#     ACADEMY       (1)   MULTI PLAYER WAR (3)
#     COUNCIL WARS  (0)
#     LOAD CW GAME  (2)   ENCYCLOPEDIA     (5)
#     OZI MISSIONS (16)
#     LOAD OZI GAME (4)   QUIT            (12)
#
# with a gap of about a quarter button height (6 px) after rows 1 and 3, which separates ACADEMY, the
# two Council Wars entries and the two pack entries.  The block is anchored on the BOTTOM row of the
# grid in the script - the one row that must not move, since the 640x480 backdrop's artwork starts 3 px
# below it - so applying this twice changes nothing.  The two gaps and the fifth row are won at the top,
# out of the credits box: it moves up and gets 20 rows shorter (patch_resolution's credits_y(204, 296)
# plus that build's height site at HD sizes, patch_ozi_menu's two 640x480 sites at the stock size).
# The untouched exe keeps Classic's four-row grid and labels in exp\intrface\bintroe (doc 10.35).
function Edit-OziMenu([string] $Text) {
    $cols = @(@(1, 0, 2, 16, 4), @(3, $null, 5, $null, 12))
    $gadgetOf = @{ 0 = 6; 1 = 7; 2 = 8; 3 = 9; 4 = 10; 5 = 11; 12 = 13; 16 = 17 }
    $labels = @{ 1 = 'COUNCIL WARS'; 2 = 'ACADEMY'; 3 = 'LOAD CW GAME'; 5 = 'LOAD OZI GAME'; 8 = 'OZI MISSIONS' }
    $xy = @{}
    foreach ($m in ([regex] '(?m)^\s*pushb\s+(\d+)\s+\d+\s+(\d+)\s+(\d+)\s').Matches($Text)) { $xy[[int]$m.Groups[1].Value] = @([int]$m.Groups[2].Value, [int]$m.Groups[3].Value) }
    $gadgets = @{}
    foreach ($m in ([regex] '(?m)^\s*gadget\s+(\d+)\s').Matches($Text)) { $gadgets[[int]$m.Groups[1].Value] = $true }
    $missing = @()
    foreach ($need in 0, 1, 2, 3, 4, 5, 12, 16) { if (-not $xy.ContainsKey($need)) { $missing += "pushb $need" } }
    foreach ($need in 6, 7, 8, 9, 10, 11, 13, 17) { if (-not $gadgets.ContainsKey($need)) { $missing += "gadget $need" } }
    $b = ([regex] '(?m)^\s*banim\s+18\s+\d+\s+(\d+)\s+(\d+)\s').Match($Text)
    if (-not $b.Success -or $b.Groups[1].Value -ne '8' -or $b.Groups[2].Value -ne '8') { $missing += 'banim 18 with 8 pairs' }
    if ($missing.Count) { throw ("bintroe: not Classic's 2x4 button grid (missing " + ($missing -join ', ') + ')') }
    $xs = @($xy.Values | ForEach-Object { $_[0] } | Sort-Object -Unique)
    $ys = @($xy.Values | ForEach-Object { $_[1] } | Sort-Object -Unique)
    if ($xs.Count -ne 2 -or $ys.Count -lt 4) { throw ('bintroe: expected two button columns and at least four rows, found {0} x {1}' -f $xs.Count, $ys.Count) }
    $pitch = [int]::MaxValue
    for ($i = 1; $i -lt $ys.Count; $i++) { if ($ys[$i] - $ys[$i - 1] -lt $pitch) { $pitch = $ys[$i] - $ys[$i - 1] } }
    $bottom = $ys[$ys.Count - 1]
    # the maintainer's grouping: about a quarter of a button's height after rows 1 and 3
    $hs = @([regex]::Matches($Text, '(?m)^\s*pushb\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)\s') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object)
    $gap = [int][Math]::Round($hs[0] * 0.25)
    $rows = $cols[0].Count
    $offs = @()
    for ($k = 0; $k -lt $rows; $k++) {
        $extra = 0
        foreach ($r in 1, 3) { if ($r -le $k) { $extra += $gap } }
        $offs += ($k * $pitch + $extra)
    }
    $move = @{}
    for ($c = 0; $c -lt $cols.Count; $c++) {
        for ($k = 0; $k -lt $cols[$c].Count; $k++) {
            $id = $cols[$c][$k]
            if ($null -ne $id) {
                $pos = @($xs[$c], ($bottom - ($offs[$rows - 1] - $offs[$k])))
                $move[[int]$id] = $pos
                $move[[int]$gadgetOf[[int]$id]] = $pos        # the gadget follows its button
            }
        }
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $Text.Split("`n")) {
        $cr = if ($raw.EndsWith("`r")) { "`r" } else { '' }
        $line = if ($cr) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        $m = [regex]::Match($line, '^\s*(pushb|gadget)\s+(\d+)\s')
        $t = [regex]::Match($line, '^\s*textmsg\s+(\d+)\s')
        if ($m.Success -and $move.ContainsKey([int]$m.Groups[2].Value)) {   # button and gadget ids do not overlap
            $pos = $move[[int]$m.Groups[2].Value]
            $toks = @($TOKENS.Matches($line) | ForEach-Object { $_.Value })
            $n = 0
            for ($i = 0; $i -lt $toks.Count; $i++) {
                if ($toks[$i].Trim().Length -eq 0) { continue }
                $n++
                if ($n -eq 4) { $toks[$i] = [string]$pos[0] } elseif ($n -eq 5) { $toks[$i] = [string]$pos[1]; break }
            }
            $line = -join $toks
        } elseif ($t.Success -and $labels.ContainsKey([int]$t.Groups[1].Value)) {
            $line = 'textmsg {0}       {1}' -f [int]$t.Groups[1].Value, $labels[[int]$t.Groups[1].Value]
        }
        $out.Add($line + $cr)
    }
    return ($out -join "`n")
}

# The whole set for one resolution. $Movies: the Classic `movies` fix is applied, so the two campaign
# lists name the DC*.AVI endings (patch_movies.py).  Returns text lines about what was written.
function Write-InterfaceSet([string] $GameDir, [string] $Mode, [bool] $Movies) {
    $wh = Get-ModeSize $Mode; $W = $wh[0]; $H = $wh[1]
    $dx0 = [int][Math]::Floor(($W - 640) / 2); $dy0 = [int][Math]::Floor(($H - 480) / 2)
    $lines = @()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $intrface = Join-Path $GameDir 'INTRFACE'; $hd = Join-Path $GameDir 'INTRF_HD'; $gamestat = Join-Path $GameDir 'GAMESTAT'
    $src = Join-Path $hd $Mode
    foreach ($need in 'INTRG.GIF', 'INTRO.GIF', 'INTRFACE.GIF') { if (-not (Find-CI $src $need)) { throw "INTRF_HD\$Mode\$need is missing: the painted backdrops and HUD frame for $Mode ship with the game and cannot be generated" } }
    Initialize-GifCodec
    $written = 0
    $introScreens = @('bintroe', 'introe', 'buttonse', 'dintroe')
    $gifsToPad = @{}
    # --- INTRFACE scripts -> INTRF_HD
    foreach ($f in [System.IO.Directory]::GetFiles($intrface)) {
        $name = [System.IO.Path]::GetFileName($f); $lname = $name.ToLower()
        if ($lname.EndsWith('.bak') -or $lname.EndsWith('.gif') -or $lname.EndsWith('.bmp') -or $lname.EndsWith('.spr') -or $lname.EndsWith('.rmp') -or $lname.EndsWith('.rgb')) { continue }
        if ($lname -eq 'multie~1.txt') { continue }     # a stray duplicate of MULTIE nothing reads (split_hd_data DROP)
        $text = Read-Latin1 $f
        if ($lname.EndsWith('.dat')) {
            $new = Edit-DatList $text
            if ($new -ne $text) { Write-Latin1 (Join-Path $hd $name) $new; $written++ }
            continue
        }
        $m4 = $SIZE4.Match($text); $m2 = $SIZE2.Match($text); $bg = $BACKGROUND.Match($text)
        if ($m4.Success -and -not $bg.Success) {
            $x = [int]$m4.Groups[3].Value; $y = [int]$m4.Groups[4].Value
            if ($x -eq 0 -and $y -eq 0) { continue }
            # a sub-window dialog: rect and widgets +(dx,dy)
            Write-Latin1 (Join-Path $hd $name) (Edit-PaddedScript $text $dx0 $dy0 @(($x + $dx0), ($y + $dy0), [int]$m4.Groups[5].Value, [int]$m4.Groups[6].Value)); $written++
            continue
        }
        if ($m4.Success -or -not $m2.Success -or -not $bg.Success) { continue }
        if ($lname -eq 'maine') {
            Write-Latin1 (Join-Path $hd $name) (Set-BackgroundHd (Edit-HudScript $text $W $H)); $written++
            continue
        }
        $gif = Find-CI $intrface ($bg.Groups[1].Value + '.GIF')
        if (-not $gif) { continue }
        if ($introScreens -contains $lname) {
            Write-Latin1 (Join-Path $hd $name) (Set-BackgroundHd (Edit-IntroScript $text $W $H)); $written++
        } else {
            $gs = [DcGif]::Size([System.IO.File]::ReadAllBytes($gif))
            Write-Latin1 (Join-Path $hd $name) (Set-BackgroundHd (Edit-PaddedScript $text ([int][Math]::Floor(($W - $gs[0]) / 2)) ([int][Math]::Floor(($H - $gs[1]) / 2)) @(0, 0, $W, $H))); $written++
        }
        $gifsToPad[[System.IO.Path]::GetFileName($gif).ToUpper()] = $gif
    }
    # --- backgrounds: the painted / spliced ones ship per size, the rest are letterboxed here
    foreach ($shipped in 'INTRG.GIF', 'INTRO.GIF', 'INTRFACE.GIF') {
        $gifsToPad.Remove($shipped)
        [System.IO.File]::Copy((Find-CI $src $shipped), (Join-Path $hd $shipped), $true); $written++
    }
    foreach ($k in @($gifsToPad.Keys | Sort-Object)) {
        $bytes = [DcGif]::Pad([System.IO.File]::ReadAllBytes($gifsToPad[$k]), $W, $H)
        [System.IO.File]::WriteAllBytes((Join-Path $hd ([System.IO.Path]::GetFileName($gifsToPad[$k]))), $bytes); $written++
    }
    # --- briefing lists.  HSCENE/GSCENE name the campaign endings: the Classic `movies` fix makes the
    # exe play DCHENDING/DCAENDING.AVI, so the lists say so when that fix is on - or when those files are
    # in the folder (the fix requires them; the Council Wars exe never reads these two lists, so a
    # Council Wars run in the shared folder must not undo the Classic names)
    $avi = Join-Path $GameDir 'AVI'
    if ((Find-CI $avi 'DCHENDING.AVI') -and (Find-CI $avi 'DCAENDING.AVI')) { $Movies = $true }
    foreach ($ln in 'HSCENE.TXT', 'GSCENE.TXT', 'HTSCENE.TXT', 'GTSCENE.TXT') {
        $p = Find-CI $gamestat $ln
        if (-not $p) { continue }
        $t = Edit-SceneList (Read-Latin1 $p) $dx0 $dy0
        if ($Movies) {
            if ($ln -eq 'HSCENE.TXT') { $t = $t.Replace('avi/hending.avi', 'avi/dchending.avi') }
            if ($ln -eq 'GSCENE.TXT') { $t = $t.Replace('avi/aending.avi', 'avi/dcaending.avi') }
        }
        Write-Latin1 (Join-Path $hd ([System.IO.Path]::GetFileName($p))) $t; $written++
    }
    # --- loading screens
    $lines += Write-LoadingScreens $GameDir $Mode
    # --- Council Wars: exp\intrface overrides -> exp\intrf_hd, and the OZI overlay's copies
    $expI = Join-Path $GameDir 'exp\intrface'; $expG = Join-Path $GameDir 'exp\gamestat'; $expHd = Join-Path $GameDir 'exp\intrf_hd'
    $expWritten = 0
    if (Test-Path -LiteralPath $expI) {
        foreach ($nm in 'bintroe', 'introe', 'shumane') {
            $p = Find-CI $expI $nm
            if (-not $p) { continue }
            $text = Read-Latin1 $p
            if ($nm -eq 'shumane') {
                $bg = $BACKGROUND.Match($text)
                $gif = if ($bg.Success) { Find-CI $intrface ($bg.Groups[1].Value + '.GIF') } else { $null }
                $gs = if ($gif) { [DcGif]::Size([System.IO.File]::ReadAllBytes($gif)) } else { @(640, 480) }
                $t = Set-BackgroundHd (Edit-PaddedScript $text ([int][Math]::Floor(($W - $gs[0]) / 2)) ([int][Math]::Floor(($H - $gs[1]) / 2)) @(0, 0, $W, $H))
            } else {
                $t = Set-BackgroundHd (Edit-IntroScript $text $W $H)
                if ($nm -eq 'bintroe') { $t = Edit-OziMenu $t }
            }
            Write-Latin1 (Join-Path $expHd ([System.IO.Path]::GetFileName($p))) $t; $expWritten++
        }
        foreach ($ln in 'hxscene.txt', 'gxscene.txt') {
            $p = Find-CI $expG $ln
            if ($p) { Write-Latin1 (Join-Path $expHd ([System.IO.Path]::GetFileName($p))) (Edit-SceneList (Read-Latin1 $p) $dx0 $dy0); $expWritten++ }
        }
    }
    $oziWritten = 0
    $ozi = Join-Path $GameDir 'ozi_ns'; $oziHd = Join-Path $ozi 'intrf_hd'; $oziG = Join-Path $ozi 'gamestat'
    if ((Test-Path -LiteralPath $ozi) -and $expWritten -gt 0) {
        foreach ($nm in 'bintroe', 'introe', 'shumane') {
            $p = Find-CI $expHd $nm
            if ($p) { if (-not (Test-Path -LiteralPath $oziHd)) { New-Item -ItemType Directory -Path $oziHd -Force | Out-Null }; [System.IO.File]::Copy($p, (Join-Path $oziHd $nm), $true); $oziWritten++ }
        }
        foreach ($ln in 'hxscene.txt', 'gxscene.txt') {
            $p = Find-CI $oziG $ln       # the pack's lists, unshifted (build_ozi_overlay.py keeps them there)
            if ($p) { Write-Latin1 (Join-Path $oziHd $ln) (Edit-SceneList (Read-Latin1 $p) $dx0 $dy0); $oziWritten++ }
        }
    }
    $lines += ('interface set for {0} written: INTRF_HD\ {1} files{2}{3} ({4:N1} s, GIFs re-encoded by the compiled DcGif codec)' -f $Mode, $written,
               $(if ($expWritten) { ", exp\intrf_hd\ $expWritten" } else { '' }), $(if ($oziWritten) { ", ozi_ns\intrf_hd\ $oziWritten" } else { '' }), $sw.Elapsed.TotalSeconds)
    return $lines
}

# --- 640x480 companions of two fixes: the exe is pointed at copies the original exe never reads ---------
# movies @ 640x480: GAMESTAT\HSCNDC.TXT / GSCNDC.TXT = the stock campaign lists naming the Classic endings
function Write-StockEndingLists([string] $GameDir) {
    $lines = @(); $gs = Join-Path $GameDir 'GAMESTAT'
    foreach ($pair in @(@('HSCENE.TXT', 'HSCNDC.TXT', 'avi/hending.avi', 'avi/dchending.avi'), @('GSCENE.TXT', 'GSCNDC.TXT', 'avi/aending.avi', 'avi/dcaending.avi'))) {
        $src = Find-CI $gs $pair[0]
        if (-not $src) { $lines += ('GAMESTAT\{0} NOT written: GAMESTAT\{1} is missing' -f $pair[1], $pair[0]); continue }
        Write-Latin1 (Join-Path $gs $pair[1]) ((Read-Latin1 $src).Replace($pair[2], $pair[3]))
        $lines += ('wrote GAMESTAT\{0} (= {1} naming {2}; the 640x480 exe reads this copy)' -f $pair[1], $pair[0], $pair[3])
    }
    return $lines
}
# ozi @ 640x480: exp\intrface\bintoze (and ozi_ns\intrface\bintoze) = the stock menu + the two OZI labels
function Write-StockOziMenu([string] $GameDir) {
    $src = Find-CI (Join-Path $GameDir 'exp\intrface') 'bintroe'
    if (-not $src) { return @('exp\intrface\bintoze NOT written: exp\intrface\bintroe is missing') }
    $t = Edit-OziMenu (Read-Latin1 $src)
    $lines = @()
    foreach ($dir in 'exp\intrface', 'ozi_ns\intrface') {
        $d = Join-Path $GameDir $dir
        if (Test-Path -LiteralPath $d) { Write-Latin1 (Join-Path $d 'bintoze') $t; $lines += ('wrote {0}\bintoze (stock menu, labels OZI MISSIONS / OZI LOAD; the 640x480 exe reads this copy)' -f $dir) }
    }
    return $lines
}

# Applies the chosen patches (canonical order) to the bytes of $OriginalPath and writes $OutputPath.
# Returns a small result object; throws on any check failure.
# $Progress (optional): a script block called with one line of text before each step - the window
# shows it in its "patching in progress" box; the command line passes nothing.
function Invoke-PatchRun([string] $OriginalPath, $Build, [object[]] $Chosen, [string] $OutputPath, [string] $Mode, [scriptblock] $Progress) {
    $data = [System.IO.File]::ReadAllBytes($OriginalPath)
    $effective = @(Get-BuildPatches $Build $Mode)
    $ordered = @($effective | Where-Object { $p = $_; ($Chosen | Where-Object { $_.Id -eq $p.Id -and $_.Mode -eq $p.Mode }) })
    $result = $data
    $n = 0
    foreach ($p in $ordered) {
        $n++
        if ($Progress) { & $Progress ("Applying fix {0} of {1}: '{2}' ({3}, {4} edits)..." -f $n, $ordered.Count, $p.Id, $p.Name, @($p.Edits).Count) }
        $result = Invoke-Patch $result $p
    }
    if ($Progress) { & $Progress ("Writing {0} ({1} bytes)..." -f (Split-Path -Leaf $OutputPath), $result.Length) }
    [System.IO.File]::WriteAllBytes($OutputPath, $result)
    $outSha = Get-Sha256Hex $result
    $ref = if ($Mode) { $Build.ReferenceSha256[$Mode] } else { $Build.PatchedSha256 }
    # an HD display fix was applied: build the INTRF_HD interface set for the chosen size (scripts,
    # briefing lists, letterboxed backgrounds, loading screens; the Council Wars and OZI copies too)
    $generated = @()
    if ($Mode -and $Mode -ne '640x480' -and ($ordered | Where-Object { $_.ContainsKey('SetSources') })) {
        $movies = [bool] ($ordered | Where-Object { $_.Id -eq 'movies' })
        if ($Progress) { & $Progress ("Writing the {0} interface set into INTRF_HD (scripts, backgrounds, loading screens) - this takes a few seconds..." -f $Mode) }
        try {
            $generated = @(Write-InterfaceSet (Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))) $Mode $movies)
        } catch {
            $generated = @('INTERFACE SET NOT WRITTEN: ' + $_.Exception.Message)
        }
    }
    if ($Mode -eq '640x480') {
        $dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
        if ($ordered | Where-Object { $_.Id -eq 'movies' }) { try { $generated += Write-StockEndingLists $dir } catch { $generated += 'GAMESTAT lists NOT written: ' + $_.Exception.Message } }
        if ($ordered | Where-Object { $_.Id -eq 'ozi' })    { try { $generated += Write-StockOziMenu $dir } catch { $generated += 'bintoze NOT written: ' + $_.Exception.Message } }
    }
    return @{
        Generated = $generated
        Applied   = $ordered
        Sha256    = $outSha
        Size      = $result.Length
        Mode      = $Mode
        Complete  = ($ordered.Count -eq $effective.Count)
        Matches   = ($outSha -eq $ref)                      # = the reference build for this resolution
        Published = ($outSha -eq $Build.PatchedSha256)      # = the exe in the repository
    }
}

# The safeguard: before anything is written, every chosen fix must have (a) the fixes it depends on
# chosen as well and (b) every data file it needs present under $GameDir (the folder the patched
# exe will run from = where it is written).  Returns text lines describing the problems; empty = ok.
# Without this an exe patched for 1024x768 in a folder without INTRF_HD/ fails at start-up or draws
# the menus into the top-left corner, and the player would blame the patch.
function Get-DataProblems($Build, [object[]] $Chosen, [string] $GameDir, [string] $Mode) {
    $problems = @()
    $chosenIds = @($Chosen | ForEach-Object { $_.Id })
    $effective = @(Get-BuildPatches $Build $Mode)
    foreach ($p in $Chosen) {
        foreach ($need in @($p.Requires)) {
            if ($chosenIds -notcontains $need) {
                $other = @($effective | Where-Object { $_.Id -eq $need })
                $otherName = if ($other.Count -gt 0) { $other[0].Name } else { $need }
                $problems += ("fix '{0}' ({1}) only works together with fix '{2}' ({3}) - select both or neither" -f $p.Id, $p.Name, $need, $otherName)
            }
        }
        $missing = @()
        foreach ($rel in @($p.Data)) { if (-not (Test-Path -LiteralPath (Join-Path $GameDir $rel))) { $missing += $rel } }
        if ($missing.Count -gt 0) {
            $total = 0; foreach ($d in @($p.Data)) { $total++ }
            $shown = @($missing | Select-Object -First 8) -join ', '
            if ($missing.Count -gt 8) { $shown += (', ... ({0} more)' -f ($missing.Count - 8)) }
            $problems += ("fix '{0}' ({1}) needs {2} data files under '{3}', {4} are missing: {5}. Copy the game folder from the repository " +
                          "(https://github.com/endotermic/Dark-Colony) or write the exe into the game folder there.") -f $p.Id, $p.Name, $total, $GameDir, $missing.Count, $shown
        }
    }
    return $problems
}

# Which fixes of a build cannot be applied into $GameDir: their resources (Data files) are not there,
# or a fix they require is itself unavailable.  Returns a hashtable id -> one-line reason (empty = all
# available).  The window greys these out as "RESOURCES NOT FOUND", -All skips them.
function Get-UnavailableFixes($Build, [string] $GameDir, [string] $Mode) {
    $out = @{}
    if (-not $GameDir) { return $out }
    $effective = @(Get-BuildPatches $Build $Mode)
    foreach ($p in $effective) {
        $missing = @(); $total = 0
        foreach ($rel in @($p.Data)) { $total++; if (-not (Test-Path -LiteralPath (Join-Path $GameDir $rel))) { $missing += $rel } }
        if ($missing.Count -gt 0) {
            $tops = @{}
            foreach ($m in $missing) { $top = ($m -split '\\')[0]; if ($tops.ContainsKey($top)) { $tops[$top]++ } else { $tops[$top] = 1 } }
            $where = @($tops.Keys | Sort-Object | ForEach-Object { '{0}\ ({1})' -f $_, $tops[$_] }) -join ', '
            $out[$p.Id] = ('{0} of {1} resource files missing: {2}' -f $missing.Count, $total, $where)
        }
    }
    # a fix that needs an unavailable fix is unavailable too (repeat until nothing changes: resolution <-> hdpaths are mutual)
    do {
        $changed = $false
        foreach ($p in $effective) {
            if ($out.ContainsKey($p.Id)) { continue }
            foreach ($need in @($p.Requires)) {
                if ($out.ContainsKey($need)) { $out[$p.Id] = ("needs fix '{0}', which is unavailable here" -f $need); $changed = $true; break }
                if (-not ($effective | Where-Object { $_.Id -eq $need })) { $out[$p.Id] = ("needs fix '{0}', which does not exist at this resolution" -f $need); $changed = $true; break }
            }
        }
    } while ($changed)
    return $out
}

# One-line summary of what a fix needs, for -List and the window.
function Get-RequirementLines($Build, $Patch) {
    $lines = @()
    $req = @($Patch.Requires)
    if ($req.Count -gt 0) { $lines += ('needs fix(es) ' + ($req -join ', ') + ' selected as well') }
    $n = 0; $tops = @{}
    foreach ($d in @($Patch.Data)) { $n++; $top = ($d -split '\\')[0]; if ($tops.ContainsKey($top)) { $tops[$top]++ } else { $tops[$top] = 1 } }
    if ($n -gt 0) {
        $parts = @($tops.Keys | Sort-Object | ForEach-Object { '{0}\ ({1})' -f $_, $tops[$_] })
        $lines += ('needs {0} data files next to the exe: {1} - checked before writing' -f $n, ($parts -join ', '))
    }
    if ($Patch.ContainsKey('SetSources')) {
        $lines += 'writes the INTRF_HD interface set for this resolution (scripts, briefing lists, letterboxed backgrounds, loading screens; exp\intrf_hd and ozi_ns\intrf_hd too) from the stock files and the three shipped pictures - the GIF codec is C# source in this file, compiled by Add-Type (see the INTERFACE SET section)'
    }
    return $lines
}

function Write-PatchList([switch] $WithEdits) {
    foreach ($b in $Builds) {
        Write-Host ''
        Write-Host ("=== {0}: {1}" -f $b.Id, $b.Title) -ForegroundColor Cyan
        Write-Host ("    original {0} ({1} bytes)  SHA-256 {2}" -f $b.OriginalName, $b.Size, $b.OriginalSha256)
        Write-Host ("    all patches -> {0}         SHA-256 {1}" -f $b.OutputName, $b.PatchedSha256)
        if (@($b.Modes).Count -gt 0) {
            Write-Host ("    resolutions: {0} (default {1}); reference SHA-256 with every fix of that resolution:" -f (($b.Modes | ForEach-Object { Format-ModeLabel $_ (Get-MonitorSize) }) -join ', '), $b.DefaultMode)
            foreach ($m in $b.Modes) { Write-Host ("      {0,-10} {1}" -f $m, $b.ReferenceSha256[$m]) }
        }
        $n = 0
        foreach ($p in $b.Patches) {
            $n++
            Write-Host ''
            $modeTag = if ($p.Mode -and $p.Mode -ne 'hd') { ' @ ' + $p.Mode } elseif ($p.Mode -eq 'hd') { ' @ every resolution but 640x480' } else { '' }
            Write-Host ("  {0}. [{1}{2}] {3}  ({4}, {5} edits)" -f $n, $p.Id, $modeTag, $p.Name, $p.Date, (Get-EditCount $p)) -ForegroundColor Yellow
            foreach ($line in ($p.Description -split "`r?`n")) { Write-Host ("       " + $line) }
            foreach ($line in (Get-RequirementLines $b $p)) { Write-Host ("       * " + $line) -ForegroundColor Magenta }
            if ($WithEdits) {
                foreach ($line in (Get-EditLines $p)) { Write-Host ("       " + $line) -ForegroundColor DarkGray }
                foreach ($d in @($p.Data)) { Write-Host ("       data  " + $d) -ForegroundColor DarkGray }
            }
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

    $script:gui = @{ Path = $null; Data = $null; Build = $null; IsOriginal = $false; Syncing = $false; Unavailable = @{}
                     Mode = ''; ModeList = @(); Patches = @(); Monitor = (Get-MonitorSize)
                     Here = $PSScriptRoot }     # the folder this script sits in = the repository root; the Browse dialog starts in its game folder
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
    $lblStatus.Text = 'Pick dc16.exe (Dark Colony) or ENGEXP16.EXE (Council Wars) from the "DC - Council wars" folder, or maped.exe from "Dark Colony - Map editor" - all three are in the repository, untouched.'
    if ($PSScriptRoot) { $lblStatus.Text += "`r`nThis script is in $PSScriptRoot - Browse starts in its game folder; the result is written next to the exe you pick." }

    # --- left: the fixes
    $grpFix = New-Object System.Windows.Forms.GroupBox
    $grpFix.Text = 'Fixes to apply (always applied in this order)'; $grpFix.Location = '12,82'; $grpFix.Size = '450,470'
    $grpFix.Anchor = 'Top,Bottom,Left'
    # the resolution drop-down: "WIDTHxHEIGHT (aspect) recommended" - recommended = your monitor's aspect ratio
    $lblRes = New-Object System.Windows.Forms.Label
    $lblRes.Text = 'Screen resolution:'; $lblRes.Location = '12,25'; $lblRes.AutoSize = $true
    $cmbRes = New-Object System.Windows.Forms.ComboBox
    $cmbRes.Location = '130,21'; $cmbRes.Size = '300,23'; $cmbRes.DropDownStyle = 'DropDownList'; $cmbRes.Enabled = $false
    $chkAll = New-Object System.Windows.Forms.CheckBox
    $chkAll.Text = 'Select all fixes  (result = the reference build for the chosen resolution)'
    $chkAll.Location = '12,52'; $chkAll.AutoSize = $true; $chkAll.Enabled = $false
    $chkAll.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lst = New-Object System.Windows.Forms.CheckedListBox
    $lst.Location = '12,80'; $lst.Size = '426,378'; $lst.Anchor = 'Top,Bottom,Left,Right'
    $lst.CheckOnClick = $true; $lst.IntegralHeight = $false; $lst.Enabled = $false
    $lst.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $grpFix.Controls.AddRange(@($lblRes, $cmbRes, $chkAll, $lst))

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
    # The output is not selectable (22 Sep 2026, maintainer request "disable resulting path and filename
    # selection"): the patched exe is always written under the build's name beside the original
    # (dc16new.exe / engexp16new.exe / maped_ozi_ns_v1.2.exe), because that is where its data files are
    # and what the READMEs, the server tests and the players' shortcuts expect.  The box only shows it.
    $lblOut.Text = 'Written to:'; $lblOut.Location = '12,565'; $lblOut.AutoSize = $true; $lblOut.Anchor = 'Bottom,Left'
    $txtOut = New-Object System.Windows.Forms.TextBox
    $txtOut.Location = '110,562'; $txtOut.Size = '862,23'; $txtOut.Anchor = 'Bottom,Left,Right'; $txtOut.ReadOnly = $true
    $txtOut.TabStop = $false
    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Apply selected fixes'; $btnApply.Location = '110,596'; $btnApply.Size = '170,30'; $btnApply.Anchor = 'Bottom,Left'
    $btnApply.Enabled = $false
    $btnVerify = New-Object System.Windows.Forms.Button
    $btnVerify.Text = 'Inspect an exe...'; $btnVerify.Location = '290,596'; $btnVerify.Size = '140,30'; $btnVerify.Anchor = 'Bottom,Left'
    $lblLog = New-Object System.Windows.Forms.Label
    $lblLog.Location = '440,596'; $lblLog.Size = '532,40'; $lblLog.Anchor = 'Bottom,Left,Right'; $lblLog.Font = $mono

    $form.Controls.AddRange(@($lblIn, $txtIn, $btnBrowse, $lblStatus, $grpFix, $grpInfo, $lblOut, $txtOut, $btnApply, $btnVerify, $lblLog))
    $script:gui.Controls = @{ Form = $form; In = $txtIn; Status = $lblStatus; All = $chkAll; List = $lst; Info = $txtInfo; Out = $txtOut; Apply = $btnApply; Log = $lblLog; Browse = $btnBrowse; Verify = $btnVerify; Res = $cmbRes }
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
            $c.Status.Text = "Not a build this script knows ($($data.Length) bytes). Use dc16.exe or ENGEXP16.EXE from the repository's DC - Council wars folder, or maped.exe from Dark Colony - Map editor."
            $c.List.Enabled = $false; $c.All.Enabled = $false; $c.Apply.Enabled = $false; $c.Res.Enabled = $false
            return
        }
        $g.Path = $path; $g.Data = $data; $g.Build = $build; $g.IsOriginal = $isOriginal
        $redirectOut = $null
        # the resolutions of this build; the default one preselected
        $g.Syncing = $true
        $c.Res.Items.Clear(); $g.ModeList = @($build.Modes)
        foreach ($m in $g.ModeList) { [void] $c.Res.Items.Add((Format-ModeLabel $m $g.Monitor)) }
        $c.Res.Enabled = ($g.ModeList.Count -gt 0)
        if ($g.ModeList.Count -gt 0) { $c.Res.SelectedIndex = [Math]::Max(0, [Array]::IndexOf($g.ModeList, (Get-PreferredMode $build $g.Monitor))) }
        $g.Syncing = $false
        if ($isOriginal) {
            $c.Status.ForeColor = 'DarkGreen'
            $c.Status.Text = "$($build.Title)`r`nSHA-256 $sha = the untouched original."
        } else {
            # a known build, but not the untouched original: an already patched build (players pick the
            # game exe they play, dc16new.exe, as the "original" - report of 21 Sep 2026), or another copy
            $patched = $false
            foreach ($e in $build.Patches[0].Edits) { if ((Get-EditState $data $e) -eq 'new') { $patched = $true } }
            if ($patched) {
                $name = [System.IO.Path]::GetFileName($path)
                $origBeside = Join-Path (Split-Path $path) $build.OriginalName
                $origData = $null
                if (Test-Path -LiteralPath $origBeside) {
                    try { $origData = [System.IO.File]::ReadAllBytes($origBeside) } catch { $origData = $null }
                    if ($origData -and (Get-Sha256Hex $origData) -ne $build.OriginalSha256) { $origData = $null }
                }
                if ($origData) {
                    # the untouched original sits beside it: that is the input, the picked file is the output
                    $g.Path = $origBeside; $g.Data = $origData; $g.IsOriginal = $true
                    $c.In.Text = $origBeside
                    $redirectOut = $path
                    $c.Status.ForeColor = 'DarkOrange'
                    $c.Status.Text = "$name is already a patched build, not the untouched original.`r`nUsing $($build.OriginalName) beside it as the input (its SHA-256 is the untouched original); the result replaces $name."
                } else {
                    $c.Status.ForeColor = 'Firebrick'
                    $c.Status.Text = "$name is already a patched build (fix $($build.Patches[0].Id) applied), not the untouched original - the fixes apply to the original only.`r`nBrowse to $($build.OriginalName) from the repository's game folder (https://github.com/endotermic/Dark-Colony), or put it beside this file and browse again."
                    $c.List.Enabled = $false; $c.All.Enabled = $false; $c.Apply.Enabled = $false; $c.Res.Enabled = $false
                    $g.Path = $null; $g.Data = $null; $g.Build = $null
                    return
                }
            } else {
                $c.Status.ForeColor = 'DarkOrange'
                $c.Status.Text = "$($build.Title)`r`nSHA-256 does not match the untouched original (another copy?). Every byte is still checked before it is written."
            }
        }
        $c.List.Enabled = $true; $c.All.Enabled = $true; $c.Apply.Enabled = $true
        # TextChanged -> Refresh (the list is not filled yet: no-op)
        $c.Out.Text = if ($redirectOut) { $redirectOut } else { Join-Path (Split-Path $path) $build.OutputName }
        & $script:gui.FillList
        $c.Log.Text = ''
    }
    $script:gui.Load = $loadOriginal

    # (Re)fills the fix list for the resolution chosen in the drop-down: the fixes of every resolution
    # plus the chosen resolution's variants of 'resolution' and 'clock' (none for 640x480).
    $script:gui.FillList = {
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build) { return }
        $g.Mode = if ($g.ModeList.Count -gt 0 -and $c.Res.SelectedIndex -ge 0) { $g.ModeList[$c.Res.SelectedIndex] } else { '' }
        $g.Patches = @(Get-BuildPatches $g.Build $g.Mode)
        $g.Syncing = $true
        $c.List.Items.Clear(); $c.All.Checked = $false
        foreach ($p in $g.Patches) { [void] $c.List.Items.Add(('{0}   ({1})' -f $p.Name, $p.Date), $false) }
        $g.Syncing = $false
        & $script:gui.Refresh
        if ($c.List.Items.Count -gt 0) { $c.List.SelectedIndex = 0 }
        if ($g.Mode -eq '640x480') { $c.Log.ForeColor = 'Black'; $c.Log.Text = '640x480 = the stock screen size: the display fixes (resolution, INTRF_HD paths, clock) are not offered.' }
    }
    $c.Res.Add_SelectedIndexChanged({ if (-not $script:gui.Syncing) { & $script:gui.FillList } })

    # Re-checks the resources of every fix against the folder the exe will be written to: fixes whose
    # files are missing (or which need such a fix) get "RESOURCES NOT FOUND" in their label, are
    # unticked and cannot be ticked.  Runs at load and whenever the output path changes.
    $script:gui.Refresh = {
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build) { return }
        $dir = $null
        try { $t = $c.Out.Text.Trim(); if ($t) { $dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($t)) } } catch { $dir = $null }
        $g.Unavailable = Get-UnavailableFixes $g.Build $dir $g.Mode
        $g.Syncing = $true
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) {
            $p = $g.Patches[$i]
            $was = $c.List.GetItemChecked($i)
            $text = '{0}   ({1})' -f $p.Name, $p.Date
            if ($g.Unavailable.ContainsKey($p.Id)) { $text = '[RESOURCES NOT FOUND]  ' + $text; $was = $false }
            $c.List.Items[$i] = $text
            $c.List.SetItemChecked($i, $was)
        }
        $g.Syncing = $false
        $n = 0; foreach ($k in $g.Unavailable.Keys) { $n++ }
        if ($n -gt 0) {
            $c.Log.ForeColor = 'DarkOrange'
            $c.Log.Text = "$n fix(es) cannot be applied into this folder - resources not found (see the label; click the fix for details)."
        }
    }
    $c.Out.Add_TextChanged({ & $script:gui.Refresh })

    $c.Browse.Add_Click({
        $c = $script:gui.Controls
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Pick the untouched original executable'
        $dlg.Filter = 'Dark Colony executables (*.exe)|*.exe|All files (*.*)|*.*'
        # Start in the folder of the exe already loaded, else in the game folder BESIDE THIS SCRIPT: without this
        # the dialog opens in the folder Windows last used for PowerShell's file dialogs - with two copies of the
        # repository (a git clone in Documents, a ZIP in Downloads) a player picks the other copy's exe without
        # noticing and the result lands there (22 Sep 2026: "the fresh copy isn't widescreen" - it was never patched)
        if ($script:gui.Path) { $dlg.InitialDirectory = Split-Path $script:gui.Path }
        elseif ($script:gui.Here) {
            $game = Join-Path $script:gui.Here 'DC - Council wars'
            $dlg.InitialDirectory = if (Test-Path -LiteralPath $game) { $game } else { $script:gui.Here }
        }
        if ($dlg.ShowDialog($c.Form) -eq 'OK') { & $script:gui.Load $dlg.FileName }
    })

    # "Select all" <-> individual boxes, without the two events feeding each other; fixes whose
    # resources are not found stay unticked in both directions
    $c.All.Add_CheckedChanged({
        $c = $script:gui.Controls
        $g = $script:gui
        if ($g.Syncing) { return }
        $g.Syncing = $true
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) {
            $avail = -not $g.Unavailable.ContainsKey($g.Patches[$i].Id)
            $c.List.SetItemChecked($i, ($c.All.Checked -and $avail))
        }
        $g.Syncing = $false
    })
    $c.List.Add_ItemCheck({
        param($sender, $e)
        $c = $script:gui.Controls
        $g = $script:gui
        if ($g.Syncing) { return }
        if ($e.NewValue -eq 'Checked' -and $g.Unavailable.ContainsKey($g.Patches[$e.Index].Id)) {
            $e.NewValue = 'Unchecked'   # cannot be ticked: resources not found
            $c.Log.ForeColor = 'Firebrick'
            $c.Log.Text = 'Resources not found for this fix in the output folder: ' + $g.Unavailable[$g.Patches[$e.Index].Id]
        }
        # "Select all" mirrors "every available fix is ticked"
        $all = $true
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) {
            if ($g.Unavailable.ContainsKey($g.Patches[$i].Id)) { continue }
            $checked = if ($i -eq $e.Index) { $e.NewValue -eq 'Checked' } else { $c.List.GetItemChecked($i) }
            if (-not $checked) { $all = $false }
        }
        $g.Syncing = $true; $c.All.Checked = $all; $g.Syncing = $false
    })

    $c.List.Add_SelectedIndexChanged({
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build -or $c.List.SelectedIndex -lt 0 -or $c.List.SelectedIndex -ge $g.Patches.Count) { return }
        $p = $g.Patches[$c.List.SelectedIndex]
        $lines = @()
        if ($g.Unavailable.ContainsKey($p.Id)) {
            $lines += @('RESOURCES NOT FOUND - this fix cannot be applied into the output folder:', ('  ' + $g.Unavailable[$p.Id]),
                        '  Copy the game folder from the repository (https://github.com/endotermic/Dark-Colony), or write', '  the exe into it.', '')
        }
        $lines += @(
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
        $reqLines = @(Get-RequirementLines $g.Build $p)
        if ($reqLines.Count -gt 0) {
            $lines += @('', 'Prerequisites (checked before anything is written):')
            foreach ($l in $reqLines) { $lines += ('  * ' + $l) }
        }
        $lines += @('', 'Byte edits (file offset: old bytes -> new bytes):', '') + (Get-EditLines $p)
        $c.Info.Text = $lines -join "`r`n"
        $c.Info.SelectionStart = 0; $c.Info.SelectionLength = 0; $c.Info.ScrollToCaret()
    })

    # Popups (22 Sep 2026, maintainer request "show a popup when patching is in progress and when it
    # succeeds and when it fails"): while the bytes and the interface set are written a small owned
    # "Patching in progress" box names the current step (the run is synchronous on the UI thread, so
    # the box is repainted by hand between the steps and the main window is disabled meanwhile), and
    # the outcome - written and byte-identical, written with a warning, refused, failed - is one
    # message box.  Every box goes through $script:gui.Notify so a headless test can replace it
    # with a recorder; the button passes $interactive = $true, a test may pass $false for silence.
    $script:gui.Notify = {
        param([string] $text, [string] $title, [string] $icon)
        [System.Windows.Forms.MessageBox]::Show($script:gui.Controls.Form, $text, $title, 'OK', $icon) | Out-Null
    }
    $script:gui.Busy = $null
    $script:gui.Progress = {
        param([string] $step)
        $c = $script:gui.Controls
        $c.Log.ForeColor = 'Black'; $c.Log.Text = $step
        $b = $script:gui.Busy
        if ($b) {
            $b.Label.Text = "Patching in progress - please wait.`r`n`r`n$step"
            $b.Form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    $script:gui.Apply = {
        param([bool] $interactive)
        $c = $script:gui.Controls
        $g = $script:gui
        if (-not $g.Build) { return $null }
        $chosen = @()
        for ($i = 0; $i -lt $c.List.Items.Count; $i++) { if ($c.List.GetItemChecked($i)) { $chosen += $g.Patches[$i] } }
        $outPath = $c.Out.Text.Trim()
        $refused = $null
        if ($chosen.Count -eq 0) { $refused = 'No fix selected - tick at least one fix.' }
        elseif (-not $outPath) { $refused = 'No output path - pick the original exe again.' }
        elseif ([System.IO.Path]::GetFullPath($outPath) -eq [System.IO.Path]::GetFullPath($g.Path)) { $refused = 'The output must not be the original file - the original is never written over.' }
        if ($refused) {
            $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = $refused
            if ($interactive) { & $g.Notify $refused 'Nothing to do' 'Warning' }
            return $null
        }
        if ((Test-Path $outPath) -and $interactive) {
            $answer = [System.Windows.Forms.MessageBox]::Show($c.Form, "$outPath exists.`r`nReplace it?", 'Replace file?', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { return $null }
        }
        $problems = @(Get-DataProblems $g.Build $chosen (Split-Path -Parent ([System.IO.Path]::GetFullPath($outPath))) $g.Mode)
        if ($problems.Count -gt 0) {
            $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'Nothing written: data files or dependent fixes are missing (see the message).'
            & $g.Notify ((($problems | ForEach-Object { '* ' + $_ }) -join "`r`n`r`n") +
                "`r`n`r`nAn exe written without them fails at start-up or draws garbage, which would look like a bug of the fix. " +
                "Write the exe into the game folder from the repository, or run the script from the command line with -IgnoreMissingData.") `
                'Prerequisites missing - nothing written' 'Warning'
            return $null
        }
        # the "in progress" box: an owned, unclosable form with the current step and a marquee bar
        if ($interactive) {
            $busy = New-Object System.Windows.Forms.Form
            $busy.Text = 'Patching in progress'
            $busy.FormBorderStyle = 'FixedDialog'; $busy.ControlBox = $false; $busy.ShowInTaskbar = $false
            $busy.Size = New-Object System.Drawing.Size(560, 190)
            $busy.StartPosition = if ($c.Form.Visible) { 'CenterParent' } else { 'CenterScreen' }
            $busy.Font = $c.Form.Font
            $busyLabel = New-Object System.Windows.Forms.Label
            $busyLabel.Location = '16,16'; $busyLabel.Size = '512,96'
            $busyLabel.Text = "Patching in progress - please wait.`r`n`r`nApplying $($chosen.Count) fixes to $(Split-Path -Leaf $g.Path), writing $(Split-Path -Leaf $outPath)..."
            $busyBar = New-Object System.Windows.Forms.ProgressBar
            $busyBar.Location = '16,120'; $busyBar.Size = '512,20'; $busyBar.Style = 'Marquee'; $busyBar.MarqueeAnimationSpeed = 30
            $busy.Controls.AddRange(@($busyLabel, $busyBar))
            $c.Form.Enabled = $false; $c.Form.UseWaitCursor = $true
            $busy.Show($c.Form)
            $g.Busy = @{ Form = $busy; Label = $busyLabel }
            $busy.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        }
        try {
            $r = Invoke-PatchRun $g.Path $g.Build $chosen $outPath $g.Mode $g.Progress
        } catch {
            $c.Log.ForeColor = 'Firebrick'; $c.Log.Text = 'Patching failed - nothing written.'
            & $g.Notify ("Patching failed:`r`n`r`n$($_.Exception.Message)`r`n`r`nNothing was written to $outPath.") 'Patching failed' 'Error'
            return $null
        } finally {
            if ($g.Busy) {
                $g.Busy.Form.Close(); $g.Busy.Form.Dispose(); $g.Busy = $null
                $c.Form.Enabled = $true; $c.Form.UseWaitCursor = $false
            }
        }
        $ids = ($r.Applied | ForEach-Object { $_.Id }) -join ', '
        $modeText = if ($r.Mode) { " for $($r.Mode)" } else { '' }
        if ($r.Generated.Count -gt 0) { $modeText += ' (' + ($r.Generated -join '; ') + ')' }
        $notWritten = @($r.Generated | Where-Object { $_ -match 'NOT WRITTEN|NOT written' })
        $where = "Written: $outPath"
        if ($notWritten.Count -gt 0) {
            $c.Log.ForeColor = 'Firebrick'
            $c.Log.Text = "The exe was written, but not its data files - see the message.`r`n$($notWritten -join '; ')"
            $title = 'Patching failed - data files not written'; $icon = 'Error'
            $text = "$where`r`n`r`nbut the data files it needs were NOT written:`r`n`r`n" + (($notWritten | ForEach-Object { '* ' + $_ }) -join "`r`n") +
                "`r`n`r`nThe game would fail at start-up with this exe. Fix the cause (a read-only or locked game folder?) and patch again."
        } elseif ($r.Complete -and $r.Published) {
            $c.Log.ForeColor = 'DarkGreen'
            $c.Log.Text = "Written: $($r.Size) bytes, all $($r.Applied.Count) fixes$modeText.`r`nSHA-256 $($r.Sha256) = byte-identical to the exe published in the repository."
            $title = 'Patching succeeded'; $icon = 'Information'
            $text = "$where`r`n`r`n$($r.Size) bytes, all $($r.Applied.Count) fixes$modeText.`r`n`r`nSHA-256 $($r.Sha256)`r`n= byte-identical to the exe published in the repository.`r`n`r`nStart the game with this file."
        } elseif ($r.Complete -and $r.Matches) {
            $c.Log.ForeColor = 'DarkGreen'
            $c.Log.Text = "Written: $($r.Size) bytes, all $($r.Applied.Count) fixes$modeText.`r`nSHA-256 $($r.Sha256) = byte-identical to the reference build for $($r.Mode)."
            $title = 'Patching succeeded'; $icon = 'Information'
            $text = "$where`r`n`r`n$($r.Size) bytes, all $($r.Applied.Count) fixes$modeText.`r`n`r`nSHA-256 $($r.Sha256)`r`n= byte-identical to the reference build for $($r.Mode).`r`n`r`nStart the game with this file."
        } elseif ($r.Complete) {
            $c.Log.ForeColor = 'Firebrick'
            $c.Log.Text = "Written, but the SHA-256 differs from the reference build$modeText - please report this.`r`n$($r.Sha256)"
            $title = 'Patched, but the result differs from the reference build'; $icon = 'Warning'
            $text = "$where`r`n`r`n$($r.Size) bytes, all $($r.Applied.Count) fixes$modeText, but the SHA-256 differs from the reference build:`r`n`r`n$($r.Sha256)`r`n`r`nThe file may still work - please report this together with the name and SHA-256 of your original."
        } else {
            $c.Log.ForeColor = 'Black'
            $c.Log.Text = "Written: $($r.Size) bytes with $($r.Applied.Count) of $($g.Patches.Count) fixes$modeText ($ids).`r`nSHA-256 $($r.Sha256)"
            $title = 'Patching succeeded'; $icon = 'Information'
            $text = "$where`r`n`r`n$($r.Size) bytes with $($r.Applied.Count) of $($g.Patches.Count) fixes${modeText}:`r`n$ids`r`n`r`nSHA-256 $($r.Sha256)`r`n`r`nStart the game with this file."
        }
        if ($interactive) { & $g.Notify $text $title $icon }
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
    if (-not $build) { throw "This is not one of the three known original executables (size / layout mismatch)." }
    if (-not $Force) {
        throw ("The SHA-256 is not that of the untouched {0} original. Start from {1} (in the repository), " +
               "or pass -Force to rely on the per-byte checks alone.") -f $build.Id, $build.OriginalName
    }
    Write-Warning "SHA-256 does not match the untouched original; continuing because -Force was given (every edit is still byte-checked)."
}
Write-Host ("build : {0}" -f $build.Title)
$mode = Resolve-Mode $build $Resolution
if ($mode) { Write-Host ("screen: {0}" -f (Format-ModeLabel $mode (Get-MonitorSize))) }

$available = @(Get-BuildPatches $build $mode)
if (-not $Output) { $Output = Join-Path (Split-Path $origPath) $build.OutputName }
$gameDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($Output))
$unavailable = Get-UnavailableFixes $build $gameDir $mode
if ($All) {
    # every fix whose resources are in the target folder; the others are skipped and reported
    $chosen = @()
    foreach ($p in $available) {
        if ($unavailable.ContainsKey($p.Id) -and -not $IgnoreMissingData) {
            Write-Host ("skipping [{0,-10}] {1,-45} RESOURCES NOT FOUND: {2}" -f $p.Id, $p.Name, $unavailable[$p.Id]) -ForegroundColor DarkYellow
        } else {
            $chosen += $p
        }
    }
    if ($chosen.Count -eq 0) { throw 'nothing to apply: no fix has its resources in the target folder' }
} else {
    # accept -Patches a,b,c from a PowerShell prompt (array) as well as "a,b,c" / "a b c" from cmd / -File (one string)
    $chosen = @()
    foreach ($id in @($Patches | ForEach-Object { $_ -split '[\s,]+' } | Where-Object { $_ })) {
        $p = $available | Where-Object { $_.Id -eq $id }
        if (-not $p) { throw "unknown patch id '$id' for $($build.Id); valid: $(($available | ForEach-Object { $_.Id }) -join ', ')" }
        $chosen += $p
    }
}
if ((Test-Path $Output) -and -not $Overwrite) { throw "output '$Output' exists; pass -Overwrite to replace it" }
if ((Test-Path $Output) -and ((Resolve-Path $Output).Path -eq $origPath)) { throw 'refusing to overwrite the original' }

$problems = @(Get-DataProblems $build $chosen $gameDir $mode)
if ($problems.Count -gt 0) {
    foreach ($pr in $problems) { Write-Warning $pr }
    if (-not $IgnoreMissingData) {
        throw ("nothing written: the chosen fixes need data files or other fixes that are not there (see the warnings above). " +
               "An exe written anyway fails at start-up or draws garbage. Write it into the game folder from the repository, " +
               "or pass -IgnoreMissingData if you know what you are doing.")
    }
    Write-Warning 'continuing because -IgnoreMissingData was given.'
}
Write-Host ''
foreach ($p in @($available | Where-Object { $p = $_; ($chosen | Where-Object { $_.Id -eq $p.Id }) })) {
    Write-Host ("applying [{0,-10}] {1,-52} {2,3} edits" -f $p.Id, $p.Name, (Get-EditCount $p))
}
$r = Invoke-PatchRun $origPath $build $chosen $Output $mode
Write-Host ''
Write-Host ("output: {0}" -f $Output)
Write-Host ("        {0} bytes, SHA-256 {1}" -f $r.Size, $r.Sha256)
foreach ($gl in @($r.Generated)) { Write-Host ("        " + $gl) }
if ($r.Complete) {
    if ($r.Published) { Write-Host '        byte-identical to the executable published in the repository.' -ForegroundColor Green }
    elseif ($r.Matches) { Write-Host ("        byte-identical to the reference build for {0} (every fix of that resolution)." -f $mode) -ForegroundColor Green }
    else { Write-Warning 'all patches applied but the SHA-256 differs from the reference build - report this.' }
} else {
    Write-Host ("        {0} of {1} patches applied ({2}); a partial build has no published reference hash." -f $r.Applied.Count, $available.Count, (($r.Applied | ForEach-Object { $_.Id }) -join ', '))
    $skipped = @($available | Where-Object { $p = $_; -not ($r.Applied | Where-Object { $_.Id -eq $p.Id }) -and $unavailable.ContainsKey($p.Id) } | ForEach-Object { $_.Id })
    if ($skipped.Count -gt 0) { Write-Host ("        not applied, resources not found: {0}" -f ($skipped -join ', ')) -ForegroundColor DarkYellow }
}
