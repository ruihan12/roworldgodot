# Live ports of tests/bot_skill.luau, sim_bots.luau (bot players, spawn shield, tribes) and the
# simsys_ai.luau planner cases (build choice, gold floor and gap, warship tracking, nukes, cadence).
extends RefCounted

var H
var hs
var m
var P := 1

func _bots() -> Array:
	var out := []
	for id in range(2, m.nations.size()):
		if m.is_bot(id): out.append(id)
	return out

func _first(cond: Callable) -> int:
	for id in range(2, m.nations.size()):
		if m.nations[id].alive and cond.call(id): return id
	return -1

func run(harness, tree) -> void:
	H = harness
	hs = load("res://sim/headless_sim.gd").new(tree)
	await hs.ready_async()
	m = hs.m
	m.boat_speed = 1.5; m.warship_speed = 1.0
	_bot_players()
	_spawn_shield()
	_planner()
	_tribes()
	_solo()
	if is_instance_valid(m): m.queue_free()

func _bot_players() -> void:
	H.section("bot_skill (live)", "bot_skill.luau")
	m.diff_i = 1
	m.bot_players = 20
	var home: int = hs.start(0, 0, Vector2(0.5, 0.38), 0, 5e8)
	var bots := _bots()
	var smart := 0; var novice := 0
	for b in bots:
		if m.is_novice_bot(b): novice += 1
		else: smart += 1
	H.expect(bots.size() == 20 and smart == m.smart_bots and novice == 20 - m.smart_bots, "%d smart, %d novice bots" % [smart, novice], "bots=%d home=%d" % [bots.size(), home])
	var nb := -1; var sb := -1
	for b in bots:
		if m.is_novice_bot(b) and nb < 0: nb = b
		if not m.is_novice_bot(b) and sb < 0: sb = b
	if nb < 0 or sb < 0:
		H.fail("bot split", "no novice or no smart bot"); return
	H.expect(m.ai_difficulty(nb) == m.NOVICE_SKILL, "novices play the Easy AI")
	H.expect(m.nations[nb].troops == m.sim_rules.start_troops(SimRules.KIND_NATION, 0), "novices start with the Easy nation's troops", "troops=%s" % str(m.nations[nb].troops))
	H.expect(m.nations[sb].troops == SimRules.START_TROOPS_HUMAN, "smart bots start with human troops")
	H.expect(absf(m.troop_cap(nb) - m.sim_rules.max_troops(SimRules.KIND_NATION, m.nations[nb].land, 0, 0)) < 0.01, "novices use the Easy nation's troop cap")
	H.expect(m.ai_difficulty(sb) == m.SMART_SKILL and m.SMART_SKILL == 1, "smart bot players play the Medium AI")
	H.expect(SimRules.SMART_VS_PLAYERS == 0 and m.human_difficulty(sb) == 0, "but follow Easy's rules towards players (SMART_VS_PLAYERS)")
	H.expect(m.human_difficulty(nb) == 0, "novices: Easy towards players")
	var nation := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION)
	H.expect(nation > 0 and m.human_difficulty(nation) == m.diff_i, "a nation keeps its match's rules (Medium here)")
	H.expect(m.ai_difficulty(P) == m.diff_i and not m.is_novice_bot(P) and not m.is_bot(P), "real players are untouched")
	H.expect(m.kind_of(sb) == SimRules.KIND_HUMAN and m.is_prot(sb), "bot players count as people (kind HUMAN) and build like nations")
	# which bots are smart is deterministic for the match RNG
	m.rng.seed = 5
	var a: Array = m.add_bot_players(20)
	m.rng.seed = 5
	var b: Array = m.add_bot_players(20)
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		if m.is_novice_bot(a[i]) != m.is_novice_bot(b[i]): same = false
	H.expect(same, "which bots are smart is deterministic")
	for id in a + b: m.nations[id].alive = false
	# novices leave real players alone twice as long
	m.peace = 0.0; m.elapsed = 1.0
	m.shield_until.clear()
	m.sim_ai.attackers_on.clear()
	var base: int = m.sim_rules.human_grace_ticks(0) + int(m.sim_ai.st[nb].grace_jitter)
	var smart_base: int = m.sim_rules.human_grace_ticks(0) + int(m.sim_ai.st[sb].grace_jitter)
	var extra: int = m.sim_ai.HUMAN_GRACE_MAX_EXTRA
	H.expect(not m.sim_ai._may_attack_human(nb, P, base * 2 - 1), "a novice waits twice the Easy grace before attacking a player")
	H.expect(m.sim_ai._may_attack_human(nb, P, base * 2 + extra + 1), "and may attack after it", "base=%d" % base)
	H.expect(m.sim_ai._may_attack_human(sb, P, smart_base + extra + 1), "a smart bot waits the Easy grace (no doubling)")

