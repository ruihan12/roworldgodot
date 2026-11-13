extends Node
## Self-contained port of RoWorld src/client/Audio/AudioDirector.luau (+ MusicMood, Playlist).
## Driven by event names. Does not edit main.gd; see docs/HOOKS_AUDIO.md for wiring.
## Music: the RoWorld soundtrack (Assets/Soundtrack.luau, 33 tracks by Rodrigo Flores, CC BY 4.0) from
## sounds/upstream/music/<key>.ogg, played as upstream's Playlist by mood (title opener, shuffled, no recent
## repeats, next track overlaps the last TRACK_OVERLAP_S, war -> calm lets the battle track play out,
## victory/defeat play once). Fallback when no track file is present: res://sounds/music/frontline_bed.wav
## (looping). Never sounds/rejected/.

const PLAYER_DEFAULT := 1
const MUSIC_FILE := "res://sounds/music/frontline_bed.wav"
## Soundtrack.luau (upstream @ae7a350): key -> [length s, title]; moods -> playlists (first title = opener).
const SOUNDTRACK_CREDIT := "Music by Rodrigo Flores (CC BY 4.0)"
const SOUNDTRACK_TRACKS := {
	"a_moment_of_reflection": [130.657483, "A Moment of Reflection"],
	"abandoned_fortress": [137.773016, "Abandoned Fortress"],
	"adventure_ahead": [123.726213, "Adventure Ahead"],
	"ancient_conflict": [151.043084, "Ancient Conflict"],
	"clashing_destiny": [128.134059, "Clashing Destiny"],
	"corrupt_policies": [123.515669, "Corrupt Policies"],
	"cultural_heritage": [128.712404, "Cultural Heritage"],
	"culture_shock": [130.604104, "Culture Shock"],
	"dance_of_fate": [143.402971, "Dance of Fate"],
	"defending_our_land": [130.893107, "Defending Our Land"],
	"diplomatic_exchange": [122.907347, "Diplomatic Exchange"],
	"foreign_traditions": [114.622971, "Foreign Traditions"],
	"forgotten_glories": [144.097279, "Forgotten Glories"],
	"formidable_opponent": [134.698798, "Formidable Opponent"],
	"friend_or_foe": [125.298866, "Friend or Foe"],
	"glorious_fortress": [120.680159, "Glorious Fortress"],
	"glory_of_the_nation": [135.216259, "Glory of the Nation"],
	"grandiose_court": [104.804331, "Grandiose Court"],
	"heroes_of_the_past": [124.120045, "Heroes of the Past"],
	"hope_is_our_ally": [148.387166, "Hope Is Our Ally"],
	"looking_for_answers": [102.138367, "Looking for Answers"],
	"march_of_war": [131.662086, "March of War"],
	"matters_of_the_court": [122.474444, "Matters of the Court"],
	"national_emblem": [122.844535, "National Emblem"],
	"path_to_greatness": [138.60678, "Path to Greatness"],
	"political_move": [131.929002, "Political Move"],
	"revolutionary_thoughts": [114.458141, "Revolutionary Thoughts"],
	"state_of_peril": [152.400907, "State of Peril"],
	"stay_alert": [97.846961, "Stay Alert!"],
	"unavoidable_consequence": [83.609116, "Unavoidable Consequence"],
	"uncertain_times": [127.198526, "Uncertain Times"],
	"uncovering_the_past": [136.226689, "Uncovering the Past"],
	"war_declaration": [141.098435, "War Declaration"],
}
const SOUNDTRACK_MOODS := {
	"title": ["glory_of_the_nation", "hope_is_our_ally", "national_emblem", "grandiose_court", "cultural_heritage"],
	"wait": ["uncertain_times", "political_move", "friend_or_foe"],
	"calm": ["uncovering_the_past", "diplomatic_exchange", "uncertain_times", "revolutionary_thoughts", "political_move", "dance_of_fate", "culture_shock", "adventure_ahead", "friend_or_foe", "forgotten_glories", "foreign_traditions", "heroes_of_the_past", "matters_of_the_court", "looking_for_answers", "corrupt_policies"],
	"war": ["war_declaration", "march_of_war", "clashing_destiny", "formidable_opponent", "ancient_conflict", "defending_our_land", "stay_alert", "path_to_greatness", "unavoidable_consequence", "state_of_peril", "abandoned_fortress"],
	"victory": ["glorious_fortress"],
	"defeat": ["a_moment_of_reflection"],
}
const SFX_ROOT := "res://sounds/play/"
## Real upstream renders (sounds/upstream/<event>.wav) win over stand-ins when present.
var upstream_root: String = "res://sounds/upstream/"
var upstream_events: Array = []

# ---------------------------------------------------------------------------------------------
# Upstream constants (AudioDirector.luau)
# ---------------------------------------------------------------------------------------------

const SFX_NAMES := [
	"ui_click", "ui_hover", "ui_open", "ui_error", "countdown_tick",
	"countdown_tick_5", "countdown_tick_4", "countdown_tick_3", "countdown_tick_2",
	"countdown_tick_1", "countdown_gamestart", "queue_start", "spectate_switch",
	"order_ack", "crate_drop", "crate_land", "crate_rattle", "crate_preview_common",
	"crate_preview_rare", "crate_preview_epic", "crate_preview_legendary", "crate_open",
	"crate_shimmer", "card_whoosh", "card_flip", "reveal_common", "reveal_rare",
	"reveal_epic", "reveal_legendary", "expand", "spawn_confirm", "attack_launch",
	"boat_launch", "build", "warship", "nuke_launch", "nuke_alarm", "nuke_explosion",
	"sam_launch", "sam_intercept", "shell_fire", "shell_hit", "shell_splash",
	"ship_sink", "under_attack", "ally_request", "alliance", "betrayal", "conquer",
	"victory", "defeat", "game_start", "ui_confirm", "ui_back", "ui_tab", "ui_locked",
	"expand_pop", "eliminate", "star_tick", "star_get", "buy_spend", "unlock",
	# Port-only names that have local files (kept as first-class events).
	"ally_decline", "slider", "warship_shot", "build_city", "build_port",
	"build_factory", "build_defense", "build_sam", "build_silo", "build_station",
	"icbm_launch",
]

## Long stings: a full play at most once per cooldown (ms). A repeat inside the window plays the
## fallback instead ("" = stay silent).
const COOLDOWNS := {
	"attack_launch": [1200, "order_ack"],
	"boat_launch": [1500, "order_ack"],
	"warship": [2000, "order_ack"],
	"spawn_confirm": [700, "ui_click"],
	"conquer": [2500, ""],
	"eliminate": [2500, ""],
	"betrayal": [3000, ""],
	"alliance": [2500, ""],
	"ally_request": [1500, ""],
	"ally_decline": [1500, ""],
	"under_attack": [4000, ""],
	"nuke_alarm": [2500, ""],
	"game_start": [3000, ""],
	"victory": [10000, ""],
	"defeat": [10000, ""],
}

