# Dark Colony `dc16.exe` — Battle Engine

Reverse-engineering notes on the simulation core of Classic `dc16.exe` (`DC - Classic/dc16.exe`,
MD5 `aa0a646b1234d1d9815a2b7480fd080b`, Watcom-linked PE32): how the balance tables in
`GAMESTAT/` are loaded, how units acquire targets, turn and fire, how projectiles fly and explode,
how damage, armour, upgrades, healing and day/night are computed, how the per-object state
machine that drives all of this is scheduled every tick (§1–§13), how units move and find paths
(§14), how buildings are placed and units produced (§15), what the lockstep checksum covers (§16),
and how the computer players work (§17).

All addresses are virtual addresses in Classic `dc16.exe` (`VA = file_offset + 0x400C00` for
code, `VA = file_offset + 0x402800` for `DGROUP`). The Council Wars `ENGEXP16.EXE` (renamed `DCEXP16.EXE` on 10 Sep 2026) is the same
code base with slightly different addresses; nothing below was re-verified there. Source file
names come from assert strings embedded in the binary (`loader.c`, `mobiles.c`, `missile.c`,
`collide.c`, `ticker.c`, `results.c`, `krusty_*.c`).

Calling convention is Watcom register-based: the first four arguments are passed in
`eax, edx, ebx, ecx`, further arguments on the stack. "gs" is the game-state block that every
simulation function receives in `eax`; "obj" is a 16-bit index into the object array.

Facts marked **(verified)** were read directly from the disassembly; facts marked *(inferred)*
are consistent with the code and the data files but were not traced to the end.

---

## 1. Overview

```
GAMESTAT/*.TXT ──loader.c──► object_types[130]   (0x50FCF8, 280 B each)
                            weapon_types[80]    (0x50E678,  72 B each)
                            boom_types[15]      (0x50DE80, 136 B each)   blast + scatter matrices
                            magic_bullet[9][10] (rows via 0x518B30)      weapon class × armour class %

game_tick (0x419978), once per lockstep tick
 ├─ day/night counters, vision masks, income, stats
 ├─ for every live object: dispatcher 0x4194DC
 │     ├─ special-charge regen, link/berserk countdowns, blood/anim
 │     └─ run state_table[top-of-stack](gs, obj, info) until it returns 0
 │           idle/guard 0x414B9C ─► find target in range 0x435D5C / wider search 0x4356C8
 │                               ─► fire_weapon 0x413018 ─► create_missile 0x44192C
 │           move state 6 0x415A94 ─► path nibbles from path.c (0x444B34) ─► step state 5
 │           building idle 0x41460C ─► production queues ─► create_object 0x41B930
 ├─ update_missiles 0x442610: move, collide 0x4350D4, arc, expire
 │     ├─ single-target hit ─► apply_damage 0x441B4C
 │     └─ area weapon ─► detonate 0x441E08 ─► apply_damage per tile (blast matrix)
 │                       burning ground 0x4423D0 (napalm/plasma)
 ├─ sync checksum 0x44ABC0 → history, AI turn 0x41AE38 (one AI player per 4 ticks)
 └─ (death) object_die 0x4165A0 ─► corpse state 0xA for 150 ticks
```

Everything is integer arithmetic; percentages are stored as 8.8 fixed point (`pct * 256 / 100`).
Positions are 16-bit, 256 units per map tile (`x >> 8` is the tile). Time is the lockstep tick
(default 66 ms, see the network protocol document in Dark-Colony-Server).

---

## 2. Balance tables and their in-memory structures

### 2.1 `GAMESTAT/WEAPSTAT.TXT` → `weapon_types[]` at `0x50E678` **(verified)**

Loader `0x43B6EC`. First line = number of weapons (assert `0 < weapons < 80`, `NUMWEAPTYPES = 80`).
Each data line is parsed with `sscanf(line, "%s %d %d %d %d %d %d %d %d %d %d %d", ...)` after the
leading weapon number (assert `0 <= number < 80`). Comment lines start with `%`; lines shorter than
4 characters are skipped. Record size 0x48 = 72 bytes.

| Offset | Type | File column (after the sprite name) | Meaning |
|---|---|---|---|
| `+0x00` | int | 1 `weapon_class` | row of the magic-bullet matrix (assert `< num_weapons`) |
| `+0x04` | int | 2 `sound` | sound id played when fired (`0x431F60`) |
| `+0x08` | int | 3 `rate_of_fire` | ticks the shooter waits after a shot (cooldown state 0xB) |
| `+0x0C` | int | 4 `damage` | base damage |
| `+0x10` | int | 5 `speed` | projectile speed in position units per tick (256 = one tile) |
| `+0x14` | int | 6 `range` | range in tiles; also the auto-engage search radius |
| `+0x18` | int | – | computed: `(((range<<8) + 0x400) * 2 + 1) / (2*speed) + 1` = maximum flight ticks (range plus 4 tiles) |
| `+0x1C` | int | 7 (unnamed in the header) | blast type = index into `boom_types` (0 = single target) |
| `+0x20` | int | 8 `shots` | shots per burst (`-1` = no burst logic) |
| `+0x24` | int | 9 `reload` | cooldown after a full burst instead of `rate_of_fire` |
| `+0x28` | byte | 11 (unnamed) | one-shot special: after firing, the shooter's special charge `obj+0x0A` is zeroed |
| `+0x2C` | sprite* | – | `<name>BULLET` sprite if `<name>BULLET0` exists, else NULL (no bullet drawn) |
| `+0x30..+0x3C` | sprite*[4] | – | explosion sprites: `<name>EXPLODE` / `<name>EXPL`, otherwise the blast type's sprites |
| `+0x40` | int | – | number of explosion sprites (0 = no explosion animation) |
| `+0x44` | byte | 10 `magic_chewing` | missile kind (see §7.2): 0 bullet, 1 ballistic arc, 2 smoke trail, 3 ground-hugging, 4 burning area, 5–7 drop-ship packets, 8–10 abduction packets |

The header comment in the file lists ten names for eleven numbers; the unnamed 7th column is the
blast type and the last column is the one-shot flag.

### 2.2 `GAMESTAT/GAMESTAT.TXT` → `object_types[]` at `0x50FCF8` **(verified)**

Loader `0x43BB80`. First line = number of object types (assert `0 < objects <= 130`,
`NUMOBJTYPES = 130`; count stored at `0x518B34`). `sscanf` with `"%s"` + 32 × `"%d"`.
Record size 0x118 = 280 bytes. The file header (`Sprite Turn Speed ObsD ObsN Weap Def Health
xsiz ysiz fly signature`) is stale; the real column order is:

| Offset | Column | Meaning |
|---|---|---|
| `+0x00` | 32 (byte, `!= 0`) | scenery flag: lights, towers, fuel, beacons; never a target |
| `+0x04` | 1 | race: 0 human, 1 alien, −1 neutral. Drives the day/night damage penalty |
| `+0x08` | 2 | turn speed, heading units (1/256 turn) per tick |
| `+0x0C` | 3 | move speed (0 = immobile: buildings, deployed towers) |
| `+0x14` | 4 | `ObsD` day vision radius (tiles) |
| `+0x10` | 5 | `ObsN` night vision radius |
| `+0x18`,`+0x1C`,`+0x20` | 6,7,8 | weapon index for weapon-upgrade level 0/1/2 (−1 = unarmed) |
| `+0x24` | – | computed `25600/100 = 256` → armour multiplier for armour level 0 |
| `+0x28`,`+0x2C` | 9,10 | armour percentages (125, 150 for all combat units); replaced in memory by `25600/col` → 204 and 170 (= damage × 0.80, × 0.67) |
| `+0x30[8]` | – | per-player **weapon upgrade level** (0..2), selects the weapon slot |
| `+0x38[8]` | – | per-player **armour upgrade level** (0..2), selects the multiplier |
| `+0x40` | 11 | defence class = column of the magic-bullet matrix (assert `< num_armours`) |
| `+0x44` | 12 | hit points |
| `+0x48..+0x57` | – | sprite bounding box (from the STAND sprite); ground units are widened to at least ±96 |
| `+0x60` | 13 (byte) | flying (1; 7 for the `DOTT` vision marker) |
| `+0x64` | 14 | "signature", 5-bit value (31/15/7/1/0); stored into `obj+0x10` together with the attacker's team when the unit fires at a target *(inferred: under-attack indicator duration)* |
| `+0x68` | 15 | hidden object (mines): visible to a team only after detection (`obj+0xCA` team bit) |
| `+0x6C` | 16 | commando / engineer flag (SARG, PSYC, ENGI, SLOM, stealing variants) |
| `+0x70`,`+0x74` | 18,19 | healer flags (BEON, ZISP) |
| `+0x78` | 17 | footprint handle from `0x454AA0(type)` for static structures (artifact site, vent, towers) *(inferred)* |
| `+0x7C`,`+0x80` | – | MOVE sprite (mobile types only), STAND sprite |
| `+0x84`,`+0x88` | – | SCRCH, BURN sprites (fallbacks: SCRCH, STAND) |
| `+0x8C`,`+0x94`,`+0x98`,`+0x9C` | – | FIG, DEPLOY, BUILD/BUILDSTAND, FUNK sprites (fallback STAND) |
| `+0xA0..+0xA8`, `+0xE4` | – | FIRE / FIREA / FIREB / FIREC firing animations and their count (fallback STAND) |
| `+0xAC..+0xB4`, `+0xE8` | – | DIE / DIEA / DIEB / DIEC death animations and their count |
| `+0xBC[7]`, `+0xD8` | – | BLOODA.. blood overlays and their count |
| `+0xDC` | 20 | set for workers and artillery (EXPL, SLUG, BARR, ATRIL) *(inferred: must stand still to work/fire)* |
| `+0xE0` | 22 | 0/32/96/128/160/216 *(not traced; probably palette/colour index)* |
| `+0xEC` | 21 | 0..3 *(not traced; unit class for UI/AI)* |
| `+0xF0` | 23 | flyer flag used by some paths (scouts, healers, drop ships) |
| `+0xF4` | 24 | 2 for buildings, 1 for SARG/PSYC, 12/28/44/60 for the four commander ranks *(not traced)* |
| `+0xF8` | 25 | **special-charge regeneration** per 32 ticks (4 cyborg/psy-raider, 1 healers and commanders) |
| `+0xFC` | 26 | commander damage bonus, stored as `(col<<8)/100` (130..160 % for lieutenant..colonel) |
| `+0x100` | 27 | commander rally size: number of units that receive the bonus (6/8/10/12) |
| `+0x104` | 28 | deploy-ability code (protocol doc table `0x50FDFC`): 2 tower builders, 3 mine layers, 5 cyborg/psy-raider, 7 mining towers/artifacts, 196 commanders |
| `+0x108`, `+0x10C` (byte) | 29 | targeted-special parameter and "has targeted special" flag (protocol doc table `0x50FE04`) |
| `+0x110` | 30 | special weapon index (50 napalm, 51 plasma, 57–60/63/64 drop-ship and abduction packets) |
| `+0x114` | 31 | counterpart type of the other race (TRSC↔GRAY, REAP↔SCYT, …), −1 if none |

