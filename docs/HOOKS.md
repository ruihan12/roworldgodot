# Hooks for main.gd (not applied; for the main.gd owner)

Purpose: add a third PLAY SOLO tab, "ROWORLD MAPS (8)" (map_tab == 2), backed by sim/upstream_maps.gd. The 12 real-world maps and the Random tab are untouched.

Exact diff: `docs/hooks_main.patch` against the current /workspace/fc_port/frontline-godot/main.gd. It applies cleanly (`patch -p1 --dry-run` OK). Apply it with `cd frontline-godot && patch -p1 < docs/hooks_main.patch`.

Validated on a scratch copy (/tmp/hooktest, Godot 4.3 headless, `--maptest` limited to tab 2):

| map | gen ms | land tiles | nations (incl. tribes) |
| --- | --- | --- | --- |
| World | 2613 | 386,774 (before Antarctica; now 553,514) | 470 |
| Asia | 2968 | 1,636,701 | 466 |
| Africa | 2919 | 1,394,759 | 447 |
| Onion | 3086 | 1,670,962 | 405 |

The tab switch took 72 ms and there were no script errors.

What it changes (10 small edits):
1. After `const RealMaps := preload(...)`, it adds `const UpstreamMaps := preload("res://sim/upstream_maps.gd")` and a lazy `_upstream_menu()`.
2. `_real_map(k)` returns `UpstreamMaps.real_map_at(k)` when `map_tab == 2`. The entry has the same shape as RealMaps entries: `{id, name, k_lin, b64, nations, land}`.
3. `_get_handcrafted_map_bytes(k)` returns `UpstreamMaps.codes_at(k)` when `map_tab == 2`. The loader caches it, separate from the tab-0 cache.
4. `gen_map()`: the three `map_tab == 0` tests that read real-map bytes, nations and k_lin become `map_tab != 1`.
5. `_active_map_entry` and `_refresh_map_tab_cards` read the table as `_upstream_menu()` on tab 2.
6. `_refresh_map_tab_cards` hides cards beyond the table size (8 of 12 shown on tab 2) and builds tab-2 previews synchronously.
7. `_map_preview` on tab 2 returns `UpstreamMaps.preview_texture(...)`, which uses the upstream terrain palette.
8. `_map_sub` on tab 2 shows "RoWorld map · N nations + T tribes".
9. `_set_map_tab` clamps to 0..2 and clamps map_i to the tab's size.
10. Play dialog: a new tab button at (460, 80) 196x28, and REROLL moves from x 464 to 668.

Not needed: nation colours. Flags match RealMaps.NATION_COLORS keys; Onion has empty flags, so it uses random colours. Range and land-width code works unchanged because it measures land.

