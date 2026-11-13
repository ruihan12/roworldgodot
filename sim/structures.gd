# Port of Rules.place_site (RoWorld): upgrade a structure in reach, or flood the builder's own land
# within PLACE_SEARCH_R (15 full-size tiles) of the click and take the nearest tile with no structure
# (any owner) closer than STRUCT_MIN_DIST (15 full-size tiles). Ports: coastal tiles within
# PORT_SPAWN_MANHATTAN (20 full-size tiles, manhattan), nearest by manhattan distance.
extends RefCounted
class_name SimStructures

var g
var R: SimRules

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules

func place_site(id: int, k: int, tile: int) -> Dictionary:
	var out := {"tile": -1, "upgrade": null, "reason": ""}
	var W: int = g.W
	if tile < 0 or tile >= g.owner_map.size():
		out.reason = "invalid"; return out
	if g.owner_map[tile] != id:
		out.reason = "not_own"; return out
	var md := R.struct_min_dist
	var md2 := md * md
	var reach := R.place_search_r() + md + 1.0
	var near := []
	var tx := tile % W; var ty := tile / W
	for st in g.structs:
		var dx: int = st.tile % W - tx; var dy: int = st.tile / W - ty
		if dx * dx + dy * dy <= reach * reach: near.append(st)
	if k in SimRules.UPGRADABLE_K:
		var best = null
		var bd := 0.0
		for st in near:
			if st.k != k: continue
			var d := _d2(st.tile, tile, W)
			if d > md2: continue
			if best == null or d < bd: best = st; bd = d
		if best != null and best.o == id and float(best.get("bt", 0.0)) <= 0.0:
			out.tile = best.tile; out.upgrade = best
			return out
	var r2 := R.place_search_r() * R.place_search_r()
	var seen := {tile: true}
	var stack := [tile]
	var flood := [tile]
	var om: PackedInt32Array = g.owner_map
	while not stack.is_empty():
		var t: int = stack.pop_back()
		var x := t % W
		for n in [t - W if t >= W else -1, t + W if t < om.size() - W else -1, t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1]:
			if n < 0 or seen.has(n) or om[n] != id or _d2(tile, n, W) >= r2: continue
			seen[n] = true
			flood.append(n); stack.append(n)
	var port := k == 1
	var pick := -1
	var pd := 0.0
	var pm := R.port_spawn_manhattan()
	for t in flood:
		var man: float = absi(t % W - tx) + absi(t / W - ty)
		if port and (not g._coastal(t) or man > pm): continue
		var blocked := false
		for st in near:
			if _d2(st.tile, t, W) < md2: blocked = true; break
		if blocked: continue
		var d: float = man if port else _d2(tile, t, W)
		if pick < 0 or d < pd: pick = t; pd = d
	if pick < 0:
		out.reason = "no_coast" if port else "no_room"
		return out
	out.tile = pick
	return out

static func _d2(a: int, b: int, W: int) -> float:
	var dx := a % W - b % W
	var dy := a / W - b / W
	return float(dx * dx + dy * dy)

static func reason_text(r: String) -> String:
	match r:
		"not_own": return "Must be on your own land"
		"no_room": return "No room: buildings need 15 tiles of space"
		"no_coast": return "No free coast nearby for a Port"
		"invalid": return "Invalid tile"
	return r
