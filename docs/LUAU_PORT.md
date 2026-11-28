# Luau sim port: progress log

Goal: run upstream RoWorld's Luau sim (src/shared/Core/*.luau, extracted copy in luau/place/ReplicatedStorage/Airfront/Core)
inside the Godot game, one module per commit, every custom in CLAUDE.md kept. Read this file first after a context reset.

Branch `luau-sim`. The remote already had a `luau-sim` (Nov 23 prototype: 182 place scripts extracted to luau/place, native
build recipe in tools/luau_proto/README.md), purely additive on b3300b7, an ancestor of `multiplayer`. Recreating the branch
would need a force-push, so it was merged instead: 84d5260 = `multiplayer` 0fbdd55 + that prototype (no conflicts).

## How to verify (every module)

```
godot --headless --path . --script tests/run_upstream_tests.gd            # parity, 0 fail, 5 intentional
godot --headless --path . -s tests/sim_hash.gd                            # owner=3683567526 since the multiplayer merge (3480782660 before), World 400 tribes, seed 5516, 6000 ticks
godot --headless --path . -s tests/sim_hash.gd -- --sliced                # same hash with both passes cut in tiny slices
godot --headless --path . -s tests/perf_sim.gd -- --seed=12345            # AVG ms/tick over 3000 ticks
```

Test list: test_ui_upstream, test_port_left, test_input_world, test_client_clicks, test_tutorial, test_map_camera,
test_console_spawn, test_nav, test_net_match, test_net_rep, test_net_lobby, test_net_teams, test_progress_sync,
test_luau_bridge (from Step 1), test_luau_rng (from Step 2), test_luau_rules (from Step 3), test_luau_state (from Step 4), test_defense_posts (from the multiplayer merge), test_title_reset, test_map_size_live, test_strike_sounds, test_crate_names, test_console_keys.
Known baseline failures that must not grow: test_lobby_ui 3, test_account_ui 55.

Perf rule: never more than 25% above the pre-Step-A baseline at any step; the end result must be faster than it.

## Baselines

| what | value | engine | commit |
|---|---|---|---|
| perf before Step A (seed 12345, 3000 ticks) | AVG 13.31 ms/tick (per minute 26.02 / 14.63 / 11.10 / 7.63 / 7.15) | 4.3 | 84d5260 |
| hash before Step A (old perf_sim loop, seed 5516, 6000 ticks) | owner=2340230155 (not repeatable: time budgets) | 4.3 | 84d5260 |
| parity before Step A | 470 total, 465 pass, 0 fail, 5 intentional | 4.3 | 84d5260 |

## Log

### Step A: tick-deterministic sim (GDScript only)

What changed:
- One tick everywhere: game/audio.gd `_sim_tick_begin` (match clock +0.1 s, rail budgets reset, defense posts, attack pass
  start) and `_sim_tick_end` (naval, economy, arsenal, missiles, requests, warships, trains, trade ships, transports,
  donation cooldowns, host deltas). main.gd still slices the attack and AI passes over frames; `_sim_tick_whole` runs it
  unsliced (sim_step, tests, perf_sim, sim_hash). Before, the frame loop, `_pt_ticks` and perf_sim each had their own order.
- `elapsed` (the match clock the AI's peace checks and the path / rail caches use) moves 0.1 s per tick, not real dt.
- Transports (`_tick_boats`) and trade ships (`_tick_trade`) move once per tick (0.1 s), not per frame with real dt; the
  unit layer draws them part way into the next tick (sub_tick) so they still glide.
- Budgets are counts: SimNav `budget_n` = 12 cold searches per tick (was 3000 us); naval `path_budget` = 2 per tick as
  upstream (the frame-time `defer_paths` is gone); rail search / web budgets reset per tick, not per frame; rail drawing
  only reads the cache (`_rail_neighbors_view`), the tick warms every station once a second (`_rail_warm`).
- `PLAYER` is a variable (state.gd), value still 1.
- The AI skips the local player and every nation flagged `human` (remote people in multiplayer). Before this the AI kept
  thinking for remote humans' nations (they were in SimAI.st).
- Sounds and the nuke hover preview draw from `fx_rng`, not the sim's `rng`. The alliance-expiry card check (UI only)
  runs every 5th frame instead of on `rng.randf() < 0.2` per frame (that draw advanced the sim rng per frame).
- Donation cooldowns count down per tick by 0.1 x SPEED_13.60 / 13.65 (the machine ran slow; 5g2 measured 12.29 / 12.29 earlier) (same length as before: they ran on the visual clock).
- New tests/sim_hash.gd; tests/perf_sim.gd times the game's tick (atk / ai / rest) and prints AVG ms/tick.

Results (Godot 4.3.stable): parity 472 total, 467 pass, 0 fail, 5 intentional (2 more live cases ran: the air strike
path); NEW 13.60 / 13.65 (the machine ran slow; 5g2 measured 12.29 / 12.29 earlier)LINE hash owner=3480782660 (troops=213616296.6 gold=266746204.0 alive=28 structs=412) identical in two
whole runs and one --sliced run; test list unchanged from before Step A (13 pass, test_lobby_ui 3, test_account_ui 55);
perf AVG 13.76 ms/tick (+3.4% on 13.31; per minute 24.92 / 14.40 / 10.74 / 9.42 / 9.31; a different match since the rng
draws changed; `rest` is higher, the rail warm-up once a second and trade ships now being stepped inside the tick).

### Step 0: Godot 4.5.1

What changed:
- Editor and export templates 4.5.1.stable (official f62fdbde1). Templates from Godot_v4.5.1-stable_export_templates.tpz
  in ~/.local/share/godot/export_templates/4.5.1.stable. The web templates include `web_dlink_release.zip` /
  `web_dlink_debug.zip` (GDExtension support, threads), the same thread mode as the extension build (pthread side module)
  and as the game's web preset (`variant/thread_support=true`, COOP/COEP served by release/serve.py and nginx).
  `variant/extensions_support` stays false until Step 1 puts the extension in the pack.
- First import created a `.uid` file next to every script and shader (Godot 4.4+ keeps them in the repo). No script,
  scene or shader needed changes: the import and every test ran without parse or script errors.
- project.godot `config/features` = 4.5; CLAUDE.md, README.md, server/deploy/README.md, docs/MULTIPLAYER.md,
  docs/VM_DEPLOY_PROMPT.md name 4.5.1 for this branch. The live VM and `multiplayer` / `vanilla` stay on 4.3 (a 4.5.1
  pack does not load in 4.3), so deploying this branch needs the 4.5.1 arm64 binary on the VM.
- Web export with 4.5.1 works (index.wasm 37.3 MB, index.pck 52.5 MB, no export errors). Not run in a browser here.

Results (Godot 4.5.1.stable): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (troops, gold,
alive, structs, attacks, traders all equal), the same as the 4.3 Step A baseline, in a whole and a --sliced run, so the
4.3 baseline stands for later steps; test list unchanged (13 pass, test_lobby_ui 3, test_account_ui 55); perf AVG
13.53 ms/tick (Step A on 4.3: 13.76; pre-A 13.31).

### Step 1: Luau runtime + bridge

What changed:
- Runtime: fernforestgames/luau-gdextension at bc1b88d (luau 0.719, godot-cpp godot-4.5-stable), no source changes.
  `tools/luau_ext/build.sh <checkout> [web|x86_64|aarch64]` clones, builds and copies the three libraries:
  - web: `luau/ext/libgdluau.wasm` (1.78 MB), emsdk 4.0.11, wasm side module with pthreads, `-fvisibility=hidden`,
    wasm longjmp (the recipe proven in tools/luau_proto, see its README).
  - Linux x86_64: `server_build/x86_64/libgdluau.linux.x86_64.so` (headless tests and x86 servers).
  - Linux aarch64: `server_build/aarch64/libgdluau.linux.arm64.so` (the Oracle VM), cross-built with
    g++-aarch64-linux-gnu (`tools/luau_ext/aarch64-linux-gnu.cmake`).
  - Both Linux builds link `tools/luau_ext/glibc_compat.c` so they need no glibc above 2.27 (Godot 4.5.1 needs 2.28;
    the build machine has 2.39, which made the first build ask for 2.38). The script checks it with objdump.
- `luau/ext/gdluau.gdextension` lists the three. An exported server loads the library of the same file name placed next
  to the Godot binary (tested with an exported x86_64 Server Pack: `LUAU ok`; without the file the server still runs and
  prints `LUAU missing`). The dedicated server prints that line at start.
- Web preset: `variant/extensions_support=true` (Godot then uses the web_dlink templates: index.wasm 1.66 MB +
  index.side.wasm 40.5 MB + index.js 4.2 MB instead of one 37.3 MB wasm and a 0.36 MB js, plus libgdluau.wasm, so about
  10 MB more before compression). Both presets add `luau/sim/*` to the pack and exclude `luau/place/*` and `server_build/*`.
- `luau/place/.gdignore`: with the extension loaded the editor treats `.luau` as scripts; the upstream reference copy
  stays out of the import and the pack (sim modules go in `luau/sim/`). tools/luau_proto's prototype .gdextension is
  renamed `.example` so only one copy of the classes registers.
- `sim/luau_vm.gd` (LuauVM): one Lua state; `load_file` / `load_source` run a module and keep its table, `call_fn` calls
  module.fn(args) and returns the first result, buffers cross as PackedByteArray (copied at the boundary), errors come
  back as null + `last_error`. `luau/sim/hello.luau` + `tests/test_luau_bridge.gd` (10 checks).
- Known: the extension logs `ERROR: Class 'Object' doesn't exist.` once at start (one method bind in the extension; all
  documented LuaState / Luau methods the bridge uses are registered). Harmless.
- Not verified here: the web build in a browser (no browser with WebGL2 in this container; the same recipe ran in
  Chromium in the Nov 23 prototype) and the aarch64 library at run time (no arm64 machine or emulator here; it is the
  same source and glibc floor as the x86_64 one).

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged); test list
unchanged plus test_luau_bridge 10/10; perf AVG 13.22 ms/tick (the extension loads but the sim does not use it yet).

### Step 2: Roblox-globals shim, module loader, bit-exact Godot RNG

What changed:
- `luau/sim/rt/prelude.luau` runs first in the Lua state. It defines `__register(name, fn)` / `__has(name)` and a
  `require(name)` that runs each registered module chunk once and caches its result (a cycle is an error). Globals the
  upstream modules use from Roblox: `Vector3.new` / `Vector2.new` (Luau native vectors), `Color3.new` / `Color3.fromRGB`
  (frozen {R, G, B}), `Random.new(seed)` with `NextInteger` / `NextNumber` (backed by GodotRng with the raw seed, not
  Roblox's generator: the sim must match the GDScript rng, not Roblox), `task.spawn` / `task.defer` (run at once; no
  scheduler in the sim), `task.wait` (error: nothing in the sim may yield). `typeof` is Luau's own.
