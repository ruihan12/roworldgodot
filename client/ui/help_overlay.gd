# Port of src/client/UI/HelpOverlay.luau (scripts/ui/help_overlay.gd, UIHelpOverlay).
# "How to play" overlay: illustrated sections (spawn, expand & attack, boats, economy, nukes,
# alliances, victory) and the controls. Scrolls on small screens.
#
# Upstream's own Scroll and Grid containers are Godot's ScrollContainer and GridContainer here.
# The key lists and the credits are this port's (its keys differ from the Roblox client's, and the
# notice names this port); the sections are upstream's.
class_name HelpOverlay
extends Control

signal closed

const SECTIONS := [
	{"icon": "target", "color": "amber", "title": "Pick your start",
		"text": "Click any unclaimed land to place your capital. Solo games deploy 5 seconds after you choose; until then you can move it."},
	{"icon": "attack", "color": "orange", "title": "Expand & attack",
		"text": "Click neutral land beside you to expand, or a nation you border to attack it. The Attack bar sets the share of troops you send (Q / E). Troops regrow on their own, fastest well below your cap."},
	{"icon": "boat", "color": "cyan", "title": "Boats",
		"text": "Click a coast you can't reach by land and a transport sails from your nearest shore, landing troops for a beachhead. Warships (built from a Port) patrol where you send them: they hit transports first, then warships, then trade ships, which they capture for gold. Below {ws_retreat}% health a warship returns to port and heals near your ports; kills earn it veterancy. Click one of yours, then the sea, to move it.{post_shoot}"},
	{"icon": "alliance", "color": "violet", "title": "Alliances & betrayal",
		"text": "Right-click a nation to propose an alliance. Allies can't attack each other and can donate troops. Breaking an alliance brands you a Traitor for {traitor_s} s: everyone knows, and attacks against you cost only {traitor_def}% of the troops and land faster."},
	{"icon": "city", "color": "gold", "title": "Build your economy", "builds": true, "wide": true,
		"text": "Gold flows from your land, factories and trade. Structures get pricier the more you own and need room ({spacing} tiles apart); place them on your own land with the command bar (1 – 7). Land near a Defense Post costs attackers {def_mag}× the troops and {def_cost}× the time."},
	{"icon": "atom", "color": "red", "title": "Nukes & SAMs",
		"text": "A Missile Silo lets you launch Atom bombs, Hydrogen bombs and MIRVs. Blasts erase troops and structures and leave fallout: land that stays poisoned until someone re-conquers it, slowly and at a high cost. SAM Launchers shoot down bombs aimed inside their range ({sam_r} tiles); MIRV warheads can't be stopped."},
	{"icon": "crown", "color": "gold", "title": "Win at 80%",
		"text": "Hold {win}% of the world's land to win (fallout doesn't count). Lose all your land and you're out."},
]

## The "Credits & licence" card, last: the AGPL's Appropriate Legal Notices and the credits.
const LEGAL := [
	"Frontline Conquest is a modified version of RoWorld, which is a modified version of OpenFront. © OpenFront and Contributors. RoWorld changes © 2026 Snick Co.",
	"It is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License, version 3, with the additional terms in its LICENSE file. It comes with ABSOLUTELY NO WARRANTY. The licence comes with the source code.",
	"Maps made with Natural Earth and NOAA ETOPO1 data (public domain). Country flags from Wikimedia Commons (public domain). Music by Rodrigo Flores.",
	"Not affiliated with or endorsed by OpenFront or RoWorld.",
]
const SOURCE_REPO := "ruihan12/Frontline-Conquest"
const SOURCE_TIP := {"title": "Source code", "body": "Source available on the github website under " + SOURCE_REPO}
const SOURCE_TIP_S := 4.0

