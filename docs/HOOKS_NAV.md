# HOOKS_NAV: SimNav water pathfinding (sim/nav.gd)

Port of RoWorld `src/shared/Core/SimNav.luau` (@ae7a350) as `sim/nav.gd` (class_name SimNav, use it via preload). It covers transports, trade ships and warships. main.gd, sim/naval.gd and sim/warships.gd are unchanged. This file holds the exact hook for them.

## What nav.gd does
- Build, once per map after `sim_naval.compute_bodies()`:
  - 8x8 tile cells. Water inside each cell is split into 4-connected regions, as upstream. Full-water cells become one region and are not flood-filled.
  - Regions are linked by 4-adjacency and by one-tile diagonal straits (CSR graph).
  - There is a coarse level of clusters: connected region groups per 64x64 tile block.
  - Each region keeps a list of its coast tiles.
  - Build takes 0.30-0.40 s on 1792x1600 (World with Antarctica, Europe, random). World has 37,862 regions and 793 clusters.
- Query (coarse-to-fine):
  - Weighted A* (w 1.4) on clusters, then A* on regions restricted to that corridor (full graph as fallback).
  - The regions are stitched through portal tiles: a straight hop when there is line of sight, otherwise an in-region BFS.
  - The result is string-pulled. Output is corner tiles; `dense()` gives the tile path.
- Caches:
  - Region-path and route caches (4096 / 2048 entries). A warm hit costs about 1 us.
- Budget:
  - `begin_tick()` resets it and `budget_us` (default 3000) caps search time per tick.
  - Non-urgent queries over the budget return [] with `last_deferred = true` and are not cached, so the caller retries.
  - Player orders are urgent. One search may overrun the budget.
- Water and land:
  - Water is `sim_naval.body > 0` (lakes are their own bodies).
  - String pulling uses a strict supercover line, so drawn polylines never graze land.
  - Corner rounding (Chaikin) is kept only where the cut stays on water.
  - One-tile diagonal straits are allowed, as upstream.
- Transports (`boat_route`):
  - The landing tile is still chosen by `launch_boat` near the click, so targeting stays local.
  - nav finds the owner's nearest coast by sea from that landing (region BFS), like the old BFS.
  - It is capped by the same `max_nodes` (water tiles searched), so AI transports (12000) keep their old reach.
  - It tries each water body that touches the landing.
- Trade (`water_path_px`): a drop-in for `_water_path`. It starts on the water next to `from_tile` and ends on `to_tile`, like the old BFS output, in pixels (x TS).
- Warships (`steer(ws, step)`):
  - Follows a water route to `ws.tgt` and re-plans when the target drifts more than 3 tiles or the route is used up.
  - A land target is snapped to adjacent water.
  - If there is no route this tick (budget), it returns false and the old straight/slide step runs.

## Results (Godot 4.3 headless, `tests/test_nav.gd`)
Path checks: 200 random pairs per map in the main ocean, caches cleared before each query.

| map | build ms | regions / clusters | found | land tiles in path | polyline over land | cold avg / p50 / p95 / max us | warm us | old _water_path (30 pairs) |
|---|---|---|---|---|---|---|---|---|
| World tab 0 (now upstream World + Antarctica) | 366 | 37,862 / 793 | 200/200 | 0 | 0 | 2,436 / 2,445 / 5,581 / 8,001 | 1.5 | 0/30 found, 13.3 ms each |
| Upstream World (tab 2) | 368 | 37,862 / 793 | 200/200 | 0 | 0 | 2,402 / 2,434 / 5,641 / 7,750 | 1.1 | 0/30, 12.8 ms |
| Europe | 378 | 26,883 / 851 | 200/200 | 0 | 0 | 2,709 / 2,246 / 7,444 / 10,138 | 1.1 | 0/30, 12.7 ms |
| Random (Pangaea Isles) | 331 | 24,806 / 680 | 200/200 | 0 | 0 | 3,457 / 2,866 / 8,402 / 13,976 | 1.1 | 1/30, 13.4 ms |

Validity is checked on the dense tile path: every tile is water of the start body, every step is a 4/8-neighbour, and no land corner is cut except one-tile straits (World 18, Europe 7, random 4). Rounded pixel polylines are sampled every 0.25 tile.

Routes around continents (red in the overlays):
- World:
  - N. Atlantic → Indian Ocean around the Cape: 896 tiles, 2.0 ms.
  - Mediterranean → Atlantic via Gibraltar: 0.5 ms.
  - W. Pacific → Atlantic via Indonesia and the Cape: 1,534 tiles, 3.6 ms.
- Europe:
  - Baltic → Mediterranean via the Danish straits, the Channel and Gibraltar: 6.4 ms.
  - North Sea → Black Sea through the Bosporus: 6.1 ms.
- Random map: corner → corner 8.2 ms; W → E 9.5 ms.

