extends Node2D
# Frontline Conquest: shared state (constants, variables, inner classes) and forward declarations.
# The game is one class split over a chain of scripts, each adding one feature area:
#   state -> map -> nations -> economy -> nukes -> navy -> rails -> bot_ai -> draw_helpers -> planes_fx -> diplomacy -> ui_anim -> ui_build -> strikes -> end_screen -> shop -> audio -> main (res://main.gd, the leaf attached to main.tscn)
const W := 1792
const H := 1600
const TS := 2.0  # pixels per tile
const RK := preload("res://ui_upstream/rw_kit.gd")
const RW_HUD := preload("res://ui_upstream/rw_hud.gd")
var hud  # ui_upstream/rw_hud.gd: the upstream in-match HUD
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
var boat_uid := 0
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
var pick_panel: Control
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
var boat_speed := 0.35  # multiplier on RoWorld ship speed (1 full-size tile/tick) for transports and trade ships; user: 0.35x
var warship_speed := 0.35  # same multiplier for warships (sim/warships.gd _move)
const AI_BOAT_CAP := 12
const MAX_TICKS_PER_FRAME := 12
const SIM_BUDGET_US := 12000   # sim time per frame (perf cap); was 28 ms with whole ticks only
const PAINT_BUDGET_US := 5000  # territory repaint per frame
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

const HANDCRAFTED_MAPS := ["", "", "", "", "", "", "", "", "", "", "", ""]  # all 12 now come from sim/real_maps.gd

var _cached_map_bytes := {}
# ---- RoWorld port (stage 1): real map data + faithful simulation modules ----
const RealMaps := preload("res://sim/real_maps.gd")
const UpstreamMaps := preload("res://sim/upstream_maps.gd")  # map_tab 2: RoWorld maps (maps/upstream/)
var _up_menu := []
const RW_MAP_FOR := {0: 0, 1: 1, 2: 6, 3: 2, 4: 3, 5: 4, 6: 5, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11}  # MAPS index -> RealMaps.MAPS index
const DEFAULT_K_LIN := 1.1161  # 1792 tiles across = RoWorld's 2000-wide world
var sim_rules := SimRules.new(DEFAULT_K_LIN)
const TILE_NORM := (640.0 * 352.0) / float(W * H)
var sim_atk: SimAttacks
var sim_ai: SimAI
var sim_struct: SimStructures
var sim_naval: SimNaval
const SimNavS := preload("res://sim/nav.gd")
var sim_nav = null  # SimNav (sim/nav.gd): water pathfinding graph for the current map
var sim_ars: SimArsenal
var sim_ws: SimWarships
var fallout_count := 0
var real_nations := []
var snow_src := PackedByteArray()  # current map codes; 4 = snow (Antarctica): plains rules, white colour
const SNOW_COL := Color8(0xF4, 0xF7, 0xFA)

var _kind_cache := PackedInt32Array()
var _gt_t := 0
var _gen_cache := {}
var _async_gen := false
# RoWorld MapSurface.terrain_pixel (src/client/Map/MapSurface.luau): OCEAN #4785b5 darkened by depth,
# shoreline water 0.7*OCEAN+76.5, coastal land SAND #CCCB9E, PLAINS #BEDC8A, HIGHLAND #DCCB9E, MOUNTAIN #e6e6e6.
var _DIRS4 := PackedInt32Array([1, -1, W, -W])
var _qual_c := -1
# Repaints are deferred to the next drawn frame so a tile flipped by several captures in one frame
# (its own capture plus neighbours') is coloured once.
var _pend_paint := {}
# Incremental border sets (owner -> {tile: true}): land tiles with a land 4-neighbour of another owner.
var border := []

var _skip_gen := false
var load_ov: Control
var load_bar: ProgressBar
var _loading := false
# ---------------- RoWorld spawn (Sim._create_nations / _random_start / _spawn_owner) ----------------
var _spawn_tiles := PackedInt32Array()
var _spawn_grid := {}

