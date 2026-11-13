extends "res://game/state.gd"
# Map generation, rendering data, tiles and ownership

func _ready() -> void:
	autoshot = "--autoshot" in OS.get_cmdline_user_args()
	_sfx_log = "--sfxlog" in OS.get_cmdline_user_args()
	bench = "--bench" in OS.get_cmdline_user_args()
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--pace="): _pace = {"init": true}
	rng.randomize()
	if autoshot or bench: save_path = "user://save_test.json"
	Engine.max_fps = 180
	load_save()
	RenderingServer.set_default_clear_color(Color(0.20, 0.42, 0.62))
	if autoshot: Engine.time_scale = 4.0
	# map split into chunk textures; only dirty chunks are uploaded each frame
	for cy in H / CH:
		for cx in W / CW:
			var im := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
			var tx := ImageTexture.create_from_image(im)
			var sp := Sprite2D.new(); sp.texture = tx; sp.centered = false
			sp.scale = Vector2(TS, TS); sp.position = Vector2(cx * CW, cy * CH) * TS
			sp.material = _map_material()
			add_child(sp)
			chunk_img.append(im); chunk_tex.append(tx); chunk_sp.append(sp)
	chunk_dirty.resize(chunk_img.size()); chunk_dirty.fill(0)
	cam = Camera2D.new()
	add_child(cam)
	cam.position = Vector2(W, H) * TS / 2
	cam.zoom = Vector2(1.2, 1.2)
	_build_ui()
	set_icbm(bool(save.get("settings", {}).get("icbm", false)))
	ui.layer = 2
	var ol := CanvasLayer.new(); ol.layer = 1; add_child(ol)
	overlay = Control.new(); overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ol.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots_dir = a.substr(8)
	gen_map()
	sim_atk = SimAttacks.new(self, sim_rules)
	sim_ai = SimAI.new(self, sim_rules)
	sim_struct = SimStructures.new(self, sim_rules)
	sim_ars = SimArsenal.new(self, sim_rules)
	sim_ws = SimWarships.new(self, sim_rules)
	apply_settings(false)
	_init_audio()
	if "--maptest" in OS.get_cmdline_user_args(): _maptest.call_deferred()
	if "--rangetest" in OS.get_cmdline_user_args(): _rangetest.call_deferred()
	if "--rangetest2" in OS.get_cmdline_user_args(): _rangetest2.call_deferred()
	if "--idletest" in OS.get_cmdline_user_args(): _idletest.call_deferred()
	if "--bordershot" in OS.get_cmdline_user_args(): _bordershot.call_deferred()
	if "--stress" in OS.get_cmdline_user_args(): _stress.call_deferred()
	if "--hudshot" in OS.get_cmdline_user_args(): _hudshot.call_deferred()
	if "--uishot" in OS.get_cmdline_user_args(): _uishot.call_deferred()
	if "--dmgshot" in OS.get_cmdline_user_args(): _dmgshot.call_deferred()
	if "--shipshot" in OS.get_cmdline_user_args(): _shipshot.call_deferred()
	if "--audiotest" in OS.get_cmdline_user_args(): _audiotest.call_deferred()
	if "--regress" in OS.get_cmdline_user_args(): _regress.call_deferred()
	if "--porttest" in OS.get_cmdline_user_args(): _porttest.call_deferred()
	if "--portshot" in OS.get_cmdline_user_args(): _portshot.call_deferred()
	if "--speedshot" in OS.get_cmdline_user_args(): _speedshot.call_deferred()

func _map_material() -> ShaderMaterial:
	if map_mat == null:
		var sh := Shader.new(); sh.code = MAP_SHADER
		map_mat = ShaderMaterial.new(); map_mat.shader = sh
	return map_mat

