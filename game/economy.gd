extends "res://game/nations.gd"
# Economy, building, attacks and combat

func _oc_rebuild() -> void:
	_oc_ver = _sv
	_oc_lvl.clear(); _oc_cnt.clear()
	for st in structs:
		var key: int = st.o * 64 + st.k
		_oc_lvl[key] = _oc_lvl.get(key, 0) + int(st.get("level", 1))
		_oc_cnt[key] = _oc_cnt.get(key, 0) + 1

func owned(id: int, k: int) -> int:
	if _oc_ver != _sv or _oc_ver < 0: _oc_rebuild()
	return _oc_lvl.get(id * 64 + k, 0)

func owned_count(id: int, k: int) -> int:
	if _oc_ver != _sv or _oc_ver < 0: _oc_rebuild()
	return _oc_cnt.get(id * 64 + k, 0)

func troop_cap(id: int) -> float:
	return sim_rules.max_troops(troop_kind(id), nations[id].land, owned(id, 0), troop_diff(id))

func gold_rate(id: int) -> float:
	# passive goldAdditionRate x 10 per second (trade ships, trains and conquests come on top)
	return sim_rules.gold_per_tick(kind_of(id)) * 10.0 if nations[id].land > 0 else 0.0

func build_cost(id: int, k: int) -> float:
	var base: float = build_data[k][2]
	if k in NUKES: return nuke_cost(k, id)
	if k == 13: return base
	var rw_names := {0: "city", 3: "defense", 4: "sam", 5: "silo", 10: "artillery", 14: "airfield", 15: "railgun"}
	if k == 1 or k == 2: return SimRules.build_cost("port", owned(id, 1) + owned(id, 2))
	if k == 6: return SimRules.build_cost("warship", _count_ws(id))
	if rw_names.has(k): return SimRules.build_cost(rw_names[k], owned(id, k))
	if k == 10: return minf(750e3, 150e3 * (owned(id, 10) + 1))
	if k == 14: return minf(1.5e6, 500e3 * (owned(id, 14) + 1))
	if k == 15: return minf(7.5e6, 2.5e6 * (owned(id, 15) + 1))
	if k == 0:
		var c := owned(id, 0)
		var l := [125e3, 250e3, 500e3, 1e6]
		return l[mini(c, 3)]
	if k == 1 or k == 2:
		var c := owned(id, 1) + owned(id, 2)
		var l := [125e3, 250e3, 500e3, 1e6]
		return l[mini(c, 3)]
	if k == 3:
		var c := owned(id, 3)
		return minf(250e3, 50e3 * (c + 1))
	if k == 4:
		return 1.5e6 if owned(id, 4) == 0 else 3.0e6
	if k == 5:
		return 1.0e6
	if k == 6:
		var c := _count_ws(id)
		return minf(1.0e6, 250e3 * (c + 1))
	return base * (1.0 + owned(id, k) * 0.5)

func _rebuild_def_posts() -> void:
	def_posts.clear()
	for st in structs:
		if st.k == 3 and float(st.get("bt", 0.0)) <= 0.0:
			if not def_posts.has(st.o): def_posts[st.o] = PackedInt32Array()
			var arr: PackedInt32Array = def_posts[st.o]
			arr.append(st.tile)
			def_posts[st.o] = arr

func defended(i: int, o: int) -> bool:
	if o <= 0 or not def_posts.has(o): return false
	var x := i % W; var y := i / W
	var r := sim_rules.defense_range
	var r2 := r * r
	for t in def_posts[o]:
		var dx: int = t % W - x; var dy: int = t / W - y
		if dx * dx + dy * dy <= r2: return true
	return false

func _find_upgrade_target(k: int, tile: int, o: int) -> Dictionary:
	if tile < 0 or not (k in UPGRADABLE): return {}
	var x := tile % W; var y := tile / W
	var best := {}
	var bd := 81.0  # within 9 tiles clicks upgrade existing building of same type
	for st in structs:
		if st.o == o and st.k == k:
			var d := Vector2(st.tile % W - x, st.tile / W - y).length_squared()
			if d <= bd:
				bd = d; best = st
	return best

func build_req(k: int, tile: int, o := PLAYER) -> String:
	if k == 9 and not mirv_enabled: return "Not available in this prototype yet"
	if o == PLAYER and (god_mode or no_cd):
		if tile >= 0 and k != 6 and not (k in NUKES or _is_strike_click(k, tile, o)) and owner_map[tile] != o: return "Must be on your own land"
		return ""
	if o == PLAYER and kind_locked(k) != "": return "Locked: unlock it in the Arsenal"
	if _is_strike_click(k, tile, o):
		var lk := k
		var have := false
		var rdy := false
		var min_cd := 999.0
		for st in structs:
			if st.o == o and st.k == lk and st.get("bt", 0.0) <= 0.0:
				have = true
				if sim_ars.ready_missiles(st) > 0: rdy = true; break
				min_cd = minf(min_cd, float(st.get("cd", 0.0)))
		if not have: return "Build an Airfield first" if k == 14 else "Build a Railgun first"
		if not rdy: return ("Airfield rearming (%ds)" if k == 14 else "Railgun reloading (%ds)") % maxi(1, ceili(min_cd))
		return ""
	if k in NUKES:
		if owned(o, 5) == 0: return "Requires a Missile Silo"
		var ready := false
		var min_cd := 999.0
		for st in structs:
			if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0:
				if _ready_slots(st) > 0: ready = true; break
				min_cd = minf(min_cd, float(st.get("cd", 9.0)))
		if not ready: return "Silo reloading (%ds)" % maxi(1, ceili(min_cd if min_cd < 900.0 else 9.0))
		return ""
	if k == 6:
		var have_port := false
		var port_wait := false
		for st in structs:
			if st.o == o and st.k == 1:
				if float(st.get("bt", 0.0)) <= 0.0: have_port = true; break
				port_wait = true
		if not have_port: return "Port under construction" if port_wait else "Requires a Port"
	if k == 13:
		var cd: float = nations[o].get("reinf_cd", 0.0)
		return ("Cooldown %ds" % ceili(cd)) if cd > 0 else ""
	if k == 6: return ""
	if tile >= 0:
		var site := sim_struct.place_site(o, k, tile)
		if site.reason != "": return SimStructures.reason_text(site.reason)
	return ""

