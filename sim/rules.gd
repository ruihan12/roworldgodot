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
const DEFENSE_POST_SHOOTS := false        # Rules.luau 727 (match option; sim_ws.defense_posts_shoot)
const DEFENSE_POST_SHELL_TICKS := 100
const DEFENSE_POST_TARGET_FULL := 75.0
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
# snaps to the cap (upstream). OVERCAP_DECAY is unused (kept for reference).
func troop_growth(kind: int, troops: float, cap: float, diff: int) -> float:
	if troops > cap:
		return cap - troops  # upstream troopIncreaseRate: min(troops + add, max) snaps an over-cap army to the cap
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

# user tuning on top of the upstream numbers: SAM radius x0.8, SAM reload x0.6 (reload_ticks in sim/arsenal.gd)
const SAM_RADIUS_MULT := 0.8
const SAM_RELOAD_MULT := 0.6

func sam_range(level: int) -> float:
	return (150.0 - 480.0 / (maxi(level, 1) + 5)) * SAM_RADIUS_MULT / k_lin

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

# ---- Phase 1 (port1): upstream Rules.luau arsenal / nukes / warships / trains / diplomacy ----
# Every number below is copied from src/shared/Core/Rules.luau (ae7a350). Full-size distances are
# divided by k_lin where used; tile counts multiplied by k_area; times are sim ticks (10/s).
# Nuke kinds (Defs.N_*): 0 atom, 1 hydrogen, 2 MIRV, 3 warhead, 4 mega, 5 scatter, 6 shell, 7 airstrike, 8 slug.
const N_ATOM := 0
const N_HYDROGEN := 1
const N_MIRV := 2
const N_WARHEAD := 3
const N_MEGA := 4
const N_SCATTER := 5
const N_SHELL := 6
const N_AIRSTRIKE := 7
const N_SLUG := 8
# our build ids -> Defs.N_*
const NUKE_KIND_OF := {7: N_ATOM, 8: N_HYDROGEN, 9: N_MIRV, 11: N_MEGA, 12: N_SCATTER}
const NUKE_COST := [750000.0, 5000000.0, 25000000.0, 0.0, 2500000.0, 3750000.0, 0.0, 0.0, 0.0]
const MIRV_COST_STEP := 15000000.0  # applied: main.nuke_cost adds it per MIRV launched this match
const NUKE_INNER_FULL := [12.0, 80.0, 0.0, 12.0, 24.0, 12.0, 0.0, 0.0, 0.0]
const NUKE_OUTER_FULL := [30.0, 100.0, 0.0, 18.0, 60.0, 30.0, 1.5, 15.0, 5.0]
const NUKE_INTERCEPT_P := [1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
const NUKE_SPEED_FULL := [10.0, 10.0, 15.0, 22.0, 10.0, 10.0, 6.0, 8.0, 80.0]
const NUKE_FLAT := [false, false, false, false, false, false, true, true, true]
const MIRV_WARHEADS := 350
const NUKE_ALLIANCE_BREAK_FULL := 100.0
const NUKE_GRUDGE_TICKS := 3000
const SAM_COOLDOWN_TICKS := 90
const SILO_COOLDOWN_TICKS := 90
const SAM_UPGRADE_TICKS := 45
const SAM_MAX_RANGE_FULL := 150.0
const SAM_MISSILE_SPEED_FULL := 12.0
const NUKE_TARGETABLE_FULL := 150.0
const SAM_CAND_REFRESH_TICKS := 30
# Defs.S_* order: city, port, factory, defense, sam, silo, artillery, airfield, railgun
const BUILD_TICKS := [20, 50, 20, 50, 300, 100, 80, 100, 150]
const STRUCT_HP := [1000, 1000, 1000, 600, 1000, 1000, 600, 800, 1000]
const RELOAD_TICKS := [0, 0, 0, 0, 90, 90, 0, 300, 250]
# our build ids -> Defs.S_*
const S_OF := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 6, 14: 7, 15: 8}
const RAPID_RELOAD_MULT := 0.5
const ARTILLERY_RANGE_FULL := 45.0
const ARTILLERY_GAP_MIN := 40
const ARTILLERY_GAP_MAX := 70
const ARTILLERY_IDLE_TICKS := 20
const ARTILLERY_SAMPLES := 24
const SHELL_KILL_FRAC := 0.0288
const SHELL_KILL_MIN := 1440.0
const SHELL_KILL_MAX := 19200.0
const AIRFIELD_RANGE_FULL := 156.0
const AIRSTRIKE_KILL_PER_TILE := 60.0
const AIRSTRIKE_KILL_FRAC := 0.06
const SLUG_KILL_PER_TILE := 150.0
const SLUG_KILL_FRAC := 0.04
const STRIKE_DAMAGE := [0, 0, 0, 0, 0, 0, 150, 600, 1000]
const SCATTER_MIN := 4
const SCATTER_MAX := 6
const SCATTER_NEAR_FULL := 28.0
const SCATTER_FAR_FULL := 46.0
const REINFORCE_COST := 100000.0
const REINFORCE_FRACTION := 0.20
const REINFORCE_COOLDOWN_TICKS := 300
# warships
const WARSHIP_HP := 1000
const WARSHIP_MAX_VET := 3
const WARSHIP_VET_TRANSPORTS := 10
const WARSHIP_VET_TRADES := 25
const WARSHIP_FIRE_TICKS := 20
const WARSHIP_RANGE_FULL := 130.0
const WARSHIP_PATROL_FULL := 100.0
const WARSHIP_DOCK_FULL := 5.0
const WARSHIP_PASSIVE_HEAL := 1
const WARSHIP_PASSIVE_HEAL_FULL := 150.0
const WARSHIP_PORT_HEAL_PER_LEVEL := 5
const WARSHIP_RETREAT_PCT := 75
const WARSHIP_MANUAL_NO_RETREAT_TICKS := 50
const SHELL_SPEED_FULL := 3.0
const SAFE_FROM_PIRATES_TICKS := 20
const SCAN_TICKS := 5
# trains
const TRUCKS_PER_FACTORY := 6
const TRAIN_UNITS := 6
const TRAIN_COOLDOWN_TICKS := 10
const TRAIN_SPEED_FULL := 2.0
# diplomacy
const ALLY_REQUEST_TICKS := 200
const ALLY_REQUEST_COOLDOWN_TICKS := 300
const ALLIANCE_TICKS := 3000
const ALLIANCE_EXTEND_WINDOW_TICKS := 300
const TRAITOR_TICKS := 300
const AI_MAX_ALLIES := 3