- `LuauVM.boot()` (sim/luau_vm.gd) runs the prelude, registers every `.luau` under luau/sim (name = path without
  extension, e.g. `Core/GodotRng`), then calls `sandbox()` (globals and library tables read-only). Upstream string
  requires (`require("./Defs")`, `require("../Net/Coop")`) are rewritten at load time to the resolved name, so copied
  upstream files need no edits. `require_module(name)` returns a module's table to GDScript.
- `luau/sim/Core/GodotRng.luau` and `luau/sim/Net/Coop.luau`: copied unchanged from upstream (c422466). GodotRng is
  Godot's PCG32 (randi, randf, randi_range, randf_range, seed hashing, hash_int for `hash(int)`).
- `luau/sim/rt/gd.luau`: what the GDScript sim does with Godot's rng, in Luau. `gd.rng(seed)` = a RandomNumberGenerator
  after `rng.seed = seed`; `gd.global` + `gd.seed(s)` = the engine's global rng after `seed(s)`; `gd.shuffle(arr)` =
  `Array.shuffle()` (Fisher-Yates from the end, j = global randi() % (i + 1)), used by navy.gd:31, nations.gd:282,
  economy.gd:378; `gd.calibrate_fused(samples)` sets GodotRng.FUSED from real `randf_range` outputs (whether the build's
  C++ compiler fused a*b+c; x86_64 official build: not fused). Dummy draws (the tribe grey #d1cdc7 path keeps its rng
  calls) need nothing special: they are ordinary calls and the test replays them.
- tests/test_luau_rng.gd + tests/luau/rng_check.luau (27 checks): loader and require rewriting, the shim globals,
  10 seeds x 3000 mixed ops (randi, randf, randi_range, randf_range, reseed) identical value for value and in the final
  rng state, hash(int) for 8 values, seed() + Array.shuffle for 3 seeds, tribe spawn order + 800 colour dummy draws for 2
  seeds, FUSED calibration.
- Note: upstream GodotRng.randi_range loops forever when the range is the full 32-bit span (bound mod 2^32 = 0). Godot
  handles that case; no sim call uses such a range, so the copy stays unchanged and the test does not use it.
- Speed: 200,000 randi + randf pairs take 139.9 ms in Luau, 11.1 ms in GDScript (native). The sim draws far fewer per
  tick, but rng-heavy modules may need a native rng later. Watch it in Step 5.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged); test list
unchanged plus test_luau_bridge 10/10 and test_luau_rng 27/27; perf AVG 13.52 ms/tick (the sim does not use Luau yet).

### Step 3: Rules data (Core/Rules.luau)

What changed:
- `luau/sim/Core/Rules.luau`: sim/rules.gd (SimRules) transliterated line for line, not upstream's Rules.luau: our
  file already holds the customs and the 1:1 troop mode, and the hash needs our numbers. 155 constants (all of
  SimRules', plus `NUKE_KINDS` = 9, the size GDScript gets from `.size()`), `Rules.new(kl)` with the same 19 instance
  fields and `set_k`, and every function (static ones without self).
- Conventions for every ported module, written at the top of Rules.luau: data arrays are 0-based like GDScript
  (`{ [0] = ... }`) so index code reads the same; GDScript int division is `//`, `int(x)` is trunc; Vector2 is Luau's
  float32 vector; PackedFloat32Array entries are rounded with gd.f32.
- No Defs.luau: this port has no GDScript Defs (the N_* / S_* ids are in SimRules, now Rules.luau; the per-tile
  constants are in game/state.gd and move with Step 4). sim/sim_colors.gd and sim/bot_names.gd move with their
  callers (nation setup).
- SimRules stays and is still what the game calls (brief: replace it in the commit that moves its callers).
- tests/test_luau_rules.gd + tests/luau/rules_check.luau: every constant (name set and value), every instance field
  for 8 configurations (map scales 0.31 to 3.0, 1:1 mode on / off, pop cap modes 0/1/2, tile_norm, growth and gold
  multipliers), and 20,467 function calls (edge values plus seeded random inputs, nuke arcs with 97 samples, arc
  points, arc ticks) per configuration, compared as raw f64 bytes. All equal. A one-ulp change in a constant or in the
  arc interpolation makes it fail (checked).
- exp, log and pow give the same bits as GDScript's (the Linux library binds the old glibc versions, Step 1; the test
  covers sigmoid, trade gold, saturation curves, troop growth and caps).

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged); test list
unchanged plus test_luau_bridge 10/10, test_luau_rng 27/27, test_luau_rules 8/8; perf AVG 12.58 ms/tick (the sim
does not call Luau yet; run-to-run spread on this machine is about 1 ms).

### Step 4: the tile layer in Luau (Core/SimState.luau) + the sync link

What changed:
- `luau/sim/Core/SimState.luau`: the match's tile layer as Luau buffers: `owner` (i32 per tile, -2 ice, -1 water,
  0 neutral, > 0 nation) and `fallout` (u8 per tile). Luau modules read them with get_owner / get_fallout and write
  with set_owner / set_fallout, which also record the change for GDScript.
- `sim/luau_link.gd` (LuauLink, one per match process, created at the first tick): boots the Lua state and keeps the
  two copies equal while the sim is half ported. GDScript records every change it makes as (tile, value) pairs
  (`luau_dirty` in map.gd `_set_owner`, `luau_fdirty` at the two fallout writes: nuke_blast and the clear in
  `_set_owner`). `flush()` sends them to Luau (C++ copies of PackedInt32Array, no per-tile GDScript work),
  `pull()` applies what Luau modules wrote through the game's own `_set_owner` (so borders, land / pop / bounding box,
  structure capture, net replication and the fallout clear all follow) and sets fallout like nuke_blast does.
  A Luau module call is wrapped flush -> call -> pull, so writes of both sides land in the order they happen;
  `sync()` = flush + pull runs at the end of every tick (game/audio.gd `_sim_tick_end`, before the host's
  replication), so at every tick boundary the copies are equal. A new map (`sim_epoch`, bumped in gen_map) restarts
  Luau from full copies. Without the extension the link stays off and the sim runs as before.
- Pairs not a per-tile flag: two appends per owner change in `_set_owner` (which already does far more), and
  coalescing would need a GDScript loop over the changed tiles at every flush.
- Nothing in the sim reads Luau yet; the hash is the proof that recording changes nothing.
- tests/test_luau_state.gd (12 checks): copies equal every 100 ticks over 600 ticks of a seeded World match; a nuke's
  owner changes and fallout reach Luau; 300 ticks later still equal; a Luau owner write reaches owner_map through
  `_set_owner` with land counts; a Luau fallout write reaches fallout / fallout_list; owning a fallout tile from Luau
  clears it in GDScript and the clear reaches Luau with the next flush; a new map restarts the copy.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged plus test_luau_bridge 10/10, test_luau_rng 27/27, test_luau_rules 8/8,
