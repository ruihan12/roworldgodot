# RoWorld audio port

Faithful extract of `src/client/Audio/AudioDirector.luau`, `MusicMood.luau`, `Playlist.luau`, and the asset manifests `src/shared/Assets/Audio.luau`, `AudioExtra.luau`, `AudioUI.luau`, `Soundtrack.luau`.

Godot implementation: `audio_upstream/audio_director.gd` (self-contained Node). Wiring snippets: `docs/HOOKS_AUDIO.md`. This document does not change `main.gd`.

Local playback uses the 16-bit PCM files in `sounds/play/` and the single music bed `sounds/music/frontline_bed.wav`. `sounds/rejected/` (old menu/war themes) is never scanned or used as a fallback.

## Hard SFX rules (enforced in the director)

These override upstream when they disagree (upstream only played `nuke_launch` for the local player; the port must also play AI launches and impacts).

- Play SFX only for the player's own actions, things hitting the player, and AI nuke launches + impacts.
- AI building / placement / boat / warship-build / conquer / SAM-vs-AI is muted (`reason=gated_ai`).
- `ui_click` / `click` plays only when the call sets `button_press` (or goes through `play_ui_click()`). Hover, sliders, and other non-button UI must use their own events (`ui_hover`, `slider`, …).
- Boat and conquer are silent for 3000 ms after `begin_match()` (`reason=match_start_hush`), including the usual `order_ack` cooldown fallback, so match-start land grabs and boats cannot spam.

Nuke alarm (`nuke_alarm` / `nuke_warning`) is not an "any-owner" sound: it plays only when the bomb is aimed at the player (`hits_player` or `who == player_id`).

MIRV warhead launches (`kind="warhead"`) stay silent, matching upstream (the bus launch already played `nuke_launch`).

## Music state machine

Moods, from `MusicMood.luau`:

| mood | when |
| --- | --- |
| title | title screen, not queued |
| wait | title screen, in a public-match waiting room |
| calm | in a match (or spectating), no fighting |
| war | player is fighting a nation/player or a nuke of theirs / at their land; holds 40 s after the last sign of fighting (`WAR_HOLD_S`) |
| victory | `screen=over` or not alive, and `winner == me` |
| defeat | match is over for us otherwise |

`set_music_mood` / `update_mood` record the mood. Soundtrack tracks (Rodrigo Flores, CC BY 4.0) and the looping `menu` / `war` Roblox themes are **not in this tree** (Roblox asset ids; the Orchestral Ambients bundle was never committed; the old mp3s in `sounds/rejected/` are not licensed-clean stand-ins). Every mood therefore plays the same allow-listed bed, `frontline_bed.wav`, looped (`LOOP_FORWARD`). A `war` → `calm` change does not restart the bed (upstream lets the battle track play out). Victory / defeat duck the bed and play their stings; they do not swap in a different file.

Music on/off fades over 0.6 s and pauses the bed so it can resume. Volume slider `v` in 0..1 uses gain `v*v`. Base music trim is -6 dB. Ducking: attack 60 dB/s, release 6 dB/s; overlapping ducks keep the deepest amount and the longest hold.

## Director API (event names)

```
audio.play_sfx(name, volume_db=0, pitch_jitter=0.04, pitch=-1, who=-1, hits_player=false, button_press=false, kind="")
audio.play("boat_launch", {who=PLAYER})
audio.play_ui_click()
audio.begin_match() / audio.end_match()
audio.set_music_mood("calm") / audio.update_mood({screen, waiting, me, alive, winner, fighting})
audio.duck_music(amount_db, seconds)
audio.pop(tiles, progress) / audio.pop_once()
```

`who=-1` means the local player. `kind` selects the launch/impact file (`atom`, `hydrogen`, `mirv`, `icbm`, `warhead`, `mega`, `scatter`).

Logical ids from `UICtx.SFX` and the current `main.gd` keys are accepted and resolved to canonical names (see the alias column below). `attack` / `attack_launch` is then replaced by `order_ack` (upstream `REPLACE`, 2026-09-26).

## Event table

Columns: canonical name, aliases accepted, local file(s), volume trim / auto-duck, throttle or cooldown, voice cap, gate. Times are milliseconds unless noted. "gap" means the Roblox asset is not on disk; the file is the closest existing stand-in.

### UI

