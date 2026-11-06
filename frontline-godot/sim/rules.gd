# Port of RoWorld src/shared/Core/Rules.luau (AGPL-3.0, lukechatton/roworld).
# All constants are in "full-size tiles" like the source; k_lin = full-size tiles per one of our tiles.
# Our MIRV is NOT taken from here (the user keeps the original un-nerfed MIRV in main.gd).
extends RefCounted
class_name SimRules

const TICK_RATE := 10
const KIND_HUMAN := 0
const KIND_NATION := 1
const KIND_TRIBE := 2

# our terrain code (mtn[]: 0 plains, 1 highland, 2 mountain) -> source index (2,3,4)
const ATTACK_MAG := [80.0, 100.0, 120.0]
const ATTACK_TILE_COST := [16.5, 20.0, 25.0]
const PRIORITY_MAG := [1.0, 1.5, 2.0]

const START_TROOPS_HUMAN := 25000.0
const START_TROOPS_TRIBE := 10000.0
const NATION_START_TROOPS := [12500.0, 18750.0, 25000.0]
const NATION_TROOP_MULT := [0.5, 0.75, 1.0]
const NATION_GROWTH_MULT := [0.9, 0.95, 1.0]
const CITY_TROOPS := 250000.0
const DEFAULT_TRIBES := 400
const SOLO_COUNTDOWN_TICKS := 50

const GOLD_PER_TICK := 100.0
const TRIBE_GOLD_PER_TICK := 50.0

const LARGE_ATTACKER_DEPTH := 0.7
const LARGE_DEFENDER_DEPTH := 0.3
const LARGE_ATTACKER_SPEED_DEPTH := 0.73
const BOT_DEFENDER_LOSS_MULT := 0.7
const TERRA_NULLIUS_COST_SCALE := 2000.0
const TERRA_NULLIUS_MIN_COST := 5.0
const TERRA_NULLIUS_MAX_COST := 100.0
const ATTACKER_LOSS_BASE := 0.463
const ATTACKER_LOSS_PER_DENSITY := 0.0039
const SPEED_COST_DIVISOR := 8.55
const BORDER_JITTER := 5
const PRIORITY_BASE := 10
const PRIORITY_RAND := 7
const RETREAT_KEEP := 0.75
const RETREAT_DELAY_TICKS := 20
const ANNEX_BELOW_FULL_TILES := 100.0
const ATTACK_UPDATE_TICKS := 10
const DEFENSE_POST_MAG := 5.0
const DEFENSE_POST_COST := 3.0
const TRAITOR_DEFENSE_DEBUFF := 0.5
const TRAITOR_SPEED_DEBUFF := 0.8
const HOSTILE_TICKS := 600
const WIN_SHARE := 0.8
const MAX_BOATS_PER_OWNER := 3
const MAX_BOATS_PLAYER := 10
const BOAT_ATTACK_FRACTION := 0.2
const HUMAN_GRACE_TICKS := [3000, 1800, 1200]
const HUMAN_GRACE_JITTER := 900
const MAX_AI_WARS_ON_HUMAN := [1, 2, 3]
const CAPITULATE_AGE := 12000
const CAPITULATE_SHARE := 0.02
const CAPITULATE_RATIO := 8.0
const CAPITULATE_GAP := 300

var k_lin := 1.0
var k_area := 1.0
var legacy_lin := 1.0
var spawn_radius := 4.0
var tribe_spawn_min_dist := 30.0
var nation_spawn_delta := 25.0
var max_tiles_per_tick := 572
var defense_range := 30.0
var struct_min_dist := 15.0
var priority_f4 := PackedInt32Array()
var log_mid := log(300000.0)

func _init(kl := 1.0) -> void:
	set_k(kl)

func set_k(kl: float) -> void:
	k_lin = kl
	k_area = kl * kl
	legacy_lin = (2000.0 / 1024.0) / kl
	spawn_radius = 4.0 / kl
	tribe_spawn_min_dist = 30.0 / kl
	nation_spawn_delta = 25.0 / kl
	max_tiles_per_tick = maxi(1, int(floor(572.0 / k_area)))
	defense_range = 30.0 / kl
	struct_min_dist = 15.0 / kl
	priority_f4.resize(15)
	for tt in 3:
		for n in 5:
			priority_f4[tt * 5 + n] = 4 - 2 * n + int(floor(2.0 * PRIORITY_MAG[tt] + 0.5))

static func sigmoid(v: float, decay: float, mid: float) -> float:
	return 1.0 / (1.0 + exp(-decay * (v - mid)))

func start_troops(kind: int, diff: int) -> float:
	if kind == KIND_TRIBE: return START_TROOPS_TRIBE
	if kind == KIND_NATION: return NATION_START_TROOPS[clampi(diff, 0, 2)]
	return START_TROOPS_HUMAN

# Land army cap (user nerf, replaces the source's 2 * (fullTiles^0.6 * 1000 + 50000)):
# cap = CAP_BASE + CAP_K * ourTiles^CAP_EXP + CITY_TROOPS per city level. ~30 tiles -> ~28k.
const CAP_BASE := 5000.0
const CAP_K := 6200.0
const CAP_EXP := 0.41
# Resolution-independent tile count: tiles are normalised to the old 640x352 grid (main sets this).
var tile_norm := 1.0
const CITY_TROOPS_NERF := 25000.0
const OVERCAP_DECAY := 0.02  # share of the excess lost per tick when above the cap
# Pacing levers (user: ~20 min matches at 1x). 1.0 = source speed.
var growth_mult := 0.8
var attack_speed_mult := 1.0   # >1 = faster conquest (divides tile time cost)
var gold_mult := 0.85
var ai_rate_mult := 1.15        # >1 = AI waits longer between attack decisions