func _sample_map_elev(k: int, x: float, y: float, n: FastNoiseLite, n2: FastNoiseLite, pa := INF, pb := INF) -> float:
	var m = MAPS[clampi(k, 0, MAPS.size() - 1)]
	var dx := (x - W / 2.0) / (W / 2.0)
	var dy := (y - H / 2.0) / (H / 2.0)
	var r2 := dx * dx + dy * dy
	var nx := x * 640.0 / W; var ny := y * 640.0 / W
	var va: float = pa if pa != INF else n.get_noise_2d(nx, ny)
	var vb: float = pb if pb != INF else n2.get_noise_2d(nx, ny)
	var nv: float = va + vb * (0.08 + float(m[2]))
	var shape := 0.25 - 0.35 * r2 - float(m[2])
	match k:
		1:  # Twin Continents: West & East landmasses separated by a central strait
			var d1 := (dx + 0.48) * (dx + 0.48) * 1.8 + dy * dy * 1.1
			var d2 := (dx - 0.48) * (dx - 0.48) * 1.8 + dy * dy * 1.1
			shape = 0.30 - minf(d1, d2) * 0.52 - exp(-dx * dx * 32.0) * 0.28
		2:  # Shattered Sea: Archipelago of island chains
			shape = 0.14 - 0.26 * r2 + 0.18 * sin(dx * 7.5) * cos(dy * 6.5)
		3:  # World Continents: Americas left, Eurasia + Africa right
			var amer := exp(-pow((dx + 0.52 + 0.12 * dy) / 0.26, 2.0) - pow(dy / 0.78, 2.0)) * 0.58
			var eura := exp(-pow((dx - 0.36) / 0.46, 2.0) - pow((dy + 0.26) / 0.48, 2.0)) * 0.62
			var afri := exp(-pow((dx - 0.14) / 0.24, 2.0) - pow((dy - 0.34) / 0.44, 2.0)) * 0.56
			var austr := exp(-pow((dx - 0.66) / 0.18, 2.0) - pow((dy - 0.55) / 0.20, 2.0)) * 0.48
			shape = maxf(maxf(amer, eura), maxf(afri, austr)) - 0.30 - 0.12 * r2
		4:  # Mediterranean: Land ring around a central elongated sea with peninsulas
			var sea := exp(-pow(dx / 0.68, 2.0) - pow((dy - 0.05) / 0.34, 2.0)) * 0.62
			var italy := exp(-pow((dx + 0.05 - dy * 0.3) / 0.09, 2.0) - pow((dy + 0.08) / 0.28, 2.0)) * 0.46
			var greece := exp(-pow((dx - 0.28) / 0.10, 2.0) - pow((dy + 0.06) / 0.25, 2.0)) * 0.42
			shape = 0.34 - sea + maxf(italy, greece) - 0.18 * r2
		5:  # Europe & Isles: Mainland south/east, Scandinavia north, British Isles west
			var main_eu := clampf((dx + 0.35) * 0.5 + (dy - 0.05) * 0.6, -0.3, 0.42)
			var scand := exp(-pow((dx - 0.05) / 0.24, 2.0) - pow((dy + 0.55) / 0.28, 2.0)) * 0.52
			var uk := exp(-pow((dx + 0.55) / 0.16, 2.0) - pow((dy + 0.12) / 0.26, 2.0)) * 0.48
			shape = maxf(main_eu, maxf(scand, uk)) - 0.08 - 0.22 * r2
		6:  # East Asia & Arc: Continental mainland west + curved island arc east
			var main_as := clampf(0.28 - (dx + 0.18) * 0.75, -0.4, 0.38) - 0.22 * dy * dy
			var arc_r := sqrt(pow(dx + 0.15, 2.0) + pow(dy, 2.0))
			var jpn := exp(-pow((arc_r - 0.72) / 0.11, 2.0)) * (0.52 if dx > 0.1 else 0.0)
			shape = maxf(main_as, jpn) - 0.04
		7:  # North America: Wide north tapering to southern isthmus + Gulf
			var width_y := 0.58 - 0.28 * (dy + 0.2)
			var cont := 0.36 - pow(dx / maxf(0.18, width_y), 2.0) * 0.32 - 0.18 * dy * dy
			var gulf := exp(-pow((dx - 0.12) / 0.24, 2.0) - pow((dy - 0.45) / 0.25, 2.0)) * 0.52
			shape = cont - gulf
		8:  # Middle East Crossroads: Landmass cut by Red Sea, Persian Gulf & Mediterranean edge
			var red_sea := exp(-pow((dx + 0.28 - dy * 0.35) / 0.09, 2.0) - pow((dy - 0.22) / 0.48, 2.0)) * 0.58
			var gulf2 := exp(-pow((dx - 0.25 - dy * 0.30) / 0.11, 2.0) - pow((dy - 0.10) / 0.32, 2.0)) * 0.54
			var med_w := exp(-pow((dx + 0.75) / 0.32, 2.0) - pow((dy + 0.25) / 0.42, 2.0)) * 0.55
			shape = 0.32 - red_sea - gulf2 - med_w - 0.14 * r2
		9:  # Ring Atoll: Circular ring continent around a lagoon with a central island
			var rad := sqrt(dx * dx * 0.85 + dy * dy * 1.15)
			var ring := exp(-pow((rad - 0.58) / 0.22, 2.0)) * 0.54
			var center_isle := exp(-pow(rad / 0.16, 2.0)) * 0.46
			shape = maxf(ring, center_isle) - 0.22
		10: # Inland Sea: Continent enclosing a deep inner sea with narrow straits
			var rad2 := sqrt(dx * dx * 0.75 + dy * dy * 1.1)
			var inner_sea := exp(-pow(rad2 / 0.42, 2.0)) * 0.62
			shape = 0.38 - 0.28 * r2 - inner_sea
		11: # Four Corners: 4 continents separated by a cross channel + central hub
			var ch_x := exp(-dx * dx * 38.0) * 0.44
			var ch_y := exp(-dy * dy * 28.0) * 0.44
			var hub := exp(-(dx * dx + dy * dy) * 26.0) * 0.55
			shape = 0.34 - maxf(ch_x, ch_y) + hub - 0.16 * r2
	return nv + shape