### 2.3 `GAMESTAT/MBULLET.TXT` → magic-bullet matrix **(verified)**

Loader `0x43B150`. Line 1 = `num_armours` (10, `0x518B28`), line 2 = `num_weapons` (9,
`0x518B2C`). `0x518B30` points to an array of `num_weapons` row pointers, each row `num_armours`
× `int16`; every entry is `round(pct * 0.01 * 256)`, i.e. 8.8 fixed point. Rows are weapon classes
(0 warrior, 1 scythe/melee, 2 air, 3 artillery, 4 psy, 5 turret, 6 mine, 7 healing ray,
8 ultimate artifact), columns are defence classes (0 warrior, 1 scythe, 2 air, 3 atril, 4 psy,
5 bot, 6 tower, 7 mine, 8 invulnerable, 9 building). A zero entry means "cannot hurt" and also
makes the target ineligible for auto-targeting (§5); column 2 (air) decides whether a projectile
collides with flying objects (§5). Row 7 is used by healers (§9).

### 2.4 `GAMESTAT/BOOMSTAT.TXT` → `boom_types[]` at `0x50DE80` **(verified)**

Loader `0x43B424`. Line 1 = count (assert `0 < booms < 15`, `NUMBLASTTYPES = 15`). Each entry:
`index size`, then sprite names terminated by `NONE`, then a `size × size` matrix, then a `3 × 3`
matrix. Record size 0x88 = 136 bytes:

| Offset | Meaning |
|---|---|
| `+0x00` | `sprite*[4]` explosion sprites (used when the weapon has no own EXPLODE sprite) |
| `+0x10` | byte `size` (1..7, odd) |
| `+0x12` | `int16[7][7]` **blast matrix**, `(pct<<8)/100`, row stride 14 bytes: damage fraction per tile around the impact |
| `+0x74` | `int16[3][3]` **scatter matrix**, `(pct<<8)/100`: probability that a shot lands on the tile offset (dx−1, dz−1) from the aim point |

Blast type 0 ("regular weapon") has size 1 and matrix `100`; its scatter matrix
`3 10 3 / 10 48 10 / 3 10 3` is unused because single-target weapons do not scatter (§6).
Types 1 and 9 (artillery, 5×5, centre 100 %, edges 10 %) and 2/10/11/12 (mines, napalm, LENS, bees:
7×7) have exact-aim scatter matrices (`0 0 0 / 0 100 0 / 0 0 0`).

### 2.5 `GAMESTAT/DEPEND.TXT` and upgrades

Items of kind 2 (`2 <unit_type> <0=weapon|1=armour> <level>`) are upgrades. Buying one makes the
client send in-game command `0x0C` (`which, player, value, slot`; handler `0x41CBD4`) **(verified)**:
`which == 0` writes `object_types[slot].weapon_level[player] = value` (`+0x30`), `which == 1`
writes `armour_level[player] = value` (`+0x38`); the cost `1000 * value` is booked to the player's
money accounts. Levels are therefore global per (player, unit type) and take effect immediately for
every existing unit of that type. Research command `0x09` (`0x41CAA4`) handles the other item kinds.

---

## 3. Runtime structures

### 3.1 Game state (`gs`) fields used by combat **(verified)**

| Offset | Meaning |
|---|---|
| `gs+0x000` | byte, non-zero disables commander specials and hero-death effects *(inferred: network/multiplayer flag)* |
| `gs+0x528` | per-player unit cap, recomputed every tick by `0x41E7FC` from the 800-object pool |
| `gs+0x52C` | game time in ticks |
| `gs+0x530` | day/night phase counter; `gs+0x534` phase length; `gs+0x538` dawn/dusk length; `gs+0x53C` phase (0 day, 1 night); `gs+0x540` light level 0..256 |
| `gs+0x544` | scenario block; `[+0x14F0]` = game type |
| `gs+0x94C` | tick counter used for the 16-tick housekeeping and the sync checksum |
| `gs+0x994` | `int16[256]` checksum history indexed by `tick % 256` (§16) |
| `gs+0xB94` | AI game state pointer (§17) |
| `gs+0xCA0 + p*0xE34` | player block `p` (stride 0xE34; offsets below are gs-relative for player 0): `+0xBAC` money, `+0xBB0` total spent, `+0xBB8` race, `+0xBBC` AI type (0 human, 1–4 personality), `+0xBC4` krusty state, `+0xBC8/+0xBCC` city origin tile, `+0xBD8[15]` building slot hit points (0 = not built), `+0xC14[15]` slot blocked flags, `+0xC60[15]` slot levels, `+0xCA4[4]` production class ready flags, `+0xCA8[4]` unused countdowns, `+0xCAC[4]` `int16` queue lengths, `+0xCB4[4][800]` queue entries, `+0x1936[4]` hero/commander object indices, `+0x1940[110]` disabled DEPEND items, `+0x19B8` income, `+0x19BC` AI income multiplier (0x100/0x200), `+0x19C4` vision mask (bit `30−q` = sees what player q sees) |
| `gs+0x46F4C` | pointer to the map (§3.4) |
| `gs+0x46F54 + a*10 + b` | alliance byte between teams a and b (10×10) |
| `gs+0x7D3C` | local player index; `gs+0x7D40` highest object index in use; `gs+0x7D44` number of missiles |
| `gs+0x7D48` | object array, 800 × 220 bytes (`MAX_OBJECTS = 800`) |
| `gs+0x32CC8` | missile array, 2024 × 40 bytes (`MAX_MISSILES = 0x7E8`) |
| `gs+0x46908` | int16 free-list head of missiles; `gs+0x4690A` int16 active-list head |
| `gs+0x4690C + obj*2` | int16 per object, −1 when the slot is unused |

Objects 0..119 are the fixed city-building slots (8 players × 15, `BUILDINGS_PER_SIDE = 15`);
objects 120..151 are reserved; units live from 152 (`0x98`) upwards.

### 3.2 Object record (220 = 0xDC bytes, at `gs + 0x7D48 + obj*220`) **(verified unless noted)**

| Offset | Meaning |
|---|---|
| `+0x00` i16 | x position (tile = `x>>8`) |
| `+0x02` i16 | height (flyers, falling wrecks) |
| `+0x04` i16 | z position |
| `+0x06` u8 | object type |
| `+0x07` u8 | team: 0..7 players, 8 unowned (artifacts, vents), 9 wildlife |
| `+0x09` u8 | heading 0..255 (256 steps per turn) |
| `+0x0A` u8 | **special charge** 0..255 (napalm/plasma/drop ship need 255, healers need ≥ 4) |
| `+0x0C` i32 | hit points |
| `+0x10` u8 | `(attacking team << 5) \| countdown` — "under attack by" marker, countdown decremented every tick |
| `+0x12` u8 | selection mask (bit per player) |
| `+0x14`, `+0x1C`, `+0x24` | 8-byte animation slots: body, blood overlay, second overlay (heal beam, BUILD animation of a produced unit) |
| `+0x1A`, `+0x22`, `+0x2A` u8 | status byte of each animation slot (2 = finished, 1 = playing) |
| `+0x2C` u8 | life state: 0 free, 10 corpse ("rotting"), otherwise alive |
| `+0x2E`, `+0x30` i16 | movement destination x, z; `+0x30` also carries the target object id for the attack order |
| `+0x34` u8 | shots fired in the current burst |
| `+0x35` u8 | nudge direction 0..7 (0xFF none): a blocked friendly unit asks this idle unit to step aside (§14.4) |
| `+0x36` u8 | pending order flag; `+0x37` pending order code (set by commands `0x05`/`0x16`) |
| `+0x38` u8 | state-stack pointer (0xFF empty); `+0x39+2k` state id of level k; `+0x3A+2k` info offset of level k (k < 6) |
| `+0x46..+0x85` | state info area, 32 × int16 (`OBJECT_INFO_SIZE = 32`) |
| `+0x86..+0x95` | current path: 32 direction nibbles (§14.3) |
| `+0xA6 + 4i`, `+0xA8 + 4i` i16 | waypoint i (x, z), i < 8; waypoint 0 doubles as the fire-at-ground target; `+0xC6` u8 waypoint count |
| `+0xC7` u8 | damaged flag → spawn blood overlay; `+0xC8`, `+0xC9` set to 1 on damage *(redraw flags, inferred)* |
| `+0xCA` u8 | detected-by-team mask for hidden objects (mines) |
| `+0xCB` u8 | pending build/production order kind (1/2, handled by `0x4143D4`; not traced) |
| `+0xD0` u8 | **berserk countdown** (decremented every 16 ticks): while non-zero the unit targets and hits anyone, allies included; set by the Maktor/Lunatek artifact effects (`0x416ED4`, `0x416FF4`) |
| `+0xD2`, `+0xD4` i16 | AI group list links (next, previous); −2 = never assigned (set at creation), −1 = list end (§17.2) |
| `+0xD6` u8 | **commander link countdown** (every 16 ticks); `+0xD8` i16 linked commander object |

