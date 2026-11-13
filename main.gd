extends "res://game/audio.gd"
# Game loop, overlay drawing, input and capture tools

func _pf_add(k: String, v: float) -> void: _pf[k] = _pf.get(k, 0.0) + v
func _pf_line() -> String:
	var f: float = maxf(1.0, _pf.get("frames", 0.0))
	var out := "frames=%d ms/frame:" % int(f)
	for k in ["process", "sim", "atk", "ai", "eco", "missiles", "fx", "boats", "paint", "draw", "wfx", "w_cap", "w_meta", "w_rail", "hud", "nv_bfs"]:
		out += " %s=%.1f" % [k, _pf.get(k, 0.0) / f / 1000.0]
	out += " ticks/frame=%.2f tiles/tick=%.0f atk_per_tick=%.0f set_owner_ms/tick=%.1f naval=%.1f" % [_pf.get("ticks", 0.0) / f, _pf.get("tiles", 0.0) / maxf(1.0, _pf.get("ticks", 0.0)), _pf.get("atk_n", 0.0) / maxf(1.0, _pf.get("ticks", 0.0)), _pf.get("set_owner", 0.0) / maxf(1.0, _pf.get("ticks", 0.0)) / 1000.0, _pf.get("naval", 0.0) / f / 1000.0]
	_pf = {}
	return out
func _process(dt: float) -> void:
	_rail_bfs_left = 4
	_rail_calc_left = 40
	var _t0 := Time.get_ticks_usec()
	map_t += dt
	if map_mat: map_mat.set_shader_parameter("t_anim", fmod(map_t, 1000.0))
	_process_inner(dt)
	_fp["process"] = Time.get_ticks_usec() - _t0
	_pf_add("frames", 1.0); _pf_add("process", _fp.process)
	if _sfx_log and _fp.process > 60000: print("SLOW process ", _fp)
	for kz in ["ai_prot", "ai_boat", "ai_mop", "ai_inv"]: _fp[kz] = 0
	if bench: _bench_step(dt, Time.get_ticks_usec() - _t0)

func _bench_step(dt: float, us: int) -> void:
	if bench_i == -1:
		_start_game()
		var st := _find_spawn_tile(W / 2, H / 2)
		_place_start(st); deploy_t = 0.0
		bench_i = 0; bench_t = -2.0
		return
	if state == "play": peace = 1e9
	bench_t += dt
	if bench_t < 0: return
	if bench_t > 0.0 and bench_frames == 0: bench_ticks0 = ticks_done
	bench_frames += 1; bench_us += us; bench_max = maxi(bench_max, us)
	if bench_t >= 6.0:
		var tk := ticks_done - bench_ticks0
		print("BENCH fps=%.0f speed=%dx frames=%d avg_ms=%.2f max_ms=%.2f sim_ticks_per_s=%.1f (target %.0f) land_player=%d attacks=%d boats=%d" % [bench_frames / bench_t, int(SPEEDS[bench_i]), bench_frames, bench_us / 1000.0 / bench_frames, bench_max / 1000.0, tk / bench_t, 10.0 * SPEEDS[bench_i], nations[PLAYER].land, attacks.size(), boats.size()])
		print("   prof ms: attacks=%.0f economy=%.0f boats=%.0f ai=%.0f ai_max=%.1f naval=%.0f traders=%d" % [prof.atk / 1000.0, prof.eco / 1000.0, prof.boat / 1000.0, prof.ai / 1000.0, prof.ai_max / 1000.0, prof.get("naval", 0) / 1000.0, traders.size()])
		for k in prof: prof[k] = 0
		bench_i += 1
		if bench_i >= SPEEDS.size():
			get_tree().quit(); return
		set_speed(bench_i)
		bench_t = 0.0; bench_frames = 0; bench_us = 0; bench_max = 0

func _pace_step() -> void:
	# headless pacing test: --pace=<map_i>,<runs>[,growth,atk,gold,airate]
	if _pace.has("init"):
		var a := ""
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--pace="): a = x.substr(7)
		var p := a.split(",")
		_pace = {"map": int(p[0]), "runs": int(p[1]), "run": 0, "started": false}
		if p.size() >= 6:
			sim_rules.growth_mult = float(p[2]); sim_rules.attack_speed_mult = float(p[3])
			sim_rules.gold_mult = float(p[4]); sim_rules.ai_rate_mult = float(p[5])
	if not _pace.started:
		map_tab = 0; map_i = _pace.map
		_start_game()
		_place_start(_find_spawn_tile(W / 2, H / 3)); deploy_t = 0.0
		state = "play"; peace = 1e9
		_pace.started = true
		return
	for k in 300:
		var t0 := Time.get_ticks_usec()
		_tick_attacks()
		var t1 := Time.get_ticks_usec()
		_ai(0.1)
		var t2 := Time.get_ticks_usec()
		sim_naval.tick()
		var t3 := Time.get_ticks_usec()
		_economy(0.1); ticks_done += 1
		sim_ars.tick(); sim_ws.tick(); _trains_tick(); _requests_tick(); _tick_missiles(SimArsenal.DT_TICK)
		var t4 := Time.get_ticks_usec()
		_tick_boats(0.1); _tick_trade(0.1)
		var t5 := Time.get_ticks_usec()
		for kk in ["atk", "ai", "nav", "eco", "units"]: if not _pace.has(kk): _pace[kk] = 0
		_pace.atk += t1 - t0; _pace.ai += t2 - t1; _pace.nav += t3 - t2; _pace.eco += t4 - t3; _pace.units += t5 - t4
		if _sfx_log and sim_atk.tick >= 1800: print("SFXLOG done 3min"); get_tree().quit(); return
		if OS.get_cmdline_user_args().has("--prof") and sim_atk.tick % 1200 == 0:
			print("   scan ms/tick=%.2f scans/tick=%.1f" % [sim_ai.scan_us / 1200000.0, sim_ai.scan_n / 1200.0]); sim_ai.scan_us = 0; sim_ai.scan_n = 0
			print("PROF t=%dmin ms/tick atk=%.2f ai=%.2f naval=%.2f eco=%.2f units=%.2f attacks=%d" % [sim_atk.tick / 600, _pace.atk / 1200000.0, _pace.ai / 1200000.0, _pace.nav / 1200000.0, _pace.eco / 1200000.0, _pace.units / 1200000.0, attacks.size()])
			for kk in ["atk", "ai", "nav", "eco", "units"]: _pace[kk] = 0
			if sim_atk.tick >= 6000: get_tree().quit(); return
		var win := (land_total - fallout_count) * SimRules.WIN_SHARE
		var best := 0; var bid := 0
		for id in range(1, nations.size()):
			if nations[id].alive and nations[id].land > best: best = nations[id].land; bid = id
		if best >= win or sim_atk.tick >= 60 * 600:
			print("PACE map=%s run=%d minutes=%.1f winner=%s share=%.2f alive=%d" % [MAPS[map_i][0], _pace.run, sim_atk.tick / 600.0, nations[bid].name, float(best) / maxf(1.0, land_total), nations.filter(func(n): return n is Dictionary and n.get("alive", false) and n.get("land", 0) > 0).size()])
			_pace.run += 1; _pace.started = false
			if _pace.run >= _pace.runs: get_tree().quit()
			return
		if sim_atk.tick % 3000 == 0:
			print("  t=%dmin lead=%.2f" % [sim_atk.tick / 600, float(best) / maxf(1.0, land_total)])

