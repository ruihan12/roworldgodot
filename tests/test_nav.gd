# Headless test for sim/nav.gd (SimNav port).
#   godot --headless --path . -s res://tests/test_nav.gd [-- --shots=/workspace/shots/nav] [--game]
# --game (needs the docs/HOOKS_NAV.md hooks applied): plays World for 900 sim ticks with ports,
# warships, trade and transports, checking every live route/ship stays on water. --game --nonav runs the
# same game with sim_nav disabled (old BFS / straight-line ships) as a baseline.
# Loads main.tscn, generates World (tab 0), Upstream World with Antarctica (tab 2, if present),
# Europe (tab 0) and a random map (tab 1); builds the nav graph from sim_naval.body and checks:
# path validity (no land tile, same body, 8-connected, no land-corner cuts except 1-tile straits),
# rounded pixel polylines stay on water, cold/warm query timing, the old BFS (_water_path) for
# comparison, routes around continents, transport routes (nearest own coast by sea), warship steering
# and the per-tick budget. Prints NAV_TEST PASS / FAIL.
extends SceneTree

const SimNavS := preload("res://sim/nav.gd")
var fails := 0
var shots := "/workspace/shots/nav"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shots)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if "--game" in OS.get_cmdline_user_args():
		_game(m)
		print("NAV_GAME %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(0 if fails == 0 else 1)
		return
	var cfgs := [[0, 0, "world"], [0, 1, "europe"], [1, 0, "random0"]]
	if FileAccess.file_exists("res://sim/upstream_maps.gd") and m.has_method("_upstream_menu"):
		cfgs.insert(1, [2, 0, "upstream_world"])
	for cfg in cfgs:
		m.map_tab = cfg[0]; m.map_i = cfg[1]
		var t0 := Time.get_ticks_usec()
		m.gen_map()
		var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
		_test_map(m, cfg[2], gen_ms)
	print("NAV_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL ", what)

func _nearest_water(nav, fx: float, fy: float, b: int) -> int:
	var cx: int = int(fx * nav.W); var cy: int = int(fy * nav.H)
	for r in 200:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r: continue
				var x := cx + dx; var y := cy + dy
				if x < 0 or y < 0 or x >= nav.W or y >= nav.H: continue
				var t: int = y * nav.W + x
				if nav.body[t] == b: return t
	return -1

# validity of a dense tile path; returns [ok, straits]
func _valid(nav, dense: PackedInt32Array, b: int) -> Array:
	var straits := 0
	var W: int = nav.W
	for i in dense.size():
		var t: int = dense[i]
		if t < 0 or t >= nav.N or nav.body[t] != b: return [false, straits, "tile %d not water of body %d" % [t, b]]
		if i == 0: continue
		var p: int = dense[i - 1]
		var dx: int = absi(t % W - p % W); var dy: int = absi(t / W - p / W)
		if dx > 1 or dy > 1 or (dx == 0 and dy == 0): return [false, straits, "gap %d->%d" % [p, t]]
		if dx == 1 and dy == 1:
			var o1: int = (p / W) * W + t % W
			var o2: int = (t / W) * W + p % W
			if nav.body[o1] != b and nav.body[o2] != b: straits += 1
	return [true, straits, ""]

func _test_map(m, name: String, gen_ms: float) -> void:
	var nav = SimNavS.new()
	var body: PackedInt32Array = m.sim_naval.body
	nav.build(body, m.W, m.H)
	var nedges: int = nav.adj_off[nav.reg_count] / 2
	# largest body
	var cnt := {}
	for i in range(0, nav.N, 7):
		var b: int = body[i]
		if b > 0: cnt[b] = cnt.get(b, 0) + 1
	var big := 0; var bc := 0
	for b in cnt:
		if cnt[b] > bc: bc = cnt[b]; big = b
	print("MAP %s gen_ms=%.0f build_ms=%.0f regions=%d edges=%d clusters=%d bodies=%d land=%d" % [name, gen_ms, nav.build_ms, nav.reg_count, nedges, nav.clu_count, cnt.size(), m.land_total])
	_check(nav.build_ms < 4000.0, "%s build too slow" % name)
	# random pairs in the largest body
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	var water := PackedInt32Array()
	for i in range(0, nav.N, 13):
		if body[i] == big: water.append(i)
	var times := []
	var bad := 0; var nofound := 0; var straits := 0; var pxbad := 0
	var detour := 0.0; var nd := 0
	var pairs := []
	for q in 200:
		pairs.append([water[rng.randi() % water.size()], water[rng.randi() % water.size()]])
	for pr in pairs:
		nav._route_cache.clear(); nav._reg_cache.clear()
		var t1 := Time.get_ticks_usec()
		var r: PackedInt32Array = nav.find_route(pr[0], pr[1])
		times.append(Time.get_ticks_usec() - t1)
		if r.is_empty(): nofound += 1; continue
		var d: PackedInt32Array = nav.dense(r)
		var v := _valid(nav, d, big)
		if not v[0]: bad += 1; print("  invalid: ", v[2])
		straits += v[1]
		if d[0] != pr[0] or d[d.size() - 1] != pr[1]: bad += 1
		var pts: PackedVector2Array = nav.to_points(r, -1, 1.0)
		for k in range(1, pts.size()):
			if pts[k - 1].distance_to(pts[k]) < 1.5 and absf(pts[k - 1].x - pts[k].x) > 0.9: continue  # 1-tile diagonal strait
			if not nav.seg_water(pts[k - 1], pts[k]):
				pxbad += 1
				if pxbad <= 3: print("  px seg on land k=%d/%d %s -> %s corners=%d" % [k, pts.size(), str(pts[k - 1]), str(pts[k]), r.size()])
				break
		var sl := Vector2(pr[0] % nav.W - pr[1] % nav.W, pr[0] / nav.W - pr[1] / nav.W).length()
		if sl > 50:
			var pl := 0.0
			for k in range(1, r.size()): pl += Vector2(r[k] % nav.W - r[k - 1] % nav.W, r[k] / nav.W - r[k - 1] / nav.W).length()
			detour += pl / sl; nd += 1
	print("  breakdown us: astar=%d stitch=%d smooth=%d expanded=%d searches=%d" % [nav.usec_astar / 200, nav.usec_stitch / 200, nav.usec_smooth / 200, nav.expanded / maxi(1, nav.searches), nav.searches])
	times.sort()
	var tot := 0
	for t in times: tot += t
	print("  cold queries=200 found=%d invalid=%d px_cross_land=%d straits=%d  us avg=%d p50=%d p95=%d max=%d  mean_detour=%.2f" % [200 - nofound, bad, pxbad, straits, tot / times.size(), times[100], times[190], times[199], detour / maxf(1, nd)])
	_check(nofound == 0 and bad == 0 and pxbad == 0, "%s random routes" % name)
	# warm (cached) repeat
	for pr in pairs: nav.find_route(pr[0], pr[1])
	var tw := Time.get_ticks_usec()
	for pr in pairs: nav.find_route(pr[0], pr[1])
	print("  warm repeat avg us=%.1f" % ((Time.get_ticks_usec() - tw) / 200.0))
	# old BFS for comparison (first 30 pairs, as coastal endpoints are not needed: it searches water)
	var old_ok := 0; var old_t := 0
	for k in 30:
		var pr = pairs[k]
		var t2 := Time.get_ticks_usec()
		var op: PackedVector2Array = m._water_path(pr[0], pr[1])
		old_t += Time.get_ticks_usec() - t2
		if op.size() >= 2: old_ok += 1
	print("  old _water_path (BFS, 14000 nodes) on 30 pairs: found=%d avg_us=%d" % [old_ok, old_t / 30])
	# routes around continents (fractions of the map; endpoints snapped to the big body)
	var img := _base_image(nav)
	var named := []
	if name.contains("world"):
		named = [["N.Atlantic->Indian Ocean (around Africa)", [0.38, 0.33], [0.62, 0.62]], ["Mediterranean->Atlantic", [0.53, 0.31], [0.40, 0.35]],
			["Pacific W->Atlantic", [0.95, 0.40], [0.40, 0.45]], ["Indian->S.Pacific", [0.62, 0.62], [0.97, 0.66]]]
	elif name == "europe":
		named = [["Baltic->Mediterranean", [0.62, 0.38], [0.62, 0.85]], ["North Sea->Black Sea", [0.45, 0.40], [0.95, 0.75]], ["Atlantic->Adriatic", [0.10, 0.60], [0.66, 0.75]]]
	else:
		named = [["corner->corner", [0.05, 0.05], [0.95, 0.95]], ["W->E", [0.03, 0.5], [0.97, 0.5]], ["N->S", [0.5, 0.1], [0.5, 0.9]]]
	for nm in named:
		var a := _nearest_water(nav, nm[1][0], nm[1][1], big)
		var b := _nearest_water(nav, nm[2][0], nm[2][1], big)
		if a < 0 or b < 0: print("  route %s: no endpoint" % nm[0]); continue
		nav._route_cache.clear(); nav._reg_cache.clear()
		var t3 := Time.get_ticks_usec()
		var r: PackedInt32Array = nav.find_route(a, b)
		var us := Time.get_ticks_usec() - t3
		if r.is_empty():
			print("  route %s: NONE" % nm[0]); _check(false, "%s %s" % [name, nm[0]]); continue
		var d: PackedInt32Array = nav.dense(r)
		var v := _valid(nav, d, big)
		_check(v[0], "%s %s valid" % [name, nm[0]])
		var miny: int = nav.H; var maxy := 0
		for t in d: miny = mini(miny, t / nav.W); maxy = maxi(maxy, t / nav.W)
		print("  route %s: (%d,%d)->(%d,%d) corners=%d tiles=%d y=%d..%d valid=%s us=%d" % [nm[0], a % nav.W, a / nav.W, b % nav.W, b / nav.W, r.size(), d.size(), miny, maxy, str(v[0]), us])
		_draw(img, nav, nav.to_points(r, -1, 1.0), Color(0.9, 0.1, 0.1))
	# transport: fake owner 99 on a coastal blob near the first route start, landing far away
	var om: PackedInt32Array = m.owner_map.duplicate()
	var own := -1
	for k in range(nav.coast_tiles.size() / 3, nav.coast_tiles.size()):
		var c: int = nav.coast_tiles[k]
		if nav.region_of(nav.water_next_to(c)) >= 0 and nav.body[nav.water_next_to(c)] == big: own = c; break
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var t: int = own + dy * nav.W + dx
			if t >= 0 and t < nav.N and om[t] >= 0: om[t] = 99
	var dest := -1
	for k in range(nav.coast_tiles.size() - 1, 0, -97):
		var c: int = nav.coast_tiles[k]
		var w: int = nav.water_next_to(c)
		if w >= 0 and nav.body[w] == big and om[c] != 99 and Vector2(c % nav.W - own % nav.W, c / nav.W - own / nav.W).length() > 300:
			dest = c; break
	var tb := Time.get_ticks_usec()
	var br: PackedInt32Array = nav.boat_route(om, 99, dest)
	var bus := Time.get_ticks_usec() - tb
	var bok := br.size() >= 1
	var start_adj := false
	if bok:
		var s0: int = br[0]
		for dd in [1, -1, nav.W, -nav.W]:
			if s0 + dd >= 0 and s0 + dd < nav.N and om[s0 + dd] == 99: start_adj = true
		var v2 := _valid(nav, nav.dense(br), big)
		bok = v2[0] and start_adj
		var bp: PackedVector2Array = nav.to_points(br, dest, 2.0)
		for k in range(1, bp.size() - 1):
			if bp[k - 1].distance_to(bp[k]) < 3.0 and absf(bp[k - 1].x - bp[k].x) > 1.8: continue  # strait
			if not nav.seg_water(bp[k - 1] / 2.0, bp[k] / 2.0): bok = false; print("  boat seg on land ", bp[k - 1] / 2.0, bp[k] / 2.0)
		_draw(img, nav, nav.to_points(br, dest, 1.0), Color(0.1, 0.2, 0.9))
	print("  boat_route own=(%d,%d) dest=(%d,%d) corners=%d starts_next_to_own=%s ok=%s us=%d" % [own % nav.W, own / nav.W, dest % nav.W, dest / nav.W, br.size(), str(start_adj), str(bok), bus])
	_check(bok, "%s boat_route" % name)
	# local transport: landing 60..200 tiles from the own coast (the usual case)
	var dest2 := -1
	for k in range(0, nav.coast_tiles.size(), 7):
		var c: int = nav.coast_tiles[k]
		var w: int = nav.water_next_to(c)
		var dl := Vector2(c % nav.W - own % nav.W, c / nav.W - own / nav.W).length()
		if w >= 0 and nav.body[w] == big and om[c] != 99 and dl > 60 and dl < 200: dest2 = c; break
	if dest2 >= 0:
		var tl := Time.get_ticks_usec()
		var br2: PackedInt32Array = nav.boat_route(om, 99, dest2)
		var lus := Time.get_ticks_usec() - tl
		var ok2: bool = br2.size() >= 1 and _valid(nav, nav.dense(br2), big)[0]
		print("  boat_route local dest=(%d,%d) corners=%d ok=%s us=%d" % [dest2 % nav.W, dest2 / nav.W, br2.size(), str(ok2), lus])
		_check(ok2, "%s local boat_route" % name)
		if ok2: _draw(img, nav, nav.to_points(br2, dest2, 1.0), Color(0.6, 0.1, 0.8))
	# warship steering to a target behind land
	var wsr := nav.find_route(_nearest_water(nav, 0.38, 0.33, big), _nearest_water(nav, 0.62, 0.62, big)) if name.contains("world") else PackedInt32Array()
	var s := water[7]; var g := water[water.size() / 2]
	if not wsr.is_empty(): s = wsr[0]; g = wsr[wsr.size() - 1]
	var ws := {"pos": Vector2(s % nav.W + 0.5, s / nav.W + 0.5), "tgt": Vector2(g % nav.W + 0.5, g / nav.W + 0.5)}
	var on_land := 0; var ticks := 0; var trail := PackedVector2Array()
	nav.budget_us = 3000
	while ticks < 40000 and ws.pos.distance_to(ws.tgt) > 0.01:
		nav.begin_tick()
		if not nav.steer(ws, 0.5): break
		ticks += 1
		var p: Vector2 = ws.pos
		if body[int(p.y) * nav.W + int(p.x)] == 0: on_land += 1
		if ticks % 4 == 0: trail.append(p)
	var arrived: bool = ws.pos.distance_to(ws.tgt) <= 0.01
	print("  warship steer: ticks=%d arrived=%s on_land_ticks=%d" % [ticks, str(arrived), on_land])
	_check(arrived and on_land == 0, "%s warship steer" % name)
	_draw(img, nav, trail, Color(0.1, 0.7, 0.1))
	# budget: 60 non-urgent cold queries in one tick
	nav._route_cache.clear(); nav._reg_cache.clear()
	nav.budget_us = 3000; nav.begin_tick()
	var done := 0; var defer0: int = nav.deferred
	var tq := Time.get_ticks_usec()
	for k in 60:
		var pr = pairs[k]
		if not nav.find_route(pr[0], pr[1], false).is_empty(): done += 1
	print("  budget 3000us: 60 requests -> %d solved, %d deferred, tick_us=%d" % [done, nav.deferred - defer0, Time.get_ticks_usec() - tq])
	img.save_png("%s/nav_%s.png" % [shots, name])

func _base_image(nav) -> Image:
	var w: int = nav.W / 2; var h: int = nav.H / 2
	var im := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var t: int = (y * 2) * nav.W + x * 2
			im.set_pixel(x, y, Color(0.27, 0.5, 0.7) if nav.body[t] > 0 else Color(0.78, 0.8, 0.62))
	return im

func _draw(im: Image, nav, pts: PackedVector2Array, col: Color) -> void:
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1] / 2.0; var b: Vector2 = pts[k] / 2.0
		var n := int(a.distance_to(b) * 2.0) + 1
		for s in n + 1:
			var p := a.lerp(b, float(s) / n)
			for oy in 2:
				for ox in 2:
					var x := int(p.x) + ox; var y := int(p.y) + oy
					if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height(): im.set_pixel(x, y, col)