### 3.3 Missile record (40 = 0x28 bytes, at `gs + 0x32CC8 + i*40`) **(verified)**

| Offset | Meaning |
|---|---|
| `+0x00/+0x02/+0x04` i16 | x, z, height |
| `+0x06/+0x08/+0x0A` i16 | velocity per tick in x, z, height |
| `+0x0C` i16 | weapon type; `+0x0E` shooter object |
| `+0x10` i16 | age in ticks; `+0x12` launch delay countdown |
| `+0x14` i16 | next missile in the active list; `+0x16` sound handle (burning ground) |
| `+0x18` i16 | remaining flight ticks for ballistic shots, −1 for direct fire (collision tested every tick) |
| `+0x1A` u8 | facing for the bullet sprite |
| `+0x1C` i16 | state: 0 waiting for launch delay, 1 flying, 2 explosion animation only, 3 burning area, 4 finished |
| `+0x1E` u8 | kind (weapon `+0x44`); `+0x1F` random byte |
| `+0x20` | animation instance |

Missiles are allocated from a free list (`0x4417F0`, assert `number_of_missiles < 2024`) and
linked into a single active list walked by `update_missiles`.

### 3.4 Map grids **(verified)**

`map = [gs+0x46F4C]`; `map+0x9A4B0` / `+0x9A4B4` = width / height in tiles. Three per-cell layers,
each an array of row pointers:

* `map+0x804`: ground layer, `int32` per cell. Low 10 bits = object id, `0x3FF` = empty, `0x3FE` =
  "look in the secondary layer"; bits 23..30 = "currently seen by player q" flags (bit `30−q`).
* `map+0xC04`: air layer, `int16` per cell (flying objects), same id encoding.
* `map+0x1004`: secondary layer, `int16` per cell: mines (engineers turn into mines here, §10.3) and
  burning-ground markers.

Collision and targeting always resolve up to three candidates per cell (ground, air, secondary).
A fourth per-tile structure, the path grid at `map+0x1404`, holds terrain passability and the path
search working data (§14.3).

---

## 4. The object state machine (`ticker.c`, `mobiles.c`)

### 4.1 Stack primitives **(verified)**

* `push_state(gs, obj, state, nwords)` `0x412114`: asserts the object is alive, `sp++` (assert
  `< 6`), stores the state id, allocates `nwords` int16 of info after the previous level's info
  (assert `< 32`), returns a pointer to the info block.
* `pop_state` `0x4122A4`: `sp--`.
* `reset_and_dispatch_order` `0x41233C`: empties the stack; if a pending order is set
  (`obj+0x36`) it is cleared and `order_table[obj+0x37](gs, obj)` is called, otherwise the idle
  state is pushed (`0x41296C`: state 1 with info `{target=-1, hp_snapshot, fidget=0}`).
* `sleep(gs, obj, n)` `0x41258C`: pushes state 3 with `{n, hp}`.
* `set_cooldown(gs, obj, n)` `0x4124F0`: pushes state 0xB with `{n}`.

### 4.2 Dispatch **(verified)**

`game_tick` (`0x419978`) walks objects 0..`gs+0x7D40` in index order and calls `0x4194DC` for
each allocated one. That function, per object and tick:

1. every 32 ticks: `charge (+0x0A) += type.+0xF8`, saturating at 255;
2. every 16 ticks: `+0xD0--` (berserk) and `+0xD6--` (commander link) if non-zero; flying units of a
   player whose HQ slot is gone lose 5 HP (game types 1/2 only) and die at 0;
3. if `+0xC7` is set and the type has blood sprites, start a random BLOOD overlay; advance the three
   animations; decrement the low 5 bits of `+0x10`;
4. `loop: state = stack[sp].state (assert < 23); r = state_table[state](gs, obj, &info); if (r) goto loop`
   (assert fewer than 100 iterations). A handler returns 1 after changing the stack so that the new
   top state runs in the same tick.

State table `0x48942C` (23 entries) — roles identified so far:

| Id | Handler | Role |
|---|---|---|
| 1 | `0x414B9C` | idle / guard: auto-engage, wider search, fidget (§4.3) |
| 2 | `0x41616C` | end-of-move-order marker → reset to idle |
| 3 | `0x4125E0` | sleep `n` ticks; wakes early on a pending order or when hit points change |
| 4 | `0x412670` | turn towards the heading in `info[0]`, pop when aligned (fidget) |
| 5 | `0x4128D4` | sliding one tile: `pos += (vx, vz)` per tick for `info[2]` ticks (§14.4) |
| 6 | `0x415A94` | moving along a path; entered through `begin_move` `0x414FD0` (§14) |
| 7 | `0x416214` | end-of-assault-order marker → reset |
| 8 | `0x4163A0` | waypoint follower for move (mode 0) and assault (mode 1) orders |
| 9 | `0x416434` | patrol: waypoint follower that wraps around, mode 1 |
| 0xA | `0x4166F8` | corpse: death animation, freed after 150 ticks (commanders stay, see §8.3) |
| 0xB | `0x412510` | **weapon cooldown / wait**: shows STAND once the fire animation ended, counts down, pops |
| 0xC | `0x413A88` | harvesting (mining tower on a vent; AI income multiplier applied here, §15.2) |
| 0xD | `0x417DA4` | wait until the current animation finishes, then deploy / undeploy / transform (§10.3) |
| 0xE | `0x41629C` | attack order reached its target → reset (the idle state then auto-engages) |
| 0x11 | `0x4167E0` | falling wreck (flyers): height −= 2·speed per tick, crash animation |
| 0x12 | `0x4182C0` | fire at ground / targeted special (§6.1) |
| 0, 0xF, 0x10, 0x13–0x16 | `0x4194D4`, `0x416DC0`, `0x4177AC`, `0x418A7C`, `0x418978`, `0x418CE0`, `0x418650` | not traced (artifact pickup, stealing commando, worker/vent handling) |

Order table `0x4893D4` (22 entries, indexed by the order byte of network commands `0x05`/`0x16`):
1 → idle, 2 → move along waypoints (`0x4161A0`: state 2 + state 8 mode 0), 7 → assault move
(`0x416224`: state 7 + state 8 mode 1), 9 → patrol (`0x416330`: state 9), 0xD → deploy
(`0x416A1C`), 0xE → attack target (`0x4162AC`: push state 0xE, then `begin_move` mode 3 towards the
object in `obj+0x30`), 0x12 → fire at ground / special at position (`0x418160`); all other entries
are no-ops (`0x4194CC`).

### 4.3 Idle / guard state `0x414B9C` **(verified)**

Runs every tick for every unit that has nothing else to do:

1. `+0xCB` build orders are delegated; a pending order (`+0x36`) resets the stack (return 1).
2. Unarmed types branch to their own idle logic (vents, artifact sites, stealing commandos,
   buildings < 120 → production, healers → `heal_nearby` §9, workers → wait 7 ticks).
3. Armed units: `target = find_target_in_range(gs, obj)` (`0x435D5C` = `find_target` with
   `rings = weapon.range`); the result is stored in `info[0]`.
4. If the unit has a waypoint (`+0x35 != 0xFF`) and is mobile, it keeps moving (`0x412EE0`,
   mode 1 without target, mode 2 with target) instead of standing.
5. **Target in range → `fire_weapon(gs, obj, target)`** every tick; `fire_weapon` itself handles
   turning and pushes the cooldown state after a shot, which suspends this state.
6. No target in range: animation STAND; if `hp < info[1]` (took damage since the last check) the
   search radius grows. Mobile units then run the wider `find_target` with `rings = 4` normally,
   `9` after taking damage, `16` for AI-controlled players and wildlife; **flying units never run the
   wider search** and only engage what is inside weapon range. Buildings and deployed towers (speed
   0) skip the wider search too. A hit sets the destination to the target's tile and calls
   `begin_move(mode 2)` — the unit walks towards it and re-engages from idle on arrival.
7. Otherwise fidget: 1/16 chance to turn to a random heading (`0x412650`, except types with
   column 20 set), then sleep 15 ticks for the first three idle rounds and 45 ticks afterwards.

---

## 5. Target acquisition (`collide.c`)

`find_target(gs, obj, max_ring)` `0x4356C8` **(verified)**:

* Visibility mask: wildlife (team 9) may see everything; players use `player.+0x19C4`, and a cell is
  only considered if `cell & mask` (the cell is currently seen by the searcher's team or an ally with
  shared vision).
* Cells are visited in a fixed spiral table at `0x434200` (`int16 dx, dz` pairs, rings separated by
  `dx == 99`): ring 0 = own tile, ring 1 = 8 neighbours, ring 2 = 16, ring 3 = 20, ring 4 = 24,
  ring 5 = 40, … up to `max_ring`. Each cell yields up to three candidates (ground, air, secondary).