func _upstream_menu() -> Array:
	if _up_menu.is_empty(): _up_menu = UpstreamMaps.menu_entries()
	return _up_menu
func _real_map(k: int) -> Dictionary:
	if map_tab == 2: return UpstreamMaps.real_map_at(k)
	if map_tab == 0 and k == 0: return UpstreamMaps.as_real_map("world")  # World with Antarctica + 3 aq spawns
	if RW_MAP_FOR.has(k): return RealMaps.MAPS[RW_MAP_FOR[k]]
	return {}

func kind_of(id: int) -> int:
	if id < _kind_cache.size(): return _kind_cache[id]
	if id == PLAYER: return SimRules.KIND_HUMAN
	if id > 0 and id < nations.size() and nations[id].get("prot", false): return SimRules.KIND_NATION
	return SimRules.KIND_TRIBE

func _rebuild_kind_cache() -> void:
	_kind_cache.resize(0)
	var kc := PackedInt32Array(); kc.resize(nations.size())
	for id in nations.size(): kc[id] = kind_of(id)
	_kind_cache = kc

# Source intent_attack: attack the owner of `tile` with `ratio` of home troops; over land when the
# attacker borders it, otherwise by transport.
func intent_attack(id: int, tile: int, ratio: float) -> bool:
	if tile < 0 or tile >= W * H: return false
	var o := owner_map[tile]
	if o < 0 or o == id: return false
	if o > 0 and _adj_any(tile, id):
		return launch_attack(id, o, ratio)
	if o == NEUTRAL and _adj_any(tile, id):
		return launch_attack(id, NEUTRAL, ratio)
	return launch_boat(id, tile, ratio if id == PLAYER else SimRules.BOAT_ATTACK_FRACTION, 12000)

func _adj_any(tile: int, id: int) -> bool:
	return _adj_to(tile, id) or owner_map[tile] == id

func _get_handcrafted_map_bytes(k: int) -> PackedByteArray:
	if map_tab == 2: return UpstreamMaps.codes_at(k)
	var idx := clampi(k, 0, HANDCRAFTED_MAPS.size() - 1)
	if _cached_map_bytes.has(idx):
		return _cached_map_bytes[idx]
	var rm := _real_map(idx)
	if not rm.is_empty():
		_cached_map_bytes[idx] = Marshalls.base64_to_raw(rm.b64).decompress(W * H, FileAccess.COMPRESSION_DEFLATE)
		return _cached_map_bytes[idx]
	var comp := Marshalls.base64_to_raw(HANDCRAFTED_MAPS[idx])
	var raw := comp.decompress(W * H, FileAccess.COMPRESSION_DEFLATE)
	_cached_map_bytes[idx] = raw
	return raw

func _map_sub(k: int, tab: int) -> String:
	var rm := _real_map(k) if tab != 1 else {}
	if tab == 2 and not rm.is_empty():
		return "RoWorld map  ·  %d nations + %d tribes" % [rm.nations.size(), SimRules.DEFAULT_TRIBES]
	if not rm.is_empty() and rm.nations.is_empty():
		return "Real map  ·  ~40 nations + %d tribes" % SimRules.DEFAULT_TRIBES
	if not rm.is_empty():
		return "Real map  ·  %d nations + %d tribes" % [rm.nations.size(), SimRules.DEFAULT_TRIBES]
	return "%d × %d  ·  ~40 nations + %d tribes" % [W, H, SimRules.DEFAULT_TRIBES]

func _active_map_entry(k: int) -> Array:
	var tbl: Array = _upstream_menu() if map_tab == 2 else (RANDOM_MAPS if map_tab == 1 else MAPS)
	return tbl[clampi(k, 0, tbl.size() - 1)]

func _store_gen_cache() -> void:
	_gen_cache = {"key": "%d|%d|%d|%d" % [map_tab, map_i, (rand_seed_off if map_tab == 1 else 0), _qual()],
		"om": owner_map.duplicate(), "el": elev_map, "mt": mtn.duplicate(), "cd": coast_dist, "bc": base_col,
		"lt": land_total, "body": sim_naval.body, "cl": sim_naval.coast_list, "nav": sim_nav}
func _gt(lbl: String) -> void:
	var t := Time.get_ticks_usec()
	if "--maptest" in OS.get_cmdline_user_args() and _gt_t > 0: print("  phase %s %.0f ms" % [lbl, (t - _gt_t) / 1000.0])
	_gt_t = t