test_luau_state 12/12; perf AVG 13.53 ms/tick (Step 3 12.58, Step 2 13.52: the link's cost is inside this
machine's ~1 ms run-to-run spread).

### Step 5a: Attacks in Luau (Core/SimAttacks.luau)

What changed:
- `luau/sim/Core/SimAttacks.luau`: sim/attacks.gd transliterated (attack list, per-attack front heaps, the conquest
  budget loop, merges, annexation, retreats). Same draw order on the shared sim rng: the rng state goes in as two
  uint32 halves with every call and comes back with the result.
- `luau/sim/Core/SimState.luau`: now also owns per-nation land, bounding box, last_by and the border sets (global
  per-tile linked lists, so a nation's border iterates in the same insertion order as GDScript's border Dictionary).
  One set_owner core (map.gd `_set_owner` + `_upd_border_fast`, same neighbour order) runs both for GDScript's
  recorded changes and Luau's own. Per call it is pushed only what the attack code reads: per nation troops, gold,
  alive, kind (team / left in team games), the ally keys, traitors, finished defense posts, fallout_count, land_total.
  Results stream back in order as i32 pairs: owner changes, fallout writes, and events (viewer attack notice,
  hostile = attacked_tick + grudge, conquest = gold hand-over + `_on_conquest` + last_by / killer), then the final
  troops of every nation the call touched.
- `sim/attacks.gd` is the GDScript face: start / end_attack / retreat / begin_tick / run_slice call Luau through
  `luau_link.lcall` (flush -> call -> apply). g.attacks holds one mirror Dictionary per attack (aid, a, t, troops,
  pend, retreat_at, frozen_from, started, counter, last, sent, tgt, plus the view's disp / shown / vel), updated in
  place so references held by the AI, HUD and net/rep.gd stay live. attack_between / troops_in_attacks /
  count_attacks_by read the mirror. New `scale_owner` / `set_troops` for the arsenal's troop cuts
  (sim/arsenal.gd: strike kills, nuke troop loss, warhead loss). The time slice is kept: GDScript passes the
  remaining microseconds and Luau checks os.clock every 8 attacks.
- The GDScript attack code is still there and runs when the extension is missing, on a remote viewer, or with the
  env var NO_LUAU_SIM set (A/B runs). It goes in Step 6.
- tests/test_luau_attacks.gd (12 checks): land / bb / last_by / border order equal to GDScript every 100 ticks over
  600 ticks; g.attacks mirrors Luau's list; no border-set anomalies; start, retreat, end_attack (troops back),
  scale_owner, set_troops through Luau; still equal on the next tick.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced, and the same with NO_LUAU_SIM=1; test list unchanged plus test_luau_attacks 12/12 (lobby_ui 3 and
account_ui 55 as before); perf AVG 11.11 / 10.93 ms/tick over two runs (Step 4 13.53). The attack pass in the
first minute went 19.72 -> 12.75 ms/tick even with the Luau rng about 12x slower per draw than the native one.

### Step 5b: Structures in Luau (Core/SimStructures.luau)

What changed:
- `luau/sim/Core/SimStructures.luau`: sim/structures.gd `place_site` (upgrade in reach, else the flood of own
  land within PLACE_SEARCH_R and the nearest tile clear of STRUCT_MIN_DIST; ports on own coast within
  PORT_SPAWN_MANHATTAN), and the construction countdown of sim/arsenal.gd tick (0.1 s per tick, activation at 0).
- `sim/structures.gd` is the face: `place_site` and `construction()` hand Luau a snapshot of game.structs first
  (f64 per structure in list order: k, tile, o, level, bt; about 0.1 ms per 400 structures) and the tile layer
  through flush. sim/arsenal.gd tick applies the new build times and calls `_activate` (the artillery's first gap is
  an rng draw) in list order, as before; the reload rings (`_refresh_cd`) stay with the arsenal (Step 5c).
- Decision: the structure list stays GDScript's in this step. It is read and written in many places outside the
  sim: the renderer, net/rep.gd (the whole dicts travel, so no new key like an id can be added without changing the
  packet), the shop's instant build, the debug modes in main.gd / game/audio.gd and the parity tests all write
  `bt`, `level`, `hp` or append dicts directly. A snapshot per call keeps all of those working without changes.
  Luau takes the list over when the per-tick readers move (arsenal 5c, AI 5f); capture on owner change stays in
  map.gd `_set_owner` until then.
- tests/test_luau_structures.gd (9 checks): Luau place_site == GDScript on 3246 clicks of a seeded match (every
  kind, own and foreign land, 92 upgrades, all four outcomes); a new post counts down 0.1 s per tick; a direct
  bt = 0 between ticks wins and the post counts as finished; an artillery battery activates when its countdown ends.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged plus test_luau_structures 9/9; perf AVG 11.72 / 11.81 ms/tick (5a 11.11 / 10.93). The
snapshot adds 0.1 to 0.3 ms to "rest" late in the match (more structures); the attack and AI columns moved by
run-to-run noise only (their code did not change).

### Step 5c: Arsenal and Nukes in Luau (Core/SimArsenal.luau)

What changed:
- `luau/sim/Core/SimArsenal.luau`: sim/arsenal.gd and the sim half of game/nukes.gd. Bombs in flight (launch,
  Scattershot warheads, SAM candidates, plans and hits, MIRV split, detonation, blast troops / structures /
  fallout, breaking alliances on a nuked ally), munitions (shells, air strikes, slugs), reloads, construction,
  battery targeting and fire. Godot's SortArray introsort is copied (`godot_sort`) so SAMs with tied scores fire in
  the order Godot's sort_custom gave them.
- Luau owns the missiles and munitions in flight (ids). game.missiles and sim_ars.munitions hold mirror dicts with
  the same keys in the same order (net/rep.gd sends the missile dicts whole; packets unchanged). Kept mirrors are
  the same Dictionary objects from launch to impact; the lists are changed in place.
- The structures stay GDScript's (as in 5b): each call sends a snapshot (k, tile, o, level, bt, hp, serial) and the
  silo / SAM / battery / airfield / railgun state, and gets back the writes and events in the order the GDScript sim
  made them (struct removed / downgraded, boats scaled, grudges, strike fx, SAM fired / hit, detonation, fallout,
  units in the blast, alliance broken).
- `sim/arsenal.gd` and `game/nukes.gd` are the face (`_lrun`, `luau_launch`, `luau_missiles`). The GDScript code
  stays as the fallback (remote viewers, NO_LUAU_SIM, no extension) and for the parity source checks.
- The list is updated before the events of a call are played, as the GDScript sim erases a bomb before its blast /
  SAM-hit fx. The client's view id (`cuid`, client/game_state.gd nukes()) is stamped lazily when the HUD reads the
  list inside such a callback; GDScript erases bombs one at a time between callbacks, the facade once per call, so
  the counter can run 1 or 2 apart from GDScript's. Each bomb still keeps one id for its whole flight. Not sim state.
- Limitation: a missile dict appended to game.missiles by hand (not through launch_nuke) is not flown; a warning is
  printed once. Nothing in the game does that (the screenshot props have no "lt" and were never flown).
- tests/test_luau_arsenal.gd (18 checks): Luau's sort == Godot's on ties (sizes 1..200); the custom constants match
  game/nukes.gd and game/state.gd; the same seeded match played with Luau and with NO_LUAU_SIM, with scripted silos,
  SAMs, batteries and an airfield on both sides and launches of every bomb kind and air strikes from tick 1200:
  game.missiles, munitions, structures, SAM shots and stats byte-identical after each of 2800 ticks (cuid left out),
  same map at the end; ICBM flight ticks, Scattershot and MIRV warheads sharing the roll and ICBM flag, and the
  player's ICBM evade rolls (11 of 60) identical in both runs.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged plus test_luau_arsenal 18/18; perf AVG 11.36 / 11.07 ms/tick (5b 11.72 / 11.81).
tests/test_icbm_evade.gd and tests/test_nuke_flight.gd (not in the VERIFY list) fail the same checks as on 5b:
their expectations predate the 0.9x nuke speed and the 20% ICBM roll, and their scenes run on frames, so their
numbers differ from run to run with either sim.

### Rails split (before Step 5b2, GDScript only)

What changed:
- The rail / train sim moved out of game/rails.gd into `sim/rails.gd` (class SimRails, `game.sim_rails`): rail paths
  (A* on the minimap), station links (_build_rail_mst / _rail_hops), the link cache with its per-tick budgets,
  routes, destinations, train spawns, legs and train gold. The code is the same, with `g.` in front of the game's
  members (W, H and owner_map read into typed locals once per call).
- game/rails.gd keeps the drawing side (`_rail_neighbors_view`, the land-path helpers, the fx and notes ticks) and
  forwards the old names (`_rail_curve`, `_rail_neighbors`, `_has_rail_link`, `spawn_train_from`, `_trains_tick`)
  so the renderer, main.gd, game/audio.gd and tests/upstream/test_live.gd are unchanged.
- The state stays on the game (rail_cache, _rail_nb_cache, _rail_mst, trains, the budgets): road_layer, planes_fx,
  unit_layer and game/nations.gd read or clear it there.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged; perf AVG 11.76 / 11.74 ms/tick (5c 11.36 / 11.07; the code path is the same plus one
forward per call, so most of the gap is run-to-run noise).

### Step 5b2: Rails, factories and trains in Luau (Core/SimRails.luau)

What changed:
- `luau/sim/Core/SimRails.luau`: sim/rails.gd line for line. Rail paths (A* on the minimap with its heap and tie
  rules), the geometry (points merged on rows / columns, lengths in float like Vector2), station links (nearest
  first, sorted with SimArsenal's copy of Godot's introsort so tied distances keep Godot's order, 4-hop check),
  the per-owner link web with its frame-tagged unfinished versions, the per-station link cache with the per-tick
  budgets (40 route searches, 40 link builds) and the pending flag, routes, destinations, spawns (rng rolls per
  factory level), legs, train gold and the float for the player.
- Luau owns the rail caches and the trains (ids). game.rail_cache, game._rail_nb_cache and game.trains hold mirrors
  with the same keys in the same order, built from what each call returns; train mirrors are the same Dictionary
  from spawn to arrival. game._rail_mst is no longer filled in Luau mode (nothing outside sim/rails.gd reads it).
  The budgets and the pending flag go in and come back each call. sim/naval.gd's per-tick hostile cache: Luau gets
  its pairs (or the same pairs from game.attacks when it is not built yet this tick) and the facade builds the cache
  after a call that asked, as the GDScript sim's first ask would.
- The structures stay GDScript's: each call sends a snapshot (id, k, tile, o, level, bt, trucks, last_spawn; id =
  tile + serial * 2^24 names a Dictionary across calls) plus the last fields of the Dictionaries dropped since the
  last call, which the caches and trains can still hold, and gets back the trucks / last_spawn writes (keys added in
  the GDScript order). Gold comes back as (payer, other side, tile, amount) records, applied in order.
- `sim/rails.gd` is the face (curve, neighbors, has_link, spawn, tick); game/rails.gd forwards the old names there.
  The GDScript code stays as the fallback (remote viewers, NO_LUAU_SIM, no extension).
- The renderer reads the mirrors only: game/rails.gd `_rail_curve_view` / `_has_rail_link_view` (draw_helpers,
  client/map/road_layer.gd, client/map/unit_layer.gd, planes_fx). Before, drawing a train or a rail could start a
  route search or a link build and spend the tick's budgets between ticks, so what the sim built depended on what
  was on screen. Headless runs (parity, hash) never drew, so their results don't change; in a window the sim no
  longer depends on the camera. A rail the sim has not searched yet is drawn once the tick has built it (each
  station is warmed every 10 ticks). Kept (Question 3, answered).
- Known differences, in cases the seeded matches never reach: GDScript compares structure Dictionaries by content
  in `st_b in links` and `trains.erase(tr)`; Luau compares identity (the same Dictionary). They differ only when a
  station is destroyed and rebuilt on the same tile with exactly the same fields while a stale link list still holds
  the old one, or when two trains have identical fields. A new map clears the link webs too (GDScript kept
  game._rail_mst across matches, so a web from the previous match could come back when owner id, _own_sv and the
  6 s bucket matched).
- tests/test_luau_rails.gd (8 checks): the same seeded match played with Luau and with NO_LUAU_SIM for 3000 ticks:
  trains (keys, route, leg, positions, t, dur, stops), rail_cache, the link cache (ver, time, stations), factories'
  keys / trucks / last_spawn, the budgets, the pending flag, the rng and every nation's gold identical after each
  tick; direct calls with a big budget (links and paths of the biggest nation's stations, spawns from its
  factories) equal; the drawing-side readers change nothing.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged plus test_luau_rails 8/8; perf AVG 11.46 / 11.84 ms/tick (rails split 11.76 / 11.74;
the trains cost well under 0.4 ms/tick, so the change is within run-to-run noise).

### Step 5d1: water navigation in Luau (Core/SimNav.luau)

What changed:
- `luau/sim/Core/SimNav.luau`: sim/nav.gd line for line. The region graph build (regions, clusters, edges with
  float32 costs, portals, coasts), the heap A* with its tie rules, the region and route caches with the same caps,
  line of sight, raster, BFS stitch, smoothing, the Chaikin `to_points`, `find_route`, `boat_route`,
  `nearest_own_coast`, `water_path_px` and the per-tick search budget. Float32 storage and Vector2 math are
  emulated, so the answers are byte for byte GDScript's.
- `sim/nav.gd` is the face: `find_route`, `boat_route` and `water_path_px` go to Luau once the game's link is on
  (not a remote viewer, not NO_LUAU_SIM); `begin_tick` forwards the budget. The old bodies are `*_gd` and stay the
  fallback. The pure helpers (to_points, dense, los, seg_water, region_of, water_next_to) and `steer` stay
  GDScript; steer searches through `find_route`, so it follows. game/map.gd calls `sim_nav.luau_attach(self)` after
  both nav builds.
- The graph is built in Luau on the first query after the link is up, and only if this nav has not answered a
  stateful query in GDScript yet (the caches and the budget history would differ). In the seeded runs nothing
  queries before the link exists, so the whole match runs in Luau.
- `boat_route` with the game's own owner map sends nothing and Luau reads SimState's copy after `flush`. The only
  owner_map writes that skip `_set_owner` are map generation (before the link) and the main.gd showcase, which
  calls `_set_owner` on the same tile right after.
- Known costs and gaps: the map's nav is built twice (GDScript about 235 ms, Luau about 196 ms at load on the
  seed 5516 map), because the link starts after map build. The GDScript counters on the match nav (searches,
  fails, cache hits) go stale in Luau mode; `luau_stats()` has Luau's. `last_deferred` is set only by the facade
  calls. If the link fails mid-match the nav falls back to GDScript with cold caches (still a valid game, but it
  leaves the pure GDScript run). tests/test_nav.gd builds its own navs without `luau_attach`, so it still tests
  the GDScript code.
- tests/test_luau_nav.gd (14 checks): the Luau graph against a fresh GDScript build of the same map (regions,
  centres, edges, costs, portals, coasts, clusters) and 3000 find_route, 800 water_path_px and 600 boat_route
  queries against GDScript, with the deferral flags and the search / fail counters.
- Drafted in a separate worktree (luau-nav-draft, never pushed) and taken over unchanged.

Results (4.5.1): parity 472 total, 467 pass, 0 fail, 5 intentional; hash owner=3480782660 (unchanged) whole and
--sliced; test list unchanged plus test_luau_nav 14/14; perf AVG 12.39 / 11.85 ms/tick (5b2 11.46 / 11.84; the Luau
searches cost about what the GDScript ones did, the difference is within run-to-run noise).

### Step 5d2: trade ship ports in Luau (Core/SimNaval.luau)

What changed:
- `luau/sim/Core/SimNaval.luau`: sim/naval.gd's ports tick line for line (`_ports_tick`, `_pick_partner`,
  `_refresh_partners`, `_trade_path`, `hostile`): every 10 ticks each finished port rolls `level` times against the
  spawn rate with its pity timer, picks a partner port of a non-hostile owner on the same water body and finds the
  trade route (its own trade cache with the same 2000 cap, searches through Core/SimNav with the 2-per-tick budget).