* A candidate is rejected if: it is a hidden object (type `+0x68`) of another team not yet detected
  by the searcher (`+0xCA` bit); it is scenery (type `+0x00`); it is a building slot (< 120) whose
  per-player flag `+0xC14[slot]` is set; its team is 8 or 9 (unowned objects and wildlife are never
  auto-attacked); it is the searcher; it is allied (`gs+0x46F54` matrix) unless the searcher is
  berserk (`+0xD0`); or `magic_bullet[my weapon class][its defence class] == 0` (e.g. ground guns
  vs air).
* Score: 50 for an unarmed type, 150 for an armed type, +200 if it flies. For area weapons
  (`weapon.+0x1C != 0`) every neighbouring occupied tile adds +10 for an enemy and −15 for an ally
  (artillery prefers clusters and avoids friendly fire). For single-target weapons the score is
  multiplied by `((hp <= 0 ? 2048 - hp : 1024) >> 11)`, which is 0 for any living target, so **direct-fire
  units simply take the first candidate in spiral order (the nearest)**; the scoring only matters for
  area weapons, which pick the highest score over all rings searched.

Ring 0 is the searcher's own tile, so `rings = range` covers a Chebyshev radius of `range` tiles.

Projectile collision `0x4350D4(gs, x, z, team, can_hit_air)` **(verified)** examines the 3×3
tiles around the projectile: ground layer always, air layer only when `can_hit_air`
(`magic_bullet[class][2] != 0`), secondary layer for mines; applies the same hidden/scenery/building
filters, excludes the shooter's own team and team 8, tests the candidate's sprite bounding box
(`0x43658C`) and prefers the object in the projectile's own tile.

---

## 6. Firing (`fire_weapon`, `mobiles.c` `0x413018`) **(verified)**

`fire_weapon(gs, obj, obj*, target, tx, tz)` (stack args `tx, tz` are used when `target == -1`).

1. If `target != -1`: return if the target is not alive (`+0x2C == 0`); aim at its position; if its
   team < 8, `obj+0x10 = (target.team << 5) | type.+0x64`.
2. Weapon = `weapon_types[type.weapons[type.weapon_level[obj.team]]]` — the player's weapon
   upgrade level selects slot 0/1/2.
3. `dir = atan2(aim − pos) >> 5` (0..255, `0x4124B8`); `turn(gs, obj, dir)` (`0x412414`) rotates
   the heading by at most `type.turn` per tick towards `dir` and returns non-zero while not aligned —
   **the unit only fires when facing the target**, otherwise the function returns without firing.
4. Firing animation: a random one of the FIRE sprites; `0x426338` reads up to 7 muzzle hotspots
   `(x, z, delay)` for the current facing from that sprite frame (one dummy hotspot at the origin if
   the sprite has none). **One projectile is created per hotspot**, with the hotspot's third value × 4
   as launch delay — this is how multi-barrel volleys are made from sprite data.
5. Scatter (area weapons only, `weapon.+0x1C != 0`): draw `r = rand() & 0xFF`, walk the blast type's
   3×3 scatter matrix cumulatively until `matrix[row][col] > r`; the aim point is shifted by
   `(col−1, row−1)` tiles. Units linked to a commander (`+0xD6 != 0`) always hit the centre.
6. Velocity: `sincos(dir << 5)` from a 2048-scaled quarter-wave table (`0x4897D4`), so
   `vx = sin · speed >> 11`, `vz = cos · speed >> 11` — the projectile moves exactly `speed` position
   units (speed/256 tiles) per tick. Flight ticks `t = max(|dx|,|dz|) / max(|vx|,|vz|)`; a guard
   loop shrinks the step by 5 % while `|v|² > (range·256)²`. Height velocity `vy = dy / t`.
   For blast-type-0 weapons with no height difference `t = -1` (pure direct fire).
7. `create_missile(gs, obj, vx, vz, vy, weapon, t, dir, delay, hotspot dx, dz, kind)`; sound
   `weapon.+0x04`; stat 8 (shots fired) for the owner.
8. Mines (types 45/46) lose 300 HP per detonation, clamped to 1 HP.
9. One-shot specials (`weapon.+0x28`) zero the special charge.
10. Cooldown: if `weapon.shots > 0`: `obj+0x34++`; when it reaches `shots` it is reset and the
    cooldown is `weapon.reload`, otherwise `rate_of_fire`. `set_cooldown` pushes state 0xB, so the
    unit does nothing else (not even move) for that many ticks. Cooldown is applied even when the shot
    is a special.

### 6.1 Fire at ground / targeted specials (order 0x12 → `0x418160`, state 0x12 → `0x4182C0`)

Artillery (BARR, ATRIL) uses its normal weapon; every other type uses its special weapon
`type.+0x110` (cyborg napalm requires research byte `[0x510188 + player] == 2`, psy-raider plasma
`[0x510A48 + player] == 2`, commanders require `gs+0 == 0`). If the target is beyond weapon range the
unit first moves closer (`begin_move` mode 4). The special needs charge 255 and is abandoned if more
than 4 ticks pass; the special weapon is temporarily swapped into the unit's current weapon slot and
`fire_weapon(..., -1, tx, tz)` is called.

---

## 7. Projectiles (`missile.c`)

### 7.1 Update loop `update_missiles(gs)` `0x442610` **(verified)**

For each missile in the active list:

* state 0: count down the launch delay, then state 1.
* state 3: `burn_tick` (§7.4). States 2 and 4 are left alone (animation / removal elsewhere).
* state 1: `pos += velocity` (kind 3 keeps height 0; kind 2 spawns a smoke puff every tick using
  weapon 43 as sprite).
  * Direct fire (`+0x18 == -1`): `hit = collide(gs, x, z, team, can_hit_air)`; the shooter itself and
    allies of the shooter are ignored (a berserk shooter ignores nothing).
  * Ballistic (`+0x18 >= 0`, kinds 1 and 4): height follows a 17-entry arc table (`0x48A9D8`, peak
    640 × total ticks / 64); when the remaining ticks reach 0 the missile detonates where it is.
  * On a hit: if the blast type has `size == 1` (single target) → `apply_damage` with fraction 1.0,
    or the commander bonus of the linked commander's type (`+0xFC`) if the shooter is linked; the
    day/night flag is set when `(shooter race == human && night) || (alien && day)`. The missile then
    plays a random explosion sprite at the victim's position (state 2). Otherwise → `detonate`.
  * Age++; when `age > weapon.max_flight_ticks` or after a hit, a flying missile becomes state 4.

### 7.2 Missile kinds (weapon column 10) **(verified in `detonate`/`update`)**

| Kind | Behaviour | Weapons |
|---|---|---|
| 0 | plain projectile | most guns |
| 1 | ballistic arc, detonates after the computed flight time | artillery 10–12, 24–26 |
| 2 | smoke-trail missile | tower missiles 34–36 |
| 3 | ground-hugging (height forced to 0) | – |
| 4 | leaves a burning area (state 3) instead of an instant blast | napalm 50, plasma 51, 52 |
| 5, 6, 7 | drop-ship packet: spawns preset units at the impact point (`0x4191E0`) | 57, 58, 59 |
| 8, 9, 10 | abduction packet: takes up to 4 / 6 / 8 enemy units near the impact point (`0x4171EC`, `0x4191E0`) | 60, 63, 64 |

### 7.3 Detonation `detonate(gs, m)` `0x441E08` **(verified)**

`boom = boom_types[weapon.+0x1C]`, `half = boom.size / 2`, `(cx, cz)` = impact tile; a sound is
played if the blast type is non-zero. Kind 4 switches to state 3 (burning). Kinds 5–10 spawn units
(see above). Otherwise a random explosion sprite starts (state 2) and every tile
`(cx−half..cx+half, cz−half..cz+half)` inside the map is inspected: the ground-layer object (or the
secondary-layer object behind a `0x3FE` marker) receives
`fraction = boom.matrix[dz+half][dx+half] × (victim.team == shooter.team ? 0x40 : 0x100) >> 8`
→ `apply_damage(gs, victim, weapon, fraction, shooter.team, 0, shooter)`. Friendly fire from area
weapons therefore does **25 %** of the normal blast damage, allies (other teams) take full damage, and
the day/night penalty never applies to blasts. Objects covering several tiles are damaged once per
covered tile.

### 7.4 Burning ground `burn_tick(gs, m)` `0x4423D0` **(verified)**

Runs while `age & 3 == 0` (every 4th tick) for 840 ticks (`0x348`). Empty tiles in the area are
marked `0x3FE`; objects in the area take `apply_damage` with the blast-matrix fraction every 64 ticks
(`age & 0x3F == 0`); a looping sound (id 63) plays. At the end the markers are cleared and the
missile is finished (state 4). Napalm (weapon 50): damage 20 × class-6 multiplier × 7×7 matrix,
so 20 × 164 % = 32 HP per damage pulse at the centre against infantry, 13 pulses in total.

---

## 8. Damage

### 8.1 `apply_damage(gs, victim, weapon*, fraction, attacker_player, night_penalty, killer_obj)` `0x441B4C` **(verified)**

```
mb   = magic_bullet[weapon.weapon_class][type(victim).defence_class]      // 8.8 fixed
d    = (mb * weapon.damage) >> 8
d    = (fraction * d) >> 8                                                 // blast matrix / 1.0 / commander bonus
d    = (d * type(victim).armour_mult[ type(victim).armour_level[victim.team] ]) >> 8   // 256 / 204 / 170
if (night_penalty) d = d * 3 / 4
victim.hp -= d
```

Then `+0xC7`/`+0xC8`/`+0xC9` are flagged (blood, redraw). If `hp <= 0`:

* if `victim.team != attacker_player`: stat 2 (kills) and per-type stat 3 for the attacker (type of
  `killer_obj`); stat 3 (losses) and per-type stat 0 for the victim's owner;