func gen_map() -> void:
	_gt_t = Time.get_ticks_usec()
	var m := _active_map_entry(map_i)
	var seed_val: int = int(m[1]) + (rand_seed_off if map_tab == 1 else 0)
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = 0.006
	n.fractal_octaves = 6
	var n2 := FastNoiseLite.new()
	n2.seed = seed_val + 7
	n2.frequency = 0.025
	var n3 := FastNoiseLite.new()
	n3.seed = seed_val + 99
	n3.frequency = 0.04
	n3.fractal_octaves = 3
	owner_map.resize(W * H)
	base_col.resize(W * H)
	mtn.resize(W * H); mtn.fill(0)
	fallout.resize(W * H); fallout.fill(0); fallout_list.clear()
	fallout_t.resize(W * H); fallout_t.fill(0.0)
	var elev := PackedFloat32Array(); elev.resize(W * H)
	land_total = 0; _land_w = -1.0
	var raw_bytes := _get_handcrafted_map_bytes(map_i) if map_tab != 1 else PackedByteArray()
	var rmap := _real_map(map_i) if map_tab != 1 else {}
	snow_src = raw_bytes
	sim_rules.tile_norm = TILE_NORM
	sim_rules.set_k(float(rmap.k_lin) if not rmap.is_empty() else DEFAULT_K_LIN)
	real_nations = rmap.nations if not rmap.is_empty() else []
	var gkey := "%d|%d|%d|%d" % [map_tab, map_i, (rand_seed_off if map_tab == 1 else 0), _qual()]
	if _gen_cache.get("key", "") == gkey:
		owner_map = _gen_cache.om.duplicate(); elev_map = _gen_cache.el; mtn = _gen_cache.mt.duplicate()
		coast_dist = _gen_cache.cd; base_col = _gen_cache.bc; land_total = _gen_cache.lt
		if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
		sim_naval.body = _gen_cache.body; sim_naval.coast_list = _gen_cache.cl; sim_naval.trade_cache.clear()
		sim_nav = _gen_cache.get("nav", null)
		if sim_nav == null or not sim_nav.ready: sim_nav = SimNavS.new(); sim_nav.build(sim_naval.body, W, H)
		_gt("cache")
		if _async_gen: await get_tree().process_frame
		_redraw_all()
		_gt("redraw")
		return
	if map_tab != 1 and raw_bytes.size() == W * H:
		var jimg := n3.get_image(W, H, false, false, false).get_data()  # L8, noise*0.5+0.5
		for i in W * H:
			var code: int = raw_bytes[i]
			if code == 0:
				owner_map[i] = WATER
				elev[i] = -0.2
			else:
				owner_map[i] = NEUTRAL
				land_total += 1
				var jitter: float = (jimg[i] / 127.5 - 1.0) * 0.04
				if code == 4:  # snow: exactly plains for movement/conquest/spawns/building
					mtn[i] = 0; elev[i] = 0.10 + jitter
				elif code >= 3:
					mtn[i] = 2; elev[i] = 0.50 + jitter
				elif code == 2:
					mtn[i] = 1; elev[i] = 0.28 + jitter
				else:
					mtn[i] = 0; elev[i] = 0.10 + jitter
	else:
		# shape evaluated on a 1/4-res grid (normalised coords, same as the thumbnails), upscaled
		# bicubically in C++, plus fine C++ noise for coastline detail at full resolution
		var lw := W / 4; var lh := H / 4
		var lo := PackedFloat32Array(); lo.resize(lw * lh)
		for ly in lh:
			for lx in lw:
				lo[ly * lw + lx] = _sample_map_elev(map_i, (lx + 0.5) * 4.0, (ly + 0.5) * 4.0, n, n2)
			if _async_gen and (ly & 3) == 3:
				_load_progress(0.08 + 0.16 * float(ly) / float(lh))
				await get_tree().process_frame
		var limg := Image.create_from_data(lw, lh, false, Image.FORMAT_RF, lo.to_byte_array())
		limg.resize(W, H, Image.INTERPOLATE_CUBIC)
		var full := limg.get_data().to_float32_array()
		var nf := FastNoiseLite.new(); nf.seed = seed_val + 31; nf.frequency = 0.05; nf.fractal_octaves = 3
		var fimg := nf.get_image(W, H, false, false, false).get_data()
		for y in H:
			var row := y * W
			for x in W:
				var ii := row + x
				var v: float = full[ii] + (fimg[ii] / 127.5 - 1.0) * 0.035
				var o := NEUTRAL if v > 0.0 else WATER
				owner_map[ii] = o
				elev[ii] = v
				if o == NEUTRAL:
					if v > 0.40: mtn[ii] = 2
					elif v > 0.20: mtn[ii] = 1
					land_total += 1
			if _async_gen and (y & 31) == 31:
				_load_progress(0.26 + 0.04 * float(y) / float(H))
				await get_tree().process_frame
	elev_map = elev
	_gt("decode")
	if _async_gen: _load_progress(0.3); await get_tree().process_frame
	# distance to land / water (for coast glow & beaches)
	coast_dist.resize(W * H); coast_dist.fill(99)
	var q := PackedInt32Array(); q.resize(W * H); var qn := 0
	var N := W * H
	var dirs := PackedInt32Array([1, -1, W, -W])
	for i in N:
		if owner_map[i] != WATER:
			for d in dirs:
				var j: int = i + d
				if j >= 0 and j < N and owner_map[j] == WATER and coast_dist[j] == 99:
					coast_dist[j] = 1; q[qn] = j; qn += 1
	var qi := 0
	while qi < qn:
		var i: int = q[qi]; qi += 1
		var cd: int = coast_dist[i]
		if cd >= 12: continue
		for d in dirs:
			var j: int = i + d
			if j >= 0 and j < N and owner_map[j] == WATER and coast_dist[j] == 99:
				coast_dist[j] = cd + 1; q[qn] = j; qn += 1
	_gt("coast")
	if _async_gen: _load_progress(0.45); await get_tree().process_frame
	if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
	sim_naval.compute_bodies()
	sim_nav = SimNavS.new()  # new object per map: the gen cache keeps the previous one
	sim_nav.build(sim_naval.body, W, H)
	_gt("bodies")
	if _async_gen: _load_progress(0.65); await get_tree().process_frame
	sim_naval.trade_cache.clear()
	_recompute_base_colors()

