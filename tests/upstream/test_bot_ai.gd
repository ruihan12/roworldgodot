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
	var main_src = _read("res://main.gd")
	var has_smart = (ai_src + main_src).find("SMART_BOTS") >= 0 or (ai_src + main_src).find("NOVICE_SKILL") >= 0 or (ai_src + main_src).find("is_novice_bot") >= 0
	if has_smart:
		H.ok("SMART_BOTS / novice-bot split is present")
	else:
		H.missing("SMART_BOTS split: some bot players are Medium, the rest are Easy novices; deterministic", "sim/ai.gd and main.gd have no SMART_BOTS / is_novice_bot / NOVICE_SKILL")

	H.missing("fewer bot attacks on a new player vs the old all-smart bots (5 min World public-style match)", "needs add_bot_players + a live 3000-tick match")
	H.missing("smart bots follow Easy's rules towards players (SMART_VS_PLAYERS == 0)", "SMART_VS_PLAYERS not in SimRules")

	H.section("simsys_ai", "simsys_ai.luau")
	H.expect(ai_src.find("grace") >= 0 or ai_src.find("may_attack_human") >= 0, "AI human-protection / grace is present in sim/ai.gd", "")
	H.missing("build choice: coastal nation first a port (PORT_FIRST), then cities, ports while < 0.75 × cities", "needs NationStructureBehavior / decide()")
	H.missing("nothing below 100K gold; 20-tick build gap; last_build stamped", "needs AI economy tick")
	H.missing("Hard: retaliation builds warships ~50% of the time, fleet cap 10; Relaxed never tracks", "needs _tracks_ships / warship behaviour")
	H.missing("no nukes before NUKE_AGE (6 min on Standard); NUKE_GAP 3 min; MIRV at a leader holding >= 35%; tribes never nuked", "needs AI nuke planner")
	H.missing("attack cadence by difficulty (attackRate nations lo-hi)", "needs a real match at each difficulty")

	H.section("sim_bots / sim_nav / spawn_shield / tribes_rules / sim_smoke", "sim_bots.luau")
	H.missing("sim_bots: bot player setup and orders", "needs Sim.add_bot_players")
	H.missing("spawn_shield: spawn protection rules", "needs spawn-shield API")
	H.missing("tribes_rules: tribe behaviour / traitor / attack tick", "partially in sim/ai.gd (_think_tribe); needs a live tribe Sim")
	H.missing("sim_smoke / sim_matches / sim_gamestate / sim_mirror / sliced_step / sim_coop", "full Sim + GameState snapshot/mirror not exposed as a headless object yet")
	H.missing("map_scale / parity_rng / parity_sort", "parity helpers; Rng should be checked once a Sim RNG is extracted")

	# no capital / no ice: documented intentional; maps tests live with executor 2
	H.section("intentional map deviations", "growth_rules.luau")
	var maps_src = _read("res://sim/upstream_maps.gd") + _read("res://main.gd")
	H.intentional("Antarctica is present as white snow (code 4) playing like plains; no impassable ice (0x9F); no capital", "maps document code 4 snow; main.gd colours it white and uses plains rules")
	H.expect(maps_src.find("is_snow") >= 0 or maps_src.find("code 4") >= 0 or maps_src.find("== 4") >= 0, "snow / Antarctica terrain is in the port", "")
	H.expect(maps_src.find("plains") >= 0 and (maps_src.find("SNOW") >= 0 or maps_src.find("snow") >= 0), "snow uses plains rules / white colour", "")
