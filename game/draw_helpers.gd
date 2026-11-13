extends "res://game/bot_ai.gd"
# Drawing helpers: sprites, icons, wakes, quality

# ---------- drawing helpers ----------
func _shape_pts(k: int, p: Vector2, r: float) -> PackedVector2Array:
	if k == 14:
		var q := r * 0.42
		var cr := PackedVector2Array()
		for v in [Vector2(-q, -r), Vector2(q, -r), Vector2(q, -q), Vector2(r, -q), Vector2(r, q), Vector2(q, q), Vector2(q, r), Vector2(-q, r), Vector2(-q, q), Vector2(-r, q), Vector2(-r, -q), Vector2(-q, -q)]: cr.append(p + v * 1.15)
		return cr
	var sides := {0: 0, 1: 5, 2: 6, 3: 8, 4: 4, 5: 3, 10: 4}.get(k, 0) as int
	var pts := PackedVector2Array()
	if sides == 0:
		for m in 20: pts.append(p + Vector2.from_angle(m * TAU / 20) * r)
		return pts
	var rot := -PI / 2
	if k == 4: rot = PI / 4
	if k == 10: rot = 0.0
	if k == 3: rot = PI / 8
	for m in sides: pts.append(p + Vector2.from_angle(rot + m * TAU / sides) * r * (1.15 if k in [4, 5] else 1.0))
	return pts


func _tex(rel: String, up := 1) -> Texture2D:
	var key := rel + "@" + str(up)
	if _tex_cache.has(key): return _tex_cache[key]
	var t: Texture2D = null
	var path := "res://assets/" + rel
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			if up > 1: img.resize(img.get_width() * up, img.get_height() * up, Image.INTERPOLATE_NEAREST)
			t = ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t

func _atlas_draw(ci: CanvasItem, tex: Texture2D, cell: float, col: int, row: int, center: Vector2, size: float, mod: Color, rot := 0.0) -> void:
	var src := Rect2(col * cell, row * cell, cell, cell)
	if rot != 0.0:
		ci.draw_set_transform(center, rot, Vector2.ONE)
		ci.draw_texture_rect_region(tex, Rect2(-size / 2, -size / 2, size, size), src, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tex, Rect2(center.x - size / 2, center.y - size / 2, size, size), src, mod)

# Unit sprite (13px cells, row 0 territory colour, row 1 border colour). Returns false if missing.
func _unit_sprite(p: Vector2, col_i: int, col: Color, size: float, rot := 0.0) -> bool:
	var t := _tex("units.png", 4)
	if t == null: return false
	_atlas_draw(overlay, t, 52.0, col_i, 0, p, size, col.lightened(0.15), rot)
	_atlas_draw(overlay, t, 52.0, col_i, 1, p, size, col.darkened(0.55), rot)
	return true

func _ship_px() -> float:
	var ds: float = hud._device_scale() if hud and hud.has_method("_device_scale") else 1.0
	var dev: float = maxf(SHIP_MIN_PX, roundf(SHIP_UNIT_SIZE_FULL / sim_rules.k_lin * TS * cam.zoom.x * ds))
	return dev / ds

func _ship_sprite(p: Vector2, col_i: int, col: Color) -> bool:
	var t := _tex("units_old.png", 4)
	if t == null: return false
	var ds: float = hud._device_scale() if hud and hud.has_method("_device_scale") else 1.0
	var px := _ship_px()
	var c := Vector2(roundf(p.x * ds), roundf(p.y * ds)) / ds
	var rim := Color.from_hsv(col.h, col.s, maxf(0.0, col.v - 0.16), col.a)
	_atlas_draw(overlay, t, 52.0, col_i, 0, c, px, col)
	_atlas_draw(overlay, t, 52.0, col_i, 1, c, px, rim)
	return true

func _map_icon(p: Vector2, k: int, col: Color, a := 1.0) -> void:
	var plates := _tex("plates.png"); var glyphs := _tex("glyphs.png")
	if plates != null and glyphs != null and ST_COL.has(k):
		var c: int = ST_COL[k]
		var base := 20.0
		var sz: float = base * SHAPE_SCALE[c]
		_atlas_draw(overlay, plates, 112.0, c, 0, p, sz, Color(col.darkened(0.55), a))
		_atlas_draw(overlay, plates, 112.0, c, 1, p, sz, Color(col.lightened(0.1), a))
		_atlas_draw(overlay, glyphs, 64.0, c, 0, p, base * ICON_FILL[c], Color(1, 1, 1, a))
		return
	_map_icon_proc(p, k, col, a)

func _map_icon_proc(p: Vector2, k: int, col: Color, a := 1.0) -> void:
	var r := 9.0
	var pts := _shape_pts(k, p, r)
	overlay.draw_colored_polygon(pts, Color(col.lightened(0.35), a))
	var ring := pts.duplicate(); ring.append(pts[0])
	overlay.draw_polyline(ring, Color(col.darkened(0.55), a), 2.0, true)
	_icon(p + Vector2(0, 1 if k == 5 else 0), k, col.darkened(0.5), a, overlay, 5.0, false)

