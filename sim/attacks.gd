# Port of RoWorld src/shared/Core/SimAttacks.luau (attackLogic, conquest queue, annexation).
# One attack per (attacker, target) pair; each tick it spends a budget of 1.0 "tick fractions"
# taking queued front tiles in priority order. Costs are per full-size tile (k_area per our tile).
extends RefCounted
class_name SimAttacks

var g  # main.gd
var R: SimRules
var tick := 0
var next_aid := 1
var merges := []

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules

func reset() -> void:
	tick = 0
	next_aid = 1
	merges.clear()

# ---------------- queue (binary min-heap on key) ----------------
static func _hpush(a: Dictionary, key: int, t: int) -> void:
	var hk: Array = a.hk
	var ht: Array = a.ht
	hk.append(key); ht.append(t)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hk[p] <= hk[i]: break
		var tk: int = hk[p]; hk[p] = hk[i]; hk[i] = tk
		var tt: int = ht[p]; ht[p] = ht[i]; ht[i] = tt
		i = p

static func _hpop(a: Dictionary) -> int:
	var hk: Array = a.hk
	var ht: Array = a.ht
	var n := hk.size()
	if n == 0: return -1
	var top: int = ht[0]
	hk[0] = hk[n - 1]; ht[0] = ht[n - 1]
	hk.resize(n - 1); ht.resize(n - 1)
	n -= 1
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n: break
		var m := l
		if l + 1 < n and hk[l + 1] < hk[l]: m = l + 1
		if hk[i] <= hk[m]: break
		var tk: int = hk[m]; hk[m] = hk[i]; hk[i] = tk
		var tt: int = ht[m]; ht[m] = ht[i]; ht[i] = tt
		i = m
	return top

func _push(a: Dictionary, t: int) -> void:
	var om: PackedInt32Array = g.owner_map
	var at: int = a.a
	var W: int = g.W
	var x := t % W
	var n := 0
	if x > 0 and om[t - 1] == at: n += 1
	if x < W - 1 and om[t + 1] == at: n += 1
	if t >= W and om[t - W] == at: n += 1
	if t < om.size() - W and om[t + W] == at: n += 1
	var gn: PackedByteArray = g.grow_n
	var key: int = 4 * tick + (R.PRIORITY_BASE + g.rng.randi() % R.PRIORITY_RAND) * R.priority_f4[int(g.mtn[t]) * 5 + n] + ((gn[t] >> 5) if gn.size() > t else 0)  # low-freq noise: organic frontier order
	_hpush(a, key, t)
	a.front[t] = true

func _add_neighbors(a: Dictionary, t: int) -> void:
	var om: PackedInt32Array = g.owner_map
	var tg: int = a.t
	var W: int = g.W
	var N := om.size()
	if _mtn.size() != N: _mtn = g.mtn; _gn = g.grow_n; _pf4 = R.priority_f4
	var x := t % W
	if t >= W and om[t - W] == tg: _push_fast(a, t - W, om, W, N)
	if t < N - W and om[t + W] == tg: _push_fast(a, t + W, om, W, N)
	if x > 0 and om[t - 1] == tg: _push_fast(a, t - 1, om, W, N)
	if x < W - 1 and om[t + 1] == tg: _push_fast(a, t + 1, om, W, N)

# _push with the map arrays passed in (same key: 4 * tick + priority(terrain, own neighbours) + noise)
var _mtn := PackedByteArray()
var _gn := PackedByteArray()
var _pf4: Array = []
func _push_fast(a: Dictionary, t: int, om: PackedInt32Array, W: int, N: int) -> void:
	var at: int = a.a
	var x := t % W
	var n := 0
	if x > 0 and om[t - 1] == at: n += 1
	if x < W - 1 and om[t + 1] == at: n += 1
	if t >= W and om[t - W] == at: n += 1
	if t < N - W and om[t + W] == at: n += 1
	var key: int = 4 * tick + (R.PRIORITY_BASE + g.rng.randi() % R.PRIORITY_RAND) * int(_pf4[int(_mtn[t]) * 5 + n]) + ((_gn[t] >> 5) if _gn.size() > t else 0)
	_hpush(a, key, t)
	a.front[t] = true

# Seeds the queue with every target tile next to the attacker, walking the attacker's border set
# (same tile set as a bounding-box sweep, without touching the interior).
func _seed_from_border(a: Dictionary) -> int:
	var at: int = a.a
	var tg: int = a.t
	var om: PackedInt32Array = g.owner_map
	var W: int = g.W
	var N := om.size()
	var front: Dictionary = a.front
	var c := 0
	if at >= g.border.size(): return 0
	for t in g.border[at].keys():
		var x: int = t % W
		if x > 0 and om[t - 1] == tg and not front.has(t - 1): _push(a, t - 1); c += 1
		if x < W - 1 and om[t + 1] == tg and not front.has(t + 1): _push(a, t + 1); c += 1
		if t >= W and om[t - W] == tg and not front.has(t - W): _push(a, t - W); c += 1
		if t < N - W and om[t + W] == tg and not front.has(t + W): _push(a, t + W); c += 1
	return c