const KEYS_DESKTOP := [
	["Click", "Expand, attack or send a boat"],
	["Right-click", "Diplomacy menu"],
	["Drag", "Pan the map"],
	["WASD / Arrows", "Pan the map"],
	["Wheel", "Zoom"],
	["1 – 0", "Build & nukes"],
	["R", "Reinforcements"],
	["I", "ICBM mode"],
	["Q / E", "Attack share −/+"],
	["Space", "Attack at cursor"],
	["Backspace", "Retreat your latest attack"],
	["− / +", "Game speed"],
	["Esc / Right-click", "Cancel · game menu"],
	["H", "This help"],
	["Tab", "Leaderboard"],
	["F2 / Esc then Tab", "Console (owner only)"],
	["Click a warship", "Then click the sea to move it"],
]
const KEYS_TOUCH := [
	["Tap", "Expand, attack or send a boat"],
	["Long-press", "Action menu"],
	["Drag", "Pan the map"],
	["Pinch", "Zoom"],
	["Tap a slot", "Tap the map, then confirm"],
	["Tap your land", "Inspect"],
	["Tap a warship", "Then tap the sea to move it"],
	["Tap an ally", "Donate or break the alliance"],
]
const COLORS := {"amber": UITheme.AMBER, "orange": UITheme.ORANGE, "cyan": UITheme.CYAN, "gold": UITheme.GOLD, "red": UITheme.RED, "violet": UITheme.VIOLET}

var ctx: UICtx
var is_open := false
var _built_compact := -1
var _scroll: ScrollContainer = null
var _dim: ColorRect
var _panel: GlassPanel
var _tip_serial := 0


static func _col(n: String) -> Color:
	return COLORS.get(n, UITheme.TEXT)


## Numbers in the help text come from Rules, so the text follows balance changes.
func _fill_rules(text: String) -> String:
	var R: SimRules = ctx.rules.rules()
	return UIRules.format(text, {
		"traitor_s": str(Defs.round_i(float(SimRules.TRAITOR_TICKS) / SimRules.TICK_RATE)),
		"traitor_def": str(Defs.round_i(SimRules.TRAITOR_DEFENSE_DEBUFF * 100.0)),
		"spacing": str(Defs.round_i(R.struct_min_dist)),
		"def_mag": str(Defs.round_i(SimRules.DEFENSE_POST_MAG)),
		"def_cost": str(Defs.round_i(SimRules.DEFENSE_POST_COST)),
		"sam_r": str(Defs.round_i(R.sam_range(1))),
		"ws_retreat": "75",
		"post_shoot": " Defense Posts also fire on enemy boats in range." if SimRules.DEFENSE_POST_SHOOTS else "",
		"win": str(Defs.round_i(SimRules.WIN_SHARE * 100.0)),
	})


func _init(c: UICtx) -> void:
	ctx = c
	name = "HelpOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.05, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		# (only a press outside the window closes)
		if e is InputEventMouseButton and e.pressed and not _panel.get_global_rect().has_point(e.global_position):
			close())
	add_child(_dim)
	_panel = GlassPanel.new(0.0, 0.0, 18, true, 34)
	_panel.set_tint(Color(0.045, 0.065, 0.13, 0.94))
	add_child(_panel)


