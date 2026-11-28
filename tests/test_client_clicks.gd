# Clicks through the ported UIInteract: expand, attack, the target card, placement with the
# two-click nuke lock, warship select and move.
#   godot --headless --path . --script tests/test_client_clicks.gd
extends SceneTree

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ok   " if ok else "  FAIL ") + what)


func _initialize() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.map_tab = 0; m.map_i = 0
	m.gen_map()
	m.rng.seed = 20261115; seed(20261115)
	m._start_game()
	for _f in 3: await process_frame
	var c = m.client
	var it = c.interact
	it.enabled = true
	_check(c.ctx.state.phase == Defs.PHASE_SPAWN, "spawn phase after start")
	var st: int = m._find_spawn_tile(int(m.W * 0.47), int(m.H * 0.40))
	it._last_click_tile = -1
	it.on_click(st)
	_check(m.nations[m.PLAYER].land > 0, "spawn click places the player")
	m.deploy_t = 0.0; m.state = "play"; m.peace = 0.0
	m._claim_blob(m.PLAYER, st, 60)
	m.nations[m.PLAYER].troops = 50000.0
	m.nations[m.PLAYER].gold = 1.0e9
	for _f in 3: await process_frame
	it.enabled = true

	# expand into neutral land next to us
	var W: int = m.W
	var neutral := -1
	var foe_tile := -1
	for t in m.owner_map.size():
		if m.owner_map[t] != m.PLAYER:
			continue
		for d in [1, -1, W, -W]:
			var q: int = t + d
			if q < 0 or q >= m.owner_map.size():
				continue
			var o: int = m.owner_map[q]
			if o == m.NEUTRAL and neutral < 0: neutral = q
			if o > 0 and o != m.PLAYER and foe_tile < 0: foe_tile = q
	if neutral >= 0:
		var n0: int = m.attacks.size()
		it._last_click_tile = -1
		it.on_click(neutral)
		_check(m.attacks.size() > n0, "click on neutral land starts an expansion")
	else:
		print("  (no neutral neighbour)")

	# select before attacking: the first click opens the card, the second fires
	if foe_tile >= 0:
		c.ctx.set_setting("confirm_orders_desktop", true)
		var n1: int = m.attacks.size()
		it._last_click_tile = -1
		it.on_click(foe_tile)
		_check(c.target_card.is_open and m.attacks.size() == n1, "first click opens the target card")
		it._last_click_tile = -1
		it.on_click(foe_tile)
		_check(not c.target_card.is_open and m.attacks.size() > n1, "second click fires the attack")
		c.ctx.set_setting("confirm_orders_desktop", false)
	else:
		print("  (no bordering foe)")

	# placement: a city on our own land
	var own := -1
	for t in m.owner_map.size():
		if m.owner_map[t] == m.PLAYER and m.build_req(0, t) == "":
			own = t; break
	m.select_build(0)
	for _f in 2: await process_frame
	it.enabled = true
	c._hover(0.0, true)
	_check(it.aim_kind == "city", "aim follows the game's build slot (got '%s')" % it.aim_kind)
	var s0: int = m.structs.size()
	it._last_click_tile = -1
	it.on_click(own)
	_check(m.structs.size() == s0 + 1, "click builds the city")
	_check(m.build_sel == -1 and it.aim_kind == "", "placement ends after one build")

	# a silo, then an atom bomb: the first click locks, the second launches
	var own2 := -1
	for t in m.owner_map.size():
		if m.owner_map[t] == m.PLAYER and m.build_req(5, t) == "":
			own2 = t; break
	if own2 >= 0:
		m.try_build(5, own2)
		for st2 in m.structs:
			if int(st2.o) == m.PLAYER: st2["bt"] = 0.0
		m.select_build(7)
		c._hover(0.0, true)
		_check(it.aim_kind == "atom", "atom aim (got '%s')" % it.aim_kind)
		var target := -1
		var pl := {"ok": false, "reason": "no foreign land in reach"}
		for t in range(0, m.owner_map.size(), 7):
			if m.owner_map[t] > 0 and m.owner_map[t] != m.PLAYER:
				var p2: Dictionary = c.ctx.rules.placement("atom", t)
				if p2.ok:
					target = t; pl = p2; break
		if pl.ok:
			it._last_click_tile = -1
			it.on_click(target)
			_check(it._confirm_tile >= 0 and m.build_sel == 7, "first click locks the target")
			var g0: float = m.nations[m.PLAYER].gold
			it._last_click_tile = -1
			it.on_click(target)
			_check(it.aim_kind == "" and m.build_sel == -1, "second click leaves placement")
			_check(m.nations[m.PLAYER].gold < g0, "the launch was paid for")
		else:
			print("  (atom not placeable: %s)" % str(pl.reason))
			m.build_sel = -1
	# keys and slots
	for _f in 2: await process_frame
	it.enabled = true
	m.build_sel = -1
	c._hover(0.0, true)
	_check(it.on_key(KEY_1, false) and m.build_sel == 0 and it.aim_kind == "city", "key 1 selects the City slot")
	_check(it.escape() and m.build_sel == -1 and it.aim_kind == "", "escape leaves placement")
	var r0: float = c.ctx.ratio
	it.on_key(KEY_E, false)
	_check(c.ctx.ratio > r0, "E raises the attack ratio")
	it._held.clear()
	var b0: bool = c.board.expanded
	_check(it.on_key(KEY_TAB, false) and c.board.expanded != b0, "Tab toggles the leaderboard (as upstream; the console is F2 / Esc then Tab)")
	it.on_key(KEY_TAB, false)
	print("CLIENT_CLICKS_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
