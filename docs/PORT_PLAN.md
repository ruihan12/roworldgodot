# RoWorld -> Frontline Conquest port plan

Upstream: github.com/ruihan12/roworldgodot @ ae7a350 (AGPL, Luau), copy at /workspace/roworld_src.
Port: /workspace/fc_port/frontline-godot (Godot 4.3). "Full-size tiles" = upstream units; ours = full / k_lin
(sim_rules.set_k(map k_lin), World 1.1161). Areas x k_area = k_lin^2. Sim tick 10/s at 1x (main.gd tick loop).
Status key: MATCH = ported faithfully, DIFF = ported with a deliberate (user) difference, LACK = not ported yet.

## Priority order
P1 (phase 1, done): Rules constants, SimNukes, SimArsenal, SimStructures (costs, build ticks, upgrades, reloads, HP),
   SimWarships, trains (SimStructures factories_tick / trucks).
P2 (next): SimAIEconomy (AI builds + warship use + retaliation), SimAI diplomacy/war/nuke choice, SimAttacks audit,
   SimNaval trade routing + capture reroute, SimNav water A* for ships, SimState alliance requests/extensions.
P3: Sim (spawn flow, intents), GameState/Teams (team games), client layers (Fx/Range/Unit/Road), UI panels,
   AudioDirector (other workers: maps -> docs/HOOKS.md, UI -> docs/UI_EXTRACT.md, audio -> docs/AUDIO_PORT.md,
   tests -> docs/PARITY.md).

## src/shared/Core
Rules.luau (1119)
- MATCH: SAM (213-307: cooldown 90, upgrade ramp 45, max 150, sam_range/sam_range_at), nuke tables (785-816: cost,
  inner/outer, intercept p, speeds, targetable 150), train rules (534-593), warship block (684-748), shell kill /
  strike kill, scatter 4-6 @ 28-46, reinforce 0.2 cap / 100k, nuke grudge, alliance-break 100. -> sim/rules.gd "Phase 1 (port1)" section.
- DIFF: max_troops (139-140, 2*(tiles^0.6*1000+50000)) not used: our nerfed cap stays (~30k small / ~200k Mali).
  Blast outer radii (NUKE_OUTER_FULL 794): ours are the x2.8 scaled NUKE_R in main.gd 1827 (atom 19.6, H 70, mega 42,
  scatter 19.6, warhead 8.4) vs upstream in our tiles (atom/scatter 26.9, H 89.6, mega 53.8, warhead 16.1). Only the
  inner/outer ratios are taken (atom/mega/scatter .4, H .8, warhead .667).
  Nuke speeds (816): ours stay custom (1.5-2.5x faster, countdown); upstream clock not applied to bomb flight.
  MIRV cost step +15M (789): applied (main.nuke_cost, mirvs_launched per match); SimRules.nuke_cost_named / launch_range added.
  Range: ours = fraction of measured land width (main.gd NUKE_RANGE_FRAC 1934) + ICBM toggle; upstream has no range cap.
- DIFF (user pacing, sim/rules.gd comment "user: ~20 min matches at 1x"): growth_mult 0.8, gold_mult 0.85 kept.
  MATCH (parity pass): over-cap troops snap to the cap; DEFAULT_ATTACK_RATIO 0.2 constant; HUD stops already = UICtx.RATIO_STOPS.
- LACK: fallout_modifier (650) defense penalty, gold rates (183) audit vs our economy, difficulty tables.
SimNukes.luau (800)
- MATCH: launch_nuke checks (118: own/ally land refused), _break_nuked_alliances (248, weights 1 inner / .5 outer x k_area
  >= 100), _sam_tick/_sam_candidates/_sam_plan/_sam_ticks_to/_sam_intercept (347-541: straight ground-track plan, score,
  intercept unless SAM lost), ready_missiles (554, level slots), _detonate (616: inner + random half of outer ring ->
  fallout, structures/units in r destroyed, grudge 3000), _nuke_troops (708: bombs ((T-n)/T)^5, warheads nukeDeathFactor
  x k_area per tile, floor 3% cap). -> sim/arsenal.gd.
