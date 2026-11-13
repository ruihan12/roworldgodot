# Headless check of sim/upstream_maps.gd:
#   godot --headless --path . -s res://tests/test_upstream_maps.gd
extends SceneTree

const UM := preload("res://sim/upstream_maps.gd")

func _init() -> void:
	var fails := 0
	var idx := UM.index()
	print("index maps=%d nation_table=%d tribes=%d" % [idx.get("maps", []).size(), UM.nation_colors().size(), UM.tribe_names().size()])
	if UM.nation_colors().size() < 80 or UM.tribe_names().size() < 400: fails += 1
	DirAccess.make_dir_recursive_absolute("user://upstream_test")
	for k in UM.count():
		var id := UM.id_at(k)
		var t0 := Time.get_ticks_usec()
		var c := UM.codes(id)
		var tb := UM.tiles(id)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var m := UM.meta(id)
		var hist := [0, 0, 0, 0, 0]
		var bad := 0
		var mismatch := 0
		for i in c.size():
			var v: int = c[i]
			if v > 4: bad += 1
			else: hist[v] += 1
			if (v > 0) != (tb[i] >= 128): mismatch += 1
		var land: int = hist[1] + hist[2] + hist[3] + hist[4]
		var ok := c.size() == UM.W * UM.H and tb.size() == UM.W * UM.H and bad == 0 and mismatch == 0 and land == int(m.land_tiles)
		# nations on land, inside the map
		var off := 0
		for n in UM.nations(id):
			var x: int = n[2]; var y: int = n[3]
			if x < 0 or y < 0 or x >= UM.W or y >= UM.H or c[y * UM.W + x] == 0: off += 1
		# no ice / impassable, no land in the far south rows of World (Antarctica)
		var ice := 0
		for i in tb.size():
			if tb[i] == 0x9F: ice += 1
		ok = ok and off == 0 and ice == 0
		if id == "world":
			var aq := UM.nations(id).filter(func(e): return e[1] == "aq").size()
			print("world snow=%d aq_spawns=%d" % [hist[4], aq])
			ok = ok and hist[4] > 100000 and aq == 3
		elif hist[4] != 0: ok = false
		var rm := UM.as_real_map(id)
		var rb: PackedByteArray = Marshalls.base64_to_raw(rm.b64).decompress(UM.W * UM.H, FileAccess.COMPRESSION_DEFLATE)
		ok = ok and rb == c
		UM.preview_image(id, 448, 400).save_png("user://upstream_test/%s.png" % id)
		print("%-13s %s codes=%s land=%d nations=%d off_land=%d ice=%d k_lin=%.3f scale=%.3f load_ms=%.0f" % [
			id, "OK  " if ok else "FAIL", str(hist), land, UM.nations(id).size(), off, ice, float(m.k_lin), float(m.scale), ms])
		if not ok: fails += 1
	print("menu_entries=", UM.menu_entries().map(func(e): return e[0]))
	print("UPSTREAM_MAPS_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
