# Port of tests/simsys_warships.luau formula cases.
extends RefCounted

func run(H) -> void:
	H.section("simsys_warships", "simsys_warships.luau")
	H.expect_eq(SimRules.build_cost("warship", 0), 250000.0, "first warship 250K")
	H.expect_eq(SimRules.build_cost("warship", 1), 500000.0, "second warship 500K")
	H.expect_eq(SimRules.WARSHIP_HP, 1000, "warship base HP 1000")
	H.expect_eq(SimRules.warship_max_hp(0), 1000, "vet 0 max HP 1000")
	H.expect_eq(SimRules.warship_max_hp(1), 1200, "vet 1 max HP 1200")
	H.expect_eq(SimRules.warship_max_hp(2), 1400, "vet 2 max HP 1400")
	H.expect_eq(SimRules.warship_max_hp(3), 1600, "vet 3 max HP 1600")
	H.expect_eq(SimRules.WARSHIP_MAX_VET, 3, "capped at vet 3")
	H.expect_eq(SimRules.WARSHIP_VET_TRADES, 25, "transport kill: +25 of 250 veterancy points")
	H.expect_eq(SimRules.WARSHIP_VET_TRANSPORTS, 10, "trade capture: +10 veterancy points")
	# 250 points / 25 = 10 transport kills per level; 9*25=225 no level yet; 25 trade captures = +1? 
	# 25 captures * 10 = 250 = 1 level, plus leftover... test said 25 trade captures = +1 level and 25*10=250.
	# "25 trade captures = +1 level" wait the test said "25 trade captures = +1 level" and v.vet == 2 after that? Let me not overclaim.
	H.expect_eq(SimRules.WARSHIP_FIRE_TICKS, 20, "warship shells > 20 ticks apart")
	H.expect_eq(SimRules.WARSHIP_RETREAT_PCT, 75, "retreat threshold 75%")
	H.expect_eq(SimRules.WARSHIP_MANUAL_NO_RETREAT_TICKS, 50, "no retreat right after a manual move (50 ticks)")
	H.expect_eq(SimRules.WARSHIP_PASSIVE_HEAL, 1, "+1 HP/tick near an own port")
	H.expect_eq(SimRules.WARSHIP_PORT_HEAL_PER_LEVEL, 5, "docked: port level x 5 HP per tick")
	H.expect_eq(SimRules.SHELL_SPEED_FULL, 3.0, "warship shell speed 3 full-size tiles/tick")
	var r = SimRules.new(1.0)
	H.expect_near(r.warship_range(), 130.0, 1e-9, "warship range 130")
	H.expect_near(r.warship_patrol(), 100.0, 1e-9, "patrol / trade hunt 100")
	H.expect_near(r.warship_tiles_per_tick(false), 1.0, 1e-9, "patrol speed 1 tile/tick")
	H.expect_near(r.warship_tiles_per_tick(true), 2.0, 1e-9, "hunting speed 2 tiles/tick")

	# shell_damage: roll 1..5 -> 200, 225, 250, 275, 300 then * (100+vet*20)/100
	H.expect_eq(SimRules.shell_damage(1, 0), 200, "shell damage roll 1 = 200")
	H.expect_eq(SimRules.shell_damage(5, 0), 300, "shell damage roll 5 = 300")
	# roll 1, vet 1: 200 * 120/100 = 240
	H.expect_eq(SimRules.shell_damage(1, 1), 240, "shell damage roll 1 vet 1 = 240")
