# Port of gameplay-relevant cases from tests/sim_core_basics.luau (formulas and constants).
extends RefCounted

const R := preload("res://sim/rules.gd")

func run(H) -> void:
	H.section("sim_core_basics / Rules", "sim_core_basics.luau")
	var r: SimRules = R.new(1.0)

	H.expect_eq(SimRules.TICK_RATE, 10, "10 ticks per second (100 ms a tick)")
	H.expect_eq(SimRules.KIND_HUMAN, 0, "KIND_HUMAN")
	H.expect_eq(SimRules.KIND_NATION, 1, "KIND_NATION")
	H.expect_eq(SimRules.KIND_TRIBE, 2, "KIND_TRIBE")

	# start manpower (matches Formula.startManpower / Rules.start_troops, difficulties 0..2)
	H.expect_eq(r.start_troops(SimRules.KIND_HUMAN, 1), 25000.0, "startManpower Human")
	H.expect_eq(r.start_troops(SimRules.KIND_TRIBE, 1), 10000.0, "startManpower Tribe")
	H.expect_eq(r.start_troops(SimRules.KIND_NATION, 0), 12500.0, "startManpower Nation Easy")
	H.expect_eq(r.start_troops(SimRules.KIND_NATION, 1), 18750.0, "startManpower Nation Medium")
	H.expect_eq(r.start_troops(SimRules.KIND_NATION, 2), 25000.0, "startManpower Nation Hard")

	# gold: base rates match upstream; gold_mult 0.85 is an intentional ~20 min pacing lever
	H.expect_eq(SimRules.GOLD_PER_TICK, 100.0, "goldAdditionRate Human/Nation base is 100/tick")
	H.expect_eq(SimRules.TRIBE_GOLD_PER_TICK, 50.0, "goldAdditionRate Tribe base is 50/tick")
	H.expect_near(r.gold_mult, 0.85, 1e-9, "gold_mult 0.85 (intentional pacing)")
	H.expect_near(r.gold_per_tick(SimRules.KIND_HUMAN), 85.0, 1e-9, "gold_per_tick Human = 100 * 0.85")
	H.expect_near(r.gold_per_tick(SimRules.KIND_TRIBE), 42.5, 1e-9, "gold_per_tick Tribe = 50 * 0.85")
	H.intentional("gold_mult 0.85 pacing (~20 min matches)", "port 85/42.5 gold per tick vs upstream 100/50")

	# build costs (sim_core_basics + arsenal price ladders)
	H.expect_eq(SimRules.build_cost("defense", 0), 50000.0, "defense cost first")
	H.expect_eq(SimRules.build_cost("defense", 9), 250000.0, "defense cost capped")
	H.expect_eq(SimRules.build_cost("city", 0), 125000.0, "first city 125K")
	H.expect_eq(SimRules.build_cost("city", 1), 250000.0, "second city 250K")
	H.expect_eq(SimRules.build_cost("city", 2), 500000.0, "third city 500K")
	H.expect_eq(SimRules.build_cost("city", 3), 1000000.0, "fourth city 1M")
	H.expect_eq(SimRules.build_cost("city", 9), 1000000.0, "city cost capped at 1M")
	H.expect_eq(SimRules.build_cost("silo", 0), 1000000.0, "silo 1M")
	H.expect_eq(SimRules.build_cost("silo", 3), 1000000.0, "silo flat 1M")
	H.expect_eq(SimRules.build_cost("sam", 0), 1500000.0, "first SAM 1.5M")
	H.expect_eq(SimRules.build_cost("sam", 1), 3000000.0, "second SAM 3M (capped)")
	H.expect_eq(SimRules.build_cost("warship", 0), 250000.0, "first warship 250K")
	H.expect_eq(SimRules.build_cost("warship", 1), 500000.0, "second warship 500K")
	H.expect_eq(SimRules.build_cost("warship", 9), 1000000.0, "warship capped 1M")
	H.expect_eq(SimRules.build_cost("artillery", 0), 150000.0, "artillery first 150K")
	H.expect_eq(SimRules.build_cost("artillery", 9), 750000.0, "artillery ladder cap 750K")
	H.expect_eq(SimRules.build_cost("airfield", 0), 500000.0, "airfield first 500K")
	H.expect_eq(SimRules.build_cost("railgun", 0), 2500000.0, "railgun first 2.5M")
	H.expect_eq(SimRules.build_cost("railgun", 5), 7500000.0, "railgun cap 7.5M")
	H.expect_eq(SimRules.build_cost("nope", 0), -1.0, "unknown kind")

	# distances at k_lin 1
	H.expect_near(r.struct_min_dist, 15.0, 1e-9, "STRUCT_MIN_DIST 15")
	H.expect_near(r.defense_range, 30.0, 1e-9, "DEFENSE_RADIUS 30")
	H.expect_near(r.spawn_radius, 4.0, 1e-9, "SPAWN_RADIUS 4")
	H.expect_near(r.sam_range(1), 70.0 * SimRules.SAM_RADIUS_MULT, 1e-6, "sam_range(1) = 70 x 0.8 (intentional)")
	H.expect_near(r.sam_range(5), (150.0 - 48.0) * SimRules.SAM_RADIUS_MULT, 1e-6, "sam_range(5) = 102 x 0.8 (intentional)")
	H.expect_near(r.sam_range_at(2, 0), r.sam_range(1), 1e-6, "sam_range_at(2, 0) = range of level 1")
	H.expect_near(r.sam_range_at(2, 45), r.sam_range(2), 1e-6, "sam_range_at(2, 45) = range of level 2")

	H.expect_eq(SimRules.warship_max_hp(1), 1200, "warship_max_hp(1) = 1200")
	H.expect_eq(SimRules.warship_max_hp(9), 1600, "warship_max_hp(9) clamped to vet 3 = 1600")
	H.expect_eq(r.shell_flight_ticks(0), 1, "shell_flight_ticks(0) == 1")
	H.expect_eq(r.shell_flight_ticks(10), 4, "shell_flight_ticks(10) == 4 (ceil(10/3))")
	H.expect_eq(r.munition_flight_ticks(100, SimRules.N_ATOM), 10, "nuke_flight_ticks(100, atom) == 10")
	H.expect_eq(r.human_grace_ticks(0), 3000, "human_grace_ticks Easy 3000")
	H.expect_eq(r.human_grace_ticks(9), 1200, "human_grace_ticks Hard (clamped) 1200")

	H.expect_near(SimRules.train_gold("self", 0), 10000.0, 1e-9, "train_gold self")
	H.expect_near(SimRules.train_gold("ally", 0), 35000.0, 1e-9, "train_gold ally")
	H.expect_near(SimRules.train_gold("other", 0), 25000.0, 1e-9, "train_gold other")
	H.expect_near(SimRules.train_gold("self", 12), 5000.0, 1e-9, "train_gold self many stops floored at 5K")

	# trade_gold(0) = 75000 / (1 + exp(9)) + 0
	var tg0 = 75000.0 / (1.0 + exp(9.0))
	H.expect_near(r.trade_gold(0), tg0, 1e-6, "trade_gold(0)")
	H.expect_eq(r.trade_spawn_rate(0, 0), int(floor(100.0 / r.trade_saturation(0))), "trade_spawn_rate(0,0)")
	H.expect_eq(SimRules.train_spawn_rate(1, 0), int(floor(165.0 / SimRules.train_saturation(0))), "train_spawn_rate(1,0)")

	H.expect_near(r.large_territory_bonus(300000.0, 0.7), 0.65, 1e-6, "large_territory_bonus midpoint")
	H.expect_near(SimRules.fallout_modifier(0.0), 5.0, 1e-9, "fallout_modifier(0) = 5")
	H.expect_near(SimRules.fallout_modifier(1.0), 3.0, 1e-9, "fallout_modifier(1) = 3")
	H.expect_near(SimRules.neutral_loss_per_mag(SimRules.KIND_TRIBE), 0.1, 1e-12, "tribe terra-nullius loss 1/10")
	H.expect_near(SimRules.neutral_loss_per_mag(SimRules.KIND_HUMAN), 0.2, 1e-12, "human terra-nullius loss 1/5")

	H.expect_eq(SimRules.NATION_GROWTH_MULT[0], 0.9, "nation growth multipliers[0] = 0.9")
	H.expect_eq(SimRules.NATION_GROWTH_MULT[1], 0.95, "nation growth multipliers[1] = 0.95")
	H.expect_eq(SimRules.NATION_GROWTH_MULT[2], 1.0, "nation growth multipliers[2] = 1.0")

	# max_troops: intentional cap vs upstream formula
	var up0 = 2.0 * (0.0 + 50000.0)  # 100000
	var got0 = r.max_troops(SimRules.KIND_HUMAN, 0, 0, 1)
	H.intentional("max_troops Human 0 tiles (intentional cap, not upstream 100000)", "port=%.1f  upstream=%.1f" % [got0, up0])
	H.expect(got0 != up0, "port max_troops differs from upstream at 0 tiles (intentional)", "port=%.1f upstream=%.1f" % [got0, up0])

	# k_lin scaling: sam range and spawn shrink
	var r2: SimRules = R.new(2.0)
	H.expect_near(r2.k_area, 4.0, 1e-9, "k_area = k_lin^2")
	H.expect_near(r2.sam_range(1), 70.0 * SimRules.SAM_RADIUS_MULT / 2.0, 1e-6, "sam_range scales with 1/k_lin")
	H.expect_near(r2.spawn_radius, 2.0, 1e-9, "spawn_radius scales with 1/k_lin")

	H.expect_near(r.launch_range(SimRules.N_AIRSTRIKE), 156.0, 1e-9, "launch_range airstrike 156")
	H.expect_near(r.launch_range(SimRules.N_SHELL), 45.0, 1e-9, "launch_range shell 45")
	H.expect_eq(r.launch_range(SimRules.N_ATOM), 0.0, "launch_range bombs 0 (range limits are the port's map-width fractions)")
	H.expect_eq(SimRules.nuke_cost_named("atom"), 750000.0, "nuke_cost_named atom 750K")
	H.expect_eq(SimRules.nuke_cost_named("mirv", 0), 25000000.0, "nuke_cost_named MIRV 25M")
	H.expect_eq(SimRules.nuke_cost_named("mirv", 1), 40000000.0, "nuke_cost_named MIRV +15M per prior launch")
	H.expect_eq(SimRules.nuke_cost_named("warhead"), -1.0, "nuke_cost_named warhead rejected")
	H.intentional("nuke flight uses a custom clock / ballistic arc in main.gd, not Rules.nuke_arc", "SimRules has no nuke_arc; intentional")
	H.expect_eq(SimRules.DEFAULT_ATTACK_RATIO, 0.2, "sim fallback DEFAULT_ATTACK_RATIO is 20% when an order carries no ratio")
	var src = FileAccess.get_file_as_string("res://main.gd")
	H.expect(src.find("0.10, 0.25, 0.35, 0.50, 0.75") >= 0 or src.find("0.10,0.25,0.35,0.50,0.75") >= 0, "HUD SHARES are 10/25/35/50/75 (upstream UICtx.RATIO_STOPS)", "")
	H.expect(src.find("share_i := 1") >= 0 or src.find("var share_i := 1") >= 0, "HUD default share_i is 1 (25%), matching UICtx.DEFAULT_RATIO", "")
