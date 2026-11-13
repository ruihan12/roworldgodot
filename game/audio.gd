extends "res://game/shop.gd"
# Sound and music

func _load_audio(path: String) -> AudioStream:
	# Absolute path first. res:// reads go through the import remap, which is empty
	# in a freshly unzipped project (the .godot cache is not shipped) and load() then
	# fails. PCM/MP3 bytes from disk do not need that cache.
	var abs_path := ProjectSettings.globalize_path(path)
	var bytes := PackedByteArray()
	if FileAccess.file_exists(abs_path):
		bytes = FileAccess.get_file_as_bytes(abs_path)
	elif FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	var ext := path.get_extension().to_lower()
	if not bytes.is_empty():
		if ext == "wav":
			var wav := _wav_stream(bytes)
			if wav != null and wav.get_length() > 0.01:
				return wav
		elif ext == "mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes.duplicate()
			if mp3.get_length() > 0.01:
				return mp3
		elif ext == "ogg":
			var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
			if ogg != null and ogg.get_length() > 0.01:
				return ogg
	var imported = load(path)
	if imported is AudioStream and (imported as AudioStream).get_length() > 0.01:
		return imported
	return null

func _wav_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var pcm := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := int(bytes.decode_u32(pos + 4))
		var start := pos + 8
		if start + sz > bytes.size():
			break
		if id == "fmt " and sz >= 16:
			var audio_fmt := int(bytes.decode_u16(start))
			channels = int(bytes.decode_u16(start + 2))
			rate = int(bytes.decode_u32(start + 4))
			bits = int(bytes.decode_u16(start + 14))
			if audio_fmt != 1:
				return null
		elif id == "data":
			pcm = bytes.slice(start, start + sz)
			break
		pos = start + sz + (sz & 1)
	if pcm.is_empty() or bits != 16 or channels < 1:
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = channels >= 2
	s.data = pcm
	return s

func _ensure_bus(nm: String) -> int:
	var idx := AudioServer.get_bus_index(nm)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, nm)
		AudioServer.set_bus_send(idx, "Master")
	return idx

func _init_audio() -> void:
	_ensure_bus("Music"); _ensure_bus("SFX")
	for key in SFX_FILES:
		var arr := []
		for fn in SFX_FILES[key]:
			var s := _load_audio("res://sounds/" + fn)
			if s: arr.append(s)
			else: sfx_missing.append(fn)
		if not arr.is_empty(): sfx_streams[key] = arr
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"
		add_child(p); sfx_pool.append(p)
	music_player = AudioStreamPlayer.new(); music_player.bus = "Music"
	add_child(music_player)
	music_player.finished.connect(func(): _play_music())
	if not sfx_missing.is_empty(): push_warning("Missing sounds: %s" % [sfx_missing])
	if autoshot or bench: print("audio: loaded %d/%d sfx keys, missing files: %s" % [sfx_streams.size(), SFX_FILES.size(), sfx_missing])
	_apply_volumes()
	_init_audio_director()
	# Menu and match share one clean loop. Contaminated themes are not candidates.
	if bool(save.get("settings", {}).get("music_on", true)): _play_music()

func _init_audio_director() -> void:
	if "--legacy_sfx" in OS.get_cmdline_user_args(): return
	var AD = load("res://audio_upstream/audio_director.gd")
	if AD == null or not AD.can_instantiate(): return
	audio_dir = AD.new()
	add_child(audio_dir)
	audio_dir.set_player_id(PLAYER)
	# RoWorld soundtrack installed (sounds/upstream/music/*.ogg): the director plays it as upstream's
	# playlist by mood; otherwise the bed stays on the legacy music_player and the director's music is off.
	_dir_music = audio_dir.has_method("soundtrack_count") and audio_dir.soundtrack_count() > 0
	audio_dir.set_music_enabled(false)
	for key in SFX_FILES: _audio_dir_known[key] = audio_dir.has_sfx(key)
	if autoshot or bench: print("audio director: on, keys known %d/%d" % [_audio_dir_known.values().count(true), SFX_FILES.size()])

func _vol_db(v: float) -> float:
	return linear_to_db(maxf(0.0001, clampf(v, 0.0, 1.0)))

func _apply_volumes() -> void:
	var cfg: Dictionary = save.get("settings", {})
	var mv := float(cfg.get("vol_master", 0.8)); var mu := float(cfg.get("vol_music", 0.5)); var sx := float(cfg.get("vol_sfx", 0.8))
	AudioServer.set_bus_volume_db(0, _vol_db(mv)); AudioServer.set_bus_mute(0, mv <= 0.001)
	var bi := AudioServer.get_bus_index("Music")
	if bi >= 0: AudioServer.set_bus_volume_db(bi, _vol_db(mu)); AudioServer.set_bus_mute(bi, mu <= 0.001 or not bool(cfg.get("music_on", true)))
	bi = AudioServer.get_bus_index("SFX")
	if bi >= 0: AudioServer.set_bus_volume_db(bi, _vol_db(sx)); AudioServer.set_bus_mute(bi, sx <= 0.001)

# who = owner whose event this is (PLAYER for your own actions / things hitting you). Everything
# except nuke launches & impacts is hard-gated to events involving the player.
func sfx(key: String, vol_db := 0.0, pitch_jitter := 0.04, who := PLAYER) -> void:
	# Player's own actions, anything aimed at / hitting the player (callers pass who=PLAYER),
	# and nuke launches/impacts from anyone. AI boat, conquer, build and SAM stay silent.
	var allowed := who == PLAYER or key in SFX_ANY_OWNER
	if _sfx_log:
		print("SFX %s t=%.1fs key=%s who=%d vol=%.0fdB" % ["PLAY" if allowed else "BLOCK", (sim_atk.tick / 10.0) if sim_atk else 0.0, key, who, vol_db])
	if not allowed: return
	if audio_dir != null and _audio_dir_known.get(key, false):
		audio_dir.play_sfx(key, vol_db, pitch_jitter, -1.0, who, who == PLAYER, key == "click")
		return
	if not sfx_streams.has(key) or sfx_pool.is_empty(): return
	var now := Time.get_ticks_msec()
	var gap := int(float(SFX_GAP.get(key, 0.12)) * 1000.0)
	if now - int(sfx_last.get(key, -100000)) < gap: return
	sfx_last[key] = now
	var p: AudioStreamPlayer = null
	for c in sfx_pool:
		if not c.playing: p = c; break
	if p == null:  # steal the oldest-started voice
		p = sfx_pool[0]; sfx_pool.remove_at(0); sfx_pool.append(p)
	var arr: Array = sfx_streams[key]
	p.stream = arr[rng.randi() % arr.size()]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func _play_music() -> void:
	if not bool(save.get("settings", {}).get("music_on", true)): return
	if _dir_music and audio_dir != null:
		if music_player: music_player.stop()
		_tick_music_mood()
		audio_dir.set_music_enabled(true)
		return
	if music_player == null: return
	if music_player.playing and str(music_player.get_meta("music_file", "")) == MUSIC_FILE: return
	var s := _load_audio(MUSIC_FILE)
	if s == null:
		push_warning("Clean music missing (%s). Rejected themes are not used as a fallback." % MUSIC_FILE)
		return
	if s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frame := 2 * (2 if wav.stereo else 1)
		wav.loop_end = int(wav.data.size() / frame)
	music_player.set_meta("music_file", MUSIC_FILE)
	music_player.stream = s
	music_player.play()

func music_on_setting() -> bool:
	return bool(save.get("settings", {}).get("music_on", true))

# top-bar music button (Main.luau): same effect as the Settings MUSIC toggle
func hud_toggle_music() -> void:
	if not save.has("settings"): save["settings"] = {}
	var on := not music_on_setting()
	save.settings["music_on"] = on
	_apply_volumes()
	if on: _play_music()
	else: _stop_music()
	write_save()

func _stop_music() -> void:
	if _dir_music and audio_dir != null: audio_dir.set_music_enabled(false)
	if music_player: music_player.stop()

# upstream UIRoot._update_music: the soundtrack mood from the screen (MusicMood), polled
func _tick_music_mood() -> void:
	if not _dir_music or audio_dir == null: return
	var scr := "title" if state == "menu" else ("over" if state == "over" else "play")
	var me := PLAYER if nations.size() > PLAYER else 0
	var alive: bool = me > 0 and bool(nations[me].get("alive", true))
	var winner := 0
	if state == "over": winner = PLAYER if alive else -1
	var fighting := false
	if scr == "play" and me > 0:
		for a in attacks:
			if (a.a == me and a.t > 0) or (a.t == me and a.a > 0): fighting = true; break
		if not fighting:
			for ms in missiles:
				if ms.o == me or int(ms.get("tgt_o", 0)) == me: fighting = true; break
	audio_dir.update_mood({"screen": scr, "waiting": false, "me": me, "alive": alive, "winner": winner, "fighting": fighting})

func _music_file() -> String:
	if _dir_music and audio_dir != null: return audio_dir.current_music_file()
	return str(music_player.get_meta("music_file", "")) if music_player else ""

