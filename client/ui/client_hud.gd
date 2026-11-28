# The remade client's HUD host: owns the UICtx, the GameState / Session facades and the HUD parts
# ported from upstream so far, and places them over the game. It grows into the port of
# src/client/UI/UIRoot.luau as the remaining parts arrive; until then the parts not yet ported are
# still drawn by ui_upstream/rw_hud.gd.
class_name ClientHud
extends Node

const LobbyWindow := preload("res://client/ui/lobby.gd")
const NetLobbyModel := preload("res://net/net_lobby_model.gd")
const AccountWindow := preload("res://client/ui/account.gd")

var g  # main.gd
var ctx: UICtx
var root: Control
var bar: CommandBar
var icbm: IcbmSlot
var tooltip: Tooltip
var top: TopStatus
var board: Leaderboard
var attacks: AttacksPanel
var feed: EventFeed
var alert: AlertBanner
var spawn: SpawnOverlay
var waiting: WaitingRoom
var topbar: ClientTopbar
var pause: PauseMenu
var over: GameOver
var help: HelpOverlay
var interact: UIInteract
var radial: RadialMenu
var float_layer: Control
var title: TitleScreen
var target_card: TargetCard
var place_confirm: PlaceConfirm
var hold_ring: HoldRing
var busy: BusyChip
var spectate_pill: GlassPanel
var _spec_sub: Label
var coach: Coach
var advisor: UIAdvisor
var tutorial: Tutorial
var arsenal: Arsenal
var crates: Crates
var account: AccountWindow
var lobby: LobbyWindow
var _tutorial_at := -1.0
const TUTORIAL_DELAY_S := 0.9
var _advise_t := 0.0
var unit_card: UnitCard
var map_picker: MapPicker
var next_match: NextMatch
var _next_shown := false
var _next_at := 0
var _next_from := ""
var _next_going := ""
var _hover_seen := -2
var _state_seen := ""
var _seen_nukes := {}
var _pending_toasts: Array = []
var _phase := -1
var _in_layout := false
var _stats_t := 0.0
var _growth_t := 0.0
var _was_play := false
var _syncing := false


## A phone or tablet: touch as the main pointer. Web: the browser says a coarse pointer and touch points (iPadOS
## Safari included); ?touch=1 / --touch force it for tests.
func _detect_touch() -> bool:
	if "--touch" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(String(window.location.search||'').indexOf('touch=1')>=0) || ((navigator.maxTouchPoints||0)>0 && matchMedia('(pointer:coarse)').matches)", true)
		return bool(v)
	return OS.has_feature("mobile")


## Web: the browser reports touch points (an iPad in desktop-site mode or with a trackpad still does).
func _has_touch_points() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("(navigator.maxTouchPoints||0)>1", true))


