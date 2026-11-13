# Frontline Conquest — mechanics as implemented

Facts from this tree, with the file the constant lives in. This is the Godot port (`frontline-godot/`), not a guess at upstream balance. Where the port names a RoWorld source, that path is the Luau file in this same fork (`src/`). Pacing numbers below are the ones already in the code. This note does not change them.

Map size is `W = 1792`, `H = 1600` (`main.gd`). `DEFAULT_K_LIN = 1.1161` scales "full-size" RoWorld tiles (a 2000-wide world) onto that grid (`main.gd`). `TILE_NORM = (640 * 352) / (W * H)` is what the troop-cap formula normalizes by.

## Economy

`sim/rules.gd` (`SimRules`), commented as a port of `src/shared/Core/Rules.luau`.

- Tick rate 10 Hz (`TICK_RATE`).
- Gold per tick: human/nation 100, tribe 50, then multiplied by `gold_mult` (0.85). So a human tick pays 85 gold before other bonuses.
- Troop growth per tick, while under the cap: `(10 + troops^0.73 / 4) * (1 - troops/cap) * growth_mult`, then ×0.5 for tribes and × `NATION_GROWTH_MULT` (0.9 / 0.95 / 1.0 by difficulty) for nations. `growth_mult` is 0.8. The result is floored.
- Over the cap, troops fall by `OVERCAP_DECAY` (0.02) of the excess per tick. They are not snapped.
- Land cap (`max_troops`): `5000 + 6200 * (tiles * tile_norm)^0.41 + 25000 * city levels`. Tribes get one third. Nations multiply by 0.5 / 0.75 / 1.0. The comment in `rules.gd` says this replaced the source `2 * (fullTiles^0.6 * 1000 + 50000)`. It is the cap the port already ships. Console edits of `troops` write `nations[PLAYER].troops` directly (`main.gd` console) and are not clamped back by that formula on the write.
- Starting troops: human 25000, tribe 10000, nations 12500 / 18750 / 25000 by difficulty.
- Conquered gold: all of a bot's gold, half of a human's (`conquer_gold`).
- Number format: `K M B T Qd Qt` in `_fmt` (`main.gd`).

Structure prices (`SimRules.build_cost`), `n` = how many you already own:

| kind | price |
| --- | --- |
| city, port, factory | `min(1e6, 125000 * 2^min(n, 4))` |
| defense | `min(250000, 50000 * (n+1))` |
| sam | `min(3e6, 1.5e6 * (n+1))` |
| silo | 1e6 flat |
| warship | `min(1e6, 250000 * (n+1))` |
| artillery | `min(750000, 150000 * (n+1))` |
| airfield | `min(1.5e6, 500000 * (n+1))` |
| railgun | `min(7.5e6, 2.5e6 * (n+1))` |

Nuke prices are separate (`nuke_cost` in `main.gd`). ICBM mode multiplies the launched bomb's price by 1.10 (`ICBM_FEE_PCT`).

Trade gold for a ship that sailed `path_tiles` of our tiles: `75000 / (1 + exp(-0.03 * (d - 300))) + 50 * d` where `d = path_tiles * k_lin` (`trade_gold`). Both ports are paid. Spawn rate and saturation are `trade_saturation` / `trade_spawn_rate` (sigmoid around 330 and 800 ships). `sim/naval.gd` rolls each finished port `level` times.

Train gold (`train_gold`): self station 10000, ally 35000, other 25000, then −5000 per stop after 9, floored at 5000.

## Buildings

Placement is `sim/structures.gd` (`place_site`), a port of `Rules.place_site`. The click must be your land. Search radius is 15 full-size tiles (`place_search_r` = `15 / k_lin`). Another structure closer than 15 full-size tiles blocks the tile (`struct_min_dist`). Ports must be coastal and within 20 full-size tiles Manhattan (`port_spawn_manhattan`).

Upgrades in place, no extra spacing, for city, port, factory, SAM, and silo (`UPGRADABLE_K`). The nearest same-kind owned structure inside the min distance, with construction already finished, is the upgrade target.

SAM range in full-size tiles: `150 - 480 / (level + 5)`, then divided by `k_lin` (`sam_range`). Reload slot time in the port is 9 s times `reload_mult()` (`_sam_intercept`). The arsenal "reload" unlock returns 0.5 from `reload_mult` (`main.gd`).

Defense posts use `DEFENSE_POST_MAG` 5 and `DEFENSE_POST_COST` 3 (`rules.gd`): the attacker loses 5× and the tile takes 3× as long, in the attack resolver.

Warships: spawned from `try_build` kind 6. The button's own copy says 1000 HP and 250 damage per shell (`main.gd` build table). Sinking a transport and capturing trade ships is in the warship tick in `main.gd`.

