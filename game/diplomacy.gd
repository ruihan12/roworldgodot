extends "res://game/planes_fx.gd"
# Alliances, embargoes and diplomacy

func _akey(a: int, b: int) -> int:
	return mini(a, b) * 4096 + maxi(a, b)

func allied(a: int, b: int) -> bool:
	return a > 0 and b > 0 and not allies.is_empty() and allies.has(_akey(a, b))

func is_traitor(id: int) -> bool:
	return int(traitor.get(id, -1)) > sim_atk.tick

# SimState.form_alliance: expires ALLIANCE_TICKS after it forms; both requests close; fighting
# between the new allies stops at once (SimAttacks._on_alliance_formed: end_attack, troops home)
func form_alliance(a: int, b: int) -> void:
	if allied(a, b): return
	var k := _akey(a, b)
	allies[k] = sim_atk.tick + SimRules.ALLIANCE_TICKS
	ally_ext[k] = 0
	ally_warned.erase(k)
	_close_request(a, b); _close_request(b, a)
	for at in attacks.duplicate():
		if (at.a == a and at.t == b) or (at.a == b and at.t == a): sim_atk.end_attack(at, true)
	if a == PLAYER or b == PLAYER: sfx("ally_accept")
	if a == PLAYER or b == PLAYER: notify("You are now allied with %s" % _nname(b if a == PLAYER else a), "good")

# SimState.end_alliance: broken by `traitor_id` (> 0), ended by an elimination (0) or `expired`
func end_alliance(a: int, b: int, traitor_id: int, expired := false) -> void:
	var k := _akey(a, b)
	if not allies.has(k): return
	allies.erase(k); ally_ext.erase(k); ally_warned.erase(k)
	if expired and (a == PLAYER or b == PLAYER):
		notify("Your alliance with %s has expired" % _nname(b if a == PLAYER else a), "info")
	if traitor_id > 0:
		var victim := b if traitor_id == a else a
		traitor[traitor_id] = sim_atk.tick + SimRules.TRAITOR_TICKS
		var gk := "grudge_" + str(traitor_id)
		nations[victim][gk] = maxi(int(nations[victim].get(gk, 0)), sim_atk.tick + SimRules.HOSTILE_TICKS * 3)
		if traitor_id == PLAYER or victim == PLAYER: sfx("ally_broken")
		if traitor_id == PLAYER: notify("You broke the alliance with %s — you are a traitor for 30 s" % _nname(victim), "bad")
		elif victim == PLAYER: notify("%s betrayed you! Attacks on them cost half for 30 s" % _nname(traitor_id), "bad")

func break_alliance(breaker: int, other: int) -> void:
	end_alliance(breaker, other, breaker)  # Sim.ally_break (traitor TRAITOR_TICKS = 30 s, victim grudge HOSTILE_TICKS x3)

# ---- alliance renewal (SimState.extend_alliance 1038-1080, Sim.ally_extend 1416, SimAI extensions 1096-1165)
func in_extension_window(a: int, b: int) -> bool:
	var k := _akey(a, b)
	return allies.has(k) and int(allies[k]) <= sim_atk.tick + SimRules.ALLIANCE_EXTEND_WINDOW_TICKS

func asked_to_extend(id: int, other: int) -> bool:
	return (int(ally_ext.get(_akey(id, other), 0)) & (1 if id < other else 2)) != 0

# "renewed" once both asked (expiry = now + ALLIANCE_TICKS), "asked" when only `id` has, "" refused
func extend_alliance(id: int, other: int) -> String:
	if id <= 0 or other <= 0 or id == other or not allied(id, other): return ""
	if not nations[id].alive or not nations[other].alive: return ""
	if not in_extension_window(id, other) or asked_to_extend(id, other): return ""
	var k := _akey(id, other)
	var bits: int = int(ally_ext.get(k, 0)) | (1 if id < other else 2)
	if bits == 3:
		ally_ext[k] = 0
		allies[k] = sim_atk.tick + SimRules.ALLIANCE_TICKS
		ally_warned.erase(k)
		if id == PLAYER or other == PLAYER: notify("Your alliance with %s was renewed" % _nname(other if id == PLAYER else id), "good")
		return "renewed"
	ally_ext[k] = bits
	if other == PLAYER: notify("%s wants to renew your alliance" % _nname(id), "info")
	return "asked"