func _music_playing() -> bool:
	if _dir_music and audio_dir != null: return audio_dir.is_music_playing() and audio_dir.is_music_enabled()
	return music_player != null and music_player.playing

func _cap_peak(cap: AudioEffectCapture) -> float:
	var n := cap.get_frames_available()
	if n < 32:
		return 0.0
	var data := cap.get_buffer(mini(n, 48000 * 4))
	var peak := 0.0
	for i in data.size():
		peak = maxf(peak, absf(data[i].x))
		peak = maxf(peak, absf(data[i].y))
	return peak

func _save_viewport(path: String) -> void:
	var im := get_viewport().get_texture().get_image()
	if im == null:
		print("SHOT missing ", path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	im.save_png(path)
	var r := speed_panel.get_global_rect() if speed_panel else Rect2()
	if r.size.x > 4.0 and r.size.y > 4.0:
		var crop := im.get_region(Rect2i(int(r.position.x), int(r.position.y), int(r.size.x) + 2, int(r.size.y) + 2))
		crop.save_png(path.get_basename() + "_crop.png")
	print("SHOT ", path, " ", im.get_width(), "x", im.get_height())

func _regress() -> void:
	# Mixer capture is the audio server's output buffer (Dummy driver in headless).
	# It is not a speaker or microphone recording.
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 8.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), cap)
	# the soundtrack's opener fades in over MOOD_FADE_S (3 s) from a quiet intro: listen past the fade
	await get_tree().create_timer(4.0 if _dir_music else 1.4).timeout
	var music_peak := _cap_peak(cap)
	var mlen := -1.0
	if _dir_music and audio_dir != null and audio_dir._current != null and audio_dir._current.stream:
		mlen = audio_dir._current.stream.get_length()
	elif music_player and music_player.stream:
		mlen = music_player.stream.get_length()
	print("REGRESS music_peak=%.4f playing=%s len=%.2f file=%s track=%s loaded=%d missing=%s" % [music_peak, str(_music_playing()), mlen, _music_file(), (audio_dir.current_track() if _dir_music else ""), sfx_streams.size(), str(sfx_missing)])
	cap.clear_buffer()
	sfx("click", 0.0, 0.0, PLAYER)
	sfx("order", 0.0, 0.0, PLAYER)
	sfx("transport", 0.0, 0.0, PLAYER)
	sfx("conquered", 0.0, 0.0, 2)
	sfx("build_city", 0.0, 0.0, 2)
	await get_tree().create_timer(0.9).timeout
	var sfx_peak := _cap_peak(cap)
	print("REGRESS sfx_peak=%.4f" % sfx_peak)
	play_dialog.visible = true
	var t0 := Time.get_ticks_usec()
	_set_map_tab(1)
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("REGRESS map_sync_ms=%.2f queue=%d" % [sync_ms, _preview_queue.size()])
	var worst := 0
	var frames := 0
	var t_start := Time.get_ticks_msec()
	while not _preview_queue.is_empty() or not _pv_job.is_empty():
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst = maxi(worst, int(Time.get_ticks_usec() - f0))
		frames += 1
		if Time.get_ticks_msec() - t_start > 25000:
			print("REGRESS map_timeout")
			break
	print("REGRESS map_frames=%d worst_frame_ms=%.1f pump_us=%d" % [frames, worst / 1000.0, preview_pump_us])
	menu_panel.visible = false
	play_dialog.visible = false
	if speed_panel:
		speed_panel.visible = true
		if speed_panel.get_parent() is CanvasItem and speed_panel.get_parent() != ui: speed_panel.get_parent().visible = true  # hud group
	var overlap := false
	for sp in [0.5, 1.0, 10.0]:
		set_speed_x(sp)
		await get_tree().process_frame
		await get_tree().process_frame
		var bad := _speed_labels_overlap()
		if bad:
			overlap = true
		print("REGRESS speed=%s overlap=%s title=%s value=%s hint=%s" % [speed_lbl.text, str(bad), speed_title.get_global_rect(), speed_lbl.get_global_rect(), speed_hint.get_global_rect()])
		_save_viewport("/tmp/speedui/speed_%s.png" % speed_lbl.text.replace(".", "p"))
	var nukes_ok := is_equal_approx(float(NUKE_R[7]), 19.6) and is_equal_approx(float(NUKE_R[8]), 70.0) and is_equal_approx(float(NUKE_R[9]), 8.4)
	var fail := music_peak < 0.02 or sfx_peak < 0.05 or sync_ms > 80.0 or worst > 90000 or overlap or not nukes_ok or sfx_streams.size() < 30
	print("REGRESS nukes_ok=%s" % str(nukes_ok))
	print("REGRESS %s" % ("FAIL" if fail else "OK"))
	get_tree().quit(1 if fail else 0)

func _speedshot() -> void:
	menu_panel.visible = false
	play_dialog.visible = false
	for n in hud_nodes:
		n.visible = false
	if speed_panel:
		speed_panel.visible = true
	var tag := "1600x900"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--res="):
			tag = arg.substr(6)
	for sp in [0.5, 1.0, 10.0]:
		set_speed_x(sp)
		await get_tree().process_frame
		await get_tree().process_frame
		_save_viewport("/tmp/speedui/%s_%s.png" % [tag, speed_lbl.text.replace(".", "p")])
		print("SPEEDSHOT %s %s overlap=%s" % [tag, speed_lbl.text, str(_speed_labels_overlap())])
	get_tree().quit(0)