- The ports stay GDScript Dictionaries in game.structs. Each call sends them in order with their trade fields (slot,
  rej, partners, ptick, water, body) and the attack pairs hostile() sees, and gets back the fields it changed (keys
  added in the GDScript order) and the new trade ships, which sim/naval.gd makes with the same cum and gold as
  before. A tick where no port rolls makes no call (the GDScript draws nothing then either). game/map.gd bumps
  `sim_naval.trade_gen` with each `trade_cache.clear()`, so Luau drops its trade cache and takes the new water bodies.
- Runs only while the nav is in Luau (Step 5d1) on the same Luau state; otherwise `_ports_tick_gd` as before.
- `sim_nav.last_deferred` is no longer set by the trade route searches (it was set inside `_trade_path`); nothing
  reads it there.
- Sailing, arrival pay, transports and warships stay GDScript (5d3, 5d4).
- tests/test_luau_naval.gd (6 checks): the seeded match with Luau and with NO_LUAU_SIM for 4000 ticks: ports,
  trade ships, gold, owner map and rng identical after each tick, same trade ships made.
- Drafted in the separate worktree with 5d1 and taken over unchanged apart from comments.

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_naval 6/6
(4000 ticks, 1002 trade ships, identical each tick), perf_sim 13.34 / 13.81 ms/tick.
- Cost: on a tick where a port rolls, the call costs more than the GDScript did (about 1.1 vs 0.7 ms on seed 12345,
  timed around the ports tick). The Luau work itself is about the GDScript's (the trade route searches, in Luau
  in both since 5d1, dominate); the extra is the snapshot of every port (about 0.15 ms) and the flush + world()
  before the call (about 0.2 ms). Ticks where no port rolls skip both. Planned fix, before Step 6: keep the ports'
  trade fields in Luau between ticks (only naval writes them) and send one world() per tick for all the modules.

### Step 5d3: warships, shells and defense posts in Luau (Core/SimWarships.luau)

What changed:
- `luau/sim/Core/SimWarships.luau`: sim/warships.gd's tick line for line: healing near an own port and docked,
  the repair retreat below 75 %, targeting (transport > warship > trade ship, safe-from-pirates along the shore),
  shells and their landing, veterancy, patrols, trade ship captures and their new route to the captor's port, the
  defense posts' shells, and sim/nav.gd `steer` (routes through Core/SimNav). Every Vector2 operation is rounded to
  float32 like Godot's.
- Nothing is kept in Luau between ticks except the trade ships' points (sent once per ship). The trade ships
  come over only when a ship needs them that tick (a trade target, a scan that gets to trade ships): Luau stops
  in the same coroutine, sim/warships.gd sends them and Luau goes on. Most ticks no ship needs them, and there
  are a few hundred. The GDScript keeps the
  ship Dictionaries, `shells`, `tref`, the posts' memory and the stats; each tick sends them and applies what comes
  back: the ship fields (written only when changed, same types; the nav keys set and erased in steer's order), the
  shells and targets (old entries kept by identity), and the events in order (shot / lost sounds, notes, hit marks,
  sunk transports and warships, captured trade ships, which sim/warships.gd makes with the same cum, gold and key
  order as before).
- `game.ai_ship_loss` stays GDScript (AI, Step 5f). Where the tick calls it (a sunk transport, a capture), Luau
  stops in a coroutine, the batch so far is applied, the AI runs (it may move or add warships and draws the rng)
  and Luau goes on with the ships and the rng as they are then. Calls the AI returns from at once (the player's
  ships, no owner) don't stop.
- Transports and trade ships have no id field, so sim/warships.gd names them by identity across ticks (both lists
  only lose entries or grow at the end); no keys are added to their Dictionaries (net/rep.gd sends them whole).
- A target that left its list before the tick stays in `tref` until its ship looks again, as in GDScript.
- Runs only while the nav is in Luau (5d1) on the same Luau state; otherwise `_tick_gd` as before. A tick with no
  warships, no shells and no post that could fire makes no call. If a resume fails after a batch was applied the
  link goes off for the rest of the match (the GDScript can't take over half a tick); not seen in the tests.
- `SimNav.find_route_t` for steer (the corners as a table, no copy).
- tests/test_luau_warships.gd (8 checks): the seeded match with Luau and with NO_LUAU_SIM for 5000 ticks: every
  warship key in order, shells, targets, posts, stats, transports, trade ships, gold, notes and rng identical after
  each tick (up to 17 warships, 177 shots, 71 ships sunk, 152 captures, 204 stops for the AI), and the capture
  custom.

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_warships
8/8 (5000 ticks identical), perf_sim 13.25 / 13.05 ms/tick.
- Cost: the first version sent all trade ships every tick and ran 15.3 / 15.5 ms/tick (bridge about 2 ms/tick at
  t=3000: building the trade ship list 0.45, ships / ports / posts 0.22, flush + world() 0.27, the call 0.7).
  Sending the trade ships only when a ship needs them brought it to the numbers above. flush + world() is still
  paid on every tick with warships; the one-world()-per-tick fix planned under 5d2 covers it.

### Step 5e: troop growth, gold income and cooldowns in Luau (Core/SimEconomy.luau)

What changed:
- `luau/sim/Core/SimEconomy.luau`: game/economy.gd `_economy`'s per-nation growth: the troop cap (max_troops or
  max_troops_pop), regen, the applied growth, gold per tick and the reinforcement cooldown, through Rules.luau
  (Step 3). One call per tick with a row per nation still alive after the GDScript's checks; the values come back
  in the same order and are written in the same key order.
- Stays GDScript in `_economy`: the nuke queue and supply drops (customs), the city levels, the overflow guards,
  deaths (sound, stats, notes, the rng draw), and the console's god mode / infinite gold / no cooldown, moved into
  `_econ_console` (marked `# CUSTOM:`) so both paths share it. Deaths draw the rng and growth does not, so doing the
  deaths in the loop and the growth after it gives the same order of every write that matters.
- `troop_kind` / `troop_diff` are looked up once per nation in the loop (same values): they were about 0.15 ms of
  the 0.7 ms the tick cost (seed 12345, t=1500, 165 nations alive).
- Cost: the tick is about 0.55 ms with Luau and about 0.55 ms without (it was 0.70 before the lookup change). The
  growth maths is a small part; most of the tick is reading and writing the nation Dictionaries, which stay.
- Runs whenever the Luau link is on (no Luau state is read); `NO_LUAU_SIM` or a remote viewer runs the GDScript
  growth as before. A failed call turns the link off and the same rows grow in GDScript.
- tests/test_luau_economy.gd (7 checks): the seeded match with Luau and with NO_LUAU_SIM for 3000 ticks: every
  nation's troops, gold, regen, cooldown, alive and land, the stats, notes and rng identical after each tick (396
  nations die), and the god mode custom on a new match (same numbers in both, gold 999M or more, cooldown 0).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_economy
7/7 (3000 ticks identical), perf_sim 13.49 / 13.05 ms/tick.

### Step 5f1: the AI's border scan in Luau (Core/SimAI.luau)

The AI pass costs about 2.7 ms/tick on seed 12345 (3000 ticks); its border scans (sim/ai.gd `_scan_border`,
about 6.5 a tick) were 1.1 ms of that. The rest is spread over the think functions and the actions they call
(attacks, boats, builds, alliances), which go through the game's own entry points. So the AI moves in sub-steps,
perception first.

What changed:
- `luau/sim/Core/SimAI.luau` `scan`: the same walk over Luau's copy of the owner's border set (Core/SimState keeps
  it in Godot Dictionary order) and tile layer, flushed first, so it reads what the GDScript would read. Same caps
  (tribes: the whole set, nations: ceil(400 * legacy_lin) tiles), same order of neighbours, same reservoir draws on
  the sim rng. sim/ai.gd fills `sc_list`, `sc_count`, `sc_tile` and the neutral / fallout fields from the result
  in the order the GDScript would have.
- Runs whenever the Luau link is on; `NO_LUAU_SIM` or a remote viewer walks in GDScript as before.
- Cost: about 40 us per nation scan in Luau against about 220 us in GDScript (seed 12345, t=1500, 50 nations);
  the scans went from 1.09 to 0.58 ms/tick, the AI pass from 2.7 to 2.3.
