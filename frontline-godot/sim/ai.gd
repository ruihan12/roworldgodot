# Port of RoWorld src/shared/Core/SimAI.luau (nation + tribe AI decision loop).
# Nations think every NATION_THINK (15) ticks; their attack cycle comes round every attackRate ticks
# (per difficulty). Tribes act only on their own attack tick (tick % rate == attack_tick).
# Not ported yet (stage 2+): SimAIEconomy (build/nuke choices: main.gd _prot_ai is used instead),
# diplomacy replies, capitulation, mop-up / invasion naval offensives.
extends RefCounted
class_name SimAI

const NATION_THINK := 15
const NATION_ATTACK_RATE := [[65, 100], [55, 70], [45, 60]]
const TRIBE_ATTACK_RATE := [40, 79]
const TRIBE_TRAITOR_ODDS := 3
const TRIBE_SKIP_PLAYER_ODDS := 2
const WAR_RATIO := [1.0, 1.0, 1.0]
const HUMAN_SKIP := [0.75, 0.25, 0.0]
const LATE_WAR_FROM := 12000
const LATE_WAR_SPAN := 9000
# Source: INVASION_AGE 12000 / MOPUP_AGE 6000; halved with the ~20 min pacing so oceans get crossed in time.
var INVASION_AGE := 6000
const INVASION_GAP := 150
var MOPUP_AGE := 3000
const MOPUP_GAP := 200

var g
var R: SimRules
var st := {}  # id -> per-AI state dict
var attackers_on := {}
# last scan_border result
var sc_list := []
var sc_count := {}
var sc_tile := {}
var sc_neutral := 0
var sc_neutral_tile := -1
var sc_fallout_tile := -1

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules

func setup() -> void:
	st.clear()
	var rng: RandomNumberGenerator = g.rng
	for id in range(2, g.nations.size()):
		var s := {
			"aggression": rng.randf_range(0.8, 1.25),
			"next_think": id % NATION_THINK,
			"grace_jitter": rng.randi_range(0, R.HUMAN_GRACE_JITTER),
			"trigger_r": rng.randi_range(50, 59) / 100.0,
			"reserve_r": rng.randi_range(30, 39) / 100.0,
			"expand_r": rng.randi_range(10, 19) / 100.0,
			"started": false, "tribe_tn": true, "next_attack": 0, "attack_rate": 0, "attack_tick": 0,
		}
		if g.kind_of(id) == SimRules.KIND_TRIBE:
			var rate := int(rng.randi_range(TRIBE_ATTACK_RATE[0], TRIBE_ATTACK_RATE[1]) * R.ai_rate_mult)
			s.attack_rate = rate
			s.attack_tick = rng.randi_range(0, rate - 1)
		st[id] = s

func _troops(id: int) -> float: return g.nations[id].troops
func _cap(id: int) -> float: return maxf(g.troop_cap(id), 1.0)

func tick() -> void:
	var t: int = g.sim_atk.tick
	attackers_on.clear()
	var pairs := {}
	for a in g.attacks:
		if not a.get("counter", false) and a.t > 0 and g.kind_of(a.a) == SimRules.KIND_NATION:
			pairs[a.a * 4096 + a.t] = true
	for bt in g.boats:
		var tg: int = g.owner_map[bt.dest]
		if tg > 0 and g.kind_of(bt.a) == SimRules.KIND_NATION:
			pairs[bt.a * 4096 + tg] = true
	for k in pairs:
		attackers_on[k % 4096] = attackers_on.get(k % 4096, 0) + 1
	for id in range(2, g.nations.size()):
		var n = g.nations[id]
		if not n.alive or n.land <= 0 or not st.has(id): continue
		var s: Dictionary = st[id]
		if g.kind_of(id) == SimRules.KIND_TRIBE:
			if t % s.attack_rate == s.attack_tick:
				if not s.started:
					s.started = true
					scan_border(id)
					_tribe_send_tn(id)
				else:
					_think_tribe(id)
			continue
		if s.next_think > t: continue
		if not s.started:
			_first_attack(id); continue
		s.next_think = t + NATION_THINK + g.rng.randi_range(-3, 3)
		_think_nation(id)

# ---------------- perception ----------------
# Source walks the owner's border list. Here: an exact scan of the bounding box for small owners,
# a random sample of it for large ones (approximation; same outputs).
var scan_us := 0
var scan_n := 0
func scan_border(id: int) -> void:
	var _t0 := Time.get_ticks_usec()
	_scan_border(id)
	scan_us += Time.get_ticks_usec() - _t0
	scan_n += 1