# ---------------- economy / combat ----------------
# Per-owner structure totals, rebuilt only when the structure list changes (_sv bumps on add,
# remove, capture and upgrade) instead of a full structs sweep on every call.
var _sv := 0
var _oc_ver := -1
var _oc_lvl := {}
var _oc_cnt := {}
var def_posts := {}  # owner -> PackedInt32Array of finished defense post tiles (rebuilt each tick)
var _ai_place_budget := 0  # AI placement searches (flood fills) left this tick
# ================= v5 systems: weapons, ships, notifications =================
# RoWorld radii (7/25/3/15/7 at 640x352) scaled by the map's linear scale so each bomb covers the same share of the map
const BLAST_S := float(W) / 640.0
var NUKE_R := {7: 7.0 * BLAST_S, 8: 25.0 * BLAST_S, 9: 3.0 * BLAST_S, 11: 15.0 * BLAST_S, 12: 7.0 * BLAST_S}
var mirv_enabled := true
var god_mode := false
var inf_gold := false
var no_cd := false
const NUKES := [7, 8, 9, 11, 12]
const LAND_STRUCTS := [0, 1, 2, 3, 4, 5, 10, 14, 15]
const UPGRADABLE := [0, 1, 2, 4, 5]  # Rules.UPGRADABLE (Rules.luau 225): city, port, factory, SAM, silo
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
const NUKE_RANGE_SCALE := 0.375  # user: all bomb ranges x0.375 (ICBM mode still ignores range)
var _land_w := -1.0
# nukes fly 1.5x (short shots) up to 2.5x (>= 1000 tiles) faster
# NUKE_SPEED_MULT removed: nuke speed now matches upstream (see game/nukes.gd nuke_speed_mult)
var mirvs_launched := 0  # Rules.nuke_cost: MIRV +15M per MIRV already launched in the match (Rules.luau 785-789)
const RAIL_KINDS := [0, 1, 2, 3, 4, 5]  # city, port, factory, defense post, SAM, silo: any two can be linked
var _rail_nb_cache := {}
var _own_sv := {}
var _rail_calc_left := 40
var _rail_bfs_left := 4  # land BFS route searches allowed per frame (26k nodes each)
var _rail_pending := false
var rail_cache := {}  # rail geometry, separate from boat path_cache (which is flushed at 400 entries)
var _rail_nb_ver := ""
const FACTORY_RANGE := 60.0  # tiles: roads/rails may only link structures inside one factory's range
# Minimum spanning tree (Manhattan weight) per owner: each structure joins the road network once.
# An edge is allowed only if both ends sit inside the same factory's range.
var _rail_mst := {}  # owner -> [ver, {tile: [structs]}]
var fx_freeze := false
const WARSHIP_RETALIATE_P := [0.0, 0.15, 0.5]  # SimAIEconomy.luau 112, by difficulty
const WARSHIP_FLEET_CAP := 10
# ---- RoWorld art (AGPL-3.0, assets/): loaded at runtime from PNG bytes, no import needed ----
var _tex_cache := {}
const ST_COL := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 6, 14: 7, 15: 8}
const SHAPE_SCALE := [1.0, 1.0, 1.12, 1.1, 1.15, 1.3, 1.2, 1.35, 1.25]
const ICON_FILL := [0.78, 0.74, 0.74, 0.74, 0.8, 0.76, 0.82, 0.8, 0.86]
const UI_TEX := {0: "ui/city.png", 1: "ui/port.png", 2: "ui/factory.png", 3: "ui/defense.png", 4: "ui/sam.png", 5: "ui/silo.png", 6: "ui/warship.png", 7: "ui/atom.png", 8: "ui/hydrogen.png", 9: "ui/mirv.png", 10: "ui/artillery.png", 11: "arsenal/ui/mega.png", 12: "arsenal/ui/scatter.png", 13: "arsenal/ui/reinforce.png", 14: "ui/airfield.png", 15: "ui/railgun.png", 16: "ui/icbm.png"}

# Ships in RoWorld's OLD look (before upstream commit 16ae383, 2026-10-25): the original unit atlas
# (assets/units_old.png = assets/openfront/of_units.png at 16ae383^), whose ship cells are small diamond
# "specks" (transport / trade ship 5 x 5 px, warship 11 x 11 px inside a 13 px cell). Drawn as
# Map/UnitLayer.luau does: never rotated, the cell UNIT_SIZE = 13 full-size tiles wide but at least
# MIN_PX = 5 device px, row 0 in the owner's colour, row 1 in border_of(colour) (HSV value - 0.16),
# snapped to whole device pixels.
const SHIP_UNIT_SIZE_FULL := 13.0
const SHIP_MIN_PX := 5.0

