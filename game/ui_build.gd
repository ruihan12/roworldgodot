extends "res://game/ui_anim.gd"
# Menus, panels, HUD building and settings

func _clean_border_col(c: Color, border: Color, bw: int) -> Color:
	if bw <= 0 or border.a <= 0.0:
		return Color(c.r, c.g, c.b, 0.0)
	if border.a < 0.99 and c.a > 0.25:
		# Pre-composite translucent border over background fill 'c' so Godot's rounded-corner AA strip never interpolates toward pure white (1,1,1)!
		var rgb := Color(c.r, c.g, c.b, 1.0).lerp(Color(border.r, border.g, border.b, 1.0), border.a)
		return Color(rgb.r, rgb.g, rgb.b, c.a)
	return border

func _panel_style(c: Color = PANEL_BG, r: int = 14, border := Color(1, 1, 1, 0.07), bw := 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	# RoWorld UITheme: R_SM 6 / R_MD 10 / R_LG 14 -> panels 12-16 px
	st.set_corner_radius_all(clampi(r, 12, 16))
	st.corner_detail = 10
	st.set_content_margin_all(8)
	st.border_color = _clean_border_col(c, border, bw)
	st.set_border_width_all(bw)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 8
	st.anti_aliasing = true
	return st

func _flat(c: Color, r: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	# buttons 8-10 px, small bars/toggles become pills (Godot clamps radius to half the height)
	st.set_corner_radius_all(r if r < 4 else (clampi(r + 4, 8, 10) if r <= 8 else mini(r + 2, 16)))
	st.corner_detail = 8
	st.border_color = _clean_border_col(c, border, bw)
	st.set_border_width_all(bw)
	st.set_content_margin_all(2)
	st.anti_aliasing = true
	return st

func _P(parent: Node, r: Rect2, c := PANEL_BG, rad := 14, border := Color(1, 1, 1, 0.07), bw := 1, shadow := true) -> Panel:
	var p := Panel.new()
	p.position = r.position; p.size = r.size
	var st := _panel_style(c, rad, border, bw)
	if not shadow: st.shadow_size = 0
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	return p

func _T(parent: Node, t: String, pos: Vector2, fs: int, col := TEXT, font: Font = null, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if font: l.add_theme_font_override("font", font)
	if w > 0:
		l.size = Vector2(w, fs + 8); l.horizontal_alignment = align; l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _head(parent: Node, t: String, pos: Vector2, fs := 12, col := MUTED, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _T(parent, t, pos, fs, col, f_head, w, align)

func _vline(parent: Node, x: float, y: float, h: float) -> void:
	var c := ColorRect.new(); c.color = Color(1, 1, 1, 0.08)
	c.position = Vector2(x, y); c.size = Vector2(1, h); c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func _draw_ctl(parent: Node, r: Rect2, f: Callable) -> Control:
	var c := Control.new()
	c.position = r.position; c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): f.call(c))
	parent.add_child(c)
	return c

func _style_btn(b: Button, on: bool) -> void:
	_pill(b, on)

func _pill(b: Button, on: bool, r := 7) -> void:
	var base := ORANGE_Y if on else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", _flat(base, r))
	b.add_theme_stylebox_override("hover", _flat(base.lightened(0.1) if on else Color(1, 1, 1, 0.08), r))
	b.add_theme_stylebox_override("pressed", _flat(base.darkened(0.1) if on else Color(1, 1, 1, 0.12), r))
	b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), r))
	b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05) if on else Color(0.82, 0.86, 0.95))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05) if on else Color.WHITE)
	b.add_theme_font_override("font", f_bold)

func _btn(t: String, on := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	_pill(b, on)
	return b

func _big_btn(parent: Node, r: Rect2, t: String, col: Color, fs := 20) -> Button:
	var b := Button.new()
	b.position = r.position; b.size = r.size; b.text = t
	b.focus_mode = Control.FOCUS_NONE
	var n := _flat(col, 12, col.darkened(0.25), 0); n.border_width_bottom = 4
	var h := _flat(col.lightened(0.08), 12, col.darkened(0.25), 0); h.border_width_bottom = 4
	var pr := _flat(col.darkened(0.08), 12)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr); b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 12))
	b.add_theme_font_override("font", f_head); b.add_theme_font_size_override("font_size", fs)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, Color(0.12, 0.09, 0.05))
	parent.add_child(b)
	return b

func _card_btn(parent: Node, r: Rect2) -> Button:
	var b := Button.new()
	b.position = r.position; b.size = r.size; b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	_card_style(b, false)
	return b

func _card_style(b: Button, on: bool) -> void:
	var bc := ORANGE_Y if on else Color(1, 1, 1, 0.07)
	var bw := 2 if on else 1
	b.add_theme_stylebox_override("normal", _flat(CELL_BG, 12, bc, bw))
	b.add_theme_stylebox_override("hover", _flat(CELL_BG.lightened(0.06), 12, bc if on else Color(1, 1, 1, 0.18), bw))
	b.add_theme_stylebox_override("pressed", _flat(CELL_BG.lightened(0.1), 12, bc, bw))
	b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 12))

func _lbl(t: String, size := 16, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _map_preview(k: int, pw: int, ph: int) -> ImageTexture:
	if map_tab == 2: return UpstreamMaps.preview_texture(UpstreamMaps.id_at(k), pw, ph)
	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	if map_tab == 0:
		var raw_bytes := _get_handcrafted_map_bytes(k)
		if raw_bytes.size() == W * H:
			for py in ph:
				var sy := clampi(int(float(py) * H / ph), 0, H - 1)
				for px in pw:
					var sx := clampi(int(float(px) * W / pw), 0, W - 1)
					var code: int = raw_bytes[sy * W + sx]
					var c := Color(0.16, 0.33, 0.50, 0.92)
					if code >= 3: c = Color(0.93, 0.93, 0.96)
					elif code == 2: c = Color(0.82, 0.76, 0.56)
					elif code == 1: c = Color(0.70, 0.82, 0.53)
					im.set_pixel(px, py, c)
			return ImageTexture.create_from_image(im)
	var m := _active_map_entry(k)
	var seed_val: int = int(m[1]) + rand_seed_off
	var n := FastNoiseLite.new(); n.seed = seed_val; n.frequency = 0.006; n.fractal_octaves = 6
	var n2 := FastNoiseLite.new(); n2.seed = seed_val + 7; n2.frequency = 0.025
	for py in ph:
		for px in pw:
			var x := float(px) * W / pw; var y := float(py) * H / ph
			var v: float = _sample_map_elev(k, x, y, n, n2)
			var c := Color(0.16, 0.33, 0.50, 0.85)
			if v > 0.0:
				if v > 0.48: c = Color(0.94, 0.94, 0.96)
				elif v > 0.40: c = Color(0.70, 0.65, 0.56)
				elif v > 0.20: c = Color(0.82, 0.76, 0.56)
				else: c = Color(0.70, 0.82, 0.53)
			im.set_pixel(px, py, c)
	return ImageTexture.create_from_image(im)

func _build_ui() -> void:
	# upstream UITheme: Rubik everywhere (regular 500, bold 700, headings 800 + letter spacing)
	var rubik: Font = RK.base_font()
	if rubik == null: rubik = ThemeDB.fallback_font
	f_reg = RK.font(500) if rubik != ThemeDB.fallback_font else rubik
	f_bold = FontVariation.new(); f_bold.base_font = rubik; f_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	f_head = FontVariation.new(); f_head.base_font = rubik; f_head.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}; f_head.spacing_glyph = 2
	if rubik == ThemeDB.fallback_font:
		f_bold.variation_embolden = 0.75; f_head.variation_embolden = 1.0
	ui = CanvasLayer.new()
	add_child(ui)
	_build_menu()
	_build_play_dialog()
	_build_pick()
	_build_top()
	_build_speed()
	_build_leaderboard()
	_build_attacks()
	_build_bottom()
	_build_help()
	_build_over()
	# the pre-upstream panels stay built (their labels are still written) but never shown
	var legacy := Control.new(); legacy.name = "LegacyHud"; legacy.visible = false
	legacy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(legacy)
	for n in hud_nodes: n.reparent(legacy)
	pick_panel.reparent(legacy)
	hud = RW_HUD.new(); hud.name = "RwHudCtl"; add_child(hud)
	hud.build(self)
	ui.move_child(hud.root, legacy.get_index())
	hud_nodes = hud.groups.duplicate()
	note_box = Control.new(); note_box.position = Vector2(16, 96); note_box.size = Vector2(380, 480)
	note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_box.draw.connect(_draw_notes)
	note_box.visible = false  # toasts are drawn by hud.toast (EventFeed)
	ui.add_child(note_box)
	_build_ally_card()
	_build_diplo_menu()
	_build_end()
	_build_arsenal()
	_build_settings()
	hud.build_menu()
	hud.build_over()
	_build_console()
	_wire_anims(ui)
	_set_share(share_i)
	tipc = Control.new(); tipc.mouse_filter = Control.MOUSE_FILTER_IGNORE; tipc.visible = false
	tipc.draw.connect(_draw_tip)
	ui.add_child(tipc)
	# legacy handles
	for n in hud_nodes: n.visible = false