Packaging: maps/upstream/*.bin and *.json are read with FileAccess. Running from the project (editor or `godot --path`) needs nothing more. If the project is ever exported, add `maps/upstream/*.bin, maps/upstream/*.json` to the export preset's include_filter (there is no export_presets.cfg yet). The zip builder can skip `maps/upstream/previews` (doc images, 1.1 MB).

Data size added: 3.0 MB of .bin/.json, which is about 0.45 MB codes + 2.3 MB full tile bytes + JSON. If size matters, `*.tiles.bin` can be left out. The loader only needs it for `preview_texture()` and `tiles()`, so in that case switch previews to codes.

Inline diff:

```diff
--- a/main.gd	2026-11-09 21:55:57.876010805 -0500
+++ b/main.gd	2026-11-09 21:56:04.379791378 -0500
@@ -389,6 +389,11 @@
 var _cached_map_bytes := {}
 # ---- RoWorld port (stage 1): real map data + faithful simulation modules ----
 const RealMaps := preload("res://sim/real_maps.gd")
+const UpstreamMaps := preload("res://sim/upstream_maps.gd")  # map_tab 2: RoWorld maps (maps/upstream/)
+var _up_menu := []
+func _upstream_menu() -> Array:
+	if _up_menu.is_empty(): _up_menu = UpstreamMaps.menu_entries()
+	return _up_menu
 const RW_MAP_FOR := {0: 0, 1: 1, 2: 6, 3: 2, 4: 3, 5: 4, 6: 5, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11}  # MAPS index -> RealMaps.MAPS index
 const DEFAULT_K_LIN := 1.1161  # 1792 tiles across = RoWorld's 2000-wide world
 var sim_rules := SimRules.new(DEFAULT_K_LIN)
@@ -403,6 +408,7 @@
 var real_nations := []
 
 func _real_map(k: int) -> Dictionary:
+	if map_tab == 2: return UpstreamMaps.real_map_at(k)
 	if RW_MAP_FOR.has(k): return RealMaps.MAPS[RW_MAP_FOR[k]]
 	return {}
 
@@ -435,6 +441,7 @@
 	return _adj_to(tile, id) or owner_map[tile] == id
 
 func _get_handcrafted_map_bytes(k: int) -> PackedByteArray:
+	if map_tab == 2: return UpstreamMaps.codes_at(k)
 	var idx := clampi(k, 0, HANDCRAFTED_MAPS.size() - 1)
 	if _cached_map_bytes.has(idx):
 		return _cached_map_bytes[idx]
@@ -448,7 +455,9 @@
 	return raw
 
 func _map_sub(k: int, tab: int) -> String:
-	var rm := _real_map(k) if tab == 0 else {}
+	var rm := _real_map(k) if tab != 1 else {}
+	if tab == 2 and not rm.is_empty():
+		return "RoWorld map  ·  %d nations + %d tribes" % [rm.nations.size(), SimRules.DEFAULT_TRIBES]
 	if not rm.is_empty() and rm.nations.is_empty():
 		return "Real map  ·  ~40 nations + %d tribes" % SimRules.DEFAULT_TRIBES
 	if not rm.is_empty():
@@ -456,7 +465,7 @@
 	return "%d × %d  ·  ~40 nations + %d tribes" % [W, H, SimRules.DEFAULT_TRIBES]
 
 func _active_map_entry(k: int) -> Array:
-	var tbl := RANDOM_MAPS if map_tab == 1 else MAPS
+	var tbl: Array = _upstream_menu() if map_tab == 2 else (RANDOM_MAPS if map_tab == 1 else MAPS)
 	return tbl[clampi(k, 0, tbl.size() - 1)]
 
 var _gt_t := 0
@@ -493,8 +502,8 @@
 	fallout_t.resize(W * H); fallout_t.fill(0.0)
 	var elev := PackedFloat32Array(); elev.resize(W * H)
 	land_total = 0; _land_w = -1.0
-	var raw_bytes := _get_handcrafted_map_bytes(map_i) if map_tab == 0 else PackedByteArray()
-	var rmap := _real_map(map_i) if map_tab == 0 else {}
+	var raw_bytes := _get_handcrafted_map_bytes(map_i) if map_tab != 1 else PackedByteArray()
+	var rmap := _real_map(map_i) if map_tab != 1 else {}
 	sim_rules.tile_norm = TILE_NORM
 	sim_rules.set_k(float(rmap.k_lin) if not rmap.is_empty() else DEFAULT_K_LIN)
 	real_nations = rmap.nations if not rmap.is_empty() else []
@@ -509,7 +518,7 @@
 		_redraw_all()
 		_gt("redraw")
 		return
-	if map_tab == 0 and raw_bytes.size() == W * H:
+	if map_tab != 1 and raw_bytes.size() == W * H:
 		var jimg := n3.get_image(W, H, false, false, false).get_data()  # L8, noise*0.5+0.5
 		for i in W * H:
 			var code: int = raw_bytes[i]
@@ -5201,6 +5210,7 @@
 	return l
 
 func _map_preview(k: int, pw: int, ph: int) -> ImageTexture:
+	if map_tab == 2: return UpstreamMaps.preview_texture(UpstreamMaps.id_at(k), pw, ph)
 	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
 	if map_tab == 0:
 		var raw_bytes := _get_handcrafted_map_bytes(k)
@@ -5350,8 +5360,12 @@
 	tab_rand.position = Vector2(256, 80); tab_rand.size = Vector2(196, 28)
 	tab_rand.add_theme_font_size_override("font_size", 12)
 	p.add_child(tab_rand)
-	map_tab_btns = [tab_real, tab_rand]
-	reroll_btn = _card_btn(p, Rect2(464, 80, 164, 28))
+	var tab_up := _btn("ROWORLD MAPS (%d)" % UpstreamMaps.count(), false)
+	tab_up.position = Vector2(460, 80); tab_up.size = Vector2(196, 28)
+	tab_up.add_theme_font_size_override("font_size", 12)
+	p.add_child(tab_up)
+	map_tab_btns = [tab_real, tab_rand, tab_up]
+	reroll_btn = _card_btn(p, Rect2(668, 80, 164, 28))
 	reroll_btn.text = "REROLL RANDOM SEEDS"
 	reroll_btn.add_theme_font_override("font", f_bold)
 	reroll_btn.add_theme_font_size_override("font_size", 11)
@@ -5362,6 +5376,7 @@
 		_refresh_map_tab_cards())
 	tab_real.pressed.connect(func(): _set_map_tab(0))
 	tab_rand.pressed.connect(func(): _set_map_tab(1))
+	tab_up.pressed.connect(func(): _set_map_tab(2))
 	for k in MAPS.size():
 		var col_i := k % 4
 		var row_i := k / 4
@@ -5403,7 +5418,8 @@
 	st.pressed.connect(_start_game_ui)
 
 func _set_map_tab(t_idx: int) -> void:
-	map_tab = clampi(t_idx, 0, 1)
+	map_tab = clampi(t_idx, 0, 2)
+	map_i = clampi(map_i, 0, (UpstreamMaps.count() if map_tab == 2 else MAPS.size()) - 1)
 	if map_tab == 1 and rand_seed_off == 0:
 		rand_seed_off = rng.randi_range(100, 999999)
 	for j in map_tab_btns.size():
@@ -5430,17 +5446,19 @@
 	return _preview_blank
 
 func _refresh_map_tab_cards() -> void:
-	var tbl := RANDOM_MAPS if map_tab == 1 else MAPS
+	var tbl: Array = _upstream_menu() if map_tab == 2 else (RANDOM_MAPS if map_tab == 1 else MAPS)
 	_pv_job = {}
 	_preview_queue.clear()
 	for k in map_cards.size():
+		map_cards[k].visible = k < tbl.size()
+		if k >= tbl.size(): continue
 		map_card_title[k].text = tbl[k][0]
 		map_card_sub[k].text = _map_sub(k, map_tab)
 		_card_style(map_cards[k], k == map_i)
 		var key := _preview_key(k)
 		if _preview_cache.has(key):
 			map_card_tex[k].texture = _preview_cache[key]
-		elif map_tab == 0:
+		elif map_tab != 1:
 			var tex := _map_preview(k, 148, 82)
 			_preview_cache[key] = tex
 			map_card_tex[k].texture = tex
```

Status: applied to main.gd by the sim worker on Nov 09 22:02 (patch -p1, clean; import clean). Backup of pre-hook main.gd: /workspace/main.gd.bak_prehook.

## Snow (Antarctica) hook, 2026-11-09

Upstream World now keeps Antarctica as code 4 "snow" in maps/upstream/world.codes.bin. Snow = plains for gameplay (mtn 0, elev 0.10), drawn white. Also routes the tab-0 World (real_maps World, which cuts Antarctica at row 845) to the upstream World, so every World in the port has Antarctica and its 3 aq spawns. real_maps.gd itself is untouched.

Apply on the hooked main.gd: `patch -p1 < docs/hooks_snow.patch` (dry-run clean against main.gd as of 22:09 Nov 09), or `python3 tools/apply_snow_hooks.py main.gd` (anchor-based, idempotent). 8 edits:

1. after `var real_nations := []`: `var snow_src := PackedByteArray()` and `const SNOW_COL := Color8(0xF4, 0xF7, 0xFA)`
2. `_real_map`: `if map_tab == 0 and k == 0: return UpstreamMaps.as_real_map("world")`
3. gen_map, after `var rmap := ...`: `snow_src = raw_bytes`
4. gen_map decode: `if code == 4: mtn[i] = 0; elev[i] = 0.10 + jitter` before `elif code >= 3:`
5. `_rw_terrain_all`: `elif snow_src.size() == N and snow_src[i] == 4: bc[i] = SNOW_COL` before `elif shore`
6. `_rw_terrain`: `if snow_src.size() == W * H and snow_src[i] == 4: return SNOW_COL` before the shore return
7. low-quality base colours: `elif owner_map[i] != WATER and snow_src.size() == W * H and snow_src[i] == 4: c = SNOW_COL`
8. hover tooltip: snow tiles read "Snow (plains rules: loss 80, cost 16.5)"

`_map_preview` needs no change (code >= 3 is already white). Only mtn[] drives attacks/rules, so snow plays exactly like plains.

Verified on /tmp/hooktest (`--snowtest`): tab 2 and tab 0 World land 553,514, snow 166,781, snow tiles with mtn != 0: 0, 3 aq spawns, tribes/nations spawn on snow; player spawned on snow (44 tiles) and attacked neutral snow 44 -> 505; attack on West Antarctica took its snow tiles 36 -> 0. Shots: /workspace/shots/upstream_maps/33_world_antarctica_tab0_start.png, 33_world_antarctica_tab2_start.png, 33_world_antarctica_conquest.png.