func setup(main, layer: Node, at_index: int = -1) -> void:
	g = main
	ctx = UICtx.new()
	ctx.state = RWGameState.new(main)
	ctx.session = RWSession.new(main)
	ctx.audio = RWAudio.new(main)
	ctx.world = MapView.new(main)
	ctx.borders = RWBorders.new(ctx.state)
	ctx.reload_settings()
	# upstream UIRoot: touch_device = touch and no mouse; ctx.touch starts as that (select-then-confirm orders, the
	# placement ghost with confirm buttons, bigger rows, "tap" wording). Was never set in the port until 2026-11-26.
	ctx.touch_device = _detect_touch()
	ctx.touch = ctx.touch_device
	UITheme.min_font_size = 12 if ctx.touch else 0
	root = Control.new()
	root.name = "ClientHud"
	# UIRoot: every button clicks when pressed and ticks under the pointer (BuildButtons and leaderboard
	# rows click quieter and do not tick)
	main.get_tree().node_added.connect(_hook_button_sfx)
	root.theme = UITheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	if at_index >= 0:
		layer.move_child(root, at_index)
	ctx.root = root

	# The title screen sits under every other part (the top bar, help and settings draw over it).
	title = TitleScreen.new(ctx, main)
	root.add_child(title)
	title.play_solo.connect(func(d: int) -> void:
		g.diff_i = d
		g._start_game_ui())
	title.show_help.connect(toggle_help)
	title.open_arsenal.connect(func() -> void: open_arsenal(null, "title"))
	title.open_crates.connect(func() -> void: crates.open())
	# The party hub: its own connection to the game server, opened from the title screen (save.settings.party_on).
	var party_model = null
	if bool(main.save.get("settings", {}).get("party_on", true)):
		party_model = PartyNetModel.new(main, str(main.save.get("settings", {}).get("server_url", NetLobbyModel.DEFAULT_URL)), str(main.save.settings.get("guest_name", ctx.username())))
		title.party.bind(party_model)
		title.party.notice.connect(func(t: String) -> void: main.notify(t, "bad"))
		party_model.notice.connect(func(t: String) -> void: main.notify(t, "bad"))
		main.add_child(PartyNet.new(party_model))
	title.open_account.connect(func() -> void: account.open())
	title.open_multiplayer.connect(func() -> void: lobby.open())

	if ctx.touch_device or _has_touch_points():  # iPadOS asks for the desktop site and may report a fine pointer (trackpad)
		root.add_child(MemOverlay.new(main))  # phones/tablets: memory readout (iOS tab kills), see client/ui/mem_overlay.gd
	top = TopStatus.new(ctx)
	root.add_child(top)
	top.visible = false
	board = Leaderboard.new(ctx)
	root.add_child(board)
	board.visible = false
	attacks = AttacksPanel.new(ctx)
	root.add_child(attacks)
	attacks.visible = false
	spawn = SpawnOverlay.new(ctx)
	root.add_child(spawn)
	spawn.visible = false
	waiting = WaitingRoom.new(ctx, g)
	root.add_child(waiting)
	feed = EventFeed.new(ctx)
	root.add_child(feed)
	alert = AlertBanner.new(ctx)
	root.add_child(alert)
	topbar = ClientTopbar.new(self)
	root.add_child(topbar)
	over = GameOver.new(ctx)
	root.add_child(over)
	over.play_again.connect(func() -> void:
		over.close()
		g._start_game_ui())
	over.to_title.connect(func() -> void:
		over.close()
		g._to_menu())
	over.open_arsenal.connect(func(key, from) -> void: open_arsenal(key, from))
	over.spectate.connect(_keep_watching)
	# NEXT MATCH, over the results of a new player's first match (UIRoot: UI/NextMatch)
	next_match = NextMatch.new(ctx)
	root.add_child(next_match)
	next_match.solo.connect(func() -> void: _next_match_go("solo"))
	next_match.closed.connect(func() -> void: _next_going = "")
	over.opened.connect(_maybe_next_match)
	spectate_pill = _build_spectate_pill()
	root.add_child(spectate_pill)
	help = HelpOverlay.new(ctx)
	root.add_child(help)
	help.closed.connect(_update_pause)
	pause = PauseMenu.new(ctx)
	root.add_child(pause)
	pause.closed.connect(_update_pause)
	pause.help_requested.connect(toggle_help)
	pause.leave_requested.connect(func() -> void:
		_update_pause()
		g._to_menu())
	pause.restart_requested.connect(func() -> void:
		_update_pause()
		g._start_game_ui())
	pause.music_toggled.connect(func(on: bool) -> void:
		ctx.set_music(on)
		topbar.refresh())
	pause.music_volume_changed.connect(func(v: float, final: bool) -> void: ctx.set_music_volume(v, final))
	pause.next_match_preview.connect(func() -> void: open_next_match("preview"))
	pause.pops_toggled.connect(func(on: bool) -> void: ctx.set_pops(on))
	# "Replay as new player": the tutorial and the match count start over, and the tutorial runs from the title
	pause.new_player_requested.connect(func() -> void:
		ctx.set_setting("tutorial", "")
		ctx.set_setting("matches", 0)
		ctx.set_setting("tutorial_off", false)
		if g.state == "menu":
			start_tutorial())
	top.rank_provider = board.my_rank
	top.tapped.connect(func() -> void:
		if ctx.compact:
			board.toggle())
	board.toggled.connect(func(_on: bool) -> void: layout())
	attacks.toggled.connect(func(_c: bool) -> void: layout())
	attacks.retreat_requested.connect(_on_retreat)
	for c in [top.panel, board.panel, board._pill, attacks.panel, spawn.panel]:
		c.resized.connect(_queue_layout)
		c.visibility_changed.connect(_queue_layout)

	bar = CommandBar.new(ctx)
	icbm = IcbmSlot.new(ctx)
	bar.port_slots = [icbm]
	root.add_child(bar)
	bar.visible = false
	bar.build_chosen.connect(_on_build_chosen)
	bar.arsenal_wanted.connect(func(key, from) -> void: open_arsenal(key, from))
	bar.slots_changed.connect(layout)
	ctx.ratio_changed.connect(_on_ratio_changed)
	tooltip = Tooltip.new(ctx)
	root.add_child(tooltip)
	ctx.tooltip = tooltip
	float_layer = Control.new()
	float_layer.name = "Floats"
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(float_layer)
	radial = RadialMenu.new(ctx)
	root.add_child(radial)
	radial.bottom_limit = func() -> float: return bar.top_edge() if bar.visible else ctx.vp.y
	interact = UIInteract.new(ctx)
	interact.tooltip = tooltip
	interact.radial = radial
	interact.bar = bar
	interact.float_layer = float_layer
	radial.picked.connect(interact.on_radial)
	target_card = TargetCard.new(ctx)
	target_card.bar = bar
	root.add_child(target_card)
	root.move_child(target_card, bar.get_index() + 1)
	unit_card = UnitCard.new(ctx)
	unit_card.bar = bar
	root.add_child(unit_card)
	root.move_child(unit_card, bar.get_index() + 1)
	place_confirm = PlaceConfirm.new(ctx)
	place_confirm.bar = bar
	root.add_child(place_confirm)
	root.move_child(place_confirm, bar.get_index() + 1)
	place_confirm.blockers = func() -> Array: return [top.panel.get_global_rect()] if top.visible else []
	place_confirm.confirmed.connect(func() -> void: interact.confirm_ghost())
	place_confirm.cancelled.connect(func() -> void: interact.cancel_aim())
	interact.place_confirm = place_confirm
	hold_ring = HoldRing.new(ctx)
	root.add_child(hold_ring)
	busy = BusyChip.new(ctx)
	root.add_child(busy)
	# Coach marks and the advisor that offers them (UIRoot's wiring).
	coach = Coach.new(ctx)
	root.add_child(coach)
	root.move_child(coach, bar.get_index() + 1)
	ctx.coach = coach
	coach.blockers = func() -> Array:
		var out := []
		for c in [top.panel, board.panel, attacks.panel, bar.panel, bar.tray, bar._place_chip, alert.panel, spawn.panel]:
			if c != null and c.is_visible_in_tree():
				out.append(c.get_global_rect())
		out.append(feed.stack_rect())
		return out
	coach.keepout = func() -> Array:
		var r = g.names.local_label_rect() if g.names != null else null
		return [r] if r is Rect2 else []
	advisor = UIAdvisor.new(self)
	ctx.floor_held.connect(advisor.on_floor_held)
	ctx.ratio_changed.connect(func(_r) -> void:
		if screen() == "play":
			coach.complete("ratio"))
	pause.tips_reset.connect(coach.reset)
	tutorial = Tutorial.new(ctx, self)
	root.add_child(tutorial)
	root.move_child(tutorial, coach.get_index() + 1)
	tutorial.closed.connect(func() -> void: coach.muted = false)
	tutorial.finished.connect(func(how: String) -> void:
		ctx.set_setting("tutorial", how)
		if how == "done":
			# what the steps taught is not said again as a tip
			for id in ["expand", "ratio", "city", "contact", "select"]:
				coach.complete(id)
			# (port) the tutorial's Stars go into this port's save
			g.save.stars = int(g.save.get("stars", 0)) + Tutorial.STARS
			g.write_save())
	_check_new_player("--tutorial" in OS.get_cmdline_user_args())
	interact.target_card = target_card
	interact.ui = self
	interact.unit_card = unit_card
	target_card.fire.connect(interact.fire_from_card)
	target_card.ally.connect(interact.ally_from_card)
	target_card.betray.connect(interact.betray_from_card)
	target_card.donate.connect(interact.donate_from_card)
	target_card.closed.connect(func() -> void: ctx.world_call("set_selected_owner", [0]))
	unit_card.closed.connect(func() -> void: ctx.world_call("set_selected_unit", [-1]))
	arsenal = Arsenal.new(ctx, main)
	root.add_child(arsenal)
	crates = Crates.new(ctx, main)
	root.add_child(crates)
	account = AccountWindow.new(ctx, main)
	root.add_child(account)
	if party_model != null:
		account.display_name_changed.connect(party_model.set_display_name)
	var net_lobby := NetLobbyModel.new(main)
	if party_model != null:
		net_lobby.bind_party(party_model)
	lobby = LobbyWindow.new(ctx, main, net_lobby)
	root.add_child(lobby)
	map_picker = MapPicker.new(ctx, main)
	root.add_child(map_picker)
	title.pick_map.connect(func() -> void: map_picker.open(UIMaps.selected(g)))
	map_picker.picked.connect(func(id: String) -> void: title.set_map_name(UIMaps.name_of(g, id)))
	root.resized.connect(layout)
	layout()


