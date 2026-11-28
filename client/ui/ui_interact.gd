# Port of src/client/UI/UIInteract.luau (scripts/ui/ui_interact.gd): what the pointer does on the
# map. Ported: the hover part (on_hover, _update_tooltip, hover_spec, _aim_spec, _crowding and the
# per-frame refresh), the action ring (on_context, on_radial, donate_to, retreat, _float,
# show_inspect) and left clicks (on_click, the target card's select-then-fire flow, warship
# selection and move orders, pick) and placement (_place with the two-click nuke lock, the touch
# ghost and its confirm buttons), select_action and the keys (on_key, key repeat, escape).
# The selection and the build themselves go through the game's select_build / try_build, so the
# port's range system, ICBM mode and warship auto-launch keep working; aim_kind follows the game's
# build slot. Touch input (connect_input, _set_touch) comes over with MapInput.
class_name UIInteract
extends RefCounted

## Nations / tribes / commanders whose capital lies within ~88 full-size tiles count as neighbours
## of a spawn spot.
const CROWD_FULL_TILES := 88.0

## Two clicks on one tile closer together than this are one click.
const DUP_MS := 180.0
## How far a tap may miss land and still pick it (screen px).
const PICK_TOUCH_PX := 22.0
const PICK_MOUSE_PX := 6.0
## How close a tap must be to a warship to select it (screen px).
const UNIT_PICK_TOUCH := 26.0
const UNIT_PICK_MOUSE := 12.0

## Q / E held: seconds before the first repeat, then seconds between repeats.
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.07
const HOTKEY_INDEX := {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4, KEY_6: 5, KEY_7: 6, KEY_8: 7, KEY_9: 8, KEY_0: 9,
	KEY_KP_1: 0, KEY_KP_2: 1, KEY_KP_3: 2, KEY_KP_4: 3, KEY_KP_5: 4, KEY_KP_6: 5, KEY_KP_7: 6, KEY_KP_8: 7, KEY_KP_9: 8, KEY_KP_0: 9}

var ctx: UICtx
## the host (ClientHud): toggle_help, help, pause, screen()
var ui = null
var _held := {}  # keycode -> {t, next}
var target_card: TargetCard = null
var place_confirm: PlaceConfirm = null
var _confirm_msec := 0.0
var _ghost_tile := -1
var _ghost_raw := -1
var _ghost_hit := -1
var _ghost_anchor := Vector2(-1, -1)
var _ghost_res := {}
var unit_card: UnitCard = null
var last_pick := -1
var _last_click_tile := -1
var _last_click_msec := -100000.0
var tooltip: Tooltip = null
var radial: RadialMenu = null
var bar: CommandBar = null
## The layer floating confirmations are added to.
var float_layer: Control = null
var _last_ctx_msec := -100000.0
var _range_focus := -1
## Current placement kind ("" = none): a structure, "warship" or a nuke.
var aim_kind := ""
var hover_tile := -1
var enabled := false
var _confirm_tile := -1
var _tip_accum := 0.0
var _tip_dirty := false
var _tip_wait := 0.0


func _init(c: UICtx) -> void:
	ctx = c


func on_hover(tile: int) -> void:
	hover_tile = tile
	if not enabled or ctx.state == null:
		ctx.world_call("set_hover_owner", [0])
		if tooltip.place == Tooltip.PLACE_FOLLOW:
			tooltip.hide_tip()
		return
	var s = ctx.state
	var own: int = s.tile_owner(tile) if tile >= 0 else 0
	ctx.world_call("set_hover_owner", [own])
	# The hover card is rebuilt at most ~16x per second (its hint may search the map).
	_tip_dirty = true
	if _tip_wait <= 0.0:
		_tip_wait = 0.06
		_tip_dirty = false
		_update_tooltip()


func _update_tooltip() -> void:
	if tooltip.place == Tooltip.PLACE_PINNED and tooltip.is_shown():
		return
	if tooltip.place == Tooltip.PLACE_ANCHOR and tooltip.is_shown():
		return
	if ctx.touch or (radial != null and radial.is_open) or not enabled:
		if tooltip.place == Tooltip.PLACE_FOLLOW:
			tooltip.hide_tip()
		return
	var spec := hover_spec(hover_tile)
	if spec.is_empty():
		tooltip.hide_tip()
	else:
		tooltip.show_follow(spec)


## Nations around a spawn spot (within CROWD_FULL_TILES full-size tiles).
func _crowding(tile: int) -> int:
	var s = ctx.state
	if s == null or tile < 0:
		return 0
	var w: int = s.map.W
	var r: float = CROWD_FULL_TILES / maxf(s.map.k_lin, 0.01)
	var r2 := r * r
	var hx := tile % w
	@warning_ignore("integer_division")
	var hy := tile / w
	var n := 0
	var mine := ctx.me()
	for o in s.owners():
		if not o.alive or o.id == mine:
			continue
		var t: int = o.get("label_tile", -1)
		if t >= 0:
			var dx := t % w - hx
			@warning_ignore("integer_division")
			var dy := t / w - hy
			if dx * dx + dy * dy <= r2:
				n += 1
	return n