# ------------------------------------------------------------------------------------------------
# in-game run (hooks applied)
func _px_ok(nav, pts: PackedVector2Array, ts: float, skip_last: bool) -> bool:
	var n := pts.size()
	if skip_last and n > 1 and not nav.is_water(int(pts[n - 1].y / ts) * nav.W + int(pts[n - 1].x / ts)): n -= 1
	var k0 := 1
	# a route may start on its port/coast tile (reversed trade routes): skip that launch leg
	if pts.size() > 1 and not nav.is_water(int(pts[0].y / ts) * nav.W + int(pts[0].x / ts)): k0 = 2
	for k in range(k0, n):
		var a: Vector2 = pts[k - 1] / ts; var b: Vector2 = pts[k] / ts
		if a.distance_to(b) < 1.5 and absf(a.x - b.x) > 0.4 and absf(a.y - b.y) > 0.4: continue  # strait
		if not nav.seg_water(a, b): return false
	return true

func _game(m) -> void:
	if m.get("sim_nav") == null and not ("sim_nav" in m):
		print("  --game: main.gd has no sim_nav (hooks not applied)"); fails += 1; return
	m.map_tab = 0; m.map_i = 0
	m.gen_map()
	var nav = m.sim_nav
	_check(nav != null and nav.ready, "sim_nav built in gen_map")
	if nav == null: return
	print("GAME world nav build_ms=%.0f regions=%d clusters=%d" % [nav.build_ms, nav.reg_count, nav.clu_count])
	m.rng.seed = 20261109; seed(20261109)
	m._start_game()
	m.rng.seed = 20261109; seed(20261109)
	var nonav := "--nonav" in OS.get_cmdline_user_args()   # baseline: old BFS / straight lines, same checks
	if nonav: m.sim_nav = null; print("  baseline run: sim_nav disabled")
	var st: int = m._find_spawn_tile(int(m.W * 0.47), int(m.H * 0.40))
	m._place_start(st); m.deploy_t = 0.0; m.state = "play"; m.peace = 0.0
	m._claim_blob(m.PLAYER, st, 40)
	var W: int = m.W
	# ports + warships for the player and 10 coastal bots
	var owners := [m.PLAYER]
	for id in range(2, m.nations.size()):
		if owners.size() >= 11: break
		if m.nations[id].alive and int(m.nations[id].get("land", 0)) > 0: owners.append(id)
	var ports := 0; var ships := 0
	for o in owners:
		m.nations[o].gold = 1e12
		for c in m.sim_naval.coast_list:
			if m.owner_map[c] == o:
				m._ai_place_budget = 100
				if m.try_build(1, c, o): ports += 1; break
	for s2 in m.structs: s2.bt = 0.0
	m._sv += 1
	for o in owners:
		for _k in 2:
			if m.spawn_warship(o): ships += 1
	print("  ports=%d warships=%d owners=%d" % [ports, ships, owners.size()])
	# a long player transport: a coast in the Americas (local landing chosen by launch_boat)
	var far := -1
	for c in m.sim_naval.coast_list:
		if c % W < int(W * 0.30) and m.owner_map[c] > 0 and m.owner_map[c] != m.PLAYER: far = c; break
	m.nations[m.PLAYER].troops = 1e6
	var t0 := Time.get_ticks_usec()
	var ok: bool = m.launch_boat(m.PLAYER, far, 0.2)
	var lus := Time.get_ticks_usec() - t0
	var bpts: PackedVector2Array = m.boats[m.boats.size() - 1].pts if ok and m.boats.size() > 0 else PackedVector2Array()
	print("  player transport to (%d,%d): launched=%s pts=%d us=%d water=%s" % [far % W, far / W, str(ok), bpts.size(), lus, str(_px_ok(nav, bpts, m.TS, true))])
	_check(ok and _px_ok(nav, bpts, m.TS, true), "player long transport")
	# play
	var bad_boat := 0; var bad_trade := 0; var bad_ws := 0
	var seen_boats := {}; var seen_trade := {}
	var max_ws := 0; var max_trade := 0; var max_boats := 0
	var ws_moved := 0
	var last_pos := {}
	var frame_max := 0; var frame_tot := 0
	var s0: int = nav.searches; var u0: int = nav.usec
	for tick in 1500:
		var tf := Time.get_ticks_usec()
		m._process(0.1)
		var fu := Time.get_ticks_usec() - tf
		frame_tot += fu; frame_max = maxi(frame_max, fu)
		if tick % 5 != 0: continue
		for bt in m.boats:
			var k := str(bt.get("uid", 0))
			if seen_boats.has(k): continue
			seen_boats[k] = true
			if not _px_ok(nav, bt.pts, m.TS, true): bad_boat += 1
		for tr in m.traders:
			var k2 := "%d" % tr.pts.size() + str(tr.pts[0]) + str(tr.pts[tr.pts.size() - 1])
			if seen_trade.has(k2): continue
			seen_trade[k2] = true
			if not _px_ok(nav, tr.pts, m.TS, true):
				bad_trade += 1
				if bad_trade <= 3:
					var dbg := []
					for q in tr.pts: dbg.append("(%.2f,%.2f)%s" % [q.x / m.TS, q.y / m.TS, "W" if nav.is_water(int(q.y / m.TS) * W + int(q.x / m.TS)) else "L"])
					print("  bad trade n=%d %s" % [tr.pts.size(), " ".join(dbg.slice(0, 6)) + " ... " + " ".join(dbg.slice(maxi(0, dbg.size() - 4)))])
		for ws in m.warships:
			var p: Vector2 = ws.pos
			if not nav.is_water(int(p.y) * W + int(p.x)): bad_ws += 1
			var u := int(ws.get("uid", 0))
			if last_pos.has(u) and last_pos[u].distance_to(p) > 0.5: ws_moved += 1
			last_pos[u] = p
		max_ws = maxi(max_ws, m.warships.size()); max_trade = maxi(max_trade, m.traders.size()); max_boats = maxi(max_boats, m.boats.size())
	print("  1500 ticks: frame avg_ms=%.2f max_ms=%.1f  transports=%d bad=%d  trade_routes=%d bad=%d  warships<=%d moves=%d on_land=%d  max_boats=%d max_traders=%d" % [frame_tot / 1500000.0, frame_max / 1000.0, seen_boats.size(), bad_boat, seen_trade.size(), bad_trade, max_ws, ws_moved, bad_ws, max_boats, max_trade])
	print("  nav during play: searches=%d avg_us=%.0f max_us=%d deferred=%d cache_hits=%d fails=%d" % [nav.searches - s0, float(nav.usec - u0) / maxf(1, nav.searches - s0), nav.usec_max, nav.deferred, nav.cache_hits, nav.fails])
	_check(bad_boat == 0 and bad_trade == 0 and bad_ws == 0, "in-game routes on water")
	_check(seen_boats.size() > 0 and ws_moved > 0, "in-game activity")