const THROTTLE_MS := {
	"expand": 150, "ui_hover": 45, "ui_click": 30, "ui_open": 60, "ui_error": 120,
	"countdown_tick": 250, "order_ack": 80, "build": 90, "sam_intercept": 90,
	"nuke_launch": 150, "nuke_explosion": 180, "sam_launch": 100, "shell_fire": 120,
	"shell_hit": 90, "shell_splash": 90, "ship_sink": 400, "spectate_switch": 150,
	"crate_rattle": 90, "ui_confirm": 60, "ui_back": 60, "ui_tab": 40, "ui_locked": 150,
	"expand_pop": 38, "eliminate": 250, "star_tick": 28, "star_get": 120,
	"buy_spend": 150, "unlock": 800, "slider": 40, "warship_shot": 90,
	"build_city": 90, "build_port": 90, "build_factory": 90, "build_defense": 90,
	"build_sam": 90, "build_silo": 90, "build_station": 90, "atom_launch": 150,
	"hydrogen_launch": 150, "mirv_launch": 150, "icbm_launch": 150,
	"atom_hit": 180, "hydrogen_hit": 180,
}
const DEFAULT_THROTTLE_MS := 50

const MAX_SAME := {
	"expand": 2, "ui_hover": 1, "ui_click": 2, "order_ack": 2, "nuke_alarm": 1,
	"attack_launch": 2, "boat_launch": 2, "warship": 2, "sam_launch": 3,
	"shell_fire": 3, "shell_hit": 3, "shell_splash": 2, "ship_sink": 2,
	"under_attack": 1, "ally_request": 1, "victory": 1, "defeat": 1,
	"game_start": 1, "countdown_tick": 1, "countdown_gamestart": 1,
	"queue_start": 1, "spectate_switch": 1, "crate_drop": 1, "crate_land": 1,
	"crate_rattle": 2, "crate_preview_common": 1, "crate_preview_rare": 1,
	"crate_preview_epic": 1, "crate_preview_legendary": 1, "crate_open": 1,
	"crate_shimmer": 1, "card_whoosh": 1, "card_flip": 1, "reveal_common": 1,
	"reveal_rare": 1, "reveal_epic": 1, "reveal_legendary": 1, "ui_confirm": 2,
	"ui_back": 2, "ui_tab": 2, "ui_locked": 1, "expand_pop": 6, "eliminate": 2,
	"star_tick": 4, "star_get": 2, "buy_spend": 1, "unlock": 1,
}
const DEFAULT_MAX_SAME := 3

const PRIORITY := {
	"ui_hover": 0, "ui_click": 0, "order_ack": 0, "expand": 0, "expand_pop": 0,
	"eliminate": 2, "ui_tab": 0, "star_tick": 0, "unlock": 2, "shell_fire": 0,
	"shell_hit": 0, "shell_splash": 0, "victory": 2, "defeat": 2, "game_start": 2,
	"nuke_alarm": 2, "nuke_explosion": 2, "under_attack": 2, "betrayal": 2,
	"conquer": 2, "alliance": 2, "crate_open": 2, "reveal_common": 2,
	"reveal_rare": 2, "reveal_epic": 2, "reveal_legendary": 2,
}

## name -> [amount_db, hold_seconds]
const AUTO_DUCK := {
	"nuke_explosion": [8.0, 2.5], "nuke_alarm": [4.0, 1.8], "game_start": [5.0, 4.0],
	"countdown_gamestart": [5.0, 2.5], "under_attack": [3.0, 1.0], "victory": [14.0, 9.0],
	"defeat": [14.0, 6.0], "betrayal": [3.0, 1.5], "conquer": [3.0, 1.2],
	"crate_preview_epic": [3.0, 1.8], "crate_preview_legendary": [4.0, 2.0],
	"crate_open": [4.0, 1.5], "reveal_epic": [4.0, 2.5], "reveal_legendary": [6.0, 4.0],
	"unlock": [5.0, 3.0], "atom_hit": [8.0, 2.5], "hydrogen_hit": [8.0, 2.5],
}

const POP_SLOW := 40.0
const POP_FAST := 600.0
const POP_RATE_MIN := 2.0
const POP_RATE_MAX := 20.0
const POP_CURVE := 2.0
const POP_SMOOTH_S := 0.45
const POP_PER_BATCH := 2
const POP_SECOND_S := 0.05
const POP_PITCH_MIN := 0.8
const POP_PITCH_MAX := 1.1
const POP_WARM_S := 15.0
const POP_COOL_S := 6.0
const POP_RUN_GAP_S := 0.7
const POP_JITTER := 0.012
const POP_PROGRESS_LIFT := 0.05
const POP_DB_MIN := -9.0
const POP_DB_MAX := -3.0
const POP_BIG := 60.0
const VOICE_COUNT := 18
const HUSH_POPS := {"eliminate": 0.65}

const CROSSFADE_S := 2.0
const TRACK_OVERLAP_S := 2.0
const MOOD_FADE_S := 3.0
const WAR_FADE_S := 2.0
const TOGGLE_FADE_S := 0.6
const DUCK_ATTACK_DB_PER_S := 60.0
const DUCK_RELEASE_DB_PER_S := 6.0
const SILENT_DB := -80.0

## Extra port rule: mute boat / conquer for this many ms after begin_match() so match-start
## land grabs and AI boats cannot spam (fallback accents are also suppressed in the window).
const MATCH_START_HUSH_MS := 3000
const MATCH_START_HUSH_EVENTS := ["boat_launch", "conquer", "eliminate", "transport"]

## Upstream REPLACE: the attack sting became a short order tap.
const REPLACE := {"attack_launch": "order_ack"}
const TRIM_DB := {"conquer": -6.0, "eliminate": -3.0}

# ---------------------------------------------------------------------------------------------
# Event aliases (UICtx.SFX + current main.gd keys) -> canonical director name
# ---------------------------------------------------------------------------------------------