func _recompute_base_colors() -> void:
	if owner_map.size() != W * H or elev_map.size() != W * H: return
	var cfg: Dictionary = save.get("settings", {})
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var m := _active_map_entry(map_i)
	var seed_val: int = int(m[1]) + (rand_seed_off if map_tab == 1 else 0)
	var n3 := FastNoiseLite.new()
	n3.seed = seed_val + 99
	n3.frequency = 0.04
	n3.fractal_octaves = 3
	var deep := Color(0.18, 0.39, 0.60) if qual_i >= 3 else Color(0.20, 0.42, 0.62)
	var shallow := Color(0.44, 0.69, 0.84) if qual_i >= 3 else Color(0.42, 0.66, 0.80)
	_qual_c = qual_i
	if qual_i >= 2:
		_rw_terrain_all()
		_gt("colors")
		_store_gen_cache()
		if _async_gen: _load_progress(0.85); await get_tree().process_frame
		_redraw_all()
		_gt("redraw")
		return
	for i in W * H:
		var x := i % W; var y := i / W
		var o := owner_map[i]
		var t: float = (n3.get_noise_2d(x, y) * 0.5 + 0.5) if qual_i >= 1 else 0.5
		var c: Color
		if o == WATER:
			var d_c: int = coast_dist[i] if coast_dist.size() == W * H else 99
			if qual_i == 0:
				# Low quality: flat ocean color
				c = Color(0.22, 0.44, 0.64)
			elif qual_i == 1:
				# Medium quality: 2-step coastal shelf
				c = shallow if d_c <= 2 else deep
			elif qual_i == 2:
				# High quality: smooth coastal shelf + subtle wave texture
				c = deep.lerp(shallow, clampf(1.0 - (d_c - 1) / 9.0, 0.0, 1.0) * 0.8) if d_c < 99 else deep
				c = c.darkened(0.04 * t)
			else:
				# Ultra quality: deep bathymetry + turquoise coral shallows + specular micro-shimmer
				var sh_f := clampf(1.0 - (d_c - 1) / 11.0, 0.0, 1.0)
				c = deep.lerp(shallow, pow(sh_f, 0.85) * 0.88) if d_c < 99 else deep.darkened(0.06)
				if d_c == 1: c = c.lerp(Color(0.56, 0.80, 0.88), 0.35)
				c = c.darkened(0.05 * t)
		else:
			var e := elev_map[i]
			if qual_i == 0:
				# Low quality: flat solid biome colors
				if mtn[i] == 2: c = Color(0.84, 0.84, 0.87)
				elif mtn[i] == 1: c = Color(0.78, 0.71, 0.52)
				else: c = Color(0.66, 0.78, 0.49)
			elif qual_i == 1:
				# Medium quality: basic elevation shading, no beaches
				if mtn[i] == 2: c = Color(0.72, 0.69, 0.65).lerp(Color(0.94, 0.94, 0.96), clampf((e - 0.42) * 4.0, 0.0, 1.0))
				elif mtn[i] == 1: c = Color(0.80, 0.73, 0.54).lerp(Color(0.72, 0.64, 0.46), t * 0.45)
				else: c = Color(0.70, 0.81, 0.52).lerp(Color(0.60, 0.73, 0.45), t * 0.45)
			else:
				# High & Ultra quality: full biome shading + snow peaks + sandy beaches + relief contrast
				if mtn[i] == 2:
					c = Color(0.62, 0.58, 0.53).lerp(Color(0.97, 0.97, 0.99), clampf((e - 0.40) * 5.2, 0.0, 1.0)).darkened(0.07 * t)
				elif mtn[i] == 1:
					c = Color(0.82, 0.75, 0.55).lerp(Color(0.73, 0.64, 0.45), t * 0.65).lerp(Color(0.68, 0.60, 0.46), clampf((e - 0.20) * 3.5, 0.0, 1.0))
				else:
					c = Color(0.72, 0.83, 0.54).lerp(Color(0.56, 0.72, 0.43), t * 0.65)
				var w_adj := 0
				for d in [1, -1, W, -W]:
					if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
					var j: int = i + d
					if j >= 0 and j < W * H and owner_map[j] == WATER: w_adj += 1
				if w_adj > 0:
					c = c.lerp(Color(0.92, 0.88, 0.71), 0.55 if qual_i == 2 else minf(0.78, 0.45 + 0.14 * w_adj))
		if qual_i >= 2: c = _rw_terrain(i)
		elif owner_map[i] != WATER and snow_src.size() == W * H and snow_src[i] == 4: c = SNOW_COL
		base_col[i] = c
	# Software Coastline & Border Anti-Aliasing pass scaled by msaa_i (0 = Off/Sharp, 1 = 2x, 2 = 4x, 3 = 8x)
	if msaa_i > 0 and qual_i < 2:
		var blend_w: float = [0.0, 0.16, 0.28, 0.40][msaa_i]
		var copy_col := base_col.duplicate()
		for i in W * H:
			var x := i % W; var y := i / W
			if x <= 0 or x >= W - 1 or y <= 0 or y >= H - 1: continue
			var o := owner_map[i]
			var diff_nb := false
			var acc_r := 0.0; var acc_g := 0.0; var acc_b := 0.0; var nb_cnt := 0
			for d in [1, -1, W, -W]:
				if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
				var j: int = i + d
				if owner_map[j] != o or mtn[j] != mtn[i]: diff_nb = true
				var nc: Color = copy_col[j]
				acc_r += nc.r; acc_g += nc.g; acc_b += nc.b; nb_cnt += 1
			if diff_nb and nb_cnt > 0:
				var avg_c := Color(acc_r / nb_cnt, acc_g / nb_cnt, acc_b / nb_cnt, 1.0)
				base_col[i] = copy_col[i].lerp(avg_c, blend_w)
	_gt("colors")
	_redraw_all()
	_gt("redraw")

