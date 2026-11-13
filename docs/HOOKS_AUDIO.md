# Wiring `audio_upstream/audio_director.gd` into `main.gd`

Executor 1 (or the parent agent) should apply these snippets. This file does not edit `main.gd`. Event names and gates are defined in `audio_upstream/audio_director.gd` and documented in `docs/AUDIO_PORT.md`.

Once the director is the sole SFX path, the old `sfx()` pool in `main.gd` can be left unused or deleted. Until then, replace the body of `sfx()` so every existing call site goes through the director without renaming them all at once.

`PLAYER` is already `1` in `main.gd`. Existing call sites already pass `who=PLAYER` for the player's own actions and for things hitting the player, and they already skip AI boat / build / conquer. The director re-checks that, adds AI nuke play, the button-press click rule, and the match-start boat/conquer hush.

## 1. Create the director (in `_init_audio` / alongside current audio init)

```gdscript
const AudioDirector := preload("res://audio_upstream/audio_director.gd")
var audio: Node

func _init_audio() -> void:
	audio = AudioDirector.new()
	add_child(audio)
	audio.set_player_id(PLAYER)
	var cfg: Dictionary = save.get("settings", {})
	audio.set_music_enabled(bool(cfg.get("music_on", true)))
	audio.set_music_volume(float(cfg.get("vol_music", 0.5)), false)
	# Keep the existing Music/SFX bus sliders (_apply_volumes). The director
	# plays onto those buses; do not also start the old music_player.
	audio.set_music_mood("title")
	# optional: still call _apply_volumes() for Master / Music / SFX bus levels
	_apply_volumes()
```

Do not scan `res://sounds/music` and do not fall back to `sounds/rejected/` or `city.mp3`. The director only ever loads `res://sounds/music/frontline_bed.wav`.

## 2. Replace the body of `sfx()` (keeps every current call site)

```gdscript
func sfx(key: String, vol_db := 0.0, pitch_jitter := 0.04, who := PLAYER) -> void:
	if audio == null:
		return
	# Existing callers already pass who=PLAYER when the event is the player's
	# or hits the player. AI nuke keys still play (director GATE_NUKE).
	var hits := who == PLAYER
	# Only the Button.button_down hook should use "click". Treat that key as a
	# real button press; sliders must not call sfx("click").
	var button := key == "click"
	audio.play_sfx(key, vol_db, pitch_jitter, -1.0, who, hits, button)
```

That covers the call sites already in `main.gd`:

| site (function) | current call | director event | notes |
| --- | --- | --- | --- |
| structure captured by player | `sfx("ka_ching")` | `buy_spend` | already gated `o == PLAYER` |
| reinforce | `sfx("spawn")` | `spawn_confirm` | player only |
| `try_build` warship | `sfx("build_warship")` | `warship` | player only |
| `try_build` / upgrade | `sfx(BUILD_SFX.get(k, "build_city"))` | `build_city` / `_port` / `_factory` / `_defense` / `_sam` / `_silo` / `_station` | player only; AI stays muted |
| `launch_attack` | `sfx("order")` | `order_ack` | player only (`attack_launch` is replaced by this) |
| `_spawn_boat` | `sfx("transport")` | `boat_launch` | player only; **hushed 3 s after `begin_match()`** |
| nation eliminated | `sfx("conquered")` | `conquer` | already `last_by == PLAYER`; **hushed 3 s after `begin_match()`** |
| nuke launch | `sfx("mirv_launch" \| "hydrogen_launch" \| "atom_launch", 0 or -8, 0.04, o)` | `nuke_launch` + kind | any owner; keep the -8 dB for AI |
| nuke warning | `sfx("nuke_warning")` when `victim == PLAYER` | `nuke_alarm` | pass `hits_player=true` (the `who==PLAYER` trick in the wrapper does this) |
| nuke impact | `sfx("hydrogen_hit" \| "atom_hit", 0 or -8, 0.04, PLAYER if mine else ms.o)` | `nuke_explosion` + kind | any owner |
| warship shot / capture / duel | `sfx("warship_shot")` / `sfx("ka_ching")` when player involved | same | already gated |
| own warship sunk | `sfx("warship_lost")` | `ship_sink` | player only |
| `form_alliance` / `break_alliance` / `propose_alliance` | `ally_accept` / `ally_broken` / `ally_suggest` / `ally_decline` | `alliance` / `betrayal` / `ally_request` / `ally_decline` | already player-involved |
| `_wire_anims` `button_down` | `sfx("click", 0.0, 0.02)` | `ui_click` | this is a real button press |
| `_game_over` | `sfx("victory" if win else "defeat")` | same | also set the music mood (below) |

Do **not** add `sfx("click")` to slider `_value_changed` or to `mouse_entered`. Hover can later use `audio.play_sfx("ui_hover", -12.0, 0.03, -1.0, PLAYER)`.

## 3. Match start / end / menu music

When the deploy timer ends and `state` becomes `"play"` (today this also calls `_play_music()`):

```gdscript
state = "play"
audio.begin_match()
audio.set_music_mood("calm")
# optional, currently loaded but never played:
# audio.play_sfx("game_start")
```

