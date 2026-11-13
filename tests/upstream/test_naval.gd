# Port of tests/simsys_naval.luau (transports + trade gold). Live pathing pending.
extends RefCounted

func run(H) -> void:
	H.section("simsys_naval", "simsys_naval.luau")
	H.expect_eq(SimRules.MAX_BOATS_PER_OWNER, 3, "AI boat cap 3 (boatMaxNumber)")
	H.expect_eq(SimRules.MAX_BOATS_PLAYER, 10, "a person: 10 transports at sea")
	H.expect_eq(SimRules.BOAT_ATTACK_FRACTION, 0.2, "landing starts a 20% beachhead attack")
	H.expect_eq(SimRules.RETREAT_KEEP, 0.75, "transport return keeps 75% of the embarked troops")
	var r = SimRules.new(1.0)
	H.expect_near(r.ship_tiles_per_s(), 10.0, 1e-9, "ships 1 full-size tile per tick = 10 tiles/s at k_lin 1")
	H.expect_eq(r.alt_landing_r(), 6, "alt landing search 6 tiles at k_lin 1")
	H.expect_near(r.port_spawn_manhattan(), 20.0, 1e-9, "port water spawn manhattan 20")
	H.expect_near(r.trade_gold(0), 75000.0 / (1.0 + exp(9.0)), 1e-6, "trade_gold(0)")
	H.expect_near(r.trade_gold(32), 75000.0 / (1.0 + exp(-0.03 * (32.0 - 300.0))) + 50.0 * 32.0, 1e-4, "trade_gold(32)")
	H.expect_eq(r.trade_spawn_rate(0, 0), int(floor(100.0 / r.trade_saturation(0))), "trade_spawn_rate")