func select_build(k: int) -> void:
	if state != "play" or k < 0 or k >= build_data.size(): return
	strike_only = false  # (the Air Strike / Slug slots set it again after selecting)
	if k == 16:
		set_icbm(not icbm_mode)
		notify("ICBM %s: +10%% cost, 20%% SAM evasion, +20%% speed, -20%% cooldown" % ("ON" if icbm_mode else "OFF"), "info"); return
	if k == 13:
		try_build(k, -1); return
	if k == 6:
		var req6 := build_req(6, -1)
		if req6 != "":
			notify(req6, "bad")
			return
		# Selecting Warship enters placement mode so you can click water/coast to place it, OR clicking the button a second time auto-launches from your Port!
		if build_sel == 6:
			try_build(6, -1)
			build_sel = -1
			return
		build_sel = 6
		return
	if k in NUKES and build_req(k, -1) != "": return
	build_sel = -1 if build_sel == k else k

func try_build(k: int, tile: int, o := PLAYER) -> bool:
	if not can_build(o): return false
	if o != PLAYER and not (k in NUKES):
		if _ai_place_budget <= 0: return false
		_ai_place_budget -= 1
	var n = nations[o]
	if o == PLAYER and strike_only and (k == 14 or k == 15) and not _is_strike_click(k, tile, o):
		notify("Pick a target outside your own land", "info")  # the Air Strike / Slug slots never build
		return false
	if _is_strike_click(k, tile, o):
		var oks := sim_ars.launch_strike(o, SimRules.N_AIRSTRIKE if k == 14 else SimRules.N_SLUG, tile)
		if oks and o == PLAYER: build_sel = -1
		return oks
	var cost := build_cost(o, k)
	var req := build_req(k, tile, o)
	if req != "" or n.gold < cost:
		if o == PLAYER and k == 6:
			notify(req if req != "" else ("Need %s gold for Warship" % _fmt(cost)), "bad")
		return false
	if k in NUKES:
		if tile < 0 or tile >= W * H: return false  # open water may be bombed (upstream allows it)
		var okn := launch_nuke(o, k, tile)
		if okn and o == PLAYER: build_sel = -1
		return okn
	n.gold -= cost
	if k == 13:
		# SimArsenal.reinforce: a fifth of the troop cap, never past it, every 30 s
		var add := SimRules.reinforce_troops(n.troops, troop_cap(o))
		if add <= 0.0:
			n.gold += cost
			if o == PLAYER: notify("Your army is already at its cap", "info")
			return false
		n.troops += add
		n.reinf_cd = SimRules.REINFORCE_COOLDOWN_TICKS / 10.0
		if o == PLAYER: sfx("spawn")
		return true
	if k == 6:
		if not spawn_warship(o, tile):
			n.gold += cost
			if o == PLAYER: notify("No coastal water found near your Port", "bad")
			return false
		if o == PLAYER:
			build_sel = -1
			sfx("build_warship")
			notify("Warship deployed!", "good")
			_update_hud()
		return true
	var site := sim_struct.place_site(o, k, tile)
	if site.reason != "":
		n.gold += cost
		return false
	if site.upgrade != null:
		_upgrade_struct(site.upgrade)
		if o == PLAYER: build_sel = -1; sfx("warship" if k == 6 else "build")
		return true
	_struct_add(k, int(site.tile), o)
	if o == PLAYER: build_sel = -1; sfx("warship" if k == 6 else "build")
	return true

# Airfield / Railgun tool on land that isn't yours fires the munition (upstream: Air Strike / Slug buttons)
func _is_strike_click(k: int, tile: int, o: int) -> bool:
	# the Airfield / Railgun tool fires at land that is not yours; water is not a target for it (an invalid
	# spot to build on, no crosshair), only the armed Air Strike / Slug slot may aim at the sea
	if (k == 14 or k == 15) and tile >= 0 and tile < owner_map.size() and owner_map[tile] == WATER and not strike_only:
		return false
	return (k == 14 or k == 15) and tile >= 0 and tile < owner_map.size() and owner_map[tile] != o

