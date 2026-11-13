# Audio: what was actually playing

## Follow-up after the first zip

The first zip’s music file was `frontline_pad.ogg`, five steady sine partials on one chord. It did play (mixer peak about 0.18) but it is a stuck tone, and an Ogg loop adds a codec seam. That is the “music is bugged” report. It is no longer the bed.

`sounds/music/frontline_bed.wav` is a 24 s original loop: four chords and a repeating figure, every partial an integer number of cycles so the join is a normal sample step (edge 0.0056, median step 0.0009). Playback sets `AudioStreamWAV.LOOP_FORWARD` across the whole buffer. The rejected theme mp3s are still not loaded.

Effects in that zip were MP3s loaded with `res://` bytes. `load("res://sounds/click.mp3")` on a tree with the `.import` files and no `.godot` cache fails (“Make sure resources have been imported”). The game now reads the file from the absolute project path and decodes 16-bit PCM in `sounds/play/`. Those WAVs are ffmpeg renders of the same OpenFront mp3s (still in `sounds/`). `order.wav` is a short original tone played only when the player’s own attack starts; attacking previously called no sound at all. AI boat, conquer, build, and SAM stay blocked. AI nuke launches and impacts still play.

Headless `--regress` (Godot 4.3, Dummy driver — there is no sound card here, ALSA returned “cannot find card 0”, so this is the mix buffer, not a speaker recording):

- Music peak 0.0867, playing `frontline_bed.wav`, length 24 s, 32 effect keys loaded, none missing.
- After `sfx("click")`, `sfx("order")`, and `sfx("transport")` for the player, mix peak 0.6683. The same calls for an AI owner do not add sound.
- Random Maps tab returned in 2.69 ms with 12 previews queued. They finished in 36 frames. The slowest of those frames was 6.9 ms.

## Original investigation

Measured on the files in this tree. Event-log lines from `godot --headless -- --audiotest` are listed separately and are not listening evidence. Listening-equivalent numbers are normalized cross-correlation of the decoded waveforms (`tools/audio_evidence.py`, 22050 Hz mono). A copy of the OpenFront boat sample mixed into the pad scores 0.978 at 0 dB, 0.760 at -12 dB, 0.282 at -24 dB, and 0.146 at -30 dB. Anything at or below ~0.12 is the detector floor, not a match.

## Root cause

Two separate defects. Gating `sfx()` could not fix the first one, and replacing effect files with duplicates did not fix the second.

### 1. Match start plays whatever is in `sounds/music/`

`_play_music()` used to open `res://sounds/music`, take every `.ogg` / `.mp3` / `.wav`, and play one at random. If that folder was empty it fell back to `res://sounds/city.mp3`. The call is in `main.gd` when the deploy timer ends and `state` becomes `"play"` (the match start, not the main-menu frame).

That folder contained only:

| file | duration | format | sha256 (prefix) |
| --- | --- | --- | --- |
| `roworld_menu.mp3` | 82.86 s | 22050 Hz mono, ~160 kbps | `55bc3a4c6f9fa5e9` |
| `roworld_war.mp3` | 128.19 s | 22050 Hz mono, ~160 kbps | `8d28c29c3419d545` |

Those are not the lengths in the RoWorld manifest. `src/shared/Assets/Audio.luau` lists `music.menu` at 106.666667 s (`rbxassetid://119819342827167`) and `music.war` at 160 s (`rbxassetid://135124812568552`). The Godot files are shorter re-encodes. A previous change described them as clean spans cut out of those themes. The user reported that boat and country-conquer sounds still played at the start of a match after that cut and after SFX were gated. Gating cannot remove audio that is already inside the music file, because the music player never goes through `sfx()`.

Waveform search of those two files against the real OpenFront samples now stored as `sounds/transport-ship.mp3` (4.38 s) and `sounds/conquered.mp3` (2.58 s):

| bed | boat NCC | conquer NCC |
| --- | --- | --- |
| rejected menu | 0.115 | 0.051 |
| rejected war | 0.106 | 0.079 |
| city ambience (not played) | 0.078 | 0.054 |
| `frontline_pad.ogg` | 0.026 | 0.011 |

The OpenFront one-shots are not mixed into the themes at a level the detector can hear (a -30 dB mix of the boat sample scores 0.146). That does **not** mean the themes are clean. The sounds the game calls boat and conquer are the RoWorld assets, not the OpenFront files:

- `boat_launch` — `rbxassetid://119923663006796`, length 2.6 s (`Audio.luau`)
- `conquer` — `rbxassetid://122420079080602`, length 3 s

`assetdelivery.roblox.com` returned 403 ("User is not authorized to access Asset") for both, and for the theme ids and for a Soundtrack track id. The Orchestral Ambients files named in `src/shared/Assets/Soundtrack.luau` (Rodrigo Flores, CC BY 4.0) are uploaded as Roblox assets and are not in git (`tools/assets/upload_soundtrack.py` says the bundle is not in git). OpenFront's own music is under `proprietary/sounds/music/` and the OpenFront license text forbids using it outside OpenFront.

So the themes cannot be certified free of the boat and conquer events the player hears, and there is no licensed clean copy of them in this repo. They are not played. They stay in `sounds/rejected/` with `README.txt` so the claim can be rechecked. Playback is an allow-list of one file, not a directory scan, and there is no fallback to `city.mp3` (a noise soundscape, spectral flatness about 0.35, not a score).