func max_troops(kind: int, tiles: int, cities: int, diff: int) -> float:
	var m := CAP_BASE + CAP_K * pow(maxf(float(tiles) * tile_norm, 0.0), CAP_EXP) + cities * CITY_TROOPS_NERF
	if kind == KIND_TRIBE: return m / 3.0
	if kind == KIND_NATION: return m * NATION_TROOP_MULT[clampi(diff, 0, 2)]
	return m

# troopIncreaseRate per tick: (10 + troops^0.73 / 4) * (1 - troops/max); above the cap the army
# decays smoothly (OVERCAP_DECAY of the excess per tick) instead of snapping down.
func troop_growth(kind: int, troops: float, cap: float, diff: int) -> float:
	if troops > cap:
		return -maxf(1.0, (troops - cap) * OVERCAP_DECAY)
	var add := (10.0 + pow(maxf(troops, 0.0), 0.73) / 4.0) * (1.0 - troops / maxf(cap, 1.0)) * growth_mult
	if kind == KIND_TRIBE: add *= 0.5
	elif kind == KIND_NATION: add *= NATION_GROWTH_MULT[clampi(diff, 0, 2)]
	return minf(troops + add, cap) - troops

func troop_growth_applied(kind: int, troops: float, cap: float, diff: int) -> float:
	var g := troop_growth(kind, troops, cap, diff)
	return floor(g) if g >= 0.0 else -floor(-g)

func gold_per_tick(kind: int) -> float:
	return (TRIBE_GOLD_PER_TICK if kind == KIND_TRIBE else GOLD_PER_TICK) * gold_mult

func conquer_gold(victim_kind: int, victim_gold: float) -> float:
	return victim_gold * (0.5 if victim_kind == KIND_HUMAN else 1.0)

func large_territory_bonus(src_full_tiles: float, depth: float) -> float:
	return 1.0 - depth * sigmoid(log(maxf(src_full_tiles, 1.0)), 2.5, log_mid)

static func fallout_modifier(ratio: float) -> float:
	return 5.0 - clampf(ratio, 0.0, 1.0) * 2.0

static func neutral_loss_per_mag(kind: int) -> float:
	return 1.0 / (10.0 if kind == KIND_TRIBE else 5.0)

# Structure prices (Rules.build_cost). Nukes are priced elsewhere (MIRV kept original).
static func build_cost(kind_name: String, n: int) -> float:
	n = maxi(n, 0)
	match kind_name:
		"city", "port", "factory": return minf(1000000.0, 125000.0 * pow(2.0, mini(n, 4)))
		"defense": return minf(250000.0, 50000.0 * (n + 1))
		"sam": return minf(3000000.0, 1500000.0 * (n + 1))
		"silo": return 1000000.0
		"warship": return minf(1000000.0, 250000.0 * (n + 1))
		"artillery": return minf(750000.0, 150000.0 * (n + 1))
		"airfield": return minf(1500000.0, 500000.0 * (n + 1))
		"railgun": return minf(7500000.0, 2500000.0 * (n + 1))
	return -1.0

func sam_range(level: int) -> float:
	return (150.0 - 480.0 / (maxi(level, 1) + 5)) / k_lin

# tradeShipGold(dist): dist = full-size tiles sailed
func trade_gold(path_tiles: float) -> float:
	var d := path_tiles * k_lin
	return 75000.0 / (1.0 + exp(-0.03 * (d - 300.0))) + 50.0 * d

static func train_gold(rel: String, stops: int) -> float:
	var base := 25000.0
	if rel == "self": base = 10000.0
	elif rel == "ally": base = 35000.0
	return maxf(5000.0, base - 5000.0 * maxi(0, stops - 9))

func human_grace_ticks(diff: int) -> int:
	return HUMAN_GRACE_TICKS[clampi(diff, 0, 2)]

# ---- Stage 2: naval + placement ----
const UPGRADABLE_K := [0, 1, 2, 4, 5]  # city, port, factory, SAM, silo (our build ids)
const TRADE_SHORT_RANGE_FULL := 300.0
const BOAT_SEARCHES_PER_S := 2

func place_search_r() -> float: return 15.0 / k_lin
func port_spawn_manhattan() -> float: return 20.0 / k_lin
# transports / trade ships: 1 full-size tile per tick -> our tiles per sim second
func ship_tiles_per_s() -> float: return 10.0 / k_lin
func alt_landing_r() -> int: return maxi(3, ceili(6.0 / k_lin))

func trade_saturation(ships: int) -> float:
	var boost := 1.0 + 0.45 * exp(-ships / 120.0)
	var damping := 1.0 - sigmoid(ships, log(2.0) / 50.0, 330.0)
	var plateau := 0.25 * (1.0 - sigmoid(ships, log(2.0) / 100.0, 800.0))
	return boost * maxf(damping, plateau)

func trade_spawn_rate(rejections: int, ships: int) -> int:
	return maxi(1, int(floor(100.0 / (rejections + 1) / trade_saturation(ships))))