func tile_cost(a: int, t: int) -> float:
	if t == NEUTRAL:
		return 16.0
	var d = nations[t]
	var base: float = 20.0 + d.troops / maxf(1.0, d.land) * 1.2
	# Anti-snowball large-defender sigmoid debuff & large-attacker scaling
	var def_share: float = float(d.land) / maxf(1.0, float(land_total))
	if def_share > 0.20:
		base *= clampf(1.0 / (1.0 + exp((def_share - 0.35) * 8.0)), 0.45, 1.0)
	if a > 0 and nations[a].land > land_total * 0.25:
		base *= pow(float(nations[a].land) / (land_total * 0.25), 0.25)
	return base

func tile_cost_at(a: int, t: int, i: int) -> float:
	var c := tile_cost(a, t)
	var ter: int = mtn[i]
	if ter == 0: c *= 0.80        # Plains: mag 80 (0.8x)
	elif ter == 1: c *= 1.00      # Highlands: mag 100 (1.0x)
	else: c *= 2.00               # Mountains: 2.0x troop loss
	if fallout[i] == 1:
		var prog: float = clampf(1.0 - fallout_t[i] / 60.0, 0.0, 1.0)
		c *= (5.0 - prog * 2.0)   # OpenFront fallout formula: 5x tapering to 3x
	if t > 0 and is_traitor(t): c *= 0.5
	if defended(i, t): c *= 5.0
	return c

func tile_time(t: int, i: int) -> int:
	var ter: int = mtn[i]
	var s := 1.0
	if ter == 1: s *= 1.25        # Highlands speed 20 vs Plains 16.5
	elif ter == 2: s *= 2.5       # Mountains 2.5x slower
	if fallout[i] == 1:
		var prog: float = clampf(1.0 - fallout_t[i] / 60.0, 0.0, 1.0)
		s *= (5.0 - prog * 2.0) * 0.7
	if defended(i, t): s *= 3.0
	return maxi(1, int(round(s)))

# True if any border tile of s1 has a 4-neighbour owned by other.
func _border_touches(s1: int, other: int) -> bool:
	var N := W * H
	for t in border[s1]:
		var x: int = t % W
		if x > 0 and owner_map[t - 1] == other: return true
		if x < W - 1 and owner_map[t + 1] == other: return true
		if t >= W and owner_map[t - W] == other: return true
		if t < N - W and owner_map[t + W] == other: return true
	return false

func _shares_land_border(a: int, b: int, click_tile: int = -1) -> bool:
	if a <= 0 or a >= nations.size() or not nations[a].alive or nations[a].land <= 0:
		return false
	if b > 0:
		if b >= nations.size() or not nations[b].alive or nations[b].land <= 0:
			return false
		var box: Rect2i = nations[a].bb.grow(1).intersection(nations[b].bb.grow(1)).intersection(Rect2i(0, 0, W, H))
		if box.size.x <= 0 or box.size.y <= 0:
			return false
		if border.size() == nations.size():
			# walk the smaller border set: a and b touch iff one has a border tile next to the other
			var s1: int = a if border[a].size() <= border[b].size() else b
			return _border_touches(s1, b if s1 == a else a)
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				var i := y * W + x
				if owner_map[i] == b and _adj_to(i, a):
					return true
		return false
	if b == NEUTRAL:
		var box_a: Rect2i = nations[a].bb.grow(1).intersection(Rect2i(0, 0, W, H))
		var has_adj_neutral := false
		if border.size() == nations.size():
			has_adj_neutral = _border_touches(a, NEUTRAL)
		else:
			for y in range(box_a.position.y, box_a.end.y):
				for x in range(box_a.position.x, box_a.end.x):
					var i := y * W + x
					if owner_map[i] == NEUTRAL and _adj_to(i, a):
						has_adj_neutral = true; break
				if has_adj_neutral: break
		if not has_adj_neutral:
			return false
		if click_tile < 0 or click_tile >= W * H:
			return true
		# Check if click_tile is on the same landmass as 'a' (reachable over land without crossing water)
		if bfs_par.size() != W * H:
			bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
		bfs_gen += 1
		var gen := bfs_gen
		var q := PackedInt32Array([click_tile])
		bfs_stamp[click_tile] = gen
		var qi := 0
		while qi < q.size() and qi < 18000:
			var cur: int = q[qi]; qi += 1
			if owner_map[cur] == a or _adj_to(cur, a):
				return true
			var cx := cur % W
			for d in [1, -1, W, -W]:
				if (d == 1 and cx == W - 1) or (d == -1 and cx == 0): continue
				var j: int = cur + d
				if j >= 0 and j < W * H and owner_map[j] >= 0 and bfs_stamp[j] != gen:
					bfs_stamp[j] = gen; q.append(j)
		return false
	return false

func launch_attack(a: int, t: int, share: float) -> bool:
	if allied(a, t):
		if a == PLAYER: notify("%s is your ally — right-click to manage alliance" % _nname(t), "info")
		return false
	if t == a or t < 0:
		return false
	if t > 0 and not nations[t].alive:
		return false
	if shielded(t):
		if a == PLAYER: notify(shield_text(t), "info")
		return false
	if t > 0 and shielded(a) and kind_of(t) != SimRules.KIND_TRIBE:
		# attacking a person or a nation ends one's own spawn shield
		shield_until.erase(a)
		if a == PLAYER: notify("You attacked %s, so your spawn shield is down" % _nname(t), "info")
	var n = nations[a]
	var troops: float = n.troops * clampf(share, 0.0, 1.0)
	if troops < 1.0:
		return false
	n.troops -= troops
	var started := sim_atk.start(a, t, troops) != null
	# (no launch sound for a land attack: the land-gain pops are its sound)
	return started

