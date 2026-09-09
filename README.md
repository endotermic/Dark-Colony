# Dark-Colony
Dark Colony - real time strategy released in 1997

Repository contains:
1) working copy of the original game
2) working copy of standalone expansion pack
3) working copy of map editor
4) decompilation project (Ghidra decompiler 11.4.2)
5) tools in `tools/` (`spr.py`: reader/writer for the `.SPR` sprite container - extract cells to PNG, rebuild, verify)
6) reverse-engineering notes in `docs/`
   - `DC16_BATTLE_ENGINE.md`: combat core of `dc16.exe` - balance tables, targeting, firing, projectiles, damage, upgrades, day/night
   - `DC16_DISPLAY_AND_RESOLUTION.md`: display pipeline (DirectDraw, software blitters, HUD geometry, mouse, movies), every resolution-dependent code site, and the staged plan for 1024x768

The purpose of this repository is to make this old game better by some assembly tweaks:
1) (TODO) increase screen resolution from 640x480 to 800x600 and maybe to 1024x768 - plan and code-site inventory in `docs/DC16_DISPLAY_AND_RESOLUTION.md` (recommends going straight to 1024x768)
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

