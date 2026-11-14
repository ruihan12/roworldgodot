extends Node2D
# Frontline Conquest - original prototype. All visuals generated in code.

const W := 1792
const H := 1600
const TS := 2.0  # pixels per tile
const WATER := -1
const ICE := -2
const NEUTRAL := 0
const PLAYER := 1
const SHARES := [0.10, 0.25, 0.35, 0.50, 0.75]
const DIFFS := [["Relaxed", 300.0], ["Standard", 180.0], ["Brutal", 120.0]]  # RoWorld HUMAN_GRACE_TICKS / 10
const MAPS := [
	["World", 4111, 0.04, 260],
	["Europe", 6317, 0.04, 240],
	["Mediterranean", 5209, 0.02, 220],
	["Asia", 7411, 0.05, 250],
	["North America", 8521, 0.03, 210],
	["South America", 5419, 0.03, 200],
	["Africa", 6529, 0.03, 230],
	["Middle East Crossroads", 9631, 0.01, 220],
	["Southeast Asia", 7643, 0.06, 240],
	["British Isles & North Sea", 8753, 0.04, 190],
	["Caribbean & Gulf", 9863, 0.05, 200],
	["Aegean & Black Sea", 3967, 0.03, 230]
]
const RANDOM_MAPS := [
	["Pangaea Isles", 1101, 0.0, 180],
	["Twin Continents", 2207, 0.06, 210],
	["Shattered Sea", 3313, 0.15, 280],
	["Continental Fractures", 4111, 0.04, 250],
	["Inner Sea & Peninsulas", 5209, 0.02, 220],
	["Northern Fjords & Isles", 6317, 0.04, 240],
	["Crescent Bay & Arc", 7411, 0.05, 240],
	["Great Gulf & Isthmus", 8521, 0.03, 210],
	["Three Seas Crossroads", 9631, 0.01, 220],
	["Ring Atoll", 1741, 0.08, 200],
	["Inland Sea", 2853, 0.02, 240],
	["Four Corners", 3967, 0.07, 260]
]
var map_tab := 0  # 0 = Real-World Maps, 1 = Random Maps
var rand_seed_off := 0
var map_tab_btns := []
var reroll_btn: Button
var map_card_tex := []
var map_card_title := []
var map_card_sub := []
const NAVY := Color(0.07, 0.09, 0.16, 0.94)
const ORANGE := Color(0.95, 0.52, 0.12)

var owner_map := PackedInt32Array()
var base_col := PackedColorArray()
var boats := []
var overlay: Control
var drag_from := Vector2.ZERO
var dragging := false
var lpress := false
var shots_dir := "/workspace/shots"
var img: Image
var tex: ImageTexture
var sprite: Sprite2D
const CW := 128
const CH := 160
var chunk_img := []
var chunk_tex := []
var chunk_sp := []
var chunk_dirty := PackedByteArray()
var elev_map := PackedFloat32Array()
var coast_dist := PackedInt32Array()
var settings_status_lbl: Label
var menu_settings_sub: Label
var uploads := 0
var cam: Camera2D
var dirty := false
var land_total := 0
var grow_n := PackedByteArray()  # per-match low-frequency growth noise (0..255, mean ~128)

var nations := []  # index = id; dict
var attacks := []  # {a,t,troops,frontier:Array,idx}
var state := "menu"  # menu, pick, play, over
var deploy_t := 0.0
var peace := 180.0
var elapsed := 0.0
var share_i := 1
var diff_i := 1
var map_i := 0
var start_tile := -1
var rng := RandomNumberGenerator.new()
var ai_timer := 0.0
var ui_timer := 0.0
var tick_acc := 0.0
var autoshot := false
var bench := false
var bench_i := -1
var bench_t := 0.0
var bench_frames := 0
var bench_us := 0
var bench_max := 0
var ticks_done := 0
var prof := {"atk": 0, "eco": 0, "boat": 0, "ai": 0, "ai_max": 0}
var bench_ticks0 := 0
var shot_t := 0.0

# UI
var ui: CanvasLayer
var menu_panel: Control
var play_dialog: Control
var pick_panel: Panel
var pick_title: Label
var pick_sub: Label
var pick_ring: Control
var f_reg: Font
var f_bold: FontVariation
var f_head: FontVariation
var tipc: Control
var tip_data := {}
var top_left_head: Label
var top_timer: Label
var top_bar_ctl: Control
var top_you: Label
var top_lead: Label
var lb_alive: Label
var lb_rows := []
var lb_me := []
var lb_dots: Label
var atk_count: Label
var atk_rows := []
var atk_empty: Label
var bb_name_sub: Label
var bb_regen: Label
var bb_troops: Label
var bb_cap: Label
var bb_bar: Control
var bb_war: Label
var bb_share: Label
var bb_sends: Label
var bb_gold: Label
var bb_goldrate: Label
var slot_price := []
var map_cards := []
var share_hl: Panel
var shown_troops := 0.0
var shown_gold := 0.0
var tip_was_visible := false
var diff_cards := []
var pick_label: Label
var top_bar: Control
var peace_label: Label
var ctrl_bar: ProgressBar
var ctrl_label: Label
var lb_panel: PanelContainer
var lb_label: RichTextLabel
var atk_box: VBoxContainer
var atk_panel: PanelContainer
var troop_label: Label
var gold_label: Label
var share_btns := []
var tooltip: PanelContainer
var tip_label: Label
var help_panel: PanelContainer
var over_panel: PanelContainer
var over_label: Label
var hud_nodes := []
var build_data := []
var build_btns := []
var mtn := PackedByteArray()
var structs := []  # {k, tile, o}
var build_sel := -1
var sim_speed := 1.0
var speed_btns := []
const SPEEDS := [1.0, 2.0, 5.0, 10.0]
const SPEED_BASE := 0.2  # new 1x == old 0.2x
var boat_speed := 1.5  # multiplier on RoWorld ship speed (1 full-size tile/tick); 1.5x boost kept per user
const AI_BOAT_CAP := 12
const MAX_TICKS_PER_FRAME := 12
const AI_BUDGET_US := 2500
var ai_cursor := 2
var path_fail := {}
var bfs_par := PackedInt32Array()
var bfs_stamp := PackedInt32Array()
var bfs_gen := 0
var path_cache := {}
var boat_launched_frame := false
var ov_t := 0.0
var _last_cam := Vector2.ZERO
var _last_zoom := Vector2.ONE
var build_tip: PanelContainer
var build_tip_lbl: RichTextLabel
var tip_slot := -1
const FUNCTIONAL := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

func _ready() -> void:
	autoshot = "--autoshot" in OS.get_cmdline_user_args()
	_sfx_log = "--sfxlog" in OS.get_cmdline_user_args()
	bench = "--bench" in OS.get_cmdline_user_args()
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--pace="): _pace = {"init": true}
	rng.randomize()
	if autoshot or bench: save_path = "user://save_test.json"
	Engine.max_fps = 180
	load_save()
	RenderingServer.set_default_clear_color(Color(0.20, 0.42, 0.62))
	if autoshot: Engine.time_scale = 4.0
	# map split into chunk textures; only dirty chunks are uploaded each frame
	for cy in H / CH:
		for cx in W / CW:
			var im := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
			var tx := ImageTexture.create_from_image(im)
			var sp := Sprite2D.new(); sp.texture = tx; sp.centered = false
			sp.scale = Vector2(TS, TS); sp.position = Vector2(cx * CW, cy * CH) * TS
			sp.material = _map_material()
			add_child(sp)
			chunk_img.append(im); chunk_tex.append(tx); chunk_sp.append(sp)
	chunk_dirty.resize(chunk_img.size()); chunk_dirty.fill(0)
	cam = Camera2D.new()
	add_child(cam)
	cam.position = Vector2(W, H) * TS / 2
	cam.zoom = Vector2(1.2, 1.2)
	_build_ui()
	set_icbm(bool(save.get("settings", {}).get("icbm", false)))
	ui.layer = 2
	var ol := CanvasLayer.new(); ol.layer = 1; add_child(ol)
	overlay = Control.new(); overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ol.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots_dir = a.substr(8)
	gen_map()
	sim_atk = SimAttacks.new(self, sim_rules)
	sim_ai = SimAI.new(self, sim_rules)
	sim_struct = SimStructures.new(self, sim_rules)
	apply_settings(false)
	_init_audio()
	if "--maptest" in OS.get_cmdline_user_args(): _maptest.call_deferred()
	if "--rangetest" in OS.get_cmdline_user_args(): _rangetest.call_deferred()
	if "--rangetest2" in OS.get_cmdline_user_args(): _rangetest2.call_deferred()
	if "--idletest" in OS.get_cmdline_user_args(): _idletest.call_deferred()
	if "--bordershot" in OS.get_cmdline_user_args(): _bordershot.call_deferred()
	if "--stress" in OS.get_cmdline_user_args(): _stress.call_deferred()
	if "--hudshot" in OS.get_cmdline_user_args(): _hudshot.call_deferred()
	if "--audiotest" in OS.get_cmdline_user_args(): _audiotest.call_deferred()
	if "--regress" in OS.get_cmdline_user_args(): _regress.call_deferred()
	if "--speedshot" in OS.get_cmdline_user_args(): _speedshot.call_deferred()

# ---------------- map ----------------
var map_mat: ShaderMaterial
const MAP_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform int quality = 3;
uniform float t_anim = 0.0;
varying vec2 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p, int oct) { float a = 0.5; float r = 0.0; for (int k = 0; k < 6; k++) { if (k >= oct) break; r += a * vn(p); p = p * 2.03 + 7.1; a *= 0.5; } return r; }
#define tx(c, sz) texelFetch(TEXTURE, clamp(c, ivec2(0), sz - ivec2(1)), 0)
void fragment() {
	ivec2 sz = textureSize(TEXTURE, 0);
	vec2 p = UV * vec2(sz);
	vec4 nearest = tx(ivec2(floor(p)), sz);
	if (quality == 0 || quality >= 2) { COLOR = vec4(nearest.rgb, 1.0); }
	else {
		vec2 q = p - 0.5; ivec2 i0 = ivec2(floor(q)); vec2 f = fract(q);
		vec4 a = tx(i0, sz), b = tx(i0 + ivec2(1, 0), sz), c = tx(i0 + ivec2(0, 1), sz), d = tx(i0 + ivec2(1, 1), sz);
		float wa = (1.0 - f.x) * (1.0 - f.y), wb = f.x * (1.0 - f.y), wc = (1.0 - f.x) * f.y, wd = f.x * f.y;
		// alpha class: water ~0.5, land 1.0, owned interior 0.94, owned border 0.86
		float ma = step(0.7, a.a), mb = step(0.7, b.a), mc = step(0.7, c.a), md = step(0.7, d.a);
		float land = wa * ma + wb * mb + wc * mc + wd * md;
		vec3 lc = (a.rgb * wa * ma + b.rgb * wb * mb + c.rgb * wc * mc + d.rgb * wd * md) / max(land, 1e-4);
		vec3 wcol = (a.rgb * wa * (1.0 - ma) + b.rgb * wb * (1.0 - mb) + c.rgb * wc * (1.0 - mc) + d.rgb * wd * (1.0 - md)) / max(1.0 - land, 1e-4);
		if (land < 0.001) lc = wcol; if (land > 0.999) wcol = lc;
		float bord = wa * step(a.a, 0.9) * ma + wb * step(b.a, 0.9) * mb + wc * step(c.a, 0.9) * mc + wd * step(d.a, 0.9) * md;
		float aa = max(fwidth(land), 1e-3);
		float mland = (quality == 1) ? land : smoothstep(0.5 - aa, 0.5 + aa, land);
		vec2 w = wpos;
		if (quality >= 2) {
			int oct = quality == 3 ? 5 : 3;
			float n = fbm(w * 0.45, oct);
			float nx = fbm(w * 0.45 + vec2(0.35, 0.0), oct) - n, ny = fbm(w * 0.45 + vec2(0.0, 0.35), oct) - n;
			float shade = clamp(1.0 + (-nx - ny) * (quality == 3 ? 1.7 : 1.1), 0.88, 1.12);
			float own = 1.0 - smoothstep(0.96, 0.99, (a.a * wa + b.a * wb + c.a * wc + d.a * wd));
			lc *= mix(shade * (0.96 + 0.08 * fbm(w * 1.7, 3)), 1.0 + (shade - 1.0) * 0.45, own);
			float tt = t_anim;
			float wv = fbm(w * 0.35 + vec2(tt * 0.35, tt * 0.22), oct) + 0.5 * fbm(w * 0.7 - vec2(tt * 0.3, -tt * 0.17), 3);
			wcol *= 0.93 + 0.12 * wv;
			if (quality == 3) {
				float gl = pow(max(0.0, sin(w.x * 0.9 + w.y * 0.6 + tt * 2.0 + 6.0 * vn(w * 0.4))), 40.0) * vn(w * 0.3 + tt * 0.2);
				wcol += vec3(0.20, 0.25, 0.28) * gl * 0.22;
			}
			// shoreline foam band (animated)
			float shore = 1.0 - smoothstep(0.0, 0.42, abs(land - 0.5));
			float foam = shore * (0.55 + 0.45 * sin(tt * 2.5 + fbm(w * 1.5, 3) * 8.0));
			wcol = mix(wcol, vec3(0.93, 0.96, 0.98), foam * (quality == 3 ? 0.5 : 0.3) * (1.0 - mland));
		}
		vec3 col = mix(wcol, lc, mland);
		if (quality >= 2) {
			float bl = smoothstep(0.20, 0.45, bord);
			float pulse = quality == 3 ? (0.75 + 0.25 * sin(t_anim * 3.0)) : 1.0;
			col = mix(col, col * 0.62, bl * pulse * mland);
			col += vec3(0.10) * (smoothstep(0.05, 0.22, bord) - bl) * float(quality == 3) * mland;
			// coastline dark rim
			col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, aa * 2.5 + 0.03, abs(land - 0.5)));
		}
		COLOR = vec4(col, 1.0);
	}
}
"""

func _map_material() -> ShaderMaterial:
	if map_mat == null:
		var sh := Shader.new(); sh.code = MAP_SHADER
		map_mat = ShaderMaterial.new(); map_mat.shader = sh
	return map_mat

func _sample_map_elev(k: int, x: float, y: float, n: FastNoiseLite, n2: FastNoiseLite, pa := INF, pb := INF) -> float:
	var m = MAPS[clampi(k, 0, MAPS.size() - 1)]
	var dx := (x - W / 2.0) / (W / 2.0)
	var dy := (y - H / 2.0) / (H / 2.0)
	var r2 := dx * dx + dy * dy
	var nx := x * 640.0 / W; var ny := y * 640.0 / W
	var va: float = pa if pa != INF else n.get_noise_2d(nx, ny)
	var vb: float = pb if pb != INF else n2.get_noise_2d(nx, ny)
	var nv: float = va + vb * (0.08 + float(m[2]))
	var shape := 0.25 - 0.35 * r2 - float(m[2])
	match k:
		1:  # Twin Continents: West & East landmasses separated by a central strait
			var d1 := (dx + 0.48) * (dx + 0.48) * 1.8 + dy * dy * 1.1
			var d2 := (dx - 0.48) * (dx - 0.48) * 1.8 + dy * dy * 1.1
			shape = 0.30 - minf(d1, d2) * 0.52 - exp(-dx * dx * 32.0) * 0.28
		2:  # Shattered Sea: Archipelago of island chains
			shape = 0.14 - 0.26 * r2 + 0.18 * sin(dx * 7.5) * cos(dy * 6.5)
		3:  # World Continents: Americas left, Eurasia + Africa right
			var amer := exp(-pow((dx + 0.52 + 0.12 * dy) / 0.26, 2.0) - pow(dy / 0.78, 2.0)) * 0.58
			var eura := exp(-pow((dx - 0.36) / 0.46, 2.0) - pow((dy + 0.26) / 0.48, 2.0)) * 0.62
			var afri := exp(-pow((dx - 0.14) / 0.24, 2.0) - pow((dy - 0.34) / 0.44, 2.0)) * 0.56
			var austr := exp(-pow((dx - 0.66) / 0.18, 2.0) - pow((dy - 0.55) / 0.20, 2.0)) * 0.48
			shape = maxf(maxf(amer, eura), maxf(afri, austr)) - 0.30 - 0.12 * r2
		4:  # Mediterranean: Land ring around a central elongated sea with peninsulas
			var sea := exp(-pow(dx / 0.68, 2.0) - pow((dy - 0.05) / 0.34, 2.0)) * 0.62
			var italy := exp(-pow((dx + 0.05 - dy * 0.3) / 0.09, 2.0) - pow((dy + 0.08) / 0.28, 2.0)) * 0.46
			var greece := exp(-pow((dx - 0.28) / 0.10, 2.0) - pow((dy + 0.06) / 0.25, 2.0)) * 0.42
			shape = 0.34 - sea + maxf(italy, greece) - 0.18 * r2
		5:  # Europe & Isles: Mainland south/east, Scandinavia north, British Isles west
			var main_eu := clampf((dx + 0.35) * 0.5 + (dy - 0.05) * 0.6, -0.3, 0.42)
			var scand := exp(-pow((dx - 0.05) / 0.24, 2.0) - pow((dy + 0.55) / 0.28, 2.0)) * 0.52
			var uk := exp(-pow((dx + 0.55) / 0.16, 2.0) - pow((dy + 0.12) / 0.26, 2.0)) * 0.48
			shape = maxf(main_eu, maxf(scand, uk)) - 0.08 - 0.22 * r2
		6:  # East Asia & Arc: Continental mainland west + curved island arc east
			var main_as := clampf(0.28 - (dx + 0.18) * 0.75, -0.4, 0.38) - 0.22 * dy * dy
			var arc_r := sqrt(pow(dx + 0.15, 2.0) + pow(dy, 2.0))
			var jpn := exp(-pow((arc_r - 0.72) / 0.11, 2.0)) * (0.52 if dx > 0.1 else 0.0)
			shape = maxf(main_as, jpn) - 0.04
		7:  # North America: Wide north tapering to southern isthmus + Gulf
			var width_y := 0.58 - 0.28 * (dy + 0.2)
			var cont := 0.36 - pow(dx / maxf(0.18, width_y), 2.0) * 0.32 - 0.18 * dy * dy
			var gulf := exp(-pow((dx - 0.12) / 0.24, 2.0) - pow((dy - 0.45) / 0.25, 2.0)) * 0.52
			shape = cont - gulf
		8:  # Middle East Crossroads: Landmass cut by Red Sea, Persian Gulf & Mediterranean edge
			var red_sea := exp(-pow((dx + 0.28 - dy * 0.35) / 0.09, 2.0) - pow((dy - 0.22) / 0.48, 2.0)) * 0.58
			var gulf2 := exp(-pow((dx - 0.25 - dy * 0.30) / 0.11, 2.0) - pow((dy - 0.10) / 0.32, 2.0)) * 0.54
			var med_w := exp(-pow((dx + 0.75) / 0.32, 2.0) - pow((dy + 0.25) / 0.42, 2.0)) * 0.55
			shape = 0.32 - red_sea - gulf2 - med_w - 0.14 * r2
		9:  # Ring Atoll: Circular ring continent around a lagoon with a central island
			var rad := sqrt(dx * dx * 0.85 + dy * dy * 1.15)
			var ring := exp(-pow((rad - 0.58) / 0.22, 2.0)) * 0.54
			var center_isle := exp(-pow(rad / 0.16, 2.0)) * 0.46
			shape = maxf(ring, center_isle) - 0.22
		10: # Inland Sea: Continent enclosing a deep inner sea with narrow straits
			var rad2 := sqrt(dx * dx * 0.75 + dy * dy * 1.1)
			var inner_sea := exp(-pow(rad2 / 0.42, 2.0)) * 0.62
			shape = 0.38 - 0.28 * r2 - inner_sea
		11: # Four Corners: 4 continents separated by a cross channel + central hub
			var ch_x := exp(-dx * dx * 38.0) * 0.44
			var ch_y := exp(-dy * dy * 28.0) * 0.44
			var hub := exp(-(dx * dx + dy * dy) * 26.0) * 0.55
			shape = 0.34 - maxf(ch_x, ch_y) + hub - 0.16 * r2
	return nv + shape

const HANDCRAFTED_MAPS := ["", "", "", "", "", "", "", "", "", "", "", ""]  # all 12 now come from sim/real_maps.gd

var _cached_map_bytes := {}
# ---- RoWorld port (stage 1): real map data + faithful simulation modules ----
const RealMaps := preload("res://sim/real_maps.gd")
const RW_MAP_FOR := {0: 0, 1: 1, 2: 6, 3: 2, 4: 3, 5: 4, 6: 5, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11}  # MAPS index -> RealMaps.MAPS index
const DEFAULT_K_LIN := 1.1161  # 1792 tiles across = RoWorld's 2000-wide world
var sim_rules := SimRules.new(DEFAULT_K_LIN)
const TILE_NORM := (640.0 * 352.0) / float(W * H)
var sim_atk: SimAttacks
var sim_ai: SimAI
var sim_struct: SimStructures
var sim_naval: SimNaval
var fallout_count := 0
var real_nations := []

func _real_map(k: int) -> Dictionary:
	if RW_MAP_FOR.has(k): return RealMaps.MAPS[RW_MAP_FOR[k]]
	return {}

var _kind_cache := PackedInt32Array()
func kind_of(id: int) -> int:
	if id < _kind_cache.size(): return _kind_cache[id]
	if id == PLAYER: return SimRules.KIND_HUMAN
	if id > 0 and id < nations.size() and nations[id].get("prot", false): return SimRules.KIND_NATION
	return SimRules.KIND_TRIBE

func _rebuild_kind_cache() -> void:
	_kind_cache.resize(0)
	var kc := PackedInt32Array(); kc.resize(nations.size())
	for id in nations.size(): kc[id] = kind_of(id)
	_kind_cache = kc

# Source intent_attack: attack the owner of `tile` with `ratio` of home troops; over land when the
# attacker borders it, otherwise by transport.
func intent_attack(id: int, tile: int, ratio: float) -> bool:
	if tile < 0 or tile >= W * H: return false
	var o := owner_map[tile]
	if o < 0 or o == id: return false
	if o > 0 and _adj_any(tile, id):
		return launch_attack(id, o, ratio)
	if o == NEUTRAL and _adj_any(tile, id):
		return launch_attack(id, NEUTRAL, ratio)
	return launch_boat(id, tile, ratio if id == PLAYER else SimRules.BOAT_ATTACK_FRACTION, 12000)

func _adj_any(tile: int, id: int) -> bool:
	return _adj_to(tile, id) or owner_map[tile] == id

func _get_handcrafted_map_bytes(k: int) -> PackedByteArray:
	var idx := clampi(k, 0, HANDCRAFTED_MAPS.size() - 1)
	if _cached_map_bytes.has(idx):
		return _cached_map_bytes[idx]
	var rm := _real_map(idx)
	if not rm.is_empty():
		_cached_map_bytes[idx] = Marshalls.base64_to_raw(rm.b64).decompress(W * H, FileAccess.COMPRESSION_DEFLATE)
		return _cached_map_bytes[idx]
	var comp := Marshalls.base64_to_raw(HANDCRAFTED_MAPS[idx])
	var raw := comp.decompress(W * H, FileAccess.COMPRESSION_DEFLATE)
	_cached_map_bytes[idx] = raw
	return raw

func _map_sub(k: int, tab: int) -> String:
	var rm := _real_map(k) if tab == 0 else {}
	if not rm.is_empty() and rm.nations.is_empty():
		return "Real map  ·  ~40 nations + %d tribes" % SimRules.DEFAULT_TRIBES
	if not rm.is_empty():
		return "Real map  ·  %d nations + %d tribes" % [rm.nations.size(), SimRules.DEFAULT_TRIBES]
	return "%d × %d  ·  ~40 nations + %d tribes" % [W, H, SimRules.DEFAULT_TRIBES]

func _active_map_entry(k: int) -> Array:
	var tbl := RANDOM_MAPS if map_tab == 1 else MAPS
	return tbl[clampi(k, 0, tbl.size() - 1)]

var _gt_t := 0
var _gen_cache := {}
var _async_gen := false
func _store_gen_cache() -> void:
	_gen_cache = {"key": "%d|%d|%d|%d" % [map_tab, map_i, (rand_seed_off if map_tab == 1 else 0), _qual()],
		"om": owner_map.duplicate(), "el": elev_map, "mt": mtn.duplicate(), "cd": coast_dist, "bc": base_col,
		"lt": land_total, "body": sim_naval.body, "cl": sim_naval.coast_list}
func _gt(lbl: String) -> void:
	var t := Time.get_ticks_usec()
	if "--maptest" in OS.get_cmdline_user_args() and _gt_t > 0: print("  phase %s %.0f ms" % [lbl, (t - _gt_t) / 1000.0])
	_gt_t = t

func gen_map() -> void:
	_gt_t = Time.get_ticks_usec()
	var m := _active_map_entry(map_i)
	var seed_val: int = int(m[1]) + (rand_seed_off if map_tab == 1 else 0)
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = 0.006
	n.fractal_octaves = 6
	var n2 := FastNoiseLite.new()
	n2.seed = seed_val + 7
	n2.frequency = 0.025
	var n3 := FastNoiseLite.new()
	n3.seed = seed_val + 99
	n3.frequency = 0.04
	n3.fractal_octaves = 3
	owner_map.resize(W * H)
	base_col.resize(W * H)
	mtn.resize(W * H); mtn.fill(0)
	fallout.resize(W * H); fallout.fill(0); fallout_list.clear()
	fallout_t.resize(W * H); fallout_t.fill(0.0)
	var elev := PackedFloat32Array(); elev.resize(W * H)
	land_total = 0; _land_w = -1.0
	var raw_bytes := _get_handcrafted_map_bytes(map_i) if map_tab == 0 else PackedByteArray()
	var rmap := _real_map(map_i) if map_tab == 0 else {}
	sim_rules.tile_norm = TILE_NORM
	sim_rules.set_k(float(rmap.k_lin) if not rmap.is_empty() else DEFAULT_K_LIN)
	real_nations = rmap.nations if not rmap.is_empty() else []
	var gkey := "%d|%d|%d|%d" % [map_tab, map_i, (rand_seed_off if map_tab == 1 else 0), _qual()]
	if _gen_cache.get("key", "") == gkey:
		owner_map = _gen_cache.om.duplicate(); elev_map = _gen_cache.el; mtn = _gen_cache.mt.duplicate()
		coast_dist = _gen_cache.cd; base_col = _gen_cache.bc; land_total = _gen_cache.lt
		if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
		sim_naval.body = _gen_cache.body; sim_naval.coast_list = _gen_cache.cl; sim_naval.trade_cache.clear()
		_gt("cache")
		if _async_gen: await get_tree().process_frame
		_redraw_all()
		_gt("redraw")
		return
	if map_tab == 0 and raw_bytes.size() == W * H:
		var jimg := n3.get_image(W, H, false, false, false).get_data()  # L8, noise*0.5+0.5
		for i in W * H:
			var code: int = raw_bytes[i]
			if code == 0:
				owner_map[i] = WATER
				elev[i] = -0.2
			else:
				owner_map[i] = NEUTRAL
				land_total += 1
				var jitter: float = (jimg[i] / 127.5 - 1.0) * 0.04
				if code >= 3:
					mtn[i] = 2; elev[i] = 0.50 + jitter
				elif code == 2:
					mtn[i] = 1; elev[i] = 0.28 + jitter
				else:
					mtn[i] = 0; elev[i] = 0.10 + jitter
	else:
		# shape evaluated on a 1/4-res grid (normalised coords, same as the thumbnails), upscaled
		# bicubically in C++, plus fine C++ noise for coastline detail at full resolution
		var lw := W / 4; var lh := H / 4
		var lo := PackedFloat32Array(); lo.resize(lw * lh)
		for ly in lh:
			for lx in lw:
				lo[ly * lw + lx] = _sample_map_elev(map_i, (lx + 0.5) * 4.0, (ly + 0.5) * 4.0, n, n2)
			if _async_gen and (ly & 3) == 3:
				_load_progress(0.08 + 0.16 * float(ly) / float(lh))
				await get_tree().process_frame
		var limg := Image.create_from_data(lw, lh, false, Image.FORMAT_RF, lo.to_byte_array())
		limg.resize(W, H, Image.INTERPOLATE_CUBIC)
		var full := limg.get_data().to_float32_array()
		var nf := FastNoiseLite.new(); nf.seed = seed_val + 31; nf.frequency = 0.05; nf.fractal_octaves = 3
		var fimg := nf.get_image(W, H, false, false, false).get_data()
		for y in H:
			var row := y * W
			for x in W:
				var ii := row + x
				var v: float = full[ii] + (fimg[ii] / 127.5 - 1.0) * 0.035
				var o := NEUTRAL if v > 0.0 else WATER
				owner_map[ii] = o
				elev[ii] = v
				if o == NEUTRAL:
					if v > 0.40: mtn[ii] = 2
					elif v > 0.20: mtn[ii] = 1
					land_total += 1
			if _async_gen and (y & 31) == 31:
				_load_progress(0.26 + 0.04 * float(y) / float(H))
				await get_tree().process_frame
	elev_map = elev
	_gt("decode")
	if _async_gen: _load_progress(0.3); await get_tree().process_frame
	# distance to land / water (for coast glow & beaches)
	coast_dist.resize(W * H); coast_dist.fill(99)
	var q := PackedInt32Array(); q.resize(W * H); var qn := 0
	var N := W * H
	var dirs := PackedInt32Array([1, -1, W, -W])
	for i in N:
		if owner_map[i] != WATER:
			for d in dirs:
				var j: int = i + d
				if j >= 0 and j < N and owner_map[j] == WATER and coast_dist[j] == 99:
					coast_dist[j] = 1; q[qn] = j; qn += 1
	var qi := 0
	while qi < qn:
		var i: int = q[qi]; qi += 1
		var cd: int = coast_dist[i]
		if cd >= 12: continue
		for d in dirs:
			var j: int = i + d
			if j >= 0 and j < N and owner_map[j] == WATER and coast_dist[j] == 99:
				coast_dist[j] = cd + 1; q[qn] = j; qn += 1
	_gt("coast")
	if _async_gen: _load_progress(0.45); await get_tree().process_frame
	if sim_naval == null: sim_naval = SimNaval.new(self, sim_rules)
	sim_naval.compute_bodies()
	_gt("bodies")
	if _async_gen: _load_progress(0.65); await get_tree().process_frame
	sim_naval.trade_cache.clear()
	_recompute_base_colors()

func _recompute_base_colors() -> void:
	if owner_map.size() != W * H or elev_map.size() != W * H: return
	var cfg: Dictionary = save.get("settings", {})
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var m := _active_map_entry(map_i)
	var seed_val: int = int(m[1]) + (rand_seed_off if map_tab == 1 else 0)
	var n3 := FastNoiseLite.new()
	n3.seed = seed_val + 99
	n3.frequency = 0.04
	n3.fractal_octaves = 3
	var deep := Color(0.18, 0.39, 0.60) if qual_i >= 3 else Color(0.20, 0.42, 0.62)
	var shallow := Color(0.44, 0.69, 0.84) if qual_i >= 3 else Color(0.42, 0.66, 0.80)
	_qual_c = qual_i
	if qual_i >= 2:
		_rw_terrain_all()
		_gt("colors")
		_store_gen_cache()
		if _async_gen: _load_progress(0.85); await get_tree().process_frame
		_redraw_all()
		_gt("redraw")
		return
	for i in W * H:
		var x := i % W; var y := i / W
		var o := owner_map[i]
		var t: float = (n3.get_noise_2d(x, y) * 0.5 + 0.5) if qual_i >= 1 else 0.5
		var c: Color
		if o == WATER:
			var d_c: int = coast_dist[i] if coast_dist.size() == W * H else 99
			if qual_i == 0:
				# Low quality: flat ocean color
				c = Color(0.22, 0.44, 0.64)
			elif qual_i == 1:
				# Medium quality: 2-step coastal shelf
				c = shallow if d_c <= 2 else deep
			elif qual_i == 2:
				# High quality: smooth coastal shelf + subtle wave texture
				c = deep.lerp(shallow, clampf(1.0 - (d_c - 1) / 9.0, 0.0, 1.0) * 0.8) if d_c < 99 else deep
				c = c.darkened(0.04 * t)
			else:
				# Ultra quality: deep bathymetry + turquoise coral shallows + specular micro-shimmer
				var sh_f := clampf(1.0 - (d_c - 1) / 11.0, 0.0, 1.0)
				c = deep.lerp(shallow, pow(sh_f, 0.85) * 0.88) if d_c < 99 else deep.darkened(0.06)
				if d_c == 1: c = c.lerp(Color(0.56, 0.80, 0.88), 0.35)
				c = c.darkened(0.05 * t)
		else:
			var e := elev_map[i]
			if qual_i == 0:
				# Low quality: flat solid biome colors
				if mtn[i] == 2: c = Color(0.84, 0.84, 0.87)
				elif mtn[i] == 1: c = Color(0.78, 0.71, 0.52)
				else: c = Color(0.66, 0.78, 0.49)
			elif qual_i == 1:
				# Medium quality: basic elevation shading, no beaches
				if mtn[i] == 2: c = Color(0.72, 0.69, 0.65).lerp(Color(0.94, 0.94, 0.96), clampf((e - 0.42) * 4.0, 0.0, 1.0))
				elif mtn[i] == 1: c = Color(0.80, 0.73, 0.54).lerp(Color(0.72, 0.64, 0.46), t * 0.45)
				else: c = Color(0.70, 0.81, 0.52).lerp(Color(0.60, 0.73, 0.45), t * 0.45)
			else:
				# High & Ultra quality: full biome shading + snow peaks + sandy beaches + relief contrast
				if mtn[i] == 2:
					c = Color(0.62, 0.58, 0.53).lerp(Color(0.97, 0.97, 0.99), clampf((e - 0.40) * 5.2, 0.0, 1.0)).darkened(0.07 * t)
				elif mtn[i] == 1:
					c = Color(0.82, 0.75, 0.55).lerp(Color(0.73, 0.64, 0.45), t * 0.65).lerp(Color(0.68, 0.60, 0.46), clampf((e - 0.20) * 3.5, 0.0, 1.0))
				else:
					c = Color(0.72, 0.83, 0.54).lerp(Color(0.56, 0.72, 0.43), t * 0.65)
				var w_adj := 0
				for d in [1, -1, W, -W]:
					if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
					var j: int = i + d
					if j >= 0 and j < W * H and owner_map[j] == WATER: w_adj += 1
				if w_adj > 0:
					c = c.lerp(Color(0.92, 0.88, 0.71), 0.55 if qual_i == 2 else minf(0.78, 0.45 + 0.14 * w_adj))
		if qual_i >= 2: c = _rw_terrain(i)
		base_col[i] = c
	# Software Coastline & Border Anti-Aliasing pass scaled by msaa_i (0 = Off/Sharp, 1 = 2x, 2 = 4x, 3 = 8x)
	if msaa_i > 0 and qual_i < 2:
		var blend_w: float = [0.0, 0.16, 0.28, 0.40][msaa_i]
		var copy_col := base_col.duplicate()
		for i in W * H:
			var x := i % W; var y := i / W
			if x <= 0 or x >= W - 1 or y <= 0 or y >= H - 1: continue
			var o := owner_map[i]
			var diff_nb := false
			var acc_r := 0.0; var acc_g := 0.0; var acc_b := 0.0; var nb_cnt := 0
			for d in [1, -1, W, -W]:
				if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
				var j: int = i + d
				if owner_map[j] != o or mtn[j] != mtn[i]: diff_nb = true
				var nc: Color = copy_col[j]
				acc_r += nc.r; acc_g += nc.g; acc_b += nc.b; nb_cnt += 1
			if diff_nb and nb_cnt > 0:
				var avg_c := Color(acc_r / nb_cnt, acc_g / nb_cnt, acc_b / nb_cnt, 1.0)
				base_col[i] = copy_col[i].lerp(avg_c, blend_w)
	_gt("colors")
	_redraw_all()
	_gt("redraw")

# RoWorld MapSurface.terrain_pixel (src/client/Map/MapSurface.luau): OCEAN #4785b5 darkened by depth,
# shoreline water 0.7*OCEAN+76.5, coastal land SAND #CCCB9E, PLAINS #BEDC8A, HIGHLAND #DCCB9E, MOUNTAIN #e6e6e6.
var _DIRS4 := PackedInt32Array([1, -1, W, -W])
# Fast whole-map version of _rw_terrain (same colours), locals only.
func _rw_terrain_all() -> void:
	var om := owner_map; var cdist := coast_dist; var el := elev_map; var mt := mtn
	var N := W * H
	var bc := PackedColorArray(); bc.resize(N)
	var shore_w := Color8(int(0.7 * 0x47 + 76.5), int(0.7 * 0x85 + 76.5), int(0.7 * 0xB5 + 76.5))
	var sand := Color8(0xCC, 0xCB, 0x9E)
	var ocean := []
	for m in 11: ocean.append(Color8(0x47 - m, 0x85 - m, 0xB5 - m))
	var mtc := []
	for mm in 7: mtc.append(Color8(0xE6 + mm, 0xE6 + mm, 0xE6 + mm))
	var hic := []
	for mh in 10: hic.append(Color8(0xDC + 2 * mh, 0xCB + 2 * mh, 0x9E + 2 * mh))
	var plc := []
	for mp in 10: plc.append(Color8(0xBE, 0xDC - 2 * mp, 0x8A))
	for i in N:
		var o: int = om[i]
		var w := o == WATER
		var x := i % W
		var shore := false
		if x > 0 and (om[i - 1] == WATER) != w: shore = true
		elif x < W - 1 and (om[i + 1] == WATER) != w: shore = true
		elif i >= W and (om[i - W] == WATER) != w: shore = true
		elif i + W < N and (om[i + W] == WATER) != w: shore = true
		if w:
			bc[i] = shore_w if shore else ocean[mini(maxi(cdist[i] - 1, 0), 10)]
		elif shore: bc[i] = sand
		else:
			var e: float = el[i]
			var k: int = mt[i]
			if k == 2: bc[i] = mtc[clampi(int((e - 0.4) * 30.0), 0, 6)]
			elif k == 1: bc[i] = hic[clampi(int((e - 0.2) * 40.0), 0, 9)]
			else: bc[i] = plc[clampi(int(e * 30.0), 0, 9)]
	base_col = bc

var _qual_c := -1
func _rw_terrain(i: int) -> Color:
	var o := owner_map[i]
	var x := i % W
	var shore := false
	for d in _DIRS4:
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
		if (owner_map[j] == WATER) != (o == WATER): shore = true; break
	if o == WATER:
		if shore: return Color8(int(0.7 * 0x47 + 76.5), int(0.7 * 0x85 + 76.5), int(0.7 * 0xB5 + 76.5))
		var dc: int = coast_dist[i] if coast_dist.size() == W * H else 10
		var m := mini(maxi(dc - 1, 0), 10)
		return Color8(0x47 - m, 0x85 - m, 0xB5 - m)
	if shore: return Color8(0xCC, 0xCB, 0x9E)
	var e: float = elev_map[i] if elev_map.size() == W * H else 0.2
	if mtn[i] == 2:
		var mm := clampi(int((e - 0.4) * 30.0), 0, 6)
		return Color8(0xE6 + mm, 0xE6 + mm, 0xE6 + mm)
	if mtn[i] == 1:
		var mh := clampi(int((e - 0.2) * 40.0), 0, 9)
		return Color8(0xDC + 2 * mh, 0xCB + 2 * mh, 0x9E + 2 * mh)
	var mp := clampi(int(e * 30.0), 0, 9)
	return Color8(0xBE, 0xDC - 2 * mp, 0x8A)

func _qual() -> int:
	if _qual_c >= 0: return _qual_c
	return clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)

func _tile_color(i: int) -> Color:
	var c0 := _tile_color_rgb(i)
	var o := owner_map[i]
	if o == WATER: c0.a = 0.5
	elif o > 0:
		var x := i % W
		var bd := false
		for d in [1, -1, W, -W]:
			if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
			var j: int = i + d
			if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
			if owner_map[j] != o: bd = true; break
		c0.a = 0.86 if bd else 0.94
	else: c0.a = 1.0
	return c0

func _tile_color_rgb(i: int) -> Color:
	var o := owner_map[i]
	if _qual() >= 2: return _rw_tile_rgb(i, o)
	if o <= 0:
		if o == NEUTRAL and fallout.size() > i and fallout[i] == 1:
			var h := (i * 2654435761) % 7
			return Color(0.25, 0.62, 0.25) if h < 3 else (Color(0.85, 0.45, 0.2) if h == 3 else base_col[i].lerp(Color(0.3, 0.7, 0.3), 0.6))
		return base_col[i]
	var c: Color = nations[o].color
	var x := i % W
	var diff_cnt := 0
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0): continue
		if owner_map[j] != o:
			diff_cnt += 1
	if diff_cnt > 0:
		var msaa_i := clampi(int(save.get("settings", {}).get("msaa_i", 2)), 0, 3)
		var b_dark: float = 0.32 if msaa_i <= 1 else (0.18 + 0.04 * mini(diff_cnt, 3))
		return c.darkened(b_dark)
	return base_col[i].lerp(c, 0.50)

# RoWorld MapSurface.tile_pixel: fill = owner colour (saturation 0.85) at alpha 150/255 over the terrain,
# border tiles opaque in the owner colour with HSL lightness - 0.125, fallout ground opaque green noise
# (0.05, 0.55, 0.07) + hash * 0.05, glowing lime while fresh (FalloutGlow heat, 150,236,90).
func _rw_tile_rgb(i: int, o: int) -> Color:
	var x := i % W
	if fallout.size() > i and fallout[i] == 1 and o != WATER:
		var y := i / W
		var h := fmod(abs(sin(x * 12.9898 + y * 78.233) * 43758.5453), 1.0) * 0.05
		var g := Color(0.05 + h, 0.55 + h, 0.07 + h)
		var heat := clampf((fallout_t[i] - 34.5) / 25.5, 0.0, 1.0)
		var bx := (x / 4 + (y / 4) * 7) % 5
		if heat > 0.0: g = g.lerp(Color8(150, 236, 90), heat * (0.75 + 0.05 * bx))
		return g
	var tc: Color = base_col[i]
	if o <= 0: return tc
	var nc: Color = nations[o].color
	nc = Color.from_hsv(nc.h, nc.s * 0.85, nc.v)
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j < 0 or j >= W * H or (d == 1 and x == W - 1) or (d == -1 and x == 0) or owner_map[j] != o:
			return _hsl_darken(nations[o].color, 0.125)
	return tc.lerp(nc, 150.0 / 255.0)

func _hsl_darken(c: Color, k: float) -> Color:
	var mx := maxf(c.r, maxf(c.g, c.b)); var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) * 0.5
	var nl := maxf(0.0, l - k)
	if l <= 0.0: return c
	# scale distance from grey proportionally (keeps hue and saturation in HSL)
	var sat := 0.0 if mx == mn else (mx - mn) / (1.0 - absf(2.0 * l - 1.0))
	var ch := (1.0 - absf(2.0 * nl - 1.0)) * sat
	var r := (c.r - mn) / maxf(1e-5, mx - mn); var g := (c.g - mn) / maxf(1e-5, mx - mn); var b := (c.b - mn) / maxf(1e-5, mx - mn)
	var m := nl - ch * 0.5
	return Color(m + r * ch, m + g * ch, m + b * ch)

func _px(x: int, y: int, c: Color) -> void:
	var k := (y / CH) * (W / CW) + x / CW
	chunk_img[k].set_pixel(x % CW, y % CH, c)
	chunk_dirty[k] = 1

func _redraw_all() -> void:
	_pend_paint.clear()
	_qual_c = clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)
	var N := W * H
	var buf := PackedByteArray(); buf.resize(N * 4)
	var hasf := fallout.size() == N
	for i in N:
		var o: int = owner_map[i]
		var c: Color
		if o <= 0 and not (hasf and fallout[i] == 1):
			c = base_col[i]; c.a = 0.5 if o == WATER else 1.0
		else:
			c = _tile_color(i)
		var b := i * 4
		buf[b] = c.r8; buf[b + 1] = c.g8; buf[b + 2] = c.b8; buf[b + 3] = c.a8
	var big := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, buf)
	var cols := W / CW
	for k in chunk_img.size():
		chunk_img[k].blit_rect(big, Rect2i((k % cols) * CW, (k / cols) * CH, CW, CH), Vector2i.ZERO)
		chunk_dirty[k] = 1
	dirty = true

# Repaints are deferred to the next drawn frame so a tile flipped by several captures in one frame
# (its own capture plus neighbours') is coloured once.
var _pend_paint := {}
func _repaint(i: int) -> void:
	_pend_paint[i] = true
	var N := W * H
	if i + 1 < N: _pend_paint[i + 1] = true
	if i >= 1: _pend_paint[i - 1] = true
	if i + W < N: _pend_paint[i + W] = true
	if i >= W: _pend_paint[i - W] = true
	dirty = true
	if _pend_paint.size() > 60000: _flush_paint()

func _flush_paint_budget(n: int) -> bool:
	if _pend_paint.size() <= n: _flush_paint(); return false
	var ks := _pend_paint.keys()
	for m in n:
		var j: int = ks[m]
		_px(j % W, j / W, _tile_color(j))
		_pend_paint.erase(j)
	return true

func _flush_paint() -> void:
	for j in _pend_paint:
		_px(j % W, j / W, _tile_color(j))
	_pend_paint.clear()

# Incremental border sets (owner -> {tile: true}): land tiles with a land 4-neighbour of another owner.
var border := []

func _upd_border(t: int) -> void:
	var o: int = owner_map[t]
	if o <= 0: return
	var x := t % W
	var b := false
	if x > 0 and owner_map[t - 1] != o and owner_map[t - 1] >= 0: b = true
	elif x < W - 1 and owner_map[t + 1] != o and owner_map[t + 1] >= 0: b = true
	elif t >= W and owner_map[t - W] != o and owner_map[t - W] >= 0: b = true
	elif t < W * (H - 1) and owner_map[t + W] != o and owner_map[t + W] >= 0: b = true
	var d: Dictionary = border[o]
	if b: d[t] = true
	else: d.erase(t)

func _set_owner(i: int, o: int) -> void:
	var old: int = owner_map[i]
	if old > 0 and old < border.size(): border[old].erase(i)
	if old > 0:
		nations[old].land -= 1
		nations[old].sx -= i % W; nations[old].sy -= i / W
	owner_map[i] = o
	if old > 0 and o > 0: nations[old]["last_by"] = o
	if struct_at.has(i):
		var st = struct_at[i]
		if o > 0 and o != old:
			_own_sv[st.o] = _own_sv.get(st.o, 0) + 1; st.o = o; _sv += 1; _own_sv[o] = _own_sv.get(o, 0) + 1
			st.hits = 0
			var lvl := int(st.get("level", 1))
			var ltxt := (" Lv%d" % lvl) if lvl > 1 else ""
			var nm: String = build_data[st.k][1] + ltxt
			if o == PLAYER:
				notify("Captured %s from %s!" % [nm, _nname(old)], "good")
				sfx("ka_ching")
				add_float(Vector2(i % W + 0.5, i / W + 0.5) * TS, "Captured %s!" % nm, GREEN)
			elif old == PLAYER:
				notify("%s captured your %s!" % [_nname(o), nm], "bad")
		elif o <= 0:
			_struct_remove(st)
	if o > 0 and fallout.size() > i and fallout[i] == 1:
		fallout[i] = 0; fallout_list.erase(i)
	if o > 0:
		var n = nations[o]
		n.land += 1
		var x := i % W
		var y := i / W
		n.bb = n.bb.merge(Rect2i(x, y, 1, 1)) if n.bb.size != Vector2i.ZERO else Rect2i(x, y, 1, 1)
		n.sx += x; n.sy += y
		if old != o and _q() >= 2 and cap_fx.size() < 6000:
			cap_fx[i] = [map_t, n.color]
	if border.size() == nations.size():
		_upd_border(i)
		var bx := i % W
		if bx > 0: _upd_border(i - 1)
		if bx < W - 1: _upd_border(i + 1)
		if i >= W: _upd_border(i - W)
		if i < W * (H - 1): _upd_border(i + W)
	_repaint(i)

# ---------------- nations ----------------
func _name() -> String:
	var a := ["Kar", "Vel", "Os", "Tam", "Bri", "Nor", "Zan", "Eld", "Mor", "Ash", "Qua", "Ril", "Dun", "Sar", "Hol", "Ter", "Ul", "Fen", "Gal", "Pry"]
	var b := ["avia", "esh", "ora", "undi", "mark", "heim", "ar", "ios", "ett", "anor", "wick", "stan", "ia", "oth", "urra"]
	var pre := ["", "", "", "Free ", "Clan ", "Tribe of ", "", "Old "]
	return pre[rng.randi() % pre.size()] + a[rng.randi() % a.size()] + b[rng.randi() % b.size()]

func _new_nation(nm: String, col: Color, ai: bool) -> int:
	if border.size() != nations.size():
		border.clear()
		for _k in nations.size(): border.append({})
	border.append({})
	nations.append({"name": nm, "color": col, "ai": ai, "land": 0, "troops": 0.0, "gold": 0.0, "bb": Rect2i(), "alive": true, "sx": 0.0, "sy": 0.0, "regen": 0.0, "reinf_cd": 0.0})
	return nations.size() - 1

func _find_spawn_tile(cx: int, cy: int) -> int:
	for r in range(0, 200, 3):
		for k in 40:
			var x := clampi(cx + rng.randi_range(-r, r), 0, W - 1)
			var y := clampi(cy + rng.randi_range(-r, r), 0, H - 1)
			if owner_map[y * W + x] == NEUTRAL:
				return y * W + x
	return -1

func _claim_blob(id: int, c: int, r: int) -> void:
	var cx := c % W
	var cy := c / W
	# slightly irregular blob: radius wobbles +-12% with angle
	var ph := rng.randf() * TAU; var ph2 := rng.randf() * TAU
	for y in range(cy - r - 2, cy + r + 3):
		for x in range(cx - r - 2, cx + r + 3):
			var ang := atan2(float(y - cy), float(x - cx))
			var rr := float(r) * (1.0 + 0.08 * sin(3.0 * ang + ph) + 0.04 * sin(5.0 * ang + ph2))
			if x >= 0 and y >= 0 and x < W and y < H and Vector2(x - cx, y - cy).length() <= rr + 0.3:
				var i := y * W + x
				if owner_map[i] == NEUTRAL:
					_set_owner(i, id)

func _clear_nation(id: int) -> void:
	for i in W * H:
		if owner_map[i] == id:
			_set_owner(i, NEUTRAL)

func _add_shake(amount: float) -> void:
	var sh_i := clampi(int(save.get("settings", {}).get("shake_i", 1)), 0, 2)
	var mult: float = SHAKE_MULT[sh_i]
	if mult <= 0.0: return
	var scaled := amount * mult
	shake_amp = clampf(maxf(shake_amp, scaled) + scaled * 0.22, 0.0, 7.5 * mult)

var _skip_gen := false
var load_ov: Control
var load_bar: ProgressBar
var _loading := false
func _load_progress(v: float) -> void:
	if load_bar: load_bar.value = v * 100.0

func _start_game_ui() -> void:
	if _loading: return
	_loading = true
	if load_ov == null:
		load_ov = ColorRect.new(); (load_ov as ColorRect).color = Color(0.03, 0.05, 0.10, 0.88)
		load_ov.set_anchors_preset(Control.PRESET_FULL_RECT); load_ov.mouse_filter = Control.MOUSE_FILTER_STOP
		ui.add_child(load_ov)
		var lb := _head(load_ov, "LOADING MAP", Vector2(0, 380), 30, TEXT, 1600, HORIZONTAL_ALIGNMENT_CENTER)
		lb.set_meta("t", 1)
		load_bar = ProgressBar.new(); load_bar.position = Vector2(600, 440); load_bar.size = Vector2(400, 18)
		load_bar.show_percentage = false
		load_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.10), 9, Color(0, 0, 0, 0), 0))
		load_bar.add_theme_stylebox_override("fill", _flat(ORANGE_Y, 9, Color(0, 0, 0, 0), 0))
		load_ov.add_child(load_bar)
	load_ov.visible = true; load_ov.move_to_front(); _load_progress(0.05)
	await get_tree().process_frame
	await get_tree().process_frame
	_async_gen = true
	await gen_map()
	_async_gen = false
	_load_progress(1.0)
	await get_tree().process_frame
	_skip_gen = true
	_start_game()
	_skip_gen = false
	load_ov.visible = false
	_loading = false

func _start_game() -> void:
	_ema_init = false
	if not _skip_gen: gen_map()
	var gnz := FastNoiseLite.new(); gnz.seed = randi(); gnz.frequency = 0.012; gnz.fractal_octaves = 2
	grow_n = gnz.get_image(W, H, false, false, true).get_data()
	nations.clear()
	planes.clear(); beams.clear(); air_t = 0.0; rail_cd = 0.0; shake_amp = 0.0; shake_t = 0.0; if cam: cam.offset = Vector2.ZERO
	stats = {"peak": 0.0, "maxtroops": 0.0, "elims": 0}
	attacks.clear()
	boats.clear()
	structs.clear(); _sv += 1
	struct_at.clear(); missiles.clear(); warships.clear(); traders.clear(); blasts.clear(); shells.clear(); notes.clear(); cap_fx.clear()
	trains.clear(); floats.clear(); embargoes.clear(); embargo_all = false; donate_troop_cd = 0.0; donate_gold_cd = 0.0
	allies.clear(); traitor.clear(); ally_warned.clear(); path_cache.clear(); rail_cache.clear(); _rail_nb_cache.clear(); path_fail.clear()
	if diplo_panel: diplo_panel.visible = false
	if ally_card: ally_card.visible = false
	build_sel = -1
	set_speed(0)
	border.clear(); border.append({})
	nations.append({})  # 0 neutral placeholder
	_new_nation("You", Color(0.15, 0.55, 1.0), false)
	_rw_spawn_all()
	peace = sim_rules.human_grace_ticks(diff_i) / 10.0  # RoWorld human grace (300/180/120 s)
	elapsed = 0.0
	sim_atk = SimAttacks.new(self, sim_rules)
	sim_ai = SimAI.new(self, sim_rules)
	_rebuild_kind_cache()
	sim_ai.setup()
	start_tile = -1
	deploy_t = 5.0
	state = "pick"
	_fade_out(menu_panel, 0.2)
	play_dialog.visible = false
	over_panel_holder.visible = false
	if end_dlg: end_dlg.visible = false
	if note_box: notes.clear(); note_box.queue_redraw()
	if ally_card: ally_card.visible = false
	pick_panel.visible = true
	for n in hud_nodes:
		n.visible = false

# ---------------- RoWorld spawn (Sim._create_nations / _random_start / _spawn_owner) ----------------
var _spawn_tiles := PackedInt32Array()
var _spawn_grid := {}

func _claim_disc(id: int, c: int, radius: float) -> void:
	var cx := c % W; var cy := c / W
	var ri := ceili(radius) + 1
	var r2 := radius * radius
	for dy in range(-ri, ri + 1):
		var y := cy + dy
		if y < 0 or y >= H: continue
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			if x < 0 or x >= W: continue
			var fx := dx + 0.5; var fy := dy + 0.5
			if fx * fx + fy * fy <= r2 or (dx == 0 and dy == 0):
				var i := y * W + x
				if owner_map[i] == NEUTRAL: _set_owner(i, id)

func _spawn_note(t: int) -> void:
	_spawn_tiles.append(t)
	var cs := maxi(1, ceili(sim_rules.tribe_spawn_min_dist))
	var key := Vector2i((t % W) / cs, (t / W) / cs)
	if not _spawn_grid.has(key): _spawn_grid[key] = []
	_spawn_grid[key].append(t)

func _spawn_near(t: int) -> bool:
	var md := sim_rules.tribe_spawn_min_dist
	var cs := maxi(1, ceili(md))
	var x := t % W; var y := t / W
	for gy in range(y / cs - 1, y / cs + 2):
		for gx in range(x / cs - 1, x / cs + 2):
			for s in _spawn_grid.get(Vector2i(gx, gy), []):
				if absi(s % W - x) + absi(s / W - y) < md: return true
	return false

func _owned_near(t: int) -> bool:
	var x := t % W
	if x > 0 and owner_map[t - 1] > 0: return true
	if x < W - 1 and owner_map[t + 1] > 0: return true
	if t >= W and owner_map[t - W] > 0: return true
	if t < W * (H - 1) and owner_map[t + W] > 0: return true
	return false

func _random_start() -> int:
	for tries in range(1, 1001):
		var c := rng.randi() % (W * H)
		if owner_map[c] != NEUTRAL or _owned_near(c): continue
		if tries <= 750 and _spawn_near(c): continue
		return c
	return -1

func _nation_spawn_land(cx: int, cy: int) -> int:
	var d := maxi(1, int(floor(sim_rules.nation_spawn_delta + 0.5)))
	for _k in 50:
		var x := rng.randi_range(cx - d, cx + d - 1)
		var y := rng.randi_range(cy - d, cy + d - 1)
		if x < 0 or y < 0 or x >= W or y >= H: continue
		var c := y * W + x
		if owner_map[c] != NEUTRAL: continue
		if mtn[c] == 2 and rng.randi() % 2 == 0: continue
		return c
	return -1

func _rw_spawn_all() -> void:
	_spawn_tiles.clear(); _spawn_grid.clear()
	var R := sim_rules
	var list := []
	if not real_nations.is_empty():
		for e in real_nations: list.append(e)
	else:
		# generated maps have no manifest: same nation count rule as before, random starts
		var base_prot := (5 + (map_i % 4) * 2) * 4
		var np := int(round(float(base_prot) * rng.randf_range(1.5, 2.0)))
		var pool := PROT_NAMES.duplicate(); pool.shuffle()
		for k in np:
			var nm: String = pool[k % pool.size()]
			list.append([nm if k < pool.size() else "New " + nm, "", -1, -1])
	for k in list.size():
		var e: Array = list[k]
		var hex: String = RealMaps.NATION_COLORS.get(str(e[1]), "")
		var col := Color.html(hex) if hex != "" else Color.from_hsv(fmod(float(k) * 0.61803398875, 1.0), rng.randf_range(0.62, 0.86), rng.randf_range(0.82, 0.96))
		var id := _new_nation(e[0], col, true)
		nations[id].prot = true
		nations[id].troops = R.start_troops(SimRules.KIND_NATION, diff_i)
		var t := -1
		if int(e[2]) >= 0:
			t = _nation_spawn_land(int(e[2]), int(e[3]))
			if t < 0: t = _find_spawn_tile(int(e[2]), int(e[3]))
		if t < 0: t = _random_start()
		if t >= 0:
			_claim_disc(id, t, R.spawn_radius); _spawn_note(t)
			nations[id].troops = R.max_troops(SimRules.KIND_NATION, nations[id].land, 0, diff_i)
	for k in SimRules.DEFAULT_TRIBES:
		var grey_v := rng.randf_range(0.40, 0.58)
		var id := _new_nation(_name(), Color.from_hsv(0.60, rng.randf_range(0.02, 0.07), grey_v), true)
		nations[id].troops = SimRules.START_TROOPS_TRIBE
		var t := _random_start()
		if t >= 0:
			_claim_disc(id, t, R.spawn_radius); _spawn_note(t)
			nations[id].troops = R.max_troops(SimRules.KIND_TRIBE, nations[id].land, 0, diff_i)
		else:
			nations[id].alive = false

func _place_start(t: int) -> void:
	if t < 0 or (owner_map[t] != NEUTRAL and owner_map[t] != PLAYER):
		return
	_clear_nation(PLAYER)
	_claim_disc(PLAYER, t, sim_rules.spawn_radius)
	nations[PLAYER].troops = sim_rules.max_troops(SimRules.KIND_HUMAN, nations[PLAYER].land, 0, diff_i)
	start_tile = t
	# Do NOT reset deploy_t when placing or switching starting location!

# ---------------- economy / combat ----------------
# Per-owner structure totals, rebuilt only when the structure list changes (_sv bumps on add,
# remove, capture and upgrade) instead of a full structs sweep on every call.
var _sv := 0
var _oc_ver := -1
var _oc_lvl := {}
var _oc_cnt := {}
func _oc_rebuild() -> void:
	_oc_ver = _sv
	_oc_lvl.clear(); _oc_cnt.clear()
	for st in structs:
		var key: int = st.o * 64 + st.k
		_oc_lvl[key] = _oc_lvl.get(key, 0) + int(st.get("level", 1))
		_oc_cnt[key] = _oc_cnt.get(key, 0) + 1

func owned(id: int, k: int) -> int:
	if _oc_ver != _sv or _oc_ver < 0: _oc_rebuild()
	return _oc_lvl.get(id * 64 + k, 0)

func owned_count(id: int, k: int) -> int:
	if _oc_ver != _sv or _oc_ver < 0: _oc_rebuild()
	return _oc_cnt.get(id * 64 + k, 0)

func troop_cap(id: int) -> float:
	return sim_rules.max_troops(kind_of(id), nations[id].land, owned(id, 0), diff_i)

func gold_rate(id: int) -> float:
	# passive goldAdditionRate x 10 per second (trade ships, trains and conquests come on top)
	return sim_rules.gold_per_tick(kind_of(id)) * 10.0 if nations[id].land > 0 else 0.0

func build_cost(id: int, k: int) -> float:
	var base: float = build_data[k][2]
	if k in NUKES: return nuke_cost(k)
	if k == 13: return base
	var rw_names := {0: "city", 3: "defense", 4: "sam", 5: "silo", 10: "artillery", 14: "airfield", 15: "railgun"}
	if k == 1 or k == 2: return SimRules.build_cost("port", owned(id, 1) + owned(id, 2))
	if k == 6: return SimRules.build_cost("warship", _count_ws(id))
	if rw_names.has(k): return SimRules.build_cost(rw_names[k], owned(id, k))
	if k == 10: return minf(750e3, 150e3 * (owned(id, 10) + 1))
	if k == 14: return minf(1.5e6, 500e3 * (owned(id, 14) + 1))
	if k == 15: return minf(7.5e6, 2.5e6 * (owned(id, 15) + 1))
	if k == 0:
		var c := owned(id, 0)
		var l := [125e3, 250e3, 500e3, 1e6]
		return l[mini(c, 3)]
	if k == 1 or k == 2:
		var c := owned(id, 1) + owned(id, 2)
		var l := [125e3, 250e3, 500e3, 1e6]
		return l[mini(c, 3)]
	if k == 3:
		var c := owned(id, 3)
		return minf(250e3, 50e3 * (c + 1))
	if k == 4:
		return 1.5e6 if owned(id, 4) == 0 else 3.0e6
	if k == 5:
		return 1.0e6
	if k == 6:
		var c := _count_ws(id)
		return minf(1.0e6, 250e3 * (c + 1))
	return base * (1.0 + owned(id, k) * 0.5)

var def_posts := {}  # owner -> PackedInt32Array of finished defense post tiles (rebuilt each tick)
func _rebuild_def_posts() -> void:
	def_posts.clear()
	for st in structs:
		if st.k == 3 and float(st.get("bt", 0.0)) <= 0.0:
			if not def_posts.has(st.o): def_posts[st.o] = PackedInt32Array()
			var arr: PackedInt32Array = def_posts[st.o]
			arr.append(st.tile)
			def_posts[st.o] = arr

func defended(i: int, o: int) -> bool:
	if o <= 0 or not def_posts.has(o): return false
	var x := i % W; var y := i / W
	var r := sim_rules.defense_range
	var r2 := r * r
	for t in def_posts[o]:
		var dx: int = t % W - x; var dy: int = t / W - y
		if dx * dx + dy * dy <= r2: return true
	return false

func _find_upgrade_target(k: int, tile: int, o: int) -> Dictionary:
	if tile < 0 or not (k in UPGRADABLE): return {}
	var x := tile % W; var y := tile / W
	var best := {}
	var bd := 81.0  # within 9 tiles clicks upgrade existing building of same type
	for st in structs:
		if st.o == o and st.k == k:
			var d := Vector2(st.tile % W - x, st.tile / W - y).length_squared()
			if d <= bd:
				bd = d; best = st
	return best

func build_req(k: int, tile: int, o := PLAYER) -> String:
	if k == 9 and not mirv_enabled: return "Not available in this prototype yet"
	if o == PLAYER and (god_mode or no_cd):
		if tile >= 0 and not (k in NUKES or k == 15) and owner_map[tile] != o: return "Must be on your own land"
		return ""
	if o == PLAYER and kind_locked(k) != "": return "Locked: unlock it in the Arsenal"
	if k == 15 or k in NUKES:
		if owned(o, 5) == 0: return "Requires a Missile Silo"
		var ready := false
		var min_cd := 999.0
		for st in structs:
			if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0:
				if _ready_slots(st) > 0: ready = true; break
				min_cd = minf(min_cd, float(st.get("cd", 9.0)))
		if not ready: return "Silo reloading (%ds)" % maxi(1, ceili(min_cd if min_cd < 900.0 else 9.0))
		if k == 15 and rail_cd > 0: return "Railgun recharging (%ds)" % ceili(rail_cd)
		return ""
	if k == 6 and owned(o, 1) == 0: return "Requires a Port"
	if k == 13:
		var cd: float = nations[o].get("reinf_cd", 0.0)
		return ("Cooldown %ds" % ceili(cd)) if cd > 0 else ""
	if k == 6: return ""
	if tile >= 0:
		var site := sim_struct.place_site(o, k, tile)
		if site.reason != "": return SimStructures.reason_text(site.reason)
	return ""

func select_build(k: int) -> void:
	if state != "play" or k < 0 or k >= build_data.size(): return
	if k == 16:
		set_icbm(not icbm_mode)
		notify("ICBM %s: bombs ignore range, +10%% cost per launch" % ("ON" if icbm_mode else "OFF"), "info"); return
	if k == 13:
		try_build(k, -1); return
	if k == 6:
		var req6 := build_req(6, -1)
		if req6 != "":
			notify(req6, "bad")
			return
		# Selecting Warship enters placement mode so you can click water/coast to place it, OR clicking the button a second time auto-launches from your Port!
		if build_sel == 6:
			try_build(6, -1)
			build_sel = -1
			return
		build_sel = 6
		return
	if (k in NUKES or k == 15) and build_req(k, -1) != "": return
	build_sel = -1 if build_sel == k else k

var _ai_place_budget := 0  # AI placement searches (flood fills) left this tick
func try_build(k: int, tile: int, o := PLAYER) -> bool:
	if not can_build(o): return false
	if o != PLAYER and not (k in NUKES):
		if _ai_place_budget <= 0: return false
		_ai_place_budget -= 1
	var n = nations[o]
	var cost := build_cost(o, k)
	var req := build_req(k, tile, o)
	if req != "" or n.gold < cost:
		if o == PLAYER and k == 6:
			notify(req if req != "" else ("Need %s gold for Warship" % _fmt(cost)), "bad")
		return false
	if k == 15:
		if tile < 0: return false
		var okr := fire_railgun(o, tile)
		if okr and o == PLAYER: build_sel = -1
		return okr
	if k in NUKES:
		if tile < 0 or owner_map[tile] == WATER: return false
		var okn := launch_nuke(o, k, tile)
		if okn and o == PLAYER: build_sel = -1
		return okn
	n.gold -= cost
	if k == 13:
		n.troops = minf(troop_cap(o), n.troops + troop_cap(o) / 5.0)
		n.reinf_cd = 30.0
		if o == PLAYER: sfx("spawn")
		return true
	if k == 6:
		if not spawn_warship(o, tile):
			n.gold += cost
			if o == PLAYER: notify("No coastal water found near your Port", "bad")
			return false
		if o == PLAYER:
			build_sel = -1
			sfx("build_warship")
			notify("Warship deployed!", "good")
			_update_hud()
		return true
	var site := sim_struct.place_site(o, k, tile)
	if site.reason != "":
		n.gold += cost
		return false
	if site.upgrade != null:
		_upgrade_struct(site.upgrade)
		if o == PLAYER: build_sel = -1; sfx(BUILD_SFX.get(k, "build_city"))
		return true
	_struct_add(k, int(site.tile), o)
	if o == PLAYER: build_sel = -1; sfx(BUILD_SFX.get(k, "build_city"))
	return true

func tile_cost(a: int, t: int) -> float:
	if t == NEUTRAL:
		return 16.0
	var d = nations[t]
	var base: float = 20.0 + d.troops / maxf(1.0, d.land) * 1.2
	# Anti-snowball large-defender sigmoid debuff & large-attacker scaling
	var def_share: float = float(d.land) / maxf(1.0, float(land_total))
	if def_share > 0.20:
		base *= clampf(1.0 / (1.0 + exp((def_share - 0.35) * 8.0)), 0.45, 1.0)
	if a > 0 and nations[a].land > land_total * 0.25:
		base *= pow(float(nations[a].land) / (land_total * 0.25), 0.25)
	return base

func tile_cost_at(a: int, t: int, i: int) -> float:
	var c := tile_cost(a, t)
	var ter: int = mtn[i]
	if ter == 0: c *= 0.80        # Plains: mag 80 (0.8x)
	elif ter == 1: c *= 1.00      # Highlands: mag 100 (1.0x)
	else: c *= 2.00               # Mountains: 2.0x troop loss
	if fallout[i] == 1:
		var prog: float = clampf(1.0 - fallout_t[i] / 60.0, 0.0, 1.0)
		c *= (5.0 - prog * 2.0)   # OpenFront fallout formula: 5x tapering to 3x
	if t > 0 and is_traitor(t): c *= 0.5
	if defended(i, t): c *= 5.0
	return c

func tile_time(t: int, i: int) -> int:
	var ter: int = mtn[i]
	var s := 1.0
	if ter == 1: s *= 1.25        # Highlands speed 20 vs Plains 16.5
	elif ter == 2: s *= 2.5       # Mountains 2.5x slower
	if fallout[i] == 1:
		var prog: float = clampf(1.0 - fallout_t[i] / 60.0, 0.0, 1.0)
		s *= (5.0 - prog * 2.0) * 0.7
	if defended(i, t): s *= 3.0
	return maxi(1, int(round(s)))

# True if any border tile of s1 has a 4-neighbour owned by other.
func _border_touches(s1: int, other: int) -> bool:
	var N := W * H
	for t in border[s1]:
		var x: int = t % W
		if x > 0 and owner_map[t - 1] == other: return true
		if x < W - 1 and owner_map[t + 1] == other: return true
		if t >= W and owner_map[t - W] == other: return true
		if t < N - W and owner_map[t + W] == other: return true
	return false

func _shares_land_border(a: int, b: int, click_tile: int = -1) -> bool:
	if a <= 0 or a >= nations.size() or not nations[a].alive or nations[a].land <= 0:
		return false
	if b > 0:
		if b >= nations.size() or not nations[b].alive or nations[b].land <= 0:
			return false
		var box: Rect2i = nations[a].bb.grow(1).intersection(nations[b].bb.grow(1)).intersection(Rect2i(0, 0, W, H))
		if box.size.x <= 0 or box.size.y <= 0:
			return false
		if border.size() == nations.size():
			# walk the smaller border set: a and b touch iff one has a border tile next to the other
			var s1: int = a if border[a].size() <= border[b].size() else b
			return _border_touches(s1, b if s1 == a else a)
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				var i := y * W + x
				if owner_map[i] == b and _adj_to(i, a):
					return true
		return false
	if b == NEUTRAL:
		var box_a: Rect2i = nations[a].bb.grow(1).intersection(Rect2i(0, 0, W, H))
		var has_adj_neutral := false
		if border.size() == nations.size():
			has_adj_neutral = _border_touches(a, NEUTRAL)
		else:
			for y in range(box_a.position.y, box_a.end.y):
				for x in range(box_a.position.x, box_a.end.x):
					var i := y * W + x
					if owner_map[i] == NEUTRAL and _adj_to(i, a):
						has_adj_neutral = true; break
				if has_adj_neutral: break
		if not has_adj_neutral:
			return false
		if click_tile < 0 or click_tile >= W * H:
			return true
		# Check if click_tile is on the same landmass as 'a' (reachable over land without crossing water)
		if bfs_par.size() != W * H:
			bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
		bfs_gen += 1
		var gen := bfs_gen
		var q := PackedInt32Array([click_tile])
		bfs_stamp[click_tile] = gen
		var qi := 0
		while qi < q.size() and qi < 18000:
			var cur: int = q[qi]; qi += 1
			if owner_map[cur] == a or _adj_to(cur, a):
				return true
			var cx := cur % W
			for d in [1, -1, W, -W]:
				if (d == 1 and cx == W - 1) or (d == -1 and cx == 0): continue
				var j: int = cur + d
				if j >= 0 and j < W * H and owner_map[j] >= 0 and bfs_stamp[j] != gen:
					bfs_stamp[j] = gen; q.append(j)
		return false
	return false

func launch_attack(a: int, t: int, share: float) -> bool:
	if allied(a, t):
		if a == PLAYER: notify("%s is your ally — right-click to manage alliance" % _nname(t), "info")
		return false
	if t == a or t < 0:
		return false
	if t > 0 and not nations[t].alive:
		return false
	var n = nations[a]
	var troops: float = n.troops * clampf(share, 0.0, 1.0)
	if troops < 1.0:
		return false
	n.troops -= troops
	var started := sim_atk.start(a, t, troops) != null
	if started and a == PLAYER:
		sfx("order")
	return started

func _frontier(a: int, t: int) -> Array:
	var bb: Rect2i = nations[a].bb.grow(1).intersection(Rect2i(0, 0, W, H))
	if t > 0 and t < nations.size():
		bb = bb.intersection(nations[t].bb.grow(1))
	var fr := []
	if bb.size.x <= 0 or bb.size.y <= 0:
		return fr
	if bb.get_area() <= 16000:
		for y in range(bb.position.y, bb.end.y):
			for x in range(bb.position.x, bb.end.x):
				var i := y * W + x
				if owner_map[i] == t and _adj_to(i, a):
					fr.append(i)
	else:
		# large nation: sample first, then fallback to full scan if sampling missed a narrow border
		for k in 5000:
			var i := (bb.position.y + rng.randi() % bb.size.y) * W + bb.position.x + rng.randi() % bb.size.x
			if owner_map[i] == t and _adj_to(i, a):
				fr.append(i)
		if fr.is_empty():
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var i := y * W + x
					if owner_map[i] == t and _adj_to(i, a):
						fr.append(i)
	fr.shuffle()
	return fr

func _adj_to(i: int, a: int) -> bool:
	var x := i % W
	if x > 0 and owner_map[i - 1] == a: return true
	if x < W - 1 and owner_map[i + 1] == a: return true
	if i >= W and owner_map[i - W] == a: return true
	if i < W * (H - 1) and owner_map[i + W] == a: return true
	return false

func _tick_attacks() -> void:
	_rebuild_def_posts()
	sim_atk.tick_all()

func _adj_count(i: int, a: int) -> int:
	var x := i % W
	var c := 0
	if x > 0 and owner_map[i - 1] == a: c += 1
	if x < W - 1 and owner_map[i + 1] == a: c += 1
	if i >= W and owner_map[i - W] == a: c += 1
	if i < W * (H - 1) and owner_map[i + W] == a: c += 1
	return c

func _coastal(i: int) -> bool:
	for d in [1, -1, W, -W]:
		if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
		var j: int = i + d
		if j >= 0 and j < W * H and owner_map[j] == WATER: return true
	return false

func launch_boat(a: int, click: int, share: float, max_nodes := 1000000) -> bool:
	if click < 0 or click >= W * H: return false
	var o := owner_map[click]
	if o < 0 or o == a or allied(a, o): return false
	# Strict rule: once your country touches someone else's land, it MUST only be raided via land!
	if o > 0 and _shares_land_border(a, o):
		return launch_attack(a, o, share)
	if o == NEUTRAL and _shares_land_border(a, NEUTRAL, click):
		return launch_attack(a, NEUTRAL, share)
	var dest := -1
	var best := 1e9
	var cx := click % W; var cy := click / W
	for y in range(maxi(0, cy - 24), mini(H, cy + 25)):
		for x in range(maxi(0, cx - 24), mini(W, cx + 25)):
			var i := y * W + x
			if owner_map[i] == o and _coastal(i):
				var dd := Vector2(x - cx, y - cy).length_squared()
				if dd < best: best = dd; dest = i
	# If the player clicked an inland tile of an overseas nation 'o', find the closest coastal tile of 'o' anywhere in its territory
	if dest < 0 and o > 0 and o < nations.size():
		var bbo: Rect2i = nations[o].bb.intersection(Rect2i(0, 0, W, H))
		for y in range(bbo.position.y, bbo.end.y):
			for x in range(bbo.position.x, bbo.end.x):
				var i := y * W + x
				if owner_map[i] == o and _coastal(i):
					var dd := Vector2(x - cx, y - cy).length_squared()
					if dd < best: best = dd; dest = i
	if dest < 0: return false
	# RoWorld launch_boat limits: boats at sea (10 for you, 3 for AI), 2 boat orders per second, floored troops
	if sim_naval.boats_of(a) >= sim_naval.max_boats(a):
		if a == PLAYER: notify("Too many transports at sea", "info")
		return false
	var troops: float = floor(nations[a].troops * clampf(share, 0.01, 1.0))
	if troops < 1.0: return false
	if not sim_naval.take_token(a):
		if a == PLAYER: notify("Too many boat orders at once — wait a moment", "info")
		return false
	var key := "%d:%d" % [a, dest]
	if path_cache.has(key) and elapsed - path_cache[key][1] < 30.0:
		var cp: PackedVector2Array = path_cache[key][0]
		var st := Vector2i(int(cp[0].x / TS), int(cp[0].y / TS))
		if _adj_to(st.y * W + st.x, a):
			_spawn_boat(a, cp, dest, troops)
			return true
	# A search that just ran out of nodes for this (owner, landing) pair is not repeated for 10 s:
	# the AI re-picks the same unreachable coast every frame and each miss walks 12000 water tiles.
	if path_fail.has(key) and elapsed - float(path_fail[key]) < 10.0: return false
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array()
	for d in [1, -1, W, -W]:
		if (d == 1 and dest % W == W - 1) or (d == -1 and dest % W == 0): continue
		var j: int = dest + d
		if j >= 0 and j < W * H and owner_map[j] == WATER:
			bfs_par[j] = -1; bfs_stamp[j] = gen; q.append(j)
	var qi := 0
	var found := -1
	# same BFS order as before (+1, -1, +W, -W), inlined for speed
	var om: PackedInt32Array = owner_map
	var NN := W * H
	while qi < q.size() and qi < max_nodes:
		var i: int = q[qi]; qi += 1
		var ix := i % W
		if (ix > 0 and om[i - 1] == a) or (ix < W - 1 and om[i + 1] == a) or (i >= W and om[i - W] == a) or (i < NN - W and om[i + W] == a):
			found = i; break
		var j := i + 1
		if ix != W - 1 and j < NN and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i - 1
		if ix != 0 and j >= 0 and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i + W
		if j < NN and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
		j = i - W
		if j >= 0 and om[j] == WATER and bfs_stamp[j] != gen:
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	if found < 0:
		if path_fail.size() > 2000: path_fail.clear()
		path_fail[key] = elapsed
		return false
	var path := []
	var k := found
	while k != -1:
		path.append(k); k = bfs_par[k]
	var pts := _smooth_path(path, dest)
	path_cache[key] = [pts, elapsed]
	if path_cache.size() > 400: path_cache.clear()
	_spawn_boat(a, pts, dest, troops)
	return true

func _spawn_boat(a: int, pts: PackedVector2Array, dest: int, troops: float) -> void:
	var cum := PackedFloat32Array([0.0])
	for m in range(1, pts.size()):
		cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
	nations[a].troops -= troops
	boats.append({"a": a, "troops": troops, "pts": pts, "cum": cum, "d": 0.0, "dest": dest, "sid": rng.randi() % 10})
	if a == PLAYER: sfx("transport")
	if a != PLAYER and dest >= 0 and owner_map[dest] == PLAYER: notify("A transport from %s is heading to your coast" % _nname(a), "bad")

func _water_los(p0: Vector2, p1: Vector2) -> bool:
	var n := int(p0.distance_to(p1) * 2.0) + 1
	for s2 in n + 1:
		var p := p0.lerp(p1, float(s2) / n)
		var x := int(p.x); var y := int(p.y)
		if x < 0 or y < 0 or x >= W or y >= H or owner_map[y * W + x] != WATER: return false
	return true

func _smooth_path(path: Array, dest: int) -> PackedVector2Array:
	var raw := PackedVector2Array()
	for t in path: raw.append(Vector2(t % W + 0.5, t / W + 0.5))
	# string pulling over water
	var pulled := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var lo := i + 1
		var hi := mini(raw.size() - 1, i + 32)
		var best_j := lo
		while lo <= hi:
			var mid_j := (lo + hi) / 2
			if _water_los(raw[i], raw[mid_j]):
				best_j = mid_j; lo = mid_j + 1
			else:
				hi = mid_j - 1
		pulled.append(raw[best_j]); i = best_j
	pulled.append(Vector2(dest % W + 0.5, dest / W + 0.5))
	# Chaikin smoothing -> curved route
	var pts := pulled
	for it in 3:
		if pts.size() < 3: break
		var np := PackedVector2Array([pts[0]])
		for m in pts.size() - 1:
			np.append(pts[m].lerp(pts[m + 1], 0.25)); np.append(pts[m].lerp(pts[m + 1], 0.75))
		np.append(pts[pts.size() - 1])
		pts = np
	for m in pts.size(): pts[m] *= TS
	return pts

func _boat_pos(bt) -> Array:
	var cum: PackedFloat32Array = bt.cum
	var pts: PackedVector2Array = bt.pts
	var d: float = bt.d
	var m := 1
	while m < cum.size() - 1 and cum[m] < d: m += 1
	var seg := maxf(0.001, cum[m] - cum[m - 1])
	var p := pts[m - 1].lerp(pts[m], clampf((d - cum[m - 1]) / seg, 0, 1))
	return [p, (pts[m] - pts[m - 1]).normalized(), m]

func _tick_boats(dt: float) -> void:
	for bt in boats.duplicate():
		var a0: int = bt.a
		var dest0: int = bt.dest
		if not nations[a0].alive:
			boats.erase(bt); continue
		var o0 := owner_map[dest0]
		# If attacker 'a0' now touches target nation 'o0' by land while boat is in transit, redirect troops into land raid!
		if o0 > 0 and o0 != a0 and (ticks_done + int(bt.get("sid", 0))) % 10 == 0 and _shares_land_border(a0, o0):
			nations[a0].troops += bt.troops
			boats.erase(bt)
			launch_attack(a0, o0, 0.05)
			for at in attacks:
				if at.a == a0 and at.t == o0:
					var add_t := minf(nations[a0].troops, float(bt.troops))
					at.troops += add_t
					nations[a0].troops -= add_t
					break
			continue
		bt.d += dt * sim_rules.ship_tiles_per_s() * boat_speed * TS
		var cum: PackedFloat32Array = bt.cum
		if bt.d >= cum[cum.size() - 1]:
			boats.erase(bt)
			var dest: int = bt.dest
			var o := owner_map[dest]
			var a: int = bt.a
			if not nations[a].alive: continue
			if o == a:
				nations[a].troops += floor(bt.troops * SimRules.RETREAT_KEEP)  # lands home: -25 %
				if a == PLAYER: notify("Your transport returned its troops home", "info")
				continue
			if not sim_naval.landable(a, dest):
				var alt := sim_naval.alt_landing(a, dest, sim_naval.coast_body(dest))
				if alt < 0:
					nations[a].troops += floor(bt.troops * 0.5)
					if a == PLAYER: notify("Your transport could not land", "bad")
					continue
				dest = alt; o = owner_map[dest]
			# RoWorld: the transport takes its landing tile, then attacks from that beachhead
			if allied(a, o):
				nations[a].troops += bt.troops; continue
			_set_owner(dest, a)
			if a == PLAYER: notify("Your transport landed on %s's coast" % _nname(o), "good")
			sim_atk.start(a, o, bt.troops, dest)

func retreat(at) -> void:
	sim_atk.retreat(at)

func _economy(dt: float) -> void:
	fallout_count = fallout_list.size()
	var city_lv := {}
	for st in structs:
		if st.k == 0: city_lv[st.o] = city_lv.get(st.o, 0) + int(st.get("level", 1))
	for id in range(1, nations.size()):
		var n = nations[id]
		if not n.alive:
			continue
		if n.land <= 0 and (id != PLAYER or state == "play"):
			n.alive = false
			if id != PLAYER and n.get("last_by", 0) == PLAYER: stats.elims += 1; sfx("conquered")
			if id != PLAYER and (is_prot(id) or rng.randf() < 0.15): notify("%s has been eliminated" % n.name, "info")
			continue
		var kd := kind_of(id)
		var cap := sim_rules.max_troops(kd, n.land, city_lv.get(id, 0), diff_i)
		n.regen = sim_rules.troop_growth(kd, n.troops, cap, diff_i) * 10.0
		n.troops += sim_rules.troop_growth_applied(kd, n.troops, cap, diff_i)
		n.gold += sim_rules.gold_per_tick(kd)
		n.reinf_cd = maxf(0.0, n.reinf_cd - dt)
		if id == PLAYER:
			if god_mode or inf_gold: n.gold = maxf(n.gold, 999e6)
			if god_mode: n.troops = maxf(n.troops, cap)
			if god_mode or no_cd: n.reinf_cd = 0.0; rail_cd = 0.0

func _ai(_dt: float) -> void:
	_ai_place_budget = 24
	sim_ai.tick()

func _ai_boat(id: int, n) -> void:
	if boat_launched_frame: return
	if sim_naval.boats_of(id) >= sim_naval.max_boats(id) or n.troops < 3000: return
	if not n.get("prot", false) and rng.randf() < 0.8: return
	var c: Vector2i = n.bb.get_center()
	for k in 60:
		var x := clampi(c.x + rng.randi_range(-120, 120), 0, W - 1)
		var y := clampi(c.y + rng.randi_range(-70, 70), 0, H - 1)
		var i := y * W + x
		var o := owner_map[i]
		if o < 0 or o == id or not _coastal(i): continue
		if o == PLAYER and elapsed < peace: continue
		if _shares_land_border(id, o, i): continue
		boat_launched_frame = true
		if launch_boat(id, i, 0.3, 12000): return
		return

# ================= v5 systems: weapons, ships, notifications =================
# RoWorld radii (7/25/3/15/7 at 640x352) scaled by the map's linear scale so each bomb covers the same share of the map
const BLAST_S := float(W) / 640.0
var NUKE_R := {7: 7.0 * BLAST_S, 8: 25.0 * BLAST_S, 9: 3.0 * BLAST_S, 11: 15.0 * BLAST_S, 12: 7.0 * BLAST_S}
var mirv_enabled := true
var god_mode := false
var inf_gold := false
var no_cd := false
const NUKES := [7, 8, 9, 11, 12]
const LAND_STRUCTS := [0, 1, 2, 3, 4, 5, 10, 14]
const UPGRADABLE := [0, 1, 2, 4, 5, 10, 14]
const BUILD_DUR := {0: 2.0, 1: 5.0, 2: 2.0, 3: 5.0, 4: 30.0, 5: 10.0, 10: 8.0, 14: 10.0, 15: 15.0}
const PROT_NAMES := [
	"Valdoria", "Kestrel Union", "Aurenhold", "Marrow Coast", "Sunreach", "Thornvale", "Ironmere", "Caldera Pact",
	"Solvaria", "Nordmark", "Vesperia", "Drakensberg", "Oakhaven", "Cinderfell", "Starfall", "Westmarch",
	"Redcliff", "Frostholm", "Silvercrest", "Stormwatch", "Blackwater", "Goldspire", "Highgarden", "Wintermoor",
	"Ashenvale", "Dawnbreak", "Ravencrest", "Windward", "Deepwater", "Stonehelm", "Emberfall", "Mistralia",
	"Osteria", "Castellan", "Valkenreach", "Ambergris", "Halcyon", "Corinthia", "Sablemark", "Verdantia",
	"Pyrewatch", "Glimmerdeep", "Cragmoor", "Lionsgate", "Tidewater", "Brimstone", "Wyverncliff", "Cloudspire",
	"Duskwood", "Falconrest", "Hearthglen", "Ivorycoast", "Jadevale", "Kingsford", "Larkspur", "Moonbrook",
	"Nighthaven", "Oakridge", "Pinecrest", "Queensport", "Rosewood", "Sunspire", "Thistledown", "Umberland",
	"Valewatch", "Whiteharbor", "Yewdale", "Zephyrion", "Arboria", "Bastion", "Citadel", "Driftmark",
	"Ebonhold", "Fairwind", "Grimwatch", "Highwater", "Ironforge", "Kestrelgard", "Lorelei", "Mirefall",
	"Netherwind", "Oakhurst", "Pendragon", "Quicksilver", "Riverrun", "Shadowfen", "Templar", "Ulsteria",
	"Vanguard", "Whitecliff", "Xandria", "Yarrow", "Zanzibaria", "Avalon", "Belmont", "Crownland"
]
var fallout := PackedByteArray()
var fallout_list := {}  # tiles with fallout == 1
var fallout_t := PackedFloat32Array()
var struct_at := {}
var missiles := []   # {o,k,from:Vector2,to:Vector2,t,dur,tile,r,mirv}
var warships := []   # {o,pos:Vector2(tile),home,hp,vet,kills,tgt:Vector2,cd}
var traders := []    # {o,pts,cum,d,src,dst,gold}
var trains := []     # {o,from:Vector2,to:Vector2,t,dur,dst,stops,visited}
var floats := []     # {pos:Vector2,text:String,col:Color,t:float}
var blasts := []     # {pos,r,t,dur,seed}
var shake_amp := 0.0
var shake_t := 0.0
var shells := []     # {pos,t}
var notes := []      # {text,col,kind,t}
var note_box: Control
var trade_t := 0.0
var train_t := 0.0
var fallout_tick_t := 0.0
var art_t := 0.0
var neigh_cache := [-1, 0]

func is_prot(id: int) -> bool:
	return id > 0 and id < nations.size() and nations[id].get("prot", false)

func can_build(id: int) -> bool:
	return id == PLAYER or is_prot(id)

func sam_range(lvl: int) -> float:
	return 150.0 - 480.0 / float(lvl + 5)  # OpenFront formula: Lv1=70, Lv2=81.4, Lv3=90, cap 150

func _ready_slots(st) -> int:
	if float(st.get("bt", 0.0)) > 0.0 or float(st.get("cd", 0.0)) > 0.0:
		return 0
	return 1

func _use_slot(st, cd_sec: float) -> bool:
	if float(st.get("cd", 0.0)) > 0.0:
		return false
	var lvl := int(st.get("level", 1))
	var actual_cd: float = cd_sec / (1.0 + 0.15 * float(lvl - 1))
	st.cd = actual_cd
	st.cmax = maxf(0.1, actual_cd)
	var slots: Array = st.get("slots", [0.0])
	if slots.size() > 0: slots[0] = actual_cd
	return true

func _struct_add(k: int, tile: int, o: int) -> void:
	var dur: float = BUILD_DUR.get(k, 2.0) * (0.05 if (autoshot or bench) else 1.0)
	var init_cd := 2.5 if k == 14 else 0.0
	var st := {"k": k, "tile": tile, "o": o, "level": 1, "hits": 0, "cd": init_cd, "cmax": maxf(1.0, init_cd), "slots": [0.0], "bt": dur, "bmax": maxf(0.1, dur)}
	structs.append(st); struct_at[tile] = st; _sv += 1; _own_sv[o] = _own_sv.get(o, 0) + 1

func _upgrade_struct(st) -> void:
	st.level = int(st.get("level", 1)) + 1; _sv += 1
	var dur: float = BUILD_DUR.get(st.k, 2.0) * 0.6 * (0.05 if (autoshot or bench) else 1.0)
	st.bt = dur; st.bmax = maxf(0.1, dur)
	if st.o == PLAYER:
		notify("%s upgraded to Lv%d" % [build_data[st.k][1], st.level], "good")
		add_float(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS, "Lv%d!" % st.level, GOLD_C)

func _struct_remove(st) -> void:
	structs.erase(st); struct_at.erase(st.tile); _sv += 1; _own_sv[st.o] = _own_sv.get(st.o, 0) + 1

func add_float(world_pos: Vector2, text: String, col: Color = GOLD_C) -> void:
	floats.append({"pos": world_pos, "text": text, "col": col, "t": 0.0})
	if floats.size() > 24: floats.pop_front()

func notify(text: String, kind := "info") -> void:
	var col := {"good": GREEN, "bad": RED, "info": CYAN}[kind] as Color
	notes.push_front({"text": text, "col": col, "kind": kind, "t": 0.0})
	if notes.size() > 5: notes.resize(5)
	if note_box: note_box.queue_redraw()

func _nname(id: int) -> String:
	if id == PLAYER: return "You"
	if id <= 0: return "the wilds"
	return nations[id].name

# ---------- nukes ----------
# ---- weapon ranges (IRL ranges scaled to map: World map = 1792 tiles for ~40,000 km => ~22.3 km/tile) ----
const KM_PER_TILE := 40000.0 / 1792.0
# 7 Atom: IRBM-class 3,000 km | 8 Hydrogen: 5,500 km (ICBM threshold) | 9 MIRV: 13,000 km (Minuteman III-class ICBM)
# 11 Mega Nuke: 4,000 km | 12 Scattershot: 1,000 km (tactical/SRBM class)
const NUKE_RANGE_KM := {7: 21060.0, 8: 23400.0, 9: 52000.0, 11: 22230.0, 12: 25740.0}
const ICBM_FEE_PCT := 0.10  # ICBM upgrade: +10% of the launched bomb's price, any range
var icbm_mode := false
# range = fraction of the current map's playable (land) width; World ratios over 40,000 km
const NUKE_RANGE_FRAC := {7: 0.5265, 8: 0.585, 9: 1.3, 11: 0.5558, 12: 0.6435}
var _land_w := -1.0
func land_width() -> float:
	if _land_w < 0.0:
		var x0 := W; var x1 := -1
		for x in range(0, W, 2):
			for y in range(0, H, 4):
				if owner_map[y * W + x] != WATER:
					x0 = mini(x0, x); x1 = maxi(x1, x); break
		_land_w = float(maxi(x1 - x0 + 2, 64)) if x1 >= 0 else float(W)
	return _land_w
func nuke_range(k: int) -> float:
	return float(NUKE_RANGE_FRAC.get(k, 0.1)) * land_width()
func nuke_range_label(k: int) -> String:
	return "%s km (%d%% of map)" % [_fmt_int(int(NUKE_RANGE_FRAC.get(k, 0.1) * 40000.0)), int(round(NUKE_RANGE_FRAC.get(k, 0.1) * 100.0))]

# nukes fly 1.5x (short shots) up to 2.5x (>= 1000 tiles) faster
func nuke_speed_mult(dist: float) -> float:
	return 1.5 + clampf(dist / 1000.0, 0.0, 1.0)

func nuke_cost(k: int) -> float:
	return float(build_data[k][2]) * ((1.0 + ICBM_FEE_PCT) if icbm_mode else 1.0)

# nearest ready silo that can reach tp with weapon k (any silo when ICBM mode is on)
func silo_for(o: int, k: int, tp: Vector2) -> Dictionary:
	var st := nearest_silo(o, tp)
	if st.is_empty() or icbm_mode: return st
	if Vector2(st.tile % W + 0.5, st.tile / W + 0.5).distance_to(tp) > nuke_range(k): return {}
	return st

func _any_silo_dist(o: int, tp: Vector2) -> float:
	var bd := INF
	for st in structs:
		if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0:
			bd = minf(bd, Vector2(st.tile % W + 0.5, st.tile / W + 0.5).distance_to(tp))
	return bd

func set_icbm(on: bool) -> void:
	icbm_mode = on
	if not save.has("settings"): save["settings"] = {}
	save.settings["icbm"] = on
	if build_btns.size() > 16: build_btns[16].queue_redraw()
	_update_hud()

func nearest_silo(o: int, target: Vector2) -> Dictionary:
	var best := {}
	var bd := 1e18
	for st in structs:
		if st.o == o and st.k == 5 and st.get("bt", 0.0) <= 0.0 and _ready_slots(st) > 0:
			var p := Vector2(st.tile % W, st.tile / W)
			var d := p.distance_squared_to(target)
			if d < bd: bd = d; best = st
	return best

func _missile_world_pos(ms, s: float) -> Vector2:
	# Clean, realistic low-profile ICBM altitude arc (pure -Y altitude above ground track, no S-curve or sideways bend)
	var sc := clampf(s, 0.0, 1.0)
	var p0: Vector2 = ms.from * TS
	var p1: Vector2 = ms.to * TS
	var dist_px: float = p0.distance_to(p1)
	var is_br: bool = ms.get("branched", false)
	var ground_pos: Vector2 = p0.lerp(p1, sc)
	var alt_profile: float = pow(sc, 0.72) * pow(1.0 - sc, 0.92) * 3.12
	var apex_h: float = clampf(dist_px * (0.11 if is_br else 0.16), 8.0 if is_br else 16.0, 28.0 if is_br else 64.0)
	return ground_pos + Vector2(0.0, -alt_profile * apex_h)

func _missile_screen_pos(ms, s: float, _z: float) -> Vector2:
	return _screen_of(_missile_world_pos(ms, s))

func launch_nuke(o: int, k: int, tile: int) -> bool:
	if k == 9 and not mirv_enabled: return false
	var tp := Vector2(tile % W + 0.5, tile / W + 0.5)
	var silo := silo_for(o, k, tp)
	if silo.is_empty():
		if o == PLAYER and not nearest_silo(o, tp).is_empty():
			notify("Target out of range (%s: %s). Build a closer silo or enable ICBM." % [build_data[k][1], nuke_range_label(k)], "bad")
		return false
	var cost: float = nuke_cost(k)
	if nations[o].gold < cost: return false
	nations[o].gold -= cost
	_use_slot(silo, 0.0 if (o == PLAYER and (god_mode or no_cd)) else 10.0 * reload_mult())
	var from := Vector2(silo.tile % W + 0.5, silo.tile / W + 0.5)
	var victim: int = owner_map[tile]
	if k == 9:
		var tgt_o: int = victim if victim > 0 else -1
		var cov_pct: float = rng.randf_range(0.65, 0.85)  # MIRV covers 65-85% of target country in fallout
		var hits := []
		for _n in 400:
			if hits.size() >= 28: break
			var cand: int
			if tgt_o > 0:
				var bb: Rect2i = nations[tgt_o].bb
				cand = (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
				if owner_map[cand] != tgt_o: continue
			else:
				cand = clampi(tile + rng.randi_range(-int(30 * BLAST_S), int(30 * BLAST_S)) + rng.randi_range(-int(30 * BLAST_S), int(30 * BLAST_S)) * W, 0, W * H - 1)
			hits.append(cand)
		# 1.2x faster MIRV carrier bus (34 * 1.2 = 40.8 tiles/s)
		var bus_dur := maxf(2.0, from.distance_to(tp) / (40.8 * nuke_speed_mult(from.distance_to(tp))))
		missiles.append({"o": o, "k": 9, "from": from, "to": tp, "t": 0.0, "dur": bus_dur, "r": float(NUKE_R[9]), "mirv": true, "mirv_bus": true, "branched": false, "hits": hits, "tgt_o": tgt_o, "mirv_cov": cov_pct, "split_done": false})
	elif k == 12:
		missiles.append({"o": o, "k": 7, "from": from, "to": tp, "t": 0.0, "dur": 0.0, "r": float(NUKE_R[7]), "mirv": false, "branched": false})
		for m in 5:
			var off := Vector2.from_angle(m * TAU / 5.0) * 9.0 * BLAST_S
			missiles.append({"o": o, "k": 12, "from": from, "to": tp + off, "t": -0.25, "dur": 0.0, "r": 3.0 * BLAST_S, "mirv": false, "branched": true})
	else:
		missiles.append({"o": o, "k": k, "from": from, "to": tp, "t": 0.0, "dur": 0.0, "r": float(NUKE_R[k]), "mirv": false, "branched": false})
	# 1.2x faster bomb travel speed (36.0 * 1.2 = 43.2 tiles/s)
	for ms in missiles:
		if ms.dur == 0.0: ms.dur = maxf(1.8, ms.from.distance_to(ms.to) / (43.2 * nuke_speed_mult(ms.from.distance_to(ms.to))))
	var nm: String = build_data[k][1]
	var lk := "mirv_launch" if k == 9 else ("hydrogen_launch" if k in [8, 11] else "atom_launch")
	sfx(lk, 0.0 if o == PLAYER else -8.0, 0.04, o)
	if victim == PLAYER and o != PLAYER: sfx("nuke_warning")
	if o == PLAYER: notify("%s launched at %s" % [nm, _nname(victim)], "info")
	elif victim == PLAYER: notify("%s launched a %s at you!" % [_nname(o), nm], "bad")
	elif is_prot(o): notify("%s launched %s at %s" % [_nname(o), nm, _nname(victim)], "info")
	return true

func _sam_intercept(ms) -> bool:
	# Only the ascending MIRV carrier bus is immune; individual branched warheads CAN be intercepted by SAMs!
	if ms.get("mirv_bus", false): return false
	for st in structs:
		if st.k == 4 and st.o != ms.o and st.get("bt", 0.0) <= 0.0 and _ready_slots(st) > 0:
			var p := Vector2(st.tile % W + 0.5, st.tile / W + 0.5)
			if p.distance_to(ms.to) <= sam_range(int(st.get("level", 1))):
				_use_slot(st, 9.0 * reload_mult())
				var near_me: bool = st.o == PLAYER or ms.o == PLAYER
				if near_me: sfx("sam_shoot"); sfx("sam_hit")
				if st.o == PLAYER: notify("Your SAM (Lv%d) intercepted a bomb from %s" % [int(st.get("level", 1)), _nname(ms.o)], "good")
				elif ms.o == PLAYER: notify("Your bomb was intercepted by %s" % _nname(st.o), "bad")
				var ip := _missile_world_pos(ms, 0.92)
				blasts.append({"pos": ip, "r": 6.0 * BLAST_S * TS, "t": 0.0, "dur": 0.72 if _qual() >= 2 else 0.65, "seed": int(ms.to.x * 31 + ms.to.y * 17), "kind": "sam"}); _add_shake(1.8)
				if _qual() >= 2: floats.append({"pos": ip + Vector2(0, -6 * TS), "text": "INTERCEPTED!", "col": Color(1, 1, 1), "t": 0.0})
				return true
	return false

func detonate(o: int, c: Vector2, r: float, eff_mult := 1.0) -> void:
	var cx := int(c.x); var cy := int(c.y)
	var ri := int(ceil(r))
	var inner_ratio: float = 0.8 * eff_mult
	var lost := {}
	for y in range(maxi(0, cy - ri), mini(H, cy + ri + 1)):
		for x in range(maxi(0, cx - ri), mini(W, cx + ri + 1)):
			var d := Vector2(x - cx, y - cy).length()
			if d > r: continue
			var i := y * W + x
			var ow: int = owner_map[i]
			if ow < 0: continue
			if d > r * inner_ratio and rng.randf() < (d - r * inner_ratio) / maxf(0.01, r * (1.0 - inner_ratio)): continue
			if struct_at.has(i): _struct_remove(struct_at[i])
			if ow > 0:
				lost[ow] = lost.get(ow, 0) + 1
				_set_owner(i, NEUTRAL)
			fallout[i] = 1; fallout_list[i] = true
			fallout_t[i] = 60.0
			_repaint(i)
	for ow in lost:
		var n = nations[ow]
		var frac: float = float(lost[ow]) / maxf(1.0, n.land + lost[ow])
		n.troops = maxf(0.0, n.troops * (1.0 - minf(0.9 * eff_mult, frac * 1.5 * eff_mult)))
	# kill boats / warships in the blast
	for ws in warships.duplicate():
		if ws.pos.distance_to(c) <= r: warships.erase(ws)
	var b_dur: float = 1.45 if r >= 6.0 * BLAST_S else 0.78
	if _qual() >= 2: b_dur = 6.0
	blasts.append({"pos": c * TS, "r": maxf(4.0, r) * TS, "t": 0.0, "dur": b_dur, "seed": cx * 73856093 ^ cy * 19349663, "kind": "nuke"})
	# Light, crisp screen shake scaled gently by blast radius (capped at 7.5 px)
	var sh_amt: float = clampf(1.8 + sqrt(maxf(1.0, r / BLAST_S)) * 0.95, 2.0, 6.5)
	_add_shake(sh_amt)

func _split_mirv_bus(ms) -> void:
	if ms.get("split_done", false): return
	ms["split_done"] = true
	var land_pt: Vector2 = ms.to
	var aim_tile := int(land_pt.y) * W + int(land_pt.x)
	var tgt_o: int = int(ms.get("tgt_o", -1))
	if aim_tile >= 0 and aim_tile < W * H and owner_map[aim_tile] > 0:
		tgt_o = owner_map[aim_tile]
	var cov: float = float(ms.get("mirv_cov", rng.randf_range(0.65, 0.85)))
	# 1. Collect target nation's tiles BEFORE the aimed impact so warheads branch across the country
	var country_tiles := []
	if tgt_o > 0 and tgt_o < nations.size() and nations[tgt_o].alive:
		var bb: Rect2i = nations[tgt_o].bb.intersection(Rect2i(0, 0, W, H))
		for y in range(bb.position.y, bb.end.y):
			for x in range(bb.position.x, bb.end.x):
				var ti := y * W + x
				if owner_map[ti] == tgt_o:
					country_tiles.append(ti)
	var hits: Array = []
	var wh_r: float = maxf(2.5 * BLAST_S, float(NUKE_R[9]))
	if not country_tiles.is_empty():
		country_tiles.shuffle()
		var desired_area: float = float(country_tiles.size()) * cov
		var single_area: float = PI * wh_r * wh_r * 0.72
		var n_wh := clampi(int(ceil(desired_area / maxf(1.0, single_area))), 8, 56)
		if float(n_wh) * single_area < desired_area:
			wh_r = clampf(sqrt(desired_area / (float(n_wh) * PI * 0.72)), wh_r, 12.0 * BLAST_S)
		var step := maxi(1, country_tiles.size() / n_wh)
		for m in n_wh:
			var cand_t: int = country_tiles[mini(country_tiles.size() - 1, m * step)]
			if cand_t != aim_tile:
				hits.append(cand_t)
	else:
		hits = ms.get("hits", [])
	# 2. First detonate right at the exact tile `ms.to` where the user aimed!
	detonate(ms.o, land_pt, maxf(wh_r, 4.0), 1.0)
	# 3. Then branch off the MIRV sub-warheads starting from the aimed landing point `land_pt` (`ms.to`)!
	for idx in hits.size():
		var h: int = hits[idx]
		var ht := Vector2(h % W + 0.5, h / W + 0.5)
		var d_vec := ht - land_pt
		if d_vec.length() < 5.5:
			var push_dir := d_vec.normalized() if d_vec.length() > 0.1 else Vector2.from_angle(float(idx) * TAU / maxf(1.0, float(hits.size())))
			ht = (land_pt + push_dir * 6.0).clamp(Vector2(2.5, 2.5), Vector2(W - 2.5, H - 2.5))
		missiles.append({
			"o": ms.o, "k": 9,
			"from": land_pt, "to": ht,
			"t": -0.02 * float(idx % 5),
			"dur": maxf(1.1, land_pt.distance_to(ht) / (36.0 * nuke_speed_mult(land_pt.distance_to(ht)))),
			"r": wh_r, "mirv": true, "branched": true,
			"tgt_o": tgt_o, "mirv_first": (idx == 0)
		})

func _tick_missiles(dt: float) -> void:
	for ms in missiles.duplicate():
		ms.t += dt
		if ms.t < ms.dur: continue
		missiles.erase(ms)
		if ms.get("mirv_bus", false):
			# MIRV carrier bus lands at the exact spot `ms.to` where the user aimed, then warheads branch off!
			_split_mirv_bus(ms)
			continue
		var tile := int(ms.to.y) * W + int(ms.to.x)
		if tile < 0 or tile >= W * H: continue
		if _sam_intercept(ms): continue
		var victim: int = owner_map[tile]
		# Every bomb (including MIRV branched warheads) ONLY creates fallout in the circular crater where it physically hits!
		detonate(ms.o, ms.to, ms.r, 0.90 if ms.k == 7 else 1.0)
		var mine: bool = ms.o == PLAYER or victim == PLAYER
		sfx("hydrogen_hit" if ms.k in [8, 11] else "atom_hit", 0.0 if mine else -8.0, 0.04, PLAYER if mine else ms.o)
		if ms.get("mirv_first", false):
			var to_id: int = int(ms.get("tgt_o", -1))
			if to_id > 0 and to_id < nations.size():
				notify("MIRV warheads struck %s" % _nname(to_id), "info")
		if ms.k in [7, 8, 11]:
			if ms.o == PLAYER: notify("%s detonated over %s" % [build_data[ms.k][1], _nname(victim)], "info")
			elif victim == PLAYER: notify("A bomb from %s hit your land" % _nname(ms.o), "bad")

# ---------- warships ----------
func _find_water_near(tile: int, max_r := 12) -> int:
	if tile < 0 or tile >= W * H: return -1
	if owner_map[tile] == WATER: return tile
	var cx := tile % W; var cy := tile / W
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r: continue
				var x := cx + dx; var y := cy + dy
				if x >= 0 and y >= 0 and x < W and y < H and owner_map[y * W + x] == WATER:
					return y * W + x
	return -1

func spawn_warship(o: int, target_tile: int = -1) -> bool:
	var ports := []
	for st in structs:
		if st.o == o and st.k == 1: ports.append(st)
	if ports.is_empty() and not (o == PLAYER and god_mode): return false
	var home_tile := -1
	var w_tile := -1
	var tgt_pos := Vector2(-1, -1)
	if target_tile >= 0 and target_tile < W * H:
		var t_pos := Vector2(target_tile % W + 0.5, target_tile / W + 0.5)
		# Pick the owned Port closest to the clicked tile
		var best_d := 1e18
		for pt in ports:
			var d := Vector2(pt.tile % W + 0.5, pt.tile / W + 0.5).distance_to(t_pos)
			if d < best_d: best_d = d; home_tile = pt.tile
		if owner_map[target_tile] == WATER:
			tgt_pos = t_pos
			# If clicked water is reasonably close to player's port/coast, spawn directly at clicked water tile!
			if best_d <= 65.0 or _find_water_near(target_tile, 0) >= 0:
				w_tile = target_tile
				if home_tile < 0: home_tile = target_tile
	if w_tile < 0 and not ports.is_empty():
		var pt = ports[rng.randi() % ports.size()]
		if home_tile < 0: home_tile = pt.tile
		w_tile = _find_water_near(home_tile, 12)
	if w_tile < 0 and o > 0 and o < nations.size() and nations[o].land > 0:
		var bb: Rect2i = nations[o].bb
		for _t in 80:
			var ti := (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
			if owner_map[ti] == o:
				var wn := _find_water_near(ti, 4)
				if wn >= 0:
					w_tile = wn
					if home_tile < 0: home_tile = ti
					break
	if w_tile < 0: return false
	var spawn_pos := Vector2(w_tile % W + 0.5, w_tile / W + 0.5)
	if tgt_pos.x < 0: tgt_pos = spawn_pos
	warships.append({"o": o, "pos": spawn_pos, "home": w_tile if home_tile < 0 else home_tile, "hp": 1000.0, "vet": 0, "kills": 0, "tgt": tgt_pos, "cd": 0.0})
	return true

func _is_water(p: Vector2) -> bool:
	var x := int(p.x); var y := int(p.y)
	return x >= 0 and y >= 0 and x < W and y < H and owner_map[y * W + x] == WATER

func _tick_warships(dt: float) -> void:
	for ws in warships.duplicate():
		if not nations[ws.o].alive: warships.erase(ws); continue
		ws.cd -= dt
		# chase nearby prey or patrol
		var prey = null
		var pd: float = 14.0 + ws.vet * 2.0
		for bt in boats:
			if bt.a == ws.o: continue
			var bp: Vector2 = _boat_pos(bt)[0] / TS
			if bp.distance_to(ws.pos) < pd: prey = bt; pd = bp.distance_to(ws.pos)
		var trade = null
		for tr in traders:
			if tr.o == ws.o: continue
			var tp: Vector2 = _path_pos(tr)[0] / TS
			if tp.distance_to(ws.pos) < 12.0: trade = tr; break
		if prey != null and ws.cd <= 0:
			boats.erase(prey); ws.cd = 2.0; _ws_kill(ws)
			if ws.o == PLAYER or prey.a == PLAYER: sfx("warship_shot")
			if ws.o == PLAYER: notify("Your warship sank a transport from %s" % _nname(prey.a), "good")
			elif prey.a == PLAYER: notify("A warship from %s sank your transport" % _nname(ws.o), "bad")
		elif trade != null and ws.cd <= 0:
			var from_o: int = trade.o
			trade.o = ws.o; ws.cd = 2.0; _ws_kill(ws)
			if ws.o == PLAYER: sfx("ka_ching")
			elif from_o == PLAYER: sfx("warship_shot")
			if ws.o == PLAYER: notify("Your warship captured a trade ship from %s" % _nname(from_o), "good")
			elif from_o == PLAYER: notify("%s captured your trade ship" % _nname(ws.o), "bad")
		# enemy warships duel (1,000 HP, 250 dmg/shell + veterancy boost)
		for ow in warships:
			if ow.o != ws.o and not allied(ws.o, ow.o) and ow.pos.distance_to(ws.pos) < 10.0 and ws.cd <= 0.0:
				ow.hp -= 250.0 * (1.0 + ws.vet * 0.2)
				ws.cd = 1.2
				shells.append({"pos": ow.pos * TS, "t": 0.0})
				if ws.o == PLAYER or ow.o == PLAYER: sfx("warship_shot")
				if ow.hp <= 0.0: _ws_kill(ws)
				break
		if ws.hp <= 0:
			warships.erase(ws)
			if ws.o == PLAYER: notify("Your warship was sunk", "bad"); sfx("warship_lost")
			continue
		# movement
		if ws.pos.distance_to(ws.tgt) < 1.5 or not _is_water(ws.tgt):
			var home := Vector2(ws.home % W, ws.home / W)
			for k in 20:
				var c := home + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
				if _is_water(c): ws.tgt = c; break
		var dir: Vector2 = (ws.tgt - ws.pos).normalized()
		var np: Vector2 = ws.pos + dir * 9.0 * dt
		if _is_water(np): ws.pos = np
		else:
			ws.tgt = ws.pos

func _ws_kill(ws) -> void:
	ws.kills += 1
	if ws.kills % 2 == 0 and ws.vet < 5:
		ws.vet += 1; ws.hp = 1000.0
		if ws.o == PLAYER: notify("Your warship reached veterancy %d" % ws.vet, "good")

# ---------- trade ----------
func _water_path(from_tile: int, to_tile: int, max_nodes := 14000) -> PackedVector2Array:
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array()
	for d in [1, -1, W, -W]:
		if (d == 1 and to_tile % W == W - 1) or (d == -1 and to_tile % W == 0): continue
		var j: int = to_tile + d
		if j >= 0 and j < W * H and owner_map[j] == WATER:
			bfs_par[j] = -1; bfs_stamp[j] = gen; q.append(j)
	var qi := 0
	var found := -1
	var fx := from_tile % W; var fy := from_tile / W
	while qi < q.size() and qi < max_nodes:
		var i: int = q[qi]; qi += 1
		if absi(i % W - fx) <= 1 and absi(i / W - fy) <= 1: found = i; break
		for d in [1, -1, W, -W]:
			if (d == 1 and i % W == W - 1) or (d == -1 and i % W == 0): continue
			var j: int = i + d
			if j >= 0 and j < W * H and owner_map[j] == WATER and bfs_stamp[j] != gen:
				bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	if found < 0: return PackedVector2Array()
	var path := []
	var k := found
	while k != -1:
		path.append(k); k = bfs_par[k]
	return _smooth_path(path, to_tile)

func _path_pos(tr) -> Array:
	return _boat_pos(tr)

func trade_ship_gold(dist_tiles: float, lvl_mult := 1.0) -> float:
	# OpenFront nonlinear distance formula scaled for 640x352 map (dist_equiv = dist_tiles * 2.0)
	return floor(sim_rules.trade_gold(dist_tiles) * lvl_mult)

func _pick_trade_endpoint(o: int) -> Dictionary:
	# If nation 'o' has at least one completed Port, trade ships ONLY spawn from / dock at its Port(s)!
	var my_ports := []
	for st in structs:
		if st.o == o and st.k == 1 and st.get("bt", 0.0) <= 0.0:
			my_ports.append(st)
	if not my_ports.is_empty():
		return my_ports[rng.randi() % my_ports.size()]
	# Otherwise (0 Ports owned by 'o'), trade ships can spawn from any coastal tile owned by 'o'
	if o <= 0 or o >= nations.size() or not nations[o].alive or nations[o].land <= 0:
		return {}
	var bb: Rect2i = nations[o].bb
	for _t in 28:
		var ti := (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
		if ti >= 0 and ti < W * H and owner_map[ti] == o and _coastal(ti):
			return {"o": o, "tile": ti, "level": 0, "k": -1}
	return {}

func _spawn_trade_ship_pair(a: Dictionary, b: Dictionary, allow_bfs: bool) -> bool:
	if a.is_empty() or b.is_empty() or a.tile == b.tile or is_embargoed(a.o, b.o): return false
	var key := "t%d:%d" % [a.tile, b.tile]
	var pts: PackedVector2Array
	var cum: PackedFloat32Array
	if path_cache.has(key):
		var entry: Array = path_cache[key]
		pts = entry[0]
		if entry.size() >= 3:
			cum = entry[2]
		else:
			cum = PackedFloat32Array([0.0])
			for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
			entry.append(cum)
	elif allow_bfs:
		pts = _water_path(a.tile, b.tile)
		cum = PackedFloat32Array([0.0])
		for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
		path_cache[key] = [pts, elapsed, cum]
	else:
		return false
	if pts.size() < 2: return false
	var dist_tiles: float = cum[cum.size() - 1] / TS
	var lmult: float = 0.7 + 0.25 * float(int(a.get("level", 0)) + int(b.get("level", 0)))
	traders.append({"o": a.o, "pts": pts, "cum": cum, "d": 0.0, "dst": b, "gold": trade_ship_gold(dist_tiles, lmult)})
	return true

func _tick_trade(dt: float) -> void:
	# spawning happens per tick in sim_naval.tick() (RoWorld ports_tick)
	for tr in traders.duplicate():
		tr.d += dt * sim_rules.ship_tiles_per_s() * boat_speed * TS
		var cum: PackedFloat32Array = tr.cum
		if tr.d >= cum[cum.size() - 1]:
			traders.erase(tr)
			if nations[tr.o].alive:
				nations[tr.o].gold += tr.gold
			var dst: Dictionary = tr.dst
			var dst_o: int = int(dst.get("o", 0))
			if dst_o > 0 and dst_o != tr.o and dst_o < nations.size() and nations[dst_o].alive and not sim_naval.hostile(tr.o, dst_o):
				nations[dst_o].gold += tr.gold
				if tr.o == PLAYER or dst_o == PLAYER:
					var ppos := Vector2(int(dst.tile) % W + 0.5, int(dst.tile) / W + 0.5) * TS
					add_float(ppos, "+%s" % _fmt(tr.gold), GOLD_C)

# ---------- rail networks & moving gold trains (OpenFront v24+) ----------
func _is_land_tile(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and owner_map[y * W + x] >= 0

func _land_los(a: Vector2, b: Vector2) -> bool:
	var n := maxi(2, int(a.distance_to(b) * 2.0))
	for k in range(n + 1):
		var p := a.lerp(b, float(k) / float(n))
		if not _is_land_tile(int(p.x), int(p.y)): return false
	return true

func _bezier_on_land(p0: Vector2, pc: Vector2, p1: Vector2, steps := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for m in range(steps + 1):
		var u: float = float(m) / float(steps)
		var om := 1.0 - u
		var p: Vector2 = om * om * p0 + 2.0 * om * u * pc + u * u * p1
		if not _is_land_tile(int(p.x), int(p.y)):
			return PackedVector2Array()
		pts.append(p)
	for m in range(1, pts.size()):
		if not _land_los(pts[m - 1], pts[m]):
			return PackedVector2Array()
	return pts

func _smooth_land_chain(raw: PackedVector2Array) -> PackedVector2Array:
	if raw.size() <= 2: return raw
	var pulled := PackedVector2Array([raw[0]])
	var idx := 0
	while idx < raw.size() - 1:
		var j := mini(raw.size() - 1, idx + 10)
		while j > idx + 1 and not _land_los(raw[idx], raw[j]): j -= 1
		pulled.append(raw[j]); idx = j
	var pts := pulled
	for _it in 3:
		if pts.size() < 3: break
		var np := PackedVector2Array([pts[0]])
		for m in pts.size() - 1:
			var p0: Vector2 = pts[m]; var p1: Vector2 = pts[m + 1]
			var q0 := p0.lerp(p1, 0.25); var q1 := p0.lerp(p1, 0.75)
			if _land_los(p0, q0) and _land_los(q0, q1) and _land_los(q1, p1):
				np.append(q0); np.append(q1)
			else:
				np.append(p0); np.append(p1)
		np.append(pts[pts.size() - 1])
		pts = np
	return pts

func _land_bfs_points(from_t: int, to_t: int, max_visit := 26000) -> PackedVector2Array:
	if from_t == to_t:
		return PackedVector2Array([Vector2(from_t % W + 0.5, from_t / W + 0.5)])
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array([to_t])
	bfs_par[to_t] = -1; bfs_stamp[to_t] = gen
	var qi := 0
	var found := -1
	var dirs8 := [1, -1, W, -W, W + 1, W - 1, -W + 1, -W - 1]
	while qi < q.size() and qi < max_visit:
		var i: int = q[qi]; qi += 1
		if i == from_t: found = i; break
		var ix := i % W
		for d in dirs8:
			var j: int = i + d
			if j < 0 or j >= W * H or absi((j % W) - ix) > 1: continue
			if owner_map[j] >= 0 and bfs_stamp[j] != gen:
				if absi(d) != 1 and absi(d) != W:
					if owner_map[i + (j % W - ix)] < 0 or owner_map[j - (j % W - ix)] < 0: continue
				bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	if found < 0:
		return PackedVector2Array()
	var raw := PackedVector2Array()
	var k := found
	while k != -1:
		raw.append(Vector2(k % W + 0.5, k / W + 0.5)); k = bfs_par[k]
	return raw

func _water_crossing_spans(a: Vector2, b: Vector2) -> Array:
	# Returns [[w_start, w_end], ...] along straight line a -> b where tiles are WATER
	var spans := []
	var dist := a.distance_to(b)
	if dist < 0.5: return spans
	var steps := maxi(8, int(dist * 3.0))
	var in_water := false
	var w0 := Vector2.ZERO
	for k in range(steps + 1):
		var u: float = float(k) / float(steps)
		var p := a.lerp(b, u)
		var is_w := not _is_land_tile(int(p.x), int(p.y))
		if is_w and not in_water:
			in_water = true
			w0 = a.lerp(b, maxf(0.0, float(k - 1) / float(steps)))
		elif not is_w and in_water:
			in_water = false
			spans.append([w0, p])
	if in_water:
		spans.append([w0, b])
	return spans

func _axis_land(a: Vector2i, b: Vector2i) -> bool:
	# a->b must be horizontal or vertical; every tile on it must be land
	var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		if not _is_land_tile(p.x, p.y): return false
		if p == b: return true
		p += d
	return true

func _land_bfs4(from_t: int, to_t: int, max_visit := 30000) -> PackedInt32Array:
	if bfs_par.size() != W * H:
		bfs_par.resize(W * H); bfs_stamp.resize(W * H); bfs_stamp.fill(0)
	bfs_gen += 1
	var gen := bfs_gen
	var q := PackedInt32Array([to_t]); bfs_par[to_t] = -1; bfs_stamp[to_t] = gen
	var qi := 0; var found := -1
	while qi < q.size() and qi < max_visit:
		var i: int = q[qi]; qi += 1
		if i == from_t: found = i; break
		var ix := i % W
		for d in [1, -1, W, -W]:
			if (d == 1 and ix == W - 1) or (d == -1 and ix == 0): continue
			var j: int = i + d
			if j < 0 or j >= W * H or owner_map[j] < 0 or bfs_stamp[j] == gen: continue
			bfs_par[j] = i; bfs_stamp[j] = gen; q.append(j)
	var out := PackedInt32Array()
	if found < 0: return out
	var k := found
	while k != -1: out.append(k); k = bfs_par[k]
	return out

func _rail_curve(tile_a: int, tile_b: int) -> Array:
	# Square-grid roads: horizontal/vertical segments only (Manhattan L-shapes), land-only.
	var lo_t := mini(tile_a, tile_b)
	var hi_t := maxi(tile_a, tile_b)
	var key := "r%d:%d" % [lo_t, hi_t]
	if rail_cache.has(key):
		return rail_cache[key]
	var A := Vector2i(lo_t % W, lo_t / W); var B := Vector2i(hi_t % W, hi_t / W)
	var corners := []
	var c1 := Vector2i(B.x, A.y); var c2 := Vector2i(A.x, B.y)
	if _axis_land(A, c1) and _axis_land(c1, B): corners = [A, c1, B]
	elif _axis_land(A, c2) and _axis_land(c2, B): corners = [A, c2, B]
	elif _rail_bfs_left <= 0:
		_rail_pending = true
		return []
	else:
		_rail_bfs_left -= 1
		var raw := _land_bfs4(lo_t, hi_t)
		var man := absi(A.x - B.x) + absi(A.y - B.y)
		if raw.size() >= 2 and raw.size() <= man * 2 + 24:
			# collapse to few axis-aligned runs: greedily extend L-shortcuts along the path
			var cells := []
			for t in raw: cells.append(Vector2i(t % W, t / W))
			corners = [cells[0]]
			var idx := 0
			while idx < cells.size() - 1:
				var j := cells.size() - 1
				var via = null
				while j > idx + 1:
					var p0: Vector2i = cells[idx]; var p1: Vector2i = cells[j]
					if p0.x == p1.x or p0.y == p1.y:
						if _axis_land(p0, p1): break
					else:
						var e1 := Vector2i(p1.x, p0.y); var e2 := Vector2i(p0.x, p1.y)
						if _axis_land(p0, e1) and _axis_land(e1, p1): via = e1; break
						if _axis_land(p0, e2) and _axis_land(e2, p1): via = e2; break
					j -= 1
				if via != null: corners.append(via)
				corners.append(cells[j]); idx = j
	if corners.size() < 2:
		rail_cache[key] = []
		return []
	var pts := PackedVector2Array()
	for c in corners:
		var v := Vector2(c.x + 0.5, c.y + 0.5)
		if pts.size() >= 1 and pts[pts.size() - 1] == v: continue
		# merge collinear runs
		if pts.size() >= 2:
			var u := pts[pts.size() - 2]; var w := pts[pts.size() - 1]
			if (u.x == w.x and w.x == v.x) or (u.y == w.y and w.y == v.y): pts[pts.size() - 1] = v; continue
		pts.append(v)
	if pts.size() < 2:
		rail_cache[key] = []
		return []
	var cum := PackedFloat32Array([0.0])
	for m in range(1, pts.size()): cum.append(cum[m - 1] + pts[m].distance_to(pts[m - 1]))
	var res := [pts, cum, []]
	rail_cache[key] = res
	return res

const RAIL_KINDS := [0, 1, 2, 3, 4, 5]  # city, port, factory, defense post, SAM, silo: any two can be linked
var _rail_nb_cache := {}
var _own_sv := {}
var _rail_calc_left := 40
var _rail_bfs_left := 4  # land BFS route searches allowed per frame (26k nodes each)
var _rail_pending := false
var rail_cache := {}  # rail geometry, separate from boat path_cache (which is flushed at 400 entries)
var _rail_nb_ver := ""
func _rail_neighbors(st) -> Array:
	if not (st.k in RAIL_KINDS) or st.get("bt", 0.0) > 0.0: return []
	# per-owner cache: one nation building something no longer invalidates everyone's rail web
	var ver := "%d|%d|%d|%d" % [st.o, _own_sv.get(st.o, 0), allies.size(), embargoes.size()]
	var ce = _rail_nb_cache.get(st.tile)
	if ce != null and ce[0] == ver and elapsed - float(ce[1]) < 6.0: return ce[2]
	if _rail_calc_left <= 0 and ce != null: return ce[2]  # over this frame's budget: reuse the stale list
	_rail_calc_left -= 1
	_rail_pending = false
	var r := _rail_neighbors_calc(st)
	if not _rail_pending: _rail_nb_cache[st.tile] = [ver, elapsed, r]
	return r

const FACTORY_RANGE := 60.0  # tiles: roads/rails may only link structures inside one factory's range
func _factories_covering(o: int, p: Vector2) -> Array:
	var out := []
	for f in structs:
		if f.k == 2 and f.o == o and f.get("bt", 0.0) <= 0.0:
			if Vector2(f.tile % W + 0.5, f.tile / W + 0.5).distance_to(p) <= FACTORY_RANGE: out.append(f)
	return out

# Minimum spanning tree (Manhattan weight) per owner: each structure joins the road network once.
# An edge is allowed only if both ends sit inside the same factory's range.
var _rail_mst := {}  # owner -> [ver, {tile: [structs]}]
func _rail_neighbors_calc(st) -> Array:
	var ver := "%d|%d|%d" % [st.o, _own_sv.get(st.o, 0), int(elapsed / 6.0)]
	var ce = _rail_mst.get(st.o)
	if ce == null or ce[0] != ver:
		var adj := _build_rail_mst(st.o)
		if adj.is_empty() and _rail_pending: return [] if ce == null else ce[1].get(st.tile, [])
		ce = [ver, adj]
		if not _rail_pending: _rail_mst[st.o] = ce
	return ce[1].get(st.tile, [])

func _uf_find(par: Array, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]; x = par[x]
	return x

func _build_rail_mst(o: int) -> Dictionary:
	var nodes := []; var facs := []
	for c in structs:
		if c.o != o or c.get("bt", 0.0) > 0.0: continue
		if c.k == 2: facs.append(Vector2(c.tile % W + 0.5, c.tile / W + 0.5))
		if c.k in RAIL_KINDS: nodes.append(c)
	var adj := {}
	if facs.is_empty() or nodes.size() < 2: return adj
	var R2 := FACTORY_RANGE * FACTORY_RANGE
	var cov := []  # per node: bitset-ish list of factory indices covering it
	for nd in nodes:
		var p := Vector2(nd.tile % W + 0.5, nd.tile / W + 0.5); var l := []
		for fi in facs.size():
			if facs[fi].distance_squared_to(p) <= R2: l.append(fi)
		cov.append(l)
	var edges := []
	for i in nodes.size():
		if cov[i].is_empty(): continue
		var ti: int = nodes[i].tile
		for j in range(i + 1, nodes.size()):
			if cov[j].is_empty(): continue
			var share := false
			for f in cov[i]:
				if f in cov[j]: share = true; break
			if not share: continue
			var tj: int = nodes[j].tile
			edges.append([absi(ti % W - tj % W) + absi(ti / W - tj / W), i, j])
	edges.sort_custom(func(x, y): return x[0] < y[0])
	var par := []; par.resize(nodes.size())
	for i in nodes.size(): par[i] = i
	for e in edges:
		var ri: int = _uf_find(par, e[1]); var rj: int = _uf_find(par, e[2])
		if ri == rj: continue
		var a = nodes[e[1]]; var b = nodes[e[2]]
		if _rail_curve(a.tile, b.tile).is_empty(): continue
		par[ri] = rj
		if not adj.has(a.tile): adj[a.tile] = []
		if not adj.has(b.tile): adj[b.tile] = []
		adj[a.tile].append(b); adj[b.tile].append(a)
	return adj

func _has_rail_link(st_a, st_b) -> bool:
	if st_a == null or st_b == null or st_a == st_b: return false
	if struct_at.get(st_a.tile) != st_a or struct_at.get(st_b.tile) != st_b: return false
	if st_b in _rail_neighbors(st_a): return true
	if st_a in _rail_neighbors(st_b): return true
	return false

func _connected_rail_stations(st) -> Array:
	return _rail_neighbors(st)

func _rail_len(st_a, st_b) -> float:
	var rc := _rail_curve(st_a.tile, st_b.tile)
	if rc.is_empty(): return 20.0
	var cum: PackedFloat32Array = rc[1]
	return maxf(1.0, cum[cum.size() - 1])

func spawn_train_from(st) -> bool:
	if not (st.k in RAIL_KINDS) or st.get("bt", 0.0) > 0.0: return false
	var nbrs := _connected_rail_stations(st)
	if nbrs.is_empty(): return false
	var dst = nbrs[rng.randi() % nbrs.size()]
	var a := Vector2(st.tile % W + 0.5, st.tile / W + 0.5)
	var b := Vector2(dst.tile % W + 0.5, dst.tile / W + 0.5)
	var rlen := _rail_len(st, dst)
	trains.append({
		"o": st.o, "src": st, "dst": dst,
		"from": a, "to": b, "t": 0.0,
		"dur": maxf(1.2, rlen / (16.0 + 2.0 * int(st.get("level", 1)))),
		"stops": 1, "lvl": int(st.get("level", 1))
	})
	return true

func _tick_trains(dt: float) -> void:
	train_t += dt
	# Trucks/trains spawn way less frequently (every 8.5s, max 12 active, max 1 per Factory) and do a single one-way delivery
	if train_t >= 8.5:
		train_t = 0.0
		for _pick in mini(16, structs.size()):
			var st = structs[rng.randi() % structs.size()]
			if st.k in RAIL_KINDS and st.get("bt", 0.0) <= 0.0 and trains.size() < 24:
				var has_tr := false
				for tr0 in trains:
					if tr0.src == st: has_tr = true; break
				if not has_tr and rng.randf() < 0.35:
					spawn_train_from(st)
					if trains.size() >= 24: break
	for tr in trains.duplicate():
		if not _has_rail_link(tr.src, tr.dst):
			trains.erase(tr); continue
		tr.o = tr.src.o
		tr.t += dt
		if tr.t < tr.dur: continue
		var dst = tr.dst
		if not (dst in structs) or not nations[tr.o].alive or is_embargoed(tr.o, dst.o):
			trains.erase(tr); continue
		# RoWorld trainGold: self 10k / ally 35k / other 25k (-5k per stop past the 9th), paid at city/port stops
		var rel := "self" if dst.o == tr.o else ("ally" if allied(tr.o, dst.o) else "other")
		var pay: float = SimRules.train_gold(rel, int(tr.get("stops", 0))) if dst.k in [0, 1] else 0.0
		if pay <= 0.0:
			trains.erase(tr); continue
		nations[tr.o].gold += pay
		if dst.o != tr.o and nations[dst.o].alive:
			nations[dst.o].gold += pay
		if tr.o == PLAYER or dst.o == PLAYER:
			add_float(tr.to * TS, "+%s" % _fmt(pay), GOLD_C)
		trains.erase(tr)

# ---------- construction, artillery & SAM slot cooldowns ----------
func _tick_artillery(dt: float) -> void:
	for st in structs:
		if st.get("bt", 0.0) > 0.0:
			st.bt = maxf(0.0, float(st.bt) - dt)
			continue
		st.cd = maxf(0.0, float(st.cd) - dt)
		if st.has("slots"):
			var sl: Array = st.slots
			for m in sl.size():
				if float(sl[m]) > 0.0: sl[m] = maxf(0.0, float(sl[m]) - dt)
		# Artillery per-structure firing interval: 2.0s / 2^(level - 1)
		if st.k == 10 and st.cd <= 0.0:
			var lvl := int(st.get("level", 1))
			st.cd = (2.0 / pow(2.0, float(lvl - 1))) * reload_mult()
			var c := Vector2(st.tile % W, st.tile / W)
			for k in 30:
				var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 45)
				var x := int(p.x); var y := int(p.y)
				if x < 0 or y < 0 or x >= W or y >= H: continue
				var ow: int = owner_map[y * W + x]
				if ow > 0 and ow != st.o and not allied(st.o, ow):
					var n = nations[ow]
					n.troops = maxf(0.0, n.troops * (1.0 - rng.randf_range(0.001, 0.01)))
					shells.append({"pos": (p + Vector2(0.5, 0.5)) * TS, "t": 0.0})
					for tst in structs:
						if tst.o == ow and Vector2(tst.tile % W, tst.tile / W).distance_to(p) < 6:
							tst.hits += 1
							if tst.hits >= 15:
								_struct_remove(tst)
								if ow == PLAYER: notify("Artillery from %s destroyed your %s" % [_nname(st.o), build_data[tst.k][1]], "bad")
							break
					break

var fx_freeze := false
func _tick_fx(dt: float) -> void:
	for b in ([] if fx_freeze else blasts.duplicate()):
		b.t += dt
		var bdur: float = float(b.get("dur", 1.35))
		if b.t >= bdur: blasts.erase(b)
	for s2 in shells.duplicate():
		s2.t += dt
		if s2.t > 0.5: shells.erase(s2)
	for fl in floats.duplicate():
		fl.t += dt
		if fl.t > 1.4: floats.erase(fl)
	fallout_tick_t += dt
	if fallout_tick_t >= 2.0:
		var step := fallout_tick_t
		fallout_tick_t = 0.0
		# only the tiles that actually carry fallout (was a 2.87M-tile scan every 2 s -> hitch)
		var q2 := _qual() >= 2
		for i in fallout_list.keys():
			if fallout[i] != 1: fallout_list.erase(i); continue
			fallout_t[i] -= step
			if fallout_t[i] > 30.0 and q2: _pend_paint[i] = true; dirty = true
			if fallout_t[i] <= 0.0:
				fallout[i] = 0; fallout_t[i] = 0.0; fallout_list.erase(i); _repaint(i)

func _tick_notes(rdt: float) -> void:
	var ch := false
	for nt in notes.duplicate():
		nt.t += rdt
		if nt.t > 7.0: notes.erase(nt); ch = true
	if ch or not notes.is_empty(): note_box.queue_redraw()

# ---------- protagonist AI ----------
func _prot_ai(id: int, n) -> void:
	if n.land < 10: return
	# 1. Nukes FIRST after peace window so AIs don't spend all their nuke money on small buildings!
	if elapsed > peace and owned(id, 5) > 0 and n.gold >= 750e3 and elapsed - n.get("last_nuke", -1e9) > 18.0:
		var target := -1
		var best := 0.0
		var maxr := 0.0
		for kk in [9, 8, 11, 7, 12]:
			if kk == 9 and not mirv_enabled: continue
			if n.gold >= nuke_cost(kk): maxr = maxf(maxr, nuke_range(kk))
		if icbm_mode: maxr = INF
		var my_silos := PackedVector2Array()
		for st0 in structs:
			if st0.o == id and st0.k == 5 and st0.get("bt", 0.0) <= 0.0: my_silos.append(Vector2(st0.tile % W + 0.5, st0.tile / W + 0.5))
		var maxr2 := maxr * maxr
		for o in range(1, nations.size()):
			if o == id or not nations[o].alive or nations[o].land < 15 * BLAST_S * BLAST_S or allied(id, o): continue
			if maxr2 < INF:
				var tpo := Vector2(nations[o].sx / maxf(1, nations[o].land), nations[o].sy / maxf(1, nations[o].land))
				var reach := false
				for sp in my_silos:
					if sp.distance_squared_to(tpo) <= maxr2: reach = true; break
				if not reach: continue
			var sc: float = nations[o].land * (2.2 if o == PLAYER else (1.5 if is_prot(o) else 0.8)) * rng.randf_range(0.7, 1.3)
			if sc > best: best = sc; target = o
		if target > 0:
			var t = nations[target]
			var ti := int(t.sy / maxf(1, t.land)) * W + int(t.sx / maxf(1, t.land))
			var nk := 7
			if mirv_enabled and n.gold >= 25.5e6 and rng.randf() < 0.4: nk = 9
			elif n.gold >= 5.2e6 and rng.randf() < 0.5: nk = 8
			elif n.gold >= 3.6e6 and rng.randf() < 0.45: nk = 12
			elif n.gold >= 2.6e6 and rng.randf() < 0.5: nk = 11
			if not icbm_mode:
				var dd := _any_silo_dist(id, Vector2(ti % W + 0.5, ti / W + 0.5))
				if dd > nuke_range(nk):
					nk = -1
					for kk in [12, 7, 11, 8, 9]:  # cheapest weapon that reaches
						if kk == 9 and not mirv_enabled: continue
						if nuke_range(kk) >= dd and n.gold >= nuke_cost(kk): nk = kk; break
			if nk > 0 and launch_nuke(id, nk, ti):
				n.last_nuke = elapsed
				return
	# 2. Prioritize building a Missile Silo (k == 5) once the AI has at least 1-2 basic structures
	if owned_count(id, 5) == 0 and (owned_count(id, 0) + owned_count(id, 1) + owned_count(id, 2) >= 1 or elapsed > peace * 0.5):
		if n.gold >= 1.0e6:
			var bb_s: Rect2i = n.bb
			for _tries in 24:
				var ti := (bb_s.position.y + rng.randi() % maxi(1, bb_s.size.y)) * W + bb_s.position.x + rng.randi() % maxi(1, bb_s.size.x)
				if owner_map[ti] == id and try_build(5, ti, id): return
		elif n.gold >= 350e3:
			# Save gold for the Missile Silo instead of draining it on small buildings!
			return
	# If AI already has a Silo and peace is over, keep 800k in reserve for Atom Bombs if Silo is ready
	var reserve := 800e3 if (owned_count(id, 5) > 0 and elapsed > peace) else 0.0
	# 3. Build economy & military (including Airfield k == 14)
	var order := [1, 0, 2, 5, 14, 3, 4, 10, 0, 1]
	for k in order:
		var cost := build_cost(id, k)
		if n.gold - reserve < cost * 1.05: continue
		if k in UPGRADABLE and rng.randf() < 0.30:
			for st in structs:
				if st.o == id and st.k == k and int(st.get("level", 1)) < 3:
					if try_build(k, st.tile, id): return
		if k == 1 or owned_count(id, k) < 1 + int(n.land * TILE_NORM) / 350:
			for tries in 14:
				var bb: Rect2i = n.bb
				var ti := (bb.position.y + rng.randi() % maxi(1, bb.size.y)) * W + bb.position.x + rng.randi() % maxi(1, bb.size.x)
				if owner_map[ti] != id: continue
				if try_build(k, ti, id): return
	# 4. Warships
	if owned(id, 1) > 0 and n.gold - reserve > 400e3 and _count_ws(id) < 3:
		n.gold -= 250e3; spawn_warship(id); return

func _count_ws(o: int) -> int:
	var c := 0
	for ws in warships: if ws.o == o: c += 1
	return c

func _neighbour_count(tile: int) -> int:
	if neigh_cache[0] == tile: return neigh_cache[1]
	var seen := {}
	var cx := tile % W; var cy := tile / W
	for k in 300:
		var p := Vector2(cx, cy) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2, 30)
		var x := int(p.x); var y := int(p.y)
		if x < 0 or y < 0 or x >= W or y >= H: continue
		var o: int = owner_map[y * W + x]
		if o > 1: seen[o] = true
	neigh_cache = [tile, seen.size()]
	return seen.size()

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


# ---- RoWorld art (AGPL-3.0, assets/): loaded at runtime from PNG bytes, no import needed ----
var _tex_cache := {}
const ST_COL := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 6, 14: 7, 15: 8}
const SHAPE_SCALE := [1.0, 1.0, 1.12, 1.1, 1.15, 1.3, 1.2, 1.35, 1.25]
const ICON_FILL := [0.78, 0.74, 0.74, 0.74, 0.8, 0.76, 0.82, 0.8, 0.86]
const UI_TEX := {0: "ui/city.png", 1: "ui/port.png", 2: "ui/factory.png", 3: "ui/defense.png", 4: "ui/sam.png", 5: "ui/silo.png", 6: "ui/warship.png", 7: "ui/atom.png", 8: "ui/hydrogen.png", 9: "ui/mirv.png", 10: "ui/artillery.png", 11: "arsenal/ui/mega.png", 12: "arsenal/ui/scatter.png", 13: "arsenal/ui/reinforce.png", 14: "ui/airfield.png", 15: "ui/railgun.png", 16: "ui/icbm.png"}

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


var cap_fx := {}
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

func _draw_capture_fx() -> void:
	if cap_fx.is_empty(): return
	var dur := 0.7
	var tz := TS * cam.zoom.x
	var vr := Rect2(Vector2(-tz, -tz), get_viewport_rect().size + Vector2(tz, tz) * 2)
	var dead := []
	for i in cap_fx:
		var u: float = (map_t - float(cap_fx[i][0])) / dur
		if u >= 1.0: dead.append(i); continue
		var p := _screen_of(Vector2(i % W, i / W) * TS)
		if not vr.has_point(p): continue
		var c: Color = cap_fx[i][1]
		var e := 1.0 - u
		overlay.draw_rect(Rect2(p, Vector2(tz, tz)), Color(c.lightened(0.55 * e), 0.6 * e * e))
	for i in dead: cap_fx.erase(i)

func _world_fx_anim(z: float) -> void:
	pass

func _draw_world_fx(z: float) -> void:
	_draw_capture_fx()
	_draw_meta_fx(z)
	# railways: factories to nearby owned/allied cities, ports, and factories
	var drawn_rails := {}
	var vr := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(FACTORY_RANGE * 2.0 * TS * z)
	for st in structs:
		if not (st.k in RAIL_KINDS) or st.get("bt", 0.0) > 0.0: continue
		if not vr.has_point(_screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)): continue
		var nbrs := _rail_neighbors(st)
		for c in nbrs:
			var rkey := "%d:%d" % [mini(st.tile, c.tile), maxi(st.tile, c.tile)]
			if drawn_rails.has(rkey): continue
			drawn_rails[rkey] = true
			var rcol := GOLD_C if c.o != st.o else Color(0.95, 0.95, 0.98, 0.88)
			_draw_railway(st, c, rcol)
	# moving gold trains strictly following the drawn canonical railway tracks
	for tr in trains:
		if not _has_rail_link(tr.src, tr.dst): continue
		var f: float = clampf(tr.t / maxf(0.01, tr.dur), 0.0, 1.0)
		var rp := _rail_pos(tr.src, tr.dst, f)
		var sp := _screen_of(rp[0] * TS)
		var dir: Vector2 = rp[1]
		var tot_tiles: float = rp[2]
		var nrm := Vector2(-dir.y, dir.x)
		var col: Color = nations[tr.o].color
		# cargo car follows the track behind the locomotive
		var f_car: float = clampf(f - 2.6 / maxf(4.0, tot_tiles), 0.0, 1.0)
		var rp_car := _rail_pos(tr.src, tr.dst, f_car)
		var car_c := _screen_of(rp_car[0] * TS)
		var cdir: Vector2 = rp_car[1]
		var cnrm := Vector2(-cdir.y, cdir.x)
		overlay.draw_line(sp, car_c, Color(0.1, 0.1, 0.14), 2.0)
		var car := PackedVector2Array([car_c + cdir * 3.5 + cnrm * 3.2, car_c - cdir * 3.5 + cnrm * 3.2, car_c - cdir * 3.5 - cnrm * 3.2, car_c + cdir * 3.5 - cnrm * 3.2])
		if not _unit_sprite(car_c, 11, GOLD_C, 11.0, cdir.angle()):
			overlay.draw_colored_polygon(car, GOLD_C.darkened(0.1))
		var qq := _q()
		if qq >= 1:
			var f_car2: float = clampf(f - 5.0 / maxf(4.0, tot_tiles), 0.0, 1.0)
			var rp2 := _rail_pos(tr.src, tr.dst, f_car2)
			var c2 := _screen_of(rp2[0] * TS); var d2: Vector2 = rp2[1]; var n2 := Vector2(-d2.y, d2.x)
			overlay.draw_line(car_c, c2, Color(0.1, 0.1, 0.14), 2.0)
			overlay.draw_colored_polygon(PackedVector2Array([c2 + d2 * 3.5 + n2 * 3.2, c2 - d2 * 3.5 + n2 * 3.2, c2 - d2 * 3.5 - n2 * 3.2, c2 + d2 * 3.5 - n2 * 3.2]), col.darkened(0.15))
		if qq >= 2:
			var np_: int = 4 if qq == 2 else 8
			for k in np_:
				var ph := fmod(map_t * 1.3 + float(k) / np_ + float(hash(tr.src) % 97) * 0.37, 1.0)
				var sp_p := sp + dir * 2.0 - dir * ph * 16.0 + Vector2(0, -ph * 10.0) + nrm * sin(ph * 6.0 + k) * 2.0
				overlay.draw_circle(sp_p, 1.6 + ph * 3.6, Color(0.92, 0.92, 0.95, 0.5 * (1.0 - ph)))
		# locomotive
		var loco := PackedVector2Array([sp + dir * 7, sp + dir * 3 + nrm * 4, sp - dir * 6 + nrm * 4, sp - dir * 6 - nrm * 4, sp + dir * 3 - nrm * 4])
		if not _unit_sprite(sp, 9, col, 12.0, dir.angle()):
			overlay.draw_colored_polygon(loco, col.lightened(0.15))
			overlay.draw_polyline(loco + PackedVector2Array([loco[0]]), Color(0.08, 0.08, 0.12), 1.5)
			overlay.draw_circle(sp + dir * 2, 2.2, GOLD_C)
	for st in structs:
		var t: int = st.tile
		var sp := _screen_of(Vector2(t % W + 0.5, t / W + 0.5) * TS)
		var bt: float = st.get("bt", 0.0)
		var cd: float = float(st.get("cd", 0.0))
		_map_icon(sp, st.k, nations[st.o].color, 0.55 if bt > 0.0 else 1.0)
		if bt > 0.0:
			var bmax: float = maxf(0.01, float(st.get("bmax", 2.0)))
			var prog: float = clampf(1.0 - bt / bmax, 0.0, 1.0)
			overlay.draw_arc(sp, 12.5, -PI / 2, -PI / 2 + TAU * prog, 24, ORANGE_Y, 2.6, true)
		elif cd > 0.0 and st.k in [4, 5, 14]:
			var cmax: float = maxf(0.1, float(st.get("cmax", 9.0)))
			var rprog: float = clampf(1.0 - cd / cmax, 0.0, 1.0)
			var ccol := CYAN if st.k == 14 else RED
			overlay.draw_arc(sp, 12.0, 0, TAU, 24, Color(0, 0, 0, 0.55), 2.8, true)
			overlay.draw_arc(sp, 12.0, -PI / 2, -PI / 2 + TAU * rprog, 24, ccol, 2.4, true)
		var lvl := int(st.get("level", 1))
		if lvl > 1:
			var badge_p := sp + Vector2(6, -11)
			overlay.draw_rect(Rect2(badge_p, Vector2(22, 12)), Color(0.06, 0.08, 0.15, 0.92))
			overlay.draw_rect(Rect2(badge_p, Vector2(22, 12)), GOLD_C, false, 1.0)
			f_bold.draw_string(overlay.get_canvas_item(), badge_p + Vector2(2, 10), "Lv%d" % lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD_C)
	# trade ships: clear gold-hulled cargo ships with wake and sea-lane line (with smooth heading interpolation)
	for tr in traders:
		var bp := _boat_pos(tr)
		var p0 := _screen_of(bp[0])
		if p0.x < -40 or p0.y < -40 or p0.x > 1640 or p0.y > 940: continue
		var raw_dir: Vector2 = bp[1]
		if raw_dir == Vector2.ZERO: raw_dir = Vector2.RIGHT
		var dir: Vector2 = _sdir(tr, raw_dir)
		var nrm := Vector2(-dir.y, dir.x)
		_wake(p0, dir, 6.0)
		var ocol: Color = nations[tr.o].color if (tr.o > 0 and tr.o < nations.size()) else GOLD_C
		if _unit_sprite(p0, 1, ocol, 15.0, dir.angle()): continue
		overlay.draw_line(p0 - dir * 10.5, p0 - dir * 3.0, Color(1, 1, 1, 0.55), 2.2)
		var hull := PackedVector2Array([
			p0 + dir * 7.5,
			p0 + dir * 2.5 + nrm * 3.8,
			p0 - dir * 6.5 + nrm * 3.4,
			p0 - dir * 6.5 - nrm * 3.4,
			p0 + dir * 2.5 - nrm * 3.8
		])
		overlay.draw_colored_polygon(hull, GOLD_C.darkened(0.22))
		overlay.draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.10, 0.08, 0.04, 0.95), 1.4)
		overlay.draw_circle(p0 + dir * 1.5, 2.3, GOLD_C.lightened(0.25))
		overlay.draw_circle(p0 - dir * 2.8, 2.0, ocol.lightened(0.15))
	# warships
	for ws in warships:
		var dp: Vector2 = ws.get("dp", ws.pos)
		var mv: Vector2 = ws.pos - dp
		dp = ws.pos if _q() == 0 or mv.length() > 6.0 else dp + mv * clampf(1.0 - exp(-8.0 * get_process_delta_time()), 0.0, 1.0)
		ws["dp"] = dp
		var p := _screen_of(dp * TS)
		var col: Color = nations[ws.o].color
		var hd := _sdir(ws, mv if mv.length() > 0.02 else Vector2.ZERO)
		var hn := Vector2(-hd.y, hd.x)
		if mv.length() > 0.02: _wake(p, hd, 7.0)
		if _unit_sprite(p, 2, col, 22.0, hd.angle()):
			if ws.vet > 0:
				for v in ws.vet: overlay.draw_circle(p + Vector2(-8 + v * 4, -12), 1.6, GOLD_C)
			continue
		var hull := PackedVector2Array([p + hd * 11 + hn * 0, p + hd * 6 + hn * 4, p - hd * 9 + hn * 4, p - hd * 10, p - hd * 9 - hn * 4, p + hd * 6 - hn * 4])
		overlay.draw_colored_polygon(hull, col.darkened(0.2))
		overlay.draw_colored_polygon(PackedVector2Array([p + hd * 3 + hn * 2.5, p - hd * 4 + hn * 2.5, p - hd * 4 - hn * 2.5, p + hd * 3 - hn * 2.5]), col.lightened(0.3))
		overlay.draw_polyline(hull + PackedVector2Array([hull[0]]), col.darkened(0.6), 1.5)
		if ws.vet > 0:
			for v in ws.vet: overlay.draw_circle(p + Vector2(-8 + v * 4, -12), 1.6, GOLD_C)
	# missiles: smooth rounded contrails with rounded end-caps, soft glow, and hot inner core
	var q_lvl := int(save.get("settings", {}).get("qual_i", 3))
	for ms in missiles:
		if ms.t < 0: continue
		var f: float = clampf(ms.t / maxf(0.01, ms.dur), 0.0, 1.0)
		var hcol: Color = nations[ms.o].color if (ms.o > 0 and ms.o < nations.size()) else Color(1, 0.4, 0.3)
		var is_br: bool = ms.get("branched", false) or (ms.get("mirv", false) and not ms.get("mirv_bus", false))
		var w_scale: float = 0.5 if is_br else 1.0
		# Subtle ground-track shadow line from launch pad to current ground shadow point
		var g0 := _screen_of(ms.from * TS)
		var g_cur := _screen_of(ms.from.lerp(ms.to, f) * TS)
		overlay.draw_line(g0, g_cur, Color(0, 0, 0, 0.20 * w_scale), 2.0 * w_scale)
		overlay.draw_circle(g_cur, 2.4 * w_scale, Color(0, 0, 0, 0.26))
		var trail_pts := PackedVector2Array()
		var base_seg: int = [20, 32, 46, 60][clampi(q_lvl, 0, 3)]
		var n_seg: int = int(base_seg * 0.75) if is_br else base_seg
		for m in range(n_seg + 1):
			var s_i: float = f * float(m) / float(n_seg)
			trail_pts.append(_missile_screen_pos(ms, s_i, z))
		var sp := trail_pts[trail_pts.size() - 1]
		# seconds-to-impact countdown pill following the missile (bus, each warhead, every owner)
		var eta := maxf(0.0, ms.dur - ms.t)
		var etxt := "%ds" % int(ceil(eta))
		var efs := 11 if is_br else 13
		var esz := f_bold.get_string_size(etxt, HORIZONTAL_ALIGNMENT_LEFT, -1, efs)
		var er := Rect2(sp + Vector2(8, -10 - esz.y), esz + Vector2(10, 4))
		overlay.draw_style_box(_flat(Color(0.07, 0.085, 0.15, 0.85), int(er.size.y / 2), Color(hcol, 0.7), 1), er)
		overlay.draw_string(f_bold, er.position + Vector2(5, esz.y - 1), etxt, HORIZONTAL_ALIGNMENT_LEFT, -1, efs, Color(1, 0.92, 0.75))
		if trail_pts.size() >= 2:
			var w_outer: float = 6.6 * w_scale
			var w_main: float = 4.5 * w_scale
			var w_core: float = 1.9 * w_scale
			var c_dark := Color(hcol.darkened(0.58), 0.90)
			var c_main := Color(hcol.r, hcol.g, hcol.b, 0.94)
			var c_glow := Color(hcol.lightened(0.25), 0.24)
			var c_core := Color(hcol.lightened(0.55), 0.92)
			if q_lvl >= 2:
				overlay.draw_polyline(trail_pts, c_glow, w_outer * 1.45, true)
				overlay.draw_circle(trail_pts[0], w_outer * 0.70, c_glow)
				overlay.draw_circle(sp, w_outer * 0.72, c_glow)
			overlay.draw_polyline(trail_pts, c_dark, w_outer, true)
			# Rounded end-caps on dark border and main host-country trail
			overlay.draw_circle(trail_pts[0], w_outer * 0.5, c_dark)
			overlay.draw_circle(sp, w_outer * 0.5, c_dark)
			overlay.draw_polyline(trail_pts, c_main, w_main, true)
			overlay.draw_circle(trail_pts[0], w_main * 0.5, c_main)
			overlay.draw_circle(sp, w_main * 0.5, c_main)
			if q_lvl < 2:
				overlay.draw_polyline(trail_pts, c_core, w_core, true)
				overlay.draw_circle(sp, w_core * 0.55, c_core)
		# faint projected remainder of the ballistic arc to target
		if not ms.get("mirv_bus", false):
			var proj_pts := PackedVector2Array()
			for m in range(15):
				var s_p: float = lerpf(f, 1.0, float(m) / 14.0)
				proj_pts.append(_missile_screen_pos(ms, s_p, z))
			if proj_pts.size() >= 2:
				overlay.draw_polyline(proj_pts, Color(hcol.r, hcol.g, hcol.b, 0.26), 1.6 * w_scale, true)
		var prev_sp := _missile_screen_pos(ms, maxf(0.0, f - 0.04), z)
		var mdir := (sp - prev_sp).normalized()
		if mdir == Vector2.ZERO: mdir = Vector2.UP
		var mnrm := Vector2(-mdir.y, mdir.x)
		var hs: float = 0.75 if is_br else 1.0
		# Rounded warhead capsule + glowing nose cone
		var warhead := PackedVector2Array([sp + mdir * 8.0 * hs, sp - mdir * 4.2 * hs + mnrm * 4.0 * hs, sp - mdir * 4.2 * hs - mnrm * 4.0 * hs])
		overlay.draw_colored_polygon(warhead, hcol.lightened(0.28))
		overlay.draw_polyline(warhead + PackedVector2Array([warhead[0]]), Color(0.08, 0.08, 0.12), 1.3 * hs)
		overlay.draw_circle(sp - mdir * 3.2 * hs, 2.8 * hs, hcol.lightened(0.22))
		overlay.draw_circle(sp, 2.8 * hs, Color(1, 0.96, 0.80))
		if not ms.get("mirv_bus", false):
			overlay.draw_arc(_screen_of(ms.to * TS), ms.r * TS * z, 0, TAU, 48, Color(hcol.r, hcol.g, hcol.b, 0.62), 2.0 * w_scale)
	var rw_fx := _qual() >= 2
	if rw_fx: _draw_rw_blasts(z)
	for b in ([] if rw_fx else blasts):
		var bdur: float = maxf(0.2, float(b.get("dur", 1.35)))
		var u: float = clampf(b.t / bdur, 0.0, 1.0)
		var sp := _screen_of(b.pos)
		var rad: float = maxf(8.0, float(b.r) * z)
		var bseed: int = int(b.get("seed", 1337))
		# 1. Persistent ground scorch & glowing magma crater ring
		var scorch_a: float = clampf((1.0 - u) * 0.78, 0.0, 0.78)
		overlay.draw_circle(sp, rad * 0.72, Color(0.08, 0.06, 0.05, scorch_a * 0.75))
		overlay.draw_arc(sp, rad * 0.62, 0, TAU, 36, Color(0.95, 0.32, 0.08, scorch_a * 0.85), maxf(1.8, rad * 0.08), true)
		# 2. Multi-layered rolling fireball core that cools into billowing ash/smoke puffs
		var fb_prog: float = pow(u, 0.36)
		var fb_r: float = rad * (0.28 + 0.68 * fb_prog)
		var core_a: float = clampf(1.0 - pow(u, 1.25), 0.0, 1.0)
		# Perimeter smoke/fire puffs (8 deterministic puffs around the fireball)
		for m in 8:
			var ang: float = float(m) * TAU / 8.0 + float((bseed >> (m % 6)) & 7) * 0.18 + u * 0.55
			var pd: float = fb_r * (0.58 + 0.28 * float((bseed >> ((m + 3) % 7)) & 3) / 3.0)
			var pr: float = fb_r * (0.26 + 0.12 * sin(float(m * 3 + bseed)))
			var puff_p: Vector2 = sp + Vector2.from_angle(ang) * pd
			var puff_col := Color(0.95, 0.38, 0.10, core_a * 0.75).lerp(Color(0.20, 0.18, 0.17, core_a * 0.68), clampf((u - 0.25) * 1.4, 0.0, 1.0))
			overlay.draw_circle(puff_p, maxf(2.0, pr), puff_col)
		# Outer crimson-orange plasma fireball
		overlay.draw_circle(sp, fb_r * 0.88, Color(0.96, 0.30, 0.08, core_a * 0.72).lerp(Color(0.24, 0.21, 0.19, core_a * 0.55), clampf((u - 0.40) * 1.6, 0.0, 1.0)))
		# Mid bright gold-orange plasma core
		if u < 0.78:
			var mid_a: float = clampf(1.0 - u / 0.78, 0.0, 1.0)
			overlay.draw_circle(sp, fb_r * 0.58, Color(1.0, 0.68, 0.18, mid_a * 0.85))
			overlay.draw_circle(sp, fb_r * 0.32, Color(1.0, 0.95, 0.72, mid_a * 0.92))
		# 3. Initial blinding white-hot thermal flash (u < 0.22)
		if u < 0.22:
			var fl_a: float = clampf(1.0 - u / 0.22, 0.0, 1.0)
			overlay.draw_circle(sp, rad * (0.65 + 0.55 * (u / 0.22)), Color(1.0, 0.98, 0.88, fl_a * 0.82))
		# 4. Dual supersonic shockwave rings (primary outer white/amber wave + secondary pressure wave)
		var sw1_r: float = rad * (0.25 + 1.25 * pow(u, 0.45))
		var sw1_a: float = clampf((1.0 - u) * 0.92, 0.0, 1.0)
		overlay.draw_arc(sp, maxf(3.0, sw1_r), 0, TAU, 56, Color(1.0, 0.88, 0.62, sw1_a), maxf(2.0, 3.8 * (1.0 - u * 0.6)), true)
		if u > 0.06:
			var u2: float = clampf((u - 0.06) / 0.94, 0.0, 1.0)
			var sw2_r: float = rad * (0.20 + 0.98 * pow(u2, 0.62))
			var sw2_a: float = clampf((1.0 - u2) * 0.72, 0.0, 1.0)
			overlay.draw_arc(sp, maxf(2.5, sw2_r), 0, TAU, 48, Color(1.0, 0.50, 0.18, sw2_a), maxf(1.5, 2.6 * (1.0 - u2 * 0.5)), true)
		# 5. Radial debris / ember sparks streaking outward
		if u < 0.82:
			var sp_a: float = clampf(1.0 - u / 0.82, 0.0, 1.0)
			var sp_prog: float = pow(u / 0.82, 0.52)
			var nsp: int = [6, 12, 20, 32][_q()]
			for s_i in nsp:
				var sang: float = float(s_i) * TAU / float(nsp) + float((bseed >> (s_i % 8)) & 15) * 0.09
				var spd_mult: float = 0.75 + 0.55 * float((bseed >> ((s_i + 2) % 9)) & 7) / 7.0
				var r_out: float = rad * (0.25 + 1.15 * sp_prog * spd_mult)
				var r_in: float = maxf(2.0, r_out - rad * 0.18 * (1.0 - 0.5 * sp_prog))
				var dir_v := Vector2.from_angle(sang)
				overlay.draw_line(sp + dir_v * r_in, sp + dir_v * r_out, Color(1.0, 0.78, 0.28, sp_a * 0.90), 1.8)
				overlay.draw_circle(sp + dir_v * r_out, 1.6, Color(1.0, 0.95, 0.75, sp_a))
	if _q() >= 2 and not rw_fx:
		for b in blasts:
			var bd: float = maxf(0.2, float(b.get("dur", 1.35)))
			var u2: float = clampf(b.t / bd, 0.0, 1.0)
			if u2 < 0.15: continue
			var sp2 := _screen_of(b.pos); var rd: float = maxf(8.0, float(b.r) * z)
			var ns: int = 6 if _q() == 2 else 12
			var bs: int = int(b.get("seed", 7))
			for k in ns:
				var v := (u2 - 0.15) / 0.85
				var ang := float(k) * TAU / ns + float((bs >> (k % 7)) & 3) * 0.4
				var pp := sp2 + Vector2.from_angle(ang) * rd * (0.3 + 0.5 * v) + Vector2(0, -rd * 0.7 * v * (0.6 + 0.1 * (k % 4)))
				overlay.draw_circle(pp, rd * (0.12 + 0.22 * v), Color(0.28, 0.26, 0.25, 0.42 * (1.0 - v)))
	for s2 in shells:
		var sp := _screen_of(s2.pos)
		overlay.draw_circle(sp, 3 + s2.t * 10, Color(1, 0.6, 0.2, 0.7 * (1.0 - s2.t / 0.5)))
	for fl in floats:
		var a: float = clampf(1.0 - fl.t / 1.4, 0.0, 1.0)
		var sp := _screen_of(fl.pos) - Vector2(0, fl.t * 22.0)
		f_bold.draw_string_outline(overlay.get_canvas_item(), sp + Vector2(-30, 0), fl.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, 3, Color(0, 0, 0, 0.85 * a))
		f_bold.draw_string(overlay.get_canvas_item(), sp + Vector2(-30, 0), fl.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(fl.col.r, fl.col.g, fl.col.b, a))

# RoWorld FxLayer + assets/map_fx/map_fx.png (tools/assets/make_map_fx.py): one atlas, a row per effect.
#   nuke 12 x (60x60) at 70 ms (y 0), sam 9 x (48x38) at 80 ms (y 108), fire 6 x (7x13) 100 ms (y 161),
#   smoke 4 x (11x12) 120 ms (y 174), big_smoke 5 x (24x16) (y 186), smoke_fire 5 x (24x16) (y 202).
# A landed nuke plays the explosion, a thin white shock ring grows to 1.5x its radius over 1.5 s, and
# debris burns within half the radius for 6 s (fade in over the first 10 %, out after 80 %).
const RW_FX := {"nuke": [0, 60, 60, 12, 0.07], "sam": [108, 48, 38, 9, 0.08], "fire": [161, 7, 13, 6, 0.1],
	"smoke": [174, 11, 12, 4, 0.12], "big_smoke": [186, 24, 16, 5, 0.12], "smoke_fire": [202, 24, 16, 5, 0.12]}
func _rw_frame(tex: Texture2D, kind: String, fr: int, center: Vector2, px: float, mod := Color.WHITE) -> void:
	var d: Array = RW_FX[kind]
	var up := 4.0
	var src := Rect2(fr * d[1] * up, d[0] * up, d[1] * up, d[2] * up)
	var sz := Vector2(d[1], d[2]) * px
	overlay.draw_texture_rect_region(tex, Rect2(center - sz * 0.5, sz), src, mod)

func _draw_rw_blasts(z: float) -> void:
	var tex := _tex("map_fx/map_fx.png", 4)
	for b in blasts:
		var sp := _screen_of(b.pos)
		var rad: float = maxf(6.0, float(b.r) * z)
		var t: float = b.t
		var kind: String = b.get("kind", "nuke")
		if tex == null:
			overlay.draw_circle(sp, rad * 0.6, Color(1, 0.6, 0.2, clampf(1.0 - t, 0.0, 1.0))); continue
		if kind == "sam":
			var fr := int(t / 0.08)
			if fr < 9: _rw_frame(tex, "sam", fr, sp, maxf(1.0, rad * 2.0 / 40.0))
			continue
		var dur: float = float(b.get("dur", 6.0))
		var tile_px := rad / maxf(1.0, float(b.r) / TS)   # screen px per map tile
		var px := rad * 2.4 / 60.0                          # sprite pixel size: explosion ~2.4x the blast radius wide
		# debris (under the fireball once it has burnt down)
		var u := t / dur
		var fade := clampf(u / 0.1, 0.0, 1.0) * clampf((1.0 - u) / 0.2, 0.0, 1.0)
		if fade > 0.0 and t > 0.35:
			var bs: int = int(b.get("seed", 1))
			var area := PI * pow(float(b.r) / TS * 0.5, 2.0)
			var plan := [["fire", 1.0 / 25.0], ["smoke", 1.0 / 28.0], ["big_smoke", 1.0 / 70.0], ["smoke_fire", 1.0 / 70.0]]
			var k := 0
			for pl in plan:
				var cnt := maxi(1, int(round(area * float(pl[1]) * 3.0)))
				var d: Array = RW_FX[pl[0]]
				for m in cnt:
					k += 1
					var hh := absi(int(bs * 0x9E37 + k * 0x85EB)) 
					var ang := float(hh % 1000) / 1000.0 * TAU
					var rr := sqrt(float((hh / 1000) % 1000) / 1000.0) * rad * 0.5
					var fr := (int(t / float(d[4])) + hh % 7) % int(d[3])
					_rw_frame(tex, pl[0], fr, sp + Vector2.from_angle(ang) * rr, maxf(0.6, tile_px * 0.5), Color(1, 1, 1, fade))
		var fr2 := int(t / 0.07)
		if fr2 < 12: _rw_frame(tex, "nuke", fr2, sp, px)
		if t < 1.5:
			var su := t / 1.5
			overlay.draw_arc(sp, rad * 1.5 * pow(su, 0.6), 0, TAU, 64, Color(1, 1, 1, 0.85 * (1.0 - su)), maxf(1.0, 2.0 * (1.0 - su)), true)

func _draw_notes() -> void:
	var y := 0.0
	for nt in notes:
		var a := clampf((7.0 - nt.t) / 0.6, 0.0, 1.0) * clampf(nt.t / 0.15, 0.0, 1.0)
		var lines := _wrap(nt.text, f_bold, 15, 290)
		var h := 22.0 + lines.size() * 20.0
		var r := Rect2(0, y, 370, h)
		note_box.draw_style_box(_flat(Color(0.07, 0.085, 0.15, 0.94 * a), 5, Color(1, 1, 1, 0.08 * a), 1), r)
		note_box.draw_rect(Rect2(0, y, 4, h), Color(nt.col, a))
		var c := Vector2(30, y + h / 2)
		note_box.draw_circle(c, 13, Color(nt.col, 0.18 * a))
		note_box.draw_arc(c, 13, 0, TAU, 24, Color(nt.col, 0.6 * a), 1.5, true)
		match nt.kind:
			"good":
				note_box.draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-2, 4), c + Vector2(6, -5)]), Color(nt.col, a), 2.2)
			"bad":
				note_box.draw_rect(Rect2(c + Vector2(-1.2, -7), Vector2(2.4, 9)), Color(nt.col, a))
				note_box.draw_circle(c + Vector2(0, 5.5), 1.5, Color(nt.col, a))
			_:
				note_box.draw_circle(c + Vector2(0, -5), 1.5, Color(nt.col, a))
				note_box.draw_rect(Rect2(c + Vector2(-1.2, -2), Vector2(2.4, 8)), Color(nt.col, a))
		var ly := y + 11 + 15
		for ln in lines:
			f_bold.draw_string(note_box.get_canvas_item(), Vector2(56, ly), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(TEXT, a))
			ly += 20
		y += h + 8

# ---------- alliances, embargoes & diplomacy ----------
const ALLY_LEN := 300.0
var allies := {}       # "a:b" -> expiry (elapsed)
var traitor := {}      # id -> until (elapsed)
var embargoes := {}    # "a:b" -> expiry (elapsed)
var embargo_all := false
var donate_troop_cd := 0.0
var donate_gold_cd := 0.0
var diplo_panel: Panel
var diplo_who := -1
var diplo_refs := {}
var ally_card: Panel
var ally_card_lbl: Label
var ally_card_sub: Label
var ally_card_bar: Control
var ally_card_sq: Control
var ally_card_btn_a: Button
var ally_card_btn_b: Button
var ally_card_mode := ""
var ally_card_who := -1
var ally_warned := {}

func _akey(a: int, b: int) -> int:
	return mini(a, b) * 4096 + maxi(a, b)

func allied(a: int, b: int) -> bool:
	return a > 0 and b > 0 and not allies.is_empty() and allies.has(_akey(a, b))

func is_traitor(id: int) -> bool:
	return traitor.get(id, -1.0) > elapsed

func form_alliance(a: int, b: int) -> void:
	allies[_akey(a, b)] = elapsed + ALLY_LEN
	ally_warned.erase(_akey(a, b))
	for at in attacks.duplicate():
		if (at.a == a and at.t == b) or (at.a == b and at.t == a): retreat(at)
	if a == PLAYER or b == PLAYER: sfx("ally_accept")
	if a == PLAYER or b == PLAYER: notify("You are now allied with %s" % _nname(b if a == PLAYER else a), "good")

func break_alliance(breaker: int, other: int) -> void:
	allies.erase(_akey(breaker, other))
	traitor[breaker] = elapsed + 30.0
	if breaker == PLAYER or other == PLAYER: sfx("ally_broken")
	if breaker == PLAYER: notify("You broke the alliance with %s — you are a traitor for 30 s" % _nname(other), "bad")
	elif other == PLAYER: notify("%s betrayed you! Attacks on them cost half for 30 s" % _nname(breaker), "bad")

func propose_alliance(a: int, b: int) -> void:
	if allied(a, b) or a == b: return
	if b == PLAYER:
		sfx("ally_suggest"); _show_ally_card("propose", a); return
	# AI decides: likes strong partners, dislikes traitors
	var nb = nations[b]
	var na = nations[a]
	var p := 0.35 + (0.25 if na.troops > nb.troops * 0.5 else 0.0) - (0.4 if is_traitor(a) else 0.0)
	if rng.randf() < p:
		form_alliance(a, b)
	elif a == PLAYER:
		sfx("ally_decline")
		notify("%s declined your alliance" % _nname(b), "info")

func is_embargoed(_a: int, _b: int) -> bool:
	return false

func donate(a: int, b: int, frac := 0.3333) -> void:
	if a == PLAYER and donate_troop_cd > 0.0:
		notify("Troop donation on cooldown (%ds)" % ceili(donate_troop_cd), "info")
		return
	var amt: float = floor(nations[a].troops * frac)
	if amt < 100: return
	nations[a].troops -= amt
	nations[b].troops = minf(troop_cap(b) * 1.25, nations[b].troops + amt)
	if a == PLAYER:
		donate_troop_cd = 10.0
		notify("Donated %s troops to %s" % [_fmt(amt), _nname(b)], "good")

func donate_gold(a: int, b: int, frac := 0.25) -> void:
	if a == PLAYER and donate_gold_cd > 0.0:
		notify("Gold donation on cooldown (%ds)" % ceili(donate_gold_cd), "info")
		return
	var amt: float = floor(nations[a].gold * frac)
	if amt < 1000: return
	nations[a].gold -= amt
	nations[b].gold += amt
	if a == PLAYER:
		donate_gold_cd = 10.0
		notify("Donated %s gold to %s" % [_fmt(amt), _nname(b)], "good")

func _tick_alliances() -> void:
	for key in allies.keys():
		var exp_t: float = allies[key]
		var a: int = key / 4096; var b: int = key % 4096
		if not nations[a].alive or not nations[b].alive or elapsed >= exp_t:
			allies.erase(key)
			if a == PLAYER or b == PLAYER: notify("Alliance with %s expired" % _nname(b if a == PLAYER else a), "info")
			continue
		if (a == PLAYER or b == PLAYER) and exp_t - elapsed < 30.0 and not ally_warned.has(key):
			ally_warned[key] = true
			_show_ally_card("expire", b if a == PLAYER else a)
		elif a != PLAYER and b != PLAYER and exp_t - elapsed < 5.0 and rng.randf() < 0.02:
			allies[key] = elapsed + ALLY_LEN
	# AI diplomacy
	if rng.randf() < 0.02:
		var a := rng.randi_range(2, nations.size() - 1)
		if nations[a].alive and is_prot(a):
			var b := rng.randi_range(1, nations.size() - 1)
			if b != a and nations[b].alive and (is_prot(b) or b == PLAYER) and not allied(a, b):
				if b != PLAYER or (ally_card == null or not ally_card.visible):
					propose_alliance(a, b)

func _build_ally_card() -> void:
	ally_card = _P(ui, Rect2(16, 600, 370, 112), PANEL_BG, 5)
	var bar := ColorRect.new(); bar.color = Color(0.68, 0.45, 1.0); bar.position = Vector2(0, 0); bar.size = Vector2(4, 112)
	ally_card.add_child(bar)
	ally_card_sq = _draw_ctl(ally_card, Rect2(18, 16, 14, 14), func(c: Control):
		c.draw_rect(Rect2(0, 0, 14, 14), c.get_meta("col", Color.GRAY)); c.draw_rect(Rect2(0, 0, 14, 14), Color(1, 1, 1, 0.6), false, 1.0))
	ally_card_lbl = _T(ally_card, "", Vector2(40, 10), 16, TEXT, f_bold, 310)
	ally_card_sub = _T(ally_card, "", Vector2(18, 34), 14, Color(0.78, 0.82, 0.94), f_reg, 340)
	ally_card_bar = _draw_ctl(ally_card, Rect2(18, 60, 334, 5), func(c: Control):
		c.draw_rect(Rect2(0, 0, 334, 5), Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(0, 0, 334 * float(c.get_meta("v", 1.0)), 5), Color(0.68, 0.45, 1.0)))
	ally_card_btn_a = _big_btn(ally_card, Rect2(18, 74, 160, 30), "RENEW", ORANGE_Y, 13)
	ally_card_btn_b = _card_btn(ally_card, Rect2(192, 74, 160, 30)); ally_card_btn_b.text = "IGNORE"
	ally_card_btn_b.add_theme_font_override("font", f_head); ally_card_btn_b.add_theme_font_size_override("font_size", 13)
	ally_card_btn_a.pressed.connect(func():
		if ally_card_mode == "expire" and allied(PLAYER, ally_card_who):
			allies[_akey(PLAYER, ally_card_who)] = elapsed + ALLY_LEN; ally_warned.erase(_akey(PLAYER, ally_card_who))
			notify("Alliance with %s renewed" % _nname(ally_card_who), "good")
		elif ally_card_mode == "propose":
			form_alliance(ally_card_who, PLAYER)
		_fade_out(ally_card))
	ally_card_btn_b.pressed.connect(func(): _fade_out(ally_card))
	ally_card.visible = false

func _show_ally_card(mode: String, who: int) -> void:
	ally_card_mode = mode; ally_card_who = who
	ally_card_sq.set_meta("col", nations[who].color); ally_card_sq.queue_redraw()
	ally_card_lbl.text = nations[who].name
	if mode == "expire":
		ally_card_sub.text = "Your alliance is about to expire"
		ally_card_btn_a.text = "RENEW"
	else:
		ally_card_sub.text = "Proposes an alliance with you"
		ally_card_btn_a.text = "ACCEPT"
	ally_card.set_meta("t0", elapsed)
	_fade_in(ally_card, Vector2(-12, 0))

func _tick_ally_card() -> void:
	if ally_card == null or not ally_card.visible: return
	var v := 1.0
	if ally_card_mode == "expire":
		v = clampf((allies.get(_akey(PLAYER, ally_card_who), elapsed) - elapsed) / 30.0, 0, 1)
		if v <= 0: _fade_out(ally_card)
	else:
		v = clampf(1.0 - (elapsed - float(ally_card.get_meta("t0", elapsed))) / 20.0, 0, 1)
		if v <= 0: _fade_out(ally_card)
	ally_card_bar.set_meta("v", v); ally_card_bar.queue_redraw()

func _build_diplo_menu() -> void:
	diplo_panel = _P(ui, Rect2(620, 260, 320, 192), Color(0.07, 0.085, 0.16, 0.98), 8, Color(1, 1, 1, 0.14), 1)
	diplo_refs.sq = _draw_ctl(diplo_panel, Rect2(16, 16, 16, 16), func(c: Control):
		c.draw_rect(Rect2(0, 0, 16, 16), c.get_meta("col", Color.GRAY))
		c.draw_rect(Rect2(0, 0, 16, 16), Color(1, 1, 1, 0.7), false, 1.0))
	diplo_refs.title = _T(diplo_panel, "", Vector2(40, 11), 18, TEXT, f_bold, 220)
	diplo_refs.sub = _T(diplo_panel, "", Vector2(16, 36), 13, MUTED, f_reg, 280)
	var x := _card_btn(diplo_panel, Rect2(276, 10, 32, 30)); x.text = "✕"
	x.pressed.connect(func(): diplo_panel.visible = false)
	diplo_refs.b_ally = _big_btn(diplo_panel, Rect2(16, 64, 288, 36), "PROPOSE ALLIANCE", ORANGE_Y, 14)
	diplo_refs.b_ally.pressed.connect(func():
		if diplo_who <= 1: return
		if allied(PLAYER, diplo_who): break_alliance(PLAYER, diplo_who)
		else: propose_alliance(PLAYER, diplo_who)
		_refresh_diplo())
	diplo_refs.b_troops = _card_btn(diplo_panel, Rect2(16, 108, 140, 36))
	diplo_refs.b_troops.add_theme_font_override("font", f_bold); diplo_refs.b_troops.add_theme_font_size_override("font_size", 13)
	diplo_refs.b_troops.pressed.connect(func():
		if diplo_who > 1: donate(PLAYER, diplo_who, 0.3333); _refresh_diplo())
	diplo_refs.b_gold = _card_btn(diplo_panel, Rect2(164, 108, 140, 36))
	diplo_refs.b_gold.add_theme_font_override("font", f_bold); diplo_refs.b_gold.add_theme_font_size_override("font_size", 13)
	diplo_refs.b_gold.pressed.connect(func():
		if diplo_who > 1: donate_gold(PLAYER, diplo_who, 0.25); _refresh_diplo())
	diplo_refs.foot = _T(diplo_panel, "", Vector2(16, 154), 12, MUTED, f_reg, 288, HORIZONTAL_ALIGNMENT_CENTER)
	diplo_panel.visible = false

func _open_diplo(who: int, screen_pos: Vector2) -> void:
	diplo_who = who
	var pos := screen_pos + Vector2(14, -40)
	pos.x = clampf(pos.x, 20, 1600 - 340)
	pos.y = clampf(pos.y, 60, 900 - 210)
	diplo_panel.position = pos
	_refresh_diplo()
	_pop_in(diplo_panel, 0.14)

func _refresh_diplo() -> void:
	if diplo_panel == null or diplo_who <= 1 or diplo_who >= nations.size(): return
	var n = nations[diplo_who]
	diplo_refs.sq.set_meta("col", n.color); diplo_refs.sq.queue_redraw()
	diplo_refs.title.text = n.name + (" [TRAITOR]" if is_traitor(diplo_who) else "")
	var status := "ALLY" if allied(PLAYER, diplo_who) else ("Nation" if is_prot(diplo_who) else "Tribe")
	diplo_refs.sub.text = "%s  ·  Troops: %s  ·  Land: %s" % [status, _fmt(n.troops), _pct(100.0 * n.land / maxf(1, land_total))]
	if allied(PLAYER, diplo_who):
		var left: float = allies.get(_akey(PLAYER, diplo_who), elapsed) - elapsed
		diplo_refs.b_ally.text = "BREAK ALLIANCE (%s)" % _fmt_time(maxf(0.0, left))
	else:
		diplo_refs.b_ally.text = "PROPOSE ALLIANCE (5:00)"
	diplo_refs.b_troops.text = ("Troops CD %ds" % ceili(donate_troop_cd)) if donate_troop_cd > 0 else "DONATE 1/3 TROOPS"
	diplo_refs.b_gold.text = ("Gold CD %ds" % ceili(donate_gold_cd)) if donate_gold_cd > 0 else "DONATE 25% GOLD"
	diplo_refs.foot.text = "Breaking an alliance marks you [TRAITOR] (0.5x def, 30s)"

func _right_click() -> void:
	var t := _mouse_tile()
	if t < 0: return
	var o: int = owner_map[t]
	if o <= 1:
		if diplo_panel: diplo_panel.visible = false
		return
	if Input.is_key_pressed(KEY_SHIFT) and allied(PLAYER, o):
		break_alliance(PLAYER, o)
		return
	_open_diplo(o, get_viewport().get_mouse_position())


# ---------------- loop ----------------
var map_t := 0.0
var _fp := {}
func _process(dt: float) -> void:
	_rail_bfs_left = 4
	_rail_calc_left = 40
	var _t0 := Time.get_ticks_usec()
	map_t += dt
	if map_mat: map_mat.set_shader_parameter("t_anim", fmod(map_t, 1000.0))
	_process_inner(dt)
	_fp["process"] = Time.get_ticks_usec() - _t0
	if _sfx_log and _fp.process > 60000: print("SLOW process ", _fp)
	for kz in ["ai_prot", "ai_boat", "ai_mop", "ai_inv"]: _fp[kz] = 0
	if bench: _bench_step(dt, Time.get_ticks_usec() - _t0)

func _bench_step(dt: float, us: int) -> void:
	if bench_i == -1:
		_start_game()
		var st := _find_spawn_tile(W / 2, H / 2)
		_place_start(st); deploy_t = 0.0
		bench_i = 0; bench_t = -2.0
		return
	if state == "play": peace = 1e9
	bench_t += dt
	if bench_t < 0: return
	if bench_t > 0.0 and bench_frames == 0: bench_ticks0 = ticks_done
	bench_frames += 1; bench_us += us; bench_max = maxi(bench_max, us)
	if bench_t >= 6.0:
		var tk := ticks_done - bench_ticks0
		print("BENCH fps=%.0f speed=%dx frames=%d avg_ms=%.2f max_ms=%.2f sim_ticks_per_s=%.1f (target %.0f) land_player=%d attacks=%d boats=%d" % [bench_frames / bench_t, int(SPEEDS[bench_i]), bench_frames, bench_us / 1000.0 / bench_frames, bench_max / 1000.0, tk / bench_t, 10.0 * SPEEDS[bench_i], nations[PLAYER].land, attacks.size(), boats.size()])
		print("   prof ms: attacks=%.0f economy=%.0f boats=%.0f ai=%.0f ai_max=%.1f naval=%.0f traders=%d" % [prof.atk / 1000.0, prof.eco / 1000.0, prof.boat / 1000.0, prof.ai / 1000.0, prof.ai_max / 1000.0, prof.get("naval", 0) / 1000.0, traders.size()])
		for k in prof: prof[k] = 0
		bench_i += 1
		if bench_i >= SPEEDS.size():
			get_tree().quit(); return
		set_speed(bench_i)
		bench_t = 0.0; bench_frames = 0; bench_us = 0; bench_max = 0

var _pace := {}
func _pace_step() -> void:
	# headless pacing test: --pace=<map_i>,<runs>[,growth,atk,gold,airate]
	if _pace.has("init"):
		var a := ""
		for x in OS.get_cmdline_user_args():
			if x.begins_with("--pace="): a = x.substr(7)
		var p := a.split(",")
		_pace = {"map": int(p[0]), "runs": int(p[1]), "run": 0, "started": false}
		if p.size() >= 6:
			sim_rules.growth_mult = float(p[2]); sim_rules.attack_speed_mult = float(p[3])
			sim_rules.gold_mult = float(p[4]); sim_rules.ai_rate_mult = float(p[5])
	if not _pace.started:
		map_tab = 0; map_i = _pace.map
		_start_game()
		_place_start(_find_spawn_tile(W / 2, H / 3)); deploy_t = 0.0
		state = "play"; peace = 1e9
		_pace.started = true
		return
	for k in 300:
		var t0 := Time.get_ticks_usec()
		_tick_attacks()
		var t1 := Time.get_ticks_usec()
		_ai(0.1)
		var t2 := Time.get_ticks_usec()
		sim_naval.tick()
		var t3 := Time.get_ticks_usec()
		_economy(0.1); ticks_done += 1
		var t4 := Time.get_ticks_usec()
		_tick_boats(0.1); _tick_trade(0.1)
		var t5 := Time.get_ticks_usec()
		for kk in ["atk", "ai", "nav", "eco", "units"]: if not _pace.has(kk): _pace[kk] = 0
		_pace.atk += t1 - t0; _pace.ai += t2 - t1; _pace.nav += t3 - t2; _pace.eco += t4 - t3; _pace.units += t5 - t4
		if _sfx_log and sim_atk.tick >= 1800: print("SFXLOG done 3min"); get_tree().quit(); return
		if OS.get_cmdline_user_args().has("--prof") and sim_atk.tick % 1200 == 0:
			print("   scan ms/tick=%.2f scans/tick=%.1f" % [sim_ai.scan_us / 1200000.0, sim_ai.scan_n / 1200.0]); sim_ai.scan_us = 0; sim_ai.scan_n = 0
			print("PROF t=%dmin ms/tick atk=%.2f ai=%.2f naval=%.2f eco=%.2f units=%.2f attacks=%d" % [sim_atk.tick / 600, _pace.atk / 1200000.0, _pace.ai / 1200000.0, _pace.nav / 1200000.0, _pace.eco / 1200000.0, _pace.units / 1200000.0, attacks.size()])
			for kk in ["atk", "ai", "nav", "eco", "units"]: _pace[kk] = 0
			if sim_atk.tick >= 6000: get_tree().quit(); return
		var win := (land_total - fallout_count) * SimRules.WIN_SHARE
		var best := 0; var bid := 0
		for id in range(1, nations.size()):
			if nations[id].alive and nations[id].land > best: best = nations[id].land; bid = id
		if best >= win or sim_atk.tick >= 60 * 600:
			print("PACE map=%s run=%d minutes=%.1f winner=%s share=%.2f alive=%d" % [MAPS[map_i][0], _pace.run, sim_atk.tick / 600.0, nations[bid].name, float(best) / maxf(1.0, land_total), nations.filter(func(n): return n is Dictionary and n.get("alive", false) and n.get("land", 0) > 0).size()])
			_pace.run += 1; _pace.started = false
			if _pace.run >= _pace.runs: get_tree().quit()
			return
		if sim_atk.tick % 3000 == 0:
			print("  t=%dmin lead=%.2f" % [sim_atk.tick / 600, float(best) / maxf(1.0, land_total)])

func _process_inner(dt: float) -> void:
	_pump_previews()
	if not _pace.is_empty() or OS.get_cmdline_user_args().has("--pacetest") : _pace_step(); return
	boat_launched_frame = false
	if state == "pick":
		var picked: bool = start_tile >= 0 and nations[PLAYER].land > 0
		if picked: deploy_t -= dt
		if picked:
			pick_title.text = "DEPLOYING IN %d" % ceili(maxf(deploy_t, 0.0))
			pick_sub.text = "Click anywhere else on land to switch your starting spot (timer won't reset)."
		else:
			pick_title.text = "CHOOSE YOUR STARTING LOCATION"
			pick_sub.text = "Click any unclaimed land to found your nation."
		pick_ring.set_meta("v", clampf(deploy_t / 5.0, 0, 1)); pick_ring.set_meta("n", ceili(maxf(deploy_t, 0.0)))
		pick_ring.visible = true; pick_ring.queue_redraw()
		if picked and deploy_t <= 0:
			state = "play"
			_play_music()
			_focus_player_smooth(2.6)
			var dl := 0.0
			for n in hud_nodes:
				var nd: Control = n
				get_tree().create_timer(dl).timeout.connect(func(): _fade_in(nd, Vector2(0, 12 if nd.position.y > 600 else -12)))
				dl += 0.04
			_fade_out(pick_panel)
	var rdt := dt
	_animate_labels(rdt)
	dt *= sim_speed
	if state == "play":
		# RoWorld runs 10 ticks per second at 1x (SPEED_BASE only slows the visual unit motion)
		var tdt := rdt * sim_speed / SPEED_BASE
		elapsed += tdt
		tick_acc += tdt
		tick_acc = minf(tick_acc, 0.1 * MAX_TICKS_PER_FRAME)
		var nt := 0
		var loop_t0 := Time.get_ticks_usec()
		while tick_acc >= 0.1 and nt < MAX_TICKS_PER_FRAME:
			if nt > 0 and Time.get_ticks_usec() - loop_t0 > 28000: break  # frame budget: never stall the window on sim catch-up
			tick_acc -= 0.1
			nt += 1
			var a0 := Time.get_ticks_usec()
			_tick_attacks()
			prof.atk += Time.get_ticks_usec() - a0
			_fp["t_atk"] = Time.get_ticks_usec() - a0
			a0 = Time.get_ticks_usec()
			_ai(0.1)
			var e_ai := Time.get_ticks_usec() - a0
			_fp["t_ai"] = e_ai
			prof.ai += e_ai; prof.ai_max = maxi(prof.ai_max, e_ai)
			a0 = Time.get_ticks_usec()
			if not OS.has_environment("NO_TRADE"): sim_naval.tick()
			prof["naval"] = prof.get("naval", 0) + Time.get_ticks_usec() - a0
			ticks_done += 1
			a0 = Time.get_ticks_usec()
			_economy(0.1)
			prof.eco += Time.get_ticks_usec() - a0
			_fp["t_eco"] = Time.get_ticks_usec() - a0
		_fp["sim"] = Time.get_ticks_usec() - loop_t0; _fp["ticks"] = nt
		var u0 := Time.get_ticks_usec()
		_tick_missiles(dt); _fp["missiles"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_tick_warships(dt)
		_tick_trade(tdt); _fp["ships"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_tick_trains(dt); _fp["trains"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_tick_artillery(dt)
		_tick_fx(dt); _fp["fx"] = Time.get_ticks_usec() - u0; u0 = Time.get_ticks_usec()
		_tick_meta(dt); _fp["meta"] = Time.get_ticks_usec() - u0
		donate_troop_cd = maxf(0.0, donate_troop_cd - dt)
		donate_gold_cd = maxf(0.0, donate_gold_cd - dt)
		if ai_timer == 0.0 or rng.randf() < 0.2: _tick_alliances()
		var b0 := Time.get_ticks_usec()
		_tick_boats(tdt)
		prof.boat += Time.get_ticks_usec() - b0
		ai_timer += dt
		# RoWorld win: 80 % of the land that is not fallout
		var pl = nations[PLAYER]
		var win_land := (land_total - fallout_count) * SimRules.WIN_SHARE
		if pl.land >= win_land:
			_game_over(true)
		elif pl.land <= 0:
			_game_over(false)
		elif ticks_done % 10 == 0:
			for id in range(2, nations.size()):
				if nations[id].alive and nations[id].land >= win_land:
					notify("%s controls 80%% of the land" % nations[id].name, "bad")
					_game_over(false); break
	dt = rdt
	_pan(dt)
	if shake_amp > 0.05:
		shake_t += dt * 42.0
		shake_amp = maxf(0.0, shake_amp - shake_amp * 14.0 * dt - 4.0 * dt)
		cam.offset = Vector2(sin(shake_t * 1.9 + 0.5), cos(shake_t * 2.5)) * shake_amp
	elif cam.offset != Vector2.ZERO:
		shake_amp = 0.0
		cam.offset = Vector2.ZERO
	if dirty:
		var more := false
		if not _pend_paint.is_empty(): more = _flush_paint_budget(30000)  # spread big repaints over frames
		var up := 0
		for k in chunk_dirty.size():
			if chunk_dirty[k] == 1:
				if up >= 48: more = true; break
				chunk_tex[k].update(chunk_img[k]); chunk_dirty[k] = 0; uploads += 1; up += 1
		dirty = more
	ui_timer += dt
	if ui_timer > 0.25 and state != "menu":
		ui_timer = 0
		_update_hud()
	_update_tooltip()
	_animate_ui(rdt)
	if note_box: _tick_notes(rdt)
	_tick_ally_card()
	ov_t += rdt
	if overlay and state != "menu":
		_last_cam = cam.position; _last_zoom = cam.zoom
		overlay.queue_redraw()
	if autoshot: _autoshot(dt)

func _animate_labels(dt: float) -> void:
	# critically-damped springs: smooth, elastic, no jitter
	for at in attacks:
		if not at.has("disp"): continue
		var acc: Vector2 = (at.tgt - at.disp) * 60.0 - at.vel * 13.0
		at.vel += acc * dt
		at.disp += at.vel * dt
		at.shown = lerpf(at.shown, at.troops, 1.0 - exp(-8.0 * dt))
	for id in range(1, nations.size()):
		var n = nations[id]
		if n.land <= 0: continue
		var c := Vector2(n.sx / n.land + 0.5, n.sy / n.land + 0.5) * TS
		if not n.has("lp"): n.lp = c; n.ls = sqrt(float(n.land))
		n.lp = n.lp.lerp(c, 1.0 - exp(-4.0 * dt))
		n.ls = lerpf(n.ls, sqrt(float(n.land)), 1.0 - exp(-4.0 * dt))

func set_speed(k: int) -> void:
	set_speed_x(SPEEDS[clampi(k, 0, SPEEDS.size() - 1)])

var speed_slider: HSlider
var speed_lbl: Label
func set_speed_x(x: float) -> void:
	x = clampf(snappedf(x, 0.5), 0.5, 10.0)
	for sp in [1.0, 2.0, 5.0, 10.0]:  # snap points
		if absf(x - sp) <= 0.26: x = sp
	sim_speed = x * SPEED_BASE
	if speed_slider: speed_slider.set_value_no_signal(x)
	if speed_lbl: speed_lbl.text = ("%dx" % int(x)) if is_equal_approx(x, roundf(x)) else ("%.1fx" % x)
	_place_speed_readout()

func _shot(name: String) -> void:
	var im = get_viewport().get_texture().get_image()
	if im:
		DirAccess.make_dir_recursive_absolute(shots_dir)
		im.save_png(shots_dir + "/" + name)
		print("SAVED ", name, " ", im.get_size())

var _step := 0
var _pboat = null
func warp_away() -> void:
	get_viewport().warp_mouse(Vector2(1580, 690))

func _focus_player(z: float) -> void:
	var n = nations[PLAYER]
	cam.zoom = Vector2(z, z); cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS; _clamp_cam()

func _focus_player_smooth(z: float, dur := 0.42) -> void:
	if nations.size() <= PLAYER or nations[PLAYER].land <= 0: return
	if autoshot or bench:
		_focus_player(z)
		return
	var n = nations[PLAYER]
	var target_pos := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam, "position", target_pos, dur)
	tw.tween_property(cam, "zoom", Vector2(z, z), dur)
	tw.chain().tween_callback(_clamp_cam)

var _pre := 0
var _qs := 0
var _l27 := 0
var _l27c := Vector2.ZERO
func _look27(tag: String) -> void:
	var tm := [1.0, 9.0, 10.0, 11.0, 11.2, 11.4, 11.6, 11.8, 12.0, 12.2, 16.0, 40.0]
	if _l27 >= tm.size() or shot_t < tm[_l27]: return
	match _l27:
		0:
			save.settings["qual_i"] = 3; apply_settings()
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(2.2, 2.2); _clamp_cam()
		2: _shot("27_%s_territory.png" % tag)
		3:
			var n = nations[PLAYER]
			var pc := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land))
			var tgt := -1
			for r in range(20, 120, 4):
				for k in 64:
					var t := Vector2i(pc + Vector2.from_angle(k * TAU / 64.0) * r)
					var ti := t.y * W + t.x
					if t.x > 0 and t.y > 0 and t.x < W and t.y < H and owner_map[ti] > 1: tgt = ti; break
				if tgt >= 0: break
			if tgt < 0: tgt = int(pc.y + 30) * W + int(pc.x + 30)
			_l27c = Vector2(tgt % W, tgt / W)
			detonate(PLAYER, _l27c, float(NUKE_R[7]), 1.0)
			cam.position = _l27c * TS; cam.zoom = Vector2(3.0, 3.0); _clamp_cam()
			fx_freeze = true
			for bl in blasts: bl.t = 0.35
		4: _shot("27_%s_nuke_impact.png" % tag)
		5: for bl in blasts: bl.t = 0.62
		6: _shot("27_%s_nuke_impact_late.png" % tag)
		7: for bl in blasts: bl.t = 2.5
		8: _shot("27_%s_nuke_debris.png" % tag)
		9: fx_freeze = false; blasts.clear()
		10: _shot("27_%s_fallout.png" % tag)
		11: _shot("27_%s_fallout_recede.png" % tag); get_tree().quit()
	_l27 += 1

func _texshot() -> void:
	var tm := [1.0, 4.0, 6.0, 7.0, 9.0, 10.0, 11.0]
	if _qs >= tm.size() or shot_t < tm[_qs]: return
	match _qs:
		0:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			n.gold = 1e9
			var c := Vector2i(int(n.sx / maxf(1, n.land)), int(n.sy / maxf(1, n.land)))
			var kinds := [0, 1, 2, 3, 4, 5, 10, 14, 15]
			var placed := 0
			for r in range(0, 40):
				for dy in range(-r, r + 1, 6):
					for dx in range(-r, r + 1, 6):
						if placed >= kinds.size(): break
						var t := (c.y + dy) * W + c.x + dx
						if t < 0 or t >= W * H or owner_map[t] != PLAYER or struct_at.has(t): continue
						var ok := true
						for s2 in structs:
							if Vector2(s2.tile % W, s2.tile / W).distance_to(Vector2(t % W, t / W)) < 6: ok = false
						if ok: _struct_add(kinds[placed], t, PLAYER); placed += 1
			spawn_warship(PLAYER); spawn_warship(PLAYER)
			save.settings["qual_i"] = 3; apply_settings()
		2:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(6, 6); _clamp_cam()
		3: _shot("26_structures_plates.png")
		4:
			if not warships.is_empty(): cam.position = warships[0].pos * TS
			elif not traders.is_empty(): cam.position = _boat_pos(traders[0])[0]
			cam.zoom = Vector2(7, 7); _clamp_cam()
		5: _shot("26_units_sprites.png"); cam.zoom = Vector2(2.5, 2.5); _clamp_cam()
		6: _shot("26_overview_buildbar.png"); get_tree().quit()
	_qs += 1
var _rws := 0
func _rw_stats(tag: String) -> void:
	var ids := []
	for id in range(1, nations.size()):
		if nations[id].alive and nations[id].land > 0: ids.append(id)
	ids.sort_custom(func(x, y): return nations[x].land > nations[y].land)
	var pl = nations[PLAYER]
	print("RWSTAT %s tick=%d alive=%d attacks=%d boats=%d player land=%d troops=%.0f cap=%.0f gold=%.0f" % [tag, sim_atk.tick, ids.size(), attacks.size(), boats.size(), pl.land, pl.troops, troop_cap(PLAYER), pl.gold])
	for k in mini(6, ids.size()):
		var n = nations[ids[k]]
		print("   #%d %s kind=%d land=%d troops=%.0f/%.0f gold=%.0f" % [k + 1, n.name, kind_of(ids[k]), n.land, n.troops, troop_cap(ids[k]), n.gold])

func _rw_full_view() -> void:
	cam.zoom = Vector2(1.5, 1.5); cam.position = Vector2(W, H) * TS / 2; _clamp_cam()

func _rw_start(mi: int, fx: float, fy: float) -> void:
	map_tab = 0; map_i = mi
	_start_game()
	var st := -1
	for r in range(0, 120, 2):
		for _k in 40:
			var x := clampi(int(W * fx) + rng.randi_range(-r, r), 4, W - 5)
			var y := clampi(int(H * fy) + rng.randi_range(-r, r), 4, H - 5)
			var ok := true
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					if owner_map[(y + dy) * W + x + dx] != NEUTRAL: ok = false
			if ok: st = y * W + x; break
		if st >= 0: break
	_place_start(st)
	_rw_full_view()

func _rwshot() -> void:
	var tm := [1.0, 2.0, 3.0, 3.5, 60.0, 61.0, 120.0, 121.0, 122.0, 123.0, 150.0, 151.0]
	if _rws >= tm.size() or shot_t < tm[_rws]: return
	match _rws:
		0: play_dialog.visible = true; _set_map_tab(0)
		1: _shot("28_map_select_real_maps.png"); play_dialog.visible = false; _rw_start(0, 0.50, 0.30)
		2: _shot("28_world_spawn_phase.png"); _rw_stats("spawn")
		3: deploy_t = 0.0; launch_attack(PLAYER, NEUTRAL, 0.5); set_speed(1)
		4: _rw_full_view(); _shot("28_world_t1.png"); _rw_stats("t1"); launch_attack(PLAYER, NEUTRAL, 0.5)
		5:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(5, 5); _clamp_cam()
		6: _shot("28_player_closeup.png"); _rw_full_view()
		7: _shot("28_world_t2.png"); _rw_stats("t2")
		8: _rw_start(1, 0.45, 0.5)
		9: _shot("28_europe_spawn.png"); deploy_t = 0.0; set_speed(1)
		10: _rw_full_view(); _shot("28_europe_t1.png"); _rw_stats("europe")
		11: get_tree().quit()
	_rws += 1

var _r29 := 0
var _r29_t := 0.0
var _r29_kind := 0
var _r29_shot := 0
const R29_KINDS := [7, 8, 9, 12]
const R29_NAMES := {7: "atom", 8: "hydrogen", 9: "mirv_fan", 12: "scattershot"}

func _r29_mid() -> Array:
	var k: int = R29_KINDS[_r29_kind]
	var out := []
	for ms in missiles:
		if ms.dur <= 0.0: continue
		var ok: bool = (ms.get("branched", false) and not ms.get("mirv_bus", false)) if k == 9 else (ms.k == k or (k == 12 and ms.get("branched", false)))
		if ok and ms.t / ms.dur >= 0.35 and ms.t / ms.dur <= 0.7: out.append(ms)
	return out

func _rw29() -> void:
	match _r29:
		0:
			if shot_t < 1.0: return
			play_dialog.visible = true; _set_map_tab(0)
		1:
			if shot_t < 2.0: return
			_shot("29_ui_map_select_rounded.png"); play_dialog.visible = false
			_rw_start(0, 0.50, 0.30)
		2:
			if shot_t < 3.0: return
			_shot("29_world_no_antarctica_spawn.png"); _rw_stats("spawn")
			deploy_t = 0.0
		3:
			if shot_t < 3.6: return
			launch_attack(PLAYER, NEUTRAL, 0.6); set_speed(1)
			_r29_t = shot_t
		4:
			if shot_t < _r29_t + 40.0: return
			_rw_full_view(); _shot("29_world_t1.png"); _rw_stats("t1")
			var ports := 0; var placed := []
			for st in structs:
				if st.k == 1: ports += 1
			print("RW29 ports=%d traders=%d boats=%d" % [ports, traders.size(), boats.size()])
			# placement test: city twice on the same click -> second snaps away or upgrades
			var n = nations[PLAYER]
			n.gold = 5e6
			var c := int(n.sy / maxf(1, n.land)) * W + int(n.sx / maxf(1, n.land))
			for k in [0, 0, 1, 2]:
				var site := sim_struct.place_site(PLAYER, k, c)
				var ok := try_build(k, c)
				placed.append("k%d ok=%s site=%d upg=%s reason=%s" % [k, str(ok), site.tile, str(site.upgrade != null), site.reason])
			print("RW29 placement ", placed)
			cam.position = Vector2(c % W, c / W) * TS; cam.zoom = Vector2(6, 6); _clamp_cam()
		5:
			if shot_t < _r29_t + 41.0: return
			_shot("29_ui_hud_rounded_buildings.png")
			_r29_t = shot_t
		6:
			if shot_t < _r29_t + 40.0: return
			_rw_full_view(); _shot("29_world_trade_t2.png"); _rw_stats("t2")
			print("RW29 traders=%d boats=%d" % [traders.size(), boats.size()])
			god_mode = true
			var n = nations[PLAYER]
			var c := -1
			for i in W * H:
				if owner_map[i] == PLAYER and not struct_at.has(i): c = i; break
			_struct_add(5, c, PLAYER); struct_at[c].bt = 0.0
			_r29_kind = 0; _r29_shot = -1
			set_speed(0)
		7:
			# launch the next kind toward a target ~130 tiles east of the silo
			var silo_t := -1
			for st in structs:
				if st.k == 5 and st.o == PLAYER: silo_t = st.tile
			var tx := clampi(silo_t % W + 130, 0, W - 1); var ty := clampi(silo_t / W + 10, 0, H - 1)
			var tgt := -1
			for r in range(0, 60):
				for dx in range(-r, r + 1):
					var i := clampi(ty + r / 2, 0, H - 1) * W + clampi(tx + dx, 0, W - 1)
					if owner_map[i] > 0 and owner_map[i] != PLAYER: tgt = i; break
				if tgt >= 0: break
			missiles.clear(); blasts.clear()
			var k: int = R29_KINDS[_r29_kind]
			print("RW29 launch ", R29_NAMES[k], " ok=", launch_nuke(PLAYER, k, tgt))
			save.settings["qual_i"] = 3; apply_settings()
			_r29_t = shot_t
		8:
			if _r29_mid().is_empty():
				if shot_t - _r29_t > 60.0: print("RW29 timeout ", _r29_kind); _r29 = 10
				return
			sim_speed = 0.0
			_r29_shot = 0
		9:
			var mids := _r29_mid()
			var nm: String = R29_NAMES[R29_KINDS[_r29_kind]]
			var focus := Vector2(W, H) * TS / 2
			if not mids.is_empty():
				var acc := Vector2.ZERO
				for ms in mids: acc += _missile_world_pos(ms, ms.t / ms.dur)
				focus = acc / mids.size()
			var zooms := [1.8, 3.5, 7.0]
			if _r29_shot < 3:
				cam.zoom = Vector2.ONE * zooms[_r29_shot]; cam.position = focus; _clamp_cam()
				_r29_shot += 10  # wait a frame before capturing
				return
			if _r29_shot >= 10 and _r29_shot < 13:
				var zi := _r29_shot - 10
				_shot("29_trail_%s_ultra_z%d.png" % [nm, zi + 1])
				_r29_shot = zi + 1
				if _r29_shot < 3: return
				save.settings["qual_i"] = 2; apply_settings()
				cam.zoom = Vector2.ONE * 3.5; cam.position = focus; _clamp_cam()
				_r29_shot = 20
				return
			if _r29_shot == 20:
				_r29_shot = 21; return
			if _r29_shot == 21:
				_shot("29_trail_%s_high_z2.png" % nm)
			set_speed(0)
			_r29_kind += 1
			if _r29_kind < R29_KINDS.size():
				_r29 = 7; return
		10:
			get_tree().quit(); return
	_r29 += 1

func _qualshot() -> void:
	var tm := [1.0, 3.0, 4.0, 4.6, 5.4, 6.0, 6.8, 9.0, 9.35, 9.6, 9.95, 10.2, 10.55, 11.0, 11.12, 11.5]
	if _qs >= tm.size() or shot_t < tm[_qs]: return
	match _qs:
		0:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st); deploy_t = 0.0
			launch_attack(PLAYER, NEUTRAL, 0.9)
			set_speed(3)
		1:
			var n = nations[PLAYER]
			cam.position = Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(9, 9); _clamp_cam()
			save.settings["qual_i"] = 0; apply_settings()
		2: _shot("22_quality_low.png"); save.settings["qual_i"] = 1; apply_settings()
		3: _shot("22b_quality_medium.png"); save.settings["qual_i"] = 2; apply_settings()
		4: _shot("22c_quality_high.png"); save.settings["qual_i"] = 3; apply_settings()
		5: _shot("23_quality_ultra.png"); _open_settings()
		6: _shot("24_settings_slider.png"); settings_dlg.visible = false
		7, 9, 11:
			var hq := _q()
			var n = nations[PLAYER]
			var c := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			cam.zoom = Vector2(4, 4); cam.position = c; _clamp_cam()
			blasts.append({"pos": c + Vector2(14, 6), "r": 6.0 * TS, "t": 0.0, "dur": 1.6, "seed": 99173})
			# capture flash demo on a patch of tiles
			var ct := Vector2i(c / TS)
			for yy in range(ct.y - 10, ct.y - 4):
				for xx in range(ct.x - 14, ct.x - 4):
					if xx >= 0 and yy >= 0 and xx < W and yy < H: cap_fx[yy * W + xx] = [map_t, n.color]
			# follow a boat/trader/warship if one exists
			var tgt = null
			if not warships.is_empty(): tgt = warships[0].pos * TS
			elif not boats.is_empty(): tgt = _boat_pos(boats[0])[0]
			elif not traders.is_empty(): tgt = _boat_pos(traders[0])[0]
			if tgt != null: cam.position = tgt; cam.zoom = Vector2(5, 5); _clamp_cam(); blasts[-1].pos = tgt + Vector2(30, 0)
			if hq != 0: pass
		8: _shot("25_anim_ultra.png"); save.settings["qual_i"] = 1; apply_settings()
		10: _shot("25_anim_medium.png"); save.settings["qual_i"] = 0; apply_settings()
		12: _shot("25_anim_low.png"); save.settings["qual_i"] = 3; apply_settings()
		13:
			if not boats.is_empty():
				cam.position = _boat_pos(boats[0])[0]; cam.zoom = Vector2(7, 7); _clamp_cam()
				print("boat dir ", _boat_pos(boats[0])[1], " q ", _q())
			blasts.append({"pos": cam.position + Vector2(10, 4), "r": 5.0 * TS, "t": 0.5, "dur": 1.6, "seed": 5511})
		14: _shot("25_anim_ultra_ships_blast.png")
		15: get_tree().quit()
	_qs += 1
func _autoshot(dt: float) -> void:
	shot_t += dt
	if "--qualshot" in OS.get_cmdline_user_args():
		_qualshot(); return
	if "--rwshot" in OS.get_cmdline_user_args():
		_rwshot(); return
	if "--rw29" in OS.get_cmdline_user_args():
		_rw29(); return
	if "--texshot" in OS.get_cmdline_user_args():
		_texshot(); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look27="):
			_look27(a.substr(9)); return
	if _pre == 0 and shot_t > 2.0:
		_shot("01_menu.png"); play_dialog.visible = true; _set_map_tab(0); _pre = 1; return
	if _pre == 1 and shot_t > 2.6:
		_shot("02_play_solo.png"); _set_map_tab(1); _pre = 2; return
	if _pre == 2 and shot_t > 3.2:
		_shot("02b_random_maps.png"); _set_map_tab(0); play_dialog.visible = false; _pre = 3; shot_t = 0.7; _step = 1; return
	if _pre < 3: return
	var plan := [0.6, 1.0, 2.6, 3.0, 14.0, 14.5, 15.5, 16.0, 17.0, 17.5, 19.5, 20.0, 21.0, 22.5, 23.0, 26.0, 27.0, 28.0, 29.0, 30.2, 31.0, 31.8, 32.6, 33.4, 34.2, 35.0, 35.8, 36.6, 37.4, 38.2, 39.0, 39.8, 40.6, 41.4]
	if _step >= plan.size() or shot_t < plan[_step]: return
	match _step:
		0: _shot("01_menu.png")
		1:
			_start_game()
			var st := -1
			for k in 5000:
				var i := rng.randi() % (W * H)
				if owner_map[i] == NEUTRAL and _coastal(i) and absi(i % W - W / 2) < 120: st = i; break
			_place_start(st)
			set_speed(3)
			get_viewport().warp_mouse(_screen_of(Vector2(st % W + 6, st / W + 4) * TS))
		2:
			_shot("03_pick_deploy.png")
			deploy_t = 0.0
		3: launch_attack(PLAYER, NEUTRAL, 0.75)
		4:
			peace = elapsed  # end peace early so AI also targets the player / sends boats
			var bb: Rect2i = nations[PLAYER].bb.grow(2).intersection(Rect2i(0, 0, W, H))
			var tgt := -1
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var o := owner_map[y * W + x]
					if o > 1 and _adj_to(y * W + x, PLAYER) and (tgt < 0 or nations[o].troops > nations[tgt].troops): tgt = o
			if tgt > 0: print("land attack on tribe ", tgt, " ok=", launch_attack(PLAYER, tgt, 0.2))
			else: print("no bordering tribe")
			launch_attack(PLAYER, NEUTRAL, 0.3)
		5:
			var ok := false
			var pc: Vector2i = nations[PLAYER].bb.get_center()
			for k in 600:
				var i := rng.randi() % (W * H)
				if owner_map[i] >= 0 and owner_map[i] != PLAYER and _coastal(i) and absi(i % W - pc.x) > 50 and absi(i % W - pc.x) < 160:
					ok = launch_boat(PLAYER, i, 0.25)
					if ok: _pboat = boats[boats.size() - 1]; break
			print("player boat ", ok, " route pts ", (_pboat.pts.size() if _pboat else 0))
		6:
			if _pboat and _pboat in boats:
				var bp := _boat_pos(_pboat)
				var pts: PackedVector2Array = _pboat.pts
				cam.position = (bp[0] + pts[pts.size() - 1]) / 2; cam.zoom = Vector2(2.0, 2.0); _clamp_cam()
				print("boat progress ", int(_pboat.d), "/", int(_pboat.cum[_pboat.cum.size() - 1]))
		7: _shot("06_boat_curve.png")
		8:
			set_speed(3)
			var ai_b := 0
			for bt in boats: if bt.a != PLAYER: ai_b += 1
			print("AI boats at sea ", ai_b, " total boats ", boats.size())
			cam.zoom = Vector2(1.25, 1.25); cam.position = Vector2(W, H) * TS / 2; _clamp_cam()
		9: _shot("07_ai_boats_speed.png")
		10:
			_focus_player(3.0)
			var bb3: Rect2i = nations[PLAYER].bb.grow(2).intersection(Rect2i(0, 0, W, H))
			var tg := -1
			for y in range(bb3.position.y, bb3.end.y):
				for x in range(bb3.position.x, bb3.end.x):
					var o := owner_map[y * W + x]
					if o > 1 and _adj_to(y * W + x, PLAYER) and (tg < 0 or nations[o].troops > nations[tg].troops): tg = o
			if tg > 0: print("front attack on ", tg, " ok=", launch_attack(PLAYER, tg, 0.15))
			var cnt := 0
			for at in attacks:
				if at.a == PLAYER or at.t == PLAYER: cnt += 1
			print("player-involved attacks ", cnt)
			var best := -1
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 30:
					var sp := _screen_of(Vector2(nn.sx / nn.land, nn.sy / nn.land) * TS)
					if sp.x > 400 and sp.x < 1200 and sp.y > 150 and sp.y < 650: best = id; break
			if best > 0:
				var nn = nations[best]
				get_viewport().warp_mouse(_screen_of(Vector2(nn.sx / nn.land, nn.sy / nn.land) * TS))
		11: _shot("08_front.png")
		12:
			_focus_player(3.0)
			var n = nations[PLAYER]
			n.gold = 6e7
			_claim_blob(PLAYER, int(n.sy / n.land) * W + int(n.sx / n.land), 26)  # test harness: give room for buildings
			_focus_player(2.2)
			var placed := 0
			for kk in [5, 1, 1, 4, 10, 0, 2, 0, 3, 0, 2]:
				for tries in 4000:
					var bb2: Rect2i = n.bb
					var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
					if try_build(kk, ti): placed += 1; print("  built ", build_data[kk][1]); break
			for st in structs:
				st.bt = 0.0
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive and owned_count(id, 1) == 0:
					var bbp: Rect2i = nations[id].bb
					for tries in 600:
						var ti := (bbp.position.y + rng.randi() % maxi(1, bbp.size.y)) * W + bbp.position.x + rng.randi() % maxi(1, bbp.size.x)
						if owner_map[ti] == id and _coastal(ti): _struct_add(1, ti, id); struct_at[ti].bt = 0.0; break
			print("buildings placed ", placed, " warship ", try_build(6, -1))
			tip_slot = -1; build_sel = -1
			warp_away()
		13: _shot("05_buildings.png")
		14:
			# nukes at the two nearest other nations
			var n = nations[PLAYER]
			var pc := Vector2(n.sx, n.sy) / maxf(1, n.land)
			var cands := []
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 20: cands.append([pc.distance_to(Vector2(nn.sx, nn.sy) / nn.land), id])
			cands.sort()
			var shots_done := 0
			for c in cands.slice(0, 2):
				for st in structs:
					if st.o == PLAYER and st.k == 5: st.cd = 0.0
				var nn = nations[c[1]]
				var ti := int(nn.sy / nn.land) * W + int(nn.sx / nn.land)
				var kk := 9 if shots_done == 0 else 7
				print("nuke ", build_data[kk][1], " at ", nn.name, " (land=", nn.land, ") ok=", try_build(kk, ti))
				shots_done += 1
			# alliance: ally with a protagonist, then force the expiry warning
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive:
					form_alliance(PLAYER, id)
					allies[_akey(PLAYER, id)] = elapsed + 25.0
					break
		15:
			var tgt := Vector2.ZERO
			if not blasts.is_empty(): tgt = blasts[0].pos
			var fo := 0
			for i in W * H: if fallout[i] == 1: fo += 1
			if tgt == Vector2.ZERO:
				for i in range(0, W * H, 7):
					if fallout[i] == 1: tgt = Vector2(i % W, i / W) * TS; break
			# Also showcase in-flight nukes on parabolic ballistic arcs with 3x thicker (4.5px) host-country-colored trails
			var n = nations[PLAYER]
			var pc := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land))
			var ft := tgt / TS if tgt != Vector2.ZERO else pc + Vector2(36, 12)
			# 1. Standard 1.0x (4.5px) Atom Bomb trail
			missiles.append({"o": PLAYER, "k": 7, "from": pc, "to": ft + Vector2(20, -8), "t": 16.0, "dur": 25.0, "r": float(NUKE_R[7]), "mirv": false, "branched": false})
			# 2. MIRV landed at the aimed point `ft` (detonating there) and branching 6 sub-warheads outward from `ft` with 0.5x (2.25px) trails
			detonate(PLAYER, ft, 6.0, 1.0)
			for m in 6:
				var ang := -PI * 0.85 + float(m) * (PI * 1.7 / 5.0)
				var sub_to := ft + Vector2.from_angle(ang) * (16.0 + float(m % 2) * 8.0)
				missiles.append({"o": PLAYER, "k": 9, "from": ft, "to": sub_to, "t": 13.5 + m * 0.7, "dur": 22.0, "r": float(NUKE_R[9]), "mirv": true, "branched": true})
			var rival_o := 2
			for id in range(2, nations.size()):
				if is_prot(id) and nations[id].alive: rival_o = id; break
			missiles.append({"o": rival_o, "k": 11, "from": ft + Vector2(-42, 16), "to": ft + Vector2(-4, 6), "t": 18.5, "dur": 25.0, "r": 36.0, "mirv": false, "branched": false})
			var b_center: Vector2 = tgt if tgt != Vector2.ZERO else (pc + Vector2(22, 6)) * TS
			blasts.append({"pos": b_center, "r": 16.0 * TS, "t": 0.32, "dur": 1.45, "seed": 424242})
			blasts.append({"pos": b_center + Vector2(36, -18) * TS, "r": 9.0 * TS, "t": 0.14, "dur": 1.45, "seed": 777111})
			print("fallout tiles ", fo, " missiles ", missiles.size(), " blasts ", blasts.size(), " notes ", notes.size())
			cam.zoom = Vector2(2.1, 2.1); cam.position = (pc * TS + b_center) * 0.5; _clamp_cam()
			overlay.queue_redraw()
		16: _shot("10_nukes_fallout_notes.png")
		17:
			print("ally card visible ", ally_card.visible, " notes ", notes.size(), " warships ", warships.size(), " traders ", traders.size(), " structs ", structs.size())
			_shot("11_alliance_card.png")
		18:
			save.unlocked = ["mega", "reinf", "air", "rail"]
			var n = nations[PLAYER]
			n.gold = 6e7
			var built := false
			for tries in 4000:
				var bb2: Rect2i = n.bb
				var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
				if try_build(14, ti): built = true; break
			var fired := 0
			for st in structs:
				if st.k == 14 and st.o == PLAYER:
					st.bt = 0.0
					if launch_sortie(st): fired += 1
			for pl in planes: pl.dur = 40.0; pl.t = 14.0
			var pc := Vector2(n.sx, n.sy) / maxf(1, n.land)
			var best := -1; var bd := 1e9
			for id in range(2, nations.size()):
				var nn = nations[id]
				if nn.alive and nn.land > 20:
					var dd := pc.distance_to(Vector2(nn.sx, nn.sy) / nn.land)
					if dd < bd: bd = dd; best = id
			for st in structs:
				if st.o == PLAYER and st.k == 5: st.cd = 0.0
			if best > 0:
				var nn = nations[best]
				print("railgun ok=", fire_railgun(PLAYER, int(nn.sy / nn.land) * W + int(nn.sx / nn.land)))
				for bm in beams: bm.t = -3.0
			print("airfield built ", built, " sorties ", fired, " planes ", planes.size())
			if not planes.is_empty():
				_focus_player(2.4)
		19: _shot("12_airstrike_railgun.png")
		20:
			# Showcase railways, moving gold trains, in-place Lv2/Lv3 upgrades, construction ring, and exponential price ladder
			var n = nations[PLAYER]
			n.gold = 9e7
			_claim_blob(PLAYER, int(n.sy / maxf(1, n.land)) * W + int(n.sx / maxf(1, n.land)), 26)
			for kk in [0, 2, 0, 2, 1, 3, 5, 4, 10]:
				if owned_count(PLAYER, kk) < (2 if kk in [0, 2] else 1):
					for tries in 3000:
						var bb2: Rect2i = n.bb
						var ti := (bb2.position.y + rng.randi() % maxi(1, bb2.size.y)) * W + bb2.position.x + rng.randi() % maxi(1, bb2.size.x)
						if owner_map[ti] == PLAYER and not struct_at.has(ti) and try_build(kk, ti): break
			var upgraded := 0
			for st in structs:
				if st.o == PLAYER:
					st.bt = 0.0
					if st.k in [0, 2, 4, 5, 10]:
						try_build(st.k, st.tile)
						upgraded += 1
						if st.k in [0, 2] and upgraded <= 3:
							try_build(st.k, st.tile)
					st.bt = 0.0
			# Show one structure actively constructing with progress ring
			# Also guarantee one Factory -> coastal Port/City across water to showcase the straight steel bridge alongside curved land tracks
			var fac_st = null
			for st in structs:
				if st.o == PLAYER and st.k == 2: fac_st = st; break
			if fac_st != null:
				var fp := Vector2(fac_st.tile % W + 0.5, fac_st.tile / W + 0.5)
				for k_ang in 36:
					var ang := float(k_ang) * TAU / 36.0
					var w_seen := false
					for dist_r in range(8, 38):
						var p := fp + Vector2.from_angle(ang) * float(dist_r)
						var tx := int(p.x); var ty := int(p.y)
						if tx < 2 or ty < 2 or tx >= W - 2 or ty >= H - 2: break
						var ti := ty * W + tx
						if owner_map[ti] == WATER:
							w_seen = true
						elif w_seen and owner_map[ti] >= 0 and not struct_at.has(ti):
							var spans_chk := _water_crossing_spans(fp, Vector2(tx + 0.5, ty + 0.5))
							if spans_chk.size() == 1:
								_set_owner(ti, PLAYER)
								_struct_add(1, ti, PLAYER)
								struct_at[ti].bt = 0.0
								# Force a straight bridge entry in path_cache so it renders the steel bridge across the inlet
								var lo_b := mini(fac_st.tile, ti); var hi_b := maxi(fac_st.tile, ti)
								var lp0 := Vector2(lo_b % W + 0.5, lo_b / W + 0.5)
								var hp0 := Vector2(hi_b % W + 0.5, hi_b / W + 0.5)
								var sp0 := _water_crossing_spans(lp0, hp0)
								if sp0.size() >= 1:
									var b_s: Vector2 = sp0[0][0]; var b_e: Vector2 = sp0[0][1]
									var b_pts := PackedVector2Array([lp0, b_s, b_e, hp0])
									var b_cum := PackedFloat32Array([0.0])
									for m in range(1, b_pts.size()): b_cum.append(b_cum[m - 1] + b_pts[m].distance_to(b_pts[m - 1]))
									path_cache["r%d:%d" % [lo_b, hi_b]] = [b_pts, b_cum, [[b_s, b_e]]]
								break
					if path_cache.size() > 0:
						var has_br := false
						for ck in path_cache:
							if String(ck).begins_with("r") and path_cache[ck].size() >= 3 and path_cache[ck][2].size() > 0: has_br = true; break
						if has_br: break
			for st in structs:
				if st.o == PLAYER: st.bt = 0.0
			trains.clear()
			for st in structs:
				if st.o == PLAYER and st.k == 2:
					spawn_train_from(st)
					spawn_train_from(st)
			for st in structs:
				if st.o == PLAYER and st.k == 3:
					st.bt = 1.6; st.bmax = 5.0; break
			for m in trains.size():
				trains[m].dur = 10.0; trains[m].t = 3.0 + m * 2.2
			# Verify capturing enemy military infrastructure (SAM / Silo / Artillery) via land conquest
			var enemy_id := 2
			for id in range(2, nations.size()):
				if nations[id].alive: enemy_id = id; break
			var cap_tile := -1
			for tries in 500:
				var bb3: Rect2i = n.bb
				var ti := (bb3.position.y + rng.randi() % maxi(1, bb3.size.y)) * W + bb3.position.x + rng.randi() % maxi(1, bb3.size.x)
				if owner_map[ti] == PLAYER and not struct_at.has(ti):
					cap_tile = ti; break
			var cap_ok := false
			if cap_tile >= 0:
				owner_map[cap_tile] = enemy_id
				nations[PLAYER].land -= 1; nations[enemy_id].land += 1
				_struct_add(4, cap_tile, enemy_id)  # Enemy SAM Launcher Lv2
				struct_at[cap_tile].level = 2; struct_at[cap_tile].bt = 0.0; _sv += 1
				_set_owner(cap_tile, PLAYER)        # Player conquers tile -> claims SAM Launcher Lv2!
				cap_ok = struct_at.has(cap_tile) and struct_at[cap_tile].o == PLAYER
			var ppos := Vector2(n.sx / maxf(1, n.land), n.sy / maxf(1, n.land)) * TS
			add_float(ppos + Vector2(18, -12), "+10K", GOLD_C)
			add_float(ppos + Vector2(-24, 10), "+35K", GOLD_C)
			_focus_player(2.6)
			_update_hud()
			overlay.queue_redraw()
			print("trains active ", trains.size(), " upgraded ", upgraded, " captured_enemy_struct=", cap_ok)
		21: _shot("16_trains_rails_upgrades.png")
		22:
			# Showcase 3-tier terrain, smooth frontlines, right-click Diplomacy & Embargo popup, and 42% peak growth indicator
			var n = nations[PLAYER]
			n.troops = troop_cap(PLAYER) * 0.42
			_update_hud()
			var target_id := -1
			for id in range(2, nations.size()):
				if nations[id].alive and is_prot(id):
					target_id = id; break
			if target_id < 0:
				for id in range(2, nations.size()):
					if nations[id].alive and nations[id].land > 15:
						target_id = id; break
			if target_id > 0:
				var tn = nations[target_id]
				var tc := Vector2(tn.sx / maxf(1, tn.land), tn.sy / maxf(1, tn.land)) * TS
				cam.zoom = Vector2(2.0, 2.0); cam.position = tc; _clamp_cam()
				_open_diplo(target_id, Vector2(820, 320))
			overlay.queue_redraw()
		23: _shot("17_diplomacy_embargo_terrain.png")
		24:
			if diplo_panel: diplo_panel.visible = false
			_open_settings()
		25:
			_shot("20_settings_graphics.png")
			settings_dlg.visible = false
			console_unlocked = false
			toggle_console()
			console_pass_in.text = "5516"
			_update_console_fps(0.0055)
		26:
			_shot("21_tab_locked_fps.png")
			unlock_console("5516")
			run_console_cmd("help")
			run_console_cmd("gold = 99999999")
			run_console_cmd("boat_speed = 6.0")
			run_console_cmd("NUKE_R[7] = 7")
			run_console_cmd("vars")
			print("tab console visible=", console_panel.visible, " unlocked=", console_unlocked)
		27:
			_shot("19_tab_console.png")
		28:
			if console_panel and console_panel.visible: toggle_console()
			stats.elims = maxi(stats.elims, 3)
			_game_over(true)
		29:
			print("stars after match ", save.stars)
			_shot("13_victory.png")
		30:
			end_dlg.visible = false
			_to_menu()
			save.stars = maxi(save.stars, 9000)
			if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
		31: _shot("14_menu_stars.png")
		32:
			_open_shop()
			# Test unlocking Artillery (2,500 stars) directly in the unified Shop/Stars modal
			var before_s: int = save.stars
			var u_ok := unlock_arsenal_item("art")
			print("shop unlock art ok=", u_ok, " stars ", before_s, " -> ", save.stars)
		33:
			_shot("15_arsenal.png")
			_shot("18_unified_shop.png")
			get_tree().quit()
	_step += 1

func _draw_overlay() -> void:
	var _dt0 := Time.get_ticks_usec()
	_draw_overlay_inner()
	var dus := Time.get_ticks_usec() - _dt0
	if _sfx_log and dus > 40000: print("SLOW draw %.0f ms" % (dus / 1000.0))

func _draw_overlay_inner() -> void:
	if state == "menu" or nations.size() < 2: return
	var f := ThemeDB.fallback_font
	var z := cam.zoom.x
	for id in range(1, nations.size()):
		var n = nations[id]
		if not n.alive or n.land < 4: continue
		var c: Vector2 = n.get("lp", Vector2(n.sx / n.land + 0.5, n.sy / n.land + 0.5) * TS)
		var sp := _screen_of(c)
		if sp.x < -100 or sp.y < -50 or sp.x > 1700 or sp.y > 950: continue
		var fs := int(float(n.get("ls", sqrt(float(n.land)))) * TS * z * 0.28)
		if fs < 8: continue
		fs = mini(fs, 64)
		var nm: String = n.name if id != PLAYER else "You"
		var w := 400.0
		f.draw_string_outline(overlay.get_canvas_item(), sp + Vector2(-w / 2, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(2, fs / 6), Color(1, 1, 1, 0.65))
		overlay.draw_string(f, sp + Vector2(-w / 2, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.08, 0.1, 0.16))
		overlay.draw_string(f, sp + Vector2(-w / 2, fs * 0.95), _fmt(n.troops), HORIZONTAL_ALIGNMENT_CENTER, w, int(fs * 0.8), Color(0.08, 0.1, 0.16, 0.85))
	# structures
	_draw_world_fx(z)
	if build_sel >= 0:
		var mt := _mouse_tile()
		if mt >= 0:
			var ok: bool = build_req(build_sel, mt) == "" and nations[PLAYER].gold >= build_cost(PLAYER, build_sel)
			var mp := get_viewport().get_mouse_position()
			var rr := {3: 30, 4: 70, 10: 45}.get(build_sel, 0) as int
			if build_sel in NUKES: rr = int(NUKE_R[build_sel]) if build_sel != 12 else int(11 * BLAST_S)
			if build_sel == 15: rr = 5
			if build_sel == 14: rr = 150
			if rr > 0:
				var cc := Color(1, 0.3, 0.25) if (build_sel in NUKES or build_sel == 15) else Color(0.3, 0.6, 1)
				overlay.draw_circle(mp, rr * TS * z, Color(cc, 0.12))
				overlay.draw_arc(mp, rr * TS * z, 0, TAU, 64, Color(cc, 0.85), 2.0)
			if build_sel in NUKES:
				var tpw := Vector2(mt % W + 0.5, mt / W + 0.5)
				var inr := icbm_mode or not silo_for(PLAYER, build_sel, tpw).is_empty()
				if not icbm_mode:
					var rpx := nuke_range(build_sel) * TS * z
					for st in structs:
						if st.o == PLAYER and st.k == 5 and st.get("bt", 0.0) <= 0.0:
							var sp0 := _screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)
							overlay.draw_circle(sp0, rpx, Color(1, 0.55, 0.2, 0.06))
							overlay.draw_arc(sp0, rpx, 0, TAU, 128, Color(1, 0.6, 0.25, 0.9), 2.0, true)
				var tgt := _tex("ui_icons/target.png")
				if tgt: overlay.draw_texture_rect(tgt, Rect2(mp - Vector2(14, 14), Vector2(28, 28)), false, Color(1, 0.3, 0.25) if inr else Color(0.5, 0.5, 0.5, 0.8))
				var lbl := ("ICBM  +10%%  (%s)" % _fmt(nuke_cost(build_sel)) if icbm_mode else nuke_range_label(build_sel)) + ("" if inr else "  ·  OUT OF RANGE")
				overlay.draw_string(f_bold, mp + Vector2(18, -14), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.8, 0.5) if inr else Color(1, 0.4, 0.35))
			if build_sel == 2:
				for st in structs:
					if st.o == PLAYER and st.k == 2:
						var sp1 := _screen_of(Vector2(st.tile % W + 0.5, st.tile / W + 0.5) * TS)
						overlay.draw_circle(sp1, FACTORY_RANGE * TS * z, Color(0.95, 0.85, 0.4, 0.06))
						overlay.draw_arc(sp1, FACTORY_RANGE * TS * z, 0, TAU, 96, Color(0.95, 0.85, 0.4, 0.8), 2.0, true)
				var spm := FACTORY_RANGE * TS * z
				overlay.draw_arc(mp, spm, 0, TAU, 96, Color(0.95, 0.85, 0.4, 0.55), 1.5, true)
			if build_sel in NUKES or build_sel == 15:
				overlay.draw_line(mp + Vector2(-10, 0), mp + Vector2(10, 0), Color(1, 0.3, 0.25), 2)
				overlay.draw_line(mp + Vector2(0, -10), mp + Vector2(0, 10), Color(1, 0.3, 0.25), 2)
			else:
				_map_icon(mp, build_sel, Color(0.3, 0.9, 0.4) if ok else Color(0.95, 0.3, 0.3), 0.8)
	# attack fronts (spring-smoothed)
	for at in attacks:
		if at.a != PLAYER and at.t != PLAYER: continue
		if not at.has("disp"): continue
		var sp := _screen_of(at.disp)
		var oid: int = at.t if at.a == PLAYER else at.a
		var mine: float = at.shown if at.a == PLAYER else nations[PLAYER].troops
		var other: float = at.shown if at.a != PLAYER else (nations[oid].troops if oid > 0 else 0.0)
		_badge(sp + Vector2(-3, -10), _fmt(mine), Color(0.2, 0.5, 1.0), true)
		if oid > 0: _badge(sp + Vector2(3, -10), _fmt(other), Color(0.88, 0.22, 0.22), false)
	# boats with curved routes
	for bt in boats:
		var bp := _boat_pos(bt)
		var pts: PackedVector2Array = bt.pts
		var col: Color = nations[bt.a].color
		var route := PackedVector2Array([_screen_of(bp[0])])
		for m in range(bp[2], pts.size()): route.append(_screen_of(pts[m]))
		if route.size() >= 2:
			var lc := Color(col.r, col.g, col.b, 0.85) if bt.a == PLAYER else Color(col.r, col.g, col.b, 0.45)
			overlay.draw_polyline(route, lc, 2.0 if bt.a == PLAYER else 1.5, true)
			overlay.draw_circle(route[route.size() - 1], 4, lc)
		var p0 := _screen_of(bp[0])
		var dir: Vector2 = _sdir(bt, bp[1])
		var nrm := Vector2(-dir.y, dir.x)
		var sc := clampf(cam.zoom.x * 3.0, 5.0, 12.0)
		_wake(p0, dir, sc)
		if not _unit_sprite(p0, 0, col, sc * 2.0, dir.angle()):
			var hull := PackedVector2Array([p0 + dir * sc, p0 + dir * sc * 0.2 + nrm * sc * 0.45, p0 - dir * sc * 0.8 + nrm * sc * 0.4, p0 - dir * sc * 0.8 - nrm * sc * 0.4, p0 + dir * sc * 0.2 - nrm * sc * 0.45])
			overlay.draw_colored_polygon(hull, col.darkened(0.3))
			overlay.draw_polyline(hull + PackedVector2Array([hull[0]]), Color(1, 1, 1, 0.9), 1.2)
		if bt.a == PLAYER or cam.zoom.x > 2.0:
			_badge(p0 + Vector2(0, -sc - 4), _fmt(bt.troops), Color(0.2, 0.5, 1.0) if bt.a == PLAYER else col.darkened(0.4), true, true)

func _icon(p: Vector2, k: int, col: Color, a: float, ci: CanvasItem = null, r := 11.0, bg := true) -> void:
	if ci == null: ci = overlay
	var u := r / 11.0
	var w := Color(1, 1, 1, a) if bg else Color(col, a)
	var dark := Color(0.1, 0.12, 0.2, a)
	if bg:
		ci.draw_circle(p, r + 2 * u, Color(1, 1, 1, a * 0.9))
		ci.draw_circle(p, r, Color(col.darkened(0.35), a))
	else:
		u *= 1.25
	if UI_TEX.has(k):
		var ut := _tex(UI_TEX[k])
		if ut != null:
			var s2 := r * (1.5 if bg else 1.7)
			ci.draw_texture_rect(ut, Rect2(p - Vector2(s2, s2) / 2, Vector2(s2, s2)), false, w)
			return
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in arr: out.append(p + v * u)
		return out
	match k:
		0:  # city: skyline
			ci.draw_rect(Rect2(p + Vector2(-7, -1) * u, Vector2(4, 7) * u), w)
			ci.draw_rect(Rect2(p + Vector2(-2, -7) * u, Vector2(4, 13) * u), w)
			ci.draw_rect(Rect2(p + Vector2(3, -3) * u, Vector2(4, 9) * u), w)
		1:  # port: mast + sail + wave
			ci.draw_line(p + Vector2(-1, -7) * u, p + Vector2(-1, 3) * u, w, 2 * u)
			ci.draw_colored_polygon(P.call([Vector2(0, -6), Vector2(6, 2), Vector2(0, 2)]), w)
			ci.draw_arc(p + Vector2(0, 1) * u, 6.5 * u, 0.35, PI - 0.35, 10, w, 2 * u)
		2:  # factory: saw roof + chimney
			ci.draw_colored_polygon(P.call([Vector2(-7, 6), Vector2(-7, -1), Vector2(-3, -4), Vector2(-3, -1), Vector2(1, -4), Vector2(1, -1), Vector2(7, -1), Vector2(7, 6)]), w)
			ci.draw_rect(Rect2(p + Vector2(4, -8) * u, Vector2(3, 7) * u), w)
		3:  # defense post: shield
			ci.draw_colored_polygon(P.call([Vector2(-6, -6), Vector2(6, -6), Vector2(6, 0), Vector2(0, 7), Vector2(-6, 0)]), w)
			ci.draw_line(p + Vector2(0, -5) * u, p + Vector2(0, 5) * u, dark, 2 * u)
		4:  # SAM: interceptor on launcher
			ci.draw_colored_polygon(P.call([Vector2(0, -8), Vector2(2.5, -3), Vector2(2.5, 3), Vector2(-2.5, 3), Vector2(-2.5, -3)]), w)
			ci.draw_rect(Rect2(p + Vector2(-6, 4) * u, Vector2(12, 3) * u), w)
		5:  # silo: dome over shaft
			ci.draw_arc(p + Vector2(0, 1) * u, 6 * u, PI, TAU, 12, w, 2 * u)
			ci.draw_rect(Rect2(p + Vector2(-6, 1) * u, Vector2(12, 5) * u), w)
			ci.draw_line(p + Vector2(0, -3) * u, p + Vector2(0, 4) * u, dark, 2 * u)
		6:  # warship: hull + tower
			ci.draw_colored_polygon(P.call([Vector2(-8, 1), Vector2(8, 1), Vector2(5, 5), Vector2(-6, 5)]), w)
			ci.draw_rect(Rect2(p + Vector2(-2, -5) * u, Vector2(5, 6) * u), w)
			ci.draw_line(p + Vector2(3, -3) * u, p + Vector2(8, -4) * u, w, 1.5 * u)
		7:  # atom bomb: core + orbit
			ci.draw_circle(p, 3 * u, w)
			ci.draw_arc(p, 7 * u, 0, TAU, 20, w, 1.5 * u)
		8:  # hydrogen bomb: core + two orbits
			ci.draw_circle(p, 2.5 * u, w)
			ci.draw_arc(p, 5 * u, 0, TAU, 16, w, 1.2 * u)
			ci.draw_arc(p, 8 * u, 0, TAU, 20, w, 1.2 * u)
		9:  # MIRV: three warheads
			for dx in [-5, 0, 5]:
				ci.draw_colored_polygon(P.call([Vector2(dx, -6 + absi(dx) * 0.4), Vector2(dx + 2, 0), Vector2(dx - 2, 0)]), w)
			ci.draw_line(p + Vector2(-6, 4) * u, p + Vector2(6, 4) * u, w, 1.5 * u)
		10:  # artillery: barrel + wheel
			ci.draw_line(p + Vector2(-5, 3) * u, p + Vector2(7, -5) * u, w, 3 * u)
			ci.draw_circle(p + Vector2(-2, 4) * u, 3 * u, w)
		11:  # mega nuke: big core, thick ring
			ci.draw_circle(p, 4.5 * u, w)
			ci.draw_arc(p, 8 * u, 0, TAU, 24, w, 2.5 * u)
		12:  # scattershot: center + five satellites
			ci.draw_circle(p, 3 * u, w)
			for m in 5:
				ci.draw_circle(p + Vector2.from_angle(m * TAU / 5 - PI / 2) * 7 * u, 1.6 * u, w)
		13:  # reinforcements: plus + chevron
			ci.draw_rect(Rect2(p + Vector2(-1.5, -7) * u, Vector2(3, 10) * u), w)
			ci.draw_rect(Rect2(p + Vector2(-5, -3.5) * u, Vector2(10, 3) * u), w)
			ci.draw_polyline(P.call([Vector2(-5, 7), Vector2(0, 4), Vector2(5, 7)]), w, 1.5 * u)
		14:  # airfield: little plane
			ci.draw_colored_polygon(P.call([Vector2(0, -8), Vector2(1.5, -3), Vector2(8, 1), Vector2(8, 3), Vector2(1.5, 1), Vector2(1, 5), Vector2(3.5, 7), Vector2(-3.5, 7), Vector2(-1, 5), Vector2(-1.5, 1), Vector2(-8, 3), Vector2(-8, 1), Vector2(-1.5, -3)]), w)
		15:  # railgun: twin rails + bolt
			ci.draw_line(p + Vector2(-7, 5) * u, p + Vector2(5, -7) * u, w, 1.8 * u)
			ci.draw_line(p + Vector2(-5, 7) * u, p + Vector2(7, -5) * u, w, 1.8 * u)
			ci.draw_circle(p + Vector2(7, -7) * u, 2 * u, w)
		_:
			ci.draw_circle(p, 4 * u, w)

func _badge(p: Vector2, t: String, col: Color, left: bool, center := false) -> void:
	var f := ThemeDB.fallback_font
	var fs := 14
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var x := p.x - sz.x / 2 - 5 if center else (p.x - sz.x - 10 if left else p.x)
	var r := Rect2(Vector2(x, p.y - sz.y + 2), sz + Vector2(10, 4))
	overlay.draw_rect(r, col)
	overlay.draw_string(f, Vector2(x + 5, p.y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _pan(dt: float) -> void:
	if console_panel != null and console_panel.visible: return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	cam.position += v * 900.0 * dt / cam.zoom.x
	_clamp_cam()

func _clamp_cam() -> void:
	var half := get_viewport_rect().size / cam.zoom / 2.0
	var m := Vector2(W, H) * TS
	var lo := half - Vector2(80, 80) / cam.zoom
	var hi := m - half + Vector2(80, 200) / cam.zoom
	cam.position.x = clampf(cam.position.x, lo.x, hi.x) if lo.x < hi.x else m.x / 2
	cam.position.y = clampf(cam.position.y, lo.y, hi.y) if lo.y < hi.y else m.y / 2

func _zoom_at(f: float, screen: Vector2) -> void:
	var before := get_global_mouse_position()
	cam.zoom = (cam.zoom * f).clamp(Vector2(0.6, 0.6), Vector2(12, 12))
	cam.force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen
	cam.position += before - after
	_clamp_cam()

func _screen_of(world: Vector2) -> Vector2:
	return get_canvas_transform() * world

func _mouse_tile() -> int:
	var p := get_global_mouse_position() / TS
	var x := int(floor(p.x)); var y := int(floor(p.y))
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return y * W + x

func _attack_at_cursor() -> void:
	var t := _mouse_tile()
	if t < 0: return
	var o: int = owner_map[t]
	if o < 0 or o == PLAYER: return
	# Once your country touches someone else's land, it must ONLY be raided via land; if there is NO land border, use ships!
	if o > 0:
		if _shares_land_border(PLAYER, o):
			launch_attack(PLAYER, o, SHARES[share_i])
		else:
			launch_boat(PLAYER, t, SHARES[share_i])
	else:
		if _shares_land_border(PLAYER, NEUTRAL, t):
			launch_attack(PLAYER, NEUTRAL, SHARES[share_i])
		else:
			launch_boat(PLAYER, t, SHARES[share_i])

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.15, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.15, e.position)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if e.pressed:
				lpress = true; dragging = false; drag_from = e.position
			else:
				if lpress and not dragging and e.button_index == MOUSE_BUTTON_LEFT:
					if state == "pick":
						_place_start(_mouse_tile())
					elif state == "play":
						if build_sel >= 0: try_build(build_sel, _mouse_tile())
						else: _attack_at_cursor()
				elif lpress and not dragging and e.button_index == MOUSE_BUTTON_RIGHT:
					if build_sel >= 0: build_sel = -1
					elif state == "play": _right_click()
				lpress = false; dragging = false
	if e is InputEventMouseMotion and lpress:
		if dragging or e.position.distance_to(drag_from) > 6:
			dragging = true
			cam.position -= e.relative / cam.zoom.x
			_clamp_cam()
	if console_panel != null and console_panel.visible and e is InputEventKey:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q: _set_share(share_i - 1)
			KEY_E: _set_share(share_i + 1)
			KEY_SPACE: if state == "play": _attack_at_cursor()
			KEY_BACKSPACE:
				for k in range(attacks.size() - 1, -1, -1):
					if attacks[k].a == PLAYER:
						retreat(attacks[k]); break
			KEY_TAB: toggle_console()
			KEY_I: if state == "play": set_icbm(not icbm_mode)
			KEY_H: help_panel.visible = not help_panel.visible
			KEY_ESCAPE:
				if build_sel >= 0: build_sel = -1
				else: _to_menu()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				select_build(e.keycode - KEY_1)
			KEY_0: select_build(9)
			KEY_R: select_build(13)
			KEY_MINUS, KEY_KP_SUBTRACT: set_speed_x(sim_speed / SPEED_BASE - 0.5)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: set_speed_x(sim_speed / SPEED_BASE + 0.5)

# ---------------- UI animation ----------------
func _animate_ui(dt: float) -> void:
	_update_console_fps(dt)
	if state == "play" and nations.size() > 1:
		var pl = nations[PLAYER]
		var k := 1.0 - exp(-10.0 * dt)
		shown_troops = lerpf(shown_troops, pl.troops, k)
		shown_gold = lerpf(shown_gold, pl.gold, k)
		bb_troops.text = _fmt(shown_troops)
		bb_gold.text = _fmt(shown_gold)
		bb_cap.position.x = bb_troops.position.x + f_bold.get_string_size(bb_troops.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 6
	# tooltip fade-in
	if tipc.visible and not tip_was_visible:
		tipc.modulate.a = 0.0
		create_tween().tween_property(tipc, "modulate:a", 1.0, 0.12)
	tip_was_visible = tipc.visible
	# deploy ring pulse
	if pick_ring.visible:
		var ph := fmod(deploy_t, 1.0)
		var sc := 1.0 + 0.08 * pow(ph, 3.0)
		pick_ring.pivot_offset = pick_ring.size / 2
		pick_ring.scale = Vector2(sc, sc)

func _fade_in(n: CanvasItem, offset := Vector2(0, 10), dur := 0.2) -> void:
	n.visible = true
	n.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, dur)
	if n is Control and offset != Vector2.ZERO:
		var c := n as Control
		var base: Vector2 = c.get_meta("base_pos", c.position)
		c.set_meta("base_pos", base)
		c.position = base + offset
		tw.tween_property(c, "position", base, dur)

func _fade_out(n: CanvasItem, dur := 0.15) -> void:
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, dur)
	tw.tween_callback(func(): n.visible = false; n.modulate.a = 1.0)

func _pop_in(c: Control, dur := 0.2) -> void:
	c.visible = true
	c.pivot_offset = c.size / 2 if c.size != Vector2.ZERO else Vector2(800, 450)
	c.modulate.a = 0.0; c.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	tw.tween_property(c, "scale", Vector2.ONE, dur)

func _wire_anims(n: Node) -> void:
	for ch in n.get_children():
		if ch is Button:
			var b := ch as Button
			var lift: bool = b in build_btns
			b.mouse_entered.connect(func(): _btn_anim(b, "hover", lift))
			b.mouse_exited.connect(func(): _btn_anim(b, "idle", lift))
			b.button_down.connect(func(): _btn_anim(b, "down", lift); sfx("click", 0.0, 0.02))
			b.button_up.connect(func(): _btn_anim(b, "hover", lift))
		_wire_anims(ch)

func _btn_anim(b: Button, mode: String, lift: bool) -> void:
	if b.has_meta("tw"):
		var old: Tween = b.get_meta("tw")
		if old and old.is_valid(): old.kill()
	b.pivot_offset = b.size / 2
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b.set_meta("tw", tw)
	var sc: float = {"idle": 1.0, "hover": 1.04, "down": 0.95}[mode]
	var br: float = {"idle": 1.0, "hover": 1.15, "down": 0.92}[mode]
	tw.tween_property(b, "modulate", Color(br, br, br, 1), 0.12)
	if lift:
		var base: float = b.get_meta("base_y", b.position.y)
		b.set_meta("base_y", base)
		tw.tween_property(b, "position:y", base - (4.0 if mode == "hover" else (1.0 if mode == "down" else 0.0)), 0.12)
	else:
		tw.tween_property(b, "scale", Vector2(sc, sc), 0.12)

func _set_share(i: int) -> void:
	share_i = clampi(i, 0, SHARES.size() - 1)
	for k in share_btns.size():
		_pill(share_btns[k], false)
		share_btns[k].add_theme_color_override("font_color", Color(0.1, 0.08, 0.05) if k == share_i else Color(0.82, 0.86, 0.95))
	if share_hl:
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(share_hl, "position:x", 3.0 + share_i * 40, 0.16)

func _game_over(win: bool) -> void:
	state = "over"
	build_sel = -1
	_stop_music()
	sfx("victory" if win else "defeat")
	show_end(win)
	return
	over_panel_holder.visible = true
	over_label.text = ("VICTORY" if win else "DEFEAT")
	over_label.add_theme_color_override("font_color", ORANGE_Y if win else RED)
	over_panel_p.get_node("sub").text = ("You hold 80% of the world." if win else "Your nation has fallen.") + "\nTime played: %s" % _fmt_time(elapsed)

func _to_menu() -> void:
	state = "menu"
	_stop_music()
	if bool(save.get("settings", {}).get("music_on", true)): _play_music()
	menu_panel.visible = true
	play_dialog.visible = false
	over_panel_holder.visible = false
	if end_dlg: end_dlg.visible = false
	if note_box: notes.clear(); note_box.queue_redraw()
	if ally_card: ally_card.visible = false
	pick_panel.visible = false
	for n in hud_nodes:
		n.visible = false

# ---------------- UI ----------------
const ORANGE_Y := Color(1.0, 0.72, 0.25)
const GOLD_C := Color(1.0, 0.82, 0.36)
const RED := Color(1.0, 0.36, 0.38)
const GREEN := Color(0.40, 0.88, 0.55)
const CYAN := Color(0.35, 0.80, 1.0)
const MUTED := Color(0.56, 0.62, 0.76)
const TEXT := Color(0.93, 0.95, 1.0)
const PANEL_BG := Color(0.075, 0.09, 0.16, 0.96)
const CELL_BG := Color(0.12, 0.145, 0.24)

func _clean_border_col(c: Color, border: Color, bw: int) -> Color:
	if bw <= 0 or border.a <= 0.0:
		return Color(c.r, c.g, c.b, 0.0)
	if border.a < 0.99 and c.a > 0.25:
		# Pre-composite translucent border over background fill 'c' so Godot's rounded-corner AA strip never interpolates toward pure white (1,1,1)!
		var rgb := Color(c.r, c.g, c.b, 1.0).lerp(Color(border.r, border.g, border.b, 1.0), border.a)
		return Color(rgb.r, rgb.g, rgb.b, c.a)
	return border

func _panel_style(c: Color = PANEL_BG, r: int = 14, border := Color(1, 1, 1, 0.07), bw := 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	# RoWorld UITheme: R_SM 6 / R_MD 10 / R_LG 14 -> panels 12-16 px
	st.set_corner_radius_all(clampi(r, 12, 16))
	st.corner_detail = 10
	st.set_content_margin_all(8)
	st.border_color = _clean_border_col(c, border, bw)
	st.set_border_width_all(bw)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 8
	st.anti_aliasing = true
	return st

func _flat(c: Color, r: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	# buttons 8-10 px, small bars/toggles become pills (Godot clamps radius to half the height)
	st.set_corner_radius_all(r if r < 4 else (clampi(r + 4, 8, 10) if r <= 8 else mini(r + 2, 16)))
	st.corner_detail = 8
	st.border_color = _clean_border_col(c, border, bw)
	st.set_border_width_all(bw)
	st.set_content_margin_all(2)
	st.anti_aliasing = true
	return st

func _P(parent: Node, r: Rect2, c := PANEL_BG, rad := 14, border := Color(1, 1, 1, 0.07), bw := 1, shadow := true) -> Panel:
	var p := Panel.new()
	p.position = r.position; p.size = r.size
	var st := _panel_style(c, rad, border, bw)
	if not shadow: st.shadow_size = 0
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	return p

func _T(parent: Node, t: String, pos: Vector2, fs: int, col := TEXT, font: Font = null, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if font: l.add_theme_font_override("font", font)
	if w > 0:
		l.size = Vector2(w, fs + 8); l.horizontal_alignment = align; l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _head(parent: Node, t: String, pos: Vector2, fs := 12, col := MUTED, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _T(parent, t, pos, fs, col, f_head, w, align)

func _vline(parent: Node, x: float, y: float, h: float) -> void:
	var c := ColorRect.new(); c.color = Color(1, 1, 1, 0.08)
	c.position = Vector2(x, y); c.size = Vector2(1, h); c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func _draw_ctl(parent: Node, r: Rect2, f: Callable) -> Control:
	var c := Control.new()
	c.position = r.position; c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): f.call(c))
	parent.add_child(c)
	return c

func _style_btn(b: Button, on: bool) -> void:
	_pill(b, on)

func _pill(b: Button, on: bool, r := 7) -> void:
	var base := ORANGE_Y if on else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", _flat(base, r))
	b.add_theme_stylebox_override("hover", _flat(base.lightened(0.1) if on else Color(1, 1, 1, 0.08), r))
	b.add_theme_stylebox_override("pressed", _flat(base.darkened(0.1) if on else Color(1, 1, 1, 0.12), r))
	b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), r))
	b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05) if on else Color(0.82, 0.86, 0.95))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05) if on else Color.WHITE)
	b.add_theme_font_override("font", f_bold)

func _btn(t: String, on := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	_pill(b, on)
	return b

func _big_btn(parent: Node, r: Rect2, t: String, col: Color, fs := 20) -> Button:
	var b := Button.new()
	b.position = r.position; b.size = r.size; b.text = t
	b.focus_mode = Control.FOCUS_NONE
	var n := _flat(col, 12, col.darkened(0.25), 0); n.border_width_bottom = 4
	var h := _flat(col.lightened(0.08), 12, col.darkened(0.25), 0); h.border_width_bottom = 4
	var pr := _flat(col.darkened(0.08), 12)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr); b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 12))
	b.add_theme_font_override("font", f_head); b.add_theme_font_size_override("font_size", fs)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, Color(0.12, 0.09, 0.05))
	parent.add_child(b)
	return b

func _card_btn(parent: Node, r: Rect2) -> Button:
	var b := Button.new()
	b.position = r.position; b.size = r.size; b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	_card_style(b, false)
	return b

func _card_style(b: Button, on: bool) -> void:
	var bc := ORANGE_Y if on else Color(1, 1, 1, 0.07)
	var bw := 2 if on else 1
	b.add_theme_stylebox_override("normal", _flat(CELL_BG, 12, bc, bw))
	b.add_theme_stylebox_override("hover", _flat(CELL_BG.lightened(0.06), 12, bc if on else Color(1, 1, 1, 0.18), bw))
	b.add_theme_stylebox_override("pressed", _flat(CELL_BG.lightened(0.1), 12, bc, bw))
	b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 12))

func _lbl(t: String, size := 16, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _map_preview(k: int, pw: int, ph: int) -> ImageTexture:
	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	if map_tab == 0:
		var raw_bytes := _get_handcrafted_map_bytes(k)
		if raw_bytes.size() == W * H:
			for py in ph:
				var sy := clampi(int(float(py) * H / ph), 0, H - 1)
				for px in pw:
					var sx := clampi(int(float(px) * W / pw), 0, W - 1)
					var code: int = raw_bytes[sy * W + sx]
					var c := Color(0.16, 0.33, 0.50, 0.92)
					if code >= 3: c = Color(0.93, 0.93, 0.96)
					elif code == 2: c = Color(0.82, 0.76, 0.56)
					elif code == 1: c = Color(0.70, 0.82, 0.53)
					im.set_pixel(px, py, c)
			return ImageTexture.create_from_image(im)
	var m := _active_map_entry(k)
	var seed_val: int = int(m[1]) + rand_seed_off
	var n := FastNoiseLite.new(); n.seed = seed_val; n.frequency = 0.006; n.fractal_octaves = 6
	var n2 := FastNoiseLite.new(); n2.seed = seed_val + 7; n2.frequency = 0.025
	for py in ph:
		for px in pw:
			var x := float(px) * W / pw; var y := float(py) * H / ph
			var v: float = _sample_map_elev(k, x, y, n, n2)
			var c := Color(0.16, 0.33, 0.50, 0.85)
			if v > 0.0:
				if v > 0.48: c = Color(0.94, 0.94, 0.96)
				elif v > 0.40: c = Color(0.70, 0.65, 0.56)
				elif v > 0.20: c = Color(0.82, 0.76, 0.56)
				else: c = Color(0.70, 0.82, 0.53)
			im.set_pixel(px, py, c)
	return ImageTexture.create_from_image(im)

func _build_ui() -> void:
	f_reg = ThemeDB.fallback_font
	f_bold = FontVariation.new(); f_bold.base_font = f_reg; f_bold.variation_embolden = 0.75
	f_head = FontVariation.new(); f_head.base_font = f_reg; f_head.variation_embolden = 1.0; f_head.spacing_glyph = 2
	ui = CanvasLayer.new()
	add_child(ui)
	_build_menu()
	_build_play_dialog()
	_build_pick()
	_build_top()
	_build_speed()
	_build_leaderboard()
	_build_attacks()
	_build_bottom()
	_build_help()
	_build_over()
	note_box = Control.new(); note_box.position = Vector2(16, 96); note_box.size = Vector2(380, 480)
	note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_box.draw.connect(_draw_notes)
	ui.add_child(note_box)
	_build_ally_card()
	_build_diplo_menu()
	_build_end()
	_build_arsenal()
	_build_settings()
	_build_console()
	_wire_anims(ui)
	_set_share(share_i)
	tipc = Control.new(); tipc.mouse_filter = Control.MOUSE_FILTER_IGNORE; tipc.visible = false
	tipc.draw.connect(_draw_tip)
	ui.add_child(tipc)
	# legacy handles
	for n in hud_nodes: n.visible = false

# ---- main menu ----
func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_panel)
	var shade := ColorRect.new(); shade.color = Color(0.03, 0.05, 0.10, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT); menu_panel.add_child(shade)
	# original emblem: compass rose inside a rounded badge
	_draw_ctl(menu_panel, Rect2(760, 62, 80, 80), func(c: Control):
		c.draw_style_box(_flat(Color(0.10, 0.16, 0.32), 20, Color(1, 1, 1, 0.25), 2), Rect2(0, 0, 80, 80))
		var o := Vector2(40, 40)
		c.draw_arc(o, 26, 0, TAU, 40, ORANGE_Y, 3, true)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2)
			var nn := Vector2(-d.y, d.x)
			c.draw_colored_polygon(PackedVector2Array([o + d * 30, o + nn * 6, o - nn * 6]), Color.WHITE if k % 2 == 0 else Color(0.55, 0.75, 1.0))
		c.draw_circle(o, 5, Color(0.95, 0.35, 0.3)))
	var title := _T(menu_panel, "FRONTLINE CONQUEST", Vector2(0, 150), 86, Color(1.0, 0.95, 0.86), f_head, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	title.size.y = 110
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 6)
	_draw_ctl(menu_panel, Rect2(600, 274, 400, 20), func(c: Control):
		c.draw_line(Vector2(0, 10), Vector2(85, 10), ORANGE_Y, 2)
		c.draw_line(Vector2(315, 10), Vector2(400, 10), ORANGE_Y, 2))
	_head(menu_panel, "CONQUER THE WORLD", Vector2(0, 272), 16, Color(0.9, 0.88, 0.82), 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var cp := _P(menu_panel, Rect2(530, 470, 540, 250))
	_T(cp, "Welcome, Commander", Vector2(0, 16), 15, MUTED, f_reg, 540, HORIZONTAL_ALIGNMENT_CENTER)
	var play := _big_btn(cp, Rect2(18, 46, 430, 60), "PLAY SOLO", ORANGE_Y, 22)
	_draw_ctl(play, Rect2(22, 18, 24, 24), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(4, 2), Vector2(20, 12), Vector2(4, 22)]), Color(0.12, 0.09, 0.05)))
	play.pressed.connect(func(): _pop_in(play_dialog))
	var hb := _card_btn(cp, Rect2(460, 46, 62, 60))
	hb.text = "?"; hb.add_theme_font_override("font", f_head); hb.add_theme_font_size_override("font_size", 24)
	hb.pressed.connect(func(): _pop_in(help_panel))
	_head(cp, "PROGRESSION & SHOP", Vector2(0, 124), 12, GOLD_C, 540, HORIZONTAL_ALIGNMENT_CENTER)
	var set_top := _card_btn(menu_panel, Rect2(1176, 26, 162, 52))
	set_top.add_theme_stylebox_override("normal", _flat(Color(0.07, 0.085, 0.15, 0.94), 6, Color(1, 1, 1, 0.18), 1))
	set_top.add_theme_stylebox_override("hover", _flat(Color(0.14, 0.16, 0.26, 0.98), 6, CYAN, 1))
	set_top.pressed.connect(_open_settings)
	_draw_ctl(set_top, Rect2(14, 13, 26, 26), func(c: Control): _draw_gear(c, Vector2(13, 13), 10.0, CYAN))
	_T(set_top, "SETTINGS", Vector2(46, 8), 16, TEXT, f_bold, 108)
	menu_settings_sub = _T(set_top, "1440p · 180 FPS · Ultra", Vector2(46, 29), 9, MUTED, f_bold, 112)
	var sp := _card_btn(menu_panel, Rect2(1350, 26, 220, 52))
	sp.add_theme_stylebox_override("normal", _flat(Color(0.07, 0.085, 0.15, 0.94), 6, Color(1, 0.8, 0.3, 0.55), 1))
	sp.add_theme_stylebox_override("hover", _flat(Color(0.14, 0.16, 0.26, 0.98), 6, GOLD_C, 1))
	sp.pressed.connect(_open_shop)
	_draw_ctl(sp, Rect2(14, 13, 26, 26), func(c: Control): _star(c, Vector2(13, 13), 11, GOLD_C))
	stars_lbl = _T(sp, _fmt_int(save.stars), Vector2(46, 7), 20, GOLD_C, f_bold, 120)
	_T(sp, "OPEN SHOP  ▸", Vector2(46, 30), 10, MUTED, f_bold, 150)
	var ab := _card_btn(cp, Rect2(18, 150, 368, 80))
	ab.pressed.connect(_open_shop)
	_draw_ctl(ab, Rect2(18, 20, 34, 40), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(34, 0), Vector2(34, 22), Vector2(17, 40), Vector2(0, 22)]), ORANGE_Y)
		_star(c, Vector2(17, 17), 9, Color(0.15, 0.1, 0.03)))
	_head(ab, "SHOP & ARSENAL", Vector2(66, 18), 16, TEXT)
	_T(ab, "●  Stars & weapon unlocks", Vector2(66, 44), 13, MUTED)
	var sb_cfg := _card_btn(cp, Rect2(396, 150, 126, 80))
	sb_cfg.pressed.connect(_open_settings)
	_draw_ctl(sb_cfg, Rect2(46, 14, 34, 34), func(c: Control): _draw_gear(c, Vector2(17, 17), 12.0, CYAN))
	_head(sb_cfg, "SETTINGS", Vector2(0, 50), 13, TEXT, 126, HORIZONTAL_ALIGNMENT_CENTER)
	_T(menu_panel, "Original prototype  ·  procedurally generated maps", Vector2(0, 864), 13, Color(0.6, 0.65, 0.78), f_reg, 1600, HORIZONTAL_ALIGNMENT_CENTER)

# ---- play solo dialog ----
func _build_play_dialog() -> void:
	play_dialog = Control.new(); play_dialog.set_anchors_preset(Control.PRESET_FULL_RECT); play_dialog.visible = false
	ui.add_child(play_dialog)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.6); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_dialog.add_child(sh)
	var p := _P(play_dialog, Rect2(190, 36, 1220, 828), Color(0.07, 0.085, 0.15, 0.98), 18)
	_head(p, "PLAY SOLO", Vector2(32, 20), 28, TEXT)
	_T(p, "Choose from 12 strategic world & regional maps and set AI aggressiveness.", Vector2(32, 56), 14, MUTED)
	var x := _card_btn(p, Rect2(1146, 18, 42, 42)); x.text = "✕"
	x.pressed.connect(func(): play_dialog.visible = false)
	var tab_real := _btn("REAL-WORLD MAPS (12)", true)
	tab_real.position = Vector2(32, 80); tab_real.size = Vector2(216, 28)
	tab_real.add_theme_font_size_override("font_size", 12)
	p.add_child(tab_real)
	var tab_rand := _btn("RANDOM MAPS (12)", false)
	tab_rand.position = Vector2(256, 80); tab_rand.size = Vector2(196, 28)
	tab_rand.add_theme_font_size_override("font_size", 12)
	p.add_child(tab_rand)
	map_tab_btns = [tab_real, tab_rand]
	reroll_btn = _card_btn(p, Rect2(464, 80, 164, 28))
	reroll_btn.text = "REROLL RANDOM SEEDS"
	reroll_btn.add_theme_font_override("font", f_bold)
	reroll_btn.add_theme_font_size_override("font_size", 11)
	reroll_btn.add_theme_color_override("font_color", GOLD_C)
	reroll_btn.visible = false
	reroll_btn.pressed.connect(func():
		rand_seed_off = rng.randi_range(100, 999999)
		_refresh_map_tab_cards())
	tab_real.pressed.connect(func(): _set_map_tab(0))
	tab_rand.pressed.connect(func(): _set_map_tab(1))
	for k in MAPS.size():
		var col_i := k % 4
		var row_i := k / 4
		var c := _card_btn(p, Rect2(32 + col_i * 292, 114 + row_i * 158, 280, 148))
		var tr := TextureRect.new(); tr.texture = _map_preview(k, 148, 82)
		tr.position = Vector2(10, 10); tr.size = Vector2(260, 86); tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.add_child(tr)
		var tl := _T(c, MAPS[k][0], Vector2(12, 100), 15, TEXT, f_bold, 256)
		var sl := _T(c, _map_sub(k, 0), Vector2(12, 122), 12, MUTED, f_reg, 256)
		map_cards.append(c)
		map_card_tex.append(tr)
		map_card_title.append(tl)
		map_card_sub.append(sl)
		c.pressed.connect(func():
			map_i = k
			for j in map_cards.size(): _card_style(map_cards[j], j == k))
	_card_style(map_cards[map_i], true)
	_head(p, "DIFFICULTY", Vector2(32, 594), 12, MUTED)
	var descs := ["Gentle AI · long peace", "Balanced AI", "Ruthless AI · short peace"]
	var cols := [GREEN, ORANGE_Y, RED]
	for k in DIFFS.size():
		var c := _card_btn(p, Rect2(32 + k * 392, 616, 372, 82))
		_draw_ctl(c, Rect2(16, 21, 40, 40), func(cc: Control):
			cc.draw_circle(Vector2(20, 20), 19, Color(cols[k], 0.18))
			cc.draw_arc(Vector2(20, 20), 19, 0, TAU, 32, cols[k], 2, true)
			for b in k + 1: cc.draw_rect(Rect2(10 + b * 8, 26 - b * 5, 5, 6 + b * 5), cols[k]))
		_T(c, DIFFS[k][0], Vector2(70, 14), 18, TEXT, f_bold)
		_T(c, "%s  ·  peace %s" % [descs[k], _fmt_time(DIFFS[k][1])], Vector2(70, 44), 13, MUTED)
		diff_cards.append(c)
		c.pressed.connect(func():
			diff_i = k
			for j in diff_cards.size(): _card_style(diff_cards[j], j == k))
	_card_style(diff_cards[diff_i], true)
	_T(p, "All land is claimable (Plains, Highlands, Mountains). Protagonist nations build cities, ports, railways, and nukes.", Vector2(32, 748), 14, MUTED)
	var st := _big_btn(p, Rect2(880, 732, 308, 60), "START GAME", ORANGE_Y, 22)
	st.pressed.connect(_start_game_ui)

func _set_map_tab(t_idx: int) -> void:
	map_tab = clampi(t_idx, 0, 1)
	if map_tab == 1 and rand_seed_off == 0:
		rand_seed_off = rng.randi_range(100, 999999)
	for j in map_tab_btns.size():
		_pill(map_tab_btns[j], j == map_tab)
	if reroll_btn:
		reroll_btn.visible = (map_tab == 1)
	_refresh_map_tab_cards()

var _preview_queue: Array = []
var _preview_cache := {}
var _pv_job := {}
var _preview_blank: ImageTexture
var preview_pump_us := 0

func _preview_key(k: int) -> String:
	return "%d:%d:%d" % [map_tab, k, rand_seed_off if map_tab == 1 else 0]

func _blank_preview() -> ImageTexture:
	if _preview_blank != null:
		return _preview_blank
	var im := Image.create(148, 82, false, Image.FORMAT_RGBA8)
	im.fill(Color(0.10, 0.18, 0.30, 1))
	_preview_blank = ImageTexture.create_from_image(im)
	return _preview_blank

func _refresh_map_tab_cards() -> void:
	var tbl := RANDOM_MAPS if map_tab == 1 else MAPS
	_pv_job = {}
	_preview_queue.clear()
	for k in map_cards.size():
		map_card_title[k].text = tbl[k][0]
		map_card_sub[k].text = _map_sub(k, map_tab)
		_card_style(map_cards[k], k == map_i)
		var key := _preview_key(k)
		if _preview_cache.has(key):
			map_card_tex[k].texture = _preview_cache[key]
		elif map_tab == 0:
			var tex := _map_preview(k, 148, 82)
			_preview_cache[key] = tex
			map_card_tex[k].texture = tex
		else:
			map_card_tex[k].texture = _blank_preview()
			_preview_queue.append(k)

func _pump_previews() -> void:
	if _loading:
		return
	var t0 := Time.get_ticks_usec()
	var budget := 6000
	while Time.get_ticks_usec() - t0 < budget:
		if _pv_job.is_empty():
			if _preview_queue.is_empty():
				preview_pump_us = 0
				return
			_pv_job = _preview_begin(int(_preview_queue.pop_front()))
		if not _preview_step():
			_pv_job = {}
	preview_pump_us = Time.get_ticks_usec() - t0

func _preview_begin(k: int) -> Dictionary:
	var pw := 148
	var ph := 82
	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	var m := _active_map_entry(k)
	var seed_val: int = int(m[1]) + rand_seed_off
	var nz := FastNoiseLite.new(); nz.seed = seed_val; nz.frequency = 0.006; nz.fractal_octaves = 6
	var nz2 := FastNoiseLite.new(); nz2.seed = seed_val + 7; nz2.frequency = 0.025
	return {"k": k, "key": _preview_key(k), "im": im, "py": 0, "pw": pw, "ph": ph, "n": nz, "n2": nz2}

func _preview_step() -> bool:
	var k: int = _pv_job.k
	var im: Image = _pv_job.im
	var pw: int = _pv_job.pw
	var ph: int = _pv_job.ph
	var py: int = _pv_job.py
	var y1 := mini(ph, py + 3)
	for y in range(py, y1):
		for px in pw:
			var v: float = _sample_map_elev(k, float(px) * W / pw, float(y) * H / ph, _pv_job.n, _pv_job.n2)
			var c := Color(0.16, 0.33, 0.50, 0.85)
			if v > 0.0:
				if v > 0.48: c = Color(0.94, 0.94, 0.96)
				elif v > 0.40: c = Color(0.70, 0.65, 0.56)
				elif v > 0.20: c = Color(0.82, 0.76, 0.56)
				else: c = Color(0.70, 0.82, 0.53)
			im.set_pixel(px, y, c)
	_pv_job.py = y1
	if y1 < ph:
		return true
	var tex := ImageTexture.create_from_image(im)
	_preview_cache[_pv_job.key] = tex
	if k < map_card_tex.size() and _preview_key(k) == str(_pv_job.key):
		map_card_tex[k].texture = tex
	return false

# ---- pick / deploy banner ----
func _build_pick() -> void:
	pick_panel = _P(ui, Rect2(530, 22, 540, 72))
	pick_title = _head(pick_panel, "", Vector2(24, 12), 19, TEXT, 440)
	pick_sub = _T(pick_panel, "", Vector2(24, 40), 15, Color(0.75, 0.8, 0.92), f_reg, 440)
	pick_ring = _draw_ctl(pick_panel, Rect2(476, 12, 48, 48), func(c: Control):
		var v: float = c.get_meta("v", 1.0)
		c.draw_arc(Vector2(24, 24), 20, 0, TAU, 40, Color(1, 1, 1, 0.12), 5, true)
		c.draw_arc(Vector2(24, 24), 20, -PI / 2, -PI / 2 + TAU * v, 40, RED, 5, true)
		f_head.draw_string(c.get_canvas_item(), Vector2(0, 32), str(c.get_meta("n", 5)), HORIZONTAL_ALIGNMENT_CENTER, 48, 22, TEXT))
	pick_panel.visible = false
	pick_label = Label.new()

# ---- top: protection + world control ----
func _build_top() -> void:
	var p := _P(ui, Rect2(545, 22, 520, 76))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(16, 13, 12, 14), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 7), Vector2(6, 14), Vector2(0, 7)]), c.get_meta("col", GREEN)))
	top_left_head = _head(p, "PROTECTED", Vector2(34, 10), 12, GREEN)
	top_timer = _T(p, "0:00", Vector2(16, 30), 30, GREEN, f_bold)
	_vline(p, 150, 14, 48)
	_draw_ctl(p, Rect2(166, 14, 12, 12), func(c: Control):
		c.draw_arc(Vector2(6, 6), 5, 0, TAU, 16, MUTED, 1.5, true); c.draw_line(Vector2(1, 6), Vector2(11, 6), MUTED, 1))
	_head(p, "WORLD CONTROL", Vector2(184, 10), 12, MUTED)
	_head(p, "GOAL 80%", Vector2(380, 10), 12, ORANGE_Y, 124, HORIZONTAL_ALIGNMENT_RIGHT)
	top_bar_ctl = _draw_ctl(p, Rect2(166, 34, 338, 10), func(c: Control):
		var you: float = c.get_meta("you", 0.0); var lead: float = c.get_meta("lead", 0.0)
		c.draw_style_box(_flat(Color(1, 1, 1, 0.10), 4), Rect2(0, 2, 338, 6))
		c.draw_style_box(_flat(Color(0.95, 0.75, 0.3, 0.6), 4), Rect2(0, 2, maxf(2, 338 * lead / 100.0), 6))
		c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 4), Rect2(0, 2, maxf(2, 338 * you / 100.0), 6))
		c.draw_rect(Rect2(338 * 0.8 - 1, 0, 2, 10), ORANGE_Y))
	_draw_ctl(p, Rect2(166, 54, 10, 10), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 2), Rect2(0, 0, 10, 10)))
	top_you = _T(p, "You 0%", Vector2(182, 48), 13, TEXT)
	_draw_ctl(p, Rect2(300, 54, 12, 10), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, 10), Vector2(0, 2), Vector2(3, 5), Vector2(6, 0), Vector2(9, 5), Vector2(12, 2), Vector2(12, 10)]), ORANGE_Y))
	top_lead = _T(p, "", Vector2(318, 48), 13, TEXT, f_reg, 190)

var speed_panel: Panel
var speed_title: Label
var speed_hint: Label
var speed_ticks: Control

func _speed_text_width(text: String, font: Font, fs: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _place_speed_readout() -> void:
	if speed_title == null or speed_lbl == null or speed_hint == null:
		return
	var title_w := _speed_text_width(speed_title.text, f_head, 12)
	var value_w := _speed_text_width(speed_lbl.text, f_bold, 15)
	var hint_w := _speed_text_width(speed_hint.text, f_reg, 12)
	speed_title.position = Vector2(14, 8)
	speed_title.size = Vector2(title_w + 2, 20)
	speed_lbl.position = Vector2(speed_title.position.x + speed_title.size.x + 18, 6)
	speed_lbl.size = Vector2(value_w + 4, 22)
	speed_hint.position = Vector2(speed_lbl.position.x + speed_lbl.size.x + 14, 8)
	speed_hint.size = Vector2(hint_w + 4, 20)
	var row_end := speed_hint.position.x + speed_hint.size.x
	var need := row_end + 16.0 + 36.0 + 12.0
	if speed_panel:
		speed_panel.size.x = maxf(speed_panel.size.x, need)
		speed_panel.size.y = 78
	if speed_slider:
		speed_slider.position = Vector2(14, 36)
		speed_slider.size = Vector2(maxf(120.0, need - 14.0 - 52.0), 22)
	if speed_ticks:
		speed_ticks.position = Vector2(14, 60)
		speed_ticks.size = Vector2(speed_slider.size.x if speed_slider else 170, 10)
	var gear := speed_panel.get_node_or_null("SpeedGear") if speed_panel else null
	if gear is Control and speed_slider:
		gear.position = Vector2(speed_slider.position.x + speed_slider.size.x + 8, 30)

func _build_speed() -> void:
	var widest := 0.0
	for sample in ["0.5x", "1x", "10x"]:
		widest = maxf(widest, 14 + _speed_text_width("GAME SPEED", f_head, 12) + 18 + _speed_text_width(sample, f_bold, 15) + 14 + _speed_text_width("– / +", f_reg, 12) + 16 + 36 + 12)
	var p := _P(ui, Rect2(16, 22, widest, 78))
	speed_panel = p
	hud_nodes.append(p)
	speed_title = _head(p, "GAME SPEED", Vector2(14, 8), 12, MUTED)
	speed_hint = _T(p, "– / +", Vector2(0, 8), 12, MUTED, f_reg)
	speed_lbl = _T(p, "1x", Vector2(0, 6), 15, ORANGE_Y, f_bold)
	var sl := HSlider.new()
	sl.min_value = 0.5; sl.max_value = 10.0; sl.step = 0.5; sl.value = 1.0
	sl.position = Vector2(14, 36); sl.size = Vector2(widest - 66, 22); sl.focus_mode = Control.FOCUS_NONE
	var grab := StyleBoxFlat.new(); grab.bg_color = Color(0.35, 0.80, 1.0, 0.85); grab.set_corner_radius_all(6); grab.content_margin_top = 5; grab.content_margin_bottom = 5
	var trk := StyleBoxFlat.new(); trk.bg_color = Color(1, 1, 1, 0.12); trk.set_corner_radius_all(6); trk.content_margin_top = 5; trk.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", trk); sl.add_theme_stylebox_override("grabber_area", grab); sl.add_theme_stylebox_override("grabber_area_highlight", grab)
	sl.value_changed.connect(func(v: float): set_speed_x(v))
	p.add_child(sl); speed_slider = sl
	speed_ticks = _draw_ctl(p, Rect2(14, 60, sl.size.x, 10), func(c: Control):
		for sp in [0.5, 1.0, 2.0, 5.0, 10.0]:
			var x: float = 8.0 + (sp - 0.5) / 9.5 * (c.size.x - 16.0)
			c.draw_circle(Vector2(x, 4), 2.2, Color(1, 1, 1, 0.55)))
	var cfg_b := _card_btn(p, Rect2(sl.position.x + sl.size.x + 8, 30, 36, 32))
	cfg_b.name = "SpeedGear"
	cfg_b.pressed.connect(_open_settings)
	_draw_ctl(cfg_b, Rect2(6, 4, 24, 24), func(c: Control): _draw_gear(c, Vector2(12, 12), 9.0, CYAN))
	_place_speed_readout()

func _speed_labels_overlap() -> bool:
	if speed_title == null or speed_lbl == null or speed_hint == null:
		return false
	var rects: Array[Rect2] = [speed_title.get_global_rect(), speed_lbl.get_global_rect(), speed_hint.get_global_rect()]
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var hit: Rect2 = rects[i].intersection(rects[j])
			if hit.size.x > 1.0 and hit.size.y > 1.0:
				return true
	return false

# ---- leaderboard ----
func _build_leaderboard() -> void:
	var p := _P(ui, Rect2(1302, 22, 288, 336))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(14, 13, 16, 14), func(c: Control):
		c.draw_rect(Rect2(0, 6, 4, 8), ORANGE_Y); c.draw_rect(Rect2(6, 0, 4, 14), ORANGE_Y); c.draw_rect(Rect2(12, 3, 4, 11), ORANGE_Y))
	_head(p, "LEADERBOARD", Vector2(38, 10), 14, TEXT)
	lb_alive = _T(p, "", Vector2(160, 11), 13, MUTED, f_reg, 112, HORIZONTAL_ALIGNMENT_RIGHT)
	_head(p, "#", Vector2(16, 38), 10, MUTED)
	_head(p, "NATION", Vector2(52, 38), 10, MUTED)
	_head(p, "LAND", Vector2(170, 38), 10, MUTED, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	_head(p, "TROOPS", Vector2(222, 38), 10, MUTED, 52, HORIZONTAL_ALIGNMENT_RIGHT)
	for k in 10:
		var y := 58 + k * 23
		var row := [
			_T(p, str(k + 1), Vector2(8, y), 13, MUTED, f_bold, 22, HORIZONTAL_ALIGNMENT_RIGHT),
			_draw_ctl(p, Rect2(38, y + 7, 9, 9), func(c: Control): c.draw_style_box(_flat(c.get_meta("col", Color.GRAY), 2), Rect2(0, 0, 9, 9))),
			_T(p, "", Vector2(52, y), 13, TEXT, f_bold, 118),
			_T(p, "", Vector2(170, y), 13, TEXT, f_bold, 52, HORIZONTAL_ALIGNMENT_RIGHT),
			_T(p, "", Vector2(222, y), 13, Color(0.85, 0.88, 0.95), f_reg, 52, HORIZONTAL_ALIGNMENT_RIGHT)]
		lb_rows.append(row)
	lb_dots = _T(p, "•••", Vector2(0, 286), 12, MUTED, f_bold, 288, HORIZONTAL_ALIGNMENT_CENTER)
	var me := _P(p, Rect2(8, 302, 272, 28), Color(0.16, 0.14, 0.12), 8, ORANGE_Y, 1, false)
	lb_me = [
		_T(me, "", Vector2(0, 4), 13, MUTED, f_bold, 30, HORIZONTAL_ALIGNMENT_RIGHT),
		_draw_ctl(me, Rect2(30, 10, 9, 9), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 2), Rect2(0, 0, 9, 9))),
		_T(me, "You", Vector2(44, 4), 13, ORANGE_Y, f_bold, 118),
		_T(me, "", Vector2(162, 4), 13, TEXT, f_bold, 52, HORIZONTAL_ALIGNMENT_RIGHT),
		_T(me, "", Vector2(214, 4), 13, TEXT, f_reg, 52, HORIZONTAL_ALIGNMENT_RIGHT)]

# ---- attacks ----
var atk_panel_p: Panel
func _build_attacks() -> void:
	atk_panel_p = _P(ui, Rect2(1302, 368, 288, 80))
	hud_nodes.append(atk_panel_p)
	_draw_ctl(atk_panel_p, Rect2(14, 13, 14, 14), func(c: Control):
		c.draw_line(Vector2(0, 0), Vector2(14, 14), ORANGE_Y, 2); c.draw_line(Vector2(14, 0), Vector2(0, 14), ORANGE_Y, 2))
	_head(atk_panel_p, "ATTACKS", Vector2(36, 10), 14, TEXT)
	atk_count = _T(atk_panel_p, "", Vector2(160, 11), 13, MUTED, f_reg, 112, HORIZONTAL_ALIGNMENT_RIGHT)
	atk_empty = _T(atk_panel_p, "No active attacks", Vector2(16, 44), 13, MUTED)
	for k in 6:
		var y := 40 + k * 32
		var bg := _P(atk_panel_p, Rect2(8, y, 272, 28), CELL_BG, 8, Color(0, 0, 0, 0), 0, false)
		var dot := _draw_ctl(bg, Rect2(8, 9, 10, 10), func(c: Control):
			c.draw_circle(Vector2(5, 5), 5, c.get_meta("col", GREEN)); c.draw_circle(Vector2(5, 5), 2.5, Color(0, 0, 0, 0.35)))
		var nm := _T(bg, "", Vector2(26, 4), 13, TEXT, f_bold, 140)
		var tr := _T(bg, "", Vector2(160, 4), 13, TEXT, f_bold, 66, HORIZONTAL_ALIGNMENT_RIGHT)
		var rb := Button.new(); rb.position = Vector2(236, 2); rb.size = Vector2(32, 24); rb.focus_mode = Control.FOCUS_NONE
		rb.add_theme_stylebox_override("normal", _flat(Color(1, 1, 1, 0.07), 6)); rb.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.16), 6))
		rb.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.2), 6))
		bg.add_child(rb)
		_draw_ctl(rb, Rect2(8, 4, 16, 16), func(c: Control):
			c.draw_arc(Vector2(9, 9), 5, -PI * 0.9, PI * 0.5, 12, TEXT, 1.6, true)
			c.draw_colored_polygon(PackedVector2Array([Vector2(0, 5), Vector2(6, 2), Vector2(5, 8)]), TEXT))
		var kk: int = k
		rb.pressed.connect(func():
			var mine := _player_attacks()
			if kk < mine.size() and mine[kk] in attacks and mine[kk].a == PLAYER: retreat(mine[kk]))
		atk_rows.append([bg, dot, nm, tr, rb])

func _player_attacks() -> Array:
	var out := []
	for at in attacks:
		if at.a == PLAYER: out.append(at)
	for at in attacks:
		if at.t == PLAYER: out.append(at)
	return out

# ---- bottom bar ----
var icbm_btn: Button
var _ema_regen := 0.0
var _ema_gold := 0.0
var _ema_init := false
var _hud_rate_t := 0.0
var _hud_txt_t := 0.0
func _build_bottom() -> void:
	var p := _P(ui, Rect2(320, 706, 960, 182))
	hud_nodes.append(p)
	_draw_ctl(p, Rect2(22, 20, 14, 14), func(c: Control): c.draw_style_box(_flat(Color(0.3, 0.6, 1.0), 3, Color(1, 1, 1, 0.6), 1), Rect2(0, 0, 14, 14)))
	_T(p, "You", Vector2(44, 12), 20, TEXT, f_bold)
	bb_name_sub = _T(p, "", Vector2(22, 44), 13, MUTED)
	_vline(p, 236, 14, 70)
	# troops
	_draw_ctl(p, Rect2(252, 11, 17, 17), func(c: Control):
		var ti := _tex("ui_icons/troops.png")
		if ti: c.draw_texture_rect(ti, Rect2(0, 0, 17, 17), false, MUTED)
		else: c.draw_circle(Vector2(6, 3), 3, MUTED))
	_head(p, "TROOPS", Vector2(272, 10), 11, MUTED)
	bb_regen = _T(p, "", Vector2(330, 10), 13, GREEN, f_bold, 130, HORIZONTAL_ALIGNMENT_RIGHT)
	bb_regen.clip_text = true
	bb_troops = _T(p, "", Vector2(252, 26), 28, TEXT, f_bold)
	bb_cap = _T(p, "", Vector2(340, 37), 14, MUTED)
	bb_bar = _draw_ctl(p, Rect2(254, 70, 100, 8), func(c: Control):
		var v: float = c.get_meta("v", 0.0)
		c.draw_style_box(_flat(Color(1, 1, 1, 0.1), 3), Rect2(0, 1, 100, 5))
		c.draw_style_box(_flat(Color(0.35, 0.62, 1.0), 3), Rect2(0, 1, maxf(3, 100 * v), 5))
		c.draw_rect(Rect2(42, 0, 2, 7), GOLD_C))
	bb_war = _T(p, "", Vector2(360, 62), 13, ORANGE_Y, f_bold, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	_vline(p, 474, 14, 70)
	# attack share
	_draw_ctl(p, Rect2(490, 15, 11, 11), func(c: Control):
		c.draw_line(Vector2(0, 0), Vector2(11, 11), MUTED, 1.6); c.draw_line(Vector2(11, 0), Vector2(0, 11), MUTED, 1.6))
	_head(p, "ATTACK", Vector2(508, 10), 11, MUTED)
	bb_share = _T(p, "", Vector2(630, 9), 14, ORANGE_Y, f_bold, 60, HORIZONTAL_ALIGNMENT_RIGHT)
	var pill := _P(p, Rect2(488, 32, 204, 30), Color(1, 1, 1, 0.06), 8, Color(0, 0, 0, 0), 0, false)
	share_hl = _P(pill, Rect2(3 + share_i * 40, 3, 38, 24), ORANGE_Y, 7, Color(0, 0, 0, 0), 0, false)
	for k in SHARES.size():
		var b := _btn("%d%%" % int(SHARES[k] * 100), k == share_i)
		b.position = Vector2(3 + k * 40, 3); b.size = Vector2(38, 24)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func(): _set_share(k))
		pill.add_child(b); share_btns.append(b)
	bb_sends = _T(p, "", Vector2(490, 64), 13, MUTED)
	_vline(p, 708, 14, 70)
	# gold
	_draw_ctl(p, Rect2(722, 11, 17, 17), func(c: Control):
		var tg := _tex("ui_icons/gold.png")
		if tg: c.draw_texture_rect(tg, Rect2(0, 0, 17, 17), false, GOLD_C)
		else: c.draw_circle(Vector2(6, 6), 6, GOLD_C))
	_head(p, "GOLD", Vector2(742, 10), 11, MUTED)
	bb_goldrate = _T(p, "", Vector2(780, 10), 13, GREEN, f_bold, 100, HORIZONTAL_ALIGNMENT_RIGHT)
	bb_goldrate.clip_text = true
	bb_gold = _T(p, "", Vector2(722, 30), 28, GOLD_C, f_bold)
	# build slots
	var builds := [
		["1", "City", 125e3, "Adds 25K to your troop cap per level. Click an existing City to upgrade."],
		["2", "Port", 125e3, "Coastal only. Boosts overall gold income by 1.01x per level, hubs Trade Ships, and launches Warships."],
		["3", "Factory", 125e3, "Connects railways to Cities & Ports and dispatches one-way Gold Trucks."],
		["4", "Defense Post", 50e3, "Land within 30 tiles costs attackers 5x troops and 3x time (non-stacking)."],
		["5", "SAM Launcher", 1.5e6, "Intercepts bombs (70-150 tiles by level, 9s reload cooldown)."],
		["6", "Missile Silo", 1e6, "Required to launch Nukes and fire the Railgun (10s reload cooldown, faster per level)."],
		["7", "Warship", 250e3, "1,000 HP, 250 dmg/shell. Sinks transports, captures trade ships, gains veterancy."],
		["8", "Atom Bomb", 750e3, "Tactical nuclear strike (7-tile blast radius) that leaves radioactive fallout."],
		["9", "Hydrogen Bomb", 5e6, "Strategic nuclear blast (25-tile radius) that wipes structures and troops."],
		["0", "MIRV", 25e6, "Splits into branched warheads covering 65-85% of the targeted country in fallout."],
		["", "Artillery", 150e3, "Shells enemy troops within 45 tiles. Upgrades halve firing cooldown (2s / 2^(Lv-1))."],
		["", "Mega Nuke", 2.5e6, "Heavy nuclear warhead (15-tile blast radius)."],
		["", "Scattershot", 3.75e6, "One central bomb plus five surrounding sub-warheads."],
		["", "Reinforcements", 500e3, "Instantly adds a fifth of your troop cap. 30 s cooldown."],
		["", "Airfield", 500e3, "Launches bomber sorties every 18 s (5 warheads base, +1 warhead per upgrade level)."],
		["", "Railgun", 2.5e6, "Fires a hypersonic beam from a ready Missile Silo to any spot on the map."],
		["I", "ICBM", 0.0, "Upgrade toggle, not a warhead: while ON every bomb launch ignores range and costs +10% of that bomb's price."]]
	build_data = builds
	var sx := 16.0
	var order := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 11, 12, 10, 13, 14, 15]
	build_btns.resize(builds.size()); slot_price.resize(builds.size())
	for k in order:
		if k == 7: sx += 10
		var b := Button.new()
		b.position = Vector2(sx, 98); b.size = Vector2(46, 70); b.focus_mode = Control.FOCUS_NONE
		sx += 49
		b.add_theme_stylebox_override("normal", _flat(CELL_BG, 8, Color(1, 1, 1, 0.06), 1))
		b.add_theme_stylebox_override("hover", _flat(CELL_BG.lightened(0.08), 8, Color(1, 1, 1, 0.2), 1))
		b.add_theme_stylebox_override("pressed", _flat(CELL_BG.lightened(0.12), 8, ORANGE_Y, 1))
		b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), 8))
		p.add_child(b)
		var kk: int = k
		if builds[k][0] != "": _T(b, builds[k][0], Vector2(5, 1), 10, MUTED, f_bold)
		var ic := Control.new(); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = Vector2(7, 16); ic.size = Vector2(32, 30)
		ic.draw.connect(func(): _icon(Vector2(16, 15), kk, Color(0.62, 0.7, 0.9) if is_avail(kk) else Color(0.45, 0.48, 0.58), 1.0 if is_avail(kk) else 0.4, ic, 11.0, false))
		b.add_child(ic)
		slot_price[k] = _T(b, _fmt(builds[k][2]), Vector2(0, 50), 12, GOLD_C, f_bold, 46, HORIZONTAL_ALIGNMENT_CENTER)
		b.pressed.connect(func(): select_build(kk))
		b.mouse_entered.connect(func(): tip_slot = kk)
		b.mouse_exited.connect(func(): if tip_slot == kk: tip_slot = -1)
		build_btns[k] = b
	var shop := _big_btn(p, Rect2(sx + 8, 98, 72, 70), "", ORANGE_Y, 12)
	_draw_ctl(shop, Rect2(0, 0, 72, 70), func(c: Control):
		var col := Color(0.12, 0.09, 0.05)
		c.draw_rect(Rect2(22, 20, 28, 20), col)
		c.draw_arc(Vector2(36, 20), 8, PI, TAU, 12, col, 3)
		c.draw_circle(Vector2(36, 30), 3, ORANGE_Y)
		f_head.draw_string(c.get_canvas_item(), Vector2(0, 60), "SHOP", HORIZONTAL_ALIGNMENT_CENTER, 72, 12, col))
	shop.pressed.connect(_open_shop)
	shop.mouse_entered.connect(func(): tip_slot = 99)
	shop.mouse_exited.connect(func(): if tip_slot == 99: tip_slot = -1)

# ---- help ----
func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.visible = false
	help_panel.position = Vector2(300, 110); help_panel.size = Vector2(1000, 640)
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.085, 0.15, 0.98), 18))
	ui.add_child(help_panel)
	var c := Control.new(); c.custom_minimum_size = Vector2(984, 624); help_panel.add_child(c)
	_head(c, "HOW TO PLAY", Vector2(28, 18), 28, TEXT)
	_T(c, "Grow from a single foothold to 80% of the world.", Vector2(28, 58), 15, MUTED)
	var x := _card_btn(c, Rect2(924, 16, 44, 44)); x.text = "✕"
	x.pressed.connect(func(): help_panel.visible = false)
	var items := [
		["01", "Found your nation", "Click unclaimed land. You have 5 seconds to change your mind.", ORANGE_Y],
		["02", "Grow & fight", "Click wilderness to expand or a neighbour to attack. Q / E or the Attack pills set how many troops go.", RED],
		["03", "Cross the sea", "Click a coast you can't reach by land: a transport sails from your nearest shore.", CYAN],
		["04", "Build", "Keys 1-4 then click your land: City, Port (coast), Factory, Defense Post. R = reinforcements.", GREEN],
		["05", "Controls", "WASD / arrows or drag to pan · wheel zoom · Space attack at cursor · Backspace retreat · -/+ speed · Esc menu", Color(0.7, 0.6, 1.0)]]
	for k in items.size():
		var it = items[k]
		var card := _P(c, Rect2(28 + (k % 2) * 470, 96 + (k / 2) * 170, 456 if k < 4 else 926, 150), CELL_BG, 14, Color(1, 1, 1, 0.06), 1, false)
		var col: Color = it[3]
		_draw_ctl(card, Rect2(18, 20, 48, 48), func(cc: Control):
			cc.draw_circle(Vector2(24, 24), 23, Color(col, 0.18)); cc.draw_arc(Vector2(24, 24), 23, 0, TAU, 36, col, 2, true)
			cc.draw_circle(Vector2(24, 24), 6, col))
		_T(card, it[0], Vector2(82, 18), 14, col, f_bold)
		_T(card, it[1], Vector2(110, 15), 19, TEXT, f_bold)
		var d := _T(card, it[2], Vector2(82, 48), 15, Color(0.8, 0.84, 0.94))
		d.size = Vector2((456 if k < 4 else 926) - 100, 90); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_over() -> void:
	var holder := Control.new(); holder.set_anchors_preset(Control.PRESET_FULL_RECT); holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)
	var p := _P(holder, Rect2(600, 300, 400, 240))
	over_label = _head(p, "", Vector2(0, 30), 40, ORANGE_Y, 400, HORIZONTAL_ALIGNMENT_CENTER)
	over_label.size.y = 52
	var sub := _T(p, "", Vector2(0, 92), 16, MUTED, f_reg, 400, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "sub"; sub.size.y = 50
	var mb := _big_btn(p, Rect2(90, 160, 220, 52), "MAIN MENU", ORANGE_Y, 18)
	mb.pressed.connect(_to_menu)
	over_panel = PanelContainer.new()
	holder.visible = false
	# use holder as the toggled node
	over_panel = null
	over_panel_holder = holder
	over_panel_p = p

var over_panel_holder: Control
var over_panel_p: Panel

# ---- tooltip rendering ----
func _wrap(t: String, f: Font, fs: int, w: float) -> Array:
	var out := []
	var line := ""
	for word in t.split(" "):
		var cand := word if line == "" else line + " " + word
		if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w and line != "":
			out.append(line); line = word
		else:
			line = cand
	if line != "": out.append(line)
	return out

func _show_tip(d: Dictionary, anchor: Vector2, above: bool) -> void:
	tip_data = d
	var w := 360.0
	var h := 16.0 + 30.0
	if d.has("sub"): h += 22
	h += d.get("rows", []).size() * 26
	if d.has("desc"):
		d.desc_lines = _wrap(d.desc, f_reg, 15, w - 32)
		h += 8 + d.desc_lines.size() * 20
	if d.has("foot"):
		d.foot_lines = _wrap(d.foot, f_bold, 15, w - 60)
		h += 20 + d.foot_lines.size() * 20
	h += 14
	tipc.size = Vector2(w, h)
	var pos := anchor + (Vector2(-w / 2, -h - 12) if above else Vector2(18, 18))
	pos.x = clampf(pos.x, 8, 1600 - w - 8); pos.y = clampf(pos.y, 8, 900 - h - 8)
	tipc.position = pos
	tipc.visible = true
	tipc.queue_redraw()

func _draw_tip() -> void:
	var d := tip_data
	var w := tipc.size.x
	tipc.draw_style_box(_panel_style(Color(0.07, 0.085, 0.15, 0.97), 12, Color(1, 1, 1, 0.1), 1), Rect2(Vector2.ZERO, tipc.size))
	var ci := tipc.get_canvas_item()
	var y := 16.0
	f_bold.draw_string(ci, Vector2(16, y + 20), d.get("title", ""), HORIZONTAL_ALIGNMENT_LEFT, w - 90, 21, TEXT)
	if d.has("badge"):
		var bt: String = d.badge
		var bc: Color = d.get("badge_col", MUTED)
		var bw := f_bold.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
		tipc.draw_style_box(_flat(Color(bc, 0.15), 10, bc, 1), Rect2(w - 16 - bw, y + 4, bw, 22))
		f_bold.draw_string(ci, Vector2(w - 16 - bw, y + 20), bt, HORIZONTAL_ALIGNMENT_CENTER, bw, 13, bc)
	y += 30
	if d.has("sub"):
		f_reg.draw_string(ci, Vector2(16, y + 14), d.sub, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 14, Color(0.75, 0.8, 0.92))
		y += 22
	for r in d.get("rows", []):
		f_reg.draw_string(ci, Vector2(16, y + 18), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
		f_bold.draw_string(ci, Vector2(16, y + 18), r[1], HORIZONTAL_ALIGNMENT_RIGHT, w - 32, 16, r[2])
		y += 26
	if d.has("desc_lines"):
		y += 4
		for ln in d.desc_lines:
			f_reg.draw_string(ci, Vector2(16, y + 16), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.82, 0.86, 0.95))
			y += 20
		y += 4
	if d.has("foot_lines"):
		y += 6
		tipc.draw_line(Vector2(16, y), Vector2(w - 16, y), Color(1, 1, 1, 0.1), 1)
		y += 10
		var fc: Color = d.get("foot_col", RED)
		var o := Vector2(26, y + 11)
		if d.get("foot_icon", "!") == "!":
			tipc.draw_circle(o, 8, fc)
			f_head.draw_string(ci, o + Vector2(-8, 5), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color(0.07, 0.08, 0.14))
		else:
			tipc.draw_arc(o, 7, 0, TAU, 20, fc, 1.8, true); tipc.draw_circle(o, 2.5, fc)
			for dd in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				tipc.draw_line(o + dd * 7, o + dd * 10, fc, 1.8)
		for ln in d.foot_lines:
			f_bold.draw_string(ci, Vector2(44, y + 16), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, fc)
			y += 20

func _update_build_tip() -> bool:
	if tip_slot < 0 or state != "play":
		return false
	var pl = nations[PLAYER]
	if tip_slot == 99:
		_show_tip({"title": "Shop & Arsenal (★ %s)" % _fmt_int(save.stars), "desc": "Stars & Shop are unified here: view your Star balance, match reward breakdown, and unlock weapons & perks.", "foot": "Click to open Shop & Arsenal", "foot_col": GOLD_C, "foot_icon": "o"}, Vector2(build_btns[13].global_position.x + 100, 800), true)
		return true
	var k := tip_slot
	if k == 16:
		var rows := [["Status", "ON" if icbm_mode else "OFF", ORANGE_Y if icbm_mode else MUTED], ["Fee", "+10% of the bomb's price", GOLD_C]]
		for nk in [7, 8, 9, 11, 12]:
			rows.append([build_data[nk][1], "%s  →  %s" % [_fmt(float(build_data[nk][2])), _fmt(float(build_data[nk][2]) * (1.0 + ICBM_FEE_PCT))], GOLD_C])
		_show_tip({"title": "ICBM upgrade", "badge": "I", "rows": rows, "desc": build_data[16][3], "foot": "Click to turn " + ("OFF" if icbm_mode else "ON"), "foot_col": CYAN, "foot_icon": "o"}, build_btns[16].global_position + Vector2(25, 0), true)
		return true
	var bd = build_data[k]
	var cost := build_cost(PLAYER, k)
	var d := {"title": bd[1], "rows": [["Cost", _fmt(cost) + " gold", GOLD_C]], "desc": bd[3]}
	if bd[0] != "": d.badge = bd[0]
	if k == 13:
		d.rows.append(["Brings", _fmt(minf(troop_cap(PLAYER) / 5.0, troop_cap(PLAYER) - pl.troops)) + " troops", TEXT])
	else:
		var oc := owned_count(PLAYER, k)
		var ol := owned(PLAYER, k)
		d.rows.append(["Owned / Levels", ("%d (total Lv %d)" % [oc, ol]) if k in UPGRADABLE else str(oc), TEXT])
		if k in UPGRADABLE:
			d.rows.append(["Upgrade", "Click existing %s on map" % bd[1], GREEN])
	if k in [7, 8, 9, 11]:
		d.rows.append(["Blast radius", "%d tiles" % int(NUKE_R[k]) if k != 9 else "many warheads", TEXT])
		d.rows.append(["Range", "Anywhere (ICBM +10%)" if icbm_mode else nuke_range_label(k), ORANGE_Y if icbm_mode else TEXT])
	var req := build_req(k, -1)
	if k == 13 and pl.troops >= troop_cap(PLAYER) - 1: req = "Your army is already at its cap"
	if req != "":
		d.foot = req; d.foot_col = RED
	elif pl.gold < cost:
		d.foot = "Need %s more gold" % _fmt(cost - pl.gold); d.foot_col = RED
	elif k == 13:
		d.foot = "Click to call them in now"; d.foot_col = CYAN; d.foot_icon = "o"
	elif k == 6:
		d.foot = "Click to select & place on water (or click twice to launch at Port)"; d.foot_col = CYAN; d.foot_icon = "o"
	else:
		d.foot = "Click, then pick a spot on your land" + (" by the coast" if k == 1 else ""); d.foot_col = CYAN; d.foot_icon = "o"
	var b: Button = build_btns[k]
	_show_tip(d, b.global_position + Vector2(25, 0), true)
	return true

func _update_hud() -> void:
	if nations.size() < 2: return
	var pl = nations[PLAYER]
	var left := peace - elapsed
	if left > 0:
		top_left_head.text = "PROTECTED"; top_left_head.add_theme_color_override("font_color", GREEN)
		top_timer.text = _fmt_time(left); top_timer.add_theme_color_override("font_color", GREEN)
	else:
		top_left_head.text = "AT WAR"; top_left_head.add_theme_color_override("font_color", RED)
		top_timer.text = _fmt_time(elapsed); top_timer.add_theme_color_override("font_color", TEXT)
	var pct: float = 100.0 * pl.land / maxf(1, land_total)
	var ids := []
	for id in range(1, nations.size()):
		if nations[id].alive and nations[id].land > 0: ids.append(id)
	ids.sort_custom(func(a, b): return nations[a].land > nations[b].land)
	var lead_id: int = ids[0] if ids.size() > 0 else PLAYER
	var lead_pct: float = 100.0 * nations[lead_id].land / maxf(1, land_total)
	top_bar_ctl.set_meta("you", pct); top_bar_ctl.set_meta("lead", lead_pct); top_bar_ctl.queue_redraw()
	top_you.text = "You %s" % _pct(pct)
	top_lead.text = "%s %s" % [("You" if lead_id == PLAYER else nations[lead_id].name), _pct(lead_pct)]
	# leaderboard
	lb_alive.text = "%d alive" % ids.size()
	for k in 10:
		var row = lb_rows[k]
		var vis: bool = k < ids.size()
		for c in row: c.visible = vis
		if not vis: continue
		var n = nations[ids[k]]
		row[0].add_theme_color_override("font_color", ORANGE_Y if k == 0 else MUTED)
		row[1].set_meta("col", n.color); row[1].queue_redraw()
		row[2].text = "You" if ids[k] == PLAYER else n.name
		row[2].add_theme_color_override("font_color", ORANGE_Y if ids[k] == PLAYER else TEXT)
		row[3].text = _pct(100.0 * n.land / maxf(1, land_total))
		row[4].text = _fmt(n.troops)
	var my_rank := ids.find(PLAYER) + 1
	lb_me[0].text = str(my_rank); lb_me[3].text = _pct(pct); lb_me[4].text = _fmt(pl.troops)
	# attacks
	var list := _player_attacks()
	var outs := 0
	for at in list: if at.a == PLAYER: outs += 1
	atk_count.text = "%d out · %d in" % [outs, list.size() - outs]
	atk_empty.visible = list.is_empty()
	for k in atk_rows.size():
		var r = atk_rows[k]
		var vis: bool = k < list.size()
		r[0].visible = vis
		if not vis: continue
		var at = list[k]
		var out: bool = at.a == PLAYER
		var other: int = at.t if out else at.a
		r[1].set_meta("col", GREEN if out else RED); r[1].queue_redraw()
		r[2].text = ("Expansion" if other == NEUTRAL else nations[other].name) if out else ("⚠ " + nations[other].name)
		r[2].add_theme_color_override("font_color", TEXT if out else RED)
		r[3].text = _fmt(at.troops)
		r[4].visible = out
	atk_panel_p.size.y = 40 + maxi(1, list.size()) * 32 + 8
	# bottom
	bb_name_sub.text = "%s of the world" % _pct(pct)
	var cap := troop_cap(PLAYER)
	var cap_pct := int(round(100.0 * pl.troops / maxf(1.0, cap)))
	# smoothed rates: ~1 s EMA, text refreshed at 4 Hz
	var now_s := Time.get_ticks_msec() / 1000.0
	var hdt := clampf(now_s - _hud_rate_t, 0.0, 1.0); _hud_rate_t = now_s
	var ka := 1.0 - exp(-hdt / 1.0)
	_ema_regen = lerpf(_ema_regen, float(pl.regen), ka) if _ema_init else float(pl.regen)
	_ema_gold = lerpf(_ema_gold, gold_rate(PLAYER), ka) if _ema_init else gold_rate(PLAYER)
	_ema_init = true
	if now_s - _hud_txt_t >= 0.25:
		_hud_txt_t = now_s
		bb_regen.text = "%s%s/s (%d%%)" % ["+" if _ema_regen >= 0 else "", _fmt(_ema_regen), clampi(cap_pct, 0, 999)]
		bb_goldrate.text = "+%s/s" % _fmt(_ema_gold)
	bb_cap.position.x = bb_troops.position.x + f_bold.get_string_size(bb_troops.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 6
	bb_cap.text = "/ %s" % _fmt(cap)
	bb_bar.set_meta("v", clampf(pl.troops / maxf(cap, 1.0), 0.0, 1.0)); bb_bar.queue_redraw()  # clamp: over-cap troops drew a bar across the whole screen
	var at_war := 0.0
	for at in attacks: if at.a == PLAYER: at_war += at.troops
	for bt in boats: if bt.a == PLAYER: at_war += bt.troops
	bb_war.text = ("%s at war" % _fmt(at_war)) if at_war > 0 else ""
	bb_share.text = "%d%%" % int(SHARES[share_i] * 100)
	bb_sends.text = "Sends %s troops" % _fmt(pl.troops * SHARES[share_i])
	var silo_ready := false
	var min_silo_cd := 999.0
	for st in structs:
		if st.o == PLAYER and st.k == 5 and st.get("bt", 0.0) <= 0.0:
			if _ready_slots(st) > 0: silo_ready = true; break
			min_silo_cd = minf(min_silo_cd, float(st.get("cd", 0.0)))
	for k in build_btns.size():
		var cost := build_cost(PLAYER, k)
		if k == 16:
			slot_price[k].text = "ON" if icbm_mode else "+10%"
			slot_price[k].add_theme_color_override("font_color", ORANGE_Y if icbm_mode else GOLD_C)
			build_btns[k].add_theme_stylebox_override("normal", _flat(Color(0.26, 0.2, 0.1) if icbm_mode else CELL_BG, 8, ORANGE_Y if icbm_mode else Color(1, 1, 1, 0.06), 1))
			continue
		if (k in NUKES or k == 15) and owned(PLAYER, 5) > 0 and not silo_ready and min_silo_cd < 900.0:
			slot_price[k].text = "%ds" % maxi(1, ceili(min_silo_cd))
			slot_price[k].add_theme_color_override("font_color", RED)
		elif k == 15 and rail_cd > 0.0:
			slot_price[k].text = "%ds" % maxi(1, ceili(rail_cd))
			slot_price[k].add_theme_color_override("font_color", RED)
		else:
			slot_price[k].text = _fmt(cost)
			var can: bool = pl.gold >= cost and is_avail(k) and build_req(k, -1) == ""
			slot_price[k].add_theme_color_override("font_color", GOLD_C if can else RED)
		var sel: bool = k == build_sel
		build_btns[k].modulate.a = 1.0 if is_avail(k) else 0.55
		build_btns[k].add_theme_stylebox_override("normal", _flat(Color(0.26, 0.2, 0.1) if sel else CELL_BG, 8, ORANGE_Y if sel else Color(1, 1, 1, 0.06), 2 if sel else 1))

func _pct(v: float) -> String:
	if v < 10: return "%.2f%%" % v
	return "%.1f%%" % v

func _update_tooltip() -> void:
	if autoshot and _r29 >= 4 and _r29 != 5:
		tipc.visible = false; return
	if (state == "play" or state == "pick") and _update_build_tip(): return
	if state != "play" and state != "pick":
		tipc.visible = false; return
	if get_viewport().gui_get_hovered_control() != null:
		tipc.visible = false; return
	var t := _mouse_tile()
	if t < 0 or (owner_map[t] == WATER and build_sel != 6):
		tipc.visible = false; return
	if owner_map[t] == WATER and build_sel == 6:
		var mp_w := get_viewport().get_mouse_position()
		var cost_w := build_cost(PLAYER, 6)
		var req_w := build_req(6, t)
		var d_w := {"title": "Deploy Warship", "badge": "NAVAL", "badge_col": CYAN,
			"rows": [["Cost", _fmt(cost_w) + " gold", GOLD_C], ["Active Warships", str(_count_ws(PLAYER)), TEXT]],
			"desc": "Click water or coast to deploy a Warship here, or press 7 again to launch at your Port.",
			"foot": (req_w if req_w != "" else ("Click to deploy Warship" if nations[PLAYER].gold >= cost_w else "Need %s more gold" % _fmt(cost_w - nations[PLAYER].gold))),
			"foot_col": RED if (req_w != "" or nations[PLAYER].gold < cost_w) else CYAN, "foot_icon": "!" if (req_w != "" or nations[PLAYER].gold < cost_w) else "o"}
		_show_tip(d_w, mp_w, false)
		return
	var o: int = owner_map[t]
	var mp := get_viewport().get_mouse_position()
	var send: float = nations[PLAYER].troops * SHARES[share_i]
	var terrain: String = ["Plains (loss 80, cost 16.5)", "Highland (loss 100, cost 20: 1.25x loss, 1.2x slower)", "Mountains (loss 120, cost 25: 1.5x loss, 1.5x slower)"][clampi(mtn[t], 0, 2)]
	var d := {}
	if state == "play" and build_sel in NUKES:
		var r: int = int(NUKE_R[build_sel]) if build_sel != 12 else int(46 * BLAST_S)
		var hit := {}
		var cx := t % W; var cy := t / W
		for k in 200:
			var pp := Vector2(cx, cy) + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * r
			var xx := int(pp.x); var yy := int(pp.y)
			if xx >= 0 and yy >= 0 and xx < W and yy < H and owner_map[yy * W + xx] > 0: hit[owner_map[yy * W + xx]] = true
		var sam_risk := false
		if build_sel != 9:
			for st in structs:
				if st.k == 4 and st.o != PLAYER and Vector2(st.tile % W, st.tile / W).distance_to(Vector2(cx, cy)) <= 70: sam_risk = true
		var names := []
		for h in hit: names.append(_nname(h))
		d = {"title": "Target: " + build_data[build_sel][1], "badge": "AIM", "badge_col": RED,
			"rows": [["Blast radius", "%d tiles" % r, TEXT], ["Cost", _fmt(nuke_cost(build_sel) if build_sel in NUKES else float(build_data[build_sel][2])) + " gold", GOLD_C], ["Hits", "%d nation(s)" % hit.size(), TEXT]],
			"desc": ("Affects: " + ", ".join(names.slice(0, 4))) if names.size() > 0 else "Only wilderness in range.",
			"foot": ("Enemy SAM covers this spot — likely intercepted" if sam_risk else "Click to launch · right-click to cancel"),
			"foot_col": RED if sam_risk else CYAN, "foot_icon": "!" if sam_risk else "o"}
		_show_tip(d, mp, false)
		return
	if o == ICE:
		d = {"title": "Unclaimed  ·  Ice cap", "foot": "Ice caps can't be claimed", "foot_col": MUTED}
	elif o == NEUTRAL:
		var fo_mult := SimRules.fallout_modifier(float(fallout_count) / maxf(float(land_total), 1.0))
		var sub: String = terrain + (" · slow to take" if mtn[t] == 2 else "") + (("  ·  Fallout (%.1fx cost)" % fo_mult) if fallout[t] == 1 else "")
		d = {"title": "Wilderness", "sub": sub, "foot": ("Click: found your nation here" if state == "pick" else "Click: expand with %s" % _fmt(send)), "foot_col": CYAN, "foot_icon": "o"}
		if state == "pick":
			var nc := _neighbour_count(t)
			d.rows = [["Neighbours nearby", str(nc), TEXT]]
			if nc >= 5:
				d.desc = "Crowded — a tough start with many rivals close by."
				d.foot = "Tough start: expect early fights"; d.foot_col = RED; d.foot_icon = "!"
			elif nc >= 3:
				d.desc = "Some rivals nearby. Expand quickly."
			else:
				d.desc = "Quiet area — room to grow."
	elif o == PLAYER:
		var n = nations[o]
		d = {"title": "You", "badge": "YOU", "badge_col": ORANGE_Y, "sub": "Commander  ·  " + terrain, "rows": [["Troops", _fmt(n.troops), TEXT], ["Land", _pct(100.0 * n.land / land_total), TEXT], ["Gold", _fmt(n.gold), GOLD_C]]}
	else:
		var n = nations[o]
		var foot := "Click: attack with %s" % _fmt(send)
		var fc := CYAN
		var badge := "NATION" if is_prot(o) else "TRIBE"
		var bcol := ORANGE_Y if is_prot(o) else MUTED
		var hint := "Right-click: Diplomacy (Ally, Donate Troops & Gold)"
		if allied(PLAYER, o):
			badge = "ALLY"; bcol = GREEN
			foot = "Allied for %s" % _fmt_time(allies[_akey(PLAYER, o)] - elapsed); fc = GREEN
			hint = "Right-click: Donate Troops/Gold or Break Alliance"
		if is_traitor(o):
			badge = "TRAITOR"; bcol = RED; hint = "Traitor: 0.5x defense & 0.8x speed for 30 s"
		d = {"title": n.name, "badge": badge, "badge_col": bcol, "sub": ("Nation" if is_prot(o) else "Tribe") + "  ·  " + terrain, "rows": [["Troops", _fmt(n.troops), TEXT], ["Land", _pct(100.0 * n.land / land_total), TEXT]], "desc": hint, "foot": foot, "foot_col": fc, "foot_icon": "o"}
	_show_tip(d, mp, false)

func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

# One shared number formatter: K M B T Qd Qt, ~4 significant digits (159.3B, 25.5M, 62.1K, 9.87M).
const _FMT_U := ["", "K", "M", "B", "T", "Qd", "Qt"]
func _fmt(n: float) -> String:
	if is_nan(n): return "0"
	if is_inf(n): return "-∞" if n < 0 else "∞"
	var a := absf(n)
	if a < 1000.0: return ("-" if n < 0 and int(a) > 0 else "") + str(int(a))
	var e := 0
	var v := a
	while v >= 999.95 and e < _FMT_U.size() - 1:
		v /= 1000.0; e += 1
	var t := ("%.2f" % v) if v < 10.0 else ("%.1f" % v)
	return ("-" if n < 0 else "") + t + _FMT_U[e]

# ================= v6: stars, arsenal, air strike, railgun, end screen =================
const ARSENAL := [
	{"id": "mega", "k": 11, "name": "Mega Nuke", "desc": "An atom bomb with double the reach.", "b": ["60-tile blast radius", "2.5M gold per launch"], "cost": 0},
	{"id": "scatter", "k": 12, "name": "Scattershot", "desc": "One warhead splits into a ring of six.", "b": ["5 lighter side blasts", "Overwhelms a single SAM"], "cost": 4000},
	{"id": "reinf", "k": 13, "name": "Reinforcements", "desc": "Buy fresh troops the moment you need them.", "b": ["+1/5 of your troop cap", "30 s cooldown"], "cost": 0},
	{"id": "art", "k": 10, "name": "Artillery", "desc": "A gun post that shells anything close.", "b": ["Fires every 2 s", "45-tile range"], "cost": 2500},
	{"id": "air", "k": 14, "name": "Air Strike", "desc": "Build an airfield that launches bombers.", "b": ["A sortie every 60 s", "+1 warhead per airfield"], "cost": 8000},
	{"id": "rail", "k": 15, "name": "Railgun", "desc": "Hit any spot on the map, instantly.", "b": ["Cannot be intercepted", "Small 5-tile impact"], "cost": 12000},
	{"id": "x2", "k": -1, "name": "2x Stars", "desc": "Every match pays out twice.", "b": ["Double star payout", "Applies to every match"], "cost": 15000},
	{"id": "reload", "k": -1, "name": "Rapid Reload", "desc": "Your structures recharge twice as fast.", "b": ["2x reload speed", "SAM, artillery, airfields"], "cost": 10000}]
const SAVE_PATH := "user://save.json"
const RES_LIST := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const RES_NAMES := ["1280 × 720 (720p)", "1600 × 900 (900p)", "1920 × 1080 (1080p)", "2560 × 1440 (1440p)"]
const FPS_LIST := [60, 120, 144, 180]
const QUAL_NAMES := ["Low", "Medium", "High", "Ultra"]
const MSAA_NAMES := ["Off", "2x MSAA", "4x MSAA", "8x MSAA"]
const SHAKE_MULT := [0.0, 1.0, 1.6]
var save := {
	"stars": 0,
	"unlocked": ["mega", "reinf"],
	"settings": {"res_i": 3, "win_i": 0, "fps_i": 3, "qual_i": 3, "msaa_i": 2, "vsync": false, "shake_i": 1, "vol_master": 0.8, "vol_music": 0.5, "vol_sfx": 0.8}
}
var settings_dlg: Control
var settings_btns := {}
var save_path := SAVE_PATH
var stats := {"peak": 0.0, "maxtroops": 0.0, "elims": 0}
var planes := []   # {o,from,to,t,dur,warheads,dropped}
var air_t := 0.0
var rail_cd := 0.0
var beams := []    # {a,b,t}
var stars_lbl: Label
var arsenal_dlg: Control
var arsenal_cards := []
var arsenal_bal: Label
var arsenal_sub_earn: Label
var arsenal_next_bar: Control
var arsenal_next_lbl: Label
var end_dlg: Control
var end_refs := {}

func load_save() -> void:
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			save.stars = int(d.get("stars", 0))
			save.unlocked = d.get("unlocked", save.unlocked)
			if d.has("settings") and d.settings is Dictionary:
				for k in d.settings:
					save.settings[k] = d.settings[k]

func _is_embedded_window() -> bool:
	if Engine.has_method("is_embedded_in_editor") and bool(Engine.call("is_embedded_in_editor")):
		return true
	for a in OS.get_cmdline_args():
		if a == "--wid" or a.begins_with("--wid="):
			return true
	return false

func _line_aa() -> bool:
	return int(save.get("settings", {}).get("msaa_i", 2)) > 0 and int(save.get("settings", {}).get("qual_i", 3)) >= 1

func apply_settings(recolor_map := true) -> void:
	_qual_c = -1
	var cfg: Dictionary = save.get("settings", {})
	var res_i := clampi(int(cfg.get("res_i", 3)), 0, RES_LIST.size() - 1)
	var win_i := clampi(int(cfg.get("win_i", 0)), 0, 2)
	var fps_i := clampi(int(cfg.get("fps_i", 3)), 0, FPS_LIST.size() - 1)
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var vs: bool = bool(cfg.get("vsync", false))
	Engine.max_fps = FPS_LIST[fps_i]
	if get_viewport():
		if str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) != "gl_compatibility": get_viewport().msaa_2d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][msaa_i] as Viewport.MSAA
	_map_material().set_shader_parameter("quality", qual_i)
	if not autoshot and not bench and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
		# Only resize or switch OS Window Mode when NOT running inside Godot 4.4's embedded editor Game tab!
		if not _is_embedded_window():
			if win_i == 0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				var target_sz: Vector2i = RES_LIST[res_i]
				var scr := DisplayServer.window_get_current_screen()
				var srect := DisplayServer.screen_get_usable_rect(scr)
				if srect.size.x > 0 and srect.size.y > 0:
					var fit_w := mini(target_sz.x, srect.size.x)
					var fit_h := mini(target_sz.y, srect.size.y)
					DisplayServer.window_set_size(Vector2i(fit_w, fit_h))
					DisplayServer.window_set_position(srect.position + (srect.size - Vector2i(fit_w, fit_h)) / 2)
				else:
					DisplayServer.window_set_size(target_sz)
			elif win_i == 1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if menu_settings_sub:
		menu_settings_sub.text = "%dp · %d FPS · %s" % [RES_LIST[res_i].y, FPS_LIST[fps_i], QUAL_NAMES[qual_i]]
	if recolor_map and owner_map.size() == W * H:
		_recompute_base_colors()
	if overlay:
		overlay.queue_redraw()

func write_save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(save))

func unlocked(id: String) -> bool:
	return id in save.unlocked

func kind_locked(k: int) -> String:
	for it in ARSENAL:
		if it.k == k and not unlocked(it.id): return it.name
	return ""

func is_avail(k: int) -> bool:
	if god_mode: return k != 9 or mirv_enabled
	return (k != 9 or mirv_enabled) and kind_locked(k) == ""

func reload_mult() -> float:
	return 0.5 if unlocked("reload") else 1.0

# ---------- air strike ----------
func _tick_air(dt: float) -> void:
	# Each completed Airfield (k == 14) runs its own sortie countdown (first sortie 2.5s after build, then every 18s)
	for st in structs:
		if st.k == 14 and st.get("bt", 0.0) <= 0.0 and float(st.get("cd", 0.0)) <= 0.0:
			var period: float = (18.0 / (1.0 + 0.12 * float(int(st.get("level", 1)) - 1))) * reload_mult()
			if launch_sortie(st):
				st.cd = period; st.cmax = period
			else:
				st.cd = 2.0; st.cmax = 2.0
	for pl in planes.duplicate():
		pl.t += dt
		var f: float = pl.t / maxf(0.01, pl.dur)
		# drop warheads across the second half of the bombing run
		while pl.dropped < pl.warheads and f >= 0.45 + 0.50 * float(pl.dropped) / maxf(1.0, float(pl.warheads)):
			pl.dropped += 1
			var p: Vector2 = pl.from.lerp(pl.to, f) + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 4.5))
			detonate(pl.o, p, 4.0)
		if f >= 1.0: planes.erase(pl)

func launch_sortie(st) -> bool:
	if st.get("bt", 0.0) > 0.0: return false
	var o: int = st.o
	var c := Vector2(st.tile % W + 0.5, st.tile / W + 0.5)
	var lvl := int(st.get("level", 1))
	var wh := 5 + (lvl - 1)
	# 1. Prefer enemies currently at war with 'o', or nearest enemy nation within 750 tiles
	var best_p := Vector2(-1, -1)
	var best_ow := -1
	var best_sc := 1e18
	for at in attacks:
		var cand_o := -1
		if at.a == o and at.t > 0: cand_o = at.t
		elif at.t == o and at.a > 0: cand_o = at.a
		if cand_o > 0 and nations[cand_o].alive and not allied(o, cand_o):
			var nn = nations[cand_o]
			var cp := Vector2(nn.sx / maxf(1, nn.land), nn.sy / maxf(1, nn.land))
			var d := c.distance_to(cp)
			if d <= 750.0 and d * 0.5 < best_sc:
				best_sc = d * 0.5; best_p = cp; best_ow = cand_o
	if best_ow < 0:
		for id in range(1, nations.size()):
			if id == o or not nations[id].alive or nations[id].land <= 0 or allied(o, id): continue
			if o != PLAYER and id == PLAYER and elapsed < peace: continue
			var nn = nations[id]
			var cp := Vector2(nn.sx / maxf(1, nn.land), nn.sy / maxf(1, nn.land))
			var d := c.distance_to(cp)
			if d <= 750.0 and d < best_sc:
				best_sc = d; best_p = cp; best_ow = id
	if best_ow < 0:
		return false
	# Pick a land tile inside or near the target nation
	var target_pt := best_p
	var bbt: Rect2i = nations[best_ow].bb
	for _t in 30:
		var tx := bbt.position.x + rng.randi() % maxi(1, bbt.size.x)
		var ty := bbt.position.y + rng.randi() % maxi(1, bbt.size.y)
		if tx >= 0 and ty >= 0 and tx < W and ty < H and owner_map[ty * W + tx] == best_ow:
			target_pt = Vector2(tx + 0.5, ty + 0.5); break
	planes.append({
		"o": o, "from": c, "to": target_pt, "t": 0.0,
		"dur": maxf(2.5, c.distance_to(target_pt) / 34.0),
		"warheads": wh, "dropped": 0
	})
	if o == PLAYER: notify("Airfield (Lv%d) launched %d-warhead Air Strike at %s" % [lvl, wh, _nname(best_ow)], "info")
	elif best_ow == PLAYER: notify("Enemy bombers from %s are inbound!" % _nname(o), "bad")
	return true

# ---------- railgun (requires a ready Missile Silo) ----------
func fire_railgun(o: int, tile: int) -> bool:
	if (not (o == PLAYER and (god_mode or no_cd))) and rail_cd > 0.0: return false
	if nations[o].gold < build_data[15][2]: return false
	var to := Vector2(tile % W + 0.5, tile / W + 0.5)
	var silo := nearest_silo(o, to)
	if silo.is_empty():
		if o == PLAYER: notify("Railgun requires a ready Missile Silo!", "bad")
		return false
	nations[o].gold -= build_data[15][2]
	_use_slot(silo, 0.0 if (o == PLAYER and (god_mode or no_cd)) else 10.0 * reload_mult())
	rail_cd = 0.0 if (o == PLAYER and (god_mode or no_cd)) else 14.0 * reload_mult()
	var from := Vector2(silo.tile % W + 0.5, silo.tile / W + 0.5)
	beams.append({"a": from, "b": to, "t": 0.0})
	var victim: int = owner_map[tile]
	detonate(o, to, 5.0)
	if o == PLAYER: notify("Railgun fired from Silo and struck %s" % _nname(victim), "info")
	return true

func _draw_meta_fx(z: float) -> void:
	for pl in planes:
		var f: float = clampf(pl.t / maxf(0.01, pl.dur), 0.0, 1.0)
		var p := _screen_of(pl.from.lerp(pl.to, f) * TS)
		var d: Vector2 = (pl.to - pl.from).normalized()
		if d == Vector2.ZERO: d = Vector2.RIGHT
		var nrm := Vector2(-d.y, d.x)
		var col: Color = nations[pl.o].color
		# Flight path & twin jet contrails
		overlay.draw_line(_screen_of(pl.from * TS), p, Color(col.r, col.g, col.b, 0.65), 2.4)
		overlay.draw_line(p - d * 22 + nrm * 3.5, p - d * 5 + nrm * 3.5, Color(1, 1, 1, 0.65), 1.8)
		overlay.draw_line(p - d * 22 - nrm * 3.5, p - d * 5 - nrm * 3.5, Color(1, 1, 1, 0.65), 1.8)
		# Strategic swept-wing bomber silhouette (scaled up for high visibility)
		var sc := 1.45
		var body := PackedVector2Array([
			p + d * 11 * sc,
			p + nrm * 2.5 * sc - d * 1 * sc,
			p + nrm * 11 * sc - d * 5 * sc,
			p + nrm * 2.5 * sc - d * 4.5 * sc,
			p + nrm * 4.5 * sc - d * 10 * sc,
			p - d * 8 * sc,
			p - nrm * 4.5 * sc - d * 10 * sc,
			p - nrm * 2.5 * sc - d * 4.5 * sc,
			p - nrm * 11 * sc - d * 5 * sc,
			p - nrm * 2.5 * sc - d * 1 * sc
		])
		overlay.draw_colored_polygon(body, col.lightened(0.25))
		overlay.draw_polyline(body + PackedVector2Array([body[0]]), Color(0.06, 0.08, 0.14, 0.95), 1.8)
		overlay.draw_arc(_screen_of(pl.to * TS), 8 * TS * z, 0, TAU, 32, Color(1, 0.55, 0.2, 0.65), 1.8)
	for bm in beams:
		var a: float = clampf(1.0 - bm.t / 0.6, 0.0, 1.0)
		overlay.draw_line(_screen_of(bm.a * TS), _screen_of(bm.b * TS), Color(0.6, 0.9, 1.0, a), 4.0 * a + 1.0)
		overlay.draw_line(_screen_of(bm.a * TS), _screen_of(bm.b * TS), Color(1, 1, 1, a), 1.5)

func _tick_meta(dt: float) -> void:
	_tick_air(dt)
	rail_cd = maxf(0.0, rail_cd - dt)
	for bm in beams.duplicate():
		bm.t += dt
		if bm.t > 0.6: beams.erase(bm)

	var pl = nations[PLAYER]
	stats.peak = maxf(stats.peak, 100.0 * pl.land / maxf(1, land_total))
	stats.maxtroops = maxf(stats.maxtroops, pl.troops)

func match_stars(win: bool) -> int:
	var s2: int = int(stats.peak * 20.0) + stats.elims * 150 + (1500 if win else 0) + int(elapsed / 6.0)
	if unlocked("x2"): s2 *= 2
	return s2

func next_locked() -> Dictionary:
	var best := {}
	for it in ARSENAL:
		if not unlocked(it.id) and (best.is_empty() or it.cost < best.cost): best = it
	return best

# ---------- star pill / small drawings ----------
func _star(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for m in 10:
		pts.append(p + Vector2.from_angle(-PI / 2 + m * PI / 5) * (r if m % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, col)

func _fmt_int(n: int) -> String:
	var s2 := str(absi(n))
	var out := ""
	while s2.length() > 3:
		out = "," + s2.substr(s2.length() - 3) + out
		s2 = s2.substr(0, s2.length() - 3)
	return ("-" if n < 0 else "") + s2 + out

# ---------- end-of-match screen ----------
func _build_end() -> void:
	end_dlg = Control.new(); end_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); end_dlg.visible = false
	ui.add_child(end_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.02, 0.04, 0.08, 0.62); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_dlg.add_child(sh)
	_head(end_dlg, "MATCH COMPLETE", Vector2(0, 150), 18, Color(0.8, 0.84, 0.95), 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var title := _T(end_dlg, "", Vector2(0, 178), 130, Color(1, 0.93, 0.7), f_head, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	title.size.y = 170
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.04))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55)); title.add_theme_constant_override("shadow_offset_y", 8)
	end_refs.title = title
	end_refs.sub = _T(end_dlg, "", Vector2(0, 380), 21, TEXT, f_bold, 1600, HORIZONTAL_ALIGNMENT_CENTER)
	var labels := ["PEAK LAND", "MAX TROOPS", "NATIONS ELIMINATED", "MATCH DURATION"]
	var icol := [ORANGE_Y, CYAN, RED, Color(0.7, 0.6, 1.0)]
	end_refs.vals = []
	for k in 4:
		var c := _P(end_dlg, Rect2(300 + k * 255, 450, 240, 140), Color(0.07, 0.085, 0.15, 0.95), 5)
		var col: Color = icol[k]
		var kk: int = k
		_draw_ctl(c, Rect2(105, 14, 30, 30), func(cc: Control): _end_icon(cc, kk, col))
		end_refs.vals.append(_T(c, "", Vector2(0, 52), 36, TEXT, f_bold, 240, HORIZONTAL_ALIGNMENT_CENTER))
		_head(c, labels[k], Vector2(0, 104), 12, MUTED, 240, HORIZONTAL_ALIGNMENT_CENTER)
	var pill := _P(end_dlg, Rect2(355, 622, 210, 64), Color(0.35, 0.27, 0.08, 0.5), 5, Color(1, 0.8, 0.3, 0.6), 1, false)
	_draw_ctl(pill, Rect2(18, 18, 28, 28), func(cc: Control): _star(cc, Vector2(14, 14), 12, GOLD_C))
	end_refs.stars = _T(pill, "", Vector2(56, 16), 24, GOLD_C, f_bold, 140, HORIZONTAL_ALIGNMENT_CENTER)
	var again := _big_btn(end_dlg, Rect2(585, 622, 300, 64), "PLAY AGAIN", ORANGE_Y, 22)
	_draw_ctl(again, Rect2(36, 20, 24, 24), func(cc: Control):
		cc.draw_colored_polygon(PackedVector2Array([Vector2(3, 1), Vector2(21, 12), Vector2(3, 23)]), Color(0.12, 0.09, 0.05)))
	again.pressed.connect(func(): end_dlg.visible = false; _start_game_ui())
	var back := _card_btn(end_dlg, Rect2(905, 622, 330, 64)); back.text = "Return to title"
	back.add_theme_font_override("font", f_bold); back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func(): end_dlg.visible = false; _to_menu())
	var prog := _P(end_dlg, Rect2(585, 706, 420, 46), Color(0.25, 0.2, 0.08, 0.45), 5, Color(1, 0.8, 0.3, 0.5), 1, false)
	_draw_ctl(prog, Rect2(16, 13, 16, 20), func(cc: Control):
		cc.draw_rect(Rect2(1, 8, 14, 11), GOLD_C); cc.draw_arc(Vector2(8, 8), 5, PI, TAU, 10, GOLD_C, 2.5))
	end_refs.prog = _T(prog, "", Vector2(44, 11), 17, GOLD_C, f_head, 370)
	end_refs.prog_p = prog

func show_end(win: bool) -> void:
	var earned := match_stars(win)
	save.stars += earned
	write_save()
	var clean := 0
	var mine := 0
	for i in W * H:
		if owner_map[i] >= 0 and owner_map[i] != ICE and fallout[i] == 0:
			clean += 1
			if owner_map[i] == PLAYER: mine += 1
	var pct := 100.0 * mine / maxf(1, clean)
	end_refs.title.text = "VICTORY" if win else "DEFEAT"
	end_refs.title.add_theme_color_override("font_color", Color(1, 0.93, 0.7) if win else Color(1, 0.55, 0.5))
	end_refs.sub.text = ("You conquered the world with %.1f%% of the land outside fallout." % pct) if win else ("Your nation fell after holding up to %.1f%% of the world." % stats.peak)
	end_refs.vals[0].text = "%.1f%%" % stats.peak
	end_refs.vals[1].text = _fmt(stats.maxtroops)
	end_refs.vals[2].text = str(stats.elims)
	end_refs.vals[3].text = _fmt_time(elapsed)
	end_refs.stars.text = "+" + _fmt_int(earned)
	var nl := next_locked()
	end_refs.prog_p.visible = not nl.is_empty()
	if not nl.is_empty():
		end_refs.prog.text = "%s   %s / %s" % [nl.name.to_upper(), _fmt_int(mini(save.stars, nl.cost)), _fmt_int(nl.cost)]
	if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
	for n in hud_nodes: n.visible = false
	notes.clear(); note_box.queue_redraw(); ally_card.visible = false
	_pop_in(end_dlg, 0.25)

# ---------- unified shop & arsenal (stars menu) ----------
func _open_shop() -> void:
	_refresh_arsenal()
	_pop_in(arsenal_dlg)

func unlock_arsenal_item(id: String) -> bool:
	for it in ARSENAL:
		if it.id == id and not unlocked(id) and save.stars >= it.cost:
			save.stars -= it.cost
			save.unlocked.append(id)
			write_save()
			notify("%s unlocked in Shop!" % it.name, "good")
			_refresh_arsenal()
			return true
	return false

func _build_arsenal() -> void:
	arsenal_dlg = Control.new(); arsenal_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); arsenal_dlg.visible = false
	ui.add_child(arsenal_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.65); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	arsenal_dlg.add_child(sh)
	var p := _P(arsenal_dlg, Rect2(150, 32, 1300, 836), Color(0.07, 0.085, 0.15, 0.98), 5)
	_draw_ctl(p, Rect2(28, 22, 34, 38), func(cc: Control):
		cc.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(34, 0), Vector2(34, 20), Vector2(17, 38), Vector2(0, 20)]), ORANGE_Y)
		_star(cc, Vector2(17, 16), 9, Color(0.15, 0.1, 0.03)))
	_head(p, "SHOP & ARSENAL", Vector2(76, 16), 28, TEXT)
	_T(p, "Earn Stars in matches and spend them here to unlock weapons & perks for your build bar.", Vector2(76, 52), 14, MUTED)
	# Integrated Stars earning breakdown + Next Unlock progress bar right in the Shop header
	var star_info := _P(p, Rect2(28, 78, 996, 36), Color(0.11, 0.135, 0.22, 0.95), 4, Color(1, 0.82, 0.36, 0.28), 1, false)
	_draw_ctl(star_info, Rect2(10, 8, 20, 20), func(cc: Control): _star(cc, Vector2(10, 10), 8, GOLD_C))
	arsenal_sub_earn = _T(star_info, "", Vector2(36, 9), 12, Color(0.9, 0.92, 0.98), f_bold, 656)
	arsenal_next_bar = _draw_ctl(star_info, Rect2(700, 8, 284, 20), func(cc: Control):
		var nl := next_locked()
		cc.draw_style_box(_flat(Color(0.06, 0.08, 0.14), 4), Rect2(0, 0, 284, 20))
		if nl.is_empty():
			cc.draw_style_box(_flat(Color(0.25, 0.55, 0.35), 4), Rect2(0, 0, 284, 20))
		else:
			var prog := clampf(float(save.stars) / maxf(1.0, float(nl.cost)), 0.0, 1.0)
			cc.draw_style_box(_flat(Color(0.55, 0.44, 0.16), 4), Rect2(0, 0, maxf(6.0, 284.0 * prog), 20)))
	arsenal_next_lbl = _T(star_info, "", Vector2(708, 9), 12, GOLD_C, f_bold, 268, HORIZONTAL_ALIGNMENT_CENTER)
	var bal := _P(p, Rect2(1038, 22, 182, 50), Color(0.25, 0.2, 0.08, 0.55), 5, Color(1, 0.8, 0.3, 0.6), 1, false)
	_draw_ctl(bal, Rect2(14, 13, 24, 24), func(cc: Control): _star(cc, Vector2(12, 12), 10, GOLD_C))
	arsenal_bal = _T(bal, "", Vector2(44, 6), 20, GOLD_C, f_bold, 128)
	_T(bal, "STAR BALANCE", Vector2(44, 30), 10, MUTED, f_bold, 128)
	var x := _card_btn(p, Rect2(1232, 22, 44, 44)); x.text = "✕"
	x.pressed.connect(func(): _fade_out(arsenal_dlg))
	for k in ARSENAL.size():
		var it = ARSENAL[k]
		var cx := 28 + (k % 4) * 314
		var cy := 124 + (k / 4) * 350
		var c := _P(p, Rect2(cx, cy, 302, 338), CELL_BG, 5, Color(1, 1, 1, 0.08), 1, false)
		var kk: int = k
		_draw_ctl(c, Rect2(1, 1, 300, 146), func(cc: Control): _draw_card_art(cc, kk))
		_head(c, it.name.to_upper(), Vector2(16, 154), 17, TEXT)
		var d := _T(c, it.desc, Vector2(16, 182), 14, Color(0.8, 0.84, 0.94)); d.size = Vector2(270, 40); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for b in 2:
			_T(c, "•  " + it.b[b].to_upper(), Vector2(16, 226 + b * 20), 12, GOLD_C, f_bold)
		var bar := _draw_ctl(c, Rect2(16, 276, 270, 20), func(cc: Control):
			var v := clampf(float(save.stars) / maxf(1, it.cost), 0, 1)
			cc.draw_style_box(_flat(Color(0.2, 0.24, 0.36), 4), Rect2(0, 0, 270, 20))
			cc.draw_style_box(_flat(Color(0.55, 0.45, 0.2), 4), Rect2(0, 0, maxf(6, 270 * v), 20))
			_star(cc, Vector2(96, 10), 7, GOLD_C)
			f_bold.draw_string(cc.get_canvas_item(), Vector2(108, 15), _fmt_int(it.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT))
		var btn := _big_btn(c, Rect2(16, 300, 270, 30), "UNLOCK", Color(0.3, 0.75, 0.45), 14)
		var item_id: String = it.id
		btn.pressed.connect(func(): unlock_arsenal_item(item_id))
		var owned_b := _card_btn(c, Rect2(16, 284, 270, 44)); owned_b.text = "UNLOCKED"; owned_b.disabled = true
		owned_b.add_theme_stylebox_override("disabled", _flat(Color(0.18, 0.15, 0.08), 4, Color(1, 0.75, 0.3, 0.55), 1))
		owned_b.add_theme_font_override("font", f_head); owned_b.add_theme_font_size_override("font_size", 15)
		owned_b.add_theme_color_override("font_disabled_color", GOLD_C)
		arsenal_cards.append({"bar": bar, "btn": btn, "owned": owned_b, "id": it.id, "cost": it.cost})

func _refresh_arsenal() -> void:
	arsenal_bal.text = _fmt_int(save.stars)
	if stars_lbl: stars_lbl.text = _fmt_int(save.stars)
	if arsenal_sub_earn:
		var mult_txt := "2X ACTIVE!" if unlocked("x2") else "1x (2x Stars doubles payout)"
		arsenal_sub_earn.text = "STARS PER MATCH: +20/Land %  ·  +150/Elim  ·  +1,500 Win  ·  +10/min  ·  " + mult_txt
	if arsenal_next_lbl:
		var nl := next_locked()
		if nl.is_empty():
			arsenal_next_lbl.text = "ALL 8 SHOP ITEMS UNLOCKED!"
		else:
			arsenal_next_lbl.text = "NEXT: %s (%s / %s ★)" % [nl.name.to_upper(), _fmt_int(mini(save.stars, nl.cost)), _fmt_int(nl.cost)]
	if arsenal_next_bar:
		arsenal_next_bar.queue_redraw()
	for c in arsenal_cards:
		var u := unlocked(c.id)
		c.bar.visible = not u; c.btn.visible = not u; c.owned.visible = u
		c.btn.disabled = save.stars < c.cost
		c.btn.text = "UNLOCK" if save.stars >= c.cost else "NEED %s MORE" % _fmt_int(c.cost - save.stars)
		c.bar.queue_redraw()
	for b in build_btns: for ch in b.get_children(): if ch is Control: ch.queue_redraw()

func _draw_card_art(cc: Control, k: int) -> void:
	var it = ARSENAL[k]
	var left := Color(0.72, 0.62, 0.95)
	var right := Color(0.55, 0.78, 0.45)
	if it.id == "x2": left = Color(0.35, 0.25, 0.1); right = Color(0.45, 0.32, 0.12)
	cc.draw_rect(Rect2(0, 0, 112, 150), left)
	cc.draw_rect(Rect2(112, 0, 188, 150), right)
	cc.draw_line(Vector2(112, 0), Vector2(112, 150), Color(1, 1, 1, 0.5), 3)
	# left: the tool, drawn with the game's own icon set
	if it.k >= 0:
		_icon(Vector2(56, 70), it.k, Color(0.25, 0.2, 0.45), 1.0, cc, 26.0, true)
	elif it.id == "x2":
		_star(cc, Vector2(56, 72), 34, GOLD_C)
	else:
		for b in 3: cc.draw_rect(Rect2(26, 40 + b * 26, 60, 14), Color(0.25, 0.2, 0.45)); cc.draw_rect(Rect2(26, 40 + b * 26, 60 - b * 18, 14), Color(1, 0.5, 0.7))
	# right: the effect
	var c := Vector2(206, 78)
	match it.id:
		"mega":
			cc.draw_circle(c, 56, Color(0.3, 0.6, 0.25, 0.8)); cc.draw_circle(c, 34, Color(0.95, 0.75, 0.35)); cc.draw_circle(c, 16, Color(1, 0.95, 0.8))
		"scatter":
			cc.draw_circle(c, 18, Color(0.95, 0.7, 0.3))
			for m in 5: cc.draw_circle(c + Vector2.from_angle(m * TAU / 5) * 44, 10, Color(0.95, 0.6, 0.25, 0.85))
		"reinf":
			for m in 6: cc.draw_circle(Vector2(150 + (m % 3) * 32, 50 + (m / 3) * 40), 10, Color(0.25, 0.3, 0.45))
			cc.draw_rect(Rect2(256, 66, 8, 26), Color.WHITE); cc.draw_rect(Rect2(247, 75, 26, 8), Color.WHITE)
		"art":
			cc.draw_arc(Vector2(120, 140), 120, -PI / 2, 0, 24, Color(1, 1, 1, 0.5), 2)
			cc.draw_circle(c + Vector2(10, -6), 16, Color(1, 0.55, 0.2)); cc.draw_circle(c + Vector2(10, -6), 8, Color(1, 0.9, 0.6))
		"air":
			for m in 3: cc.draw_circle(Vector2(170 + m * 30, 100 - m * 18), 12, Color(0.35, 0.3, 0.2, 0.7))
			cc.draw_line(Vector2(130, 30), Vector2(290, 60), Color(1, 1, 1, 0.6), 2)
		"rail":
			cc.draw_line(Vector2(120, 20), c, Color(0.6, 0.9, 1.0), 5); cc.draw_line(Vector2(120, 20), c, Color.WHITE, 2)
			cc.draw_circle(c, 12, Color(0.8, 0.95, 1.0))
		"x2":
			f_head.draw_string(cc.get_canvas_item(), Vector2(150, 96), "2X", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, GOLD_C)
		"reload":
			cc.draw_arc(c, 30, -PI * 0.2, PI * 1.4, 24, Color.WHITE, 5)
			cc.draw_colored_polygon(PackedVector2Array([c + Vector2(30, -18), c + Vector2(42, 2), c + Vector2(20, 0)]), Color.WHITE)
	if not unlocked(it.id):
		cc.draw_rect(Rect2(0, 0, 300, 150), Color(0, 0, 0, 0.35))


func _end_icon(cc: Control, kk: int, col: Color) -> void:
	var o := Vector2(15, 15)
	match kk:
		0:
			cc.draw_arc(o, 11, 0, TAU, 24, col, 2, true); cc.draw_line(o - Vector2(11, 0), o + Vector2(11, 0), col, 1.5)
			cc.draw_arc(o, 5, -PI / 2, PI / 2, 10, col, 1.5); cc.draw_arc(o, 5, PI / 2, PI * 1.5, 10, col, 1.5)
		1:
			cc.draw_arc(o + Vector2(0, 4), 11, PI, TAU, 16, col, 6); cc.draw_line(o + Vector2(-14, 5), o + Vector2(14, 5), col, 2.5)
		2:
			cc.draw_line(o + Vector2(-10, -10), o + Vector2(10, 10), col, 3); cc.draw_line(o + Vector2(10, -10), o + Vector2(-10, 10), col, 3)
			cc.draw_circle(o, 4, col)
		3:
			cc.draw_arc(o, 11, 0, TAU, 24, col, 2, true); cc.draw_line(o, o + Vector2(0, -7), col, 2); cc.draw_line(o, o + Vector2(5, 3), col, 2)

# ================= v9: Settings & Graphics Modal + Password-Protected Tab Console =================
func _draw_gear(c: Control, o: Vector2, r: float, col: Color) -> void:
	for m in 8:
		var a := float(m) * TAU / 8.0
		c.draw_line(o + Vector2.from_angle(a) * (r * 0.65), o + Vector2.from_angle(a) * (r * 1.08), col, 2.6)
	c.draw_circle(o, r * 0.78, col)
	c.draw_circle(o, r * 0.36, Color(0.07, 0.09, 0.16))

func _open_settings() -> void:
	_refresh_settings()
	_pop_in(settings_dlg)

func _build_settings() -> void:
	settings_dlg = Control.new(); settings_dlg.set_anchors_preset(Control.PRESET_FULL_RECT); settings_dlg.visible = false
	ui.add_child(settings_dlg)
	var sh := ColorRect.new(); sh.color = Color(0.01, 0.02, 0.05, 0.65); sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_dlg.add_child(sh)
	var p := _P(settings_dlg, Rect2(260, 14, 1080, 872), Color(0.07, 0.085, 0.15, 0.98), 8)
	_draw_ctl(p, Rect2(32, 24, 34, 34), func(cc: Control): _draw_gear(cc, Vector2(17, 17), 13.0, CYAN))
	_head(p, "SETTINGS & GRAPHICS", Vector2(78, 18), 28, TEXT)
	_T(p, "Configure display resolution (up to 1440p), 180 FPS cap, anti-aliasing, and visual quality.", Vector2(78, 54), 14, MUTED)
	var x := _card_btn(p, Rect2(1012, 20, 42, 42)); x.text = "✕"
	x.pressed.connect(func(): _fade_out(settings_dlg))
	# Row 1: Display Resolution (up to 2560 x 1440 / 1440p)
	_head(p, "DISPLAY RESOLUTION  (MAX 1440P)", Vector2(36, 102), 12, GOLD_C)
	settings_btns["res"] = []
	for k in RES_NAMES.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 126, 242, 54))
		_T(b, RES_NAMES[k], Vector2(0, 16), 14, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["res_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["res"].append(b)
	# Row 2: Window Mode
	_head(p, "WINDOW MODE", Vector2(36, 198), 12, CYAN)
	var wmodes := ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
	settings_btns["win"] = []
	for k in wmodes.size():
		var b := _card_btn(p, Rect2(36 + k * 340, 222, 324, 50))
		_T(b, wmodes[k], Vector2(0, 14), 15, TEXT, f_bold, 324, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["win_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["win"].append(b)
	# Row 3: Max Frame Rate Cap (up to 180 FPS)
	_head(p, "MAX FRAME RATE CAP  (DEFAULT 180 FPS)", Vector2(36, 290), 12, GOLD_C)
	settings_btns["fps"] = []
	for k in FPS_LIST.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 314, 242, 50))
		_T(b, "%d FPS%s" % [FPS_LIST[k], " (MAX)" if k == 3 else ""], Vector2(0, 14), 15, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["fps_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["fps"].append(b)
	# Row 4: Graphics & Trail Animation Quality
	_head(p, "GRAPHICS & MISSILE TRAIL QUALITY", Vector2(36, 382), 12, CYAN)
	var qdescs := ["LOW · flat pixels", "MEDIUM · smooth", "HIGH · relief + waves", "ULTRA · full detail + glow"]
	var sl := HSlider.new()
	sl.min_value = 0; sl.max_value = 3; sl.step = 1; sl.tick_count = 4; sl.ticks_on_borders = true
	sl.position = Vector2(48, 410); sl.size = Vector2(980, 24)
	sl.value = clampi(int(save.get("settings", {}).get("qual_i", 3)), 0, 3)
	p.add_child(sl)
	settings_btns["qual"] = []
	for k in QUAL_NAMES.size():
		settings_btns["qual"].append(_T(p, qdescs[k], Vector2(36 + k * 254, 438), 13, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER))
	settings_btns["qual_slider"] = sl
	sl.value_changed.connect(func(v: float):
		if int(v) == int(save.settings.get("qual_i", 3)): return
		save.settings["qual_i"] = int(v)
		write_save(); apply_settings(); _refresh_settings())
	# Row 5: Anti-Aliasing (2D MSAA)
	_head(p, "ANTI-ALIASING  (2D MSAA & SMOOTH VECTORS)", Vector2(36, 478), 12, GOLD_C)
	settings_btns["msaa"] = []
	for k in MSAA_NAMES.size():
		var b := _card_btn(p, Rect2(36 + k * 254, 502, 242, 50))
		_T(b, MSAA_NAMES[k], Vector2(0, 14), 15, TEXT, f_bold, 242, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["msaa_i"] = kk
			write_save(); apply_settings(); _refresh_settings())
		settings_btns["msaa"].append(b)
	# Row 6: V-Sync & Screen Shake Intensity
	_head(p, "V-SYNC & BLAST SCREEN SHAKE", Vector2(36, 570), 12, CYAN)
	var vs_b := _card_btn(p, Rect2(36, 594, 324, 50))
	settings_btns["vsync_lbl"] = _T(vs_b, "V-Sync: OFF (Uncapped 180 FPS)", Vector2(0, 14), 14, TEXT, f_bold, 324, HORIZONTAL_ALIGNMENT_CENTER)
	vs_b.pressed.connect(func():
		save.settings["vsync"] = not bool(save.settings.get("vsync", false))
		write_save(); apply_settings(); _refresh_settings())
	settings_btns["vsync"] = vs_b
	var sh_names := ["Shake: Off", "Shake: Light (Default)", "Shake: Strong"]
	settings_btns["shake"] = []
	for k in 3:
		var b := _card_btn(p, Rect2(380 + k * 224, 594, 212, 50))
		_T(b, sh_names[k], Vector2(0, 14), 14, TEXT, f_bold, 212, HORIZONTAL_ALIGNMENT_CENTER)
		var kk: int = k
		b.pressed.connect(func():
			save.settings["shake_i"] = kk
			write_save(); _refresh_settings()
			if kk > 0: _add_shake(3.2 if kk == 1 else 5.5))
		settings_btns["shake"].append(b)
	# Row 7: Audio volumes (Master / Music / SFX), saved in save.settings
	_head(p, "AUDIO VOLUME", Vector2(36, 662), 12, GOLD_C)
	var mus_b := _btn("MUSIC: ON" if bool(save.settings.get("music_on", true)) else "MUSIC: OFF", bool(save.settings.get("music_on", true)))
	mus_b.position = Vector2(924, 654); mus_b.size = Vector2(120, 26); mus_b.add_theme_font_size_override("font_size", 12)
	p.add_child(mus_b)
	_pill(mus_b, bool(save.settings.get("music_on", true)), 13)
	mus_b.pressed.connect(func():
		var on := not bool(save.settings.get("music_on", true))
		save.settings["music_on"] = on
		mus_b.text = "MUSIC: ON" if on else "MUSIC: OFF"; _pill(mus_b, on, 13)
		_apply_volumes()
		if on: _play_music()
		else: _stop_music()
		write_save())
	var vkeys := [["vol_master", "Master", 0.8], ["vol_music", "Music", 0.5], ["vol_sfx", "SFX", 0.8]]
	for k in vkeys.size():
		var vk: String = vkeys[k][0]
		var vx := 36 + k * 340
		var vl := _T(p, "", Vector2(vx, 686), 14, TEXT, f_bold, 324)
		var vs_sl := HSlider.new()
		vs_sl.min_value = 0; vs_sl.max_value = 100; vs_sl.step = 1
		vs_sl.position = Vector2(vx, 712); vs_sl.size = Vector2(316, 24)
		vs_sl.value = roundi(float(save.settings.get(vk, vkeys[k][2])) * 100.0)
		p.add_child(vs_sl)
		var vname: String = vkeys[k][1]
		vl.text = "%s: %d%%" % [vname, int(vs_sl.value)]
		settings_btns["vol_" + str(k)] = vs_sl
		vs_sl.value_changed.connect(func(v: float):
			save.settings[vk] = v / 100.0
			vl.text = "%s: %d%%" % [vname, int(v)]
			_apply_volumes())
		vs_sl.drag_ended.connect(func(_c: bool): write_save())
	var status_bar := _P(p, Rect2(36, 754, 1008, 30), Color(0.04, 0.06, 0.11, 0.95), 4, Color(0.35, 0.80, 1.0, 0.35), 1, false)
	settings_status_lbl = _T(status_bar, "", Vector2(12, 5), 13, CYAN, f_bold, 984)
	var done_b := _big_btn(p, Rect2(764, 798, 280, 52), "APPLY & CLOSE", ORANGE_Y, 18)
	done_b.pressed.connect(func(): write_save(); apply_settings(); _fade_out(settings_dlg))

func _refresh_settings() -> void:
	if settings_dlg == null or settings_btns.is_empty(): return
	var cfg: Dictionary = save.get("settings", {})
	var res_i := clampi(int(cfg.get("res_i", 3)), 0, 3)
	var win_i := clampi(int(cfg.get("win_i", 0)), 0, 2)
	var fps_i := clampi(int(cfg.get("fps_i", 3)), 0, 3)
	var qual_i := clampi(int(cfg.get("qual_i", 3)), 0, 3)
	var msaa_i := clampi(int(cfg.get("msaa_i", 2)), 0, 3)
	var shake_i := clampi(int(cfg.get("shake_i", 1)), 0, 2)
	var vs := bool(cfg.get("vsync", false))
	for k in 4:
		_card_style(settings_btns["res"][k], k == res_i)
		_card_style(settings_btns["fps"][k], k == fps_i)
		(settings_btns["qual"][k] as Label).modulate = Color(0.45, 1.0, 1.0) if k == qual_i else Color(0.6, 0.6, 0.6)
		_card_style(settings_btns["msaa"][k], k == msaa_i)
	for k in 3:
		_card_style(settings_btns["win"][k], k == win_i)
		_card_style(settings_btns["shake"][k], k == shake_i)
	_card_style(settings_btns["vsync"], vs)
	if settings_btns.has("qual_slider"): (settings_btns["qual_slider"] as HSlider).set_value_no_signal(qual_i)
	settings_btns["vsync_lbl"].text = "V-Sync: ON" if vs else "V-Sync: OFF (180 FPS Ready)"
	if settings_status_lbl:
		var fps_now := int(Engine.get_frames_per_second())
		if fps_now <= 0: fps_now = FPS_LIST[fps_i]
		var emb_note := "  ·  [Embedded Editor Pane: internal scaling active]" if _is_embedded_window() else ""
		settings_status_lbl.text = "ACTIVE: %s  ·  Cap: %d FPS (Live: %d FPS)  ·  Quality: %s  ·  AA: %s%s" % [RES_NAMES[res_i], FPS_LIST[fps_i], fps_now, QUAL_NAMES[qual_i], MSAA_NAMES[msaa_i], emb_note]

var console_panel: Panel
var console_body: Control
var console_lock_box: Control
var console_pass_in: LineEdit
var console_lock_msg: Label
var console_fps_lbl: Label
var console_unlocked := false
const CONSOLE_PASS := "5516"
var console_log: RichTextLabel
var console_in: LineEdit
var console_hist := []
var console_hist_i := -1

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_TAB:
			toggle_console()
			get_viewport().set_input_as_handled()
		elif console_panel != null and console_panel.visible:
			if e.keycode == KEY_ESCAPE:
				toggle_console()
				get_viewport().set_input_as_handled()
			elif console_unlocked and e.keycode == KEY_UP and not console_hist.is_empty():
				console_hist_i = maxi(0, console_hist_i - 1)
				console_in.text = console_hist[console_hist_i]
				console_in.caret_column = console_in.text.length()
				get_viewport().set_input_as_handled()
			elif console_unlocked and e.keycode == KEY_DOWN and not console_hist.is_empty():
				console_hist_i = mini(console_hist.size(), console_hist_i + 1)
				console_in.text = console_hist[console_hist_i] if console_hist_i < console_hist.size() else ""
				console_in.caret_column = console_in.text.length()
				get_viewport().set_input_as_handled()

func _build_console() -> void:
	console_panel = _P(ui, Rect2(220, 70, 1160, 540), Color(0.04, 0.055, 0.11, 0.96), 8, ORANGE_Y, 2)
	console_panel.visible = false
	_head(console_panel, "TAB MENU  ·  PERFORMANCE & DEVELOPER CONSOLE", Vector2(20, 14), 16, ORANGE_Y)
	_T(console_panel, "Live FPS telemetry & password-protected developer command console.", Vector2(20, 38), 13, MUTED)
	# Prominent Live FPS Counter badge in the Tab Menu header
	var fps_pill := _P(console_panel, Rect2(760, 10, 330, 40), Color(0.08, 0.14, 0.12, 0.95), 6, GREEN, 1, false)
	console_fps_lbl = _T(fps_pill, "FPS: 180 / 180   ·   5.5 ms", Vector2(0, 9), 15, GREEN, f_bold, 330, HORIZONTAL_ALIGNMENT_CENTER)
	var x := _card_btn(console_panel, Rect2(1104, 12, 40, 36)); x.text = "✕"
	x.pressed.connect(func(): toggle_console())
	# 1. Password Lock Gate ("5516")
	console_lock_box = Control.new()
	console_lock_box.position = Vector2(0, 60); console_lock_box.size = Vector2(1160, 480)
	console_lock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_panel.add_child(console_lock_box)
	var lock_card := _P(console_lock_box, Rect2(310, 76, 540, 310), Color(0.07, 0.09, 0.17, 0.98), 8, Color(1, 0.72, 0.25, 0.45), 1, false)
	_draw_ctl(lock_card, Rect2(246, 24, 48, 52), func(cc: Control):
		cc.draw_rect(Rect2(8, 22, 32, 26), GOLD_C)
		cc.draw_arc(Vector2(24, 22), 11, PI, TAU, 16, GOLD_C, 4.0)
		cc.draw_circle(Vector2(24, 35), 4.0, Color(0.07, 0.09, 0.17)))
	_head(lock_card, "CONSOLE LOCKED", Vector2(0, 88), 22, TEXT, 540, HORIZONTAL_ALIGNMENT_CENTER)
	_T(lock_card, "Enter the 4-digit access password to unlock live game editing:", Vector2(0, 120), 14, MUTED, f_reg, 540, HORIZONTAL_ALIGNMENT_CENTER)
	console_pass_in = LineEdit.new()
	console_pass_in.position = Vector2(90, 162); console_pass_in.size = Vector2(230, 44)
	console_pass_in.placeholder_text = "Password..."
	console_pass_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	console_pass_in.add_theme_font_override("font", f_bold)
	console_pass_in.add_theme_font_size_override("font_size", 18)
	console_pass_in.add_theme_stylebox_override("normal", _flat(Color(0.04, 0.06, 0.12), 5, Color(1, 0.72, 0.25, 0.6), 1))
	console_pass_in.add_theme_stylebox_override("focus", _flat(Color(0.08, 0.11, 0.20), 5, ORANGE_Y, 2))
	console_pass_in.text_submitted.connect(func(txt: String): unlock_console(txt))
	lock_card.add_child(console_pass_in)
	var ul_btn := _big_btn(lock_card, Rect2(332, 162, 118, 44), "UNLOCK", ORANGE_Y, 15)
	ul_btn.pressed.connect(func(): unlock_console(console_pass_in.text))
	console_lock_msg = _T(lock_card, "Protected access · Enter password to continue", Vector2(0, 224), 13, MUTED, f_bold, 540, HORIZONTAL_ALIGNMENT_CENTER)
	# 2. Unlocked Console Body
	console_body = Control.new()
	console_body.position = Vector2(0, 0); console_body.size = Vector2(1160, 540)
	console_body.visible = false
	console_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_panel.add_child(console_body)
	x.move_to_front.call_deferred()
	var qbtns := [
		["+10M Gold", "gold +10000000"],
		["+100K Troops", "troops +100000"],
		["+10K Stars", "stars +10000"],
		["Unlock All", "unlock all"],
		["God Mode", "god"],
		["No Cooldowns", "no_cd"],
		["Peace = 0", "peace 0"],
		["Toggle MIRV", "mirv"],
		["Speed 20x", "speed 20"],
		["Inspect Vars", "vars"]
	]
	for k in qbtns.size():
		var qb := _card_btn(console_body, Rect2(20 + k * 112, 64, 108, 28))
		qb.text = qbtns[k][0]
		qb.add_theme_font_override("font", f_bold); qb.add_theme_font_size_override("font_size", 11)
		var cmd_str: String = qbtns[k][1]
		qb.pressed.connect(func(): run_console_cmd(cmd_str))
	var log_bg := _P(console_body, Rect2(20, 100, 1120, 372), Color(0.02, 0.03, 0.06, 0.95), 5, Color(1, 1, 1, 0.08), 1, false)
	console_log = RichTextLabel.new()
	console_log.position = Vector2(12, 8); console_log.size = Vector2(1096, 356)
	console_log.bbcode_enabled = true
	console_log.scroll_following = true
	console_log.add_theme_font_override("normal_font", f_reg)
	console_log.add_theme_font_override("bold_font", f_bold)
	console_log.add_theme_font_size_override("normal_font_size", 14)
	console_log.add_theme_font_size_override("bold_font_size", 14)
	log_bg.add_child(console_log)
	console_in = LineEdit.new()
	console_in.position = Vector2(20, 484); console_in.size = Vector2(990, 40)
	console_in.placeholder_text = "Enter command or assignment (e.g. gold 5000000, boat_speed = 6.0, NUKE_R[7] = 7, unlock all, spawn city 3, help)..."
	console_in.add_theme_font_override("font", f_bold)
	console_in.add_theme_font_size_override("font_size", 15)
	console_in.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.10, 0.18), 5, Color(1, 0.72, 0.25, 0.6), 1))
	console_in.add_theme_stylebox_override("focus", _flat(Color(0.10, 0.13, 0.22), 5, ORANGE_Y, 2))
	console_in.text_submitted.connect(func(txt: String):
		if txt.strip_edges() != "":
			run_console_cmd(txt)
			console_in.clear()
		console_in.grab_focus())
	console_body.add_child(console_in)
	var run_b := _big_btn(console_body, Rect2(1020, 484, 120, 40), "EXECUTE", ORANGE_Y, 14)
	run_b.pressed.connect(func():
		if console_in.text.strip_edges() != "":
			run_console_cmd(console_in.text)
			console_in.clear()
		console_in.grab_focus())
	_clog("[color=#ffbe42][b]Frontline Conquest Developer Console Ready.[/b][/color] Type [b]help[/b] or [b]vars[/b], or edit any property (e.g. [b]gold 5000000[/b], [b]boat_speed = 6.0[/b], [b]NUKE_R[7] = 7[/b]).")

func unlock_console(code: String) -> bool:
	if code.strip_edges() == CONSOLE_PASS:
		console_unlocked = true
		console_lock_box.visible = false
		console_body.visible = true
		_clog("[color=#66e08c][b]Access granted (code 5516). Developer Console unlocked.[/b][/color]")
		if console_panel and console_panel.visible:
			console_in.grab_focus()
		return true
	console_lock_msg.text = "Access denied — invalid password"
	console_lock_msg.add_theme_color_override("font_color", RED)
	console_pass_in.clear()
	return false

func _update_console_fps(dt: float) -> void:
	if settings_dlg != null and settings_dlg.visible:
		_refresh_settings()
	if console_panel == null or not console_panel.visible or console_fps_lbl == null:
		return
	var fps_now := int(Engine.get_frames_per_second())
	if fps_now <= 0: fps_now = int(round(1.0 / maxf(0.001, dt)))
	var cap_now := Engine.max_fps if Engine.max_fps > 0 else 180
	var ms_now := dt * 1000.0
	var res_i := clampi(int(save.get("settings", {}).get("res_i", 3)), 0, RES_LIST.size() - 1)
	var r_v: Vector2i = RES_LIST[res_i]
	console_fps_lbl.text = "FPS: %d / %d  (%.1f ms)  ·  %dp" % [fps_now, cap_now, ms_now, r_v.y]

func toggle_console() -> void:
	if console_panel == null: return
	console_panel.visible = not console_panel.visible
	if console_panel.visible:
		_update_console_fps(0.0055)
		console_lock_box.visible = not console_unlocked
		console_body.visible = console_unlocked
		if console_unlocked:
			console_in.grab_focus()
		else:
			console_pass_in.grab_focus()
	else:
		console_in.release_focus()
		console_pass_in.release_focus()

func _clog(msg: String) -> void:
	if console_log:
		console_log.append_text(msg + "\n")

func _eval_expr(expr_str: String):
	var ex := Expression.new()
	if ex.parse(expr_str) != OK:
		return null
	return ex.execute([], self, false)

func run_console_cmd(raw: String) -> void:
	var cmd := raw.strip_edges()
	if cmd == CONSOLE_PASS:
		unlock_console(cmd)
		return
	if cmd.begins_with("/"): cmd = cmd.substr(1).strip_edges()
	if cmd == "": return
	console_hist.append(cmd)
	console_hist_i = console_hist.size()
	_clog("[color=#59ccff]> %s[/color]" % cmd)
	var low := cmd.to_lower()
	var parts := cmd.split(" ", false)
	var head := parts[0].to_lower() if parts.size() > 0 else ""
	if head in ["help", "?"]:
		_clog("[b]Commands (no leading slash needed):[/b]")
		_clog("  [b]gold <val|+val>[/b] · [b]troops <val|+val>[/b] · [b]stars <val|+val>[/b] · [b]speed <mult>[/b] · [b]peace <sec>[/b]")
		_clog("  [b]unlock all[/b] | [b]lock all[/b] | [b]unlock <id>[/b] · [b]god[/b] · [b]inf_gold[/b] · [b]no_cd[/b] · [b]mirv[/b]")
		_clog("  [b]claim <radius>[/b] · [b]spawn <building_or_id> [level][/b] · [b]nuke <7|8|11|12> [tile][/b]")
		_clog("  [b]nation <id_or_name> <gold|troops|alive|prot> <val>[/b] · [b]win[/b] · [b]lose[/b] · [b]vars[/b] · [b]clear[/b]")
		_clog("  [b]Any assignment or GDScript expression:[/b] e.g. [b]boat_speed = 6.0[/b], [b]NUKE_R[7] = 27[/b], [b]nations[1].gold = 9e8[/b]")
		return
	if head == "clear":
		console_log.clear(); return
	if head == "vars":
		var pg: float = nations[PLAYER].gold if nations.size() > PLAYER else 0.0
		var pt: float = nations[PLAYER].troops if nations.size() > PLAYER else 0.0
		_clog("[b]Live Editable Variables:[/b]")
		_clog("  gold = %s  |  troops = %s / %s  |  save.stars = %d" % [_fmt(pg), _fmt(pt), _fmt(troop_cap(PLAYER) if nations.size() > PLAYER else 0.0), save.stars])
		_clog("  sim_speed = %.2fx (raw %.2f)  |  peace = %.1fs  |  boat_speed = %.2f" % [sim_speed / SPEED_BASE, sim_speed, maxf(0.0, peace - elapsed), boat_speed])
		_clog("  NUKE_R = %s  |  mirv_enabled = %s" % [str(NUKE_R), str(mirv_enabled)])
		_clog("  god_mode = %s  |  inf_gold = %s  |  no_cd = %s  |  traders = %d  |  trains = %d" % [str(god_mode), str(inf_gold), str(no_cd), traders.size(), trains.size()])
		return
	if head == "god":
		god_mode = not god_mode
		if god_mode and nations.size() > PLAYER:
			nations[PLAYER].gold = maxf(nations[PLAYER].gold, 999e6)
			nations[PLAYER].troops = troop_cap(PLAYER)
		_clog("god_mode = [b]%s[/b]" % str(god_mode)); _update_hud(); return
	if head == "inf_gold":
		inf_gold = not inf_gold
		if inf_gold and nations.size() > PLAYER: nations[PLAYER].gold = maxf(nations[PLAYER].gold, 999e6)
		_clog("inf_gold = [b]%s[/b]" % str(inf_gold)); _update_hud(); return
	if head == "no_cd":
		no_cd = not no_cd
		_clog("no_cd = [b]%s[/b]" % str(no_cd)); _update_hud(); return
	if head == "mirv":
		mirv_enabled = not mirv_enabled
		_clog("mirv_enabled = [b]%s[/b]" % str(mirv_enabled)); _refresh_arsenal(); _update_hud(); return
	if head == "leaderboard":
		if hud_nodes.size() > 2: hud_nodes[2].visible = not hud_nodes[2].visible
		_clog("Toggled leaderboard visibility."); return
	if head == "win":
		_game_over(true); _clog("Triggered VICTORY."); return
	if head == "lose":
		_game_over(false); _clog("Triggered DEFEAT."); return
	if head in ["gold", "troops", "stars", "speed", "peace"] and parts.size() >= 2 and parts[1] != "=":
		var arg := parts[1]
		var add_mode := arg.begins_with("+")
		var val := float(arg)
		if head == "gold" and nations.size() > PLAYER:
			nations[PLAYER].gold = (nations[PLAYER].gold + val) if add_mode else val
			_clog("Player gold -> [b]%s[/b]" % _fmt(nations[PLAYER].gold))
		elif head == "troops" and nations.size() > PLAYER:
			nations[PLAYER].troops = (nations[PLAYER].troops + val) if add_mode else val
			_clog("Player troops -> [b]%s[/b]" % _fmt(nations[PLAYER].troops))
		elif head == "stars":
			save.stars = (save.stars + int(val)) if add_mode else int(val)
			write_save(); _refresh_arsenal()
			_clog("Stars -> [b]%s[/b]" % _fmt_int(save.stars))
		elif head == "speed":
			sim_speed = maxf(0.05, val * SPEED_BASE)
			_clog("Simulation speed -> [b]%.2fx[/b]" % val)
		elif head == "peace":
			peace = elapsed + val
			_clog("Peace timer -> [b]%.1fs remaining[/b]" % val)
		_update_hud(); return
	if head == "unlock" and parts.size() >= 2:
		var target_u := parts[1].to_lower()
		if target_u == "all":
			for it in ARSENAL:
				if not (it.id in save.unlocked): save.unlocked.append(it.id)
			write_save(); _refresh_arsenal(); _update_hud()
			_clog("Unlocked all 8 Arsenal items: [b]%s[/b]" % str(save.unlocked))
		else:
			if not (target_u in save.unlocked): save.unlocked.append(target_u)
			write_save(); _refresh_arsenal(); _update_hud()
			_clog("Unlocked [b]%s[/b]" % target_u)
		return
	if head == "lock" and parts.size() >= 2 and parts[1].to_lower() == "all":
		save.unlocked = []
		write_save(); _refresh_arsenal(); _update_hud()
		_clog("Locked all Arsenal items."); return
	if head == "claim":
		var rad := int(parts[1]) if parts.size() >= 2 else 15
		var t := _mouse_tile()
		if t < 0 and nations.size() > PLAYER and nations[PLAYER].land > 0:
			t = int(nations[PLAYER].sy / nations[PLAYER].land) * W + int(nations[PLAYER].sx / nations[PLAYER].land)
		if t >= 0:
			_claim_blob(PLAYER, t, clampi(rad, 1, 120))
			_clog("Claimed radius %d around tile %d for Player." % [rad, t])
		return
	if head == "spawn" and parts.size() >= 2:
		var q := parts[1].to_lower()
		var lvl := int(parts[2]) if parts.size() >= 3 else 1
		var k := int(q) if q.is_valid_int() else -1
		if k < 0:
			for m in build_data.size():
				if build_data[m][1].to_lower().begins_with(q): k = m; break
		var t := _mouse_tile()
		if t < 0 and nations.size() > PLAYER and nations[PLAYER].land > 0:
			t = int(nations[PLAYER].sy / nations[PLAYER].land) * W + int(nations[PLAYER].sx / nations[PLAYER].land)
		if k >= 0 and t >= 0:
			if k == 6:
				spawn_warship(PLAYER); _clog("Spawned Warship.")
			else:
				_struct_add(k, t, PLAYER)
				struct_at[t].level = maxi(1, lvl); struct_at[t].bt = 0.0; _sv += 1
				_clog("Spawned %s Lv%d at tile %d." % [build_data[k][1], maxi(1, lvl), t])
			overlay.queue_redraw()
		return
	if head == "nation" and parts.size() >= 4:
		var q := parts[1].to_lower()
		var prop := parts[2].to_lower()
		var val_s := parts[3]
		var nid := int(q) if q.is_valid_int() else -1
		if nid < 0:
			for id in range(1, nations.size()):
				if nations[id].name.to_lower().find(q) >= 0: nid = id; break
		if nid > 0 and nid < nations.size():
			var n = nations[nid]
			if prop in ["gold", "troops"]:
				n[prop] = float(val_s)
			elif prop in ["alive", "prot"]:
				n[prop] = (val_s.to_lower() in ["true", "1", "yes"])
			else:
				n[prop] = _eval_expr(val_s)
			_clog("Updated nation #%d (%s) %s -> [b]%s[/b]" % [nid, n.name, prop, str(n[prop])])
			_update_hud()
		return
	# Universal assignment handler: e.g. boat_speed = 6.0, NUKE_R[7] = 27, nations[1].gold = 9e8, gold = 5000000
	if "=" in cmd and not ("==" in cmd):
		var eq := cmd.find("=")
		var lhs := cmd.substr(0, eq).strip_edges()
		var rhs := cmd.substr(eq + 1).strip_edges()
		var val = _eval_expr(rhs)
		if val == null and rhs.is_valid_float(): val = float(rhs)
		if lhs == "gold" and nations.size() > PLAYER:
			nations[PLAYER].gold = float(val); _clog("gold = [b]%s[/b]" % _fmt(nations[PLAYER].gold)); _update_hud(); return
		if lhs == "troops" and nations.size() > PLAYER:
			nations[PLAYER].troops = float(val); _clog("troops = [b]%s[/b]" % _fmt(nations[PLAYER].troops)); _update_hud(); return
		if lhs == "stars" or lhs == "save.stars":
			save.stars = int(val); write_save(); _refresh_arsenal(); _clog("save.stars = [b]%d[/b]" % save.stars); return
		if "[" in lhs and lhs.ends_with("]"):
			var b0 := lhs.find("[")
			var cname := lhs.substr(0, b0).strip_edges()
			var kexpr := lhs.substr(b0 + 1, lhs.length() - b0 - 2).strip_edges()
			var target_c = get(cname) if cname != "nuke_r" else NUKE_R
			var key_v = _eval_expr(kexpr)
			if target_c != null and key_v != null:
				target_c[key_v] = val
				_clog("%s[%s] = [b]%s[/b]" % [cname, str(key_v), str(val)]); _update_hud(); return
		if "." in lhs:
			var dot := lhs.rfind(".")
			var obj_e := lhs.substr(0, dot).strip_edges()
			var field := lhs.substr(dot + 1).strip_edges()
			var obj = _eval_expr(obj_e)
			if obj != null:
				obj[field] = val
				_clog("%s.%s = [b]%s[/b]" % [obj_e, field, str(val)]); _update_hud(); return
		set(lhs, val)
		_clog("%s = [b]%s[/b]" % [lhs, str(get(lhs))]); _update_hud(); return
	# Fallback: evaluate any GDScript expression or method call on self
	var res = _eval_expr(cmd)
	_clog("=> [b]%s[/b]" % str(res))
	_update_hud()

# ---------------- sound (OpenFront CC BY-SA 4.0 assets, see sounds/LICENSE.txt) ----------------
const SFX_FILES := {
	"click": ["play/click.wav", "play/click-1.wav", "play/click-2.wav", "play/click-3.wav"],
	"order": ["play/order.wav"],
	"slider": ["play/slider.wav"],
	"game_start": ["play/game-start.wav"],
	"spawn": ["play/spawn.wav"],
	"atom_launch": ["play/atom-launch.wav"],
	"hydrogen_launch": ["play/hydrogen-launch.wav"],
	"mirv_launch": ["play/mirv-launch.wav"],
	"atom_hit": ["play/atom-hit.wav"],
	"hydrogen_hit": ["play/hydrogen-hit.wav"],
	"nuke_warning": ["play/nuke-warning.wav"],
	"sam_shoot": ["play/sam-shoot.wav"],
	"sam_hit": ["play/sam-hit.wav"],
	"build_city": ["play/build-city.wav"],
	"build_port": ["play/build-port.wav"],
	"build_factory": ["play/build-factory.wav"],
	"build_defense": ["play/build-defense-post.wav"],
	"build_sam": ["play/sam-built.wav"],
	"build_silo": ["play/silo-built.wav"],
	"build_warship": ["play/build-warship.wav"],
	"build_station": ["play/build-train-station.wav"],
	"warship_shot": ["play/warship-shot.wav"],
	"warship_lost": ["play/warship-lost.wav"],
	"transport": ["play/transport-ship.wav"],
	"conquered": ["play/conquered.wav"],
	"ka_ching": ["play/ka-ching.wav"],
	"ally_suggest": ["play/alliance-suggested.wav"],
	"ally_accept": ["play/alliance-accepted.wav"],
	"ally_decline": ["play/alliance-declined.wav"],
	"ally_broken": ["play/alliance-broken.wav"],
	"victory": ["play/victory.wav"],
	"defeat": ["play/defeat.wav"],
}
# minimum seconds between two plays of the same sound key (spam limiter)
const SFX_GAP := {"click": 0.05, "conquered": 1.2, "ka_ching": 0.8, "atom_hit": 0.25, "hydrogen_hit": 0.4, "sam_shoot": 0.3, "sam_hit": 0.3, "warship_shot": 0.5, "transport": 0.8, "nuke_warning": 3.0, "atom_launch": 0.3, "hydrogen_launch": 0.3, "mirv_launch": 0.5}
const SFX_POOL_SIZE := 16
var sfx_streams := {}      # key -> Array[AudioStream]
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_last := {}         # key -> msec
var music_player: AudioStreamPlayer
var sfx_missing := []

func _load_audio(path: String) -> AudioStream:
	# Absolute path first. res:// reads go through the import remap, which is empty
	# in a freshly unzipped project (the .godot cache is not shipped) and load() then
	# fails. PCM/MP3 bytes from disk do not need that cache.
	var abs_path := ProjectSettings.globalize_path(path)
	var bytes := PackedByteArray()
	if FileAccess.file_exists(abs_path):
		bytes = FileAccess.get_file_as_bytes(abs_path)
	elif FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	var ext := path.get_extension().to_lower()
	if not bytes.is_empty():
		if ext == "wav":
			var wav := _wav_stream(bytes)
			if wav != null and wav.get_length() > 0.01:
				return wav
		elif ext == "mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes.duplicate()
			if mp3.get_length() > 0.01:
				return mp3
		elif ext == "ogg":
			var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
			if ogg != null and ogg.get_length() > 0.01:
				return ogg
	var imported = load(path)
	if imported is AudioStream and (imported as AudioStream).get_length() > 0.01:
		return imported
	return null

func _wav_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var pcm := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := int(bytes.decode_u32(pos + 4))
		var start := pos + 8
		if start + sz > bytes.size():
			break
		if id == "fmt " and sz >= 16:
			var audio_fmt := int(bytes.decode_u16(start))
			channels = int(bytes.decode_u16(start + 2))
			rate = int(bytes.decode_u32(start + 4))
			bits = int(bytes.decode_u16(start + 14))
			if audio_fmt != 1:
				return null
		elif id == "data":
			pcm = bytes.slice(start, start + sz)
			break
		pos = start + sz + (sz & 1)
	if pcm.is_empty() or bits != 16 or channels < 1:
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = channels >= 2
	s.data = pcm
	return s

func _ensure_bus(nm: String) -> int:
	var idx := AudioServer.get_bus_index(nm)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, nm)
		AudioServer.set_bus_send(idx, "Master")
	return idx

func _init_audio() -> void:
	_ensure_bus("Music"); _ensure_bus("SFX")
	for key in SFX_FILES:
		var arr := []
		for fn in SFX_FILES[key]:
			var s := _load_audio("res://sounds/" + fn)
			if s: arr.append(s)
			else: sfx_missing.append(fn)
		if not arr.is_empty(): sfx_streams[key] = arr
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"
		add_child(p); sfx_pool.append(p)
	music_player = AudioStreamPlayer.new(); music_player.bus = "Music"
	add_child(music_player)
	music_player.finished.connect(func(): _play_music())
	if not sfx_missing.is_empty(): push_warning("Missing sounds: %s" % [sfx_missing])
	if autoshot or bench: print("audio: loaded %d/%d sfx keys, missing files: %s" % [sfx_streams.size(), SFX_FILES.size(), sfx_missing])
	_apply_volumes()
	# Menu and match share one clean loop. Contaminated themes are not candidates.
	if bool(save.get("settings", {}).get("music_on", true)): _play_music()

func _vol_db(v: float) -> float:
	return linear_to_db(maxf(0.0001, clampf(v, 0.0, 1.0)))

func _apply_volumes() -> void:
	var cfg: Dictionary = save.get("settings", {})
	var mv := float(cfg.get("vol_master", 0.8)); var mu := float(cfg.get("vol_music", 0.5)); var sx := float(cfg.get("vol_sfx", 0.8))
	AudioServer.set_bus_volume_db(0, _vol_db(mv)); AudioServer.set_bus_mute(0, mv <= 0.001)
	var bi := AudioServer.get_bus_index("Music")
	if bi >= 0: AudioServer.set_bus_volume_db(bi, _vol_db(mu)); AudioServer.set_bus_mute(bi, mu <= 0.001 or not bool(cfg.get("music_on", true)))
	bi = AudioServer.get_bus_index("SFX")
	if bi >= 0: AudioServer.set_bus_volume_db(bi, _vol_db(sx)); AudioServer.set_bus_mute(bi, sx <= 0.001)

# play a sound by key; vol_db lets far/AI events be quieter. Missing sounds are ignored.
var _sfx_log := false
const SFX_ANY_OWNER := ["atom_launch", "hydrogen_launch", "mirv_launch", "atom_hit", "hydrogen_hit"]
# who = owner whose event this is (PLAYER for your own actions / things hitting you). Everything
# except nuke launches & impacts is hard-gated to events involving the player.
func sfx(key: String, vol_db := 0.0, pitch_jitter := 0.04, who := PLAYER) -> void:
	# Player's own actions, anything aimed at / hitting the player (callers pass who=PLAYER),
	# and nuke launches/impacts from anyone. AI boat, conquer, build and SAM stay silent.
	var allowed := who == PLAYER or key in SFX_ANY_OWNER
	if _sfx_log:
		print("SFX %s t=%.1fs key=%s who=%d vol=%.0fdB" % ["PLAY" if allowed else "BLOCK", (sim_atk.tick / 10.0) if sim_atk else 0.0, key, who, vol_db])
	if not allowed: return
	if not sfx_streams.has(key) or sfx_pool.is_empty(): return
	var now := Time.get_ticks_msec()
	var gap := int(float(SFX_GAP.get(key, 0.12)) * 1000.0)
	if now - int(sfx_last.get(key, -100000)) < gap: return
	sfx_last[key] = now
	var p: AudioStreamPlayer = null
	for c in sfx_pool:
		if not c.playing: p = c; break
	if p == null:  # steal the oldest-started voice
		p = sfx_pool[0]; sfx_pool.remove_at(0); sfx_pool.append(p)
	var arr: Array = sfx_streams[key]
	p.stream = arr[rng.randi() % arr.size()]
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# Only this file may play as music. sounds/rejected/ holds the old themes; they are not scanned.
const MUSIC_FILE := "res://sounds/music/frontline_bed.wav"

func _play_music() -> void:
	if music_player == null: return
	if not bool(save.get("settings", {}).get("music_on", true)): return
	if music_player.playing and str(music_player.get_meta("music_file", "")) == MUSIC_FILE: return
	var s := _load_audio(MUSIC_FILE)
	if s == null:
		push_warning("Clean music missing (%s). Rejected themes are not used as a fallback." % MUSIC_FILE)
		return
	if s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frame := 2 * (2 if wav.stereo else 1)
		wav.loop_end = int(wav.data.size() / frame)
	music_player.set_meta("music_file", MUSIC_FILE)
	music_player.stream = s
	music_player.play()

func _stop_music() -> void:
	if music_player: music_player.stop()

const BUILD_SFX := {0: "build_city", 1: "build_port", 2: "build_factory", 3: "build_defense", 4: "build_sam", 5: "build_silo", 6: "build_warship", 10: "build_defense", 14: "build_silo"}

func _cap_peak(cap: AudioEffectCapture) -> float:
	var n := cap.get_frames_available()
	if n < 32:
		return 0.0
	var data := cap.get_buffer(mini(n, 48000 * 4))
	var peak := 0.0
	for i in data.size():
		peak = maxf(peak, absf(data[i].x))
		peak = maxf(peak, absf(data[i].y))
	return peak

func _save_viewport(path: String) -> void:
	var im := get_viewport().get_texture().get_image()
	if im == null:
		print("SHOT missing ", path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	im.save_png(path)
	var r := speed_panel.get_global_rect() if speed_panel else Rect2()
	if r.size.x > 4.0 and r.size.y > 4.0:
		var crop := im.get_region(Rect2i(int(r.position.x), int(r.position.y), int(r.size.x) + 2, int(r.size.y) + 2))
		crop.save_png(path.get_basename() + "_crop.png")
	print("SHOT ", path, " ", im.get_width(), "x", im.get_height())

func _regress() -> void:
	# Mixer capture is the audio server's output buffer (Dummy driver in headless).
	# It is not a speaker or microphone recording.
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 8.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), cap)
	await get_tree().create_timer(1.4).timeout
	var music_peak := _cap_peak(cap)
	var mlen := -1.0
	if music_player and music_player.stream:
		mlen = music_player.stream.get_length()
	print("REGRESS music_peak=%.4f playing=%s len=%.2f file=%s loaded=%d missing=%s" % [music_peak, str(music_player.playing if music_player else false), mlen, str(music_player.get_meta("music_file", "") if music_player else ""), sfx_streams.size(), str(sfx_missing)])
	cap.clear_buffer()
	sfx("click", 0.0, 0.0, PLAYER)
	sfx("order", 0.0, 0.0, PLAYER)
	sfx("transport", 0.0, 0.0, PLAYER)
	sfx("conquered", 0.0, 0.0, 2)
	sfx("build_city", 0.0, 0.0, 2)
	await get_tree().create_timer(0.9).timeout
	var sfx_peak := _cap_peak(cap)
	print("REGRESS sfx_peak=%.4f" % sfx_peak)
	play_dialog.visible = true
	var t0 := Time.get_ticks_usec()
	_set_map_tab(1)
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("REGRESS map_sync_ms=%.2f queue=%d" % [sync_ms, _preview_queue.size()])
	var worst := 0
	var frames := 0
	var t_start := Time.get_ticks_msec()
	while not _preview_queue.is_empty() or not _pv_job.is_empty():
		var f0 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst = maxi(worst, int(Time.get_ticks_usec() - f0))
		frames += 1
		if Time.get_ticks_msec() - t_start > 25000:
			print("REGRESS map_timeout")
			break
	print("REGRESS map_frames=%d worst_frame_ms=%.1f pump_us=%d" % [frames, worst / 1000.0, preview_pump_us])
	menu_panel.visible = false
	play_dialog.visible = false
	if speed_panel:
		speed_panel.visible = true
	var overlap := false
	for sp in [0.5, 1.0, 10.0]:
		set_speed_x(sp)
		await get_tree().process_frame
		await get_tree().process_frame
		var bad := _speed_labels_overlap()
		if bad:
			overlap = true
		print("REGRESS speed=%s overlap=%s title=%s value=%s hint=%s" % [speed_lbl.text, str(bad), speed_title.get_global_rect(), speed_lbl.get_global_rect(), speed_hint.get_global_rect()])
		_save_viewport("/tmp/speedui/speed_%s.png" % speed_lbl.text.replace(".", "p"))
	var nukes_ok := is_equal_approx(float(NUKE_R[7]), 19.6) and is_equal_approx(float(NUKE_R[8]), 70.0) and is_equal_approx(float(NUKE_R[9]), 8.4)
	var fail := music_peak < 0.02 or sfx_peak < 0.05 or sync_ms > 80.0 or worst > 90000 or overlap or not nukes_ok or sfx_streams.size() < 30
	print("REGRESS nukes_ok=%s" % str(nukes_ok))
	print("REGRESS %s" % ("FAIL" if fail else "OK"))
	get_tree().quit(1 if fail else 0)

func _speedshot() -> void:
	menu_panel.visible = false
	play_dialog.visible = false
	for n in hud_nodes:
		n.visible = false
	if speed_panel:
		speed_panel.visible = true
	var tag := "1600x900"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--res="):
			tag = arg.substr(6)
	for sp in [0.5, 1.0, 10.0]:
		set_speed_x(sp)
		await get_tree().process_frame
		await get_tree().process_frame
		_save_viewport("/tmp/speedui/%s_%s.png" % [tag, speed_lbl.text.replace(".", "p")])
		print("SPEEDSHOT %s %s overlap=%s" % [tag, speed_lbl.text, str(_speed_labels_overlap())])
	get_tree().quit(0)

func _audiotest() -> void:
	# Event log only. Whether a file contains boat or conquer audio is measured outside Godot
	# (tools/audio_evidence.py): a PLAY/BLOCK line is not listening evidence.
	_sfx_log = true
	print("AUDIOTEST begin state=%s" % state)
	for _i in 8:
		await get_tree().process_frame
	print("AUDIOTEST menu music_file=%s playing=%s" % [str(music_player.get_meta("music_file", "")), str(music_player.playing)])
	print("AUDIOTEST rejected_menu=%s rejected_war=%s" % [str(FileAccess.file_exists("res://sounds/rejected/roworld_menu.mp3")), str(FileAccess.file_exists("res://sounds/rejected/roworld_war.mp3"))])
	sfx("transport", 0.0, 0.0, 2)
	sfx("conquered", 0.0, 0.0, 2)
	sfx("build_city", 0.0, 0.0, 2)
	sfx("sam_shoot", 0.0, 0.0, 2)
	sfx("atom_launch", 0.0, 0.0, 2)
	sfx("hydrogen_hit", 0.0, 0.0, 2)
	sfx("click", 0.0, 0.0, PLAYER)
	sfx("transport", 0.0, 0.0, PLAYER)
	save.settings["music_on"] = false
	_apply_volumes(); _stop_music()
	print("AUDIOTEST toggle_off playing=%s bus_mute=%s" % [str(music_player.playing), str(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))])
	save.settings["music_on"] = true
	_apply_volumes(); _play_music()
	print("AUDIOTEST toggle_on playing=%s file=%s" % [str(music_player.playing), str(music_player.get_meta("music_file", ""))])
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(int(W / 2), int(H / 3))
	_place_start(st)
	deploy_t = 0.0
	state = "play"
	peace = 0.0
	set_speed_x(10.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	print("AUDIOTEST gameplay_ms=%d tick=%d boats=%d attacks=%d" % [Time.get_ticks_msec() - t0, sim_atk.tick if sim_atk else -1, boats.size(), attacks.size()])
	print("AUDIOTEST map=%dx%d blast_s=%.4f" % [W, H, BLAST_S])
	for k in [7, 8, 9, 11, 12]:
		print("AUDIOTEST nuke k=%d frac=%.4f radius=%.2f" % [k, float(NUKE_RANGE_FRAC[k]), float(NUKE_R[k])])
	var slow := clampf(snappedf(0.4, 0.5), 0.5, 10.0)
	var fast := clampf(snappedf(12.0, 0.5), 0.5, 10.0)
	print("AUDIOTEST speed_lo=%.1f speed_hi=%.1f" % [slow, fast])
	print("AUDIOTEST done")
	get_tree().quit()

func _maptest() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/shots")
	for tab in 2:
		var t0 := Time.get_ticks_usec()
		_set_map_tab(tab)
		print("MAPTEST tab %d switch ms=%.0f" % [tab, (Time.get_ticks_usec() - t0) / 1000.0])
		for k in map_card_tex.size():
			var im: Image = _map_preview(k, 448, 400).get_image()
			im.save_png("/workspace/shots/31_%s_%02d.png" % ["real" if tab == 0 else "random", k])
	for cfg in [[0, 0], [0, 7], [0, 2], [1, 0]]:
		map_tab = cfg[0]; map_i = cfg[1]
		var t1 := Time.get_ticks_usec()
		gen_map()
		var t2 := Time.get_ticks_usec()
		_start_game()
		var t3 := Time.get_ticks_usec()
		print("MAPTEST start tab=%d map=%d gen_ms=%.0f start_game_ms=%.0f land=%d nations=%d" % [cfg[0], cfg[1], (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, land_total, nations.size()])
		_flush_paint()
		var big := Image.create(W, H, false, Image.FORMAT_RGBA8)
		for k in chunk_img.size():
			big.blit_rect(chunk_img[k], Rect2i(0, 0, CW, CH), Vector2i((k % (W / CW)) * CW, (k / (W / CW)) * CH))
		big.resize(896, 800); big.save_png("/workspace/shots/31_match_tab%d_map%02d.png" % [cfg[0], cfg[1]])
	get_tree().quit()

func _rangetest() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 1
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 50 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 1e9
	_claim_blob(PLAYER, st, 70)
	nations[PLAYER].gold = 2e8
	var c0 := st
	var sx := c0 % W; var sy := c0 / W
	var spots := [[0, 0, 2], [20, 8, 0], [-18, 12, 0], [10, -22, 5], [-25, -10, 1], [35, 25, 0], [-5, 30, 3], [28, -5, 4]]
	for sp in spots:
		var t := _find_spawn_tile(sx + sp[0], sy + sp[1])
		if owner_map[t] != PLAYER: t = (sy + sp[1]) * W + sx + sp[0]
		print("build k=", sp[2], " ok=", try_build(sp[2], t))
	for s2 in structs: s2.bt = 0.0
	_sv += 1
	var good := 0; var over_water := 0
	for a in structs:
		for b in _rail_neighbors(a):
			var rc := _rail_curve(a.tile, b.tile)
			var pts: PackedVector2Array = rc[0]
			good += 1
			for m in range(1, pts.size()):
				if not _land_los(pts[m - 1], pts[m]): over_water += 1
			print("rail %d->%d segs=%d" % [a.k, b.k, pts.size() - 1])
	print("RAILS links=%d water_segments=%d" % [good, over_water])
	_focus_player(2.2)
	for k in [7, 8, 12]:
		build_sel = k
		var silo_t := -1
		for s3 in structs: if s3.k == 5: silo_t = s3.tile
		cam.zoom = Vector2(0.55, 0.55) if k != 12 else Vector2(1.4, 1.4)
		cam.position = Vector2(silo_t % W, silo_t / W) * TS
		await get_tree().process_frame
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.72, 0.4))
		for _f in 6: await get_tree().process_frame
		_shot("32_range_k%d.png" % k)
		var far := Vector2(silo_t % W, silo_t / W) + Vector2(nuke_range(k) + 30, 0)
		var ft := clampi(int(far.y) * W + int(far.x), 0, W * H - 1)
		var near := clampi((silo_t / W) * W + silo_t % W + int(nuke_range(k) * 0.5), 0, W * H - 1)
		print("RANGE k=%d range_tiles=%.0f far_ok=%s near_ok=%s" % [k, nuke_range(k), str(not silo_for(PLAYER, k, Vector2(far)).is_empty()), str(not silo_for(PLAYER, k, Vector2(near % W, near / W)).is_empty())])
	set_icbm(true)
	var g0: float = nations[PLAYER].gold
	var tgt := clampi(W * H - W * 200 - 200, 0, W * H - 1)
	for i in range(W * H - 1, 0, -997):
		if owner_map[i] > 0 and owner_map[i] != PLAYER: tgt = i; break
	for s4 in structs: if s4.k == 5: s4.erase("slots")
	print("ICBM launch ok=", launch_nuke(PLAYER, 7, tgt), " gold spent=", g0 - nations[PLAYER].gold)
	set_icbm(false)
	build_sel = 2
	cam.zoom = Vector2(1.6, 1.6); _focus_player(1.6)
	for _f in 6: await get_tree().process_frame
	_shot("32_factory_range_rails.png")
	build_sel = -1
	for _f in 4: await get_tree().process_frame
	_shot("32_rails_hud.png")
	get_tree().quit()

func _rangetest2() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	for mi in [0, 6]:
		map_tab = 0; map_i = mi
		_start_game()
		var stp := _find_spawn_tile(W / 2, H / 2)
		_place_start(stp); deploy_t = 0.0; state = "play"; peace = 1e9
		var lw := land_width()
		# westmost / eastmost land tiles on the middle-ish rows
		var west := -1; var east := -1
		for x in W:
			for y in range(0, H, 3):
				if owner_map[y * W + x] != WATER: west = y * W + x; break
			if west >= 0: break
		for x in range(W - 1, -1, -1):
			for y in range(0, H, 3):
				if owner_map[y * W + x] != WATER: east = y * W + x; break
			if east >= 0: break
		var silo := {"o": PLAYER, "k": 5, "tile": west, "bt": 0.0, "level": 1}
		structs.append(silo); struct_at[west] = silo
		var ep := Vector2(east % W + 0.5, east / W + 0.5)
		for k in [7, 11, 8, 12, 9]:
			icbm_mode = false
			var far_ok := not silo_for(PLAYER, k, ep).is_empty()
			icbm_mode = true
			var icbm_ok := not silo_for(PLAYER, k, ep).is_empty()
			print("RANGE2 map=%s land_w=%.0f k=%d range=%.0f tiles (%s) west->east dist=%.0f reach=%s icbm=%s" % [RealMaps.MAPS[RW_MAP_FOR[mi]].name, lw, k, nuke_range(k), nuke_range_label(k), Vector2(west % W, west / W).distance_to(ep), str(far_ok), str(icbm_ok)])
		icbm_mode = false
		if mi == 0 and DisplayServer.get_name() != "headless":
			build_sel = 7
			cam.zoom = Vector2(0.42, 0.42); cam.position = Vector2(west % W + 400, west / W) * TS
			await get_tree().process_frame
			get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.75, 0.45))
			for _f in 8: await get_tree().process_frame
			_shot("36_range_circle_world.png")
			build_sel = -1
			# blast size: H-bomb + atom near Irkutsk-ish (east Asia interior)
			var tgt := _find_spawn_tile(int(W * 0.78), int(H * 0.27))
			var c := Vector2(tgt % W + 0.5, tgt / W + 0.5)
			cam.zoom = Vector2(0.9, 0.9); cam.position = c * TS
			detonate(PLAYER, c, float(NUKE_R[8]), 1.0); detonate(PLAYER, c + Vector2(110, 40), float(NUKE_R[7]), 1.0)
			for _f in 40: await get_tree().process_frame
			_shot("36_blast_after.png")

		structs.erase(silo); struct_at.erase(west)
	get_tree().quit()

func _bordershot() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 1
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 50 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	set_speed_x(10.0)
	for tgt in [90.0, 480.0]:
		while elapsed < tgt: await get_tree().process_frame
		cam.zoom = Vector2(0.62, 0.62); cam.position = Vector2(W * 0.52, H * 0.42) * TS
		for _f in 4: await get_tree().process_frame
		_shot("37_borders_%dmin.png" % int(tgt / 60.0))
	get_tree().quit()

func _idletest() -> void:
	_sfx_log = true
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 50 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	for id in range(2, nations.size()):
		if is_prot(id): nations[id].gold = 4e7
	set_speed_x(10.0)
	print("IDLE start")
	var t0 := Time.get_ticks_msec()
	while elapsed < 300.0 and Time.get_ticks_msec() - t0 < 600000:
		await get_tree().process_frame
	print("IDLE done game_s=%.0f missiles_total? structs=%d boats=%d" % [elapsed, structs.size(), boats.size()])
	get_tree().quit()

func _stress() -> void:
	shots_dir = "/workspace/shots"
	_sfx_log = true
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 50 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 0.0
	_claim_blob(PLAYER, st, 90)
	nations[PLAYER].troops = 1.59304e11; nations[PLAYER].gold = 3.24e8
	for id in range(2, nations.size()):
		if is_prot(id): nations[id].gold = 4e7
	set_speed(SPEEDS.size() - 1)
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var worst := 0.0; var sec_worst := 0.0; var frames := 0; var sec := 0
	var hits := 0
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0; last = now
		frames += 1; sec_worst = maxf(sec_worst, ms); worst = maxf(worst, ms)
		if ms > 50.0: hits += 1
		if (now / 1000 - t0) / 1000 > sec:
			sec = (now / 1000 - t0) / 1000
			if sec % 10 == 0:
				print("STRESS t=%ds game=%.1fmin fps=%d worst_ms=%.0f troops=%s gold=%s structs=%d fallout=%d trains=%d boats=%d attacks=%d missiles=%d alive=%d" % [sec, elapsed / 60.0, frames / 10, sec_worst, _fmt(nations[PLAYER].troops), _fmt(nations[PLAYER].gold), structs.size(), fallout_list.size(), trains.size(), boats.size(), attacks.size(), missiles.size(), _alive_count()])
				frames = 0; sec_worst = 0.0
			if sec % 30 == 0: _shot("33_stress_%03d.png" % sec)
			if sec % 7 == 0:
				var ids := []
				for id in range(2, nations.size()): if nations[id].alive and nations[id].land > 50: ids.append(id)
				if ids.size() > 0:
					var v: int = ids[rng.randi() % ids.size()]
					var tt := int(nations[v].sy / nations[v].land) * W + int(nations[v].sx / nations[v].land)
					nations[PLAYER].gold += 3e7
					_struct_add(5, _find_spawn_tile(st % W, st / W), PLAYER)
					for s5 in structs: if s5.o == PLAYER: s5.bt = 0.0
					launch_nuke(PLAYER, [7, 8, 11, 12][sec % 4], tt)
					var ok := intent_attack(PLAYER, tt, 0.3)
	print("STRESS DONE worst_ms=%.0f frames_over_50ms=%d" % [worst, hits])
	get_tree().quit()

func _alive_count() -> int:
	var c := 0
	for n in nations: if not n.is_empty() and n.alive: c += 1
	return c

func _hudshot() -> void:
	shots_dir = "/workspace/shots"
	play_dialog.visible = false
	map_tab = 0; map_i = 0
	_start_game()
	var st := _find_spawn_tile(W * 52 / 100, H * 30 / 100)
	_place_start(st); deploy_t = 0.0; state = "play"; peace = 1e9
	_claim_blob(PLAYER, st, 40)
	nations[PLAYER].gold = 3.24e8; nations[PLAYER].troops = 1.59304e11
	_struct_add(5, st, PLAYER)
	for s5 in structs: s5.bt = 0.0
	for nd in hud_nodes: nd.visible = true; nd.modulate.a = 1.0; nd.position.y = nd.position.y
	_focus_player(0.8)
	for _f in 30: await get_tree().process_frame
	_update_hud()
	_shot("34_hud_icbm_off.png")
	set_icbm(true)
	tip_slot = 16
	for _f in 20: await get_tree().process_frame
	_shot("34_hud_icbm_on_tip.png")
	tip_slot = 8
	for _f in 10: await get_tree().process_frame
	_shot("34_hud_hbomb_tip.png")
	tip_slot = -1; build_sel = 8
	get_viewport().warp_mouse(Vector2(300, 300))
	for _f in 10: await get_tree().process_frame
	_shot("34_hbomb_range_icbm.png")
	get_tree().quit()