func _audiotest() -> void:
	# Event log only. Whether a file contains boat or conquer audio is measured outside Godot
	# (tools/audio_evidence.py): a PLAY/BLOCK line is not listening evidence.
	_sfx_log = true
	print("AUDIOTEST begin state=%s" % state)
	for _i in 8:
		await get_tree().process_frame
	print("AUDIOTEST menu music_file=%s playing=%s track=%s" % [_music_file(), str(_music_playing()), (audio_dir.current_track() if _dir_music else "")])
	print("AUDIOTEST rejected_menu=%s rejected_war=%s" % [str(FileAccess.file_exists("res://sounds/rejected/roworld_menu.mp3")), str(FileAccess.file_exists("res://sounds/rejected/roworld_war.mp3"))])
	sfx("transport", 0.0, 0.0, 2)
	sfx("conquered", 0.0, 0.0, 2)
	sfx("build_city", 0.0, 0.0, 2)
	sfx("sam_shoot", 0.0, 0.0, 2)
	sfx("atom_launch", 0.0, 0.0, 2)
	sfx("hydrogen_hit", 0.0, 0.0, 2)
	sfx("click", 0.0, 0.0, PLAYER)
	sfx("transport", 0.0, 0.0, PLAYER)
	save.settings["music_on"] = false
	_apply_volumes(); _stop_music()
	print("AUDIOTEST toggle_off playing=%s bus_mute=%s" % [str(_music_playing()), str(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))])
	save.settings["music_on"] = true
	_apply_volumes(); _play_music()
	print("AUDIOTEST toggle_on playing=%s file=%s" % [str(_music_playing()), _music_file()])
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(int(W / 2), int(H / 3))
	_place_start(st)
	deploy_t = 0.0
	state = "play"
	peace = 0.0
	set_speed_x(10.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	print("AUDIOTEST gameplay_ms=%d tick=%d boats=%d attacks=%d" % [Time.get_ticks_msec() - t0, sim_atk.tick if sim_atk else -1, boats.size(), attacks.size()])
	print("AUDIOTEST map=%dx%d blast_s=%.4f" % [W, H, BLAST_S])
	for k in [7, 8, 9, 11, 12]:
		print("AUDIOTEST nuke k=%d frac=%.4f radius=%.2f" % [k, float(NUKE_RANGE_FRAC[k]), float(NUKE_R[k])])
	var slow := clampf(snappedf(0.4, 0.5), 0.5, 10.0)
	var fast := clampf(snappedf(12.0, 0.5), 0.5, 10.0)
	print("AUDIOTEST speed_lo=%.1f speed_hi=%.1f" % [slow, fast])
	print("AUDIOTEST done")
	get_tree().quit()

func _maptest() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	for tab in 2:
		var t0 := Time.get_ticks_usec()
		_set_map_tab(tab)
		print("MAPTEST tab %d switch ms=%.0f" % [tab, (Time.get_ticks_usec() - t0) / 1000.0])
		for k in map_card_tex.size():
			var im: Image = _map_preview(k, 448, 400).get_image()
			im.save_png("/workspace/shots/31_%s_%02d.png" % ["real" if tab == 0 else "random", k])
	for cfg in [[0, 0], [0, 7], [0, 2], [1, 0]]:
		map_tab = cfg[0]; map_i = cfg[1]
		var t1 := Time.get_ticks_usec()
		gen_map()
		var t2 := Time.get_ticks_usec()
		_start_game()
		var t3 := Time.get_ticks_usec()
		print("MAPTEST start tab=%d map=%d gen_ms=%.0f start_game_ms=%.0f land=%d nations=%d" % [cfg[0], cfg[1], (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, land_total, nations.size()])
		_flush_paint()
		var big := Image.create(W, H, false, Image.FORMAT_RGBA8)
		for k in chunk_img.size():
			big.blit_rect(chunk_img[k], Rect2i(0, 0, CW, CH), Vector2i((k % (W / CW)) * CW, (k / (W / CW)) * CH))
		big.resize(896, 800); big.save_png("/workspace/shots/31_match_tab%d_map%02d.png" % [cfg[0], cfg[1]])
	get_tree().quit()

func _rangetest() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 1
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 50 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 1e9
	_claim_blob(PLAYER, st, 70)
	nations[PLAYER].gold = 2e8
	var c0 := st
	var sx := c0 % W; var sy := c0 / W
	var spots := [[0, 0, 2], [20, 8, 0], [-18, 12, 0], [10, -22, 5], [-25, -10, 1], [35, 25, 0], [-5, 30, 3], [28, -5, 4]]
	for sp in spots:
		var t := _find_spawn_tile(sx + sp[0], sy + sp[1])
		if owner_map[t] != PLAYER: t = (sy + sp[1]) * W + sx + sp[0]
		print("build k=", sp[2], " ok=", try_build(sp[2], t))
	for s2 in structs: s2.bt = 0.0
	_sv += 1
	var good := 0; var over_water := 0
	for a in structs:
		for b in _rail_neighbors(a):
			var rc := _rail_curve(a.tile, b.tile)
			var pts: PackedVector2Array = rc[0]
			good += 1
			for m in range(1, pts.size()):
				if not _land_los(pts[m - 1], pts[m]): over_water += 1
			print("rail %d->%d segs=%d" % [a.k, b.k, pts.size() - 1])
	print("RAILS links=%d water_segments=%d" % [good, over_water])
	_focus_player(2.2)
	for k in [7, 8, 12]:
		build_sel = k
		var silo_t := -1
		for s3 in structs: if s3.k == 5: silo_t = s3.tile
		cam.zoom = Vector2(0.55, 0.55) if k != 12 else Vector2(1.4, 1.4)
		cam.position = Vector2(silo_t % W, silo_t / W) * TS
		await get_tree().process_frame
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.72, 0.4))
		for _f in 6: await get_tree().process_frame
		_shot("32_range_k%d.png" % k)
		var far := Vector2(silo_t % W, silo_t / W) + Vector2(nuke_range(k) + 30, 0)
		var ft := clampi(int(far.y) * W + int(far.x), 0, W * H - 1)
		var near := clampi((silo_t / W) * W + silo_t % W + int(nuke_range(k) * 0.5), 0, W * H - 1)
		print("RANGE k=%d range_tiles=%.0f far_ok=%s near_ok=%s" % [k, nuke_range(k), str(not silo_for(PLAYER, k, Vector2(far)).is_empty()), str(not silo_for(PLAYER, k, Vector2(near % W, near / W)).is_empty())])
	set_icbm(true)
	var g0: float = nations[PLAYER].gold
	var tgt := clampi(W * H - W * 200 - 200, 0, W * H - 1)
	for i in range(W * H - 1, 0, -997):
		if owner_map[i] > 0 and owner_map[i] != PLAYER: tgt = i; break
	for s4 in structs: if s4.k == 5: s4.erase("slots")
	print("ICBM launch ok=", launch_nuke(PLAYER, 7, tgt), " gold spent=", g0 - nations[PLAYER].gold)
	set_icbm(false)
	build_sel = 2
	cam.zoom = Vector2(1.6, 1.6); _focus_player(1.6)
	for _f in 6: await get_tree().process_frame
	_shot("32_factory_range_rails.png")
	build_sel = -1
	for _f in 4: await get_tree().process_frame
	_shot("32_rails_hud.png")
	get_tree().quit()

func _rangetest2() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	for mi in [0, 6]:
		map_tab = 0; map_i = mi
		_start_game()
		var stp := _find_spawn_tile(W / 2, H / 2)
		_place_start(stp); deploy_t = 0.0; state = "play"; peace = 1e9
		var lw := land_width()
		# westmost / eastmost land tiles on the middle-ish rows
		var west := -1; var east := -1
		for x in W:
			for y in range(0, H, 3):
				if owner_map[y * W + x] != WATER: west = y * W + x; break
			if west >= 0: break
		for x in range(W - 1, -1, -1):
			for y in range(0, H, 3):
				if owner_map[y * W + x] != WATER: east = y * W + x; break
			if east >= 0: break
		var silo := {"o": PLAYER, "k": 5, "tile": west, "bt": 0.0, "level": 1}
		structs.append(silo); struct_at[west] = silo
		var ep := Vector2(east % W + 0.5, east / W + 0.5)
		for k in [7, 11, 8, 12, 9]:
			icbm_mode = false
			var far_ok := not silo_for(PLAYER, k, ep).is_empty()
			icbm_mode = true
			var icbm_ok := not silo_for(PLAYER, k, ep).is_empty()
			print("RANGE2 map=%s land_w=%.0f k=%d range=%.0f tiles (%s) west->east dist=%.0f reach=%s icbm=%s" % [RealMaps.MAPS[RW_MAP_FOR[mi]].name, lw, k, nuke_range(k), nuke_range_label(k), Vector2(west % W, west / W).distance_to(ep), str(far_ok), str(icbm_ok)])
		icbm_mode = false
		if mi == 0 and DisplayServer.get_name() != "headless":
			build_sel = 7
			cam.zoom = Vector2(0.42, 0.42); cam.position = Vector2(west % W + 400, west / W) * TS
			await get_tree().process_frame
			get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.75, 0.45))
			for _f in 8: await get_tree().process_frame
			_shot("36_range_circle_world.png")
			build_sel = -1
			# blast size: H-bomb + atom near Irkutsk-ish (east Asia interior)
			var tgt := _find_spawn_tile(int(W * 0.78), int(H * 0.27))
			var c := Vector2(tgt % W + 0.5, tgt / W + 0.5)
			cam.zoom = Vector2(0.9, 0.9); cam.position = c * TS
			detonate(PLAYER, c, float(NUKE_R[8]), 1.0); detonate(PLAYER, c + Vector2(110, 40), float(NUKE_R[7]), 1.0)
			for _f in 40: await get_tree().process_frame
			_shot("36_blast_after.png")

		structs.erase(silo); struct_at.erase(west)
	get_tree().quit()

func _bordershot() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 1
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 50 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	set_speed_x(10.0)
	for tgt in [90.0, 480.0]:
		while elapsed < tgt: await get_tree().process_frame
		cam.zoom = Vector2(0.62, 0.62); cam.position = Vector2(W * 0.52, H * 0.42) * TS
		for _f in 4: await get_tree().process_frame
		_shot("37_borders_%dmin.png" % int(tgt / 60.0))
	get_tree().quit()

func _idletest() -> void:
	_sfx_log = true
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 50 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	for id in range(2, nations.size()):
		if is_prot(id): nations[id].gold = 4e7
	set_speed_x(10.0)
	print("IDLE start")
	var t0 := Time.get_ticks_msec()
	while elapsed < 300.0 and Time.get_ticks_msec() - t0 < 600000:
		await get_tree().process_frame
	print("IDLE done game_s=%.0f missiles_total? structs=%d boats=%d" % [elapsed, structs.size(), boats.size()])
	get_tree().quit()

func _stress() -> void:
	shots_dir = "/workspace/shots"
	_sfx_log = true
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 50 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	_claim_blob(PLAYER, st, 90)
	nations[PLAYER].troops = 1.59304e11; nations[PLAYER].gold = 3.24e8
	for id in range(2, nations.size()):
		if is_prot(id): nations[id].gold = 4e7
	set_speed(SPEEDS.size() - 1)
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var worst := 0.0; var sec_worst := 0.0; var frames := 0; var sec := 0
	var hits := 0
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0; last = now
		frames += 1; sec_worst = maxf(sec_worst, ms); worst = maxf(worst, ms)
		if ms > 50.0: hits += 1
		if (now / 1000 - t0) / 1000 > sec:
			sec = (now / 1000 - t0) / 1000
			if sec % 10 == 0:
				print("STRESS t=%ds game=%.1fmin fps=%d worst_ms=%.0f troops=%s gold=%s structs=%d fallout=%d trains=%d boats=%d attacks=%d missiles=%d alive=%d" % [sec, elapsed / 60.0, frames / 10, sec_worst, _fmt(nations[PLAYER].troops), _fmt(nations[PLAYER].gold), structs.size(), fallout_list.size(), trains.size(), boats.size(), attacks.size(), missiles.size(), _alive_count()])
				frames = 0; sec_worst = 0.0
				print("PERF t=%ds %s" % [sec, _pf_line()])
			if sec % 30 == 0: _shot("33_stress_%03d.png" % sec)
			if "--cycles" in OS.get_cmdline_user_args():
				var cy := _cycle_report()
				if cy != "": print("CYCLE ", cy)
			if sec % 7 == 0:
				var ids := []
				for id in range(2, nations.size()): if nations[id].alive and nations[id].land > 50: ids.append(id)
				if ids.size() > 0:
					var v: int = ids[rng.randi() % ids.size()]
					var tt := int(nations[v].sy / nations[v].land) * W + int(nations[v].sx / nations[v].land)
					nations[PLAYER].gold += 3e7
					_struct_add(5, _find_spawn_tile(st % W, st / W), PLAYER)
					for s5 in structs: if s5.o == PLAYER: s5.bt = 0.0
					launch_nuke(PLAYER, [7, 8, 11, 12][sec % 4], tt)
					var ok := intent_attack(PLAYER, tt, 0.3)
	print("STRESS DONE worst_ms=%.0f frames_over_50ms=%d" % [worst, hits])
	get_tree().quit()

