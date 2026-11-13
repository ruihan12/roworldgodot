# Headless runner for tests/upstream/*.gd
#   godot --headless --path . -s res://tests/run_upstream_tests.gd
extends SceneTree

const SUITES := [
	"res://tests/upstream/test_core_rules.gd",
	"res://tests/upstream/test_growth.gd",
	"res://tests/upstream/test_nukes.gd",
	"res://tests/upstream/test_arsenal.gd",
	"res://tests/upstream/test_alliances.gd",
	"res://tests/upstream/test_warships.gd",
	"res://tests/upstream/test_naval.gd",
	"res://tests/upstream/test_structures.gd",
	"res://tests/upstream/test_attacks.gd",
	"res://tests/upstream/test_conquest.gd",
	"res://tests/upstream/test_bot_ai.gd",
	"res://tests/upstream/test_parity_godot.gd",
]

func _init() -> void:
	print("Frontline Conquest upstream parity suite")
	call_deferred("_boot")

func _boot() -> void:
	await _run()

func _run() -> void:
	print("godot headless, %d formula files + live headless_sim" % SUITES.size())
	var hs = load("res://tests/upstream/_harness.gd")
	if hs == null:
		print("UPSTREAM_PARITY  FAIL  could not load harness")
		quit(1)
		return
	var H = hs.new()
	for path in SUITES:
		var scr = load(path)
		if scr == null or not scr.can_instantiate():
			H.section(path, path)
			H.fail("load " + path, "could not load script")
			continue
		var inst = scr.new()
		if inst == null or not inst.has_method("run"):
			H.section(path, path)
			H.fail("run " + path, "script failed to instance or has no run()")
			continue
		inst.run(H)
	var live = load("res://tests/upstream/test_live.gd")
	if live == null or not live.can_instantiate():
		H.section("live", "test_live.gd")
		H.fail("load test_live.gd", "could not load live suite")
	else:
		var inst2 = live.new()
		await inst2.run(H, self)
	var bots = load("res://tests/upstream/test_bots_live.gd")
	if bots == null or not bots.can_instantiate():
		H.section("bots live", "test_bots_live.gd")
		H.fail("load test_bots_live.gd", "could not load bots live suite")
	else:
		await bots.new().run(H, self)
	H.write_parity_md("res://docs/PARITY.md")
	var n_pass: int = H.count(H.PASS)
	var n_fail: int = H.count(H.FAIL)
	var n_miss: int = H.count(H.MISSING)
	var n_intl: int = H.count(H.INTENTIONAL)
	var n_all: int = H.results.size()
	print("")
	print("============================================================")
	print("UPSTREAM_PARITY  total=%d  pass=%d  fail=%d  missing=%d  intentional=%d" % [n_all, n_pass, n_fail, n_miss, n_intl])
	if n_fail > 0:
		print("FAILS:")
		for r in H.results:
			if r.status == H.FAIL:
				print("  - [%s] %s: %s" % [r.suite, r.name, r.detail])
	print("============================================================")
	quit(1 if n_fail else 0)
