extends "res://game/map.gd"
# Nations and the RoWorld spawn phase

# ---------------- nations ----------------
func _name() -> String:
	var a := ["Kar", "Vel", "Os", "Tam", "Bri", "Nor", "Zan", "Eld", "Mor", "Ash", "Qua", "Ril", "Dun", "Sar", "Hol", "Ter", "Ul", "Fen", "Gal", "Pry"]
	var b := ["avia", "esh", "ora", "undi", "mark", "heim", "ar", "ios", "ett", "anor", "wick", "stan", "ia", "oth", "urra"]
	var pre := ["", "", "", "Free ", "Clan ", "Tribe of ", "", "Old "]
	return pre[rng.randi() % pre.size()] + a[rng.randi() % a.size()] + b[rng.randi() % b.size()]

func _new_nation(nm: String, col: Color, ai: bool) -> int:
	if border.size() != nations.size():
		border.clear()
		for _k in nations.size(): border.append({})
	border.append({})
	nations.append({"name": nm, "color": col, "ai": ai, "land": 0, "troops": 0.0, "gold": 0.0, "bb": Rect2i(), "alive": true, "sx": 0.0, "sy": 0.0, "regen": 0.0, "reinf_cd": 0.0})
	return nations.size() - 1

func _find_spawn_tile(cx: int, cy: int) -> int:
	for r in range(0, 200, 3):
		for k in 40:
			var x := clampi(cx + rng.randi_range(-r, r), 0, W - 1)
			var y := clampi(cy + rng.randi_range(-r, r), 0, H - 1)
			if owner_map[y * W + x] == NEUTRAL:
				return y * W + x
	return -1

func _claim_blob(id: int, c: int, r: int) -> void:
	var cx := c % W
	var cy := c / W
	# slightly irregular blob: radius wobbles +-12% with angle
	var ph := rng.randf() * TAU; var ph2 := rng.randf() * TAU
	for y in range(cy - r - 2, cy + r + 3):
		for x in range(cx - r - 2, cx + r + 3):
			var ang := atan2(float(y - cy), float(x - cx))
			var rr := float(r) * (1.0 + 0.08 * sin(3.0 * ang + ph) + 0.04 * sin(5.0 * ang + ph2))
			if x >= 0 and y >= 0 and x < W and y < H and Vector2(x - cx, y - cy).length() <= rr + 0.3:
				var i := y * W + x
				if owner_map[i] == NEUTRAL:
					_set_owner(i, id)

func _clear_nation(id: int) -> void:
	for i in W * H:
		if owner_map[i] == id:
			_set_owner(i, NEUTRAL)

func _add_shake(amount: float) -> void:
	var sh_i := clampi(int(save.get("settings", {}).get("shake_i", 1)), 0, 2)
	var mult: float = SHAKE_MULT[sh_i]
	if mult <= 0.0: return
	var scaled := amount * mult
	shake_amp = clampf(maxf(shake_amp, scaled) + scaled * 0.22, 0.0, 7.5 * mult)

func _load_progress(v: float) -> void:
	if load_bar: load_bar.value = v * 100.0