func _rail_pos(st_from, st_to, f: float) -> Array:
	var rc := _rail_curve(st_from.tile, st_to.tile)
	if rc.is_empty():
		var p0 := Vector2(st_from.tile % W + 0.5, st_from.tile / W + 0.5)
		var p1 := Vector2(st_to.tile % W + 0.5, st_to.tile / W + 0.5)
		return [p0.lerp(p1, f), (p1 - p0).normalized(), maxf(1.0, p0.distance_to(p1))]
	var pts: PackedVector2Array = rc[0]
	var cum: PackedFloat32Array = rc[1]
	var tot: float = maxf(0.001, cum[cum.size() - 1])
	var forward: bool = st_from.tile < st_to.tile
	var u: float = clampf(f, 0.0, 1.0) if forward else clampf(1.0 - f, 0.0, 1.0)
	var d: float = u * tot
	var m := 1
	while m < cum.size() - 1 and cum[m] < d:
		m += 1
	var seg := maxf(0.0001, cum[m] - cum[m - 1])
	var p: Vector2 = pts[m - 1].lerp(pts[m], clampf((d - cum[m - 1]) / seg, 0.0, 1.0))
	var dir: Vector2 = (pts[m] - pts[m - 1]).normalized() * (1.0 if forward else -1.0)
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	return [p, dir, tot]

func _draw_straight_bridge(pa: Vector2, pb: Vector2, col: Color) -> void:
	var L := pa.distance_to(pb)
	if L < 2.0: return
	var dir := (pb - pa) / L
	var nrm := Vector2(-dir.y, dir.x)
	# 1. Underwater concrete support piers/pilings at regular intervals
	var pier_step := 16.0
	var pd := 8.0
	while pd < L - 4.0:
		var pc := pa + dir * pd
		overlay.draw_line(pc - nrm * 6.2, pc + nrm * 6.2, Color(0.12, 0.15, 0.22, 0.95), 4.2)
		overlay.draw_circle(pc - nrm * 5.8, 2.3, Color(0.55, 0.62, 0.72, 0.95))
		overlay.draw_circle(pc + nrm * 5.8, 2.3, Color(0.55, 0.62, 0.72, 0.95))
		pd += pier_step
	# 2. Straight steel/concrete bridge deck (NOT curved)
	overlay.draw_line(pa, pb, Color(0.14, 0.17, 0.24, 0.96), 9.0)
	overlay.draw_line(pa, pb, Color(0.42, 0.47, 0.56, 0.95), 6.2)
	# 3. Parallel outer steel truss girders + diagonal X-bracing struts
	var g_off := nrm * 4.2
	overlay.draw_line(pa + g_off, pb + g_off, Color(0.82, 0.86, 0.94, 0.95), 1.6)
	overlay.draw_line(pa - g_off, pb - g_off, Color(0.82, 0.86, 0.94, 0.95), 1.6)
	var td := 0.0
	var t_step := 8.0
	var flip := false
	while td < L - 1.0:
		var p0 := pa + dir * td
		var p1 := pa + dir * minf(L, td + t_step)
		overlay.draw_line(p0 - g_off, p0 + g_off, Color(0.28, 0.32, 0.40, 0.9), 1.2)
		if flip:
			overlay.draw_line(p0 - g_off, p1 + g_off, Color(0.75, 0.80, 0.90, 0.65), 1.1)
		else:
			overlay.draw_line(p0 + g_off, p1 - g_off, Color(0.75, 0.80, 0.90, 0.65), 1.1)
		flip = not flip
		td += t_step
	# 4. Dead-straight center railway track along the bridge deck
	overlay.draw_line(pa, pb, col, 2.0)

func _draw_railway(st_a, st_b, col: Color) -> void:
	_tie_vr = Rect2(Vector2.ZERO, get_viewport_rect().size).grow(8.0)
	var rc := _rail_curve(st_a.tile, st_b.tile)
	if rc.is_empty(): return
	var pts: PackedVector2Array = rc[0]
	var bridges: Array = rc[2] if rc.size() >= 3 else []
	var spts := PackedVector2Array()
	for p in pts:
		spts.append(_screen_of(p * TS))
	if spts.size() < 2: return
	overlay.draw_polyline(spts, Color(0.18, 0.14, 0.10, 0.88), 4.4, true)
	overlay.draw_polyline(spts, col, 1.9, true)
	# draw railroad cross-ties perpendicular to the smooth land curve (skipping straight bridge spans)
	var acc := 4.5
	var step := 9.0
	for m in range(1, spts.size()):
		var w0: Vector2 = pts[m - 1]
		var w1: Vector2 = pts[m]
		var is_br_seg := false
		for br in bridges:
			if w0.distance_to(br[0]) < 0.2 and w1.distance_to(br[1]) < 0.2:
				is_br_seg = true; break
		if is_br_seg: continue
		var p0: Vector2 = spts[m - 1]
		var p1: Vector2 = spts[m]
		var L := p0.distance_to(p1)
		if L < 0.01: continue
		if not _tie_vr.intersects(Rect2(p0, Vector2.ZERO).expand(p1)):  # off-screen: no ties (perf)
			acc = fmod(acc - L, step) + (step if fmod(acc - L, step) < 0.0 else 0.0)
			continue
		var dir := (p1 - p0) / L
		var nrm := Vector2(-dir.y, dir.x) * 3.5
		while acc <= L:
			var pt := p0 + dir * acc
			overlay.draw_line(pt - nrm, pt + nrm, Color(0.92, 0.86, 0.72, 0.78), 1.3)
			acc += step
		acc -= L
	# Draw straight steel-truss bridges over any water crossing spans
	for br in bridges:
		_draw_straight_bridge(_screen_of(br[0] * TS), _screen_of(br[1] * TS), col)