# AIs never ask to renew; an AI ally answers the other side's ask (tribes always, on their next
# attack tick; nations as for a new request, retrying every attack-rate span until it expires)
func ally_extend(id: int, target: int) -> bool:
	if target <= 0 or target >= nations.size(): return false
	var r := extend_alliance(id, target)
	if r == "asked" and target != PLAYER:
		ally_extensions.append([sim_atk.tick + (1 if kind_of(target) == SimRules.KIND_TRIBE else rng.randi_range(20, 45)), id, target])
	return r != ""

func _ai_accept_extension(me: int, other: int) -> bool:
	if kind_of(me) == SimRules.KIND_TRIBE: return true
	if _grudge_of(me, other) or _great_powers(_land_share(me), _land_share(other)): return false
	return rng.randf() < _accept_p(me, other)

static func _great_powers(a_share: float, b_share: float) -> bool:
	return (a_share >= 0.12 and b_share >= 0.08) or (b_share >= 0.12 and a_share >= 0.08)

func _process_extensions() -> void:
	var t: int = sim_atk.tick
	var keep := []
	for r in ally_extensions:
		if int(r[0]) > t: keep.append(r); continue
		var from: int = r[1]; var to: int = r[2]
		if to == PLAYER or not nations[to].alive or not allied(from, to) or not asked_to_extend(from, to) or asked_to_extend(to, from): continue
		if kind_of(to) == SimRules.KIND_TRIBE and not sim_ai.tribe_answers(to):
			keep.append(r); continue
		if _ai_accept_extension(to, from):
			extend_alliance(to, from)
		else:
			var span: Array = EXTEND_RETRY[clampi(diff_i, 0, 2)]
			r[0] = t + rng.randi_range(span[0], span[1])
			keep.append(r)
	ally_extensions = keep

func has_request(a: int, b: int) -> bool: return ally_requests.has(a * 1024 + b)
func _close_request(a: int, b: int) -> void:
	var k := a * 1024 + b
	if ally_requests.has(k):
		ally_req_last[k] = ally_requests[k]; ally_requests.erase(k)
func request_cooldown_left(a: int, b: int) -> int:
	var k := a * 1024 + b
	if not ally_req_last.has(k): return 0
	return maxi(0, int(ally_req_last[k]) + SimRules.ALLY_REQUEST_COOLDOWN_TICKS - sim_atk.tick)

func propose_alliance(a: int, b: int) -> bool:
	if b <= 0 or b >= nations.size() or a == b or not nations[b].alive: return false
	if allied(a, b) or has_request(a, b): return false
	if has_request(b, a):  # asking back accepts
		_close_request(b, a); form_alliance(b, a); return true
	var wait := request_cooldown_left(a, b)
	if wait > 0:
		if a == PLAYER: notify("You can ask %s again in %d s" % [_nname(b), ceili(wait / 10.0)], "info")
		return false
	ally_requests[a * 1024 + b] = sim_atk.tick
	if b == PLAYER:
		sfx("ally_suggest"); _show_ally_card("propose", a)
	else:
		var due: int = sim_atk.tick + (1 if kind_of(b) == SimRules.KIND_TRIBE else rng.randi_range(20, 45))
		ally_replies.append([due, a, b])
		if a == PLAYER: notify("Alliance request sent to %s" % _nname(b), "info")
	return true

# Sim.ally_reply: `id` answers `target`'s request
func ally_reply(id: int, target: int, accept: bool) -> bool:
	if not has_request(target, id): return false
	_close_request(target, id)
	if accept and nations[target].alive:
		form_alliance(target, id)
	elif target == PLAYER:
		sfx("ally_decline"); notify("%s declined your alliance" % _nname(id), "info")
	return true

func _ally_count(id: int) -> int:
	var c := 0
	for key in allies: if key / 4096 == id or key % 4096 == id: c += 1
	return c

func _land_share(id: int) -> float:
	return float(nations[id].land) / maxf(1.0, float(land_total - fallout_count))

func _grudge_of(me: int, other: int) -> bool:
	return int(nations[me].get("grudge_" + str(other), -1)) > sim_atk.tick

func _shared_enemy(a: int, b: int) -> bool:
	for id in range(1, nations.size()):
		if id != a and id != b and _grudge_of(a, id) and _grudge_of(b, id): return true
	return false

# SimAI._accept (SimAI.luau 1051)
func _ai_accept(me: int, other: int) -> bool:
	if _ally_count(me) >= AI_MAX_ALLIES or _grudge_of(me, other): return false
	var sa := _land_share(me); var sb := _land_share(other)
	if (sa >= 0.12 and sb >= 0.08) or (sb >= 0.12 and sa >= 0.08): return false
	for at in attacks:
		if (at.a == me and at.t == other) or (at.a == other and at.t == me): return false
	return rng.randf() < _accept_p(me, other)