func _start_game_ui() -> void:
	if _loading: return
	_loading = true
	if load_ov == null:
		load_ov = ColorRect.new(); (load_ov as ColorRect).color = Color(0.03, 0.05, 0.10, 0.88)
		load_ov.set_anchors_preset(Control.PRESET_FULL_RECT); load_ov.mouse_filter = Control.MOUSE_FILTER_STOP
		ui.add_child(load_ov)
		var lb := _head(load_ov, "LOADING MAP", Vector2(0, 380), 30, TEXT, 1600, HORIZONTAL_ALIGNMENT_CENTER)
		lb.set_meta("t", 1)
		load_bar = ProgressBar.new(); load_bar.position = Vector2(600, 440); load_bar.size = Vector2(400, 18)
		load_bar.show_percentage = false
		load_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.10), 9, Color(0, 0, 0, 0), 0))
		load_bar.add_theme_stylebox_override("fill", _flat(ORANGE_Y, 9, Color(0, 0, 0, 0), 0))
		load_ov.add_child(load_bar)
	load_ov.visible = true; load_ov.move_to_front(); _load_progress(0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	_async_gen = true
	await gen_map()
	_async_gen = false
	_load_progress(1.0)
	await get_tree().process_frame
	_skip_gen = true
	_start_game()
	_skip_gen = false
	load_ov.visible = false
	_loading = false

func _start_game() -> void:
	_ema_init = false
	mirvs_launched = 0
	ally_requests.clear(); ally_req_last.clear(); ally_replies.clear()
	if not _skip_gen: gen_map()
	var gnz := FastNoiseLite.new(); gnz.seed = randi(); gnz.frequency = 0.012; gnz.fractal_octaves = 2
	grow_n = gnz.get_image(W, H, false, false, true).get_data()
	nations.clear()
	_air_cargo_t.clear(); planes.clear(); beams.clear(); air_t = 0.0; rail_cd = 0.0; shake_amp = 0.0; shake_t = 0.0; if cam: cam.offset = Vector2.ZERO
	stats = {"peak": 0.0, "maxtroops": 0.0, "elims": 0}
	attacks.clear()
	boats.clear()
	structs.clear(); _sv += 1
	if sim_ars: sim_ars.reset()
	if sim_ws: sim_ws.reset()
	sel_ws = null
	struct_at.clear(); missiles.clear(); warships.clear(); traders.clear(); blasts.clear(); shells.clear(); notes.clear(); cap_fx.clear()
	trains.clear(); floats.clear(); embargoes.clear(); embargo_all = false; donate_troop_cd = 0.0; donate_gold_cd = 0.0
	allies.clear(); traitor.clear(); ally_warned.clear(); ally_ext.clear(); ally_extensions.clear(); path_cache.clear(); rail_cache.clear(); _rail_nb_cache.clear(); path_fail.clear()
	if diplo_panel: diplo_panel.visible = false
	if ally_card: ally_card.visible = false
	build_sel = -1
	set_speed(0)
	border.clear(); border.append({})
	nations.append({})  # 0 neutral placeholder
	_new_nation("You", Color(0.15, 0.55, 1.0), false)
	_rw_spawn_all()
	shield_until.clear()
	if bot_players > 0: add_bot_players(bot_players)
	peace = sim_rules.human_grace_ticks(diff_i) / 10.0  # RoWorld human grace (300/180/120 s)
	elapsed = 0.0
	sim_atk = SimAttacks.new(self, sim_rules)
	sim_ai = SimAI.new(self, sim_rules)
	_rebuild_kind_cache()
	sim_ai.setup()
	start_tile = -1
	deploy_t = 5.0
	state = "pick"
	_fade_out(menu_panel, 0.2)
	play_dialog.visible = false
	over_panel_holder.visible = false
	if end_dlg: end_dlg.visible = false
	if note_box: notes.clear(); note_box.queue_redraw()
	if ally_card: ally_card.visible = false
	pick_panel.visible = true
	for n in hud_nodes:
		n.visible = false
	if hud: hud.show_match()

func _claim_disc(id: int, c: int, radius: float) -> void:
	var cx := c % W; var cy := c / W
	var ri := ceili(radius) + 1
	var r2 := radius * radius
	for dy in range(-ri, ri + 1):
		var y := cy + dy
		if y < 0 or y >= H: continue
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			if x < 0 or x >= W: continue
			var fx := dx + 0.5; var fy := dy + 0.5
			if fx * fx + fy * fy <= r2 or (dx == 0 and dy == 0):
				var i := y * W + x
				if owner_map[i] == NEUTRAL: _set_owner(i, id)

func _spawn_note(t: int) -> void:
	_spawn_tiles.append(t)
	var cs := maxi(1, ceili(sim_rules.tribe_spawn_min_dist))
	var key := Vector2i((t % W) / cs, (t / W) / cs)
	if not _spawn_grid.has(key): _spawn_grid[key] = []
	_spawn_grid[key].append(t)

func _spawn_near(t: int) -> bool:
	var md := sim_rules.tribe_spawn_min_dist
	var cs := maxi(1, ceili(md))
	var x := t % W; var y := t / W
	for gy in range(y / cs - 1, y / cs + 2):
		for gx in range(x / cs - 1, x / cs + 2):
			for s in _spawn_grid.get(Vector2i(gx, gy), []):
				if absi(s % W - x) + absi(s / W - y) < md: return true
	return false

func _owned_near(t: int) -> bool:
	var x := t % W
	if x > 0 and owner_map[t - 1] > 0: return true
	if x < W - 1 and owner_map[t + 1] > 0: return true
	if t >= W and owner_map[t - W] > 0: return true
	if t < W * (H - 1) and owner_map[t + W] > 0: return true
	return false

func _random_start() -> int:
	for tries in range(1, 1001):
		var c := rng.randi() % (W * H)
		if owner_map[c] != NEUTRAL or _owned_near(c): continue
		if tries <= 750 and _spawn_near(c): continue
		return c
	return -1

func _nation_spawn_land(cx: int, cy: int) -> int:
	var d := maxi(1, int(floor(sim_rules.nation_spawn_delta + 0.5)))
	for _k in 50:
		var x := rng.randi_range(cx - d, cx + d - 1)
		var y := rng.randi_range(cy - d, cy + d - 1)
		if x < 0 or y < 0 or x >= W or y >= H: continue
		var c := y * W + x
		if owner_map[c] != NEUTRAL: continue
		if mtn[c] == 2 and rng.randi() % 2 == 0: continue
		return c
	return -1

func _rw_spawn_all() -> void:
	_spawn_tiles.clear(); _spawn_grid.clear()
	var R := sim_rules
	var list := []
	if not real_nations.is_empty():
		for e in real_nations: list.append(e)
	else:
		# generated maps have no manifest: same nation count rule as before, random starts
		var base_prot := (5 + (map_i % 4) * 2) * 4
		var np := int(round(float(base_prot) * rng.randf_range(1.5, 2.0)))
		var pool := PROT_NAMES.duplicate(); pool.shuffle()
		for k in np:
			var nm: String = pool[k % pool.size()]
			list.append([nm if k < pool.size() else "New " + nm, "", -1, -1])
	for k in list.size():
		var e: Array = list[k]
		var hex: String = RealMaps.NATION_COLORS.get(str(e[1]), "")
		var col := Color.html(hex) if hex != "" else Color.from_hsv(fmod(float(k) * 0.61803398875, 1.0), rng.randf_range(0.62, 0.86), rng.randf_range(0.82, 0.96))
		var id := _new_nation(e[0], col, true)
		nations[id].prot = true
		nations[id].troops = R.start_troops(SimRules.KIND_NATION, diff_i)
		var t := -1
		if int(e[2]) >= 0:
			t = _nation_spawn_land(int(e[2]), int(e[3]))
			if t < 0: t = _find_spawn_tile(int(e[2]), int(e[3]))
		if t < 0: t = _random_start()
		if t >= 0:
			_claim_disc(id, t, R.spawn_radius); _spawn_note(t); nations[id].spawn_tile = t
			nations[id].troops = R.max_troops(SimRules.KIND_NATION, nations[id].land, 0, diff_i)
		nations[id]["authored_color"] = hex != ""
	_nudge_nation_colors()
	for k in SimRules.DEFAULT_TRIBES:
		var grey_v := rng.randf_range(0.40, 0.58)
		var id := _new_nation(_name(), Color.from_hsv(0.60, rng.randf_range(0.02, 0.07), grey_v), true)
		nations[id].troops = SimRules.START_TROOPS_TRIBE
		var t := _random_start()
		if t >= 0:
			_claim_disc(id, t, R.spawn_radius); _spawn_note(t); nations[id].spawn_tile = t
			nations[id].troops = R.max_troops(SimRules.KIND_TRIBE, nations[id].land, 0, diff_i)
		else:
			nations[id].alive = false

# Sim._create_nations colour pass (COLOR_NEAR_NATION = 70 legacy tiles): an authored flag colour stays unless a
# capital nearby is too similar (minimal nudge); a nation without one gets the human-palette colour most
# distinct from its neighbours. Several nations sharing one flag (the US states) end up distinguishable.
const COLOR_NEAR_NATION := 70.0
func _nudge_nation_colors() -> void:
	var r: float = COLOR_NEAR_NATION * sim_rules.legacy_lin
	var r2 := r * r
	for id in range(2, nations.size()):
		var t: int = int(nations[id].get("spawn_tile", -1))
		if t < 0 or not nations[id].alive: continue
		var p := Vector2(t % W, t / W)
		var refs := []
		for o in range(2, nations.size()):
			if o == id or not nations[o].alive: continue
			var to: int = int(nations[o].get("spawn_tile", -1))
			if to < 0: continue
			if p.distance_squared_to(Vector2(to % W, to / W)) <= r2: refs.append(SimColors.oklab(nations[o].color))
		if nations[id].get("authored_color", false):
			nations[id].color = SimColors.nudge(nations[id].color, refs)
		else:
			nations[id].color = SimColors.pick(SimColors.human_palette(), refs, rng)

func _place_start(t: int) -> void:
	if t < 0 or (owner_map[t] != NEUTRAL and owner_map[t] != PLAYER):
		return
	_clear_nation(PLAYER)
	_claim_disc(PLAYER, t, sim_rules.spawn_radius)
	nations[PLAYER].troops = sim_rules.max_troops(SimRules.KIND_HUMAN, nations[PLAYER].land, 0, diff_i)
	start_tile = t
	# Do NOT reset deploy_t when placing or switching starting location!


# ---------------- bot players and spawn shields (upstream Sim.luau / SimState.luau) ----------------
func is_bot(id: int) -> bool:
	return id > 0 and id < nations.size() and bool(nations[id].get("bot", false))

func is_novice_bot(id: int) -> bool:
	return is_bot(id) and int(nations[id].get("skill", -1)) == NOVICE_SKILL

# The AI difficulty `id` plays at (its own for bot players, else the match's).
func ai_difficulty(id: int) -> int:
	if id > 0 and id < nations.size():
		var s := int(nations[id].get("skill", -1))
		if s >= 0: return s
	return clampi(diff_i, 0, 2)

# The difficulty whose human-protection rules `id` follows (SMART_VS_PLAYERS for a smart bot player).
func human_difficulty(id: int) -> int:
	var d := ai_difficulty(id)
	if is_bot(id) and not is_novice_bot(id): return mini(d, SimRules.SMART_VS_PLAYERS)
	return d

# Troop rules `id` grows by: novice bot players use the Easy nation's cap and growth.
func troop_kind(id: int) -> int:
	return SimRules.KIND_NATION if is_novice_bot(id) else kind_of(id)

func troop_diff(id: int) -> int:
	return NOVICE_SKILL if is_novice_bot(id) else diff_i

func start_troops_of(id: int) -> float:
	if is_novice_bot(id): return sim_rules.start_troops(SimRules.KIND_NATION, NOVICE_SKILL)
	return SimRules.START_TROOPS_HUMAN

# A solo match has no other people in it (bot players count as people).
func is_solo() -> bool:
	for id in range(2, nations.size()):
		if is_bot(id): return false
	return true

# `smart`: plays at SMART_SKILL with human troop numbers; otherwise a novice.
func add_bot_player(display_name: String, smart: bool) -> int:
	var col := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.85), rng.randf_range(0.8, 0.95))
	var id := _new_nation(display_name, col, true)
	nations[id].bot = true
	nations[id].skill = SMART_SKILL if smart else NOVICE_SKILL
	nations[id].troops = start_troops_of(id)
	var t := _random_start()
	if t >= 0:
		_claim_disc(id, t, sim_rules.spawn_radius); _spawn_note(t); nations[id].spawn_tile = t
	else:
		nations[id].alive = false
	return id

