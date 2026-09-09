# Dark-Colony
Dark Colony - real time strategy released in 1997

Repository contains:
1) working copy of the original game
2) working copy of standalone expansion pack
3) working copy of map editor
4) decompilation project (Ghidra decompiler 11.4.2)
5) tools in `tools/`
   - `patch_resolution.py`: raises the screen resolution of `dc16.exe` / `ENGEXP16.EXE` (verify / plan / apply, staged, byte-checked, keeps a `.bak`)
   - `hud_layout.py`: scaffolding for redrawing the in-game HUD frame - region geometry, tracing layers, a target-resolution template, and the `MAINE` widget transform
   - `pad_background.py`: letterboxes the interface screens into a larger framebuffer - pads the background `.GIF`, sets the bounds rect and shifts every widget (plan / apply / revert)
   - `spr.py`: reader/writer for the `.SPR` sprite container - extract cells to PNG, rebuild, verify
6) reverse-engineering notes in `docs/`
   - `DC16_BATTLE_ENGINE.md`: combat core of `dc16.exe` - balance tables, targeting, firing, projectiles, damage, upgrades, day/night
   - `DC16_DISPLAY_AND_RESOLUTION.md`: display pipeline (DirectDraw, software blitters, HUD geometry, mouse, movies), every resolution-dependent code site, and the staged plan for 1024x768

The purpose of this repository is to make this old game better by some assembly tweaks:
1) (IN PROGRESS) increase screen resolution from 640x480 to 1024x768 - plan and code-site inventory in `docs/DC16_DISPLAY_AND_RESOLUTION.md` (going straight to 1024x768; 800x600 is not a power of two and would need real multiplies)
   - the 1024x768 display mode runs, and the menus letterbox correctly (`patch_resolution.py --stage 2` + `pad_background.py`)
   - the full-size battlefield runs: **28x23 tiles = 896x736**, 2.9x the stock view area (`patch_resolution.py --stage 3`). The blocker was a lightmap that `draw_terrain` keeps on its own stack frame, sized for one screen; the patcher now grows that frame (11 code sites + the PE header's stack reserve/commit) - sections 10.4 and 10.5 of the display doc. Its 144-byte row stride turned out to need no change (overflowing columns only hit cells the algorithm never uses)
   - verified as a crash test on the attract-mode demo map; lighting at the right edge of a wide view is argued, not yet eyeballed
   - the HUD frame still has to be repainted for the full-size view (`hud_layout.py` is the scaffolding)
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