- tests/test_luau_ai.gd (6 checks): the seeded match with Luau and with NO_LUAU_SIM for 3000 ticks: owner map,
  troops, gold, attacks, the AI's per-nation state and stats and the rng identical after each tick; every 100
  ticks every live nation scanned both ways from the same rng state (6155 scans, all equal, rng included).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_ai 6/6
(3000 ticks identical), perf_sim 12.43 / 13.04 ms/tick.

### Step 5f2: the tribes' nearby owners in Luau (Core/SimAI.luau near)

After 5f1 the AI pass was about 2.3 ms/tick (seed 12345, 3000 ticks). Per function (timing wrappers around
sim/ai.gd): the nations' think 1.2, the tribes' think 0.76, of which `_tribe_nearby` 0.57 (its whole-border scan
plus the shore probes over `own_coast_tiles`); then the transport choice 0.3 and builds 0.2. The rest is under
0.1 each.

What changed:
- `luau/sim/Core/SimAI.luau` `near`: the tribe's whole-border scan (the 5f1 walk, same rng draws), then the shore
  probes in border order: every `every`-th coastal tile (a 4-neighbour is water, -1, as game/economy.gd `_coastal`)
  looks `dist` tiles out up, down, left and right where the first step is water; an owner there that is not water
  or ice, not the tribe, not seen yet and not fallout land is added. `every` and `dist` come from sim/ai.gd
  (10 / k_lin and 5 / k_lin rounded, at least 1 and 2).
- sim/ai.gd `_tribe_nearby` fills `sc_*` and `_near` from it in the GDScript's order (scan owners, 0 when the
  scan saw free land, then the probe finds) and returns the same flag. `_scan_luau` and the new `_near_luau` share
  one call path (`_ai_luau`). `NO_LUAU_SIM` or a remote viewer runs the GDScript as before.
- Cost: `_tribe_nearby` 0.57 to 0.21 ms/tick, the AI pass about 2.3 to 1.9.
- tests/test_luau_ai.gd (8 checks): adds every 100 ticks each live tribe's nearby list both ways from the same
  rng state (flag, owners in order, scan fields, rng; 4518 lists, all equal, 41 with probe finds).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_ai 8/8,
perf_sim 12.14 / 12.17 ms/tick.

### Step 5f3: the AI's coastal border tiles in Luau (Core/SimAI.luau coast)

sim/ai.gd `own_coast` (a nation's cached coastal tile, else the first coastal tile of its border) and
`own_coast_tiles` (all of them, at most cap) walk the border set with game/economy.gd `_coastal` per tile; a
landlocked nation finds none, caches -1 and walks again on its next transport, build and invasion check.

What changed:
- `luau/sim/Core/SimAI.luau` `coast`: the same walk over Luau's border list and tile layer (coastal: a
  4-neighbour is water, -1), at most `cap` tiles, in border order.
- `own_coast` and `own_coast_tiles` (without the `water_ok` filter, which needs the water-body sizes and stays
  GDScript) take the tiles from it. The cache and its check stay as they were. `NO_LUAU_SIM` or a remote viewer
  walks in GDScript as before.
- Cost (seed 12345, 3000 ticks, timing wrappers): the transport choice 0.29 to 0.25 ms/tick (most of what is left
  is the transport launch and its route search, 5d4), builds 0.20 to 0.17, the AI pass about 1.9 to 1.8.
- tests/test_luau_ai.gd (10 checks): adds every 100 ticks each live nation's coastal tiles both ways at caps 1, 64
  and all (18465 lists, all equal).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_ai 10/10,
perf_sim 11.90 / 12.33 ms/tick.

### Step 5g: a cheaper world() (sim/attacks.gd)

`SimAttacks._world()` builds what every Luau module call reads through SimState.nat_all (troops, gold, alive, kind,
teams, alliances, traitors, defence posts). It is built about 3.3 times a tick (the attack pass, naval, rails,
warships, the arsenal) and cost about 0.75 ms/tick (seed 12345, 3000 ticks), most of it reading the nation
Dictionaries: 473 nations, about 70% of them dead on average.

What changed:
- A dead nation's troops and gold are kept from the build that first saw it dead (keyed on its Dictionary, so a
  replaced Dictionary is read again); only its alive flag is read each time. A nation that is alive again is read
  in full. Checked first: over 6000 ticks of seeds 5516 and 12345 no dead nation's troops, gold, team or left
  changed at any tick end. Teams, alliances, traitors and defence posts are built as before.
- Cost: 0.75 to 0.61 ms/tick. The alive flags themselves (about 46 us a build) stay: nations come back alive in
  online play (net/mp_host.gd), so every build reads them.
- tests/test_luau_world.gd (6 checks): two seeds, 3000 ticks each: after every phase of every tick (begin, attack
  pass, AI pass, end) the cached build equals a full read (`world_full`), and the match is identical, tick for
  tick, to one played with full builds only.

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_world 6/6,
perf_sim 12.44 / 12.90 ms/tick. The machine was slower in this run: back to back right after, 12.69 / 13.00 with the
change and 13.70 / 13.76 without it (5f3).

### Step 5g2: a lite world for naval, rails and warships (sim/attacks.gd world_call)

Naval (trade ports), rails and warships read only alive and allied() from SimState (team mode, teams, leavers,
alliances), never troops, gold, traitors, defence posts or the fallout / land totals (checked in SimNaval,
SimRails, SimWarships and the one SimArsenal function they use, godot_sort). Their calls now send only those.

What changed:
- SimState.nat_lite sets alive, kind, team mode, teams, leavers and alliances, and leaves troops, gold, traitors,
  defence posts and the totals as the last nat_all set them. The attack pass and the arsenal still send the full
  world before every call that reads those, and SimState.take only writes back troops that set_troops changed.
- SimArsenal.world_lite and SimRails.world_lite take nat_lite's arguments. sim/attacks.gd `_world_lite()` builds
  them; `world_call()` gives the lite one, or the full world() when `world_full` is on (tests). sim/naval.gd,
  sim/rails.gd and sim/warships.gd call it.
- tests/test_luau_world.gd (10 checks): the per-tick state now also covers the structure, boat and trader lists;
  each seed checks the lite world was used (about 6900 calls in 3000 ticks) and that the full builds run used none,
  so the tick-for-tick match also compares lite against full.

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before plus luau_world 10/10,
perf_sim 12.29 / 12.29 ms/tick; 5g back to back right after: 12.87 / 12.52.

Dropped from the 5d2 plan: keeping the ports' trade fields in Luau. The whole ports snapshot costs about 0.14
ms/tick and the trade fields are under half of it, while Luau would have to follow each port across calls as the
structure list changes order. The ports' Luau time (about 0.6 ms/tick) is the route searches.

### Step 5d4: ship movement stays GDScript (profiled; one GDScript fix)

Answer to Question 4: keep it in GDScript, port only if a profile shows a real gain. Profile (4.5.1, 6000 ticks,
tick end timed piece by piece, the owner hash unchanged by the probe):

| seed | trade ships (avg / max) | `_tick_trade` before | after | transports (avg / max) | `_tick_boats` |
|---|---|---|---|---|---|
| 12345 | 287 / 417 | 0.255 ms/tick | 0.178 | 2.4 / 20 | 0.012 |
| 5516 | 285 / 425 | 0.261 ms/tick | 0.195 | 2.6 / 22 | 0.014 |

