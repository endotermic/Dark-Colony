# Dark-Colony
Dark Colony - real time strategy released in 1997

Repository contains:
1) working copy of the original game
2) working copy of standalone expansion pack
3) working copy of map editor
4) the patch tools (`patch_resolution.py`, `patch_cursor.py`, `hud_layout.py`, `pad_background.py`, `spr.py`, `logo_art.py`, `paint_intro.py`) and the reverse-engineering notes (`DC16_BATTLE_ENGINE.md`, `DC16_DISPLAY_AND_RESOLUTION.md`) live in the sister repository [Dark-Colony-Server](https://github.com/endotermic/Dark-Colony-Server) since 10 Sep 2026: [`tools/`](https://github.com/endotermic/Dark-Colony-Server/tree/main/tools) and [`docs/`](https://github.com/endotermic/Dark-Colony-Server/tree/main/docs), next to the network-protocol notes and the relay server. This repository keeps only the game files. The tools take the game directory or executable as an argument, e.g. `python ../Dark-Colony-Server/tools/patch_cursor.py verify "DC - Classic/dc16.exe"`.

The purpose of this repository is to make this old game better by some assembly tweaks:
1) (DONE) increase screen resolution from 640x480 to 1024x768 - both `DC - Classic/dc16.exe` and `DC - Council wars/DCEXP16.EXE` (the expansion executable, renamed from `ENGEXP16.EXE` on 10 Sep 2026) in this repository are patched, together with their interface data; everything is in Dark-Colony-Server `docs/DC16_DISPLAY_AND_RESOLUTION.md` (going straight to 1024x768; 800x600 is not a power of two and would need real multiplies)
   - the battlefield is **28x23 tiles = 896x736**, 2.9x the stock view area; the HUD keeps its native pixel size on the right and bottom edges (`INTRFACE.GIF` and `MAINE` rebuilt by `hud_layout.py`)
   - the 30 menu screens, the loading screens and the briefing-globe markers are letterboxed by `pad_background.py`; the 44 code-positioned menu elements follow in the exe
   - the main menu (`bintroe`) is painted full-frame at 1024x768 by `paint_intro.py` (starfield and Mars limb re-rendered from the stock picture's measured geometry, richer surface, same palette; the code-positioned credits box follows via two patcher fixups); the title is re-set with a bevelled, brushed surface by `logo_art.py`, the DC mark is the original art on black - doc section 10.11
   - movies are stretched across the full width at 16:9 through a rerouted frame path, which also removes the stock player's skipped scanlines
   - the exe patch is 165 byte-checked edits per binary (`patch_resolution.py`); the stock executables are in the git history (last stock commit `0307feb`) and `verify` tells the two apart
   - not covered: the map editor (the unrelated `dc16.exe` build that shipped in the Council Wars folder was removed from the repository on 10 Sep 2026, together with the Ghidra project; both are in the git history before that commit)
2) (DONE) remove the CD check to play campaign
   - (DONE 10 Sep 2026) the Windows pointer no longer flickers over the game cursor (arrow on the loading screen, block on the menu and in battle): `patch_cursor.py`, 4 code sites + 7 relocation entries per exe, both repository exes patched - doc section 10.12
3) (TODO) increase quality of movies
4) (DONE) tweak multiplayer to be modern and online: see project [Dark-Colony-Server](https://github.com/endotermic/Dark-Colony-Server)
5) (DONE) fix original map editor
6) etc.

Greatest thing I would like to do:
1) (TODO) create third race from artifacts (there are enough of them to do that)
2) (TODO) maps are always randomly generated according to pattern rules you set
3) (TODO) map of whole Mars planet is interactive and contains huge amount of battles with AI or online players

Feel free to contact me and provide info, code or patches.

Official fan site:
www.darkcolony.pl
(I am not an admin of this site! Mentioning it for the newcomers.)