* `object_die(gs, victim)` (`0x4165A0`) and `0x434EB8` (remove from the collision grids);
* if the attacker's first hero (`player.+0x1936[0]`) is within 20 tiles (Manhattan) of the victim,
  stat 11 for the attacker.

### 8.2 Worked examples (Classic tables)

* Security trooper (weapon 1: class 0, damage 100, rate 15) vs Grey warrior (defence 0, 800 HP):
  `MB[0][0] = 25 %` → 25 HP per shot, 32 shots, 480 ticks (≈ 32 s at 66 ms). Against a warrior with
  armour upgrade 1: `25 × 204 >> 8 = 19` → 43 shots. At night the human trooper does 18 → 45 shots.
* Thunderbolt mortar (weapon 10: class 3, damage 250, rate 75, blast 1) vs warrior: `MB[3][0] = 100 %`
  → 250 at the centre tile, 187 / 125 / 62 / 25 on the 75 / 50 / 25 / 10 % tiles; 4 direct hits.
* Scythe demon (weapon 21: class 1, damage 100, range 1) vs trooper: `MB[1][0] = 100 %` → 100 per hit.
* Mine (weapon 38: class 6, damage 1300, blast 2 = 7×7) vs infantry: 164 % → 2132 at the centre;
  vs a building (defence 9): 2 % → 26.

### 8.3 Death `object_die(gs, obj)` `0x4165A0` **(verified)**

Sets `+0x2C = 10` (corpse), clears the stack, removes the selection bit, for building slots clears
`player.+0xBD8[slot]` and recomputes dependencies (`0x437D00`), plays the type's death sound.
Commander types (`+0x100 != 0`) in single-player trigger `0x4191E0` (hero-death event). State 0xA
then plays a random DIE sprite (commanders: the FUNK pose, and their corpse never expires); after 150
ticks the slot is freed (`+0x2C = 0`, `gs+0x4690C[obj] = -1`). Flyers instead enter state 0x11 and
fall (`height −= 2·speed` per tick) before the crash animation.

---

## 9. Healing (`heal_nearby`, `0x413F24`) **(verified)**

Called from the idle state of healer types (49 BEON, 50 ZISP) while `charge (+0x0A) >= 4`. Scans an
expanding square (up to 8 rings, ground and air layers) for same-team objects that are alive and
not at full health:

```
missing = type(target).hit_points - target.hp          (assert >= 0)
rate    = (magic_bullet[7][type(target).defence_class] * 36) >> 8   // 36 HP at 100 %, 18 at 50 %, 72 for buildings (200 %)
heal    = min(rate, missing);  target.hp += heal;  stat 9 += heal
```

Any heal action sets the healer's charge to 0, so with regeneration 1 per 32 ticks (`+0xF8 = 1`)
a healer heals once per ~128 ticks. The healer plays its DEPLOY animation (state 0xD, back to idle
when it ends); the target shows the healer's FIRE sprite as an overlay.

---

## 10. Special abilities, links and transformations

### 10.1 Special charge **(verified)**

`obj+0x0A` grows by `type.+0xF8` every 32 ticks up to 255. Napalm / plasma / drop ship / abduction
need 255 and reset it to 0 (weapon one-shot flag); healers need 4. Heroes of a player whose unit count
has reached the cap `gs+0x528` are held at 230 every tick so they cannot call reinforcements.

### 10.2 Commander rally (`0x417400`, reached from state 0xD for types with `+0xFC != 0`) **(verified)**

When a commander (types 69–76) executes its deploy order it zeroes its charge and searches a
spiral of radius 10 for same-team armed units that are not commanders themselves; the first
`type.+0x100` (6 / 8 / 10 / 12) of them get `+0xD6 = 20 + (rand & 15)` (decremented every 16 ticks,
i.e. 320..560 ticks) and `+0xD8 = commander`. Linked units deal `type(commander).+0xFC` (130..160 %)
instead of 100 % on single-target hits and never scatter area shots.

### 10.3 Deploy / undeploy transformations (state 0xD, `0x417DA4`) **(verified)**

After the animation finishes the object type is swapped: tower builder 1 (TURR) ↔ 41 (T, human
tower), 9 (XENO) ↔ 42 (XDEPLOY), cyborg 4 ↔ 77 (stealing mode), psy-raider 12 ↔ 78, exploiter 6 ↔ 47
(mining tower), slug 14 ↔ 48; engineers 43/44 become mines 45/46 and are written into the secondary
map layer (hidden until detected). Artifacts have their own effects here: LENS (63) fires weapon 46
(8000 damage, blast 11) and dies (suicide bomb), MAKT (64) → `0x416ED4` and LUNA (65) → `0x416FF4`
set the berserk countdown `+0xD0` on nearby units, TEKT (67) → `0x417644`, HYYK (66) → `0x417A6C`.

---

## 11. Day, night and vision **(verified)**

The scenario header (`*.SCN`, text) carries `phase / phase_length / counter / dawn_length`
(`D8PLAY01.SCN`: `0 5400 225 225`) into `gs+0x53C / +0x534 / +0x530 / +0x538`. Each tick
`gs+0x530++`; when it exceeds the phase length it restarts and `gs+0x53C ^= 1` (0 = day, 1 = night).
During the first `dawn_length` ticks of a phase the light level `gs+0x540` fades linearly
(256 → 0 at dawn, 0 → 256 at dusk, treated as a darkness amount by the renderer). Effects on combat:

* **Damage penalty**: human single-target hits at night and alien single-target hits by day do 75 %
  (`missile.c` `0x4429D5`). Area blasts, burning ground and healing are unaffected.
* **Vision radius** (`0x44A7C0`, every 16 ticks): `radius = (ObsN × darkness + ObsD × (256 − darkness)) >> 8`
  per object; the seen-by flags it writes into the ground layer gate all auto-targeting (§5).

---

## 12. Determinism

All randomness in combat comes from `rand()` `0x4120F0`: a 256-entry table of pre-generated values
(`0x488F20`, 0..32767) walked by the byte index at `0x489320`. Because every machine processes the
same objects in the same order at the same tick, the sequence stays identical across the network;
anything that consumes `rand()` out of lockstep would desynchronise the game. The per-tick order is:
player bookkeeping → objects 0..N in index order → missiles → sync checksum → AI command generation.

---

## 13. Address index

| Function | Address | File |
|---|---|---|
| load weapstat / gamestat / mbullet / boomstat | `0x43B6EC` / `0x43BB80` / `0x43B150` / `0x43B424` | loader.c |
| parse FIRE/DIE sprite names | `0x43BA3C` | loader.c |
| game tick | `0x419978` | game |
| object dispatcher (per-object per-tick) | `0x4194DC` | ticker.c |
| push / pop / reset+dispatch order / sleep / set cooldown / push idle | `0x412114` / `0x4122A4` / `0x41233C` / `0x41258C` / `0x4124F0` / `0x41296C` | ticker.c, mobiles.c |
| idle-guard state | `0x414B9C` | mobiles.c |
| begin move (modes 2/3/4) | `0x414FD0`; move state `0x415A94` | mobiles.c |
| turn towards / direction / random heading | `0x412414` / `0x4124B8` / `0x412650` | mobiles.c |
| fire_weapon | `0x413018` (wrappers `0x414B08`, `0x414B18`) | mobiles.c |
| fire-at-ground order / state | `0x418160` / `0x4182C0` | mobiles.c |
| heal_nearby | `0x413F24` | mobiles.c |
| deploy/transform state, commander rally, stealing search | `0x417DA4`, `0x417400`, `0x417BDC` | mobiles.c |
| object_die, corpse state, falling wreck | `0x4165A0`, `0x4166F8`, `0x4167E0` | mobiles.c |
| find_target, find_target_in_range, collide | `0x4356C8`, `0x435D5C`, `0x4350D4` | collide.c |
| grid remove | `0x434EB8` | collide.c |
| missile alloc / create / explosion-only / update / detonate / burn / apply_damage | `0x4417F0` / `0x44192C` / `0x441A9C` / `0x442610` / `0x441E08` / `0x4423D0` / `0x441B4C` | missile.c |
| sincos (2048-scaled, 8192 units per turn) / atan2 | `0x441724` / `0x4415C0` | missile.c |
| rand | `0x4120F0` | mobiles.c |
| stats: player stat / per-type stat | `0x41A06C` / `0x41A154` | results.c |
| unit cap | `0x41E7FC` | game |
| upgrade level command 0x0C / build-building command 0x09 / build-units command 0x0A | `0x41CBD4` / `0x41CAA4` / `0x41C9C8` | client/game |
| vision recompute | `0x44A718` (radius blend at `0x44A7C0`) | – |
| waypoint command 0x07 / follow waypoints / nudge step choice (mode 1, random, mode 2) | `0x41D574` / `0x412EE0` / `0x4129C0`, `0x412B38`, `0x412D68` | client, mobiles.c |
| move order / assault / patrol handlers, waypoint states 8 / 9 | `0x4161A0` / `0x416224` / `0x416330`, `0x4163A0` / `0x416434` | mobiles.c |
| begin_move, move state 6, handle_block, re-route, start_step, step state 5, position add | `0x414FD0`, `0x415A94`, `0x41570C`, `0x415454`, `0x4126A0`, `0x4128D4`, `0x43508C` | mobiles.c, collide.c |
| path grid init from `.PTH` / from map, reset buckets, find_path, expand_one, relax, flying path, obstacle import/clear, re-route search, path_length, extract_path, path cost | `0x442D8C` / `0x442C60`, `0x442C20`, `0x444B34`, `0x4445CC`, `0x4434A0`, `0x444830`, `0x443458` / `0x443490`, `0x444748`, `0x443238`, `0x4432BC`, `0x443130` | path.c |
| DEPEND loader, dep_check_building, dep_check_troop, dep_recompute, costs by type / by slot+level / by item, slot blocked | `0x4379C0`, `0x43832C`, `0x4384A8`, `0x437D00`, `0x4381A4` / `0x4381EC` / `0x438188`, `0x4382F4` | depend.c |
| build_slot, building idle / production, slot→class, create_object / init object, pickups | `0x4450F4`, `0x41460C`, `0x41B07C`, `0x41B930` / `0x41B124`, `0x4143D4` | city.c, mobiles.c |
| checksum, record, check, desync, read history | `0x44ABC0`, `0x44AC68`, `0x44ACF8`, `0x44AC94`, `0x44AE84` | sync.c |
| ai_init, ai_turn, ai_think, AI shutdown | `0x41AC80`, `0x41AE38`, `0x41AD30`, `0x41ACD8` | ai.c |
| krusty alloc/init, think, zone init, influence map, census, production rules, assign unit, zone route | `0x44BD50`, `0x44BE64`, `0x456EF4`, `0x456818`, `0x4572AC`, `0x457614`, `0x44BC8C`, `0x457EA4` | ai.c, krusty_*.c |
| level-1/2 AI weights and actions | `0x455E30/0x455E70`, `0x44AEB0/0x44AF10`, `0x44B004/0x44B058`, `0x455EC0/0x455F3C`, `0x44B2C0/0x44B360`, `0x44B500/0x44B50C` | ai.c |