const ALIASES := {
	"hover": "ui_hover", "click": "ui_click", "open": "ui_open", "close": "ui_back",
	"deny": "ui_error", "toast": "ui_tab", "confirm": "ui_confirm", "tab": "ui_tab",
	"locked": "ui_locked", "buy": "buy_spend", "attack": "attack_launch",
	"boat": "boat_launch", "transport": "boat_launch", "explosion": "nuke_explosion",
	"intercept": "sam_intercept", "alarm": "nuke_alarm", "nuke_warning": "nuke_alarm",
	"tick": "countdown_tick", "start": "game_start", "spawn": "spawn_confirm",
	"ship_lost": "ship_sink", "warship_lost": "ship_sink", "ally_suggest": "ally_request",
	"ally_accept": "alliance", "ally_broken": "betrayal", "order": "order_ack",
	"ka_ching": "buy_spend", "conquered": "conquer", "sam_shoot": "sam_launch",
	"sam_hit": "sam_intercept", "atom_launch": "nuke_launch",
	"hydrogen_launch": "nuke_launch", "mirv_launch": "nuke_launch",
	"icbm_launch": "nuke_launch", "atom_hit": "nuke_explosion",
	"hydrogen_hit": "nuke_explosion", "build_warship": "warship",
	"ship_kill": "warship_shot", "shell": "shell_fire",
}

# ---------------------------------------------------------------------------------------------
# Local file map (canonical name -> files under sounds/play/). Gaps use the closest file.
# ---------------------------------------------------------------------------------------------

const EVENT_FILES := {
	"ui_click": ["click.wav", "click-1.wav", "click-2.wav", "click-3.wav"],
	"ui_hover": ["slider.wav"],
	"ui_open": ["click-2.wav"],
	"ui_error": ["alliance-declined.wav"],
	"countdown_tick": ["slider.wav"],
	"countdown_tick_5": ["slider.wav"], "countdown_tick_4": ["slider.wav"],
	"countdown_tick_3": ["slider.wav"], "countdown_tick_2": ["slider.wav"],
	"countdown_tick_1": ["click-1.wav"],
	"countdown_gamestart": ["game-start.wav"],
	"queue_start": ["game-start.wav"],
	"spectate_switch": ["click-3.wav"],
	"order_ack": ["order.wav"],
	"crate_drop": ["build-port.wav"],
	"crate_land": ["build-defense-post.wav"],
	"crate_rattle": ["slider.wav"],
	"crate_preview_common": ["ka-ching.wav"],
	"crate_preview_rare": ["ka-ching.wav"],
	"crate_preview_epic": ["ka-ching.wav"],
	"crate_preview_legendary": ["ka-ching.wav"],
	"crate_open": ["ka-ching.wav"],
	"crate_shimmer": ["alliance-accepted.wav"],
	"card_whoosh": ["slider.wav"],
	"card_flip": ["click-2.wav"],
	"reveal_common": ["ka-ching.wav"],
	"reveal_rare": ["ka-ching.wav"],
	"reveal_epic": ["ka-ching.wav"],
	"reveal_legendary": ["ka-ching.wav"],
	"expand": ["spawn.wav"],
	"spawn_confirm": ["spawn.wav"],
	"attack_launch": ["order.wav"],
	"boat_launch": ["transport-ship.wav"],
	"build": ["build-city.wav"],
	"warship": ["build-warship.wav"],
	"nuke_launch": ["atom-launch.wav"],
	"nuke_alarm": ["nuke-warning.wav"],
	"nuke_explosion": ["atom-hit.wav"],
	"sam_launch": ["sam-shoot.wav"],
	"sam_intercept": ["sam-hit.wav"],
	"shell_fire": ["warship-shot.wav"],
	"shell_hit": ["warship-shot.wav"],
	"shell_splash": ["sam-hit.wav"],
	"ship_sink": ["warship-lost.wav"],
	"under_attack": ["alliance-broken.wav"],
	"ally_request": ["alliance-suggested.wav"],
	"alliance": ["alliance-accepted.wav"],
	"betrayal": ["alliance-broken.wav"],
	"conquer": ["conquered.wav"],
	"victory": ["victory.wav"],
	"defeat": ["defeat.wav"],
	"game_start": ["game-start.wav"],
	"ui_confirm": ["click-3.wav"],
	"ui_back": ["click-2.wav"],
	"ui_tab": ["click-1.wav"],
	"ui_locked": ["alliance-declined.wav"],
	"expand_pop": ["slider.wav"],
	"eliminate": ["conquered.wav"],
	"star_tick": ["slider.wav"],
	"star_get": ["ka-ching.wav"],
	"buy_spend": ["ka-ching.wav"],
	"unlock": ["alliance-accepted.wav"],
	"ally_decline": ["alliance-declined.wav"],
	"slider": ["slider.wav"],
	"warship_shot": ["warship-shot.wav"],
	"build_city": ["build-city.wav"],
	"build_port": ["build-port.wav"],
	"build_factory": ["build-factory.wav"],
	"build_silo": ["silo-built.wav"],
	"build_sam": ["sam-built.wav"],
	"build_defense": ["build-defense-post.wav"],
	"build_station": ["build-train-station.wav"],
	"icbm_launch": ["hydrogen-launch.wav"],
}

## Launch / impact file by munition kind (overrides EVENT_FILES when opts.kind or alias says so).
const LAUNCH_BY_KIND := {
	"atom": "atom-launch.wav", "mega": "atom-launch.wav", "scatter": "atom-launch.wav",
	"hydrogen": "hydrogen-launch.wav", "h": "hydrogen-launch.wav",
	"mirv": "mirv-launch.wav", "icbm": "hydrogen-launch.wav",
}
const IMPACT_BY_KIND := {
	"atom": "atom-hit.wav", "mega": "atom-hit.wav", "scatter": "atom-hit.wav",
	"warhead": "atom-hit.wav", "hydrogen": "hydrogen-hit.wav", "h": "hydrogen-hit.wav",
	"mirv": "atom-hit.wav", "icbm": "hydrogen-hit.wav",
}

## Still missing with the real RoWorld set installed: the looping menu / war themes (never preloaded
## upstream; the soundtrack playlist replaces them). "soundtrack.*" counts as a gap only when no
## sounds/upstream/music/*.ogg track loads (bed fallback).
const GAPS := ["music.menu", "music.war"]
## Events whose port stand-in (sounds/play/) is not the RoWorld asset: a gap only while
## sounds/upstream/<event>.wav is absent (all 62 RoWorld sfx are installed there since 2026-11-09).
const STANDIN_GAPS := [
	"ui_hover", "ui_open", "ui_error", "ui_confirm", "ui_back", "ui_tab", "ui_locked",
	"countdown_tick", "countdown_tick_1", "countdown_tick_2", "countdown_tick_3",
	"countdown_tick_4", "countdown_tick_5", "countdown_gamestart", "queue_start",
	"spectate_switch", "expand", "expand_pop", "under_attack", "shell_fire",
	"shell_hit", "shell_splash", "eliminate", "star_tick", "star_get", "unlock",
	"crate_drop", "crate_land", "crate_rattle", "crate_preview_common",
	"crate_preview_rare", "crate_preview_epic", "crate_preview_legendary",
	"crate_open", "crate_shimmer", "card_whoosh", "card_flip", "reveal_common",
	"reveal_rare", "reveal_epic", "reveal_legendary",
]