- DIFF: _split_mirv (570: 350 warheads, 55 tiles apart within 1500) NOT used; port MIRV kept (bus flies to aim and
  branches, fallout only in real warhead circles, main.gd _split_mirv_bus). Fallout decays after 60 s (upstream permanent).
- LACK: _mirv_mark/_mirv_overlaps (762-772) as they only serve the upstream split.
SimArsenal.luau (409)
- MATCH: shot_stamp + Rapid Reload (80), damage_struct (95: lose a level, destroy at 1), battery ready/gap/target (138-195:
  artillery 45 range, 40-70 gap, structures first, 24 samples), arsenal_tick (196), _strike (233: per-army kill, grudge,
  structure damage), _scatter_warheads (322), reinforce/reinforce_wait (372-377).
- DIFF: strike kill is applied to nation troops + attacks/boats scaled by keep share (upstream iterates armies directly).
  Artillery is not upgradable (port UI); AI does not build Arsenal items (upstream same: unlock-gated).
SimStructures.luau (1726)
- MATCH: build ticks (58), construction_tick/_activate (681-735), upgrade_struct (622: instant, SAM ramp, extra reloading
  slot), struct HP, costs (cost_count 604), trains factories_tick/_spawn_truck/_truck_tick (1426-1645: spawn rate,
  saturation, multi-stop, city/port pay).
- DIFF: roads/rails stay the custom grid-orthogonal land-only MST inside factory range (upstream _snap_to_rails/_link_nearby/
  rail_path 954-1417 station graph not used). Trains only on own roads -> ally/other train_gold rates never occur.
- LACK: _defense_post_covers (852) attack slowdown audit, structs_in_box spatial cells (perf only).
SimWarships.luau (1121)
- MATCH: hp/vet (118, 740-787), _find_target priority transport > warship > trade (537), _shoot/_fire/_shells_tick/_hit
  (636-739), _heal + port heal (350), retreat at 75% / manual no-retreat 50 (874-988), _hunt/_capture (788-873),
  patrol radius (388). -> sim/warships.gd (per sim tick).