(Question 4's 0.044 ms/tick was 3000 ticks, before the late-game ship counts.) The cost is the per-ship moves; the
arrivals (pay, notes) are about 0.011 ms/tick and the transports are too few to matter.
- What changed: `_tick_trade` (game/navy.gd) computed `dt * ship_tiles_per_s() * boat_speed * TS` again for every
  ship (a method call each); it is now made once per tick and added to each `d`. The same product in the same order,
  so the positions are bit for bit the same (hash unchanged).
- Why not Luau: the trade ship Dictionaries stay in GDScript (the renderer and net/rep.gd read `d`), so a Luau
  version still writes every `d` back each tick. Writing `d` alone is about half of what is left (benchmark: 370
  ships, 0.036 of 0.077 ms), so Luau could save at most about 0.08 ms/tick, and it would need a Luau copy of the
  ship list kept in step with spawns, warship captures and removals. Not ported.
- Transports (`_tick_boats`) are left as they are (0.013 ms/tick).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before, perf_sim 12.94 / 13.28; 5g2 back to
back right after: 13.60 / 13.65 (the machine ran slow; 5g2 measured 12.29 / 12.29 earlier).

### Step 6: the GDScript sim stays as the fallback; docs

Answer to Question 6 (Ruihan, Nov 27 2026): keep the GDScript sim as the fallback. Nothing is deleted. Step 6 is the
docs and checks only:
- What runs where, at the end of the port: in Luau when the extension loads (Linux x86_64 / arm64, web): attacks
  (5a), structures (5b), arsenal and nukes (5c), rails and trains (5b2), water routes (5d1), trade ports (5d2),
  warships (5d3), economy (5e), the AI's perception (5f1 to 5f3). GDScript always: the AI's decisions (Question 5),
  transport and trade ship movement (5d4), rendering, UI, audio, input, networking, accounts, party. Everywhere else
  (Windows / macOS editor and desktop builds, a web build whose libgdluau.wasm does not load, NO_LUAU_SIM=1) the
  GDScript bodies in sim/*.gd and game/*.gd run, and the tests keep them equal to Luau tick for tick.
- Each module's Luau gate (the function that says whether Luau runs it: sim/attacks.gd `_L`, structures.gd and
  nav.gd `_lu`, arsenal.gd and rails.gd `lu_on`, naval.gd `_luau_ports`, warships.gd `_luau_tick`, ai.gd `_ai_luau`,
  game/economy.gd's `lu_on`) carries a `# FALLBACK` comment: past it, the module's GDScript code is the fallback.
- Both paths checked at this step: parity 467 / 0 / 5 with Luau and with NO_LUAU_SIM=1; sim_hash owner=3480782660
  whole and sliced, with Luau and with NO_LUAU_SIM=1 (troops, gold and counts equal too).
- docs/PARITY.md: its generator (tests/upstream/_harness.gd) now says which sim the run used and which cases depend
  on it (committed with the header line only: two live-case notes in this run, a warship's hp and a bot's base, differ
  from the committed table, both still pass). CLAUDE.md: what runs in Luau and what stays GDScript, the fallback, the luau-sim branch line, and a rule for
  agents (change both paths; test_luau_* and sim_hash must hold). docs/MULTIPLAYER.md: the host ticks Luau or
  GDScript, viewers neither, packets unchanged, the server needs the arm64 library next to Godot 4.5.1.
- Speed: 13.31 ms/tick before the port (pre-A, seed 12345); 12.29 / 12.29 at 5g2, 12.94 / 13.28 at 5d4 on a slow run
  (with 13.60 / 13.65 for 5g2 right after). This step changes no game code (comments only).

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before, perf_sim 12.37 / 10.84 (the machine's speed moves about 1 ms between runs).

### Web build check: which sim runs

Ruihan asked (Nov 27 2026) to run the luau-sim web build in headless Chromium. The web export works (Godot 4.5.1,
libgdluau.wasm in the build), but no Chromium could run here: the container has no browser, browser downloads are
blocked, and installing one was refused. So sim/luau_link.gd now prints one line when a game starts, in the log and
the browser console: `Luau sim: on`, `Luau sim: off, GDScript fallback (NO_LUAU_SIM)`, or
`Luau sim: off, GDScript fallback (<why the link failed>)`. Open the web build, press F12 and look for that line.
No game code changed.

Results (4.5.1): parity 467/0/5, sim_hash 3480782660 (whole and sliced), all tests as before, perf_sim 12.22 / 13.28.

### Web release fix: release builds of the Luau library, and the web fallback

Ruihan's headless Chromium run of 7c87e52 (Nov 27 2026): the release web export aborted at start
("Aborted(native code called abort())", stuck at LOADING 100%), the debug export ran, and with libgdluau.wasm
missing the page hung on load.
- Cause: the library was built only against godot-cpp template_debug. godot-cpp's debug allocator leaves the
  padding to the engine, which a debug engine adds and a release engine does not. At load, LuaState still bound
  `to_string`, a method this luau-gdextension revision no longer defines, so the bind landed on Object, failed
  ("Class 'Object' doesn't exist", the one-off error every log showed) and freed the bind. In a release engine
  that free is on a pointer the allocator never returned. The same crash on Linux: the official 4.5.1
  linux_release.x86_64 template with the old library aborted at once with "free(): invalid pointer" inside
  LuaState::_bind_methods; linux_debug.x86_64 ran. Godot 4.5.1's web release templates are linked with emscripten
  ASSERTIONS=1 (platform/web/detect.py), whose checked malloc turns that bad free into the abort; the debug
  templates are not, so they ran on.
- Not the cause: emscripten versions. The 4.5.1 web templates report "Emscripten 4.0.10" in the browser, the library
  is built with 4.0.11; the release library loads and runs on them (below). Every import of the library is exported
  by both templates.
- Fix: tools/luau_ext/build.sh builds each library twice, template_debug (the files as before: the editor binary,
  the VM server's editor binary and debug exports) and template_release (`libgdluau.release.wasm`,
  `libgdluau.linux.release.x86_64.so`, `libgdluau.linux.release.arm64.so`), and drops the stale `to_string` bind.
  luau/ext/gdluau.gdextension picks them by the debug / release feature tag. The Linux release template now runs
  with "Luau sim: on" (title screen and a server match start); the "Class 'Object'" error is gone.
- Web fallback (release/loading_shell.html): the page starts the engine without the Luau library, so the GDScript
  sim runs, when the address has `?luau=0`, when the library file is not on the server (checked with a HEAD request
  first, since Godot stops the load on a missing library), or when the last start in this tab aborted with the
  library loaded (the page records it in sessionStorage and reloads once without it). The console says which
  ("Luau library not loaded (...)") and the game prints "Luau sim: off, GDScript fallback (Luau extension not
  loaded)". Godot still logs "Can't open dynamic library: luau/ext/libgdluau.release.wasm" in those cases (it reads
  the extension list from the pck); that error is harmless and the game runs on.
- Results: parity 467/0/5, hash 3480782660 (whole and sliced), perf 13.32 / 12.07 ms/tick, all tests as before
  (lobby_ui 3, account_ui 55 known).
- Browser check (Nov 27 2026, headless Chrome for Testing 159 with SwiftShader WebGL2, release and debug zips of
  2193b36 served by serve.py): release and debug both print "Luau sim: on", no "Aborted(", the title's attract sim
  runs. `?luau=0`, a deleted libgdluau.release.wasm, and the pre-fix library put back in its place (which aborts
  as before) all end in "Luau sim: off, GDScript fallback (Luau extension not loaded)" with the game running; the
  abort case reloads once by itself. Software rendering caps fps at about 12 either way, so fps compares nothing
  here. In a solo World match (Standard, bots off) over the same 2.3 min of wall time, the Luau sim got through
  about twice the game time of the GDScript sim (spawn protection 33 s vs 16 s used, gold 33.6K vs 16.4K); one run
  each. Real GPU and phone fps are still unmeasured.
- The VM server runs the editor binary, so it keeps using the debug library name it has.

### Merge of multiplayer: defense posts don't shell ships (new hash 3683567526)

Ruihan asked (Nov 28 2026) to merge multiplayer into luau-sim. `git merge multiplayer` (not a rebase) went in clean
(f49e456). It brings multiplayer's 130a1be: `SimRules.DEFENSE_POST_SHOOTS := false` (upstream's default) and
sim/warships.gd `var defense_posts_shoot := SimRules.DEFENSE_POST_SHOOTS`, so a defense post no longer shells
transports or warships (owner request 2026-11-26); plus the memory readout (client/ui/mem_overlay.gd).
- The Luau side reads the same flag: sim/warships.gd sends `defense_posts_shoot` in the call header (index 8) and
  SimWarships.luau `posts_tick` runs only when `C.posts_shoot` is set. Nothing else in either sim makes a post fire;
  economy.gd `defended()` only changes land attacks (5x troops, 3x time), as before.
- tests/test_defense_posts.gd (new, in VERIFY): the seeded match (5516) on the Luau path and the GDScript fallback.
  When the first transport is at sea, a finished post of a non-allied nation goes on the nearest land tile and a
  warship of the transport's owner next to it; 400 ticks, no post shell may fly. A control with the flag forced on
  fires at the same transport (so the scene really puts both ships in reach). 10/10 on both paths.
- Hash: owner=3683567526 (whole and sliced) instead of 3480782660. The merge explains it: the same run with
  `defense_posts_shoot` forced on gives 3480782660 exactly, so the only change is the posts not shooting. This is
  the new baseline from here on.

Results (4.5.1): parity 467/0/5, sim_hash 3683567526 (whole and sliced), all tests as before plus defense_posts 10/10
(lobby_ui 3, account_ui 55 known), perf_sim 12.57 / 12.34 (13.54 / 12.63 while the browser check ran).

### Title screen: nothing of the last match is drawn over the attract sim

Ruihan's report (Nov 28 2026, web, older than the Luau port): after a win and Return to title, the last match's
structure icons, ships and nuke arcs stayed on screen over the title's attract sim.
- Reproduced in the web build (headless Chrome for Testing 159, SwiftShader, Luau on): a World match with
  structures, a warship per nation and nukes in flight, won, then the end screen's Return to title. Every sim list
  was already empty, but the icons and ships stayed on screen for as long as the title ran (screenshots in
  /mnt/project-files/rofront/title_leftovers/).
- Cause: main.gd `_process` redraws the map overlay (where structures, ships, trains, munitions and nuke arcs are
  drawn) only when the state is not "menu", and the title and its attract sim run in "menu". A CanvasItem keeps
  its last drawing until it redraws, so the match's last frame stayed. Also stale: the client's tick-keyed caches
  (client/game_state.gd structures(), units(), attacks()): the old sim_atk keeps its tick on the title, so units()
  kept returning the match's ships, and a new attract sim reaching the same tick number could get them back; the
  rail piece cache (road_layer), the rail edge cache, the range layer's struct list and the front labels; and, on
  the Luau path, the missiles, munitions, trains and attacks Luau holds, with their GDScript mirrors, which were
  only dropped at the next map's first flush.
- Fix, in one place: game/ui_anim.gd `_clear_world_view()`, called by `_to_menu()` (the title starts) and by
  main.gd `_attract_begin()` before the attract builds anything. It clears the round state and the supply drops,
  resets sim_atk, the Luau lists (sim/luau_link.gd `reset_world`: SimAttacks, SimArsenal, SimRails, SimStructures
  reset, mirrors cleared, the next flush sends the whole world again), the rail edge cache, the client caches
  (`RWGameState.reset_caches`), the road layer (`RoadLayer.unbind`), the front labels and the range layer's struct
  list, and asks the overlay, names, ranges, fronts, fx and fallout glow to redraw. No sim rule changed.
- tests/test_title_reset.gd (new, in VERIFY), Luau and GDScript: a seeded match gets structures for every nation,
  warships and nukes in flight, is won and goes to the title: all 39 (Luau) / 30 (GDScript) lists, caches, layer
  counts and Luau lists are zero and the overlay redrew; then an attract sim gets the same, a new attract starts,
  and before its first tick everything is zero again and the overlay redrew. Without the fix it fails 8 checks.
- Web check after the fix: the same run shows the title and the attract sim clean.

Results (4.5.1): parity 467/0/5, sim_hash 3683567526 (whole and sliced), all tests as before plus title_reset
13/13 (lobby_ui 3, account_ui 55 known), perf_sim 11.93 / 13.38.

### Others tab: Didier and Didier France removed

Owner request (Nov 28 2026, screenshot of the two maps): remove Didier (1500x1348) and Didier France (1050x1124).
Removed maps/upstream/of_didier.* and of_didierfrance.* (codes, json, thumb, tiles) and their two entries in
index.json "others" (131 to 129). tools/import_openfront.py skips both, so a re-import doesn't bring them back.
build_web.sh copies of_*.codes.bin and tiles.bin, so they leave the web pack too. No sim change.

### Client map size follows the match's map (range rings drawn in the wrong place)

Owner report (Nov 28 2026, web): while placing artillery, its range ring was drawn far from the cursor.
Cause: RWGameState.map (client/game_state.gd RWMapInfo) copied W and H from the game once, when the client
state was made at boot. A match on a map of another size kept the boot size, so every client layer that turns a
tile number into a position with `t % W`, `t / W` (RangeLayer rings and the build ring, FxLayer, the target card,
UIRules and UIInteract tile math) was off. Structure icons use the game's own W, so they were right.
Fix: RWMapInfo.W and H read g.W and g.H. tests/test_map_size_live.gd (new, in VERIFY) starts maps of three sizes
in a row and checks the client's size and the artillery build ring's tile on each (4 fails without the fix).
No sim change. Customs: none (the range system is unchanged).

### Shell, air strike and slug sounds as upstream

Owner report (Nov 28 2026): artillery used the nuke explosion sound. Owner's call: match upstream.
Cause: sim/arsenal.gd played `atom_hit` (the director's nuke_explosion, atom-hit.wav) when a shell, an air strike
or a slug landed, on both paths (strike() and the Luau path's _strike_fx), and `atom_launch` (the nuke launch
sting) when the player sent a strike; nothing played when a shell was fired. Upstream UIAdvisor.on_nuke_launched /
on_nuke_detonated, for NUKE_FLAT kinds: a shell plays shell_fire when fired and shell_hit when it lands, both only
when on screen; an air strike sam_launch at pitch 0.85 and intercept (sam_intercept) at 0.8, a slug shell_fire at
0.6 and intercept at 1.25, when on screen or yours. Volumes as upstream.
Fix: SimArsenal._fired_sfx (from _spawn_munition on the GDScript path, and for each munition a Luau call made)
and _impact_sfx (from strike() and _strike_fx). sfx() takes an optional fixed pitch (upstream ctx:sfx's 4th
argument), passed to the audio director. tests/test_strike_sounds.gd (new, in VERIFY), Luau and GDScript: the
player fires each kind with the camera on it; the director's log holds exactly those sounds and pitches and no
nuke sound (without the fix: no fire sound and nuke_explosion on impact). No sim change.

### Crate reveal card names fit their cards

Owner report (Nov 28 2026): on the Open x10 reveal, long flag names ("Central African Republic", "Federated States
of Micronesia") ran into the next card. Cause: client/ui/crates.gd set the name Label's size before turning clipping
on, and a Label never sizes below its minimum (the whole name, unclipped), so the text overflowed the card.
Fix (as upstream: its single reveal scales the name down to fit, its Locker cuts with an ellipsis): the reveal name
takes the largest font size that fits the card's inner width on one line, else two lines split at a word, else is
cut with an ellipsis at the smallest size; the picture gives up the room a second line needs, and the card size and
the rarity line stay where they were. The Locker grid's name sets its clip and ellipsis before its size. The Arsenal
already set them first (checked, unchanged). tests/test_crate_names.gd (new, in VERIFY): every flag name, at both
card sizes, measured with the label's own font, fits inside its card above the rarity line; the two reported names
show in full; Locker names are cut inside their cards. No sim change.

### Artillery, air strike and railgun x2.5 (owner custom)

Owner request (Nov 28 2026): "Buff all 3 by 2.5x", everything excluding reloads. Rule change, on both paths
(sim/rules.gd and luau/sim/Core/Rules.luau, same literals): SHELL_KILL_FRAC 0.0288 to 0.072, SHELL_KILL_MIN /
MAX 1,440 / 19,200 to 3,600 / 48,000, AIRSTRIKE_KILL_PER_TILE / FRAC 60 / 0.06 to 150 / 0.15, SLUG_KILL_PER_TILE /
FRAC 150 / 0.04 to 375 / 0.1, STRIKE_DAMAGE 150 / 600 / 1000 to 375 / 1500 / 2500, ARTILLERY_RANGE_FULL 45 to 112.5,
AIRFIELD_RANGE_FULL 156 to 390 (launch_range now reads those two instead of literals), NUKE_OUTER_FULL for shell /
air strike / slug 1.5 / 15 / 5 to 3.75 / 37.5 / 12.5. SimRules.STRIKE_BUFF = 2.5 documents the factor. Unchanged:
reloads (RELOAD_TICKS), battery gaps, rapid reload, cost, HP, build time, projectile speed. Note: a bigger radius
also covers 6.25x the tiles, so air strike and slug kills grow up to their (also x2.5) % caps.
Parity: the upstream checks for these values now expect upstream x2.5, plus one intentional line (467/0/6, 473
checks). The Shop and build-menu texts show the new numbers. The hash is unchanged (3683567526): bots never build
Arsenal structures, so the seed-5516 bot match fires no shell, strike or slug. test_luau_rules and
test_luau_arsenal (GDScript vs Luau) pass.

### Owner console on F2

Owner request (Nov 28 2026): "Make the console open via the F keys if possible / If not, ESC, then TAB / It checks
if the account is henry9149 first". F2: Microsoft's Edge shortcut list binds F1, F3, F4, F5, F6, F7, F9, F10, F11
and F12, and leaves F2 and F8 to the page; in the web build F2 reaches the game (headless Chrome, a probe build
logging keys: F2, F8, Esc and Tab all arrive during a match). game/shop.gd _input opens / closes the console on
F2 or on Esc then Tab, in a match only; toggle_console still checks the owner's signed account token (or the local
--console arg) first. A lone Tab also opened it for the owner (main.gd _unhandled_input still had KEY_TAB from
before the Esc then Tab change); that line is gone. tests/test_console_keys.gd (new, in VERIFY): without a token
or the arg, neither key opens it; it reruns itself with --console, where F2 opens and closes it, Esc then Tab
opens it, a lone Tab doesn't, Esc closes it, and F2 does nothing on the title screen. No sim change.

### Tab toggles the leaderboard, as upstream

Owner (Nov 28 2026), asked whether Tab should toggle the leaderboard like upstream: "Yes, match upstream".
Upstream UIInteract.luau: `elseif key == K.Tab then if ui:screen() == "title" then handled = false else
ui:toggle_leaderboard() end`. client/ui/ui_interact.gd on_key does the same (ClientHud.toggle_leaderboard, new,
calls Leaderboard.toggle). The owner console keeps F2 and Esc then Tab: game/shop.gd _input runs before
_unhandled_input and marks the event handled, so Esc then Tab opens the console without toggling the board. The
help screen says "Tab: Leaderboard" as upstream, plus a row "F2 / Esc then Tab: Console (owner only)".
tests/test_console_keys.gd checks a lone Tab toggles the board in a match (owner or not) and back, Tab on the title
screen leaves it, and Esc then Tab leaves it for the owner. No sim change.

### Elimination gold, as upstream Sim._eliminate

Owner (Nov 28 2026), asked whether to match upstream's payout on elimination: "Match upstream". The port only
paid Rules.conquer_gold (all of a nation's or tribe's gold, half of a human's) inside annex (sim/attacks.gd
annex, Luau SimAttacks annex via EV_CONQUEST). Upstream also pays it in Sim._eliminate to o_killer, the owner that
took the last tile (SimState set_owner; SimNukes and Sim.capitulate set it too), which covers capitulation, nukes,
a human worn down tile by tile, and pocket gold earned after an annex. The port's o_killer is last_by
(game/map.gd _set_owner, sim/arsenal.gd for nukes). game/economy.gd _economy now takes conquer_gold of the gold
left when a player goes out with last_by > 0 and zeroes it, and pays it after the growth (the Luau SimEconomy
writes gold back whole, so paying inside the loop could be dropped); the elimination check runs in GDScript on
both sim paths. The "+ gold" popup (_on_conquest, upstream Ev.CONQUEST) goes once per victim: annex sets
conq_sent, so the later payout is silent. tests/test_elim_gold.gd (new, in VERIFY; runs once with Luau and once
with NO_LUAU_SIM): a nation's 1000 gold all goes to the taker, a human's half, nothing twice after an annex.
The seed-5516 hash is unchanged (3683567526): every elimination in that run is a tribe annexed the same tick, with
its gold already zeroed.

## Results

| step | commit | parity | hash (seed 5516, 6000 ticks) | perf AVG ms/tick (seed 12345) | tests |
|---|---|---|---|---|---|
| pre-A | 84d5260 | 465/0/5 | (2340230155, not repeatable) | 13.31 | 13 pass, lobby_ui 3, account_ui 55 |
| A (4.3) | 421aa12 | 467/0/5 | 3480782660 | 13.76 | 13 pass, lobby_ui 3, account_ui 55 |
| 0 (4.5.1) | f7214fc | 467/0/5 | 3480782660 | 13.53 | 13 pass, lobby_ui 3, account_ui 55 |
| 1 | a43b116 | 467/0/5 | 3480782660 | 13.22 | same + luau_bridge 10/10 |
| 2 | 9b35211 | 467/0/5 | 3480782660 | 13.52 | same + luau_bridge 10/10, luau_rng 27/27 |
| 3 | 0c719e1 | 467/0/5 | 3480782660 | 12.58 | same + luau_rules 8/8 |
| 4 | d85a762 | 467/0/5 | 3480782660 | 13.53 | same + luau_state 12/12 |
| 5a | e33428f | 467/0/5 | 3480782660 | 11.11 / 10.93 | same + luau_attacks 12/12 |
| 5b | 88bb160 | 467/0/5 | 3480782660 | 11.72 / 11.81 | same + luau_structures 9/9 |
| 5c | b89e9f7 | 467/0/5 | 3480782660 | 11.36 / 11.07 | same + luau_arsenal 18/18 |
| rails split | 662352f | 467/0/5 | 3480782660 | 11.76 / 11.74 | same |
| 5b2 | 5dd163f | 467/0/5 | 3480782660 | 11.46 / 11.84 | same + luau_rails 8/8 |
| 5d1 | a61a285 | 467/0/5 | 3480782660 | 12.39 / 11.85 | same + luau_nav 14/14 |
| 5d2 | d412c8d | 467/0/5 | 3480782660 | 13.34 / 13.81 | same + luau_naval 6/6 |
| 5d3 | fee8c12 | 467/0/5 | 3480782660 | 13.25 / 13.05 | same + luau_warships 8/8 |
| 5e | 5c58c85 | 467/0/5 | 3480782660 | 13.49 / 13.05 | same + luau_economy 7/7 |
| 5f1 | 271ac24 | 467/0/5 | 3480782660 | 12.43 / 13.04 | same + luau_ai 6/6 |
| 5f2 | 569510a | 467/0/5 | 3480782660 | 12.14 / 12.17 | same + luau_ai 8/8 |
| 5f3 | b064328 | 467/0/5 | 3480782660 | 11.90 / 12.33 | same + luau_ai 10/10 |
| 5g | cbc8e22 | 467/0/5 | 3480782660 | 12.44 / 12.90 (5f3 right after: 13.70 / 13.76) | same + luau_world 6/6 |
| 5g2 | a1b2c71 | 467/0/5 | 3480782660 | 12.29 / 12.29 (5g right after: 12.87 / 12.52) | same + luau_world 10/10 |
| 5d4 | d4b44e8 | 467/0/5 | 3480782660 | 12.94 / 13.28 (5g2 right after: 13.60 / 13.65 (the machine ran slow; 5g2 measured 12.29 / 12.29 earlier)) | same |
| 6 (docs) | 7c87e52 | 467/0/5 | 3480782660 | 12.37 / 10.84 | same |
| web log line | fb3ecd8 | 467/0/5 | 3480782660 | 12.22 / 13.28 | same |
| web release fix | see git log | 467/0/5 | 3480782660 | 13.32 / 12.07 | same |
| merge multiplayer (posts off) | f49e456 + see git log | 467/0/5 | 3683567526 (3480782660 with posts forced on) | 12.57 / 12.34 | same + defense_posts 10/10 |
| title screen clear | see git log | 467/0/5 | 3683567526 | 11.93 / 13.38 | same + title_reset 13/13 |
| perf rerun, c04498a vs 33f84ff, alternating x4 | - | - | - | 10.85 11.03 11.51 12.17 (mean 11.39) vs 11.45 11.42 11.21 11.68 (mean 11.44) | - |
| remove Didier maps | see git log | 467/0/5 | 3683567526 | 12.52 / 12.23 (ran beside a headless Chrome run) | same |
| client map size live | see git log | 467/0/5 | 3683567526 | 11.44 / 11.52 | same + map_size_live 10/10 |
| shell/strike sounds as upstream | see git log | 467/0/5 | 3683567526 | 11.01 / 10.66 (beside a headless Chrome run) | same + strike_sounds 30/30 |
| crate reveal names fit | see git log | 467/0/5 | 3683567526 | 11.73 / 12.18, rerun 11.20 / 12.09 (beside a headless Chrome run; UI-only change, sim code untouched) | same + crate_names 8/8 |
| strike buff x2.5 (owner custom) | see git log | 467/0/6 (473) | 3683567526 (bots build no Arsenal structures) | 11.42 / 11.22 | same |
| owner console on F2 | see git log | 467/0/6 (473) | 3683567526 | 11.81 / 13.15; alternating HEAD vs this: 13.66 / 11.68 vs 12.88 / 12.78 (noise; input-only change) | same + console_keys 14/14 |
| Tab toggles the leaderboard | see git log | 467/0/6 (473) | 3683567526 | 12.10 / 12.95 (input-only change) | same + console_keys 20/20 |
| elimination gold as upstream | see git log | 467/0/6 (473) | 3683567526 (no non-annex elimination in this run) | 11.19 / 12.38 | same + elim_gold 21/21 |

## Customs touched per step

- Didier maps removed: Others tab (131 to 129 maps).
- Title screen clear: none (a redraw and cache clears; no rule or number).
- Multiplayer merge: none new here (defense posts off and the memory readout come from multiplayer as they are).
- Step 6: none (docs and the PARITY.md header only).
- Step 5d4: none (ship speed is unchanged: boat_speed and upstream's 1 tile per tick, the same product).
- Step 5g2: none (what Luau calls are sent, not values; the hash is unchanged).
- Step 5g: none (a cache; the hash is unchanged).

- Step 5e: the console's god mode, infinite gold and no cooldown: game/economy.gd `_econ_console` (`# CUSTOM:`),
  used by both paths; test_luau_economy checks it. Supply drops and the nuke queue stay as they were.
- Step 5d3: a warship capturing a trade ship plays no sound: SimWarships.luau capture_trade (`-- CUSTOM:`) pushes
  notes only; test_luau_warships checks it. Warship 0.7 and boat 0.35 speeds still come from the game.
- Step 5d2: none (trade ship spawns; boat 0.35 stays on the game).
- Step 5d1: none (water routes only; boat 0.35 and warship 0.7 speeds stay on the game).
- Step 5b2: none of the listed customs are in the rail / train sim (supply drops stay off; train gold and spawn
  rates are upstream's). Nothing to add a custom test for.
- Rails split: none (code moved, values unchanged).
- Step 5c: the 0.9x nuke speed (all bombs, warheads included), ICBM 1.2x speed and the 20% seeded SAM-ignore roll
  for the player's launches with the toggle on, MIRV and Scattershot warheads sharing the carrier's roll and speed:
  copied into SimArsenal.luau (`-- CUSTOM:`), the constants checked against game/nukes.gd and game/state.gd by
  test_luau_arsenal, and the rolls checked against the GDScript sim. Stay in GDScript: the ICBM +10% fee and the
  -20% silo cooldown (game/nukes.gd, applied to the shot stamp before the Luau launch), Arsenal Star prices and owned
  items (shop). Upstream values kept: SAM range, reload 90, fallout until recaptured. Supply drops stay off.
- Step 5b: none of the listed customs are in placement or construction (the autoshot / bench build-time cut stays
  in economy.gd `_struct_add`). Supply drops stay off.
- Step 5a: none of the listed customs live in the attack code (troops /10 and the 80% win stay where they were). The
  arsenal now cuts attack troops through scale_owner / set_troops; values unchanged (hash).
- Step 4: none (recording only; the hash is unchanged).
- Step 3: none in the game (the numbers are copied). Not in SimRules: the 0.9x nuke speed (game/nukes.gd
  NUKE_SPEED_X, moves with Nukes) and the Arsenal Star prices (game/shop.gd, the shop, stays GDScript).
- Step 2: none (runtime and rng only).
- Step 1: none (runtime only).
- Step 0: none (engine only; the hash is unchanged).
- Step A: none of the listed customs change. Speed slider / attract speed still scale how many ticks run per real
  second (tick_acc); the attract boost (20x/5x/1x by real seconds) is unchanged. Supply drops stay off.

## Questions

1. Player and network intents are still applied when they arrive (between frames, so possibly between two slices of a tick).
   Upstream queues intents and runs them at the start of the next tick (Sim._process_intents). Queue them the same way
   (needed for lockstep, not for the host-authoritative multiplayer)? Not done in Step A.
   Answer (Ruihan, Nov 27 2026): no, skip it for now; keep applying player and network intents when they arrive
   (online play is host-authoritative, queueing would add up to 0.1 s to every command). Deferred until lockstep or
   tick-exact replay is wanted.
2. Rails, stations, factories and trains (game/rails.gd: rail paths, the MST links, train routes, train gold) are
   part of upstream SimStructures, but here they sit with the rail drawing and train animation. Port them to Luau
   with Structures (a later sub-step) or with Economy, or keep them in GDScript? For now they stay GDScript and read
   game.structs as before.
   Answer (Ruihan, Nov 27 2026): "Port them with Structures, but split the file first". Plan: split game/rails.gd's
   sim (rail paths, links, trains) from the drawing / fx as its own commit, then port the sim half as Step 5b2.
3. Step 5b2 points the renderer at cache-only readers (`_rail_curve_view`, `_has_rail_link_view`) in both modes, so
   drawing no longer starts route searches or spends the tick's rail budgets. That changes nothing headless, but in
   a window the sim no longer depends on what is drawn, and a rail shows up once the tick has searched it instead of
   when it first comes on screen. Keep it (it is a determinism fix, needed so Luau and GDScript agree), or should the
   GDScript fallback keep the old drawing-side searches?
   Answer (Ruihan, Nov 27 2026): "Keep the new one". The renderer reads cached rails only, with and without Luau;
   no drawing-side searches come back.
4. Step 5d4 (transport and trade ship movement: game/economy.gd `_tick_boats`, game/navy.gd `_tick_trade`). The
   movement loop costs about 0.044 ms/tick in GDScript (seed 12345, 3000 ticks, about 200 trade ships). The ship
   Dictionaries stay in GDScript (the renderer and net/rep.gd read `d` every frame), so a Luau version still writes
   every `d` back each tick, plus a call: it can only be slower. The landings (troops, notes, `sim_atk.start`) are
   rare. Port it anyway as planned, or keep both in GDScript until Step 6 decides what Luau owns? Until answered,
   5d4 is skipped and Economy (5e) goes first.
   Answer (Ruihan, Nov 27 2026): keep it in GDScript by default, but profile it first. Profiled in Step 5d4: at most
   about 0.08 ms/tick to gain in Luau, so it stays GDScript; the trade ship loop got a GDScript fix (0.26 to 0.18).
5. Step 5f (the AI) after 5f1 to 5f3: perception (border scans, the tribes' nearby owners, coastal tiles) runs in
   Luau and the AI pass is down from about 2.7 to 1.8 ms/tick (seed 12345). What is left is decision code: about
   20 think functions reading and writing the nation and per-AI Dictionaries and calling the game's action entry
   points (intent_attack, launch_boat with its route search, builds, alliances, nukes). No single part is above
   0.25 ms/tick, and the biggest (transport choice) is mostly the launch, which is 5d4. Ported, each decision would
   copy that state across (as in 5e, where the Luau maths gave no gain). Stop the AI port at perception, or port
   the decisions anyway? Until answered, the AI stays as it is and the ports' perf fix (one world() per tick, the
   ports' trade fields kept in Luau, planned in 5d2) goes first.
   Answer (Ruihan, Nov 27 2026): stop at perception. The decision code stays GDScript.
6. Step 6 (delete the dead GDScript sim). After 5a to 5g2 no GDScript sim code is unreachable: every ported tick
   body is still the path taken when the Luau extension is not loaded, and three things depend on that:
   - Platforms: luau/ext/gdluau.gdextension has Linux x86_64 / arm64 and web libraries only. The Godot editor or a
     desktop export on Windows or macOS runs the GDScript sim. The web side module (libgdluau.wasm) has never been run
     in a browser (Step 1); if it fails to load, the site keeps working on the GDScript sim.
   - Tests: every test_luau_* plays the match with Luau and with NO_LUAU_SIM and compares them tick by tick; without
     the GDScript path they can only compare hashes.
   - Parity: the upstream source checks (tests/upstream/_harness.gd) read main.gd and game/*.gd, so deleting sim code
     there needs those checks moved to the Luau files (PARITY.md).
   The speed condition holds (12.29 / 12.29 ms/tick at 5g2, 12.94 / 13.28 on a slower run at 5d4, against 13.31).
   Delete the fallback now (Luau required everywhere: Windows / macOS libraries or no sim there, the web build checked
   in a browser first, tests reduced to hashes, parity checks moved), or keep it and do only Step 6's doc updates
   (PARITY.md, MULTIPLAYER.md, CLAUDE.md) with the fallback-only code marked? Until answered, nothing is deleted.
   Answer (Ruihan, Nov 27 2026): keep it as the fallback. Step 6 is docs only; nothing is deleted.