Artillery and airfields are build kinds 10 and 14. Railgun is kind 15 (`fire_railgun`). Reinforce is kind 13: adds `troop_cap/5` and sets a 30 s cooldown, and plays `spawn` only for the player.

Construction time is the `bt` field on a structure. Icons draw at 0.55 alpha while `bt > 0`.

## Transport, trade, roads

Land attack vs boat (`intent_attack` in `main.gd`): if any neighbor of the clicked tile is already the attacker, it is a land attack (`launch_attack`). Otherwise `launch_boat`. The same rule is on the player click path around the "must ONLY be raided via land" comment. AI boats skip a target when `_shares_land_border` is already true (`_ai_boat`).

`_shares_land_border` walks the smaller nation's border set (or the overlapping bounding boxes) and looks for a 4-neighbor of the other owner. Neutral counts only when the attacker already touches some neutral tile; a click is then checked against that.

Boat speed: `ship_tiles_per_s()` is `10 / k_lin` tiles per second (1 full-size tile per tick), times `boat_speed` 1.5 in `main.gd`. Player may have 10 boats, others 3 (`MAX_BOATS_PLAYER`, `MAX_BOATS_PER_OWNER`). AI boat fraction is `BOAT_ATTACK_FRACTION` 0.2. Path search is capped (`launch_boat` `max_nodes`, naval `BOAT_SEARCHES_PER_S` = 2). If a boat is at sea and the attacker later shares a land border with the target, the troops are pulled into a land attack (`_tick_boats`).

Trade ships use the water-body ids from `SimNaval.compute_bodies` (4-connected water flood fill). A ship only sails to a port on the same body.

Roads (`_rail_curve`, `_build_rail_mst` in `main.gd`):

- Links are a minimum spanning tree of the owner's finished structures whose kinds are in `RAIL_KINDS`, and only between structures that sit inside the same factory's radius.
- `FACTORY_RANGE` is 60 tiles.
- A candidate segment must be an axis-aligned L (horizontal then vertical, or the other order). `_axis_land` rejects the segment if any tile on it is not land.
- Geometry is cached in `rail_cache`, separate from the boat `path_cache`.

## AI

`sim/ai.gd`. Nations think every 15 ticks (`NATION_THINK`). Attack-rate bands: nations `[[65, 100], [55, 70], [45, 60]]` by difficulty, tribes `[40, 79]`. `ai_rate_mult` is 1.15 (higher waits longer). Human skip odds by difficulty: 0.75 / 0.25 / 0. Late war starts at tick 12000 and spreads over 9000 ticks. Invasion gap 150 ticks, mop-up gap 200.

`main.gd` caps AI work with `AI_BUDGET_US` 2500 and `MAX_TICKS_PER_FRAME` 12, and bails out of the tick loop after 28 ms in a frame. `AI_BOAT_CAP` is 12. Placement searches spend `_ai_place_budget`.

Protagonist nations (`prot`) and tribes are different kinds (`KIND_NATION` 1, `KIND_TRIBE` 2). Tribes have a traitor roll (`TRIBE_TRAITOR_ODDS` 3) and a chance to skip the player (`TRIBE_SKIP_PLAYER_ODDS` 2).

Grace before bots focus the human: 3000 / 1800 / 1200 ticks plus up to 900 jitter (`HUMAN_GRACE_*`). Max simultaneous AI wars on the human: 1 / 2 / 3.

## Combat

`sim/attacks.gd` and `sim/rules.gd`.

Terrain indexes into `ATTACK_MAG` 80 / 100 / 120 and `ATTACK_TILE_COST` 16.5 / 20 / 25 for plains, highland, mountain (`mtn[]` 0, 1, 2). There is no ice tile in this resolver. The old README line about ice caps does not match `rules.gd`.

Attacker loss: `ATTACKER_LOSS_BASE` 0.463 plus `ATTACKER_LOSS_PER_DENSITY` 0.0039 per density, with large-territory sigmoids (`LARGE_ATTACKER_DEPTH` 0.7, `LARGE_DEFENDER_DEPTH` 0.3, speed depth 0.73, `SPEED_COST_DIVISOR` 8.55). Bot defenders lose 0.7× (`BOT_DEFENDER_LOSS_MULT`). Terra nullius (neutral) tile cost is scaled by 2000, clamped to 5..100.

Border growth speed (`attacks.gd`, the organic factor): `1 + 0.07 * (grow_n/127.5 - 1) + rand(-0.03, 0.03)`, clamped to 0.9..1.1. The comment says the mean is 1.0. `attack_speed_mult` is 1.0 (divides tile time). `BORDER_JITTER` is 5.