func nuke_radii_full_scaled(kind: int) -> Vector2:
	return Vector2(NUKE_INNER_FULL[kind], NUKE_OUTER_FULL[kind]) / k_lin

# share of a blast radius that is the inner (always-fallout) disc: inner / outer of the source
static func inner_frac(kind: int) -> float:
	var o: float = NUKE_OUTER_FULL[kind]
	return NUKE_INNER_FULL[kind] / o if o > 0.0 else 0.0

func sam_range_at(level: int, ticks_since_upgrade: int) -> float:
	var r := sam_range(level)
	if level <= 1 or ticks_since_upgrade >= SAM_UPGRADE_TICKS: return r
	var r0 := sam_range(level - 1)
	return r0 + (r - r0) * maxf(ticks_since_upgrade, 0) / float(SAM_UPGRADE_TICKS)

func sam_ticks_to(manhattan_tiles: float) -> int:
	return int(ceil(manhattan_tiles * k_lin / SAM_MISSILE_SPEED_FULL))

func munition_flight_ticks(dist_tiles: float, kind: int) -> int:
	return maxi(1, int(ceil(dist_tiles * k_lin / NUKE_SPEED_FULL[clampi(kind, 0, 8)])))

func artillery_range() -> float: return ARTILLERY_RANGE_FULL / k_lin
func airfield_range() -> float: return AIRFIELD_RANGE_FULL / k_lin
func strike_radius(kind: int) -> float: return NUKE_OUTER_FULL[kind] / k_lin
func scatter_near() -> float: return SCATTER_NEAR_FULL / k_lin
func scatter_far() -> float: return SCATTER_FAR_FULL / k_lin

