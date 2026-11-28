# Port of RoWorld src/shared/Core/SimAttacks.luau (attackLogic, conquest queue, annexation).
# One attack per (attacker, target) pair; each tick it spends a budget of 1.0 "tick fractions"
# taking queued front tiles in priority order. Costs are per full-size tile (k_area per our tile).
#
# Step 5 of docs/LUAU_PORT.md: with the Luau extension loaded the attacks run in Luau
# (luau/sim/Core/SimAttacks.luau, the same code transliterated) and this class is the GDScript face of it:
# start / end_attack / retreat / begin_tick / run_slice call Luau through g.luau_link (flush -> call -> apply),
# and g.attacks holds one mirror Dictionary per attack (the fields the AI, the HUD, net/rep.gd and the tests
# read), updated in place from what each call returns. attack_between / troops_in_attacks / count_attacks_by
# read the mirror. Without the extension (or with NO_LUAU_SIM set) the GDScript code below runs as before.
extends RefCounted
class_name SimAttacks

var g  # main.gd
var R: SimRules
var tick := 0
var next_aid := 1
var merges := []
const LMOD := "Core/SimAttacks"
const REC := 15  # f64 per attack record (SimAttacks.luau M.REC)
const RULE_FIELDS := ["k_lin", "k_area", "legacy_lin", "spawn_radius", "tribe_spawn_min_dist", "nation_spawn_delta",
	"max_tiles_per_tick", "defense_range", "struct_min_dist", "log_mid", "ts", "tile_norm", "growth_mult",
	"attack_speed_mult", "gold_mult", "ai_rate_mult", "pop_cap_mode", "pop_k"]
var lu: LuauLink = null  # Luau owns the attacks while this is on
var _mir := {}  # attack id -> its mirror Dictionary in g.attacks

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules
	_rng = main.rng
	assert(R.PRIORITY_BASE == 10 and R.PRIORITY_RAND == 7)  # (inlined in _add_neighbors_fast)
	if not OS.has_environment("NO_LUAU_SIM") and "luau_link" in main:
		if main.luau_link == null: main.luau_link = LuauLink.new()
		lu = main.luau_link
		if lu.on and lu.vm.call_fn(LMOD, "reset", []) == null: lu._fail(main, lu.vm.last_error)

func reset() -> void:
	tick = 0
	next_aid = 1
	merges.clear()
	if _L():
		lu.vm.call_fn(LMOD, "reset", [])
		_mir.clear()

## Luau runs the attacks (not on a remote viewer: there the host's list arrives through net/rep.gd)
# FALLBACK (docs/LUAU_PORT.md Step 6): when this returns no Luau, this module's GDScript code runs (no extension, NO_LUAU_SIM).
func _L() -> bool:
	return lu != null and lu.on and not g.net_remote

## A new Luau world (sim/luau_link.gd _begin): Luau's attack list restarts empty, so does the mirror.
func luau_reset() -> void:
	if _mir.is_empty(): return
	for aid in _mir: g.attacks.erase(_mir[aid])
	_mir.clear()

# (id, troops, alive) of the nations a call may touch (SimState.nat_some)
func _nat(ids: Array) -> PackedByteArray:
	var out := PackedFloat64Array()
	for id in ids:
		var n: Dictionary = g.nations[id]
		out.append(id); out.append(float(n.troops)); out.append(1.0 if n.alive else 0.0)
	return out.to_byte_array()

# what a whole attack pass reads (SimState.nat_all). Built about 3 times a tick (attacks, naval, rails, warships,
# arsenal). A dead nation's troops and gold never change (Step 5g: checked over 6000 ticks of two seeds, and by
# tests/test_luau_world.gd after every phase), so once it is seen dead they come from the last build and only its
# alive flag is read again (about 70% of the nations of a match are dead on average).
var _wc_nats = null
var _wc_tr := PackedFloat64Array()
var _wc_gl := PackedFloat64Array()
var _wc_dead: Array = []  # id -> the dead nation's Dictionary when its values are kept, else null
var world_full := false  # tests: read every nation

