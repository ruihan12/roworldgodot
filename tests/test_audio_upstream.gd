# Headless check of audio_upstream/audio_director.gd:
#   godot --headless --path . -s res://tests/test_audio_upstream.gd
extends SceneTree

const AD := preload("res://audio_upstream/audio_director.gd")
const PLAYER := 1
const AI := 2

var fails := 0
var checks := 0

func _initialize() -> void:
	var audio = AD.new()
	# Stand-in checks run against an empty upstream dir; the real sounds/upstream/ set is checked below.
	DirAccess.make_dir_recursive_absolute("user://upstream_empty/")
	audio.upstream_root = "user://upstream_empty/"
	root.add_child(audio)
	audio.setup()
	audio.set_player_id(PLAYER)
	audio.set_clock_ms(100000)
	audio.set_music_enabled(true)
	audio.play_theme("bed")

	_check(audio.missing_files().is_empty(), "all mapped play/ wavs loaded (%s)" % [audio.missing_files()])
	_check(audio.loaded_event_count() >= 40, "loaded_event_count=%d" % audio.loaded_event_count())
	_check(audio.has_sfx("boat_launch") and audio.has_sfx("transport") and audio.has_sfx("ui_click"), "core has_sfx")
	_check(audio.has_sfx("nuke_launch") and audio.has_sfx("atom_launch") and audio.has_sfx("icbm_launch"), "nuke aliases registered")
	_check(audio.current_music_file() == "res://sounds/music/frontline_bed.wav", "music file is frontline_bed.wav (got %s)" % audio.current_music_file())
	_check(not audio.music_is_rejected(), "music is not a rejected theme")
	_check(audio.resolve("click") == "ui_click", "alias click -> ui_click")
	_check(audio.resolve("attack") == "order_ack", "REPLACE attack_launch -> order_ack (via attack)")
	_check(audio.resolve("attack_launch") == "order_ack", "REPLACE attack_launch -> order_ack")
	_check(audio.resolve("transport") == "boat_launch", "alias transport -> boat_launch")
	_check(audio.resolve("conquered") == "conquer", "alias conquered -> conquer")
	_check(audio.resolve("nuke_warning") == "nuke_alarm", "alias nuke_warning -> nuke_alarm")
	_check("slider.wav" in audio.files_for("expand_pop"), "expand_pop stand-in file")
	_check(audio.is_gap("expand_pop") and audio.is_gap("shell_fire") and audio.is_gap("soundtrack.*"), "gaps flagged")
	_check(not audio.is_gap("boat_launch") and not audio.is_gap("ui_click") and not audio.is_gap("nuke_alarm"), "real assets are not gaps")

	# --- gating: player vs AI ---
	audio.clear_logs()
	_ok(audio, audio.play_sfx("boat_launch", 0.0, 0.0, 1.0, PLAYER), "play", "player boat plays")
	_check(audio.last_file == "transport-ship.wav", "player boat file=%s" % audio.last_file)

	audio.clear_logs()
	_ok(audio, audio.play_sfx("boat_launch", 0.0, 0.0, 1.0, AI), "gated_ai", "AI boat blocked")

	audio.clear_logs()
	_ok(audio, audio.play_sfx("build_city", 0.0, 0.0, 1.0, AI), "gated_ai", "AI build blocked")
	_ok(audio, audio.play_sfx("build", 0.0, 0.0, 1.0, AI), "gated_ai", "AI generic build blocked")
	_ok(audio, audio.play_sfx("warship", 0.0, 0.0, 1.0, AI), "gated_ai", "AI warship build blocked")

	audio.clear_logs()
	_ok(audio, audio.play_sfx("conquer", 0.0, 0.0, 1.0, AI), "gated_ai", "AI conquer blocked")

	audio.clear_logs()
	_ok(audio, audio.play_sfx("build_factory", 0.0, 0.0, 1.0, PLAYER), "play", "player factory plays")
	_check(audio.last_file == "build-factory.wav", "player factory file=%s" % audio.last_file)

	# --- nukes: AI launch + impact always play; alarm only if it hits the player ---
	audio.clear_logs()
	_ok(audio, audio.play_sfx("atom_launch", -8.0, 0.0, 1.0, AI), "play", "AI atom launch plays")
	_check(audio.last_file == "atom-launch.wav", "AI atom launch file=%s" % audio.last_file)
	audio.advance_ms(200)
	_ok(audio, audio.play_sfx("hydrogen_launch", -8.0, 0.0, 1.0, AI, false, false, "hydrogen"), "play", "AI hydrogen launch plays")
	# throttle is 150ms; advance so the next launch is a new event
	audio.advance_ms(200)
	_ok(audio, audio.play_sfx("mirv_launch", -8.0, 0.0, 1.0, AI, false, false, "mirv"), "play", "AI MIRV launch plays")
	_check(audio.last_file == "mirv-launch.wav", "AI MIRV launch file=%s" % audio.last_file)
	audio.advance_ms(200)
	_ok(audio, audio.play_sfx("icbm_launch", -8.0, 0.0, 1.0, AI, false, false, "icbm"), "play", "AI ICBM launch plays")
	_check(audio.last_file == "hydrogen-launch.wav", "ICBM launch file=%s" % audio.last_file)

	audio.advance_ms(200)
	_ok(audio, audio.play_sfx("atom_hit", -8.0, 0.0, 1.0, AI), "play", "AI atom impact plays")
	audio.advance_ms(200)
	_ok(audio, audio.play_sfx("hydrogen_hit", 0.0, 0.0, 1.0, AI, true, false, "hydrogen"), "play", "AI H-bomb hitting player plays")
	_check(audio.last_file == "hydrogen-hit.wav", "H impact file=%s" % audio.last_file)

	audio.clear_logs()
	_ok(audio, audio.play_sfx("nuke_alarm", 0.0, 0.0, 1.0, AI, false), "nuke_alarm_not_player", "AI alarm at someone else blocked")
	_ok(audio, audio.play_sfx("nuke_warning", 0.0, 0.0, 1.0, AI, true), "play", "AI alarm at the player plays")
	_check(audio.last_file == "nuke-warning.wav", "alarm file=%s" % audio.last_file)

	# warhead launches stay silent (MIRV split)
	audio.clear_logs()
	_ok(audio, audio.play_sfx("nuke_launch", 0.0, 0.0, 1.0, PLAYER, false, false, "warhead"), "warhead_launch_silent", "MIRV warhead launch silent")

	# --- UI click only on a real button press ---
	audio.clear_logs()
	_ok(audio, audio.play_sfx("ui_click", 0.0, 0.0, 1.0, PLAYER, false, false), "click_not_button", "ui_click without button flag blocked")
	_ok(audio, audio.play_sfx("click", 0.0, 0.0, 1.0, PLAYER, false, false), "click_not_button", "click alias without button flag blocked")
	_ok(audio, audio.play_ui_click(0.0, 0.0), "play", "play_ui_click allowed")
	audio.advance_ms(50)
	_ok(audio, audio.play_sfx("ui_click", 0.0, 0.0, 1.0, PLAYER, false, true), "play", "ui_click with button_press allowed")

	audio.clear_logs()
	_ok(audio, audio.play_sfx("ui_hover", -12.0, 0.0, 1.0, PLAYER), "play", "hover is its own event")
	_check(audio.last_canonical == "ui_hover", "hover canonical=%s" % audio.last_canonical)
	_check(audio.last_file != "click.wav", "hover does not play click.wav (file=%s)" % audio.last_file)
	_ok(audio, audio.play_sfx("slider", 0.0, 0.0, 1.0, PLAYER), "play", "slider is not a click")
	_check(audio.last_canonical == "slider", "slider canonical=%s" % audio.last_canonical)

	# throttle: two real clicks 10ms apart, only the first plays
	audio.advance_ms(100)
	audio.clear_logs()
	_ok(audio, audio.play_ui_click(0.0, 0.0), "play", "first click plays")
	audio.advance_ms(10)
	_ok(audio, audio.play_ui_click(0.0, 0.0), "throttle", "second click 10ms later throttled (30ms)")
	audio.advance_ms(30)
	_ok(audio, audio.play_ui_click(0.0, 0.0), "play", "third click after throttle window plays")

	# --- boat cooldown fallback (outside match-start hush) ---
	audio.end_match()
	audio.advance_ms(5000)
	audio.clear_logs()
	_ok(audio, audio.play_sfx("boat_launch", 0.0, 0.0, 1.0, PLAYER), "play", "first boat (no hush) plays")
	_check(audio.last_canonical == "boat_launch", "first boat canonical")
	audio.advance_ms(100)
	_ok(audio, audio.play_sfx("boat_launch", 0.0, 0.0, 1.0, PLAYER), "play", "second boat inside 1500ms falls back to order_ack")
	_check(audio.last_canonical == "order_ack", "boat cooldown fallback canonical=%s" % audio.last_canonical)
	_check(audio.last_file == "order.wav", "boat cooldown fallback file=%s" % audio.last_file)

	# --- match-start hush: boat and conquer silent (no order_ack fallback either) ---
	audio.begin_match()
	audio.clear_logs()
	_ok(audio, audio.play_sfx("transport", 0.0, 0.0, 1.0, PLAYER), "match_start_hush", "player boat hushed at match start")
	_ok(audio, audio.play_sfx("conquered", 0.0, 0.0, 1.0, PLAYER), "match_start_hush", "player conquer hushed at match start")
	_ok(audio, audio.play_sfx("boat_launch", 0.0, 0.0, 1.0, AI), "gated_ai", "AI boat still gated during hush")
	# UI and nukes are not hushed
	_ok(audio, audio.play_ui_click(0.0, 0.0), "play", "click still works during hush")
	audio.advance_ms(50)
	_ok(audio, audio.play_sfx("atom_launch", 0.0, 0.0, 1.0, AI), "play", "AI nuke launch still works during hush")
	_check(audio.match_hush_active(), "hush still active mid-window")

	audio.advance_ms(3000)
	_check(not audio.match_hush_active(), "hush ended after 3000ms")
	audio.clear_logs()
	_ok(audio, audio.play_sfx("transport", 0.0, 0.0, 1.0, PLAYER), "play", "player boat plays after hush")
	_ok(audio, audio.play_sfx("conquered", 0.0, 0.0, 1.0, PLAYER), "play", "player conquer plays after hush")
	_check(audio.last_file == "conquered.wav", "conquer file=%s" % audio.last_file)
	# conquer cooldown: silent fallback
	audio.advance_ms(100)
	_ok(audio, audio.play_sfx("conquered", 0.0, 0.0, 1.0, PLAYER), "cooldown", "second conquer inside 2500ms silent")

	# SAM: only when the player is involved
	audio.advance_ms(200)
	audio.clear_logs()
	_ok(audio, audio.play_sfx("sam_shoot", 0.0, 0.0, 1.0, AI, false), "gated_ai", "AI SAM vs AI bomb silent")
	_ok(audio, audio.play_sfx("sam_shoot", 0.0, 0.0, 1.0, AI, true), "play", "AI SAM vs player bomb plays")
	_ok(audio, audio.play_sfx("sam_hit", 0.0, 0.0, 1.0, PLAYER), "play", "player SAM intercept plays")

	# alliance involving the player
	audio.advance_ms(3000)
	audio.clear_logs()
	_ok(audio, audio.play_sfx("ally_accept", 0.0, 0.0, 1.0, PLAYER), "play", "alliance with player plays")
	_ok(audio, audio.play_sfx("alliance", 0.0, 0.0, 1.0, AI, false), "gated_ai", "AI-only alliance silent")
	_ok(audio, audio.play_sfx("ally_suggest", 0.0, 0.0, 1.0, AI, true), "play", "AI offer to player plays")

	# --- music mood state machine ---
	var mood = audio.new_music_mood()
	_check(mood.mood({"screen": "title", "waiting": false, "me": 1, "alive": true, "winner": 0, "fighting": false}, 0.0) == "title", "mood title")
	_check(mood.mood({"screen": "title", "waiting": true, "me": 1, "alive": true, "winner": 0, "fighting": false}, 0.0) == "wait", "mood wait")
	_check(mood.mood({"screen": "play", "waiting": false, "me": 1, "alive": true, "winner": 0, "fighting": false}, 10.0) == "calm", "mood calm")
	_check(mood.mood({"screen": "play", "waiting": false, "me": 1, "alive": true, "winner": 0, "fighting": true}, 20.0) == "war", "mood war on fight")
	_check(mood.mood({"screen": "play", "waiting": false, "me": 1, "alive": true, "winner": 0, "fighting": false}, 50.0) == "war", "mood war holds 40s")
	_check(mood.mood({"screen": "play", "waiting": false, "me": 1, "alive": true, "winner": 0, "fighting": false}, 61.0) == "calm", "mood returns to calm after hold")
	_check(mood.mood({"screen": "over", "waiting": false, "me": 1, "alive": false, "winner": 1, "fighting": false}, 80.0) == "victory", "mood victory")
	_check(mood.mood({"screen": "over", "waiting": false, "me": 1, "alive": false, "winner": 2, "fighting": false}, 80.0) == "defeat", "mood defeat")
	_check(mood.mood({"screen": "play", "waiting": false, "me": 0, "alive": true, "winner": 0, "fighting": true}, 90.0) == "calm", "spectator is calm")
	_check(AD.MusicMood.fighting(1, [{"attacker": 1, "target": 2}], []) == true, "fighting: player attack")
	_check(AD.MusicMood.fighting(1, [{"attacker": 2, "target": 3}], []) == false, "fighting: other war ignored")
	_check(AD.MusicMood.fighting(1, [], [{"owner": 2, "to_owner": 1}]) == true, "fighting: nuke at player")

	# playlist opener / no-repeat / after
	var pl = audio.new_playlist({
		"tracks": {
			"a": {"id": "res://a"}, "b": {"id": "res://b"}, "c": {"id": "res://c"},
			"d": {"id": "res://d"}, "e": {"id": "res://e"},
		},
		"moods": {"title": ["a", "b", "c", "d", "e"], "victory": ["c"], "defeat": []},
	})
	_check(pl.next("title") == "a", "playlist title opener is first track")
	_check(pl.after("victory") == "title" and pl.after("defeat") == "calm", "playlist AFTER")
	_check(pl.pool("defeat").size() == 5, "empty defeat falls back to calm then title")
	var seen: Dictionary = {}
	for _i in 8:
		seen[pl.next("title")] = true
	_check(seen.size() >= 4, "playlist shuffles through the title pool (got %s)" % [seen.keys()])

	# --- pop_rate curve (upstream numbers in the comment) ---
	_check(is_equal_approx(AD.pop_rate(0.0), 0.0), "pop_rate(0)=0")
	_check(is_equal_approx(AD.pop_rate(40.0), 2.0), "pop_rate(40)=2")
	_check(abs(AD.pop_rate(60.0) - 2.403) < 0.05, "pop_rate(60)~2.4 (got %.3f)" % AD.pop_rate(60.0))
	_check(abs(AD.pop_rate(100.0) - 4.047) < 0.08, "pop_rate(100)~4 (got %.3f)" % AD.pop_rate(100.0))
	_check(is_equal_approx(AD.pop_rate(600.0), 20.0), "pop_rate(600)=20")
	_check(is_equal_approx(AD.pop_pitch(0.0), 0.8) and is_equal_approx(AD.pop_pitch(1.0), 1.1), "pop_pitch ends")

	# pops are a player-only event (pop() always uses player_id)
	audio.advance_ms(1000)
	audio.clear_logs()
	var n_pops: int = audio.pop(80.0, 0.2)
	_check(n_pops >= 1, "pop() fired at least one expand_pop (n=%d)" % n_pops)
	_check(audio.play_log.size() >= 1 and audio.play_log[0]["canonical"] == "expand_pop", "pop plays expand_pop")

	# --- ducking ---
	audio.clear_logs()
	audio.play_sfx("nuke_explosion", 0.0, 0.0, 1.0, AI)
	_check(audio.duck_hold_s() >= 2.4, "nuke_explosion auto-ducks (hold=%.2f)" % audio.duck_hold_s())
	audio.tick(0.1)
	_check(audio.duck_db() < -1.0, "duck attacks toward -8 dB (db=%.2f)" % audio.duck_db())

	# music on/off does not load rejected themes
	audio.set_music_enabled(false)
	audio.tick(1.0)
	_check(not audio.music_is_rejected(), "toggle off still not rejected")
	audio.set_music_enabled(true)
	audio.play_theme("war")
	_check(audio.current_music_file() == "res://sounds/music/frontline_bed.wav", "war mood still uses the bed, not rejected war theme")

	# volume law
	_check(is_equal_approx(AD.level_gain(0.5), 0.25), "level_gain(0.5)=0.25")
	_check(is_equal_approx(AD.level_gain(0.0), 0.0) and is_equal_approx(AD.level_gain(1.0), 1.0), "level_gain ends")

	# upstream override: a wav at <upstream_root>/<event>.wav replaces the stand-in, gates unchanged
	_check(audio.upstream_events.is_empty(), "no upstream files on disk -> stand-ins (%s)" % [audio.upstream_events])
	var up_dir := "user://upstream_override/"
	DirAccess.make_dir_recursive_absolute(up_dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://sounds/play/order.wav"), ProjectSettings.globalize_path(up_dir + "boat_launch.wav"))
	var a2 = AD.new()
	a2.upstream_root = up_dir
	root.add_child(a2)
	a2.setup()
	a2.set_clock_ms(500000)
	_check("boat_launch" in a2.upstream_events, "upstream boat_launch.wav picked up")
	_ok(a2, a2.play_sfx("transport", 0.0, 0.0, 1.0, PLAYER), "play", "player boat plays upstream file")
	_check(a2.last_file == "upstream/boat_launch.wav", "file=%s" % a2.last_file)
	a2.advance_ms(5000)
	_ok(a2, a2.play_sfx("transport", 0.0, 0.0, 1.0, AI), "gated_ai", "AI boat still gated with upstream file")
	_check(a2.files_for("conquer").has("conquered.wav"), "events without upstream keep stand-in")

	# real RoWorld renders recovered from the Roblox cache (sounds/upstream/<event>.wav)
	var a3 = AD.new()
	root.add_child(a3)
	a3.setup()
	a3.set_clock_ms(500000)
	_check(a3.upstream_events.size() >= 62, "repo sounds/upstream/ loads all 62 RoWorld sfx (got %d)" % a3.upstream_events.size())
	_ok(a3, a3.play_sfx("transport", 0.0, 0.0, 1.0, PLAYER), "play", "player boat plays real upstream file")
	_check(a3.last_file == "upstream/boat_launch.wav", "real upstream file=%s" % a3.last_file)
	a3.advance_ms(5000)
	_ok(a3, a3.play_sfx("transport", 0.0, 0.0, 1.0, AI), "gated_ai", "AI boat still gated with real upstream files")

	# real RoWorld soundtrack (sounds/upstream/music/*.ogg) as upstream's Playlist; bed is the fallback
	_check(audio.soundtrack_count() == 0 and audio.is_gap("soundtrack.*"), "no soundtrack on disk -> soundtrack gap, bed fallback")
	_check(a3.soundtrack_count() == 33, "33 soundtrack tracks found (got %d)" % a3.soundtrack_count())
	_check(not a3.is_gap("soundtrack.*") and not a3.is_gap("expand_pop") and not a3.is_gap("shell_fire"), "real set: soundtrack and sfx are not gaps")
	_check(a3.gap_list() == ["music.menu", "music.war"], "real set gap list is only the menu/war themes (got %s)" % [a3.gap_list()])
	a3.set_music_enabled(true)
	a3.set_music_mood("title")
	_check(a3.current_track() == "glory_of_the_nation", "title opener is glory_of_the_nation (got %s)" % a3.current_track())
	_check(a3.current_music_file().ends_with("music/glory_of_the_nation.ogg") and not a3.music_is_rejected(), "track file %s" % a3.current_music_file())
	a3.set_music_mood("war")
	var wt: String = a3.current_track()
	_check(wt in AD.SOUNDTRACK_MOODS["war"], "war mood plays a war track (got %s)" % wt)
	a3.set_music_mood("calm")
	_check(a3.current_track() == wt, "war -> calm lets the battle track play out")
	a3._advance()
	_check(a3.current_track() in AD.SOUNDTRACK_MOODS["calm"], "next track after war is calm (got %s)" % a3.current_track())
	a3.set_music_mood("victory")
	_check(a3.current_track() == "glorious_fortress", "victory plays glorious_fortress")
	a3._advance()
	_check(a3.current_track() in AD.SOUNDTRACK_MOODS["title"], "after victory -> title pool (got %s)" % a3.current_track())
	a3.play_theme("war")
	_check(a3.current_music_file() == "res://sounds/music/frontline_bed.wav" and a3.current_track() == "", "play_theme falls back to the bed")

	print("AUDIO_UPSTREAM_TEST %s fails=%d checks=%d events_loaded=%d gaps=%d real_gaps=%s tracks=%d music=%s" % [
		"PASS" if fails == 0 else "FAIL", fails, checks, audio.loaded_event_count(), AD.GAPS.size(),
		a3.gap_list(), a3.soundtrack_count(), audio.current_music_file(),
	])
	quit(1 if fails else 0)


func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("OK    %s" % label)
	else:
		fails += 1
		print("FAIL  %s" % label)


func _ok(audio, played: bool, want_reason: String, label: String) -> void:
	var got := "play" if played else str(audio.last_reason)
	_check(got == want_reason, "%s (got %s)" % [label, got])
