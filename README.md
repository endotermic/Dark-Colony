# Dark-Colony
Dark Colony - real time strategy released in 1997

Repository contains:
1) working copy of the original game
2) working copy of standalone expansion pack
3) working copy of map editor
4) tools in `tools/`
   - `patch_resolution.py`: raises the screen resolution of `dc16.exe` / `DCEXP16.EXE` (verify / plan / apply, staged, byte-checked, keeps a `.bak`)
   - `hud_layout.py`: scaffolding for redrawing the in-game HUD frame - region geometry, tracing layers, a target-resolution template, and the `MAINE` widget transform
   - `pad_background.py`: letterboxes the interface screens into a larger framebuffer - pads the background `.GIF`, sets the bounds rect and shifts every widget (plan / apply / revert)
   - `spr.py`: reader/writer for the `.SPR` sprite container - extract cells to PNG, rebuild, verify
   - `logo_art.py`: re-sets the main-menu DARK COLONY title (Impact, lit bevel, brushed surface, palette colours) and rebuilds `DCUT.SPR`; the DC mark stays the original art
   - `paint_intro.py`: repaints the main-menu backdrops `INTRG.GIF` / `INTRO.GIF` at any framebuffer size from measured geometry (procedural stars and planet, fixed palette), re-bakes the backdrop into the logo animations `DCUK.SPR` / `DCSS.SPR` / `DCUT.SPR`, and lays the menu scripts out for the new canvas (render / plan / apply / preview)
5) reverse-engineering notes in `docs/`
   - `DC16_BATTLE_ENGINE.md`: combat core of `dc16.exe` - balance tables, targeting, firing, projectiles, damage, upgrades, day/night
   - `DC16_DISPLAY_AND_RESOLUTION.md`: display pipeline (DirectDraw, software blitters, HUD geometry, mouse, movies), every resolution-dependent code site, and the staged plan for 1024x768

The purpose of this repository is to make this old game better by some assembly tweaks:
1) (DONE) increase screen resolution from 640x480 to 1024x768 - both `DC - Classic/dc16.exe` and `DC - Council wars/DCEXP16.EXE` (the expansion executable, renamed from `ENGEXP16.EXE` on 10 Sep 2026) in this repository are patched, together with their interface data; everything is in `docs/DC16_DISPLAY_AND_RESOLUTION.md` (going straight to 1024x768; 800x600 is not a power of two and would need real multiplies)
   - the battlefield is **28x23 tiles = 896x736**, 2.9x the stock view area; the HUD keeps its native pixel size on the right and bottom edges (`INTRFACE.GIF` and `MAINE` rebuilt by `hud_layout.py`)
   - the 30 menu screens, the loading screens and the briefing-globe markers are letterboxed by `pad_background.py`; the 44 code-positioned menu elements follow in the exe
   - the main menu (`bintroe`) is painted full-frame at 1024x768 by `paint_intro.py` (starfield and Mars limb re-rendered from the stock picture's measured geometry, richer surface, same palette; the code-positioned credits box follows via two patcher fixups); the title is re-set with a bevelled, brushed surface by `logo_art.py`, the DC mark is the original art on black - doc section 10.11
   - movies are stretched across the full width at 16:9 through a rerouted frame path, which also removes the stock player's skipped scanlines
   - the exe patch is 165 byte-checked edits per binary (`patch_resolution.py`); the stock executables are in the git history (last stock commit `0307feb`) and `verify` tells the two apart
   - not covered: the map editor (the unrelated `dc16.exe` build that shipped in the Council Wars folder was removed from the repository on 10 Sep 2026, together with the Ghidra project; both are in the git history before that commit)
2) (DONE) remove the CD check to play campaign
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