func _alive_count() -> int:
	var c := 0
	for n in nations: if not n.is_empty() and n.alive: c += 1
	return c

# --uishot: upstream-HUD screenshots (spawn pick, mid-game with menus open, nukes in flight, end screens)
# into /workspace/shots/ui_match/raw_<width>/. Run under xvfb with --resolution WxH.
func _uishot_foe(st: int) -> Array:
	var cx := st % W; var cy := st / W
	for r in range(20, 260, 6):
		for k in 48:
			var a := TAU * k / 48.0
			var x := cx + int(cos(a) * r); var y := cy + int(sin(a) * r)
			if x < 0 or y < 0 or x >= W or y >= H: continue
			var t := y * W + x
			if owner_map[t] > PLAYER and nations[owner_map[t]].alive: return [owner_map[t], t]
	return [-1, -1]

func _uishot_mouse_at_tile(t: int) -> void:
	var sp := _screen_of(Vector2(t % W + 0.5, t / W + 0.5) * TS)
	var k := Vector2(get_window().size) / get_viewport().get_visible_rect().size
	get_viewport().warp_mouse(sp)
	Input.warp_mouse(sp * k)

func _uishot_rects(tag: String) -> void:
	var k := float(get_window().size.x) / get_viewport().get_visible_rect().size.x
	var f := FileAccess.open(shots_dir + "/" + tag + "_rects.json", FileAccess.WRITE)
	var d := {}
	for pair in [["top", hud.top], ["spawn", hud.spawn], ["board", hud.board], ["pill", hud.board_pill], ["atk", hud.atk], ["bar", hud.bar], ["feed", hud.feed], ["tip", tipc], ["topbar", hud.topbar], ["speed", hud.speed], ["alert", hud.alert]]:
		var c: Control = pair[1]
		if c.is_visible_in_tree():
			var r := c.get_global_rect()
			d[pair[0]] = [r.position.x * k, r.position.y * k, r.size.x * k, r.size.y * k]
	f.store_string(JSON.stringify(d))
	f.close()

func _uishot() -> void:
	var ws := get_window().size
	shots_dir = "/workspace/shots/ui_match/raw_%d" % ws.x
	DirAccess.make_dir_recursive_absolute(shots_dir)
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 30 / 100)
	cam.position = Vector2(st % W, st / W) * TS
	cam.zoom = Vector2(1.6, 1.6); _clamp_cam()
	for _f in 20: await get_tree().process_frame
	_uishot_mouse_at_tile(st)
	for _f in 20: await get_tree().process_frame
	_update_tooltip()
	_shot("1_spawn.png")
	_uishot_rects("1_spawn")
	_place_start(st); deploy_t = 4.4
	for _f in 8: await get_tree().process_frame
	_shot("1b_spawn_deploy.png")
	deploy_t = 0.0
	for _f in 40: await get_tree().process_frame
	peace = elapsed + 95.0
	_claim_blob(PLAYER, st, 40)
	nations[PLAYER].gold = 3.24e8; nations[PLAYER].troops = 1.59304e6
	_struct_add(5, st, PLAYER); _struct_add(0, st + 6, PLAYER)
	for s5 in structs: s5.bt = 0.0
	var fo := _uishot_foe(st)
	var foe: int = fo[0]
	if foe > 0:
		launch_attack(PLAYER, foe, 0.25)
		launch_attack(foe, PLAYER, 0.3)
	launch_attack(PLAYER, NEUTRAL, 0.1)
	notify("Your warship sank a transport from %s" % (_nname(foe) if foe > 0 else "a rival"), "good")
	notify("You captured a City from %s" % (_nname(foe) if foe > 0 else "a rival"), "good")
	notify("Not enough gold for a Hydrogen Bomb", "bad")
	notify("Your warship is returning to port for repairs", "info")
	if foe > 0: _show_ally_card("propose", foe)
	_focus_player(1.1)
	hud.set_board_open(true)
	for _f in 30: await get_tree().process_frame
	_update_hud()
	tip_slot = 8
	for _f in 12: await get_tree().process_frame
	_shot("2_mid.png")
	_uishot_rects("2_mid")
	tip_slot = -1
	hud.set_board_open(false)
	if foe > 0: _uishot_mouse_at_tile(fo[1])
	for _f in 12: await get_tree().process_frame
	_shot("2b_mid_tooltip.png")
	_uishot_rects("2b_mid_tooltip")
	if foe > 0:
		_open_diplo(foe, _screen_of(Vector2(fo[1] % W + 0.5, fo[1] / W + 0.5) * TS))
		for _f in 2: await get_tree().process_frame
		var dc := diplo_panel.get_global_rect().get_center()
		get_viewport().warp_mouse(dc); Input.warp_mouse(dc * Vector2(get_window().size) / get_viewport().get_visible_rect().size)
		for _f in 12: await get_tree().process_frame
		_shot("2c_diplo.png")
		diplo_panel.visible = false
	hud.open_menu()
	for _f in 30: await get_tree().process_frame
	_shot("3_menu.png")
	hud.close_menu()
	# nukes in flight: a rival bomb at us (alert banner) and ours with the seconds countdown
	if foe > 0:
		var ft: int = fo[1]
		_struct_add(5, ft, foe)
		for s5 in structs: s5.bt = 0.0
		nations[foe].gold = 1e9
		set_icbm(true)
		launch_nuke(foe, 7, st)
		var fo2 := _uishot_foe(st)
		if fo2[1] >= 0: launch_nuke(PLAYER, 8, fo2[1])
	set_icbm(false)
	build_sel = 7
	for _f in 50: await get_tree().process_frame
	if foe > 0: _uishot_mouse_at_tile(fo[1] + 30)
	for _f in 6: await get_tree().process_frame
	_shot("4_nuke.png")
	_uishot_rects("4_nuke")
	build_sel = -1
	# end screens (shown directly so the harness never touches the star save)
	state = "over"
	for n in hud_nodes: n.visible = false
	ally_card.visible = false
	hud.show_match()
	hud.show_over(true, {"title": "VICTORY", "sub": "You conquered the world with 81.2% of the land outside fallout.", "winner_id": PLAYER,
		"peak": "81.2%", "troops": _fmt(2.41e6), "kills": "14", "duration": "24:31", "stars": "+1,250", "next": "MEGA NUKE   1,250 / 4,000"})
	for _f in 60: await get_tree().process_frame
	_shot("5_end_victory.png")
	hud.show_over(false, {"title": "DEFEAT", "sub": "Your nation fell after holding up to 12.4% of the world.", "winner_id": foe if foe > 0 else -1,
		"peak": "12.4%", "troops": _fmt(5.3e5), "kills": "3", "duration": "11:02", "stars": "+180", "next": ""})
	for _f in 60: await get_tree().process_frame
	_shot("5b_end_defeat.png")
	get_tree().quit()