func attack_between(at: int, tg: int):
	for a in g.attacks:
		if a.a == at and a.t == tg and not a.get("dead", false): return a
	return null

func troops_in_attacks(id: int) -> float:
	var s := 0.0
	for a in g.attacks:
		if a.a == id: s += a.troops + float(a.get("pend", 0.0))
	return s

func count_attacks_by(id: int, players_only: bool) -> int:
	var c := 0
	for a in g.attacks:
		if a.a == id and (not players_only or a.t > 0): c += 1
	return c

# start_attack: troops already removed from the attacker by the caller.
func start(at: int, tg: int, troops: float, beachhead := -1):
	var n = g.nations[at]
	if troops < 1.0:
		n.troops += troops
		return null
	var counter := false
	if tg != 0:
		var opp = attack_between(tg, at)
		if opp != null:
			counter = true
			var cancel := minf(troops, opp.troops)
			troops -= cancel
			opp.troops -= cancel
			if opp.troops < 1.0: end_attack(opp, false)
			if troops < 1.0: return null
	var a = attack_between(at, tg)
	if a != null:
		if beachhead >= 0:
			# a boat landing joins the running attack with its beachhead's neighbours
			a.troops += troops
			a.retreat_at = 0; a.frozen_from = 0
			_add_neighbors(a, beachhead)
		elif int(a.started) == tick:
			# two orders in one tick: the second absorbs the first
			a.troops += troops
			_seed_from_border(a)
		else:
			# SimAttacks.start_attack / _apply_merges: absorbed at the end of the next attacks tick,
			# after the running attack advanced once more with its own troops
			if float(a.get("pend", 0.0)) == 0.0: merges.append(a)
			a.pend = float(a.get("pend", 0.0)) + troops
		return a
	a = {"a": at, "t": tg, "troops": troops, "hk": [], "ht": [],
		"front": {}, "head": -1, "chew": 0.0, "aid": next_aid, "retreat_at": 0, "frozen_from": 0,
		"started": tick, "counter": counter, "last": -1, "sent": int(troops), "shown": troops, "vel": Vector2.ZERO, "pend": 0.0}
	next_aid += 1
	if beachhead >= 0:
		_add_neighbors(a, beachhead)
		a.last = beachhead
	else:
		_seed_from_border(a)
	if a.front.is_empty():
		n.troops += troops
		return null
	if a.last < 0:
		a.last = a.ht[0]
	var wp: Vector2 = Vector2(a.last % g.W + 0.5, a.last / g.W + 0.5) * g.TS
	a.tgt = wp; a.disp = wp
	g.attacks.append(a)
	if tg > 0:
		g.nations[tg]["attacked_tick"] = tick
		var gk: String = "grudge_" + str(at)
		g.nations[tg][gk] = maxi(int(g.nations[tg].get(gk, 0)), tick + R.HOSTILE_TICKS)  # add_grudge keeps the later expiry
	return a

func end_attack(a: Dictionary, give_back: bool, keep := 1.0) -> void:
	if a.get("dead", false): return
	a.dead = true
	if give_back and g.nations[a.a].alive:
		g.nations[a.a].troops += floorf(maxf(a.troops, 0.0) * keep)  # floored to whole troops (source)
	if float(a.get("pend", 0.0)) > 0.0 and g.nations[a.a].alive:
		g.nations[a.a].troops += a.pend  # an order not yet merged never left home
	a.pend = 0.0
	a.troops = 0.0
	g.attacks.erase(a)

# Retreat order: the attack freezes and the troops come home RETREAT_DELAY_TICKS later (-25 % vs players).
func retreat(a: Dictionary) -> void:
	if a.retreat_at > 0: return
	# source: advances on this tick and the next, frozen after that, home RETREAT_DELAY_TICKS after the order
	a.retreat_at = tick + R.RETREAT_DELAY_TICKS + 1
	a.frozen_from = tick + 2

func tick_all() -> void:
	begin_tick()
	run_slice(-1)

# Time-sliced attacks pass (upstream spreads a local step over frames with Coop.check()): begin_tick
# snapshots the list, run_slice processes attacks until the deadline (usec; -1 none) and returns true
# once the whole pass (and the merges) is done.
var _pass: Array = []
var _pass_i := 0
var pass_open := false
func begin_tick() -> void:
	tick += 1
	_pass = g.attacks.duplicate()
	_pass_i = 0
	pass_open = true
	_mtn = g.mtn; _gn = g.grow_n; _pf4 = R.priority_f4