func _build() -> void:
	var T := UITheme
	for ch in _panel.get_children():
		_panel.remove_child(ch)
		ch.queue_free()
	var compact := ctx.compact
	_built_compact = 1 if compact else 0
	var v := T.vbox(0)
	_panel.add_child(v)
	# Header
	var hm := MarginContainer.new()
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		hm.add_theme_constant_override("margin_" + side, 28 if not compact else 16)
	hm.add_theme_constant_override("margin_top", 22 if not compact else 12)
	hm.add_theme_constant_override("margin_bottom", 14 if not compact else 8)
	var head := T.hbox(14)
	hm.add_child(head)
	var hic := T.icon_rect("help", 28.0 if not compact else 22.0, T.AMBER)
	hic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hic)
	var tv := T.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(T.label("HOW TO PLAY", 24 if not compact else 18, 800, T.TEXT, 3))
	var paused := ctx.mode() == UICtx.MODE_SOLO and ctx.in_match()
	tv.add_child(T.label("Conquer the real world in seven ideas." + ("  ·  Game paused" if paused else ""), 13, 500, T.TEXT_2))
	head.add_child(tv)
	var close_b := T.button("", "GlassButton", "close", 44.0)
	close_b.expand_icon = true
	close_b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_b.add_theme_constant_override("icon_max_width", 14)
	close_b.custom_minimum_size = Vector2(44, 44)
	close_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_b.pressed.connect(close)
	head.add_child(close_b)
	v.add_child(hm)
	v.add_child(T.hdivider())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	v.add_child(scroll)
	var body_m := MarginContainer.new()
	body_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side2 in ["left", "right"]:
		body_m.add_theme_constant_override("margin_" + side2, 24 if not compact else 12)
	body_m.add_theme_constant_override("margin_top", 18 if not compact else 10)
	body_m.add_theme_constant_override("margin_bottom", 22 if not compact else 12)
	scroll.add_child(body_m)
	var body := T.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_m.add_child(body)
	# Two cards per row on wide screens; "wide" sections span the full row.
	var row: HBoxContainer = null
	for i in SECTIONS.size():
		var d: Dictionary = SECTIONS[i]
		var card := _section(i + 1, d)
		if compact or d.get("wide", false):
			body.add_child(card)
			row = null
			continue
		if row == null:
			row = T.hbox(14)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(row)
		row.add_child(card)
		if row.get_child_count() >= 2:
			row = null
	body.add_child(_controls())
	body.add_child(_legal())
	body.add_child(_source())


static func _card_panel(mh: float, mv: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UITheme.flat(Color(1, 1, 1, 0.035), 12, Color(1, 1, 1, 0.07), 1, mh, mv))
	return card