func _accept_p(me: int, other: int) -> float:
	var p := 0.3
	var ratio := (float(nations[other].land) + 1.0) / (float(nations[me].land) + 1.0)
	if ratio > 1.5: p += 0.35
	elif ratio > 0.7: p += 0.2
	if other == PLAYER: p += 0.15
	if _shared_enemy(me, other): p += 0.2
	if is_traitor(other): p = 0.08
	p += AI_ACCEPT_BIAS[clampi(diff_i, 0, 2)]
	return p

# per sim tick: AI replies due, and requests unanswered for ALLY_REQUEST_TICKS expire (SimState._alliances_tick)
func _requests_tick() -> void:
	var t: int = sim_atk.tick
	if not ally_replies.is_empty():
		var keep := []
		for r in ally_replies:
			if int(r[0]) > t: keep.append(r); continue
			var from: int = r[1]; var to: int = r[2]
			if not has_request(from, to) or not nations[to].alive or to == PLAYER: continue
			if kind_of(to) == SimRules.KIND_TRIBE:
				# a tribe accepts every request, on its next attack tick (SimAI._tribe_answers)
				if sim_ai.tribe_answers(to): ally_reply(to, from, true)
				else: keep.append(r)
				continue
			ally_reply(to, from, _ai_accept(to, from))
		ally_replies = keep
	if not ally_extensions.is_empty(): _process_extensions()
	# alliance expiry (SimState._alliances_tick) and eliminations
	if not allies.is_empty():
		for key in allies.keys():
			var a: int = key / 4096; var b: int = key % 4096
			if not nations[a].alive or not nations[b].alive:
				end_alliance(a, b, 0)
			elif int(allies[key]) <= t:
				end_alliance(a, b, 0, true)
	if not ally_requests.is_empty():
		var limit := t - SimRules.ALLY_REQUEST_TICKS
		for k in ally_requests.keys():
			if int(ally_requests[k]) < limit:
				var from: int = k / 1024; var to: int = k % 1024
				_close_request(from, to)
				if from == PLAYER: notify("%s did not answer your alliance request" % _nname(to), "info")
				if to == PLAYER and ally_card != null and ally_card_mode == "propose" and ally_card_who == from and ally_card.visible: _fade_out(ally_card)

func is_embargoed(_a: int, _b: int) -> bool:
	return false

func donate(a: int, b: int, frac := 0.3333) -> void:
	if a == PLAYER and donate_troop_cd > 0.0:
		notify("Troop donation on cooldown (%ds)" % ceili(donate_troop_cd), "info")
		return
	var amt: float = floor(nations[a].troops * frac)
	if amt < 100: return
	nations[a].troops -= amt
	nations[b].troops = minf(troop_cap(b) * 1.25, nations[b].troops + amt)
	if a == PLAYER:
		donate_troop_cd = 10.0
		notify("Donated %s troops to %s" % [_fmt(amt), _nname(b)], "good")

func donate_gold(a: int, b: int, frac := 0.25) -> void:
	if a == PLAYER and donate_gold_cd > 0.0:
		notify("Gold donation on cooldown (%ds)" % ceili(donate_gold_cd), "info")
		return
	var amt: float = floor(nations[a].gold * frac)
	if amt < 1000: return
	nations[a].gold -= amt
	nations[b].gold += amt
	if a == PLAYER:
		donate_gold_cd = 10.0
		notify("Donated %s gold to %s" % [_fmt(amt), _nname(b)], "good")

# The player's renewal card: once per window (the last ALLIANCE_EXTEND_WINDOW_TICKS). Expiry, renewals
# and AI diplomacy run per sim tick (_requests_tick, SimAI._consider_diplomacy).
func _tick_alliances() -> void:
	for key in allies.keys():
		var a: int = key / 4096; var b: int = key % 4096
		if a != PLAYER and b != PLAYER: continue
		var other := b if a == PLAYER else a
		if in_extension_window(a, b) and not ally_warned.has(key) and not asked_to_extend(PLAYER, other):
			ally_warned[key] = true
			_show_ally_card("expire", other)