func _process_inner(dt: float) -> void:
	_pump_previews()
	if not _pace.is_empty() or OS.get_cmdline_user_args().has("--pacetest") : _pace_step(); return
	boat_launched_frame = false
	if state == "pick":
		var picked: bool = start_tile >= 0 and nations[PLAYER].land > 0
		if picked: deploy_t -= dt
		if picked:
			pick_title.text = "DEPLOYING IN %d" % ceili(maxf(deploy_t, 0.0))
			pick_sub.text = "Click anywhere else on land to switch your starting spot (timer won't reset)."
		else:
			pick_title.text = "CHOOSE YOUR STARTING LOCATION"
			pick_sub.text = "Click any unclaimed land to found your nation."
		pick_ring.set_meta("v", clampf(deploy_t / 5.0, 0, 1)); pick_ring.set_meta("n", ceili(maxf(deploy_t, 0.0)))
		pick_ring.visible = true; pick_ring.queue_redraw()
		if picked and deploy_t <= 0:
			state = "play"
			if audio_dir != null: audio_dir.begin_match(); audio_dir.set_music_mood("calm")
			_play_music()
			_focus_player_smooth(2.6)
			var dl := 0.0
			for n in hud_nodes:
				var nd: Control = n
				get_tree().create_timer(dl).timeout.connect(func(): _fade_in(nd, Vector2(0, 12 if nd.position.y > 600 else -12)))
				dl += 0.04
			_fade_out(pick_panel)
			if hud: hud.show_match()
	var rdt := dt
	_animate_labels(rdt)
	dt *= sim_speed
	if state == "play":
		# RoWorld runs 10 ticks per second at 1x (SPEED_BASE only slows the visual unit motion)
		var tdt := rdt * sim_speed / SPEED_BASE
		elapsed += tdt
		tick_acc += tdt
		tick_acc = minf(tick_acc, 0.1 * MAX_TICKS_PER_FRAME)
		var nt := 0
		var loop_t0 := Time.get_ticks_usec()
		# frame budget: the sim gets SIM_BUDGET_US per frame; a long attacks pass is time-sliced over frames
		# (upstream runs a local step as a Coop job spread over frames), so the window never stalls and the
		# sim simply runs slower than the chosen speed when it can't keep up
		while (tick_acc >= 0.1 or sim_atk.pass_open) and nt < MAX_TICKS_PER_FRAME:
			if Time.get_ticks_usec() - loop_t0 > SIM_BUDGET_US: break
			if not sim_atk.pass_open:
				tick_acc -= 0.1
				nt += 1
				_rebuild_def_posts()
				sim_atk.begin_tick()
			var a0 := Time.get_ticks_usec()
			var atk_done := sim_atk.run_slice(loop_t0 + SIM_BUDGET_US)
			prof.atk += Time.get_ticks_usec() - a0
			_fp["t_atk"] = Time.get_ticks_usec() - a0; _pf_add("atk", _fp.t_atk)
			if not atk_done: break
			a0 = Time.get_ticks_usec()
			_ai(0.1)
			var e_ai := Time.get_ticks_usec() - a0
			_fp["t_ai"] = e_ai; _pf_add("ai", e_ai)
			prof.ai += e_ai; prof.ai_max = maxi(prof.ai_max, e_ai)
			a0 = Time.get_ticks_usec()
			sim_naval.defer_paths = Time.get_ticks_usec() - loop_t0 > SIM_BUDGET_US / 2
			if not OS.has_environment("NO_TRADE"): sim_naval.tick()
			sim_naval.defer_paths = false
			prof["naval"] = prof.get("naval", 0) + Time.get_ticks_usec() - a0
			_pf_add("naval", Time.get_ticks_usec() - a0)
			ticks_done += 1
			a0 = Time.get_ticks_usec()
			_economy(0.1)
			sim_ars.tick()
			_requests_tick()
			sim_ws.tick()
			_trains_tick()
			prof.eco += Time.get_ticks_usec() - a0
			_fp["t_eco"] = Time.get_ticks_usec() - a0; _pf_add("eco", _fp.t_eco)
		_fp["sim"] = Time.get_ticks_usec() - loop_t0; _fp["ticks"] = nt; _pf_add("sim", _fp.sim); _pf_add("ticks", nt)
		var u0 := Time.get_ticks_usec()
		_tick_missiles(dt); _fp["missiles"] = Time.get_ticks_usec() - u0; _pf_add("missiles", _fp.missiles); u0 = Time.get_ticks_usec()
		_tick_trade(tdt); _fp["ships"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_fp["trains"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_tick_fx(dt); _fp["fx"] = Time.get_ticks_usec() - u0; _pf_add("fx", _fp.fx); u0 = Time.get_ticks_usec()
		_tick_meta(dt); _fp["meta"] = Time.get_ticks_usec() - u0
		donate_troop_cd = maxf(0.0, donate_troop_cd - dt)
		donate_gold_cd = maxf(0.0, donate_gold_cd - dt)
		if ai_timer == 0.0 or rng.randf() < 0.2: _tick_alliances()
		var b0 := Time.get_ticks_usec()
		_tick_boats(tdt)
		prof.boat += Time.get_ticks_usec() - b0
		_pf_add("boats", Time.get_ticks_usec() - b0)
		ai_timer += dt
		# RoWorld win: 80 % of the land that is not fallout
		var pl = nations[PLAYER]
		var win_land := (land_total - fallout_count) * SimRules.WIN_SHARE
		if pl.land >= win_land:
			_game_over(true)
		elif pl.land <= 0:
			_game_over(false)
		elif ticks_done % 10 == 0:
			for id in range(2, nations.size()):
				if nations[id].alive and nations[id].land >= win_land:
					notify("%s controls 80%% of the land" % nations[id].name, "bad")
					_game_over(false); break
	dt = rdt
	_pan(dt)
	if shake_amp > 0.05:
		shake_t += dt * 42.0
		shake_amp = maxf(0.0, shake_amp - shake_amp * 14.0 * dt - 4.0 * dt)
		cam.offset = Vector2(sin(shake_t * 1.9 + 0.5), cos(shake_t * 2.5)) * shake_amp
	elif cam.offset != Vector2.ZERO:
		shake_amp = 0.0
		cam.offset = Vector2.ZERO
	if dirty:
		var more := false
		var p0 := Time.get_ticks_usec()
		if not _pend_paint.is_empty(): more = _flush_paint_budget(PAINT_BUDGET_US)  # spread big repaints over frames
		var up := 0
		for k in chunk_dirty.size():
			if chunk_dirty[k] == 1:
				if up >= 24: more = true; break
				chunk_tex[k].update(chunk_img[k]); chunk_dirty[k] = 0; uploads += 1; up += 1
		dirty = more
		_pf_add("paint", Time.get_ticks_usec() - p0)
	ui_timer += dt
	if ui_timer > 0.25 and state != "menu":
		ui_timer = 0
		var h0 := Time.get_ticks_usec()
		_tick_music_mood()
		_update_hud()
		_pf_add("hud", Time.get_ticks_usec() - h0)
	_update_tooltip()
	_animate_ui(rdt)
	if hud: hud.process(rdt)
	if note_box: _tick_notes(rdt)
	_tick_ally_card()
	ov_t += rdt
	if overlay and state != "menu":
		_last_cam = cam.position; _last_zoom = cam.zoom
		overlay.queue_redraw()
	if autoshot: _autoshot(dt)

func _animate_labels(dt: float) -> void:
	# critically-damped springs: smooth, elastic, no jitter
	for at in attacks:
		if not at.has("disp"): continue
		var acc: Vector2 = (at.tgt - at.disp) * 60.0 - at.vel * 13.0
		at.vel += acc * dt
		at.disp += at.vel * dt
		at.shown = lerpf(at.shown, at.troops, 1.0 - exp(-8.0 * dt))
	for id in range(1, nations.size()):
		var n = nations[id]
		if n.land <= 0: continue
		var c := Vector2(n.sx / n.land + 0.5, n.sy / n.land + 0.5) * TS
		if not n.has("lp"): n.lp = c; n.ls = sqrt(float(n.land))
		n.lp = n.lp.lerp(c, 1.0 - exp(-4.0 * dt))
		n.ls = lerpf(n.ls, sqrt(float(n.land)), 1.0 - exp(-4.0 * dt))

func set_speed(k: int) -> void:
	set_speed_x(SPEEDS[clampi(k, 0, SPEEDS.size() - 1)])

func set_speed_x(x: float) -> void:
	x = clampf(snappedf(x, 0.5), 0.5, 10.0)
	for sp in [1.0, 2.0, 5.0, 10.0]:  # snap points
		if absf(x - sp) <= 0.26: x = sp
	sim_speed = x * SPEED_BASE
	if speed_slider: speed_slider.set_value_no_signal(x)
	if speed_lbl: speed_lbl.text = ("%dx" % int(x)) if is_equal_approx(x, roundf(x)) else ("%.1fx" % x)
	_place_speed_readout()

func _shot(name: String) -> void:
	var im = get_viewport().get_texture().get_image()
	if im:
		DirAccess.make_dir_recursive_absolute(shots_dir)
		im.save_png(shots_dir + "/" + name)
		print("SAVED ", name, " ", im.get_size())

func warp_away() -> void:
	get_viewport().warp_mouse(Vector2(1580, 690))

func _focus_player(z: float) -> void:
	var n = nations[PLAYER]
	cam.zoom = Vector2(z, z); cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS; _clamp_cam()

func _focus_player_smooth(z: float, dur := 0.42) -> void:
	if nations.size() <= PLAYER or nations[PLAYER].land <= 0: return
	if autoshot or bench:
		_focus_player(z)
		return
	var n = nations[PLAYER]
	var target_pos := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam, "position", target_pos, dur)
	tw.tween_property(cam, "zoom", Vector2(z, z), dur)
	tw.chain().tween_callback(_clamp_cam)

func _look27(tag: String) -> void:
	var tm := [1.0, 9.0, 10.0, 11.0, 11.2, 11.4, 11.6, 11.8, 12.0, 12.2, 16.0, 40.0]
	if _l27 >= tm.size() or shot_t < tm[_l27]: return
	match _l27:
		0:
			save.settings["qual_i"] = 3; apply_settings()
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(2.2, 2.2); _clamp_cam()
		2: _shot("27_%s_territory.png" % tag)
		3:
			var n = nations[PLAYER]
			var pc := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land))
			var tgt := -1
			for r in range(20, 120, 4):
				for k in 64:
					var t := Vector2i(pc + Vector2.from_angle(k * TAU / 64.0) * r)
					var ti := t.y * W + t.x
					if t.x > 0 and t.y > 0 and t.x < W and t.y < H and owner_map[ti] > 1: tgt = ti; break
				if tgt >= 0: break
			if tgt < 0: tgt = int(pc.y + 30) * W + int(pc.x + 30)
			_l27c = Vector2(tgt % W, tgt / W)
			detonate(PLAYER, _l27c, float(NUKE_R[7]), 1.0)
			cam.position = _l27c * TS; cam.zoom = Vector2(3.0, 3.0); _clamp_cam()
			fx_freeze = true
			for bl in blasts: bl.t = 0.35
		4: _shot("27_%s_nuke_impact.png" % tag)
		5: for bl in blasts: bl.t = 0.62
		6: _shot("27_%s_nuke_impact_late.png" % tag)
		7: for bl in blasts: bl.t = 2.5
		8: _shot("27_%s_nuke_debris.png" % tag)
		9: fx_freeze = false; blasts.clear()
		10: _shot("27_%s_fallout.png" % tag)
		11: _shot("27_%s_fallout_recede.png" % tag); get_tree().quit()
	_l27 += 1

