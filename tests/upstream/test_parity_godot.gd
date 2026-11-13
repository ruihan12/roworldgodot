# Port of tests/parity_rng.luau and tests/parity_sort.luau. Upstream re-implemented Godot's RNG and
# sort_custom in Luau and checked them against reference files printed by Godot (tools/parity/*_ref.gd).
# This port runs on Godot itself, so the same generators are re-run here and must reproduce those files:
# that pins the engine build (RNG streams and tie order) the game's AI and map seeds depend on.
extends RefCounted

func _h(x: float) -> String:
	return PackedFloat64Array([x]).to_byte_array().hex_encode()

func _rng_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for s in [1, 2, 3, 12345, 0, -7]:
		out.append("hash %d %d" % [s, hash(s)])
	for s in [1, 2, 3, 12345]:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(s)
		out.append("seed %d state %d" % [s, rng.state])
		var line := "randi"
		for i in 8: line += " %d" % rng.randi()
		out.append(line)
		line = "randf"
		for i in 8: line += " " + _h(rng.randf())
		out.append(line)
		line = "randi_range"
		for i in 8: line += " %d" % rng.randi_range(-3, 3)
		for i in 8: line += " %d" % rng.randi_range(0, 600)
		for i in 4: line += " %d" % rng.randi_range(5, 5)
		for i in 4: line += " %d" % rng.randi_range(0, 2147483646)
		out.append(line)
		line = "randf_range"
		for i in 8: line += " " + _h(rng.randf_range(0.8, 1.25))
		for i in 8: line += " " + _h(rng.randf_range(0.35, 0.65))
		out.append(line)
		out.append("state_after %d" % rng.state)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash(99)
	for i in 2000: out.append(_h(rng2.randf()))
	for i in 2000: out.append(_h(rng2.randf_range(0.5, 1.5)))
	return out

func _sort_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var x := 7
	for n: int in [1, 2, 3, 5, 8, 15, 16, 17, 18, 31, 33, 50, 64, 100, 170, 257, 600, 1500]:
		for rep in 3:
			var arr: Array = []
			var keys := PackedInt32Array()
			for i in n:
				x = (x * 16807) % 2147483647
				var k := x % (3 + rep * n / 4 + 1)
				keys.append(k)
				arr.append([k, i])
			arr.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
			var line := "%d" % n
			for k2 in keys: line += " %d" % k2
			line += " |"
			for e: Array in arr: line += " %d" % int(e[1])
			out.append(line)
	return out

func _compare(H, got: PackedStringArray, path: String, what: String) -> void:
	var want := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var bad := 0
	var first := ""
	for i in maxi(want.size(), got.size()):
		var w := want[i].strip_edges() if i < want.size() else "<missing>"
		var g := got[i].strip_edges() if i < got.size() else "<missing>"
		if w != g:
			bad += 1
			if first == "": first = "line %d: want %s got %s" % [i + 1, w.left(60), g.left(60)]
	H.expect(bad == 0, what, "%d lines, %d differ %s" % [want.size(), bad, first])

func run(H) -> void:
	H.section("parity_rng", "parity_rng.luau")
	_compare(H, _rng_lines(), "res://tests/fixtures/parity/rng_ref.txt", "Godot RandomNumberGenerator reproduces upstream's reference stream (hash, state, randi, randf, ranges)")
	H.section("parity_sort", "parity_sort.luau")
	_compare(H, _sort_lines(), "res://tests/fixtures/parity/sort_ref.txt", "Array.sort_custom orders ties exactly like upstream's reference")
	H.section("map_scale", "map_scale.luau")
	H.intentional("public matches play a map at 80 % (world@80) with k_lin scaled", "no public matches in this single-player port; maps always play at full size")
	H.section("sim_smoke / sim_matches / sim_gamestate / sim_mirror / sliced_step / sim_coop", "sim_bots.luau")
	H.intentional("GameState snapshot / client mirror / sliced stepping / co-op netcode", "networking layer of the Roblox server; the port runs one local Sim")