| event | aliases | file(s) | vol / duck | limit | gate |
| --- | --- | --- | --- | --- | --- |
| ui_click | click | click.wav + click-1/2/3.wav | 0 | throttle 30, max 2 | UI, **button_press only** |
| ui_hover | hover | slider.wav (**gap**) | 0 | throttle 45, max 1 | UI |
| ui_open | open | click-2.wav (**gap**) | 0 | throttle 60 | UI |
| ui_error | deny | alliance-declined.wav (**gap**) | 0 | throttle 120 | UI |
| ui_confirm | confirm | click-3.wav (**gap**) | 0 | throttle 60, max 2 | UI |
| ui_back | close | click-2.wav (**gap**) | 0 | throttle 60, max 2 | UI |
| ui_tab | tab, toast | click-1.wav (**gap**) | 0 | throttle 40, max 2 | UI |
| ui_locked | locked | alliance-declined.wav (**gap**) | 0 | throttle 150, max 1 | UI |
| slider |  | slider.wav | 0 | throttle 40 | UI (not a click) |
| countdown_tick | tick | slider.wav (**gap**) | 0 | throttle 250, max 1 | UI |
| countdown_tick_1..5 |  | slider.wav / click-1.wav (**gap**) | 0 | default 50 | UI |
| countdown_gamestart |  | game-start.wav (**gap**, length differs) | duck 5 dB / 2.5 s | max 1 | UI |
| queue_start |  | game-start.wav (**gap**) | 0 | max 1 | UI |
| spectate_switch |  | click-3.wav (**gap**) | 0 | throttle 150, max 1 | UI |
| star_tick |  | slider.wav (**gap**) | 0 | throttle 28, max 4 | UI |
| star_get |  | ka-ching.wav (**gap**) | 0 | throttle 120, max 2 | UI |
| buy_spend | buy, ka_ching | ka-ching.wav | 0 | throttle 150, max 1 | UI |
| unlock |  | alliance-accepted.wav (**gap**, length differs) | duck 5 dB / 3 s | throttle 800, max 1, prio 2 | UI |
| game_start | start | game-start.wav | duck 5 dB / 4 s | cooldown 3000 silent, max 1 | UI |

### Orders, buildings, boats

| event | aliases | file(s) | vol / duck | limit | gate |
| --- | --- | --- | --- | --- | --- |
| order_ack | order, attack, attack_launch | order.wav | 0 | throttle 80, max 2 | player |
| boat_launch | boat, transport | transport-ship.wav | 0 | cooldown 1500 → order_ack; **match-start hush 3000 silent** | player |
| build |  | build-city.wav | 0 | throttle 90 | player |
| build_city / _port / _factory / _defense / _sam / _silo / _station |  | matching `build-*.wav`, `sam-built.wav`, `silo-built.wav` | 0 | throttle 90 | player |
| warship | build_warship | build-warship.wav | 0 | cooldown 2000 → order_ack | player |
| spawn_confirm | spawn | spawn.wav | 0 | cooldown 700 → ui_click | player |

### Nukes, SAM, shells

| event | aliases | file(s) | vol / duck | limit | gate |
| --- | --- | --- | --- | --- | --- |
| nuke_launch | atom_launch, hydrogen_launch, mirv_launch, icbm_launch | atom-launch.wav; hydrogen-launch.wav if kind h/icbm; mirv-launch.wav if mirv | caller: 0 player, -8 AI | throttle 150 | **any owner** (not warheads) |
| nuke_explosion | explosion, atom_hit, hydrogen_hit | atom-hit.wav; hydrogen-hit.wav if kind h/icbm | duck 8 dB / 2.5 s; caller: 0 if player involved, else -8 | throttle 180, prio 2 | **any owner** |
| nuke_alarm | alarm, nuke_warning | nuke-warning.wav | duck 4 dB / 1.8 s | cooldown 2500 silent, max 1, prio 2 | hits player only |
| sam_launch | sam_shoot | sam-shoot.wav | 0 | throttle 100, max 3 | player or hits_player |
| sam_intercept | intercept, sam_hit | sam-hit.wav | 0 | throttle 90 | player or hits_player |
| shell_fire | shell | warship-shot.wav (**gap**) | 0 | throttle 120, max 3 | player or hits_player |
| shell_hit |  | warship-shot.wav (**gap**) | 0 | throttle 90, max 3 | player or hits_player |
| shell_splash |  | sam-hit.wav (**gap**) | 0 | throttle 90, max 2 | player or hits_player |

ICBM is a port-only slot: `icbm_launch` / `kind="icbm"` uses `hydrogen-launch.wav` (closest "big missile" file). There is no dedicated ICBM sample.

### Combat, diplomacy, end