func _frontier(a: int, t: int) -> Array:
	var bb: Rect2i = nations[a].bb.grow(1).intersection(Rect2i(0, 0, W, H))
	if t > 0 and t < nations.size():
		bb = bb.intersection(nations[t].bb.grow(1))
	var fr := []
	if bb.size.x <= 0 or bb.size.y <= 0:
		return fr
	if bb.get_area() <= 16000:
		for y in range(bb.position.y, bb.end.y):
			for x in range(bb.position.x, bb.end.x):
				var i := y * W + x
				if owner_map[i] == t and _adj_to(i, a):
					fr.append(i)
	else:
		# large nation: sample first, then fallback to full scan if sampling missed a narrow border
		for k in 5000:
			var i := (bb.position.y + rng.randi() % bb.size.y) * W + bb.position.x + rng.randi() % bb.size.x
			if owner_map[i] == t and _adj_to(i, a):
				fr.append(i)
		if fr.is_empty():
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var i := y * W + x
					if owner_map[i] == t and _adj_to(i, a):
						fr.append(i)
	fr.shuffle()
	return fr

func _adj_to(i: int, a: int) -> bool:
	var x := i % W
	if x > 0 and owner_map[i - 1] == a: return true
	if x < W - 1 and owner_map[i + 1] == a: return true
	if i >= W and owner_map[i - W] == a: return true
	if i < W * (H - 1) and owner_map[i + W] == a: return true
	return false

func _tick_attacks() -> void:
	_rebuild_def_posts()
	sim_atk.tick_all()

func _adj_count(i: int, a: int) -> int:
	var x := i % W
	var c := 0
	if x > 0 and owner_map[i - 1] == a: c += 1
	if x < W - 1 and owner_map[i + 1] == a: c += 1
	if i >= W and owner_map[i - W] == a: c += 1
	if i < W * (H - 1) and owner_map[i + W] == a: c += 1
	return c

func _coastal(i: int) -> bool:
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j >= 0 and j < W * H and owner_map[j] == WATER: return true
	return false

func launch_boat(a: int, click: int, share: float, max_nodes := 1000000) -> bool:
	if click < 0 or click >= W * H: return false
	var o := owner_map[click]
	if o < 0 or o == a or allied(a, o): return false
	# Upstream SimNaval.launch_boat does not redirect to a land attack when a land border exists
	# (UI already chooses attack vs boat). Vanilla: a boat order stays a boat order.
	var dest := -1
	var best := 1e9
	var cx := click % W; var cy := click / W
	for y in range(maxi(0, cy - 24), mini(H, cy + 25)):
		for x in range(maxi(0, cx - 24), mini(W, cx + 25)):
			var i := y * W + x
			if owner_map[i] == o and _coastal(i):
				var dd := Vector2(x - cx, y - cy).length_squared()
				if dd < best: best = dd; dest = i
	# If the player clicked an inland tile of an overseas nation 'o', find the closest coastal tile of 'o' anywhere in its territory
	if dest < 0 and o > 0 and o < nations.size():
		var bbo: Rect2i = nations[o].bb.intersection(Rect2i(0, 0, W, H))
		for y in range(bbo.position.y, bbo.end.y):
			for x in range(bbo.position.x, bbo.end.x):
				var i := y * W + x
				if owner_map[i] == o and _coastal(i):
					var dd := Vector2(x - cx, y - cy).length_squared()
					if dd < best: best = dd; dest = i
	if dest < 0: return false  # no coast to land on (vanilla has no transport planes)
	# RoWorld launch_boat limits: boats at sea (10 for you, 3 for AI), 2 boat orders per second, floored troops
	if sim_naval.boats_of(a) >= sim_naval.max_boats(a):
		if a == PLAYER: notify("Too many transports at sea", "info")
		return false
	var troops: float = floor(nations[a].troops * clampf(share, 0.01, 1.0))
	if troops < 1.0: return false
	if not sim_naval.take_token(a):
		if a == PLAYER: notify("Too many boat orders at once — wait a moment", "info")
		return false
	var key := "%d:%d" % [a, dest]
	if path_cache.has(key) and elapsed - path_cache[key][1] < 30.0:
		var cp: PackedVector2Array = path_cache[key][0]
		var st := Vector2i(int(cp[0].x / TS), int(cp[0].y / TS))
		if _adj_to(st.y * W + st.x, a):
			_spawn_boat(a, cp, dest, troops)
			return true
	# A search that just ran out of nodes for this (owner, landing) pair is not repeated for 10 s:
	# the AI re-picks the same unreachable coast every frame and each miss walks 12000 water tiles.
	if path_fail.has(key) and elapsed - float(path_fail[key]) < 10.0: return false
	if sim_nav != null and sim_nav.ready:
		# SimNav: nearest own coast by sea from the (local) landing tile, A* over the region graph
		var nr: PackedInt32Array = sim_nav.boat_route(owner_map, a, dest, max_nodes)  # same reach cap as the old BFS
		if nr.is_empty():
			if path_fail.size() > 2000: path_fail.clear()
			path_fail[key] = elapsed
			return false  # no sea route (vanilla has no transport planes)
		var npts: PackedVector2Array = sim_nav.to_points(nr, dest, TS)
		path_cache[key] = [npts, elapsed]
		if path_cache.size() > 400: path_cache.clear()
		_spawn_boat(a, npts, dest, troops)
		return true
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array()
	for d in [1, -1, W, -W]:
		if (d == 1 and dest % W == W - 1) or (d == -1 and dest % W == 0): continue
		var j: int = dest + d
		if j >= 0 and j < W * H and owner_map[j] == WATER:
			bfs_par[j] = -1; bfs_stamp[j] = gen; q.append(j)
	var qi := 0
	var found := -1
	# same BFS order as before (+1, -1, +W, -W), inlined for speed
	var om: PackedInt32Array = owner_map
	var NN := W * H
	while qi < q.size() and qi < max_nodes:
		var i: int = q[qi]; qi += 1
		var ix := i % W
		if (ix > 0 and om[i - 1] == a) or (ix < W - 1 and om[i + 1] == a) or (i >= W and om[i - W] == a) or (i < NN - W and om[i + W] == a):
			found = i; break
		var j := i + 1
		if ix != W - 1 and j < NN and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i - 1
		if ix != 0 and j >= 0 and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i + W
		if j < NN and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i - W
		if j >= 0 and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	if found < 0:
		if path_fail.size() > 2000: path_fail.clear()
		path_fail[key] = elapsed
		return false
	var path := []
	var k := found
	while k != -1:
		path.append(k); k = bfs_par[k]
	var pts := _smooth_path(path, dest)
	path_cache[key] = [pts, elapsed]
	if path_cache.size() > 400: path_cache.clear()
	_spawn_boat(a, pts, dest, troops)
	return true