# Fast whole-map version of _rw_terrain (same colours), locals only.
func _rw_terrain_all() -> void:
	var om := owner_map; var cdist := coast_dist; var el := elev_map; var mt := mtn
	var N := W * H
	var bc := PackedColorArray(); bc.resize(N)
	var shore_w := Color8(int(0.7 * 0x47 + 76.5), int(0.7 * 0x85 + 76.5), int(0.7 * 0xB5 + 76.5))
	var sand := Color8(0xCC, 0xCB, 0x9E)
	var ocean := []
	for m in 11: ocean.append(Color8(0x47 - m, 0x85 - m, 0xB5 - m))
	var mtc := []
	for mm in 7: mtc.append(Color8(0xE6 + mm, 0xE6 + mm, 0xE6 + mm))
	var hic := []
	for mh in 10: hic.append(Color8(0xDC + 2 * mh, 0xCB + 2 * mh, 0x9E + 2 * mh))
	var plc := []
	for mp in 10: plc.append(Color8(0xBE, 0xDC - 2 * mp, 0x8A))
	for i in N:
		var o: int = om[i]
		var w := o == WATER
		var x := i % W
		var shore := false
		if x > 0 and (om[i - 1] == WATER) != w: shore = true
		elif x < W - 1 and (om[i + 1] == WATER) != w: shore = true
		elif i >= W and (om[i - W] == WATER) != w: shore = true
		elif i + W < N and (om[i + W] == WATER) != w: shore = true
		if w:
			bc[i] = shore_w if shore else ocean[mini(maxi(cdist[i] - 1, 0), 10)]
		elif snow_src.size() == N and snow_src[i] == 4: bc[i] = SNOW_COL
		elif shore: bc[i] = sand
		else:
			var e: float = el[i]
			var k: int = mt[i]
			if k == 2: bc[i] = mtc[clampi(int((e - 0.4) * 30.0), 0, 6)]
			elif k == 1: bc[i] = hic[clampi(int((e - 0.2) * 40.0), 0, 9)]
			else: bc[i] = plc[clampi(int(e * 30.0), 0, 9)]
	base_col = bc

