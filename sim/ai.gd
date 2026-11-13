# Port of RoWorld src/shared/Core/SimAI.luau + SimAIEconomy.luau (nation and tribe AI).
# Nations think every NATION_THINK (15) ticks (staggered by id); their attack cycle comes round every
# attackRate ticks. Tribes act only on their own attack tick (tick % rate == attack_tick).
# The AI perceives the world through scan_border() and acts through the same entry points as the
# player (intent_attack, launch_boat, launch_nuke, propose_alliance, break_alliance); builds go
# through _build_at (the cost and placement rules of try_build without its flood search).
# Port differences (custom rules kept): nukes must reach the target from a silo (custom range as a
# fraction of land width, unless ICBM mode is on); radii are the port's x2.8 NUKE_R; INVASION_AGE /
# MOPUP_AGE are halved for the ~20 min pacing; no retint (colour upkeep), no team-mode refusals.
extends RefCounted
class_name SimAI

const NATION_THINK := 15
const NATION_ATTACK_RATE := [[65, 100], [55, 70], [45, 60]]
const TRIBE_ATTACK_RATE := [40, 79]
const TRIBE_TRAITOR_ODDS := 3
const TRIBE_SKIP_PLAYER_ODDS := 2
const TRIBE_DELETE_COOLDOWN := 300
const TRIBE_DELETE_DELAY := 300
const WAR_RATIO := [1.0, 1.0, 1.0]
const HUMAN_SKIP := [0.75, 0.25, 0.0]
const NUKE_GAP := 1800
const NUKE_TARGET_COOL := 600
const HUMAN_NUKE_EXTRA := 1200
const LATE_WAR_FROM := 12000
const LATE_WAR_SPAN := 9000
# Source: INVASION_AGE 12000 / MOPUP_AGE 6000; halved with the ~20 min pacing so oceans get crossed in time.
var INVASION_AGE := 6000
const INVASION_GAP := 150
var MOPUP_AGE := 3000
const MOPUP_GAP := 200
# Rules (human protection)
const HUMAN_GRACE_NEAR := 40
const HUMAN_GRACE_PER_TILE := 3
const HUMAN_GRACE_MAX_EXTRA := 1200
# SimAIEconomy
const NUKE_AGE := [4800, 3600, 2700]
const NATION_WAR_AGE := 1200
const SILO_TOP_RANK := 12
const PORT_PER_CITY := 0.75
const FACTORY_PER_CITY := 0.75
const FACTORY_COASTAL_MULT := 0.33
const SAM_PER_CITY := [0.15, 0.2, 0.25]
const SILO_PER_CITY := 0.2
const FIRST_SILO_PER_CITY := 0.4
const MAX_SILOS := 3
const PERCEIVED_COST_STEP := {0: 1.0, 1: 1.0, 2: 1.0, 3: 0.0, 4: 0.3, 5: 1.0}
const UPGRADE_DENSITY_FULL_TILES := 1500.0
const BUILD_ORDER := [1, 2, 4, 5]   # port, factory, SAM, silo; a city when none is due
const CROWDED_FULL_TILES_PER_NATION := 7500.0
const PORT_FIRST := true
const CITIES_BEFORE_SAVING := 3
const PORT_WATER_FULL_TILES := 3000.0
const PORT_RETRY_TICKS := 300
const DEFENSE_PER_BORDER := 250
const DEFENSE_CAP := 6
const DEFENSE_GAP := 600
const WARSHIP_RETALIATE_P := [0.0, 0.15, 0.5]
const WARSHIP_FLEET_CAP := 10
const STRUCT_KINDS := [0, 1, 2, 3, 4, 5, 10, 14, 15]
const TRIBE_STRUCT_KINDS := [0, 1, 2, 3, 4, 5]
# port building ids (main.gd): 0 city 1 port 2 factory 3 defense 4 SAM 5 silo; bombs 7 atom 8 hydrogen 9 MIRV
const K_CITY := 0
const K_PORT := 1
const K_FACTORY := 2
const K_DEFENSE := 3
const K_SAM := 4
const K_SILO := 5
const K_ATOM := 7
const K_HYDROGEN := 8
const K_MIRV := 9

var g
var R: SimRules
var st := {}  # id -> per-AI state dict
var attackers_on := {}
var rank := {}
var leader := 0
var leader_share := 0.0
var runaway_human := 0
var nuke_cool := {}
var doomed := []
var last_capitulation := -100000
var _crowded = null
var _body_sizes := {}
var _body_src_size := -1
var _ocean_body := -1
var stats := {"builds": 0, "upgrades": 0, "nukes": 0, "asks": 0, "breaks": 0, "capitulations": 0, "tribe_boats": 0, "deletes": 0, "boats": 0}
# last scan_border result
var sc_list := []
var sc_count := {}
var sc_tile := {}
var sc_neutral := 0
var sc_neutral_tile := -1
var sc_fallout_tile := -1
var _near := []   # tribe: nearby owners (0 = free land)

func _init(main, rules: SimRules) -> void:
	g = main
	R = rules

func setup() -> void:
	st.clear(); rank.clear(); nuke_cool.clear(); doomed.clear()
	leader = 0; leader_share = 0.0; runaway_human = 0; last_capitulation = -100000
	_crowded = null; _body_src_size = -1
	for k in stats: stats[k] = 0
	var rng: RandomNumberGenerator = g.rng
	for id in range(2, g.nations.size()):
		var s := {
			"aggression": rng.randf_range(0.8, 1.25),
			"naval": rng.randf_range(0.5, 1.5),
			"next_think": id % NATION_THINK,
			"grace_jitter": rng.randi_range(0, R.HUMAN_GRACE_JITTER),
			"last_ally_ask": rng.randi_range(0, 600),
			"trigger_r": rng.randi_range(50, 59) / 100.0,
			"reserve_r": rng.randi_range(30, 39) / 100.0,
			"expand_r": rng.randi_range(10, 19) / 100.0,
			"started": false, "tribe_tn": true, "next_attack": 0, "attack_rate": 0, "attack_tick": 0,
			"last_boat": 0, "last_nuke": -100000, "last_build": 0, "crowded_first": false, "port_wait": 0,
			"last_defense": -100000, "last_delete": -1, "last_mop": 0, "last_inv": 0, "coast": -1,
		}
		if g.kind_of(id) == SimRules.KIND_TRIBE:
			var rate := int(rng.randi_range(TRIBE_ATTACK_RATE[0], TRIBE_ATTACK_RATE[1]) * R.ai_rate_mult)
			s.attack_rate = rate
			s.attack_tick = rng.randi_range(0, rate - 1)
		st[id] = s