## Gating sets (after alias + REPLACE resolution).
const GATE_NUKE := ["nuke_launch", "nuke_explosion"]
const GATE_NUKE_IF_HIT := ["nuke_alarm"]
const GATE_UI := [
	"ui_click", "ui_hover", "ui_open", "ui_error", "ui_confirm", "ui_back", "ui_tab",
	"ui_locked", "countdown_tick", "countdown_tick_1", "countdown_tick_2",
	"countdown_tick_3", "countdown_tick_4", "countdown_tick_5", "countdown_gamestart",
	"queue_start", "spectate_switch", "game_start", "star_tick", "star_get",
	"buy_spend", "unlock", "slider", "card_flip", "card_whoosh", "crate_drop",
	"crate_land", "crate_rattle", "crate_preview_common", "crate_preview_rare",
	"crate_preview_epic", "crate_preview_legendary", "crate_open", "crate_shimmer",
	"reveal_common", "reveal_rare", "reveal_epic", "reveal_legendary",
]

signal music_enabled_changed(on: bool)
signal pops_enabled_changed(on: bool)
signal sfx_played(event: String, canonical: String, file: String)
signal sfx_blocked(event: String, canonical: String, reason: String)

var player_id: int = PLAYER_DEFAULT
var music_volume_db: float = -6.0
var sfx_volume_db: float = 0.0
## 0..1 slider; gain is its square (upstream level_gain).
var _music_level: float = 1.0
var _music_on: bool = true
var _pops_on: bool = true

var play_log: Array = []
var blocked_log: Array = []
## If >= 0, _now_ms() returns this (tests).
var clock_ms: int = -1
var last_reason: String = ""
var last_file: String = ""
var last_canonical: String = ""

var _streams: Dictionary = {} # canonical -> Array[AudioStream]
var _pool: Dictionary = {} # canonical -> Array[Dictionary] {player, started, name}
var _voices: Array = []
var _last_start_ms: Dictionary = {}
var _last_full_ms: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current: AudioStreamPlayer
var _outgoing: AudioStreamPlayer
var _current_theme: String = ""
var _fade_t: float = 1.0
var _fade_len: float = CROSSFADE_S
var _master_gain: float = 1.0
var _duck_db: float = 0.0
var _duck_target_db: float = 0.0
var _duck_hold_s: float = 0.0
var _toggle_paused: Dictionary = {}
var _requested_mood: String = ""
var _mood: MusicMood = MusicMood.new()
var _match_t0_ms: int = -1
var _pop_debt: float = 0.0
var _pop_speed: float = 0.0
var _pop_last: float = -1e9
var _pop_run_last: float = -1e9
var _pop_hush_until: float = -1e9
var _pop_heat: float = 0.0
var _pending_second_pop: float = -1.0
var _pending_pop_pitch: float = 1.0
var _pending_pop_db: float = POP_DB_MAX
var _rng := RandomNumberGenerator.new()
var _ready_ok: bool = false
var _music_stream: AudioStream
var _missing: Array = []
## Soundtrack (upstream AudioDirector _playlist/_pool_mood/_track/_next)
var _playlist: Playlist = null
var _pool_mood: String = ""
var _track: String = ""
var _track_len: float = 0.0
var _next_mood: String = ""
var _next_key: String = ""
var _track_streams: Dictionary = {} # key -> AudioStream (current + preloaded next only)
var _current_file: String = ""

class MusicMood:
	const WAR_HOLD_S := 40.0
	const KIND_TRIBE := 1
	var _war_until: float = -1e18

	func reset() -> void:
		_war_until = -1e18

	## attacks: Array of {attacker, target}; nukes: Array of {owner, to_owner}
	static func fighting(me: int, attacks: Array, nukes: Array) -> bool:
		if me == 0:
			return false
		for a in attacks:
			var atk := int(a.get("attacker", a.get("a", 0)))
			var tgt := int(a.get("target", a.get("t", 0)))
			if (atk == me and tgt != 0 and tgt != me) or (tgt == me and atk != 0 and atk != me):
				return true
		for n in nukes:
			if int(n.get("owner", n.get("o", 0))) == me:
				return true
			if int(n.get("to_owner", n.get("victim", 0))) == me:
				return true
		return false

	func mood(input: Dictionary, now_s: float) -> String:
		var screen := str(input.get("screen", "title"))
		var waiting := bool(input.get("waiting", false))
		var me := int(input.get("me", 0))
		var alive := bool(input.get("alive", true))
		var winner := int(input.get("winner", 0))
		var is_fight := bool(input.get("fighting", false))
		if screen == "title":
			_war_until = -1e18
			return "wait" if waiting else "title"
		if me == 0:
			return "calm"
		if screen == "over" or not alive:
			return "victory" if winner != 0 and winner == me else "defeat"
		if is_fight:
			_war_until = now_s + WAR_HOLD_S
		return "war" if now_s < _war_until else "calm"


class Playlist:
	const HISTORY := 6
	const FALLBACK := {"wait": "calm", "calm": "title", "war": "calm", "victory": "title", "defeat": "calm"}
	const AFTER := {"victory": "title", "defeat": "calm"}
	var tracks: Dictionary = {}
	var moods: Dictionary = {}
	var _history: Array = []
	var _opened: Dictionary = {}
	var _rng: RandomNumberGenerator

	func _init(manifest: Dictionary = {}, rng: RandomNumberGenerator = null) -> void:
		tracks = manifest.get("tracks", {})
		moods = manifest.get("moods", {})
		_rng = rng if rng != null else RandomNumberGenerator.new()

	func pool(mood: String) -> Array:
		var seen := {}
		var m: String = mood
		while m != "" and not seen.has(m):
			seen[m] = true
			var out: Array = []
			for k in moods.get(m, []):
				var t = tracks.get(k, null)
				if t is Dictionary and str(t.get("id", "")) != "":
					out.append(k)
			if not out.is_empty():
				return out
			m = str(FALLBACK.get(m, ""))
		return []

	func next(mood: String) -> String:
		var p := pool(mood)
		if p.is_empty():
			return ""
		var pick := ""
		if mood == "title" and not bool(_opened.get(mood, false)):
			_opened[mood] = true
			pick = str(p[0])
		else:
			var keep := mini(HISTORY, p.size() / 2)
			var recent := {}
			var i := _history.size() - 1
			var kept := 0
			while i >= 0 and kept < keep:
				recent[_history[i]] = true
				i -= 1
				kept += 1
			var fresh: Array = []
			for k in p:
				if not recent.has(k):
					fresh.append(k)
			if fresh.is_empty():
				fresh = p
			pick = str(fresh[_rng.randi_range(0, fresh.size() - 1)])
		_history.append(pick)
		if _history.size() > 32:
			_history.pop_front()
		return pick

	func after(mood: String) -> String:
		return str(AFTER.get(mood, mood))


