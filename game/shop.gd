extends "res://game/end_screen.gd"
# Shop and arsenal (stars menu)

func _open_shop() -> void:
	_refresh_arsenal()
	# the end-of-match overlay sits above the shop and swallowed its clicks (softlock): hide it while the shop is open
	if hud != null and hud.over != null and hud.over.visible:
		_shop_hid_over = true; hud.over.visible = false
	arsenal_dlg.move_to_front()
	_pop_in(arsenal_dlg)

func _close_shop() -> void:
	if arsenal_dlg == null or not arsenal_dlg.visible: return
	_fade_out(arsenal_dlg)
	if _shop_hid_over and hud != null and hud.over != null and state == "over":
		hud.over.visible = true
	_shop_hid_over = false

func unlock_arsenal_item(id: String) -> bool:
	for it in ARSENAL:
		if it.id == id and not unlocked(id) and save.stars >= it.cost:
			save.stars -= it.cost
			save.unlocked.append(id)
			write_save()
			notify("%s unlocked in Shop!" % it.name, "good")
			_refresh_arsenal()
			return true
	return false

func _build_arsenal() -> void:
	arsenal_dlg = Control.new(); arsenal_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); arsenal_dlg.visible = false
	ui.add_child(arsenal_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.65); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	arsenal_dlg.add_child(sh)
	var p := _P(arsenal_dlg, Rect2(150, 32, 1300, 836), Color(0.07, 0.085, 0.15, 0.98), 5)
	_draw_ctl(p, Rect2(28, 22, 34, 38), func(cc: Control):
		cc.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(34, 0), Vector2(34, 20), Vector2(17, 38), Vector2(0, 20)]), ORANGE_Y)
		_star(cc, Vector2(17, 16), 9, Color(0.15, 0.1, 0.03)))
	_head(p, "SHOP & ARSENAL", Vector2(76, 16), 28, TEXT)
	_T(p, "Earn Stars in matches and spend them here to unlock weapons & perks for your build bar.", Vector2(76, 52), 14, MUTED)
	# Integrated Stars earning breakdown + Next Unlock progress bar right in the Shop header
	var star_info := _P(p, Rect2(28, 78, 996, 36), Color(0.11, 0.135, 0.22, 0.95), 4, Color(1, 0.82, 0.36, 0.28), 1, false)
	_draw_ctl(star_info, Rect2(10, 8, 20, 20), func(cc: Control): _star(cc, Vector2(10, 10), 8, GOLD_C))
	arsenal_sub_earn = _T(star_info, "", Vector2(36, 9), 12, Color(0.9, 0.92, 0.98), f_bold, 656)
	arsenal_next_bar = _draw_ctl(star_info, Rect2(700, 8, 284, 20), func(cc: Control):
		var nl := next_locked()
		cc.draw_style_box(_flat(Color(0.06, 0.08, 0.14), 4), Rect2(0, 0, 284, 20))
		if nl.is_empty():
			cc.draw_style_box(_flat(Color(0.25, 0.55, 0.35), 4), Rect2(0, 0, 284, 20))
		else:
			var prog := clampf(float(save.stars) / maxf(1.0, float(nl.cost)), 0.0, 1.0)
			cc.draw_style_box(_flat(Color(0.55, 0.44, 0.16), 4), Rect2(0, 0, maxf(6.0, 284.0 * prog), 20)))
	arsenal_next_lbl = _T(star_info, "", Vector2(708, 9), 12, GOLD_C, f_bold, 268, HORIZONTAL_ALIGNMENT_CENTER)
	var bal := _P(p, Rect2(1038, 22, 182, 50), Color(0.25, 0.2, 0.08, 0.55), 5, Color(1, 0.8, 0.3, 0.6), 1, false)
	_draw_ctl(bal, Rect2(14, 13, 24, 24), func(cc: Control): _star(cc, Vector2(12, 12), 10, GOLD_C))
	arsenal_bal = _T(bal, "", Vector2(44, 6), 20, GOLD_C, f_bold, 128)
	_T(bal, "STAR BALANCE", Vector2(44, 30), 10, MUTED, f_bold, 128)
	var x := _card_btn(p, Rect2(1232, 22, 44, 44)); x.text = "✕"
	x.pressed.connect(_close_shop)
	sh.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _close_shop())
	for k in ARSENAL.size():
		var it = ARSENAL[k]
		var cx := 28 + (k % 4) * 314
		var cy := 124 + (k / 4) * 350
		var c := _P(p, Rect2(cx, cy, 302, 338), CELL_BG, 5, Color(1, 1, 1, 0.08), 1, false)
		var kk: int = k
		_draw_ctl(c, Rect2(1, 1, 300, 146), func(cc: Control): _draw_card_art(cc, kk))
		_head(c, it.name.to_upper(), Vector2(16, 154), 17, TEXT)
		var d := _T(c, it.desc, Vector2(16, 182), 14, Color(0.8, 0.84, 0.94)); d.size = Vector2(270, 40); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for b in 2:
			_T(c, "•  " + it.b[b].to_upper(), Vector2(16, 226 + b * 20), 12, GOLD_C, f_bold)
		var bar := _draw_ctl(c, Rect2(16, 276, 270, 20), func(cc: Control):
			var v := clampf(float(save.stars) / maxf(1, it.cost), 0, 1)
			cc.draw_style_box(_flat(Color(0.2, 0.24, 0.36), 4), Rect2(0, 0, 270, 20))
			cc.draw_style_box(_flat(Color(0.55, 0.45, 0.2), 4), Rect2(0, 0, maxf(6, 270 * v), 20))
			_star(cc, Vector2(96, 10), 7, GOLD_C)
			f_bold.draw_string(cc.get_canvas_item(), Vector2(108, 15), _fmt_int(it.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT))
		var btn := _big_btn(c, Rect2(16, 300, 270, 30), "UNLOCK", Color(0.3, 0.75, 0.45), 14)
		var item_id: String = it.id
		btn.pressed.connect(func(): unlock_arsenal_item(item_id))
		var owned_b := _card_btn(c, Rect2(16, 284, 270, 44)); owned_b.text = "UNLOCKED"; owned_b.disabled = true
		owned_b.add_theme_stylebox_override("disabled", _flat(Color(0.18, 0.15, 0.08), 4, Color(1, 0.75, 0.3, 0.55), 1))
		owned_b.add_theme_font_override("font", f_head); owned_b.add_theme_font_size_override("font_size", 15)
		owned_b.add_theme_color_override("font_disabled_color", GOLD_C)
		arsenal_cards.append({"bar": bar, "btn": btn, "owned": owned_b, "id": it.id, "cost": it.cost})

func _refresh_arsenal() -> void:
	arsenal_bal.text = _fmt_int(save.stars)
	if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
	if arsenal_sub_earn:
		var mult_txt := "2X ACTIVE!" if unlocked("x2") else "1x (2x Stars doubles payout)"
		arsenal_sub_earn.text = "STARS PER MATCH: +20/Land %  ·  +150/Elim  ·  +1,500 Win  ·  +10/min  ·  " + mult_txt
	if arsenal_next_lbl:
		var nl := next_locked()
		if nl.is_empty():
			arsenal_next_lbl.text = "ALL 8 SHOP ITEMS UNLOCKED!"
		else:
			arsenal_next_lbl.text = "NEXT: %s (%s / %s ★)" % [nl.name.to_upper(), _fmt_int(mini(save.stars, nl.cost)), _fmt_int(nl.cost)]
	if arsenal_next_bar:
		arsenal_next_bar.queue_redraw()
	for c in arsenal_cards:
		var u := unlocked(c.id)
		c.bar.visible = not u; c.btn.visible = not u; c.owned.visible = u
		c.btn.disabled = save.stars < c.cost
		c.btn.text = "UNLOCK" if save.stars >= c.cost else "NEED %s MORE" % _fmt_int(c.cost - save.stars)
		c.bar.queue_redraw()
	for b in build_btns: for ch in b.get_children(): if ch is Control: ch.queue_redraw()

func _draw_card_art(cc: Control, k: int) -> void:
	var it = ARSENAL[k]
	var left := Color(0.72, 0.62, 0.95)
	var right := Color(0.55, 0.78, 0.45)
	if it.id == "x2": left = Color(0.35, 0.25, 0.1); right = Color(0.45, 0.32, 0.12)
	cc.draw_rect(Rect2(0, 0, 112, 150), left)
	cc.draw_rect(Rect2(112, 0, 188, 150), right)
	cc.draw_line(Vector2(112, 0), Vector2(112, 150), Color(1, 1, 1, 0.5), 3)
	# left: the tool, drawn with the game's own icon set
	if it.k >= 0:
		_icon(Vector2(56, 70), it.k, Color(0.25, 0.2, 0.45), 1.0, cc, 26.0, true)
	elif it.id == "x2":
		_star(cc, Vector2(56, 72), 34, GOLD_C)
	else:
		for b in 3: cc.draw_rect(Rect2(26, 40 + b * 26, 60, 14), Color(0.25, 0.2, 0.45)); cc.draw_rect(Rect2(26, 40 + b * 26, 60 - b * 18, 14), Color(1, 0.5, 0.7))
	# right: the effect
	var c := Vector2(206, 78)
	match it.id:
		"mega":
			cc.draw_circle(c, 56, Color(0.3, 0.6, 0.25, 0.8)); cc.draw_circle(c, 34, Color(0.95, 0.75, 0.35)); cc.draw_circle(c, 16, Color(1, 0.95, 0.8))
		"scatter":
			cc.draw_circle(c, 18, Color(0.95, 0.7, 0.3))
			for m in 5: cc.draw_circle(c + Vector2.from_angle(m * TAU / 5) * 44, 10, Color(0.95, 0.6, 0.25, 0.85))
		"reinf":
			for m in 6: cc.draw_circle(Vector2(150 + (m % 3) * 32, 50 + (m / 3) * 40), 10, Color(0.25, 0.3, 0.45))
			cc.draw_rect(Rect2(256, 66, 8, 26), Color.WHITE); cc.draw_rect(Rect2(247, 75, 26, 8), Color.WHITE)
		"art":
			cc.draw_arc(Vector2(120, 140), 120, -PI / 2, 0, 24, Color(1, 1, 1, 0.5), 2)
			cc.draw_circle(c + Vector2(10, -6), 16, Color(1, 0.55, 0.2)); cc.draw_circle(c + Vector2(10, -6), 8, Color(1, 0.9, 0.6))
		"air":
			for m in 3: cc.draw_circle(Vector2(170 + m * 30, 100 - m * 18), 12, Color(0.35, 0.3, 0.2, 0.7))
			cc.draw_line(Vector2(130, 30), Vector2(290, 60), Color(1, 1, 1, 0.6), 2)
		"rail":
			cc.draw_line(Vector2(120, 20), c, Color(0.6, 0.9, 1.0), 5); cc.draw_line(Vector2(120, 20), c, Color.WHITE, 2)
			cc.draw_circle(c, 12, Color(0.8, 0.95, 1.0))
		"x2":
			f_head.draw_string(cc.get_canvas_item(), Vector2(150, 96), "2X", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, GOLD_C)
		"reload":
			cc.draw_arc(c, 30, -PI * 0.2, PI * 1.4, 24, Color.WHITE, 5)
			cc.draw_colored_polygon(PackedVector2Array([c + Vector2(30, -18), c + Vector2(42, 2), c + Vector2(20, 0)]), Color.WHITE)
	if not unlocked(it.id):
		cc.draw_rect(Rect2(0, 0, 300, 150), Color(0, 0, 0, 0.35))


func _end_icon(cc: Control, kk: int, col: Color) -> void:
	var o := Vector2(15, 15)
	match kk:
		0:
			cc.draw_arc(o, 11, 0, TAU, 24, col, 2, true); cc.draw_line(o - Vector2(11, 0), o + Vector2(11, 0), col, 1.5)
			cc.draw_arc(o, 5, -PI / 2, PI / 2, 10, col, 1.5); cc.draw_arc(o, 5, PI / 2, PI * 1.5, 10, col, 1.5)
		1:
			cc.draw_arc(o + Vector2(0, 4), 11, PI, TAU, 16, col, 6); cc.draw_line(o + Vector2(-14, 5), o + Vector2(14, 5), col, 2.5)
		2:
			cc.draw_line(o + Vector2(-10, -10), o + Vector2(10, 10), col, 3); cc.draw_line(o + Vector2(10, -10), o + Vector2(-10, 10), col, 3)
			cc.draw_circle(o, 4, col)
		3:
			cc.draw_arc(o, 11, 0, TAU, 24, col, 2, true); cc.draw_line(o, o + Vector2(0, -7), col, 2); cc.draw_line(o, o + Vector2(5, 3), col, 2)

# ================= v9: Settings & Graphics Modal + Password-Protected Tab Console =================
func _draw_gear(c: Control, o: Vector2, r: float, col: Color) -> void:
	for m in 8:
		var a := float(m) * TAU / 8.0
		c.draw_line(o + Vector2.from_angle(a) * (r * 0.65), o + Vector2.from_angle(a) * (r * 1.08), col, 2.6)
	c.draw_circle(o, r * 0.78, col)
	c.draw_circle(o, r * 0.36, Color(0.07, 0.09, 0.16))

func _open_settings() -> void:
	_refresh_settings()
	_pop_in(settings_dlg)

func _build_settings() -> void:
	settings_dlg = Control.new(); settings_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); settings_dlg.visible = false
	ui.add_child(settings_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.65); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_dlg.add_child(sh)
	var p := _P(settings_dlg, Rect2(260, 14, 1080, 872), Color(0.07, 0.085, 0.15, 0.98), 8)
	_draw_ctl(p, Rect2(32, 24, 34, 34), func(cc: Control): _draw_gear(cc, Vector2(17, 17), 13.0, CYAN))
	_head(p, "SETTINGS & GRAPHICS", Vector2(78, 18), 28, TEXT)
	_T(p, "Configure display resolution (up to 1440p), 180 FPS cap, anti-aliasing, and visual quality.", Vector2(78, 54), 14, MUTED)
	var x := _card_btn(p, Rect2(1012, 20, 42, 42)); x.text = "✕"
	x.pressed.connect(func(): _fade_out(settings_dlg))
	# Row 1: Display Resolution (up to 2560 x 1440 / 1440p)
	_head(p, "DISPLAY RESOLUTION  (MAX 1440P)", Vector2(36, 102), 12, GOLD_C)
	settings_btns["res"] = []
	for k in RES_NAMES.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 126, 242, 54))
		_T(b, RES_NAMES[k], Vector2(0, 16), 14, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["res_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["res"].append(b)
	# Row 2: Window Mode
	_head(p, "WINDOW MODE", Vector2(36, 198), 12, CYAN)
	var wmodes := ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
	settings_btns["win"] = []
	for k in wmodes.size():
		var b := _card_btn(p, Rect2(36 + k * 340, 222, 324, 50))
		_T(b, wmodes[k], Vector2(0, 14), 15, TEXT, f_bold, 324, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["win_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["win"].append(b)
	# Row 3: Max Frame Rate Cap (up to 180 FPS)
	_head(p, "MAX FRAME RATE CAP  (DEFAULT 180 FPS)", Vector2(36, 290), 12, GOLD_C)
	settings_btns["fps"] = []
	for k in FPS_LIST.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 314, 242, 50))
		_T(b, "%d FPS%s" % [FPS_LIST[k], " (MAX)" if k == 3 else ""], Vector2(0, 14), 15, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["fps_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["fps"].append(b)
	# Row 4: Graphics & Trail Animation Quality
	_head(p, "GRAPHICS & MISSILE TRAIL QUALITY", Vector2(36, 382), 12, CYAN)
	var qdescs := ["LOW · flat pixels", "MEDIUM · smooth", "HIGH · relief + waves", "ULTRA · full detail + glow"]
	var sl := HSlider.new()
	sl.min_value = 0; sl.max_value = 3; sl.step = 1; sl.tick_count = 4; sl.ticks_on_borders = true
	sl.position = Vector2(48, 410); sl.size = Vector2(980, 24)
	sl.value = clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)
	p.add_child(sl)
	settings_btns["qual"] = []
	for k in QUAL_NAMES.size():
		settings_btns["qual"].append(_T(p, qdescs[k], Vector2(36 + k * 254, 438), 13, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER))
	settings_btns["qual_slider"] = sl
	sl.value_changed.connect(func(v: float):
		if int(v) == int(save.settings.get("qual_i", 3)): return
		save.settings["qual_i"] = int(v)
		write_save(); apply_settings(); _refresh_settings())
	# Row 5: Anti-Aliasing (2D MSAA)
	_head(p, "ANTI-ALIASING  (2D MSAA & SMOOTH VECTORS)", Vector2(36, 478), 12, GOLD_C)
	settings_btns["msaa"] = []
	for k in MSAA_NAMES.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 502, 242, 50))
		_T(b, MSAA_NAMES[k], Vector2(0, 14), 15, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["msaa_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["msaa"].append(b)
	# Row 6: V-Sync & Screen Shake Intensity
	_head(p, "V-SYNC & BLAST SCREEN SHAKE", Vector2(36, 570), 12, CYAN)
	var vs_b := _card_btn(p, Rect2(36, 594, 324, 50))
	settings_btns["vsync_lbl"] = _T(vs_b, "V-Sync: OFF (Uncapped 180 FPS)", Vector2(0, 14), 14, TEXT, f_bold, 324, HORIZONTAL_ALIGNMENT_CENTER)
	vs_b.pressed.connect(func():
		save.settings["vsync"] = not bool(save.settings.get("vsync", false))
		write_save(); apply_settings(); _refresh_settings())
	settings_btns["vsync"] = vs_b
	var sh_names := ["Shake: Off", "Shake: Light (Default)", "Shake: Strong"]
	settings_btns["shake"] = []
	for k in 3:
		var b := _card_btn(p, Rect2(380 + k * 224, 594, 212, 50))
		_T(b, sh_names[k], Vector2(0, 14), 14, TEXT, f_bold, 212, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["shake_i"] = kk
			write_save(); _refresh_settings()
			if kk > 0: _add_shake(3.2 if kk == 1 else 5.5))
		settings_btns["shake"].append(b)
	# Row 7: Audio volumes (Master / Music / SFX), saved in save.settings
	_head(p, "AUDIO VOLUME", Vector2(36, 662), 12, GOLD_C)
	var mus_b := _btn("MUSIC: ON" if bool(save.settings.get("music_on", true)) else "MUSIC: OFF", bool(save.settings.get("music_on", true)))
	mus_b.position = Vector2(924, 654); mus_b.size = Vector2(120, 26); mus_b.add_theme_font_size_override("font_size", 12)
	p.add_child(mus_b)
	_pill(mus_b, bool(save.settings.get("music_on", true)), 13)
	mus_b.pressed.connect(func():
		var on := not bool(save.settings.get("music_on", true))
		save.settings["music_on"] = on
		mus_b.text = "MUSIC: ON" if on else "MUSIC: OFF"; _pill(mus_b, on, 13)
		_apply_volumes()
		if on: _play_music()
		else: _stop_music()
		write_save())
	var vkeys := [["vol_master", "Master", 0.8], ["vol_music", "Music", 0.5], ["vol_sfx", "SFX", 0.8]]
	for k in vkeys.size():
		var vk: String = vkeys[k][0]
		var vx := 36 + k * 340
		var vl := _T(p, "", Vector2(vx, 686), 14, TEXT, f_bold, 324)
		var vs_sl := HSlider.new()
		vs_sl.min_value = 0; vs_sl.max_value = 100; vs_sl.step = 1
		vs_sl.position = Vector2(vx, 712); vs_sl.size = Vector2(316, 24)
		vs_sl.value = roundi(float(save.settings.get(vk, vkeys[k][2])) * 100.0)
		p.add_child(vs_sl)
		var vname: String = vkeys[k][1]
		vl.text = "%s: %d%%" % [vname, int(vs_sl.value)]
		settings_btns["vol_" + str(k)] = vs_sl
		vs_sl.value_changed.connect(func(v: float):
			save.settings[vk] = v / 100.0
			vl.text = "%s: %d%%" % [vname, int(v)]
			_apply_volumes())
		vs_sl.drag_ended.connect(func(_c: bool): write_save())
	var status_bar := _P(p, Rect2(36, 754, 1008, 30), Color(0.04, 0.06, 0.11, 0.95), 4, Color(0.35, 0.80, 1.0, 0.35), 1, false)
	settings_status_lbl = _T(status_bar, "", Vector2(12, 5), 13, CYAN, f_bold, 984)
	var done_b := _big_btn(p, Rect2(764, 798, 280, 52), "APPLY & CLOSE", ORANGE_Y, 18)
	done_b.pressed.connect(func(): write_save(); apply_settings(); _fade_out(settings_dlg))

func _refresh_settings() -> void:
	if settings_dlg == null or settings_btns.is_empty(): return
	var cfg: Dictionary = save.get("settings", {})
	var res_i := clampi(int(cfg.get("res_i", 3)), 0, 3)
	var win_i := clampi(int(cfg.get("win_i", 0)), 0, 2)
	var fps_i := clampi(int(cfg.get("fps_i", 3)), 0, 3)
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var shake_i := clampi(int(cfg.get("shake_i", 1)), 0, 2)
	var vs := bool(cfg.get("vsync", false))
	for k in 4:
		_card_style(settings_btns["res"][k], k == res_i)
		_card_style(settings_btns["fps"][k], k == fps_i)
		(settings_btns["qual"][k] as Label).modulate = Color(0.45, 1.0, 1.0) if k == qual_i else Color(0.6, 0.6, 0.6)
		_card_style(settings_btns["msaa"][k], k == msaa_i)
	for k in 3:
		_card_style(settings_btns["win"][k], k == win_i)
		_card_style(settings_btns["shake"][k], k == shake_i)
	_card_style(settings_btns["vsync"], vs)
	if settings_btns.has("qual_slider"): (settings_btns["qual_slider"] as HSlider).set_value_no_signal(qual_i)
	settings_btns["vsync_lbl"].text = "V-Sync: ON" if vs else "V-Sync: OFF (180 FPS Ready)"
	if settings_status_lbl:
		var fps_now := int(Engine.get_frames_per_second())
		if fps_now <= 0: fps_now = FPS_LIST[fps_i]
		var emb_note := "  ·  [Embedded Editor Pane: internal scaling active]" if _is_embedded_window() else ""
		settings_status_lbl.text = "ACTIVE: %s  ·  Cap: %d FPS (Live: %d FPS)  ·  Quality: %s  ·  AA: %s%s" % [RES_NAMES[res_i], FPS_LIST[fps_i], fps_now, QUAL_NAMES[qual_i], MSAA_NAMES[msaa_i], emb_note]

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_TAB:
			toggle_console()
			get_viewport().set_input_as_handled()
		elif console_panel != null and console_panel.visible:
			if e.keycode == KEY_ESCAPE:
				toggle_console()
				get_viewport().set_input_as_handled()
			elif console_unlocked and e.keycode == KEY_UP and not console_hist.is_empty():
				console_hist_i = maxi(0, console_hist_i - 1)
				console_in.text = console_hist[console_hist_i]
				console_in.caret_column = console_in.text.length()
				get_viewport().set_input_as_handled()
			elif console_unlocked and e.keycode == KEY_DOWN and not console_hist.is_empty():
				console_hist_i = mini(console_hist.size(), console_hist_i + 1)
				console_in.text = console_hist[console_hist_i] if console_hist_i < console_hist.size() else ""
				console_in.caret_column = console_in.text.length()
				get_viewport().set_input_as_handled()

func _build_console() -> void:
	console_panel = _P(ui, Rect2(220, 70, 1160, 540), Color(0.04, 0.055, 0.11, 0.96), 8, ORANGE_Y, 2)
	console_panel.visible = false
	_head(console_panel, "TAB MENU  ·  PERFORMANCE & DEVELOPER CONSOLE", Vector2(20, 14), 16, ORANGE_Y)
	_T(console_panel, "Live FPS telemetry & password-protected developer command console.", Vector2(20, 38), 13, MUTED)
	# Prominent Live FPS Counter badge in the Tab Menu header
	var fps_pill := _P(console_panel, Rect2(760, 10, 330, 40), Color(0.08, 0.14, 0.12, 0.95), 6, GREEN, 1, false)
	console_fps_lbl = _T(fps_pill, "FPS: 180 / 180   ·   5.5 ms", Vector2(0, 9), 15, GREEN, f_bold, 330, HORIZONTAL_ALIGNMENT_CENTER)
	var x := _card_btn(console_panel, Rect2(1104, 12, 40, 36)); x.text = "✕"
	x.pressed.connect(func(): toggle_console())
	# 1. Password Lock Gate ("5516")
	console_lock_box = Control.new()
	console_lock_box.position = Vector2(0, 60); console_lock_box.size = Vector2(1160, 480)
	console_lock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_panel.add_child(console_lock_box)
	var lock_card := _P(console_lock_box, Rect2(310, 76, 540, 310), Color(0.07, 0.09, 0.17, 0.98), 8, Color(1, 0.72, 0.25, 0.45), 1, false)
	_draw_ctl(lock_card, Rect2(246, 24, 48, 52), func(cc: Control):
		cc.draw_rect(Rect2(8, 22, 32, 26), GOLD_C)
		cc.draw_arc(Vector2(24, 22), 11, PI, TAU, 16, GOLD_C, 4.0)
		cc.draw_circle(Vector2(24, 35), 4.0, Color(0.07, 0.09, 0.17)))
	_head(lock_card, "CONSOLE LOCKED", Vector2(0, 88), 22, TEXT, 540, HORIZONTAL_ALIGNMENT_CENTER)
	_T(lock_card, "Enter the 4-digit access password to unlock live game editing:", Vector2(0, 120), 14, MUTED, f_reg, 540, HORIZONTAL_ALIGNMENT_CENTER)
	console_pass_in = LineEdit.new()
	console_pass_in.position = Vector2(90, 162); console_pass_in.size = Vector2(230, 44)
	console_pass_in.placeholder_text = "Password..."
	console_pass_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	console_pass_in.add_theme_font_override("font", f_bold)
	console_pass_in.add_theme_font_size_override("font_size", 18)
	console_pass_in.add_theme_stylebox_override("normal", _flat(Color(0.04, 0.06, 0.12), 5, Color(1, 0.72, 0.25, 0.6), 1))
	console_pass_in.add_theme_stylebox_override("focus", _flat(Color(0.08, 0.11, 0.20), 5, ORANGE_Y, 2))
	console_pass_in.text_submitted.connect(func(txt: String): unlock_console(txt))
	lock_card.add_child(console_pass_in)
	var ul_btn := _big_btn(lock_card, Rect2(332, 162, 118, 44), "UNLOCK", ORANGE_Y, 15)
	ul_btn.pressed.connect(func(): unlock_console(console_pass_in.text))
	console_lock_msg = _T(lock_card, "Protected access · Enter password to continue", Vector2(0, 224), 13, MUTED, f_bold, 540, HORIZONTAL_ALIGNMENT_CENTER)
	# 2. Unlocked Console Body
	console_body = Control.new()
	console_body.position = Vector2(0, 0); console_body.size = Vector2(1160, 540)
	console_body.visible = false
	console_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_panel.add_child(console_body)
	x.move_to_front.call_deferred()
	var qbtns := [
		["+10M Gold", "gold +10000000"],
		["+100K Troops", "troops +100000"],
		["+10K Stars", "stars +10000"],
		["Unlock All", "unlock all"],
		["God Mode", "god"],
		["No Cooldowns", "no_cd"],
		["Peace = 0", "peace 0"],
		["Toggle MIRV", "mirv"],
		["Speed 20x", "speed 20"],
		["Inspect Vars", "vars"]
	]
	for k in qbtns.size():
		var qb := _card_btn(console_body, Rect2(20 + k * 112, 64, 108, 28))
		qb.text = qbtns[k][0]
		qb.add_theme_font_override("font", f_bold); qb.add_theme_font_size_override("font_size", 11)
		var cmd_str: String = qbtns[k][1]
		qb.pressed.connect(func(): run_console_cmd(cmd_str))
	var log_bg := _P(console_body, Rect2(20, 100, 1120, 372), Color(0.02, 0.03, 0.06, 0.95), 5, Color(1, 1, 1, 0.08), 1, false)
	console_log = RichTextLabel.new()
	console_log.position = Vector2(12, 8); console_log.size = Vector2(1096, 356)
	console_log.bbcode_enabled = true
	console_log.scroll_following = true
	console_log.add_theme_font_override("normal_font", f_reg)
	console_log.add_theme_font_override("bold_font", f_bold)
	console_log.add_theme_font_size_override("normal_font_size", 14)
	console_log.add_theme_font_size_override("bold_font_size", 14)
	log_bg.add_child(console_log)
	console_in = LineEdit.new()
	console_in.position = Vector2(20, 484); console_in.size = Vector2(990, 40)
	console_in.placeholder_text = "Enter command or assignment (e.g. gold 5000000, boat_speed = 6.0, NUKE_R[7] = 7, unlock all, spawn city 3, help)..."
	console_in.add_theme_font_override("font", f_bold)
	console_in.add_theme_font_size_override("font_size", 15)
	console_in.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.10, 0.18), 5, Color(1, 0.72, 0.25, 0.6), 1))
	console_in.add_theme_stylebox_override("focus", _flat(Color(0.10, 0.13, 0.22), 5, ORANGE_Y, 2))
	console_in.text_submitted.connect(func(txt: String):
		if txt.strip_edges() != "":
			run_console_cmd(txt)
			console_in.clear()
		console_in.grab_focus())
	console_body.add_child(console_in)
	var run_b := _big_btn(console_body, Rect2(1020, 484, 120, 40), "EXECUTE", ORANGE_Y, 14)
	run_b.pressed.connect(func():
		if console_in.text.strip_edges() != "":
			run_console_cmd(console_in.text)
			console_in.clear()
		console_in.grab_focus())
	_clog("[color=#ffbe42][b]Frontline Conquest Developer Console Ready.[/b][/color] Type [b]help[/b] or [b]vars[/b], or edit any property (e.g. [b]gold 5000000[/b], [b]boat_speed = 6.0[/b], [b]NUKE_R[7] = 7[/b]).")