func _spawn_shield() -> void:
	H.section("spawn_shield (live)", "sim_bots.luau spawn_shield")
	H.expect(not m.is_solo(), "a match with bot players is not solo")
	m.begin_shields()
	var bots := _bots().filter(func(id): return m.nations[id].alive and m.nations[id].land > 0)
	var bt: int = bots[0] if not bots.is_empty() else -1
	H.expect(m.shielded(P) and bt > 0 and m.shielded(bt), "every person gets a spawn shield when play starts")
	H.expect(int(m.shield_until[P]) - m.sim_atk.tick == SimRules.SPAWN_SHIELD_TICKS and SimRules.SPAWN_SHIELD_TICKS == 300, "the shield lasts 30 s (300 ticks)")
	if bt > 0:
		H.expect(not m.launch_attack(P, bt, 0.2), "no one can attack a shielded person")
		var nation := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION)
		m.peace = 0.0; m.elapsed = 1.0
		H.expect(not m.sim_ai._may_attack_human(nation, bt, 100000), "the AI respects the spawn shield")
	var tribe := _first(func(id): return m.kind_of(id) == SimRules.KIND_TRIBE and m.nations[id].land > 0)
	if tribe > 0:
		m.launch_attack(P, tribe, 0.01)
		H.expect(m.shielded(P), "attacking a tribe keeps one's own shield")
	var nat := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION and m.nations[id].land > 0)
	if nat > 0:
		m.launch_attack(P, nat, 0.01)
		H.expect(not m.shielded(P), "attacking a nation drops one's own shield")
	hs.step(SimRules.SPAWN_SHIELD_TICKS + 1)
	H.expect(bt <= 0 or not m.shielded(bt), "shields end after 300 ticks")