Other checks:
- Transports:
  - A cross-world route (Alaska → Antarctica, uncapped) takes 12-21 ms.
  - A local landing 60-200 tiles away takes 1.0-1.7 ms.
  - The route always starts next to the owner's land.
- Warships: steered behind continents with no tick on land (World 1,379 ticks, Europe 1,523, random 1,184).
- Budget: 60 non-urgent cold requests in one tick give 11-25 solved and the rest deferred.

Overlays: /workspace/shots/nav/nav_world.png, nav_upstream_world.png, nav_europe.png, nav_random0.png. Colours: red = test routes, blue/purple = transports, green = warship trail.

In-game check: the hooks applied to a scratch copy (`-- --game`), World, 1,500 sim ticks, 11 owners with ports and warships, fixed seed.
- With hooks: 29 transports and all trade routes on water, warships 2,010 moves and 0 ticks on land.
  - The player's cross-ocean transport takes 7.9 ms (24-32 points).
  - nav during play: avg 0.8-1.9 ms per search, max 6.4 ms.
  - Frame avg 22.0 ms.
- Baseline (`--game --nonav`, same copy): 27/27 transport polylines and the trade polylines cross land (Chaikin corners and the landing tail).
  - The player transport takes 296 ms (BFS with 1M nodes).
  - Trade: 1 route in 1,500 ticks (BFS 14000/60000 node caps), against 48 with nav on the same seed and naval.gd revision.
  - Frame avg 22.8 ms.
- Upstream parity suite (`tests/run_upstream_tests.gd`) with the hooks matches the same snapshot without them: 409/385/0 and 407/383/0. One SAM case is flaky in both.

Gameplay effect: AI transport reach is unchanged (same max_nodes cap). Trade ships now find long routes that the old capped BFS dropped, as upstream (which has no cap), so trade income can rise on large maps.

## Apply
`cd frontline-godot && patch -p1 < <the patch below>`. It dry-runs clean against main.gd, sim/naval.gd and sim/warships.gd as of Nov 9 23:22 EST. Exactly 9 edits:

1. main.gd: `const SimNavS := preload("res://sim/nav.gd")` and `var sim_nav = null` after `var sim_naval: SimNaval`.
2. main.gd `_store_gen_cache`: add `"nav": sim_nav`.
3. main.gd gen_map cache path: restore `sim_nav` from the cache (rebuild if missing).
4. main.gd gen_map after `sim_naval.compute_bodies()`: `sim_nav = SimNavS.new(); sim_nav.build(sim_naval.body, W, H)`. This makes a new object per map, so the cached one stays valid.
5. main.gd `launch_boat`, after the `path_fail` check: `sim_nav.boat_route(owner_map, a, dest, max_nodes)` → `to_points(..., dest, TS)` → `_spawn_boat`. On failure it marks `path_fail`. The landing choice above it is unchanged.
6. main.gd `_water_path`, first line: `if sim_nav != null and sim_nav.ready: return sim_nav.water_path_px(from_tile, to_tile, TS)`. This covers `_spawn_trade_ship_pair` and the captured-trade re-route in warships.gd.
7. sim/naval.gd `tick()`: `g.sim_nav.begin_tick()`.
8. sim/naval.gd `_trade_path`: use `water_path_px(..., false)` (budgeted). A deferred miss returns without caching.
9. sim/warships.gd `_move`, first line: `if g.sim_nav != null and g.sim_nav.ready and g.sim_nav.steer(ws, step): return`.

Optional:
- naval.gd `path_budget` (now 1 per 4 ticks) can be raised, since nav searches are about 1-3 ms and time-budgeted.
- `sim_nav.budget_us` sets the per-tick search budget.
- Water must not change during a match. If it ever does (terraform), call `sim_nav.build(sim_naval.body, W, H)` again after `compute_bodies()`.

Test: `godot --headless --path . -s res://tests/test_nav.gd` (graph and paths, about 25 s) and `... -- --game` (in-game, hooks required).