# Rules.strike_kill: troops a shell / air strike / slug kills of an army with src_full_tiles under it
static func strike_kill(kind: int, troops: float, src_full_tiles: float) -> float:
	var t := maxf(troops, 0.0)
	if kind == N_SHELL: return minf(t, clampf(floor(t * SHELL_KILL_FRAC), SHELL_KILL_MIN, SHELL_KILL_MAX))
	if kind == N_AIRSTRIKE: return floor(minf(t, minf(src_full_tiles * AIRSTRIKE_KILL_PER_TILE, t * AIRSTRIKE_KILL_FRAC)))
	if kind == N_SLUG: return floor(minf(t, minf(src_full_tiles * SLUG_KILL_PER_TILE, t * SLUG_KILL_FRAC)))
	return 0.0

static func reinforce_troops(troops: float, cap: float) -> float:
	return maxf(0.0, minf(floor(cap * REINFORCE_FRACTION), floor(cap) - floor(troops)))

# nukeDeathFactor for a warhead, per full-size tile: 500 * (1 - e^(-2 * excess / max))
static func warhead_death(troops: float, max_troops: float) -> float:
	var m := maxf(max_troops, 1.0)
	var excess := maxf(0.0, troops - 0.03 * m)
	return 500.0 * (1.0 - exp(-2.0 * excess / m))

static func warship_max_hp(vet: int) -> int:
	return WARSHIP_HP * (100 + clampi(vet, 0, 3) * 20) / 100

static func shell_damage(roll: int, vet: int) -> int:
	var mult := (clampi(roll, 1, 5) - 1) * 25 + 200
	if vet > 0: mult = mult * (100 + vet * 20) / 100
	return int(round(250.0 / 250.0 * mult))

func shell_flight_ticks(dist_tiles: float) -> int:
	return maxi(1, int(ceil(dist_tiles * k_lin / SHELL_SPEED_FULL)))

func warship_range() -> float: return WARSHIP_RANGE_FULL / k_lin
func warship_patrol() -> float: return WARSHIP_PATROL_FULL / k_lin
func warship_tiles_per_tick(hunting: bool) -> float: return (2.0 if hunting else 1.0) / k_lin

static func train_saturation(units: float) -> float:
	var boost := 1.0 + 0.5 * exp(-units / 30.0)
	var damping := 1.0 - sigmoid(units, log(2.0) / 100.0, 560.0)
	var plateau := 0.25 * (1.0 - sigmoid(units, log(2.0) / 150.0, 900.0))
	return boost * maxf(damping, plateau)

static func train_spawn_rate(owner_factories: int, train_units: int) -> int:
	var rate := (owner_factories + 10) * 15.0
	return maxi(1, int(floor(rate / train_saturation(train_units))))

func train_tiles_per_tick() -> float: return TRAIN_SPEED_FULL / k_lin

# Rules.DEFAULT_ATTACK_RATIO (Rules.luau 641): the sim fallback when an order carries no ratio. The HUD
# stops are UICtx.RATIO_STOPS 10/25/35/50/75% with UICtx.DEFAULT_RATIO 25% (main.gd SHARES, share_i 1).
const DEFAULT_ATTACK_RATIO := 0.2

# Defs.NUKE_NAMES / Rules.nuke_cost (Rules.luau 836) / Rules.launch_range (985)
const NUKE_NAMES := ["atom", "hydrogen", "mirv", "warhead", "mega", "scatter", "shell", "airstrike", "slug"]
static func nuke_kind_from_name(kind_name: String) -> int:
	return NUKE_NAMES.find(kind_name)

static func nuke_cost_named(kind_name: String, mirvs_launched := 0) -> float:
	var k := nuke_kind_from_name(kind_name)
	if k < 0 or k == N_WARHEAD or k == N_SHELL: return -1.0
	if k == N_MIRV: return NUKE_COST[k] + MIRV_COST_STEP * maxi(mirvs_launched, 0)
	return NUKE_COST[k]

func launch_range(kind: int) -> float:
	if kind == N_AIRSTRIKE: return 156.0 / k_lin
	if kind == N_SHELL: return 45.0 / k_lin
	return 0.0
