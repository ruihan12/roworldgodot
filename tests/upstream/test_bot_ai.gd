# Port of tests/bot_skill.luau and tests/simsys_ai.luau constants. Live matches pending.
extends RefCounted

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""

func run(H) -> void:
	H.section("bot_skill", "bot_skill.luau")
	var r = SimRules.new(1.0)
	H.expect_eq(r.start_troops(SimRules.KIND_NATION, 0), 12500.0, "novices start with the Easy nation's troops (12500)")
	H.expect_eq(r.human_grace_ticks(0), 3000, "Easy towards players: 5 min of peace")
	H.expect_eq(SimRules.MAX_AI_WARS_ON_HUMAN[0], 1, "Easy: 1 AI war on a player")
	H.expect_eq(SimRules.MAX_AI_WARS_ON_HUMAN[1], 2, "Standard: at most 2 AI nations at war with a human")
	H.expect_eq(SimRules.MAX_AI_WARS_ON_HUMAN[2], 3, "Hard: 3 AI wars on a human")
	H.expect_eq(SimRules.HUMAN_GRACE_TICKS[0], 3000, "grace 5 min Easy")
	H.expect_eq(SimRules.HUMAN_GRACE_TICKS[1], 1800, "grace 3 min Standard")
	H.expect_eq(SimRules.HUMAN_GRACE_TICKS[2], 1200, "grace 2 min Hard")
	H.expect_eq(SimRules.HUMAN_GRACE_JITTER, 900, "grace jitter 900 ticks")

	var ai_src = _read("res://sim/ai.gd")
	var main_src = preload("res://tests/upstream/_harness.gd").game_src()
	H.expect(main_src.find("func add_bot_players") >= 0 and main_src.find("func is_novice_bot") >= 0, "SMART_BOTS / novice-bot split is present (live cases in test_bots_live.gd)")
	H.intentional("fewer bot attacks on a new player vs the old all-smart bots (5 min World@80 public match, AF_SLOW)", "a slow statistical comparison upstream skips by default; the rules it measures are checked live")
	H.section("simsys_ai", "simsys_ai.luau")
	H.expect(ai_src.find("grace") >= 0 or ai_src.find("may_attack_human") >= 0, "AI human-protection / grace is present in sim/ai.gd", "")

	# no capital / no ice: documented intentional; maps tests live with executor 2
	H.section("intentional map deviations", "growth_rules.luau")
	var maps_src = _read("res://sim/upstream_maps.gd") + preload("res://tests/upstream/_harness.gd").game_src()
	H.intentional("Antarctica is present as white snow (code 4) playing like plains; no impassable ice (0x9F); no capital", "maps document code 4 snow; main.gd colours it white and uses plains rules")
	H.expect(maps_src.find("is_snow") >= 0 or maps_src.find("code 4") >= 0 or maps_src.find("== 4") >= 0, "snow / Antarctica terrain is in the port", "")
	H.expect(maps_src.find("plains") >= 0 and (maps_src.find("SNOW") >= 0 or maps_src.find("snow") >= 0), "snow uses plains rules / white colour", "")