func _ready() -> void:
	if not _ready_ok:
		setup()


func setup() -> void:
	if _ready_ok:
		return
	_rng.randomize()
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_streams()
	_make_voices()
	_make_music_players()
	_build_playlist()
	_ready_ok = true
	set_process(true)


func set_player_id(id: int) -> void:
	player_id = id


func clear_logs() -> void:
	play_log.clear()
	blocked_log.clear()
	last_reason = ""
	last_file = ""
	last_canonical = ""


func set_clock_ms(ms: int) -> void:
	clock_ms = ms


func advance_ms(ms: int) -> void:
	if clock_ms < 0:
		clock_ms = _now_ms()
	clock_ms += ms
	tick(float(ms) / 1000.0)


func _now_ms() -> int:
	return clock_ms if clock_ms >= 0 else Time.get_ticks_msec()


func _now_s() -> float:
	return float(_now_ms()) / 1000.0


func is_gap(name: String) -> bool:
	var n := resolve(name)
	if n in GAPS or name in GAPS:
		return true
	if name == "soundtrack.*" or name.begins_with("soundtrack."):
		return soundtrack_count() == 0
	return (n in STANDIN_GAPS or name in STANDIN_GAPS) and not (n in upstream_events)


## Current gap list (names), for reports.
func gap_list() -> Array:
	var out: Array = GAPS.duplicate()
	for n in STANDIN_GAPS:
		if not (n in upstream_events):
			out.append(n)
	if soundtrack_count() == 0:
		out.append("soundtrack.*")
	return out


func has_sfx(sfx_name: String) -> bool:
	var n := resolve(sfx_name)
	return _streams.has(n) or EVENT_FILES.has(n)


func resolve(name: String) -> String:
	var n := name
	if ALIASES.has(n):
		n = str(ALIASES[n])
	if REPLACE.has(n):
		n = str(REPLACE[n])
	return n


func files_for(name: String, kind: String = "") -> PackedStringArray:
	var n := resolve(name)
	var out := PackedStringArray()
	var k := kind.to_lower()
	if k == "" and name in ["atom_launch", "hydrogen_launch", "mirv_launch", "icbm_launch", "atom_hit", "hydrogen_hit"]:
		k = name.split("_")[0]
	if n == "nuke_launch" and LAUNCH_BY_KIND.has(k):
		out.append(str(LAUNCH_BY_KIND[k]))
		return out
	if n == "nuke_explosion" and IMPACT_BY_KIND.has(k):
		out.append(str(IMPACT_BY_KIND[k]))
		return out
	for f in EVENT_FILES.get(n, []):
		out.append(str(f))
	return out


## Convenience: play({"event":"boat_launch", "who":1, ...}) or play("ui_click", {button=true}).
func play(event, opts: Dictionary = {}) -> bool:
	if event is Dictionary:
		opts = event
		event = str(opts.get("event", opts.get("name", "")))
	var vol := float(opts.get("volume_db", opts.get("vol_db", 0.0)))
	var jitter := float(opts.get("pitch_jitter", 0.04))
	var pitch := float(opts.get("pitch", -1.0))
	var who := int(opts.get("who", -1))
	var hits := bool(opts.get("hits_player", opts.get("hits", false)))
	var button := bool(opts.get("button_press", opts.get("button", false)))
	var kind := str(opts.get("kind", ""))
	return play_sfx(str(event), vol, jitter, pitch, who, hits, button, kind)


func play_ui_click(volume_db: float = 0.0, pitch_jitter: float = 0.02) -> bool:
	return play_sfx("ui_click", volume_db, pitch_jitter, -1.0, player_id, false, true, "")


func play_sfx(
		sfx_name: String,
		volume_db: float = 0.0,
		pitch_jitter: float = 0.04,
		pitch: float = -1.0,
		who: int = -1,
		hits_player: bool = false,
		button_press: bool = false,
		kind: String = ""
	) -> bool:
	if not _ready_ok:
		setup()
	var raw := sfx_name
	# Kind from well-known port aliases if not passed.
	if kind == "":
		if raw in ["atom_launch", "atom_hit"]:
			kind = "atom"
		elif raw in ["hydrogen_launch", "hydrogen_hit"]:
			kind = "hydrogen"
		elif raw in ["mirv_launch"]:
			kind = "mirv"
		elif raw in ["icbm_launch"]:
			kind = "icbm"
	var name := raw
	if ALIASES.has(name):
		name = str(ALIASES[name])
	# MIRV warheads: upstream skips the launch sting.
	if name == "nuke_launch" and kind == "warhead":
		return _block(raw, name, "warhead_launch_silent")
	name = str(REPLACE.get(name, name))
	var actor := player_id if who < 0 else who
	var gate := _gate(name, actor, hits_player, button_press)
	if gate != "":
		return _block(raw, name, gate)
	if _in_match_hush(name):
		return _block(raw, name, "match_start_hush")
	if not _streams.has(name):
		return _block(raw, name, "no_stream")
	var now := _now_ms()
	if COOLDOWNS.has(name):
		var cd: Array = COOLDOWNS[name]
		var last_full := int(_last_full_ms.get(name, -100000000))
		if now - last_full < int(cd[0]):
			var fallback := str(cd[1])
			if fallback != "" and fallback != name:
				return play_sfx(fallback, volume_db, pitch_jitter, pitch, actor, hits_player, button_press, kind)
			return _block(raw, name, "cooldown")
		_last_full_ms[name] = now
	else:
		var gap := int(THROTTLE_MS.get(name, DEFAULT_THROTTLE_MS))
		var last := int(_last_start_ms.get(name, -100000000))
		if now - last < gap:
			return _block(raw, name, "throttle")
	_last_start_ms[name] = now
	var voice = _pick_voice(name)
	if voice == null:
		return _block(raw, name, "no_voice")
	var streams: Array = _streams[name]
	var stream: AudioStream = streams[_rng.randi_range(0, streams.size() - 1)]
	var fname := _file_for_kind(name, kind, stream)
	var p: AudioStreamPlayer = voice["player"]
	p.stop()
	p.stream = stream
	p.volume_db = sfx_volume_db + volume_db + float(TRIM_DB.get(name, 0.0))
	if pitch > 0.0:
		p.pitch_scale = clampf(pitch, 0.25, 4.0)
	elif pitch_jitter > 0.0:
		p.pitch_scale = clampf(1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter), 0.25, 4.0)
	else:
		p.pitch_scale = 1.0
	if p.is_inside_tree():
		p.play()
	voice["started"] = now
	if HUSH_POPS.has(name):
		_pop_hush_until = maxf(_pop_hush_until, _now_s() + float(HUSH_POPS[name]))
	if AUTO_DUCK.has(name):
		var d: Array = AUTO_DUCK[name]
		duck_music(float(d[0]), float(d[1]))
	last_reason = "play"
	last_file = fname
	last_canonical = name
	var rec := {
		"event": raw, "canonical": name, "file": fname, "vol_db": p.volume_db,
		"pitch": p.pitch_scale, "who": actor, "hits_player": hits_player,
		"kind": kind, "reason": "play",
	}
	play_log.append(rec)
	sfx_played.emit(raw, name, fname)
	return true


