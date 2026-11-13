extends "res://game/economy.gd"
# Nukes, MIRVs, fallout and SAM interception

func land_width() -> float:
	if _land_w < 0.0:
		var x0 := W; var x1 := -1
		for x in range(0, W, 2):
			for y in range(0, H, 4):
				if owner_map[y * W + x] != WATER:
					x0 = mini(x0, x); x1 = maxi(x1, x); break
		_land_w = float(maxi(x1 - x0 + 2, 64)) if x1 >= 0 else float(W)
	return _land_w
func nuke_range(k: int) -> float:
	return float(NUKE_RANGE_FRAC.get(k, 0.1)) * NUKE_RANGE_SCALE * land_width()
func nuke_range_label(k: int) -> String:
	return "%s km (%d%% of map)" % [_fmt_int(int(NUKE_RANGE_FRAC.get(k, 0.1) * NUKE_RANGE_SCALE * 40000.0)), int(round(NUKE_RANGE_FRAC.get(k, 0.1) * NUKE_RANGE_SCALE * 100.0))]

func nuke_speed_mult(_dist: float) -> float:
	return NUKE_SPEED_MULT

func nuke_cost(k: int) -> float:
	var base := float(build_data[k][2]) + (SimRules.MIRV_COST_STEP * mirvs_launched if k == 9 else 0.0)
	return base * ((1.0 + ICBM_FEE_PCT) if icbm_mode else 1.0)

# nearest ready silo that can reach tp with weapon k (any silo when ICBM mode is on)
func silo_for(o: int, k: int, tp: Vector2) -> Dictionary:
	var st := nearest_silo(o, tp)
	if st.is_empty() or icbm_mode: return st
	if Vector2(st.tile % W + 0.5, st.tile / W + 0.5).distance_to(tp) > nuke_range(k): return {}
	return st

func _any_silo_dist(o: int, tp: Vector2) -> float:
	var bd := INF
	for st in structs:
		if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0:
			bd = minf(bd, Vector2(st.tile % W + 0.5, st.tile / W + 0.5).distance_to(tp))
	return bd

func set_icbm(on: bool) -> void:
	icbm_mode = on
	if not save.has("settings"): save["settings"] = {}
	save.settings["icbm"] = on
	if build_btns.size() > 16: build_btns[16].queue_redraw()
	_update_hud()

func nearest_silo(o: int, target: Vector2) -> Dictionary:
	var best := {}
	var bd := 1e18
	for st in structs:
		if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0 and _ready_slots(st) > 0:
			var p := Vector2(st.tile % W, st.tile / W)
			var d := p.distance_squared_to(target)
			if d < bd: bd = d; best = st
	return best

func _missile_world_pos(ms, s: float) -> Vector2:
	# Clean, realistic low-profile ICBM altitude arc (pure -Y altitude above ground track, no S-curve or sideways bend)
	var sc := clampf(s, 0.0, 1.0)
	var p0: Vector2 = ms.from * TS
	var p1: Vector2 = ms.to * TS
	var dist_px: float = p0.distance_to(p1)
	var is_br: bool = ms.get("branched", false)
	var ground_pos: Vector2 = p0.lerp(p1, sc)
	var alt_profile: float = pow(sc, 0.72) * pow(1.0 - sc, 0.92) * 3.12
	var apex_h: float = clampf(dist_px * (0.11 if is_br else 0.16), 8.0 if is_br else 16.0, 28.0 if is_br else 64.0)
	return ground_pos + Vector2(0.0, -alt_profile * apex_h)

func _missile_screen_pos(ms, s: float, _z: float) -> Vector2:
	return _screen_of(_missile_world_pos(ms, s))