func hover_spec(tile: int, pinned: bool = false) -> Dictionary:
	var Th := UITheme
	var s = ctx.state
	if s == null or tile < 0:
		return {}
	var map = s.map
	var own: int = s.tile_owner(tile)
	var terrain := ctx.terrain_title(tile)
	var spec := {}
	if aim_kind != "" and not pinned:
		return _aim_spec(tile)
	if own != 0:
		var o = s.get_owner(own)
		if o == null:
			return {}
		var rel := ctx.relation(own)
		spec["title"] = o.name
		spec["swatch"] = o.color
		spec["badge"] = rel
		spec["badge_color"] = ctx.relation_color(rel)
		spec["sub"] = "%s  ·  %s" % [ctx.kind_title(o.kind), terrain]
		var rows := [["Troops", Th.fmt_troops(o.troops), Th.TEXT], ["Land", Th.fmt_pct(s.land_share(own)), Th.TEXT]]
		if own == ctx.me() or pinned:
			rows.append(["Gold", Th.fmt_num(o.gold), Th.GOLD])
		var st = ctx.structure_at(tile, 1)
		if st != null and st.owner == own and st.kind >= 0:
			var lv := " · Lv %d" % st.level if st.level > 1 else ""
			rows.append(["Structure", Defs.STRUCT_TITLES[st.kind] + lv, Th.TEXT])
			if st.active_tick > s.tick:
				# Under construction: it does nothing yet (no cap, trade, defense, interception, launch).
				rows.append(["Building…", Th.fmt_time(ceil(float(st.active_tick - s.tick) / Defs.TICK_RATE)), Th.ORANGE])
		if s.is_traitor(own):
			rows.append(["Traitor", "%ds left" % int(ceil(float(o.traitor_until - s.tick) / Defs.TICK_RATE)), Th.RED])
		# the player panel's "Alliance Expires In": red in the last 30 s, yellow in the last 60 s
		var ai = s.alliance_info(ctx.me(), own) if own != ctx.me() else null
		if ai != null and ai.expires_at >= 0:
			var secs := int(ceil(float(ai.ticks_left) / Defs.TICK_RATE))
			var col: Color = Th.RED if secs <= 30 else (Th.AMBER if secs <= 60 else Th.GREEN)
			rows.append(["Alliance ends", Th.fmt_time(secs), col])
			if ai.me_asked or ai.other_asked:
				rows.append(["Renewal", "asked, waiting for them" if ai.me_asked else "they asked", Th.VIOLET])
		spec["rows"] = rows
	elif map.is_land(tile):
		var fallout: bool = s.has_fallout(tile)
		spec["title"] = ("Unclaimed  ·  " + terrain) if not fallout else "Fallout zone"
		spec["title_color"] = Th.TEXT_2 if not fallout else Th.ORANGE
		var st2 = ctx.structure_at(tile, 0)
		if st2 != null and st2.kind >= 0:
			spec["sub"] = Defs.STRUCT_TITLES[st2.kind]
	else:
		if not pinned:
			return {}
		spec["title"] = terrain
		spec["title_color"] = Th.TEXT_2
	if pinned:
		return spec
	var act: Dictionary = ctx.rules.primary(tile)
	var verb := "Tap" if ctx.touch else "Click"
	var ty := str(act.type)
	if ty == "spawn":
		spec["hint"] = verb + " to place your capital here"
		spec["hint_color"] = Th.AMBER
		spec["hint_icon"] = "target"
		var crowd := _crowding(tile)
		var rows2: Array = spec.get("rows", [])
		if crowd >= 6:
			rows2.append(["Neighbours", "%d nearby · crowded, tough start" % crowd, Th.ORANGE])
		elif crowd >= 3:
			rows2.append(["Neighbours", "%d nearby · contested" % crowd, Th.AMBER])
		else:
			rows2.append(["Neighbours", "%d nearby · open land, safer start" % crowd, Th.GREEN])
		spec["rows"] = rows2
	elif ty == "expand" or ty == "attack":
		if act.ok:
			spec["hint"] = "%s: %s with %s" % [verb, "expand" if ty == "expand" else "attack", Th.fmt_troops(act.troops)]
			spec["hint_color"] = Th.GREEN if ty == "expand" else Th.AMBER
			spec["hint_icon"] = "attack"
	elif ty == "boat":
		if act.ok:
			spec["hint"] = "%s: boat invasion with %s" % [verb, Th.fmt_troops(act.troops)]
			spec["hint_color"] = Th.CYAN
			spec["hint_icon"] = "boat"
		else:
			spec["hint"] = str(act.reason)
			spec["hint_color"] = Th.TEXT_3
			spec["hint_icon"] = "boat"
	elif ty == "none":
		if str(act.reason) != "":
			spec["hint"] = str(act.reason)
			spec["hint_color"] = Th.TEXT_3
			spec["hint_icon"] = "info"
	if s.phase == Defs.PHASE_PLAYING and ctx.alive_player():
		spec["footer"] = "Right-click for more actions"
	return spec


func _aim_spec(tile: int) -> Dictionary:
	var Th := UITheme
	var k := aim_kind
	var nuke := UIRules.is_nuke(k)
	var title: String = UIRules.TITLES.get(k, k)
	var spec := {"title": ("Launch " if nuke else "Build ") + title, "title_color": Th.RED if nuke else Th.TEXT}
	var av: Dictionary = ctx.rules.availability(k)
	var pl: Dictionary = ctx.rules.placement(k, tile)
	# Your own structure under the cursor: the click upgrades it.
	var upgrade: bool = pl.ok and pl.get("upgrade", false) == true and not nuke
	if upgrade:
		spec["title"] = "Upgrade %s -> Lv %d" % [title, int(pl.get("level", 2))]
	var rows := [["Cost", Th.fmt_cost(av.cost) + " gold", Th.GOLD]]
	if nuke:
		rows.append(["Blast radius", ctx.rules.blast_text(k), Th.TEXT])
		if tile >= 0 and ctx.state.tile_owner(tile) != 0:
			rows.append(["Target", ctx.state.owner_name(ctx.state.tile_owner(tile)), Th.TEXT])
		# Hostile SAM cover of the aimed tile (the view counts it for the current aim).
		var ns = ctx.world_call("aim_sams", [tile])
		var n_sam := int(ns) if ns != null else 0
		if n_sam > 0 and k != "mirv" and not UIRules.is_strike(k):  # (custom, owner 2026-11-25: strikes and slugs cannot be intercepted)
			rows.append(["SAM cover", "%d SAM%s cover this target" % [n_sam, "" if n_sam == 1 else "s"], Th.RED])
	spec["rows"] = rows
	var verb := "Tap" if ctx.touch else "Click"
	if not pl.ok:
		spec["hint"] = str(pl.reason)
		spec["hint_color"] = Th.RED
		spec["hint_icon"] = "info"
	else:
		spec["hint"] = (verb + " to target") if nuke else ((verb + " to upgrade") if upgrade else (verb + " to build here"))
		spec["hint_color"] = Th.GREEN
		spec["hint_icon"] = "target"
		if str(pl.get("warn", "")) != "":
			spec["body"] = str(pl.warn)
	# (Esc opens the game menu's cancel here as well; right-click cancels.)
	spec["footer"] = "Right-click or Esc to cancel" if not ctx.touch else "Long-press to cancel"
	return spec


