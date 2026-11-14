# Port of RoWorld SimNaval.luau: water bodies, transport limits/tokens/landing, and trade ships
# (ports_tick: every 10 ticks each finished port rolls `level` times against tradeShipSpawnRate with a
# pity timer, picks a partner port of a non-hostile owner on the same water body, sails, and pays
# tradeShipGold(tiles sailed) to both owners).
extends RefCounted
class_name SimNaval

var g
var R: SimRules
var body := PackedInt32Array()
var tokens := {}       # owner -> boat orders left this second
var path_budget := 0

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules

var coast_list := PackedInt32Array()

func own_coast_tile(id: int) -> int:
	var n := coast_list.size()
	if n == 0: return -1
	for _k in 400:
		var c: int = coast_list[g.rng.randi() % n]
		if g.owner_map[c] == id: return c
	return -1

func compute_bodies() -> void:
	var W: int = g.W
	var om: PackedInt32Array = g.owner_map
	var N: int = om.size()
	var WT: int = g.WATER
	var bd := PackedInt32Array(); bd.resize(N); bd.fill(0)
	var q := PackedInt32Array(); q.resize(N)
	var next := 1
	for s in N:
		if om[s] != WT or bd[s] != 0: continue
		var qn := 1; q[0] = s
		bd[s] = next
		var qi := 0
		while qi < qn:
			var i: int = q[qi]; qi += 1
			var x := i % W
			var j := i - W
			if j >= 0 and bd[j] == 0 and om[j] == WT: bd[j] = next; q[qn] = j; qn += 1
			j = i + W
			if j < N and bd[j] == 0 and om[j] == WT: bd[j] = next; q[qn] = j; qn += 1
			if x > 0:
				j = i - 1
				if bd[j] == 0 and om[j] == WT: bd[j] = next; q[qn] = j; qn += 1
			if x < W - 1:
				j = i + 1
				if bd[j] == 0 and om[j] == WT: bd[j] = next; q[qn] = j; qn += 1
		next += 1
	body = bd
	var cl := PackedInt32Array(); cl.resize(N); var cn := 0
	for i in N:
		if om[i] == WT: continue
		if (i >= 1 and om[i - 1] == WT) or (i + 1 < N and om[i + 1] == WT) or (i >= W and om[i - W] == WT) or (i + W < N and om[i + W] == WT):
			cl[cn] = i; cn += 1
	cl.resize(cn)
	coast_list = cl

# water body a coastal land tile touches (first of west, east, north, south), 0 if none
func coast_body(t: int) -> int:
	var W: int = g.W
	var x := t % W
	for j in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
		if j >= 0 and j < body.size() and body[j] > 0: return body[j]
	return 0

func water_next_to(t: int) -> int:
	var W: int = g.W
	var x := t % W
	for j in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
		if j >= 0 and j < body.size() and body[j] > 0: return j
	return -1

func tick() -> void:
	var t: int = g.sim_atk.tick
	if t % 10 == 0:
		tokens.clear()
	path_budget = 1 if t % 2 == 0 else 0
	_ports_tick(t)

func take_token(id: int) -> bool:
	var left: int = tokens.get(id, SimRules.BOAT_SEARCHES_PER_S)
	if left <= 0: return false
	tokens[id] = left - 1
	return true

func boats_of(id: int) -> int:
	var c := 0
	for bt in g.boats:
		if bt.a == id: c += 1
	return c

func max_boats(id: int) -> int:
	return SimRules.MAX_BOATS_PLAYER if id == g.PLAYER else SimRules.MAX_BOATS_PER_OWNER

func landable(id: int, t: int) -> bool:
	var o: int = g.owner_map[t]
	if o < 0: return false
	return o != id and not (o > 0 and g.allied(id, o))

func alt_landing(id: int, t: int, wb: int) -> int:
	var W: int = g.W; var H: int = g.H
	var cx := t % W; var cy := t / W
	for r in range(1, R.alt_landing_r() + 1):
		for dy in range(-r, r + 1):
			var y := cy + dy
			if y < 0 or y >= H: continue
			for dx in range(-r, r + 1):
				var x := cx + dx
				if x < 0 or x >= W: continue
				var c := y * W + x
				if g._coastal(c) and coast_body(c) == wb and landable(id, c): return c
	return -1