func _spawn_boat(a: int, pts: PackedVector2Array, dest: int, troops: float) -> void:
	var cum := PackedFloat32Array([0.0])
	for m in range(1, pts.size()):
		cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
	nations[a].troops -= troops
	boat_uid += 1
	boats.append({"a": a, "troops": troops, "pts": pts, "cum": cum, "d": 0.0, "dest": dest, "sid": rng.randi() % 10, "uid": boat_uid})
	if a == PLAYER: sfx("transport")
	if a != PLAYER and dest >= 0 and owner_map[dest] == PLAYER: notify("A transport from %s is heading to your coast" % _nname(a), "bad")

func _water_los(p0: Vector2, p1: Vector2) -> bool:
	var n := int(p0.distance_to(p1) * 2.0) + 1
	for s2 in n + 1:
		var p := p0.lerp(p1, float(s2) / n)
		var x := int(p.x); var y := int(p.y)
		if x < 0 or y < 0 or x >= W or y >= H or owner_map[y * W + x] != WATER: return false
	return true

func _smooth_path(path: Array, dest: int) -> PackedVector2Array:
	var raw := PackedVector2Array()
	for t in path: raw.append(Vector2(t % W + 0.5, t / W + 0.5))
	# string pulling over water
	var pulled := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var lo := i + 1
		var hi := mini(raw.size() - 1, i + 32)
		var best_j := lo
		while lo <= hi:
			var mid_j := (lo + hi) / 2
			if _water_los(raw[i], raw[mid_j]):
				best_j = mid_j; lo = mid_j + 1
			else:
				hi = mid_j - 1
		pulled.append(raw[best_j]); i = best_j
	pulled.append(Vector2(dest % W + 0.5, dest / W + 0.5))
	# Chaikin smoothing -> curved route
	var pts := pulled
	for it in 3:
		if pts.size() < 3: break
		var np := PackedVector2Array([pts[0]])
		for m in pts.size() - 1:
			np.append(pts[m].lerp(pts[m + 1], 0.25)); np.append(pts[m].lerp(pts[m + 1], 0.75))
		np.append(pts[pts.size() - 1])
		pts = np
	for m in pts.size(): pts[m] *= TS
	return pts

func _boat_pos(bt) -> Array:
	var cum: PackedFloat32Array = bt.cum
	var pts: PackedVector2Array = bt.pts
	var d: float = bt.d
	var m := 1
	while m < cum.size() - 1 and cum[m] < d: m += 1
	var seg := maxf(0.001, cum[m] - cum[m - 1])
	var p := pts[m - 1].lerp(pts[m], clampf((d - cum[m - 1]) / seg, 0, 1))
	return [p, (pts[m] - pts[m - 1]).normalized(), m]