func _troops(id: int) -> float: return g.nations[id].troops
func _cap(id: int) -> float: return maxf(g.troop_cap(id), 1.0)
func _diff() -> int: return clampi(g.diff_i, 0, 2)
func _L() -> float: return R.legacy_lin
func _LA() -> float: return R.legacy_lin * R.legacy_lin

# SimAI._tribe_answers: a tribe answers alliance requests / renewals on its attack ticks after its first
func tribe_answers(id: int) -> bool:
	if not st.has(id): return true
	var s: Dictionary = st[id]
	return s.started and s.attack_rate > 0 and g.sim_atk.tick % int(s.attack_rate) == int(s.attack_tick)

func tick() -> void:
	var t: int = g.sim_atk.tick
	if t % 50 == 0 or rank.is_empty(): _update_leader()
	# AI nations at war with each owner: live non-counter attacks plus transports under way to a human
	attackers_on.clear()
	var pairs := {}
	for a in g.attacks:
		if not a.get("counter", false) and a.t > 0 and g.kind_of(a.a) == SimRules.KIND_NATION:
			pairs[a.a * 4096 + a.t] = true
	for bt in g.boats:
		var tg: int = g.owner_map[bt.dest]
		if tg > 0 and g.kind_of(tg) == SimRules.KIND_HUMAN and g.kind_of(bt.a) == SimRules.KIND_NATION:
			pairs[bt.a * 4096 + tg] = true
	for k in pairs:
		attackers_on[k % 4096] = attackers_on.get(k % 4096, 0) + 1
	if not doomed.is_empty(): _delete_doomed()
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

func _update_leader() -> void:
	var best := 0; var bt := 0; var second := 0
	var ids := []
	for id in range(1, g.nations.size()):
		var n = g.nations[id]
		if not n.alive: continue
		var land: int = n.land
		if land > bt:
			second = bt; bt = land; best = id
		elif land > second:
			second = land
		if land > 0: ids.append(id)
	leader = best
	leader_share = _land_share(best) if best > 0 else 0.0
	ids.sort_custom(func(p, q): return g.nations[p].land > g.nations[q].land)
	rank.clear()
	for k in ids.size(): rank[ids[k]] = k + 1
	runaway_human = 0
	if best > 0 and g.kind_of(best) == SimRules.KIND_HUMAN and leader_share >= 0.15 and bt >= 1.3 * second:
		runaway_human = best

# ---------------- perception ----------------
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
		# (unrolled 4-neighbourhood: no per-tile array allocation)
		for d in 4:
			var n: int
			if d == 0:
				if x == 0: continue
				n = t - 1
			elif d == 1:
				if x == W - 1: continue
				n = t + 1
			elif d == 2:
				n = t - W
				if n < 0: continue
			else:
				n = t + W
				if n >= N: continue
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
	var r: Array = NATION_ATTACK_RATE[_diff()]
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

static func _great_powers(a_share: float, b_share: float) -> bool:
	return (a_share >= 0.12 and b_share >= 0.08) or (b_share >= 0.12 and a_share >= 0.08)

func _grudge_of(me: int, other: int) -> bool:
	return int(g.nations[me].get("grudge_" + str(other), -1)) > g.sim_atk.tick

func _hostile(a: int, b: int) -> bool:
	return _grudge_of(a, b) or _grudge_of(b, a)

func _spawn_tile(id: int) -> int:
	if id == g.PLAYER: return int(g.start_tile)
	return int(g.nations[id].get("spawn_tile", -1))

# Tribes have no human protection beyond the spawn shield (here: the peace window).
func may_attack_human(id: int, h: int) -> bool:
	if g.kind_of(id) == SimRules.KIND_TRIBE: return g.elapsed >= g.peace
	return _may_attack_human(id, h, g.sim_atk.tick)

# Human protection: the AI's grace (global minimum + its random delay + more for distant nations)
# has passed and fewer than MAX_AI_WARS_ON_HUMAN nations already fight that human.
func _may_attack_human(id: int, h: int, age: int) -> bool:
	if g.elapsed < g.peace: return false
	var grace: int = R.human_grace_ticks(g.diff_i) + int(st[id].grace_jitter)
	var a := _spawn_tile(id)
	if a < 0: a = centre_tile(id)
	var b := _spawn_tile(h)
	if a >= 0 and b >= 0:
		var W: int = g.W
		var dist := int(Vector2(a % W - b % W, a / W - b / W).length() / R.legacy_lin)
		grace += clampi((dist - HUMAN_GRACE_NEAR) * HUMAN_GRACE_PER_TILE, 0, HUMAN_GRACE_MAX_EXTRA)
	if age < grace: return false
	if g.kind_of(id) == SimRules.KIND_NATION and attackers_on.get(h, 0) >= R.MAX_AI_WARS_ON_HUMAN[_diff()]:
		return false
	return true

# ---------------- nations ----------------
func _think_nation(id: int) -> void:
	var s: Dictionary = st[id]
	var age: int = g.sim_atk.tick
	var troops := _troops(id)
	var fill := troops / _cap(id)
	scan_border(id)
	if _consider_capitulation(id, age): return
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
	var u0 := Time.get_ticks_usec()
	if g.can_build(id): _consider_build(id, age)
	if due:
		_maybe_spawn_warship(id)
		_counter_infestation(id)
	var u1 := Time.get_ticks_usec()
	if not warred and sc_neutral == 0:
		_consider_boat(id, age)
	var u2 := Time.get_ticks_usec()
	_consider_mopup(id, age)
	var u3 := Time.get_ticks_usec()
	_consider_invasion(id, age)
	var u4 := Time.get_ticks_usec()
	_consider_nuke(id, age)
	_consider_diplomacy(id, age)
	g._fp["ai_prot"] = g._fp.get("ai_prot", 0) + u1 - u0
	g._fp["ai_boat"] = g._fp.get("ai_boat", 0) + u2 - u1
	g._fp["ai_mop"] = g._fp.get("ai_mop", 0) + u3 - u2
	g._fp["ai_inv"] = g._fp.get("ai_inv", 0) + u4 - u3

# Endgame: a small nation overrun by a far stronger attacker surrenders (Rules.CAPITULATE_*).
func _consider_capitulation(id: int, age: int) -> bool:
	if age < SimRules.CAPITULATE_AGE or _land_share(id) >= SimRules.CAPITULATE_SHARE: return false
	var t: int = g.sim_atk.tick
	if t - last_capitulation < SimRules.CAPITULATE_GAP: return false
	if t - int(g.nations[id].get("attacked_tick", -1000)) > 40: return false
	var mine := _troops(id) + 1.0
	for a in g.attacks:
		if a.t != id or g.kind_of(a.a) == SimRules.KIND_TRIBE: continue
		if _troops(a.a) + a.troops >= SimRules.CAPITULATE_RATIO * mine:
			capitulate(id, a.a)
			return true
	return false