func _planner() -> void:
	H.section("simsys_ai planner (live)", "simsys_ai.luau")
	var ai = m.sim_ai
	var t: int = m.sim_atk.tick
	# build choice: a coastal nation's first building is a port
	var coastal := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION and m.nations[id].land > 50 and ai.own_coast(id) >= 0 and m.owned_count(id, 1) == 0)
	if coastal < 0:
		H.ok("port-first case skipped: no coastal nation without a port")
	else:
		var s: Dictionary = ai.st[coastal]
		s.crowded_first = false; s.last_build = t - 100
		m.nations[coastal].gold = 5e6
		var before: int = m.owned_count(coastal, 1)
		ai._consider_build(coastal, 5000)
		H.expect(m.owned_count(coastal, 1) == before + 1, "coastal nation builds a port first (PORT_FIRST)", "ports %d -> %d" % [before, m.owned_count(coastal, 1)])
		H.expect(int(s.last_build) == m.sim_atk.tick, "last_build is stamped")
		var n0: int = m.structs.size()
		ai._consider_build(coastal, 5000)
		H.expect(m.structs.size() == n0, "no second build inside the 20-tick gap")
		s.last_build = t - 100
		m.nations[coastal].gold = 99999.0
		ai._consider_build(coastal, 5000)
		H.expect(m.structs.size() == n0, "nothing is built below 100K gold")
	H.expect(ai.PORT_PER_CITY == 0.75 and ai.PORT_FIRST, "ports while fewer than 0.75 x cities")
	# warship tracking by difficulty
	var porter := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION and m.owned_count(id, 1) > 0)
	if porter > 0:
		var keep: int = m.diff_i
		m.diff_i = 0
		H.expect(not m._tracks_ships(porter), "Relaxed nations never track ship losses")
		m.diff_i = 2
		H.expect(m._tracks_ships(porter), "Hard nations with a port track ship losses")
		m.diff_i = keep
	H.expect(m.WARSHIP_RETALIATE_P[2] == 0.5 and m.WARSHIP_RETALIATE_P[0] == 0.0 and ai.WARSHIP_FLEET_CAP == 10, "Hard retaliates with a warship half the time; fleet cap 10")
	# nukes: none before NUKE_AGE, NUKE_GAP 3 min
	var nuker := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION and m.nations[id].land > 100)
	if nuker > 0:
		var tile: int = ai.centre_tile(nuker)
		if tile >= 0 and m.owned_count(nuker, 5) == 0:
			m._struct_add(5, tile, nuker)
			if m.struct_at.has(tile): m.struct_at[tile].bt = 0.0
		m.nations[nuker].gold = 1e9
		m.peace = 0.0; m.elapsed = 1e6
		var ms0: int = m.missiles.size()
		ai.st[nuker].last_nuke = -100000
		ai._consider_nuke(nuker, ai.NUKE_AGE[m.ai_difficulty(nuker)] - 1)
		H.expect(m.missiles.size() == ms0, "no nukes before NUKE_AGE")
	H.expect(ai.NUKE_AGE[1] == 3600 and ai.NUKE_GAP == 1800, "NUKE_AGE 6 min on Standard; NUKE_GAP 3 min")
	var src := FileAccess.get_file_as_string("res://sim/ai.gd")
	H.expect(src.find("_land_share(best) >= 0.35") >= 0, "MIRV only at the leader holding >= 35 %")
	H.expect(src.find("g.kind_of(p) == SimRules.KIND_TRIBE or g.nations[p].land < 400") >= 0, "tribes are never nuked")
	# attack cadence by difficulty
	var cad := _first(func(id): return m.kind_of(id) == SimRules.KIND_NATION)
	var ok := true
	var keep2: int = m.diff_i
	for d in 3:
		m.diff_i = d
		for _i in 20:
			ai._first_attack(cad)
			var r: Array = ai.NATION_ATTACK_RATE[d]
			var rate: int = ai.st[cad].attack_rate
			if rate < int(r[0] * m.sim_rules.ai_rate_mult) or rate > int(r[1] * m.sim_rules.ai_rate_mult): ok = false
	m.diff_i = keep2
	H.expect(ok, "attack cadence follows attackRate by difficulty (65-100 / 55-70 / 45-60 ticks)")
	var nb := _first(func(id): return m.is_novice_bot(id))
	if nb > 0:
		ai._first_attack(nb)
		var rate2: int = ai.st[nb].attack_rate
		H.expect(rate2 >= int(65 * m.sim_rules.ai_rate_mult) and rate2 <= int(100 * m.sim_rules.ai_rate_mult), "novice bots attack at the Easy cadence")

func _tribes() -> void:
	H.section("tribes_rules (live)", "sim_bots.luau tribes_rules")
	var ai = m.sim_ai
	var ok := true; var n := 0
	for id in range(2, m.nations.size()):
		if m.kind_of(id) != SimRules.KIND_TRIBE or not ai.st.has(id): continue
		n += 1
		var s: Dictionary = ai.st[id]
		var lo := int(ai.TRIBE_ATTACK_RATE[0] * m.sim_rules.ai_rate_mult); var hi := int(ai.TRIBE_ATTACK_RATE[1] * m.sim_rules.ai_rate_mult)
		if s.attack_rate < lo or s.attack_rate > hi or s.attack_tick < 0 or s.attack_tick >= s.attack_rate: ok = false
	H.expect(n > 0 and ok, "tribes act every 40-79 ticks at their own attack tick", "tribes=%d" % n)
	H.expect(ai.TRIBE_TRAITOR_ODDS == 3 and ai.TRIBE_SKIP_PLAYER_ODDS == 2, "tribe traitor odds 1 in 3, skip-player odds 1 in 2")

func _solo() -> void:
	H.section("spawn_shield solo (live)", "sim_bots.luau spawn_shield")
	m.bot_players = 0
	hs.start(0, 0, Vector2(0.5, 0.38), 0, 5e8)
	H.expect(m.is_solo() and not m.shielded(P), "solo matches have no spawn shield")