func _texshot() -> void:
	var tm := [1.0, 4.0, 6.0, 7.0, 9.0, 10.0, 11.0]
	if _qs >= tm.size() or shot_t < tm[_qs]: return
	match _qs:
		0:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			n.gold = 1e9
			var c := Vector2i(int(n.sx / maxf(1, n.land)), int(n.sy / maxf(1, n.land)))
			var kinds := [0, 1, 2, 3, 4, 5, 10, 14, 15]
			var placed := 0
			for r in range(0, 40):
				for dy in range(-r, r + 1, 6):
					for dx in range(-r, r + 1, 6):
						if placed >= kinds.size(): break
						var t := (c.y + dy) * W + c.x + dx
						if t < 0 or t >= W * H or owner_map[t] != PLAYER or struct_at.has(t): continue
						var ok := true
						for s2 in structs:
							if Vector2(s2.tile % W, s2.tile / W).distance_to(Vector2(t % W, t / W)) < 6: ok = false
						if ok: _struct_add(kinds[placed], t, PLAYER); placed += 1
			spawn_warship(PLAYER); spawn_warship(PLAYER)
			save.settings["qual_i"] = 3; apply_settings()
		2:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(6, 6); _clamp_cam()
		3: _shot("26_structures_plates.png")
		4:
			if not warships.is_empty(): cam.position = warships[0].pos * TS
			elif not traders.is_empty(): cam.position = _boat_pos(traders[0])[0]
			cam.zoom = Vector2(7, 7); _clamp_cam()
		5: _shot("26_units_sprites.png"); cam.zoom = Vector2(2.5, 2.5); _clamp_cam()
		6: _shot("26_overview_buildbar.png"); get_tree().quit()
	_qs += 1
func _rw_stats(tag: String) -> void:
	var ids := []
	for id in range(1, nations.size()):
		if nations[id].alive and nations[id].land > 0: ids.append(id)
	ids.sort_custom(func(x, y): return nations[x].land > nations[y].land)
	var pl = nations[PLAYER]
	print("RWSTAT %s tick=%d alive=%d attacks=%d boats=%d player land=%d troops=%.0f cap=%.0f gold=%.0f" % [tag, sim_atk.tick, ids.size(), attacks.size(), boats.size(), pl.land, pl.troops, troop_cap(PLAYER), pl.gold])
	for k in mini(6, ids.size()):
		var n = nations[ids[k]]
		print("   #%d %s kind=%d land=%d troops=%.0f/%.0f gold=%.0f" % [k + 1, n.name, kind_of(ids[k]), n.land, n.troops, troop_cap(ids[k]), n.gold])

func _rw_full_view() -> void:
	cam.zoom = Vector2(1.5, 1.5); cam.position = Vector2(W, H) * TS / 2; _clamp_cam()

func _rw_start(mi: int, fx: float, fy: float) -> void:
	map_tab = 0; map_i = mi
	_start_game()
	var st := -1
	for r in range(0, 120, 2):
		for _k in 40:
			var x := clampi(int(W * fx) + rng.randi_range(-r, r), 4, W - 5)
			var y := clampi(int(H * fy) + rng.randi_range(-r, r), 4, H - 5)
			var ok := true
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					if owner_map[(y + dy) * W + x + dx] != NEUTRAL: ok = false
			if ok: st = y * W + x; break
		if st >= 0: break
	_place_start(st)
	_rw_full_view()

func _rwshot() -> void:
	var tm := [1.0, 2.0, 3.0, 3.5, 60.0, 61.0, 120.0, 121.0, 122.0, 123.0, 150.0, 151.0]
	if _rws >= tm.size() or shot_t < tm[_rws]: return
	match _rws:
		0: play_dialog.visible = true; _set_map_tab(0)
		1: _shot("28_map_select_real_maps.png"); play_dialog.visible = false; _rw_start(0, 0.50, 0.30)
		2: _shot("28_world_spawn_phase.png"); _rw_stats("spawn")
		3: deploy_t = 0.0; launch_attack(PLAYER, NEUTRAL, 0.5); set_speed(1)
		4: _rw_full_view(); _shot("28_world_t1.png"); _rw_stats("t1"); launch_attack(PLAYER, NEUTRAL, 0.5)
		5:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(5, 5); _clamp_cam()
		6: _shot("28_player_closeup.png"); _rw_full_view()
		7: _shot("28_world_t2.png"); _rw_stats("t2")
		8: _rw_start(1, 0.45, 0.5)
		9: _shot("28_europe_spawn.png"); deploy_t = 0.0; set_speed(1)
		10: _rw_full_view(); _shot("28_europe_t1.png"); _rw_stats("europe")
		11: get_tree().quit()
	_rws += 1

func _r29_mid() -> Array:
	var k: int = R29_KINDS[_r29_kind]
	var out := []
	for ms in missiles:
		if ms.dur <= 0.0: continue
		var ok: bool = (ms.get("branched", false) and not ms.get("mirv_bus", false)) if k == 9 else (ms.k == k or (k == 12 and ms.get("branched", false)))
		if ok and ms.t / ms.dur >= 0.35 and ms.t / ms.dur <= 0.7: out.append(ms)
	return out

func _rw29() -> void:
	match _r29:
		0:
			if shot_t < 1.0: return
			play_dialog.visible = true; _set_map_tab(0)
		1:
			if shot_t < 2.0: return
			_shot("29_ui_map_select_rounded.png"); play_dialog.visible = false
			_rw_start(0, 0.50, 0.30)
		2:
			if shot_t < 3.0: return
			_shot("29_world_no_antarctica_spawn.png"); _rw_stats("spawn")
			deploy_t = 0.0
		3:
			if shot_t < 3.6: return
			launch_attack(PLAYER, NEUTRAL, 0.6); set_speed(1)
			_r29_t = shot_t
		4:
			if shot_t < _r29_t + 40.0: return
			_rw_full_view(); _shot("29_world_t1.png"); _rw_stats("t1")
			var ports := 0; var placed := []
			for st in structs:
				if st.k == 1: ports += 1
			print("RW29 ports=%d traders=%d boats=%d" % [ports, traders.size(), boats.size()])
			# placement test: city twice on the same click -> second snaps away or upgrades
			var n = nations[PLAYER]
			n.gold = 5e6
			var c := int(n.sy / maxf(1, n.land)) * W + int(n.sx / maxf(1, n.land))
			for k in [0, 0, 1, 2]:
				var site := sim_struct.place_site(PLAYER, k, c)
				var ok := try_build(k, c)
				placed.append("k%d ok=%s site=%d upg=%s reason=%s" % [k, str(ok), site.tile, str(site.upgrade != null), site.reason])
			print("RW29 placement ", placed)
			cam.position = Vector2(c % W, c / W) * TS; cam.zoom = Vector2(6, 6); _clamp_cam()
		5:
			if shot_t < _r29_t + 41.0: return
			_shot("29_ui_hud_rounded_buildings.png")
			_r29_t = shot_t
		6:
			if shot_t < _r29_t + 40.0: return
			_rw_full_view(); _shot("29_world_trade_t2.png"); _rw_stats("t2")
			print("RW29 traders=%d boats=%d" % [traders.size(), boats.size()])
			god_mode = true
			var n = nations[PLAYER]
			var c := -1
			for i in W * H:
				if owner_map[i] == PLAYER and not struct_at.has(i): c = i; break
			_struct_add(5, c, PLAYER); struct_at[c].bt = 0.0
			_r29_kind = 0; _r29_shot = -1
			set_speed(0)
		7:
			# launch the next kind toward a target ~130 tiles east of the silo
			var silo_t := -1
			for st in structs:
				if st.k == 5 and st.o == PLAYER: silo_t = st.tile
			var tx := clampi(silo_t % W + 130, 0, W - 1); var ty := clampi(silo_t / W + 10, 0, H - 1)
			var tgt := -1
			for r in range(0, 60):
				for dx in range(-r, r + 1):
					var i := clampi(ty + r / 2, 0, H - 1) * W + clampi(tx + dx, 0, W - 1)
					if owner_map[i] > 0 and owner_map[i] != PLAYER: tgt = i; break
				if tgt >= 0: break
			missiles.clear(); blasts.clear()
			var k: int = R29_KINDS[_r29_kind]
			print("RW29 launch ", R29_NAMES[k], " ok=", launch_nuke(PLAYER, k, tgt))
			save.settings["qual_i"] = 3; apply_settings()
			_r29_t = shot_t
		8:
			if _r29_mid().is_empty():
				if shot_t - _r29_t > 60.0: print("RW29 timeout ", _r29_kind); _r29 = 10
				return
			sim_speed = 0.0
			_r29_shot = 0
		9:
			var mids := _r29_mid()
			var nm: String = R29_NAMES[R29_KINDS[_r29_kind]]
			var focus := Vector2(W, H) * TS / 2
			if not mids.is_empty():
				var acc := Vector2.ZERO
				for ms in mids: acc += _missile_world_pos(ms, ms.t / ms.dur)
				focus = acc / mids.size()
			var zooms := [1.8, 3.5, 7.0]
			if _r29_shot < 3:
				cam.zoom = Vector2.ONE * zooms[_r29_shot]; cam.position = focus; _clamp_cam()
				_r29_shot += 10  # wait a frame before capturing
				return
			if _r29_shot >= 10 and _r29_shot < 13:
				var zi := _r29_shot - 10
				_shot("29_trail_%s_ultra_z%d.png" % [nm, zi + 1])
				_r29_shot = zi + 1
				if _r29_shot < 3: return
				save.settings["qual_i"] = 2; apply_settings()
				cam.zoom = Vector2.ONE * 3.5; cam.position = focus; _clamp_cam()
				_r29_shot = 20
				return
			if _r29_shot == 20:
				_r29_shot = 21; return
			if _r29_shot == 21:
				_shot("29_trail_%s_high_z2.png" % nm)
			set_speed(0)
			_r29_kind += 1
			if _r29_kind < R29_KINDS.size():
				_r29 = 7; return
		10:
			get_tree().quit(); return
	_r29 += 1