func _section(n: int, d: Dictionary) -> PanelContainer:
	var T := UITheme
	var c := _col(d.color)
	var card := _card_panel(16.0, 14.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := T.hbox(14)
	card.add_child(h)
	h.add_child(_medallion(d.icon, c))
	var v := T.vbox(5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tr := T.hbox(8)
	var num := T.label("%02d" % n, 12, 800, c, 1)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(num)
	tr.add_child(T.label(d.title, 16, 700))
	v.add_child(tr)
	var body := _fill_rules(d.text)
	if ctx.touch:
		body = body.replace("Right-click", "Long-press").replace("Click", "Tap").replace("click", "tap")
		body = body.replace(" (Q / E)", "").replace(" with the command bar (1 – 7)", " with BUILD")
	var t := T.label(body, 13, 500, T.TEXT_2)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(220, 0)
	v.add_child(t)
	if d.get("builds", false):
		var g := GridContainer.new()
		g.columns = 1 if ctx.compact else 2
		g.add_theme_constant_override("h_separation", 18)
		g.add_theme_constant_override("v_separation", 8)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in UIRules.BUILD_KINDS:
			var item := T.hbox(10)
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.custom_minimum_size = Vector2(30, 30)
			chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			chip.add_theme_stylebox_override("panel", T.flat(T.c(T.GOLD, 0.1), 8, T.c(T.GOLD, 0.3), 1))
			var ic := T.icon_rect(k, 16.0, T.GOLD)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(ic)
			item.add_child(chip)
			var tv := T.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_child(T.label(UIRules.TITLES[k], 13, 700))
			var bl := T.label(ctx.rules.blurb(k), 12, 500, T.TEXT_3)
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(180, 0)
			tv.add_child(bl)
			item.add_child(tv)
			g.add_child(item)
		v.add_child(g)
	h.add_child(v)
	return card


## Round icon medallion with a coloured glow (a StyleBoxFlat shadow in the section colour).
func _medallion(icon_name: String, c: Color) -> Control:
	var T := UITheme
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.custom_minimum_size = Vector2(52, 52)
	var sb := T.flat(T.c(c, 0.14), 25, T.c(c, 0.55), 1)  # (radius = exactly half the size left cross-shaped seams in the AA edge)
	sb.shadow_color = T.c(c, 0.18)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	var ic := T.icon_rect(icon_name, 26.0, c)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	return p


func _controls() -> PanelContainer:
	var T := UITheme
	var card := _card_panel(18.0, 16.0)
	var v := T.vbox(12)
	card.add_child(v)
	var hr := T.hbox(10)
	var lic := T.icon_rect("layers", 18.0, T.CYAN)
	lic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(lic)
	hr.add_child(T.label("CONTROLS", 14, 800, T.TEXT, 2))
	v.add_child(hr)
	var cols: BoxContainer = T.vbox(16) if ctx.compact else T.hbox(32)
	v.add_child(cols)
	cols.add_child(_key_list("Mouse & keyboard", KEYS_DESKTOP))
	cols.add_child(_key_list("Touch", KEYS_TOUCH))
	return card


func _legal() -> PanelContainer:
	var T := UITheme
	var card := _card_panel(18.0, 16.0)
	var v := T.vbox(8)
	card.add_child(v)
	v.add_child(T.label("CREDITS & LICENCE", 14, 800, T.TEXT, 2))
	for para in LEGAL:
		var t := T.label(para, 12, 500, T.TEXT_3)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(220, 0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(t)
	return card


## "Source  [<GitHub mark> repo]", centred below the credits card; pressing the repo name pops up
## where to find it (SOURCE_TIP).
func _source() -> HBoxContainer:
	var T := UITheme
	var row := T.hbox(4)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cap := T.label("Source", 13, 500, T.TEXT_3)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	var b := T.button(SOURCE_REPO, "GhostButton", "github", 40.0)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("icon_max_width", 18)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: _show_source_tip(b))
	row.add_child(b)
	return row


func _show_source_tip(b: Control) -> void:
	ctx.show_hint(b, SOURCE_TIP, true)
	_tip_serial += 1
	var serial := _tip_serial
	get_tree().create_timer(SOURCE_TIP_S).timeout.connect(func() -> void:
		if _tip_serial == serial:
			ctx.hide_hint(b))


## Key cap: white 0.09, r 6, border white 0.2, 1 px, a 2 px bottom border.
static func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.flat(Color(1, 1, 1, 0.09), 6, Color(1, 1, 1, 0.2), 1, 8.0, 2.0)
	sb.border_width_bottom = 2
	sb.content_margin_bottom = 3.0
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cap.add_child(UITheme.label(text, 11, 700, UITheme.TEXT))
	return cap


func _key_list(title: String, keys: Array) -> VBoxContainer:
	var v := UITheme.vbox(7)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UITheme.caption(title, 11, UITheme.TEXT_3))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 6)
	for k in keys:
		g.add_child(_keycap(k[0]))
		var d := UITheme.label(k[1], 13, 500, UITheme.TEXT_2)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(d)
	v.add_child(g)
	return v


func apply_layout() -> void:
	if is_open and _built_compact != (1 if ctx.compact else 0):
		_build()
	_place()


func _place() -> void:
	var area := ctx.clear_rect()
	var margin_x := 24.0 if not ctx.compact else 8.0
	var margin_y := 28.0 if not ctx.compact else 6.0
	var w := minf(1080.0, area.size.x - margin_x * 2.0)
	var h := minf(820.0, area.size.y - margin_y * 2.0)
	var p := area.position + (area.size - Vector2(w, h)) * 0.5
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.position = Vector2(floorf(p.x + 0.5), floorf(p.y + 0.5))
	_panel.size = Vector2(w, h)


func open() -> void:
	if is_open:
		return
	is_open = true
	_build()
	_place()
	visible = true
	modulate.a = 1.0
	_panel.modulate.a = 1.0
	_dim.modulate.a = 0.0
	UIFx.fade(_dim, 1.0, 0.25)
	UIFx.pop_in(_panel, 0.0, 0.95, 0.35)
	ctx.sfx("open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	ctx.sfx("close")
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "modulate:a", 0.0, 0.2)
	t.tween_property(_panel, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(func() -> void:
		if not is_open:
			visible = false)
	closed.emit()


func scroll_by(px: float) -> void:
	if _scroll != null:
		_scroll.scroll_vertical += int(px)