func _tick_boats(dt: float) -> void:
	for bt in boats.duplicate():
		var a0: int = bt.a
		var dest0: int = bt.dest
		if not nations[a0].alive:
			boats.erase(bt); continue
		var o0 := owner_map[dest0]
		bt.d += dt * sim_rules.ship_tiles_per_s() * boat_speed * TS
		var cum: PackedFloat32Array = bt.cum
		if bt.d >= cum[cum.size() - 1]:
			boats.erase(bt)
			var dest: int = bt.dest
			var o := owner_map[dest]
			var a: int = bt.a
			if not nations[a].alive: continue
			if o == a:
				nations[a].troops += floor(bt.troops * SimRules.RETREAT_KEEP)  # lands home: -25 %
				if a == PLAYER: notify("Your transport returned its troops home", "info")
				continue
			if not sim_naval.landable(a, dest):
				var alt := sim_naval.alt_landing(a, dest, sim_naval.coast_body(dest))
				if alt < 0:
					nations[a].troops += floor(bt.troops * 0.5)
					if a == PLAYER: notify("Your transport could not land", "bad")
					continue
				dest = alt; o = owner_map[dest]
			# RoWorld: the transport takes its landing tile, then attacks from that beachhead
			if allied(a, o):
				nations[a].troops += bt.troops; continue
			if shielded(o):
				# Sim._landing_allowed: no transport lands on a person under their spawn shield
				nations[a].troops += floor(bt.troops * SimRules.RETREAT_KEEP)
				if a == PLAYER: notify(shield_text(o), "info")
				continue
			_set_owner(dest, a)
			if a == PLAYER: notify("Your transport landed on %s's coast" % _nname(o), "good")
			sim_atk.start(a, o, bt.troops, dest)

func retreat(at) -> void:
	sim_atk.retreat(at)

# ---------- supply drops (custom) ----------
const SUPPLY_FIRST_TICKS := 900    # 90 s into the match
const SUPPLY_GAP_TICKS := 1200     # then one every 2 min at 1x
const SUPPLY_LIFE_TICKS := 3000    # unclaimed after 5 min: gone
const SUPPLY_MAX := 3

func _supply_pick_tile() -> int:
	for _i in 4000:
		var t := _supply_rng.randi() % (W * H)
		if owner_map[t] == NEUTRAL and fallout[t] != 1:
			return t
	return -1

func _supply_tick() -> void:
	var tick := sim_atk.tick
	if tick < SUPPLY_FIRST_TICKS:
		return
	if _supply_next == 0:
		_supply_next = tick
	if tick >= _supply_next and drops.size() < SUPPLY_MAX:
		var t := _supply_pick_tile()
		# (no free land found: try again in 5 s rather than skipping the whole 2-minute gap; neutral land runs out as tribes and nations grow)
		_supply_next = tick + (SUPPLY_GAP_TICKS if t >= 0 else 50)
		if t >= 0:
			drops.append({"tile": t, "t0": tick})
			notify("Supply drop landed: take the land to claim it", "info")
			sfx("spawn")
	for d in drops.duplicate():
		var o: int = owner_map[d.tile]
		if o > 0 and nations[o].alive:
			drops.erase(d)
			_supply_claim(o, d)
		elif tick - int(d.t0) > SUPPLY_LIFE_TICKS:
			drops.erase(d)

# A claimed drop: gold, troops, or (the player only) a free cosmetic crate.
func _supply_claim(o: int, d: Dictionary) -> void:
	var n = nations[o]
	var r := _supply_rng.randf()
	var msg := ""
	if o == PLAYER and r < 0.18 and client != null and client.ctx.session != null:
		var co: Dictionary = save.cosmetics
		var id := CosmeticsRules.roll(co.owned, _supply_rng.randf(), _supply_rng.randf())
		if id != "":
			co.owned[id] = true
			co.last = id
			write_save()
			msg = "Supply drop: a free crate item, %s" % CosmeticsRules.item(id).name
	if msg == "":
		if r < 0.6:
			var gold := clampf(float(n.gold) * 0.15, 250000.0, 20000000.0)
			n.gold += gold
			msg = "Supply drop: +%s gold" % _fmt(gold)
		else:
			var add := minf(troop_cap(o) * 0.12, maxf(0.0, troop_cap(o) - float(n.troops)))
			n.troops += add
			msg = "Supply drop: +%s troops" % _fmt(add)
	if o == PLAYER:
		notify(msg, "good")
		sfx("spawn")
	elif allied(PLAYER, o):
		notify("%s claimed a supply drop" % _nname(o), "info")

# Bulk nuke launches: the 2nd, 3rd... bomb leave NUKE_GAP_TICKS (0.2 s) after the one before (owner request 2026-11-25).
const NUKE_GAP_TICKS := 2

func queue_nuke(k: int, tile: int, o: int, due: int) -> void:
	nuke_queue.append([due, k, tile, o])

func _nuke_queue_tick() -> void:
	var t: int = sim_atk.tick
	var i := 0
	while i < nuke_queue.size():
		var q: Array = nuke_queue[i]
		if int(q[0]) <= t:
			nuke_queue.remove_at(i)
			try_build(int(q[1]), int(q[2]), int(q[3]))
		else:
			i += 1