func _build_ally_card() -> void:
	# EventFeed alliance card (violet glass, Primary Accept/Renew + Glass Ignore, expiry bar)
	hud.build_ally_card()
	ally_card_btn_a.pressed.connect(func():
		if ally_card_mode == "expire" and allied(PLAYER, ally_card_who):
			var r := extend_alliance(PLAYER, ally_card_who)
			if r == "asked":
				ally_extensions.append([sim_atk.tick + (1 if kind_of(ally_card_who) == SimRules.KIND_TRIBE else rng.randi_range(20, 45)), PLAYER, ally_card_who])
				notify("Asked %s to renew the alliance" % _nname(ally_card_who), "info")
			elif r == "": notify("The alliance can't be renewed now", "info")
		elif ally_card_mode == "propose":
			if not ally_reply(PLAYER, ally_card_who, true): notify("That alliance request has expired", "info")
		_fade_out(ally_card))
	ally_card_btn_b.pressed.connect(func(): _fade_out(ally_card))
	ally_card.visible = false

func _show_ally_card(mode: String, who: int) -> void:
	ally_card_mode = mode; ally_card_who = who
	RK.set_swatch(ally_card_sq as Panel, nations[who].color)
	ally_card_lbl.text = nations[who].name
	if mode == "expire":
		ally_card_sub.text = "Your alliance is about to expire"
		ally_card_btn_a.text = "RENEW"
		ally_card_btn_b.text = "Ignore"
	else:
		ally_card_sub.text = "Proposes an alliance with you"
		ally_card_btn_a.text = "ACCEPT"
		ally_card_btn_b.text = "Decline"
	ally_card.set_meta("t0", elapsed)
	hud.set_ally_bar(1.0)
	ally_card.get_parent().move_child(ally_card, -1)
	RK.pop_in(ally_card, 0.0, 0.96, 0.3)

func _tick_ally_card() -> void:
	if ally_card == null or not ally_card.visible: return
	var v := 1.0
	if ally_card_mode == "expire":
		v = clampf(float(int(allies.get(_akey(PLAYER, ally_card_who), sim_atk.tick)) - sim_atk.tick) / float(SimRules.ALLIANCE_EXTEND_WINDOW_TICKS), 0, 1)
		if v <= 0: _fade_out(ally_card)
	else:
		v = clampf(1.0 - (elapsed - float(ally_card.get_meta("t0", elapsed))) / 20.0, 0, 1)
		if v <= 0: _fade_out(ally_card)
	hud.set_ally_bar(v)

func _build_diplo_menu() -> void:
	diplo_panel = _P(ui, Rect2(620, 260, 320, 192), Color(0.07, 0.085, 0.16, 0.98), 8, Color(1, 1, 1, 0.14), 1)
	diplo_refs.sq = _draw_ctl(diplo_panel, Rect2(16, 16, 16, 16), func(c: Control):
		c.draw_rect(Rect2(0, 0, 16, 16), c.get_meta("col", Color.GRAY))
		c.draw_rect(Rect2(0, 0, 16, 16), Color(1, 1, 1, 0.7), false, 1.0))
	diplo_refs.title = _T(diplo_panel, "", Vector2(40, 11), 18, TEXT, f_bold, 220)
	diplo_refs.sub = _T(diplo_panel, "", Vector2(16, 36), 13, MUTED, f_reg, 280)
	var x := _card_btn(diplo_panel, Rect2(276, 10, 32, 30)); x.text = "✕"
	x.pressed.connect(func(): diplo_panel.visible = false)
	diplo_refs.b_ally = _big_btn(diplo_panel, Rect2(16, 64, 288, 36), "PROPOSE ALLIANCE", ORANGE_Y, 14)
	diplo_refs.b_ally.pressed.connect(func():
		if diplo_who <= 1: return
		if allied(PLAYER, diplo_who): break_alliance(PLAYER, diplo_who)
		else: propose_alliance(PLAYER, diplo_who)
		_refresh_diplo())
	diplo_refs.b_troops = _card_btn(diplo_panel, Rect2(16, 108, 140, 36))
	diplo_refs.b_troops.add_theme_font_override("font", f_bold); diplo_refs.b_troops.add_theme_font_size_override("font_size", 13)
	diplo_refs.b_troops.pressed.connect(func():
		if diplo_who > 1: donate(PLAYER, diplo_who, 0.3333); _refresh_diplo())
	diplo_refs.b_gold = _card_btn(diplo_panel, Rect2(164, 108, 140, 36))
	diplo_refs.b_gold.add_theme_font_override("font", f_bold); diplo_refs.b_gold.add_theme_font_size_override("font_size", 13)
	diplo_refs.b_gold.pressed.connect(func():
		if diplo_who > 1: donate_gold(PLAYER, diplo_who, 0.25); _refresh_diplo())
	diplo_refs.foot = _T(diplo_panel, "", Vector2(16, 154), 12, MUTED, f_reg, 288, HORIZONTAL_ALIGNMENT_CENTER)
	# upstream glass card + Primary / Glass / Ghost buttons (UI kit)
	diplo_panel.add_theme_stylebox_override("panel", RK.glass_style(RK.GLASS, RK.R_LG, RK.LINE, 18, Vector4(0, 0, 0, 0)))
	_rw_restyle(diplo_refs.b_ally, "PrimaryButton", 14)
	_rw_restyle(diplo_refs.b_troops, "GlassButton", 11)
	_rw_restyle(diplo_refs.b_gold, "GlassButton", 11)
	_rw_restyle(x, "GhostButton", 15)
	diplo_refs.title.add_theme_font_override("font", RK.font(700)); diplo_refs.title.add_theme_font_size_override("font_size", 17)
	diplo_refs.sub.add_theme_color_override("font_color", RK.TEXT_2); diplo_refs.sub.add_theme_font_size_override("font_size", 12)
	diplo_refs.foot.add_theme_color_override("font_color", RK.TEXT_3)
	diplo_refs.foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diplo_refs.foot.add_theme_font_size_override("font_size", 11)
	for b in [diplo_refs.b_ally, diplo_refs.b_troops, diplo_refs.b_gold, x]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb: StyleBox = b.get_theme_stylebox(st).duplicate()
			sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 2; sb.content_margin_bottom = 2
			b.add_theme_stylebox_override(st, sb)
		b.clip_text = true
	diplo_panel.visible = false