var _layout_queued := false


func _queue_layout() -> void:
	if _in_layout or _layout_queued:
		return
	_layout_queued = true
	_do_queued.call_deferred()


func _do_queued() -> void:
	_layout_queued = false
	layout()


## UIRoot._layout: metrics, then each part.
func layout() -> void:
	if root == null or _in_layout:
		return
	_in_layout = true
	var vp := root.size
	if vp.x < 10:
		vp = Vector2(1600, 900)
	ctx.vp = vp
	ctx.compact = vp.y < 560.0 or vp.x < 900.0
	# (the single-row bar: ten slots, plus the Arsenal's SHOP slot and a slot per unlocked kind)
	ctx.wide = vp.x >= 1420.0 + bar.extra_width() + 62.0 * bar.port_slots.size()
	# the top-left corner belongs to the top-bar buttons (and the speed chip under them)
	topbar.layout()
	var tr := topbar.topbar_rect()
	ctx.airship_bar = Rect2(0, 0, tr.end.x + 8.0, tr.end.y + 2.0)
	ctx.reserved_top_left = Rect2(0, 0, tr.end.x + 8.0, tr.end.y + 8.0)
	title.apply_layout()
	if next_match != null and next_match.is_open:
		next_match.apply_layout()
	if map_picker != null:
		map_picker.apply_layout()
	if arsenal != null:
		arsenal.apply_layout()
	if crates != null:
		crates.apply_layout()
	if account != null:
		account.apply_layout()
	if lobby != null:
		lobby.apply_layout()
	top.apply_layout()
	spawn.apply_layout()
	waiting.apply_layout()
	if coach != null:
		coach.apply_layout()
	if tutorial != null:
		tutorial.apply_layout()
	bar.apply_layout()
	# Leaderboard: top-right, dropping below the status pill / spawn banner when they would touch.
	var board_top := 12.0 + ctx.insets.y
	var board_w := 250.0 if ctx.compact else 300.0
	var board_left := vp.x - 12.0 - ctx.insets.z - board_w
	var blockers: Array[Control] = []
	if top.visible:
		blockers.append(top.panel)
	if spawn.visible:
		blockers.append(spawn.panel)
	for b in blockers:
		var r := b.get_global_rect()
		if r.end.x + 12.0 > board_left:
			board_top = maxf(board_top, r.end.y + 10.0)
	board.apply_layout(board_top)
	# Phones: when the status pill had to drop below the top bar, the rank pill sits beside it.
	if ctx.compact and top.visible and not board.expanded:
		var tr2 := top.panel.get_global_rect()
		var pill_w := board._pill.get_combined_minimum_size().x
		var min_x := ctx.insets.x + 8.0 if tr2.position.y >= ctx.reserved_top_left.end.y else ctx.reserved_top_left.end.x + 8.0
		if tr2.position.x - 8.0 - pill_w >= min_x:
			board.place_pill_left_of(tr2)
	var attacks_top := maxf(board.bottom_edge() if board.visible else 0.0, top.bottom_edge() if top.visible else 0.0) + 10.0
	attacks.tray_open = bar.tray.visible
	attacks.apply_layout(attacks_top, (bar.top_edge() if bar.visible else vp.y - ctx.insets.w) - 8.0)
	if attacks.visible:
		attacks.refresh()
	var bar_top := bar.top_edge() if bar.visible else vp.y - ctx.insets.w
	# (UIRoot: the feed sits above the bar; beside it when the bar leaves the left edge free)
	if bar.visible and bar.panel.position.x > 16.0 + 340.0 + 12.0:
		bar_top = vp.y - ctx.insets.w - 4.0
	feed.apply_layout(bar_top - 12.0)
	_layout_alert()
	if pause.is_open:
		pause.apply_layout()
	if over.is_open:
		over.apply_layout()
	if help.is_open:
		help.apply_layout()
	ctx.layout_changed.emit()
	_in_layout = false


