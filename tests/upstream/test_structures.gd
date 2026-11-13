# Port of tests/simsys_structures.luau cost/placement cases. Roads/trucks mostly pending.
extends RefCounted

class FakeWorld:
	var W: int
	var H: int
	var owner_map = PackedInt32Array()
	var structs: Array = []
	var water = PackedByteArray()  # 1 = water

	func _init(w: int, h: int) -> void:
		W = w
		H = h
		owner_map.resize(w * h)
		owner_map.fill(0)
		water.resize(w * h)
		water.fill(0)

	func fill_rect(o: int, x0: int, y0: int, x1: int, y1: int) -> void:
		for y in range(y0, y1):
			for x in range(x0, x1):
				owner_map[y * W + x] = o

	func set_water_border() -> void:
		# left column water
		for y in H:
			water[y * W] = 1
			owner_map[y * W] = -1

	func _coastal(t: int) -> bool:
		if t < 0 or t >= owner_map.size() or owner_map[t] <= 0:
			return false
		var x = t % W
		for n in [t - W if t >= W else -1, t + W if t < owner_map.size() - W else -1, t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1]:
			if n >= 0 and water[n] == 1:
				return true
		return false

func run(H) -> void:
	H.section("simsys_structures", "simsys_structures.luau")
	H.expect_eq(SimRules.build_cost("city", 0), 125000.0, "first city costs 125K")
	H.expect_eq(SimRules.build_cost("city", 1), 250000.0, "second city costs 250K")
	H.expect_eq(SimRules.build_cost("city", 2), 500000.0, "upgrade / third city 500K")
	H.expect_eq(SimRules.BUILD_TICKS[0], 20, "city construction 20 ticks (2 s)")
	H.expect_eq(SimRules.BUILD_TICKS[4], 300, "SAM construction 300 ticks (30 s)")
	H.expect_eq(SimRules.BUILD_TICKS[3], 50, "defense post 50 ticks")
	H.expect_eq(SimRules.RELOAD_TICKS[4], 90, "SAM missile reload 90 ticks")
	H.expect_eq(SimRules.TRUCKS_PER_FACTORY, 6, "TRUCKS_PER_FACTORY 6")
	H.expect_eq(SimRules.TRAIN_UNITS, 6, "TRAIN_UNITS 6")
	H.expect_eq(SimRules.TRAIN_COOLDOWN_TICKS, 10, "TRAIN_COOLDOWN_TICKS 10")
	var r = SimRules.new(1.0)
	H.expect_near(r.place_search_r(), 15.0, 1e-9, "PLACE_SEARCH_R 15")
	H.expect_near(r.struct_min_dist, 15.0, 1e-9, "STRUCT_MIN_DIST 15")
	H.expect_near(r.train_tiles_per_tick(), 2.0, 1e-9, "train speed 2 full-size tiles/tick")
	H.expect_eq(SimRules.train_gold("self", 0), 10000.0, "self train stop 10K")

	# place_site against a stub world (does not touch main.gd)
	var g = FakeWorld.new(60, 40)
	g.fill_rect(1, 5, 5, 40, 30)
	g.set_water_border()
	var S = load("res://sim/structures.gd").new(g, r)
	var bad = S.place_site(1, 0, 0)  # water / not own
	H.expect_eq(str(bad.reason), "not_own", "place_site on unowned/water: not_own")
	var inv = S.place_site(1, 0, -5)
	H.expect_eq(str(inv.reason), "invalid", "place_site invalid tile")
	var okp = S.place_site(1, 0, 10 * 60 + 10)
	H.expect(int(okp.tile) >= 0 and okp.upgrade == null, "place_site city on a clear owned tile", "tile=%s reason=%s" % [str(okp.tile), str(okp.reason)])
	# occupy that tile with a city, then a second city too close should be pushed away or no_room if the whole flood is blocked
	g.structs.append({"k": 0, "tile": int(okp.tile), "o": 1, "bt": 0.0, "level": 1})
	var up = S.place_site(1, 0, int(okp.tile))
	H.expect(up.upgrade != null, "place_site on an existing city is an upgrade", "tile=%s" % str(up.tile))
	# port on inland land: no_coast (left column is water, so right side of the blob has no water neighbour)
	var inland = 20 * 60 + 30
	var pr = S.place_site(1, 1, inland)
	H.expect_eq(str(pr.reason), "no_coast", "inland port click: no_coast (manhattan 20 from a coast)")
	# port near the west coast of the blob (x=5 next to water x=0? wait water is x=0, land starts x=5 — manhattan 5)
	# land is 5..40, water is x=0, so x=5 is not adjacent to water (x=1..4 are owner 0). Make a coastal strip.
	# The earlier city at ~(10,10) is within STRUCT_MIN_DIST of the west coast, so drop it.
	g.structs.clear()
	g.fill_rect(1, 1, 8, 8, 20)  # land abutting water column 0
	var coast_t = 12 * 60 + 1
	H.expect(g._coastal(coast_t), "fixture: tile (1,12) is coastal", "")
	var p2 = S.place_site(1, 1, coast_t)
	H.expect(int(p2.tile) >= 0, "port snaps to a free coastal tile in range", "tile=%s reason=%s" % [str(p2.tile), str(p2.reason)])
