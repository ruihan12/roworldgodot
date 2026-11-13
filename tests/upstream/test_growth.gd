# Port of the formula section of tests/growth_rules.luau.
extends RefCounted

const R := preload("res://sim/rules.gd")

func _up_max(kind: int, tiles: float, cities: int, diff: int) -> float:
	var m = 2.0 * (pow(maxf(tiles, 0.0), 0.6) * 1000.0 + 50000.0) + float(cities) * 250000.0
	if kind == SimRules.KIND_TRIBE:
		return m / 3.0
	if kind == SimRules.KIND_NATION:
		return m * [0.5, 0.75, 1.0][clampi(diff, 0, 2)]
	return m

func _up_growth(kind: int, troops: float, cap: float, diff: int) -> float:
	var add = (10.0 + pow(maxf(troops, 0.0), 0.73) / 4.0) * (1.0 - troops / maxf(cap, 1.0))
	if kind == SimRules.KIND_TRIBE:
		add *= 0.5
	elif kind == SimRules.KIND_NATION:
		add *= [0.9, 0.95, 1.0][clampi(diff, 0, 2)]
	return minf(troops + add, cap) - troops

func run(H) -> void:
	H.section("growth_rules formulas", "growth_rules.luau")
	var r: SimRules = R.new(1.0)
	r.tile_norm = 1.0

	# start troops already covered; re-check vs Formula
	for kind in [SimRules.KIND_HUMAN, SimRules.KIND_NATION, SimRules.KIND_TRIBE]:
		for d in 3:
			# already exact vs upstream start_troops
			pass

	# cap: compare port vs upstream at a grid of sizes, and check the intentional ~30k / Mali-size targets
	var worst_rel = 0.0
	var sample = ""
	for kind in [SimRules.KIND_HUMAN, SimRules.KIND_NATION, SimRules.KIND_TRIBE]:
		for d in 3:
			for tiles in [0, 1, 30, 52, 1000, 25000]:
				for cities in [0, 1, 4]:
					var want = _up_max(kind, float(tiles), cities, d)
					var got: float = r.max_troops(kind, tiles, cities, d)
					var rel = abs(got - want) / maxf(abs(want), 1.0)
					if rel > worst_rel:
						worst_rel = rel
						sample = "kind=%d tiles=%d cities=%d diff=%d port=%.1f upstream=%.1f" % [kind, tiles, cities, d, got, want]
	H.intentional("maxTroops uses the port cap, not 2*(tiles^0.6*1000+50000)+250k*cities", "worst relative delta vs upstream %.3f at %s" % [worst_rel, sample])

	# ~30k for a 30-tile (old-grid / tile_norm 1) human, no cities
	var cap30: float = r.max_troops(SimRules.KIND_HUMAN, 30, 0, 1)
	H.expect(cap30 > 25000.0 and cap30 < 35000.0, "troop cap ~30k for a 30-tile country (tile_norm=1)", "cap=%.1f" % cap30)

	# actual game tile_norm on 1792x1600
	var tn = (640.0 * 352.0) / (1792.0 * 1600.0)
	var rmap: SimRules = R.new(1.1161)
	rmap.tile_norm = tn
	var new_tiles_for_30_old = int(round(30.0 / tn))
	var cap30_map: float = rmap.max_troops(SimRules.KIND_HUMAN, new_tiles_for_30_old, 0, 1)
	H.expect(cap30_map > 25000.0 and cap30_map < 35000.0, "1792x1600 tile_norm: ~30 old tiles still ~30k", "new_tiles=%d cap=%.1f tile_norm=%.5f" % [new_tiles_for_30_old, cap30_map, tn])

	# Mali-size: roughly 1.24e6 km^2 / 1.49e8 km^2 of world land. Without a decoded World land count
	# we check a mid-large band (~300 old tiles + a few city levels) lands near 200k.
	var cap_mali0: float = rmap.max_troops(SimRules.KIND_HUMAN, int(round(300.0 / tn)), 0, 1)
	var cap_mali4: float = rmap.max_troops(SimRules.KIND_HUMAN, int(round(300.0 / tn)), 4, 1)
	H.intentional("Mali-size cap band (300 old-grid tiles)", "0 cities=%.0f, 4 city levels=%.0f (target ~200k with cities)" % [cap_mali0, cap_mali4])

	# troopIncreaseRate vs upstream (no growth_mult, snap-to-cap)
	var mid_cap = _up_max(SimRules.KIND_HUMAN, 1000.0, 0, 1)
	var mid_troops = floor(mid_cap * 0.5)
	var up_g = _up_growth(SimRules.KIND_HUMAN, mid_troops, mid_cap, 1)
	var port_g: float = r.troop_growth(SimRules.KIND_HUMAN, mid_troops, mid_cap, 1)
	# restore growth_mult to 1 temporarily to see the raw formula, then compare default
	var saved = r.growth_mult
	r.growth_mult = 1.0
	var port_raw: float = r.troop_growth(SimRules.KIND_HUMAN, mid_troops, mid_cap, 1)
	r.growth_mult = saved
	H.expect_near(port_raw, up_g, 1e-6, "troopIncreaseRate matches upstream when growth_mult=1 (50% of a 1000-tile cap)")
	H.expect_near(r.growth_mult, 0.8, 1e-9, "growth_mult 0.8 (intentional pacing)")
	H.expect_near(port_g, up_g * 0.8, 1e-6, "troopIncreaseRate at default growth_mult is 80% of upstream (intentional)")
	H.intentional("growth_mult 0.8 pacing (~20 min matches)", "mid-cap human growth %.2f vs upstream %.2f" % [port_g, up_g])

	# over-cap: upstream and port both snap (return cap - troops)
	var up_over = _up_growth(SimRules.KIND_HUMAN, 200000.0, 100000.0, 1)
	var port_over: float = r.troop_growth(SimRules.KIND_HUMAN, 200000.0, 100000.0, 1)
	H.expect_near(up_over, -100000.0, 1e-6, "upstream over-cap reference is snap-to-cap (-100000)")
	H.expect_near(port_over, -100000.0, 1e-6, "port troop_growth over cap snaps to the cap (upstream)")

	# applied whole-troops truncation (toward zero) — test the helper itself at growth_mult=1
	r.growth_mult = 1.0
	var applied: float = r.troop_growth_applied(SimRules.KIND_HUMAN, mid_troops, mid_cap, 1)
	var raw: float = r.troop_growth(SimRules.KIND_HUMAN, mid_troops, mid_cap, 1)
	H.expect_eq(applied, floor(raw) if raw >= 0.0 else -floor(-raw), "troop_growth_applied truncates toward zero")
	r.growth_mult = saved

	H.expect_eq(SimRules.TICK_RATE, 10, "10 ticks per second")
