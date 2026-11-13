# Headless check of the map geography fixes (tools/mapfix.py): on every map that shows them, ships route
# Mediterranean -> Red Sea through the Suez Canal and Caribbean -> Pacific through the Panama Canal (the route
# passes the canal's middle), each canal is one 4-connected channel >= 2 tiles wide from sea to sea (every
# tile of it in an all-water 2x2 block, no diagonal-only links or 1-tile pinches), Hainan is its own island, and Hawaii's main islands are separate.
#   godot --headless --path . -s res://tests/test_mapfix.gd
# Cases: tests/mapfix_cases.json (python3 tools/mapfix_cases.py). Prints MAPFIX_TEST PASS / FAIL.
extends SceneTree

const SimNavS := preload("res://sim/nav.gd")
var fails := 0

func _initialize() -> void:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/mapfix_cases.json"))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	for c in cases:
		m.map_tab = int(c.tab); m.map_i = int(c.k)
		m.gen_map()
		var W: int = m.W
		var nav = SimNavS.new()
		nav.build(m.sim_naval.body, W, m.H)
		for r in c.routes:
			var src := int(r.src); var dst := int(r.dst); var mid := int(r.mid)
			var same: bool = m.sim_naval.body[src] > 0 and m.sim_naval.body[src] == m.sim_naval.body[dst]
			var route: PackedInt32Array = nav.find_route(src, dst) if same else PackedInt32Array()
			var dense: PackedInt32Array = nav.dense(route) if route.size() > 0 else PackedInt32Array()
			var best := 1e9
			var on_land := 0
			for t in dense:
				if m.owner_map[t] != m.WATER: on_land += 1
				best = minf(best, Vector2(t % W - mid % W, t / W - mid / W).length())
			var ok: bool = same and dense.size() > 0 and on_land == 0 and best <= float(r.max_d)
			print("%-18s %-7s %s same_body=%s tiles=%d land=%d canal_dist=%.1f (max %.1f) nav_ms=%.1f" % [c.map, r.name, "OK  " if ok else "FAIL",
				str(same), dense.size(), on_land, best, float(r.max_d), nav.usec_max / 1000.0])
			if not ok: fails += 1
			var wide := _wide_link(m, r.win, int(r.sea_a), int(r.sea_b))
			print("%-18s %-7s %s 2-wide 4-connected channel sea to sea: %s" % [c.map, r.name, "OK  " if wide else "FAIL", str(wide)])
			if not wide: fails += 1
		for isl in c.islands:
			var comp := []
			for t in isl.tiles: comp.append(_component(m, int(t)))
			var ok := true
			for i in comp.size():
				if comp[i].is_empty(): ok = false
				for j in range(i + 1, comp.size()):
					if comp[i].has(int(isl.tiles[j])): ok = false
			print("%-18s %-7s %s sizes=%s" % [c.map, isl.name, "OK  " if ok else "FAIL", str(comp.map(func(d): return d.size()))])
			if not ok: fails += 1
	print("MAPFIX_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)

# land component (4-connected) of tile t, capped at 300k tiles (a continent)
func _component(m, t: int) -> Dictionary:
	var seen := {}
	if m.owner_map[t] == m.WATER: return seen
	var W: int = m.W; var N: int = m.W * m.H
	var q := [t]; seen[t] = true
	while q.size() > 0 and seen.size() < 300000:
		var i: int = q.pop_back()
		for j in [i - W, i + W, i - 1 if i % W > 0 else -1, i + 1 if i % W < W - 1 else -1]:
			if j >= 0 and j < N and not seen.has(j) and m.owner_map[j] != m.WATER:
				seen[j] = true; q.append(j)
	return seen

# BFS (4-way) over the window's "wide water" (tiles inside an all-water 2x2 block) from sea_a to sea_b
func _wide_link(m, win: Array, a: int, b: int) -> bool:
	var W: int = m.W
	var x0 := int(win[0]); var x1 := int(win[1]); var y0 := int(win[2]); var y1 := int(win[3])
	var w := x1 - x0; var h := y1 - y0
	var wet := PackedByteArray(); wet.resize(w * h)
	for y in h:
		for x in w:
			wet[y * w + x] = 1 if m.owner_map[(y + y0) * W + x + x0] == m.WATER else 0
	var wide := PackedByteArray(); wide.resize(w * h)
	for y in h - 1:
		for x in w - 1:
			var i := y * w + x
			if wet[i] and wet[i + 1] and wet[i + w] and wet[i + w + 1]:
				wide[i] = 1; wide[i + 1] = 1; wide[i + w] = 1; wide[i + w + 1] = 1
	var sa := (a / W - y0) * w + a % W - x0
	var sb := (b / W - y0) * w + b % W - x0
	if sa < 0 or sb < 0 or sa >= w * h or sb >= w * h or not wide[sa] or not wide[sb]: return false
	var seen := PackedByteArray(); seen.resize(w * h)
	var q := PackedInt32Array([sa]); seen[sa] = 1
	var qi := 0
	while qi < q.size():
		var i: int = q[qi]; qi += 1
		if i == sb: return true
		var x := i % w
		for j in [i - w, i + w, i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1]:
			if j >= 0 and j < w * h and wide[j] and not seen[j]:
				seen[j] = 1; q.append(j)
	return false