## The match ended for the player (main.show_end). `earned`: the Stars this match paid, already added
## to the balance.
func show_over(win: bool, eliminated: bool, leader: int, earned: int) -> void:
	ctx.set_setting("matches", int(ctx.setting("matches", 0)) + 1)
	coach.clear()
	var st: Dictionary = g.stats
	var me: int = g.PLAYER
	var lines: Array = g.star_lines
	ctx.session.last_award = {"total": earned, "balance": int(g.save.stars), "lines": lines}
	var kind := "victory" if win else ("eliminated" if eliminated else "defeat")
	var killer := int(g.nations[me].get("last_by", 0)) if eliminated else 0
	var winner := me if win else leader
	var reason := Defs.OVER_DOMINATION if (winner > 0 and ctx.win_share(winner) >= SimRules.WIN_SHARE - 0.0005) else -1
	over.open(kind, winner, killer, {
		"peak_share": float(st.get("peak", 0.0)) / 100.0,
		"max_troops": float(st.get("maxtroops", 0.0)),
		"kills": int(st.get("elims", 0)),
		"duration_s": float(g.elapsed),
		"match_s": float(g.elapsed),
	}, reason)
	over.move_to_front()


## UIRoot._maybe_next_match: a new player's first match (a solo one) ended: NEXT MATCH, once,
## NextMatch.DELAY_S after the results.
func _maybe_next_match() -> void:
	return  # owner request 2026-11-24: no NEXT MATCH panel over the results (the menu preview still opens it)
	if _next_shown or int(ctx.setting("matches", 0)) != 1 or ctx.mode() != UICtx.MODE_SOLO:
		return
	_next_shown = true
	_next_at = Time.get_ticks_msec() + int(NextMatch.DELAY_S * 1000.0)


## UIRoot.open_next_match: "first" (after a first match) or "preview" (the game menu on the title).
func open_next_match(from: String) -> void:
	_next_from = from
	_next_going = ""
	next_match.open(UIMaps.name_of(g), over.is_open)


## NEXT MATCH's choice: a solo match on the player's difficulty and map (the only kind here).
func _next_match_go(kind: String) -> void:
	_next_going = kind
	next_match.close()
	if over.is_open:
		over.close()
	g._start_game_ui()  # (g.diff_i and the picked map: the player's own)


## The top bar's ? and the H key.
func toggle_help() -> void:
	if help.is_open:
		help.close()
	else:
		help.open()
		help.move_to_front()
		tooltip.move_to_front()
	_update_pause()


## The settings page of the game menu (the gear on the top bar, the speed slider's gear; works on the title too).
func open_settings_page() -> void:
	if pause.is_open:
		pause.show_settings()
		return
	pause.open(true, "settings")
	pause.move_to_front()
	_update_pause()


func open_pause_menu() -> void:
	if g.state != "play" and g.state != "pick":
		return
	pause.open(true)
	pause.move_to_front()
	_update_pause()


## Solo freezes the simulation while the game menu is open (UIRoot._update_pause).
func _update_pause() -> void:
	var want: bool = (pause.is_open or help.is_open) and ctx.mode() == UICtx.MODE_SOLO and ctx.in_match() and ctx.state.phase != Defs.PHASE_OVER
	ctx.set_paused(want)


func _layout_alert() -> void:
	if ctx.compact:
		# Phones: the alert temporarily takes over the status pill's slot (top-right).
		alert.apply_layout(top.panel.offset_top, 8.0 + ctx.insets.z)
		return
	var y := 12.0 + ctx.insets.y
	if top.visible:
		y = top.bottom_edge() + 10.0
	elif spawn.visible:
		y = spawn.bottom_edge() + 10.0
	alert.apply_layout(y)


## The game has no nuke events: the missiles in flight are compared with the last frame's.
func _track_nukes() -> void:
	var now: Dictionary = ctx.state.nukes()
	for uid in now:
		if not _seen_nukes.has(uid):
			var r := alert.track(uid)
			if r[1]:
				ctx.sfx("alarm")
				_layout_alert()
	for uid in _seen_nukes.keys():
		if not now.has(uid):
			var raw = _seen_nukes[uid]
			alert.resolve(uid, bool(raw.get("shot_down", false)))
			_seen_nukes.erase(uid)
	for uid in now:
		_seen_nukes[uid] = now[uid].raw