func process_frame(delta: float) -> void:
	_key_repeat(delta)
	if _tip_wait > 0.0:
		_tip_wait -= delta
		if _tip_wait <= 0.0 and _tip_dirty:
			_tip_dirty = false
			_tip_wait = 0.06
			_update_tooltip()
	# Keep the hover card's numbers fresh while the pointer rests.
	_tip_accum += delta
	if _tip_accum >= 0.5:
		_tip_accum = 0.0
		if enabled and tooltip.place == Tooltip.PLACE_FOLLOW and tooltip.is_shown():
			_update_tooltip()


# ---------------------------------------------------------------------------------------------
# Left clicks
# ---------------------------------------------------------------------------------------------
## A click (tap) on the map: select or steer a warship, fire the primary order for the tile, or
## (with "select before attacking" on) open the target card first.
func on_click(tile: int) -> void:
	if not enabled or ctx.state == null:
		return
	var now := UICtx.msec()
	if tile == _last_click_tile and now - _last_click_msec < DUP_MS:
		return
	_last_click_tile = tile
	_last_click_msec = now
	if radial.is_open:
		radial.close()
		return
	var pos := tap_pos(tile)
	var s = ctx.state
	if aim_kind == "":
		var on_land: bool = tile >= 0 and s.map.is_land(tile)
		var steering: bool = unit_card != null and unit_card.is_open and unit_card.own and not on_land
		var uid := unit_at(pos, 12.0 if (on_land or steering) else -1.0)
		if uid != 0 and not (steering and uid == unit_card.uid):
			select_unit(uid)
			return
		if unit_card != null and unit_card.is_open:
			if unit_card.own and tile >= 0 and s.map.is_water(tile):
				_move_selected(tile, pos)
			else:
				deselect_unit(true)
			return
	tile = pick(tile, pos)
	last_pick = tile
	if aim_kind != "":
		_place(tile, pos)
		return
	var act: Dictionary = ctx.rules.primary(tile)
	var kind := str(act.type)
	var selectable: bool = (kind == "attack" or kind == "boat") and act.ok
	var ally_own := _ally_at(tile) if ctx.touch else 0
	if target_card != null and target_card.is_open:
		if selectable and target_card.matches(tile, kind):
			_fire_selected(pos)
			return
		var same_ally: bool = ally_own != 0 and target_card.kind == "ally" and target_card.owner_id == ally_own
		target_card.hide_card()
		if ally_own != 0 and not same_ally:
			_select(tile, "ally", act)
		elif selectable and confirm_orders():
			_select(tile, kind, act)
		return
	if ally_own != 0:
		tooltip.hide_tip()
		_select(tile, "ally", act)
		return
	if tooltip.place == Tooltip.PLACE_PINNED and tooltip.is_shown():
		tooltip.hide_tip()
		if ctx.touch:
			return
	if selectable and confirm_orders():
		_select(tile, kind, act)
		return
	if kind == "inspect":
		var own: int = s.tile_owner(tile)
		ctx.world_call("set_selected_owner", [own])
		if ctx.touch and own != 0:
			show_inspect(tile)
		return
	if kind == "none" or not act.ok:
		var reason := str(act.reason)
		if reason != "":
			ctx.sfx("deny", -4.0)
			_float(reason, "info", UITheme.TEXT_2, pos)
		if act.get("floor", false) == true:
			ctx.floor_held.emit()
		return
	var intent: Dictionary = ctx.rules.primary_intent(tile, act)
	if intent.is_empty():
		return
	ctx.send(intent)
	var coach = ctx.coach
	if coach != null:
		if kind == "expand":
			coach.complete("expand")
		elif kind == "attack":
			coach.complete("expand")
			coach.complete("contact")
		elif kind == "boat":
			coach.complete("boat")
	if kind == "spawn":
		ctx.sfx("spawn")
	elif kind == "expand":
		_float(ctx.rules.confirm_text(act), "attack", UITheme.GREEN, pos)
	elif kind == "attack":
		_float(ctx.rules.confirm_text(act), "attack", UITheme.AMBER, pos)
	elif kind == "boat":
		_float(ctx.rules.confirm_text(act), "boat", UITheme.CYAN, pos)


## "Select before attacking": separate settings for touch and mouse.
func confirm_orders() -> bool:
	if ctx.touch:
		return bool(ctx.setting("confirm_orders", true))
	return bool(ctx.setting("confirm_orders_desktop", false))


func _select(tile: int, kind: String, act: Dictionary) -> void:
	if target_card == null:
		return
	target_card.show_target(tile, kind, act)
	var own: int = ctx.state.tile_owner(tile)
	ctx.world_call("set_selected_owner", [own])
	if own != 0 and kind != "ally":
		ctx.world_call("set_range_owner", [own])
		ctx.world_call("set_range_mode", ["attack_aim"])
	_range_focus = tile
	ctx.world_call("set_range_focus", [tile])
	if ctx.coach != null:
		ctx.coach.offer("select")


func _fire_selected(pos: Vector2) -> void:
	var tc := target_card
	var t := tc.tile
	var k := tc.kind
	tc.hide_card()
	ctx.world_call("set_selected_owner", [0])
	var act: Dictionary = ctx.rules.primary(t)
	if str(act.type) == "none" or not act.ok:
		ctx.sfx("deny", -4.0)
		var r := str(act.reason)
		_float(r if r != "" else "Target out of reach", "info", UITheme.TEXT_2, pos)
		if act.get("floor", false) == true:
			ctx.floor_held.emit()
		return
	if str(act.type) != k and not (k == "attack" and str(act.type) == "expand"):
		act.type = k
	var intent: Dictionary = ctx.rules.primary_intent(t, act)
	if intent.is_empty():
		return
	ctx.send(intent)
	if ctx.coach != null:
		ctx.coach.complete("select")
		ctx.coach.complete("contact")
		if k == "boat":
			ctx.coach.complete("boat")
	_float(ctx.rules.confirm_text(act), "attack" if k == "attack" else "boat", UITheme.AMBER if k == "attack" else UITheme.CYAN, pos)


