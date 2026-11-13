# Port of tests/simsys_nukes.luau (costs, radii, speeds, SAM, MIRV) plus intentional range/ICBM/blast scale.
extends RefCounted

const R := preload("res://sim/rules.gd")

func _read_main() -> String:
	return preload("res://tests/upstream/_harness.gd").game_src()

func _has(src: String, pat: String) -> bool:
	return src.find(pat) >= 0

func run(H) -> void:
	H.section("simsys_nukes / munitions constants", "simsys_nukes.luau")
	var r: SimRules = R.new(1.0)

	# costs
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_ATOM], 750000.0, "atom costs 750K")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_HYDROGEN], 5000000.0, "hydrogen costs 5M")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_MIRV], 25000000.0, "MIRV base cost 25M")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_MEGA], 2500000.0, "mega costs 2.5M")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_SCATTER], 3750000.0, "scatter costs 3.75M")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_SHELL], 0.0, "shell is free (battery is the price)")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_AIRSTRIKE], 0.0, "airstrike is free (airfield is the price)")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_SLUG], 0.0, "slug is free (railgun is the price)")
	H.expect_eq(SimRules.MIRV_COST_STEP, 15000000.0, "upstream MIRV_COST_STEP constant is 15M")

	# inner/outer full-size radii stored in Rules (source numbers)
	var atom: Vector2 = r.nuke_radii_full_scaled(SimRules.N_ATOM)
	H.expect(abs(atom.x - 12.0) < 1e-5 and abs(atom.y - 30.0) < 1e-5, "Rules atom radii 12 / 30 (full-size, k_lin=1)", "inner=%s outer=%s" % [str(atom.x), str(atom.y)])
	var hyd: Vector2 = r.nuke_radii_full_scaled(SimRules.N_HYDROGEN)
	H.expect(abs(hyd.x - 80.0) < 1e-5 and abs(hyd.y - 100.0) < 1e-5, "Rules hydrogen radii 80 / 100", "inner=%s outer=%s" % [str(hyd.x), str(hyd.y)])
	var wh: Vector2 = r.nuke_radii_full_scaled(SimRules.N_WARHEAD)
	H.expect(abs(wh.x - 12.0) < 1e-5 and abs(wh.y - 18.0) < 1e-5, "Rules warhead radii 12 / 18", "inner=%s outer=%s" % [str(wh.x), str(wh.y)])
	var mega: Vector2 = r.nuke_radii_full_scaled(SimRules.N_MEGA)
	H.expect(abs(mega.x - 24.0) < 1e-5 and abs(mega.y - 60.0) < 1e-5, "Rules mega = 2× atom inner / outer (24 / 60)", "inner=%s outer=%s" % [str(mega.x), str(mega.y)])
	var sc: Vector2 = r.nuke_radii_full_scaled(SimRules.N_SCATTER)
	H.expect(abs(sc.x - 12.0) < 1e-5 and abs(sc.y - 30.0) < 1e-5, "Rules scatter crater = atom (12 / 30)", "inner=%s outer=%s" % [str(sc.x), str(sc.y)])

	# speeds (source table)
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_ATOM], 10.0, "atom speed 10 full-size tiles/tick")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_HYDROGEN], 10.0, "hydrogen speed 10")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_MIRV], 15.0, "MIRV bus speed 15")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_WARHEAD], 22.0, "warhead speed 22")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_MEGA], 10.0, "mega speed 10")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_SCATTER], 10.0, "scatter speed 10")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_SHELL], 6.0, "shell speed 6")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_AIRSTRIKE], 8.0, "airstrike speed 8")
	H.expect_eq(SimRules.NUKE_SPEED_FULL[SimRules.N_SLUG], 80.0, "slug speed 80")

	H.expect_eq(SimRules.NUKE_INTERCEPT_P[SimRules.N_MIRV], 0.0, "MIRV bus intercept probability 0 (can't be intercepted)")
	H.expect_eq(SimRules.NUKE_INTERCEPT_P[SimRules.N_ATOM], 1.0, "atom can be intercepted")
	H.expect_eq(SimRules.NUKE_INTERCEPT_P[SimRules.N_SHELL], 0.0, "shells are not SAM-able")
	H.expect_eq(SimRules.NUKE_INTERCEPT_P[SimRules.N_AIRSTRIKE], 0.0, "air strikes are not SAM-able")
	H.expect_eq(SimRules.MIRV_WARHEADS, 350, "MIRV_WARHEADS 350 (upstream cap)")
	H.expect_eq(SimRules.SILO_COOLDOWN_TICKS, 90, "silo cooldown 9 s (90 ticks)")
	H.expect_eq(SimRules.SAM_COOLDOWN_TICKS, 90, "SAM cooldown 9 s")
	H.expect_eq(SimRules.SAM_MISSILE_SPEED_FULL, 12.0, "SAM missile 12 full-size tiles/tick")
	H.expect_eq(r.sam_ticks_to(12.0), 1, "SAM manhattan time: 12 tiles / 12 per tick = 1")
	H.expect_eq(SimRules.NUKE_GRUDGE_TICKS, 3000, "nuke grudge 3000 ticks")
	H.expect_eq(SimRules.SCATTER_MIN, 4, "scatter 4–6 warheads (min)")
	H.expect_eq(SimRules.SCATTER_MAX, 6, "scatter 4–6 warheads (max)")
	H.expect_near(r.scatter_near(), 28.0, 1e-9, "scatter near 28 full-size tiles")
	H.expect_near(r.scatter_far(), 46.0, 1e-9, "scatter far 46 full-size tiles")

	# warhead death factor
	H.expect_near(SimRules.warhead_death(0.0, 10000.0), 0.0, 1e-9, "warhead_death: no loss at 0 troops")
	# below 3% of max: excess 0
	H.expect_near(SimRules.warhead_death(200.0, 10000.0), 0.0, 1e-9, "warhead_death: no loss below 3% of cap")
	var excess = 10000.0 - 0.03 * 10000.0
	var want_full = 500.0 * (1.0 - exp(-2.0 * excess / 10000.0))
	H.expect_near(SimRules.warhead_death(10000.0, 10000.0), want_full, 1e-6, "warhead_death at cap = 500*(1-e^(-2*0.97))")

	# --- intentional deviations, verified in main.gd source (cannot instance the game in this suite) ---
	H.section("intentional nuke deviations (main.gd)", "simsys_nukes.luau")
	var src = _read_main()
	H.expect(src != "", "main.gd readable", "")
	H.expect(_has(src, "0.5265") and _has(src, "0.5558") and _has(src, "0.585") and _has(src, "0.6435") and _has(src, "1.3"),
		"NUKE_RANGE_FRAC Atom .5265, Mega .5558, H .585, Scatter .6435, MIRV 1.3", "intentional range system")
	H.intentional("upstream bombs have no range limit (launch_range 0)", "port ranges are fractions of map land width; not a bug")
	H.expect(_has(src, "ICBM_FEE_PCT := 0.10") or _has(src, "ICBM_FEE_PCT := 0.1"), "ICBM +10% cost", "intentional")
	H.expect(_has(src, "icbm_mode"), "ICBM toggle present", "intentional")
	H.expect(_has(src, "BLAST_S := float(W) / 640.0"), "BLAST_S = W/640 (= 2.8 on 1792-wide maps)", "intentional ×2.8")

	var blast_s = 1792.0 / 640.0
	H.expect_near(blast_s, 2.8, 1e-9, "1792/640 = 2.8 scale")
	H.expect_near(7.0 * blast_s, 19.6, 1e-9, "Atom blast 7*2.8 = 19.6 tiles")
	H.expect_near(25.0 * blast_s, 70.0, 1e-9, "H blast 25*2.8 = 70 tiles")
	H.expect_near(3.0 * blast_s, 8.4, 1e-9, "MIRV warhead blast 3*2.8 = 8.4 tiles")
	H.expect_near(15.0 * blast_s, 42.0, 1e-9, "Mega blast 15*2.8 = 42 tiles")
	H.expect_near(7.0 * blast_s, 19.6, 1e-9, "Scatter blast 7*2.8 = 19.6 tiles")
	H.expect(_has(src, "7.0 * BLAST_S") and _has(src, "25.0 * BLAST_S") and _has(src, "3.0 * BLAST_S") and _has(src, "15.0 * BLAST_S"),
		"NUKE_R uses 7/25/3/15/7 * BLAST_S", "intentional radii")

	H.expect(_has(src, "UPSTREAM_NUKE_TILES_PER_S := 100.0"),
		"nukes fly at upstream speed (10 full-size tiles per tick)", "matches Rules.NUKE_SPEED_FULL atom")
	H.expect(_has(src, "mirv_bus") or _has(src, "split_done") or _has(src, "branched"),
		"MIRV bus flies to the aim, then branches", "intentional pattern")
	H.expect(_has(src, "ONLY creates fallout in the circular crater") or _has(src, "fallout in the circular") or _has(src, "real warhead"),
		"MIRV fallout only inside real warhead blast circles", "intentional")

	H.expect_eq(SimRules.nuke_cost_named("mirv", 0), 25000000.0, "first MIRV is 25M")
	H.expect_eq(SimRules.nuke_cost_named("mirv", 1), 40000000.0, "second MIRV is 40M (+15M step)")
	H.expect(src.find("MIRV_COST_STEP") >= 0 and src.find("mirvs_launched") >= 0, "main.nuke_cost applies MIRV_COST_STEP * mirvs_launched", "")
	H.intentional("fallout decays after 60 s (fallout_t stamped at 60, cleared at 0)", "upstream fallout lasts until recapture")
	H.intentional("nuke flight uses a custom missile clock (DT_TICK per sim tick) and ballistic arcs, not Rules.nuke_arc", "intentional")

