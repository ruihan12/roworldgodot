# Elimination gold, as upstream Sim._eliminate (owner request 2026-11-28 "Match upstream"): the owner that took a
# player's last tile (last_by) gets Rules.conquer_gold of the gold left (all of a nation's or tribe's, half of a
# human's), once, with the "+ gold" popup only if no annex already showed it. Runs once with the Luau sim and
# once with NO_LUAU_SIM (the GDScript fallback), since the Luau growth writes gold back whole.
#   godot --headless --path . -s res://tests/test_elim_gold.gd
extends SceneTree

var fails := 0
var pops: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ok   " if ok else "  FAIL ") + what)


func _initialize() -> void:
	_run()


# hands every tile of `victim` to `by` (last_by follows, as an attack would leave it)
func _take_all(m, victim: int, by: int) -> void:
	for i in m.owner_map.size():
		if m.owner_map[i] == victim:
			m._set_owner(i, by)


func _run() -> void:
	var fallback := OS.has_environment("NO_LUAU_SIM")
	var tag := "gdscript" if fallback else "luau"
	var hs = load("res://sim/headless_sim.gd").new(self)
	await hs.ready_async()
	var m = hs.m
	hs.start(0, 0, Vector2(0.5, 0.38), 0, -1.0)
	await process_frame
	hs.step(20)
	var R: SimRules = m.sim_rules
	var alive: Array = []
	for id in range(2, m.nations.size()):
		var n = m.nations[id]
		if n.alive and n.land > 0 and m.kind_of(id) == SimRules.KIND_NATION:
			alive.append(id)
	_check(alive.size() >= 3, "%s: three live nations to work with (%d)" % [tag, alive.size()])
	if alive.size() < 3:
		_finish(fallback)
		return
	var killer: int = alive[0]
	var victim: int = alive[1]
	var annexed: int = alive[2]
	var P: int = m.PLAYER
	# a nation's last tile taken: all its gold
	m.nations[victim].gold = 1000.0
	var k0: float = m.nations[killer].gold
	_take_all(m, victim, killer)
	_check(int(m.nations[victim].get("last_by", 0)) == killer, "%s: last_by is the taker of the last tile" % tag)
	m._economy(0.1)
	var grow: float = R.gold_per_tick(m.kind_of(killer))
	_check(not m.nations[victim].alive, "%s: the nation is out" % tag)
	_check(absf(m.nations[killer].gold - (k0 + grow + 1000.0)) < 0.01, "%s: the killer took all 1000 of a nation's gold (%.2f -> %.2f, growth %.2f)" % [tag, k0, m.nations[killer].gold, grow])
	_check(m.nations[victim].gold == 0.0, "%s: the nation's gold is zeroed" % tag)
	_check(m.nations[victim].get("conq_sent", false), "%s: the conquest popup went once" % tag)
	# after an annex (gold already taken and zeroed, popup shown): nothing more, no second popup
	m.nations[annexed].gold = 0.0
	m.nations[annexed]["conq_sent"] = true
	var k1: float = m.nations[killer].gold
	_take_all(m, annexed, killer)
	m._economy(0.1)
	_check(absf(m.nations[killer].gold - (k1 + grow)) < 0.01, "%s: no double pay after an annex (%.2f -> %.2f)" % [tag, k1, m.nations[killer].gold])
	# a human (the player) loses the last tile: half
	m.nations[P].gold = 1000.0
	var k2: float = m.nations[killer].gold
	_take_all(m, P, killer)
	m._economy(0.1)
	_check(not m.nations[P].alive, "%s: the player is out" % tag)
	_check(absf(m.nations[killer].gold - (k2 + grow + 500.0)) < 0.01, "%s: the killer took half of the player's 1000 (%.2f -> %.2f)" % [tag, k2, m.nations[killer].gold])
	_check(m.nations[P].gold == 0.0, "%s: the player's gold is zeroed" % tag)
	if not fallback:
		_check(m.luau_link != null and m.luau_link.on, "luau: the Luau sim was on")
	_finish(fallback)


func _finish(fallback: bool) -> void:
	if not fallback:
		OS.set_environment("NO_LUAU_SIM", "1")
		var out := []
		var rc := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/test_elim_gold.gd"], out, true)
		var text := "\n".join(out)
		for line in text.split("\n"):
			if line.begins_with("  ok") or line.begins_with("  FAIL"):
				print(line)
		_check(rc == 0 and text.find("ELIM_GOLD_TEST PASS") >= 0, "the GDScript fallback run passes (rc %d)" % rc)
	print("ELIM_GOLD_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