# ---- main menu ----
func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_panel)
	var shade := ColorRect.new(); shade.color = Color(0.03, 0.05, 0.10, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT); menu_panel.add_child(shade)
	# original emblem: compass rose inside a rounded badge
	_draw_ctl(menu_panel, Rect2(760, 62, 80, 80), func(c: Control):
		c.draw_style_box(_flat(Color(0.10, 0.16, 0.32), 20, Color(1, 1, 1, 0.25), 2), Rect2(0, 0, 80, 80))
		var o := Vector2(40, 40)
		c.draw_arc(o, 26, 0, TAU, 40, ORANGE_Y, 3, true)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2)
			var nn := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([o + d * 30, o + nn * 6, o - nn * 6]), Color.WHITE if k % 2 == 0 else Color(0.55, 0.75, 1.0))
		c.draw_circle(o, 5, Color(0.95, 0.35, 0.3)))
	var title := _T(menu_panel, "FRONTLINE CONQUEST", Vector2(0, 150), 86, Color(1.0, 0.95, 0.86), f_head, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	title.size.y = 110
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 6)
	_draw_ctl(menu_panel, Rect2(600, 274, 400, 20), func(c: Control):
		c.draw_line(Vector2(0, 10), Vector2(85, 10), ORANGE_Y, 2)
		c.draw_line(Vector2(315, 10), Vector2(400, 10), ORANGE_Y, 2))
	_head(menu_panel, "CONQUER THE WORLD", Vector2(0, 272), 16, Color(0.9, 0.88, 0.82), 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var cp := _P(menu_panel, Rect2(530, 470, 540, 250))
	_T(cp, "Welcome, Commander", Vector2(0, 16), 15, MUTED, f_reg, 540, HORIZONTAL_ALIGNMENT_CENTER)
	var play := _big_btn(cp, Rect2(18, 46, 430, 60), "PLAY SOLO", ORANGE_Y, 22)
	_draw_ctl(play, Rect2(22, 18, 24, 24), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(4, 2), Vector2(20, 12), Vector2(4, 22)]), Color(0.12, 0.09, 0.05)))
	play.pressed.connect(func(): _pop_in(play_dialog))
	var hb := _card_btn(cp, Rect2(460, 46, 62, 60))
	hb.text = "?"; hb.add_theme_font_override("font", f_head); hb.add_theme_font_size_override("font_size", 24)
	hb.pressed.connect(func(): _pop_in(help_panel))
	_head(cp, "PROGRESSION & SHOP", Vector2(0, 124), 12, GOLD_C, 540, HORIZONTAL_ALIGNMENT_CENTER)
	var set_top := _card_btn(menu_panel, Rect2(1176, 26, 162, 52))
	set_top.add_theme_stylebox_override("normal", _flat(Color(0.07, 0.085, 0.15, 0.94), 6, Color(1, 1, 1, 0.18), 1))
	set_top.add_theme_stylebox_override("hover", _flat(Color(0.14, 0.16, 0.26, 0.98), 6, CYAN, 1))
	set_top.pressed.connect(_open_settings)
	_draw_ctl(set_top, Rect2(14, 13, 26, 26), func(c: Control): _draw_gear(c, Vector2(13, 13), 10.0, CYAN))
	_T(set_top, "SETTINGS", Vector2(46, 8), 16, TEXT, f_bold, 108)
	menu_settings_sub = _T(set_top, "1440p · 180 FPS · Ultra", Vector2(46, 29), 9, MUTED, f_bold, 112)
	var sp := _card_btn(menu_panel, Rect2(1350, 26, 220, 52))
	sp.add_theme_stylebox_override("normal", _flat(Color(0.07, 0.085, 0.15, 0.94), 6, Color(1, 0.8, 0.3, 0.55), 1))
	sp.add_theme_stylebox_override("hover", _flat(Color(0.14, 0.16, 0.26, 0.98), 6, GOLD_C, 1))
	sp.pressed.connect(_open_shop)
	_draw_ctl(sp, Rect2(14, 13, 26, 26), func(c: Control): _star(c, Vector2(13, 13), 11, GOLD_C))
	stars_lbl = _T(sp, _fmt_int(save.stars), Vector2(46, 7), 20, GOLD_C, f_bold, 120)
	_T(sp, "OPEN SHOP  ▸", Vector2(46, 30), 10, MUTED, f_bold, 150)
	var ab := _card_btn(cp, Rect2(18, 150, 368, 80))
	ab.pressed.connect(_open_shop)
	_draw_ctl(ab, Rect2(18, 20, 34, 40), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(34, 0), Vector2(34, 22), Vector2(17, 40), Vector2(0, 22)]), ORANGE_Y)
		_star(c, Vector2(17, 17), 9, Color(0.15, 0.1, 0.03)))
	_head(ab, "SHOP & ARSENAL", Vector2(66, 18), 16, TEXT)
	_T(ab, "●  Stars & weapon unlocks", Vector2(66, 44), 13, MUTED)
	var sb_cfg := _card_btn(cp, Rect2(396, 150, 126, 80))
	sb_cfg.pressed.connect(_open_settings)
	_draw_ctl(sb_cfg, Rect2(46, 14, 34, 34), func(c: Control): _draw_gear(c, Vector2(17, 17), 12.0, CYAN))
	_head(sb_cfg, "SETTINGS", Vector2(0, 50), 13, TEXT, 126, HORIZONTAL_ALIGNMENT_CENTER)
	_T(menu_panel, "Original prototype  ·  procedurally generated maps", Vector2(0, 864), 13, Color(0.6, 0.65, 0.78), f_reg, 1600, HORIZONTAL_ALIGNMENT_CENTER)

# ---- play solo dialog ----
func _build_play_dialog() -> void:
	play_dialog = Control.new(); play_dialog.set_anchors_preset(Control.PRESET_FULL_RECT); play_dialog.visible = false
	ui.add_child(play_dialog)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.6); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_dialog.add_child(sh)
	var p := _P(play_dialog, Rect2(190, 36, 1220, 828), Color(0.07, 0.085, 0.15, 0.98), 18)
	_head(p, "PLAY SOLO", Vector2(32, 20), 28, TEXT)
	_T(p, "Choose from 12 strategic world & regional maps and set AI aggressiveness.", Vector2(32, 56), 14, MUTED)
	var x := _card_btn(p, Rect2(1146, 18, 42, 42)); x.text = "✕"
	x.pressed.connect(func(): play_dialog.visible = false)
	var tab_real := _btn("REAL-WORLD MAPS (12)", true)
	tab_real.position = Vector2(32, 80); tab_real.size = Vector2(216, 28)
	tab_real.add_theme_font_size_override("font_size", 12)
	p.add_child(tab_real)
	var tab_rand := _btn("RANDOM MAPS (12)", false)
	tab_rand.position = Vector2(256, 80); tab_rand.size = Vector2(196, 28)
	tab_rand.add_theme_font_size_override("font_size", 12)
	p.add_child(tab_rand)
	var tab_up := _btn("ROWORLD MAPS (%d)" % UpstreamMaps.count(), false)
	tab_up.position = Vector2(460, 80); tab_up.size = Vector2(196, 28)
	tab_up.add_theme_font_size_override("font_size", 12)
	p.add_child(tab_up)
	map_tab_btns = [tab_real, tab_rand, tab_up]
	reroll_btn = _card_btn(p, Rect2(668, 80, 164, 28))
	reroll_btn.text = "REROLL RANDOM SEEDS"
	reroll_btn.add_theme_font_override("font", f_bold)
	reroll_btn.add_theme_font_size_override("font_size", 11)
	reroll_btn.add_theme_color_override("font_color", GOLD_C)
	reroll_btn.visible = false
	reroll_btn.pressed.connect(func():
		rand_seed_off = rng.randi_range(100, 999999)
		_refresh_map_tab_cards())
	tab_real.pressed.connect(func(): _set_map_tab(0))
	tab_rand.pressed.connect(func(): _set_map_tab(1))
	tab_up.pressed.connect(func(): _set_map_tab(2))
	for k in MAPS.size():
		var col_i := k % 4
		var row_i := k / 4
		var c := _card_btn(p, Rect2(32 + col_i * 292, 114 + row_i * 158, 280, 148))
		var tr := TextureRect.new(); tr.texture = _map_preview(k, 148, 82)
		tr.position = Vector2(10, 10); tr.size = Vector2(260, 86); tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.add_child(tr)
		var tl := _T(c, MAPS[k][0], Vector2(12, 100), 15, TEXT, f_bold, 256)
		var sl := _T(c, _map_sub(k, 0), Vector2(12, 122), 12, MUTED, f_reg, 256)
		map_cards.append(c)
		map_card_tex.append(tr)
		map_card_title.append(tl)
		map_card_sub.append(sl)
		c.pressed.connect(func():
			map_i = k
			for j in map_cards.size(): _card_style(map_cards[j], j == k))
	_card_style(map_cards[map_i], true)
	_head(p, "DIFFICULTY", Vector2(32, 594), 12, MUTED)
	var descs := ["Gentle AI · long peace", "Balanced AI", "Ruthless AI · short peace"]
	var cols := [GREEN, ORANGE_Y, RED]
	for k in DIFFS.size():
		var c := _card_btn(p, Rect2(32 + k * 392, 616, 372, 82))
		_draw_ctl(c, Rect2(16, 21, 40, 40), func(cc: Control):
			cc.draw_circle(Vector2(20, 20), 19, Color(cols[k], 0.18))
			cc.draw_arc(Vector2(20, 20), 19, 0, TAU, 32, cols[k], 2, true)
			for b in k + 1: cc.draw_rect(Rect2(10 + b * 8, 26 - b * 5, 5, 6 + b * 5), cols[k]))
		_T(c, DIFFS[k][0], Vector2(70, 14), 18, TEXT, f_bold)
		_T(c, "%s  ·  peace %s" % [descs[k], _fmt_time(DIFFS[k][1])], Vector2(70, 44), 13, MUTED)
		diff_cards.append(c)
		c.pressed.connect(func():
			diff_i = k
			for j in diff_cards.size(): _card_style(diff_cards[j], j == k))
	_card_style(diff_cards[diff_i], true)
	# bot players (upstream public matches): 0 keeps the match solo
	_head(p, "BOT PLAYERS", Vector2(32, 712), 12, MUTED)
	var bot_opts := [0, 4, 9, 19, 29]
	var bot_cards := []
	for k in bot_opts.size():
		var bc := _card_btn(p, Rect2(32 + k * 70, 734, 62, 40))
		_T(bc, "Off" if bot_opts[k] == 0 else str(bot_opts[k]), Vector2(0, 9), 16, TEXT, f_bold, 62, HORIZONTAL_ALIGNMENT_CENTER)
		bot_cards.append(bc)
		bc.pressed.connect(func():
			bot_players = bot_opts[k]
			for j in bot_cards.size(): _card_style(bot_cards[j], j == k))
	_card_style(bot_cards[maxi(0, bot_opts.find(bot_players))], true)
	_T(p, "Bot players look and play like people: 2 play smart, the rest are novices.", Vector2(392, 736), 12, MUTED)
	_T(p, "Any bot ends solo play, so everyone gets a 30 s spawn shield.", Vector2(392, 756), 12, MUTED)
	var st := _big_btn(p, Rect2(880, 732, 308, 60), "START GAME", ORANGE_Y, 22)
	st.pressed.connect(_start_game_ui)