func unlock_console(code: String) -> bool:
	if code.strip_edges() == CONSOLE_PASS:
		console_unlocked = true
		console_lock_box.visible = false
		console_body.visible = true
		_clog("[color=#66e08c][b]Access granted (code 5516). Developer Console unlocked.[/b][/color]")
		if console_panel and console_panel.visible:
			console_in.grab_focus()
		return true
	console_lock_msg.text = "Access denied — invalid password"
	console_lock_msg.add_theme_color_override("font_color", RED)
	console_pass_in.clear()
	return false

func _update_console_fps(dt: float) -> void:
	if settings_dlg != null and settings_dlg.visible:
		_refresh_settings()
	if console_panel == null or not console_panel.visible or console_fps_lbl == null:
		return
	var fps_now := int(Engine.get_frames_per_second())
	if fps_now <= 0: fps_now = int(round(1.0 / maxf(0.001, dt)))
	var cap_now := Engine.max_fps if Engine.max_fps > 0 else 180
	var ms_now := dt * 1000.0
	var res_i := clampi(int(save.get("settings", {}).get("res_i", 3)), 0, RES_LIST.size() - 1)
	var r_v: Vector2i = RES_LIST[res_i]
	console_fps_lbl.text = "FPS: %d / %d  (%.1f ms)  ·  %dp" % [fps_now, cap_now, ms_now, r_v.y]