func _world() -> Array:
	var nats: Array = g.nations
	var nn := nats.size()
	if not is_same(_wc_nats, nats) or _wc_dead.size() > nn:
		_wc_nats = nats
		_wc_tr = PackedFloat64Array(); _wc_gl = PackedFloat64Array(); _wc_dead = []
	if _wc_dead.size() < nn:
		_wc_tr.resize(nn); _wc_gl.resize(nn); _wc_dead.resize(nn)
	var tr := _wc_tr
	var gl := _wc_gl
	var dd := _wc_dead
	var al := PackedByteArray(); al.resize(nn)
	var full := world_full
	for id in range(1, nn):
		var d: Dictionary = nats[id]
		if d.alive:
			tr[id] = d.troops; gl[id] = d.gold; al[id] = 1
			if dd[id] != null: dd[id] = null
		elif full or not is_same(dd[id], d):
			tr[id] = d.troops; gl[id] = d.gold
			dd[id] = d
	_wc_tr = tr; _wc_gl = gl  # (packed arrays are copied on write)
	var kc: PackedInt32Array = g._kind_cache
	if kc.size() != nn:
		kc = PackedInt32Array(); kc.resize(nn)
		for id in nn: kc[id] = g.kind_of(id)
	var tm := PackedInt32Array()
	var lf := PackedByteArray()
	if g.team_mode:
		tm.resize(nn); lf.resize(nn)
		for id in range(1, nn):
			var d: Dictionary = nats[id]
			tm[id] = int(d.get("team", 0)); lf[id] = 1 if d.get("left", false) else 0
	var trt := PackedInt32Array()
	for id in g.traitor:
		trt.append(int(id)); trt.append(int(g.traitor[id]))
	var defs := PackedInt32Array()
	for o in g.def_posts:
		var arr: PackedInt32Array = g.def_posts[o]
		defs.append(int(o)); defs.append(arr.size()); defs.append_array(arr)
	return [nn, tr.to_byte_array(), gl.to_byte_array(), al, kc.to_byte_array(), bool(g.team_mode),
		tm.to_byte_array(), lf, PackedInt32Array(g.allies.keys()).to_byte_array(), trt.to_byte_array(),
		defs.to_byte_array(), int(g.fallout_count), int(g.land_total)]

# Step 5g2: what naval, rails and warships read (SimState.nat_lite: alive, kind, teams, alliances), for their
# world_lite calls. With world_full (tests) they get the whole world() instead.
var world_lites := 0  # world_lite calls made (tests)
func _world_lite() -> Array:
	var nats: Array = g.nations
	var nn := nats.size()
	var al := PackedByteArray(); al.resize(nn)
	for id in range(1, nn):
		var d: Dictionary = nats[id]
		if d.alive: al[id] = 1
	var kc: PackedInt32Array = g._kind_cache
	if kc.size() != nn:
		kc = PackedInt32Array(); kc.resize(nn)
		for id in nn: kc[id] = g.kind_of(id)
	var tm := PackedInt32Array()
	var lf := PackedByteArray()
	if g.team_mode:
		tm.resize(nn); lf.resize(nn)
		for id in range(1, nn):
			var d: Dictionary = nats[id]
			tm[id] = int(d.get("team", 0)); lf[id] = 1 if d.get("left", false) else 0
	return [nn, al, kc.to_byte_array(), bool(g.team_mode), tm.to_byte_array(), lf,
		PackedInt32Array(g.allies.keys()).to_byte_array()]

## The world a naval / rails / warships call needs: [function name, its arguments] for the module's world entry.
func world_call() -> Array:
	if world_full: return ["world", _world()]
	world_lites += 1
	return ["world_lite", _world_lite()]