func _file_for_kind(name: String, kind: String, stream: AudioStream) -> String:
	if name in upstream_events:
		return "upstream/%s.wav" % name
	var files := files_for(name, kind)
	if files.size() > 0:
		return files[0]
	if stream != null and stream.has_meta("sfx_file"):
		return str(stream.get_meta("sfx_file"))
	return str(stream.resource_path.get_file()) if stream != null else name


func _block(raw: String, name: String, reason: String) -> bool:
	last_reason = reason
	last_canonical = name
	last_file = ""
	var rec := {"event": raw, "canonical": name, "reason": reason}
	blocked_log.append(rec)
	sfx_blocked.emit(raw, name, reason)
	return false


func _gate(name: String, who: int, hits_player: bool, button_press: bool) -> String:
	if name == "ui_click" and not button_press:
		return "click_not_button"
	if name in GATE_NUKE:
		return ""
	if name in GATE_NUKE_IF_HIT:
		return "" if hits_player or who == player_id else "nuke_alarm_not_player"
	if name in GATE_UI:
		return ""
	if who == player_id or hits_player:
		return ""
	return "gated_ai"


func _in_match_hush(name: String) -> bool:
	if _match_t0_ms < 0:
		return false
	if name not in MATCH_START_HUSH_EVENTS:
		return false
	return _now_ms() - _match_t0_ms < MATCH_START_HUSH_MS


func begin_match() -> void:
	_match_t0_ms = _now_ms()
	# Reset sting cooldowns so a real mid-match event is not eaten by a hushed start attempt.
	for ev in MATCH_START_HUSH_EVENTS:
		_last_full_ms.erase(ev)
		_last_start_ms.erase(ev)


func end_match() -> void:
	_match_t0_ms = -1


func match_hush_active() -> bool:
	return _match_t0_ms >= 0 and _now_ms() - _match_t0_ms < MATCH_START_HUSH_MS


# ---------------------------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------------------------

func set_music_mood(mood: String) -> void:
	if not _ready_ok:
		setup()
	if mood == _requested_mood:
		return
	var old := _requested_mood
	_requested_mood = mood
	if _playlist == null or _playlist.pool(mood).is_empty():
		# no soundtrack on disk: the clean bed for every mood (war -> calm keeps the playing bed)
		if old == "war" and mood == "calm" and _current != null and _current.playing:
			return
		play_theme("bed")
		return
	_pool_mood = mood
	_next_key = ""
	if old == "war" and mood == "calm" and _track != "":
		return # the battle track plays out; the next one is calm
	var key := _playlist.next(mood)
	if key != "":
		_start_track(key, WAR_FADE_S if mood == "war" else MOOD_FADE_S)


## Soundtrack root: <upstream_root>music/<key>.ogg
func soundtrack_root() -> String:
	return upstream_root + "music/"


func soundtrack_count() -> int:
	return 0 if _playlist == null else _playlist.tracks.size()


func current_track() -> String:
	return _track


func _build_playlist() -> void:
	var tracks := {}
	for k in SOUNDTRACK_TRACKS:
		var path := soundtrack_root() + str(k) + ".ogg"
		if FileAccess.file_exists(ProjectSettings.globalize_path(path)) or FileAccess.file_exists(path):
			tracks[k] = {"id": path, "length": float(SOUNDTRACK_TRACKS[k][0]), "title": str(SOUNDTRACK_TRACKS[k][1])}
	_playlist = Playlist.new({"tracks": tracks, "moods": SOUNDTRACK_MOODS}, _rng) if not tracks.is_empty() else null


func _track_stream(key: String) -> AudioStream:
	if _track_streams.has(key):
		return _track_streams[key]
	var path: String = str(_playlist.tracks[key].id)
	var s: AudioStream = null
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		s = AudioStreamOggVorbis.load_from_file(abs_path)
	if s == null:
		var imp = load(path) if ResourceLoader.exists(path) else null
		if imp is AudioStream:
			s = imp
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	if s != null:
		_track_streams[key] = s
	return s


func _start_track(key: String, fade_s: float) -> void:
	if _playlist == null or not _playlist.tracks.has(key):
		return
	var s := _track_stream(key)
	if s == null:
		# unreadable track: forget it for this session (upstream TRACK_LOAD_TIMEOUT_S skip), try another
		_playlist.tracks.erase(key)
		var k2 := _playlist.next(_pool_mood)
		if k2 != "" and _playlist.tracks.has(k2):
			_start_track(k2, fade_s)
		else:
			_track = ""
			play_theme("bed")
		return
	_track = key
	_track_len = float(_playlist.tracks[key].length)
	_current_theme = "track:" + key
	# keep only the playing track (and the next one, below) decoded
	for k in _track_streams.keys():
		if k != key:
			_track_streams.erase(k)
	_crossfade_to(s, fade_s, false, str(_playlist.tracks[key].id))
	var m := _playlist.after(_pool_mood)
	var nk := _playlist.next(m)
	_next_mood = m
	_next_key = nk
	if nk != "" and nk != key:
		_track_stream(nk) # preload the next one only (upstream)


## The playing track is ending: the next one (victory / defeat give way to their AFTER mood).
func _advance() -> void:
	if _playlist == null:
		return
	_pool_mood = _playlist.after(_pool_mood)
	var key := _next_key if _next_key != "" and _next_mood == _pool_mood else _playlist.next(_pool_mood)
	_next_key = ""
	if key != "":
		_start_track(key, TRACK_OVERLAP_S)
	else:
		_track = ""


func _track_tick() -> void:
	if _track == "" or _current == null:
		return
	if bool(_toggle_paused.get(_current, false)):
		return
	if not _current.playing:
		if _current.is_inside_tree() and _current.stream != null:
			_advance() # ended before the overlap started the next one
		return
	var len := _current.stream.get_length() if _current.stream != null else 0.0
	if len <= 0.0:
		len = _track_len
	if len > TRACK_OVERLAP_S and _current.get_playback_position() >= len - TRACK_OVERLAP_S:
		_advance()


func music_mood() -> String:
	return _requested_mood


func update_mood(input: Dictionary, now_s: float = -1.0) -> String:
	var t := now_s if now_s >= 0.0 else _now_s()
	var m := _mood.mood(input, t)
	set_music_mood(m)
	return m