func fire_from_card() -> void:
	var tc := target_card
	if tc == null or not tc.is_open:
		return
	var p := ctx.tile_screen_pos(tc.tile)
	_fire_selected(p if p.x >= 0.0 else tc.panel_rect().get_center())


## The ally (or teammate) who owns `tile`, else 0.
func _ally_at(tile: int) -> int:
	var s = ctx.state
	if s == null or tile < 0 or s.phase != Defs.PHASE_PLAYING or not ctx.alive_player():
		return 0
	var own: int = s.tile_owner(tile)
	return own if (own != 0 and own != ctx.me() and s.are_allies(ctx.me(), own)) else 0


func betray_from_card(attack: bool) -> void:
	var tc := target_card
	if tc == null or not tc.is_open or tc.owner_id == 0:
		return
	var own := tc.owner_id
	var t := tc.tile
	var p := ctx.tile_screen_pos(t)
	tc.hide_card()
	ctx.world_call("set_selected_owner", [0])
	ctx.send({"type": "ally_break", "target": own})
	ctx.sfx("deny", -2.0)
	var at := p if p.x >= 0.0 else ctx.mouse_pos()
	if attack and ctx.troops_for_ratio() >= 1.0:
		var land: bool = ctx.borders.borders_owner(own)
		var landing: int = -1 if land else ctx.rules.boat_landing(t)
		ctx.send({"type": "attack" if land else "boat", "tile": landing if landing >= 0 else t, "ratio": ctx.order_ratio()})
		_float("You betrayed %s · attacking with %s" % [ctx.state.owner_name(own), UITheme.fmt_troops(ctx.troops_for_ratio())], "betray", UITheme.RED, at)
	else:
		_float("You broke your alliance with " + ctx.state.owner_name(own), "betray", UITheme.RED, at)


func donate_from_card() -> void:
	var tc := target_card
	if tc == null or not tc.is_open or tc.owner_id == 0:
		return
	var own := tc.owner_id
	var p := ctx.tile_screen_pos(tc.tile)
	if donate_to(own, p if p.x >= 0.0 else ctx.mouse_pos()):
		tc.hide_card()
		ctx.world_call("set_selected_owner", [0])


func ally_from_card() -> void:
	var tc := target_card
	if tc == null or not tc.is_open or tc.owner_id == 0:
		return
	var own := tc.owner_id
	tc.hide_card()
	ctx.world_call("set_selected_owner", [0])
	ctx.send({"type": "ally_request", "target": own})
	_float("Alliance proposed to " + ctx.state.owner_name(own), "alliance", UITheme.VIOLET, ctx.mouse_pos())


## The Space key: the primary order for the tile under the pointer.
func primary_at_hover() -> void:
	if hover_tile >= 0:
		_last_click_tile = -1
		on_click(hover_tile)


# ---------------------------------------------------------------------------------------------
# Choosing what to place, and the keys
# ---------------------------------------------------------------------------------------------
## A build / launch slot was pressed (or its number key): refuse with the reason, open the Arsenal
## for a locked item, or enter (or leave) placement.
func select_action(kind: String) -> void:
	if not enabled or not ctx.alive_player():
		return
	var b = bar.button(kind) if bar != null else null
	var av: Dictionary = ctx.rules.availability(kind)
	if av.get("arsenal") != null:
		ctx.sfx("locked")
		if ui != null:
			ui.open_arsenal(av.arsenal, "locked")
		return
	if not av.ok:
		if b != null:
			b.deny()
		ctx.sfx("deny")
		_float(str(av.reason), "info", UITheme.RED, _anchor_pos(b))
		return
	var g = ctx.session.g
	var k := int(RWGameState.BUILD_ID.get(kind, -1))
	if k < 0:
		return
	if kind == "reinforce":
		cancel_aim(false)
		ctx.send({"type": "reinforce"})
		ctx.sfx("confirm")
		return
	# (port) the game's own selection: pressing Warship twice launches one from your port
	var was: int = g.build_sel
	g.select_build(k)
	var now: int = g.build_sel
	if now == was and now != k:
		return
	aim_kind = kind if now == k else ""
	g.strike_only = now == k and (kind == "airstrike" or kind == "slug")
	_confirm_tile = -1
	_clear_ghost()
	if aim_kind == "":
		bar.set_placing("")
		ctx.set_aim("", -1, 0)
		ctx.world_call("set_range_mode", ["auto"])
		ctx.sfx("close", -6.0)
		on_hover(hover_tile)
		return
	if target_card != null:
		target_card.hide_card()
	ctx.world_call("set_range_mode", ["nuke_aim" if UIRules.is_nuke(kind) else "auto"])
	bar.set_placing(kind)
	ctx.hide_hint()
	ctx.sfx("click")
	on_hover(hover_tile)


## Where a slot's messages float from: just above it (the pointer when the slot is off screen).
func _anchor_pos(c) -> Vector2:
	if c is Control and c.is_visible_in_tree():
		var r: Rect2 = c.get_global_rect()
		return Vector2(r.get_center().x, r.position.y - 6.0)
	return ctx.mouse_pos()