func _on_retreat(aid: int) -> void:
	for a in ctx.state.attacks():
		if a.aid == aid:
			ctx.send({"type": "retreat", "attack": a})
			ctx.sfx("click", -6.0)
			attacks.mark_dirty()
			return


func _on_build_chosen(kind: String) -> void:
	interact.select_action(kind)


## UIRoot.open_arsenal: the Arsenal window, on `key`'s page when one is given.
func open_arsenal(key = null, from = "") -> void:
	arsenal.open(key, str(from))


## UIRoot.screen: "title", "spawn", "play" or "over".
## UIRoot:toggle_leaderboard: the Tab key.
func toggle_leaderboard() -> void:
	board.toggle()


func screen() -> String:
	match str(g.state):
		"pick":
			return "spawn"
		"play":
			return "play"
		"over":
			return "over"
	return "title"


## UIRoot._build_spectate_pill: shown at the bottom while the player watches a match their nation
## is out of. (Upstream's "Take over" button buys a nation back in; not applicable here.)
func _build_spectate_pill() -> GlassPanel:
	var p := GlassPanel.new(16.0, 8.0, 999, true, 16)
	p.name = "SpectatePill"
	var h := UITheme.hbox(12)
	p.add_child(h)
	var eye := UITheme.icon_rect("eye", 18.0, UITheme.CYAN)
	eye.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(eye)
	var v := UITheme.vbox(0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UITheme.label("SPECTATING", 13, 800, UITheme.TEXT, 2))
	_spec_sub = UITheme.label("Drag to look around · click a nation for details", 11, 500, UITheme.TEXT_2)
	v.add_child(_spec_sub)
	h.add_child(v)
	var again := UITheme.button("Play again", "PrimaryButton", "play", 44.0)
	again.add_theme_font_size_override("font_size", 13)
	again.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func() -> void:
		g.spectating = false
		g._start_game_ui())
	h.add_child(again)
	var b := UITheme.button("Title", "GlassButton", "exit", 44.0)
	b.add_theme_font_size_override("font_size", 13)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		g.spectating = false
		g._to_menu())
	h.add_child(b)
	p.visible = false
	return p


## GameOver's "Keep watching": the war goes on without the player.
func _keep_watching() -> void:
	over.close()
	g.spectating = true
	g.state = "play"
	g.build_sel = -1


## main.gd: someone won while the player was watching.
func show_over_watched(winner: int) -> void:
	var st: Dictionary = g.stats
	var reason := Defs.OVER_DOMINATION if ctx.win_share(winner) >= SimRules.WIN_SHARE - 0.0005 else -1
	over.open("defeat", winner, 0, {
		"peak_share": float(st.get("peak", 0.0)) / 100.0,
		"max_troops": float(st.get("maxtroops", 0.0)),
		"kills": int(st.get("elims", 0)),
		"duration_s": float(g.elapsed),
		"match_s": float(g.elapsed),
	}, reason)
	over.move_to_front()


func _update_spectate_pill() -> void:
	var show: bool = g.spectating and g.state == "play" and not over.is_open
	if show != spectate_pill.visible:
		spectate_pill.visible = show
	if not show:
		return
	var killer := int(g.nations[g.PLAYER].get("last_by", 0)) if g.nations.size() > g.PLAYER else 0
	_spec_sub.text = ("Conquered by %s · the war goes on without you" % ctx.state.owner_name(killer)) if killer > 0 else "Your nation fell · the war goes on without you"
	var sp := spectate_pill
	var sb := 14.0 + ctx.insets.w
	sp.anchor_left = 0.5
	sp.anchor_right = 0.5
	sp.anchor_top = 1.0
	sp.anchor_bottom = 1.0
	sp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sp.offset_top = -sb
	sp.offset_bottom = -sb
	sp.offset_left = 0
	sp.offset_right = 0
	UITheme.fix_width(_spec_sub, 250.0 if ctx.compact else 330.0, HORIZONTAL_ALIGNMENT_LEFT, false)
	sp.reset_size()


## main.gd: a key went down. True when the ported key handling used it.
func on_key(key: int, echo: bool) -> bool:
	return interact.on_key(key, echo)


## The Attack bar and the game's share index stay the same stop.
func _on_ratio_changed(_r: float) -> void:
	if _syncing:
		return
	_syncing = true
	var i := UICtx.ratio_stop_index(ctx.ratio, ctx.ratio_max)
	if g.share_i != i:
		g._set_share(i)
	_syncing = false


## main._set_share (Q / E keys, the wheel): the bar follows.
func on_share_changed() -> void:
	if _syncing or ctx == null:
		return
	_syncing = true
	ctx.set_ratio(UICtx.RATIO_STOPS[clampi(g.share_i, 0, UICtx.RATIO_STOPS.size() - 1)])
	_syncing = false


## The kind name of the game's selected build id ("" for none).
func _placing_kind() -> String:
	var k: int = g.build_sel
	if k < 0:
		return ""
	if (k == 14 or k == 15) and g.strike_only:
		return "airstrike" if k == 14 else "slug"
	if k == 14 and g.has_method("_is_strike_click"):
		return "airfield"
	for name in RWGameState.BUILD_ID:
		if RWGameState.BUILD_ID[name] == k and name != "airstrike" and name != "slug":
			return name
	return ""