# Source Sim.scan_border: a walk over the owner's border list (nations: at most 400 legacy tiles,
# tribes: the whole border), recording the owners of the land next to it.
func _scan_border(id: int) -> void:
	sc_list.clear(); sc_count.clear(); sc_tile.clear()
	sc_neutral = 0; sc_neutral_tile = -1; sc_fallout_tile = -1
	if id >= g.border.size(): return
	var bset: Dictionary = g.border[id]
	var cap: int = bset.size() if g.kind_of(id) == SimRules.KIND_TRIBE else ceili(400 * R.legacy_lin)
	var om: PackedInt32Array = g.owner_map
	var fo: PackedByteArray = g.fallout
	var W: int = g.W
	var N := om.size()
	var rng: RandomNumberGenerator = g.rng
	var seen := 0
	for t in bset:
		if seen >= cap: break
		seen += 1
		var x: int = t % W
		for n in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W if t < N - W else -1]:
			if n < 0: continue
			var o: int = om[n]
			if o < 0 or o == id: continue
			if o == 0:
				if fo[n] == 1:
					if sc_fallout_tile < 0: sc_fallout_tile = n
				else:
					sc_neutral += 1
					if sc_neutral_tile < 0 or rng.randi() % sc_neutral == 0: sc_neutral_tile = n
				continue
			if not sc_count.has(o):
				sc_list.append(o); sc_count[o] = 0; sc_tile[o] = n
			sc_count[o] += 1

func _above(id: int, keep: float) -> float:
	var troops := _troops(id)
	return (troops - keep * _cap(id)) / maxf(troops, 1.0)

func _first_attack(id: int) -> void:
	var s: Dictionary = st[id]
	s.started = true
	var r: Array = NATION_ATTACK_RATE[clampi(g.diff_i, 0, 2)]
	s.attack_rate = int(g.rng.randi_range(r[0], r[1]) * R.ai_rate_mult)
	s.next_attack = g.sim_atk.tick + g.rng.randi_range(0, s.attack_rate)
	scan_border(id)
	if sc_neutral > 0 and sc_neutral_tile >= 0:
		g.intent_attack(id, sc_neutral_tile, 0.5)

func _attack_due(id: int) -> bool:
	var s: Dictionary = st[id]
	if g.sim_atk.tick < s.next_attack: return false
	s.next_attack = g.sim_atk.tick + s.attack_rate
	return true

func may_attack_human(id: int, h: int) -> bool:
	var age: int = g.sim_atk.tick
	if age < R.human_grace_ticks(g.diff_i) + int(st[id].grace_jitter): return false
	if g.elapsed < g.peace: return false
	if attackers_on.get(h, 0) >= R.MAX_AI_WARS_ON_HUMAN[clampi(g.diff_i, 0, 2)]:
		return g.sim_atk.attack_between(id, h) != null
	return true

func _think_nation(id: int) -> void:
	var s: Dictionary = st[id]
	var age: int = g.sim_atk.tick
	var troops := _troops(id)
	var fill := troops / _cap(id)
	scan_border(id)
	var defended := _defend(id)
	var due := _attack_due(id)
	var expanded := false
	if due and sc_neutral > 0 and sc_neutral_tile >= 0:
		var send := _above(id, s.expand_r)
		if send * troops >= 1.0:
			expanded = g.intent_attack(id, sc_neutral_tile, send)
	var warred := false
	if due and not defended and not expanded:
		warred = _consider_war(id, fill, age)
	if due and not warred and not defended and sc_neutral == 0 and sc_fallout_tile >= 0 and fill >= s.trigger_r:
		var send2 := _above(id, s.reserve_r) * 0.5
		if send2 * troops >= 1.0:
			g.intent_attack(id, sc_fallout_tile, send2)
	# economy / nukes: SimAIEconomy not ported yet -> existing build/nuke AI
	var u0 := Time.get_ticks_usec()
	g._prot_ai(id, g.nations[id])
	var u1 := Time.get_ticks_usec()
	if not warred and sc_neutral == 0 and g.rng.randf() < 0.25:
		g._ai_boat(id, g.nations[id])
	var u2 := Time.get_ticks_usec()
	_consider_mopup(id, age)
	var u3 := Time.get_ticks_usec()
	_consider_invasion(id, age)
	var u4 := Time.get_ticks_usec()
	g._fp["ai_prot"] = g._fp.get("ai_prot", 0) + u1 - u0
	g._fp["ai_boat"] = g._fp.get("ai_boat", 0) + u2 - u1
	g._fp["ai_mop"] = g._fp.get("ai_mop", 0) + u3 - u2
	g._fp["ai_inv"] = g._fp.get("ai_inv", 0) + u4 - u3