## A key went down. True when it was used. (Port: Tab is the console, and the game keeps its own
## keys: I for ICBM, R for reinforcements, - and = for the game speed.)
func on_key(key: int, echo: bool) -> bool:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT) or ctx.pause_menu_open():
		return false
	if echo and key != KEY_Q and key != KEY_E:
		return false
	var scr: String = ui.screen() if ui != null else ""
	var handled := true
	if key == KEY_X:
		handled = escape()
	elif key == KEY_H:
		ui.toggle_help()
	elif key == KEY_TAB:
		# the leaderboard (UIInteract: Tab, as in most games), not on the title screen; the owner console's
		# Esc then Tab is taken first by game/shop.gd _input
		if scr == "title":
			handled = false
		else:
			ui.toggle_leaderboard()
	elif key == KEY_SPACE:
		if scr == "play" or scr == "spawn":
			primary_at_hover()
		else:
			handled = false
	elif key == KEY_BACKSPACE:
		handled = scr == "play" and enabled and retreat_latest()
	elif key == KEY_Q or key == KEY_E:
		if scr == "play" and enabled:
			ctx.step_ratio(1 if key == KEY_E else -1)
			if not echo:
				_held[key] = {"t": 0.0, "next": REPEAT_DELAY}
		else:
			handled = false
	else:
		if HOTKEY_INDEX.has(key) and scr == "play" and enabled:
			select_action(UIRules.ACTIONS[HOTKEY_INDEX[key]])
		else:
			handled = false
	return handled


func _key_repeat(delta: float) -> void:
	if _held.is_empty():
		return
	for key in _held.keys():
		if not Input.is_key_pressed(key):
			_held.erase(key)
			continue
		var h: Dictionary = _held[key]
		h.t += delta
		while h.t >= h.next:
			h.next += REPEAT_RATE
			on_key(key, true)


## Esc (or X): close the innermost open thing. True when something was closed.
func escape() -> bool:
	if radial.is_open:
		radial.close()
		return true
	if unit_card != null and unit_card.is_open:
		deselect_unit(true)
		return true
	if target_card != null and target_card.is_open:
		target_card.hide_card(true)
		return true
	if aim_kind != "":
		cancel_aim()
		return true
	if ui != null and ui.help.is_open:
		ui.help.close()
		return true
	if ui != null and ui.pause.is_open:
		ui.pause.close()
		return true
	if tooltip.is_shown() and tooltip.place == Tooltip.PLACE_PINNED:
		tooltip.hide_tip()
		return true
	return false


# ---------------------------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------------------------
## Leaves placement. (The game owns the selection: this clears its build slot.)
func cancel_aim(play_sound: bool = true) -> void:
	if aim_kind == "":
		return
	var was_mirv := aim_kind == "mirv"
	aim_kind = ""
	_confirm_tile = -1
	_clear_ghost()
	ctx.session.g.build_sel = -1
	if bar != null:
		bar.set_placing("")
	ctx.set_aim("", -1, 0)
	ctx.world_call("set_range_mode", ["auto"])
	if was_mirv:
		ctx.world_call("set_selected_owner", [0])
	if play_sound:
		ctx.sfx("close", -6.0)
	on_hover(hover_tile)


## (port) The Airfield and Railgun slots build on your own land and fire at anything else.
func _aim_for(tile: int) -> String:
	var g = ctx.session.g
	if (aim_kind == "airfield" or aim_kind == "railgun") and g._is_strike_click(int(g.build_sel), tile, int(g.PLAYER)):
		return "airstrike" if aim_kind == "airfield" else "slug"
	return aim_kind


static func _shift_down() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


func _tile_distance(a: int, b: int) -> float:
	var w: int = ctx.state.map.W
	return Vector2(a % w - b % w, a / w - b / w).length()


## How far the second click may land from the locked target: 6 tiles, or 14 screen px when the map is
## zoomed out far enough that a hand's jitter spans more tiles than that.
func _confirm_radius() -> float:
	var g = ctx.session.g
	var ppt: float = maxf(0.01, g.cam.zoom.x * float(g.TS))
	return maxf(6.0, 14.0 / ppt)


## A click while placing: build / upgrade here, or lock and then launch a nuke.
func _place(tile: int, pos: Vector2) -> void:
	var kind := _aim_for(tile)
	var av: Dictionary = ctx.rules.availability(kind)
	if not av.ok:
		ctx.sfx("deny")
		_float(str(av.reason), "info", UITheme.RED, pos)
		cancel_aim(false)
		return
	if ctx.touch and place_confirm != null:
		_move_ghost(tile, pos)
		return
	var pl: Dictionary = ctx.rules.placement(kind, tile)
	if not pl.ok:
		ctx.sfx("deny", -4.0)
		_float(str(pl.reason), "info", UITheme.RED, pos)
		return
	if pl.get("tile") != null:
		tile = int(pl.tile)  # the snapped site / the structure an upgrade applies to
	if UIRules.is_nuke(kind):
		var now := UICtx.msec()
		var confirmed: bool = _confirm_tile >= 0 and now - _confirm_msec < 6000.0 and _tile_distance(_confirm_tile, tile) <= _confirm_radius()
		if UIRules.is_strike(kind):
			confirmed = true
			_confirm_tile = tile
		if not confirmed:
			_confirm_tile = tile
			_confirm_msec = now
			ctx.sfx("click")
			var what: String = UIRules.TITLES[kind]
			on_hover(tile)
			var n_sam := int(ctx.world_call("aim_sams", [tile]))
			var verb := "Tap" if ctx.touch else "Click"
			if n_sam > 0 and kind != "mirv":
				_float("Target inside %d enemy SAM%s: the %s may be shot down. %s again to launch" % [n_sam, "" if n_sam == 1 else "s", what, verb], "sam", UITheme.RED, pos)
			else:
				_float("Target locked. %s again to launch the %s" % [verb, what], "target", UITheme.RED, pos)
			return
		var at := _confirm_tile
		if _send(kind, at, true):
			_float(str(UIRules.TITLES[kind]) + " launched", kind, UITheme.RED, pos)
			cancel_aim(false)
		else:
			# (port) the game refused the launch and said why in the event feed: keep aiming
			ctx.sfx("deny", -4.0)
			_confirm_tile = -1
		return
	_send_build(kind, tile, pl, pos)
	if not _shift_down():
		cancel_aim(false)


## (port) The order itself is the game's try_build (range system, ICBM mode, its own reasons);
## true when it went through. The game clears its build slot on some successes: put it back, so
## leaving placement stays this file's decision (Shift keeps building).
func _send(kind: String, tile: int, _nuke: bool) -> bool:
	var g = ctx.session.g
	var k: int = g.build_sel
	if k < 0:
		k = int(RWGameState.BUILD_ID.get(kind, -1))
	if k < 0:
		return false
	var ok: bool = g.try_build(k, tile)
	if aim_kind != "":
		g.build_sel = k
	return ok