func _qualshot() -> void:
	var tm := [1.0, 3.0, 4.0, 4.6, 5.4, 6.0, 6.8, 9.0, 9.35, 9.6, 9.95, 10.2, 10.55, 11.0, 11.12, 11.5]
	if _qs >= tm.size() or shot_t < tm[_qs]: return
	match _qs:
		0:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(9, 9); _clamp_cam()
			save.settings["qual_i"] = 0; apply_settings()
		2: _shot("22_quality_low.png"); save.settings["qual_i"] = 1; apply_settings()
		3: _shot("22b_quality_medium.png"); save.settings["qual_i"] = 2; apply_settings()
		4: _shot("22c_quality_high.png"); save.settings["qual_i"] = 3; apply_settings()
		5: _shot("23_quality_ultra.png"); _open_settings()
		6: _shot("24_settings_slider.png"); settings_dlg.visible = false
		7, 9, 11:
			var hq := _q()
			var n = nations[PLAYER]
			var c := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(4, 4); cam.position = c; _clamp_cam()
			blasts.append({"pos": c + Vector2(14, 6), "r": 6.0 * TS, "t": 0.0, "dur": 1.6, "seed": 99173})
			# capture flash demo on a patch of tiles
			var ct := Vector2i(c / TS)
			for yy in range(ct.y - 10, ct.y - 4):
				for xx in range(ct.x - 14, ct.x - 4):
					if xx >= 0 and yy >= 0 and xx < W and yy < H: cap_fx[yy * W + xx] = [map_t, n.color]
			# follow a boat/trader/warship if one exists
			var tgt = null
			if not warships.is_empty(): tgt = warships[0].pos * TS
			elif not boats.is_empty(): tgt = _boat_pos(boats[0])[0]
			elif not traders.is_empty(): tgt = _boat_pos(traders[0])[0]
			if tgt != null: cam.position = tgt; cam.zoom = Vector2(5, 5); _clamp_cam(); blasts[-1].pos = tgt + Vector2(30, 0)
			if hq != 0: pass
		8: _shot("25_anim_ultra.png"); save.settings["qual_i"] = 1; apply_settings()
		10: _shot("25_anim_medium.png"); save.settings["qual_i"] = 0; apply_settings()
		12: _shot("25_anim_low.png"); save.settings["qual_i"] = 3; apply_settings()
		13:
			if not boats.is_empty():
				cam.position = _boat_pos(boats[0])[0]; cam.zoom = Vector2(7, 7); _clamp_cam()
				print("boat dir ", _boat_pos(boats[0])[1], " q ", _q())
			blasts.append({"pos": cam.position + Vector2(10, 4), "r": 5.0 * TS, "t": 0.5, "dur": 1.6, "seed": 5511})
		14: _shot("25_anim_ultra_ships_blast.png")
		15: get_tree().quit()
	_qs += 1