func launch_nuke(o: int, k: int, tile: int) -> bool:
	if not NUKE_R.has(k): return false  # only bomb kinds launch (warheads / other ids never do)
	if k == 9 and not mirv_enabled: return false
	var tp := Vector2(tile % W + 0.5, tile / W + 0.5)
	var victim: int = owner_map[tile]
	# SimNukes.launch_nuke: never your own land, never an ally
	if victim == o:
		if o == PLAYER: notify("You can't nuke your own land", "info")
		return false
	if victim > 0 and allied(o, victim):
		if o == PLAYER: notify("You can't nuke an ally", "info")
		return false
	var silo := silo_for(o, k, tp)
	if silo.is_empty():
		if o == PLAYER and not nearest_silo(o, tp).is_empty():
			notify("Target out of range (%s: %s). Build a closer silo or enable ICBM." % [build_data[k][1], nuke_range_label(k)], "bad")
		return false
	var cost: float = nuke_cost(k)
	if nations[o].gold < cost: return false
	nations[o].gold -= cost
	if k == 9: mirvs_launched += 1
	_use_slot(silo, 0.0 if (o == PLAYER and (god_mode or no_cd)) else 1.0)
	var from := Vector2(silo.tile % W + 0.5, silo.tile / W + 0.5)
	var nk: int = SimRules.NUKE_KIND_OF.get(k, SimRules.N_ATOM)
	var first := missiles.size()
	if k == 9:
		var tgt_o: int = victim if victim > 0 else -1
		var cov_pct: float = rng.randf_range(0.65, 0.85)  # MIRV covers 65-85% of target country in fallout
		var hits := []
		for _n in 400:
			if hits.size() >= 28: break
			var cand: int
			if tgt_o > 0:
				var bb: Rect2i = nations[tgt_o].bb
				cand = (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
				if owner_map[cand] != tgt_o: continue
			else:
				cand = clampi(tile + rng.randi_range(-int(30 * BLAST_S), int(30 * BLAST_S)) + rng.randi_range(-int(30 * BLAST_S), int(30 * BLAST_S)) * W, 0, W * H - 1)
			hits.append(cand)
		# 1.2x faster MIRV carrier bus (34 * 1.2 = 40.8 tiles/s)
		var bus_dur := maxf(2.0, from.distance_to(tp) / (40.8 * nuke_speed_mult(from.distance_to(tp))))
		missiles.append({"o": o, "k": 9, "nk": SimRules.N_MIRV, "from": from, "to": tp, "t": 0.0, "dur": bus_dur, "r": float(NUKE_R[9]), "mirv": true, "mirv_bus": true, "branched": false, "hits": hits, "tgt_o": tgt_o, "mirv_cov": cov_pct, "split_done": false})
	elif k == 12:
		# SimArsenal scattershot: an atom bomb's crater at the aim + 4..6 warheads 28..46 full-size tiles out
		missiles.append({"o": o, "k": 12, "nk": SimRules.N_SCATTER, "from": from, "to": tp, "t": 0.0, "dur": 0.0, "r": float(NUKE_R[12]), "mirv": false, "branched": false})
		var core_dur := maxf(1.8, from.distance_to(tp) / (43.2 * nuke_speed_mult(from.distance_to(tp))))
		var fired := 0
		for wp in sim_ars.scatter_targets(o, tp):
			fired += 1
			var wd := maxf(core_dur, maxf(1.8, from.distance_to(wp) / (43.2 * nuke_speed_mult(from.distance_to(wp))))) + fired * 2 * SimArsenal.DT_TICK
			missiles.append({"o": o, "k": 12, "nk": SimRules.N_WARHEAD, "from": from, "to": wp, "t": 0.0, "dur": wd, "r": 3.0 * BLAST_S, "mirv": false, "branched": true})
	else:
		missiles.append({"o": o, "k": k, "nk": nk, "from": from, "to": tp, "t": 0.0, "dur": 0.0, "r": float(NUKE_R[k]), "mirv": false, "branched": false})
	# 1.2x faster bomb travel speed (36.0 * 1.2 = 43.2 tiles/s)
	for mi in range(first, missiles.size()):
		var ms = missiles[mi]
		if ms.dur == 0.0: ms.dur = maxf(1.8, ms.from.distance_to(ms.to) / (43.2 * nuke_speed_mult(ms.from.distance_to(ms.to))))
	# SimNukes: grudge + alliance break (not for the MIRV: its split ends an alliance with the target)
	if victim > 0:
		nations[victim]["grudge_" + str(o)] = sim_atk.tick + SimRules.NUKE_GRUDGE_TICKS
		nations[victim]["attacked_tick"] = sim_atk.tick
	if k != 9:
		for ow in sim_ars.break_nuked_alliances(o, tp, float(NUKE_R[k]), nk):
			if ow == PLAYER or o == PLAYER: notify("The %s launch ended the alliance between %s and %s" % [build_data[k][1], _nname(o), _nname(ow)], "bad")
	var nm: String = build_data[k][1]
	var lk := "mirv_launch" if k == 9 else ("hydrogen_launch" if k in [8, 11] else "atom_launch")
	sfx(lk, 0.0 if o == PLAYER else -8.0, 0.04, o)
	if victim == PLAYER and o != PLAYER: sfx("nuke_warning")
	if o == PLAYER: notify("%s launched at %s" % [nm, _nname(victim)], "info")
	elif victim == PLAYER: notify("%s launched a %s at you!" % [_nname(o), nm], "bad")
	elif is_prot(o): notify("%s launched %s at %s" % [_nname(o), nm, _nname(victim)], "info")
	return true

# SimNukes._detonate (inner disc + random half of the outer ring -> fallout, nukeDeathFactor troop loss,
# everything inside the outer radius destroyed). `r` stays the port's radius (NUKE_R, user x2.8 scale).
func detonate(o: int, c: Vector2, r: float, _eff_mult := 1.0, nk := SimRules.N_ATOM) -> void:
	var cx := int(c.x); var cy := int(c.y)
	sim_ars.nuke_blast(o, c, r, nk)
	var b_dur: float = 1.45 if r >= 6.0 * BLAST_S else 0.78
	if _qual() >= 2: b_dur = 6.0
	blasts.append({"pos": c * TS, "r": maxf(4.0, r) * TS, "t": 0.0, "dur": b_dur, "seed": cx * 73856093 ^ cy * 19349663, "kind": "nuke"})
	# Light, crisp screen shake scaled gently by blast radius (capped at 7.5 px)
	var sh_amt: float = clampf(1.8 + sqrt(maxf(1.0, r / BLAST_S)) * 0.95, 2.0, 6.5)
	_add_shake(sh_amt)

func _split_mirv_bus(ms) -> void:
	if ms.get("split_done", false): return
	ms["split_done"] = true
	var land_pt: Vector2 = ms.to
	var aim_tile := int(land_pt.y) * W + int(land_pt.x)
	var tgt_o: int = int(ms.get("tgt_o", -1))
	if aim_tile >= 0 and aim_tile < W * H and owner_map[aim_tile] > 0:
		tgt_o = owner_map[aim_tile]
	if tgt_o > 0 and allied(ms.o, tgt_o): break_alliance(ms.o, tgt_o)
	var cov: float = float(ms.get("mirv_cov", rng.randf_range(0.65, 0.85)))
	# 1. Collect target nation's tiles BEFORE the aimed impact so warheads branch across the country
	var country_tiles := []
	if tgt_o > 0 and tgt_o < nations.size() and nations[tgt_o].alive:
		var bb: Rect2i = nations[tgt_o].bb.intersection(Rect2i(0, 0, W, H))
		for y in range(bb.position.y, bb.end.y):
			for x in range(bb.position.x, bb.end.x):
				var ti := y * W + x
				if owner_map[ti] == tgt_o:
					country_tiles.append(ti)
	var hits: Array = []
	var wh_r: float = maxf(2.5 * BLAST_S, float(NUKE_R[9]))
	if not country_tiles.is_empty():
		country_tiles.shuffle()
		var desired_area: float = float(country_tiles.size()) * cov
		var single_area: float = PI * wh_r * wh_r * 0.72
		var n_wh := clampi(int(ceil(desired_area / maxf(1.0, single_area))), 8, 56)
		if float(n_wh) * single_area < desired_area:
			wh_r = clampf(sqrt(desired_area / (float(n_wh) * PI * 0.72)), wh_r, 12.0 * BLAST_S)
		var step := maxi(1, country_tiles.size() / n_wh)
		for m in n_wh:
			var cand_t: int = country_tiles[mini(country_tiles.size() - 1, m * step)]
			if cand_t != aim_tile:
				hits.append(cand_t)
	else:
		hits = ms.get("hits", [])
	# 2. First detonate right at the exact tile `ms.to` where the user aimed!
	detonate(ms.o, land_pt, maxf(wh_r, 4.0), 1.0, SimRules.N_WARHEAD)
	# 3. Then branch off the MIRV sub-warheads starting from the aimed landing point `land_pt` (`ms.to`)!
	for idx in hits.size():
		var h: int = hits[idx]
		var ht := Vector2(h % W + 0.5, h / W + 0.5)
		var d_vec := ht - land_pt
		if d_vec.length() < 5.5:
			var push_dir := d_vec.normalized() if d_vec.length() > 0.1 else Vector2.from_angle(float(idx) * TAU / maxf(1.0, float(hits.size())))
			ht = (land_pt + push_dir * 6.0).clamp(Vector2(2.5, 2.5), Vector2(W - 2.5, H - 2.5))
		missiles.append({
			"o": ms.o, "k": 9, "nk": SimRules.N_WARHEAD,
			"from": land_pt, "to": ht,
			"t": -0.02 * float(idx % 5),
			"dur": maxf(1.1, land_pt.distance_to(ht) / (36.0 * nuke_speed_mult(land_pt.distance_to(ht)))),
			"r": wh_r, "mirv": true, "branched": true,
			"tgt_o": tgt_o, "mirv_first": (idx == 0)
		})

func _tick_missiles(dt: float) -> void:
	for ms in missiles.duplicate():
		ms.t += dt
		if ms.t < ms.dur: continue
		missiles.erase(ms)
		if ms.get("mirv_bus", false):
			# MIRV carrier bus lands at the exact spot `ms.to` where the user aimed, then warheads branch off!
			_split_mirv_bus(ms)
			continue
		var tile := int(ms.to.y) * W + int(ms.to.x)
		if tile < 0 or tile >= W * H: continue
		# a SAM missile already on its way was planned to meet the bomb before impact
		if ms.get("sam_st") != null and sim_ars.sam_resolve(ms): continue
		var victim: int = owner_map[tile]
		# Every bomb (including MIRV branched warheads) ONLY creates fallout in the circular crater where it physically hits!
		detonate(ms.o, ms.to, ms.r, 1.0, int(ms.get("nk", SimRules.NUKE_KIND_OF.get(ms.k, 0))))
		var mine: bool = ms.o == PLAYER or victim == PLAYER
		sfx("hydrogen_hit" if ms.k in [8, 11] else "atom_hit", 0.0 if mine else -8.0, 0.04, PLAYER if mine else ms.o)
		if ms.get("mirv_first", false):
			var to_id: int = int(ms.get("tgt_o", -1))
			if to_id > 0 and to_id < nations.size():
				notify("MIRV warheads struck %s" % _nname(to_id), "info")
		if ms.k in [7, 8, 11] or (ms.k == 12 and not ms.get("branched", false)):
			if ms.o == PLAYER: notify("%s detonated over %s" % [build_data[ms.k][1], _nname(victim)], "info")
			elif victim == PLAYER: notify("A bomb from %s hit your land" % _nname(ms.o), "bad")