# a Luau call's attack records -> the mirror Dictionaries (in place, so references held elsewhere stay live)
func _mirror(out) -> void:
	if out == null: return
	var recs: PackedFloat64Array = (out.atk as PackedByteArray).to_float64_array()
	for k in range(0, recs.size(), REC):
		var aid := int(recs[k])
		var d = _mir.get(aid)
		var troops: float = recs[k + 3]
		var tgt := Vector2(recs[k + 12], recs[k + 13])
		if d == null:
			d = {"a": int(recs[k + 1]), "t": int(recs[k + 2]), "troops": troops, "hk": PackedInt64Array(), "ht": PackedInt32Array(),
				"front": {}, "head": -1, "chew": 0.0, "aid": aid, "retreat_at": 0, "frozen_from": 0,
				"started": int(recs[k + 8]), "counter": recs[k + 9] != 0.0, "last": -1, "sent": 0, "shown": troops,
				"vel": Vector2.ZERO, "pend": 0.0, "tgt": tgt, "disp": tgt}
			_mir[aid] = d
		d.troops = troops
		d.pend = recs[k + 4]
		d.retreat_at = int(recs[k + 6])
		d.frozen_from = int(recs[k + 7])
		d.last = int(recs[k + 10])
		d.sent = int(recs[k + 11])
		d.tgt = tgt
		if recs[k + 5] != 0.0:
			d.dead = true
			_mir.erase(aid)
	if out.has("order"):
		var ids: PackedInt32Array = (out.order as PackedByteArray).to_int32_array()
		g.attacks.clear()
		for aid in ids: g.attacks.append(_mir[aid])

func _lcall(fn: String, args: Array):
	var out = lu.lcall(g, LMOD, fn, LuauLink.rng_args(g) + args)
	_mirror(out)
	return out

## arsenal: an owner's running attacks lose a share of their troops
func scale_owner(o: int, f: float) -> void:
	if _L():
		_lcall("scale_owner", [o, f]); return
	for a in g.attacks:
		if a.a == o: a.troops *= f

func set_troops(a: Dictionary, v: float) -> void:
	if _L():
		_lcall("set_troops", [int(a.aid), v]); return
	a.troops = v

# ---------------- queue (binary min-heap on key) ----------------
# (perf) keys/tiles live in PackedInt64Array/PackedInt32Array (shared by reference, so the locals below
# write the attack's own arrays); the heap algorithm and push order are unchanged, so pops are identical.
static func _hpush(hk: PackedInt64Array, ht: PackedInt32Array, key: int, t: int) -> void:
	hk.append(key); ht.append(t)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		var kp := hk[p]
		if kp <= key: break
		hk[i] = kp; ht[i] = ht[p]
		i = p
	hk[i] = key; ht[i] = t

static func _hpop(a: Dictionary) -> int:
	var hk: PackedInt64Array = a.hk
	var ht: PackedInt32Array = a.ht
	var n := hk.size()
	if n == 0: return -1
	var top: int = ht[0]
	var lk := hk[n - 1]; var lt := ht[n - 1]
	n -= 1
	hk.resize(n); ht.resize(n)
	if n == 0: return top
	# sift the last element down from the root (same swaps as the swap-based version)
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n: break
		var m := l
		if l + 1 < n and hk[l + 1] < hk[l]: m = l + 1
		if lk <= hk[m]: break
		hk[i] = hk[m]; ht[i] = ht[m]
		i = m
	hk[i] = lk; ht[i] = lt
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
	var key: int = 4 * tick + (R.PRIORITY_BASE + _rng.randi() % R.PRIORITY_RAND) * R.priority_f4[int(g.mtn[t]) * 5 + n]
	_hpush(a.hk, a.ht, key, t)
	a.front[t] = true

func _add_neighbors(a: Dictionary, t: int) -> void:
	var om: PackedInt32Array = g.owner_map
	var tg: int = a.t
	var W: int = g.W
	var N := om.size()
	if _mtn.size() != N: _mtn = g.mtn; _pf4 = R.priority_f4
	_add_neighbors_fast(a, t, om, W, N, tg, a.a, a.hk, a.ht, a.front)

# (perf) the neighbours of t that the target owns, in the same order (up, down, left, right) with the
# same key and RNG draw per push as _push
func _add_neighbors_fast(a: Dictionary, t: int, om: PackedInt32Array, W: int, N: int, tg: int, at: int, hk: PackedInt64Array, ht: PackedInt32Array, front: Dictionary) -> void:
	var x := t % W
	var t4 := 4 * tick
	for k in 4:
		var u: int
		if k == 0:
			if t < W: continue
			u = t - W
		elif k == 1:
			if t >= N - W: continue
			u = t + W
		elif k == 2:
			if x == 0: continue
			u = t - 1
		else:
			if x == W - 1: continue
			u = t + 1
		if om[u] != tg: continue
		var ux := u % W
		var n := 0
		if ux > 0 and om[u - 1] == at: n += 1
		if ux < W - 1 and om[u + 1] == at: n += 1
		if u >= W and om[u - W] == at: n += 1
		if u < N - W and om[u + W] == at: n += 1
		var key: int = t4 + (10 + _rng.randi() % 7) * _pf4[_mtn[u] * 5 + n]
		_hpush(hk, ht, key, u)
		front[u] = true