func run_slice(deadline: int) -> bool:
	if not pass_open: return true
	var n := _pass.size()
	while _pass_i < n:
		var a: Dictionary = _pass[_pass_i]
		_pass_i += 1
		if not a.get("dead", false): _process(a)
		if deadline >= 0 and (_pass_i & 7) == 0 and Time.get_ticks_usec() > deadline: return false
	_pass = []
	pass_open = false
	if not merges.is_empty(): _apply_merges()
	return true

# SimAttacks._apply_merges: pending orders join their attack (retreat dropped, queue re-seeded from
# the whole border); an attack that ended meanwhile restarts with them.
func _apply_merges() -> void:
	var list := merges
	merges = []
	for a in list:
		var troops: float = a.get("pend", 0.0)
		a.pend = 0.0
		var at: int = a.a; var tg: int = a.t
		if troops <= 0.0 or not g.nations[at].alive: continue
		if tg != 0 and (not g.nations[tg].alive or g.allied(at, tg)):
			g.nations[at].troops += troops; continue
		if a.get("dead", false):
			start(at, tg, troops, -1); continue
		a.troops += troops
		a.retreat_at = 0; a.frozen_from = 0
		_seed_from_border(a)

func _touches(t: int, at: int) -> bool:
	var om: PackedInt32Array = g.owner_map
	var W: int = g.W
	var x := t % W
	if x > 0 and om[t - 1] == at: return true
	if x < W - 1 and om[t + 1] == at: return true
	if t >= W and om[t - W] == at: return true
	return t < om.size() - W and om[t + W] == at

func _process(a: Dictionary) -> void:
	var at: int = a.a
	var tg: int = a.t
	var nats: Array = g.nations
	if not nats[at].alive or (tg != 0 and not nats[tg].alive):
		end_attack(a, true); return
	var neutral := tg == 0
	if a.retreat_at > 0:
		if tick >= a.retreat_at:
			end_attack(a, true, 1.0 if neutral else R.RETREAT_KEEP); return
		if tick >= a.frozen_from: return
	if not neutral and g.allied(at, tg):
		end_attack(a, true); return
	var K_AREA: float = R.k_area
	var border_of: float = a.front.size() * R.k_lin + g.rng.randi() % R.BORDER_JITTER
	var fo_mod := SimRules.fallout_modifier(float(g.fallout_count) / maxf(float(g.land_total), 1.0))
	var at_kind: int = g.kind_of(at)
	var nl := SimRules.neutral_loss_per_mag(at_kind)
	var bonus_l := 1.0
	var bonus_s := 1.0
	var trait_l := 1.0
	var trait_s := 1.0
	var mag_k := 1.0
	if not neutral:
		var att_of: float = nats[at].land * K_AREA
		var def_of: float = maxf(nats[tg].land * K_AREA, 1.0)
		var ldb := R.large_territory_bonus(def_of, R.LARGE_DEFENDER_DEPTH)
		bonus_l = R.ATTACKER_LOSS_BASE * R.large_territory_bonus(att_of, R.LARGE_ATTACKER_DEPTH) * ldb
		bonus_s = R.large_territory_bonus(att_of, R.LARGE_ATTACKER_SPEED_DEPTH) * ldb / (R.SPEED_COST_DIVISOR * maxf(border_of, 1.0))
		if g.is_traitor(tg):
			trait_l = R.TRAITOR_DEFENSE_DEBUFF; trait_s = R.TRAITOR_SPEED_DEBUFF
		if g.kind_of(tg) == SimRules.KIND_TRIBE and at_kind != SimRules.KIND_TRIBE:
			mag_k = R.BOT_DEFENDER_LOSS_MULT
	var mtn: PackedByteArray = g.mtn
	var border1 := maxf(border_of, 1.0)
	var cap: int = R.max_tiles_per_tick
	var budget := 1.0
	var taken := 0
	var sx := 0.0; var sy := 0.0
	var W: int = g.W
	while budget > 0.0:
		if a.troops < 1.0:
			a.troops = 0.0
			end_attack(a, false); break
		var t: int = a.head
		if t >= 0 and (g.owner_map[t] != tg or not _touches(t, at)):
			a.head = -1; a.chew = 0.0; t = -1
		if t < 0:
			if taken >= cap: break
			t = _hpop(a)
			if t < 0:
				end_attack(a, true); break
			a.front.erase(t)
			if g.owner_map[t] != tg or not _touches(t, at): continue
			_add_neighbors(a, t)
			a.head = t; a.chew = 0.0
		var tt: int = mtn[t]
		var mag: float = R.ATTACK_MAG[tt]
		var tc: float = R.ATTACK_TILE_COST[tt]
		if not neutral and g.defended(t, tg):
			mag *= R.DEFENSE_POST_MAG; tc *= R.DEFENSE_POST_COST
		if g.fallout[t] == 1:
			mag *= fo_mod; tc *= fo_mod
		var loss: float
		var tf: float
		var dloss := 0.0
		if neutral:
			loss = mag * nl
			var v := clampf(R.TERRA_NULLIUS_COST_SCALE * tc / a.troops, R.TERRA_NULLIUS_MIN_COST, R.TERRA_NULLIUS_MAX_COST)
			tf = v / (border1 * 2.0)
		else:
			var dtroops: float = nats[tg].troops
			dloss = dtroops / maxf(nats[tg].land * K_AREA, 1.0)
			var ratio: float = dtroops / a.troops
			loss = mag * mag_k * trait_l * clampf(ratio, 0.6, 2.0) * (bonus_l + R.ATTACKER_LOSS_PER_DENSITY * dloss)
			tf = clampf(ratio, 0.82, 7.5) * clampf(ratio / 20.0, 1.0, 50.0) * tc * bonus_s * trait_s
		# light organic speed factor: low-freq noise (+-7%) and jitter (+-3%), clamped to 0.9..1.1, mean 1.0
		var gw := 1.0
		if _gn.size() > t: gw = clampf(1.0 + 0.07 * (_gn[t] / 127.5 - 1.0) + g.rng.randf_range(-0.03, 0.03), 0.9, 1.1)
		tf = maxf(tf * gw / R.attack_speed_mult, 1e-6)
		var dfloor := floorf(dloss)
		var need: float = K_AREA - a.chew
		var can := ceilf(budget / tf)
		if loss > 0.0: can = minf(can, ceilf(a.troops / loss))
		if can >= need:
			budget -= need * tf
			a.troops -= need * loss
			if not neutral:
				nats[tg].troops -= minf(need * dfloor, maxf(nats[tg].troops, 0.0))
			a.chew = 0.0; a.head = -1
			g._set_owner(t, at)
			a.last = t
			taken += 1
			sx += t % W; sy += t / W
			if not neutral and nats[tg].land * K_AREA < R.ANNEX_BELOW_FULL_TILES \
					and (g.kind_of(tg) != SimRules.KIND_HUMAN or a.troops > nats[tg].troops):
				annex(tg, at)
				end_attack(a, true); break
		else:
			budget -= can * tf
			a.troops -= can * loss
			if not neutral:
				nats[tg].troops -= minf(can * dfloor, maxf(nats[tg].troops, 0.0))
			a.chew += can
	g._pf_add("tiles", taken); g._pf_add("atk_n", 1)
	if taken > 0:
		a.tgt = Vector2(sx / taken + 0.5, sy / taken + 0.5) * g.TS
	if not a.get("dead", false) and (tick + a.aid) % R.ATTACK_UPDATE_TICKS == 0 and int(a.troops) != int(a.sent):
		a.sent = int(a.troops)
		if not neutral:
			nats[tg]["attacked_tick"] = tick
			var gk: String = "grudge_" + str(at)
			nats[tg][gk] = maxi(int(nats[tg].get(gk, 0)), tick + R.HOSTILE_TICKS)

