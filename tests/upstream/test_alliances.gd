# Port of tests/alliances.luau constants. Live request/expiry/extend cases are in test_live.gd.
extends RefCounted

func run(H) -> void:
	H.section("alliances constants", "alliances.luau")
	H.expect_eq(SimRules.ALLIANCE_TICKS, 3000, "alliance lasts 3000 ticks (5 min)")
	H.expect_eq(SimRules.ALLIANCE_EXTEND_WINDOW_TICKS, 300, "renewal window opens 300 ticks before expiry")
	H.expect_eq(SimRules.ALLY_REQUEST_TICKS, 200, "request expires in 200 ticks")
	H.expect_eq(SimRules.ALLY_REQUEST_COOLDOWN_TICKS, 300, "request cooldown 300 ticks")
	H.expect_eq(SimRules.TRAITOR_TICKS, 300, "traitor debuff 300 ticks (30 s)")
	H.expect_eq(SimRules.AI_MAX_ALLIES, 3, "AI_MAX_ALLIES 3")
	H.expect_eq(SimRules.HOSTILE_TICKS, 600, "hostile / grudge-style 600 ticks")
	var src = preload("res://tests/upstream/_harness.gd").game_src()
	H.expect(src.find("func has_request") >= 0 and src.find("func propose_alliance") >= 0 and src.find("func ally_reply") >= 0, "request / reply / ask-back APIs are in main.gd", "")
	H.expect(src.find("randi_range(20, 45)") >= 0, "AI reply is due in 20..45 ticks", "")
	H.expect(src.find("p := 0.3") >= 0 and src.find("p += 0.35") >= 0, "AI accept best case 0.65 = 0.3+0.35 (ratio > 1.5)", "")
	H.expect(src.find("func in_extension_window") >= 0 and src.find("func ally_extend") >= 0, "alliance extend / window APIs are present", "")
	H.expect(src.find("sim_atk.tick + SimRules.ALLIANCE_TICKS") >= 0, "alliance expiry is in sim ticks (ALLIANCE_TICKS)", "")