# ---------------------------------------------------------------------------------------------
# Event feed: the game's notify() and alliance prompts
# ---------------------------------------------------------------------------------------------
const _KIND_CAT := {"good": Defs.MSG_GOOD, "bad": Defs.MSG_BAD, "info": Defs.MSG_INFO, "alert": Defs.MSG_ALERT, "ally": Defs.MSG_ALLIANCE}
## UIAdvisor._naval_sfx: which naval news a message is ("" = none); naval news wears the warship glyph.
static func _naval_kind(t: String) -> String:
	if t.contains("sank your") or t.contains("your transport was sunk") or t.contains("your warship was sunk"):
		return "ship_lost"
	if t.contains("you sank") or t.contains("your warship sank"):
		return "ship_kill"
	if t.contains("captured a trade ship") and t.begins_with("your"):
		return "trade_captured"
	if t.contains("trade ship"):
		return "trade_lost"
	return ""


## main.notify(text, kind): kind is "good" / "bad" / "info". It can fire inside a time-budgeted sim
## pass, so the toast is built on the next frame; only the newest few are kept while no frames run.
func toast(text: String, kind: String = "info") -> void:
	_pending_toasts.append([text, kind])
	if _pending_toasts.size() > 6:
		_pending_toasts.pop_front()


func _toast_now(text: String, kind: String) -> void:
	var t := text.to_lower()
	var k := kind
	if kind == "bad" and (t.contains("nuke") or t.contains("bomb") or t.contains("incoming") or t.contains("attack")):
		k = "alert"
	elif t.contains("alliance") or t.contains("allied") or t.contains("ally"):
		k = "ally"
	# Upstream (UIAdvisor.on_message / the alliance handlers): the category's own glyph
	# (UITheme.msg_icon), except naval news (warship) and the alliance lines (alliance / betray).
	var icon := ""
	if _naval_kind(t) != "":
		icon = "warship"
	elif t.contains("betrayed you"):
		icon = "betray"
	elif t.begins_with("alliance formed") or (t.begins_with("your alliance with") and t.ends_with("has ended")):
		icon = "alliance"
	feed.toast(_KIND_CAT.get(k, Defs.MSG_INFO), text, icon)


## The game's alliance prompt: "propose" (a request from `who`) or "expire" (the renewal window).
func show_ally_card(mode: String, who: int) -> void:
	if mode == "expire":
		var expires := float(int(g.allies.get(g._akey(g.PLAYER, who), ctx.state.tick)))
		feed.alliance_renewal(who, expires, bool(g.asked_to_extend(who, g.PLAYER)))
	else:
		feed.alliance_request(who)


func close_ally_request(who: int) -> void:
	feed.close_request(who)


func clear_feed() -> void:
	_pending_toasts.clear()
	feed.clear()


## The pointer over the map: the hover card (UIInteract.on_hover). main.gd still owns the clicks.
func _hover(dt: float, in_match: bool) -> void:
	var modal: bool = pause.is_open or over.is_open or help.is_open or (g.arsenal_dlg != null and g.arsenal_dlg.visible) or (g.settings_dlg != null and g.settings_dlg.visible)
	interact.enabled = in_match and not modal and (g.state == "pick" or g.state == "play") and not g.in_waiting_room()
	var aim := _placing_kind() if g.state == "play" else ""
	if aim != interact.aim_kind:
		# (the game changed its build selection: a new aim starts unlocked, with no ghost)
		interact.aim_kind = aim
		interact._confirm_tile = -1
		interact._clear_ghost()
		if aim != "" and target_card.is_open:
			target_card.hide_card()
	interact._follow_ghost()
	var tile := -1
	if interact.enabled and root.get_viewport().gui_get_hovered_control() == null:
		tile = ctx.tile_at(root.get_viewport().get_mouse_position())
	if tile != _hover_seen or not interact.enabled:
		_hover_seen = tile
		interact.on_hover(tile)
	interact.process_frame(dt)
	radial.update(dt)
	if radial.is_open and not interact.enabled:
		radial.close()
	if not in_match or (g.state != "pick" and g.state != "play"):
		if target_card.is_open:
			target_card.hide_card()
		if unit_card.is_open:
			interact.deselect_unit()


## A new player on the title: their first match starts by itself, as the tutorial.
func _check_new_player(forced: bool = false) -> void:
	if tutorial == null or tutorial.active:
		return
	if not forced:
		# (owner request 2026-11-25) no automatic tutorial on first load: a new player lands on the title and starts
		# it themselves (How to play, or "Replay as new player" in Settings); Settings can switch it off.
		return
	if not forced:
		# (screenshot and test runs start their own matches)
		var args := OS.get_cmdline_user_args()
		for a in args:
			if a.begins_with("--") and a != "--tutorial":
				return
		if DisplayServer.get_name() == "headless":
			return
		if int(g.save.get("stars", 0)) > 0 or not Tutorial.is_new(ctx.settings, int(ctx.setting("matches", 0))):
			return
	_tutorial_at = UICtx.msec() + TUTORIAL_DELAY_S * 1000.0


func _tutorial_step() -> void:
	if UICtx.msec() < _tutorial_at:
		return
	if g.state != "menu":
		_tutorial_at = -1.0  # (they are on their way into a match already)
		return
	if g._loading or title.solo_menu_open() or map_picker.is_open:
		return
	_tutorial_at = -1.0
	start_tutorial()