func _autoshot(dt: float) -> void:
	shot_t += dt
	if "--qualshot" in OS.get_cmdline_user_args():
		_qualshot(); return
	if "--rwshot" in OS.get_cmdline_user_args():
		_rwshot(); return
	if "--rw29" in OS.get_cmdline_user_args():
		_rw29(); return
	if "--texshot" in OS.get_cmdline_user_args():
		_texshot(); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look27="):
			_look27(a.substr(9)); return
	if _pre == 0 and shot_t > 2.0:
		_shot("01_menu.png"); play_dialog.visible = true; _set_map_tab(0); _pre = 1; return
	if _pre == 1 and shot_t > 2.6:
		_shot("02_play_solo.png"); _set_map_tab(1); _pre = 2; return
	if _pre == 2 and shot_t > 3.2:
		_shot("02b_random_maps.png"); _set_map_tab(0); play_dialog.visible = false; _pre = 3; shot_t = 0.7; _step = 1; return
	if _pre < 3: return
	var plan := [0.6, 1.0, 2.6, 3.0, 14.0, 14.5, 15.5, 16.0, 17.0, 17.5, 19.5, 20.0, 21.0, 22.5, 23.0, 26.0, 27.0, 28.0, 29.0, 30.2, 31.0, 31.8, 32.6, 33.4, 34.2, 35.0, 35.8, 36.6, 37.4, 38.2, 39.0, 39.8, 40.6, 41.4]
	if _step >= plan.size() or shot_t < plan[_step]: return
	match _step:
		0: _shot("01_menu.png")
		1:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st)
			set_speed(3)
			get_viewport().warp_mouse(_screen_of(Vector2(st % W + 6, st / W + 4) * TS))
		2:
			_shot("03_pick_deploy.png")
			deploy_t = 0.0
		3: launch_attack(PLAYER, NEUTRAL, 0.75)
		4:
			peace = elapsed  # end peace early so AI also targets the player / sends boats
			var bb: Rect2i = nations[PLAYER].bb.grow(2).intersection(Rect2i(0, 0, W, H))
			var tgt := -1
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var o := owner_map[y * W + x]
					if o > 1 and _adj_to(y * W + x, PLAYER) and (tgt < 0 or nations[o].troops > nations[tgt].troops): tgt = o
			if tgt > 0: print("land attack on tribe ", tgt, " ok=", launch_attack(PLAYER, tgt, 0.2))
			else: print("no bordering tribe")
			launch_attack(PLAYER, NEUTRAL, 0.3)
		5:
			var ok := false
			var pc: Vector2i = nations[PLAYER].bb.get_center()
			for k in 600:
				var i := rng.randi() % (W * H)
				if owner_map[i] >= 0 and owner_map[i] != PLAYER and _coastal(i) and absi(i % W - pc.x) > 50 and absi(i % W - pc.x) < 160:
					ok = launch_boat(PLAYER, i, 0.25)
					if ok: _pboat = boats[boats.size() - 1]; break
			print("player boat ", ok, " route pts ", (_pboat.pts.size() if _pboat else 0))
		6:
			if _pboat and _pboat in boats:
				var bp := _boat_pos(_pboat)
				var pts: PackedVector2Array = _pboat.pts
				cam.position = (bp[0] + pts[pts.size() - 1]) / 2; cam.zoom = Vector2(2.0, 2.0); _clamp_cam()
				print("boat progress ", int(_pboat.d), "/", int(_pboat.cum[_pboat.cum.size() - 1]))
		7: _shot("06_boat_curve.png")
		8:
			set_speed(3)
			var ai_b := 0
			for bt in boats: if bt.a != PLAYER: ai_b += 1
			print("AI boats at sea ", ai_b, " total boats ", boats.size())
			cam.zoom = Vector2(1.25, 1.25); cam.position = Vector2(W, H) * TS / 2; _clamp_cam()
		9: _shot("07_ai_boats_speed.png")
		10:
			_focus_player(3.0)
			var bb3: Rect2i = nations[PLAYER].bb.grow(2).intersection(Rect2i(0, 0, W, H))
			var tg := -1
			for y in range(bb3.position.y, bb3.end.y):
				for x in range(bb3.position.x, bb3.end.x):
					var o := owner_map[y * W + x]
					if o > 1 and _adj_to(y * W + x, PLAYER) and (tg < 0 or nations[o].troops > nations[tg].troops): tg = o
			if tg > 0: print("front attack on ", tg, " ok=", launch_attack(PLAYER, tg, 0.15))
			var cnt := 0
			for at in attacks:
				if at.a == PLAYER or at.t == PLAYER: cnt += 1
			print("player-involved attacks ", cnt)
			var best := -1
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 30:
					var sp := _screen_of(Vector2(nn.sx / nn.land, nn.sy / nn.land) * TS)
					if sp.x > 400 and sp.x < 1200 and sp.y > 150 and sp.y < 650: best = id; break
			if best > 0:
				var nn = nations[best]
				get_viewport().warp_mouse(_screen_of(Vector2(nn.sx / nn.land, nn.sy / nn.land) * TS))
		11: _shot("08_front.png")
		12:
			_focus_player(3.0)
			var n = nations[PLAYER]
			n.gold = 6e7
			_claim_blob(PLAYER, int(n.sy / n.land) * W + int(n.sx / n.land), 26)  # test harness: give room for buildings
			_focus_player(2.2)
			var placed := 0
			for kk in [5, 1, 1, 4, 10, 0, 2, 0, 3, 0, 2]:
				for tries in 4000:
					var bb2: Rect2i = n.bb
					var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
					if try_build(kk, ti): placed += 1; print("  built ", build_data[kk][1]); break
			for st in structs:
				st.bt = 0.0
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive and owned_count(id, 1) == 0:
					var bbp: Rect2i = nations[id].bb
					for tries in 600:
						var ti := (bbp.position.y + rng.randi() % maxi(1, bbp.size.y)) * W + bbp.position.x + rng.randi() % maxi(1, bbp.size.x)
						if owner_map[ti] == id and _coastal(ti): _struct_add(1, ti, id); struct_at[ti].bt = 0.0; break
			print("buildings placed ", placed, " warship ", try_build(6, -1))
			tip_slot = -1; build_sel = -1
			warp_away()
		13: _shot("05_buildings.png")
		14:
			# nukes at the two nearest other nations
			var n = nations[PLAYER]
			var pc := Vector2(n.sx, n.sy) / maxf(1, n.land)
			var cands := []
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 20: cands.append([pc.distance_to(Vector2(nn.sx, nn.sy) / nn.land), id])
			cands.sort()
			var shots_done := 0
			for c in cands.slice(0, 2):
				for st in structs:
					if st.o == PLAYER and st.k == 5: st.cd = 0.0
				var nn = nations[c[1]]
				var ti := int(nn.sy / nn.land) * W + int(nn.sx / nn.land)
				var kk := 9 if shots_done == 0 else 7
				print("nuke ", build_data[kk][1], " at ", nn.name, " (land=", nn.land, ") ok=", try_build(kk, ti))
				shots_done += 1
			# alliance: ally with a protagonist, then force the expiry warning
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive:
					form_alliance(PLAYER, id)
					allies[_akey(PLAYER, id)] = sim_atk.tick + 250
					break
		15:
			var tgt := Vector2.ZERO
			if not blasts.is_empty(): tgt = blasts[0].pos
			var fo := 0
			for i in W * H: if fallout[i] == 1: fo += 1
			if tgt == Vector2.ZERO:
				for i in range(0, W * H, 7):
					if fallout[i] == 1: tgt = Vector2(i % W, i / W) * TS; break
			# Also showcase in-flight nukes on parabolic ballistic arcs with 3x thicker (4.5px) host-country-colored trails
			var n = nations[PLAYER]
			var pc := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land))
			var ft := tgt / TS if tgt != Vector2.ZERO else pc + Vector2(36, 12)
			# 1. Standard 1.0x (4.5px) Atom Bomb trail
			missiles.append({"o": PLAYER, "k": 7, "from": pc, "to": ft + Vector2(20, -8), "t": 16.0, "dur": 25.0, "r": float(NUKE_R[7]), "mirv": false, "branched": false})
			# 2. MIRV landed at the aimed point `ft` (detonating there) and branching 6 sub-warheads outward from `ft` with 0.5x (2.25px) trails
			detonate(PLAYER, ft, 6.0, 1.0)
			for m in 6:
				var ang := -PI * 0.85 + float(m) * (PI * 1.7 / 5.0)
				var sub_to := ft + Vector2.from_angle(ang) * (16.0 + float(m % 2) * 8.0)
				missiles.append({"o": PLAYER, "k": 9, "from": ft, "to": sub_to, "t": 13.5 + m * 0.7, "dur": 22.0, "r": float(NUKE_R[9]), "mirv": true, "branched": true})
			var rival_o := 2
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive: rival_o = id; break
			missiles.append({"o": rival_o, "k": 11, "from": ft + Vector2(-42, 16), "to": ft + Vector2(-4, 6), "t": 18.5, "dur": 25.0, "r": 36.0, "mirv": false, "branched": false})
			var b_center: Vector2 = tgt if tgt != Vector2.ZERO else (pc + Vector2(22, 6)) * TS
			blasts.append({"pos": b_center, "r": 16.0 * TS, "t": 0.32, "dur": 1.45, "seed": 424242})
			blasts.append({"pos": b_center + Vector2(36, -18) * TS, "r": 9.0 * TS, "t": 0.14, "dur": 1.45, "seed": 777111})
			print("fallout tiles ", fo, " missiles ", missiles.size(), " blasts ", blasts.size(), " notes ", notes.size())
			cam.zoom = Vector2(2.1, 2.1); cam.position = (pc * TS + b_center) * 0.5; _clamp_cam()
			overlay.queue_redraw()
		16: _shot("10_nukes_fallout_notes.png")
		17:
			print("ally card visible ", ally_card.visible, " notes ", notes.size(), " warships ", warships.size(), " traders ", traders.size(), " structs ", structs.size())
			_shot("11_alliance_card.png")
		18:
			save.unlocked = ["mega", "reinf", "air", "rail"]
			var n = nations[PLAYER]
			n.gold = 6e7
			var built := false
			for tries in 4000:
				var bb2: Rect2i = n.bb
				var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
				if try_build(14, ti): built = true; break
			var fired := 0
			for st in structs:
				if st.k == 14 and st.o == PLAYER:
					st.bt = 0.0
					if launch_sortie_legacy(st): fired += 1
			for pl in planes: pl.dur = 40.0; pl.t = 14.0
			var pc := Vector2(n.sx, n.sy) / maxf(1, n.land)
			var best := -1; var bd := 1e9
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 20:
					var dd := pc.distance_to(Vector2(nn.sx, nn.sy) / nn.land)
					if dd < bd: bd = dd; best = id
			for st in structs:
				if st.o == PLAYER and st.k == 5: st.cd = 0.0
			if best > 0:
				var nn = nations[best]
				print("railgun ok=", fire_railgun(PLAYER, int(nn.sy / nn.land) * W + int(nn.sx / nn.land)))
				for bm in beams: bm.t = -3.0
			print("airfield built ", built, " sorties ", fired, " planes ", planes.size())
			if not planes.is_empty():
				_focus_player(2.4)
		19: _shot("12_airstrike_railgun.png")
		20:
			# Showcase railways, moving gold trains, in-place Lv2/Lv3 upgrades, construction ring, and exponential price ladder
			var n = nations[PLAYER]
			n.gold = 9e7
			_claim_blob(PLAYER, int(n.sy / maxf(1, n.land)) * W + int(n.sx / maxf(1, n.land)), 26)
			for kk in [0, 2, 0, 2, 1, 3, 5, 4, 10]:
				if owned_count(PLAYER, kk) < (2 if kk in [0, 2] else 1):
					for tries in 3000:
						var bb2: Rect2i = n.bb
						var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
						if owner_map[ti] == PLAYER and not struct_at.has(ti) and try_build(kk, ti): break
			var upgraded := 0
			for st in structs:
				if st.o == PLAYER:
					st.bt = 0.0
					if st.k in [0, 2, 4, 5, 10]:
						try_build(st.k, st.tile)
						upgraded += 1
						if st.k in [0, 2] and upgraded <= 3:
							try_build(st.k, st.tile)
					st.bt = 0.0
			# Show one structure actively constructing with progress ring
			# Also guarantee one Factory -> coastal Port/City across water to showcase the straight steel bridge alongside curved land tracks
			var fac_st = null
			for st in structs:
				if st.o == PLAYER and st.k == 2: fac_st = st; break
			if fac_st != null:
				var fp := Vector2(fac_st.tile % W + 0.5, fac_st.tile / W + 0.5)
				for k_ang in 36:
					var ang := float(k_ang) * TAU / 36.0
					var w_seen := false
					for dist_r in range(8, 38):
						var p := fp + Vector2.from_angle(ang) * float(dist_r)
						var tx := int(p.x); var ty := int(p.y)
						if tx < 2 or ty < 2 or tx >= W - 2 or ty >= H - 2: break
						var ti := ty * W + tx
						if owner_map[ti] == WATER:
							w_seen = true
						elif w_seen and owner_map[ti] >= 0 and not struct_at.has(ti):
							var spans_chk := _water_crossing_spans(fp, Vector2(tx + 0.5, ty + 0.5))
							if spans_chk.size() == 1:
								_set_owner(ti, PLAYER)
								_struct_add(1, ti, PLAYER)
								struct_at[ti].bt = 0.0
								# Force a straight bridge entry in path_cache so it renders the steel bridge across the inlet
								var lo_b := mini(fac_st.tile, ti); var hi_b := maxi(fac_st.tile, ti)
								var lp0 := Vector2(lo_b % W + 0.5, lo_b / W + 0.5)
								var hp0 := Vector2(hi_b % W + 0.5, hi_b / W + 0.5)
								var sp0 := _water_crossing_spans(lp0, hp0)
								if sp0.size() >= 1:
									var b_s: Vector2 = sp0[0][0]; var b_e: Vector2 = sp0[0][1]
									var b_pts := PackedVector2Array([lp0, b_s, b_e, hp0])
									var b_cum := PackedFloat32Array([0.0])
									for m in range(1, b_pts.size()): b_cum.append(b_cum[m - 1] + b_pts[m].distance_to(b_pts[m - 1]))
									path_cache["r%d:%d" % [lo_b, hi_b]] = [b_pts, b_cum, [[b_s, b_e]]]
								break
					if path_cache.size() > 0:
						var has_br := false
						for ck in path_cache:
							if String(ck).begins_with("r") and path_cache[ck].size() >= 3 and path_cache[ck][2].size() > 0: has_br = true; break
						if has_br: break
			for st in structs:
				if st.o == PLAYER: st.bt = 0.0
			trains.clear()
			for st in structs:
				if st.o == PLAYER and st.k == 2:
					spawn_train_from(st)
					spawn_train_from(st)
			for st in structs:
				if st.o == PLAYER and st.k == 3:
					st.bt = 1.6; st.bmax = 5.0; break
			for m in trains.size():
				trains[m].dur = 10.0; trains[m].t = 3.0 + m * 2.2
			# Verify capturing enemy military infrastructure (SAM / Silo / Artillery) via land conquest
			var enemy_id := 2
			for id in range(2, nations.size()):
				if nations[id].alive: enemy_id = id; break
			var cap_tile := -1
			for tries in 500:
				var bb3: Rect2i = n.bb
				var ti := (bb3.position.y + rng.randi() % maxi(1, bb3.size.y)) * W + bb3.position.x + rng.randi() % maxi(1, bb3.size.x)
				if owner_map[ti] == PLAYER and not struct_at.has(ti):
					cap_tile = ti; break
			var cap_ok := false
			if cap_tile >= 0:
				owner_map[cap_tile] = enemy_id
				nations[PLAYER].land -= 1; nations[enemy_id].land += 1
				_struct_add(4, cap_tile, enemy_id)  # Enemy SAM Launcher Lv2
				struct_at[cap_tile].level = 2; struct_at[cap_tile].bt = 0.0; _sv += 1
				_set_owner(cap_tile, PLAYER)        # Player conquers tile -> claims SAM Launcher Lv2!
				cap_ok = struct_at.has(cap_tile) and struct_at[cap_tile].o == PLAYER
			var ppos := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			add_float(ppos + Vector2(18, -12), "+10K", GOLD_C)
			add_float(ppos + Vector2(-24, 10), "+35K", GOLD_C)
			_focus_player(2.6)
			_update_hud()
			overlay.queue_redraw()
			print("trains active ", trains.size(), " upgraded ", upgraded, " captured_enemy_struct=", cap_ok)
		21: _shot("16_trains_rails_upgrades.png")
		22:
			# Showcase 3-tier terrain, smooth frontlines, right-click Diplomacy & Embargo popup, and 42% peak growth indicator
			var n = nations[PLAYER]
			n.troops = troop_cap(PLAYER) * 0.42
			_update_hud()
			var target_id := -1
			for id in range(2, nations.size()):
				if nations[id].alive and is_prot(id):
					target_id = id; break
			if target_id < 0:
				for id in range(2, nations.size()):
					if nations[id].alive and nations[id].land > 15:
						target_id = id; break
			if target_id > 0:
				var tn = nations[target_id]
				var tc := Vector2(tn.sx / maxf(1, tn.land), tn.sy / maxf(1, tn.land)) * TS
				cam.zoom = Vector2(2.0, 2.0); cam.position = tc; _clamp_cam()
				_open_diplo(target_id, Vector2(820, 320))
			overlay.queue_redraw()
		23: _shot("17_diplomacy_embargo_terrain.png")
		24:
			if diplo_panel: diplo_panel.visible = false
			_open_settings()
		25:
			_shot("20_settings_graphics.png")
			settings_dlg.visible = false
			console_unlocked = false
			toggle_console()
			console_pass_in.text = "5516"
			_update_console_fps(0.0055)
		26:
			_shot("21_tab_locked_fps.png")
			unlock_console("5516")
			run_console_cmd("help")
			run_console_cmd("gold = 99999999")
			run_console_cmd("boat_speed = 6.0")
			run_console_cmd("NUKE_R[7] = 7")
			run_console_cmd("vars")
			print("tab console visible=", console_panel.visible, " unlocked=", console_unlocked)
		27:
			_shot("19_tab_console.png")
		28:
			if console_panel and console_panel.visible: toggle_console()
			stats.elims = maxi(stats.elims, 3)
			_game_over(true)
		29:
			print("stars after match ", save.stars)
			_shot("13_victory.png")
		30:
			end_dlg.visible = false
			_to_menu()
			save.stars = maxi(save.stars, 9000)
			if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
		31: _shot("14_menu_stars.png")
		32:
			_open_shop()
			# Test unlocking Artillery (2,500 stars) directly in the unified Shop/Stars modal
			var before_s: int = save.stars
			var u_ok := unlock_arsenal_item("art")
			print("shop unlock art ok=", u_ok, " stars ", before_s, " -> ", save.stars)
		33:
			_shot("15_arsenal.png")
			_shot("18_unified_shop.png")
			get_tree().quit()
	_step += 1