func _defend(id: int) -> bool:
	var n = g.nations[id]
	if g.sim_atk.tick - int(n.get("attacked_tick", -1000)) > 40: return false
	var worst = null
	for a in g.attacks:
		if a.t == id and (worst == null or a.troops > worst.troops): worst = a
	if worst == null: return false
	var x: int = worst.a
	var tile := -1
	if sc_count.get(x, 0) > 0: tile = sc_tile[x]
	elif worst.last >= 0 and g.owner_map[worst.last] == x and g._adj_to(worst.last, id): tile = worst.last
	if tile < 0: return false
	var mine := _troops(id)
	if mine < worst.troops * 1.1 or worst.troops < mine * 0.02: return false
	if x == g.PLAYER and not may_attack_human(id, x) and g.elapsed < g.peace: return false
	var ours = g.sim_atk.attack_between(id, x)
	if ours != null and ours.troops >= worst.troops * 0.8: return false
	var ratio := clampf(worst.troops * 1.25 / maxf(mine, 1.0), 0.05, 0.4)
	return g.intent_attack(id, tile, ratio)

func _land_share(id: int) -> float:
	return float(g.nations[id].land) / maxf(float(g.land_total), 1.0)

func _consider_war(id: int, fill: float, age: int) -> bool:
	var s: Dictionary = st[id]
	if fill < s.reserve_r: return false
	if fill < s.trigger_r and g.rng.randf() >= 0.1: return false
	var d := clampi(g.diff_i, 0, 2)
	var mine := _troops(id)
	var my_share := _land_share(id)
	var best := -1
	var best_s := 0.0
	var L: float = R.legacy_lin
	for p in sc_list:
		if sc_count[p] < 2 * L or g.allied(id, p): continue
		var pk: int = g.kind_of(p)
		var at_war: bool = g.sim_atk.attack_between(id, p) != null
		if pk == SimRules.KIND_HUMAN and not at_war and (not may_attack_human(id, p) or g.rng.randf() < HUMAN_SKIP[d]):
			continue
		var sc := mine / (_troops(p) + 1.0)
		sc *= pow(0.6, attackers_on.get(p, 0) - (1 if at_war else 0))
		if pk == SimRules.KIND_TRIBE: sc *= 1.5
		if g.is_traitor(p): sc *= 1.3
		if int(g.nations[id].get("grudge_" + str(p), -1)) > age: sc *= 1.35
		if at_war: sc *= 1.2
		var ps := _land_share(p)
		if (my_share >= 0.12 and ps >= 0.08) or (ps >= 0.12 and my_share >= 0.08): sc *= 1.5
		sc *= s.aggression * (0.8 + 0.2 * minf(sc_count[p] / (20.0 * L), 1.0))
		if sc > best_s:
			best_s = sc; best = p
	var w := clampf(float(age - LATE_WAR_FROM) / LATE_WAR_SPAN, 0.0, 1.0)
	var need: float = WAR_RATIO[d] * (1.0 - 0.5 * w)
	if best < 0 or best_s < need: return false
	var new_war: bool = g.sim_atk.attack_between(id, best) == null
	if new_war and g.sim_atk.count_attacks_by(id, true) >= (3 if my_share >= 0.12 else 2): return false
	var ratio := _above(id, s.reserve_r)
	if ratio * mine < 1.0: return false
	if not new_war:
		var ex = g.sim_atk.attack_between(id, best)
		if ex != null and ex.troops > _troops(best) * 0.8: return false
	var ok: bool = g.intent_attack(id, sc_tile[best], ratio)
	if ok and new_war: attackers_on[best] = attackers_on.get(best, 0) + 1
	return ok

# ---------------- tribes ----------------
func _think_tribe(id: int) -> void:
	var s: Dictionary = st[id]
	scan_border(id)
	var tn_near := sc_neutral > 0 or sc_fallout_tile >= 0
	var traitor := _tribe_traitor(id)
	if traitor > 0 and g.rng.randi_range(1, TRIBE_TRAITOR_ODDS) == 1 and _tribe_send(id, traitor): return
	if s.tribe_tn:
		if tn_near:
			if _tribe_send_tn(id): return
		else:
			s.tribe_tn = false
	_tribe_attack_random(id)

func _tribe_traitor(id: int) -> int:
	for p in sc_list:
		if g.is_traitor(p) and not g.allied(id, p): return p
	return 0

func _tribe_incoming(id: int) -> int:
	var best = null
	for a in g.attacks:
		if a.t == id and (best == null or a.troops > best.troops): best = a
	return best.a if best != null else 0