Data: `weapon_types 0x50E678`, `object_types 0x50FCF8`, `boom_types 0x50DE80`,
`magic_bullet 0x518B28/0x518B2C/0x518B30`, `state_table 0x48942C[23]`, `order_table 0x4893D4[22]`,
`rand table 0x488F20[256]` + index `0x489320`, `sin table 0x4897D4`, `arc table 0x48A9D8[17]`,
`spiral 0x434200`, research bytes `0x510188[8]` (napalm) / `0x510A48[8]` (plasma),
`dir table 0x489324[8]`, nudge tables `0x489364/0x489384/0x4893A4/0x4893C0`, `dir3x3 0x48AAA0`,
neighbour orders `0x48AAD0`, DEPEND items `0x5049F0[110]` (count `0x506048`), `unitdef 0x48B0C4`,
city slot offsets `0x48AC8C`, footprints `0x48AD04`, slot→class `0x41B040`, spawn offsets `0x41AFE0`,
AI personalities `0x489488[4]`, krusty rule table `0x499158[18]`, building-kind items `0x499110`.

---

## 14. Movement and pathing (`mobiles.c`, `path.c`)

### 14.1 Orders and waypoints **(verified)**

* Network commands `0x07`/`0x19` store up to 8 waypoints in the object: `obj+0xA6+4i` = x,
  `obj+0xA8+4i` = z, count in `obj+0xC6` (handler `0x41D574`).
* Order 2 (move, `0x4161A0`) pushes marker state 2 and then state 8 with `{index = 0, mode = 0}`;
  order 7 (assault, `0x416224`) pushes marker state 7 and state 8 with `mode = 1`; order 9 (patrol,
  `0x416330`) pushes state 9 with `{index = 0}`. Immobile types reset to idle instead.
* State 8 (`0x4163A0`): when `index >= count` the count is cleared and the state pops (the marker
  state then resets the stack → idle). Otherwise the destination `obj+0x2E/+0x30` becomes
  `waypoint[index]`, `index++`, `begin_move(mode)`. State 9 (`0x416434`) is the same with the index
  wrapping to 0, always mode 1 — an endless patrol.
* Move modes (state 6 `info[4]`, jump table `0x415A80`):

| Mode | Used by | Behaviour while walking |
|---|---|---|
| 0 | move order, nudge step | plain movement, never fires |
| 1 | assault, patrol, wandering after a block | fires at anything inside weapon range (`0x435D5C`); the cooldown state pauses the walk |
| 2 | idle unit walking towards a spotted enemy | pops as soon as any enemy is inside weapon range (idle then engages) |
| 3 | attack order | chases the object in `obj+0x30`; switches to mode 1 when it dies; fires when within `range²` |
| 4 | fire-at-ground / special | pops when within weapon range of the destination |

* Direction encoding (`0x489324`, 8 × {dx, dz}): 0 (−1,−1), 1 (0,−1), 2 (1,−1), 3 (−1,0), 4 (1,0),
  5 (−1,1), 6 (0,1), 7 (1,1). The same numbers are the path nibbles and the nudge directions.

### 14.2 `begin_move(gs, obj, mode, flag)` `0x414FD0` **(verified)**

1. Destination tile from `obj+0x2E/+0x30` (mode 3 with `flag = 0`: the tile of the target object
   whose index is in `obj+0x30`); clamped to the map, flyers to `height − 3`.
2. If the destination tile is impassable (family 0, see below) and the unit does not fly, the nearest
   passable tile within 256 rings replaces it; `obj+0x2E/+0x30` is set to that tile centre
   (`(tile << 8) + 0x80`).
3. Ground units: `find_path(dest → start)`; `len = path_length(start)` capped to 32;
   `extract_path(start, obj+0x86, 0, 32, len)`; `len == 0x8000` triggers the "Start moving many
   squares... couldn't get there" assert. Flyers use the straight-line path (`0x444830`).
4. Push state 6 with eight info words: `[0]` step cursor = `len − 1`, `[1]` len, `[2..3]` current
   tile, `[4]` mode, `[5..6]` blocked cell (−1), `[7]` nibble offset (0).

### 14.3 Path search (`path.c`) **(verified)**

* Path grid `map+0x1404`: an array of row pointers (one border row/column with family 0xFF) to
  24-byte cells: `+0` search-generation stamp (equal to the global `0x48AA9C` = visited in the current
  search), `+4` cost, `+8` x, `+9` z, `+0xA` parent z, `+0xB` parent x, `+0xC` **family** (0 =
  impassable), `+0xD`, `+0x10`/`+0x14` bucket links.
* Terrain comes from the scenario's `.PTH` file (`0x442D8C`): first a 65536-byte **family routing
  matrix** `next[a][b]` = the family to enter next when travelling from region `a` to region `b`
  (0 = unreachable), then `width × height` family bytes (checked: `D8PLAY01.PTH` = 65536 + 160×140).
  Families are the connected walkable regions of the map as produced by the map editor. At load the
  engine derives per-family neighbour lists (`CLIST2`, at most 32 entries each, `0x442F28`).
* `find_path(path, xd, zd, xs, zs, fly)` `0x444B34`: for ground units the allowed-family set
  (`0x51D8BC[256]`) is the chain `fam(dest) → next[fam][fam(start)] → …` until the start family
  is reached (asserts `current_family!=0`, `destination_family!=0`, "There is no path" when a hop is
  0). Then **Dijkstra with a 256-bucket circular priority queue keyed by `cost mod 256` (Dial's
  algorithm)**, seeded at the *destination*: `expand_one` `0x4445CC` pops the head of the current
  bucket, relaxes its eight neighbours (`0x4434A0`: visiting order biased toward the start via the
  table `0x48AAD0`; only allowed families; when an obstacle set is active, tiles occupied in the
  ground or air grid are treated as blocked), unlinks the node and returns 0 when the start cell has
  been popped or every bucket is empty. Step costs are 5 orthogonal and 7 diagonal (`0x443130`). No
  heuristic, no terrain cost differences.
* `path_length` `0x443238` counts the parent chain from the start; `extract_path` `0x4432BC` writes
  one direction nibble per step into `obj+0x86` (16 bytes = 32 steps, index `len − 1` = first step,
  `dir3x3` table `0x48AAA0`) and bumps the generation stamp (assert `pos/2 < path_size`).
* Flyers (`0x444830`): a straight line of parent pointers, diagonal steps first, ignoring terrain.
* Re-route (`0x415454`): the unit removes itself from its tile, imports the ground/air grids as
  obstacles (`0x443458`), searches from the blocked cell with every family allowed except 0 for
  ground units (`0x444748`), splices the new segment in front of the remaining steps (`info[7]` =
  offset) and clears the obstacle set (`0x443490`).

### 14.4 Executing a path (state 6, `0x415A94`) **(verified)**

* A global re-entry counter (`0x488F1C`, reset per object per tick) above 10 makes the unit sleep
  7 ticks (assert `nasty_global_loop_trap<100`).
* Cursor −1 (path exhausted): pop; if the unit is not on its destination tile, `begin_move` again.
* A pending blocked cell (`info[5] ≠ −1`) is re-routed around unless it was reached.
* Mode checks (§14.1), then the step: `dir = nibble[cursor]`, `next = current + dir`.
  * Target tile occupied (ground grid for walkers, air grid for flyers) → `handle_block`
    `0x41570C`: walk the remaining path to the first occupied tile; if the path is clear but the
    destination is not reached, the destination is jittered by ±1 tile and the unit re-plans in mode 1
    ("wander"); otherwise a re-route is attempted; if no path exists the blocker, when it is an idle
    allied unit without orders, receives the nudge `blocker+0x35 = dir`, and the mover shows STAND and
    sleeps 4 ticks. Reaching the destination through the check resets the stack (idle).
  * Free → the object id is written into the new tile (`grid = (grid & 0xFC00) | obj`), `info[2..3]`
    = new tile, cursor−−, `start_step` `0x4126A0`: MOVE animation, heading set to the step
    direction, state 5 pushed with `{vx, vz, ticks, old x, old z}` where `vx = sin·speed >> 11`,
    `vz = cos·speed >> 11` (`speed` = GAMESTAT column 3 in position units per tick, 256 per tile) and
    `ticks = distance / speed`; the **old** tile is cleared at once (a moving unit is registered on its
    destination tile while it slides) and both tiles get the team's seen-by bit. State 5 (`0x4128D4`)
    adds `(vx, vz)` to the position every tick (`0x43508C`) and pops at 0.