# --dmgshot: front troop labels (FrontLayer.luau port) in the user's report situation: expanding into
# wilderness with the Hydrogen Bomb tooltip open (upstream: no label), then real fronts out / in.
func _dmgshot() -> void:
	var ws := get_window().size
	shots_dir = "/workspace/shots/ui_match/raw_%d" % ws.x
	DirAccess.make_dir_recursive_absolute(shots_dir)
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 22 / 100)
	_place_start(st); deploy_t = 0.0
	for _f in 20: await get_tree().process_frame
	peace = elapsed + 95.0
	_claim_blob(PLAYER, st, 40)
	nations[PLAYER].gold = 3.24e8; nations[PLAYER].troops = 9.6e5
	_struct_add(5, st, PLAYER)
	for s5 in structs: s5.bt = 0.0
	launch_attack(PLAYER, NEUTRAL, 0.14)
	_focus_player(2.2)
	for _f in 30: await get_tree().process_frame
	_update_hud()
	tip_slot = 8
	for _f in 20: await get_tree().process_frame
	var n_lbl := 0
	for aid in _front_entries: n_lbl += _front_entries[aid].slots.size()
	print("DMGSHOT expand labels=%d attacks=%d" % [n_lbl, attacks.size()])
	_shot("dmg_1_expand_hbomb.png")
	tip_slot = -1
	var fo := [-1, -1]
	var cx0 := st % W; var cy0 := st / W
	for r in range(20, 400, 4):
		for kk in 64:
			var an := TAU * kk / 64.0
			var x := cx0 + int(cos(an) * r); var y := cy0 + int(sin(an) * r)
			if x < 0 or y < 0 or x >= W or y >= H: continue
			var t := y * W + x
			if owner_map[t] > PLAYER and nations[owner_map[t]].alive and kind_of(owner_map[t]) == SimRules.KIND_NATION:
				fo = [owner_map[t], t]; break
		if fo[0] > 0: break
	var foe: int = fo[0]
	if foe > 0:
		# a second patch of our land pressed against the nation so the two share a border
		var dv := (Vector2(cx0, cy0) - Vector2(fo[1] % W, fo[1] / W)).normalized()
		var pc := Vector2(fo[1] % W, fo[1] / W) + dv * 9.0
		_claim_blob(PLAYER, int(pc.y) * W + int(pc.x), 12)
		nations[foe].troops = maxf(nations[foe].troops, 4.0e5)
		peace = 0.0
		nations[PLAYER].troops = 9.6e5
		launch_attack(PLAYER, foe, 0.25)
		cam.position = Vector2(fo[1] % W, fo[1] / W) * TS
		_clamp_cam()
	for _f in 16: await get_tree().process_frame
	n_lbl = 0
	var txt := []
	for aid in _front_entries:
		n_lbl += _front_entries[aid].slots.size(); txt.append(("in " if _front_entries[aid].incoming else "out ") + _front_entries[aid].text + " x%d" % _front_entries[aid].slots.size())
	var mine := attacks.filter(func(a): return a.a == PLAYER or a.t == PLAYER).map(func(a): return [a.a, a.t, int(a.troops)])
	print("DMGSHOT state=%s border=%d mine=%s" % [state, border[PLAYER].size() if border.size() > PLAYER else -1, str(mine)])
	print("DMGSHOT fronts foe=%d kind=%d labels=%d %s" % [foe, kind_of(foe) if foe > 0 else -1, n_lbl, str(txt)])
	_shot("dmg_2_front_out.png")
	if foe > 0:
		nations[foe].troops = 2.5e6
		launch_attack(foe, PLAYER, 0.5)
	for _f in 16: await get_tree().process_frame
	txt = []
	for aid in _front_entries: txt.append(("in " if _front_entries[aid].incoming else "out ") + _front_entries[aid].text + " x%d" % _front_entries[aid].slots.size())
	print("DMGSHOT incoming %s" % str(txt))
	_shot("dmg_3_front_in.png")
	get_tree().quit()

# --shipshot: a transport, a trade ship and a warship near our port, close and zoomed out, into
# raw_<width>/ships_<tag>_{near,far}.png (tag from --shiptag=..., default "after").
func _shipshot() -> void:
	var tag := "after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shiptag="): tag = a.substr(10)
	var ws := get_window().size
	shots_dir = "/workspace/shots/ui_match/raw_%d" % ws.x
	DirAccess.make_dir_recursive_absolute(shots_dir)
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	rng.seed = 4242
	_start_game()
	var st := -1
	for k in 20000:
		var i := rng.randi() % (W * H)
		if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 300 and i / W > H / 5 and i / W < H * 3 / 5: st = i; break
	_place_start(st); deploy_t = 0.0
	for _f in 10: await get_tree().process_frame
	peace = elapsed + 95.0
	_claim_blob(PLAYER, st, 14)
	nations[PLAYER].gold = 1e9; nations[PLAYER].troops = 9.6e5
	var port_t := -1
	for r in range(0, 16):
		for k in 64:
			var an := TAU * k / 64.0
			var t := (st / W + int(sin(an) * r)) * W + st % W + int(cos(an) * r)
			if t >= 0 and t < W * H and owner_map[t] == PLAYER and _coastal(t): port_t = t; break
		if port_t >= 0: break
	_struct_add(1, port_t, PLAYER)
	for s5 in structs: s5.bt = 0.0
	var port: Dictionary = {}
	for s5 in structs:
		if s5.o == PLAYER and s5.k == 1: port = s5
	var ok_w := spawn_warship(PLAYER)
	for _f in 120:
		if sim_nav == null or sim_nav.ready: break
		await get_tree().process_frame
	print("SHIPSHOT nav=%s" % [sim_nav != null and sim_nav.ready])
	var _cands := 0
	# a trade ship out of our port and a transport heading back in, on real sea paths
	var paths := []
	for k in 6000:
		if paths.size() >= 2: break
		var jx := clampi(port_t % W + rng.randi_range(-90, 90), 0, W - 1)
		var jy := clampi(port_t / W + rng.randi_range(-90, 90), 0, H - 1)
		var j := jy * W + jx
		if owner_map[j] < 0 or owner_map[j] == PLAYER or not _coastal(j): continue
		var dd := Vector2(j % W, j / W).distance_to(Vector2(port_t % W, port_t / W))
		if dd < 30 or dd > 90: continue
		var pts := _water_path(port_t, j)
		_cands += 1
		if pts.size() < 2: continue
		var cum := PackedFloat32Array([0.0])
		for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
		if cum[cum.size() - 1] < 26.0 * TS: continue
		paths.append([pts, cum, j])
	var ok_t := paths.size() > 0
	var ok_b := paths.size() > 1
	if ok_t:
		traders.append({"o": PLAYER, "pts": paths[0][0], "cum": paths[0][1], "d": 12.0 * TS, "dst": port, "gold": 1.0})
	if ok_b:
		boat_uid += 1
		boats.append({"a": PLAYER, "troops": 4.0e4, "pts": paths[1][0], "cum": paths[1][1], "d": 14.0 * TS, "dest": paths[1][2], "sid": 3, "uid": boat_uid})
	print("SHIPSHOT cands=%d" % _cands)
	print("SHIPSHOT port=%d warship=%s trader=%s boat=%s boats=%d" % [port_t, ok_w, ok_t, ok_b, boats.size()])
	cam.position = Vector2(port_t % W, port_t / W) * TS
	var my_tr: Dictionary = traders[traders.size() - 1] if ok_t else {}
	var my_bt: Dictionary = boats[boats.size() - 1] if ok_b else {}
	for z in [[4.0, "near"], [1.6, "far"]]:
		cam.zoom = Vector2(z[0], z[0]); _clamp_cam()
		if ok_t and not traders.has(my_tr): traders.append(my_tr)
		if ok_b and not boats.has(my_bt): boats.append(my_bt)
		if ok_t: my_tr.d = 12.0 * TS
		if ok_b: my_bt.d = 14.0 * TS
		get_viewport().warp_mouse(Vector2(1590, 250)); Input.warp_mouse(Vector2(1590, 250) * Vector2(get_window().size) / get_viewport().get_visible_rect().size)
		for _f in 20: await get_tree().process_frame
		var c := Vector2.ZERO; var n := 0
		for bt in boats: c += _boat_pos(bt)[0]; n += 1
		for tr in traders.slice(traders.size() - 1): c += _boat_pos(tr)[0]; n += 1
		for w in warships: c += w.pos * TS; n += 1
		if n > 0 and z[1] == "near":
			cam.position = c / n; _clamp_cam()
			for _f in 3: await get_tree().process_frame
		_shot("ships_%s_%s.png" % [tag, z[1]])
	get_tree().quit()

func _hudshot() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 1e9
	_claim_blob(PLAYER, st, 40)
	nations[PLAYER].gold = 3.24e8; nations[PLAYER].troops = 1.59304e11
	_struct_add(5, st, PLAYER)
	for s5 in structs: s5.bt = 0.0
	for nd in hud_nodes: nd.visible = true; nd.modulate.a = 1.0; nd.position.y = nd.position.y
	_focus_player(0.8)
	for _f in 30: await get_tree().process_frame
	_update_hud()
	_shot("34_hud_icbm_off.png")
	set_icbm(true)
	tip_slot = 16
	for _f in 20: await get_tree().process_frame
	_shot("34_hud_icbm_on_tip.png")
	tip_slot = 8
	for _f in 10: await get_tree().process_frame
	_shot("34_hud_hbomb_tip.png")
	tip_slot = -1; build_sel = 8
	get_viewport().warp_mouse(Vector2(300, 300))
	for _f in 10: await get_tree().process_frame
	_shot("34_hbomb_range_icbm.png")
	get_tree().quit()