func hostile(a: int, b: int) -> bool:
	if g.is_embargoed(a, b): return true
	return g.sim_atk.attack_between(a, b) != null or g.sim_atk.attack_between(b, a) != null

# ---------------- trade ----------------
func _ports_tick(t: int) -> void:
	var slot := t % 10
	var rng: RandomNumberGenerator = g.rng
	var n_trade: int = g.traders.size()
	for p in g.structs:
		if p.k != 1 or float(p.get("bt", 0.0)) > 0.0: continue
		if not p.has("slot"):
			p.slot = rng.randi() % 10; p.rej = 0; p.partners = []; p.ptick = -100000
			p.water = water_next_to(p.tile); p.body = body[p.water] if p.water >= 0 else 0
		if p.slot != slot or p.water < 0 or not g.nations[p.o].alive: continue
		var hit := false
		for _l in int(p.get("level", 1)):
			if rng.randi() % R.trade_spawn_rate(p.rej, n_trade) == 0:
				hit = true; break
			p.rej += 1
		if not hit: continue
		p.rej = 0
		var dst = _pick_partner(p, t)
		if dst == null: continue
		var pts := _trade_path(p, dst)
		if pts.size() < 2:
			if path_budget <= 0: p.rej += 1
			continue
		var cum := PackedFloat32Array([0.0])
		for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
		g.traders.append({"o": p.o, "pts": pts, "cum": cum, "d": 0.0, "dst": dst, "src": p,
			"gold": floor(R.trade_gold(cum[cum.size() - 1] / g.TS))})
		n_trade += 1

func _pick_partner(p: Dictionary, t: int):
	if p.partners.is_empty() or t - int(p.ptick) > 1200:
		_refresh_partners(p, t)
	var n: int = p.partners.size()
	for _k in 3:
		if n == 0: return null
		var q = p.partners[g.rng.randi() % n]
		if not (q in g.structs) or q.k != 1 or q.o == p.o or not g.nations[q.o].alive or hostile(p.o, q.o): continue
		return q
	p.ptick = -100000
	return null

func _refresh_partners(p: Dictionary, t: int) -> void:
	p.ptick = t
	var keep := []
	for q in p.partners:
		if q in g.structs and q.k == 1 and q.o != p.o and g.nations[q.o].alive: keep.append(q)
	var dists := []
	var W: int = g.W
	for q in g.structs:
		if q.k != 1 or float(q.get("bt", 0.0)) > 0.0 or q.o == p.o or not g.nations[q.o].alive: continue
		if not q.has("slot"): continue
		if q.body != p.body or q.water < 0 or hostile(p.o, q.o): continue
		dists.append([(absi(p.tile % W - q.tile % W) + absi(p.tile / W - q.tile / W)) * R.k_lin, q])
	dists.sort_custom(func(a, b): return a[0] < b[0])
	var n := dists.size()
	var bonus_n := clampi(n / 3, mini(4, n), n)
	var cands := []
	var weights := []
	var total := 0.0
	for i in n:
		var q = dists[i][1]
		var far: bool = dists[i][0] >= SimRules.TRADE_SHORT_RANGE_FULL
		var lv := int(q.get("level", 1))
		var w := lv
		if far and i < bonus_n: w += lv
		if far and g.allied(p.o, q.o): w += lv
		cands.append(q); weights.append(w); total += w
	var partners := keep.duplicate()
	for _k in 8 - keep.size():
		if cands.is_empty(): break
		var r: float = g.rng.randf() * total
		var pick = cands[cands.size() - 1]
		for i in cands.size():
			r -= weights[i]
			if r <= 0.0: pick = cands[i]; break
		if not (pick in partners): partners.append(pick)
	p.partners = partners

var trade_cache := {}
func _trade_path(a: Dictionary, b: Dictionary) -> PackedVector2Array:
	var key := "%d:%d" % [a.tile, b.tile]
	if trade_cache.has(key): return trade_cache[key]
	var rk := "%d:%d" % [b.tile, a.tile]
	if trade_cache.has(rk):
		var rv: PackedVector2Array = trade_cache[rk].duplicate()
		rv.reverse()
		trade_cache[key] = rv
		return rv
	if path_budget <= 0: return PackedVector2Array()
	path_budget -= 1
	var pts: PackedVector2Array = g._water_path(a.tile, b.tile, 60000)
	trade_cache[key] = pts
	if trade_cache.size() > 2000: trade_cache.clear()
	return pts