# Adds `n` bot players: smart_bots of them (random picks, deterministic for the match RNG) smart.
func add_bot_players(n: int, names: Array = []) -> Array:
	var smart := {}
	var left := mini(smart_bots, n)
	for k in range(1, n + 1):
		if left > 0 and rng.randi() % (n - k + 1) < left:
			smart[k] = true; left -= 1
	if names.is_empty():
		var taken := {}
		for nn in nations: if nn is Dictionary and nn.has("name"): taken[nn.name] = true
		names = BotNames.many(n, func() -> float: return rng.randf(), taken)
	var out := []
	for k in range(1, n + 1):
		var nm: String = names[k - 1] if k - 1 < names.size() else "Player%d" % (1000 + k)
		out.append(add_bot_player(nm, smart.has(k)))
	return out

# No one may attack `id` yet (its spawn shield).
func shielded(id: int) -> bool:
	return id > 0 and sim_atk != null and int(shield_until.get(id, 0)) > sim_atk.tick

func shield_text(id: int) -> String:
	var s := maxi(1, ceili((int(shield_until.get(id, 0)) - sim_atk.tick) / 10.0))
	return "%s has a spawn shield for %d s" % [_nname(id), s]

# Start of play: every person gets a spawn shield, unless the match is solo.
func begin_shields() -> void:
	shield_until.clear()
	if is_solo() or sim_atk == null: return
	for id in range(1, nations.size()):
		if nations[id].alive and kind_of(id) == SimRules.KIND_HUMAN:
			shield_until[id] = sim_atk.tick + SimRules.SPAWN_SHIELD_TICKS
	if shielded(PLAYER):
		notify("You have landed. Expand into free land! No one can attack you for %d s" % (SimRules.SPAWN_SHIELD_TICKS / 10), "good")