# Sim.capitulate: every tile of the loser goes to the winner (never a human loser)
func capitulate(loser: int, winner: int) -> void:
	if loser <= 0 or winner <= 0 or not g.nations[loser].alive or not g.nations[winner].alive: return
	if g.kind_of(loser) == SimRules.KIND_HUMAN: return
	var nv = g.nations[loser]
	var bb: Rect2i = nv.bb.intersection(Rect2i(0, 0, g.W, g.H))
	var W: int = g.W
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var i: int = y * W + x
			if g.owner_map[i] == loser: g._set_owner(i, winner)
	last_capitulation = g.sim_atk.tick
	nv["killer"] = winner
	stats.capitulations += 1
	g.notify("%s surrendered to %s" % [g._nname(loser), g._nname(winner)], "info")

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
	return float(g.nations[id].land) / maxf(float(g.land_total - g.fallout_count), 1.0)

func _consider_war(id: int, fill: float, age: int) -> bool:
	var s: Dictionary = st[id]
	if fill < s.reserve_r: return false
	if fill < s.trigger_r and g.rng.randf() >= 0.1: return false
	var d := _diff()
	var mine := _troops(id)
	var my_share := _land_share(id)
	var best := -1
	var best_s := 0.0
	var L: float = R.legacy_lin
	for p in sc_list:
		if sc_count[p] < 2 * L or g.allied(id, p): continue
		var pk: int = g.kind_of(p)
		var at_war: bool = g.sim_atk.attack_between(id, p) != null
		if pk == SimRules.KIND_HUMAN and not at_war and (not _may_attack_human(id, p, age) or g.rng.randf() < HUMAN_SKIP[d]):
			continue
		var sc := mine / (_troops(p) + 1.0)
		sc *= pow(0.6, attackers_on.get(p, 0) - (1 if at_war else 0))
		if pk == SimRules.KIND_TRIBE: sc *= 1.5
		if g.is_traitor(p): sc *= 1.3
		if _grudge_of(id, p): sc *= 1.35
		if at_war: sc *= 1.2
		if p == runaway_human: sc *= 1.4
		if _great_powers(my_share, _land_share(p)): sc *= 1.5
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

# A transport aimed at a human takes a war slot at once
func _boat_at(id: int, tile: int, ratio: float, max_nodes := 250000) -> bool:
	var tg: int = g.owner_map[tile]
	var ok: bool = g.launch_boat(id, tile, ratio, max_nodes)
	if ok:
		stats.boats += 1
		if tg > 0 and g.kind_of(tg) == SimRules.KIND_HUMAN and g.sim_atk.attack_between(id, tg) == null:
			attackers_on[tg] = attackers_on.get(tg, 0) + 1
	return ok

# Coastal land tile -> id of the water body it touches (0: none)
func _coast_body(t: int) -> int:
	var body: PackedInt32Array = g.sim_naval.body
	if body.size() != g.owner_map.size(): return 0
	var W: int = g.W
	var N: int = body.size()
	var x := t % W
	if x > 0 and body[t - 1] > 0: return body[t - 1]
	if x < W - 1 and body[t + 1] > 0: return body[t + 1]
	if t >= W and body[t - W] > 0: return body[t - W]
	if t < N - W and body[t + W] > 0: return body[t + W]
	return 0