* Hence one orthogonal tile takes `256 / speed` ticks (Security trooper 25 → ~10 ticks ≈ 0.7 s at
  66 ms, VTOL 47 → ~5.4 ticks) and a diagonal one ~1.4× that; all passable terrain costs the same.
* Nudging (`0x412EE0` from the idle state when `obj+0x35 ≠ 0xFF`): the unit picks a free, passable
  neighbouring tile near the nudge direction — perpendicular offsets first (±2), then ±1, ±3 and the
  direction itself (`0x4129C0`, tables `0x489384/0x4893A4/0x489364`; a random shuffle in `0x412B38`
  when nothing fits; five candidates in `0x412D68` when the idle unit has a target) — and walks there
  with `begin_move(0)`. Diagonal nudge steps require both orthogonal neighbours to be passable.

---

## 15. Buildings and production (`city.c`, `depend.c`, `mobiles.c`)

### 15.1 City slots and construction **(verified)**

* Every player owns the 15 fixed building objects `player × 15 + slot` (objects 0..119,
  `BUILDINGS_PER_SIDE = 15`). Slot → object type through `unitdef[race][level][slot]` (`0x48B0C4`):
  race 0 = 16 HQ, 17 barracks, 18/19 robot factory 1/2, 20/21 science 1/2, 22 research centre,
  81 city tower (slot 5), 25 for the unused slots 6–12; race 1 = 28, 29, 30/31, 32/33, 34, 81, 25.
* Positions are fixed relative to the player's city origin (`gs+0xBC8/+0xBCC`, tiles): slot offsets
  `0x48AC8C` in 1/32 tile — slot 0 (−2, +0.5), 1 (0, 0), 2 (+1, +2), 3 (+2, +0.3), 4 (−1, +2),
  5 (0, +1); footprints `0x48AD04` are 2×2 tiles (slot 0: (−3,0) (−2,0) (−3,1) (−2,1), slot 1:
  (−1,−1) (0,−1) (−1,−2) (0,−2), slot 2: (0,2) (1,2) (0,3) (1,3), slot 3: (1,0) (2,0) (1,1) (2,1),
  slot 4: (−1,2) (−1,3) (−2,2) (−2,3), tower: (0,0) (−1,0) (−1,−1) (0,−1)).
* Command `0x09 (slot, level, player)` (`0x41CAA4`, sent by the build menu and the AI):
  `type = unitdef[race][level][slot]`; if the slot is already alive (`+0xBD8[slot] ≠ 0`) at that
  level the cost is refunded to `+0xBAC`; otherwise `+0xBB0 += cost`, `+0xBD8[slot] = health`,
  `+0xC60[slot] = level` and `build_slot` `0x4450F4` re-initialises the object (type, position,
  hit points from the slot field, team, alive, STAND animations, state stack reset) and writes its
  footprint into the ground grid (the tower slot 5 is not written). **Buildings have no construction
  time**: they exist with full hit points as soon as the command executes; the BUILD animation is
  cosmetic. A destroyed building clears `+0xBD8[slot]` (§8.3) and can be bought again.
* `DEPEND.TXT` (`0x4379C0`, up to 110 items, 52-byte records at `0x5049F0`, count `0x506048`):
  columns `id cost button kind a b c deps…` → `+8` cost, `+0xC` interface button id, `+0x10` kind,
  `+0x14/+0x18/+0x1C` = (slot, level, race) for buildings, (unit type) for troops, (unit type,
  weapon 0 / armour 1, level) for upgrades, `+0x20..` up to five dependency ids ending in −1
  (`MAX_DEPEND = 5`). `dep_check_building` `0x43832C(gs, player, item, &slot, &level)` returns 0 =
  already built, 1 = buildable, 2 = unavailable (invalid, slot blocked `+0xC14[slot]`, item disabled
  by a scenario trigger `+0x1940[item]`, wrong race, or a dependency not yet built — recursively);
  `dep_check_troop` `0x4384A8(gs, player, item, &type, &cost)` likewise for troop items.
  `dep_recompute` `0x437D00` refreshes the item status bytes (`+4`: 0 done, 1 available, 2 blocked)
  for the local player's build menu after every purchase or building loss. Upgrades are bought with
  command `0x0C` (§2.5).

### 15.2 Unit production **(verified)**

* Command `0x0A (type, player, count)` (`0x41C9C8`): production class `k = type.+0xEC` (GAMESTAT
  column 21: 0 infantry and engineers, 1 mechs / artillery / tower builders, 2 workers / aircraft /
  healers, 3 cyborg / psy-raider); queue `k` = `int16` length at `player+0xCAC+2k` and 800 type
  bytes at `player+0xCB4+800k`; `count` copies are appended and `+0xBB0 += cost × count`. The
  handler does not check or deduct money: the build menu deducts `+0xBAC` before sending
  (`0x43332F`), as do the AI rules.
* Producers: slot → class table `0x41B040`: HQ → class 2, barracks → 0, robot factory → 1, research
  centre → 3 (science slots and the tower produce nothing). The building's idle handler
  `0x41460C` runs every tick (it also picks the damage sprite: STAND above 11/16 hit points, SCRCH
  below that, BURN below 5/16):
  1. ready flag `player+0xCA4+k == 1` and queue not empty → spawn tile = origin + `0x41AFE0[k*3 + flyer]`
     (class 0: (0,−3); class 1: (2,3) / (−5,−1) for flyers; class 2: (−4,0) / (−5,−1); class 3: (−4,3)).
     An occupied spawn tile makes the occupant step aside (`+0x35 = 0`) and the building waits.
     Unit count ≥ cap `gs+0x528` → refund (`+0xBAC += cost`, `+0xBB0 −= cost`), drop the queue head
     and show message 0x77. Otherwise, if the unit type has a BUILD sprite (`type.+0x98`), the spawn
     tile is reserved (`0x3FE`), the ready flag is cleared and the unit's BUILD animation plays in the
     building's third animation slot; types without a BUILD sprite appear immediately.
  2. ready flag 0 → wait while that animation is still playing (`obj+0x2A == 1`), then
     `create_object` `0x41B930` (first free object from 152, else extend `gs+0x7D40`, assert < 800;
     `0x41B124` initialises it with `+0xD2/+0xD4 = −2`), remove the queue head, ready = 1.
  3. The per-class countdown `player+0xCA8+k` is decremented here but only ever written as 0, so
     **production time is the length of the unit's BUILD animation (or zero)**; there is no per-unit
     build time in the tables.
* Money: `+0xBAC` receives the income `+0x19B8` every 16 ticks while the HQ slot is alive
  (`game_tick`), the `0x0F` bonus (+1000), cheats and refunds; `+0xBB0` accumulates spending (results
  statistic). Since money is not part of the checksum, only the owning machine's copy matters for a
  human player; AI players deduct on every machine identically. Mining income in the harvesting
  state `0x413A88` is multiplied by `player+0x19BC` for AI players: 0x100 (×1) for lobby type 0,
  0x200 (×2) for lobby type 1 — the only effect of the lobby's two computer-player types.
* Pickups (`0x4143D4`, field `obj+0xCB`): 1 = capturable object taken over by a team-0 unit within
  2 tiles; 2 = money crate: the finder's owner gains `hp` money and the crate dies.

---

## 16. Sync checksum (`sync.c`) **(verified)**

```
sum  = w16(gs+0x534) + w16(gs+0x538) + w16(gs+0x53C) + w16(gs+0x540)   // day/night: phase length, dawn length, phase, light
     + w16(gs+0x94C) + w16(gs+0x7D40) + w16(gs+0x7D44)                 // tick counter, highest object index, missile count
for obj in 0 .. gs+0x7D40:                                             // inclusive
    sum += obj.life (+0x2C, byte)
    if obj.life != 0:
        sum += obj.x + obj.z + (obj.hp & 0xFFFF) + obj.team + obj.type
checksum = sum & 0xFFFF
```

`checksum(gs)` `0x44ABC0` adds 16-bit and 8-bit values into 32-bit registers whose upper halves are
uninitialised; only the low 16 bits are ever used, so the value is well defined. Not covered: money,
orders and state stacks, animations, headings, missiles' positions, targets, the RNG index, upgrade
levels and production queues — a divergence there is detected only once it changes a position, a
hit-point value or an object's existence.