var _tie_vr := Rect2()
var cap_fx := {}
# click one of your warships, then the sea, to move it (upstream: Click one of yours, then the sea)
var sel_ws = null
# ---------- cargo and transport planes (custom): cargo planes work like trade ships, transport planes like boats ----------
const AIR_SPEED := 3.0          # x ship speed
const MAX_PLANE_TRANSPORTS := 3
const AIR_CARGO_EVERY := 20.0   # s between cargo flights per owner
const AIR_CARGO_MAX := 6
var _air_cargo_t := {}

const CAP_FX_MAX := 2000  # perf cap on capture flashes (was 6000; each is a rect per frame)
# RoWorld FxLayer + assets/map_fx/map_fx.png (tools/assets/make_map_fx.py): one atlas, a row per effect.
#   nuke 12 x (60x60) at 70 ms (y 0), sam 9 x (48x38) at 80 ms (y 108), fire 6 x (7x13) 100 ms (y 161),
#   smoke 4 x (11x12) 120 ms (y 174), big_smoke 5 x (24x16) (y 186), smoke_fire 5 x (24x16) (y 202).
# A landed nuke plays the explosion, a thin white shock ring grows to 1.5x its radius over 1.5 s, and
# debris burns within half the radius for 6 s (fade in over the first 10 %, out after 80 %).
const RW_FX := {"nuke": [0, 60, 60, 12, 0.07], "sam": [108, 48, 38, 9, 0.08], "fire": [161, 7, 13, 6, 0.1],
	"smoke": [174, 11, 12, 4, 0.12], "big_smoke": [186, 24, 16, 5, 0.12], "smoke_fire": [202, 24, 16, 5, 0.12]}
# ---------- alliances, embargoes & diplomacy ----------
const ALLY_LEN := 300.0  # seconds at 1x = SimRules.ALLIANCE_TICKS (3000) / 10; expiries are kept in sim ticks
var allies := {}       # _akey(a, b) -> expiry tick (formed / last renewed + ALLIANCE_TICKS)
var ally_ext := {}     # _akey(a, b) -> renewal asks: bit 1 the lower id asked, bit 2 the higher (SimState.ally_ext)
var ally_extensions := []  # [due_tick, from, to] renewal requests an AI ally must answer (SimAI.extensions)
var traitor := {}      # id -> traitor until tick (TRAITOR_TICKS)
var embargoes := {}    # "a:b" -> expiry (elapsed)
var embargo_all := false
var donate_troop_cd := 0.0
var donate_gold_cd := 0.0
var diplo_panel: Panel
var diplo_who := -1
var diplo_refs := {}
var ally_card: Control
var ally_card_lbl: Label
var ally_card_sub: Label
var ally_card_bar: Control
var ally_card_sq: Control
var ally_card_btn_a: Button
var ally_card_btn_b: Button
var ally_card_mode := ""
var ally_card_who := -1
var ally_warned := {}

const EXTEND_RETRY := [[65, 100], [55, 70], [45, 60]]
# ---- alliance requests (Sim.ally_request / ally_reply 1371-1410, SimState requests 991-1035, SimAI replies 1013-1085)
var ally_requests := {}   # from*1024+to -> tick made
var ally_req_last := {}   # from*1024+to -> tick the last (closed) request was made: cooldown
var ally_replies := []    # [due_tick, from, to] AI answers
const AI_ACCEPT_BIAS := [0.1, 0.0, -0.15]  # SimAI.ACCEPT_BIAS by difficulty
const AI_MAX_ALLIES := 3                   # Rules.AI_MAX_ALLIES
# ---------------- loop ----------------
var map_t := 0.0
var _fp := {}
var _pf := {}  # perf sums over a window (stress / --perf): frames, process, sim, ticks, atk, ai, eco, missiles, fx, draw
var _pace := {}
var speed_slider: HSlider
var speed_lbl: Label
var _step := 0
var _pboat = null
var _pre := 0
var _qs := 0
var _l27 := 0
var _l27c := Vector2.ZERO
var _rws := 0
var _r29 := 0
var _r29_t := 0.0
var _r29_kind := 0
var _r29_shot := 0
const R29_KINDS := [7, 8, 9, 12]
const R29_NAMES := {7: "atom", 8: "hydrogen", 9: "mirv_fan", 12: "scattershot"}