func _draw_overlay() -> void:
	var _dt0 := Time.get_ticks_usec()
	_draw_overlay_inner()
	var dus := Time.get_ticks_usec() - _dt0
	_pf_add("draw", dus)
	if _sfx_log and dus > 40000: print("SLOW draw %.0f ms" % (dus / 1000.0))

func _draw_overlay_inner() -> void:
	if state == "menu" or nations.size() < 2: return
	var f := ThemeDB.fallback_font
	var z := cam.zoom.x
	for id in range(1, nations.size()):
		var n = nations[id]
		if not n.alive or n.land < 4: continue
		var c: Vector2 = n.get("lp", Vector2(n.sx / n.land + 0.5, n.sy / n.land + 0.5) * TS)
		var sp := _screen_of(c)
		if sp.x < -100 or sp.y < -50 or sp.x > 1700 or sp.y > 950: continue
		var fs := int(float(n.get("ls", sqrt(float(n.land)))) * TS * z * 0.28)
		if fs < 8: continue
		fs = mini(fs, 64)
		var nm: String = n.name if id != PLAYER else "You"
		var w := 400.0
		f.draw_string_outline(overlay.get_canvas_item(), sp + Vector2(-w / 2, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(2, fs / 6), Color(1, 1, 1, 0.65))
		overlay.draw_string(f, sp + Vector2(-w / 2, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.08, 0.1, 0.16))
		overlay.draw_string(f, sp + Vector2(-w / 2, fs * 0.95), _fmt(n.troops), HORIZONTAL_ALIGNMENT_CENTER, w, int(fs * 0.8), Color(0.08, 0.1, 0.16, 0.85))
	# structures
	var _w0 := Time.get_ticks_usec()
	_draw_world_fx(z)
	_pf_add("wfx", Time.get_ticks_usec() - _w0)
	if build_sel >= 0:
		var mt := _mouse_tile()
		if mt >= 0:
			var ok: bool = build_req(build_sel, mt) == "" and nations[PLAYER].gold >= build_cost(PLAYER, build_sel)
			var mp := get_viewport().get_mouse_position()
			var rr := {3: sim_rules.defense_range, 4: sim_rules.sam_range(1), 10: sim_rules.artillery_range()}.get(build_sel, 0.0) as float
			if build_sel in NUKES: rr = float(NUKE_R[build_sel]) if build_sel != 12 else sim_rules.scatter_far()
			var strike_aim := _is_strike_click(build_sel, mt, PLAYER)
			if strike_aim: rr = sim_rules.strike_radius(SimRules.N_AIRSTRIKE if build_sel == 14 else SimRules.N_SLUG)
			if build_sel == 14:
				for st in structs:
					if st.o == PLAYER and st.k == 14 and st.get("bt", 0.0) <= 0.0:
						var spa := _screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)
						overlay.draw_arc(spa, sim_rules.airfield_range() * TS * z, 0, TAU, 96, Color(0.4, 0.8, 1.0, 0.7), 1.6, true)
			if rr > 0:
				var cc := Color(1, 0.3, 0.25) if (build_sel in NUKES or strike_aim) else Color(0.3, 0.6, 1)
				overlay.draw_circle(mp, rr * TS * z, Color(cc, 0.12))
				overlay.draw_arc(mp, rr * TS * z, 0, TAU, 64, Color(cc, 0.85), 2.0)
			if build_sel in NUKES:
				var tpw := Vector2(mt % W + 0.5, mt / W + 0.5)
				var inr := icbm_mode or not silo_for(PLAYER, build_sel, tpw).is_empty()
				if not icbm_mode:
					var rpx := nuke_range(build_sel) * TS * z
					for st in structs:
						if st.o == PLAYER and st.k == 5 and st.get("bt", 0.0) <= 0.0:
							var sp0 := _screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)
							overlay.draw_circle(sp0, rpx, Color(1, 0.55, 0.2, 0.06))
							overlay.draw_arc(sp0, rpx, 0, TAU, 128, Color(1, 0.6, 0.25, 0.9), 2.0, true)
				var tgt := _tex("ui_icons/target.png")
				if tgt: overlay.draw_texture_rect(tgt, Rect2(mp - Vector2(14, 14), Vector2(28, 28)), false, Color(1, 0.3, 0.25) if inr else Color(0.5, 0.5, 0.5, 0.8))
				var lbl := ("ICBM  +10%%  (%s)" % _fmt(nuke_cost(build_sel)) if icbm_mode else nuke_range_label(build_sel)) + ("" if inr else "  ·  OUT OF RANGE")
				overlay.draw_string(f_bold, mp + Vector2(18, -14), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.8, 0.5) if inr else Color(1, 0.4, 0.35))
			if build_sel == 2:
				for st in structs:
					if st.o == PLAYER and st.k == 2:
						var sp1 := _screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)
						overlay.draw_circle(sp1, FACTORY_RANGE * TS * z, Color(0.95, 0.85, 0.4, 0.06))
						overlay.draw_arc(sp1, FACTORY_RANGE * TS * z, 0, TAU, 96, Color(0.95, 0.85, 0.4, 0.8), 2.0, true)
				var spm := FACTORY_RANGE * TS * z
				overlay.draw_arc(mp, spm, 0, TAU, 96, Color(0.95, 0.85, 0.4, 0.55), 1.5, true)
			if build_sel in NUKES or strike_aim:
				overlay.draw_line(mp + Vector2(-10, 0), mp + Vector2(10, 0), Color(1, 0.3, 0.25), 2)
				overlay.draw_line(mp + Vector2(0, -10), mp + Vector2(0, 10), Color(1, 0.3, 0.25), 2)
			else:
				_map_icon(mp, build_sel, Color(0.3, 0.9, 0.4) if ok else Color(0.95, 0.3, 0.3), 0.8)
	# attack fronts: upstream FrontLayer.luau (plain stroked troop text on the local player's fronts)
	_fronts_draw()
	# boats with curved routes
	for bt in boats:
		var bp := _boat_pos(bt)
		var pts: PackedVector2Array = bt.pts
		var col: Color = nations[bt.a].color
		# no route line: the ship leaves a wake trail behind it instead
		var p0 := _screen_of(bp[0])
		if bt.get("air", false):
			_plane_glyph(p0, _sdir(bt, bp[1]), col, 1.0, false); continue
		_wake_trail(bt, bp[0], maxf(1.6, _ship_px() * 0.28))
		var dir: Vector2 = _sdir(bt, bp[1])
		var nrm := Vector2(-dir.y, dir.x)
		var sc := clampf(cam.zoom.x * 3.0, 5.0, 12.0)
		_wake(p0, dir, maxf(2.5, _ship_px() * 5.0 / 26.0))  # upstream: transports leave a wake (UnitLayer)
		if not _ship_sprite(p0, 0, col):
			var hull := PackedVector2Array([p0 + dir * sc, p0 + dir * sc * 0.2 + nrm * sc * 0.45, p0 - dir * sc * 0.8 + nrm * sc * 0.4, p0 - dir * sc * 0.8 - nrm * sc * 0.4, p0 + dir * sc * 0.2 - nrm * sc * 0.45])
			overlay.draw_colored_polygon(hull, col.darkened(0.3))
			overlay.draw_polyline(hull + PackedVector2Array([hull[0]]), Color(1, 1, 1, 0.9), 1.2)
		# upstream UnitLayer.luau draws no troop label on transport boats