func _q() -> int:
	return clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)

func _sdir(obj: Dictionary, raw: Vector2) -> Vector2:
	if raw == Vector2.ZERO: raw = obj.get("sdir", Vector2.RIGHT)
	if _q() == 0: obj["sdir"] = raw.normalized(); return obj["sdir"]
	var prev: Vector2 = obj.get("sdir", raw)
	var k := 1.0 - exp(-[0.0, 8.0, 7.0, 6.0][_q()] * get_process_delta_time())
	var d := prev.slerp(raw.normalized(), clampf(k, 0.0, 1.0)) if prev.length() > 0.5 else raw.normalized()
	if d == Vector2.ZERO: d = raw.normalized()
	obj["sdir"] = d
	return d

func _wake(p: Vector2, dir: Vector2, sc: float) -> void:
	var q := _q()
	if q == 0: return
	var nrm := Vector2(-dir.y, dir.x)
	var n: int = [0, 3, 5, 8][q]
	for k in n:
		var f := float(k + 1) / float(n)
		var ph := fmod(map_t * 1.6 + f, 1.0)
		var back := p - dir * sc * (0.8 + 2.6 * f)
		var spread := nrm * sc * (0.35 + 1.1 * f) * (1.0 + 0.12 * sin(map_t * 4.0 + k))
		var a := 0.55 * (1.0 - f) * (0.7 + 0.3 * ph)
		overlay.draw_line(back + spread, back + spread * 0.55 + dir * sc * 0.5, Color(1, 1, 1, a), 1.3, q >= 2)
		overlay.draw_line(back - spread, back - spread * 0.55 + dir * sc * 0.5, Color(1, 1, 1, a), 1.3, q >= 2)
	if q >= 2:
		overlay.draw_line(p - dir * sc * 0.6, p - dir * sc * 3.2, Color(0.85, 0.95, 1.0, 0.28), sc * 0.35, true)

# fading wake behind a moving ship (world = TS-pixel position); the trail is kept on the unit dict
func _wake_trail(u: Dictionary, world: Vector2, width: float) -> void:
	if _q() == 0: return
	var tr: PackedVector2Array = u.get("trail", PackedVector2Array())
	if tr.is_empty() or tr[tr.size() - 1].distance_to(world) > TS * 0.6:
		tr.append(world)
		if tr.size() > 22: tr.remove_at(0)
		u["trail"] = tr
	var n := tr.size()
	if n < 1: return
	var prev := _screen_of(tr[0])
	for i in range(1, n):
		var cur := _screen_of(tr[i])
		var f := float(i) / float(n)
		overlay.draw_line(prev, cur, Color(1, 1, 1, 0.42 * f), maxf(1.0, width * (0.35 + 0.65 * f)), true)
		prev = cur
	overlay.draw_line(prev, _screen_of(world), Color(1, 1, 1, 0.42), width, true)

func _warship_click() -> bool:
	var mp := get_viewport().get_mouse_position()
	var best = null
	var bd := 18.0
	for ws in warships:
		if ws.o != PLAYER: continue
		var d := _screen_of(ws.pos * TS).distance_to(mp)
		if d < bd: bd = d; best = ws
	if best != null:
		sel_ws = best
		notify("Warship selected: click the sea to move it", "info")
		return true
	if sel_ws == null: return false
	if not SimWarships.has_ref(warships, sel_ws):
		sel_ws = null; return false
	var t := _mouse_tile()
	if t < 0 or owner_map[t] != WATER:
		sel_ws = null  # land click: deselect and let the click act normally
		return false
	var err := order_warship(sel_ws, t)
	if err != "": notify(err, "bad")
	else: sfx("click")
	return true

# move order for a warship to a water tile; "" on success, else the reason
func order_warship(ws: Dictionary, t: int) -> String:
	if t < 0 or t >= W * H or owner_map[t] != WATER: return "Warships can only sail on water"
	var p := Vector2(t % W + 0.5, t / W + 0.5)
	if sim_ws._body_at(p) != sim_ws._body_at(ws.pos): return "That water is not reachable by this warship"
	ws.tgt = p; ws.patrol = p
	ws.manual = sim_atk.tick
	if ws.state != 0: ws.state = 0; ws.port = null
	sim_ws.tref.erase(int(ws.uid))
	return ""