# ---- FrontLayer.luau port (src/client/Map/FrontLayer.luau): troop counts on the local player's fronts ----
# Outgoing attacks on a real owner (never wilderness / expansion) and incoming attacks from players or
# nations (never tribes) get one label each: that attack's troops in Rubik Bold 17 px, blue / red, black
# 1.5 px stroke, no background. Labels sit on the 1-2 largest 8-connected clusters of our border tiles that
# touch the other owner (nearest tile to each cluster centroid), glide 0.25 s, snap on long jumps.
const FRONT_POLL_S := 0.2
const FRONT_ANIM_S := 0.25
const FRONT_SNAP_FULL := 200.0
const FRONT_MIN_CLUSTER_FULL := 30.0
const FRONT_MAX_CLUSTERS := 2
const FRONT_OUT := Color(0x3f / 255.0, 0xa9 / 255.0, 0xf5 / 255.0)
const FRONT_IN := Color(0xf8 / 255.0, 0x71 / 255.0, 0x71 / 255.0)
const FRONT_TEXT_PX := 17.0
const FRONT_STROKE_PX := 1.5
var _front_entries := {}  # aid -> {text, incoming, slots: [{sx, sy, dx, dy, t0}]}
var _front_next := 0.0

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

var _preview_queue: Array = []
var _preview_cache := {}
var _pv_job := {}
var _preview_blank: ImageTexture
var preview_pump_us := 0

var speed_panel: Control
var speed_title: Label
var speed_hint: Label
var speed_ticks: Control

# ---- attacks ----
var atk_panel_p: Panel
# ---- bottom bar ----
var icbm_btn: Button
var _ema_regen := 0.0
var _ema_gold := 0.0
var _ema_init := false
var _hud_rate_t := 0.0
var _hud_txt_t := 0.0
var over_panel_holder: Control
var over_panel_p: Panel

# Tooltip.luau: glass(12, 10, R_MD); title 15/700 + badge pill 10/700; sub 12/500; rows 12/500 key vs
# 13/600 value; body 12/500 wrapped; hint 12/600 with a 14 px icon after a divider. Min width 236 when it
# follows the cursor (+20, +22), 220 when anchored (10 px above the anchor).
const TIP_PAD := Vector2(12, 10)
# One shared number formatter: K M B T Qd Qt, ~4 significant digits (159.3B, 25.5M, 62.1K, 9.87M).
const _FMT_U := ["", "K", "M", "B", "T", "Qd", "Qt"]
# ================= v6: stars, arsenal, air strike, railgun, end screen =================
const ARSENAL := [
	{"id": "mega", "k": 11, "name": "Mega Nuke", "desc": "An atom bomb with double the blast.", "b": ["Twice the atom blast radius", "2.5M gold per launch"], "cost": 0},
	{"id": "scatter", "k": 12, "name": "Scattershot", "desc": "A core bomb plus 4-6 scattered warheads.", "b": ["Warheads land 28-46 tiles out", "Overwhelms a single SAM"], "cost": 4000},
	{"id": "reinf", "k": 13, "name": "Reinforcements", "desc": "Buy fresh troops the moment you need them.", "b": ["+1/5 of your troop cap", "30 s cooldown"], "cost": 0},
	{"id": "art", "k": 10, "name": "Artillery", "desc": "A gun post that shells nearby enemies.", "b": ["A shell every 4-7 s", "Targets structures first"], "cost": 2500},
	{"id": "air", "k": 14, "name": "Air Strike", "desc": "Airfields fly aimed bombing runs.", "b": ["Free strike, 30 s rearm", "Kills up to 6% of troops"], "cost": 8000},
	{"id": "rail", "k": 15, "name": "Railgun", "desc": "A railgun fires a slug at any range.", "b": ["Free shot, 25 s reload", "Kills up to 4% of troops"], "cost": 12000},
	{"id": "x2", "k": -1, "name": "2x Stars", "desc": "Every match pays out twice.", "b": ["Double star payout", "Applies to every match"], "cost": 15000},
	{"id": "reload", "k": -1, "name": "Rapid Reload", "desc": "Your structures recharge twice as fast.", "b": ["2x reload speed", "SAM, silo, airfield, railgun"], "cost": 10000}]
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

# ---------- unified shop & arsenal (stars menu) ----------
var _shop_hid_over := false
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