`begin_match()` starts the 3000 ms boat/conquer hush. Call it once per match, not when the player only switches spawn tiles.

On `_game_over(win)`:

```gdscript
audio.end_match()
audio.set_music_mood("victory" if win else "defeat")
# existing: sfx("victory" if win else "defeat")
# do not start a different music file; the director ducks the bed under the sting
```

On `_to_menu()`:

```gdscript
audio.end_match()
audio.set_music_mood("title")
# audio.set_music_enabled(bool(save.settings.get("music_on", true)))
```

Settings music toggle (the MUSIC: ON/OFF button) should call `audio.set_music_enabled(on)` instead of `_play_music()` / `_stop_music()`. Volume sliders stay on the buses via `_apply_volumes()`; if you also want the director's squared music-gain law, call `audio.set_music_volume(vol_music, true)` when the music slider is released (not on every drag step).

Optional, each sim tick or HUD poll while `state == "play"` (40 s war hold is inside the director):

```gdscript
var fighting := false
for at in attacks:
	if at.a == PLAYER or at.t == PLAYER:
		fighting = true
		break
if not fighting:
	for ms in missiles:
		if ms.o == PLAYER or int(ms.get("tgt_o", -1)) == PLAYER:
			fighting = true
			break
audio.update_mood({
	"screen": "play" if state == "play" else ("over" if state == "over" else "title"),
	"waiting": false,
	"me": PLAYER,
	"alive": nations[PLAYER].alive,
	"winner": PLAYER if state == "over" and /* player won */ false else 0,
	"fighting": fighting,
})
```

## 4. ICBM and Mega / Scatter launches

The launch site already picks a key with something like:

```gdscript
var lk := "mirv_launch" if k == 9 else ("hydrogen_launch" if k in [8, 11] else "atom_launch")
sfx(lk, 0.0 if o == PLAYER else -8.0, 0.04, o)
```

Extend the same line for the ICBM slot (key `I`) and for mega/scatter if you want distinct files:

```gdscript
var lk := "mirv_launch" if k == 9 else ("hydrogen_launch" if k in [8, 11] else "atom_launch")
# ICBM (custom slot): uses hydrogen-launch.wav as the closest big-missile file
# if k == ICBM_KIND: lk = "icbm_launch"
sfx(lk, 0.0 if o == PLAYER else -8.0, 0.04, o)
if victim == PLAYER and o != PLAYER:
	sfx("nuke_warning")
```

MIRV **warhead** branches must not call `nuke_launch` again. If a future hook fires `play_sfx("nuke_launch", …, kind="warhead")`, the director drops it (`warhead_launch_silent`). Impacts of those warheads still use `atom_hit` / `nuke_explosion`.

## 5. New hooks not yet in `main.gd`

These exist upstream (`UIAdvisor`) and the director already implements them. Add only when the sim signals exist.

SAM fire / intercept (today `sim_ars.sam_resolve` has no SFX). Play only if the SAM owner or the missile owner is the player:

```gdscript
# when a SAM missile is launched
if sam_owner == PLAYER or missile_owner == PLAYER:
	sfx("sam_shoot", 0.0, 0.04, PLAYER)
# when it hits
if sam_owner == PLAYER or missile_owner == PLAYER:
	sfx("sam_hit", 0.0, 0.04, PLAYER)
# AI SAM vs AI bomb: do not call
```

Shell / air strike / slug (Arsenal munitions, not nukes):

```gdscript
# fire
if o == PLAYER or /* target tile is player's */ false:
	audio.play_sfx("shell_fire", -8.0 if o == PLAYER else -12.0, 0.08, -1.0, o, victim == PLAYER)
# hit
if o == PLAYER or victim == PLAYER:
	audio.play_sfx("shell_hit", -6.0 if o == PLAYER or victim == PLAYER else -11.0, 0.08, -1.0, o, victim == PLAYER)
```

Player land gained (border pops). After a batch of owner changes, count tiles that flipped to `PLAYER` during `state == "play"` (not during spawn pick):

```gdscript
if gained > 0 and state == "play":
	var land := maxi(land_count - fallout_count, 1)
	var progress := float(nations[PLAYER].land) / float(land) # / WIN_SHARE if you have it
	audio.pop(float(gained), progress)
```

Player is under a land attack (4 s cooldown is inside the director):

```gdscript
if at.t == PLAYER:
	audio.play_sfx("under_attack", 0.0, 0.04, -1.0, at.a, true)
```

## 6. What not to hook

- AI `try_build` / AI `_spawn_boat` / AI eliminations / AI-only alliances: do not call, or call with `who=AI` and let the director no-op.
- Slider drag, hover, or "the deploy timer ticked": not `ui_click`.
- Match start: do not play `transport` or `conquered` just because many tiles changed or boats existed in the world.
- `sounds/rejected/*` and a directory scan of `sounds/music/`.
- Restarting the bed on every mood change; `war` → `calm` must leave it playing.

## 7. Headless check

```
/home/box/bin/godot --headless --path /workspace/fc_port/frontline-godot -s res://tests/test_audio_upstream.gd
```

Expect `AUDIO_UPSTREAM_TEST PASS`. The Dummy driver is enough: the test asserts the director's play/block log, not a speaker recording.