func _consider_boat(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	if age < 600 or g.sim_naval.boats_of(id) >= (2 if _diff() == 2 else 1): return
	if g.sim_atk.tick - int(s.last_boat) < int(300.0 / float(s.naval)): return
	var home := own_coast(id)
	if home < 0: return
	s.last_boat = g.sim_atk.tick
	var water_body := _coast_body(home)
	var cl: PackedInt32Array = g.sim_naval.coast_list
	if cl.is_empty(): return
	var om: PackedInt32Array = g.owner_map
	var fo: PackedByteArray = g.fallout
	var mine := _troops(id)
	var L := _L()
	var tile_troops := 60.0 * _LA()
	var W: int = g.W
	var best := -1
	var best_s := 0.0
	var rng: RandomNumberGenerator = g.rng
	for _k in 48:
		var c: int = cl[rng.randi() % cl.size()]
		if _coast_body(c) != water_body or fo[c] == 1: continue
		var o: int = om[c]
		if o < 0 or o == id or g.allied(id, o): continue
		var sc := 0.0
		if o == 0:
			sc = 3.0
		else:
			var ratio := mine * 0.3 / (_troops(o) / maxf(g.nations[o].land, 1) * tile_troops + 1.0)
			if ratio < 1.0: continue
			if g.kind_of(o) == SimRules.KIND_HUMAN and g.sim_atk.attack_between(id, o) == null and not _may_attack_human(id, o, age):
				continue
			sc = 1.0 + minf(ratio, 3.0) * 0.3
			if g.kind_of(o) == SimRules.KIND_TRIBE: sc *= 1.4
		var dist := Vector2(home % W - c % W, home / W - c / W).length()
		sc /= 1.0 + dist / (110.0 * L)
		if sc > best_s:
			best_s = sc; best = c
	if best >= 0 and best_s > 0.35:
		_boat_at(id, best, SimRules.BOAT_ATTACK_FRACTION, 12000)

func _consider_invasion(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	if age < INVASION_AGE or g.sim_atk.tick - int(s.last_inv) < INVASION_GAP: return
	s.last_inv = g.sim_atk.tick + g.rng.randi_range(0, 80)
	if _land_share(id) < 0.12 or g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return
	var mine := _troops(id)
	if mine < _cap(id) * 0.3: return
	var best := 0
	var best_s := 0.0
	for p in range(1, g.nations.size()):
		if p == id or not g.nations[p].alive or int(rank.get(p, 999)) > 8 or g.allied(id, p) or _land_share(p) < 0.04: continue
		if sc_count.get(p, 0) > 0 or own_coast(p) < 0: continue
		var theirs := _troops(p) + 1.0
		if mine < 0.7 * theirs: continue
		if g.kind_of(p) == SimRules.KIND_HUMAN and g.sim_atk.attack_between(id, p) == null and not _may_attack_human(id, p, age): continue
		var sc := (mine / theirs) * _land_share(p) * (1.5 if _grudge_of(id, p) else 1.0)
		if sc > best_s: best_s = sc; best = p
	if best <= 0: return
	var cl: PackedInt32Array = g.sim_naval.coast_list
	if cl.is_empty(): return
	for _k in 300:
		var c: int = cl[g.rng.randi() % cl.size()]
		if g.owner_map[c] == best and g.fallout[c] == 0:
			_boat_at(id, c, SimRules.BOAT_ATTACK_FRACTION)
			return

func _consider_mopup(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	if age < MOPUP_AGE or g.sim_atk.tick - int(s.last_mop) < MOPUP_GAP: return
	s.last_mop = g.sim_atk.tick + g.rng.randi_range(0, 100)
	if _land_share(id) < 0.03 or g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return
	var mine := _troops(id)
	var LA := _LA()
	var small := maxi(int(600 * LA), int(0.006 * g.land_total))
	var home := own_coast(id)
	if home < 0: return
	var best := 0
	var best_s := 0.0
	var W: int = g.W
	for p in range(1, g.nations.size()):
		var np = g.nations[p]
		if p == id or not np.alive or np.land <= 0 or np.land > small or g.allied(id, p): continue
		if np.troops > 0.2 * mine or own_coast(p) < 0: continue
		if g.kind_of(p) == SimRules.KIND_HUMAN and g.sim_atk.attack_between(id, p) == null and not _may_attack_human(id, p, age): continue
		var anchor := _spawn_tile(p)
		if anchor < 0: anchor = home
		var sc := 1.0 / (1.0 + Vector2(home % W - anchor % W, home / W - anchor / W).length() / (200.0 * _L()))
		if sc_count.get(p, 0) > 0: sc *= 0.3
		if sc > best_s: best_s = sc; best = p
	if best <= 0: return
	var target := own_coast(best)
	if target < 0: return
	var need: float = (_troops(best) + g.nations[best].land * 60.0 * LA) * 1.6
	_boat_at(id, target, clampf(need / maxf(mine, 1.0), 0.05, SimRules.BOAT_ATTACK_FRACTION))

# ---------------- nukes (SimAI._consider_nuke 805-949) ----------------
func _consider_nuke(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	var d := _diff()
	if age < NUKE_AGE[d] or g.elapsed < g.peace or g.owned_count(id, K_SILO) == 0: return
	var t: int = g.sim_atk.tick
	if t - int(s.last_nuke) < NUKE_GAP: return
	var gold: float = g.nations[id].gold
	if gold < g.nuke_cost(K_ATOM): return
	var mine := _troops(id)
	var best := 0
	var best_s := 0.0
	var LA := _LA()
	for p in sc_list:
		if g.allied(id, p) or g.kind_of(p) == SimRules.KIND_TRIBE or g.nations[p].land < 400 * LA or int(nuke_cool.get(p, 0)) > t: continue
		if g.kind_of(p) == SimRules.KIND_HUMAN and (age < HUMAN_NUKE_EXTRA or not _may_attack_human(id, p, age - HUMAN_NUKE_EXTRA)): continue
		var sc := float(g.nations[p].land)
		if _grudge_of(id, p): sc *= 1.6
		var at_war := _grudge_of(id, p) or g.sim_atk.attack_between(id, p) != null
		if not at_war: continue
		if _troops(p) > mine: sc *= 1.3
		if sc > best_s: best_s = sc; best = p
	# the leader / a runaway human: only for rivals that border it or hold a grudge
	for p2 in [leader, runaway_human]:
		if p2 <= 0 or p2 == id or g.allied(id, p2) or int(nuke_cool.get(p2, 0)) > t or _land_share(p2) < 0.25: continue
		if sc_count.get(p2, 0) == 0 and not _grudge_of(id, p2): continue
		if g.kind_of(p2) == SimRules.KIND_HUMAN and not _may_attack_human(id, p2, age - HUMAN_NUKE_EXTRA): continue
		var s2: float = g.nations[p2].land * (2.0 if p2 == runaway_human else 1.2)
		if s2 > best_s: best_s = s2; best = p2
	if best <= 0: return
	var kind := K_ATOM
	if g.mirv_enabled and gold >= g.nuke_cost(K_MIRV) and (best == leader or best == runaway_human) and _land_share(best) >= 0.35:
		kind = K_MIRV
	elif gold >= g.nuke_cost(K_HYDROGEN) and g.nations[best].land > 2500 * LA:
		kind = K_HYDROGEN
	var target := _nuke_target(id, best, kind)
	if target < 0: return
	# custom range rule: the chosen bomb must reach from a silo; else the cheapest affordable one that does
	if not g.icbm_mode:
		var dd: float = g._any_silo_dist(id, Vector2(target % g.W + 0.5, target / g.W + 0.5))
		if dd > g.nuke_range(kind):
			kind = -1
			for kk in [K_ATOM, K_HYDROGEN, K_MIRV]:
				if kk == K_MIRV and not g.mirv_enabled: continue
				if g.nuke_range(kk) >= dd and gold >= g.nuke_cost(kk): kind = kk; break
			if kind < 0: return
	s.last_nuke = t
	if g.launch_nuke(id, kind, target):
		stats.nukes += 1
		nuke_cool[best] = t + NUKE_TARGET_COOL
		g.nations[id].last_nuke = g.elapsed
		if sc_count.get(best, 0) > 0 and _troops(id) > _troops(best) * 0.6:
			g.intent_attack(id, sc_tile[best], 0.3)

func _nuke_target(id: int, p: int, kind: int) -> int:
	var cands := []
	for k in [K_CITY, K_SILO, K_FACTORY, K_PORT]:
		if g.owned_count(p, k) > 0:
			for s in g.structs:
				if s.o == p and s.k == k: cands.append(s.tile)
			if cands.size() >= 6: break
	if sc_count.get(p, 0) > 0: cands.append(sc_tile[p])
	var spt := _spawn_tile(p)
	if spt >= 0 and g.owner_map[spt] == p: cands.append(spt)
	if cands.is_empty(): return -1
	var radius: float = float(g.NUKE_R.get(kind, 7.0))
	for _k in mini(cands.size(), 6):
		var c: int = cands[g.rng.randi() % cands.size()]
		if kind == K_MIRV or _blast_safe(id, c, radius + 2.0 * _L()): return c
	return -1

# True when a blast of `radius` at `c` would not touch allies and would spare most own land.
func _blast_safe(id: int, c: int, radius: float) -> bool:
	var own := 0; var total := 0
	var W: int = g.W; var H: int = g.H
	var cx := c % W; var cy := c / W
	var r := int(radius)
	var rng: RandomNumberGenerator = g.rng
	for _k in 40:
		var x := clampi(cx + rng.randi_range(-r, r), 0, W - 1)
		var y := clampi(cy + rng.randi_range(-r, r), 0, H - 1)
		var o: int = g.owner_map[y * W + x]
		if o <= 0: continue
		total += 1
		if o == id: own += 1
		elif g.allied(id, o): return false
	return own * 4 <= total

# ---------------- diplomacy (SimAI._consider_diplomacy 951-1007) ----------------
func _allies_of(id: int) -> Array:
	var out := []
	for key in g.allies:
		var a: int = key / 4096; var b: int = key % 4096
		if a == id: out.append(b)
		elif b == id: out.append(a)
	return out

func _consider_diplomacy(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	var t: int = g.sim_atk.tick
	if age < 300 or t - int(s.last_ally_ask) < 600: return
	s.last_ally_ask = t + g.rng.randi_range(0, 600)
	var mine := _troops(id)
	var my_share := _land_share(id)
	var mine_allies := _allies_of(id)
	# betrayal: great powers, dominant nations shedding weak allies, aggressive stabs
	for p in mine_allies:
		var ps := _land_share(p)
		var chance := 0.0
		if _great_powers(my_share, ps): chance = 0.35
		elif my_share >= 0.25 and mine > 2.0 * _troops(p): chance = 0.15
		elif mine > 3.0 * _troops(p) and sc_count.get(p, 0) > 0: chance = 0.04 * float(s.aggression) * (0.5 + 0.5 * _diff())
		if g.kind_of(p) == SimRules.KIND_HUMAN and age < R.human_grace_ticks(g.diff_i) * 2: chance *= 0.25
		if chance > 0.0 and g.rng.randf() < chance:
			g.break_alliance(id, p)
			stats.breaks += 1
			return
	if mine_allies.size() >= g.AI_MAX_ALLIES or g.rng.randf() > 0.4: return
	var best := 0
	var best_s := 0.0
	for p in sc_list:
		if g.kind_of(p) == SimRules.KIND_TRIBE or g.allied(id, p) or _hostile(id, p) or g.has_request(id, p): continue
		if g.is_traitor(p) or g._ally_count(p) >= g.AI_MAX_ALLIES + (2 if g.kind_of(p) == SimRules.KIND_HUMAN else 0): continue
		if _great_powers(my_share, _land_share(p)): continue
		var sc: float = _troops(p) / maxf(mine, 1.0) + g.rng.randf() * 0.5
		if g.kind_of(p) == SimRules.KIND_HUMAN: sc += 0.4
		if sc > best_s: best_s = sc; best = p
	if best > 0 and best_s > 0.6:
		if best == g.PLAYER and g.ally_card != null and g.ally_card.visible: return
		if g.propose_alliance(id, best): stats.asks += 1

# ---------------- economy (SimAIEconomy._consider_build 244-573) ----------------
func _structs_of(id: int, k: int) -> Array:
	var out := []
	for s in g.structs:
		if s.o == id and s.k == k: out.append(s)
	return out

func _crowded_map() -> bool:
	if _crowded == null:
		var nat := 0
		for id in range(2, g.nations.size()):
			if g.kind_of(id) == SimRules.KIND_NATION: nat += 1
		var land: float = g.land_total * R.k_area
		_crowded = land > 0 and nat * CROWDED_FULL_TILES_PER_NATION > land
	return _crowded

func _structure_due(id: int, kind: int, cities: int, age: int) -> bool:
	var d := _diff()
	match kind:
		K_PORT:
			return own_coast(id) >= 0 and g.owned(id, K_PORT) < int(cities * PORT_PER_CITY)
		K_FACTORY:
			var mult := FACTORY_COASTAL_MULT if own_coast(id) >= 0 else 1.0
			return g.owned(id, K_FACTORY) < int(cities * FACTORY_PER_CITY * mult)
		K_SAM:
			return g.owned(id, K_SAM) < int(cities * SAM_PER_CITY[d]) and age > NATION_WAR_AGE
		K_SILO:
			var silos: int = g.owned_count(id, K_SILO)
			return silos < MAX_SILOS and silos < int(cities * (FIRST_SILO_PER_CITY if silos == 0 else SILO_PER_CITY)) \
				and age > NUKE_AGE[d] - 900 and int(rank.get(id, 999)) <= SILO_TOP_RANK
	return false

func _save_up() -> float:
	return float(g.build_data[K_MIRV][2]) + SimRules.MIRV_COST_STEP * g.mirvs_launched + float(g.build_data[K_HYDROGEN][2])

func _spawn_structure(id: int, kind: int, cities: int, threat: int) -> bool:
	var gold: float = g.nations[id].gold
	var cost: float = g.build_cost(id, kind)
	var perceived := cost
	if kind != K_DEFENSE and cities >= CITIES_BEFORE_SAVING and gold < _save_up():
		perceived = cost * (1.0 + float(PERCEIVED_COST_STEP.get(kind, 1.0)) * g.owned(id, kind))
	if gold < perceived: return false
	if kind in g.UPGRADABLE and g.owned_count(id, kind) > 0:
		var total := 0
		for k in STRUCT_KINDS: total += g.owned_count(id, k)
		if total * UPGRADE_DENSITY_FULL_TILES > g.nations[id].land * R.k_area:
			var ready := []
			for s in _structs_of(id, kind):
				if float(s.get("bt", 0.0)) <= 0.0: ready.append(s)
			if ready.is_empty(): return false
			return _upgrade_at(id, ready[g.rng.randi() % ready.size()])
	var site := _pick_site(id, kind, threat)
	return site >= 0 and _build_at(id, kind, site)

func _build_at(id: int, kind: int, site: int) -> bool:
	var n = g.nations[id]
	var cost: float = g.build_cost(id, kind)
	if n.gold < cost or not valid_site(id, kind, site): return false
	n.gold -= cost
	g._struct_add(kind, site, id)
	stats.builds += 1
	return true

func _upgrade_at(id: int, s) -> bool:
	var n = g.nations[id]
	var cost: float = g.build_cost(id, s.k)
	if n.gold < cost: return false
	n.gold -= cost
	g._upgrade_struct(s)
	stats.upgrades += 1
	return true

func _consider_build(id: int, age: int) -> void:
	var s: Dictionary = st[id]
	var t: int = g.sim_atk.tick
	if t - int(s.last_build) < 20: return
	if g.nations[id].gold < 100000.0: return
	var cities: int = g.owned(id, K_CITY)
	var threat := _defense_threat(id)
	if cities > 0 and threat > 0 and g.owned_count(id, K_DEFENSE) < _defense_cap(id) \
			and t - int(s.last_defense) >= DEFENSE_GAP and g.rng.randf() < 0.35:
		if _spawn_structure(id, K_DEFENSE, cities, threat):
			s.last_build = t; s.last_defense = t
		return
	if not s.crowded_first:
		var coastal := own_coast(id) >= 0
		if (coastal and PORT_FIRST) or _crowded_map():
			var first := K_PORT if coastal else K_FACTORY
			if g.nations[id].gold >= g.build_cost(id, first):
				s.crowded_first = true
				if _spawn_structure(id, first, cities, threat):
					s.last_build = t
					return
		else:
			s.crowded_first = true
	for kind in BUILD_ORDER:
		if _structure_due(id, kind, cities, age) and _spawn_structure(id, kind, cities, threat):
			s.last_build = t
			return
	if _spawn_structure(id, K_CITY, cities, threat):
		s.last_build = t

func _defense_cap(id: int) -> int:
	if g.kind_of(id) == SimRules.KIND_TRIBE: return 1
	return clampi(int(g.border[id].size() / (DEFENSE_PER_BORDER * _L())), 1, DEFENSE_CAP)

func _defense_threat(id: int) -> int:
	var mine := maxf(_troops(id), 1.0)
	var age: int = g.sim_atk.tick
	var tribe: bool = g.kind_of(id) == SimRules.KIND_TRIBE
	var best := 0
	var bs := 0.0
	var L := _L()
	for p in sc_list:
		if sc_count[p] < 6 * L or g.allied(id, p): continue
		var theirs := _troops(p)
		var attacking: bool = g.sim_atk.attack_between(p, id) != null
		var ok := attacking
		if not ok and not tribe:
			if (_grudge_of(id, p) and theirs > 0.7 * mine) or (age > NATION_WAR_AGE and g.kind_of(p) != SimRules.KIND_TRIBE and theirs > 1.5 * mine and sc_count[p] >= 12 * L):
				ok = true
		if not ok: continue
		var sc := theirs * (2.0 if attacking else 1.0)
		if sc > bs: bs = sc; best = p
	return best

func _pick_site(id: int, kind: int, threat: int) -> int:
	var tiles: int = g.nations[id].land
	if kind == K_PORT: return _port_site(id)
	if kind == K_FACTORY: return _factory_site(id)
	if kind == K_DEFENSE: return _defense_site(id, threat)
	var L := _L()
	if kind == K_SAM:
		var cities := _structs_of(id, K_CITY)
		if not cities.is_empty():
			var s0 := find_site(id, kind, cities[g.rng.randi() % cities.size()].tile, ceili(8 * L), 16)
			if s0 >= 0: return s0
	var spread := clampi(int(sqrt(float(tiles)) * 0.45), ceili(6 * L), ceili(45 * L))
	var site := find_site(id, kind, centre_tile(id), spread, 24)
	if site < 0:
		var a := _spawn_tile(id)
		if a < 0 or g.owner_map[a] != id: a = own_border_tile(id)
		site = find_site(id, kind, a, spread, 12)
	return site

func _body_size(b: int) -> int:
	var body: PackedInt32Array = g.sim_naval.body
	if _body_src_size != body.size():
		_body_src_size = body.size()
		_body_sizes.clear()
		for v in body:
			if v > 0: _body_sizes[v] = _body_sizes.get(v, 0) + 1
		var big := 0
		_ocean_body = -1
		for k in _body_sizes:
			if _body_sizes[k] > big: big = _body_sizes[k]; _ocean_body = k
	return _body_sizes.get(b, 0)

func _water_ok(t: int) -> bool:
	var b := _coast_body(t)
	if b <= 0: return false
	var sz := _body_size(b)
	return b == _ocean_body or sz >= PORT_WATER_FULL_TILES / R.k_area

func _port_site(id: int) -> int:
	var s: Dictionary = st[id]
	var t: int = g.sim_atk.tick
	if t < int(s.port_wait): return -1
	var anchor := own_coast(id)
	var L := _L()
	var far := ceili(60 * L)
	var mine := own_coast_tiles(id, 4096, true)
	var best := -1
	var best_d := -1.0
	for i in 36:
		var c := -1
		if i < 16:
			c = find_site(id, K_PORT, anchor, ceili(30 * L), 1)
		elif not mine.is_empty():
			var r: int = mine[g.rng.randi() % mine.size()]
			if valid_site(id, K_PORT, r): c = r
		if c < 0 or not _water_ok(c): continue
		var dd := own_struct_dist2(id, K_PORT, c, far)
		if dd < 0.0: dd = far * far + 1.0
		if dd > best_d: best_d = dd; best = c
	if best < 0: s.port_wait = t + PORT_RETRY_TICKS
	return best

func _factory_site(id: int) -> int:
	var hubs := _structs_of(id, K_CITY) + _structs_of(id, K_PORT)
	if hubs.is_empty(): return -1
	for _k in mini(hubs.size(), 4):
		var h = hubs[g.rng.randi() % hubs.size()]
		var site := find_site(id, K_FACTORY, h.tile, ceili(R.struct_min_dist) + ceili(3 * _L()), 14)
		if site >= 0: return site
	return -1

func _defense_site(id: int, threat: int) -> int:
	if threat <= 0 or sc_count.get(threat, 0) <= 0: return -1
	var contact: int = sc_tile[threat]
	var r: float = R.defense_range
	var near := ceili(4 * _L())
	for _k in 16:
		var c := find_site(id, K_DEFENSE, contact, near, 1)
		if c >= 0 and own_struct_dist2(id, K_DEFENSE, c, r) < 0.0: return c
	return -1

# SimStructures.find_site: a random valid site within `radius` (box) of `anchor`; ports snap to own
# coast within 4 original tiles
func find_site(id: int, kind: int, anchor: int, radius: int, tries: int) -> int:
	if anchor < 0: return -1
	var W: int = g.W; var H: int = g.H
	var cx := anchor % W; var cy := anchor / W
	var coast_r := ceili(4 * _L())
	var rng: RandomNumberGenerator = g.rng
	for _k in tries:
		var x := clampi(cx + rng.randi_range(-radius, radius), 0, W - 1)
		var y := clampi(cy + rng.randi_range(-radius, radius), 0, H - 1)
		var t := y * W + x
		if kind == K_PORT:
			t = _nearest_coast(id, t, coast_r)
			if t < 0: continue
		if valid_site(id, kind, t): return t
	return -1

func valid_site(id: int, kind: int, t: int) -> bool:
	if t < 0 or t >= g.owner_map.size() or g.owner_map[t] != id: return false
	if kind == K_PORT and not g._coastal(t): return false
	var W: int = g.W
	var md: float = R.struct_min_dist
	var md2 := md * md
	var tx := t % W; var ty := t / W
	for s in g.structs:
		var dx: int = s.tile % W - tx; var dy: int = s.tile / W - ty
		if dx * dx + dy * dy < md2: return false
	return true

func own_struct_dist2(id: int, kind: int, t: int, r: float) -> float:
	var best := -1.0
	var rr := r * r
	var W: int = g.W
	for s in g.structs:
		if s.o != id or s.k != kind: continue
		var dx: int = s.tile % W - t % W; var dy: int = s.tile / W - t / W
		var d := float(dx * dx + dy * dy)
		if d <= rr and (best < 0.0 or d < best): best = d
	return best

func _nearest_coast(id: int, t: int, r: int) -> int:
	var W: int = g.W; var H: int = g.H
	var cx := t % W; var cy := t / W
	var best := -1
	var bd := 1 << 30
	for y in range(maxi(0, cy - r), mini(H, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(W, cx + r + 1)):
			var c := y * W + x
			if g.owner_map[c] != id or not g._coastal(c): continue
			var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
			if d < bd: bd = d; best = c
	return best

# SimState.centre_tile: the owned tile nearest the centre of mass (square rings, bounded)
func centre_tile(id: int) -> int:
	var n = g.nations[id]
	if n.land <= 0: return -1
	var W: int = g.W; var H: int = g.H
	var cx := clampi(int(floor(n.sx / float(n.land) + 0.5)), 0, W - 1)
	var cy := clampi(int(floor(n.sy / float(n.land) + 0.5)), 0, H - 1)
	var c := cy * W + cx
	if g.owner_map[c] == id: return c
	var rmax := maxi(39, ceili(40.0 / R.k_lin))
	for r in range(1, rmax + 1):
		for dy in range(-r, r + 1):
			var y := cy + dy
			if y < 0 or y >= H: continue
			var step_x := 1 if absi(dy) == r else 2 * r
			var dx := -r
			while dx <= r:
				var x := cx + dx
				if x >= 0 and x < W and g.owner_map[y * W + x] == id: return y * W + x
				dx += step_x
	return own_border_tile(id)

func own_border_tile(id: int) -> int:
	if id >= g.border.size(): return -1
	for t in g.border[id]: return t
	return -1

# A coastal tile owned by `id` (-1 if none): cached, else the first coastal tile of its border
func own_coast(id: int) -> int:
	var s = st.get(id)
	if s != null:
		var c: int = s.coast
		if c >= 0 and g.owner_map[c] == id: return c
	var found := -1
	if id < g.border.size():
		for t in g.border[id]:
			if g._coastal(t): found = t; break
	if s != null: s.coast = found
	return found

# Every coastal tile of `id` (at most `cap`; water_ok filter optional), in border order
func own_coast_tiles(id: int, cap := 1 << 30, water_ok := false) -> Array:
	var out := []
	if id >= g.border.size(): return out
	for t in g.border[id]:
		if g._coastal(t) and (not water_ok or _water_ok(t)):
			out.append(t)
			if out.size() >= cap: break
	return out

# ---------------- warships (SimAIEconomy 579-764) ----------------
func _maybe_spawn_warship(id: int) -> void:
	if g.rng.randi() % 50 != 0 or g._count_ws(id) > 0 or g.nations[id].gold <= g.build_cost(id, 6): return
	var ports := []
	for s in _structs_of(id, K_PORT):
		if float(s.get("bt", 0.0)) <= 0.0: ports.append(s)
	if ports.is_empty(): return
	var sea: int = g._ai_sea_tile_near(ports[g.rng.randi() % ports.size()].tile, 250.0 / R.k_lin)
	if sea >= 0:
		var c6: float = g.build_cost(id, 6)
		if g.spawn_warship(id, sea): g.nations[id].gold -= c6

# Hard only: with 10+ warships at sea and an enemy owning more than 10, one of the three richest AI
# owners builds a warship on top of one of them.
func _counter_infestation(id: int) -> void:
	if _diff() < 2 or g.warships.size() <= WARSHIP_FLEET_CAP or g._count_ws(id) >= WARSHIP_FLEET_CAP: return
	var c6: float = g.build_cost(id, 6)
	if g.nations[id].gold < c6 or g.owned(id, K_PORT) <= 0: return
	var richer := 0
	for p in range(1, g.nations.size()):
		if p != id and g.nations[p].alive and g.kind_of(p) != SimRules.KIND_HUMAN and g.nations[p].gold > g.nations[id].gold:
			richer += 1
			if richer >= 3: return
	for p in range(1, g.nations.size()):
		if p == id or not g.nations[p].alive or g.allied(id, p) or g._count_ws(p) <= WARSHIP_FLEET_CAP: continue
		var theirs := []
		for w in g.warships:
			if w.o == p: theirs.append(w)
		if theirs.is_empty(): continue
		var tw = theirs[g.rng.randi() % theirs.size()]
		var pos: Vector2 = tw.pos
		var tt: int = int(pos.y) * g.W + int(pos.x)
		if g.owner_map[tt] == g.WATER and g.spawn_warship(id, tt): g.nations[id].gold -= c6
		else: g._ai_move_nearest_warship(id, tt)
		return

# ---------------- tribes ----------------
func _think_tribe(id: int) -> void:
	var s: Dictionary = st[id]
	var tn_near := _tribe_nearby(id)
	_tribe_delete_next(id)
	var traitor := _tribe_traitor(id)
	if traitor > 0 and g.rng.randi_range(1, TRIBE_TRAITOR_ODDS) == 1 and _tribe_send(id, traitor): return
	if s.tribe_tn:
		if tn_near:
			if _tribe_send_tn(id): return
		else:
			s.tribe_tn = false
	_tribe_attack_random(id)

# Owners next to the border (scan_border), free land (0) when it touches, then the shore probes:
# every SHORE_PROBE_EVERY-th coastal tile looks SHORE_PROBE_DIST tiles away in each direction whose
# first step is water. True when free land (not fallout) is nearby.
func _tribe_nearby(id: int) -> bool:
	scan_border(id)
	_near.clear()
	var seen := {}
	for p in sc_list:
		_near.append(p); seen[p] = true
	var tn := sc_neutral > 0
	if tn:
		_near.append(0); seen[0] = true
	var coasts := own_coast_tiles(id)
	if coasts.is_empty(): return tn
	var every := maxi(1, int(floor(10.0 / R.k_lin + 0.5)))
	var dist := maxi(2, int(floor(5.0 / R.k_lin + 0.5)))
	var W: int = g.W; var H: int = g.H
	var om: PackedInt32Array = g.owner_map
	var k := 0
	for c in coasts:
		if k % every == 0:
			var x: int = c % W; var y: int = c / W
			for dd in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var x1: int = x + dd.x; var y1: int = y + dd.y
				if x1 < 0 or x1 >= W or y1 < 0 or y1 >= H or om[y1 * W + x1] != g.WATER: continue
				var nx: int = x + dd.x * dist; var ny: int = y + dd.y * dist
				if nx < 0 or nx >= W or ny < 0 or ny >= H: continue
				var n: int = ny * W + nx
				var o: int = om[n]
				if o < 0 or o == id or seen.has(o) or (o == 0 and g.fallout[n] == 1): continue
				seen[o] = true
				_near.append(o)
				tn = tn or o == 0
		k += 1
	return tn

func _tribe_traitor(id: int) -> int:
	var pick := []
	for p in _near:
		if p > 0 and g.is_traitor(p) and not g.allied(id, p): pick.append(p)
	if pick.is_empty(): return 0
	return pick[g.rng.randi_range(0, pick.size() - 1)]

# The attacker of the biggest attack on `id` that is not an ally (tribes count too)
func _tribe_incoming(id: int) -> int:
	var best := 0
	var most := 0.0
	for a in g.attacks:
		if a.t != id or a.troops <= most or not g.nations[a.a].alive or g.allied(id, a.a): continue
		most = a.troops; best = a.a
	return best

func _tribe_attack_random(id: int) -> void:
	var s: Dictionary = st[id]
	if _troops(id) / _cap(id) < s.trigger_r: return
	var attacker := _tribe_incoming(id)
	if attacker > 0 and _tribe_send(id, attacker): return
	var traitor := _tribe_traitor(id)
	if traitor > 0 and g.rng.randi_range(1, TRIBE_TRAITOR_ODDS) == 1 and _tribe_send(id, traitor): return
	var rng: RandomNumberGenerator = g.rng
	for i in range(_near.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = _near[i]; _near[i] = _near[j]; _near[j] = tmp
	for p in _near:
		if p == 0 or g.allied(id, p): continue
		if g.kind_of(p) != SimRules.KIND_TRIBE and rng.randi_range(1, TRIBE_SKIP_PLAYER_ODDS) == 1: continue
		if p == g.PLAYER and g.elapsed < g.peace: continue
		if _tribe_send(id, p): return

func _holds_structures(p: int) -> bool:
	for k in TRIBE_STRUCT_KINDS:
		if g.owned_count(p, k) > 0: return true
	return false

# A land attack when it borders `p` (everything above reserveRatio x max, or expandRatio against a
# tribe holding structures), else a transport (_tribe_boat).
func _tribe_send(id: int, p: int) -> bool:
	if sc_count.get(p, 0) > 0:
		var s: Dictionary = st[id]
		var keep: float = s.expand_r if (g.kind_of(p) == SimRules.KIND_TRIBE and _holds_structures(p)) else s.reserve_r
		var troops := _troops(id) - _cap(id) * keep
		if troops < 1.0: return false
		return g.intent_attack(id, sc_tile[p], troops / maxf(_troops(id), 1.0))
	if p == g.PLAYER and g.elapsed < g.peace: return false
	return _tribe_boat(id, p)

func _tribe_send_tn(id: int) -> bool:
	var tile := sc_neutral_tile if sc_neutral_tile >= 0 else sc_fallout_tile
	if tile >= 0:
		var troops := _troops(id) - _cap(id) * float(st[id].expand_r)
		if troops < 1.0: return false
		return g.intent_attack(id, tile, troops / maxf(_troops(id), 1.0))
	return _tribe_boat_tn(id)

# A boat to free land seen by a shore probe: lands on the first land along the probe
func _tribe_boat_tn(id: int) -> bool:
	if g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return false
	var coasts := own_coast_tiles(id)
	if coasts.is_empty(): return false
	var every := maxi(1, int(floor(10.0 / R.k_lin + 0.5)))
	var dist := maxi(2, int(floor(5.0 / R.k_lin + 0.5)))
	var W: int = g.W; var H: int = g.H
	var om: PackedInt32Array = g.owner_map
	var fo: PackedByteArray = g.fallout
	var k := 0
	for c in coasts:
		k += 1
		if (k - 1) % every != 0: continue
		var x: int = c % W; var y: int = c / W
		for dd in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var x1: int = x + dd.x; var y1: int = y + dd.y
			if x1 < 0 or x1 >= W or y1 < 0 or y1 >= H or om[y1 * W + x1] != g.WATER: continue
			var nx: int = x + dd.x * dist; var ny: int = y + dd.y * dist
			if nx < 0 or nx >= W or ny < 0 or ny >= H: continue
			var n: int = ny * W + nx
			if om[n] != 0 or fo[n] == 1: continue
			var shore := -1
			for s in range(2, dist + 1):
				var t: int = (y + dd.y * s) * W + x + dd.x * s
				if om[t] != g.WATER: shore = t; break
			if shore < 0 or om[shore] != 0 or fo[shore] == 1: continue
			if _troops(id) / 5.0 < 1.0: return false
			if g.launch_boat(id, shore, SimRules.BOAT_ATTACK_FRACTION, 12000):
				stats.tribe_boats += 1
				return true
	return false

# Closest pair of tiles (both lists sorted by x, a sweep keeping the closest manhattan pair);
# returns the tile of `ys` of that pair
func _closest_two(xs: Array, ys: Array) -> int:
	if xs.is_empty() or ys.is_empty(): return -1
	var W: int = g.W
	var N: int = g.owner_map.size()
	var kx := []; var ky := []
	for a in xs: kx.append((a % W) * N + a)
	for b in ys: ky.append((b % W) * N + b)
	kx.sort(); ky.sort()
	var i := 0; var j := 0
	var nx := kx.size(); var ny := ky.size()
	var best := 1 << 30
	var result: int = ky[0] % N
	while i < nx and j < ny:
		var a: int = kx[i] % N; var b: int = ky[j] % N
		var ax := a % W; var bx := b % W
		var d := absi(ax - bx) + absi(a / W - b / W)
		if d < best: best = d; result = b
		if i != nx - 1 and (j == ny - 1 or ax < bx): i += 1
		else: j += 1
	return result

func _tribe_boat(id: int, p: int) -> bool:
	if g.sim_naval.boats_of(id) >= g.sim_naval.max_boats(id): return false
	var mine := own_coast_tiles(id)
	if mine.is_empty(): return false
	var theirs := own_coast_tiles(p, 8192)
	var dst := _closest_two(mine, theirs)
	if dst < 0: return false
	var ok: bool = g.launch_boat(id, dst, SimRules.BOAT_ATTACK_FRACTION, 12000)
	if ok: stats.tribe_boats += 1
	return ok

# Tribe structure deletion: one captured structure marked per TRIBE_DELETE_COOLDOWN, gone
# TRIBE_DELETE_DELAY ticks later unless captured first
func _tribe_delete_next(id: int) -> void:
	var s: Dictionary = st[id]
	var t: int = g.sim_atk.tick
	if t - int(s.last_delete) < TRIBE_DELETE_COOLDOWN or not _holds_structures(id): return
	var first = null
	for x in g.structs:
		if x.o == id and int(x.get("delete_at", 0)) == 0:
			first = x; break
	if first == null: return
	s.last_delete = t
	first["delete_at"] = t + TRIBE_DELETE_DELAY
	first["delete_by"] = id
	doomed.append(first)

func _delete_doomed() -> void:
	var keep := []
	var t: int = g.sim_atk.tick
	for x in doomed:
		if not g.struct_at.has(x.tile) or not is_same(g.struct_at[x.tile], x): continue
		if x.o != int(x.get("delete_by", -1)):
			x.delete_at = 0; continue  # captured meanwhile: the mark is cleared
		if t > int(x.delete_at):
			g._struct_remove(x)
			stats.deletes += 1
		else:
			keep.append(x)
	doomed = keep