# docs/HOOKS_AUDIO.md: upstream AudioDirector gates and plays SFX. Loaded with load() (not preload) so a
# broken director file can never stop main.gd from parsing; then the legacy pool below is used.
# The bed stays on the legacy music_player (same frontline_bed.wav), so the director's music is off.
var audio_dir: Node = null
var _audio_dir_known := {}
var _dir_music := false  # the director plays the soundtrack playlist (music_player idle)
# play a sound by key; vol_db lets far/AI events be quieter. Missing sounds are ignored.
var _sfx_log := false
const SFX_ANY_OWNER := ["atom_launch", "hydrogen_launch", "mirv_launch", "atom_hit", "hydrogen_hit"]
# Only this file may play as music. sounds/rejected/ holds the old themes; they are not scanned.
const MUSIC_FILE := "res://sounds/music/frontline_bed.wav"

const BUILD_SFX := {0: "build_city", 1: "build_port", 2: "build_factory", 3: "build_defense", 4: "build_sam", 5: "build_silo", 6: "build_warship", 10: "build_defense", 14: "build_silo"}

# ================= port1 tests: systems ported from RoWorld (sim/arsenal.gd, sim/warships.gd, trains) =================
var _pt_fail := 0
var _pt_saved_unlocks := []


# ---------------- forward declarations ----------------
# Functions called from an earlier layer than the one that defines them. The real versions override these.

func _load_progress(v: float) -> void:
	pass  # forward declaration; implemented in game/nations.gd

func _random_start() -> int:
	return 0  # forward declaration; implemented in game/nations.gd

func owned(id: int, k: int) -> int:
	return 0  # forward declaration; implemented in game/economy.gd

func launch_attack(a: int, t: int, share: float) -> bool:
	return false  # forward declaration; implemented in game/economy.gd

func _adj_to(i: int, a: int) -> bool:
	return false  # forward declaration; implemented in game/economy.gd

func launch_boat(a: int, click: int, share: float, max_nodes := 1000000) -> bool:
	return false  # forward declaration; implemented in game/economy.gd

func _struct_remove(st) -> void:
	pass  # forward declaration; implemented in game/economy.gd

func add_float(world_pos: Vector2, text: String, col: Color = GOLD_C) -> void:
	pass  # forward declaration; implemented in game/economy.gd

func notify(text: String, kind := "info") -> void:
	pass  # forward declaration; implemented in game/economy.gd

func _nname(id: int) -> String:
	return ""  # forward declaration; implemented in game/economy.gd

func nuke_cost(k: int) -> float:
	return 0.0  # forward declaration; implemented in game/nukes.gd

func set_icbm(on: bool) -> void:
	pass  # forward declaration; implemented in game/nukes.gd

func launch_nuke(o: int, k: int, tile: int) -> bool:
	return false  # forward declaration; implemented in game/nukes.gd

func spawn_warship(o: int, target_tile: int = -1) -> bool:
	return false  # forward declaration; implemented in game/navy.gd

func _count_ws(o: int) -> int:
	return 0  # forward declaration; implemented in game/bot_ai.gd

func _q() -> int:
	return 0  # forward declaration; implemented in game/draw_helpers.gd

func launch_plane(a: int, click: int, share: float) -> bool:
	return false  # forward declaration; implemented in game/planes_fx.gd

func _tick_air_cargo(dt: float) -> void:
	pass  # forward declaration; implemented in game/planes_fx.gd

func _akey(a: int, b: int) -> int:
	return 0  # forward declaration; implemented in game/diplomacy.gd

func allied(a: int, b: int) -> bool:
	return false  # forward declaration; implemented in game/diplomacy.gd

func is_traitor(id: int) -> bool:
	return false  # forward declaration; implemented in game/diplomacy.gd

func break_alliance(breaker: int, other: int) -> void:
	pass  # forward declaration; implemented in game/diplomacy.gd

func ally_reply(id: int, target: int, accept: bool) -> bool:
	return false  # forward declaration; implemented in game/diplomacy.gd

func is_embargoed(_a: int, _b: int) -> bool:
	return false  # forward declaration; implemented in game/diplomacy.gd

func _pf_add(k: String, v: float) -> void:
	pass  # forward declaration; implemented in main.gd

func _pf_line() -> String:
	return ""  # forward declaration; implemented in main.gd

func set_speed(k: int) -> void:
	pass  # forward declaration; implemented in main.gd

func set_speed_x(x: float) -> void:
	pass  # forward declaration; implemented in main.gd

func _shot(name: String) -> void:
	pass  # forward declaration; implemented in main.gd

func warp_away() -> void:
	pass  # forward declaration; implemented in main.gd

func _focus_player(z: float) -> void:
	pass  # forward declaration; implemented in main.gd

func _draw_overlay() -> void:
	pass  # forward declaration; implemented in main.gd

