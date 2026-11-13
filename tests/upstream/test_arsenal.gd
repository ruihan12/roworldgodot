# Port of tests/arsenal.luau formula/cost cases. Live launch/build cases are pending.
extends RefCounted

func run(H) -> void:
	H.section("arsenal", "arsenal.luau")
	H.expect_eq(SimRules.build_cost("artillery", 0), 150000.0, "artillery price ladder first 150,000")
	H.expect_eq(SimRules.build_cost("artillery", 9), 750000.0, "artillery price ladder cap 750,000")
	H.expect_eq(SimRules.build_cost("airfield", 0), 500000.0, "airfield 500,000")
	H.expect_eq(SimRules.build_cost("railgun", 0), 2500000.0, "railgun first 2,500,000")
	H.expect_eq(SimRules.build_cost("railgun", 5), 7500000.0, "railgun cap 7,500,000")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_MEGA], 2500000.0, "mega 2,500,000 gold")
	H.expect_eq(SimRules.NUKE_COST[SimRules.N_SCATTER], 3750000.0, "scatter 3,750,000 gold")
	H.expect_eq(SimRules.REINFORCE_COST, 100000.0, "reinforcements 100,000 gold")
	H.expect_eq(SimRules.REINFORCE_FRACTION, 0.20, "reinforcements a fifth of the cap")
	H.expect_eq(SimRules.REINFORCE_COOLDOWN_TICKS, 300, "30 s between reinforcement calls")
	H.expect_eq(SimRules.RAPID_RELOAD_MULT, 0.5, "rapid reload halves silo / battery gaps")
	H.expect_eq(SimRules.SILO_COOLDOWN_TICKS, 90, "silo 9 s; half is 4.5 s (45 ticks)")
	H.expect_eq(SimRules.RELOAD_TICKS[7], 300, "airfield rearm 30 s (300 ticks)")
	H.expect_eq(SimRules.RELOAD_TICKS[8], 250, "railgun reload 25 s")
	H.expect_eq(SimRules.BUILD_TICKS[6], 80, "artillery construction 8 s (80 ticks)")
	H.expect_eq(SimRules.STRUCT_HP[0], 1000, "city HP 1000")
	H.expect_eq(SimRules.STRUCT_HP[3], 600, "defense post HP 600")
	H.expect_eq(SimRules.STRIKE_DAMAGE[SimRules.N_SHELL], 150, "shell 150 damage to a city")
	H.expect_eq(SimRules.STRIKE_DAMAGE[SimRules.N_AIRSTRIKE], 600, "airstrike 600 damage")
	H.expect_eq(SimRules.STRIKE_DAMAGE[SimRules.N_SLUG], 1000, "slug 1000 damage")

	var r = SimRules.new(1.0)
	H.expect_near(r.artillery_range(), 45.0, 1e-9, "artillery range 45")
	H.expect_near(r.airfield_range(), 156.0, 1e-9, "airfield / airstrike reach 156")

	# strike_kill
	H.expect_eq(SimRules.strike_kill(SimRules.N_SHELL, 20000.0, 1.0), 1440.0, "a small army loses at least 1,440 to a shell")
	H.expect_eq(SimRules.strike_kill(SimRules.N_SHELL, 900.0, 1.0), 900.0, "shell never more than the army")
	H.expect_eq(SimRules.strike_kill(SimRules.N_SHELL, 5000000.0, 1.0), 19200.0, "shell at most 19,200")
	# 2.88% of 100000 = 2880
	H.expect_eq(SimRules.strike_kill(SimRules.N_SHELL, 100000.0, 1.0), 2880.0, "shell kills 2.88% of a 100k army")

	H.expect_eq(SimRules.strike_kill(SimRules.N_AIRSTRIKE, 10000.0, 1.0), 60.0, "airstrike 60 per tile (capped by 6% = 600)")
	H.expect_eq(SimRules.strike_kill(SimRules.N_AIRSTRIKE, 10000.0, 200.0), 600.0, "airstrike at most 6% of the army")
	H.expect_eq(SimRules.strike_kill(SimRules.N_SLUG, 10000.0, 1.0), 150.0, "slug 150 per tile")
	H.expect_eq(SimRules.strike_kill(SimRules.N_SLUG, 10000.0, 100.0), 400.0, "slug at most 4% of the army")

	H.expect_eq(SimRules.reinforce_troops(0.0, 200000.0), 40000.0, "reinforce: a fifth of 200k cap")
	H.expect_eq(SimRules.reinforce_troops(180000.0, 200000.0), 20000.0, "reinforce never past the cap")
	H.expect_eq(SimRules.reinforce_troops(200000.0, 200000.0), 0.0, "reinforce at cap is 0")