- DIFF: ships steer straight with coast sliding (no _build_ship_grid / SimNav path 448), captured trade ships keep their
  route (upstream reroutes to captor's port 809).
- LACK: _posts_tick (1027, coastal defense posts vs ships), _safe_from_pirates (616), move_warship command path.
SimAttacks.luau (1067) - port: sim/attacks.gd. Not re-audited in phase 1 (land-border attack rule + never-slow conquest
  are custom). LACK audit: _process_attack (736) tile cost, _annex (927), merges (710), retreat (631).
SimAI.luau (1589) / SimAIEconomy.luau (767) - port: sim/ai.gd. Phase 1 only changed the AI build order (main.gd) to
  [port, city, factory, silo, defense, SAM, city, port]. LACK: _consider_war/_consider_nuke/_nuke_target/_blast_safe
  (486-950), diplomacy/requests/extensions (951-1167), tribe behaviours (1222-1574), economy _consider_build/_pick_site/
  _maybe_spawn_warship/_retaliate/_counter_infestation (320-760).
SimNaval.luau (531) - port: sim/naval.gd. MATCH (earlier): boats, ports_tick trade spawning. LACK: _trade_candidates/
  _weighted_pick (385-440) audit, _alt_landing (243). Local boat targeting rule is custom (kept).
SimNav.luau (910) - LACK: water A*/region path/LOS for ships (find_path 458, _smooth 743, los 796).
SimState.luau (1154) - MATCH: grudges/hostile (865-890), form/end alliance, request queue + 200-tick expiry + 300-tick
  cooldown + ask-back accepts (991-1035, 1087-1128; Sim.ally_request/ally_reply 1371-1410; SimAI replies 20-45 ticks and
  _accept 1013-1085). LACK: extensions/renewal window (1039-1086, port keeps its own renew card), shielded (600), bonus gold (1136).
Sim.luau (1793) - LACK (not needed for single player): intents/network, take_over, team assign. Spawn flow is custom.
GameState.luau (1483) / Teams.luau (240) - LACK: client-side state mirror, team games.
WorldMap.luau (651) / MapCodec.luau (146) / Data/Maps - MATCH: World, Europe, Asia, NorthAmerica, SouthAmerica, Africa
  converted into sim/real_maps.gd. Further upstream maps: maps worker (docs/HOOKS.md).
Defs.luau (701) - MATCH: S_* / N_* enums mirrored in sim/rules.gd. SimColors/GodotRng/NumberFormat - port has its own.

## src/client
Map/* (FxLayer 1015, RangeLayer 717, UnitLayer 742, RoadLayer 672, StructureLayer 633, FalloutGlow 713, MapSurface 1517):
  port draws its own; phase 1 added munitions/SAM-missile/bomber drawing (main.gd _draw_port_munitions) and upstream
  preview rings (SAM Lv1 70, artillery 45, airfield reach 156, scatter far 46, strike radius).
UI/* (UIRoot 2542, Widgets 3151, Arsenal 1368, CommandBar 965, ...): UI worker (docs/UI_EXTRACT.md). Rounded UI stays.
Audio/AudioDirector (1330): audio worker (docs/AUDIO_PORT.md). Custom SFX gating stays.
src/server: matchmaking/purchases/analytics - out of scope.
tests (87): tests worker (docs/PARITY.md); port-side check: main.gd --porttest; live entry sim/headless_sim.gd (docs/HEADLESS_SIM.md).

## Phase 2 (box only)
SimAI.luau / SimAIEconomy.luau - sim/ai.gd rewritten: leader/rank + runaway human, human grace by distance + peace window,
  capitulation, defend/expand/war target choice, fallout resettle, economy builds (perceived cost, upgrades on crowded
  land, port/factory/defense site pickers), warship spawn + counter-infestation, boats, mop-up, invasion, nuke planner
  (target + kind choice, _blast_safe on NUKE_R), diplomacy (ask/accept/break), tribe behaviour (nearby + shore probes,
  traitor rolls, incoming, random attacks, boats, structure deletion). Stats in sim_ai.stats.
  Deviations: INVASION_AGE 6000 / MOPUP_AGE 3000 kept halved (custom pacing); AI nukes obey the custom range rule
  (fall back to the cheapest bomb that reaches, unless icbm_mode); no retint, no team refusal (no teams).
SimAttacks - audited: troops_in_attacks counts pending merges; upstream merge semantics (beachhead joins at once, same-tick
  orders absorb, otherwise queued and applied end of tick); end_attack refunds floor(troops*keep)+pend; retreat
  delay/frozen_from; grudge refresh only on real change; annex passes (attacker, else non-allied neighbour) + killer.
  Fallout defense modifier on fallout tiles (fallout_modifier(fallout/land)) matches upstream.
SimState alliances - now tick based: expiry tick, extension window with both-sides renewal bits, AI accept for extension,
  traitor/grudge ticks, attacks between new allies end. Player renew card uses extend_alliance.
SimWarships - coastal defense posts shoot transports first then warships (100-tick shell cooldown, range
  DEFENSE_POST_TARGET_FULL). Upstream default DEFENSE_POST_SHOOTS=false; port runs it ON (requested feature).
  Captured trade ships are rerouted to the captor's nearest port on the same water body, gold re-priced on total
  distance sailed, paid only to the captor.
Perf (10x): attacks pass time-sliced across frames (begin_tick/run_slice, Coop-style), sim 12 ms/frame, paint 5 ms/frame,
  24 chunk uploads, capture flashes capped 2000, naval hostile() cached per tick, inlined attack neighbour pushes.
Camera clamp: map bounds incl. Antarctica, slack only for the top/bottom bars.