Traitor: defense 0.5, speed 0.8, for the hostile window (`TRAITOR_*`, `HOSTILE_TICKS` 600 = 60 s at 10 Hz). Retreat keeps 0.75 of the troops and waits 20 ticks.

Win when one nation holds `WIN_SHARE` 0.8 of land that is not fallout.

Attacks update every 10 ticks. The per-tick tile cap is `max_tiles_per_tick = floor(572 / k_area)`.

## Nukes

Ranges are fractions of `land_width()` (`NUKE_RANGE_FRAC` in `main.gd`):

| id | weapon | fraction | blast radius (tiles) |
| --- | --- | --- | --- |
| 7 | Atom | 0.5265 | 19.60 |
| 11 | Mega | 0.5558 | 42.00 |
| 8 | Hydrogen | 0.585 | 70.00 |
| 12 | Scatter | 0.6435 | 19.60 |
| 9 | MIRV | 1.3 | 8.40 per warhead |

`BLAST_S = W / 640` = 2.8. `NUKE_R` is `{7: 7, 8: 25, 9: 3, 11: 15, 12: 7} * BLAST_S`, which is the table above. Headless `--audiotest` printed those five radii.

ICBM is a separate toggle (build id 16 and key `I`). `set_icbm` makes `silo_for` ignore range. Each launch then costs 10% more (`ICBM_FEE_PCT`). It does not change the blast radius.

Flight (`launch_nuke`): non-MIRV bombs use `max(1.8, distance / (43.2 * nuke_speed_mult))` seconds. The comment says 43.2 is 1.2× a 36 tile/s base. The MIRV bus uses 40.8 tiles/s (comment: 1.2× 34) and at least 2 s. Branched warheads use 36 tiles/s and at least 1.1 s. `reload` of a silo slot is `10 * reload_mult()` seconds unless the player has god mode or `no_cd`.

MIRV (`launch_nuke` kind 9, `_split_mirv_bus`, `_tick_missiles`):

- One bus flies to the aimed point `ms.to`.
- On arrival the bus does not spray fallout along the way. `_split_mirv_bus` detonates once at `land_pt`, then spawns warheads from that point toward tiles of the nation under the aim.
- Coverage roll is 0.65..0.85 of that nation's tiles. Warhead count is 8..56 from the coverage area versus one warhead's disc. Radius starts at `max(2.5 * BLAST_S, NUKE_R[9])` and can grow up to `12 * BLAST_S` if the count would otherwise miss the coverage.
- Each branched warhead detonates only at its own `ms.to` (`detonate` on a disc). Fallout is that disc (`fallout[i] = 1`, 60 s timer). The comment in `_tick_missiles` says fallout is only the crater.
- The bus itself is not SAM-interceptable (`mirv_bus`). Branched warheads are.

Scatter (kind 12) fires one atom-sized core plus five offset warheads.

SAM intercepts when the SAM tile is within `sam_range` of the **target** point, spends a slot, and plays shoot/hit only if the SAM or the missile is the player's.

`detonate` removes structures in the disc, sets owners to neutral, writes fallout, and scales the victim's troops down by the fraction of land lost (capped).

The arsenal blurb for Mega still says "60-tile blast radius" (`ARSENAL` in `main.gd`). The radius the sim uses is 42. The blurb was not edited.

## Maps

`sim/real_maps.gd` supplies the real-map bytes. `RW_MAP_FOR` in `main.gd` maps the 12 menu slots onto that list. `HANDCRAFTED_MAPS` is twelve empty strings; the comment says all 12 come from `real_maps.gd`. Random maps still exist as the other tab (`map_tab`). Terrain painting is in `gen_map` / `_tile_color` (water, plains, highland, mountain). No Antarctica, no ice claim, no capital tile type in `rules.gd`.

## UI

1600×900 viewport, window override 2560×1440, canvas-items stretch, nearest filter (`project.godot`). Panels are `StyleBoxFlat` with corner radius (rounded). Speed slider: min 0.5, max 10, step 0.5 (`set_speed_x` snaps to 0.5 and clamps). Keys `-` and `+` step by 0.5. The discrete `SPEEDS` array `[1, 2, 5, 10]` is the benchmark ladder, not the slider.

Build bar, diplomacy (right click), settings (volumes, music toggle), and the end screen are in `main.gd`. Stars and the arsenal persist in `user://save.json`.

## Audio

See `docs/AUDIO.md`. Short version: only `sounds/music/frontline_pad.ogg` is music. Effects are the OpenFront CC BY-SA files from commit `030274df`. AI boat, conquer, build, and SAM do not play. Nuke launches and impacts do, from any owner. A button click plays `click`. A slider does not.

## Port gaps (not done here)