func toggle_console() -> void:
	if console_panel == null: return
	if not console_panel.visible and state != "play" and state != "pick": return  # no console on the title / end screens
	console_panel.visible = not console_panel.visible
	if console_panel.visible:
		_update_console_fps(0.0055)
		console_lock_box.visible = not console_unlocked
		console_body.visible = console_unlocked
		if console_unlocked:
			console_in.grab_focus()
		else:
			console_pass_in.grab_focus()
	else:
		console_in.release_focus()
		console_pass_in.release_focus()

func _clog(msg: String) -> void:
	if console_log:
		console_log.append_text(msg + "\n")

func _eval_expr(expr_str: String):
	var ex := Expression.new()
	if ex.parse(expr_str) != OK:
		return null
	return ex.execute([], self, false)

func run_console_cmd(raw: String) -> void:
	var cmd := raw.strip_edges()
	if cmd == CONSOLE_PASS:
		unlock_console(cmd)
		return
	if cmd.begins_with("/"): cmd = cmd.substr(1).strip_edges()
	if cmd == "": return
	console_hist.append(cmd)
	console_hist_i = console_hist.size()
	_clog("[color=#59ccff]> %s[/color]" % cmd)
	var low := cmd.to_lower()
	var parts := cmd.split(" ", false)
	var head := parts[0].to_lower() if parts.size() > 0 else ""
	if head in ["help", "?"]:
		_clog("[b]Commands (no leading slash needed):[/b]")
		_clog("  [b]gold <val|+val>[/b] · [b]troops <val|+val>[/b] · [b]stars <val|+val>[/b] · [b]speed <mult>[/b] · [b]peace <sec>[/b]")
		_clog("  [b]unlock all[/b] | [b]lock all[/b] | [b]unlock <id>[/b] · [b]god[/b] · [b]inf_gold[/b] · [b]no_cd[/b] · [b]mirv[/b]")
		_clog("  [b]claim <radius>[/b] · [b]spawn <building_or_id> [level][/b] · [b]nuke <7|8|11|12> [tile][/b]")
		_clog("  [b]nation <id_or_name> <gold|troops|alive|prot> <val>[/b] · [b]win[/b] · [b]lose[/b] · [b]vars[/b] · [b]clear[/b]")
		_clog("  [b]Any assignment or GDScript expression:[/b] e.g. [b]boat_speed = 6.0[/b], [b]NUKE_R[7] = 27[/b], [b]nations[1].gold = 9e8[/b]")
		return
	if head == "clear":
		console_log.clear(); return
	if head == "vars":
		var pg: float = nations[PLAYER].gold if nations.size() > PLAYER else 0.0
		var pt: float = nations[PLAYER].troops if nations.size() > PLAYER else 0.0
		_clog("[b]Live Editable Variables:[/b]")
		_clog("  gold = %s  |  troops = %s / %s  |  save.stars = %d" % [_fmt(pg), _fmt(pt), _fmt(troop_cap(PLAYER) if nations.size() > PLAYER else 0.0), save.stars])
		_clog("  sim_speed = %.2fx (raw %.2f)  |  peace = %.1fs  |  boat_speed = %.2f" % [sim_speed / SPEED_BASE, sim_speed, maxf(0.0, peace - elapsed), boat_speed])
		_clog("  NUKE_R = %s  |  mirv_enabled = %s" % [str(NUKE_R), str(mirv_enabled)])
		_clog("  god_mode = %s  |  inf_gold = %s  |  no_cd = %s  |  traders = %d  |  trains = %d" % [str(god_mode), str(inf_gold), str(no_cd), traders.size(), trains.size()])
		return
	if head == "god":
		god_mode = not god_mode
		if god_mode and nations.size() > PLAYER:
			nations[PLAYER].gold = maxf(nations[PLAYER].gold, 999e6)
			nations[PLAYER].troops = troop_cap(PLAYER)
		_clog("god_mode = [b]%s[/b]" % str(god_mode)); _update_hud(); return
	if head == "inf_gold":
		inf_gold = not inf_gold
		if inf_gold and nations.size() > PLAYER: nations[PLAYER].gold = maxf(nations[PLAYER].gold, 999e6)
		_clog("inf_gold = [b]%s[/b]" % str(inf_gold)); _update_hud(); return
	if head == "no_cd":
		no_cd = not no_cd
		_clog("no_cd = [b]%s[/b]" % str(no_cd)); _update_hud(); return
	if head == "mirv":
		mirv_enabled = not mirv_enabled
		_clog("mirv_enabled = [b]%s[/b]" % str(mirv_enabled)); _refresh_arsenal(); _update_hud(); return
	if head == "leaderboard":
		if hud_nodes.size() > 2: hud_nodes[2].visible = not hud_nodes[2].visible
		_clog("Toggled leaderboard visibility."); return
	if head == "win":
		_game_over(true); _clog("Triggered VICTORY."); return
	if head == "lose":
		_game_over(false); _clog("Triggered DEFEAT."); return
	if head in ["gold", "troops", "stars", "speed", "peace"] and parts.size() >= 2 and parts[1] != "=":
		var arg := parts[1]
		var add_mode := arg.begins_with("+")
		var val := float(arg)
		if head == "gold" and nations.size() > PLAYER:
			nations[PLAYER].gold = (nations[PLAYER].gold + val) if add_mode else val
			_clog("Player gold -> [b]%s[/b]" % _fmt(nations[PLAYER].gold))
		elif head == "troops" and nations.size() > PLAYER:
			nations[PLAYER].troops = (nations[PLAYER].troops + val) if add_mode else val
			_clog("Player troops -> [b]%s[/b]" % _fmt(nations[PLAYER].troops))
		elif head == "stars":
			save.stars = (save.stars + int(val)) if add_mode else int(val)
			write_save(); _refresh_arsenal()
			_clog("Stars -> [b]%s[/b]" % _fmt_int(save.stars))
		elif head == "speed":
			sim_speed = maxf(0.05, val * SPEED_BASE)
			_clog("Simulation speed -> [b]%.2fx[/b]" % val)
		elif head == "peace":
			peace = elapsed + val
			_clog("Peace timer -> [b]%.1fs remaining[/b]" % val)
		_update_hud(); return
	if head == "unlock" and parts.size() >= 2:
		var target_u := parts[1].to_lower()
		if target_u == "all":
			for it in ARSENAL:
				if not (it.id in save.unlocked): save.unlocked.append(it.id)
			write_save(); _refresh_arsenal(); _update_hud()
			_clog("Unlocked all 8 Arsenal items: [b]%s[/b]" % str(save.unlocked))
		else:
			if not (target_u in save.unlocked): save.unlocked.append(target_u)
			write_save(); _refresh_arsenal(); _update_hud()
			_clog("Unlocked [b]%s[/b]" % target_u)
		return
	if head == "lock" and parts.size() >= 2 and parts[1].to_lower() == "all":
		save.unlocked = []
		write_save(); _refresh_arsenal(); _update_hud()
		_clog("Locked all Arsenal items."); return
	if head == "claim":
		var rad := int(parts[1]) if parts.size() >= 2 else 15
		var t := _mouse_tile()
		if t < 0 and nations.size() > PLAYER and nations[PLAYER].land > 0:
			t = int(nations[PLAYER].sy / nations[PLAYER].land) * W + int(nations[PLAYER].sx / nations[PLAYER].land)
		if t >= 0:
			_claim_blob(PLAYER, t, clampi(rad, 1, 120))
			_clog("Claimed radius %d around tile %d for Player." % [rad, t])
		return
	if head == "spawn" and parts.size() >= 2:
		var q := parts[1].to_lower()
		var lvl := int(parts[2]) if parts.size() >= 3 else 1
		var k := int(q) if q.is_valid_int() else -1
		if k < 0:
			for m in build_data.size():
				if build_data[m][1].to_lower().begins_with(q): k = m; break
		var t := _mouse_tile()
		if t < 0 and nations.size() > PLAYER and nations[PLAYER].land > 0:
			t = int(nations[PLAYER].sy / nations[PLAYER].land) * W + int(nations[PLAYER].sx / nations[PLAYER].land)
		if k >= 0 and t >= 0:
			if k == 6:
				spawn_warship(PLAYER); _clog("Spawned Warship.")
			else:
				_struct_add(k, t, PLAYER)
				struct_at[t].level = maxi(1, lvl); struct_at[t].bt = 0.0; _sv += 1
				_clog("Spawned %s Lv%d at tile %d." % [build_data[k][1], maxi(1, lvl), t])
			overlay.queue_redraw()
		return
	if head == "nation" and parts.size() >= 4:
		var q := parts[1].to_lower()
		var prop := parts[2].to_lower()
		var val_s := parts[3]
		var nid := int(q) if q.is_valid_int() else -1
		if nid < 0:
			for id in range(1, nations.size()):
				if nations[id].name.to_lower().find(q) >= 0: nid = id; break
		if nid > 0 and nid < nations.size():
			var n = nations[nid]
			if prop in ["gold", "troops"]:
				n[prop] = float(val_s)
			elif prop in ["alive", "prot"]:
				n[prop] = (val_s.to_lower() in ["true", "1", "yes"])
			else:
				n[prop] = _eval_expr(val_s)
			_clog("Updated nation #%d (%s) %s -> [b]%s[/b]" % [nid, n.name, prop, str(n[prop])])
			_update_hud()
		return
	# Universal assignment handler: e.g. boat_speed = 6.0, NUKE_R[7] = 27, nations[1].gold = 9e8, gold = 5000000
	if "=" in cmd and not ("==" in cmd):
		var eq := cmd.find("=")
		var lhs := cmd.substr(0, eq).strip_edges()
		var rhs := cmd.substr(eq + 1).strip_edges()
		var val = _eval_expr(rhs)
		if val == null and rhs.is_valid_float(): val = float(rhs)
		if lhs == "gold" and nations.size() > PLAYER:
			nations[PLAYER].gold = float(val); _clog("gold = [b]%s[/b]" % _fmt(nations[PLAYER].gold)); _update_hud(); return
		if lhs == "troops" and nations.size() > PLAYER:
			nations[PLAYER].troops = float(val); _clog("troops = [b]%s[/b]" % _fmt(nations[PLAYER].troops)); _update_hud(); return
		if lhs == "stars" or lhs == "save.stars":
			save.stars = int(val); write_save(); _refresh_arsenal(); _clog("save.stars = [b]%d[/b]" % save.stars); return
		if "[" in lhs and lhs.ends_with("]"):
			var b0 := lhs.find("[")
			var cname := lhs.substr(0, b0).strip_edges()
			var kexpr := lhs.substr(b0 + 1, lhs.length() - b0 - 2).strip_edges()
			var target_c = get(cname) if cname != "nuke_r" else NUKE_R
			var key_v = _eval_expr(kexpr)
			if target_c != null and key_v != null:
				target_c[key_v] = val
				_clog("%s[%s] = [b]%s[/b]" % [cname, str(key_v), str(val)]); _update_hud(); return
		if "." in lhs:
			var dot := lhs.rfind(".")
			var obj_e := lhs.substr(0, dot).strip_edges()
			var field := lhs.substr(dot + 1).strip_edges()
			var obj = _eval_expr(obj_e)
			if obj != null:
				obj[field] = val
				_clog("%s.%s = [b]%s[/b]" % [obj_e, field, str(val)]); _update_hud(); return
		set(lhs, val)
		_clog("%s = [b]%s[/b]" % [lhs, str(get(lhs))]); _update_hud(); return
	# Fallback: evaluate any GDScript expression or method call on self
	var res = _eval_expr(cmd)
	_clog("=> [b]%s[/b]" % str(res))
	_update_hud()
