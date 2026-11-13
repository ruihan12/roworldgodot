# Port of tests/sim_conquest.luau gold-handover rules.
extends RefCounted

func run(H) -> void:
	H.section("sim_conquest", "sim_conquest.luau")
	H.expect_eq(SimRules.new().conquer_gold(SimRules.KIND_NATION, 5000.0), 5000.0, "killer takes a nation's gold (100%)")
	H.expect_eq(SimRules.new().conquer_gold(SimRules.KIND_TRIBE, 1234.0), 1234.0, "killer takes a tribe's gold (100%)")
	H.expect_eq(SimRules.new().conquer_gold(SimRules.KIND_HUMAN, 1000.0), 500.0, "killer takes half of a human's gold")
	H.expect_eq(SimRules.CAPITULATE_AGE, 12000, "capitulate age 12000 ticks")
	H.expect_eq(SimRules.CAPITULATE_SHARE, 0.02, "capitulate share 0.02")
	H.expect_eq(SimRules.CAPITULATE_RATIO, 8.0, "capitulate ratio 8")
	H.expect_eq(SimRules.CAPITULATE_GAP, 300, "capitulate gap 300 ticks")
	H.expect_eq(SimRules.ANNEX_BELOW_FULL_TILES, 100.0, "annex below 100 full-size tiles")