# _push with the map arrays passed in (same key: 4 * tick + priority(terrain, own neighbours))
var _mtn := PackedByteArray()
var _pf4 := PackedInt32Array()
var _rng: RandomNumberGenerator
func _push_fast(a: Dictionary, t: int, om: PackedInt32Array, W: int, N: int) -> void:
	var at: int = a.a
	var x := t % W
	var n := 0
	if x > 0 and om[t - 1] == at: n += 1
	if x < W - 1 and om[t + 1] == at: n += 1
	if t >= W and om[t - W] == at: n += 1
	if t < N - W and om[t + W] == at: n += 1
	var key: int = 4 * tick + (R.PRIORITY_BASE + _rng.randi() % R.PRIORITY_RAND) * int(_pf4[int(_mtn[t]) * 5 + n])
	_hpush(a.hk, a.ht, key, t)
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
	if _L():
		var out = _lcall("start", [_nat([at] if tg <= 0 or tg == at else [at, tg]), at, tg, troops, beachhead])
		if out == null: return null
		var aid := int(out.ret)
		return _mir.get(aid) if aid >= 0 else null
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
	a = {"a": at, "t": tg, "troops": troops, "hk": PackedInt64Array(), "ht": PackedInt32Array(),
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
		g._viewer_event({"type": "attack", "actor": at, "target": tg}, [tg])
		g.nations[tg]["attacked_tick"] = tick
		var gk: String = "grudge_" + str(at)
		g.nations[tg][gk] = maxi(int(g.nations[tg].get(gk, 0)), tick + R.HOSTILE_TICKS)  # add_grudge keeps the later expiry
	return a

func end_attack(a: Dictionary, give_back: bool, keep := 1.0) -> void:
	if a.get("dead", false): return
	if _L():
		_lcall("end_attack", [_nat([int(a.a)]), int(a.aid), give_back, keep]); return
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
	if _L():
		_lcall("retreat", [int(a.aid)]); return
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
	if _L():
		pass_open = false
		if not lu.flush(g): return
		var f := PackedFloat64Array()
		for k in RULE_FIELDS: f.append(float(R.get(k)))
		if lu.vm.call_fn(LMOD, "begin_tick", [tick, f.to_byte_array(), R.priority_f4.to_byte_array(), float(g.TS)]) == null:
			lu._fail(g, lu.vm.last_error); return
		pass_open = true
		return
	_pass = g.attacks.duplicate()
	_pass_i = 0
	pass_open = true
	_mtn = g.mtn; _pf4 = R.priority_f4

func run_slice(deadline: int) -> bool:
	if not pass_open: return true
	if _L():
		var budget := -1 if deadline < 0 else maxi(0, deadline - Time.get_ticks_usec())
		var out = _lcall("run_slice", _world() + [budget])
		if out == null or bool(out.ret):
			pass_open = false
			return true
		return false
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
	# (perf) hot-loop locals: the shared map arrays (same storage as the game's), the attack's queue,
	# the defender's dictionary; same reads and writes in the same order as before
	var om: PackedInt32Array = g.owner_map
	var N := om.size()
	var fall: PackedByteArray = g.fallout
	var hk: PackedInt64Array = a.hk
	var ht: PackedInt32Array = a.ht
	var front: Dictionary = a.front
	var ntg: Dictionary = nats[tg]
	var chk_def: bool = not neutral and g.def_posts.has(tg)
	var ATTACK_MAG: Array = R.ATTACK_MAG
	var ATTACK_TILE_COST: Array = R.ATTACK_TILE_COST
	var rts: float = R.ts
	var TN_SCALE: float = R.TERRA_NULLIUS_COST_SCALE
	var TN_MIN: float = R.TERRA_NULLIUS_MIN_COST
	var TN_MAX: float = R.TERRA_NULLIUS_MAX_COST
	var LPD: float = R.ATTACKER_LOSS_PER_DENSITY
	var troops: float = a.troops
	var head: int = a.head
	var chew: float = a.chew
	while budget > 0.0:
		if troops < 1.0:
			a.troops = 0.0; a.head = head; a.chew = chew
			end_attack(a, false); _done(a, taken, sx, sy, neutral, at, tg, nats); return
		var t: int = head
		if t >= 0:
			var tx := t % W
			if om[t] != tg or not ((tx > 0 and om[t - 1] == at) or (tx < W - 1 and om[t + 1] == at) or (t >= W and om[t - W] == at) or (t < N - W and om[t + W] == at)):
				head = -1; chew = 0.0; t = -1
		if t < 0:
			if taken >= cap: break
			t = _hpop(a)
			if t < 0:
				a.troops = troops; a.head = head; a.chew = chew
				end_attack(a, true); _done(a, taken, sx, sy, neutral, at, tg, nats); return
			front.erase(t)
			var tx2 := t % W
			if om[t] != tg or not ((tx2 > 0 and om[t - 1] == at) or (tx2 < W - 1 and om[t + 1] == at) or (t >= W and om[t - W] == at) or (t < N - W and om[t + W] == at)): continue
			_add_neighbors_fast(a, t, om, W, N, tg, at, hk, ht, front)
			head = t; chew = 0.0
		var tt: int = mtn[t]
		var mag: float = ATTACK_MAG[tt] * rts  # (1:1: loss per tile is a troop amount)
		var tc: float = ATTACK_TILE_COST[tt]
		if chk_def and g.defended(t, tg):
			mag *= R.DEFENSE_POST_MAG; tc *= R.DEFENSE_POST_COST
		if fall[t] == 1:
			mag *= fo_mod; tc *= fo_mod
		var loss: float
		var tf: float
		var dloss := 0.0
		if neutral:
			# upstream SimAttacks.luau:849-857 — loss = mag * nl; time from TERRA_NULLIUS_* (ts=1 in vanilla)
			loss = mag * nl
			var v := clampf(TN_SCALE * tc / troops, TN_MIN, TN_MAX)
			tf = v / (border1 * 2.0)
		else:
			var dtroops: float = ntg.troops
			dloss = dtroops / maxf(ntg.land * K_AREA, 1.0)
			var ratio: float = dtroops / troops
			loss = mag * mag_k * trait_l * clampf(ratio, 0.6, 2.0) * (bonus_l + LPD * dloss)
			tf = clampf(ratio, 0.82, 7.5) * clampf(ratio / 20.0, 1.0, 50.0) * tc * bonus_s * trait_s
		tf = maxf(tf, 1e-6)
		var dfloor := floorf(dloss)
		var need: float = K_AREA - chew
		var can := ceilf(budget / tf)
		if loss > 0.0: can = minf(can, ceilf(troops / loss))
		if can >= need:
			budget -= need * tf
			troops -= need * loss
			if not neutral:
				ntg.troops -= minf(need * dfloor, maxf(ntg.troops, 0.0))
			chew = 0.0; head = -1
			a.troops = troops; a.head = head; a.chew = chew
			g._set_owner(t, at)
			a.last = t
			taken += 1
			sx += t % W; sy += t / W
			if not neutral and ntg.land * K_AREA < R.ANNEX_BELOW_FULL_TILES \
					and (g.kind_of(tg) != SimRules.KIND_HUMAN or troops > ntg.troops):
				annex(tg, at)
				end_attack(a, true); _done(a, taken, sx, sy, neutral, at, tg, nats); return
		else:
			budget -= can * tf
			troops -= can * loss
			if not neutral:
				ntg.troops -= minf(can * dfloor, maxf(ntg.troops, 0.0))
			chew += can
	a.troops = troops; a.head = head; a.chew = chew
	_done(a, taken, sx, sy, neutral, at, tg, nats)

func _done(a: Dictionary, taken: int, sx: float, sy: float, neutral: bool, at: int, tg: int, nats: Array) -> void:
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
	var taken: float = R.conquer_gold(g.kind_of(victim), nv.gold)
	g.nations[by].gold += taken
	nv.gold = 0.0
	nv["conq_sent"] = true  # (Sim._conquest_sent: the elimination payout after this one is silent)
	if g.has_method("_on_conquest"): g._on_conquest(victim, by, taken)  # (the view: a victory flag)
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