func _set_map_tab(t_idx: int) -> void:
	map_tab = clampi(t_idx, 0, 2)
	map_i = clampi(map_i, 0, (UpstreamMaps.count() if map_tab == 2 else MAPS.size()) - 1)
	if map_tab == 1 and rand_seed_off == 0:
		rand_seed_off = rng.randi_range(100, 999999)
	for j in map_tab_btns.size():
		_pill(map_tab_btns[j], j == map_tab)
	if reroll_btn:
		reroll_btn.visible = (map_tab == 1)
	_refresh_map_tab_cards()

func _preview_key(k: int) -> String:
	return "%d:%d:%d" % [map_tab, k, rand_seed_off if map_tab == 1 else 0]

func _blank_preview() -> ImageTexture:
	if _preview_blank != null:
		return _preview_blank
	var im := Image.create(148, 82, false, Image.FORMAT_RGBA8)
	im.fill(Color(0.10, 0.18, 0.30, 1))
	_preview_blank = ImageTexture.create_from_image(im)
	return _preview_blank

func _refresh_map_tab_cards() -> void:
	var tbl: Array = _upstream_menu() if map_tab == 2 else (RANDOM_MAPS if map_tab == 1 else MAPS)
	_pv_job = {}
	_preview_queue.clear()
	for k in map_cards.size():
		map_cards[k].visible = k < tbl.size()
		if k >= tbl.size(): continue
		map_card_title[k].text = tbl[k][0]
		map_card_sub[k].text = _map_sub(k, map_tab)
		_card_style(map_cards[k], k == map_i)
		var key := _preview_key(k)
		if _preview_cache.has(key):
			map_card_tex[k].texture = _preview_cache[key]
		elif map_tab != 1:
			var tex := _map_preview(k, 148, 82)
			_preview_cache[key] = tex
			map_card_tex[k].texture = tex
		else:
			map_card_tex[k].texture = _blank_preview()
			_preview_queue.append(k)

func _pump_previews() -> void:
	if _loading:
		return
	var t0 := Time.get_ticks_usec()
	var budget := 6000
	while Time.get_ticks_usec() - t0 < budget:
		if _pv_job.is_empty():
			if _preview_queue.is_empty():
				preview_pump_us = 0
				return
			_pv_job = _preview_begin(int(_preview_queue.pop_front()))
		if not _preview_step():
			_pv_job = {}
	preview_pump_us = Time.get_ticks_usec() - t0

func _preview_begin(k: int) -> Dictionary:
	var pw := 148
	var ph := 82
	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	var m := _active_map_entry(k)
	var seed_val: int = int(m[1]) + rand_seed_off
	var nz := FastNoiseLite.new(); nz.seed = seed_val; nz.frequency = 0.006; nz.fractal_octaves = 6
	var nz2 := FastNoiseLite.new(); nz2.seed = seed_val + 7; nz2.frequency = 0.025
	return {"k": k, "key": _preview_key(k), "im": im, "py": 0, "pw": pw, "ph": ph, "n": nz, "n2": nz2}

func _preview_step() -> bool:
	var k: int = _pv_job.k
	var im: Image = _pv_job.im
	var pw: int = _pv_job.pw
	var ph: int = _pv_job.ph
	var py: int = _pv_job.py
	var y1 := mini(ph, py + 3)
	for y in range(py, y1):
		for px in pw:
			var v: float = _sample_map_elev(k, float(px) * W / pw, float(y) * H / ph, _pv_job.n, _pv_job.n2)
			var c := Color(0.16, 0.33, 0.50, 0.85)
			if v > 0.0:
				if v > 0.48: c = Color(0.94, 0.94, 0.96)
				elif v > 0.40: c = Color(0.70, 0.65, 0.56)
				elif v > 0.20: c = Color(0.82, 0.76, 0.56)
				else: c = Color(0.70, 0.82, 0.53)
			im.set_pixel(px, y, c)
	_pv_job.py = y1
	if y1 < ph:
		return true
	var tex := ImageTexture.create_from_image(im)
	_preview_cache[_pv_job.key] = tex
	if k < map_card_tex.size() and _preview_key(k) == str(_pv_job.key):
		map_card_tex[k].texture = tex
	return false

# ---- pick / deploy banner ----
func _build_pick() -> void:
	pick_panel = _P(ui, Rect2(530, 22, 540, 72))
	pick_title = _head(pick_panel, "", Vector2(24, 12), 19, TEXT, 440)
	pick_sub = _T(pick_panel, "", Vector2(24, 40), 15, Color(0.75, 0.8, 0.92), f_reg, 440)
	pick_ring = _draw_ctl(pick_panel, Rect2(476, 12, 48, 48), func(c: Control):
		var v: float = c.get_meta("v", 1.0)
		c.draw_arc(Vector2(24, 24), 20, 0, TAU, 40, Color(1, 1, 1, 0.12), 5, true)
		c.draw_arc(Vector2(24, 24), 20, -PI / 2, -PI / 2 + TAU * v, 40, RED, 5, true)
		f_head.draw_string(c.get_canvas_item(), Vector2(0, 32), str(c.get_meta("n", 5)), HORIZONTAL_ALIGNMENT_CENTER, 48, 22, TEXT))
	pick_panel.visible = false
	pick_label = Label.new()

# ---- top: protection + world control ----
func _build_top() -> void:
	var p := _P(ui, Rect2(545, 22, 520, 76))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(16, 13, 12, 14), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 7), Vector2(6, 14), Vector2(0, 7)]), c.get_meta("col", GREEN)))
	top_left_head = _head(p, "PROTECTED", Vector2(34, 10), 12, GREEN)
	top_timer = _T(p, "0:00", Vector2(16, 30), 30, GREEN, f_bold)
	_vline(p, 150, 14, 48)
	_draw_ctl(p, Rect2(166, 14, 12, 12), func(c: Control):
		c.draw_arc(Vector2(6, 6), 5, 0, TAU, 16, MUTED, 1.5, true); c.draw_line(Vector2(1, 6), Vector2(11, 6), MUTED, 1))
	_head(p, "WORLD CONTROL", Vector2(184, 10), 12, MUTED)
	_head(p, "GOAL 80%", Vector2(380, 10), 12, ORANGE_Y, 124, HORIZONTAL_ALIGNMENT_RIGHT)
	top_bar_ctl = _draw_ctl(p, Rect2(166, 34, 338, 10), func(c: Control):
		var you: float = c.get_meta("you", 0.0); var lead: float = c.get_meta("lead", 0.0)
		c.draw_style_box(_flat(Color(1, 1, 1, 0.10), 4), Rect2(0, 2, 338, 6))
		c.draw_style_box(_flat(Color(0.95, 0.75, 0.3, 0.6), 4), Rect2(0, 2, maxf(2, 338 * lead / 100.0), 6))
		c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 4), Rect2(0, 2, maxf(2, 338 * you / 100.0), 6))
		c.draw_rect(Rect2(338 * 0.8 - 1, 0, 2, 10), ORANGE_Y))
	_draw_ctl(p, Rect2(166, 54, 10, 10), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 2), Rect2(0, 0, 10, 10)))
	top_you = _T(p, "You 0%", Vector2(182, 48), 13, TEXT)
	_draw_ctl(p, Rect2(300, 54, 12, 10), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 10), Vector2(0, 2), Vector2(3, 5), Vector2(6, 0), Vector2(9, 5), Vector2(12, 2), Vector2(12, 10)]), ORANGE_Y))
	top_lead = _T(p, "", Vector2(318, 48), 13, TEXT, f_reg, 190)