func _send_build(kind: String, tile: int, pl: Dictionary, pos: Vector2) -> void:
	var av: Dictionary = ctx.rules.availability(kind)
	if not _send(kind, tile, false):
		return
	if kind == "city" and ctx.coach != null:
		ctx.coach.complete("city")
	var title: String = UIRules.TITLES[kind]
	if pl.get("upgrade", false):
		_float("%s upgraded to Lv %d  ·  %s gold" % [title, int(pl.get("level", 2)), UITheme.fmt_cost(av.cost)], kind, UITheme.GOLD, pos)
	else:
		_float("%s  ·  %s gold" % [title, UITheme.fmt_cost(av.cost)], kind, UITheme.GOLD, pos)


func _show_aim(t: int, pl: Dictionary, locked: bool = false) -> void:
	var nuke := UIRules.is_nuke(aim_kind)
	var ok: bool = locked or pl.get("ok", false) == true
	var at: int = int(pl.get("tile", t)) if (ok and pl.get("tile") != null) else t
	var radius: float = ctx.rules.nuke_radius(aim_kind) if nuke else 0.0
	if aim_kind == "mirv":
		radius = 0.0
		ctx.world_call("set_selected_owner", [ctx.state.tile_owner(at) if ok else 0])
	ctx.set_aim("nuke" if nuke else "build", at, radius, ok, aim_kind, int(pl.get("level", 1)))


## Touch: put the ghost at `tile` and show the confirm buttons beside it.
func _move_ghost(tile: int, pos: Vector2, quiet: bool = false) -> void:
	var kind := aim_kind
	var pl: Dictionary = ctx.rules.placement(kind, tile)
	_ghost_anchor = pos
	_ghost_raw = tile
	_ghost_hit = ctx.tile_at(pos)
	_ghost_res = pl
	var ok: bool = pl.get("ok", false) == true
	var moved_to: int = int(pl.tile) if (ok and pl.get("tile") != null) else tile
	var changed := moved_to != _ghost_tile
	_ghost_tile = moved_to
	_show_aim(_ghost_tile, pl)
	place_confirm.show_for(_ghost_tile, _ghost_caption(kind, pl), UIRules.is_nuke(kind), ok)
	if not quiet or changed:
		ctx.sfx("click" if ok else "deny", -8.0)


func _ghost_caption(kind: String, pl: Dictionary) -> String:
	var title: String = UIRules.TITLES[kind]
	if not pl.get("ok", false):
		var r := str(pl.get("reason", ""))
		return r if r != "" else "Can't place here"
	var cost := UITheme.fmt_cost(ctx.rules.availability(kind).cost)
	if pl.get("upgrade", false):
		return "Upgrade %s -> Lv %d · %s" % [UIRules.SHORT[kind], int(pl.get("level", 2)), cost]
	if kind == "warship":
		return "Warship patrols here · " + cost
	if UIRules.is_nuke(kind):
		var n_sam := int(ctx.world_call("aim_sams", [_ghost_tile]))
		if n_sam > 0 and kind != "mirv":
			return "%d SAM%s cover this target" % [n_sam, "" if n_sam == 1 else "s"]
		return "Launch %s · %s" % [UIRules.SHORT[kind], cost]
	return "%s · %s" % [title, cost]


## The confirm button beside the ghost.
func confirm_ghost() -> void:
	if aim_kind == "" or _ghost_tile < 0:
		return
	var kind := aim_kind
	var pos := ctx.tile_screen_pos(_ghost_tile)
	var at := pos if pos.x >= 0.0 else ctx.mouse_pos()
	var av: Dictionary = ctx.rules.availability(kind)
	if not av.ok:
		ctx.sfx("deny")
		_float(str(av.reason), "info", UITheme.RED, at)
		return
	var pl: Dictionary = ctx.rules.placement(kind, _ghost_raw if not UIRules.is_nuke(kind) else _ghost_tile)
	if not pl.ok:
		ctx.sfx("deny", -4.0)
		_float(str(pl.reason), "info", UITheme.RED, at)
		_move_ghost(_ghost_raw, _ghost_anchor)
		return
	if UIRules.is_nuke(kind):
		if _send(kind, _ghost_tile, true):
			_float(str(UIRules.TITLES[kind]) + " launched", kind, UITheme.RED, at)
	else:
		_send_build(kind, int(pl.tile) if pl.get("tile") != null else _ghost_tile, pl, at)
	cancel_aim(false)


func _clear_ghost() -> void:
	_ghost_tile = -1
	_ghost_raw = -1
	_ghost_anchor = Vector2(-1, -1)
	_ghost_res = {}
	if place_confirm != null:
		place_confirm.hide_confirm()


## The map moved under a placed ghost (drag, zoom): keep the ghost under the same screen point.
func _follow_ghost() -> void:
	if _ghost_tile < 0 or aim_kind == "" or _ghost_anchor.x < 0.0:
		return
	var t := ctx.tile_at(_ghost_anchor)
	if t < 0 or t == _ghost_hit:
		return
	_move_ghost(pick(t, _ghost_anchor), _ghost_anchor, true)


## Aims that take two clicks: nukes on desktop (touch confirms with the floating button instead).
func _locks_target(kind: String) -> bool:
	return UIRules.is_nuke(kind) and not ctx.touch


# ---------------------------------------------------------------------------------------------
# Warships
# ---------------------------------------------------------------------------------------------
## The warship under `pos` (screen px), 0 for none; `radius` <= 0 uses the default pick radius.
func unit_at(pos: Vector2, radius: float = -1.0) -> int:
	var s = ctx.state
	if s == null:
		return 0
	var r := radius if radius > 0.0 else (UNIT_PICK_TOUCH if ctx.touch else UNIT_PICK_MOUSE)
	var best := 0
	var bd := r * r
	for u in s.units():
		if u.kind != Defs.U_WARSHIP or u.get("path", []).is_empty():
			continue
		# (the ship's exact position, not its tile's centre)
		var p: Vector2 = ctx.world_call("screen_pos_of_world", [u.raw.pos])
		if p.x < 0.0:
			continue
		var d := p.distance_squared_to(pos)
		if d <= bd and (d < bd or best == 0 or int(u.uid) < best):
			bd = d
			best = int(u.uid)
	return best


