# In-match HUD rebuilt from the upstream RoWorld client (2026-11-10, "make the in game UI 99% like the one
# in Roblox"). One node per upstream module, same container trees, sizes, colours, fonts and tweens:
#   top-bar buttons  Main.luau (build_hud / layout_hud)          status pill   UI/TopStatus.luau
#   spawn banner     UI/SpawnOverlay.luau                       leaderboard   UI/Leaderboard.luau (+ rank pill)
#   attacks          UI/AttacksPanel.luau                       command bar   UI/CommandBar.luau, BuildButton,
#   event feed       UI/EventFeed.luau (toasts, alliance cards)               RatioSlider, ShopSlot, FillBar
#   nuke alert       UI/AlertBanner.luau                        game menu     UI/PauseMenu.luau
#   game over        UI/GameOver.luau
# Port-only controls drawn in the same style: game-speed chip (0.5x-10x), ICBM slot (key I), nuke ranges.
# Placement follows UIRoot._layout (UIRoot.luau:2190-2300) on the 1600x900 logical canvas.
extends Node

const RK := preload("res://ui_upstream/rw_kit.gd")

var m  # main.gd
var root: Control

# top bar
var topbar: HBoxContainer
var tb_buttons := {}
var tb_tip: PanelContainer
var tb_tip_l: Label
# status pill
var top: PanelContainer
var st_phase: Label
var st_grace_row: HBoxContainer
var st_grace: Label
var st_clock: Label
var st_limit: Label
var st_bar: Control
var st_you_sw: Panel
var st_you: Label
var st_lead_box: HBoxContainer
var st_lead_sw: Panel
var st_lead: Label
# spawn banner
var spawn: PanelContainer
var sp_title: Label
var sp_sub: Label
var sp_ring: Control
# leaderboard
var board: PanelContainer
var board_pill: Button
var board_rows := []
var board_count: Label
var board_pin_sep: Label
var board_pin: Array
var board_open := false
# attacks
var atk: PanelContainer
var atk_count: Label
var atk_list: VBoxContainer
var atk_rows := []
var atk_more: Label
# command bar
var bar: PanelContainer
var bar_root: Control
var cb_swatch: Panel
var cb_name: Label
var cb_crown: TextureRect
var cb_land: Label
var cb_growth: Label
var cb_troops: Label
var cb_cap: Label
var cb_troops_bar: Control
var cb_committed: Label
var cb_ratio_pct: Label
var cb_slider: Control
var cb_ratio_sub: Label
var cb_gold: Label
var cb_income: Label
var cb_nation: Control
var cb_troops_box: Control
var cb_ratio_box: Control
var cb_gold_box: Control
var cb_builds: HBoxContainer
var cb_nuke_wrap: MarginContainer
var cb_shop_wrap: MarginContainer
var slots := {}  # kind -> Button
var shop_btn: Button
var _flow := -1
var _arsenal_sig := "?"
var slider_hover := -1
var slider_shown := 1.0
var slider_drag := false
# speed chip (port control)
var speed: PanelContainer
# alert
var alert: PanelContainer
var al_title: Label
var al_detail: Label
var al_disc: Panel
var al_icon: TextureRect
var _al_t := 0.0
# feed
var feed: VBoxContainer
var _recent := {}
# game menu
var menu: Control
var menu_panel: PanelContainer
# game over
var over: Control
var ov_kicker: Label
var ov_title: Label
var ov_sub: Label
var ov_winner: PanelContainer
var ov_winner_sw: Panel
var ov_winner_name: Label
var ov_crown: TextureRect
var ov_stats: HBoxContainer
var ov_stars: Button
var ov_next: Label
var ov_grad := [Color.WHITE, RK.GOLD]
var _slices := []
var _shop_t := 0.0
var _last_ws := Vector2i.ZERO
var groups := []
var _dirty := true
var _in_layout := false
var _clock_s := -1

# =============================================================================================
func build(main) -> void:
	m = main
	root = Control.new()
	root.name = "RwHud"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.ui.add_child(root)
	_build_top()
	_build_speed()
	_build_board()
	_build_attacks()
	_build_bar()
	_build_feed()
	_build_alert()
	_build_spawn()
	_build_topbar()
	# hud_nodes groups (main.gd shows / hides / fades these as a unit; inner visibility stays ours)
	groups = []
	for grp in [[top], [speed], [board, board_pill], [atk], [bar]]:
		var g := Control.new()
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(g)
		for n in grp: n.reparent(g, false)
		groups.append(g)
	root.move_child(feed, -1)
	root.move_child(alert, -1)
	root.move_child(spawn, -1)
	root.move_child(topbar, -1)
	root.move_child(tb_tip, -1)
	for c in [top, spawn, board, board_pill, atk, bar, feed, alert, speed]:
		c.resized.connect(_mark_dirty)
		c.visibility_changed.connect(_mark_dirty)
	feed.sort_children.connect(_mark_dirty)
	layout()

# click sound only on real presses (main.gd _wire_anims rule); no scale animation: upstream buttons only
# restyle on hover / press
func wire(b: BaseButton) -> void:
	b.set_meta("rw", true)
	b.button_down.connect(func(): m.sfx("click", 0.0, 0.02))

# =============================================================================================
# Top-bar buttons (Main.luau:31-42, 340-397): 44 px dark circles, 36 px icon frames, 8 px apart,
# 12 px below the top. Device px, not scaled with the HUD.
func _build_topbar() -> void:
	topbar = HBoxContainer.new()
	topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(topbar)
	var defs := [
		["music", "hud_music_on", "Music (M)"],
		["help", "hud_help", "Help & Credits (H)"],
		["leaderboard", "hud_leaderboard", "Leaderboard"],
		["home", "hud_globe", "Center on your nation (Home)"],
		["settings", "hud_settings", "Settings"],
		["menu", "hud_exit", "Game menu"]]
	for d in defs:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var key: String = d[0]
		var tip: String = d[2]
		b.set_meta("icon", d[1])
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.draw.connect(func(): _draw_topbar_btn(b))
		b.mouse_entered.connect(func(): _topbar_tip(b, tip))
		b.mouse_exited.connect(func(): tb_tip.visible = false; b.queue_redraw())
		b.button_down.connect(func(): b.queue_redraw())
		b.button_up.connect(func(): b.queue_redraw())
		b.pressed.connect(func(): _topbar_pressed(key))
		wire(b)
		topbar.add_child(b)
		tb_buttons[key] = b
	tb_tip = PanelContainer.new()
	tb_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb_tip_l = RK.label("", 14, 500, Color.WHITE)
	tb_tip.add_child(tb_tip_l)
	tb_tip.visible = false
	root.add_child(tb_tip)

func _device_scale() -> float:
	var ws := Vector2(1600, 900)
	if m.get_window(): ws = Vector2(m.get_window().size)
	return clampf(minf(ws.x / 1600.0, ws.y / 900.0), 0.5, 4.0)

func _draw_topbar_btn(b: Button) -> void:
	var s := b.size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5
	b.draw_circle(c, r, RK.TOPBAR_FILL)
	var ov := 0.0
	if b.button_pressed or (b.is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)): ov = 0.16
	elif b.is_hovered(): ov = 0.08
	if ov > 0: b.draw_circle(c, r, Color(1, 1, 1, ov))
	var t := RK.icon_tex(b.get_meta("icon"))
	if t:
		var ip := s.x * 36.0 / 44.0
		b.draw_texture_rect(t, Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), false, Color.WHITE)

func _topbar_tip(b: Button, text: String) -> void:
	b.queue_redraw()
	tb_tip_l.text = text
	var k := 1.0 / _device_scale()
	tb_tip_l.add_theme_font_size_override("font_size", maxi(8, int(round(14 * k))))
	tb_tip.add_theme_stylebox_override("panel", RK.flat(Color8(18, 18, 21, 230), int(8 * k), RK.CLEAR, 0, 10 * k, 6 * k))
	tb_tip.reset_size()
	tb_tip.position = Vector2(b.global_position.x + b.size.x * 0.5 - tb_tip.size.x * 0.5, b.global_position.y + b.size.y + 8 * k)
	tb_tip.position.x = maxf(4, tb_tip.position.x)
	tb_tip.visible = true

func _topbar_pressed(key: String) -> void:
	match key:
		"music": m.hud_toggle_music()
		"help": m.help_panel.visible = not m.help_panel.visible
		"leaderboard": set_board_open(not board_open)
		"home": m._focus_player_smooth(m.cam.zoom.x)
		"settings": m._open_settings()
		"menu": open_menu()
	refresh_topbar()

func refresh_topbar() -> void:
	var in_match: bool = m.state == "play" or m.state == "pick"
	for k in ["leaderboard", "home", "menu"]:
		tb_buttons[k].visible = in_match
	var on: bool = m.music_on_setting()
	tb_buttons["music"].set_meta("icon", "hud_music_on" if on else "hud_music_off")
	tb_buttons["music"].queue_redraw()