## Starts the tutorial's match: a solo match on the default map with the gentlest AI, the steps on
## top (UI/Tutorial).
func start_tutorial() -> void:
	if g._loading or g.state != "menu":
		return
	if bool(ctx.setting("tutorial_off", false)) and not ("--tutorial" in OS.get_cmdline_user_args()):
		return
	ctx.set_setting("tutorial", "started")
	coach.muted = true
	coach.clear()
	tutorial.begin()
	g.map_tab = 0
	g.map_i = 0
	g.diff_i = Tutorial.DIFFICULTY
	g.bot_players = 0
	g._start_game_ui()


## The game is building a match: the busy chip with how far along it is.
func set_loading(on: bool, frac: float = 0.0) -> void:
	if on:
		busy.show_text("Deploying a new world…  %d%%" % int(clampf(frac, 0.0, 1.0) * 100.0))
	else:
		busy.hide_chip()


## main.gd: a left click on the map while picking a start or playing (UIInteract.on_click).
func on_click() -> void:
	if not interact.enabled:
		return
	interact.on_click(ctx.tile_at(root.get_viewport().get_mouse_position()))


## What the range rings show follows the pointer, the aim and the selected warship (upstream:
## UIInteract.on_hover / _show_aim and MapView's unit rings).
func _feed_ranges() -> void:
	var rl: RangeLayer = g.ranges
	rl.visible = g.state != "menu"
	if not rl.visible:
		return
	var px_tiles := 12.0 / maxf(0.01, g.cam.zoom.x * g.TS)
	var ht: int = interact.hover_tile if interact.enabled else -1
	rl.set_hover_tile(ht, px_tiles)
	var u = ctx.state.unit(unit_card.uid) if unit_card.is_open else null
	if u != null:
		var raw: Dictionary = u.raw
		var pos: Vector2 = raw.pos
		var pat: Vector2 = raw.get("patrol", pos)
		rl.set_unit_rings(pat.x, pat.y, ViewRules.warship_patrol_range() if unit_card.own else 0.0, pos.x, pos.y, ViewRules.warship_target_range(), ctx.state.owner_color(int(u.owner)))
	else:
		rl.clear_unit_rings()


## MapInput.tile_clicked.
func on_click_tile(tile: int) -> void:
	if interact.enabled:
		interact.on_click(tile)


## MapInput.tile_context (right click, or a finger held on the map).
func on_context_at(tile: int, pos: Vector2) -> void:
	if interact.enabled:
		interact.on_context(tile, pos)


## main.gd: the Space key.
func on_primary_key() -> void:
	if interact.enabled:
		interact.primary_at_hover()


## main.gd: right-click or Esc with something selected. True when a card was closed.
func cancel_selection() -> bool:
	if target_card.is_open:
		target_card.hide_card(true)
		return true
	if unit_card.is_open:
		interact.deselect_unit(true)
		return true
	return false


## main.gd: a right-click on the map in play (nothing to cancel first). True when the ring opened.
func on_context() -> bool:
	if not interact.enabled:
		return false
	var pos := root.get_viewport().get_mouse_position()
	interact.on_context(ctx.tile_at(pos), pos)
	return radial.is_open


## Bottom edge of the status pill (the old HUD's alert banner sits under it).
func status_bottom() -> float:
	return top.bottom_edge() if top.visible else 0.0