func _economy(dt: float) -> void:
	if not nuke_queue.is_empty(): _nuke_queue_tick()
	if supply_on: _supply_tick()
	fallout_count = fallout_list.size()
	var city_lv := {}
	for st in structs:
		if st.k == 0: city_lv[st.o] = city_lv.get(st.o, 0) + mini(int(st.get("level", 1)), 1000)
	# FALLBACK (docs/LUAU_PORT.md Step 6): when this returns no Luau, this module's GDScript code runs (no extension, NO_LUAU_SIM).
	var lu_on := not net_remote and luau_link != null and luau_link.on and not OS.has_environment("NO_LUAU_SIM")
	var lu_rows := PackedFloat64Array()
	var payouts: Array = []  # [victim, killer, gold]: Sim._eliminate's _conquest_gold, paid after the growth (below)
	for id in range(1, nations.size()):
		var n = nations[id]
		if not n.alive:
			continue
		if is_nan(n.troops) or is_inf(n.troops): n.troops = 0.0  # (a console value that overflowed)
		if is_nan(n.gold) or is_inf(n.gold): n.gold = 0.0
		if n.land <= 0 and (id != PLAYER or state == "play"):
			n.alive = false
			# upstream Sim._eliminate: the owner that took the last tile (o_killer = last_by here; capitulation and
			# nukes set it too) takes conquer_gold of what is left (all of a nation's or tribe's, half of a human's).
			# After an annex this is only the gold earned since (annex zeroed it); owner request 2026-11-28
			# "Match upstream". Queued so the Luau growth, which writes gold back whole, can't drop it.
			var kb: int = int(n.get("last_by", 0))
			if kb > 0 and kb < nations.size():
				payouts.append([id, kb, sim_rules.conquer_gold(kind_of(id), n.gold)])
				n.gold = 0.0
			if id != PLAYER and n.get("last_by", 0) == PLAYER:
				stats.elims += 1; sfx("eliminate")  # upstream UIAdvisor.on_owner_eliminated: the kill sound, not the old 3 s conquer sting
				if kind_of(id) != SimRules.KIND_TRIBE: stats["conq"] = int(stats.get("conq", 0)) + 1  # Stars: tribes don't count
			if id != PLAYER and (is_prot(id) or rng.randf() < 0.15): notify("%s has been eliminated" % n.name, "info")
			continue
		# floats run to 1e308: keep a runaway number finite (NaN reads 0, infinity stops at the largest value)
		if is_nan(n.troops) or is_inf(n.troops): n.troops = 0.0 if is_nan(n.troops) else 1.0e300
		if is_nan(n.gold) or is_inf(n.gold): n.gold = 0.0 if is_nan(n.gold) else 1.0e300
		var kd := kind_of(id)
		# novice bot players: Easy nation numbers (troop_kind / troop_diff, looked up once)
		var nov := is_novice_bot(id)
		var tk := SimRules.KIND_NATION if nov else kd
		var tdf := NOVICE_SKILL if nov else diff_i
		if lu_on:
			# Step 5e: the growth runs in luau/sim/Core/SimEconomy.luau after this loop
			lu_rows.append(id); lu_rows.append(n.troops); lu_rows.append(n.gold); lu_rows.append(n.land)
			lu_rows.append(n.get("pop", 0.0)); lu_rows.append(city_lv.get(id, 0)); lu_rows.append(tk)
			lu_rows.append(tdf); lu_rows.append(kd); lu_rows.append(n.reinf_cd)
			continue
		var cap := sim_rules.max_troops(tk, n.land, city_lv.get(id, 0), tdf) if tile_pop.is_empty() \
			else sim_rules.max_troops_pop(tk, n.land, n.get("pop", 0.0), tile_pop_avg, city_lv.get(id, 0), tdf)
		n.regen = sim_rules.troop_growth(tk, n.troops, cap, tdf) * 10.0
		n.troops += sim_rules.troop_growth_applied(tk, n.troops, cap, tdf)
		n.gold += sim_rules.gold_per_tick(kd)
		n.reinf_cd = maxf(0.0, n.reinf_cd - dt)
		if id == PLAYER: _econ_console(n, cap)
	if lu_on and not lu_rows.is_empty(): _economy_luau(lu_rows, dt, city_lv)
	for p in payouts:
		var vic: int = p[0]; var kb: int = p[1]; var gold: float = p[2]
		nations[kb].gold += gold
		# Ev.CONQUEST once per victim (the conqueror's "+ gold" popup); a payout after an annex is silent
		if not nations[vic].get("conq_sent", false):
			nations[vic]["conq_sent"] = true
			_on_conquest(vic, kb, gold)

# CUSTOM: the console's god mode, infinite gold and no cooldown (Tab / owner console) on the player's numbers
func _econ_console(n: Dictionary, cap: float) -> void:
	if god_mode or inf_gold: n.gold = maxf(n.gold, 999e6)
	if god_mode: n.troops = maxf(n.troops, cap)
	if god_mode or no_cd: n.reinf_cd = 0.0; rail_cd = 0.0

var econ_luau_calls := 0  # tests