# =============================================================================================
# TopStatus.luau: glass(18, 10, R_LG, 18), top-centre at 12; [phase/clock | world control bar].
func _build_top() -> void:
	top = RK.glass(18, 10, RK.R_LG, 18)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := RK.hbox(16)
	top.add_child(row)
	var tb := RK.vbox(0)
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st_grace_row = RK.hbox(4)
	st_grace_row.add_child(RK.icon_rect("defense", 11, RK.GREEN))
	st_grace = RK.label("PROTECTED", 11, 700, RK.GREEN, 1)
	st_grace_row.add_child(st_grace)
	tb.add_child(st_grace_row)
	st_phase = RK.caption("Match time")
	tb.add_child(st_phase)
	var tv := RK.hbox(4)
	st_clock = RK.label("0:00", 20, 700)
	tv.add_child(st_clock)
	st_limit = RK.label("", 12, 600, RK.TEXT_3)
	st_limit.size_flags_vertical = Control.SIZE_SHRINK_END
	tv.add_child(st_limit)
	tb.add_child(tv)
	var w_block := maxf(RK.text_width("SPAWN PHASE", 11, 700, 1) + 12.0, RK.text_width("PROTECTED 8:88", 11, 700, 1) + 20.0)
	RK.fix_width(st_phase, w_block)
	var w_clock := RK.text_width("8:88:88", 20, 700) + 2.0
	RK.fix_width(st_clock, w_clock)
	RK.fix_width(st_limit, maxf(w_block - w_clock - 4.0, RK.text_width("/ 88:88", 12, 600) + 2.0))
	tb.custom_minimum_size = Vector2(maxf(88, w_block), 0)
	st_grace_row.custom_minimum_size = Vector2(w_block, st_phase.get_combined_minimum_size().y)
	row.add_child(tb)
	row.add_child(RK.vdivider(38))
	var sb := RK.vbox(5)
	sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head := RK.hbox(6)
	head.add_child(RK.icon_rect("globe", 12, RK.TEXT_3))
	head.add_child(RK.caption("World control"))
	head.add_child(RK.spacer())
	head.add_child(RK.caption("Goal 80%", 11, RK.GOLD))
	sb.add_child(head)
	st_bar = RK.fill_bar(7.0, RK.AMBER)
	st_bar.set_meta("goal", 0.8)
	st_bar.custom_minimum_size = Vector2(340, 12)
	sb.add_child(st_bar)
	var who := RK.hbox(6)
	st_you_sw = RK.swatch(RK.AMBER, 9, 2)
	who.add_child(st_you_sw)
	st_you = RK.label("You 0.0%", 12, 600)
	var w_you := RK.text_width("You lead · 88.88%", 12, 600) + 2.0
	RK.fix_width(st_you, w_you)
	who.add_child(st_you)
	who.add_child(RK.spacer())
	st_lead_box = RK.hbox(6)
	st_lead_box.add_child(RK.icon_rect("crown", 12, RK.GOLD))
	st_lead_sw = RK.swatch(RK.TEXT, 9, 2)
	st_lead_box.add_child(st_lead_sw)
	st_lead = RK.label("", 12, 600, RK.TEXT_2)
	RK.fix_width(st_lead, maxf(40.0, 340.0 - w_you - 12.0 - 9.0 - 12.0 - 18.0))
	st_lead_box.add_child(st_lead)
	who.add_child(st_lead_box)
	sb.add_child(who)
	row.add_child(sb)

func refresh_top() -> void:
	var pl = m.nations[m.PLAYER]
	var left: float = m.peace - m.elapsed
	if m.state == "pick":
		st_grace_row.visible = false; st_phase.visible = true
		st_phase.text = "SPAWN PHASE"
		st_clock.text = "--:--"
		RK.set_color(st_clock, RK.TEXT)
	elif left > 0 and m.state == "play":
		st_grace_row.visible = true; st_phase.visible = false
		st_clock.text = RK.fmt_time(ceilf(left))
		RK.set_color(st_clock, RK.GREEN)
	else:
		st_grace_row.visible = false; st_phase.visible = true
		st_phase.text = "MATCH TIME" if m.state != "over" else "MATCH OVER"
		st_clock.text = RK.fmt_time(m.elapsed)
		RK.set_color(st_clock, RK.TEXT)
	st_limit.text = ""
	var lt: float = maxf(1.0, m.land_total)
	var my_share: float = pl.land / lt
	var mcol := RK.owner_ui_color(pl.color)
	RK.set_swatch(st_you_sw, mcol)
	st_you.text = "You " + RK.fmt_pct(my_share)
	st_bar.set_meta("col", mcol)
	RK.fill_set(st_bar, clampf(my_share, 0.0, 1.0))
	var lead_id := _leader()
	var markers := []
	if lead_id > 0:
		var n = m.nations[lead_id]
		var ls: float = n.land / lt
		st_lead_box.visible = lead_id != m.PLAYER
		RK.set_swatch(st_lead_sw, n.color)
		st_lead.text = "%s %s" % [n.name, RK.fmt_pct(ls)]
		if lead_id != m.PLAYER:
			markers.append({"v": ls, "color": RK.owner_ui_color(n.color)})
		else:
			st_you.text = "You lead · " + RK.fmt_pct(my_share)
	else:
		st_lead_box.visible = false
	st_bar.set_meta("markers", markers)
	st_bar.queue_redraw()

func _leader() -> int:
	var best := -1
	var bl := 0.0
	for id in range(1, m.nations.size()):
		var n = m.nations[id]
		if n.alive and n.land > bl:
			bl = n.land; best = id
	return best