| event | aliases | file(s) | vol / duck | limit | gate |
| --- | --- | --- | --- | --- | --- |
| under_attack |  | alliance-broken.wav (**gap**) | duck 3 dB / 1 s | cooldown 4000 silent, max 1, prio 2 | player / hits_player |
| ally_request | ally_suggest | alliance-suggested.wav | 0 | cooldown 1500 silent, max 1 | player / hits_player |
| alliance | ally_accept | alliance-accepted.wav | 0 | cooldown 2500 silent, prio 2 | player / hits_player |
| betrayal | ally_broken | alliance-broken.wav | duck 3 dB / 1.5 s | cooldown 3000 silent, prio 2 | player / hits_player |
| ally_decline |  | alliance-declined.wav | 0 | cooldown 1500 silent | player / hits_player |
| conquer | conquered | conquered.wav | trim -6 dB; duck 3 dB / 1.2 s | cooldown 2500 silent; **match-start hush 3000**; prio 2 | player / hits_player |
| eliminate |  | conquered.wav (**gap**, shorter upstream kill sting) | trim -3 dB | cooldown 2500 silent; hush 3000; max 2, prio 2; hushes pops 0.65 s | player / hits_player |
| ship_sink | ship_lost, warship_lost | warship-lost.wav | 0 | throttle 400, max 2 | player / hits_player |
| warship_shot | ship_kill | warship-shot.wav | 0 | throttle 90 | player / hits_player |
| victory |  | victory.wav | duck 14 dB / 9 s | cooldown 10000 silent, max 1, prio 2 | UI / end |
| defeat |  | defeat.wav | duck 14 dB / 6 s | cooldown 10000 silent, max 1, prio 2 | UI / end |

### Border pops and leftover cosmetics

| event | aliases | file(s) | vol / duck | limit | gate |
| --- | --- | --- | --- | --- | --- |
| expand_pop |  | slider.wav (**gap** — no bubble-pop sample) | pop() sets -9..-3 dB, pitch 0.8..1.1 | throttle 38, max 6 | player (`pop` / `pop_once`) |
| expand |  | spawn.wav (**gap**, rarely used after expand_pop) | 0 | throttle 150, max 2 | player |
| crate_* / card_* / reveal_* |  | ka-ching / slider / build-port / click stand-ins (**all gaps**) | epic/legendary preview + crate_open + reveals duck | mostly max 1 | UI (crate show; not required for a match) |

Voice steal: at most 18 effects ring at once (`VOICE_COUNT`). A new sound may stop a quieter, older voice, but never a higher-priority one.

Default throttle for anything not listed: 50 ms. Default max copies: 3. Default pitch jitter: ±4%.

## Gaps (no local file for the Roblox id)

Every id in `Audio.luau` / `AudioExtra.luau` / `AudioUI.luau` / `Soundtrack.luau` is a `rbxassetid://…`. None of those bytes are in git. What we do have are the OpenFront CC BY-SA 4.0 one-shots already decoded as 16-bit PCM in `sounds/play/`, plus `frontline_bed.wav`.

Closest-file stand-ins are in the table above and in `AudioDirector.GAPS`. The important holes:

- **Music.** `music.menu` (106.67 s) and `music.war` (160 s), and all 33 Rodrigo Flores soundtrack tracks, have no licensed copy here. `assetdelivery.roblox.com` 403s the ids. Do not use `sounds/rejected/roworld_menu.mp3` or `roworld_war.mp3` (shorter re-encodes, cannot be certified clean of boat/conquer). Playback is the 24 s `frontline_bed.wav` loop only.
- **expand_pop.** Upstream's border-growth bubble (0.12 s). Closest short tick: `slider.wav`. Pitch/volume envelope of `pop()` is still implemented.
- **under_attack.** No dedicated sting; `alliance-broken.wav` is the closest "something bad" sample.
- **shell_fire / shell_hit / shell_splash.** No artillery one-shots; `warship-shot.wav` / `sam-hit.wav`.
- **UI kit** (`ui_hover`, `ui_open`, `ui_error`, `ui_confirm`, `ui_back`, `ui_tab`, `ui_locked`, countdown ticks, spectate switch). Short clicks / `slider.wav` / `alliance-declined.wav`.
- **eliminate.** Upstream replaced the 3 s conquer sting with a 0.61 s kill sound. We only have `conquered.wav`.
- **Crate / card / reveal / star / unlock / queue_start / countdown_gamestart.** Cosmetic / lobby; stand-ins only. Not needed to play a match.

