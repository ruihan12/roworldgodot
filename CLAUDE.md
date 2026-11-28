# RoFront (Frontline Conquest) — handoff notes

Godot port of upstream RoWorld (lukechatton/roworld, AGPL). Engine: Godot 4.5.1.stable on branch luau-sim (Step 0 of
docs/LUAU_PORT.md); `multiplayer`, `vanilla` and the live VM are still Godot 4.3.stable. A 4.5.1 pack does not load in 4.3.
Luau runtime (branch luau-sim): luau/ext/gdluau.gdextension, libraries in luau/ext (web) and server_build/<arch>
(Linux), built by tools/luau_ext/build.sh; bridge sim/luau_vm.gd; sim modules in luau/sim. Progress: docs/LUAU_PORT.md.
Luau sim (branch luau-sim, Step 6 of docs/LUAU_PORT.md, 2026-11-27): in Luau when the extension loads: attacks, structures,
arsenal and nukes, rails and trains, water routes, trade ports, warships, economy, the AI's perception (border scans,
nearby owners, coast tiles). Stays GDScript (owner's calls): the AI's decisions, transport and trade ship movement,
rendering, UI, audio, input, networking, accounts, party. sim/*.gd are the facades: each ported tick has a Luau call
and its GDScript body. The GDScript bodies stay as the fallback (owner, 2026-11-27): they run wherever the extension is
not loaded (Windows / macOS editor and desktop builds: the .gdextension has Linux and web libraries only; a web build
whose libgdluau.wasm fails to load) and with NO_LUAU_SIM=1. Remote viewers never tick the sim. Each module's Luau gate
is marked `# FALLBACK` (grep it). Every Luau library exists twice, debug and `.release` (godot-cpp template_debug /
template_release; a debug one aborts in a release export): rebuild both with tools/luau_ext/build.sh. On the web the
loading page (release/loading_shell.html) starts without the library on `?luau=0`, a missing file, or an abort.
Last updated: 2026-11-27 (Luau sim, branch luau-sim).

## Direction
As of Nov 21 2026 the game is "100% vanilla" (matches upstream RoWorld) except for these customs:
- Owner console (password 5516 no longer used for it, FPS counter): opens with F2 (owner request 2026-11-28; Edge and Chrome leave F2 to the page) or Esc then Tab (a lone Tab toggles the leaderboard, as upstream UIInteract; owner said "Yes, match upstream" 2026-11-28), only for the owner's account (henry9149): the account server signs a 7-day token (GET /admin/token, RSA-SHA256, private key on the VM via ADMIN_KEY_FILE + ADMIN_USERS env) and the game checks it against net/admin_pub.pem (net/admin_console.gd). Works in online matches too: the console sends {type: console} and the host (net/mp_host.gd _admin_console) runs only gold, troops, god, claim, nation <name|id> gold|troops <n>, never expressions. Offline `--console` user arg still works locally. Private key: /home/claude/admin_keys/console_private.pem (never commit).
- Game speed slider 0.5x–10x
- Artillery, Air Strike and Railgun x2.5 (owner request 2026-11-28, "Buff all 3 by 2.5x", excluding reloads): troop kills (per tile, % caps, the shell's 1,440 / 19,200 floor and cap), structure damage, ranges (artillery 45 to 112.5, airfield 156 to 390 full-size tiles) and radii (shell 1.5, air strike 15, slug 5) are upstream's x2.5 (SimRules.STRIKE_BUFF, same numbers in luau/sim/Core/Rules.luau). Reloads, battery gaps, cost, HP, build time and projectile speed stay upstream's.
- Map shader (game/state.gd MAP_SHADER, quality >= 2): each screen pixel averages the texels it covers (box filter), so skin patterns no longer break into stray dots at a fractional zoom; whole-number zoom stays pixel-crisp (owner request 2026-11-25).
- Aim card hides the "SAM cover" row for Air Strike and Railgun shots (they ignore SAMs); a warship capturing a trade ship plays no sound (owner request 2026-11-25).
- ICBM toggle (key I): +10% cost (player only); 20% seeded chance per launch to ignore SAMs, +20% flight speed, -20% silo cooldown (as of Nov 22 2026). MIRV/Scattershot warheads share the carrier's roll and speed.
- Bulk launch ring (x1, x2, x5, most affordable) for every bomb (atom, hydrogen, MIRV, Mega, Scattershot; upstream: atom only), client/ui/ui_rules.gd (owner request 2026-11-24).
- Nukes fly at 0.9x upstream speed (NUKE_SPEED_X in game/nukes.gd).
- Range borders (with a mouse too: main.gd _feed_ranges feeds RangeLayer the aim; before 2026-11-24 only the touch ghost did, so SAM, post, artillery, airfield, factory and warship rings never showed before placing): armed Air Strike shows every airfield's reach; warship placement shows its 130-tile range; names show when they fit their territory.
- Others tab (owner request 2026-11-25): 129 OpenFront maps (131 imported; Didier and Didier France removed on owner request 2026-11-28, skipped in tools/import_openfront.py) (openfrontio/openfrontio resources/maps) imported by tools/import_openfront.py as maps/upstream/of_<id> (largest of map/map4x/map16x with <= 2.4M tiles; 0x9F impassable tiles -> water; nations snapped to land); listed after the 10 upstream maps (index.json "others", sim/upstream_maps.gd ids()); picker tab "Others" (client/ui/ui_maps.gd). tests/test_lobby_ui.gd has 3 failures that predate this.
- Web build loads on demand (owner request 2026-11-25, iPad froze/reloaded from memory): the Web preset leaves the 66 music tracks (sounds/upstream/music) and the OpenFront maps' codes/tiles out of index.pck (178 to 51 MB; every pack MB costs about 2.3 MB of RAM); tools/build_web.sh copies them to <out>/lazy/ and the game downloads a track when it is needed (current + next, audio_upstream/audio_director.gd _lazy_fetch) and a map before its match starts (sim/upstream_maps.gd ensure(), called in nations.gd _start_game_ui and net/mp_client.gd S_HELLO; keeps one downloaded map). Native/server builds read everything from the pack. Card thumbnails of Others maps come from small of_<id>.thumb.bin files. Web builds must be made with tools/build_web.sh and the lazy/ folder must be deployed with them. Measured in headless Chromium (World): biggest process 910 to about 765 MB.
- Touch mode (fix 2026-11-26): ctx.touch / ctx.touch_device are now set at HUD setup (client/ui/client_hud.gd _detect_touch: web = maxTouchPoints>0 and a coarse pointer, so iPadOS Safari counts; native = mobile feature; ?touch=1 or --touch force it; a mouse as main pointer = desktop mode). They were never set before, so phones/tablets ran the desktop controls (instant attack on tap, nukes fired on tap, no confirm). Touch mode is upstream's: tap a target to select it, tap again to attack (setting confirm_orders), a placement/nuke ghost with confirm buttons, tapping an ally opens its card, hold = radial menu, bigger rows (44 px). tests/test_client_clicks.gd assumes desktop mode and fails with --touch by design.
- Title screen is a live AI-only attract simulation (5x time-lapse for first 8 s, silent, restarts on a winner or 300 s; setting save.settings.attract_on)
- No custom settings window any more (removed 2026-11-24): the gear/Settings rows open upstream's own settings page (client/ui/pause_menu.gd). FPS is uncapped (Engine.max_fps = 0) and V-Sync is off on desktop; the web follows the browser.
- Name tags: a new placement pass every 0.1 s of real time in a match (was 1 s until 2026-11-25) and every 1 ms (as soon as the last pass is through) before the match, i.e. in the spawn phase (upstream: every 30 ticks); ease speed 18 (upstream 10), placement budget 3 ms, redraw 20 Hz, 0.5 px visibility hysteresis (client/map/name_layer.gd; owner request 2026-11-24).
- Arsenal Star prices are upstream's (Data/Arsenal.luau: Mega 20k, Scattershot 40k, Reinforcements 40k, Artillery 50k +5k bonus, Air Strike 200k +5k bonus, Railgun 500k; owner request 2026-11-25). Mega Nuke and Reinforcements start owned, and 2x Stars (15k) / Rapid Reload (10k) cost Stars here (upstream: Robux only).
- Cosmetic crates / loot boxes: removed from the UI on 2026-11-25 and put back on 2026-11-26 (owner request): title Crates button and Crates window (title_screen.gd, client_hud.gd).
- Title-screen accounts with guest identities, optional local progress upload, and Minecraft linking, password recovery and match history (client/ui/account.gd, net/api.gd).
- Title-screen Multiplayer lobby preview with casual and ranked lobby screens, queue, account leaderboard, and ranked results.
- No automatic NEXT MATCH panel over the results (owner request 2026-11-24; client_hud.gd _maybe_next_match returns early; the menu preview still opens it).
- Player colour: 12 swatches in the pre-game (PLAY SOLO) menu, saved as save.settings.player_color, applied to your nation in game/nations.gd _start_game (owner request 2026-11-24; not used by the title attract sim).
- Phones (owner request 2026-11-25): stretch aspect "expand" and Window.content_scale_factor keep the logical short side at 400-600 px (540 min upright) so the canvas fills the screen in portrait and landscape (game/map.gd _fit_scale); the title wordmark shrinks to fit a narrow portrait screen and sits under the PARTY pill; the web loading screen shows a percentage (release/loading_shell.html).
- Tutorial (owner request 2026-11-25): never starts by itself on first load; a Tutorial switch in Settings (save.settings.tutorial_off) turns it off; "Replay as new player" resets it and starts it from the title.
- Account progress sync (owner request 2026-11-26, net/progress_sync.gd): registered accounts keep stars, skins/flags, unlocked arsenal and stats on the account server (/progress): pulled at start and after login (server copy wins), pushed ~4 s after a change and on focus loss/logout. Guests (and signed-out) keep progress in local browser storage only. Logout resets local progress to a fresh guest; a new account never inherits another account's local progress. Not server-validated (a modified client can still write any stars). tests/test_progress_sync.gd.
- Online waiting room + shared spawn phase (owner request 2026-11-26, upstream MatchServer lobby/spawn stages and TitleScreen's public-match card): a dedicated server's match opens in a waiting room (net/mp_host.gd lobby: 60 s from the first player in, FRONTLINE_LOBBY_SECS overrides; vote to start at 2/3 of the players, at least 2 (1 after 30 s alone), then 10 s; joins close 6 s before the start with reject match_started), then one 20 s spawn phase for everybody (S_LOBBY packets, C_VOTE; unplaced players get a start chosen for them; deltas are now sent during the spawn phase, before this viewers did not see their own capital until play). Panel client/ui/waiting_room.gd (PUBLIC MATCH / TEAM GAME, countdown, players, Vote to start, Leave). Before this, anyone joining after the first placement landed in an already running match and could not place a capital. A PC that hosts for friends (host_is_player) skips the waiting room. tests/test_net_lobby.gd.
- Party menu (owner request 2026-11-25, upstream PartyPanel.luau; hybrid of hub and share code): PARTY pill + panel on phones, always-visible panel on desktop, invite list, JOIN/NO, kick, LEAVE (client/ui/party_panel.gd; rules ported from server/Party.luau in net/party.gd, max 8). Players connect from the title screen to the game server's party hub (own WebSocket, net/party_net_model.gd + party_net.gd; server net/party_service.gd, packets C_PARTY/S_PARTY/S_GO/S_NOTICE), invite each other from the list of connected players or join by a 6-character share code (the code is the consent). The leader picks the match (followers can't); the server sends S_GO and every member joins it with the party key, which keeps them on one team in team games (MPHost.team_groups). save.settings.party_on=false hides it; offline it shows "Can't reach the server". Local stand-in model: net/party_model.gd (tests).
- Memory readout (owner request 2026-11-26, iOS/iPadOS tab kills): touch devices only, a small bottom-left line once a second (engine memory in use / peak, texture and video memory, object and node counts, sim tick); on the web the last line is kept in localStorage (rf_memlog) and shows as "last run: ..." after a crash and reload; ?nomem=1 hides it (client/ui/mem_overlay.gd).
- Defense posts do not shoot ships (2026-11-26, owner request; upstream default; sim/warships.gd defense_posts_shoot = SimRules.DEFENSE_POST_SHOOTS). The sinking message said "warship" for a post's shell.
- Supply drops (the crate that landed on the map): REMOVED 2026-11-26 (owner request): nations.gd _start_game_ui no longer sets supply_on, so no crates land and nobody gets the gold/troops/crate reward. The code (game/economy.gd _supply_tick, client/map/fx_layer.gd _draw_drops) stays dormant. Cosmetic crates (title button, Crates window, Stars) stay.

Everything else follows upstream: native 2000x1000 World (k_lin 1.0, 400 tribes, 10 maps), troops display /10,
upstream max-troops formula, boat 0.35 / warship 0.7, upstream nuke speeds and radii, silos reach whole map,
SAM range 150 - 480/(level+5), reload 90 ticks, fallout until recaptured, tribe color #d1cdc7,
World Control bar = tiles / (contestable - fallout), win at 80%. See docs/VANILLA.md and docs/PARITY.md.

## Branches
- luau-sim: the sim in Luau (see the top), off `multiplayer`, Godot 4.5.1. Parity 467 / 0 / 5, sim_hash owner=3480782660
  (seed 5516, 6000 ticks) on both paths. Not merged.
- vanilla (e623664): main vanilla line. Parity 464 pass / 0 fail / 5 intentional (seeded 5516).
- density-test (164babe): old real-population 1:1 mode, kept for reference only.
- fix-gfx (f512577): DONE. Upstream terrain palette (0 px mismatch), tribe grey #d1cdc7 (dummy RNG calls kept for determinism), upstream name placement, StyleBox AA = exactly 1 screen px (UITheme.smooth()). Parity 464/0.
- fix-input-upstream (f89af0d): DONE, PREFERRED input fix. intent_attack ported from upstream Sim.intent_attack_troops (never launches a boat; refunds + toast if no shared border). borders.gd ported from upstream BorderTracker (3000-tile region check, sea reach requires shared water body). Test: tests/test_input_world.gd.
- fix-input (6ffca83): ALTERNATIVE input fix (whole-map landmass labelling, ~0.9s extra map load). Conflicts with fix-input-upstream in game/map.gd and client/borders.gd. Use fix-input-upstream; optionally cherry-pick its tests (tests/test_input_flow.gd, tools/web_input_test/).
- fix-perf (3abeba8): WIP, PAUSED, UNVERIFIED. Uncommitted perf edits were snapshot-committed when paused. Do not merge without review + parity.

## Done on 2026-11-22 (branch vanilla-merge, pushed)
- Merged fix-input-upstream, fix-gfx and fix-perf into vanilla (no conflicts). Parity 463 pass / 0 fail / 5 intentional; test_input_world, test_client_clicks, test_tutorial, test_map_camera, test_console_spawn, test_nav all PASS.
- Perf check (native headless, tests/perf_sim.gd, World, 400 tribes, seed 12345): first minute per tick vanilla 66 ms (worst 555) -> vanilla-merge 32 ms (worst 129); minute 2 32 ms -> 19 ms. So fix-perf is verified in the sim; the web build is still untested for fps in a real browser.
- Web export of vanilla-merge delivered as roworld_web.zip (needs COOP/COEP headers; serve.py/serve.bat are in release/).
- Perf, name labels (client/map/name_layer.gd): text metrics cached per plate, troop text refreshed at 10 Hz, layer redrawn only when the camera or hover changes or every 0.1 s (was every frame). In xvfb software GL with --perfstart --webprof: names 7.4 -> 4.4 ms/frame; process still ~25 ms/frame there (sim 13.5 of it, atk 10.9; paint 3.7, cam_paint 3.8, client_proc 5.8). xvfb frame time (~75 ms) is software rendering, not representative of a GPU.
- Not merged: fix-input (alternative), density-test. vanilla itself is unchanged: merge vanilla-merge into it when approved.

## Done on 2026-11-23 (branch vanilla-merge, pushed)
- Rails: stations are city/port/factory only (upstream; defense posts, SAMs and silos were wrongly linked); rail_path is now upstream's minimap A* (land only); the unfinished web is cached per frame (60 factories: train tick avg 52 -> 4 ms, worst 14.6 s -> 0.24 s); road layer culls and caches edges.
- docs/PLACE_COMPARE.md: RoWorld.rbxl (built about Nov 13-14) vs the repo copy (Nov 4): 160/182 scripts identical, sim identical; all 10 maps match exactly.
- Multiplayer finding: the sim is NOT lockstep-safe. It depends on time budgets (sim/nav.gd budget_us, sim_naval.defer_paths from elapsed microseconds, per-frame rail budgets, `elapsed` from real dt) and PLAYER is a const used in about 500 places. LAN options: (A) host-authoritative state replication to a thin client, or (B) make the sim tick-deterministic (count-based budgets, elapsed from ticks), make PLAYER a variable, flag human nations so the AI skips them, then lockstep intents (RWSession.send_intent already routes by owner). Needs the owner's choice.
- tests/test_input_world.gd failed once in three full-suite runs and passed twice solo: flaky, cause not found.

## Done on 2026-11-24 (branch vanilla-merge, pushed)
- Settings window removed (gear opens upstream's page), FPS uncapped, V-Sync off on desktop.
- Frame hitches at high fps: the AI pass is time-sliced like the attack pass (sim/ai.gd begin_tick/run_slice, main.gd _tick_stage), and the water-body census (~100 ms, was inside the first AI think) now runs in SimAI.setup. Worst single AI slice 184 ms -> 9 ms (tests/perf_sim.gd --sliced --real). Sliced and unsliced give the same hash with --navfree (nav's time budget makes runs differ otherwise). A real worker thread was judged unsafe: the sim calls UI/fx/audio about 80 times and the client reads sim state in about 138 places.
- New round: the finished round's sim lists and client layers are cleared and the world hidden while the map builds (nations.gd _clear_round_state/_set_world_visible; was: old territory, buildings and names showed through). Choosing a skin repaints only the player's territory (session.gd equip; was a whole-map recolour, ~4 s freeze).
- Territory repaint (game/map.gd _repaint, _paint_budget_us): a captured tile queues only its owned neighbours (neutral land and water don't change look), and the per-frame paint budget scales with game speed (to 4x). In a 10x match the stale-pixel backlog (old owner colour on tiles awaiting repaint: single-pixel dots at fronts) fell from ~17k to ~3.5k queued tiles; it is not zero while the fighting is heavy.
- UI package A aligns ranking columns, resets match-clock colours across phases, and repositions the spawn banner as its contents change.
- UI package B matches compact Locker sizing, keeps title actions in one row, and uses the upstream fallout colour-noise formula.
- UI package C updates the Tab console layout and keyboard scrolling, matches the Arsenal unlock motion, and fixes large HUD suffixes and name-plate flicker near the visibility cutoff.
- Remaining non-sliced spikes: naval up to 13 ms, economy up to 6.6 ms per tick.

## Multiplayer support (2026-11-24)
- Account API service and schema for sessions, Minecraft linking, recovery, progress and ranked Elo.
- Minecraft link and recovery commands with the local account API and per-player cooldowns.
- Casual and ranked lobby preview, queue and results driven by a replaceable model with a local mock.
- Deterministic ranked queue matching and an isolated headless simulation host benchmark.

## Multiplayer build (2026-11-25, branch multiplayer, pushed)
- Host-authoritative replication over WebSocket (server) and ENet (player host): net/mp_host.gd, mp_client.gd, mp_node.gd, transport.gd, intents.gd, rep.gd, net_lobby_model.gd. Docs and status: docs/MULTIPLAYER.md. Deploy: server/deploy/.
- Customs added: online matches have no Tab console and no speed changes (main.gd set_speed_x, shop.gd toggle_console); the Multiplayer lobby connects for real, with Host on this PC and Join address; `--server`, `--hostlocal`, `--connect=` command-line modes.
- Tests: tests/test_net_match.gd, tests/test_net_rep.gd, tests/test_lobby_ui.gd; tests/fake_accounts.py is a stand-in for the account service's internal endpoints (manual real-socket checks).
- On multiplayer, tests/test_input_world.gd rechecks its target after the deployment camera moves during hover and verifies the exact 120-tile land attack order.
- Team games (online only, 2026-11-25): upstream Teams rules, random team size, no bot players; see docs/MULTIPLAYER.md.
- Known gaps: see the last Status entry in docs/MULTIPLAYER.md (attack list replication, interpolation, host events, VM deploy).

## What's left
1. Measure fps of the vanilla-merge web build in a real browser; target steady 60fps at 1x on World (user measured ~30fps before fix-perf). Name relabel spike still to check.
   Known hotspots: per-tick attack pass ~80–90ms in web build (sliced 8ms/frame -> only ~1–1.5 ticks/s in software-rendered Chrome);
   full name relabel ~350ms CPU spread over 4–6s, ~25ms spike at end of spawn phase.
2. Fast-forward vanilla to vanilla-merge once the owner approves (and decide whether any 2026-11-16 main-branch fixes are wanted).
3. Run parity solo (must be 0 fail), plus test_input_world, test_client_clicks, test_tutorial, test_map_camera, test_console_spawn, test_nav.
4. Web export (threads on -> needs COOP/COEP; serve.py on port 8060 sends them, serve.bat runs it). Zip and deliver.
5. Later: multiplayer. Phase 1 LAN with host-run sim (ENet desktop, relay for web). Phase 2 online dedicated headless Godot server on the Oracle VM (WebSocket + ENet, lobby, server-authoritative sim, console disabled online, maybe rofront.henrymc.org).
6. Luau sim: integrated on branch luau-sim (2026-11-27, docs/LUAU_PORT.md). Not yet run in a browser: the web build's
   libgdluau.wasm (the GDScript sim takes over if it fails to load). Deploying it needs Godot 4.5.1 on the VM.
7. Paused backlog: batch 3 UI / ships / nukes-SAM-reinforce-SFX, custom cargo + transport planes.

## Rules for agents
- Verify claims: check git log -1, git status, and build zip dates/sizes before reporting.
- Every Web release zip must include release/serve.py and release/serve.bat (owner's rule): copy both next to index.html before zipping.
- Push to GitHub after every large update (feature, fix batch, or release build), on the current working branch only. Never push to `vanilla` or force-push without the owner saying so. Verify with `git ls-remote origin <branch>` == HEAD.
- Keep the vanilla customs list above as the only deviations from upstream.
- Sim changes on luau-sim: change the Luau module and its GDScript fallback the same way (sim/*.gd facade, luau/sim/Core).
  tests/test_luau_* play the seeded match on both paths and must stay identical tick for tick; tests/sim_hash.gd
  (whole and `-- --sliced`) must stay owner=3480782660 unless the owner approves a gameplay change. Mark customs
  `-- CUSTOM:` / `# CUSTOM:` and list them in docs/LUAU_PORT.md.