func _icon(p: Vector2, k: int, col: Color, a: float, ci: CanvasItem = null, r := 11.0, bg := true) -> void:
	if ci == null: ci = overlay
	var u := r / 11.0
	var w := Color(1, 1, 1, a) if bg else Color(col, a)
	var dark := Color(0.1, 0.12, 0.2, a)
	if bg:
		ci.draw_circle(p, r + 2 * u, Color(1, 1, 1, a * 0.9))
		ci.draw_circle(p, r, Color(col.darkened(0.35), a))
	else:
		u *= 1.25
	if UI_TEX.has(k):
		var ut := _tex(UI_TEX[k])
		if ut != null:
			var s2 := r * (1.5 if bg else 1.7)
			ci.draw_texture_rect(ut, Rect2(p - Vector2(s2, s2) / 2, Vector2(s2, s2)), false, w)
			return
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in arr: out.append(p + v * u)
		return out
	match k:
		0:  # city: skyline
			ci.draw_rect(Rect2(p + Vector2(-7, -1) * u, Vector2(4, 7) * u), w)
			ci.draw_rect(Rect2(p + Vector2(-2, -7) * u, Vector2(4, 13) * u), w)
			ci.draw_rect(Rect2(p + Vector2(3, -3) * u, Vector2(4, 9) * u), w)
		1:  # port: mast + sail + wave
			ci.draw_line(p + Vector2(-1, -7) * u, p + Vector2(-1, 3) * u, w, 2 * u)
			ci.draw_colored_polygon(P.call([Vector2(0, -6), Vector2(6, 2), Vector2(0, 2)]), w)
			ci.draw_arc(p + Vector2(0, 1) * u, 6.5 * u, 0.35, PI - 0.35, 10, w, 2 * u)
		2:  # factory: saw roof + chimney
			ci.draw_colored_polygon(P.call([Vector2(-7, 6), Vector2(-7, -1), Vector2(-3, -4), Vector2(-3, -1), Vector2(1, -4), Vector2(1, -1), Vector2(7, -1), Vector2(7, 6)]), w)
			ci.draw_rect(Rect2(p + Vector2(4, -8) * u, Vector2(3, 7) * u), w)
		3:  # defense post: shield
			ci.draw_colored_polygon(P.call([Vector2(-6, -6), Vector2(6, -6), Vector2(6, 0), Vector2(0, 7), Vector2(-6, 0)]), w)
			ci.draw_line(p + Vector2(0, -5) * u, p + Vector2(0, 5) * u, dark, 2 * u)
		4:  # SAM: interceptor on launcher
			ci.draw_colored_polygon(P.call([Vector2(0, -8), Vector2(2.5, -3), Vector2(2.5, 3), Vector2(-2.5, 3), Vector2(-2.5, -3)]), w)
			ci.draw_rect(Rect2(p + Vector2(-6, 4) * u, Vector2(12, 3) * u), w)
		5:  # silo: dome over shaft
			ci.draw_arc(p + Vector2(0, 1) * u, 6 * u, PI, TAU, 12, w, 2 * u)
			ci.draw_rect(Rect2(p + Vector2(-6, 1) * u, Vector2(12, 5) * u), w)
			ci.draw_line(p + Vector2(0, -3) * u, p + Vector2(0, 4) * u, dark, 2 * u)
		6:  # warship: hull + tower
			ci.draw_colored_polygon(P.call([Vector2(-8, 1), Vector2(8, 1), Vector2(5, 5), Vector2(-6, 5)]), w)
			ci.draw_rect(Rect2(p + Vector2(-2, -5) * u, Vector2(5, 6) * u), w)
			ci.draw_line(p + Vector2(3, -3) * u, p + Vector2(8, -4) * u, w, 1.5 * u)
		7:  # atom bomb: core + orbit
			ci.draw_circle(p, 3 * u, w)
			ci.draw_arc(p, 7 * u, 0, TAU, 20, w, 1.5 * u)
		8:  # hydrogen bomb: core + two orbits
			ci.draw_circle(p, 2.5 * u, w)
			ci.draw_arc(p, 5 * u, 0, TAU, 16, w, 1.2 * u)
			ci.draw_arc(p, 8 * u, 0, TAU, 20, w, 1.2 * u)
		9:  # MIRV: three warheads
			for dx in [-5, 0, 5]:
				ci.draw_colored_polygon(P.call([Vector2(dx, -6 + absi(dx) * 0.4), Vector2(dx + 2, 0), Vector2(dx - 2, 0)]), w)
			ci.draw_line(p + Vector2(-6, 4) * u, p + Vector2(6, 4) * u, w, 1.5 * u)
		10:  # artillery: barrel + wheel
			ci.draw_line(p + Vector2(-5, 3) * u, p + Vector2(7, -5) * u, w, 3 * u)
			ci.draw_circle(p + Vector2(-2, 4) * u, 3 * u, w)
		11:  # mega nuke: big core, thick ring
			ci.draw_circle(p, 4.5 * u, w)
			ci.draw_arc(p, 8 * u, 0, TAU, 24, w, 2.5 * u)
		12:  # scattershot: center + five satellites
			ci.draw_circle(p, 3 * u, w)
			for m in 5:
				ci.draw_circle(p + Vector2.from_angle(m * TAU / 5 - PI / 2) * 7 * u, 1.6 * u, w)
		13:  # reinforcements: plus + chevron
			ci.draw_rect(Rect2(p + Vector2(-1.5, -7) * u, Vector2(3, 10) * u), w)
			ci.draw_rect(Rect2(p + Vector2(-5, -3.5) * u, Vector2(10, 3) * u), w)
			ci.draw_polyline(P.call([Vector2(-5, 7), Vector2(0, 4), Vector2(5, 7)]), w, 1.5 * u)
		14:  # airfield: little plane
			ci.draw_colored_polygon(P.call([Vector2(0, -8), Vector2(1.5, -3), Vector2(8, 1), Vector2(8, 3), Vector2(1.5, 1), Vector2(1, 5), Vector2(3.5, 7), Vector2(-3.5, 7), Vector2(-1, 5), Vector2(-1.5, 1), Vector2(-8, 3), Vector2(-8, 1), Vector2(-1.5, -3)]), w)
		15:  # railgun: twin rails + bolt
			ci.draw_line(p + Vector2(-7, 5) * u, p + Vector2(5, -7) * u, w, 1.8 * u)
			ci.draw_line(p + Vector2(-5, 7) * u, p + Vector2(7, -5) * u, w, 1.8 * u)
			ci.draw_circle(p + Vector2(7, -7) * u, 2 * u, w)
		_:
			ci.draw_circle(p, 4 * u, w)

func _front_now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _fronts_clusters(tiles: Array, min_size: float) -> Array:
	var in_set := {}
	for t in tiles: in_set[t] = true
	var seen := {}
	var out := []
	for start in tiles:
		if seen.has(start): continue
		seen[start] = true
		var members := [start]
		var head := 0
		var sx := 0.0
		var sy := 0.0
		while head < members.size():
			var t: int = members[head]; head += 1
			var x := t % W
			var y := t / W
			sx += x; sy += y
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0: continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= W or ny < 0 or ny >= H: continue
					var n: int = ny * W + nx
					if in_set.has(n) and not seen.has(n):
						seen[n] = true; members.append(n)
		var cx := sx / members.size()
		var cy := sy / members.size()
		var best: int = members[0]
		var bd := INF
		for t in members:
			var d := pow(t % W - cx, 2) + pow(t / W - cy, 2)
			if d < bd: bd = d; best = t
		out.append({"size": members.size(), "x": best % W, "y": best / W})
	out.sort_custom(func(a, b): return a.size > b.size)
	var kept := []
	for c in out:
		if kept.size() >= FRONT_MAX_CLUSTERS: break
		if kept.is_empty() or c.size >= min_size: kept.append(c)
	return kept