func _tribe_attack_random(id: int) -> void:
	var s: Dictionary = st[id]
	if _troops(id) / _cap(id) < s.trigger_r: return
	var attacker := _tribe_incoming(id)
	if attacker > 0 and _tribe_send(id, attacker): return
	var near := sc_list.duplicate()
	if sc_neutral > 0: near.append(0)
	var rng: RandomNumberGenerator = g.rng
	for i in range(near.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = near[i]; near[i] = near[j]; near[j] = tmp
	for p in near:
		if p == 0 or g.allied(id, p): continue
		if g.kind_of(p) != SimRules.KIND_TRIBE and rng.randi_range(1, TRIBE_SKIP_PLAYER_ODDS) == 1: continue
		if p == g.PLAYER and g.elapsed < g.peace: continue
		if _tribe_send(id, p): return

func _tribe_send(id: int, p: int) -> bool:
	if sc_count.get(p, 0) > 0:
		var s: Dictionary = st[id]
		var troops := _troops(id) - _cap(id) * float(s.reserve_r)
		if troops < 1.0: return false
		return g.intent_attack(id, sc_tile[p], troops / maxf(_troops(id), 1.0))
	return false

func _tribe_send_tn(id: int) -> bool:
	var tile := sc_neutral_tile if sc_neutral_tile >= 0 else sc_fallout_tile
	if tile >= 0:
		var troops := _troops(id) - _cap(id) * float(st[id].expand_r)
		if troops < 1.0: return false
		return g.intent_attack(id, tile, troops / maxf(_troops(id), 1.0))
	return false

var _top8 := {}
var _top8_tick := -1
func _rank_ok(p: int) -> bool:
	# top-8 by land (source rank[p] <= 8; the source refreshes its ranking every 50 ticks)
	var t: int = g.sim_atk.tick
	if _top8_tick < 0 or t - _top8_tick >= 50:
		_top8_tick = t
		_top8.clear()
		var ids := []
		for id in range(1, g.nations.size()):
			if g.nations[id].alive and g.nations[id].land > 0: ids.append(id)
		ids.sort_custom(func(a, b): return g.nations[a].land > g.nations[b].land)
		for k in mini(8, ids.size()): _top8[ids[k]] = true
	return _top8.has(p)

func _consider_invasion(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	if age < INVASION_AGE or g.sim_atk.tick - int(s.get("last_inv", 0)) < INVASION_GAP: return
	s.last_inv = g.sim_atk.tick + g.rng.randi_range(0, 80)
	if _land_share(id) < 0.12 or g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return
	var mine := _troops(id)
	if mine < _cap(id) * 0.3: return
	var best := 0
	var best_s := 0.0
	for p in range(1, g.nations.size()):
		if p == id or not g.nations[p].alive or g.allied(id, p) or _land_share(p) < 0.04: continue
		if sc_count.get(p, 0) > 0 or not _rank_ok(p): continue
		var theirs := _troops(p) + 1.0
		if mine < 0.7 * theirs: continue
		if p == g.PLAYER and g.sim_atk.attack_between(id, p) == null and not may_attack_human(id, p): continue
		var sc := (mine / theirs) * _land_share(p)
		if sc > best_s: best_s = sc; best = p
	if best <= 0: return
	var cl: PackedInt32Array = g.sim_naval.coast_list
	for _k in 300:
		var c: int = cl[g.rng.randi() % cl.size()]
		if g.owner_map[c] == best and g.fallout[c] == 0:
			g.launch_boat(id, c, SimRules.BOAT_ATTACK_FRACTION, 250000)
			return

func _consider_mopup(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	if age < MOPUP_AGE or g.sim_atk.tick - int(s.get("last_mop", 0)) < MOPUP_GAP: return
	s.last_mop = g.sim_atk.tick + g.rng.randi_range(0, 100)
	if _land_share(id) < 0.03 or g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return
	var mine := _troops(id)
	var LA: float = R.legacy_lin * R.legacy_lin
	var small := maxi(int(600 * LA), int(0.006 * g.land_total))
	var home: int = g.sim_naval.own_coast_tile(id)
	if home < 0: return
	var best := 0
	var best_s := 0.0
	var W: int = g.W
	for p in range(1, g.nations.size()):
		var np = g.nations[p]
		if p == id or not np.alive or np.land <= 0 or np.land > small or g.allied(id, p): continue
		if np.troops > 0.2 * mine: continue
		if p == g.PLAYER and g.sim_atk.attack_between(id, p) == null and not may_attack_human(id, p): continue
		var anchor := Vector2(np.sx / maxf(1, np.land), np.sy / maxf(1, np.land))
		var sc := 1.0 / (1.0 + anchor.distance_to(Vector2(home % W, home / W)) / (200.0 * R.legacy_lin))
		if sc_count.get(p, 0) > 0: sc *= 0.3
		if sc > best_s: best_s = sc; best = p
	if best <= 0: return
	var target: int = g.sim_naval.own_coast_tile(best)
	if target < 0: return
	var need: float = (_troops(best) + g.nations[best].land * 60.0 * LA) * 1.6
	g.launch_boat(id, target, clampf(need / maxf(mine, 1.0), 0.05, SimRules.BOAT_ATTACK_FRACTION), 250000)