### 2. Most effect files were not the sounds they were named

`sounds/LICENSE.txt` previously said every effect was an unmodified OpenFront file from commit `030274df6e377a57e784a9f6f9865720b0dfbbba`. Byte comparison with that commit says otherwise.

Kept, already identical (10 effects + 4 ambience): `alliance-accepted`, `alliance-broken`, `alliance-declined`, `defeat`, `ka-ching`, `nuke-warning`, `sam-shoot`, `slider`, `warship-lost`, `warship-shot`, `city`, `factory`, `missile-silo`, `sam-silo`.

Replaced, because the bytes differed (24): `alliance-suggested`, `atom-hit`, `atom-launch`, `build-city`, `build-defense-post`, `build-factory`, `build-port`, `build-train-station`, `build-warship`, `click`, `click-1`, `click-2`, `click-3`, `conquered`, `game-start`, `hydrogen-hit`, `hydrogen-launch`, `mirv-launch`, `sam-built`, `sam-hit`, `silo-built`, `spawn`, `transport-ship`, `victory`.

What the bad copies actually were, from PCM identity (not filenames):

- `build-city`, `build-defense-post`, `build-factory`, `build-port`, `build-train-station`, `sam-built`, and `silo-built` were one file (1.94 s).
- `atom-launch`, `hydrogen-launch`, and `mirv-launch` were one file (4.21 s). The real `mirv-launch.mp3` is 19.50 s.
- `atom-hit` and `hydrogen-hit` were one file (6.01 s).
- `click`, `click-1`, `click-2`, and `click-3` were one 0.10 s beep. The real clicks are four different files, about 0.41 s.
- `transport-ship.mp3` was 1.60 s and its correlation against the real 4.38 s boat sample was about 0.01. It was not the boat sound.
- `conquered.mp3` was 3.01 s and did not match the real 2.58 s conquer sample (correlation about 0.02).

A player action that asked for "boat" or "conquer" therefore played some other clip. That is independent of the music bed. Those 24 files are now the unmodified OpenFront bytes. Full sha256 values are in `docs/audio_measurements.json`.

## What plays now

`sfx()` in `main.gd` allows the event only when `who == PLAYER` or the key is in `SFX_ANY_OWNER` (`atom_launch`, `hydrogen_launch`, `mirv_launch`, `atom_hit`, `hydrogen_hit`). Call sites:

- Transport: `sfx("transport")` only when the launching owner is the player (`_spawn_boat`).
- Country eliminated: `sfx("conquered")` only when `last_by` is the player.
- Build / upgrade / warship: only when the owner is the player (`try_build`).
- SAM shot and hit: only when the launcher or the missile owner is the player (`_sam_intercept`, `near_me`). An AI SAM shooting an AI missile does not call `sfx`.
- Nuke launch: any owner, quieter (-8 dB) when it is not the player. Nuke warning only when the victim is the player.
- Nuke impact: any owner (allowed). Volume is full when the player launched it or it lands on the player, otherwise -8 dB.
- UI: `button_down` on a `Button` plays `click`. The volume slider used to play `slider` on every step. That call is removed. Dragging a slider is not a button click.
- `game_start` is loaded and never called.

Music is `sounds/music/frontline_pad.ogg` (32.00 s, rms 0.064). It is a sum of five sine partials (A minor, frequencies snapped so each completes an integer number of cycles in 32 s) times a 2-cycle tremolo. No noise and no percussion. It loops. It starts when audio initializes if music is on, and the match-start call does not restart it. The music toggle stops it and mutes the Music bus; turning music back on starts the same file. Match end and returning to the menu stop it; the menu starts it again if music is on.

## Tests (not listening)

`godot --headless --path frontline-godot --check-only --script res://main.gd` and the five `sim/*.gd` scripts: parse exit 0 after `--import` built the class cache.

`godot --headless --path frontline-godot -- --audiotest` (Godot 4.3.stable):

- Menu: `music_file=res://sounds/music/frontline_pad.ogg playing=true`. Rejected files present on disk, not selected.
- Gate probes: `transport`, `conquered`, `build_city`, `sam_shoot` with `who=2` logged `BLOCK`. `atom_launch` and `hydrogen_hit` with `who=2` logged `PLAY`. `click` and `transport` with `who=1` logged `PLAY`.
- Toggle off: `playing=false`, Music bus mute true. Toggle on: playing the pad again.
- Then a real match on the 1792×1600 map, player placed, speed 10×, about 6 s wall time, sim tick 125, 390 attacks, 0 boats. The AI boat routine ran (profiler `ai_boat` non-zero on several frames). No `SFX PLAY` and no `SFX BLOCK` lines during that match, so AI boat, build, conquer, and SAM did not enter `sfx()` at all.
- Printed constants: map 1792×1600, `BLAST_S` 2.8, radii Atom 19.60, Hydrogen 70.00, MIRV-warhead 8.40, Mega 42.00, Scatter 19.60, speed clamp 0.5 and 10.0.

Headless shutdown also printed pre-existing RID leak warnings from the dummy renderer. They are not an audio result.

`tools/audio_evidence.py` is the listening-equivalent check. Re-run it after any music change. A pad NCC against the boat sample above ~0.15 means a mix louder than about -30 dB and the file should not ship as clean.