func _speed_text_width(text: String, font: Font, fs: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _place_speed_readout() -> void:
	if speed_title == null or speed_lbl == null or speed_hint == null:
		return
	if hud != null and speed_panel is PanelContainer:
		return  # upstream-style chip: laid out by its HBox/VBox
	var title_w := _speed_text_width(speed_title.text, f_head, 12)
	var value_w := _speed_text_width(speed_lbl.text, f_bold, 15)
	var hint_w := _speed_text_width(speed_hint.text, f_reg, 12)
	speed_title.position = Vector2(14, 8)
	speed_title.size = Vector2(title_w + 2, 20)
	speed_lbl.position = Vector2(speed_title.position.x + speed_title.size.x + 18, 6)
	speed_lbl.size = Vector2(value_w + 4, 22)
	speed_hint.position = Vector2(speed_lbl.position.x + speed_lbl.size.x + 14, 8)
	speed_hint.size = Vector2(hint_w + 4, 20)
	var row_end := speed_hint.position.x + speed_hint.size.x
	var need := row_end + 16.0 + 36.0 + 12.0
	if speed_panel:
		speed_panel.size.x = maxf(speed_panel.size.x, need)
		speed_panel.size.y = 78
	if speed_slider:
		speed_slider.position = Vector2(14, 36)
		speed_slider.size = Vector2(maxf(120.0, need - 14.0 - 52.0), 22)
	if speed_ticks:
		speed_ticks.position = Vector2(14, 60)
		speed_ticks.size = Vector2(speed_slider.size.x if speed_slider else 170, 10)
	var gear := speed_panel.get_node_or_null("SpeedGear") if speed_panel else null
	if gear is Control and speed_slider:
		gear.position = Vector2(speed_slider.position.x + speed_slider.size.x + 8, 30)

func _build_speed() -> void:
	var widest := 0.0
	for sample in ["0.5x", "1x", "10x"]:
		widest = maxf(widest, 14 + _speed_text_width("GAME SPEED", f_head, 12) + 18 + _speed_text_width(sample, f_bold, 15) + 14 + _speed_text_width("– / +", f_reg, 12) + 16 + 36 + 12)
	var p := _P(ui, Rect2(16, 22, widest, 78))
	speed_panel = p
	hud_nodes.append(p)
	speed_title = _head(p, "GAME SPEED", Vector2(14, 8), 12, MUTED)
	speed_hint = _T(p, "– / +", Vector2(0, 8), 12, MUTED, f_reg)
	speed_lbl = _T(p, "1x", Vector2(0, 6), 15, ORANGE_Y, f_bold)
	var sl := HSlider.new()
	sl.min_value = 0.5; sl.max_value = 10.0; sl.step = 0.5; sl.value = 1.0
	sl.position = Vector2(14, 36); sl.size = Vector2(widest - 66, 22); sl.focus_mode = Control.FOCUS_NONE
	var grab := StyleBoxFlat.new(); grab.bg_color = Color(0.35, 0.80, 1.0, 0.85); grab.set_corner_radius_all(6); grab.content_margin_top = 5; grab.content_margin_bottom = 5
	var trk := StyleBoxFlat.new(); trk.bg_color = Color(1, 1, 1, 0.12); trk.set_corner_radius_all(6); trk.content_margin_top = 5; trk.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", trk); sl.add_theme_stylebox_override("grabber_area", grab); sl.add_theme_stylebox_override("grabber_area_highlight", grab)
	sl.value_changed.connect(func(v: float): set_speed_x(v))
	p.add_child(sl); speed_slider = sl
	speed_ticks = _draw_ctl(p, Rect2(14, 60, sl.size.x, 10), func(c: Control):
		for sp in [0.5, 1.0, 2.0, 5.0, 10.0]:
			var x: float = 8.0 + (sp - 0.5) / 9.5 * (c.size.x - 16.0)
			c.draw_circle(Vector2(x, 4), 2.2, Color(1, 1, 1, 0.55)))
	var cfg_b := _card_btn(p, Rect2(sl.position.x + sl.size.x + 8, 30, 36, 32))
	cfg_b.name = "SpeedGear"
	cfg_b.pressed.connect(_open_settings)
	_draw_ctl(cfg_b, Rect2(6, 4, 24, 24), func(c: Control): _draw_gear(c, Vector2(12, 12), 9.0, CYAN))
	_place_speed_readout()

func _speed_labels_overlap() -> bool:
	if speed_title == null or speed_lbl == null or speed_hint == null:
		return false
	var rects: Array[Rect2] = [speed_title.get_global_rect(), speed_lbl.get_global_rect(), speed_hint.get_global_rect()]
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var hit: Rect2 = rects[i].intersection(rects[j])
			if hit.size.x > 1.0 and hit.size.y > 1.0:
				return true
	return false

# ---- leaderboard ----
func _build_leaderboard() -> void:
	var p := _P(ui, Rect2(1302, 22, 288, 336))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(14, 13, 16, 14), func(c: Control):
		c.draw_rect(Rect2(0, 6, 4, 8), ORANGE_Y); c.draw_rect(Rect2(6, 0, 4, 14), ORANGE_Y); c.draw_rect(Rect2(12, 3, 4, 11), ORANGE_Y))
	_head(p, "LEADERBOARD", Vector2(38, 10), 14, TEXT)
	lb_alive = _T(p, "", Vector2(160, 11), 13, MUTED, f_reg, 112, HORIZONTAL_ALIGNMENT_RIGHT)
	_head(p, "#", Vector2(16, 38), 10, MUTED)
	_head(p, "NATION", Vector2(52, 38), 10, MUTED)
	_head(p, "LAND", Vector2(170, 38), 10, MUTED, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	_head(p, "TROOPS", Vector2(222, 38), 10, MUTED, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	for k in 10:
		var y := 58 + k * 23
		var row := [
			_T(p, str(k + 1), Vector2(8, y), 13, MUTED, f_bold, 22, HORIZONTAL_ALIGNMENT_RIGHT),
			_draw_ctl(p, Rect2(38, y + 7, 9, 9), func(c: Control): c.draw_style_box(_flat(c.get_meta("col", Color.GRAY), 2), Rect2(0, 0, 9, 9))),
			_T(p, "", Vector2(52, y), 13, TEXT, f_bold, 118),
			_T(p, "", Vector2(170, y), 13, TEXT, f_bold, 52, HORIZONTAL_ALIGNMENT_RIGHT),
			_T(p, "", Vector2(222, y), 13, Color(0.85, 0.88, 0.95), f_reg, 52, HORIZONTAL_ALIGNMENT_RIGHT)]
		lb_rows.append(row)
	lb_dots = _T(p, "•••", Vector2(0, 286), 12, MUTED, f_bold, 288, HORIZONTAL_ALIGNMENT_CENTER)
	var me := _P(p, Rect2(8, 302, 272, 28), Color(0.16, 0.14, 0.12), 8, ORANGE_Y, 1, false)
	lb_me = [
		_T(me, "", Vector2(0, 4), 13, MUTED, f_bold, 30, HORIZONTAL_ALIGNMENT_RIGHT),
		_draw_ctl(me, Rect2(30, 10, 9, 9), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 2), Rect2(0, 0, 9, 9))),
		_T(me, "You", Vector2(44, 4), 13, ORANGE_Y, f_bold, 118),
		_T(me, "", Vector2(162, 4), 13, TEXT, f_bold, 52, HORIZONTAL_ALIGNMENT_RIGHT),
		_T(me, "", Vector2(214, 4), 13, TEXT, f_reg, 52, HORIZONTAL_ALIGNMENT_RIGHT)]

func _build_attacks() -> void:
	atk_panel_p = _P(ui, Rect2(1302, 368, 288, 80))
	hud_nodes.append(atk_panel_p)
	_draw_ctl(atk_panel_p, Rect2(14, 13, 14, 14), func(c: Control):
		c.draw_line(Vector2(0, 0), Vector2(14, 14), ORANGE_Y, 2); c.draw_line(Vector2(14, 0), Vector2(0, 14), ORANGE_Y, 2))
	_head(atk_panel_p, "ATTACKS", Vector2(36, 10), 14, TEXT)
	atk_count = _T(atk_panel_p, "", Vector2(160, 11), 13, MUTED, f_reg, 112, HORIZONTAL_ALIGNMENT_RIGHT)
	atk_empty = _T(atk_panel_p, "No active attacks", Vector2(16, 44), 13, MUTED)
	for k in 6:
		var y := 40 + k * 32
		var bg := _P(atk_panel_p, Rect2(8, y, 272, 28), CELL_BG, 8, Color(0, 0, 0, 0), 0, false)
		var dot := _draw_ctl(bg, Rect2(8, 9, 10, 10), func(c: Control):
			c.draw_circle(Vector2(5, 5), 5, c.get_meta("col", GREEN)); c.draw_circle(Vector2(5, 5), 2.5, Color(0, 0, 0, 0.35)))
		var nm := _T(bg, "", Vector2(26, 4), 13, TEXT, f_bold, 140)
		var tr := _T(bg, "", Vector2(160, 4), 13, TEXT, f_bold, 66, HORIZONTAL_ALIGNMENT_RIGHT)
		var rb := Button.new(); rb.position = Vector2(236, 2); rb.size = Vector2(32, 24); rb.focus_mode = Control.FOCUS_NONE
		rb.add_theme_stylebox_override("normal", _flat(Color(1, 1, 1, 0.07), 6)); rb.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.16), 6))
		rb.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.2), 6))
		bg.add_child(rb)
		_draw_ctl(rb, Rect2(8, 4, 16, 16), func(c: Control):
			c.draw_arc(Vector2(9, 9), 5, -PI * 0.9, PI * 0.5, 12, TEXT, 1.6, true)
			c.draw_colored_polygon(PackedVector2Array([Vector2(0, 5), Vector2(6, 2), Vector2(5, 8)]), TEXT))
		var kk: int = k
		rb.pressed.connect(func():
			var mine := _player_attacks()
			if kk < mine.size() and mine[kk] in attacks and mine[kk].a == PLAYER: retreat(mine[kk]))
		atk_rows.append([bg, dot, nm, tr, rb])

func _player_attacks() -> Array:
	var out := []
	for at in attacks:
		if at.a == PLAYER: out.append(at)
	for at in attacks:
		if at.t == PLAYER: out.append(at)
	return out