`record` `0x44AC68` stores `history[tick % 256] = checksum` (`int16[256]` at `gs+0x994`) once per
tick from `game_tick` with `tick = gs+0x94C`; `read` `0x44AE84(gs, tick)` returns an entry; the
active player with the lowest network id sends `0x08 (checksum, tick)` every tick (§ network protocol
document). `check` `0x44ACF8(gs, tick, value)` asserts `tick ≤ gs+0x94C` ("AUGH check sync time %ld >
game time %ld") and `gs+0x94C − tick < 256` ("records start at %ld"), compares the history entry and
on mismatch prints "sync error: time %ld, net %d, me %d" and calls `0x44AC94` ("Sync history dump not
compiled into this build, sorry"), which asserts and ends the game.

---

## 17. Computer players (`ai.c`, `krusty_*.c`)

### 17.1 Framework **(verified)**

* Setup (`0x40122C`): for each lobby slot the player's race goes to `+0xBB8`, the AI type to
  `+0xBBC`: lobby type 2 (human) → 0, type 3 (closed) → 4, computer types 0/1 → 3. `+0x19BC` is set
  to 0x100 for type 0 and 0x200 for type 1 (income multiplier, §15.2). `ai_init` `0x41AC80`
  allocates the AI game state (`gs+0xB94`: start tick, round-robin counter). The scenario trigger
  action `ai <player> <type>` (`0x43D930`, action 0 of `trigger.c`) sets any type in campaign
  missions, and a disconnected human is switched to type 3 (§ protocol `DISCONNECT`).
* `ai_turn` `0x41AE38` is called from `game_tick` in local-command mode every 4th tick: on tick 4
  every AI player thinks once, afterwards one AI player per call in round robin — so each computer
  player thinks every 32 ticks and its commands are generated identically on every machine.
* `ai_think` `0x41AD30(gs, player)`: `personality = 0x489488[type − 1]` = `{pairs, save, load,
  destroy, message}`; `pairs` is a NULL-terminated list of `{weight_fn, action_fn}`. All weights are
  evaluated and one action is drawn with probability `w_i / Σ w` (reservoir sampling using
  `rand()·(cum + w_i)·2⁻¹⁵ ≤ w_i`, constant `0x48385C`); the chosen action runs once. Actions use the
  client command builders (`0x40C50C` build building, `0x40C538` build units, `0x40C7D4` waypoint
  orders, `0x40C978` attack target) so the commands go through the same handlers as a human's.
* Helpers: `own_unit(obj, player)` `0x456078` = alive, own, not flying, mobile, armed;
  `enemy_target(gs, obj, player)` `0x4560CC` = other team **and that team is human**;
  `unit_class(type)` `0x456150`: types 0–15 → 0..7 (type − 8 for aliens: 0 infantry, 1 tower
  builder, 2 mech/scythe, 3 artillery, 4 cyborg/psy-raider, 5 scout, 6 worker, 7 carry-all),
  healers → 7, deployed towers → 1, everything else → 8.

| Type | Pairs (`weight → action`) | Behaviour |
|---|---|---|
| 1 | `0x455E30→0x455E70`: any building buildable → build the first one; `0x44AEB0→0x44AF10`: a troop affordable → pick a random buildable troop item and order `max(1, money / candidates / cost)` units; `0x44B004→0x44B058`: own units exist → all of them assault-move to a random point in a box around a random *human* player's HQ; `0x455EC0→0x455F3C`: own flyer exists → send a random flyer to a random map tile; `0x44B2C0→0x44B360`: a vent (type 40) and a worker exist → send a random worker to a random free vent | simple base builder and rusher |
| 2 | flyer scouting as above; `0x44B500→0x44B50C`: every own unit attacks a random visible human unit (`0x0E` commands in one frame) | attacks only, never builds |
| 3 | `0x44BC80→0x44BE64` (weight 1) | "Krusty", the real AI (§17.2) |
| 4 | `0x44D660→0x44D668` | does nothing (closed lobby slots) |

### 17.2 Krusty (type 3) *(architecture verified, task internals inferred)*

* State: `0x6C40` bytes per player (`player+0xBC4`, allocated on first use by `0x44BD50`, name
  "Krusty AI"): byte 0 first-run flag; **zone table** 256 × 18 bytes (a zone is a path family, §14.3):
  `+2/+3` centre tile, `+4/+6`, `+8/+0xA`, `+0xC/+0xE` = (owner, net strength) for anti-air,
  ground and air presence, `+0x10` building count, `+0x12` flags (bit 0 contested), `+0xD` hop
  distance from the home zone; `+0x1200` four bytes per object (task assignment, 0xFF none);
  four **major tasks** with a nine-class demand array (`+0x3154 + 4860·i`, `int16[9]`) and six
  callbacks (`+0x3168..+0x317C`), each owning minor tasks = unit groups linked through
  `obj+0xD2/+0xD4` (`kai->major_tasks[task].tasks[minor]`); 18 production rules copied to `+0x6A94`
  from `0x499158`; tunables `+0x6C14..+0x6C30` (defaults 0xC0 = 75 %, 1, 1, 2, 4, 2, 4, 2);
  `+0x6C38[8]` enemy-team flags. The scenario trigger `aimsg` (`0x44BF78`, 15 message ids) changes
  the tunables: id 0 sets the 75 % split as `value·256/100`, ids 1–5 the class weights, higher ids
  zone-related parameters (not traced). `0x44C750`/`0x44CF48` save and load the state
  (`KRUSTY_SAVE_*`).
* Initialisation (`0x456EF4`): home zone = family of the city origin (assert `start_zone!=0`), hop
  distances of all zones by breadth-first search over the routing matrix (`0x44B670` also gives the
  hop count between two zones), zone centres = mean tile of every family snapped to a real tile of
  that family; task slots are initialised by `0x459B68` (0), `0x459574` (1, scouting), `0x458E54`
  (2, defence) and `0x45A460` (3), each installing its callbacks.
* Every think (`0x44BE64`):
  1. `krusty_general` `0x456818` rebuilds the **influence map**: for every object of a team < 8 that
     the AI can currently see (own vision mask; hidden mines only when detected), buildings add to the
     zone's building count, combat units add a strength value derived from their magic-bullet row to
     the zone's anti-air, ground or air pool — added to the current owner's total, or subtracted from
     it and the owner flipped when exceeded, flagging the zone contested.
  2. Census (`0x4572AC`): own units per class; unassigned units are offered to the four tasks through
     their "want a unit of this class" callbacks and linked into their groups (`0x44BC8C`); the 75 %
     tunable splits units between two pools.
  3. Demand (`0x457684`): task demands and queued units are summed per class and the **production
     rules** run (`0x457614`): the first rule whose check returns 0 fires and the chain stops.
  4. The tasks' update callbacks run (`+0x3168`, `+0x3174`, `+0x316C`, `+0x3170`): they move unit
     groups between zones along zone routes (`0x457EA4`, "AI Path not found (hsm)"), choose attack
     targets (`best_candidate`), defend zones (`krusty_defend.c`), scout and bomb (`krusty_scout.c`,
     `OBJ_BOMBING`) and manage groups (`krusty_army.c`). Their internals were not traced.

Production rules (`0x499158`; "army" = own units of classes 0, 2, 3, 4, 5; building kinds map to
DEPEND items by race through `0x499110`):

| # | fires when | action |
|---|---|---|
| 0 | HQ / mind hive (items 0 / 14) buildable | build it (`0x09`) |
| 1 | fewer than 1 worker | build a worker |
| 2 | barracks / warrior hive (1 / 15) buildable | build |
| 3 | army < 5 and unit count < cap | build one unit of the class with the smallest `count × weight` among buildable troop items |
| 4 | robot factory 1 / breeding 1 (3 / 17) | build |
| 5 | science 1 (2 / 16) | build |
| 6 | army < 10 | build a unit |
| 7 | fewer than 2 workers | build a worker |
| 8 | army < 15 | build a unit |
| 9 | science 2 (4 / 18) | build |
| 10 | robot factory 2 / breeding 2 (5 / 19) | build |
| 11 | army < 20 | build a unit |
| 12 | mech / scythe armour upgrade (69 / 43) | checked with `dep_check_building`, which never returns 1 for an upgrade item — dead rule *(inferred)* |
| 13 | mech / scythe weapon upgrade (67 / 41) | same |
| 14 | army < 30 | build a unit |
| 15 | research centre (6 / 20) | build |
| 16 | army < 200 | build a unit |
| 17 | always | nothing |

Building rules fire when `dep_check_building` returns 1, and also when the slot is blocked for the
scenario (then the action does nothing but the chain still stops). The unit-building action prefers
the class whose `count × weight` is lowest, the weights being the tunables per class (infantry
`+0x6C18`, mech `+0x6C1C`, artillery `+0x6C20`, cyborg `+0x6C24`, scout `+0x6C28`, carry-all/healer
`+0x6C2C`, tower builder `+0x6C30`), deducts the cost from `+0xBAC` and sends `0x0A` for one unit;
a building action checks `cost ≤ money` and the slot before deducting and sending `0x09`.

---

## 18. Open points

* Object-type columns 22 and 24 and the exact meaning of "signature" (column 14) were not traced.
* State handlers 0, 0xF, 0x10, 0x13–0x16 (artifact pickup, stealing commandos, vents/workers) and
  the harvesting arithmetic in state 0xC are not covered.
* Krusty's task callbacks (attack target choice, defence, scouting, group movement) are described
  only structurally; the `aimsg` ids above 5 and the strength formula in the influence map were not
  decoded exactly.
* The `.PTH` family map and routing matrix are consumed as produced by the map editor; how the
  editor computes them was not examined.
* The direct-fire target score collapsing to 0 for living targets looks like a bug in the original
  code; in practice direct-fire units engage the nearest visible enemy.
* Stat ids: 1 income, 2 kills, 3 losses, 6 unit count, 8 shots fired, 9 HP healed, 10 day/night, 11
  hero-related events *(inferred from usage; `results.c` names not recovered)*.
* `gs+0x000` gating commander specials was read as a "multiplayer" flag from its use in game init;
  not confirmed.
* Nothing here was re-checked against `ENGEXP16.EXE`.

---

## 15. How this was produced

`dumpbin -ALL -DISASM` output of the exe (`dc16.asm` in the development folder), string extraction
(`tr -c '[:print:]\n' '\n' | grep -E '.{4,}'`) to find the `loader.c`/`mobiles.c`/`missile.c`
assert messages, `DGROUP` string addresses (`VA = file offset + 0x402800`) to find their code
references, the `.reloc` table to recover the `DGROUP → AUTO` function-pointer tables (state and
order tables), and a list of `call` targets as function boundaries. Regions that `dumpbin` had
decoded as data (after inline jump tables, e.g. `0x417400`) were re-disassembled by wrapping the
raw bytes in a minimal COFF object and running `dumpbin -DISASM` on it.