# The growth of the rows _economy collected, in Luau; written back in the same order and key order as the GDScript.
# A failed call turns the link off and the same rows grow here.
func _economy_luau(rows: PackedFloat64Array, dt: float, city_lv: Dictionary) -> void:
	var vm: LuauVM = luau_link.vm
	var out = null
	if vm.require_module("Core/SimEconomy"):
		var rf := PackedFloat64Array()
		for k in SimAttacks.RULE_FIELDS: rf.append(float(sim_rules.get(k)))
		var hdr := PackedFloat64Array([dt, 0.0 if tile_pop.is_empty() else 1.0, tile_pop_avg])
		out = vm.call_fn("Core/SimEconomy", "tick", [rf.to_byte_array(), hdr.to_byte_array(), rows.to_byte_array()])
	if out == null:
		luau_link._fail(self, vm.last_error)
		for j in range(0, rows.size(), 10):
			var id := int(rows[j])
			var n = nations[id]
			var tk := int(rows[j + 6]); var tdf := int(rows[j + 7])
			var cap := sim_rules.max_troops(tk, n.land, city_lv.get(id, 0), tdf) if tile_pop.is_empty() \
				else sim_rules.max_troops_pop(tk, n.land, n.get("pop", 0.0), tile_pop_avg, city_lv.get(id, 0), tdf)
			n.regen = sim_rules.troop_growth(tk, n.troops, cap, tdf) * 10.0
			n.troops += sim_rules.troop_growth_applied(tk, n.troops, cap, tdf)
			n.gold += sim_rules.gold_per_tick(int(rows[j + 8]))
			n.reinf_cd = maxf(0.0, n.reinf_cd - dt)
			if id == PLAYER: _econ_console(n, cap)
		return
	econ_luau_calls += 1
	var res: PackedFloat64Array = (out.rows as PackedByteArray).to_float64_array()
	var o := 0
	for j in range(0, rows.size(), 10):
		var id := int(rows[j])
		var n = nations[id]
		n.regen = res[o + 2]; n.troops = res[o]; n.gold = res[o + 1]; n.reinf_cd = res[o + 3]
		if id == PLAYER: _econ_console(n, res[o + 4])
		o += 5

func _ai(_dt: float) -> void:
	_ai_place_budget = 24
	sim_ai.tick()


func is_prot(id: int) -> bool:
	# protagonist: an AI nation or a bot player (anything that builds, unlike a tribe)
	return id > 0 and id < nations.size() and (nations[id].get("prot", false) or nations[id].get("bot", false))

func can_build(id: int) -> bool:
	return id == PLAYER or is_prot(id)

func sam_range(lvl: int) -> float:
	return 150.0 - 480.0 / float(lvl + 5)  # OpenFront formula: Lv1=70, Lv2=81.4, Lv3=90, cap 150

func _ready_slots(st) -> int:
	return sim_ars.ready_missiles(st)

# a launch spends one loaded missile (reloads Rules.RELOAD_TICKS); cd_sec 0 = free (god mode / no_cd)
func _use_slot(st, cd_sec: float) -> bool:
	if cd_sec <= 0.0: return true
	if sim_ars.ready_missiles(st) <= 0: return false
	sim_ars.fire_shot(st)
	return true

func _struct_add(k: int, tile: int, o: int) -> void:
	var dur: float = BUILD_DUR.get(k, 2.0) * (0.05 if (autoshot or bench) else 1.0)
	var init_cd := 0.0
	var st := {"k": k, "tile": tile, "o": o, "level": 1, "hits": 0, "cd": init_cd, "cmax": maxf(1.0, init_cd), "shots": [], "bt": dur, "bmax": maxf(0.1, dur), "trucks": 0, "last_spawn": -1000}
	st["hp"] = sim_ars.struct_hp_full(st) if sim_ars else 1000
	structs.append(st); struct_at[tile] = st; _sv += 1; _own_sv[o] = _own_sv.get(o, 0) + 1

func _upgrade_struct(st) -> void:
	st.level = mini(int(st.get("level", 1)) + 1, 1000); _sv += 1
	if st.k == 4: st["up_tick"] = sim_atk.tick
	if st.k in [4, 5]:
		var shots: Array = st.get("shots", [])
		shots.append(sim_atk.tick); st["shots"] = shots
	if st.o == PLAYER:
		notify("%s upgraded to Lv%d" % [build_data[st.k][1], st.level], "good")
		add_float(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS, "Lv%d!" % st.level, GOLD_C)

# The local player conquered `victim` outright and took `gold`: a victory flag where its name was.
func _on_conquest(victim: int, by: int, gold: float) -> void:
	if by != PLAYER or fx_layer == null: return
	var loc = names.name_location(victim) if names != null else null
	var n = nations[victim]
	var land := maxf(1.0, float(n.land))
	var u: float = loc[0] if loc != null else float(n.sx) / land
	var v: float = loc[1] if loc != null else float(n.sy) / land
	fx_layer.conquest(u, v, gold)

func _struct_remove(st) -> void:
	if fx_layer != null: fx_layer.on_structure_removed(RWGameState.S_OF.get(int(st.k), -1), int(st.tile))
	structs.erase(st); struct_at.erase(st.tile); _sv += 1; _own_sv[st.o] = _own_sv.get(st.o, 0) + 1

func add_float(world_pos: Vector2, text: String, col: Color = GOLD_C) -> void:
	floats.append({"pos": world_pos, "text": text, "col": col, "t": 0.0})
	if floats.size() > 24: floats.pop_front()

func notify(text: String, kind := "info") -> void:
	if attract_on and state == "menu": return  # the title's demo world is silent
	var col := {"good": GREEN, "bad": RED, "info": CYAN}[kind] as Color
	notes.push_front({"text": text, "col": col, "kind": kind, "t": 0.0})
	if notes.size() > 5: notes.resize(5)
	if note_box: note_box.queue_redraw()
	if client: client.toast(text, kind)
	elif hud: hud.toast(text, kind)

func _nname(id: int) -> String:
	if id == PLAYER: return "You"
	if id <= 0: return "the wilds"
	return nations[id].name