func _build_bottom() -> void:
	var p := _P(ui, Rect2(320, 706, 960, 182))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(22, 20, 14, 14), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 3, Color(1, 1, 1, 0.6), 1), Rect2(0, 0, 14, 14)))
	_T(p, "You", Vector2(44, 12), 20, TEXT, f_bold)
	bb_name_sub = _T(p, "", Vector2(22, 44), 13, MUTED)
	_vline(p, 236, 14, 70)
	# troops
	_draw_ctl(p, Rect2(252, 11, 17, 17), func(c: Control):
		var ti := _tex("ui_icons/troops.png")
		if ti: c.draw_texture_rect(ti, Rect2(0, 0, 17, 17), false, MUTED)
		else: c.draw_circle(Vector2(6, 3), 3, MUTED))
	_head(p, "TROOPS", Vector2(272, 10), 11, MUTED)
	bb_regen = _T(p, "", Vector2(330, 10), 13, GREEN, f_bold, 130, HORIZONTAL_ALIGNMENT_RIGHT)
	bb_regen.clip_text = true
	bb_troops = _T(p, "", Vector2(252, 26), 28, TEXT, f_bold)
	bb_cap = _T(p, "", Vector2(340, 37), 14, MUTED)
	bb_bar = _draw_ctl(p, Rect2(254, 70, 100, 8), func(c: Control):
		var v: float = c.get_meta("v", 0.0)
		c.draw_style_box(_flat(Color(1, 1, 1, 0.1), 3), Rect2(0, 1, 100, 5))
		c.draw_style_box(_flat(Color(0.35, 0.62, 1.0), 3), Rect2(0, 1, maxf(3, 100 * v), 5))
		c.draw_rect(Rect2(42, 0, 2, 7), GOLD_C))
	bb_war = _T(p, "", Vector2(360, 62), 13, ORANGE_Y, f_bold, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	_vline(p, 474, 14, 70)
	# attack share
	_draw_ctl(p, Rect2(490, 15, 11, 11), func(c: Control):
		c.draw_line(Vector2(0, 0), Vector2(11, 11), MUTED, 1.6); c.draw_line(Vector2(11, 0), Vector2(0, 11), MUTED, 1.6))
	_head(p, "ATTACK", Vector2(508, 10), 11, MUTED)
	bb_share = _T(p, "", Vector2(630, 9), 14, ORANGE_Y, f_bold, 60, HORIZONTAL_ALIGNMENT_RIGHT)
	var pill := _P(p, Rect2(488, 32, 204, 30), Color(1, 1, 1, 0.06), 8, Color(0, 0, 0, 0), 0, false)
	share_hl = _P(pill, Rect2(3 + share_i * 40, 3, 38, 24), ORANGE_Y, 7, Color(0, 0, 0, 0), 0, false)
	for k in SHARES.size():
		var b := _btn("%d%%" % int(SHARES[k] * 100), k == share_i)
		b.position = Vector2(3 + k * 40, 3); b.size = Vector2(38, 24)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func(): _set_share(k))
		pill.add_child(b); share_btns.append(b)
	bb_sends = _T(p, "", Vector2(490, 64), 13, MUTED)
	_vline(p, 708, 14, 70)
	# gold
	_draw_ctl(p, Rect2(722, 11, 17, 17), func(c: Control):
		var tg := _tex("ui_icons/gold.png")
		if tg: c.draw_texture_rect(tg, Rect2(0, 0, 17, 17), false, GOLD_C)
		else: c.draw_circle(Vector2(6, 6), 6, GOLD_C))
	_head(p, "GOLD", Vector2(742, 10), 11, MUTED)
	bb_goldrate = _T(p, "", Vector2(780, 10), 13, GREEN, f_bold, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	bb_goldrate.clip_text = true
	bb_gold = _T(p, "", Vector2(722, 30), 28, GOLD_C, f_bold)
	# build slots
	var builds := [
		["1", "City", 125e3, "Adds 25K to your troop cap per level. Click an existing City to upgrade."],
		["2", "Port", 125e3, "Coastal only. Boosts overall gold income by 1.01x per level, hubs Trade Ships, and launches Warships."],
		["3", "Factory", 125e3, "Connects railways to Cities & Ports and dispatches one-way Gold Trucks."],
		["4", "Defense Post", 50e3, "Land within 30 tiles costs attackers 5x troops and 3x time (non-stacking)."],
		["5", "SAM Launcher", 1.5e6, "Shoots down bombs along their flight path (range 70 tiles at Lv1, up to 150). One missile per level, each reloads in 9 s."],
		["6", "Missile Silo", 1e6, "Launches nukes. One missile per level, each reloads in 9 s."],
		["7", "Warship", 250e3, "1,000 HP (+20% per veterancy, max 3). Shells transports and warships within 130 tiles, captures trade ships, repairs at your ports."],
		["8", "Atom Bomb", 750e3, "Tactical nuclear strike (7-tile blast radius) that leaves radioactive fallout."],
		["9", "Hydrogen Bomb", 5e6, "Strategic nuclear blast (25-tile radius) that wipes structures and troops."],
		["0", "MIRV", 25e6, "Splits into branched warheads covering 65-85% of the targeted country in fallout."],
		["", "Artillery", 150e3, "Shells enemy land and buildings within 45 tiles every 4-7 s: kills 2.88% of the army hit (1,440-19,200), 150 damage to buildings."],
		["", "Mega Nuke", 2.5e6, "Heavy nuclear warhead (15-tile blast radius)."],
		["", "Scattershot", 3.75e6, "An atom-sized crater at the aim plus 4-6 warheads 25-41 tiles around it (never on your or an ally's land)."],
		["", "Reinforcements", 100e3, "Adds a fifth of your troop cap (never past it). 30 s cooldown."],
		["", "Airfield", 500e3, "Build on your land. Aim at enemy land within 156 tiles for a free Air Strike (15-tile circle, up to 6% of the army, 600 to buildings). Rearms in 30 s."],
		["", "Railgun", 2.5e6, "Build on your land. Aim anywhere for a free slug (5-tile circle, up to 4% of the army, 1,000 to buildings). Reloads in 25 s."],
		["I", "ICBM", 0.0, "Upgrade toggle, not a warhead: while ON every bomb launch ignores range and costs +10% of that bomb's price."]]
	build_data = builds
	var sx := 16.0
	var order := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 11, 12, 10, 13, 14, 15]
	build_btns.resize(builds.size()); slot_price.resize(builds.size())
	for k in order:
		if k == 7: sx += 10
		var b := Button.new()
		b.position = Vector2(sx, 98); b.size = Vector2(46, 70); b.focus_mode = Control.FOCUS_NONE
		sx += 49
		b.add_theme_stylebox_override("normal", _flat(CELL_BG, 8, Color(1, 1, 1, 0.06), 1))
		b.add_theme_stylebox_override("hover", _flat(CELL_BG.lightened(0.08), 8, Color(1, 1, 1, 0.2), 1))
		b.add_theme_stylebox_override("pressed", _flat(CELL_BG.lightened(0.12), 8, ORANGE_Y, 1))
		b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 8))
		p.add_child(b)
		var kk: int = k
		if builds[k][0] != "": _T(b, builds[k][0], Vector2(5, 1), 10, MUTED, f_bold)
		var ic := Control.new(); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = Vector2(7, 16); ic.size = Vector2(32, 30)
		ic.draw.connect(func(): _icon(Vector2(16, 15), kk, Color(0.62, 0.7, 0.9) if is_avail(kk) else Color(0.45, 0.48, 0.58), 1.0 if is_avail(kk) else 0.4, ic, 11.0, false))
		b.add_child(ic)
		slot_price[k] = _T(b, _fmt(builds[k][2]), Vector2(0, 50), 12, GOLD_C, f_bold, 46, HORIZONTAL_ALIGNMENT_CENTER)
		b.pressed.connect(func(): select_build(kk))
		b.mouse_entered.connect(func(): tip_slot = kk)
		b.mouse_exited.connect(func(): if tip_slot == kk: tip_slot = -1)
		build_btns[k] = b
	var shop := _big_btn(p, Rect2(sx + 8, 98, 72, 70), "", ORANGE_Y, 12)
	_draw_ctl(shop, Rect2(0, 0, 72, 70), func(c: Control):
		var col := Color(0.12, 0.09, 0.05)
		c.draw_rect(Rect2(22, 20, 28, 20), col)
		c.draw_arc(Vector2(36, 20), 8, PI, TAU, 12, col, 3)
		c.draw_circle(Vector2(36, 30), 3, ORANGE_Y)
		f_head.draw_string(c.get_canvas_item(), Vector2(0, 60), "SHOP", HORIZONTAL_ALIGNMENT_CENTER, 72, 12, col))
	shop.pressed.connect(_open_shop)
	shop.mouse_entered.connect(func(): tip_slot = 99)
	shop.mouse_exited.connect(func(): if tip_slot == 99: tip_slot = -1)