func _pt(ok: bool, what: String) -> void:
	print("PORTTEST %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok: _pt_fail += 1

func _pt_rearm() -> void:
	for st in structs:
		if st.o == PLAYER: st.shots = []

func _pt_ticks(n: int) -> void:
	for _i in n:
		_tick_attacks()
		_ai(0.1)
		sim_naval.tick()
		ticks_done += 1
		_economy(0.1)
		sim_ars.tick()
		sim_ws.tick()
		_trains_tick()
		_requests_tick()
		_tick_missiles(SimArsenal.DT_TICK)
		_tick_boats(0.1)

func _pt_free_land_near(o: int, c: int, r: int) -> int:
	var cx := c % W; var cy := c / W
	for rr in range(0, r):
		for k in 64:
			var x := clampi(cx + int(round(cos(k * TAU / 64.0) * rr)), 0, W - 1)
			var y := clampi(cy + int(round(sin(k * TAU / 64.0) * rr)), 0, H - 1)
			var t := y * W + x
			if owner_map[t] == o and not struct_at.has(t):
				var ok := true
				for st in structs:
					if Vector2(st.tile % W - x, st.tile / W - y).length() < sim_rules.struct_min_dist + 0.5: ok = false; break
				if ok: return t
	return -1

func _pt_center(o: int) -> int:
	var n = nations[o]
	var t := int(n.sy / maxf(1, n.land)) * W + int(n.sx / maxf(1, n.land))
	if owner_map[t] == o: return t
	for i in range(0, W * H, 7):
		if owner_map[i] == o: return i
	return -1

func _porttest_setup() -> Array:
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 50 / 100, H * 38 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 1e9
	_claim_blob(PLAYER, st, 80)
	nations[PLAYER].gold = 5e8
	_pt_ticks(150)
	nations[PLAYER].gold = 5e8
	# Arsenal unlocks for the test only (not saved: restored by _pt_restore); Rapid Reload stays off
	_pt_saved_unlocks = save.unlocked.duplicate()
	for it in ARSENAL:
		if int(it.get("k", -1)) >= 0 and it.id != "reload" and not (it.id in save.unlocked): save.unlocked.append(it.id)
	# biggest other nation that is not the player
	var foe := -1
	var bd := 1e18
	for id in range(2, nations.size()):
		if not nations[id].alive or nations[id].land < 100: continue
		var d := _tile_v(st).distance_to(_tile_v(_pt_center(id)))
		if d < bd and d > 160.0: bd = d; foe = id
	if foe > 0: _claim_blob(foe, _pt_center(foe), 60)
	return [st, foe]

func _tile_v(t: int) -> Vector2:
	return Vector2(t % W + 0.5, t / W + 0.5)

func _porttest() -> void:
	var t0 := Time.get_ticks_msec()
	var su := _porttest_setup()
	var home: int = su[0]; var foe: int = su[1]
	print("PORTTEST setup map=%s k_lin=%.4f player_land=%d foe=%d (%s) land=%d" % [str(MAPS[map_i][0]), sim_rules.k_lin, nations[PLAYER].land, foe, nations[foe].name if foe > 0 else "-", nations[foe].land if foe > 0 else 0])
	var R := sim_rules
	# ---- Rules formulas against hand values from Rules.luau
	_pt(absf(R.sam_range(1) - 70.0 * SimRules.SAM_RADIUS_MULT / R.k_lin) < 1e-6, "sam_range(1) = 70 full-size tiles x SAM_RADIUS_MULT")
	_pt(absf(R.sam_range_at(2, 0) - R.sam_range(1)) < 1e-6 and absf(R.sam_range_at(2, 45) - R.sam_range(2)) < 1e-6, "SAM range ramps over 45 ticks after an upgrade")
	_pt(SimRules.strike_kill(SimRules.N_SHELL, 10000.0, 1.0) == 1440.0 and SimRules.strike_kill(SimRules.N_SHELL, 1000000.0, 1.0) == 19200.0 and SimRules.strike_kill(SimRules.N_SHELL, 100000.0, 1.0) == 2880.0, "shell kill 2.88% clamped 1440..19200")
	_pt(SimRules.strike_kill(SimRules.N_AIRSTRIKE, 100000.0, 50.0) == 3000.0 and SimRules.strike_kill(SimRules.N_AIRSTRIKE, 100000.0, 200.0) == 6000.0, "air strike 60/tile up to 6%")
	_pt(SimRules.strike_kill(SimRules.N_SLUG, 100000.0, 10.0) == 1500.0 and SimRules.strike_kill(SimRules.N_SLUG, 100000.0, 100.0) == 4000.0, "slug 150/tile up to 4%")
	_pt(SimRules.warship_max_hp(0) == 1000 and SimRules.warship_max_hp(3) == 1600 and SimRules.shell_damage(1, 0) == 200 and SimRules.shell_damage(5, 0) == 300 and SimRules.shell_damage(5, 3) == 480, "warship hp / shell damage table")
	_pt(absf(SimRules.warhead_death(3000.0, 100000.0)) < 1e-9 and absf(SimRules.warhead_death(100000.0, 100000.0) - 500.0 * (1.0 - exp(-2.0 * 0.97))) < 1e-6, "warhead nukeDeathFactor")
	_pt(SimRules.train_spawn_rate(1, 0) == int(floor(165.0 / SimRules.train_saturation(0))) and SimRules.reinforce_troops(90.0, 100.0) == 10.0, "train spawn rate / reinforce clamp")
	_pt(absf(SimRules.inner_frac(SimRules.N_ATOM) - 0.4) < 1e-6 and absf(SimRules.inner_frac(SimRules.N_HYDROGEN) - 0.8) < 1e-6 and absf(SimRules.inner_frac(SimRules.N_WARHEAD) - 12.0 / 18.0) < 1e-6, "inner/outer blast shares")
	if foe <= 0:
		_pt(false, "found a foe nation"); get_tree().quit(1); return
	# ---- buildings: construction on the sim clock, instant upgrade with a reloading slot
	var built := {}
	for k in [5, 4, 2, 0, 0, 1, 10, 14, 15]:
		var t := _pt_free_land_near(PLAYER, home, 80)
		if k == 1:
			for i in range(0, W * H, 3):
				if owner_map[i] == PLAYER and _coastal(i): t = i; break
		if t < 0: continue
		var ok := try_build(k, t)
		if ok: built[k] = built.get(k, 0) + 1
	print("PORTTEST built ", built)
	var sam = null
	for st in structs: if st.o == PLAYER and st.k == 4: sam = st
	_pt(sam != null and absf(float(sam.bt) - 30.0) < 0.01, "SAM construction = 300 ticks (30 s)")
	_pt_ticks(305)
	var all_done := true
	for st in structs: if st.o == PLAYER and float(st.bt) > 0.0: all_done = false
	_pt(all_done, "every structure finished after 305 ticks")
	var lv0: int = sam.level
	var g0: float = nations[PLAYER].gold
	try_build(4, sam.tile)
	_pt(int(sam.level) == lv0 + 1 and float(sam.bt) <= 0.0 and sim_ars.ready_missiles(sam) == 1, "SAM upgrade is instant; the new missile slot starts reloading")
	print("PORTTEST sam upgrade cost ", g0 - nations[PLAYER].gold)
	_pt_ticks(95)
	_pt(sim_ars.ready_missiles(sam) == 2, "upgraded SAM holds 2 missiles after 90 ticks")
	# ---- artillery shells, air strike, slug
	var sh0: int = sim_ars.stats.shells
	var art = null
	for st in structs: if st.o == PLAYER and st.k == 10: art = st
	if art != null:
		# put an enemy structure in range
		var near_t := -1
		for i in range(0, W * H, 1):
			if owner_map[i] > 0 and owner_map[i] != PLAYER and _tile_v(i).distance_to(_tile_v(art.tile)) < sim_rules.artillery_range() - 2:
				near_t = i; break
		print("PORTTEST artillery enemy land in range: ", near_t >= 0)
		_pt_ticks(160)
		_pt(near_t < 0 or sim_ars.stats.shells > sh0, "artillery fired %d shells in 160 ticks" % (sim_ars.stats.shells - sh0))
	var air = null
	for st in structs: if st.o == PLAYER and st.k == 14: air = st
	if air != null:
		var tgt_a := -1
		for i in range(0, W * H, 5):
			if owner_map[i] > 0 and owner_map[i] != PLAYER and _tile_v(i).distance_to(_tile_v(air.tile)) < sim_rules.airfield_range() - 3:
				tgt_a = i; break
		if tgt_a < 0: print("PORTTEST SKIP air strike: no enemy land within airfield reach")
		if tgt_a >= 0:
			var vo: int = owner_map[tgt_a]
			var vt: float = nations[vo].troops
			var k0: int = sim_ars.stats.killed
			var okA := try_build(14, tgt_a)
			_pt(okA and not try_build(14, tgt_a), "air strike launched; airfield then rearming")
			_pt_ticks(1)
			var mt_left := 0
			for m in sim_ars.munitions: mt_left = maxi(mt_left, int(m.t1) - sim_atk.tick)
			_pt_ticks(mt_left + 1)
			print("PORTTEST airstrike victim %s troops %.0f -> %.0f (growth during flight included)" % [nations[vo].name, vt, nations[vo].troops])
			_pt(sim_ars.stats.killed > k0, "air strike killed %d troops" % (sim_ars.stats.killed - k0))
			_pt_ticks(300)
			_pt(sim_ars.ready_missiles(air) == 1, "airfield rearmed after 300 ticks")
	var rg = null
	for st in structs: if st.o == PLAYER and st.k == 15: rg = st
	if rg != null:
		var tgt_s := -1
		var far := 0.0
		for i in range(0, W * H, 97):
			if owner_map[i] > NEUTRAL and owner_map[i] != PLAYER and owner_map[i] != WATER:
				var dd := _tile_v(i).distance_to(_tile_v(rg.tile))
				if dd > far: far = dd; tgt_s = i
		var okS := try_build(15, tgt_s)
		_pt(okS, "railgun slug fired at any range (%.0f tiles)" % _tile_v(rg.tile).distance_to(_tile_v(tgt_s)))
		_pt_ticks(60)
	# ---- warships duel: shells, damage, veterancy
	var wt := -1
	for st in structs:
		if st.o == PLAYER and st.k == 1:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var j: int = st.tile + dy * W + dx
					if wt < 0 and j >= 0 and j < W * H and owner_map[j] == WATER and sim_naval.body[j] > 0: wt = j
	if wt < 0:
		# any open water touching our land (the port may have been snapped/lost)
		for i in range(W, W * H - W):
			if owner_map[i] == WATER and sim_naval.body[i] > 0 and (owner_map[i - 1] == PLAYER or owner_map[i + 1] == PLAYER or owner_map[i - W] == PLAYER or owner_map[i + W] == PLAYER):
				wt = i; break
	if wt < 0:
		for i in range(0, W * H, 13):
			if owner_map[i] == WATER and sim_naval.body[i] > 0: wt = i; break
	print("PORTTEST warship water tile ", wt, " ports=", owned(PLAYER, 1))
	if wt >= 0:
		var my_ws := {"o": PLAYER, "pos": _tile_v(wt), "home": wt, "hp": 1000.0, "vet": 0, "kills": 0, "tgt": _tile_v(wt), "cd": 0.0}
		sim_ws.init_ship(my_ws); warships.append(my_ws)
		var en_ws := {"o": foe, "pos": _tile_v(wt) + Vector2(1, 0), "home": wt, "hp": 1000.0, "vet": 0, "kills": 0, "tgt": _tile_v(wt), "cd": 0.0}
		if not _is_water(en_ws.pos): en_ws.pos = _tile_v(wt)
		sim_ws.init_ship(en_ws); warships.append(en_ws)
		var s0: int = sim_ws.stats.shots
		# up to 1000 ticks: with SimNav steering the ships manoeuvre (and may shell nearby boats first), so
		# the duel takes longer than the old straight-line 400 ticks
		for _r in 100:
			_pt_ticks(10)
			if not SimWarships.has_ref(warships, en_ws) or not SimWarships.has_ref(warships, my_ws): break
		print("PORTTEST warships shots=%d sunk=%d my_hp=%.0f en_hp=%.0f my_vet=%d" % [sim_ws.stats.shots - s0, sim_ws.stats.sunk_warships, my_ws.hp, en_ws.hp, my_ws.vet])
		var retreated: bool = int(en_ws.get("state", 0)) != 0 or int(my_ws.get("state", 0)) != 0
		_pt(sim_ws.stats.shots - s0 > 0 and (sim_ws.stats.sunk_warships >= 1 or retreated), "warships duel until one sinks or retreats at 75%% HP (state my=%d en=%d)" % [int(my_ws.get("state", 0)), int(en_ws.get("state", 0))])
	# ---- foe SAM intercepts a bomb along its path
	var fc := _pt_center(foe)
	var fsam_t := _pt_free_land_near(foe, fc, 60)
	_struct_add(4, fsam_t, foe); struct_at[fsam_t].bt = 0.0
	var fsam = struct_at[fsam_t]
	var aim := fsam_t + 8
	if owner_map[aim] != foe: aim = fsam_t
	set_icbm(true)
	var hits0: int = sim_ars.stats.sam_hits
	var ok1 := launch_nuke(PLAYER, 7, aim)
	var tl := 0
	while tl < 3000 and not missiles.is_empty():
		_pt_ticks(1); tl += 1
	_pt(ok1 and sim_ars.stats.sam_hits == hits0 + 1, "foe SAM shot down the atom bomb (fired %d, hit %d, %d ticks)" % [sim_ars.stats.sam_fired, sim_ars.stats.sam_hits, tl])
	_pt(sim_ars.ready_missiles(fsam) == 0, "the SAM spent its only missile")
	# ---- detonation: inner disc all fallout, outer ring about half; bomb troop loss ((T-n)/T)^5
	_struct_remove(fsam)
	# fresh target: the foe may have been conquered meanwhile
	if not nations[foe].alive or nations[foe].land < 300:
		var bl := 0
		for id in range(2, nations.size()):
			if nations[id].alive and nations[id].land > bl and _tile_v(_pt_center(id)).distance_to(_tile_v(home)) > 160.0: bl = nations[id].land; foe = id
		_claim_blob(foe, _pt_center(foe), 60)
	var aim2 := _pt_center(foe)
	var r8: float = NUKE_R[8]
	var b_land: int = nations[foe].land
	var b_tr: float = nations[foe].troops
	for st in structs.duplicate(): if st.o == foe and st.k == 4: _struct_remove(st)
	_pt_rearm()
	var ok2 := launch_nuke(PLAYER, 8, aim2)
	tl = 0
	while tl < 4000 and not missiles.is_empty():
		_pt_ticks(1); tl += 1
	var inner_n := 0; var inner_f := 0; var ring_n := 0; var ring_f := 0
	var cx := aim2 % W; var cy := aim2 / W
	var ri := int(ceil(r8))
	for y in range(maxi(0, cy - ri), mini(H, cy + ri + 1)):
		for x in range(maxi(0, cx - ri), mini(W, cx + ri + 1)):
			var d2 := float((x - cx) * (x - cx) + (y - cy) * (y - cy))
			var i := y * W + x
			if d2 > r8 * r8 or owner_map[i] == WATER: continue
			if d2 <= pow(r8 * 0.8, 2): inner_n += 1; inner_f += int(fallout[i] == 1)
			else: ring_n += 1; ring_f += int(fallout[i] == 1)
	var lost_land: int = b_land - nations[foe].land
	var expect := b_tr * pow(float(b_land - lost_land) / b_land, 5.0)
	print("PORTTEST hbomb inner %d/%d ring %d/%d lost_land=%d troops %.0f -> %.0f (expect <= %.0f, growth adds a little)" % [inner_f, inner_n, ring_f, ring_n, lost_land, b_tr, nations[foe].troops, expect])
	_pt(ok2 and inner_n > 0 and inner_f == inner_n, "H-bomb: whole inner disc is fallout")
	var ring_share := float(ring_f) / maxf(1.0, ring_n)
	_pt(ring_share > 0.35 and ring_share < 0.65, "H-bomb: about half the outer ring is fallout (%.2f)" % ring_share)
	_pt(nations[foe].troops <= expect + 400.0 * tl / 10.0 + 1.0, "bomb troop loss follows ((T-n)/T)^5")
	# ---- alliance break: >= 100 weighted full-size tiles of an ally inside the blast
	var ally := -1
	for id in range(2, nations.size()):
		if id != foe and nations[id].alive and nations[id].land > 100 and _tile_v(_pt_center(id)).distance_to(_tile_v(_pt_center(foe))) > 200 and _tile_v(_pt_center(id)).distance_to(_tile_v(home)) > 200: ally = id; break
	if ally > 0:
		_claim_blob(ally, _pt_center(ally), 50)
		form_alliance(PLAYER, ally)
		var was := allied(PLAYER, ally)
		_pt_rearm()
		var ac := _pt_center(ally)
		var aim3 := -1
		for rr in range(40, 120, 4):
			for kk in 48:
				var x := clampi(ac % W + int(cos(kk * TAU / 48.0) * rr), 0, W - 1)
				var y := clampi(ac / W + int(sin(kk * TAU / 48.0) * rr), 0, H - 1)
				var o3: int = owner_map[y * W + x]
				if aim3 < 0 and o3 != ally and o3 != PLAYER and o3 != WATER: aim3 = y * W + x
		print("PORTTEST ally %d land=%d aim owner=%d dist=%.0f" % [ally, nations[ally].land, owner_map[aim3] if aim3 >= 0 else -9, _tile_v(aim3).distance_to(_tile_v(ac)) if aim3 >= 0 else -1.0])
		launch_nuke(PLAYER, 8, aim3)
		_pt(was and not allied(PLAYER, ally), "nuking an ally's land breaks the alliance at launch")
		# allied target is refused before that (can't nuke an ally): re-ally and try again
		form_alliance(PLAYER, ally)
		_pt_rearm()
		_pt(not launch_nuke(PLAYER, 7, _pt_center(ally)), "can't nuke an ally's land")
		break_alliance(PLAYER, ally)
	tl = 0
	while tl < 4000 and not missiles.is_empty():
		_pt_ticks(1); tl += 1
	# ---- scattershot: 4..6 warheads
	var nm0 := missiles.size()
	_pt_rearm()
	var sc_t := -1
	var bl2 := 0
	for id in range(2, nations.size()):
		if nations[id].alive and nations[id].land > bl2 and not allied(PLAYER, id) and _tile_v(_pt_center(id)).distance_to(_tile_v(home)) > 160.0: bl2 = nations[id].land; sc_t = _pt_center(id)
	var sc_ok := launch_nuke(PLAYER, 12, sc_t)
	print("PORTTEST scatter target owner=%d land=%d ok=%s" % [owner_map[sc_t] if sc_t >= 0 else -9, bl2, str(sc_ok)])
	var wh := 0
	for ms in missiles: if ms.get("nk", -1) == SimRules.N_WARHEAD and ms.k == 12: wh += 1
	_pt(wh >= 1 and wh <= 6 and missiles.size() - nm0 == wh + 1, "scattershot: core + %d warheads (4-6 minus own/ally land)" % wh)
	tl = 0
	while tl < 4000 and not missiles.is_empty():
		_pt_ticks(1); tl += 1
	set_icbm(false)
	# ---- structure health: an air strike knocks a level off, then destroys
	var city2 = null
	for st in structs: if st.o != PLAYER and st.o > NEUTRAL: city2 = st; break
	if city2 != null:
		city2.level = 2; city2.hp = sim_ars.struct_hp_full(city2)
		sim_ars.damage_struct(city2, 1000, PLAYER)
		var lv_after: int = city2.level
		sim_ars.damage_struct(city2, 2000, PLAYER)
		_pt(lv_after == 1 and not is_same(struct_at.get(city2.tile), city2), "structure HP: 0 HP drops a level, then destroys at level 1")
	# ---- reinforcements
	var cap := troop_cap(PLAYER)
	nations[PLAYER].troops = cap * 0.5
	nations[PLAYER].reinf_cd = 0.0
	var gb: float = nations[PLAYER].gold
	try_build(13, -1)
	_pt(absf(nations[PLAYER].troops - (floor(cap * 0.5) + floor(cap * 0.2))) <= 1.0 and absf(gb - nations[PLAYER].gold - 100000.0) < 1.0, "reinforcements: +20% cap for 100K")
	# ---- trains from factories along the road tree
	var tr_n := 0
	var g_before: float = nations[PLAYER].gold
	for _r in 6:
		_pt_ticks(100)
		tr_n = maxi(tr_n, trains.size())
	var links := 0
	for st in structs: if st.o == PLAYER: links += _rail_neighbors(st).size()
	print("PORTTEST rails links=%d trains_peak=%d" % [links, tr_n])
	_pt(links == 0 or tr_n > 0, "factories dispatch trains when rails exist")
	# ---- longer soak: AI + everything for 3000 ticks, no errors, timing
	var ts := Time.get_ticks_msec()
	_pt_ticks(3000)
	print("PORTTEST soak 3000 ticks %.1f ms/tick structs=%d trains=%d warships=%d munitions=%d alive=%d" % [float(Time.get_ticks_msec() - ts) / 3000.0, structs.size(), trains.size(), warships.size(), sim_ars.munitions.size(), _alive_count()])
	print("PORTTEST stats ars=%s ws=%s" % [str(sim_ars.stats), str(sim_ws.stats)])
	save.unlocked = _pt_saved_unlocks
	print("PORTTEST %s fails=%d (%.1f s)" % ["OK" if _pt_fail == 0 else "FAIL", _pt_fail, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(0 if _pt_fail == 0 else 1)

# render shots of the new visuals (needs a display: xvfb-run)
func _portshot() -> void:
	shots_dir = "/workspace/shots"
	var su := _porttest_setup()
	var home: int = su[0]; var foe: int = su[1]
	for k in [5, 4, 10, 14, 15, 2, 0]:
		var t := _pt_free_land_near(PLAYER, home, 80)
		if t >= 0: try_build(k, t)
	for st in structs: st.bt = 0.05
	_pt_ticks(5)
	set_icbm(true)
	var fc := _pt_center(foe)
	var fsam_t := _pt_free_land_near(foe, fc, 60)
	_struct_add(4, fsam_t, foe); struct_at[fsam_t].bt = 0.0
	launch_nuke(PLAYER, 7, fsam_t)
	var air = null
	for st in structs: if st.o == PLAYER and st.k == 14: air = st
	var tgt_a := -1
	if air != null:
		for i in range(0, W * H, 5):
			if owner_map[i] > 0 and owner_map[i] != PLAYER and _tile_v(i).distance_to(_tile_v(air.tile)) < sim_rules.airfield_range() * 0.8:
				tgt_a = i; break
	if tgt_a >= 0: try_build(14, tgt_a)
	_pt_ticks(12)
	pick_panel.visible = false
	for n in hud_nodes:
		var nd: Control = n
		nd.visible = true; nd.modulate.a = 1.0
	warp_away()
	_update_hud()
	_focus_player(1.4)
	for _f in 8: await get_tree().process_frame
	_shot("40_port_strike_inflight.png")
	# advance until the SAM fires
	var tl := 0
	while tl < 2000 and sim_ars.sam_shots.is_empty() and not missiles.is_empty():
		_pt_ticks(1); tl += 1
	_pt_ticks(3)
	if not missiles.is_empty():
		var ms = missiles[0]
		var mp: Vector2 = _missile_world_pos(ms, clampf(ms.t / ms.dur, 0, 1))
		cam.position = mp; cam.zoom = Vector2(1.6, 1.6); _clamp_cam()
	for _f in 8: await get_tree().process_frame
	_shot("41_port_sam_intercept.png")
	build_sel = 14
	var ap := Vector2(home % W, home / W) * TS
	cam.position = ap; cam.zoom = Vector2(0.9, 0.9); _clamp_cam()
	for _f in 4: await get_tree().process_frame
	if tgt_a >= 0: get_viewport().warp_mouse(_screen_of(_tile_v(tgt_a) * TS) / get_viewport().get_canvas_transform().get_scale() if false else get_viewport().get_visible_rect().size * 0.5)
	for _f in 6: await get_tree().process_frame
	_shot("42_port_airfield_aim.png")
	build_sel = -1
	warp_away()
	for _f in 4: await get_tree().process_frame
	_shot("43_port_hud.png")
	tip_slot = 14
	for _f in 12: await get_tree().process_frame
	_shot("44_port_tip_airfield.png")
	tip_slot = 15
	for _f in 12: await get_tree().process_frame
	_shot("45_port_tip_railgun.png")
	tip_slot = 10
	for _f in 12: await get_tree().process_frame
	_shot("46_port_tip_artillery.png")
	tip_slot = -1
	cam.position = Vector2(W * 0.5, H * 0.86) * TS; cam.zoom = Vector2(0.75, 0.75); _clamp_cam()
	for _f in 8: await get_tree().process_frame
	_shot("47_world_antarctica.png")
	get_tree().quit()


# ================= headless Sim entry (sim/headless_sim.gd wraps these; tests/upstream live cases) =================
# Starts a match without the menu: map_tab 0 real maps / 1 random / 2 RoWorld maps. `at` is the player's
# spawn as a fraction of the map. Returns the player's start tile.
func sim_start(tab := 0, idx := 0, at := Vector2(0.5, 0.38), claim_r := 0, gold := -1.0) -> int:
	if play_dialog: play_dialog.visible = false
	map_tab = tab; map_i = idx
	_start_game()
	var st := _find_spawn_tile(int(W * at.x), int(H * at.y))
	_place_start(st); deploy_t = 0.0; state = "play"
	if claim_r > 0: _claim_blob(PLAYER, st, claim_r)
	if gold >= 0.0: nations[PLAYER].gold = gold
	return st

# Advances n sim ticks (10 per second at 1x): attacks, AI, naval, economy, arsenal, warships, trains,
# alliance requests, missiles (custom flight clock: DT_TICK per tick), boats.
func sim_step(n := 1) -> void:
	_pt_ticks(n)

func sim_tick() -> int:
	return sim_atk.tick


# debug: report a reference cycle among sim containers (deep == / hash on such data recurses forever)
func _cyc(v, stack: Array, path: String, depth: int) -> String:
	if depth > 12: return ""
	if v is Dictionary or v is Array:
		for x in stack:
			if is_same(x, v): return path
		stack.append(v)
		if v is Dictionary:
			for k in v:
				var r := _cyc(v[k], stack, path + "." + str(k), depth + 1)
				if r != "": return r
		else:
			for i in mini(v.size(), 64):
				var r := _cyc(v[i], stack, path + "[%d]" % i, depth + 1)
				if r != "": return r
		stack.pop_back()
	return ""

func _cycle_report() -> String:
	var tops := {"structs": structs, "missiles": missiles, "warships": warships, "boats": boats, "traders": traders, "trains": trains, "attacks": attacks, "sam_shots": sim_ars.sam_shots, "munitions": sim_ars.munitions, "shells": sim_ws.shells, "blasts": blasts}
	for nm in tops:
		var arr: Array = tops[nm]
		for i in mini(arr.size(), 400):
			var r := _cyc(arr[i], [], nm + "[%d]" % i, 0)
			if r != "": return r
	return ""
