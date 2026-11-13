# Attack / growth-rules constants and the organic-border factor. Live conquest ticks are pending.
extends RefCounted

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""

func run(H) -> void:
	H.section("growth_rules attackLogic constants", "growth_rules.luau")
	H.expect_eq(SimRules.ATTACK_MAG[0], 80.0, "plains magnitude 80")
	H.expect_eq(SimRules.ATTACK_MAG[1], 100.0, "highland magnitude 100")
	H.expect_eq(SimRules.ATTACK_MAG[2], 120.0, "mountain magnitude 120")
	H.expect_eq(SimRules.ATTACK_TILE_COST[0], 16.5, "plains tileCost 16.5")
	H.expect_eq(SimRules.ATTACK_TILE_COST[1], 20.0, "highland tileCost 20")
	H.expect_eq(SimRules.ATTACK_TILE_COST[2], 25.0, "mountain tileCost 25")
	H.expect_eq(SimRules.PRIORITY_MAG[0], 1.0, "plains priority mag 1")
	H.expect_eq(SimRules.PRIORITY_MAG[1], 1.5, "highland priority mag 1.5")
	H.expect_eq(SimRules.PRIORITY_MAG[2], 2.0, "mountain priority mag 2")
	H.expect_eq(SimRules.LARGE_ATTACKER_DEPTH, 0.7, "largeTerritoryBonus attacker 0.7")
	H.expect_eq(SimRules.LARGE_DEFENDER_DEPTH, 0.3, "largeTerritoryBonus defender 0.3")
	H.expect_eq(SimRules.LARGE_ATTACKER_SPEED_DEPTH, 0.73, "attacker speed depth 0.73")
	H.expect_eq(SimRules.BOT_DEFENDER_LOSS_MULT, 0.7, "human/nation vs bot: mag × 0.7")
	H.expect_eq(SimRules.ATTACKER_LOSS_BASE, 0.463, "attacker loss base 0.463")
	H.expect_eq(SimRules.ATTACKER_LOSS_PER_DENSITY, 0.0039, "attacker loss per density 0.0039")
	H.expect_eq(SimRules.SPEED_COST_DIVISOR, 8.55, "speedCost divisor 8.55")
	H.expect_eq(SimRules.TERRA_NULLIUS_COST_SCALE, 2000.0, "terra nullius cost scale 2000")
	H.expect_eq(SimRules.TERRA_NULLIUS_MIN_COST, 5.0, "terra nullius min 5")
	H.expect_eq(SimRules.TERRA_NULLIUS_MAX_COST, 100.0, "terra nullius max 100")
	H.expect_eq(SimRules.TRAITOR_DEFENSE_DEBUFF, 0.5, "traitorDefenseDebuff 0.5")
	H.expect_eq(SimRules.TRAITOR_SPEED_DEBUFF, 0.8, "traitorSpeedDebuff 0.8")
	H.expect_eq(SimRules.RETREAT_KEEP, 0.75, "retreat keeps 75%")
	H.expect_eq(SimRules.RETREAT_DELAY_TICKS, 20, "cancelDelay 20 ticks")
	H.expect_eq(SimRules.DEFENSE_POST_MAG, 5.0, "defense post magnitude ×5")
	H.expect_eq(SimRules.DEFENSE_POST_COST, 3.0, "defense post tile cost ×3")
	H.expect_eq(SimRules.WIN_SHARE, 0.8, "WIN_SHARE 0.8")

	H.section("organic borders (intentional)", "growth_rules.luau")
	var atk = _read("res://sim/attacks.gd")
	H.expect(atk.find("0.9, 1.1") >= 0 or atk.find("0.9,1.1") >= 0, "organic speed factor clamped to 0.9–1.1", "intentional")
	H.intentional("organic borders 0.9–1.1× per tile (not in upstream attackLogic)", "port: low-freq noise ±7% plus jitter ±3%, clamped 0.9..1.1, mean 1.0")