func _rw_terrain(i: int) -> Color:
	var o := owner_map[i]
	var x := i % W
	var shore := false
	for d in _DIRS4:
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
		if (owner_map[j] == WATER) != (o == WATER): shore = true; break
	if o == WATER:
		if shore: return Color8(int(0.7 * 0x47 + 76.5), int(0.7 * 0x85 + 76.5), int(0.7 * 0xB5 + 76.5))
		var dc: int = coast_dist[i] if coast_dist.size() == W * H else 10
		var m := mini(maxi(dc - 1, 0), 10)
		return Color8(0x47 - m, 0x85 - m, 0xB5 - m)
	if snow_src.size() == W * H and snow_src[i] == 4: return SNOW_COL
	if shore: return Color8(0xCC, 0xCB, 0x9E)
	var e: float = elev_map[i] if elev_map.size() == W * H else 0.2
	if mtn[i] == 2:
		var mm := clampi(int((e - 0.4) * 30.0), 0, 6)
		return Color8(0xE6 + mm, 0xE6 + mm, 0xE6 + mm)
	if mtn[i] == 1:
		var mh := clampi(int((e - 0.2) * 40.0), 0, 9)
		return Color8(0xDC + 2 * mh, 0xCB + 2 * mh, 0x9E + 2 * mh)
	var mp := clampi(int(e * 30.0), 0, 9)
	return Color8(0xBE, 0xDC - 2 * mp, 0x8A)

func _qual() -> int:
	if _qual_c >= 0: return _qual_c
	return clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)

func _tile_color(i: int) -> Color:
	var c0 := _tile_color_rgb(i)
	var o := owner_map[i]
	if o == WATER: c0.a = 0.5
	elif o > 0:
		var x := i % W
		var bd := false
		for d in [1, -1, W, -W]:
			if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
			var j: int = i + d
			if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
			if owner_map[j] != o: bd = true; break
		c0.a = 0.86 if bd else 0.94
	else: c0.a = 1.0
	return c0

func _tile_color_rgb(i: int) -> Color:
	var o := owner_map[i]
	if _qual() >= 2: return _rw_tile_rgb(i, o)
	if o <= 0:
		if o == NEUTRAL and fallout.size() > i and fallout[i] == 1:
			var h := (i * 2654435761) % 7
			return Color(0.25, 0.62, 0.25) if h < 3 else (Color(0.85, 0.45, 0.2) if h == 3 else base_col[i].lerp(Color(0.3, 0.7, 0.3), 0.6))
		return base_col[i]
	var c: Color = nations[o].color
	var x := i % W
	var diff_cnt := 0
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
		if owner_map[j] != o:
			diff_cnt += 1
	if diff_cnt > 0:
		var msaa_i := clampi(int(save.get("settings", {}).get("msaa_i", 2)), 0, 3)
		var b_dark: float = 0.32 if msaa_i <= 1 else (0.18 + 0.04 * mini(diff_cnt, 3))
		return c.darkened(b_dark)
	return base_col[i].lerp(c, 0.50)

# RoWorld MapSurface.tile_pixel: fill = owner colour (saturation 0.85) at alpha 150/255 over the terrain,
# border tiles opaque in the owner colour with HSL lightness - 0.125, fallout ground opaque green noise
# (0.05, 0.55, 0.07) + hash * 0.05, glowing lime while fresh (FalloutGlow heat, 150,236,90).
func _rw_tile_rgb(i: int, o: int) -> Color:
	var x := i % W
	if fallout.size() > i and fallout[i] == 1 and o != WATER:
		var y := i / W
		var h := fmod(abs(sin(x * 12.9898 + y * 78.233) * 43758.5453), 1.0) * 0.05
		var g := Color(0.05 + h, 0.55 + h, 0.07 + h)
		var heat := clampf((fallout_t[i] - 34.5) / 25.5, 0.0, 1.0)
		var bx := (x / 4 + (y / 4) * 7) % 5
		if heat > 0.0: g = g.lerp(Color8(150, 236, 90), heat * (0.75 + 0.05 * bx))
		return g
	var tc: Color = base_col[i]
	if o <= 0: return tc
	var nc: Color = nations[o].color
	nc = Color.from_hsv(nc.h, nc.s * 0.85, nc.v)
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0) or owner_map[j] != o:
			return _hsl_darken(nations[o].color, 0.125)
	return tc.lerp(nc, 150.0 / 255.0)

func _hsl_darken(c: Color, k: float) -> Color:
	var mx := maxf(c.r, maxf(c.g, c.b)); var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) * 0.5
	var nl := maxf(0.0, l - k)
	if l <= 0.0: return c
	# scale distance from grey proportionally (keeps hue and saturation in HSL)
	var sat := 0.0 if mx == mn else (mx - mn) / (1.0 - absf(2.0 * l - 1.0))
	var ch := (1.0 - absf(2.0 * nl - 1.0)) * sat
	var r := (c.r - mn) / maxf(1e-5, mx - mn); var g := (c.g - mn) / maxf(1e-5, mx - mn); var b := (c.b - mn) / maxf(1e-5, mx - mn)
	var m := nl - ch * 0.5
	return Color(m + r * ch, m + g * ch, m + b * ch)