func select_unit(uid: int) -> void:
	if target_card != null:
		target_card.hide_card()
	tooltip.hide_tip()
	unit_card.show_unit(uid)
	ctx.world_call("set_selected_unit", [uid])


func deselect_unit(user: bool = false) -> void:
	if unit_card != null and unit_card.is_open:
		unit_card.hide_card(user)
	ctx.world_call("set_selected_unit", [-1])


func _move_selected(tile: int, pos: Vector2) -> void:
	var uid := unit_card.uid
	# (port) the game says why a ship cannot sail somewhere: another sea, not water
	var err: String = ctx.session.move_warship(uid, tile)
	if err != "":
		ctx.sfx("deny", -4.0)
		_float(err, "info", UITheme.RED, pos)
		return
	unit_card.mark_destination(tile)
	ctx.sfx("click", -4.0)
	_float("Warship moving", "warship", UITheme.CYAN, pos)


## Where on screen a click on `tile` landed: the pointer if it is on that tile, else the tile.
func tap_pos(tile: int) -> Vector2:
	var pos := ctx.mouse_pos()
	if ctx.tile_at(pos) == tile:
		return pos
	var c := ctx.tile_screen_pos(tile)
	return c if c.x >= 0.0 else pos


## Forgiving pick: a click that just misses land (a coast, a thin island) takes the nearest land
## within a few pixels.
func pick(tile: int, pos: Vector2) -> int:
	var s = ctx.state
	if s == null or ctx.world == null:
		return tile
	var map = s.map
	if aim_kind != "" and (UIRules.is_nuke(aim_kind) or aim_kind == "warship"):
		return tile
	if ctx.tile_at(pos) != tile:
		var c := ctx.tile_screen_pos(tile)
		if c.x >= 0.0:
			pos = c
	var own_build := aim_kind != ""
	var me := ctx.me()
	var good := func(t: int) -> bool:
		if t < 0:
			return false
		if own_build:
			return s.tile_owner(t) == me and map.is_land(t)
		return map.is_contestable(t)
	if good.call(tile):
		return tile
	var r_max := PICK_TOUCH_PX if ctx.touch else PICK_MOUSE_PX
	var prefer_owner: int = s.tile_owner(tile) if (tile >= 0 and map.is_land(tile)) else -1
	var best := -1
	var best_score := INF
	var rings := [r_max * 0.35, r_max * 0.7, r_max] if ctx.touch else [r_max]
	for r: float in rings:
		var n := 8 if r < 10.0 else (12 if r < 18.0 else 16)
		for i in n:
			var a := TAU * i / n
			var t := ctx.tile_at(pos + Vector2(cos(a), sin(a)) * r)
			if not good.call(t):
				continue
			var score := r
			if prefer_owner >= 0 and s.tile_owner(t) != prefer_owner:
				score += r_max * 0.5
			if score < best_score:
				best_score = score
				best = t
	if best >= 0:
		return best
	var span := _px_to_tiles(r_max, pos)
	if tile >= 0 and span > 0:
		var w: int = map.W
		var h: int = map.H
		var cx := tile % w
		var cy := tile / w
		var bd := INF
		for dy in range(-span, span + 1):
			var y := cy + dy
			if y < 0 or y >= h:
				continue
			for dx in range(-span, span + 1):
				var x := cx + dx
				if x < 0 or x >= w:
					continue
				var t2 := y * w + x
				if good.call(t2):
					var d := float(dx * dx + dy * dy)
					if d < bd:
						bd = d
						best = t2
	return best if best >= 0 else tile


func _px_to_tiles(px: float, pos: Vector2) -> int:
	var a := ctx.tile_at(pos)
	var b := ctx.tile_at(pos + Vector2(px, 0))
	if a < 0 or b < 0:
		return 1
	var w: int = ctx.state.map.W
	return clampi(maxi(absi(a % w - b % w), absi(a / w - b / w)), 1, 6)


# ---------------------------------------------------------------------------------------------
# The action ring
# ---------------------------------------------------------------------------------------------
## Right-click (long-press) on the map: the ring of actions for that tile.
func on_context(tile: int, screen_pos: Vector2) -> void:
	if not enabled or ctx.state == null:
		return
	var now := UICtx.msec()
	if now - _last_ctx_msec < 350:
		return
	_last_ctx_msec = now
	if tile < 0:
		return
	var s = ctx.state
	if s.phase == Defs.PHASE_SPAWN:
		return
	tooltip.hide_tip()
	var own: int = s.tile_owner(tile)
	var title := ctx.terrain_title(tile)
	var col: Color = UITheme.TEXT_2
	if own != 0:
		title = s.owner_name(own)
		col = UITheme.owner_ui_color(s.owner_color(own))
	elif s.map.is_contestable(tile):
		title = "Unclaimed " + ctx.terrain_title(tile).to_lower()
	radial.open_at(tile, screen_pos, ctx.rules.radial_items(tile), title, col)