func process(dt: float) -> void:
	if root == null:
		return
	var in_match: bool = (g.state == "play" or g.state == "pick" or g.state == "over") and g.nations.size() > g.PLAYER
	if _next_at > 0 and Time.get_ticks_msec() >= _next_at:
		_next_at = 0
		if over.is_open and not next_match.is_open and ctx.mode() == UICtx.MODE_SOLO:
			open_next_match("first")
	var play: bool = g.state == "play" and in_match
	ctx.state_mode = ctx.mode()
	if g.state != _state_seen:
		_state_seen = g.state
		if g.state != "over" and over.is_open:
			over.close()
		if g.state != "over" and g.state != "menu" and next_match.is_open:
			next_match.close()
		topbar.refresh()
		layout()
	var ph: int = ctx.state.phase if in_match else -1
	var room: bool = in_match and waiting.should_show()
	if room != waiting.visible:
		waiting.visible = room
		if room:
			waiting.refresh()
		if ph == Defs.PHASE_SPAWN:
			var was := spawn.visible
			spawn.visible = not room
			if spawn.visible and not was:
				spawn.on_show()
	if ph != _phase:
		var before := _phase
		_phase = ph
		top.visible = ph == Defs.PHASE_PLAYING or ph == Defs.PHASE_OVER
		var was_spawn := spawn.visible
		spawn.visible = ph == Defs.PHASE_SPAWN and not g.in_waiting_room()
		if spawn.visible and not was_spawn:
			spawn.on_show()
		if ph != Defs.PHASE_PLAYING:
			alert.clear()
			_seen_nukes.clear()
		board.visible = ph == Defs.PHASE_PLAYING
		attacks.visible = ph == Defs.PHASE_PLAYING
		if ph == Defs.PHASE_SPAWN or (ph == Defs.PHASE_PLAYING and before != Defs.PHASE_SPAWN) or ph == -1:
			# a new match (or back at the title)
			clear_feed()
			board.close_for_match()
			ctx.play_start_tick = -1.0
			ctx.alive_from_tick = NAN
			ctx.troop_floor = NAN  # (a new player's floor arms again in this match)
			if g.names != null:
				g.names.unbind()
			if g.ranges != null:
				g.ranges.unbind()
			if g.fx_layer != null:
				g.fx_layer.unbind()
			if g.fallout_glow != null:
				g.fallout_glow.reset()
			if g.surface != null:
				g.surface.clear()
			coach.clear()
			advisor.reset()
		if ph == Defs.PHASE_PLAYING and before == Defs.PHASE_SPAWN:
			advisor.war_begins()
		if ph == Defs.PHASE_PLAYING:
			ctx.play_start_tick = float(ctx.state.tick)
			top.on_bind()
			board.refresh()
			attacks.mark_dirty()
		elif ph == Defs.PHASE_OVER:
			top.on_phase(ph, 0)
		layout()
	if play != _was_play:
		_was_play = play
		bar.visible = play
		if play:
			ctx.rules.recount()
			bar.reset_rate()
			on_share_changed()
			bar.refresh(false)
			layout()
	if g.names != null:
		g.names.visible = g.state != "menu"
		var _c_world := Time.get_ticks_usec()
		ctx.world.update(dt)
		g._pf_add('c_world', Time.get_ticks_usec() - _c_world)
	_update_spectate_pill()
	if g.ranges != null:
		var _c_ranges := Time.get_ticks_usec()
		_feed_ranges()
		g._pf_add('c_ranges', Time.get_ticks_usec() - _c_ranges)
	# Coach marks: hidden outside a match, and they step aside while placing or using the ring.
	coach.visible = (play or g.state == "pick") and not over.is_open
	var want_a := 0.0 if (radial.is_open or interact.aim_kind != "") else 1.0
	coach.modulate.a = move_toward(coach.modulate.a, want_a, dt * 6.0)
	coach.eff_a = coach.modulate.a
	tutorial.visible = (play or g.state == "pick") and not over.is_open
	if _tutorial_at >= 0.0:
		_tutorial_step()
	# back on the title from the tutorial's match: it is over
	if g.state == "menu" and tutorial.active and not g._loading:
		tutorial.stop("left")
	_advise_t += dt
	if _advise_t >= 0.5 and in_match:
		_advise_t = 0.0
		advisor.check_threats()
		if not tutorial.active:
			advisor.check_tips()
			var _c_advisor := Time.get_ticks_usec()
			advisor.check_floor()
			g._pf_add('c_advisor', Time.get_ticks_usec() - _c_advisor)
	if top.visible:
		var _c_top := Time.get_ticks_usec()
		top.update(dt)
		g._pf_add('c_top', Time.get_ticks_usec() - _c_top)
	feed.visible = in_match
	var _c_hover := Time.get_ticks_usec()
	_hover(dt, in_match)
	g._pf_add('c_hover', Time.get_ticks_usec() - _c_hover)
	if not _pending_toasts.is_empty():
		var q := _pending_toasts
		_pending_toasts = []
		for e in q:
			_toast_now(e[0], e[1])
	var _c_feed := Time.get_ticks_usec()
	feed.update(dt)
	g._pf_add('c_feed', Time.get_ticks_usec() - _c_feed)
	if not play:
		return
	# (the server sends stats every 5 ticks: the bar's numbers refresh four times a second)
	_stats_t += dt
	if _stats_t >= 0.25:
		_stats_t = 0.0
		bar.refresh(true)
		board.mark_dirty()
	_growth_t += dt
	if _growth_t >= 0.5:
		_growth_t = 0.0
		var _c_bar_s := Time.get_ticks_usec()
		bar.sample_growth()
		g._pf_add('c_bar_s', Time.get_ticks_usec() - _c_bar_s)
	var placing := _placing_kind()
	if placing != bar._placing:
		bar.set_placing(placing)
	icbm.refresh()
	var _c_nukes := Time.get_ticks_usec()
	_track_nukes()
	g._pf_add('c_nukes', Time.get_ticks_usec() - _c_nukes)
	var _c_alert := Time.get_ticks_usec()
	alert.update(dt)
	g._pf_add('c_alert', Time.get_ticks_usec() - _c_alert)
	var _c_bar := Time.get_ticks_usec()
	bar.update(dt)
	g._pf_add('c_bar', Time.get_ticks_usec() - _c_bar)
	var _c_board := Time.get_ticks_usec()
	board.update(dt)
	g._pf_add('c_board', Time.get_ticks_usec() - _c_board)
	var _c_attacks := Time.get_ticks_usec()
	attacks.update(dt)
	g._pf_add('c_attacks', Time.get_ticks_usec() - _c_attacks)


## UIRoot's button sounds (W.button_sound / the pressed + mouse_entered hooks): a press clicks (-2 dB;
## -4 dB for a BuildButton or a leaderboard row), the pointer entering an enabled button ticks
## (-14 dB, mouse only; none on those quiet ones).
func _hook_button_sfx(node: Node) -> void:
	if not (node is BaseButton) or root == null or not root.is_ancestor_of(node) or node.has_meta("_sfx_hooked"):
		return
	node.set_meta("_sfx_hooked", true)
	var b := node as BaseButton
	var quiet := b is BuildButton or b is Leaderboard.Row
	if quiet:
		b.pressed.connect(func() -> void: ctx.sfx("click", -4.0))
	else:
		b.pressed.connect(func() -> void: ctx.sfx("click", -2.0))
		b.mouse_entered.connect(func() -> void:
			if not b.disabled and not ctx.touch:
				ctx.sfx("hover", -14.0))