func _px(x: int, y: int, c: Color) -> void:
	var k := (y / CH) * (W / CW) + x / CW
	chunk_img[k].set_pixel(x % CW, y % CH, c)
	chunk_dirty[k] = 1

func _redraw_all() -> void:
	_pend_paint.clear()
	_qual_c = clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)
	var N := W * H
	var buf := PackedByteArray(); buf.resize(N * 4)
	var hasf := fallout.size() == N
	for i in N:
		var o: int = owner_map[i]
		var c: Color
		if o <= 0 and not (hasf and fallout[i] == 1):
			c = base_col[i]; c.a = 0.5 if o == WATER else 1.0
		else:
			c = _tile_color(i)
		var b := i * 4
		buf[b] = c.r8; buf[b + 1] = c.g8; buf[b + 2] = c.b8; buf[b + 3] = c.a8
	var big := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, buf)
	var cols := W / CW
	for k in chunk_img.size():
		chunk_img[k].blit_rect(big, Rect2i((k % cols) * CW, (k / cols) * CH, CW, CH), Vector2i.ZERO)
		chunk_dirty[k] = 1
	dirty = true

func _repaint(i: int) -> void:
	_pend_paint[i] = true
	var N := W * H
	if i + 1 < N: _pend_paint[i + 1] = true
	if i >= 1: _pend_paint[i - 1] = true
	if i + W < N: _pend_paint[i + W] = true
	if i >= W: _pend_paint[i - W] = true
	dirty = true
	if _pend_paint.size() > 60000: _flush_paint()

func _flush_paint_budget(n: int) -> bool:
	if _pend_paint.size() <= n: _flush_paint(); return false
	var ks := _pend_paint.keys()
	for m in n:
		var j: int = ks[m]
		_px(j % W, j / W, _tile_color(j))
		_pend_paint.erase(j)
	return true

func _flush_paint() -> void:
	for j in _pend_paint:
		_px(j % W, j / W, _tile_color(j))
	_pend_paint.clear()

func _upd_border(t: int) -> void:
	var o: int = owner_map[t]
	if o <= 0: return
	var x := t % W
	var b := false
	if x > 0 and owner_map[t - 1] != o and owner_map[t - 1] >= 0: b = true
	elif x < W - 1 and owner_map[t + 1] != o and owner_map[t + 1] >= 0: b = true
	elif t >= W and owner_map[t - W] != o and owner_map[t - W] >= 0: b = true
	elif t < W * (H - 1) and owner_map[t + W] != o and owner_map[t + W] >= 0: b = true
	var d: Dictionary = border[o]
	if b: d[t] = true
	else: d.erase(t)

func _set_owner(i: int, o: int) -> void:
	var old: int = owner_map[i]
	if old > 0 and old < border.size(): border[old].erase(i)
	if old > 0:
		nations[old].land -= 1
		nations[old].sx -= i % W; nations[old].sy -= i / W
	owner_map[i] = o
	if old > 0 and o > 0: nations[old]["last_by"] = o
	if struct_at.has(i):
		var st = struct_at[i]
		if o > 0 and o != old:
			_own_sv[st.o] = _own_sv.get(st.o, 0) + 1; st.o = o; _sv += 1; _own_sv[o] = _own_sv.get(o, 0) + 1
			st.hits = 0
			var lvl := int(st.get("level", 1))
			var ltxt := (" Lv%d" % lvl) if lvl > 1 else ""
			var nm: String = build_data[st.k][1] + ltxt
			if o == PLAYER:
				notify("Captured %s from %s!" % [nm, _nname(old)], "good")
				sfx("ka_ching")
				add_float(Vector2(i % W + 0.5, i / W + 0.5) * TS, "Captured %s!" % nm, GREEN)
			elif old == PLAYER:
				notify("%s captured your %s!" % [_nname(o), nm], "bad")
		elif o <= 0:
			_struct_remove(st)
	if o > 0 and fallout.size() > i and fallout[i] == 1:
		fallout[i] = 0; fallout_list.erase(i)
	if o > 0:
		var n = nations[o]
		n.land += 1
		var x := i % W
		var y := i / W
		n.bb = n.bb.merge(Rect2i(x, y, 1, 1)) if n.bb.size != Vector2i.ZERO else Rect2i(x, y, 1, 1)
		n.sx += x; n.sy += y
		if old != o and _q() >= 2 and cap_fx.size() < CAP_FX_MAX:
			cap_fx[i] = [map_t, n.color]
	if border.size() == nations.size():
		_upd_border(i)
		var bx := i % W
		if bx > 0: _upd_border(i - 1)
		if bx < W - 1: _upd_border(i + 1)
		if i >= W: _upd_border(i - W)
		if i < W * (H - 1): _upd_border(i + W)
	_repaint(i)