func _icon(p: Vector2, k: int, col: Color, a: float, ci: CanvasItem = null, r := 11.0, bg := true) -> void:
	pass  # forward declaration; implemented in main.gd

func _clamp_cam() -> void:
	pass  # forward declaration; implemented in main.gd

func _screen_of(world: Vector2) -> Vector2:
	return Vector2.ZERO  # forward declaration; implemented in main.gd

func _mouse_tile() -> int:
	return 0  # forward declaration; implemented in main.gd

func _fade_out(n: CanvasItem, dur := 0.15) -> void:
	pass  # forward declaration; implemented in game/ui_anim.gd

func _pop_in(c: Control, dur := 0.2) -> void:
	pass  # forward declaration; implemented in game/ui_anim.gd

func _flat(c: Color, r: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	return null  # forward declaration; implemented in game/ui_build.gd

func _P(parent: Node, r: Rect2, c := PANEL_BG, rad := 14, border := Color(1, 1, 1, 0.07), bw := 1, shadow := true) -> Panel:
	return null  # forward declaration; implemented in game/ui_build.gd

func _T(parent: Node, t: String, pos: Vector2, fs: int, col := TEXT, font: Font = null, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return null  # forward declaration; implemented in game/ui_build.gd

func _head(parent: Node, t: String, pos: Vector2, fs := 12, col := MUTED, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return null  # forward declaration; implemented in game/ui_build.gd

func _draw_ctl(parent: Node, r: Rect2, f: Callable) -> Control:
	return null  # forward declaration; implemented in game/ui_build.gd

func _pill(b: Button, on: bool, r := 7) -> void:
	pass  # forward declaration; implemented in game/ui_build.gd

func _big_btn(parent: Node, r: Rect2, t: String, col: Color, fs := 20) -> Button:
	return null  # forward declaration; implemented in game/ui_build.gd

func _card_btn(parent: Node, r: Rect2) -> Button:
	return null  # forward declaration; implemented in game/ui_build.gd

func _build_ui() -> void:
	pass  # forward declaration; implemented in game/ui_build.gd

func _wrap(t: String, f: Font, fs: int, w: float) -> Array:
	return []  # forward declaration; implemented in game/ui_build.gd

func _update_hud() -> void:
	pass  # forward declaration; implemented in game/ui_build.gd

func _pct(v: float) -> String:
	return ""  # forward declaration; implemented in game/ui_build.gd

func _fmt_time(s: float) -> String:
	return ""  # forward declaration; implemented in game/ui_build.gd

func _fmt(n: float) -> String:
	return ""  # forward declaration; implemented in game/ui_build.gd

func load_save() -> void:
	pass  # forward declaration; implemented in game/ui_build.gd

func apply_settings(recolor_map := true) -> void:
	pass  # forward declaration; implemented in game/ui_build.gd

func unlocked(id: String) -> bool:
	return false  # forward declaration; implemented in game/ui_build.gd

func kind_locked(k: int) -> String:
	return ""  # forward declaration; implemented in game/ui_build.gd

func _draw_meta_fx(z: float) -> void:
	pass  # forward declaration; implemented in game/strikes.gd

func _star(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	pass  # forward declaration; implemented in game/end_screen.gd

func _fmt_int(n: int) -> String:
	return ""  # forward declaration; implemented in game/end_screen.gd

func _build_end() -> void:
	pass  # forward declaration; implemented in game/end_screen.gd

func show_end(win: bool) -> void:
	pass  # forward declaration; implemented in game/end_screen.gd

func _open_shop() -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _build_arsenal() -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _end_icon(cc: Control, kk: int, col: Color) -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _draw_gear(c: Control, o: Vector2, r: float, col: Color) -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _open_settings() -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _build_settings() -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _build_console() -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _update_console_fps(dt: float) -> void:
	pass  # forward declaration; implemented in game/shop.gd

func _init_audio() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _apply_volumes() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func sfx(key: String, vol_db := 0.0, pitch_jitter := 0.04, who := PLAYER) -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _play_music() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _stop_music() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _regress() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _speedshot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _audiotest() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _maptest() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _rangetest() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _rangetest2() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _bordershot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _idletest() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _stress() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _uishot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _dmgshot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _shipshot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _hudshot() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _porttest() -> void:
	pass  # forward declaration; implemented in game/audio.gd

func _portshot() -> void:
	pass  # forward declaration; implemented in game/audio.gd