func new_music_mood() -> MusicMood:
	return MusicMood.new()


func new_playlist(manifest: Dictionary, rng: RandomNumberGenerator = null) -> Playlist:
	return Playlist.new(manifest, rng)


func play_theme(theme_name: String, crossfade_s: float = -1.0) -> void:
	if not _ready_ok:
		setup()
	if _music_stream == null or _music_a == null:
		return
	# Looping themes (menu / war) were never shipped: every theme is the clean bed. Never restart a
	# playing bed; never touch rejected/.
	_track = ""
	_next_key = ""
	if _current != null and _active(_current) and str(_current.get_meta("music_file", "")) == MUSIC_FILE:
		_current_theme = theme_name
		return
	_current_theme = theme_name
	_crossfade_to(_music_stream, CROSSFADE_S if crossfade_s < 0.0 else crossfade_s, true, MUSIC_FILE)


func current_theme() -> String:
	return _current_theme


func current_music_file() -> String:
	if _current != null:
		return str(_current.get_meta("music_file", ""))
	return ""


func music_is_rejected() -> bool:
	var f := current_music_file()
	return f.find("rejected") >= 0


func is_music_playing() -> bool:
	return _current != null and _active(_current)


func stop_music(fade_s: float = 1.0) -> void:
	if _current == null:
		return
	if _outgoing != null:
		_outgoing.stop()
		_toggle_paused.erase(_outgoing)
	_outgoing = _current
	_current = null
	_current_theme = ""
	_requested_mood = ""
	_track = ""
	_next_key = ""
	_fade_len = maxf(0.01, fade_s)
	_fade_t = 0.0


func set_music_enabled(on: bool) -> void:
	if on == _music_on:
		return
	_music_on = on
	if on:
		for p in _toggle_paused.keys():
			if p is AudioStreamPlayer:
				p.stream_paused = false
		_toggle_paused.clear()
		if _current == null:
			var m := _requested_mood
			_requested_mood = ""
			if _playlist != null and m != "":
				set_music_mood(m)
			elif _playlist != null:
				set_music_mood("title")
			else:
				play_theme(m if m != "" else "bed")
	music_enabled_changed.emit(on)


func is_music_enabled() -> bool:
	return _music_on


func toggle_music() -> bool:
	set_music_enabled(not _music_on)
	return _music_on


static func level_gain(v: float) -> float:
	var c := clampf(v, 0.0, 1.0)
	return c * c


func set_music_volume(v: float, _save: bool = false) -> void:
	_music_level = clampf(v, 0.0, 1.0)
	_apply_music_volume()


func music_volume() -> float:
	return _music_level


func set_pops_enabled(on: bool) -> void:
	if on == _pops_on:
		return
	_pops_on = on
	if not on:
		_pop_debt = 0.0
		_pop_speed = 0.0
		_pop_heat = 0.0
	pops_enabled_changed.emit(on)


func is_pops_enabled() -> bool:
	return _pops_on


func duck_music(amount_db: float, seconds: float) -> void:
	var target := -absf(amount_db)
	if _duck_hold_s > 0.0:
		_duck_target_db = minf(_duck_target_db, target)
		_duck_hold_s = maxf(_duck_hold_s, seconds)
	else:
		_duck_target_db = target
		_duck_hold_s = seconds


func duck_db() -> float:
	return _duck_db


func duck_hold_s() -> float:
	return _duck_hold_s


# ---------------------------------------------------------------------------------------------
# Border pops
# ---------------------------------------------------------------------------------------------

static func pop_rate(speed: float) -> float:
	if speed <= POP_SLOW:
		return POP_RATE_MIN * maxf(speed, 0.0) / POP_SLOW
	var k := minf(log(speed / POP_SLOW) / log(POP_FAST / POP_SLOW), 1.0)
	return POP_RATE_MIN + (POP_RATE_MAX - POP_RATE_MIN) * pow(k, POP_CURVE)


static func pop_pitch(heat: float) -> float:
	return POP_PITCH_MIN + (POP_PITCH_MAX - POP_PITCH_MIN) * clampf(heat, 0.0, 1.0)


func pop(tiles: float, progress: float = 0.0) -> int:
	if tiles <= 0.0 or not _pops_on or not _streams.has("expand_pop"):
		return 0
	var now := _now_s()
	var dt := clampf(now - _pop_last, 0.1, 3.0)
	_pop_last = now
	_pop_speed += (tiles / dt - _pop_speed) * (1.0 - exp(-dt / POP_SMOOTH_S))
	var speed := _pop_speed
	var per := (POP_SLOW / POP_RATE_MIN) if speed <= POP_SLOW else speed / pop_rate(speed)
	_pop_debt = minf(_pop_debt + tiles, maxf(POP_BIG, per * 2.0))
	if _pop_debt < per:
		return 0
	var n := mini(int(_pop_debt / per), POP_PER_BATCH)
	var bite := _pop_debt
	_pop_debt = minf(_pop_debt - float(n) * per, per)
	var quiet := now - _pop_run_last
	_pop_run_last = now
	if quiet <= POP_RUN_GAP_S:
		_pop_heat = minf(1.0, _pop_heat + quiet / POP_WARM_S)
	else:
		_pop_heat = maxf(0.0, _pop_heat - (quiet - POP_RUN_GAP_S) / POP_COOL_S)
	var lift := 1.0 + POP_PROGRESS_LIFT * clampf(progress, 0.0, 1.0)
	var pitch := pop_pitch(_pop_heat) * lift
	var db := POP_DB_MIN + (POP_DB_MAX - POP_DB_MIN) * sqrt(clampf(bite / POP_BIG, 0.0, 1.0))
	_strike_pop(db, pitch)
	if n >= 2:
		_pending_second_pop = POP_SECOND_S
		_pending_pop_pitch = pitch
		_pending_pop_db = db
	return n


func pop_once() -> void:
	if not _pops_on:
		return
	play_sfx("expand_pop", POP_DB_MAX, 0.0, 1.0, player_id, false, false, "")


func _strike_pop(db: float, pitch: float) -> void:
	if _now_s() < _pop_hush_until:
		return
	var j := 1.0 + _rng.randf_range(-POP_JITTER, POP_JITTER)
	play_sfx("expand_pop", db, 0.0, pitch * j, player_id, false, false, "")


# ---------------------------------------------------------------------------------------------
# Voices / tick
# ---------------------------------------------------------------------------------------------