Events with a real named OpenFront file (not a gap): `ui_click`, `order_ack`, `boat_launch`, `build` and the per-building names, `warship`, `spawn_confirm`, `nuke_launch` (and kind files), `nuke_alarm`, `nuke_explosion` (and kind files), `sam_launch`, `sam_intercept`, `ship_sink`, `warship_shot`, `ally_request`, `alliance`, `betrayal`, `ally_decline`, `conquer`, `victory`, `defeat`, `game_start`, `buy_spend` (`ka-ching.wav`).

## Upstream trigger cheat-sheet

From `UIAdvisor.luau` / `UIRoot.luau` / `UICtx.luau` (what should call the director, once hooked):

- Player land gained in a batch → `pop(tiles * K_AREA, progress)`
- Structure placed by the local player → `build` (or the per-building name)
- Transport / warship spawned by the local player → `boat_launch` / `warship`
- Nuke launched: any owner, not a warhead → `nuke_launch` with kind; if aimed at the player → also `nuke_alarm`
- Nuke detonated (radius > 0): any owner → `nuke_explosion` with kind
- SAM launch / intercept only if the SAM or the missile belongs to the player
- Shell / air-strike / slug: player shot or shot hitting the player → `shell_fire` / `shell_hit` (not the nuke alarm)
- Country eliminated by the player → `conquer` or `eliminate`
- Alliance propose / accept / decline / break involving the player → `ally_request` / `alliance` / `ally_decline` / `betrayal`
- Under attack (player's land) → `under_attack` (4 s cooldown)
- Match start → `begin_match()`, optional `game_start`, mood calm
- Victory / defeat → mood + sting, duck the bed
- Real `Button.button_down` only → `play_ui_click()` (not slider drag, not hover)

## Throttle / cooldown summary (director, after alias resolution)

Cooldowns (full sting, then fallback): attack_launch 1200 → order_ack (but attack_launch is replaced first, so this path is unused); boat_launch 1500 → order_ack (suppressed during match-start hush); warship 2000 → order_ack; spawn_confirm 700 → ui_click; conquer / eliminate 2500 silent; betrayal 3000 silent; alliance 2500 silent; ally_request / ally_decline 1500 silent; under_attack 4000 silent; nuke_alarm 2500 silent; game_start 3000 silent; victory / defeat 10000 silent.

Plus the extra 3000 ms match-start hush on `boat_launch`, `conquer`, `eliminate`.

## Fetch of official Roblox asset ids (2026-11-09, America/New_York)

Tried every unique id in `ui_upstream/audio.json` (62 sfx names / 69 sfx records including Extra+UI overrides, plus `menu` / `war` and 33 soundtrack tracks = **104 ids**), cookieless, on the three public routes only:

| route | result for all 104 ids |
| --- | --- |
| `https://assetdelivery.roblox.com/v1/asset/?id=ID` | HTTP **403**, body `User is not authorized to access Asset.` (one transient disconnect, same 403 on retry) |
| `https://assetdelivery.roblox.com/v2/assetId/ID` | HTTP 200 wrapping JSON **error code 403**, same message (one transient disconnect, same 403 on retry). No `locations` CDN URL to follow. |
| `https://www.roblox.com/asset/?id=ID` | HTTP **404** HTML |

Downloaded: **0**. Blocked: **104**. No files were written under `sounds/upstream/raw/` or converted to wav. The director still prefers `res://sounds/upstream/<event>.wav` when that file is present, otherwise the `sounds/play/` stand-in. Full per-id log: `sounds/upstream/download_report.json`.


## Soundtrack (port2, 2026-11-09)
audio_director.gd now plays the RoWorld soundtrack (33 tracks, sounds/upstream/music/<key>.ogg, Soundtrack.luau
manifest embedded as SOUNDTRACK_TRACKS / SOUNDTRACK_MOODS) with upstream Playlist + AudioDirector behaviour:
title opener (glory_of_the_nation) once per session, shuffle without the last min(6, pool/2), FALLBACK moods,
AFTER (victory -> title, defeat -> calm), next track overlaps the last 2 s (TRACK_OVERLAP_S), mood fades 3 s
(war 2 s), war -> calm lets the battle track play out, only the playing + next track are decoded.
main.gd drives the mood like UIRoot._update_music (title on the menu, calm/war from player attacks and nukes,
victory/defeat at the end). frontline_bed.wav stays the fallback when no track file loads (and for play_theme).
Gap list: GAPS is now only music.menu / music.war; STANDIN_GAPS (the old 44) count only while the matching
sounds/upstream/<event>.wav is absent; "soundtrack.*" only when no track loads. Credit: Music by Rodrigo Flores, CC BY 4.0.