# A defender under ANNEX_BELOW_FULL_TILES is conquered outright: its land goes to the attacker
# (source: tiles touching the attacker go to it, others to a bordering non-allied player, in passes).
func annex(victim: int, by: int) -> void:
	var nv = g.nations[victim]
	g.nations[by].gold += R.conquer_gold(g.kind_of(victim), nv.gold)
	nv.gold = 0.0
	nv["last_by"] = by
	nv["killer"] = by
	# source _annex: tiles touching the attacker go to it, others to a bordering non-allied player,
	# in repeated passes (max 100); unreachable pockets stay
	var W: int = g.W
	var tiles := PackedInt32Array()
	var bb: Rect2i = nv.bb.intersection(Rect2i(0, 0, g.W, g.H))
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var i: int = y * W + x
			if g.owner_map[i] == victim: tiles.append(i)
	for _pass in 100:
		var progressed := false
		var rest := PackedInt32Array()
		for t in tiles:
			if g.owner_map[t] != victim: continue
			if _touches(t, by):
				g._set_owner(t, by); progressed = true; continue
			var taker := _annex_neighbour(t, victim)
			if taker > 0:
				g._set_owner(t, taker); progressed = true
			else:
				rest.append(t)
		tiles = rest
		if not progressed or tiles.is_empty(): break
	for a in g.attacks.duplicate():
		if a.a == victim: end_attack(a, false)

func _annex_neighbour(t: int, victim: int) -> int:
	var om: PackedInt32Array = g.owner_map
	var W: int = g.W
	var N := om.size()
	var x := t % W
	for n in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W if t >= W else -1, t + W if t < N - W else -1]:
		if n < 0: continue
		var o: int = om[n]
		if o > 0 and o != victim and not g.allied(o, victim): return o
	return 0