# ---- help ----
func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.visible = false
	help_panel.position = Vector2(300, 110); help_panel.size = Vector2(1000, 640)
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.085, 0.15, 0.98), 18))
	ui.add_child(help_panel)
	var c := Control.new(); c.custom_minimum_size = Vector2(984, 624); help_panel.add_child(c)
	_head(c, "HOW TO PLAY", Vector2(28, 18), 28, TEXT)
	_T(c, "Grow from a single foothold to 80% of the world.", Vector2(28, 58), 15, MUTED)
	var x := _card_btn(c, Rect2(924, 16, 44, 44)); x.text = "✕"
	x.pressed.connect(func(): help_panel.visible = false)
	var items := [
		["01", "Found your nation", "Click unclaimed land. You have 5 seconds to change your mind.", ORANGE_Y],
		["02", "Grow & fight", "Click wilderness to expand or a neighbour to attack. Q / E or the Attack pills set how many troops go.", RED],
		["03", "Cross the sea", "Click a coast you can't reach by land: a transport sails from your nearest shore.", CYAN],
		["04", "Build", "Keys 1-4 then click your land: City, Port (coast), Factory, Defense Post. R = reinforcements.", GREEN],
		["05", "Controls", "WASD / arrows or drag to pan · wheel zoom · Space attack at cursor · Backspace retreat · -/+ speed · Esc menu", Color(0.7, 0.6, 1.0)]]
	for k in items.size():
		var it = items[k]
		var card := _P(c, Rect2(28 + (k % 2) * 470, 96 + (k / 2) * 170, 456 if k < 4 else 926, 150), CELL_BG, 14, Color(1, 1, 1, 0.06), 1, false)
		var col: Color = it[3]
		_draw_ctl(card, Rect2(18, 20, 48, 48), func(cc: Control):
			cc.draw_circle(Vector2(24, 24), 23, Color(col, 0.18)); cc.draw_arc(Vector2(24, 24), 23, 0, TAU, 36, col, 2, true)
			cc.draw_circle(Vector2(24, 24), 6, col))
		_T(card, it[0], Vector2(82, 18), 14, col, f_bold)
		_T(card, it[1], Vector2(110, 15), 19, TEXT, f_bold)
		var d := _T(card, it[2], Vector2(82, 48), 15, Color(0.8, 0.84, 0.94))
		d.size = Vector2((456 if k < 4 else 926) - 100, 90); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_over() -> void:
	var holder := Control.new(); holder.set_anchors_preset(Control.PRESET_FULL_RECT); holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)
	var p := _P(holder, Rect2(600, 300, 400, 240))
	over_label = _head(p, "", Vector2(0, 30), 40, ORANGE_Y, 400, HORIZONTAL_ALIGNMENT_CENTER)
	over_label.size.y = 52
	var sub := _T(p, "", Vector2(0, 92), 16, MUTED, f_reg, 400, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "sub"; sub.size.y = 50
	var mb := _big_btn(p, Rect2(90, 160, 220, 52), "MAIN MENU", ORANGE_Y, 18)
	mb.pressed.connect(_to_menu)
	over_panel = PanelContainer.new()
	holder.visible = false
	# use holder as the toggled node
	over_panel = null
	over_panel_holder = holder
	over_panel_p = p

# ---- tooltip rendering ----
func _wrap(t: String, f: Font, fs: int, w: float) -> Array:
	var out := []
	var line := ""
	for word in t.split(" "):
		var cand := word if line == "" else line + " " + word
		if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w and line != "":
			out.append(line); line = word
		else:
			line = cand
	if line != "": out.append(line)
	return out

func _show_tip(d: Dictionary, anchor: Vector2, above: bool) -> void:
	tip_data = d
	var fT := RK.font(700); var fB := RK.font(700); var fR := RK.font(500); var fV := RK.font(600)
	var w := 220.0 if above else 236.0
	var tw := fT.get_string_size(str(d.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	if d.has("badge"): tw += fB.get_string_size(str(d.badge), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 16 + 10
	w = maxf(w, tw + TIP_PAD.x * 2)
	if d.has("sub"): w = maxf(w, minf(fR.get_string_size(str(d.sub), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + TIP_PAD.x * 2, 300.0))
	for r in d.get("rows", []):
		w = maxf(w, fR.get_string_size(str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + fV.get_string_size(str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24 + TIP_PAD.x * 2)
	w = minf(ceilf(w), 340.0)
	var h := TIP_PAD.y + 20.0
	if d.has("sub"):
		d.sub_lines = _wrap(str(d.sub), fR, 12, w - TIP_PAD.x * 2)
		h += 2 + d.sub_lines.size() * 15
	var rows: Array = d.get("rows", [])
	if rows.size() > 0: h += 6 + rows.size() * 19
	if d.has("desc"):
		d.desc_lines = _wrap(d.desc, fR, 12, w - TIP_PAD.x * 2)
		h += 6 + d.desc_lines.size() * 16
	if d.has("foot"):
		d.foot_lines = _wrap(d.foot, fV, 12, w - TIP_PAD.x * 2 - 20)
		h += 9 + 8 + d.foot_lines.size() * 16
	h += TIP_PAD.y
	tipc.size = Vector2(w, ceilf(h))
	var pos := anchor + (Vector2(-w / 2, -h - 10) if above else Vector2(20, 22))
	var vs := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1600, 900)
	pos.x = clampf(pos.x, 8, vs.x - w - 8); pos.y = clampf(pos.y, 8, vs.y - h - 8)
	tipc.position = pos.round()
	tipc.visible = true
	tipc.queue_redraw()

func _tip_hex(c: Color) -> Color:
	# map the port's legacy palette onto the upstream tokens
	if c == ORANGE_Y: return RK.AMBER
	if c == GOLD_C: return RK.GOLD
	if c == RED: return RK.RED
	if c == GREEN: return RK.GREEN
	if c == CYAN: return RK.CYAN
	if c == MUTED: return RK.TEXT_3
	if c == TEXT: return RK.TEXT
	return c

func _draw_tip() -> void:
	var d := tip_data
	var w := tipc.size.x
	var sz := tipc.size
	var gs := RK.glass_style(RK.GLASS, RK.R_MD, RK.LINE, 18)
	tipc.draw_style_box(gs, Rect2(Vector2.ZERO, sz))
	# top sheen
	for i in 4:
		var y0 := sz.y * 0.6 * i / 4.0
		tipc.draw_rect(Rect2(2, y0 + 1, sz.x - 4, sz.y * 0.15), Color(1, 1, 1, RK.GLASS_SHEEN * (1.0 - (i + 0.5) / 4.0)))
	var fT := RK.font(700); var fB := RK.font(700); var fR := RK.font(500); var fV := RK.font(600)
	var ci := tipc.get_canvas_item()
	var x0 := TIP_PAD.x
	var y := TIP_PAD.y
	var bw := 0.0
	if d.has("badge"):
		var bt: String = str(d.badge).to_upper()
		var bc: Color = _tip_hex(d.get("badge_col", MUTED))
		bw = fB.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 16
		tipc.draw_style_box(RK.flat(RK.c(bc, 0.16), 999, RK.c(bc, 0.5), 1), Rect2(w - x0 - bw, y + 1, bw, 18))
		fB.draw_string(ci, Vector2(w - x0 - bw, y + 14), bt, HORIZONTAL_ALIGNMENT_CENTER, bw, 10, bc)
	fT.draw_string(ci, Vector2(x0, y + 15), d.get("title", ""), HORIZONTAL_ALIGNMENT_LEFT, w - x0 * 2 - bw - 8, 15, RK.TEXT)
	y += 20
	if d.has("sub_lines"):
		y += 2
		for ln in d.sub_lines:
			fR.draw_string(ci, Vector2(x0, y + 12), ln, HORIZONTAL_ALIGNMENT_LEFT, w - x0 * 2, 12, RK.TEXT_2)
			y += 15
	var rows: Array = d.get("rows", [])
	if rows.size() > 0:
		y += 6
		for r in rows:
			fR.draw_string(ci, Vector2(x0, y + 14), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RK.TEXT_3)
			fV.draw_string(ci, Vector2(x0, y + 14), str(r[1]), HORIZONTAL_ALIGNMENT_RIGHT, w - x0 * 2, 13, _tip_hex(r[2]))
			y += 19
	if d.has("desc_lines"):
		y += 6
		for ln in d.desc_lines:
			fR.draw_string(ci, Vector2(x0, y + 12), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RK.TEXT_2)
			y += 16
	if d.has("foot_lines"):
		y += 8
		tipc.draw_line(Vector2(x0, y), Vector2(w - x0, y), RK.LINE, 1)
		y += 9
		var fc: Color = _tip_hex(d.get("foot_col", RED))
		var icn := "info" if d.get("foot_icon", "!") == "!" else "target"
		var t := RK.icon_tex(icn)
		if t: tipc.draw_texture_rect(t, Rect2(x0, y, 14, 14), false, fc)
		for ln in d.foot_lines:
			fV.draw_string(ci, Vector2(x0 + 20, y + 12), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)
			y += 16

func _update_build_tip() -> bool:
	if tip_slot < 0 or state != "play":
		return false
	var pl = nations[PLAYER]
	if tip_slot == 99:
		_show_tip({"title": "Shop & Arsenal (★ %s)" % _fmt_int(save.stars), "desc": "Stars & Shop are unified here: view your Star balance, match reward breakdown, and unlock weapons & perks.", "foot": "Click to open Shop & Arsenal", "foot_col": GOLD_C, "foot_icon": "o"}, (hud.shop_btn.global_position + Vector2(hud.shop_btn.size.x * 0.5, 0)) if hud != null else Vector2(build_btns[13].global_position.x + 100, 800), true)
		return true
	var k := tip_slot
	if k == 16:
		var rows := [["Status", "ON" if icbm_mode else "OFF", ORANGE_Y if icbm_mode else MUTED], ["Fee", "+10% of the bomb's price", GOLD_C]]
		for nk in [7, 8, 9, 11, 12]:
			rows.append([build_data[nk][1], "%s  →  %s" % [_fmt(float(build_data[nk][2])), _fmt(float(build_data[nk][2]) * (1.0 + ICBM_FEE_PCT))], GOLD_C])
		_show_tip({"title": "ICBM upgrade", "badge": "I", "rows": rows, "desc": build_data[16][3], "foot": "Click to turn " + ("OFF" if icbm_mode else "ON"), "foot_col": CYAN, "foot_icon": "o"}, build_btns[16].global_position + Vector2(build_btns[16].size.x * 0.5, 0), true)
		return true
	var bd = build_data[k]
	var cost := build_cost(PLAYER, k)
	var d := {"title": bd[1], "rows": [["Cost", _fmt(cost) + " gold", GOLD_C]], "desc": bd[3]}
	if bd[0] != "": d.badge = bd[0]
	if k == 13:
		d.rows.append(["Brings", _fmt(minf(troop_cap(PLAYER) / 5.0, troop_cap(PLAYER) - pl.troops)) + " troops", TEXT])
	else:
		var oc := owned_count(PLAYER, k)
		var ol := owned(PLAYER, k)
		d.rows.append(["Owned / Levels", ("%d (total Lv %d)" % [oc, ol]) if k in UPGRADABLE else str(oc), TEXT])
		if k in UPGRADABLE:
			d.rows.append(["Upgrade", "Click existing %s on map" % bd[1], GREEN])
	if k in [7, 8, 9, 11]:
		d.rows.append(["Blast radius", "%d tiles" % int(NUKE_R[k]) if k != 9 else "many warheads", TEXT])
		d.rows.append(["Range", "Anywhere (ICBM +10%)" if icbm_mode else nuke_range_label(k), ORANGE_Y if icbm_mode else TEXT])
	var req := build_req(k, -1)
	if k == 13 and pl.troops >= troop_cap(PLAYER) - 1: req = "Your army is already at its cap"
	if req != "":
		d.foot = req; d.foot_col = RED
	elif pl.gold < cost:
		d.foot = "Need %s more gold" % _fmt(cost - pl.gold); d.foot_col = RED
	elif k == 13:
		d.foot = "Click to call them in now"; d.foot_col = CYAN; d.foot_icon = "o"
	elif k == 6:
		d.foot = "Click to select & place on water (or click twice to launch at Port)"; d.foot_col = CYAN; d.foot_icon = "o"
	else:
		d.foot = "Click, then pick a spot on your land" + (" by the coast" if k == 1 else ""); d.foot_col = CYAN; d.foot_icon = "o"
	var b: Button = build_btns[k]
	_show_tip(d, b.global_position + Vector2(b.size.x * 0.5, 0), true)
	return true

func _update_hud() -> void:
	if nations.size() < 2: return
	var pl = nations[PLAYER]
	if hud != null:
		var now_h := Time.get_ticks_msec() / 1000.0
		var hdt_h := clampf(now_h - _hud_rate_t, 0.0, 1.0); _hud_rate_t = now_h
		var ka_h := 1.0 - exp(-hdt_h / 1.0)
		_ema_regen = lerpf(_ema_regen, float(pl.regen), ka_h) if _ema_init else float(pl.regen)
		_ema_gold = lerpf(_ema_gold, gold_rate(PLAYER), ka_h) if _ema_init else gold_rate(PLAYER)
		_ema_init = true
		var txt_h := now_h - _hud_txt_t >= 0.25
		if txt_h: _hud_txt_t = now_h
		hud.refresh_all(_ema_regen, _ema_gold, txt_h)
		return
	var left := peace - elapsed
	if left > 0:
		top_left_head.text = "PROTECTED"; top_left_head.add_theme_color_override("font_color", GREEN)
		top_timer.text = _fmt_time(left); top_timer.add_theme_color_override("font_color", GREEN)
	else:
		top_left_head.text = "AT WAR"; top_left_head.add_theme_color_override("font_color", RED)
		top_timer.text = _fmt_time(elapsed); top_timer.add_theme_color_override("font_color", TEXT)
	var pct: float = 100.0 * pl.land / maxf(1, land_total)
	var ids := []
	for id in range(1, nations.size()):
		if nations[id].alive and nations[id].land > 0: ids.append(id)
	ids.sort_custom(func(a, b): return nations[a].land > nations[b].land)
	var lead_id: int = ids[0] if ids.size() > 0 else PLAYER
	var lead_pct: float = 100.0 * nations[lead_id].land / maxf(1, land_total)
	top_bar_ctl.set_meta("you", pct); top_bar_ctl.set_meta("lead", lead_pct); top_bar_ctl.queue_redraw()
	top_you.text = "You %s" % _pct(pct)
	top_lead.text = "%s %s" % [("You" if lead_id == PLAYER else nations[lead_id].name), _pct(lead_pct)]
	# leaderboard
	lb_alive.text = "%d alive" % ids.size()
	for k in 10:
		var row = lb_rows[k]
		var vis: bool = k < ids.size()
		for c in row: c.visible = vis
		if not vis: continue
		var n = nations[ids[k]]
		row[0].add_theme_color_override("font_color", ORANGE_Y if k == 0 else MUTED)
		row[1].set_meta("col", n.color); row[1].queue_redraw()
		row[2].text = "You" if ids[k] == PLAYER else n.name
		row[2].add_theme_color_override("font_color", ORANGE_Y if ids[k] == PLAYER else TEXT)
		row[3].text = _pct(100.0 * n.land / maxf(1, land_total))
		row[4].text = _fmt(n.troops)
	var my_rank := ids.find(PLAYER) + 1
	lb_me[0].text = str(my_rank); lb_me[3].text = _pct(pct); lb_me[4].text = _fmt(pl.troops)
	# attacks
	var list := _player_attacks()
	var outs := 0
	for at in list: if at.a == PLAYER: outs += 1
	atk_count.text = "%d out · %d in" % [outs, list.size() - outs]
	atk_empty.visible = list.is_empty()
	for k in atk_rows.size():
		var r = atk_rows[k]
		var vis: bool = k < list.size()
		r[0].visible = vis
		if not vis: continue
		var at = list[k]
		var out: bool = at.a == PLAYER
		var other: int = at.t if out else at.a
		r[1].set_meta("col", GREEN if out else RED); r[1].queue_redraw()
		r[2].text = ("Expansion" if other == NEUTRAL else nations[other].name) if out else ("⚠ " + nations[other].name)
		r[2].add_theme_color_override("font_color", TEXT if out else RED)
		r[3].text = _fmt(at.troops)
		r[4].visible = out
	atk_panel_p.size.y = 40 + maxi(1, list.size()) * 32 + 8
	# bottom
	bb_name_sub.text = "%s of the world" % _pct(pct)
	var cap := troop_cap(PLAYER)
	var cap_pct := int(round(100.0 * pl.troops / maxf(1.0, cap)))
	# smoothed rates: ~1 s EMA, text refreshed at 4 Hz
	var now_s := Time.get_ticks_msec() / 1000.0
	var hdt := clampf(now_s - _hud_rate_t, 0.0, 1.0); _hud_rate_t = now_s
	var ka := 1.0 - exp(-hdt / 1.0)
	_ema_regen = lerpf(_ema_regen, float(pl.regen), ka) if _ema_init else float(pl.regen)
	_ema_gold = lerpf(_ema_gold, gold_rate(PLAYER), ka) if _ema_init else gold_rate(PLAYER)
	_ema_init = true
	if now_s - _hud_txt_t >= 0.25:
		_hud_txt_t = now_s
		bb_regen.text = "%s%s/s (%d%%)" % ["+" if _ema_regen >= 0 else "", _fmt(_ema_regen), clampi(cap_pct, 0, 999)]
		bb_goldrate.text = "+%s/s" % _fmt(_ema_gold)
	bb_cap.position.x = bb_troops.position.x + f_bold.get_string_size(bb_troops.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 6
	bb_cap.text = "/ %s" % _fmt(cap)
	bb_bar.set_meta("v", clampf(pl.troops / maxf(cap, 1.0), 0.0, 1.0)); bb_bar.queue_redraw()  # clamp: over-cap troops drew a bar across the whole screen
	var at_war := 0.0
	for at in attacks: if at.a == PLAYER: at_war += at.troops
	for bt in boats: if bt.a == PLAYER: at_war += bt.troops
	bb_war.text = ("%s at war" % _fmt(at_war)) if at_war > 0 else ""
	bb_share.text = "%d%%" % int(SHARES[share_i] * 100)
	bb_sends.text = "Sends %s troops" % _fmt(pl.troops * SHARES[share_i])
	var silo_ready := false
	var min_silo_cd := 999.0
	for st in structs:
		if st.o == PLAYER and st.k == 5 and st.get("bt", 0.0) <= 0.0:
			if _ready_slots(st) > 0: silo_ready = true; break
			min_silo_cd = minf(min_silo_cd, float(st.get("cd", 0.0)))
	for k in build_btns.size():
		var cost := build_cost(PLAYER, k)
		if k == 16:
			slot_price[k].text = "ON" if icbm_mode else "+10%"
			slot_price[k].add_theme_color_override("font_color", ORANGE_Y if icbm_mode else GOLD_C)
			build_btns[k].add_theme_stylebox_override("normal", _flat(Color(0.26, 0.2, 0.1) if icbm_mode else CELL_BG, 8, ORANGE_Y if icbm_mode else Color(1, 1, 1, 0.06), 1))
			continue
		if k in NUKES and owned(PLAYER, 5) > 0 and not silo_ready and min_silo_cd < 900.0:
			slot_price[k].text = "%ds" % maxi(1, ceili(min_silo_cd))
			slot_price[k].add_theme_color_override("font_color", RED)
		elif (k == 14 or k == 15) and _strike_cd(k) > 0.0:
			slot_price[k].text = "%ds" % maxi(1, ceili(_strike_cd(k)))
			slot_price[k].add_theme_color_override("font_color", RED)
		else:
			slot_price[k].text = _fmt(cost)
			var can: bool = pl.gold >= cost and is_avail(k) and build_req(k, -1) == ""
			slot_price[k].add_theme_color_override("font_color", GOLD_C if can else RED)
		var sel: bool = k == build_sel
		build_btns[k].modulate.a = 1.0 if is_avail(k) else 0.55
		build_btns[k].add_theme_stylebox_override("normal", _flat(Color(0.26, 0.2, 0.1) if sel else CELL_BG, 8, ORANGE_Y if sel else Color(1, 1, 1, 0.06), 2 if sel else 1))

# seconds until the player's first airfield / railgun is loaded again (0 = one is ready or none built)
func _strike_cd(k: int) -> float:
	var best := INF
	for st in structs:
		if st.o == PLAYER and st.k == k and st.get("bt", 0.0) <= 0.0:
			if sim_ars.ready_missiles(st) > 0: return 0.0
			best = minf(best, float(st.get("cd", 0.0)))
	return 0.0 if best == INF else best

func _pct(v: float) -> String:
	if v < 10: return "%.2f%%" % v
	return "%.1f%%" % v

func _update_tooltip() -> void:
	if autoshot and _r29 >= 4 and _r29 != 5:
		tipc.visible = false; return
	if (state == "play" or state == "pick") and _update_build_tip(): return
	if state != "play" and state != "pick":
		tipc.visible = false; return
	if get_viewport().gui_get_hovered_control() != null:
		tipc.visible = false; return
	var t := _mouse_tile()
	if t < 0 or (owner_map[t] == WATER and build_sel != 6):
		tipc.visible = false; return
	if owner_map[t] == WATER and build_sel == 6:
		var mp_w := get_viewport().get_mouse_position()
		var cost_w := build_cost(PLAYER, 6)
		var req_w := build_req(6, t)
		var d_w := {"title": "Deploy Warship", "badge": "NAVAL", "badge_col": CYAN,
			"rows": [["Cost", _fmt(cost_w) + " gold", GOLD_C], ["Active Warships", str(_count_ws(PLAYER)), TEXT]],
			"desc": "Click water or coast to deploy a Warship here, or press 7 again to launch at your Port.",
			"foot": (req_w if req_w != "" else ("Click to deploy Warship" if nations[PLAYER].gold >= cost_w else "Need %s more gold" % _fmt(cost_w - nations[PLAYER].gold))),
			"foot_col": RED if (req_w != "" or nations[PLAYER].gold < cost_w) else CYAN, "foot_icon": "!" if (req_w != "" or nations[PLAYER].gold < cost_w) else "o"}
		_show_tip(d_w, mp_w, false)
		return
	var o: int = owner_map[t]
	var mp := get_viewport().get_mouse_position()
	var send: float = nations[PLAYER].troops * SHARES[share_i]
	var terrain: String = ["Plains (loss 80, cost 16.5)", "Highland (loss 100, cost 20: 1.25x loss, 1.2x slower)", "Mountains (loss 120, cost 25: 1.5x loss, 1.5x slower)"][clampi(mtn[t], 0, 2)]
	if snow_src.size() == W * H and snow_src[t] == 4: terrain = "Snow (plains rules: loss 80, cost 16.5)"
	var d := {}
	if state == "play" and build_sel in NUKES:
		var r: int = int(NUKE_R[build_sel]) if build_sel != 12 else int(46 * BLAST_S)
		var hit := {}
		var cx := t % W; var cy := t / W
		for k in 200:
			var pp := Vector2(cx, cy) + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * r
			var xx := int(pp.x); var yy := int(pp.y)
			if xx >= 0 and yy >= 0 and xx < W and yy < H and owner_map[yy * W + xx] > 0: hit[owner_map[yy * W + xx]] = true
		var sam_risk := false
		if build_sel != 9:
			for st in structs:
				if st.k == 4 and st.o != PLAYER and Vector2(st.tile % W, st.tile / W).distance_to(Vector2(cx, cy)) <= 70: sam_risk = true
		var names := []
		for h in hit: names.append(_nname(h))
		d = {"title": "Target: " + build_data[build_sel][1], "badge": "AIM", "badge_col": RED,
			"rows": [["Blast radius", "%d tiles" % r, TEXT], ["Cost", _fmt(nuke_cost(build_sel) if build_sel in NUKES else float(build_data[build_sel][2])) + " gold", GOLD_C], ["Hits", "%d nation(s)" % hit.size(), TEXT]],
			"desc": ("Affects: " + ", ".join(names.slice(0, 4))) if names.size() > 0 else "Only wilderness in range.",
			"foot": ("Enemy SAM covers this spot — likely intercepted" if sam_risk else "Click to launch · right-click to cancel"),
			"foot_col": RED if sam_risk else CYAN, "foot_icon": "!" if sam_risk else "o"}
		_show_tip(d, mp, false)
		return
	if o == ICE:
		d = {"title": "Unclaimed  ·  Ice cap", "foot": "Ice caps can't be claimed", "foot_col": MUTED}
	elif o == NEUTRAL:
		var fo_mult := SimRules.fallout_modifier(float(fallout_count) / maxf(float(land_total), 1.0))
		var sub: String = terrain + (" · slow to take" if mtn[t] == 2 else "") + (("  ·  Fallout (%.1fx cost)" % fo_mult) if fallout[t] == 1 else "")
		d = {"title": "Wilderness", "sub": sub, "foot": ("Click: found your nation here" if state == "pick" else "Click: expand with %s" % _fmt(send)), "foot_col": CYAN, "foot_icon": "o"}
		if state == "pick":
			var nc := _neighbour_count(t)
			d.rows = [["Neighbours nearby", str(nc), TEXT]]
			if nc >= 5:
				d.desc = "Crowded — a tough start with many rivals close by."
				d.foot = "Tough start: expect early fights"; d.foot_col = RED; d.foot_icon = "!"
			elif nc >= 3:
				d.desc = "Some rivals nearby. Expand quickly."
			else:
				d.desc = "Quiet area — room to grow."
	elif o == PLAYER:
		var n = nations[o]
		d = {"title": "You", "badge": "YOU", "badge_col": ORANGE_Y, "sub": "Commander  ·  " + terrain, "rows": [["Troops", _fmt(n.troops), TEXT], ["Land", _pct(100.0 * n.land / land_total), TEXT], ["Gold", _fmt(n.gold), GOLD_C]]}
	else:
		var n = nations[o]
		var foot := "Click: attack with %s" % _fmt(send)
		var fc := CYAN
		var badge := "PLAYER" if is_bot(o) else ("NATION" if is_prot(o) else "TRIBE")
		var bcol := ORANGE_Y if is_prot(o) else MUTED
		var hint := "Right-click: Diplomacy (Ally, Donate Troops & Gold)"
		if allied(PLAYER, o):
			badge = "ALLY"; bcol = GREEN
			foot = "Allied for %s" % _fmt_time((int(allies[_akey(PLAYER, o)]) - sim_atk.tick) / 10.0); fc = GREEN
			hint = "Right-click: Donate Troops/Gold or Break Alliance"
		if is_traitor(o):
			badge = "TRAITOR"; bcol = RED; hint = "Traitor: 0.5x defense & 0.8x speed for 30 s"
		d = {"title": n.name, "badge": badge, "badge_col": bcol, "sub": ("Player" if is_bot(o) else ("Nation" if is_prot(o) else "Tribe")) + "  ·  " + terrain, "rows": [["Troops", _fmt(n.troops), TEXT], ["Land", _pct(100.0 * n.land / land_total), TEXT]], "desc": hint, "foot": foot, "foot_col": fc, "foot_icon": "o"}
	_show_tip(d, mp, false)

func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

func _fmt(n: float) -> String:
	if is_nan(n): return "0"
	if is_inf(n): return "-∞" if n < 0 else "∞"
	var a := absf(n)
	if a < 1000.0: return ("-" if n < 0 and int(a) > 0 else "") + str(int(a))
	var e := 0
	var v := a
	while v >= 999.95 and e < _FMT_U.size() - 1:
		v /= 1000.0; e += 1
	var t := ("%.2f" % v) if v < 10.0 else ("%.1f" % v)
	return ("-" if n < 0 else "") + t + _FMT_U[e]

func load_save() -> void:
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			save.stars = int(d.get("stars", 0))
			save.unlocked = d.get("unlocked", save.unlocked)
			if d.has("settings") and d.settings is Dictionary:
				for k in d.settings:
					save.settings[k] = d.settings[k]

func _is_embedded_window() -> bool:
	if Engine.has_method("is_embedded_in_editor") and bool(Engine.call("is_embedded_in_editor")):
		return true
	for a in OS.get_cmdline_args():
		if a == "--wid" or a.begins_with("--wid="):
			return true
	return false

func _line_aa() -> bool:
	return int(save.get("settings", {}).get("msaa_i", 2)) > 0 and int(save.get("settings", {}).get("qual_i", 3)) >= 1

func apply_settings(recolor_map := true) -> void:
	_qual_c = -1
	var cfg: Dictionary = save.get("settings", {})
	var res_i := clampi(int(cfg.get("res_i", 3)), 0, RES_LIST.size() - 1)
	var win_i := clampi(int(cfg.get("win_i", 0)), 0, 2)
	var fps_i := clampi(int(cfg.get("fps_i", 3)), 0, FPS_LIST.size() - 1)
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var vs: bool = bool(cfg.get("vsync", false))
	Engine.max_fps = FPS_LIST[fps_i]
	if get_viewport():
		if str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) != "gl_compatibility": get_viewport().msaa_2d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][msaa_i] as Viewport.MSAA
	_map_material().set_shader_parameter("quality", qual_i)
	if not autoshot and not bench and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
		# Only resize or switch OS Window Mode when NOT running inside Godot 4.4's embedded editor Game tab!
		if not _is_embedded_window():
			if win_i == 0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				var target_sz: Vector2i = RES_LIST[res_i]
				var scr := DisplayServer.window_get_current_screen()
				var srect := DisplayServer.screen_get_usable_rect(scr)
				if srect.size.x > 0 and srect.size.y > 0:
					var fit_w := mini(target_sz.x, srect.size.x)
					var fit_h := mini(target_sz.y, srect.size.y)
					DisplayServer.window_set_size(Vector2i(fit_w, fit_h))
					DisplayServer.window_set_position(srect.position + (srect.size - Vector2i(fit_w, fit_h)) / 2)
				else:
					DisplayServer.window_set_size(target_sz)
			elif win_i == 1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if menu_settings_sub:
		menu_settings_sub.text = "%dp · %d FPS · %s" % [RES_LIST[res_i].y, FPS_LIST[fps_i], QUAL_NAMES[qual_i]]
	if recolor_map and owner_map.size() == W * H:
		_recompute_base_colors()
	if overlay:
		overlay.queue_redraw()

func write_save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(save))

func unlocked(id: String) -> bool:
	return id in save.unlocked

func kind_locked(k: int) -> String:
	for it in ARSENAL:
		if it.k == k and not unlocked(it.id): return it.name
	return ""

func is_avail(k: int) -> bool:
	if god_mode: return k != 9 or mirv_enabled
	return (k != 9 or mirv_enabled) and kind_locked(k) == ""

func reload_mult() -> float:
	return 0.5 if unlocked("reload") else 1.0
