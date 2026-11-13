extends "res://game/nukes.gd"
# Warships, boats and trade ships

# ---------- warships ----------
func _find_water_near(tile: int, max_r := 12) -> int:
	if tile < 0 or tile >= W * H: return -1
	if owner_map[tile] == WATER: return tile
	var cx := tile % W; var cy := tile / W
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r: continue
				var x := cx + dx; var y := cy + dy
				if x >= 0 and y >= 0 and x < W and y < H and owner_map[y * W + x] == WATER:
					return y * W + x
	return -1

func spawn_warship(o: int, target_tile: int = -1) -> bool:
	var ports := []
	for st in structs:
		if st.o == o and st.k == 1: ports.append(st)
	if ports.is_empty() and not (o == PLAYER and god_mode): return false
	var home_tile := -1
	var w_tile := -1
	var tgt_pos := Vector2(-1, -1)
	if target_tile >= 0 and target_tile < W * H:
		var t_pos := Vector2(target_tile % W + 0.5, target_tile / W + 0.5)
		# Pick the owned Port closest to the clicked tile
		var best_d := 1e18
		for pt in ports:
			var d := Vector2(pt.tile % W + 0.5, pt.tile / W + 0.5).distance_to(t_pos)
			if d < best_d: best_d = d; home_tile = pt.tile
		if owner_map[target_tile] == WATER:
			tgt_pos = t_pos
			# If clicked water is reasonably close to player's port/coast, spawn directly at clicked water tile!
			if best_d <= 65.0 or _find_water_near(target_tile, 0) >= 0:
				w_tile = target_tile
				if home_tile < 0: home_tile = target_tile
	if w_tile < 0 and not ports.is_empty():
		var pt = ports[rng.randi() % ports.size()]
		if home_tile < 0: home_tile = pt.tile
		w_tile = _find_water_near(home_tile, 12)
	if w_tile < 0 and o > 0 and o < nations.size() and nations[o].land > 0:
		var bb: Rect2i = nations[o].bb
		for _t in 80:
			var ti := (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
			if owner_map[ti] == o:
				var wn := _find_water_near(ti, 4)
				if wn >= 0:
					w_tile = wn
					if home_tile < 0: home_tile = ti
					break
	if w_tile < 0: return false
	var spawn_pos := Vector2(w_tile % W + 0.5, w_tile / W + 0.5)
	if tgt_pos.x < 0: tgt_pos = spawn_pos
	var ws := {"o": o, "pos": spawn_pos, "home": w_tile if home_tile < 0 else home_tile, "hp": 1000.0, "vet": 0, "kills": 0, "tgt": tgt_pos, "cd": 0.0}
	sim_ws.init_ship(ws)
	if o == PLAYER: ws["manual"] = sim_atk.tick
	warships.append(ws)
	return true

func _is_water(p: Vector2) -> bool:
	var x := int(p.x); var y := int(p.y)
	return x >= 0 and y >= 0 and x < W and y < H and owner_map[y * W + x] == WATER

func _tick_warships_legacy(dt: float) -> void:
	for ws in warships.duplicate():
		if not nations[ws.o].alive: warships.erase(ws); continue
		ws.cd -= dt
		# chase nearby prey or patrol
		var prey = null
		var pd: float = 14.0 + ws.vet * 2.0
		for bt in boats:
			if bt.a == ws.o or bt.get("air", false): continue
			var bp: Vector2 = _boat_pos(bt)[0] / TS
			if bp.distance_to(ws.pos) < pd: prey = bt; pd = bp.distance_to(ws.pos)
		var trade = null
		for tr in traders:
			if tr.o == ws.o or tr.get("air", false): continue
			var tp: Vector2 = _path_pos(tr)[0] / TS
			if tp.distance_to(ws.pos) < 12.0: trade = tr; break
		if prey != null and ws.cd <= 0:
			boats.erase(prey); ws.cd = 2.0; _ws_kill(ws)
			if ws.o == PLAYER or prey.a == PLAYER: sfx("warship_shot")
			if ws.o == PLAYER: notify("Your warship sank a transport from %s" % _nname(prey.a), "good")
			elif prey.a == PLAYER: notify("A warship from %s sank your transport" % _nname(ws.o), "bad")
		elif trade != null and ws.cd <= 0:
			var from_o: int = trade.o
			trade.o = ws.o; ws.cd = 2.0; _ws_kill(ws)
			if ws.o == PLAYER: sfx("ka_ching")
			elif from_o == PLAYER: sfx("warship_shot")
			if ws.o == PLAYER: notify("Your warship captured a trade ship from %s" % _nname(from_o), "good")
			elif from_o == PLAYER: notify("%s captured your trade ship" % _nname(ws.o), "bad")
		# enemy warships duel (1,000 HP, 250 dmg/shell + veterancy boost)
		for ow in warships:
			if ow.o != ws.o and not allied(ws.o, ow.o) and ow.pos.distance_to(ws.pos) < 10.0 and ws.cd <= 0.0:
				ow.hp -= 250.0 * (1.0 + ws.vet * 0.2)
				ws.cd = 1.2
				shells.append({"pos": ow.pos * TS, "t": 0.0})
				if ws.o == PLAYER or ow.o == PLAYER: sfx("warship_shot")
				if ow.hp <= 0.0: _ws_kill(ws)
				break
		if ws.hp <= 0:
			warships.erase(ws)
			if ws.o == PLAYER: notify("Your warship was sunk", "bad"); sfx("warship_lost")
			continue
		# movement
		if ws.pos.distance_to(ws.tgt) < 1.5 or not _is_water(ws.tgt):
			var home := Vector2(ws.home % W, ws.home / W)
			for k in 20:
				var c := home + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
				if _is_water(c): ws.tgt = c; break
		var dir: Vector2 = (ws.tgt - ws.pos).normalized()
		var np: Vector2 = ws.pos + dir * 9.0 * dt
		if _is_water(np): ws.pos = np
		else:
			ws.tgt = ws.pos

func _ws_kill(ws) -> void:
	ws.kills += 1
	if ws.kills % 2 == 0 and ws.vet < 5:
		ws.vet += 1; ws.hp = 1000.0
		if ws.o == PLAYER: notify("Your warship reached veterancy %d" % ws.vet, "good")

# ---------- trade ----------
func _water_path(from_tile: int, to_tile: int, max_nodes := 14000) -> PackedVector2Array:
	if sim_nav != null and sim_nav.ready: return sim_nav.water_path_px(from_tile, to_tile, TS)
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array()
	for d in [1, -1, W, -W]:
		if (d == 1 and to_tile % W == W - 1) or (d == -1 and to_tile % W == 0): continue
		var j: int = to_tile + d
		if j >= 0 and j < W * H and owner_map[j] == WATER:
			bfs_par[j] = -1; bfs_stamp[j] = gen; q.append(j)
	var qi := 0
	var found := -1
	var fx := from_tile % W; var fy := from_tile / W
	while qi < q.size() and qi < max_nodes:
		var i: int = q[qi]; qi += 1
		if absi(i % W - fx) <= 1 and absi(i / W - fy) <= 1: found = i; break
		for d in [1, -1, W, -W]:
			if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
			var j: int = i + d
			if j >= 0 and j < W * H and owner_map[j] == WATER and bfs_stamp[j] != gen:
				bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	if found < 0: return PackedVector2Array()
	var path := []
	var k := found
	while k != -1:
		path.append(k); k = bfs_par[k]
	return _smooth_path(path, to_tile)

func _path_pos(tr) -> Array:
	return _boat_pos(tr)

func trade_ship_gold(dist_tiles: float, lvl_mult := 1.0) -> float:
	# OpenFront nonlinear distance formula scaled for 640x352 map (dist_equiv = dist_tiles * 2.0)
	return floor(sim_rules.trade_gold(dist_tiles) * lvl_mult)

func _pick_trade_endpoint(o: int) -> Dictionary:
	# If nation 'o' has at least one completed Port, trade ships ONLY spawn from / dock at its Port(s)!
	var my_ports := []
	for st in structs:
		if st.o == o and st.k == 1 and st.get("bt", 0.0) <= 0.0:
			my_ports.append(st)
	if not my_ports.is_empty():
		return my_ports[rng.randi() % my_ports.size()]
	# Otherwise (0 Ports owned by 'o'), trade ships can spawn from any coastal tile owned by 'o'
	if o <= 0 or o >= nations.size() or not nations[o].alive or nations[o].land <= 0:
		return {}
	var bb: Rect2i = nations[o].bb
	for _t in 28:
		var ti := (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
		if ti >= 0 and ti < W * H and owner_map[ti] == o and _coastal(ti):
			return {"o": o, "tile": ti, "level": 0, "k": -1}
	return {}

func _spawn_trade_ship_pair(a: Dictionary, b: Dictionary, allow_bfs: bool) -> bool:
	if a.is_empty() or b.is_empty() or a.tile == b.tile or is_embargoed(a.o, b.o): return false
	var key := "t%d:%d" % [a.tile, b.tile]
	var pts: PackedVector2Array
	var cum: PackedFloat32Array
	if path_cache.has(key):
		var entry: Array = path_cache[key]
		pts = entry[0]
		if entry.size() >= 3:
			cum = entry[2]
		else:
			cum = PackedFloat32Array([0.0])
			for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
			entry.append(cum)
	elif allow_bfs:
		pts = _water_path(a.tile, b.tile)
		cum = PackedFloat32Array([0.0])
		for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
		path_cache[key] = [pts, elapsed, cum]
	else:
		return false
	if pts.size() < 2: return false
	var dist_tiles: float = cum[cum.size() - 1] / TS
	var lmult: float = 0.7 + 0.25 * float(int(a.get("level", 0)) + int(b.get("level", 0)))
	traders.append({"o": a.o, "pts": pts, "cum": cum, "d": 0.0, "dst": b, "gold": trade_ship_gold(dist_tiles, lmult)})
	return true

func _tick_trade(dt: float) -> void:
	# spawning happens per tick in sim_naval.tick() (RoWorld ports_tick)
	_tick_air_cargo(dt)
	for tr in traders.duplicate():
		tr.d += dt * sim_rules.ship_tiles_per_s() * boat_speed * TS * (AIR_SPEED if tr.get("air", false) else 1.0)
		var cum: PackedFloat32Array = tr.cum
		if tr.d >= cum[cum.size() - 1]:
			SimWarships.erase_ref(traders, tr)
			var dst: Dictionary = tr.dst
			if tr.has("orig"):
				# a captured ship pays its captor alone, if it still holds the port it reached (SimNaval._trade_arrive)
				if nations[tr.o].alive and is_same(struct_at.get(int(dst.tile)), dst) and int(dst.o) == int(tr.o):
					nations[tr.o].gold += tr.gold
					if tr.o == PLAYER: add_float(Vector2(int(dst.tile) % W + 0.5, int(dst.tile) / W + 0.5) * TS, "+%s" % _fmt(tr.gold), GOLD_C)
				continue
			if nations[tr.o].alive:
				nations[tr.o].gold += tr.gold
			var dst_o: int = int(dst.get("o", 0))
			if dst_o > 0 and dst_o != tr.o and dst_o < nations.size() and nations[dst_o].alive and not sim_naval.hostile(tr.o, dst_o):
				nations[dst_o].gold += tr.gold
				if tr.o == PLAYER or dst_o == PLAYER:
					var ppos := Vector2(int(dst.tile) % W + 0.5, int(dst.tile) / W + 0.5) * TS
					add_float(ppos, "+%s" % _fmt(tr.gold), GOLD_C)
