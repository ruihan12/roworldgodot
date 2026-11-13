extends "res://game/strikes.gd"
# Star pill and end-of-match screen

# ---------- star pill / small drawings ----------
func _star(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for m in 10:
		pts.append(p + Vector2.from_angle(-PI / 2 + m * PI / 5) * (r if m % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, col)

func _fmt_int(n: int) -> String:
	var s2 := str(absi(n))
	var out := ""
	while s2.length() > 3:
		out = "," + s2.substr(s2.length() - 3) + out
		s2 = s2.substr(0, s2.length() - 3)
	return ("-" if n < 0 else "") + s2 + out

# ---------- end-of-match screen ----------
func _build_end() -> void:
	end_dlg = Control.new(); end_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); end_dlg.visible = false
	ui.add_child(end_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.02, 0.04, 0.08, 0.62); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_dlg.add_child(sh)
	_head(end_dlg, "MATCH COMPLETE", Vector2(0, 150), 18, Color(0.8, 0.84, 0.95), 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var title := _T(end_dlg, "", Vector2(0, 178), 130, Color(1, 0.93, 0.7), f_head, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	title.size.y = 170
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.04))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55)); title.add_theme_constant_override("shadow_offset_y", 8)
	end_refs.title = title
	end_refs.sub = _T(end_dlg, "", Vector2(0, 380), 21, TEXT, f_bold, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var labels := ["PEAK LAND", "MAX TROOPS", "NATIONS ELIMINATED", "MATCH DURATION"]
	var icol := [ORANGE_Y, CYAN, RED, Color(0.7, 0.6, 1.0)]
	end_refs.vals = []
	for k in 4:
		var c := _P(end_dlg, Rect2(300 + k * 255, 450, 240, 140), Color(0.07, 0.085, 0.15, 0.95), 5)
		var col: Color = icol[k]
		var kk: int = k
		_draw_ctl(c, Rect2(105, 14, 30, 30), func(cc: Control): _end_icon(cc, kk, col))
		end_refs.vals.append(_T(c, "", Vector2(0, 52), 36, TEXT, f_bold, 240, HORIZONTAL_ALIGNMENT_CENTER))
		_head(c, labels[k], Vector2(0, 104), 12, MUTED, 240, HORIZONTAL_ALIGNMENT_CENTER)
	var pill := _P(end_dlg, Rect2(355, 622, 210, 64), Color(0.35, 0.27, 0.08, 0.5), 5, Color(1, 0.8, 0.3, 0.6), 1, false)
	_draw_ctl(pill, Rect2(18, 18, 28, 28), func(cc: Control): _star(cc, Vector2(14, 14), 12, GOLD_C))
	end_refs.stars = _T(pill, "", Vector2(56, 16), 24, GOLD_C, f_bold, 140, HORIZONTAL_ALIGNMENT_CENTER)
	var again := _big_btn(end_dlg, Rect2(585, 622, 300, 64), "PLAY AGAIN", ORANGE_Y, 22)
	_draw_ctl(again, Rect2(36, 20, 24, 24), func(cc: Control):
		cc.draw_colored_polygon(PackedVector2Array([Vector2(3, 1), Vector2(21, 12), Vector2(3, 23)]), Color(0.12, 0.09, 0.05)))
	again.pressed.connect(func(): end_dlg.visible = false; _start_game_ui())
	var back := _card_btn(end_dlg, Rect2(905, 622, 330, 64)); back.text = "Return to title"
	back.add_theme_font_override("font", f_bold); back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func(): end_dlg.visible = false; _to_menu())
	var prog := _P(end_dlg, Rect2(585, 706, 420, 46), Color(0.25, 0.2, 0.08, 0.45), 5, Color(1, 0.8, 0.3, 0.5), 1, false)
	_draw_ctl(prog, Rect2(16, 13, 16, 20), func(cc: Control):
		cc.draw_rect(Rect2(1, 8, 14, 11), GOLD_C); cc.draw_arc(Vector2(8, 8), 5, PI, TAU, 10, GOLD_C, 2.5))
	end_refs.prog = _T(prog, "", Vector2(44, 11), 17, GOLD_C, f_head, 370)
	end_refs.prog_p = prog

func show_end(win: bool) -> void:
	var earned := match_stars(win)
	save.stars += earned
	write_save()
	var clean := 0
	var mine := 0
	for i in W * H:
		if owner_map[i] >= 0 and owner_map[i] != ICE and fallout[i] == 0:
			clean += 1
			if owner_map[i] == PLAYER: mine += 1
	var pct := 100.0 * mine / maxf(1, clean)
	end_refs.title.text = "VICTORY" if win else "DEFEAT"
	end_refs.title.add_theme_color_override("font_color", Color(1, 0.93, 0.7) if win else Color(1, 0.55, 0.5))
	end_refs.sub.text = ("You conquered the world with %.1f%% of the land outside fallout." % pct) if win else ("Your nation fell after holding up to %.1f%% of the world." % stats.peak)
	end_refs.vals[0].text = "%.1f%%" % stats.peak
	end_refs.vals[1].text = _fmt(stats.maxtroops)
	end_refs.vals[2].text = str(stats.elims)
	end_refs.vals[3].text = _fmt_time(elapsed)
	end_refs.stars.text = "+" + _fmt_int(earned)
	var nl := next_locked()
	end_refs.prog_p.visible = not nl.is_empty()
	if not nl.is_empty():
		end_refs.prog.text = "%s   %s / %s" % [nl.name.to_upper(), _fmt_int(mini(save.stars, nl.cost)), _fmt_int(nl.cost)]
	if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
	for n in hud_nodes: n.visible = false
	notes.clear(); note_box.queue_redraw(); ally_card.visible = false
	if hud != null:
		hud.show_match()
		var lead_e := -1
		var bl_e := 0.0
		for id in range(1, nations.size()):
			if nations[id].alive and nations[id].land > bl_e: bl_e = nations[id].land; lead_e = id
		var eliminated: bool = not bool(nations[PLAYER].get("alive", true)) or nations[PLAYER].land <= 0
		hud.show_over(win, {"title": "VICTORY" if win else ("ELIMINATED" if eliminated else "DEFEAT"),
			"sub": end_refs.sub.text, "winner_id": PLAYER if win else lead_e,
			"peak": "%.1f%%" % stats.peak, "troops": _fmt(stats.maxtroops), "kills": str(stats.elims),
			"duration": _fmt_time(elapsed), "stars": "+" + _fmt_int(earned),
			"next": end_refs.prog.text if not nl.is_empty() else ""})
		return
	_pop_in(end_dlg, 0.25)