func on_radial(id: String, tile: int) -> void:
	var Th := UITheme
	var s = ctx.state
	if s == null:
		return
	var own: int = s.tile_owner(tile)
	var pos := radial.center
	# "build:<kind>" or "build:<kind>:<amount>" (the bulk ring: several levels at once), likewise nukes
	if id.begins_with("build:"):
		var parts := id.split(":")
		var k := parts[1]
		var n := maxi(1, int(parts[2]) if parts.size() > 2 else 1)
		var cost: float = ctx.rules.bulk_cost(k, n) if n > 1 else ctx.rules.cost(k)
		ctx.send({"type": "build", "kind": k, "tile": tile, "amount": n})
		_float("%s%s  ·  %s gold" % [UIRules.TITLES[k], " ×%d" % n if n > 1 else "", Th.fmt_cost(cost)], k, Th.GOLD, pos)
		return
	if id.begins_with("nuke:"):
		var nparts := id.split(":")
		var nk := nparts[1]
		var nn := maxi(1, int(nparts[2]) if nparts.size() > 2 else 1)
		ctx.send({"type": "nuke", "kind": nk, "tile": tile, "amount": nn})
		_float("%s%s launched at %s" % [UIRules.TITLES[nk], " ×%d" % nn if nn > 1 else "", s.owner_name(own)], nk, Th.RED, pos)
		return
	if id == "attack":
		var act: Dictionary = ctx.rules.primary(tile)
		ctx.send({"type": "attack", "tile": tile, "ratio": ctx.order_ratio()})
		_float(ctx.rules.confirm_text(act), "attack", Th.AMBER if own != 0 else Th.GREEN, pos)
	elif id == "boat":
		var landing: int = ctx.rules.boat_landing(tile)
		ctx.send({"type": "boat", "tile": landing if landing >= 0 else tile, "ratio": ctx.order_ratio()})
		var act2: Dictionary = ctx.rules.primary(tile)
		act2.type = "boat"
		_float(ctx.rules.confirm_text(act2), "boat", Th.CYAN, pos)
	elif id == "ally_request":
		ctx.send({"type": "ally_request", "target": own})
		ctx.sfx("click")
		_float("Alliance proposed to " + s.owner_name(own), "alliance", Th.VIOLET, pos)
	elif id == "ally_accept":
		ctx.send({"type": "ally_reply", "target": own, "accept": true})
		_float("Alliance accepted", "alliance", Th.VIOLET, pos)
	elif id == "ally_extend":
		ctx.send({"type": "ally_extend", "target": own})
	elif id == "ally_break:yes":
		# (upstream asks on the ally card; until that card is ported the ring's own sub-ring asks)
		ctx.send({"type": "ally_break", "target": own})
		ctx.sfx("deny", -2.0)
		_float("You broke your alliance with " + s.owner_name(own), "betray", Th.RED, pos)
	elif id == "donate":
		donate_to(own, pos)
	elif id == "donate_gold":
		ctx.send({"type": "donate_gold", "target": own})
	elif id == "retreat":
		var aid := my_attack_on(own)
		if aid >= 0:
			retreat(aid)
	elif id == "focus":
		ctx.world_call("focus_tile", [tile])
	elif id == "info":
		show_inspect(tile)


## Send troops to ally `own` (ratio share, capped at their troop headroom; see UIRules.donate_plan)
## with a float at `pos`. False (and a deny float) when nothing useful can be sent.
func donate_to(own: int, pos: Vector2) -> bool:
	var Th := UITheme
	var plan: Dictionary = ctx.rules.donate_plan(own)
	var nm: String = ctx.state.owner_name(own)
	if plan.want < 1 or plan.full or plan.amount < 1:
		ctx.sfx("deny", -4.0)
		_float("No troops to spare" if plan.want < 1 else nm + " is at its troop cap", "info", Th.RED, pos)
		return false
	ctx.send({"type": "donate", "target": own, "troops": plan.amount})
	_float("Sent %s troops  ·  %s is now at its troop cap" % [Th.fmt_troops(plan.amount), nm] if plan.capped else "Sent %s troops to %s" % [Th.fmt_troops(plan.amount), nm], "donate", Th.GREEN, pos)
	return true


## Our newest outgoing attack against `target` (0 = expansion), or -1.
func my_attack_on(target: int) -> int:
	var best := -1
	if ctx.state == null:
		return best
	var mine := ctx.me()
	for a in ctx.state.attacks():
		if a.attacker == mine and a.target == target and a.aid > best:
			best = a.aid
	return best


func retreat(aid: int) -> void:
	var s = ctx.state
	if s == null:
		return
	for a in s.attacks():
		if a.aid == aid:
			ctx.send({"type": "retreat", "attack_id": aid})
			ctx.sfx("click")
			var who: String = s.owner_name(a.target) if a.target != 0 else "neutral land"
			_float("Retreating from " + who, "retreat", UITheme.CYAN, ctx.mouse_pos())
			return


## Backspace: pull back the most recent outgoing attack.
func retreat_latest() -> bool:
	var s = ctx.state
	if s == null:
		return false
	var best := -1
	var mine := ctx.me()
	for a in s.attacks():
		if a.attacker == mine and a.aid > best:
			best = a.aid
	if best < 0:
		return false
	retreat(best)
	return true


func _float(text: String, icon_name: String, col: Color, pos: Vector2) -> void:
	if not FloatText.bounds_provider.is_valid():
		FloatText.bounds_provider = float_bounds
	FloatText.spawn(float_layer, pos, text, icon_name, col, float_bounds())


## Where floating confirmations may appear: below the top bar row, above the command bar / tray.
func float_bounds() -> Rect2:
	var area := ctx.clear_rect()
	var bottom: float = bar.top_edge() if (bar != null and bar.is_visible_in_tree()) else area.end.y
	return Rect2(area.position, Vector2(area.size.x, minf(area.end.y, bottom) - area.position.y))


## The pinned card for a tile (the ring's Info).
func show_inspect(tile: int) -> void:
	var spec := hover_spec(tile, true)
	if spec.is_empty():
		return
	# Bottom-left above the command bar: the right column holds the Attacks panel on phones.
	var area := ctx.clear_rect()
	var bottom: float = bar.top_edge() - 8.0 if bar.is_visible_in_tree() else area.end.y
	tooltip.show_pinned(spec, Rect2(area.position.x, area.position.y, 0.0, bottom - area.position.y))
	# Never cover the tapped spot: move to the right when it lies under the card.
	var tp := ctx.tile_screen_pos(tile)
	if tp.x >= 0 and tooltip.target_rect().grow(24.0).has_point(tp):
		tooltip.show_pinned(spec, Rect2(area.end.x, area.position.y, 0.0, bottom - area.position.y))
	# A tapped SAM / defense post shows its range ring while the card is open.
	_range_focus = tile
	ctx.world_call("set_range_focus", [tile])