# =============================================================================================
# Port control in the upstream style: game speed 0.5x..10x (a RatioSlider-like track with an amber fill).
func _build_speed() -> void:
	speed = RK.glass(12, 9, RK.R_LG, 16)
	root.add_child(speed)
	var v := RK.vbox(5)
	speed.add_child(v)
	var head := RK.hbox(6)
	head.add_child(RK.icon_rect("clock", 12, RK.TEXT_3))
	var title := RK.caption("Game speed")
	head.add_child(title)
	head.add_child(RK.spacer())
	var val := RK.label("1x", 13, 800, RK.AMBER)
	RK.fix_width(val, RK.text_width("10.5x", 13, 800) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(val)
	var hint := RK.label("− / +", 11, 600, RK.TEXT_3)
	head.add_child(hint)
	v.add_child(head)
	var sl := HSlider.new()
	sl.min_value = 0.5; sl.max_value = 10.0; sl.step = 0.5; sl.value = 1.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(196, 16)
	var trk := RK.flat(Color(1, 1, 1, 0.07), 5, Color(1, 1, 1, 0.12), 1)
	trk.content_margin_top = 3; trk.content_margin_bottom = 3
	var fill := RK.flat(RK.c(RK.AMBER, 0.85), 5)
	fill.content_margin_top = 3; fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", trk)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var gimg := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			var a := clampf(7.5 - d, 0.0, 1.0)
			var col := Color.WHITE if d < 5.5 else RK.AMBER_LO
			gimg.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var gt := ImageTexture.create_from_image(gimg)
	sl.add_theme_icon_override("grabber", gt)
	sl.add_theme_icon_override("grabber_highlight", gt)
	sl.value_changed.connect(func(x: float): m.set_speed_x(x))
	v.add_child(sl)
	var ticks := Control.new()
	ticks.custom_minimum_size = Vector2(196, 4)
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticks.draw.connect(func():
		for sp in [0.5, 1.0, 2.0, 5.0, 10.0]:
			var x: float = 8.0 + (sp - 0.5) / 9.5 * (ticks.size.x - 16.0)
			ticks.draw_rect(Rect2(x - 1, 0, 2, 4), Color(1, 1, 1, 0.28)))
	v.add_child(ticks)
	m.speed_panel = speed
	m.speed_title = title
	m.speed_lbl = val
	m.speed_hint = hint
	m.speed_slider = sl
	m.speed_ticks = ticks

# =============================================================================================
# Leaderboard.luau: glass(8, 10, R_LG, 18), 300 wide, top-right 12 px; closed each match behind a
# rank pill ("#2  ·  6.3%"), GlassButton pill radius 999, min 170 x 40.
func _build_board() -> void:
	board = RK.glass(8, 10, RK.R_LG, 18)
	board.custom_minimum_size = Vector2(300, 0)
	root.add_child(board)
	var v := RK.vbox(4)
	board.add_child(v)
	var hm := MarginContainer.new()
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_theme_constant_override("margin_left", 10); hm.add_theme_constant_override("margin_right", 4)
	var header := RK.hbox(8)
	header.add_child(RK.icon_rect("leaderboard", 14, RK.AMBER))
	header.add_child(RK.label("LEADERBOARD", 12, 800, RK.TEXT, 2))
	header.add_child(RK.spacer())
	board_count = RK.label("", 11, 600, RK.TEXT_3)
	RK.fix_width(board_count, 84, HORIZONTAL_ALIGNMENT_RIGHT)
	board_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(board_count)
	var close := RK.button("", "GhostButton", "close", 26)
	close.custom_minimum_size = Vector2(26, 26)
	close.expand_icon = true
	close.add_theme_constant_override("icon_max_width", 11)
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_stylebox_override("normal", RK.empty_box(6, 6))
	close.add_theme_stylebox_override("hover", RK.flat(RK.FILL, 6, RK.CLEAR, 0, 6, 6))
	close.add_theme_stylebox_override("pressed", RK.flat(RK.FILL, 6, RK.CLEAR, 0, 6, 6))
	close.pressed.connect(func(): set_board_open(false))
	wire(close)
	header.add_child(close)
	hm.add_child(header)
	v.add_child(hm)
	var cm := MarginContainer.new()
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cm.add_theme_constant_override("margin_left", 10); cm.add_theme_constant_override("margin_right", 10)
	var cols := RK.hbox(8)
	var c1 := RK.caption("#", 10); c1.custom_minimum_size = Vector2(26, 0); c1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cols.add_child(c1)
	var c2 := RK.caption("Nation", 10); c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	var c3 := RK.caption("Land", 10); c3.custom_minimum_size = Vector2(50, 0); c3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cols.add_child(c3)
	var c4 := RK.caption("Troops", 10); c4.custom_minimum_size = Vector2(46, 0); c4.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cols.add_child(c4)
	cm.add_child(cols)
	v.add_child(cm)
	v.add_child(RK.hdivider())
	var list := RK.vbox(0)
	v.add_child(list)
	for i in 10:
		var r := _board_row()
		list.add_child(r.btn)
		board_rows.append(r)
	board_pin_sep = RK.label("···", 12, 700, RK.TEXT_3)
	board_pin_sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(board_pin_sep)
	board_pin = [_board_row()]
	list.add_child(board_pin[0].btn)
	board_pill = RK.button("Leaderboard", "GlassButton", "leaderboard", 40)
	board_pill.add_theme_constant_override("icon_max_width", 16)
	board_pill.custom_minimum_size = Vector2(170, 40)
	board_pill.add_theme_stylebox_override("normal", RK.flat(RK.GLASS, 999, RK.LINE, 1, 14, 6))
	for st in ["hover", "pressed", "hover_pressed"]:
		board_pill.add_theme_stylebox_override(st, RK.flat(RK.GLASS_RAISED, 999, RK.LINE_2, 1, 14, 6))
	board_pill.add_theme_font_size_override("font_size", 13)
	board_pill.clip_text = true
	board_pill.pressed.connect(func(): set_board_open(true))
	wire(board_pill)
	root.add_child(board_pill)
	board.visible = false
	board_pill.visible = false

func _board_row() -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 28)
	b.set_meta("rw", true)
	var me_style := RK.flat(RK.c(RK.AMBER, 0.12), 7, RK.c(RK.AMBER, 0.35), 1)
	var hov := RK.flat(Color(1, 1, 1, 0.07), 7)
	for sb in [me_style, hov]:
		sb.expand_margin_left = -2; sb.expand_margin_right = -2; sb.expand_margin_top = -1; sb.expand_margin_bottom = -1
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", hov)
	var h := RK.hbox(8)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10; h.offset_right = -10
	b.add_child(h)
	var rank := RK.label("1", 12, 600, RK.TEXT_3)
	RK.fix_width(rank, 26, HORIZONTAL_ALIGNMENT_RIGHT)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rank)
	var sw := RK.swatch(RK.TEXT, 10, 3)
	h.add_child(sw)
	var nm := RK.label("", 13, 600)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(40, 0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var mark := RK.icon_rect("alliance", 13, RK.GREEN)
	h.add_child(mark)
	var land := RK.label("", 13, 700)
	RK.fix_width(land, RK.text_width("88.88%", 13, 700) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	land.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(land)
	var tr := RK.label("", 12, 500, RK.TEXT_2)
	RK.fix_width(tr, RK.text_width("888.8K", 12, 500) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tr)
	var row := {"btn": b, "rank": rank, "sw": sw, "name": nm, "mark": mark, "land": land, "troops": tr, "id": 0, "me_style": me_style, "hov": hov}
	b.pressed.connect(func(): if int(row.id) > 0: focus_owner(int(row.id)))
	wire(b)
	return row

func _set_board_row(r: Dictionary, id: int, rank: int) -> void:
	var n = m.nations[id]
	var me: bool = id == m.PLAYER
	r.id = id
	r.rank.text = str(rank)
	RK.set_color(r.rank, RK.GOLD if rank == 1 else RK.TEXT_3)
	RK.set_swatch(r.sw, n.color)
	r.name.text = n.name
	r.land.text = RK.fmt_pct(n.land / maxf(1.0, m.land_total))
	r.troops.text = m._fmt(n.troops)
	var pl = m.nations[m.PLAYER]
	var threat: bool = not me and pl.troops > 0 and n.troops > 3 * pl.troops and not m.allied(m.PLAYER, id)
	RK.set_color(r.troops, RK.RED if threat else RK.TEXT_2)
	var ally: bool = not me and m.allied(m.PLAYER, id)
	var traitor: bool = m.is_traitor(id)
	r.mark.visible = ally or traitor
	if traitor:
		RK.set_icon(r.mark, "betray"); r.mark.modulate = RK.RED
	elif ally:
		RK.set_icon(r.mark, "alliance"); r.mark.modulate = RK.GREEN
	var nc := RK.TEXT
	if me: nc = RK.AMBER_HI
	elif traitor: nc = Color(1.0, 0.7, 0.72)
	RK.set_color(r.name, nc)
	var b: Button = r.btn
	b.add_theme_stylebox_override("normal", r.me_style if me else StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", r.me_style if me else r.hov)

func set_board_open(on: bool) -> void:
	var was := board_open
	board_open = on
	board.visible = on
	board_pill.visible = not on and (m.state == "play" or m.state == "pick")
	if on and not was:
		refresh_board()
		board.reset_size()
		layout()
		RK.pop_in(board, 0.0, 0.97, 0.3)
		m.sfx("open", -8.0)
	elif not on and was:
		m.sfx("close", -8.0)
	layout()

func _ranking() -> Array:
	var ids := []
	for id in range(1, m.nations.size()):
		if m.nations[id].alive and m.nations[id].land > 0: ids.append(id)
	ids.sort_custom(func(a, b): return m.nations[a].land > m.nations[b].land)
	return ids

func refresh_board() -> void:
	var ids := _ranking()
	var my_rank := ids.find(m.PLAYER) + 1
	var lt: float = maxf(1.0, m.land_total)
	if my_rank > 0:
		board_pill.text = "#%d  ·  %s" % [my_rank, RK.fmt_pct(m.nations[m.PLAYER].land / lt)]
	elif ids.size() > 0:
		var nm: String = m.nations[ids[0]].name
		if nm.length() > 10: nm = nm.substr(0, 9) + "…"
		board_pill.text = "%s  %s" % [nm, RK.fmt_pct(m.nations[ids[0]].land / lt)]
	if not board_open: return
	var shown := mini(10, ids.size())
	for i in board_rows.size():
		var r: Dictionary = board_rows[i]
		r.btn.visible = i < shown
		if i < shown: _set_board_row(r, ids[i], i + 1)
	var pin: bool = my_rank > shown
	board_pin_sep.visible = pin
	board_pin[0].btn.visible = pin
	if pin: _set_board_row(board_pin[0], m.PLAYER, my_rank)
	board_count.text = "%d alive" % ids.size()

func focus_owner(id: int) -> void:
	if id <= 0 or id >= m.nations.size(): return
	var n = m.nations[id]
	if n.land <= 0: return
	var target: Vector2 = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * m.TS
	var tw: Tween = m.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m.cam, "position", target, 0.42)
	tw.tween_callback(m._clamp_cam)

# =============================================================================================
# AttacksPanel.luau: glass(10, 9, R_LG, 16), 300 wide, right 12, under the board / status pill;
# hidden while there are no attacks. Rows: red-tinted incoming, glass outgoing, retreat / eye action.
func _build_attacks() -> void:
	atk = RK.glass(10, 9, RK.R_LG, 16)
	atk.custom_minimum_size = Vector2(300, 0)
	root.add_child(atk)
	var v := RK.vbox(5)
	atk.add_child(v)
	var hm := MarginContainer.new()
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_theme_constant_override("margin_left", 4); hm.add_theme_constant_override("margin_right", 4)
	hm.custom_minimum_size = Vector2(0, 24)
	var head := RK.hbox(8)
	head.add_child(RK.icon_rect("attack", 13, RK.AMBER))
	head.add_child(RK.label("ATTACKS", 12, 800, RK.TEXT, 2))
	head.add_child(RK.spacer())
	atk_count = RK.label("", 11, 600, RK.TEXT_3)
	RK.fix_width(atk_count, 90, HORIZONTAL_ALIGNMENT_RIGHT)
	atk_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(atk_count)
	head.add_child(RK.icon_rect("chevron", 12, RK.TEXT_3))
	hm.add_child(head)
	v.add_child(hm)
	atk_list = RK.vbox(4)
	v.add_child(atk_list)
	for i in 6:
		var r := _atk_row()
		atk_list.add_child(r.panel)
		atk_rows.append(r)
	atk_more = RK.label("", 11, 600, RK.TEXT_3)
	atk_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(atk_more)
	atk.visible = false

func _atk_row() -> Dictionary:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg_in := RK.flat(RK.c(RK.RED, 0.14), 8, RK.c(RK.RED, 0.45), 1, 8, 3)
	var bg_out := RK.flat(Color(1, 1, 1, 0.04), 8, Color(1, 1, 1, 0.06), 1, 8, 3)
	p.add_theme_stylebox_override("panel", bg_out)
	var h := RK.hbox(8)
	p.add_child(h)
	var arrow := RK.icon_rect("attack", 13, RK.AMBER)
	h.add_child(arrow)
	var sw := RK.swatch(RK.TEXT, 9, 2)
	h.add_child(sw)
	var nm := RK.label("", 13, 600)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(40, 0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var tr := RK.label("", 13, 700)
	RK.fix_width(tr, RK.text_width("888.8K", 13, 700) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tr)
	var act := Button.new()
	act.focus_mode = Control.FOCUS_NONE
	act.custom_minimum_size = Vector2(30, 26)
	act.expand_icon = true
	act.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.add_theme_constant_override("icon_max_width", 14)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		act.add_theme_stylebox_override(st, RK.flat(RK.FILL if st == "normal" else RK.FILL_2, 7, RK.LINE, 1, 6, 4))
	act.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		act.add_theme_color_override(k, RK.TEXT)
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(act)
	var row := {"panel": p, "arrow": arrow, "sw": sw, "name": nm, "troops": tr, "act": act, "bg_in": bg_in, "bg_out": bg_out, "at": null, "inc": false}
	act.pressed.connect(func():
		var at = row.at
		if at == null: return
		if row.inc: focus_owner(int(at.a))
		elif at in m.attacks and at.a == m.PLAYER: m.retreat(at))
	wire(act)
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and row.at != null:
			var oth: int = int(row.at.t) if not row.inc else int(row.at.a)
			if oth > 1: focus_owner(oth))
	return row

func refresh_attacks() -> void:
	var list: Array = []
	for at in m.attacks:
		if at.t == m.PLAYER: list.append(at)
	var outs := []
	for at in m.attacks:
		if at.a == m.PLAYER: outs.append(at)
	outs.sort_custom(func(p, q):
		var pe: bool = p.t <= 1
		var qe: bool = q.t <= 1
		if pe != qe: return qe
		return p.troops > q.troops)
	var inc := list.size()
	list.append_array(outs)
	var vis: bool = list.size() > 0 and m.state == "play"
	if vis != atk.visible:
		atk.visible = vis
		if vis:
			atk.reset_size()
			RK.pop_in(atk, 0.0, 0.97, 0.25)
	if not vis: return
	var shown := mini(6, list.size())
	for i in atk_rows.size():
		var r: Dictionary = atk_rows[i]
		r.panel.visible = i < shown
		if i >= shown:
			r.at = null
			continue
		var at = list[i]
		var incoming: bool = at.t == m.PLAYER
		var other: int = int(at.a) if incoming else int(at.t)
		r.at = at; r.inc = incoming
		r.panel.add_theme_stylebox_override("panel", r.bg_in if incoming else r.bg_out)
		var expansion: bool = other <= 1 or other >= m.nations.size()
		r.panel.modulate.a = 0.72 if (not incoming and expansion) else 1.0
		RK.set_icon(r.arrow, "target" if incoming else ("globe" if expansion else "attack"))
		r.arrow.modulate = RK.RED if incoming else (RK.GREEN if expansion else RK.AMBER)
		r.sw.visible = not expansion
		if not expansion: RK.set_swatch(r.sw, m.nations[other].color)
		r.name.text = "Expansion" if expansion else m.nations[other].name
		RK.set_color(r.name, Color(1.0, 0.82, 0.84) if incoming else RK.TEXT)
		r.troops.text = m._fmt(at.troops)
		RK.set_color(r.troops, RK.RED if incoming else RK.TEXT)
		r.act.icon = RK.icon_tex("eye" if incoming else "retreat")
	var outn := list.size() - inc
	atk_count.text = ("%d out" % outn) if inc == 0 else ("%d in" % inc if outn == 0 else "%d out · %d in" % [outn, inc])
	atk_more.visible = list.size() > shown
	atk_more.text = "+%d more" % (list.size() - shown)

# =============================================================================================
# CommandBar.luau: glass(18, 12, R_LG, 22), bottom-centre 12 px. WIDE: one row
# [nation | troops | attack | gold | build slots | SHOP]; STACKED (narrow / many arsenal slots):
# stats row over the slots row (vbox 10). BuildButton 54 x 60, ShopSlot 58 x 60, RatioSlider 5 stops.
const BASE_ORDER := [0, 1, 2, 3, 4, 5, 6]
const NUKE_ORDER := [7, 8, 9, 11, 12]
const EXTRA_ORDER := [10, 13, 14, 15]
const HOTKEY := {0: "1", 1: "2", 2: "3", 3: "4", 4: "5", 5: "6", 6: "7", 7: "8", 8: "9", 9: "0", 13: "R", 16: "I"}

func _section(icon: String, cap: String, icon_col := RK.TEXT_3) -> Dictionary:
	var v := RK.vbox(2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head := RK.hbox(5)
	if icon != "": head.add_child(RK.icon_rect(icon, 12, icon_col))
	head.add_child(RK.caption(cap))
	head.add_child(RK.spacer())
	v.add_child(head)
	return {"box": v, "head": head}

func _build_bar() -> void:
	bar = RK.glass(18, 12, RK.R_LG, 22)
	root.add_child(bar)
	bar_root = RK.vbox(10)
	bar.add_child(bar_root)
	# nation
	var nv := RK.vbox(2)
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nh := RK.hbox(8)
	cb_swatch = RK.swatch(RK.AMBER, 14, 4)
	nh.add_child(cb_swatch)
	cb_name = RK.label("You", 17, 700)
	cb_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cb_name.clip_text = true
	cb_name.custom_minimum_size = Vector2(96, 0)
	nh.add_child(cb_name)
	cb_crown = RK.icon_rect("crown", 14, RK.GOLD)
	nh.add_child(cb_crown)
	nv.add_child(nh)
	cb_land = RK.label("", 12, 500, RK.TEXT_2)
	nv.add_child(cb_land)
	nv.custom_minimum_size = Vector2(150, 0)
	cb_nation = nv
	# troops
	var ts := _section("troops", "Troops")
	cb_growth = RK.label("", 12, 700, RK.GREEN)
	RK.fix_width(cb_growth, RK.text_width("+88.8K/s (888%)", 12, 700) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	ts.head.add_child(cb_growth)
	var tv := RK.hbox(5)
	cb_troops = RK.label("0", 24, 800)
	tv.add_child(cb_troops)
	cb_cap = RK.label("", 13, 600, RK.TEXT_3)
	cb_cap.size_flags_vertical = Control.SIZE_SHRINK_END
	tv.add_child(cb_cap)
	ts.box.add_child(tv)
	var tb := RK.hbox(8)
	cb_troops_bar = RK.fill_bar(4.0, RK.CYAN)
	cb_troops_bar.custom_minimum_size = Vector2(120, 6)
	cb_troops_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_child(cb_troops_bar)
	cb_committed = RK.label("", 11, 700, RK.ORANGE)
	cb_committed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb_committed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tb.add_child(cb_committed)
	ts.box.add_child(tb)
	ts.box.custom_minimum_size = Vector2(212, 0)
	cb_troops_box = ts.box
	# attack ratio
	var rs := _section("attack", "Attack")
	cb_ratio_pct = RK.label("", 14, 800, RK.AMBER)
	rs.head.add_child(cb_ratio_pct)
	cb_slider = Control.new()
	cb_slider.custom_minimum_size = Vector2(210, 28)
	cb_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	cb_slider.draw.connect(_draw_ratio)
	cb_slider.gui_input.connect(_ratio_input)
	cb_slider.mouse_exited.connect(func(): slider_hover = -1; cb_slider.queue_redraw())
	rs.box.add_child(cb_slider)
	cb_ratio_sub = RK.label("", 12, 500, RK.TEXT_3)
	rs.box.add_child(cb_ratio_sub)
	cb_ratio_box = rs.box
	# gold
	var gs := _section("gold", "Gold", RK.GOLD)
	cb_income = RK.label("", 12, 700, RK.GREEN)
	RK.fix_width(cb_income, RK.text_width("+888.8K/s", 12, 700) + 2, HORIZONTAL_ALIGNMENT_RIGHT)
	gs.head.add_child(cb_income)
	cb_gold = RK.label("0", 24, 800, RK.GOLD)
	gs.box.add_child(cb_gold)
	gs.box.custom_minimum_size = Vector2(150, 0)
	cb_gold_box = gs.box
	# slots
	cb_builds = RK.hbox(6)
	cb_builds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in BASE_ORDER + NUKE_ORDER + [16] + EXTRA_ORDER:
		slots[k] = _make_slot(k)
	shop_btn = Button.new()
	shop_btn.focus_mode = Control.FOCUS_NONE
	shop_btn.custom_minimum_size = Vector2(58, 60)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		shop_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	shop_btn.draw.connect(_draw_shop)
	shop_btn.mouse_entered.connect(func(): m.tip_slot = 99; shop_btn.queue_redraw())
	shop_btn.mouse_exited.connect(func():
		if m.tip_slot == 99: m.tip_slot = -1
		shop_btn.queue_redraw())
	shop_btn.pressed.connect(func(): m._open_shop())
	wire(shop_btn)
	# legacy handles used by main.gd's build tips
	m.build_btns.resize(17)
	for k in slots: m.build_btns[k] = slots[k]
	_arrange_slots()
	_reflow(true)

func _make_slot(k: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(54, 60)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.set_meta("k", k)
	b.draw.connect(func(): _draw_slot(b, k))
	b.mouse_entered.connect(func(): m.tip_slot = k; b.queue_redraw())
	b.mouse_exited.connect(func():
		if m.tip_slot == k: m.tip_slot = -1
		b.queue_redraw())
	b.button_down.connect(func(): b.queue_redraw())
	b.button_up.connect(func(): b.queue_redraw())
	b.pressed.connect(func(): m.select_build(k))
	wire(b)
	return b

func _visible_kinds() -> Array:
	var out := []
	for k in BASE_ORDER: out.append(k)
	for k in NUKE_ORDER:
		if k <= 9 or m.is_avail(k): out.append(k)
	out.append(16)
	for k in EXTRA_ORDER:
		if m.is_avail(k): out.append(k)
	return out

func _arrange_slots() -> void:
	var ks := _visible_kinds()
	var sig := str(ks)
	if sig == _arsenal_sig: return
	_arsenal_sig = sig
	for c in cb_builds.get_children(): cb_builds.remove_child(c)
	var prev := -1
	for k in ks:
		var grp := 0 if k in BASE_ORDER else (1 if (k in NUKE_ORDER or k == 16) else 2)
		if prev >= 0 and grp != prev:
			var d := RK.vdivider(44)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			d.set_meta("slotdiv", true)
			cb_builds.add_child(d)
		prev = grp
		cb_builds.add_child(slots[k])
	for k in slots: slots[k].visible = k in ks
	cb_builds.add_child(shop_btn)
	_flow = -1

func _extra_slots() -> int:
	return _visible_kinds().size() - 10

func _reflow(force := false) -> void:
	var extra := 62 * _extra_slots() + 58 + 4
	var wide := 1600 >= 1420 + extra
	var want := 0 if wide else 1
	if want == _flow and not force: return
	_flow = want
	for c in bar_root.get_children(): bar_root.remove_child(c)
	for n in [cb_nation, cb_troops_box, cb_ratio_box, cb_gold_box, cb_builds]:
		if n.get_parent(): n.get_parent().remove_child(n)
	var dh := 44.0 if wide else 40.0
	var stats := RK.hbox(16)
	stats.add_child(cb_nation)
	stats.add_child(RK.vdivider(dh))
	stats.add_child(cb_troops_box)
	stats.add_child(RK.vdivider(dh))
	stats.add_child(cb_ratio_box)
	stats.add_child(RK.vdivider(dh))
	stats.add_child(cb_gold_box)
	for c in stats.get_children():
		if c is ColorRect: c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if wide:
		stats.add_child(RK.vdivider(dh))
		stats.get_child(stats.get_child_count() - 1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(cb_builds)
		bar_root.add_child(stats)
	else:
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		bar_root.add_child(stats)
		var row := RK.hbox(0)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(cb_builds)
		bar_root.add_child(row)
	bar.reset_size()

var _silo_cd := 0.0
func _calc_silo_cd() -> float:
	if m.owned(m.PLAYER, 5) <= 0: return 0.0
	var best := INF
	for st in m.structs:
		if st.o == m.PLAYER and st.k == 5 and st.get("bt", 0.0) <= 0.0:
			if m._ready_slots(st) > 0: return 0.0
			best = minf(best, float(st.get("cd", 0.0)))
	return 0.0 if best == INF else best

func _slot_cooldown(k: int) -> float:
	if k in NUKE_ORDER: return _silo_cd
	if k == 14 or k == 15: return m._strike_cd(k)
	return 0.0

func _draw_slot(b: Button, k: int) -> void:
	var s := b.size
	var r := Rect2(Vector2.ZERO, s)
	var avail: bool = m.is_avail(k)
	var active: bool = (k == 16 and m.icbm_mode) or (k != 16 and m.build_sel == k)
	var hover := b.is_hovered()
	var nuke: bool = k in NUKE_ORDER or k == 16
	var bg := RK.FILL
	var bc := RK.LINE
	if nuke: bg = RK.c(RK.RED, 0.07); bc = RK.c(RK.RED, 0.22)
	if hover and avail: bg = Color(1, 1, 1, 0.1); bc = RK.LINE_2
	if active: bg = RK.c(RK.AMBER, 0.2); bc = RK.AMBER
	var sb := RK.flat(bg, RK.R_MD, bc, 1)
	b.draw_style_box(sb, r)
	var a := 1.0 if avail else 0.4
	var t: Texture2D = m._tex(m.UI_TEX[k]) if m.UI_TEX.has(k) else null
	var ip := 24.0
	var ic := Vector2(s.x * 0.5, s.y * 0.42)
	if t:
		b.draw_texture_rect(t, Rect2(ic - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), false, Color(1, 1, 1, a))
	var cost_txt := ""
	var cost_col := RK.GOLD
	var cd := _slot_cooldown(k) if avail else 0.0
	var pl = m.nations[m.PLAYER] if m.nations.size() > m.PLAYER else null
	if k == 16:
		cost_txt = "ON" if m.icbm_mode else "+10%"
		cost_col = RK.AMBER_HI if m.icbm_mode else RK.GOLD
	elif pl != null:
		var cost: float = m.build_cost(m.PLAYER, k)
		cost_txt = m._fmt(cost)
		if cd > 0.0:
			cost_txt = "%ds" % maxi(1, ceili(cd)); cost_col = RK.RED
		elif not avail or pl.gold < cost or m.build_req(k, -1) != "":
			cost_col = RK.c(RK.RED, 0.9)
	var f8 := RK.font(700)
	b.draw_string(f8, Vector2(0, s.y - 7), cost_txt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 11, Color(cost_col, a if cost_col != RK.RED else 1.0))
	var hk: String = HOTKEY.get(k, "")
	if hk != "":
		b.draw_string(RK.font(600), Vector2(6, 13), hk, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(RK.TEXT_3, a))
	if pl != null and k < 16 and k != 13:
		var n: int = m.owned_count(m.PLAYER, k)
		if n > 0:
			b.draw_string(RK.font(600), Vector2(0, 13), "×%d" % n, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 6, 9, RK.TEXT_2)
	if cd > 0.0:
		var top_c := Vector2(ic.x, ic.y)
		b.draw_arc(top_c, 15, -PI / 2, -PI / 2 + TAU * clampf(cd / 9.0, 0.0, 1.0), 28, RK.c(RK.RED, 0.7), 2.0, true)

func _draw_shop() -> void:
	var b := shop_btn
	var s := b.size
	var hover := b.is_hovered()
	var top_c := Color8(255, 226, 122)
	var bot_c := Color8(238, 148, 28)
	if hover: top_c = top_c.lightened(0.12); bot_c = bot_c.lightened(0.12)
	# vertical gradient inside a rounded rect: draw the rounded base, then horizontal bands clipped by radius
	var rad := float(RK.R_MD)
	var steps := 20
	for i in steps:
		var y0 := s.y * i / steps
		var y1 := s.y * (i + 1) / steps
		var col := top_c.lerp(bot_c, (i + 0.5) / steps)
		var inset := 0.0
		var ym := (y0 + y1) * 0.5
		if ym < rad: inset = rad - sqrt(maxf(0.0, rad * rad - (rad - ym) * (rad - ym)))
		elif ym > s.y - rad: inset = rad - sqrt(maxf(0.0, rad * rad - (ym - (s.y - rad)) * (ym - (s.y - rad))))
		b.draw_rect(Rect2(inset, y0, s.x - inset * 2, y1 - y0 + 0.5), col)
	b.draw_style_box(RK.flat(RK.CLEAR, RK.R_MD, RK.c(RK.INK, 0.55), 1), Rect2(Vector2.ZERO, s))
	# cycling arsenal render (ShopSlot.luau cycles unlockable weapons)
	var pool := [11, 12, 10, 14, 15, 13]
	var k: int = pool[int(_shop_t / 2.4) % pool.size()]
	var t: Texture2D = m._tex(m.UI_TEX[k]) if m.UI_TEX.has(k) else null
	if t:
		b.draw_texture_rect(t, Rect2(Vector2(s.x * 0.5 - 13, 8), Vector2(26, 26)), false, Color(RK.INK, 0.9))
	b.draw_string(RK.font(900, 1), Vector2(0, s.y - 9), "SHOP", HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, RK.INK)

func _draw_ratio() -> void:
	var c := cb_slider
	var s := c.size
	var n: int = m.SHARES.size()
	var pad := 3.0
	var seg := (s.x - pad * 2) / n
	c.draw_style_box(RK.flat(Color(1, 1, 1, 0.07), 8, Color(1, 1, 1, 0.12), 1), Rect2(Vector2.ZERO, s))
	if slider_hover >= 0 and slider_hover != m.share_i:
		c.draw_style_box(RK.flat(Color(1, 1, 1, 0.06), 6), Rect2(pad + seg * slider_hover, pad, seg, s.y - pad * 2))
	var tr := Rect2(pad + seg * slider_shown, pad, seg, s.y - pad * 2)
	var thumb := RK.flat(RK.AMBER, 6, RK.AMBER_LO, 0)
	thumb.border_width_bottom = 2
	c.draw_style_box(thumb, tr)
	for i in n:
		var on: bool = i == m.share_i
		var col := RK.INK if on else (RK.TEXT if i == slider_hover else RK.TEXT_2)
		c.draw_string(RK.font(800 if on else 600), Vector2(pad + seg * i, s.y * 0.5 + 4.5), "%d%%" % int(round(m.SHARES[i] * 100)), HORIZONTAL_ALIGNMENT_CENTER, seg, 12, col)

func _ratio_index(x: float) -> int:
	var n: int = m.SHARES.size()
	return clampi(int((x - 3.0) / ((cb_slider.size.x - 6.0) / n)), 0, n - 1)

func _ratio_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _ratio_index(e.position.x)
		if h != slider_hover: slider_hover = h; cb_slider.queue_redraw()
		if slider_drag and h != m.share_i: m._set_share(h)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		slider_drag = e.pressed
		if e.pressed:
			var i := _ratio_index(e.position.x)
			m.sfx("click", 0.0, 0.02)
			if i != m.share_i: m._set_share(i)
		cb_slider.accept_event()

func on_share_changed() -> void:
	if cb_slider: cb_slider.queue_redraw()
	refresh_bar_text()

func refresh_bar_text() -> void:
	if m.nations.size() <= m.PLAYER: return
	var pl = m.nations[m.PLAYER]
	cb_ratio_pct.text = "%d%%" % int(round(m.SHARES[m.share_i] * 100))
	cb_ratio_sub.text = "Sends %s troops" % m._fmt(pl.troops * m.SHARES[m.share_i])

func refresh_bar(ema_regen: float, ema_gold: float, txt: bool) -> void:
	var pl = m.nations[m.PLAYER]
	var cap: float = m.troop_cap(m.PLAYER)
	RK.set_swatch(cb_swatch, RK.owner_ui_color(pl.color))
	cb_name.text = pl.name if str(pl.get("name", "")) != "" else "You"
	cb_crown.visible = _leader() == m.PLAYER
	cb_land.text = "%s of the world" % RK.fmt_pct(pl.land / maxf(1.0, m.land_total))
	if txt:
		var cap_pct := int(round(100.0 * pl.troops / maxf(1.0, cap)))
		cb_growth.text = "%s%s/s (%d%%)" % ["+" if ema_regen >= 0 else "", m._fmt(ema_regen), clampi(cap_pct, 0, 999)]
		cb_income.text = "+%s/s" % m._fmt(ema_gold)
	cb_cap.text = "/ %s" % m._fmt(cap)
	RK.fill_set(cb_troops_bar, clampf(pl.troops / maxf(cap, 1.0), 0.0, 1.0))
	var at_war := 0.0
	for at in m.attacks: if at.a == m.PLAYER: at_war += at.troops
	for bt in m.boats: if bt.a == m.PLAYER: at_war += bt.troops
	cb_committed.text = ("%s at war" % m._fmt(at_war)) if at_war > 0 else ""
	refresh_bar_text()
	_arrange_slots()
	_reflow()
	_silo_cd = _calc_silo_cd()
	for k in slots:
		if slots[k].visible: slots[k].queue_redraw()

# =============================================================================================
# EventFeed.luau: lower-left, 340 wide, newest at the bottom; toasts glass(12, 9, R_MD, 12) with a 3 px
# category accent, a 26 px icon disc and 13/500 text. Repeats fold into "×N"; at most 5 stay.
const FEED_W := 340.0
const KIND_COL := {"good": RK.GREEN, "bad": RK.ORANGE, "info": RK.CYAN, "alert": RK.RED, "ally": RK.VIOLET}
const KIND_ICON := {"good": "check", "bad": "info", "info": "info", "alert": "target", "ally": "alliance"}
const KIND_LIFE := {"good": 6.5, "bad": 6.5, "info": 4.0, "alert": 9.0, "ally": 6.5}

func _build_feed() -> void:
	feed = RK.vbox(8)
	feed.custom_minimum_size = Vector2(FEED_W, 0)
	feed.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(feed)

func _toast_kind(text: String, kind: String) -> String:
	var t := text.to_lower()
	if kind == "bad" and (t.contains("nuke") or t.contains("bomb") or t.contains("incoming") or t.contains("attack")): return "alert"
	if t.contains("alliance") or t.contains("allied") or t.contains("ally"): return "ally"
	return kind

# EventFeed picks the event's own glyph (boat for naval news, crown for captures, ...)
func _toast_icon(text: String, k: String) -> String:
	var t := text.to_lower()
	for pair in [["warship", "boat"], ["transport", "boat"], ["boat", "boat"], ["captured", "crown"], ["alliance", "alliance"], ["allied", "alliance"],
			["betray", "betray"], ["traitor", "betray"], ["nuke", "atom"], ["bomb", "atom"], ["mirv", "atom"], ["gold", "gold"], ["troops", "troops"],
			["eliminated", "skull"], ["destroyed", "skull"], ["attack", "attack"], ["unlocked", "check"]]:
		if t.contains(pair[0]): return pair[1]
	return KIND_ICON.get(k, "info")

# main.notify() can fire inside a time-budgeted sim pass (sim/attacks.gd deadline), so building the
# toast is deferred to the next frame; only the newest few are kept while no frames run (headless).
var _pending := []
func toast(text: String, kind := "info") -> void:
	if feed == null: return
	_pending.append([text, kind])
	if _pending.size() > 6: _pending.pop_front()

func _flush_toasts() -> void:
	if _pending.is_empty(): return
	var q := _pending
	_pending = []
	for e in q: _toast_now(e[0], e[1])

func _toast_now(text: String, kind := "info") -> void:
	var k := _toast_kind(text, kind)
	if _recent.has(text):
		var old: Dictionary = _recent[text]
		if is_instance_valid(old.panel):
			old.n += 1
			old.t = 0.0
			old.count.text = "×%d" % old.n
			old.count.visible = true
			RK.pop_in(old.panel, 0.0, 0.98, 0.2)
			return
	var col: Color = KIND_COL.get(k, RK.CYAN)
	var p := RK.glass(12, 9, RK.R_MD, 12)
	RK.glass_set(p, "accent", col)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := RK.hbox(10)
	p.add_child(h)
	h.add_child(_disc(col, _toast_icon(text, k)))
	var l := RK.label(text, 13, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(FEED_W - 24 - 26 - 10 - 40, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var cnt := RK.label("", 12, 700, RK.TEXT_2)
	cnt.visible = false
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cnt)
	p.custom_minimum_size = Vector2(FEED_W, 0)
	feed.add_child(p)
	var rec := {"panel": p, "count": cnt, "n": 1, "t": 0.0, "life": float(KIND_LIFE.get(k, 6.5)), "text": text}
	p.set_meta("rec", rec)
	_recent[text] = rec
	RK.pop_in(p, 0.0, 0.96, 0.3)
	var toasts := []
	var dying := []
	for c in feed.get_children():
		if c.has_meta("rec"):
			if c.get_meta("dying", false): dying.append(c)
			else: toasts.append(c)
	while toasts.size() > 5:
		var o: Control = toasts.pop_front()
		_drop_toast(o)
		dying.append(o)
	# fade-outs need frames; without them (headless sims) never keep more than 2 leaving toasts around
	while dying.size() > 2:
		var d: Control = dying.pop_front()
		feed.remove_child(d)
		d.queue_free()

func _drop_toast(p: Control) -> void:
	if not is_instance_valid(p) or p.get_meta("dying", false): return
	p.set_meta("dying", true)
	var rec: Dictionary = p.get_meta("rec")
	if _recent.get(rec.text) == rec: _recent.erase(rec.text)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)

# 26 px icon disc (EventFeed): tinted circle, 1 px ring, 14 px icon centred
func _disc(col: Color, icon: String) -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(26, 26)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := RK.icon_tex(icon)
	d.draw.connect(func():
		var c := d.size * 0.5
		d.draw_circle(c, 13, RK.c(col, 0.16))
		d.draw_arc(c, 12.5, 0, TAU, 32, RK.c(col, 0.28), 1.0, true)
		if t: d.draw_texture_rect(t, Rect2(c - Vector2(7, 7), Vector2(14, 14)), false, col))
	return d

func clear_feed() -> void:
	_pending.clear()
	for c in feed.get_children():
		if c.has_meta("rec"): c.queue_free()
	_recent.clear()

func _tick_feed(dt: float) -> void:
	for c in feed.get_children():
		if not c.has_meta("rec") or c.get_meta("dying", false): continue
		var rec: Dictionary = c.get_meta("rec")
		rec.t += dt
		if rec.t > rec.life: _drop_toast(c)

# =============================================================================================
# AlertBanner.luau: red pill under the status pill, "INCOMING NUKE" 15/800 spacing 3, border pulses at
# 7 rad/s; seconds to impact for the soonest warhead (port countdown).
func _build_alert() -> void:
	alert = PanelContainer.new()
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert.add_theme_stylebox_override("panel", RK.flat(Color(0.26, 0.03, 0.07, 0.9), 999, RK.RED, 1, 18, 8))
	var h := RK.hbox(10)
	alert.add_child(h)
	al_disc = Panel.new()
	al_disc.custom_minimum_size = Vector2(26, 26)
	al_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	al_disc.add_theme_stylebox_override("panel", RK.flat(RK.c(RK.RED, 0.25), 13))
	al_icon = RK.icon_rect("atom", 16, Color(1, 0.85, 0.86))
	al_icon.position = Vector2(5, 5); al_icon.size = Vector2(16, 16)
	al_disc.add_child(al_icon)
	h.add_child(al_disc)
	al_title = RK.label("INCOMING NUKE", 15, 800, Color(1, 0.88, 0.89), 3)
	al_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(al_title)
	al_detail = RK.label("", 13, 600, Color(1, 0.75, 0.77))
	al_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(al_detail)
	alert.visible = false
	root.add_child(alert)

func _tick_alert(dt: float) -> void:
	var soon := INF
	var who := -1
	var cnt := 0
	if m.state == "play":
		for ms in m.missiles:
			if ms.o == m.PLAYER: continue
			if bool(ms.get("mirv_bus", false)) and bool(ms.get("split_done", false)): continue
			var tp: Vector2 = ms.to
			var tx := int(tp.x); var ty := int(tp.y)
			if tx < 0 or ty < 0 or tx >= m.W or ty >= m.H: continue
			if m.owner_map[ty * m.W + tx] != m.PLAYER and int(ms.get("tgt_o", -1)) != m.PLAYER: continue
			cnt += 1
			var eta: float = maxf(0.0, float(ms.dur) - float(ms.t))
			if eta < soon: soon = eta; who = int(ms.o)
	var on := cnt > 0
	if on != alert.visible:
		alert.visible = on
		if on:
			alert.reset_size(); layout()
			RK.pop_in(alert, 0.0, 0.9, 0.3)
	if not on: return
	_al_t += dt
	var pulse := 0.55 + 0.45 * sin(_al_t * 7.0)
	var sb: StyleBoxFlat = alert.get_theme_stylebox("panel")
	sb.border_color = RK.c(RK.RED, pulse)
	al_title.text = "INCOMING NUKE" if cnt == 1 else "INCOMING NUKES ×%d" % cnt
	var nm: String = m.nations[who].name if who > 0 and who < m.nations.size() else "Unknown"
	al_detail.text = "%s  ·  %ds" % [nm, int(ceil(soon))]
	var w := alert.get_combined_minimum_size().x
	if absf(alert.size.x - w) > 1: alert.reset_size(); layout()

# =============================================================================================
# SpawnOverlay.luau: top-centre glass banner during the spawn phase.
func _build_spawn() -> void:
	spawn = RK.glass(16, 8, RK.R_LG, 18)
	RK.glass_padding(spawn, 16, 8, 12, 8)
	spawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spawn)
	var h := RK.hbox(16)
	spawn.add_child(h)
	var v := RK.vbox(1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sp_title = RK.label("CHOOSE YOUR STARTING LOCATION", 14, 800, RK.TEXT, 1.5)
	v.add_child(sp_title)
	sp_sub = RK.label("Click any unclaimed land to found your nation.", 12, 500, RK.TEXT_2)
	v.add_child(sp_sub)
	RK.fix_width(sp_sub, RK.text_width("Click anywhere else on land to switch your starting spot (timer won't reset).", 12, 500) + 4)
	h.add_child(v)
	sp_ring = Control.new()
	sp_ring.custom_minimum_size = Vector2(40, 40)
	sp_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sp_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp_ring.draw.connect(func():
		var v2: float = sp_ring.get_meta("v", 1.0)
		var n: int = int(sp_ring.get_meta("n", 5))
		var c := sp_ring.size * 0.5
		var col := RK.RED if n <= 5 else RK.AMBER
		sp_ring.draw_circle(c, 17, Color(0, 0, 0, 0.35))
		sp_ring.draw_arc(c, 17, 0, TAU, 40, Color(1, 1, 1, 0.12), 3, true)
		sp_ring.draw_arc(c, 17, -PI / 2, -PI / 2 + TAU * v2, 40, col, 3, true)
		sp_ring.draw_string(RK.font(800), Vector2(0, c.y + 6), str(n), HORIZONTAL_ALIGNMENT_CENTER, sp_ring.size.x, 17, RK.TEXT))
	h.add_child(sp_ring)
	spawn.visible = false
	m.pick_panel = spawn
	m.pick_title = sp_title
	m.pick_sub = sp_sub
	m.pick_ring = sp_ring

# =============================================================================================
# UIRoot._layout: everything on the 1600 x 900 logical canvas.
func _mark_dirty() -> void:
	if not _in_layout: _dirty = true

func layout() -> void:
	if root == null: return
	_in_layout = true
	_dirty = false
	var vs := root.get_viewport_rect().size
	if vs.x < 10: vs = Vector2(1600, 900)
	# top-bar row, device px
	var k := 1.0 / _device_scale()
	var bs := RK.TOPBAR_BUTTON * k
	var gap := RK.TOPBAR_GAP * k
	for b in tb_buttons.values():
		b.custom_minimum_size = Vector2(bs, bs)
		b.size = Vector2(bs, bs)
	topbar.add_theme_constant_override("separation", int(round(gap)))
	topbar.position = Vector2(12 * k, 12 * k)
	topbar.reset_size()
	var tb_bottom := topbar.position.y + bs
	# speed chip under the top-bar row
	speed.reset_size()
	speed.position = Vector2(12, tb_bottom + 10)
	# status pill / spawn banner, top centre
	top.reset_size()
	top.position = Vector2(round((vs.x - top.size.x) * 0.5), 12)
	spawn.reset_size()
	spawn.position = Vector2(round((vs.x - spawn.size.x) * 0.5), 12)
	var status_bottom := top.position.y + top.size.y
	if spawn.is_visible_in_tree(): status_bottom = maxf(status_bottom, spawn.position.y + spawn.size.y)
	alert.reset_size()
	alert.position = Vector2(round((vs.x - alert.size.x) * 0.5), status_bottom + 10)
	# board / rank pill, top right
	board.reset_size()
	board.position = Vector2(vs.x - 12 - board.size.x, 12)
	board_pill.reset_size()
	board_pill.position = Vector2(vs.x - 12 - board_pill.size.x, 12)
	var right_bottom := board.position.y + board.size.y if board.visible else board_pill.position.y + board_pill.size.y
	atk.reset_size()
	var atk_top := right_bottom + 10
	# keep clear of the status pill when they would overlap horizontally
	if vs.x - 12 - atk.size.x < top.position.x + top.size.x + 8: atk_top = maxf(atk_top, status_bottom + 10)
	atk.position = Vector2(vs.x - 12 - atk.size.x, atk_top)
	# command bar, bottom centre
	bar.reset_size()
	bar.position = Vector2(round((vs.x - bar.size.x) * 0.5), vs.y - 12 - bar.size.y)
	# feed above the bar, left 16
	feed.reset_size()
	var fb := bar.position.y - 12
	if bar.position.x > 16 + FEED_W + 12: fb = vs.y - 16
	feed.position = Vector2(16, fb - feed.size.y)
	if menu: menu.size = vs
	if over: over.size = vs
	_in_layout = false

func process(dt: float) -> void:
	if root == null: return
	_shop_t += dt
	var ws := Vector2i(m.get_window().size) if m.get_window() else Vector2i.ZERO
	if ws != _last_ws:
		_last_ws = ws
		_dirty = true
	if shop_btn and shop_btn.is_visible_in_tree() and int((_shop_t - dt) / 2.4) != int(_shop_t / 2.4): shop_btn.queue_redraw()
	var target := float(m.share_i)
	if absf(slider_shown - target) > 0.001:
		slider_shown = lerpf(slider_shown, target, 1.0 - exp(-18.0 * dt))
		if absf(slider_shown - target) < 0.01: slider_shown = target
		cb_slider.queue_redraw()
	if st_bar: RK.fill_step(st_bar, dt)
	if cb_troops_bar: RK.fill_step(cb_troops_bar, dt)
	_flush_toasts()
	_tick_feed(dt)
	_tick_alert(dt)
	if m.state == "play" and m.nations.size() > m.PLAYER:
		cb_troops.text = m._fmt(m.shown_troops)
		cb_gold.text = m._fmt(m.shown_gold)
	if m.state == "pick" or m.state == "play":
		var cs := int(m.elapsed) if m.elapsed >= m.peace or m.state == "pick" else int(ceilf(m.peace - m.elapsed))
		if cs != _clock_s:
			_clock_s = cs
			refresh_top()
	if _dirty: layout()

func refresh_all(ema_regen: float, ema_gold: float, txt: bool) -> void:
	refresh_top()
	refresh_board()
	refresh_attacks()
	refresh_bar(ema_regen, ema_gold, txt)
	refresh_topbar()

# called on every state change (menu / pick / play / over)
func show_match() -> void:
	refresh_topbar()
	if m.state == "pick":
		board_open = false
		board.visible = false
		board_pill.visible = false
		clear_feed()
		if over: over.visible = false
	elif m.state == "play":
		board.visible = board_open
		board_pill.visible = not board_open
	else:
		board.visible = false
		board_pill.visible = false
		atk.visible = false
		alert.visible = false
		clear_feed()
		if menu and m.state == "menu": close_menu()
	layout()

# =============================================================================================
# Alliance card (EventFeed.luau alliance request / renew): violet glass card in the feed with a
# Primary Accept/Renew + Glass Ignore and an expiry bar. Fills main.gd's ally_card_* handles.
func build_ally_card() -> PanelContainer:
	var p := RK.glass(14, 12, RK.R_MD, 14)
	RK.glass_set(p, "accent", RK.VIOLET)
	RK.glass_set(p, "border", RK.c(RK.VIOLET, 0.35))
	p.custom_minimum_size = Vector2(FEED_W, 0)
	var v := RK.vbox(8)
	p.add_child(v)
	var h := RK.hbox(10)
	h.add_child(_disc(RK.VIOLET, "alliance"))
	var tv := RK.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var th := RK.hbox(6)
	var sw := RK.swatch(RK.TEXT, 10, 3)
	th.add_child(sw)
	var nm := RK.label("", 14, 700)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(nm)
	tv.add_child(th)
	var sub := RK.label("", 12, 500, RK.TEXT_2)
	tv.add_child(sub)
	h.add_child(tv)
	v.add_child(h)
	var bar_c := RK.fill_bar(3.0, RK.VIOLET)
	bar_c.custom_minimum_size = Vector2(0, 4)
	RK.fill_set(bar_c, 1.0, true)
	v.add_child(bar_c)
	var bh := RK.hbox(8)
	var a := RK.button("ACCEPT", "PrimaryButton", "", 34)
	a.add_theme_font_size_override("font_size", 13)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := RK.button("Ignore", "GlassButton", "", 34)
	b.add_theme_font_size_override("font_size", 13)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(a); bh.add_child(b)
	v.add_child(bh)
	wire(a); wire(b)
	feed.add_child(p)
	p.visible = false
	m.ally_card = p
	m.ally_card_lbl = nm
	m.ally_card_sub = sub
	m.ally_card_bar = bar_c
	m.ally_card_sq = sw
	m.ally_card_btn_a = a
	m.ally_card_btn_b = b
	return p

func set_ally_bar(v: float) -> void:
	var bc: Control = m.ally_card_bar
	bc.set_meta("v", v); bc.set_meta("target", v); bc.queue_redraw()

# =============================================================================================
# PauseMenu.luau: dim + glass card (22, 22, 18, 34), "GAME MENU" 20/800 spacing 3.
func build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	m.ui.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: close_menu())
	menu.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(cc)
	menu_panel = RK.glass(22, 22, 18, 34, Color(0.045, 0.065, 0.13, 0.94))
	menu_panel.custom_minimum_size = Vector2(380, 0)
	cc.add_child(menu_panel)
	var v := RK.vbox(10)
	menu_panel.add_child(v)
	var t := RK.label("GAME MENU", 20, 800, RK.TEXT, 3)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := RK.label("", 12, 500, RK.TEXT_3)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.name = "Sub"
	v.add_child(st)
	v.add_child(RK.gap(4))
	var resume := RK.button("RESUME", "PrimaryButton", "play", 50)
	resume.pressed.connect(close_menu)
	v.add_child(resume)
	var help := RK.button("How to play", "GlassButton", "help", 46)
	help.pressed.connect(func(): close_menu(); m.help_panel.visible = true)
	v.add_child(help)
	var sett := RK.button("Settings", "GlassButton", "settings", 46)
	sett.pressed.connect(func(): close_menu(); m._open_settings())
	v.add_child(sett)
	v.add_child(RK.hdivider())
	var leave := RK.button("LEAVE MATCH", "SurrenderButton", "exit", 46)
	leave.add_theme_font_size_override("font_size", 15)
	leave.pressed.connect(func(): close_menu(); m._to_menu())
	v.add_child(leave)
	var hint := RK.label("Esc to resume", 11, 600, RK.TEXT_3, 1)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	for b in [resume, help, sett, leave]: wire(b)
	menu.visible = false

func menu_open() -> bool:
	return menu != null and menu.visible

func open_menu() -> void:
	if menu == null: return
	if menu.visible: return
	var sub: Label = menu_panel.get_parent().get_parent().find_child("Sub", true, false)
	if sub: sub.text = "Match time %s  ·  %s of the world" % [RK.fmt_time(m.elapsed), RK.fmt_pct(m.nations[m.PLAYER].land / maxf(1.0, m.land_total))] if m.nations.size() > m.PLAYER else ""
	menu.visible = true
	menu.move_to_front()
	menu_panel.pivot_offset = menu_panel.size * 0.5
	RK.pop_in(menu_panel, 0.0, 0.94, 0.3)
	m.sfx("open", -6.0)

func close_menu() -> void:
	if menu == null or not menu.visible: return
	menu.visible = false
	m.sfx("close", -6.0)

# =============================================================================================
# GameOver.luau: kicker, 110/900 gradient title, subtitle, winner pill, stat cards, buttons.
const GRAD_SHADER := """
shader_type canvas_item;
uniform vec4 top_col : source_color = vec4(1.0);
uniform vec4 bot_col : source_color = vec4(1.0);
uniform float y0 = 0.0;
uniform float y1 = 130.0;
varying float vy;
void vertex() { vy = VERTEX.y; }
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float k = clamp((vy - y0) / max(1.0, y1 - y0), 0.0, 1.0);
	vec4 g = mix(top_col, bot_col, k);
	COLOR = vec4(g.rgb, t.a * COLOR.a);
}
"""

func build_over() -> void:
	over = Control.new()
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_STOP
	m.ui.add_child(over)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(cc)
	var v := RK.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(v)
	ov_kicker = RK.label("MATCH COMPLETE", 14, 700, RK.TEXT_2, 6)
	ov_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_kicker)
	ov_title = RK.label("VICTORY", 110, 900, Color.WHITE, 10)
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRAD_SHADER
	sm.shader = sh
	ov_title.material = sm
	v.add_child(ov_title)
	ov_sub = RK.label("", 18, 500, RK.TEXT_2)
	ov_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_sub)
	v.add_child(RK.gap(14))
	var wc := CenterContainer.new()
	wc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov_winner = PanelContainer.new()
	ov_winner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov_winner.add_theme_stylebox_override("panel", RK.flat(RK.c(RK.GOLD, 0.12), 999, RK.c(RK.GOLD, 0.45), 1, 16, 7))
	var wh := RK.hbox(8)
	ov_crown = RK.icon_rect("crown", 16, RK.GOLD)
	wh.add_child(ov_crown)
	ov_winner_sw = RK.swatch(RK.TEXT, 11, 3)
	wh.add_child(ov_winner_sw)
	ov_winner_name = RK.label("", 14, 700, RK.GOLD)
	wh.add_child(ov_winner_name)
	ov_winner.add_child(wh)
	wc.add_child(ov_winner)
	v.add_child(wc)
	v.add_child(RK.gap(22))
	ov_stats = RK.hbox(12)
	ov_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(ov_stats)
	v.add_child(RK.gap(26))
	var bh := RK.hbox(12)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	ov_stars = RK.button("+0", "GlassButton", "", 52)
	ov_stars.custom_minimum_size = Vector2(150, 52)
	ov_stars.add_theme_stylebox_override("normal", RK.flat(RK.c(RK.GOLD, 0.14), RK.R_MD, RK.c(RK.GOLD, 0.5), 1, 16, 8))
	ov_stars.add_theme_stylebox_override("hover", RK.flat(RK.c(RK.GOLD, 0.22), RK.R_MD, RK.GOLD, 1, 16, 8))
	ov_stars.add_theme_stylebox_override("pressed", RK.flat(RK.c(RK.GOLD, 0.1), RK.R_MD, RK.GOLD, 1, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]: ov_stars.add_theme_color_override(k, RK.GOLD)
	ov_stars.add_theme_font_override("font", RK.font(800))
	ov_stars.add_theme_font_size_override("font_size", 18)
	ov_stars.pressed.connect(func(): m._open_shop())
	bh.add_child(ov_stars)
	var again := RK.button("PLAY AGAIN", "PrimaryButton", "", 52)
	again.custom_minimum_size = Vector2(200, 52)
	again.pressed.connect(func(): over.visible = false; m._start_game_ui())
	bh.add_child(again)
	var back := RK.button("Return to title", "GlassButton", "", 52)
	back.custom_minimum_size = Vector2(200, 52)
	back.pressed.connect(func(): over.visible = false; m._to_menu())
	bh.add_child(back)
	for b in [ov_stars, again, back]: wire(b)
	v.add_child(bh)
	v.add_child(RK.gap(14))
	ov_next = RK.label("", 12, 600, RK.TEXT_3, 1)
	ov_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ov_next)
	over.visible = false

func _stat_card(icon: String, value: String, cap: String, col: Color) -> PanelContainer:
	var p := RK.glass(16, 14, 14, 16)
	p.custom_minimum_size = Vector2(150, 0)
	var v := RK.vbox(4)
	p.add_child(v)
	var ic := RK.icon_rect(icon, 20, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := RK.label(value, 26, 800)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var c := RK.caption(cap, 10)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	return p

# d: title, sub, winner_id, peak, troops, kills, duration, stars, next
func show_over(win: bool, d: Dictionary) -> void:
	if over == null: build_over()
	var title: String = d.get("title", "VICTORY" if win else "DEFEAT")
	ov_title.text = title
	var top_c := Color(1.0, 0.97, 0.85)
	var bot_c := RK.GOLD.darkened(0.05)
	if title != "VICTORY":
		top_c = Color(1.0, 0.8, 0.8); bot_c = RK.RED.darkened(0.1)
	var sm: ShaderMaterial = ov_title.material
	sm.set_shader_parameter("top_col", top_c)
	sm.set_shader_parameter("bot_col", bot_c)
	var lh := ov_title.get_combined_minimum_size().y
	sm.set_shader_parameter("y0", lh * 0.22)
	sm.set_shader_parameter("y1", lh * 0.82)
	ov_sub.text = d.get("sub", "")
	var wid: int = int(d.get("winner_id", -1))
	ov_winner.get_parent().visible = wid > 0
	if wid > 0:
		var n = m.nations[wid]
		RK.set_swatch(ov_winner_sw, n.color)
		ov_winner_name.text = ("You won the match" if wid == m.PLAYER else "%s won the match" % n.name)
	for c in ov_stats.get_children(): c.queue_free()
	ov_stats.add_child(_stat_card("globe", d.get("peak", ""), "Peak land", RK.CYAN))
	ov_stats.add_child(_stat_card("troops", d.get("troops", ""), "Peak troops", RK.AMBER))
	ov_stats.add_child(_stat_card("skull", d.get("kills", ""), "Nations eliminated", RK.RED))
	ov_stats.add_child(_stat_card("clock", d.get("duration", ""), "Duration", RK.TEXT_2))
	ov_stars.text = "★ " + str(d.get("stars", "+0"))
	ov_next.text = d.get("next", "")
	ov_next.visible = ov_next.text != ""
	over.visible = true
	over.move_to_front()
	for i in over.get_child(1).get_child(0).get_child_count():
		var ch = over.get_child(1).get_child(0).get_child(i)
		if ch is Control:
			ch.modulate.a = 0.0
			var tw: Tween = ch.create_tween()
			tw.tween_interval(0.08 + i * 0.05)
			tw.tween_property(ch, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ov_title.pivot_offset = ov_title.size * 0.5
	ov_title.scale = Vector2(1.12, 1.12)
	ov_title.create_tween().tween_property(ov_title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