- No Roblox session, parties, DataStore handoff, or spawn shield. Those live in `src/server` and `src/client` and are not what this Godot scene runs.
- No 3D globe and no shop-flag picker. The PNGs are in the fork; see `docs/TEXTURES.md`.
- RoWorld's soundtrack (Rodrigo Flores, CC BY 4.0) and the original `theme_menu` / `theme_war` bytes are Roblox assets. The asset API returned 403. They are not in this project. The rejected mp3s are not a substitute.
- OpenFront `proprietary/` music is not licensed for this port and is not included.
- Multiplayer, alliances across servers, and the Luau `AudioDirector` voice limits are not reimplemented. The Godot `sfx()` gate is the smaller rule in `docs/AUDIO.md`.
- `README.md` in this folder still describes an older prototype (it says MIRV is unavailable and mentions ice). The code in this file and `sim/` is the behavior. MIRV is the bus-then-branch path above. There is no ice type in `SimRules`.

## Port 1: RoWorld sim rules (upstream ae7a350)

All tick values are sim ticks (10 per second at 1x). Ranges in full-size tiles are divided by the map's k_lin.

- Construction and upgrades. Build times come from SimStructures. A SAM takes 300 ticks (30 s). Upgrades are instant, and only city, port, factory, SAM and silo can be upgraded (Rules.UPGRADABLE). After an upgrade, a SAM's range ramps up over 45 ticks, and the new missile slot starts out reloading.
- Reloads. SAM and silo hold `level` missiles with a 90-tick reload each. The airfield rearms in 300 ticks and the railgun reloads in 250 ticks. Rapid Reload halves these.
- Structure HP. A structure at 0 HP loses a level, and is destroyed at level 1. Strikes deal STRIKE_DAMAGE to structures.
- SAM. The planner follows each bomb's ground track. Priority is: hydrogen bomb first, then closeness to the SAM, then the bomb nearest to landing. An interceptor takes manhattan distance / 12 ticks to reach the bomb. The bomb is destroyed unless the SAM is lost in the meantime. The MIRV bus cannot be intercepted; its warheads can.
- Nukes. You can't aim a nuke at your own land or an ally's. The inner disc plus a random half of the outer ring become fallout, owned by no one. Fallout still decays after 60 s (custom rule). Every structure, warship, boat and trade ship inside the radius is destroyed.
  - Bombs: troops are multiplied by ((T-n)/T)^5.
  - Warheads: losses follow nukeDeathFactor x k_area per tile, and a nation keeps at least 3% of its cap.
  - Grudge lasts 3000 ticks.
  - At launch, an alliance breaks if the blast covers at least 100 weighted full-size tiles of the ally (inner counts 1, outer 0.5).
- Inner/outer blast ratios are upstream: atom, mega and scatter .4; H .8; warhead .667. Outer radii stay at the x2.8 scaled values.
- Scattershot. A core blast (an atom-size crater) plus 4–6 warheads, landing 28–46 tiles out. Warheads that would land on your own or an ally's land are dropped.
- Artillery. Range 45. Fires a shell every 40–70 ticks, aiming at the nearest enemy structure, otherwise at random enemy land. A shell kills 2.88% of the army (at least 1440, at most 19200).
- Air strike. A free, aimed strike from the nearest loaded airfield within 156 tiles. Kills 60 per tile hit, up to 6% of the army.
- Railgun. A free slug at any range. Kills 150 per tile, up to 4%.
- Reinforcements. Cost 100K and add 20% of your cap, but never above the cap. 30 s cooldown.
- Warships.
  - HP is 1000 + 20% per veterancy level. A shell does 200–300 damage + 20% per level. Range 130, fires every 20 ticks.
  - Target priority: transports, then warships, then trade ships.
  - A ship retreats at 75% HP unless you gave it an order within the last 50 ticks. It heals 1 HP within 150 tiles of an own port, plus 5 per port level while docked.
  - Trade ships are captured within 5 tiles.
- Trains. A factory spawns a train with probability 1/rate per tick, where rate = (factories+10)*15 / saturation. At most 6 trains per factory, with at least 10 ticks between trains. Trains travel on your own road tree and pay at city and port stops.
- Alliance requests: a request stays pending 200 ticks, then expires; re-asking the same nation waits 300 ticks from the last request; asking back accepts a pending request. AI nations answer after 20-45 ticks with SimAI._accept odds; tribes always accept.
- MIRV cost: 25M + 15M per MIRV already launched in the match. Over-cap armies snap to the cap.
- AI warships: 1 in 50 per economy pass, only a first ship, near a random port; on a sunk transport or captured trade ship, a nation answers with a warship (Standard 15%, Brutal 50%) or re-tasks its nearest ship; fleet cap 10.
- Unchanged (custom): nuke range as a fraction of land width, the ICBM toggle, the MIRV bus, nuke flight speed and countdown, troop cap, roads, boat targeting, SFX gating.
