extends "res://game/rails.gd"
# Protagonist AI hooks

# SimAIEconomy._sea_tile_near: a random water tile within r tiles (box) of t, or -1
func _ai_sea_tile_near(t: int, r: float) -> int:
	var ri := int(r)
	for _i in 50:
		var x := t % W + rng.randi_range(-ri, ri)
		var y := t / W + rng.randi_range(-ri, ri)
		if y < 1 or y >= H - 1 or x < 0 or x >= W: continue
		var c := y * W + x
		if owner_map[c] == WATER and sim_naval.body[c] > 0: return c
	return -1

# SimAIEconomy.on_transport_sunk / on_trade_captured -> _retaliate (630-697)
func ai_ship_loss(victim: int, tile: int, enemy: int) -> void:
	if victim <= 0 or victim == PLAYER or victim >= nations.size() or enemy == victim or tile < 0: return
	if kind_of(victim) != SimRules.KIND_NATION or not nations[victim].alive or diff_i <= 0 or owned_count(victim, 1) == 0: return
	if _count_ws(victim) >= WARSHIP_FLEET_CAP:
		_ai_move_nearest_warship(victim, tile); return
	if rng.randf() < WARSHIP_RETALIATE_P[clampi(diff_i, 0, 2)]:
		var c6 := build_cost(victim, 6)
		if owner_map[tile] != WATER or nations[victim].gold < c6 or not spawn_warship(victim, tile):
			_ai_move_nearest_warship(victim, tile)
		else:
			nations[victim].gold -= c6

# SimAIEconomy._move_nearest_warship: the nearest ship still near its patrol area takes `t` as its patrol tile
func _ai_move_nearest_warship(id: int, t: int) -> void:
	if owner_map[t] != WATER: return
	var near := SimRules.WARSHIP_RANGE_FULL / sim_rules.k_lin
	var tp := Vector2(t % W + 0.5, t / W + 0.5)
	var best = null
	var bd := 0.0
	for ws in warships:
		if ws.o != id or not ws.has("patrol"): continue
		var pos: Vector2 = ws.pos
		var pp: Vector2 = ws.patrol
		if absf(pos.x - pp.x) + absf(pos.y - pp.y) >= near: continue
		var d := absf(pos.x - tp.x) + absf(pos.y - tp.y)
		if best == null or d < bd: best = ws; bd = d
	if best != null:
		best.patrol = tp; best.tgt = tp

func _count_ws(o: int) -> int:
	var c := 0
	for ws in warships: if ws.o == o: c += 1
	return c

func _neighbour_count(tile: int) -> int:
	if neigh_cache[0] == tile: return neigh_cache[1]
	var seen := {}
	var cx := tile % W; var cy := tile / W
	for k in 300:
		var p := Vector2(cx, cy) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2, 30)
		var x := int(p.x); var y := int(p.y)
		if x < 0 or y < 0 or x >= W or y >= H: continue
		var o: int = owner_map[y * W + x]
		if o > 1: seen[o] = true
	neigh_cache = [tile, seen.size()]
	return seen.size()