# copy an upstream button variant's styles onto an existing port button (keeps its handlers / layout)
func _rw_restyle(b: Button, variant: String, fs := 0) -> void:
	var tmp: Button = RK.button("", variant)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if tmp.has_theme_stylebox_override(st): b.add_theme_stylebox_override(st, tmp.get_theme_stylebox(st))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		if tmp.has_theme_color_override(k): b.add_theme_color_override(k, tmp.get_theme_color(k))
	if tmp.has_theme_font_override("font"): b.add_theme_font_override("font", tmp.get_theme_font("font"))
	if fs > 0: b.add_theme_font_size_override("font_size", fs)
	tmp.free()

func _open_diplo(who: int, screen_pos: Vector2) -> void:
	diplo_who = who
	var pos := screen_pos + Vector2(14, -40)
	pos.x = clampf(pos.x, 20, 1600 - 340)
	pos.y = clampf(pos.y, 60, 900 - 210)
	diplo_panel.position = pos
	_refresh_diplo()
	_pop_in(diplo_panel, 0.14)

func _refresh_diplo() -> void:
	if diplo_panel == null or diplo_who <= 1 or diplo_who >= nations.size(): return
	var n = nations[diplo_who]
	diplo_refs.sq.set_meta("col", n.color); diplo_refs.sq.queue_redraw()
	diplo_refs.title.text = n.name + (" [TRAITOR]" if is_traitor(diplo_who) else "")
	var status := "ALLY" if allied(PLAYER, diplo_who) else ("Player" if is_bot(diplo_who) else ("Nation" if is_prot(diplo_who) else "Tribe"))
	diplo_refs.sub.text = "%s  ·  Troops: %s  ·  Land: %s" % [status, _fmt(n.troops), _pct(100.0 * n.land / maxf(1, land_total))]
	if allied(PLAYER, diplo_who):
		var left: float = allies.get(_akey(PLAYER, diplo_who), elapsed) - elapsed
		diplo_refs.b_ally.text = "BREAK ALLIANCE (%s)" % _fmt_time(maxf(0.0, left))
	else:
		diplo_refs.b_ally.text = "PROPOSE ALLIANCE (5:00)"
	diplo_refs.b_troops.text = ("Troops CD %ds" % ceili(donate_troop_cd)) if donate_troop_cd > 0 else "DONATE 1/3 TROOPS"
	diplo_refs.b_gold.text = ("Gold CD %ds" % ceili(donate_gold_cd)) if donate_gold_cd > 0 else "DONATE 25% GOLD"
	diplo_refs.foot.text = "Breaking an alliance marks you [TRAITOR] (0.5x def, 30s)"

func _right_click() -> void:
	var t := _mouse_tile()
	if t < 0: return
	var o: int = owner_map[t]
	if o <= 1:
		if diplo_panel: diplo_panel.visible = false
		return
	if Input.is_key_pressed(KEY_SHIFT) and allied(PLAYER, o):
		break_alliance(PLAYER, o)
		return
	_open_diplo(o, get_viewport().get_mouse_position())