func _pick_voice(sfx_name: String) -> Variant:
	var pool: Array = _pool.get(sfx_name, [])
	if pool.is_empty():
		return null
	var limit := int(MAX_SAME.get(sfx_name, DEFAULT_MAX_SAME))
	var same := 0
	var oldest_same = null
	var idle = null
	for v in pool:
		var p: AudioStreamPlayer = v["player"]
		if p.playing:
			same += 1
			if oldest_same == null or int(v["started"]) < int(oldest_same["started"]):
				oldest_same = v
		elif idle == null:
			idle = v
	if (same >= limit or idle == null) and oldest_same != null:
		return oldest_same
	var total := 0
	var victim = null
	var victim_prio := 99
	for v in _voices:
		if v["player"].playing:
			total += 1
			var prio := int(PRIORITY.get(str(v["name"]), 1))
			if prio < victim_prio or (prio == victim_prio and victim != null and int(v["started"]) < int(victim["started"])):
				victim = v
				victim_prio = prio
	if total >= VOICE_COUNT and victim != null:
		if victim_prio > int(PRIORITY.get(sfx_name, 1)):
			return null
		victim["player"].stop()
	return idle


func _process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if dt < 0.0:
		return
	if _pending_second_pop >= 0.0:
		_pending_second_pop -= dt
		if _pending_second_pop <= 0.0:
			_pending_second_pop = -1.0
			_strike_pop(_pending_pop_db, _pending_pop_pitch)
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + dt / maxf(0.01, _fade_len))
		if _fade_t >= 1.0 and _outgoing != null:
			_outgoing.stop()
			_toggle_paused.erase(_outgoing)
			_outgoing = null
	if _duck_hold_s > 0.0:
		_duck_hold_s -= dt
		_duck_db = _move_toward(_duck_db, _duck_target_db, DUCK_ATTACK_DB_PER_S * dt)
	else:
		_duck_target_db = 0.0
		_duck_db = _move_toward(_duck_db, 0.0, DUCK_RELEASE_DB_PER_S * dt)
	var target := 1.0 if _music_on else 0.0
	_master_gain = _move_toward(_master_gain, target, dt / TOGGLE_FADE_S)
	_apply_music_volume()
	_track_tick()


static func _move_toward(from: float, to: float, delta: float) -> float:
	if absf(to - from) <= delta:
		return to
	return from + signf(to - from) * delta


func _apply_music_volume() -> void:
	var g_in := sin(_fade_t * PI * 0.5) * _master_gain
	var g_out := cos(_fade_t * PI * 0.5) * _master_gain
	if _current != null:
		_current.volume_db = _gain_db(g_in)
	if _outgoing != null:
		_outgoing.volume_db = _gain_db(g_out)
	if not _music_on and _master_gain <= 0.0:
		_pause_silent(_music_a)
		_pause_silent(_music_b)


func _gain_db(g: float) -> float:
	if g <= 0.0005:
		return SILENT_DB
	return linear_to_db(g) + music_volume_db + _duck_db + linear_to_db(maxf(0.0001, level_gain(_music_level)))


func _pause_silent(p: AudioStreamPlayer) -> void:
	if p != null and p.playing:
		p.stream_paused = true
		_toggle_paused[p] = true


func _active(s: AudioStreamPlayer) -> bool:
	return s.playing or bool(_toggle_paused.get(s, false))


func _crossfade_to(stream: AudioStream, fade_s: float, looped: bool, file: String = MUSIC_FILE) -> void:
	var incoming: AudioStreamPlayer = _music_b if _current == _music_a else _music_a
	incoming.stop()
	_toggle_paused.erase(incoming)
	_outgoing = _current if _current != null and _active(_current) else null
	_current = incoming
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
		var frame := 2 * (2 if wav.stereo else 1)
		wav.loop_begin = 0
		if frame > 0:
			wav.loop_end = int(wav.data.size() / frame)
	incoming.stream = stream
	incoming.set_meta("music_file", file)
	incoming.volume_db = SILENT_DB
	if incoming.is_inside_tree():
		incoming.play()
	if _master_gain <= 0.0 and not _music_on:
		incoming.stream_paused = true
		_toggle_paused[incoming] = true
	_fade_len = maxf(0.01, fade_s)
	_fade_t = 0.0
	_apply_music_volume()


func _make_music_players() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_a.name = "MusicA"
	_music_a.bus = "Music"
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.name = "MusicB"
	_music_b.bus = "Music"
	add_child(_music_b)
	_music_stream = _load_audio(MUSIC_FILE)
	if _music_stream == null:
		push_warning("Clean music missing (%s). Rejected themes are not used as a fallback." % MUSIC_FILE)


func _make_voices() -> void:
	for name in EVENT_FILES.keys():
		if not _streams.has(name):
			continue
		var copies := int(MAX_SAME.get(name, DEFAULT_MAX_SAME))
		var pool: Array = []
		for i in copies:
			var s := AudioStreamPlayer.new()
			s.name = "Sfx_%s_%d" % [name, i]
			s.bus = "SFX"
			add_child(s)
			var v := {"player": s, "name": name, "started": 0}
			pool.append(v)
			_voices.append(v)
		_pool[name] = pool


var _file_cache: Dictionary = {} # filename -> AudioStream (one stream per wav)

func _load_streams() -> void:
	_missing.clear()
	_file_cache.clear()
	upstream_events.clear()
	for name in EVENT_FILES.keys():
		var up_path := upstream_root + str(name) + ".wav"
		var up: AudioStream = null
		if FileAccess.file_exists(ProjectSettings.globalize_path(up_path)) or FileAccess.file_exists(up_path):
			up = _load_audio(up_path)
		if up != null:
			up.set_meta("sfx_file", "upstream/" + str(name) + ".wav")
			_streams[name] = [up]
			upstream_events.append(name)
			continue
		var arr: Array = []
		var seen := {}
		for fn in EVENT_FILES[name]:
			if seen.has(fn):
				continue
			seen[fn] = true
			var s: AudioStream = _file_cache.get(fn, null)
			if s == null:
				s = _load_audio(SFX_ROOT + str(fn))
				if s != null:
					s.set_meta("sfx_file", str(fn))
					_file_cache[fn] = s
			if s != null:
				arr.append(s)
			else:
				_missing.append(fn)
		if not arr.is_empty():
			_streams[name] = arr
	if _missing.size() > 0:
		push_warning("AudioDirector missing sounds: %s" % [_missing])


func missing_files() -> Array:
	return _missing.duplicate()


func loaded_event_count() -> int:
	return _streams.size()


func _ensure_bus(nm: String) -> int:
	var idx := AudioServer.get_bus_index(nm)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, nm)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _load_audio(path: String) -> AudioStream:
	var abs_path := ProjectSettings.globalize_path(path)
	var bytes := PackedByteArray()
	if FileAccess.file_exists(abs_path):
		bytes = FileAccess.get_file_as_bytes(abs_path)
	elif FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty() and path.get_extension().to_lower() == "wav":
		var wav := _wav_stream(bytes)
		if wav != null and wav.get_length() > 0.01:
			return wav
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
