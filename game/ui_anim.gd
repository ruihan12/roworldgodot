extends "res://game/diplomacy.gd"
# UI animation helpers

# ---------------- UI animation ----------------
func _animate_ui(dt: float) -> void:
	_update_console_fps(dt)
	if state == "play" and nations.size() > 1:
		var pl = nations[PLAYER]
		var k := 1.0 - exp(-10.0 * dt)
		shown_troops = lerpf(shown_troops, pl.troops, k)
		shown_gold = lerpf(shown_gold, pl.gold, k)
		bb_troops.text = _fmt(shown_troops)
		bb_gold.text = _fmt(shown_gold)
		bb_cap.position.x = bb_troops.position.x + f_bold.get_string_size(bb_troops.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 6
	# tooltip fade-in
	if tipc.visible and not tip_was_visible:
		tipc.modulate.a = 0.0
		create_tween().tween_property(tipc, "modulate:a", 1.0, 0.12)
	tip_was_visible = tipc.visible
	# deploy ring pulse
	if pick_ring.visible:
		var ph := fmod(deploy_t, 1.0)
		var sc := 1.0 + 0.08 * pow(ph, 3.0)
		pick_ring.pivot_offset = pick_ring.size / 2
		pick_ring.scale = Vector2(sc, sc)

func _fade_in(n: CanvasItem, offset := Vector2(0, 10), dur := 0.2) -> void:
	n.visible = true
	n.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, dur)
	if n is Control and offset != Vector2.ZERO:
		var c := n as Control
		var base: Vector2 = c.get_meta("base_pos", c.position)
		c.set_meta("base_pos", base)
		c.position = base + offset
		tw.tween_property(c, "position", base, dur)

func _fade_out(n: CanvasItem, dur := 0.15) -> void:
	if n.has_meta("fade_tw"):
		var old: Tween = n.get_meta("fade_tw")
		if old and old.is_valid(): old.kill()
	var tw := create_tween()
	n.set_meta("fade_tw", tw)
	tw.tween_property(n, "modulate:a", 0.0, dur)
	tw.tween_callback(func(): n.visible = false; n.modulate.a = 1.0)

func _pop_in(c: Control, dur := 0.2) -> void:
	if c.has_meta("fade_tw"):
		var old: Tween = c.get_meta("fade_tw")
		if old and old.is_valid(): old.kill()
	c.visible = true
	c.pivot_offset = c.size / 2 if c.size != Vector2.ZERO else Vector2(800, 450)
	c.modulate.a = 0.0; c.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	tw.tween_property(c, "scale", Vector2.ONE, dur)

func _wire_anims(n: Node) -> void:
	for ch in n.get_children():
		if ch is Button and ch.has_meta("rw"):
			pass
		elif ch is Button:
			var b := ch as Button
			var lift: bool = b in build_btns
			b.mouse_entered.connect(func(): _btn_anim(b, "hover", lift))
			b.mouse_exited.connect(func(): _btn_anim(b, "idle", lift))
			b.button_down.connect(func(): _btn_anim(b, "down", lift); sfx("click", 0.0, 0.02))
			b.button_up.connect(func(): _btn_anim(b, "hover", lift))
		_wire_anims(ch)

func _btn_anim(b: Button, mode: String, lift: bool) -> void:
	if b.has_meta("tw"):
		var old: Tween = b.get_meta("tw")
		if old and old.is_valid(): old.kill()
	b.pivot_offset = b.size / 2
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b.set_meta("tw", tw)
	var sc: float = {"idle": 1.0, "hover": 1.04, "down": 0.95}[mode]
	var br: float = {"idle": 1.0, "hover": 1.15, "down": 0.92}[mode]
	tw.tween_property(b, "modulate", Color(br, br, br, 1), 0.12)
	if lift:
		var base: float = b.get_meta("base_y", b.position.y)
		b.set_meta("base_y", base)
		tw.tween_property(b, "position:y", base - (4.0 if mode == "hover" else (1.0 if mode == "down" else 0.0)), 0.12)
	else:
		tw.tween_property(b, "scale", Vector2(sc, sc), 0.12)

func _set_share(i: int) -> void:
	share_i = clampi(i, 0, SHARES.size() - 1)
	if hud: hud.on_share_changed()
	for k in share_btns.size():
		_pill(share_btns[k], false)
		share_btns[k].add_theme_color_override("font_color", Color(0.1, 0.08, 0.05) if k == share_i else Color(0.82, 0.86, 0.95))
	if share_hl:
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(share_hl, "position:x", 3.0 + share_i * 40, 0.16)

func _game_over(win: bool) -> void:
	if audio_dir != null: audio_dir.end_match()
	state = "over"
	build_sel = -1
	_stop_music()
	sfx("victory" if win else "defeat")
	show_end(win)
	return
	over_panel_holder.visible = true
	over_label.text = ("VICTORY" if win else "DEFEAT")
	over_label.add_theme_color_override("font_color", ORANGE_Y if win else RED)
	over_panel_p.get_node("sub").text = ("You hold 80% of the world." if win else "Your nation has fallen.") + "\nTime played: %s" % _fmt_time(elapsed)

func _to_menu() -> void:
	if audio_dir != null: audio_dir.end_match()
	state = "menu"
	_stop_music()
	if bool(save.get("settings", {}).get("music_on", true)): _play_music()
	menu_panel.visible = true
	play_dialog.visible = false
	over_panel_holder.visible = false
	if end_dlg: end_dlg.visible = false
	if note_box: notes.clear(); note_box.queue_redraw()
	if ally_card: ally_card.visible = false
	pick_panel.visible = false
	for n in hud_nodes:
		n.visible = false
	if hud: hud.show_match()