func _fronts_set_slots(e: Dictionary, pts: Array, now: float, snap: float) -> void:
	var olds: Array = e.slots
	# two labels: keep each where it is closest (swap the pairing if that is shorter)
	if olds.size() == 2 and pts.size() == 2:
		var c0: Vector2 = _front_cur(olds[0], now)
		var c1: Vector2 = _front_cur(olds[1], now)
		var p0 := Vector2(pts[0].x, pts[0].y)
		var p1 := Vector2(pts[1].x, pts[1].y)
		if c0.distance_to(p1) + c1.distance_to(p0) < c0.distance_to(p0) + c1.distance_to(p1):
			pts = [pts[1], pts[0]]
	var slots := []
	for i in pts.size():
		var dst := Vector2(pts[i].x, pts[i].y)
		if i < olds.size():
			var cur: Vector2 = _front_cur(olds[i], now)
			var old_dst := Vector2(olds[i].dx, olds[i].dy)
			if old_dst == dst:
				slots.append(olds[i]); continue
			if cur.distance_to(dst) > snap: cur = dst
			slots.append({"sx": cur.x, "sy": cur.y, "dx": dst.x, "dy": dst.y, "t0": now})
		else:
			slots.append({"sx": dst.x, "sy": dst.y, "dx": dst.x, "dy": dst.y, "t0": now})
	e.slots = slots

func _front_cur(sl: Dictionary, now: float) -> Vector2:
	var f := clampf((now - float(sl.t0)) / FRONT_ANIM_S, 0.0, 1.0)
	return Vector2(sl.sx, sl.sy).lerp(Vector2(sl.dx, sl.dy), f)

func _fronts_poll(now: float) -> void:
	if state != "play" or nations.size() <= PLAYER or border.size() <= PLAYER or nations[PLAYER].land <= 0:
		_front_entries.clear(); return
	var todo := {}  # aid -> [other owner, incoming, troops]
	var wanted := {}
	for at in attacks:
		if at.get("dead", false): continue
		var aid: int = int(at.get("aid", -1))
		if at.a == PLAYER and at.t > 0:
			todo[aid] = [int(at.t), false, float(at.troops)]; wanted[int(at.t)] = true
		elif at.t == PLAYER and at.a > 0 and kind_of(at.a) != SimRules.KIND_TRIBE:
			todo[aid] = [int(at.a), true, float(at.troops)]; wanted[int(at.a)] = true
	for aid in _front_entries.keys():
		if not todo.has(aid): _front_entries.erase(aid)
	if todo.is_empty(): return
	# fronts_by_owner: our border tiles with a 4-neighbour owned by a wanted owner (first hit counts)
	var fronts := {}
	for t in border[PLAYER]:
		var x: int = t % W
		var hit := -1
		if x > 0 and wanted.has(owner_map[t - 1]): hit = owner_map[t - 1]
		elif x < W - 1 and wanted.has(owner_map[t + 1]): hit = owner_map[t + 1]
		elif t >= W and wanted.has(owner_map[t - W]): hit = owner_map[t - W]
		elif t + W < W * H and wanted.has(owner_map[t + W]): hit = owner_map[t + W]
		if hit > 0:
			if not fronts.has(hit): fronts[hit] = []
			fronts[hit].append(t)
	var k: float = sim_rules.k_lin
	var clusters := {}
	for aid in todo:
		var oid: int = todo[aid][0]
		if not fronts.has(oid): _front_entries.erase(aid); continue
		if not clusters.has(oid): clusters[oid] = _fronts_clusters(fronts[oid], FRONT_MIN_CLUSTER_FULL / k)
		var pts: Array = clusters[oid]
		if pts.is_empty(): _front_entries.erase(aid); continue
		var e: Dictionary = _front_entries.get(aid, {"slots": []})
		e.text = _fmt(todo[aid][2])
		e.incoming = todo[aid][1]
		_fronts_set_slots(e, pts, now, FRONT_SNAP_FULL / k)
		_front_entries[aid] = e

func _fronts_draw() -> void:
	var now := _front_now()
	if now >= _front_next:
		_front_next = now + FRONT_POLL_S
		_fronts_poll(now)
	if _front_entries.is_empty(): return
	var ds: float = hud._device_scale() if hud and hud.has_method("_device_scale") else 1.0
	var fs := maxi(1, int(round(FRONT_TEXT_PX / ds)))
	var stroke := maxi(1, int(round(FRONT_STROKE_PX * 2.0 / ds)))
	var f: Font = RK.font(700)
	var vs := overlay.size
	for aid in _front_entries:
		var e: Dictionary = _front_entries[aid]
		var col: Color = FRONT_IN if e.incoming else FRONT_OUT
		var ts := f.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		for sl in e.slots:
			var c := _front_cur(sl, now)
			var sp := _screen_of((c + Vector2(0.5, 0.5)) * TS)
			if sp.x < -40 or sp.y < -40 or sp.x > vs.x + 40 or sp.y > vs.y + 40: continue
			var pos := Vector2(sp.x - ts.x * 0.5, sp.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
			overlay.draw_string_outline(f, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, stroke, Color.BLACK)
			overlay.draw_string(f, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _badge(p: Vector2, t: String, col: Color, left: bool, center := false) -> void:
	var f := ThemeDB.fallback_font
	var fs := 14
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var x := p.x - sz.x / 2 - 5 if center else (p.x - sz.x - 10 if left else p.x)
	var r := Rect2(Vector2(x, p.y - sz.y + 2), sz + Vector2(10, 4))
	overlay.draw_rect(r, col)
	overlay.draw_string(f, Vector2(x + 5, p.y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _pan(dt: float) -> void:
	if console_panel != null and console_panel.visible: return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	cam.position += v * 900.0 * dt / cam.zoom.x
	_clamp_cam()

func _clamp_cam() -> void:
	var half := get_viewport_rect().size / cam.zoom / 2.0
	var m := Vector2(W, H) * TS
	# map bounds incl. Antarctica: only enough slack (screen px) that the top bar / bottom command bar
	# don't hide the first and last rows; never past the map edge by more than that
	var lo := half - Vector2(24, 64) / cam.zoom
	var hi := m - half + Vector2(24, 128) / cam.zoom
	cam.position.x = clampf(cam.position.x, lo.x, hi.x) if lo.x < hi.x else m.x / 2
	cam.position.y = clampf(cam.position.y, lo.y, hi.y) if lo.y < hi.y else m.y / 2

func _zoom_at(f: float, screen: Vector2) -> void:
	var before := get_global_mouse_position()
	cam.zoom = (cam.zoom * f).clamp(Vector2(0.6, 0.6), Vector2(12, 12))
	cam.force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen
	cam.position += before - after
	_clamp_cam()

func _screen_of(world: Vector2) -> Vector2:
	return get_canvas_transform() * world

func _mouse_tile() -> int:
	var p := get_global_mouse_position() / TS
	var x := int(floor(p.x)); var y := int(floor(p.y))
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return y * W + x

func _attack_at_cursor() -> void:
	var t := _mouse_tile()
	if t < 0: return
	var o: int = owner_map[t]
	if o < 0 or o == PLAYER: return
	# Once your country touches someone else's land, it must ONLY be raided via land; if there is NO land border, use ships!
	if o > 0:
		if _shares_land_border(PLAYER, o):
			launch_attack(PLAYER, o, SHARES[share_i])
		else:
			launch_boat(PLAYER, t, SHARES[share_i])
	else:
		if _shares_land_border(PLAYER, NEUTRAL, t):
			launch_attack(PLAYER, NEUTRAL, SHARES[share_i])
		else:
			launch_boat(PLAYER, t, SHARES[share_i])

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.15, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.15, e.position)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if e.pressed:
				lpress = true; dragging = false; drag_from = e.position
			else:
				if lpress and not dragging and e.button_index == MOUSE_BUTTON_LEFT:
					if state == "pick":
						_place_start(_mouse_tile())
					elif state == "play":
						if build_sel >= 0: try_build(build_sel, _mouse_tile())
						elif _warship_click(): pass
						else: _attack_at_cursor()
				elif lpress and not dragging and e.button_index == MOUSE_BUTTON_RIGHT:
					if build_sel >= 0: build_sel = -1
					elif sel_ws != null: sel_ws = null
					elif state == "play": _right_click()
				lpress = false; dragging = false
	if e is InputEventMouseMotion and lpress:
		if dragging or e.position.distance_to(drag_from) > 6:
			dragging = true
			cam.position -= e.relative / cam.zoom.x
			_clamp_cam()
	if console_panel != null and console_panel.visible and e is InputEventKey:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q: _set_share(share_i - 1)
			KEY_E: _set_share(share_i + 1)
			KEY_SPACE: if state == "play": _attack_at_cursor()
			KEY_BACKSPACE:
				for k in range(attacks.size() - 1, -1, -1):
					if attacks[k].a == PLAYER:
						retreat(attacks[k]); break
			KEY_TAB: toggle_console()
			KEY_I: if state == "play": set_icbm(not icbm_mode)
			KEY_H: help_panel.visible = not help_panel.visible
			KEY_ESCAPE:
				if arsenal_dlg != null and arsenal_dlg.visible: _close_shop()
				elif hud != null and hud.menu_open(): hud.close_menu()
				elif build_sel >= 0: build_sel = -1
				elif sel_ws != null: sel_ws = null
				elif hud != null and (state == "play" or state == "pick"): hud.open_menu()
				else: _to_menu()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				select_build(e.keycode - KEY_1)
			KEY_0: select_build(9)
			KEY_R: select_build(13)
			KEY_MINUS, KEY_KP_SUBTRACT: set_speed_x(sim_speed / SPEED_BASE - 0.5)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: set_speed_x(sim_speed / SPEED_BASE + 0.5)