```diff
diff -ru a/main.gd b/main.gd
--- a/main.gd
+++ b/main.gd
@@ -404,6 +404,8 @@
 var sim_ai: SimAI
 var sim_struct: SimStructures
 var sim_naval: SimNaval
+const SimNavS := preload("res://sim/nav.gd")
+var sim_nav = null  # SimNav (sim/nav.gd): water pathfinding graph for the current map
 var sim_ars: SimArsenal
 var sim_ws: SimWarships
 var fallout_count := 0
@@ -479,7 +481,7 @@
 func _store_gen_cache() -> void:
 	_gen_cache = {"key": "%d|%d|%d|%d" % [map_tab, map_i, (rand_seed_off if map_tab == 1 else 0), _qual()],
 		"om": owner_map.duplicate(), "el": elev_map, "mt": mtn.duplicate(), "cd": coast_dist, "bc": base_col,
-		"lt": land_total, "body": sim_naval.body, "cl": sim_naval.coast_list}
+		"lt": land_total, "body": sim_naval.body, "cl": sim_naval.coast_list, "nav": sim_nav}
 func _gt(lbl: String) -> void:
 	var t := Time.get_ticks_usec()
 	if "--maptest" in OS.get_cmdline_user_args() and _gt_t > 0: print("  phase %s %.0f ms" % [lbl, (t - _gt_t) / 1000.0])
@@ -519,6 +521,8 @@
 		coast_dist = _gen_cache.cd; base_col = _gen_cache.bc; land_total = _gen_cache.lt
 		if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
 		sim_naval.body = _gen_cache.body; sim_naval.coast_list = _gen_cache.cl; sim_naval.trade_cache.clear()
+		sim_nav = _gen_cache.get("nav", null)
+		if sim_nav == null or not sim_nav.ready: sim_nav = SimNavS.new(); sim_nav.build(sim_naval.body, W, H)
 		_gt("cache")
 		if _async_gen: await get_tree().process_frame
 		_redraw_all()
@@ -601,6 +605,8 @@
 	if _async_gen: _load_progress(0.45); await get_tree().process_frame
 	if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
 	sim_naval.compute_bodies()
+	sim_nav = SimNavS.new()  # new object per map: the gen cache keeps the previous one
+	sim_nav.build(sim_naval.body, W, H)
 	_gt("bodies")
 	if _async_gen: _load_progress(0.65); await get_tree().process_frame
 	sim_naval.trade_cache.clear()
@@ -1645,6 +1651,18 @@
 	# A search that just ran out of nodes for this (owner, landing) pair is not repeated for 10 s:
 	# the AI re-picks the same unreachable coast every frame and each miss walks 12000 water tiles.
 	if path_fail.has(key) and elapsed - float(path_fail[key]) < 10.0: return false
+	if sim_nav != null and sim_nav.ready:
+		# SimNav: nearest own coast by sea from the (local) landing tile, A* over the region graph
+		var nr: PackedInt32Array = sim_nav.boat_route(owner_map, a, dest, max_nodes)  # same reach cap as the old BFS
+		if nr.is_empty():
+			if path_fail.size() > 2000: path_fail.clear()
+			path_fail[key] = elapsed
+			return false
+		var npts: PackedVector2Array = sim_nav.to_points(nr, dest, TS)
+		path_cache[key] = [npts, elapsed]
+		if path_cache.size() > 400: path_cache.clear()
+		_spawn_boat(a, npts, dest, troops)
+		return true
 	if bfs_par.size() != W * H:
 		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
 	bfs_gen += 1
@@ -2296,6 +2314,7 @@
 
 # ---------- trade ----------
 func _water_path(from_tile: int, to_tile: int, max_nodes := 14000) -> PackedVector2Array:
+	if sim_nav != null and sim_nav.ready: return sim_nav.water_path_px(from_tile, to_tile, TS)
 	if bfs_par.size() != W * H:
 		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
 	bfs_gen += 1
diff -ru a/sim/naval.gd b/sim/naval.gd
--- a/sim/naval.gd
+++ b/sim/naval.gd
@@ -79,6 +79,7 @@
 var defer_paths := false
 func tick() -> void:
 	var t: int = g.sim_atk.tick
+	if g.sim_nav != null: g.sim_nav.begin_tick()  # SimNav per-tick search budget (budget_us)
 	if t % 10 == 0:
 		tokens.clear()
 	# perf cap: one trade-route BFS per 4 ticks, and none in a frame already past half its sim budget
@@ -229,7 +230,12 @@
 	if path_budget <= 0: return PackedVector2Array()
 	path_budget -= 1
 	var _b0 := Time.get_ticks_usec()
-	var pts: PackedVector2Array = g._water_path(a.tile, b.tile, 60000)
+	var pts: PackedVector2Array
+	if g.sim_nav != null and g.sim_nav.ready:
+		pts = g.sim_nav.water_path_px(a.tile, b.tile, g.TS, false)
+		if pts.is_empty() and g.sim_nav.last_deferred: return pts  # over this tick's budget: retry, don't cache
+	else:
+		pts = g._water_path(a.tile, b.tile, 60000)
 	g._pf_add("nv_bfs", Time.get_ticks_usec() - _b0)
 	trade_cache[key] = pts
 	if trade_cache.size() > 2000: trade_cache.clear()
diff -ru a/sim/warships.gd b/sim/warships.gd
--- a/sim/warships.gd
+++ b/sim/warships.gd
@@ -327,6 +327,8 @@
 	_move(ws, R.warship_tiles_per_tick(false))
 
 func _move(ws: Dictionary, step: float) -> void:
+	# SimNav: follow a water route around land; falls back to the straight step when no route this tick
+	if g.sim_nav != null and g.sim_nav.ready and g.sim_nav.steer(ws, step): return
 	var d: Vector2 = ws.tgt - ws.pos
 	if d.length() <= step:
 		if g._is_water(ws.tgt): ws.pos = ws.tgt
```
